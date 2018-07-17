#include "binds.h"
#include "obj/object.h"
#include "empire.h"
#include "util/format.h"
#include "main/logging.h"
#include "main/initialization.h"
#include "main/references.h"
#include "processing.h"
#include "scripts/script_components.h"
#include "scene/scripted_node.h"

extern std::vector<ScriptObjectType*> objTypeList;
extern const StateDefinition* empStates;
extern std::unordered_map<std::string, scene::scriptNodeType*> nodeTypes;

namespace scripts {

extern Object* objTarget(Object* obj, unsigned num);
extern void bindObject(ClassBind& object, ScriptObjectType* type, bool server);
extern void bindScriptNode(ClassBind& bind);

static Object* baseCast(Object* obj) {
	if(obj)
		obj->grab();
	return obj;
}

static void castObj(asIScriptGeneric* f) {
	Object* obj = (Object*)f->GetObject();
	if(!obj || obj->type != f->GetFunction()->GetUserData()) {
		f->SetReturnAddress(0);
	}
	else {
		obj->grab();
		f->SetReturnAddress(obj);
	}
}

static void isObjectType(asIScriptGeneric* f) {
	Object* obj = (Object*)f->GetObject();
	if(!obj || obj->type != f->GetFunction()->GetUserData())
		f->SetReturnByte(false);
	else
		f->SetReturnByte(true);
}

static scene::Node* nodeBaseCast(scene::ScriptedNode* node) {
	if(node)
		node->grab();
	return node;
}

static void nodeCast(asIScriptGeneric* f) {
	scene::ScriptedNode* node = dynamic_cast<scene::ScriptedNode*>((scene::Node*)f->GetObject());
	if(!node || &node->type != f->GetFunction()->GetUserData()) {
		f->SetReturnAddress(0);
	}
	else {
		node->grab();
		f->SetReturnAddress(node);
	}
}

//Stored component offsets for each object type
void SetObjectTypeOffsets() {
	auto* bpState = getStateValueType("Blueprint");
	for(auto i = objTypeList.begin(), end = objTypeList.end(); i != end; ++i) {
		ScriptObjectType* type = *i;
		const StateDefinition& def = *type->states;

		unsigned compCnt = getComponentCount();
		type->componentOffsets.resize(compCnt, 0);
		type->optionalComponents.resize(compCnt, false);
		
		unsigned base = sizeof(Object);
		StateDefinition::align(base);

		for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
			auto& mtype = *var->def;
			if(&mtype == bpState)
				type->blueprintOffset = base + var->offset;

			bool optional = false;
			Component* comp = getComponent(&mtype, &optional);
			if(comp) {
				if(type->componentOffsets[comp->id] != 0) {
					error("ERROR: Object type '%s' has two components of type '%s'.",
						type->name.c_str(), comp->name.c_str());
				}
				else {
					type->componentOffsets[comp->id] = base + var->offset;
					type->optionalComponents[comp->id] = optional;
				}
			}
		}
	}
}

static void writeEmpStates(Empire* emp, net::Message& msg) {
	auto* def = Empire::getEmpireStates();
	if(!def)
		return;
	def->syncWrite(msg, emp + 1);
}

static void readEmpStates(Empire* emp, net::Message& msg) {
	auto* def = Empire::getEmpireStates();
	if(!def)
		return;
	def->syncRead(msg, emp + 1);
}

static void restrictedState(asIScriptGeneric* f) {
	Object* obj = (Object*)f->GetObject();
	auto* member = (StateDefinition::stateDefMember*)f->GetFunction()->GetUserData();

	if(obj->owner != Empire::getPlayerEmpire()) {
		info("Cannot access state on unowned objects.");
		member->def->setReturn(f, nullptr);
	}
	else {
		void* memory = (void*)(obj + 1);
		StateDefinition::align(memory);
		member->def->setReturn(f, ((char*)memory) + member->offset);
	}
}

static void paramStateGet(asIScriptGeneric* f) {
	Object* obj = (Object*)f->GetObject();
	auto* member = (StateDefinition::stateDefMember*)f->GetFunction()->GetUserData();

	void* memory = (void*)(obj + 1);
	StateDefinition::align(memory);
	member->def->setReturn(f, ((char*)memory) + member->offset);
}

static void paramStateSet(asIScriptGeneric* f) {
	Object* obj = (Object*)f->GetObject();
	auto* member = (StateDefinition::stateDefMember*)f->GetFunction()->GetUserData();

	void* memory = (void*)(obj + 1);
	StateDefinition::align(memory);
	member->def->setFromParam(f, ((char*)memory) + member->offset);
}

static void nodeFactory(asIScriptGeneric* f) {
	auto* type = (scene::scriptNodeType*)f->GetFunction()->GetUserData();
	scene::Node* node = new scene::ScriptedNode(type);
	if(processing::isRunning())
		node->queueReparent(devices.scene);
	else
		devices.scene->addChild(node);
	*(scene::Node**)f->GetAddressOfReturnLocation() = node;
}

static double configGet(const std::string& name) {
	auto it = gameConfig.indices.find(name);
	if(it == gameConfig.indices.end())
		return 0;
	return gameConfig.values[it->second];
}

