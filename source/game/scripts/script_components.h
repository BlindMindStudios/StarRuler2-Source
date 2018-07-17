#pragma once
#include "generic_call.h"
#include <vector>
#include <string>

namespace scene {
	struct scriptNodeType;
};

struct ScriptObjectType;
class StateValueDefinition;

namespace scripts {

struct MethodFlags {
	bool local;
	bool server;
	bool shadow;
	bool restricted;
	bool async;
	bool safe;
	bool relocking;
	bool visible;

	MethodFlags() {
		reset();
	}

	void parse(std::string& flags);

	void reset() {
		local = false;
		server = false;
		shadow = false;
		restricted = false;
		async = false;
		safe = false;
		relocking = false;
		visible = false;
	}
};

struct WrappedMethod {
	GenericCallDesc desc;
	GenericCallDesc origDesc;
	GenericCallDesc wrapped;
	asIScriptFunction* func;
	std::string fullDeclaration;
	union {
		unsigned compId;
		unsigned objTypeId;
	};
	unsigned index;
	bool isComponentMethod;
	bool local;
	bool server;
	bool shadow;
	bool onlyPrimitive;
	bool restricted;
	bool async;
	bool relocking;
	bool safe;

	bool passPlayer;
	bool passContaining;

	std::string doc_desc;
	std::string doc_return;
	std::vector<std::string> doc_args;

	WrappedMethod() : compId(0), index(0), func(0), local(false),
		server(false), shadow(false), onlyPrimitive(true),
		restricted(false), async(false), relocking(false), safe(false),
		passPlayer(false), passContaining(false) {
	}
};

struct Component {
	unsigned id;
	std::string name;
	std::vector<WrappedMethod*> methods;

	std::string typeDecl;
	asITypeInfo* type;

	asIScriptFunction *save, *load;

	std::string containing;
	GenericType* containingType;

	const StateValueDefinition* def;
	const StateValueDefinition* optDef;

	Component() : id(0), type(0), save(0), load(0) {}
	~Component();
};

void clearComponents();
void loadComponents(const std::string& filename);
void addComponentStateValueTypes();

unsigned getComponentCount();
Component* getComponent(unsigned index);
Component* getComponent(const std::string& name);
Component* getComponent(const StateValueDefinition* def, bool* optional = 0);

void BindEmpireComponentOffsets();

void RegisterObjectComponentWrappers(ClassBind& cls, bool server, ScriptObjectType* type = 0);
void RegisterEmpireComponentWrappers(ClassBind& cls, bool server);
void RegisterNodeMethodWrappers(ClassBind& cls, bool server, scene::scriptNodeType* type);
void RegisterComponentInterfaces(bool server);
void bindComponentClasses();

void objectWait(Object* obj);
bool getSafeCallWait();
void setSafeCallWait(bool wait);
	
};
