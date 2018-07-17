#include "script_bind.h"
#include "threads.h"
#include "str_util.h"
#include "main/references.h"
#include <map>
#include <set>
#include <stdarg.h>

namespace scripts {

#ifdef _DEBUG
int check(int id) {
	if(id < 0) {
		if(id == asALREADY_REGISTERED)
			throw "Already bound";
		else
			throw "Binding error";
	}
	return id;
}
#else
#define check(x) x
#endif

#ifdef DOCUMENT_API
#define check_doc(x) return *new Documentor(check(x), declaration);
#else
#define check_doc(x) check(x)
#endif

Threaded(asIScriptEngine*) engine;

void setEngine(asIScriptEngine* _engine) {
	engine = _engine;
}

asIScriptEngine* getEngine() {
	return engine;
}

_DOC bind(const char* declaration, asSFuncPtr func, asDWORD callType) {
	check_doc( engine->RegisterGlobalFunction(declaration, func, callType) );
}

_DOC bind(const char* declaration, asSFuncPtr func, void* obj) {
	check_doc( engine->RegisterGlobalFunction(declaration, func, asCALL_THISCALL_ASGLOBAL, obj) );
}

void bindStringFactory(const char* stringClass, asSFuncPtr func, asDWORD callType) {
	check( engine->RegisterStringFactory(stringClass, func, callType) );
}

_GLOBAL_DOC bindGlobal(const char* declaration, void* ptr) {
	check( engine->RegisterGlobalProperty(declaration, ptr) );
#ifdef DOCUMENT_API
	return *new GlobalDoc(declaration);
#endif
}

void bindFuncdef(const char* declaration) {
	check( engine->RegisterFuncdef( declaration ) );
}

ClassBind::ClassBind(const char* Name) : name(Name) {}
ClassBind::ClassBind(const char* Name, asDWORD flags, int size) : name(Name) {
	if(flags & asOBJ_TEMPLATE) {
		std::string regName = name;
		regName += "<class T>";
		name += "<T>";

		check( engine->RegisterObjectType(regName.c_str(), size, flags) );
	}
	else {
		check( engine->RegisterObjectType(Name, size, flags) );
	}
}

asITypeInfo* ClassBind::getType() {
	return engine->GetTypeInfoByName(name.c_str());
}

_DOC ClassBind::addFactory(const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_FACTORY, declaration, func, asCALL_CDECL) );
}

_DOC ClassBind::addGenericFactory(const char* declaration, asSFuncPtr func, void* userdata) {
	int fid = engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_FACTORY, declaration, func, asCALL_GENERIC);
#ifdef _DEBUG
	check(fid);
#endif

	if(userdata)
		engine->GetFunctionById(fid)->SetUserData(userdata);
#ifdef DOCUMENT_API
	return *new Documentor(fid, declaration);
#endif
}

_DOC ClassBind::addConstructor(const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_CONSTRUCT, declaration, func, asCALL_CDECL_OBJFIRST) );
}

_DOC ClassBind::addDestructor(const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_DESTRUCT, declaration, func, asCALL_CDECL_OBJFIRST) );
}
	
_DOC ClassBind::addMethod(const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectMethod(name.c_str(), declaration, func, asCALL_THISCALL) );
}

_DOC ClassBind::addBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), behav, declaration, func, asCALL_THISCALL) );
}

_DOC ClassBind::addExternBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func, bool ptrFirst) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), behav, declaration, func, ptrFirst ? asCALL_CDECL_OBJFIRST : asCALL_CDECL_OBJLAST) );
}

_DOC ClassBind::addGenericBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func, void* userdata) {
	int fid = engine->RegisterObjectBehaviour(name.c_str(), behav, declaration, func, asCALL_GENERIC);
#ifdef _DEBUG
	check(fid);
#endif

	if(userdata)
		engine->GetFunctionById(fid)->SetUserData(userdata);
#ifdef DOCUMENT_API
	return *new Documentor(fid, declaration);
#endif
}

_DOC ClassBind::addLooseBehaviour(asEBehaviours behav, const char* declaration, asSFuncPtr func) {
	check_doc( engine->RegisterObjectBehaviour(name.c_str(), behav, declaration, func, asCALL_CDECL) );
}

void ClassBind::addGarbageCollection(asSFuncPtr setflag, asSFuncPtr getflag, asSFuncPtr getrefcount, asSFuncPtr enumrefs, asSFuncPtr releaserefs) {
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_SETGCFLAG, "void f()", setflag, asCALL_THISCALL) );
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_GETGCFLAG, "bool f()", getflag, asCALL_THISCALL) );
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_GETREFCOUNT, "int f()", getrefcount, asCALL_THISCALL) );
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_ENUMREFS, "void f(int&in)", enumrefs, asCALL_THISCALL) );
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_RELEASEREFS, "void f(int&in)", releaserefs, asCALL_THISCALL) );
}

