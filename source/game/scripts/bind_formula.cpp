#include "binds.h"
#include "util/formula.h"
#include "util/refcount.h"
#include "util/save_file.h"
#include "network/message.h"
#include "main/logging.h"
#include "scripts/context_cache.h"
#include "general_states.h"
#include <unordered_map>
#include <vector>

namespace scripts {

class FormulaNamespace;
static int varIndex(const std::string* str);
static double varName(void* user, const std::string* name);
static double nsVar(void* user, int index);

static threads::ReadWriteMutex nsVarMutex;
static std::unordered_map<std::string, int> nsVariables;
static std::vector<std::string> nsVariableNames;

class FormulaNamespace : public AtomicRefCounted {
public:
	enum VarType {
		vConstant,
		vFormula,
	};

	struct Var {
		VarType type;
		union {
			double decimal;
			Formula* formula;
		};
		std::string* str;

		Var() : type(vConstant), decimal(0.0), str(0) {
		}

		~Var() {
			switch(type) {
				case vFormula:
					delete formula;
				break;
			}
			delete str;
		}

		void setType(VarType newType) {
			switch(type) {
				case vFormula:
					delete formula;
				break;
			}
			type = newType;
		}

		void setString(const std::string& value) {
			if(!str)
				str = new std::string();
			*str = value;
		}

		void write(net::Message& msg) {
			msg << (uint8_t)type;

			switch(type) {
				case vConstant:
					msg << decimal;
				break;
				case vFormula:
					if(str)
						msg << *str;
					else
						msg << "0";
				break;
			}
		}

		void read(net::Message& msg) {
			auto prevType = type;
			uint8_t utp;
			msg >> utp;
			type = (VarType)utp;

			switch(type) {
				case vConstant:
					msg >> decimal;
				break;
				case vFormula:
					if(!str)
						str = new std::string();
					msg >> *str;
					if(prevType == vFormula && formula)
						delete formula;
					formula = Formula::fromInfix(str->c_str(), &varIndex);
				break;
			}
		}
	};

	threads::ReadWriteMutex mtx;
	std::vector<Var> variables;
	std::vector<int> indexes;

	int lookup(const std::string& name, bool create = true) {
		{
			threads::ReadLock nl(nsVarMutex);
			auto it = nsVariables.find(name);
			if(it != nsVariables.end())
				return it->second;
		}

		if(create) {
			int globInd = -1;
			{
				threads::WriteLock wl(nsVarMutex);
				globInd = nsVariables.size();
				nsVariables[name] = globInd;
				nsVariableNames.push_back(name);
			}

			{
				threads::WriteLock wl(mtx);
				int index = variables.size();
				variables.push_back(Var());

				if((unsigned)globInd >= indexes.size())
					indexes.resize(globInd+1, -1);
				indexes[globInd] = index;
			}

			return globInd;
		}
		else {
			return -1;
		}
	}

	inline int fromGlobalIndex(int index) {
		if((unsigned)index >= indexes.size())
			return -1;
		return indexes[index];
	}

	double get(const std::string& name) {
		threads::ReadLock rl(mtx);
		int index = lookup(name, false);
		if(index == -1) {
			error("Formula variable '%s' does not exist.", name.c_str());
			scripts::logException();
			return 0.0;
		}

		return get(index);
	}

	double get(int globalIndex) {
		threads::ReadLock rl(mtx);
		int index = fromGlobalIndex(globalIndex);
		if(index == -1) {
			if(globalIndex > 0 && globalIndex < (int)nsVariableNames.size()) {
				//Formula variable exists, just hasn't been set in this particular namespace,
				//which means we should consider it a 0 so we don't fuck with execution order

				//error("Formula variable '%s' does not exist.", nsVariableNames[globalIndex].c_str());
				//scripts::logException();
				return 0.0;
			}
			else {
				error("Invalid namespace variable index.");
				scripts::logException();
			}
			return 0.0;
		}

		Var& v = variables[index];
		switch(v.type) {
			case vConstant:
				return v.decimal;
			case vFormula:
				return v.formula->evaluate(&varName, this, &nsVar);
		}
		return 0.0;
	}

	bool has(const std::string& name) {
		threads::ReadLock rl(mtx);
		return fromGlobalIndex(lookup(name, false)) != -1;
	}

	void setConstant(const std::string& name, double value) {
		threads::WriteLock wl(mtx);
		int index = lookup(name, true);
		setConstant(index, value);
	}

	void setConstant(int globIndex, double value) {
		threads::WriteLock wl(mtx);
		int index = fromGlobalIndex(globIndex);
		if(index == -1) {
			index = variables.size();
			variables.push_back(Var());
			if((unsigned)globIndex >= indexes.size())
				indexes.resize(globIndex+1, -1);
			indexes[globIndex] = index;
		}

		Var& v = variables[index];
		v.setType(vConstant);
		v.decimal = value;
	}

