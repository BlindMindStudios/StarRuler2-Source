#include "script_type.h"
#include "script_bind.h"
#include "main/logging.h"
#include "str_util.h"

namespace scripts {

ScriptType::ScriptType(const std::string& Name, int ID)
	: id(ID), name(Name), manager(0), type(0) {
}

void ScriptType::bind(Manager* mng, const std::vector<std::string>& decls) {
	manager = mng;

	//Split into module and class name
	std::vector<std::string> parts;
	split(scriptClass, parts, "::");

	if(parts.size() != 2) {
		error("ERROR: Invalid type script type declaration '%s'.\n", scriptClass.c_str());
		return;
	}

	//Find the object type
	type = manager->getClass(parts[0].c_str(), parts[1].c_str());
	if(!type) {
		error("ERROR: Could not find script type '%s'.\n", scriptClass.c_str());
		return;
	}

	//Find all the functions
	functions.reserve(decls.size());
	auto it = decls.begin(), end = decls.end();
	for(; it != end; ++it) {
		asIScriptFunction* func = type->GetMethodByDecl(it->c_str());
		functions.push_back(func);
	}
}

bool ScriptType::has(unsigned index) {
	if(index >= functions.size())
		return false;
	return functions[index] != 0;
}

Call ScriptType::call(unsigned index) {
	if(index >= functions.size() || functions[index] == 0)
		return Call();
	return manager->call(functions[index]);
}

void* ScriptType::create() {
	if(!type)
		return 0;
	return manager->engine->CreateScriptObject(type);
}

ScriptTypes::~ScriptTypes() {
	clear();
}

void ScriptTypes::clear() {
	auto it = types.begin(), end = types.end();
	for(; it != end; ++it)
		delete *it;
	types.clear();
}

int ScriptTypes::add(ScriptType* type) {
	type->id = types.size();
	types.push_back(type);

	return type->id;
}

ScriptType* ScriptTypes::get(int id) {
	if(id < 0 || (unsigned)id >= types.size())
		return 0;
	return types[id];
}

void ScriptTypes::registerEnum(std::string enumName, std::string prefix) {
	EnumBind enm(enumName.c_str());

	auto it = types.begin(), end = types.end();
	for(; it != end; ++it) {
		ScriptType& type = **it;
		enm[prefix + type.name] = type.id;
	}
}

void ScriptTypes::bind(Manager* manager, const std::vector<std::string>& decls) {
	auto it = types.begin(), end = types.end();
	for(; it != end; ++it)
		(*it)->bind(manager, decls);
}

void ScriptTypes::each(std::function<void(ScriptType&)> func) {
	auto it = types.begin(), end = types.end();
	for(; it != end; ++it)
		func(**it);
}

};