_DOC ClassBind::addExternMethod(const char* declaration, asSFuncPtr func, bool ptrFirst) {
	check_doc( engine->RegisterObjectMethod(name.c_str(), declaration, func, ptrFirst ? asCALL_CDECL_OBJFIRST : asCALL_CDECL_OBJLAST) );
}

_DOC ClassBind::addGenericMethod(const char* declaration, asSFuncPtr func, void* userdata) {
	int fid = engine->RegisterObjectMethod(name.c_str(), declaration, func, asCALL_GENERIC);
#ifdef _DEBUG
	check(fid);
#endif

	if(userdata)
		engine->GetFunctionById(fid)->SetUserData(userdata);
#ifdef DOCUMENT_API
	return *new Documentor(fid, declaration);
#endif
}

_MEMBER_DOC ClassBind::addMember(const char* declaration, size_t offset) {
	check( engine->RegisterObjectProperty(name.c_str(), declaration, (int)offset) );
#ifdef DOCUMENT_API
	return *new MemberDoc(name, declaration);
#endif
}
	
void ClassBind::setReferenceFuncs(asSFuncPtr grab, asSFuncPtr drop) {
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_ADDREF, "void f()", grab, asCALL_THISCALL) );
	check( engine->RegisterObjectBehaviour(name.c_str(), asBEHAVE_RELEASE, "void f()", drop, asCALL_THISCALL) );
}

InterfaceBind::InterfaceBind(const char* Name, bool Register) : name(Name) {
	if(Register)
		check( engine->RegisterInterface(Name) );
}

_DOC InterfaceBind::addMethod(const char* declaration, asIScriptFunction** ptr) {
	int fid = engine->RegisterInterfaceMethod(name, declaration);
#ifdef _DEBUG
	check(fid);
#endif

	if(ptr)
		*ptr = engine->GetFunctionById(fid);
#ifdef DOCUMENT_API
	return *new Documentor(fid, declaration);
#endif
}

EnumBind::EnumBind(const char* Name, bool Register) : name(Name) {
	if(Register)
		check( engine->RegisterEnum(Name) );
}


void EnumBind::setter::operator=(int val) {
	check( engine->RegisterEnumValue( enumName, itemName, val) );
}

EnumBind::setter::setter(const char* E, const char* I) : enumName(E), itemName(I) {}

EnumBind::setter EnumBind::operator[](const char* item) {
	return setter(name, item);
}

EnumBind::setter EnumBind::operator[](const std::string& item) {
	return setter(name, item.c_str());
}

#ifdef DOCUMENT_API
static std::map<std::pair<asIScriptEngine*, int>, Documentor*> documentation;
static std::map<std::pair<asIScriptEngine*, std::string>, std::string> class_documentation;
static std::map<std::pair<asIScriptEngine*, std::string>, GlobalDoc*> global_documentation;
static std::map<std::tuple<asIScriptEngine*, std::string, std::string>, MemberDoc*> member_documentation;
static threads::Mutex docMtx;

std::set<std::string> INIT_VAR(ignoredWords) {
	ignoredWords.insert("&");
	ignoredWords.insert("&in");
	ignoredWords.insert("&out");
	ignoredWords.insert("&inout");
	ignoredWords.insert("in");
	ignoredWords.insert("out");
	ignoredWords.insert("inout");
} INIT_VAR_END;

Documentor::Documentor() : fid(-1), documented(false) {
}

Documentor::Documentor(int fid, std::string decl)
	: fid(fid), decl(decl), documented(false) {

	funcSplit(decl, funcName, argNames);
	argDefaults.resize(argNames.size());

	//Only use the variable name
	for(unsigned i = 0, cnt = argNames.size(); i < cnt; ++i) {
		std::vector<std::string> parts;
		split(argNames[i], parts, ' ', true);

		//Find default argument and variable name
		argNames[i] = "";
		for(int j = parts.size() - 1; j >= 1; --j) {
			if(ignoredWords.find(parts[j]) != ignoredWords.end())
				continue;
			if(j == 1 && parts[0] == "const")
				break;
			if(j > 0 && parts[j-1] == "=") {
				argDefaults[i] = parts[j];
				--j;
			}
			else {
				argNames[i] = parts[j];
				break;
			}
		}
	}

	//Add to global list
	{
		threads::Lock lock(docMtx);
		documentation[std::pair<asIScriptEngine*,int>(engine, fid)] = this;
	}
}

