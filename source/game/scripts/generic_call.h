#pragma once
#include "scripts/manager.h"
#include "script_bind.h"
#include "vec3.h"
#include "vec2.h"
#include "quaternion.h"
#include <string>
#include <stdint.h>
#include <vector>
#include <functional>

#ifndef MAX_GENERIC_ARGUMENTS
#define MAX_GENERIC_ARGUMENTS 16
#endif

class Object;
class Empire;
class Design;
struct Player;
struct ScriptObjectType;

namespace net {
	struct Message;
};

namespace scene {
	class Node;
};

namespace scripts {

struct ArgumentDesc;
struct GenericValue;

typedef std::function<void(net::Message&,ArgumentDesc&,GenericValue&)> customRW;
typedef std::function<asIScriptObject*(ArgumentDesc&,asIScriptObject*)> customHandle;

struct GenericValue {
	union {
		int integer;
		unsigned uint;
		float sfloat;
		double dfloat;
		bool boolean;
		int64_t longint;
		std::string* str;

		Object* obj;
		Empire* emp;
		scene::Node* node;
		Design* design;
		Player* player;
		asIScriptObject* script;
		net::Message* msg;
		vec3d* v3;
		vec2i* v2;
		quaterniond* quat;
		void* ptr;
	};
	bool managed;
	volatile bool asyncReturned;

	template<class T>
	T& get() {
		return *(T*)this;
	}

	GenericValue() :
		ptr(nullptr), managed(false), asyncReturned(false) {}
};

void trivialCopy(GenericValue& to, GenericValue& from);

struct GenericType {
	std::string name;
	bool wouldConst;

	std::function<void(GenericValue&,unsigned,asIScriptGeneric*)> get;
	std::function<void(GenericValue&,GenericValue&)> copy;
	std::function<void(GenericValue&,asIScriptGeneric*)> ret;
	std::function<void(Call&,GenericValue&)> call;
	std::function<void(Call&,ArgumentDesc&,GenericValue&,customHandle custom)> push;
	std::function<void(net::Message&,ArgumentDesc&,GenericValue&,customRW custom)> write;
	std::function<bool(net::Message&,ArgumentDesc&,GenericValue&,customRW custom)> read;
	std::function<void(GenericValue&)> destruct;

	GenericType() : wouldConst(false) {}

	template<class T>
	GenericType* setup(std::string Name, decltype(get) Get, decltype(ret) Ret, decltype(copy) Copy = trivialCopy,
			    decltype(call) Cl = nullptr, decltype(push) Push = nullptr,
				decltype(write) Write = nullptr, decltype(read) Read = nullptr,
				decltype(destruct) Destruct = nullptr, bool WouldConst = false) {
		name = Name;
		get = Get;
		ret = Ret;
		copy = Copy;

		if(Cl == nullptr) {
			call = [](Call& cl, GenericValue& val) {
				cl.call(val.get<T>());
			};
		}
		else {
			call = Cl;
		}

		if(Push == nullptr) {
			push = [](Call& cl, ArgumentDesc& desc, GenericValue& val, customHandle custom) {
				cl.push(val.get<T>());
			};
		}
		else {
			push = Push;
		}

		if(Write == nullptr) {
			write = [](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) {
				msg << val.get<T>();
			};
		}
		else {
			write = Write;
		}

		if(Read == nullptr) {
			read = [](net::Message& msg, ArgumentDesc& desc, GenericValue& val, customRW custom) -> bool {
				msg >> val.get<T>();
				return true;
			};
		}
		else {
			read = Read;
		}

		destruct = Destruct;
		wouldConst = WouldConst;
		return this;
	}
};

extern GenericType* GT_uint;
extern GenericType* GT_Custom_Handle;
extern GenericType* GT_Player_Ref;
extern GenericType* GT_Object_Ref;
extern GenericType* GT_Empire_Ref;
extern GenericType* GT_Node_Ref;

const std::string& getTypeString(GenericType* type);
GenericType* getStringType(const std::string& type);

struct ArgumentDesc {
	GenericType* type;
	std::string argName;
	std::string defaultValue;
	std::string customName;
	void* customType;
	void* customRead;
	void* customWrite;
	bool isConst;

