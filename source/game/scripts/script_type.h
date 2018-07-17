#pragma once
#include "manager.h"
#include <string>
#include <unordered_map>
#include <functional>

namespace scripts {

//Generic type that can pre-cache function pointers for a type.
struct ScriptType {
	Manager* manager;
	asITypeInfo* type;
	std::vector<asIScriptFunction*> functions;

	int id;
	std::string name;
	std::string scriptClass;

	ScriptType(const std::string& name, int id = -1);

	void bind(Manager* manager, const std::vector<std::string>& functionDeclarations);

	bool has(unsigned index);
	Call call(unsigned index);

	void* create();
};

//Container for script types that manages them
class ScriptTypes {
	std::vector<ScriptType*> types;
public:
	~ScriptTypes();

	//Clear and delete all script types
	void clear();

	//Add a new script type to the database
	// Returns the reserved id of the type
	int add(ScriptType* type);

	//Get the script type corresponding to the id
	ScriptType* get(int id);

	//Bind all added script types
	void bind(Manager* manager, const std::vector<std::string>& functionDeclarations);

	//Register the type enum to the active script engine
	void registerEnum(std::string enumName, std::string prefix);

	//Call a function on all types
	void each(std::function<void(ScriptType&)> func);
};

};