static void configSet(const std::string& name, double value) {
	auto it = gameConfig.indices.find(name);
	if(it != gameConfig.indices.end())
		gameConfig.values[it->second] = value;
}

static double configGet_id(unsigned id) {
	if(id >= gameConfig.count)
		return 0;
	return gameConfig.values[id];
}

static void configSet_id(unsigned id, double value) {
	if(id >= gameConfig.count)
		return;
	gameConfig.values[id] = value;
}

static std::string configGetName(unsigned id) {
	if(id >= gameConfig.count)
		return "";
	return gameConfig.names[id];
}

static unsigned configGetIndex(const std::string& name) {
	auto it = gameConfig.indices.find(name);
	if(it != gameConfig.indices.end())
		return it->second;
	return (unsigned)-1;
}

void RegisterObjectDefinitions() {
	//Create the object types (states may refer to them)
	for(auto i = objTypeList.begin(), end = objTypeList.end(); i != end; ++i) {
		ScriptObjectType* type = *i;
		ClassBind object(type->name.c_str(), asOBJ_REF);
	}
}

static std::unordered_map<std::string,unsigned> empAttribNames;
static std::vector<std::string> empAttribIdents;
static std::vector<size_t> empAttribOffsets;

double getEmpAttrib(Empire* emp, unsigned index) {
	if(index >= empAttribOffsets.size())
		return 0.0;
	return *(double*)(((char*)emp) + empAttribOffsets[index]);
}

void setEmpAttrib(Empire* emp, unsigned index, double value) {
	if(index >= empAttribOffsets.size())
		return;
	*(double*)(((char*)emp) + empAttribOffsets[index]) = value;
}

unsigned getEmpAttribIndex(const std::string& str) {
	auto it = empAttribNames.find(str);
	if(it == empAttribNames.end())
		return (unsigned)-1;
	return it->second;
}

std::string getEmpAttribName(unsigned id) {
	if(id >= empAttribIdents.size())
		return "";
	return empAttribIdents[id];
}

void buildEmpAttribIndices() {
	empAttribNames.clear();
	empAttribIdents.clear();
	empAttribOffsets.clear();
	auto* doubleType = getStateValueType("double");

	if(!empStates)
		return;

	unsigned base = sizeof(Empire);
	StateDefinition::align(base);
	
	const StateDefinition& def = *empStates;
	for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
		//Bind member
		auto& mtype = *var->def;

		//Doubles are accessible generically in order to facilitate empire attributes
		if(&mtype == doubleType && var->attribute) {
			empAttribNames[var->name] = empAttribOffsets.size();
			empAttribOffsets.push_back(base + var->offset);
			empAttribIdents.push_back(var->name);
		}
	}
}

