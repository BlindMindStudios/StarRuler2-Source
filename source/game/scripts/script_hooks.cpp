#include "binds.h"
#include "generic_call.h"
#include "compat/misc.h"
#include <fstream>
#include "main/logging.h"
#include "render/spritesheet.h"
#include "str_util.h"
#include "../source/as_objecttype.h"
#include "../as_addons/include/scriptarray.h"

void dummy() {
}

namespace scripts {

static std::vector<GenericCallDesc*> hooks;

void LoadScriptHooks(const std::string& filename) {
	//Clear existing hooks
	foreach(it, hooks)
		delete *it;
	hooks.clear();

	//Load new hooks
	std::ifstream file(filename);
	if(!file.is_open())
		return;
	skipBOM(file);
	
	while(true) {
		std::string line;
		std::getline(file, line);
		if(file.fail())
			break;

		std::string parse = line.substr(0, line.find("//"));
		if(parse.find_first_not_of(" \t\n\r") == std::string::npos)
			continue;

		parse = trim(parse);
		hooks.push_back(new GenericCallDesc(parse, true, true));
	}
}

static void getHook(asIScriptGeneric* f) {
	const std::string& func = *(std::string*)f->GetArgAddress(0);
	GenericCallDesc* desc = (GenericCallDesc*)f->GetFunction()->GetUserData();

	std::vector<std::string> parts;
	split(func, parts, "::");

	if(parts.size() != 2) {
		throwException(format("Invalid hook specifier '$1'.", func).c_str());
		return;
	}

	//First part is the module
	const std::string& module = parts[0];

	//Create a call description with the new function name
	GenericCallDesc lookup = *desc;
	lookup.name = parts[1];

	std::string decl = lookup.declaration();

	//Find the function
	Manager* man = getActiveManager();
	asIScriptFunction* ptr = man->getFunction(module.c_str(), decl.c_str());

	if(!ptr) {
		throwException(format("Could not find script function '$1'", decl).c_str());
		return;
	}

	//Copy the pointer into the target position
	*(asIScriptFunction**)f->GetObject() = ptr;
}

static void emptyHook(asIScriptFunction** f) {
	*f = 0;
}

static GenericValue callHook(void* arg, GenericCallData& data) {
	Manager* man = getActiveManager();
	asIScriptFunction* func = *(asIScriptFunction**)data.object;

	if(!func) {
		throwException("Unbound script hook called.");
		return GenericValue();
	}

	Call cl = man->call(func);
	data.pushTo(cl);
	return data.call(cl);
}

static bool validHook(asIScriptFunction** f) {
	return *f != 0;
}

static asIScriptFunction** assignHook(asIScriptFunction** dest, asIScriptFunction** src) {
	*dest = *src;
	return dest;
}

static asITypeInfo* getClass(const std::string& func) {
	std::vector<std::string> parts;
	split(func, parts, "::");

	asITypeInfo* type = nullptr;
	if(parts.size() == 1) {
		auto* ctx = asGetActiveContext();
		if(ctx) {
			auto* func = ctx->GetFunction();
			type = getActiveManager()->getClass(func->GetModuleName(), parts[0].c_str());
		}
	}
	else if(parts.size() == 2) {
		type = getActiveManager()->getClass(parts[0].c_str(), parts[1].c_str());
	}
	else {
		throwException(format("Invalid class specifier '$1'.", func).c_str());
		return 0;
	}

	if(type)
		type->AddRef();
	return type;
}

static asIScriptObject* createClass(asITypeInfo* scriptType) {
	asIScriptObject* ptr = 0;
	asIScriptFunction* func = scriptType->GetFactoryByIndex(0);
	if(!func)
		return nullptr;
	scripts::Call cl = getActiveManager()->call(func);
	cl.call(ptr);

	if(ptr)
		ptr->AddRef();
	return ptr;
}

static asITypeInfo* thisClass(void* ptr, int typeId) {
	if(ptr != nullptr && (typeId & asTYPEID_SCRIPTOBJECT)) {
		auto* p = ((asIScriptObject*)ptr)->GetObjectType();
		if(p)
			p->AddRef();
		return p;
	}
	else {
		return nullptr;
	}
}

static bool implClass(asCObjectType* type, asCObjectType* impl) {
	if(!impl)
		return false;
	if(impl->IsInterface())
		return type->Implements(impl);
	else
		return type->DerivesFrom(impl);
}

static std::string modName(asIScriptModule* mod) {
	return mod->GetName();
}

static std::string className(asITypeInfo* mod) {
	return mod->GetName();
}

static unsigned modClassCount(asIScriptModule* mod) {
	return mod->GetObjectTypeCount();
}

static asITypeInfo* modClass(asIScriptModule* mod, unsigned index) {
	return mod->GetObjectTypeByIndex(index);
}

static asITypeInfo* modClassName(asIScriptModule* mod, const std::string& name) {
	return mod->GetTypeInfoByName(name.c_str());
}

static asIScriptModule* getModule(const std::string& str) {
	auto* man = getActiveManager();
	if(!man)
		return nullptr;
	auto* mod = man->getModule(str.c_str());
	if(!mod)
		return nullptr;
	return mod->module;
}

static asIScriptModule* thisModule() {
	auto* ctx = asGetActiveContext();
	if(ctx) {
		auto* func = ctx->GetFunction();
		if(func)
			return func->GetModule();
	}
	return nullptr;
}

static asIScriptModule* clsModule(asCObjectType* type) {
	return type->GetModule();
}

static int clsId(asCObjectType* type) {
	return type->GetTypeId();
}

static unsigned clsMemberCount(asCObjectType* type) {
	return type->GetPropertyCount();
}

static asITypeInfo* clsMember(asITypeInfo* type, unsigned index) {
	if(index >= type->GetPropertyCount())
		return nullptr;
	int typeId = 0;
	type->GetProperty(index, nullptr, &typeId);
	auto* memType = type->GetEngine()->GetTypeInfoById(typeId);
	if(memType)
		memType->AddRef();
	return memType;
}

static std::string clsMemberName(asITypeInfo* type, unsigned index) {
	if(index >= type->GetPropertyCount())
		return nullptr;
	const char* name;
	type->GetProperty(index, &name);
	return std::string(name);
}

static bool objGC(asCObjectType* type) {
	return type->GetFlags() & asOBJ_GC;
}

static asIScriptObject* objMember(asCObjectType* type, void* ptr, int typeId, unsigned index) {
	if(ptr != nullptr && (typeId & asTYPEID_SCRIPTOBJECT)) {
		auto* p = ((asIScriptObject*)ptr);
		if(index >= p->GetPropertyCount())
			return nullptr;
		int memType = p->GetPropertyTypeId(index);
		if(!(memType & asTYPEID_SCRIPTOBJECT))
			return nullptr;
		asIScriptObject* obj = (asIScriptObject*)p->GetAddressOfProperty(index);
		if(memType & asTYPEID_OBJHANDLE)
			obj = *(asIScriptObject**)obj;
		if(obj)
			obj->AddRef();
		return obj;
	}
	else {
		return nullptr;
	}
}

static void getImplementing(CScriptArray* arr, asCObjectType* type) {
	if(type == nullptr)
		return;
	auto* engine = type->GetEngine();
	asUINT modCnt = engine->GetModuleCount();
	for(asUINT n = 0; n < modCnt; ++n) {
		auto* module = engine->GetModuleByIndex(n);
		asUINT cnt = module->GetObjectTypeCount();
		for(asUINT i = 0; i < cnt; ++i) {
			auto* cls = module->GetObjectTypeByIndex(i);
			if(type->IsInterface() ? cls->Implements(type) : cls->DerivesFrom(type))
				arr->InsertLast(&cls);
		}
	}
}

static render::Sprite getGlobalSprite(const std::string& module, const std::string& name) {
	render::Sprite sprt;
	auto* man = getActiveManager();
	if(man != nullptr) {
		auto* type = man->engine->GetTypeInfoByName("Sprite");
		auto* mod = man->getModule(module.c_str());
		if(mod != nullptr && type != nullptr) {
			int index = mod->module->GetGlobalVarIndexByDecl((std::string("const Sprite ")+name).c_str());
			if(index < 0)
				index = mod->module->GetGlobalVarIndexByDecl((std::string("Sprite ")+name).c_str());
			if(index >= 0) {
				int typeId = 0;
				if(mod->module->GetGlobalVar(index, nullptr, nullptr, &typeId, nullptr) == asSUCCESS) {
					if(typeId == type->GetTypeId()) {
						sprt = *(render::Sprite*)mod->module->GetAddressOfGlobalVar(index);
					}
				}
			}
		}
	}
	return sprt;
}

static Color getGlobalColor(const std::string& module, const std::string& name) {
	Color col;
	auto* man = getActiveManager();
	if(man != nullptr) {
		auto* type = man->engine->GetTypeInfoByName("Color");
		auto* mod = man->getModule(module.c_str());
		if(mod != nullptr && type != nullptr) {
			int index = mod->module->GetGlobalVarIndexByDecl((std::string("const Color ")+name).c_str());
			if(index < 0)
				index = mod->module->GetGlobalVarIndexByDecl((std::string("Color ")+name).c_str());
			if(index >= 0) {
				int typeId = 0;
				if(mod->module->GetGlobalVar(index, nullptr, nullptr, &typeId, nullptr) == asSUCCESS) {
					if(typeId == type->GetTypeId()) {
						col = *(Color*)mod->module->GetAddressOfGlobalVar(index);
					}
				}
			}
		}
	}
	return col;
}

void RegisterScriptHooks() {
	foreach(it, hooks) {
		GenericCallDesc* type = *it;

		std::string name = type->name + "Hook";

		ClassBind cls(name.c_str(), asOBJ_VALUE | asOBJ_APP_CLASS_CDAK, sizeof(void*));
		cls.addConstructor("void f()", asFUNCTION(emptyHook));
		cls.addConstructor(format("void f(const $1&)", name).c_str(), asFUNCTION(assignHook));
		cls.addDestructor("void f()", asFUNCTION(dummy));

		cls.addExternMethod("bool get_valid() const", asFUNCTION(validHook));
		cls.addExternMethod(format("$1& opAssign(const $1&in)", name, name).c_str(), asFUNCTION(assignHook));

		//Constructor for the class
		int fid = getEngine()->RegisterObjectBehaviour(
			cls.name.c_str(), asBEHAVE_CONSTRUCT, "void f(const string &in)",
			asFUNCTION(getHook), asCALL_GENERIC);

		if(fid > 0)
			getEngine()->GetFunctionById(fid)->SetUserData((void*)type);

		//Secondary bind
		fid = getEngine()->RegisterObjectMethod(
			cls.name.c_str(), "void bind(const string &in)",
			asFUNCTION(getHook), asCALL_GENERIC);

		if(fid > 0)
			getEngine()->GetFunctionById(fid)->SetUserData((void*)type);

		//Call bind
		GenericCallDesc call = *type;
		call.name = "call";
		call.constFunction = true;

		bindGeneric(cls, call, callHook, (void*)type);
	}

	//Class creation
	InterfaceBind anyif("IAnyObject");
	ClassBind classptr("AnyClass", asOBJ_REF);
	classptr.setReferenceFuncs(asMETHOD(asITypeInfo, AddRef),
			asMETHOD(asITypeInfo, Release));
	classptr.addExternMethod("int get_id() const", asFUNCTION(clsId));
	classptr.addExternMethod("string get_name() const", asFUNCTION(className));
	classptr.addExternMethod("IAnyObject@ create() const", asFUNCTION(createClass));
	classptr.addExternMethod("bool implements(const AnyClass@ check) const", asFUNCTION(implClass));
	classptr.addExternMethod("uint get_memberCount() const", asFUNCTION(clsMemberCount));
	classptr.addExternMethod("AnyClass@ get_members(uint index) const", asFUNCTION(clsMember));
	classptr.addExternMethod("string get_memberName(uint index) const", asFUNCTION(clsMemberName));
	classptr.addExternMethod("IAnyObject@ getMember(const ?&, uint index) const", asFUNCTION(objMember));
	classptr.addExternMethod("bool get_isGC()", asFUNCTION(objGC));

	bind("AnyClass@ getClass(const string&in spec)", asFUNCTION(getClass));
	bind("AnyClass@ getClass(const ?&)", asFUNCTION(thisClass));

	ClassBind modptr("ScriptModule", asOBJ_REF | asOBJ_NOCOUNT);
	modptr.addExternMethod("string get_name() const", asFUNCTION(modName));
	modptr.addExternMethod("uint get_classCount() const", asFUNCTION(modClassCount));
	modptr.addExternMethod("AnyClass& get_classes(uint index) const", asFUNCTION(modClass));
	modptr.addExternMethod("AnyClass& getClass(const string& name) const", asFUNCTION(modClassName));

	classptr.addExternMethod("ScriptModule@ get_module() const", asFUNCTION(clsModule));
	bind("ScriptModule@ getScriptModule(const string& name)", asFUNCTION(getModule));
	bind("ScriptModule@ get_THIS_MODULE()", asFUNCTION(thisModule));
	bind("void getClassesImplementing(array<AnyClass@>& results, AnyClass& base)", asFUNCTION(getImplementing));

	bind("Sprite getGlobalSprite(const string& module, const string& name)", asFUNCTION(getGlobalSprite));
	bind("Color getGlobalColor(const string& module, const string& name)", asFUNCTION(getGlobalColor));
}

};
