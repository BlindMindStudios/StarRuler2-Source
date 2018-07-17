#pragma once
#include "scene/node.h"
#include <string>

class asIScriptObject;
class asIScriptFunction;

namespace scripts {
	struct WrappedMethod;
};

namespace scene {
	
	struct scriptNodeType {
		unsigned id;
		std::string name, identifier;
		asIScriptFunction *factory, *preRender, *render;
		std::vector<scripts::WrappedMethod*> methods;

		scriptNodeType(const std::string& name, const std::string& ident);
		void bind();
	};

	class ScriptedNode : public Node {
		unsigned errors;

		~ScriptedNode();

		bool preRender(render::RenderDriver& driver);
		void render(render::RenderDriver& driver);
		void destroy();
		NodeType getType() const override;

	public:
		asIScriptObject* scriptObject;
		scriptNodeType& type;

		ScriptedNode(scriptNodeType* nodeType);
		static ScriptedNode* create(const std::string& type);
	};

	void loadScriptNodeTypes(const std::string& filename);
	void bindScriptNodeTypes();
	void clearScriptNodeTypes();
	const char* getScriptNodeName(unsigned id);
};
