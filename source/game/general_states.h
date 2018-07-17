#pragma once
#include "threads.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <functional>
#include "scripts/script_components.h"

namespace net {
	struct Message;
};

class asIScriptGeneric;
class StateValueDefinition {
	std::function<void(void*,void*)> init;
	std::function<void*(const std::string&)> parser;
	std::function<void(void*)> clear;
	std::function<void(void*)> clearRefs;
	std::function<void(net::Message&,void*)> writeSync;
	std::function<void(net::Message&,void*)> readSync;
	std::function<void(asIScriptGeneric*,void*)> returnFunc;
	std::function<void(asIScriptGeneric*,void*)> paramSetFunc;
public:
	unsigned size;
	size_t alignment;
	std::string type;
	std::string returnType;

	void setup(unsigned Size, std::string Type,
		decltype(init) Init, decltype(parser) Parse,
		decltype(clear) Clear = nullptr,
		decltype(writeSync) Write = nullptr,
		decltype(readSync) Read = nullptr,
		decltype(returnFunc) Return = nullptr,
		decltype(clearRefs) ClearRefs = nullptr,
		decltype(paramSetFunc) ParamSet = nullptr);

	void* parse(const std::string& str) const;
	
	void alloc(void* memory, void* arg) const;

	void preClear(void* memory) const;
	void free(void* memory) const;
	
	bool syncable() const;
	bool returnable() const;

	void syncWrite(net::Message& file, void* memory) const;

	void syncRead(net::Message& file, void* memory) const;

	void setReturn(asIScriptGeneric* gen, void* memory) const;

	bool isParam() const;
	void setFromParam(asIScriptGeneric* gen, void* memory) const;
};

extern std::unordered_map<std::string, StateValueDefinition> stateValueTypes;
const StateValueDefinition* getStateValueType(const std::string& type);
void resetStateValueTypes();

enum StateRestriction {
	SR_Visible,
	SR_Restricted,
	SR_Invisible,
};

struct StateDefinition {
public:
	struct stateDefMember {
		std::string name, typeName, defText;
		const StateValueDefinition* def;
		void* defaultValue;
		bool synced;
		bool attribute;
		StateRestriction access;
		unsigned offset;

		stateDefMember() : def(0), defaultValue(0),
			synced(false), attribute(false), access(SR_Restricted), offset(0) {
		}
	};

	struct method {
		std::string decl;
		scripts::MethodFlags flags;
		scripts::WrappedMethod* wrapped;
	};

	const StateDefinition* base;
	static void align(void*& mem);
	std::string name;

	std::string scriptClass;

	//Relatively indexes
	std::vector<stateDefMember> types;
	unsigned totalDataSize;

	std::vector<method> methods;

	StateValueDefinition asVar;

	unsigned getSize(unsigned atOffset) const;
	static void align(unsigned& offset);
	
	void prepare(void*& memory) const;
	void copy(void*& memory, void*& from) const;
	void preClear(void*& memory) const;
	void unprepare(void*& memory) const;

	void syncWrite(net::Message& msg, void* memory) const;
	void syncRead(net::Message& msg, void* memory) const;

	StateDefinition();
	StateDefinition(const StateDefinition& other);
	~StateDefinition();
};

struct StateList {
	const StateDefinition* def;
	char* values;

	StateList& operator=(StateList& other);
	void change(const StateDefinition& def);
	void clear();
	unsigned count() const;

	StateList();
	StateList(const StateDefinition& def);
	~StateList();
};

void loadStateDefinitions(const std::string& filename, const std::string& sharedBase = "");
void finalizeStateDefinitions();
const StateDefinition& getStateDefinition(const std::string& name);
void clearStateDefinitions();

extern StateDefinition errorStateDefinition;
extern std::vector<StateDefinition*> stateDefinitions;