void Documentor::operator()(const char* func_doc, ...) {
	if(fid == -1)
		return;
	va_list args;
	va_start(args, func_doc);

	//Function documentation
	funcDoc = func_doc;
	documented = true;

	//Arguments
	argDoc.resize(argNames.size());
	for(unsigned i = 0, cnt = argNames.size(); i < cnt; ++i)
		argDoc[i] = va_arg(args, const char*);

	//Return value
	auto* func = engine->GetFunctionById(fid);
	if(func && func->GetReturnTypeId() != asTYPEID_VOID)
		retDoc = va_arg(args, const char*);

	va_end(args);
}

Documentor* getDocumentation(asIScriptEngine* eng, int fid) {
	std::pair<asIScriptEngine*, int> key(eng, fid);
	auto it = documentation.find(key);
	if(it != documentation.end())
		return it->second;
	return 0;
}

Documentor* getDocumentation(asIScriptFunction* func) {
	std::pair<asIScriptEngine*, int> key(func->GetEngine(), func->GetId());
	auto it = documentation.find(key);
	if(it != documentation.end())
		return it->second;
	return 0;
}

GlobalDoc* getGlobalDocumentation(asIScriptEngine* eng, std::string varname) {
	std::pair<asIScriptEngine*, std::string> key(eng, varname);
	auto it = global_documentation.find(key);
	if(it != global_documentation.end())
		return it->second;
	return 0;
}

MemberDoc* getMemberDocumentation(asIScriptEngine* eng, std::string clsname, std::string varname) {
	std::tuple<asIScriptEngine*, std::string, std::string> key(eng, clsname, varname);
	auto it = member_documentation.find(key);
	if(it != member_documentation.end())
		return it->second;
	return 0;
}

std::string getClassDocumentation(asIScriptEngine* eng, std::string clsname) {
	std::pair<asIScriptEngine*, std::string> key(eng, clsname);
	auto it = class_documentation.find(key);
	if(it != class_documentation.end())
		return it->second;
	return "";
}

GlobalDoc::GlobalDoc(std::string decl) {
	std::vector<std::string> parts;
	split(decl, parts, ' ', true);
	varname = parts[parts.size() - 1];
}

void GlobalDoc::operator()(const char* _doc) {
	doc = _doc;
	threads::Lock lock(docMtx);
	global_documentation[std::pair<asIScriptEngine*,std::string>(engine, varname)] = this;
}

MemberDoc::MemberDoc(std::string clsname, std::string decl)
	: clsname(clsname) {
	std::vector<std::string> parts;
	split(decl, parts, ' ', true);
	varname = parts[parts.size() - 1];
}

void MemberDoc::operator()(const char* _doc) {
	doc = _doc;
	threads::Lock lock(docMtx);
	member_documentation[std::tuple<asIScriptEngine*,std::string,std::string>(engine, clsname, varname)] = this;
}

void ClassBind::document(std::string str) {
	threads::Lock lock(docMtx);
	class_documentation[std::pair<asIScriptEngine*,std::string>(engine, name)] = str;
}

void InterfaceBind::document(std::string str) {
	threads::Lock lock(docMtx);
	class_documentation[std::pair<asIScriptEngine*,std::string>(engine, name)] = str;
}

void EnumBind::document(std::string str) {
	threads::Lock lock(docMtx);
	class_documentation[std::pair<asIScriptEngine*,std::string>(engine, name)] = str;
}