	void modConstant(int globIndex, double value) {
		threads::WriteLock wl(mtx);
		int index = fromGlobalIndex(globIndex);
		if(index == -1) {
			index = variables.size();
			variables.push_back(Var());
			if((unsigned)globIndex >= indexes.size())
				indexes.resize(globIndex+1, -1);
			indexes[globIndex] = index;
		}

		Var& v = variables[index];
		if(v.type == vConstant) {
			v.decimal = v.decimal + value;
		}
		else {
			double last = get(globIndex);
			v.setType(vConstant);
			v.decimal = last + value;
		}
	}

	void setFormula(const std::string& name, const std::string& formula) {
		threads::ReadLock rl(mtx);
		int index = lookup(name, true);
		setFormula(index, formula);
	}

	void setFormula(int globIndex, const std::string& formula) {
		threads::WriteLock wl(mtx);
		int index = fromGlobalIndex(globIndex);
		if(index == -1) {
			index = variables.size();
			variables.push_back(Var());
			if((unsigned)globIndex >= indexes.size())
				indexes.resize(globIndex+1, -1);
			indexes[globIndex] = index;
		}

		Var& v = variables[index];
		v.setType(vFormula);

		v.formula = Formula::fromInfix(formula.c_str(), &varIndex);
		v.setString(formula);
	}

	void write(net::Message& msg) {
		threads::ReadLock rl(mtx);
		msg << (unsigned)variables.size();
		for(unsigned i = 0, cnt = indexes.size(); i < cnt; ++i) {
			if(indexes[i] == -1)
				continue;
			msg << nsVariableNames[i];
			variables[indexes[i]].write(msg);
		}
	}

	void read(net::Message& msg) {
		try {
			threads::WriteLock wl(mtx);
			unsigned varCnt = 0;
			msg >> varCnt;

			for(unsigned i = 0; i < varCnt; ++i) {
				std::string name;
				msg >> name;

				int globIndex = lookup(name, true);
				int index = fromGlobalIndex(globIndex);
				if(index == -1) {
					index = variables.size();
					variables.push_back(Var());
					if((unsigned)globIndex >= indexes.size())
						indexes.resize(globIndex+1, -1);
					indexes[globIndex] = index;
				}

				variables[index].read(msg);
			}
		}
		catch(net::MessageReadError) {
			scripts::throwException("Error reading from message: end of message.");
		}
	}
};

static FormulaNamespace* makeNamespace() {
	return new FormulaNamespace();
}

static int varIndex(const std::string* name) {
	{
		threads::ReadLock nl(nsVarMutex);
		auto it = nsVariables.find(*name);
		if(it != nsVariables.end())
			return it->second;
	}

	threads::WriteLock wl(nsVarMutex);
	auto it = nsVariables.find(*name);
	if(it != nsVariables.end())
		return it->second;
	int globInd = nsVariables.size();
	nsVariables[*name] = globInd;
	nsVariableNames.push_back(*name);
	return globInd;
}

static double varName(void* user, const std::string* name) {
	return 0.0;
}

static double nsVar(void* user, int index) {
	FormulaNamespace* ns = (FormulaNamespace*)user;
	if(ns)
		return ns->get(index);
	else
		return 0.0;
}

class ScriptFormula : public AtomicRefCounted {
public:
	Formula* formula;

	ScriptFormula() : formula(0) {
	}

	void parse(const std::string& expr) {
		if(formula)
			delete formula;
		try {
			formula = Formula::fromInfix(expr.c_str(), &varIndex);
		}
		catch(FormulaError& err) {
			error("Script Formula Error: %s", err.msg.c_str());
			scripts::logException();
			formula = 0;
		}
	}

	double evaluate(FormulaNamespace* ns = 0) {
		if(!formula)
			return 0.0;
		return formula->evaluate(&varName, ns, &nsVar);
	}