void RegisterDynamicTypes(bool server) {
	//Bind global object states
	{
		ClassBind object("Object");
		const StateDefinition& def = getStateDefinition("Object");
		if(&def != &errorStateDefinition) {
			//Add state list vars
			unsigned base = sizeof(Object);
			StateDefinition::align(base);

			for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
				//Bind member
				auto& mtype = *var->def;

				if(mtype.isParam()) {
					if(var->def->returnable()) {
						if(var->access != SR_Visible) {
							object.addGenericMethod(format("$1 get_$2() const",
									mtype.returnType.empty() ? mtype.type : mtype.returnType,
									var->name).c_str(),
								asFUNCTION(restrictedState), (void*)&*var)
							doc("Member created from datafiles.", "");
						}
						else {
							object.addGenericMethod(format("$1 get_$2() const",
									mtype.returnType.empty() ? mtype.type : mtype.returnType,
									var->name).c_str(),
								asFUNCTION(paramStateGet), (void*)&*var)
							doc("Member created from datafiles.", "");
						}
					}
					if(server) {
						object.addGenericMethod(format("void set_$2($1 value)",
								mtype.type, var->name).c_str(),
							asFUNCTION(paramStateSet), (void*)&*var)
						doc("Member created from datafiles.", "");
					}
				}
				else if(server || var->access == SR_Visible) {
					object.addMember(format("$1 $2", mtype.type, var->name).c_str(), base + var->offset)
						doc("Member created from datafiles.");
				}
				else if(var->access == SR_Restricted) {
					if(var->def->returnable()) {
						object.addGenericMethod(format("$1 get_$2() const",
								mtype.returnType.empty() ? mtype.type : mtype.returnType,
								var->name).c_str(),
							asFUNCTION(restrictedState), (void*)&*var)
						doc("Member created from datafiles.", "");
					}
				}
			}
		}
	}

	//Bind each custom object type, adding its state list variables in
	EnumBind objType("ObjectType", false);
	objType["OT_COUNT"] = objTypeList.size();
	for(auto i = objTypeList.begin(), end = objTypeList.end(); i != end; ++i) {
		ScriptObjectType* type = *i;
		const StateDefinition& def = *type->states;

		EnumBind objType("ObjectType", false);
		objType[std::string("OT_")+type->name] = type->id;

		ClassBind genObj("Object");
		ClassBind object(type->name.c_str());
		classdoc(object,"Derived Object created based on datafiles. Can be cast to and from an Object@.");
		bindObject(object, type, server);
		RegisterObjectComponentWrappers(object, server, type);
		
		object.addExternMethod("Object@ opImplCast() const",
				asFUNCTION(baseCast));
		genObj.addGenericMethod(format("$1@ opCast() const", object.name).c_str(),
				asFUNCTION(castObj), type);
		genObj.addGenericMethod(format("bool get_is$1() const", object.name).c_str(),
				asFUNCTION(isObjectType), type);

		//Add state list vars
		unsigned base = sizeof(Object);
		StateDefinition::align(base);

		for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
			//Bind member
			auto& mtype = *var->def;

			if(mtype.isParam()) {
				if(var->def->returnable()) {
					if(var->access != SR_Visible) {
						object.addGenericMethod(format("$1 get_$2() const",
								mtype.returnType.empty() ? mtype.type : mtype.returnType,
								var->name).c_str(),
							asFUNCTION(restrictedState), (void*)&*var)
						doc("Member created from datafiles.", "");
					}
					else {
						object.addGenericMethod(format("$1 get_$2() const",
								mtype.returnType.empty() ? mtype.type : mtype.returnType,
								var->name).c_str(),
							asFUNCTION(paramStateGet), (void*)&*var)
						doc("Member created from datafiles.", "");
					}
				}
				if(server) {
					object.addGenericMethod(format("void set_$2($1 value)",
							mtype.type, var->name).c_str(),
						asFUNCTION(paramStateSet), (void*)&*var)
					doc("Member created from datafiles.", "");
				}
			}
			else if(server || var->access == SR_Visible) {
				object.addMember(format("$1 $2", mtype.type, var->name).c_str(), base + var->offset)
					doc("Member created from datafiles.");
			}
			else if(var->access == SR_Restricted) {
				if(var->def->returnable()) {
					object.addGenericMethod(format("$1 get_$2() const",
							mtype.returnType.empty() ? mtype.type : mtype.returnType,
							var->name).c_str(),
						asFUNCTION(restrictedState), (void*)&*var)
					doc("Member created from datafiles.", "");
				}
			}
		}
	}

	//Bind game config
	{
		Namespace ns("config");
		for(size_t i = 0; i < gameConfig.count; ++i)
			bindGlobal(format("double $1", gameConfig.names[i]).c_str(), (void*)&gameConfig.values[i]);
		bind("double get(const string& name)", asFUNCTION(configGet));
		bind("void set(const string& name, double value)", asFUNCTION(configSet));
		bind("double get(uint index)", asFUNCTION(configGet_id));
		bind("void set(uint index, double value)", asFUNCTION(configSet_id));
		bind("string getName(uint index)", asFUNCTION(configGetName));
		bind("uint getIndex(const string& name)", asFUNCTION(configGetIndex));
	}

	//Bind empire states
	if(empStates) {
		const StateDefinition& def = *empStates;
		auto* doubleType = getStateValueType("double");

		EnumBind attr("EmpireAttribute");

		ClassBind emp("Empire");
		unsigned base = sizeof(Empire);
		StateDefinition::align(base);

		bind("uint getEmpireAttribute(const string& name)", asFUNCTION(getEmpAttribIndex));
		bind("string getEmpireAttributeName(uint id)", asFUNCTION(getEmpAttribName));
		emp.addExternMethod("double get_attributes(uint index) const", asFUNCTION(getEmpAttrib));
		if(server)
			emp.addExternMethod("void set_attributes(uint index, double value)", asFUNCTION(setEmpAttrib));

		emp.addExternMethod("void writeSyncedStates(Message& msg)", asFUNCTION(writeEmpStates));
		emp.addExternMethod("void readSyncedStates(Message& msg)", asFUNCTION(readEmpStates));

		for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
			//Bind member
			auto& mtype = *var->def;

			emp.addMember(format("$1 $2", mtype.type, var->name).c_str(), base + var->offset)
				doc("Member created from datafiles.");

			//Doubles are accessible generically in order to facilitate empire attributes
			if(&mtype == doubleType && var->attribute)
				attr[std::string("EA_")+var->name] = empAttribNames[var->name];
		}

		attr["EA_COUNT"] = empAttribNames.size();
	}

	//Node methods
	for(auto i = nodeTypes.begin(), end = nodeTypes.end(); i != end; ++i) {
		auto* type = i->second;
		ClassBind baseNode("Node");
		ClassBind node(type->name.c_str(), asOBJ_REF);
			classdoc(node,"Derived Node created based on datafiles. Can be cast to and from a Node@.");

		node.addGenericFactory(format("$1@ f()", type->name).c_str(), asFUNCTION(nodeFactory), type);

		node.addExternMethod("Node@ opImplCast() const",
				asFUNCTION(nodeBaseCast));
		baseNode.addGenericMethod(format("$1@ opCast() const", type->name).c_str(),
				asFUNCTION(nodeCast), type);

		RegisterNodeMethodWrappers(node, server, type);
		bindScriptNode(node);
	}
}

};
