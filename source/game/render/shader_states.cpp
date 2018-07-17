#include "obj/object.h"
#include "scene/node.h"
#include "main/references.h"
#include "main/logging.h"
#include <map>

struct StateVar {
	ScriptObjectType* type;
	unsigned offset;
};

std::map<std::string,unsigned> vars;
std::vector<StateVar> stateVars;

unsigned registerVar(const std::string& name) {
	auto entry = vars.find(name);
	if(entry == vars.end()) {
		unsigned index = (unsigned)vars.size();
		vars[name] = index;
		return index;
	}
	else {
		return entry->second;
	}
}

void prepareShaderStateVars() {
	stateVars.resize(vars.size());
	for(auto i = vars.begin(), end = vars.end(); i != end; ++i) {
		StateVar& var = stateVars[i->second];
		var.type = 0;

		auto pos = i->first.find("::");
		if(pos == std::string::npos) {
			error("Shader State Variable: '%s' is not a state (should be ObjectType::MemberName)", i->first.c_str());
			continue;
		}

		std::string objName = i->first.substr(0,pos), memberName = i->first.substr(pos+2);

		ScriptObjectType* type = getScriptObjectType(objName);
		if(type == 0) {
			error("Shader State Variable: '%s' is not an object type (from '%s')", objName.c_str(), i->first.c_str());
			continue;
		}

		bool memberFound = false;

		//Locate the member, and make sure it is a double
		const StateDefinition& states = *type->states;
		unsigned base = sizeof(Object);
		states.align(base);
		for(unsigned j = 0; j < states.types.size(); ++j) {
			auto& member = states.types[j];
			if(member.name == memberName) {
				memberFound = true;

				if(member.def->type == "double") {
					var.offset = base + member.offset;
					var.type = type;
				}
				else {
					error("Shader State Variable: Only doubles are supported");
				}
				break;
			}
		}

		if(!memberFound) {
			error("Shader State Variable: %s has no member of type '%s'", objName.c_str(), memberName.c_str());
		}
	}
}

void clearShaderStateVars() {
	stateVars.clear();
	vars.clear();
}

void shader_statevars(float* out, unsigned short n, void* args) {
	if(!scene::renderingNode)
		return;

	Object* obj = scene::renderingNode->obj;
	if(obj) {
		int* indices = (int*)args;
		char* base = (char*)obj;

		for(unsigned short i = 0; i < n; ++i) {
			const StateVar& var = stateVars[indices[i]];
			if(obj->type == var.type)
				out[i] = (float)*(double*)(base + var.offset);
			else
				out[i] = 0;
		}
	}
	else {
		for(unsigned short i = 0; i < n; ++i)
			out[i] = 0;
	}
}