	ArgumentDesc()
		: type(nullptr), customType(nullptr), customRead(nullptr), customWrite(nullptr), isConst(false) {
	}

	ArgumentDesc(GenericType* Type)
		: type(Type), customType(nullptr), customRead(nullptr), customWrite(nullptr), isConst(false) {
	}

	ArgumentDesc(GenericType* Type, bool IsConst)
		: type(Type), customType(nullptr), customRead(nullptr), customWrite(nullptr), isConst(IsConst) {
	}

	ArgumentDesc(std::string CustomName, bool IsConst)
		: type(GT_Custom_Handle), customName(CustomName), customType(nullptr), customRead(nullptr),
			customWrite(nullptr), isConst(IsConst) {
	}

	void operator=(const ArgumentDesc& other) {
		type = other.type;
		defaultValue = other.defaultValue;
		argName = other.argName;
		customName = other.customName;
		customType = other.customType;
		customRead = other.customRead;
		customWrite = other.customWrite;
		isConst = other.isConst;
	}

	void operator=(GenericType* Type) {
		type = Type;
	}

	operator GenericType*() {
		return type;
	}

	std::string toString() {
		if(!type)
			return "void";

		std::string out;
		if(isConst)
			out += "const ";

		if(type == GT_Custom_Handle)
			out += customName+"@";
		else
			out += getTypeString(type);

		return out;
	}
};

//Generic calls follow descriptors that state
//which arguments they have and what their return value is
class GenericCallDesc {
public:
	std::string name;
	ArgumentDesc returnType;
	ArgumentDesc arguments[MAX_GENERIC_ARGUMENTS];
	bool returnsArray;
	bool constFunction;
	unsigned argCount;

	GenericCallDesc();
	GenericCallDesc(std::string declaration, bool hasReturnType = true, bool customRefs = false);

	void parse(std::string declaration, bool hasReturnType = true, bool customRefs = false);

	void append(GenericType* argument);
	void append(GenericCallDesc& desc);
	void append(std::vector<std::string>& arguments, bool customRefs = false);
	void prepend(ArgumentDesc argument);

	GenericValue call(Call& cl);

	std::string declaration(bool addReturnType = true, bool forceConst = false, unsigned start = 0);
};

//Call data holds the values of all the arguments for easy passing around
class GenericCallData {
public:
	GenericCallDesc& desc;
	GenericValue values[MAX_GENERIC_ARGUMENTS];
	void* object;

	GenericCallData(GenericCallDesc& desc);
	GenericCallData(GenericCallData& data);
	~GenericCallData();

	//Generic call data can be sent over the network,
	//the function descriptor should be sent manually though,
	//depending on what system is sending it.
	void write(net::Message& msg, unsigned startAt = 0, customRW custom = nullptr);
	bool read(net::Message& msg, unsigned startAt = 0, customRW custom = nullptr);

	//Read all the arguments from an angelscript generic
	//call, and stash them here
	GenericCallData(GenericCallDesc& desc, asIScriptGeneric* gen);

	//Push all the arguments onto a script call to angelscript
	void pushTo(Call& call, int startAt = 0, customHandle custom = nullptr);
	GenericValue call(Call& cl);
};

//Retrieve the function matching the call desc from this manager
asIScriptFunction* getFunction(Manager* manager, const char* module, GenericCallDesc& desc, bool forceConst = false);

//Bind a generically specified function to a callback,
//the callback receives the argument data and the bind id
//returned by the call to bindGeneric so it can identify which
//generic call was received
typedef GenericValue (*GenericHandler)(void* arg, GenericCallData& data);
int bindGeneric(GenericCallDesc& desc, GenericHandler handler, void* arg = nullptr, bool acceptConst = false);
int bindGeneric(ClassBind& cls, GenericCallDesc& desc, GenericHandler handler, void* arg = nullptr, bool forceConst = false);
int bindGeneric(ClassBind& cls, const std::string& decl, GenericCallDesc& desc, GenericHandler handler, void* arg = 0);
void clearGenericBinds();

void initGenericTypes();

void bindGenericObjectType(ScriptObjectType* type, std::string name);

};