	~ScriptFormula() {
		delete formula;
	}
};

static ScriptFormula* makeFormula_e() {
	return new ScriptFormula();
}

static ScriptFormula* makeFormula(const std::string& expr) {
	ScriptFormula* f = new ScriptFormula();
	f->parse(expr);
	return f;
}

void RegisterFormulaBinds(bool server) {
	nsVariables.clear();
	nsVariableNames.clear();

	/* FORMULA NAMESPACE */
	ClassBind ns("Namespace", asOBJ_REF);
		classdoc(ns, "A namespace of variables that can be accessed from formulas attached to it.");

	ns.addFactory("Namespace@ f()", asFUNCTION(makeNamespace));
	ns.setReferenceFuncs(asMETHOD(FormulaNamespace,grab), asMETHOD(FormulaNamespace,drop));

	ns.addMember("ReadWriteMutex mtx", offsetof(FormulaNamespace, mtx))
		doc("Mutex that governs reading and writing on this namespace.");

	ns.addMethod("int lookup(const string&in name, bool create = true)",
			asMETHOD(FormulaNamespace, lookup))
		doc("Lookup the index of a variable in the namespace.",
				"Name of the variable.",
				"If true, create the variable if it does not exist.",
			"Index of the variable. -1 if it does not exist and was not created.");

	ns.addMethod("double get(const string&in name)",
			asMETHODPR(FormulaNamespace, get, (const std::string&), double))
		doc("Get or calculate the value of a variable by name.",
				"Name of the variable.",
			"Value of that variable.");

	ns.addMethod("double get(int index)",
			asMETHODPR(FormulaNamespace, get, (int), double))
		doc("Get or calculate the value of a variable by index.",
				"Index of the variable.",
			"Value of that variable.");

	ns.addMethod("bool has(const string&in name)",
			asMETHOD(FormulaNamespace, has))
		doc("", "Name of the variable to check for.",
				"True if a variable with this name exists.");

	ns.addMethod("void setConstant(const string&in name, double value)",
			asMETHODPR(FormulaNamespace, setConstant, (const std::string&, double), void))
		doc("Set a constant value for a variable.",
				"Name of the variable to set.",
				"Value to set the variable to.");

	ns.addMethod("void setConstant(int index, double value)",
			asMETHODPR(FormulaNamespace, setConstant, (int, double), void))
		doc("Set a constant value for a variable.",
				"Index of the variable to set.",
				"Value to set the variable to.");

	ns.addMethod("void modConstant(int index, double value)",
			asMETHODPR(FormulaNamespace, modConstant, (int, double), void))
		doc("Modify a constant value for a variable by adding a new value.",
				"Index of the variable to set.",
				"Amount to add to the constant value.");

	ns.addMethod("void setFormula(const string&in name, const string&in formula)",
			asMETHODPR(FormulaNamespace, setFormula, (const std::string&, const std::string&), void))
		doc("Set a formula to evaluate for a variable. Formula is evaluated in this namespace.",
				"Name of the variable to set.",
				"Formula to set the variable to.");

	ns.addMethod("void setFormula(int index, const string&in formula)",
			asMETHODPR(FormulaNamespace, setFormula, (int, const std::string&), void))
		doc("Set a formula to evaluate for a variable. Formula is evaluated in this namespace.",
				"Index of the variable to set.",
				"Formula to set the variable to.");

	ns.addMethod("void write(Message& msg)", asMETHOD(FormulaNamespace, write))
		doc("Write the namespace to a message.", "Message to write to.");

	ns.addMethod("void read(Message& msg)", asMETHOD(FormulaNamespace, read))
		doc("Read the namespace from a message.", "Message to read from.");

	ns.addMethod("void save(SaveFile& file)", asMETHOD(FormulaNamespace, write))
		doc("Write the namespace to a save file.", "Save file to write to.");

	ns.addMethod("void load(SaveFile& file)", asMETHOD(FormulaNamespace, read))
		doc("Read the namespace from a save file.", "Save file to read from.");

	{
		Namespace ns("formula");
		bind("int variable(const ::string&in name)", asFUNCTION(varIndex));
	}


	/* FORMULA */
	ClassBind f("Formula", asOBJ_REF);
		classdoc(f, "Evaluator for arbitrary formula expressions.");

	f.addFactory("Formula@ f()", asFUNCTION(makeFormula_e));
	f.addFactory("Formula@ f(const string&in formula)", asFUNCTION(makeFormula))
		doc("Construct a new formula.", "Formula expression to use.", "Constructed formula.");
	f.setReferenceFuncs(asMETHOD(ScriptFormula,grab), asMETHOD(ScriptFormula,drop));

	f.addMethod("void parse(const string&in formula)", asMETHOD(ScriptFormula, parse))
		doc("Parse an expression into this formula.", "Formula expression to use.");

	f.addMethod("double evaluate(Namespace@ ns = null)", asMETHOD(ScriptFormula, evaluate))
		doc("Evaluate the formula expression with the current state of "
			"the namespace it was constructed with.",
			"Namespace to retrieve variables from.",
			"Value of the formula.");
}

void addNamespaceState() {
	stateValueTypes["Namespace"].setup(
		sizeof(FormulaNamespace*), "Namespace@",

		//Copy reference only, or create new if not copying
		[](void* m, void* s) {
			FormulaNamespace** dest = (FormulaNamespace**)m;
			FormulaNamespace** src = (FormulaNamespace**)s;

			if(src) {
				*dest = *src;

				if(*src)
					(*src)->grab();
			}
			else {
				*dest = new FormulaNamespace();
			}
		},

		//No initializer
		nullptr,

		//Release reference on destruct
		[](void* mem) {
			FormulaNamespace* ns = *(FormulaNamespace**)mem;
			if(ns)
				ns->drop();
		},

		//Write to network
		[](net::Message& msg, void* mem) {
			FormulaNamespace* ns = *(FormulaNamespace**)mem;
			if(ns)
				ns->write(msg);
		},

		//Read from network
		[](net::Message& msg, void* mem) {
			FormulaNamespace* ns = *(FormulaNamespace**)mem;
			if(ns)
				ns->read(msg);
		}
	);
}

};