void documentBinds() {
	std::ofstream file("api_documentation.json");
	file << "{\n";

	auto docType = [&](asIScriptEngine* eng, int tid, asDWORD flags) {
		file << eng->GetTypeDeclaration(tid);
		if(flags != 0)
			file << "&";
	};

	auto docFunction = [&](asIScriptFunction* f) {
		Documentor* doc = getDocumentation(f);

		file << "{ \"name\": \"";
		file << f->GetName();

		//Function documentation
		if(doc && doc->documented) {
			file << "\",\n\"doc\": \"";
			file << doc->funcDoc;
		}

		//Arguments
		file << "\",\n\"arguments\": [";

		unsigned argCnt = f->GetParamCount();
		for(unsigned a = 0; a < argCnt; ++a) {
			asDWORD flags;
			int tid;
			f->GetParam(a, &tid, &flags);

			if(a != 0)
				file << ",";

			file << "{ \"type\": \"";
			docType(f->GetEngine(), tid, flags);

			file << "\", \"name\": \"";
			if(doc && a < doc->argNames.size() && !doc->argNames[a].empty())
				file << doc->argNames[a];
			else
				file << "arg" + toString(a);

			if(doc && a < doc->argDefaults.size() && !doc->argDefaults[a].empty()) {
				file << "\", \"default\": \"";
				file << doc->argDefaults[a];
			}

			if(doc && a < doc->argDoc.size() && !doc->argDoc[a].empty()) {
				file << "\", \"doc\": \"";
				file << doc->argDoc[a];
			}

			file << "\"}";
		}

		file << "],\n";

		//Return value
		int tid = f->GetReturnTypeId();

		file << "\"return\": {\n";

		file << "\"type\": \"";
		docType(f->GetEngine(), tid, 0);

		if(doc && !doc->retDoc.empty()) {
			file << "\",\n\"doc\": \"";
			file << doc->retDoc;
		}

		file << "\"},\n";

		//Constness of function
		if(f->IsReadOnly())
			file << "\"const\": true";
		else
			file << "\"const\": false";

		file << "}";
	};

	auto docEngine = [&](asIScriptEngine* eng) {
		//Document classes
		file << "\"classes\": [\n";

		unsigned clsCnt = eng->GetObjectTypeCount();
		for(unsigned i = 0; i < clsCnt; ++i) {
			auto* cls = eng->GetObjectTypeByIndex(i);

			if(i != 0)
				file << ",\n";

			file << "{ \"name\": \"";
			file << cls->GetName();

			std::string clsdoc = getClassDocumentation(eng, cls->GetName());
			if(!clsdoc.empty()) {
				file << "\",\n\"doc\": \"";
				file << clsdoc;
			}

			if(cls->GetFlags() & asOBJ_SCRIPT_OBJECT && cls->GetSize() == 0)
				file << "\",\n\"interface\": true";
			else
				file << "\",\n\"interface\": false";

			//Document members
			file << ",\n\"members\": [";

			unsigned memCnt = cls->GetPropertyCount();
			for(unsigned m = 0; m < memCnt; ++m) {
				const char* name;
				int typeId;

				cls->GetProperty(m, &name, &typeId);

				if(m != 0)
					file << ",";
				file << "{\n";

				file << "\"type\": \"";
				docType(eng, typeId, 0);

				file << "\",\n\"name\": \"";
				file << name;

				auto* mdoc = getMemberDocumentation(eng, cls->GetName(), name);
				if(mdoc && !mdoc->doc.empty()) {
					file << "\",\n\"doc\": \"";
					file << mdoc->doc;
				}

				file << "\"}";
			}

			file << "],\n";

			//Document methods
			file << "\"methods\": [";

			unsigned mthCnt = cls->GetMethodCount();
			for(unsigned m = 0; m < mthCnt; ++m) {
				if(m != 0)
					file << ",\n";
				docFunction(cls->GetMethodByIndex(m));
			}

			file << "]\n";
			file << "}";
		}

		file << "],\n";

		//Document enums
		file << "\"enums\": [";
		unsigned enumCnt = eng->GetEnumCount();
		for(unsigned i = 0; i < enumCnt; ++i) {
			int enumid;
			const char* name;

			name = eng->GetEnumByIndex(i, &enumid);

			if(i != 0)
				file << ",";
			file << "\n{";

			file << "\"name\": \"";
			file << name;

			std::string clsdoc = getClassDocumentation(eng, name);
			if(!clsdoc.empty()) {
				file << "\",\n\"doc\": \"";
				file << clsdoc;
			}

			file << "\",\n\"values\": {";

			unsigned vCnt = eng->GetEnumValueCount(enumid);
			for(unsigned j = 0; j < vCnt; ++j) {
				const char* vname;
				int val;
				vname = eng->GetEnumValueByIndex(enumid, j, &val);

				if(j != 0)
					file << ",\n";
				file << "\"" << vname << "\": " << val;
			}

			file << "}}";
		}
		file << "],\n";

		//Document global functions
		file << "\"functions\": [\n";

		unsigned funcCnt = eng->GetGlobalFunctionCount();
		for(unsigned i = 0; i < funcCnt; ++i) {
			auto* f = eng->GetGlobalFunctionByIndex(i);

			if(i != 0)
				file << ",\n";
			docFunction(f);
		}


		file << "],\n";

		//Document global variables
		file << "\"globals\": [";

		unsigned propCnt = eng->GetGlobalPropertyCount();
		for(unsigned p = 0; p < propCnt; ++p) {
			const char* name, *ns;
			int typeId;

			eng->GetGlobalPropertyByIndex(p, &name, &ns, &typeId);

			if(p != 0)
				file << ",";
			file << "{\n";

			file << "\"type\": \"";
			docType(eng, typeId, 0);

			file << "\",\n\"ns\": \"";
			file << ns;

			file << "\",\n\"name\": \"";
			file << name;

			auto* pdoc = getGlobalDocumentation(eng, name);
			if(pdoc) {
				file << "\",\n\"doc\": \"";
				file << pdoc->doc;
			}

			file << "\"}";
		}

		file << "]\n";
	};

	file << "\"server\": {\n";
	docEngine(devices.scripts.cache_server->engine);
	file << "},\n\n";

	file << "\"client\": {\n";
	docEngine(devices.scripts.client->engine);
	file << "}\n";

	file << "}\n";
	file.close();
}
#endif

};
