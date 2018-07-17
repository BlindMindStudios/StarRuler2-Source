#include "scripted_node.h"
#include "angelscript.h"
#include "scripts/manager.h"
#include "scripts/script_components.h"
#include "scripts/generic_call.h"
#include "main/references.h"
#include "main/logging.h"
#include "util/format.h"
#include "str_util.h"
#include <fstream>
#include <unordered_map>
#include "threads.h"
#include "frustum.h"

std::unordered_map<std::string, scene::scriptNodeType*> nodeTypes;
static unsigned nextScriptNodeID = 0;

namespace scene {
	scriptNodeType::scriptNodeType(const std::string& Name, const std::string& ident)
		: id(nextScriptNodeID++), name(Name), identifier(ident), factory(0), preRender(0), render(0) {}

	void scriptNodeType::bind() {
		asITypeInfo* type = 0;

		std::vector<std::string> parts;
		split(identifier, parts, "::");
		if(parts.size() == 2)
			type = devices.scripts.client->getClass(parts[0].c_str(),parts[1].c_str());

		if(type) {
			factory = type->GetFactoryByDecl(format("$1@ $1(Node&)", type->GetName()).c_str());
			preRender = type->GetMethodByDecl("bool preRender(Node&)",false);
			render = type->GetMethodByDecl("void render(Node&)",false);

			for(unsigned i = 0; i < methods.size(); ++i) {
				auto* method = methods[i];

				auto descContaining = method->desc;
				descContaining.prepend(scripts::GT_Node_Ref);
				
				method->func = type->GetMethodByDecl(descContaining.declaration().c_str(),false);
				if(method->func) {
					method->desc = descContaining;
					method->passContaining = true;
				}
				else {
					method->func = type->GetMethodByDecl(method->desc.declaration().c_str(),false);
				}
			}
		}
		else {
			error("'%s' was not a valid script class identifier", identifier.c_str());
		}
	}

	ScriptedNode::ScriptedNode(scriptNodeType* nodeType) : scriptObject(0), errors(0), type(*nodeType) {
		if(asIScriptFunction* func = type.factory) {
			auto call = devices.scripts.client->call(func);
			call.push(this);
			call.call(scriptObject);
			if(scriptObject)
				scriptObject->AddRef();
			else
				throw "Failed to create script node";
		}
		else {
			throw "Script object has no acceptable factory";
		}
	}
	
	ScriptedNode* ScriptedNode::create(const std::string& type) {
		try {
			auto entry = nodeTypes.find(type);
			if(entry != nodeTypes.end())
				return new ScriptedNode(entry->second);
			else
				error("Error creating script node '%s': No such node type", type.c_str());
		}
		catch(const char* err) {
			error("Error creating script node '%s': %s", type.c_str(), err);
		}
		return 0;
	}

	void ScriptedNode::destroy() {
		if(scriptObject) {
			scriptObject->Release();
			scriptObject = 0;
		}

		Node::destroy();
	}
	
	ScriptedNode::~ScriptedNode() {
		if(scriptObject)
			scriptObject->Release();
	}
	
	NodeType ScriptedNode::getType() const {
		return (NodeType)(NT_ScriptBase + type.id);
	}

	bool ScriptedNode::preRender(render::RenderDriver& driver) {
		if(!scriptObject)
			return false;

		sortDistance = abs_position.distanceTo(driver.cam_pos);

		//Call scripted pre-render if available
		if(asIScriptFunction* func = type.preRender) {
			auto call = devices.scripts.client->call(func);
			call.setObject(scriptObject);
			call.push(this);

			bool ret = false;
			if(!call.call(ret)) {
				if(++errors >= 3) {
					markForDeletion();
					return false;
				}
			}

			if(!ret)
				return false;
		}

		if(!visible)
			return false;
		if(!getFlag(NF_NoCulling) && !driver.getViewFrustum().overlaps(abs_position, abs_scale))
			return false;
		return true;
	}

	void ScriptedNode::render(render::RenderDriver& driver) {
		if(!scriptObject)
			return;
		if(asIScriptFunction* func = type.render) {
			auto call = devices.scripts.client->call(func);
			call.setObject(scriptObject);
			call.push(this);

			if(!call.call()) {
				if(++errors >= 3) {
					markForDeletion();
				}
			}
		}
	}

	void loadScriptNodeTypes(const std::string& filename) {
		std::ifstream file(filename);
		skipBOM(file);
		char name[80], script[80], bracket;

		bool inType = false;
		scriptNodeType* type = 0;

		while(true) {
			std::string line;
			std::getline(file, line);
			if(file.fail())
				break;

			std::string parse = line.substr(0, line.find("//"));
			if(parse.find_first_not_of(" \t\n\r") == std::string::npos)
				continue;
		
			if(!inType) {
				int args = sscanf(parse.c_str(), "Node %79s from %79s {", name, script);
				if(args != 2) {
					error("Unrecognized line '%s'", line.c_str());
					continue;
				}

				std::string typeName = name;

				if(nodeTypes.find(typeName) != nodeTypes.end()) {
					error("Duplicate node type '%s'", name);
					continue;
				}

				type = new scriptNodeType(name, script);
				nodeTypes[name] = type;

				inType = true;
			}
			else if(type) {
				int args = sscanf(parse.c_str(), " %c", &bracket);
				if(args == 1 && bracket == '}') {
					inType = false;
					continue;
				}

				parse = trim(parse);

				if(parse[parse.size() - 1] == ':') {
					parse[parse.size() - 1] = ' ';
					continue;
				}

				//Parse declaration
				scripts::GenericCallDesc desc;
				desc.parse(parse, true, false);

				if(desc.returnType.type) {
					error("Error: '%s': node functions may not return a value.", parse.c_str());
					continue;
				}

				//Create method desc
				scripts::WrappedMethod* m = new scripts::WrappedMethod();
				m->index = (unsigned)type->methods.size();
				m->compId = 0;
				m->local = true;
				m->server = true;
				m->shadow = true;
				m->wrapped = desc;
				m->restricted = false;

				m->desc.append(desc);
				m->desc.name = desc.name;
				m->desc.constFunction = false;
				m->desc.returnType = desc.returnType;
				m->desc.returnsArray = m->wrapped.returnsArray;

				type->methods.push_back(m);
			}
			else {
				if(parse.find('}') != std::string::npos)
					inType = false;
			}
		}
	}

	void bindScriptNodeTypes() {
		foreach(it, nodeTypes)
			it->second->bind();
	}

	void clearScriptNodeTypes() {
		foreach(it, nodeTypes)
			delete it->second;
		nodeTypes.clear();
		nextScriptNodeID = 0;
	}
	
	const char* getScriptNodeName(unsigned id) {
		foreach(it, nodeTypes)
			if(it->second->id == id)
				return it->first.c_str();
		return "";
	}
};
