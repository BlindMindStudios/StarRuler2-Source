#include "general_states.h"
#include "str_util.h"
#include "main/logging.h"
#include "compat/misc.h"
#include "util/locked_type.h"
#include "util/lockless_type.h"
#include "obj/object.h"
#include "obj/blueprint.h"
#include <cstring>
#include <vector>
#include <string>
#include <fstream>
#include <unordered_map>
#include <unordered_set>
#include "network.h"
#include "empire.h"
#include "scripts/script_components.h"
#include "scripts/generic_call.h"

StateDefinition errorStateDefinition;
std::unordered_map<std::string, StateDefinition*> definitions;
std::vector<StateDefinition*> stateDefinitions;

template<class T>
void copySimple(void* dest, void* src) {
	if(src)
		*(T*)dest = *(T*)src;
	else
		new(dest) T();
}

template<class T>
void* parseNumber(const std::string& str) {
	return (void*) new T(toNumber<T>(str));
}

template<class T>
void defaultConstruct(void* dest, void* src) {
	new(dest) T();
}

template<class T>
void destruct(void* mem) {
	if(mem)
		((T*)mem)->~T();
}

template<class T>
void defaultWrite(net::Message& msg, void* mem) {
	msg << *(T*)mem;
}

template<class T>
void defaultRead(net::Message& msg, void* mem) {
	msg >> *(T*)mem;
}

//In bind_network.cpp
namespace scripts {
	extern net::Message& readObjectScr(net::Message& msg, Object** obj);
	extern net::Message& writeObjectScr(net::Message& msg, Object* obj);
	extern net::Message& readEmpire(net::Message& msg, Empire** emp);
	extern net::Message& writeEmpire(net::Message& msg, Empire* emp);
};

std::unordered_map<std::string, StateValueDefinition> stateValueTypes;

void resetStateValueTypes() {
	stateValueTypes.clear();

	stateValueTypes["int"].setup(sizeof(int), "int",
		copySimple<int>,
		parseNumber<int>,
		nullptr,
		defaultWrite<int>,
		defaultRead<int>,
		[](asIScriptGeneric* f, void* mem) {
			if(mem)
				f->SetReturnDWord(*(asDWORD*)mem);
			else
				f->SetReturnDWord((asDWORD)0);
		});

	stateValueTypes["uint"].setup(sizeof(unsigned), "uint",
		copySimple<unsigned>,
		parseNumber<unsigned>,
		nullptr,
		defaultWrite<unsigned>,
		defaultRead<unsigned>,
		[](asIScriptGeneric* f, void* mem) {
			if(mem)
				f->SetReturnDWord(*(asDWORD*)mem);
			else
				f->SetReturnDWord((asDWORD)0);
		});

	stateValueTypes["double"].setup(sizeof(double), "double",
		copySimple<double>,
		parseNumber<double>,
		nullptr,
		defaultWrite<double>,
		defaultRead<double>,
		[](asIScriptGeneric* f, void* mem) {
			if(mem)
				f->SetReturnDouble(*(double*)mem);
			else
				f->SetReturnDouble((double)0.0);
		});

	stateValueTypes["float"].setup(sizeof(double), "float",
		copySimple<float>,
		parseNumber<float>,
		nullptr,
		defaultWrite<float>,
		defaultRead<float>,
		[](asIScriptGeneric* f, void* mem) {
			if(mem)
				f->SetReturnDouble(*(float*)mem);
			else
				f->SetReturnDouble((float)0.0);
		});

	stateValueTypes["bool"].setup(sizeof(bool), "bool",
		copySimple<bool>,
		[](const std::string& str) -> void* {
			return new bool(toBool(str));
		},
		nullptr, defaultWrite<bool>, defaultRead<bool>,
		[&](asIScriptGeneric* f, void* mem) {
			if(mem)
				f->SetReturnByte(*(bool*)mem);
			else
				f->SetReturnByte(false);
		});

	stateValueTypes["locked_int"].setup(sizeof(LocklessInt), "locked_int",
		[](void* dest, void* src) {
			if(src)
				new(dest) LocklessInt(*(LocklessInt*)src);
			else
				new(dest) LocklessInt();
		},
		[](const std::string& str) -> void* {
			return new LocklessInt(toNumber<int>(str));
		},
		[](void* memory) {
			((LocklessInt*)memory)->~LocklessInt();
		}, 
		[](net::Message& msg, void* mem) {
			msg << ((LocklessInt*)mem)->value;
		},
		[](net::Message& msg, void* mem) {
			msg >> ((LocklessInt*)mem)->value;
		},
		[](asIScriptGeneric* f, void* mem) {
			f->SetReturnObject(mem);
		});

	stateValueTypes["locked_double"].setup(sizeof(LocklessDouble), "locked_double",
		[](void* dest, void* src) {
			if(src)
				new(dest) LocklessDouble(*(LocklessDouble*)src);
			else
				new(dest) LocklessDouble();
		},
		[](const std::string& str) -> void* {
			return new LocklessDouble(toNumber<double>(str));
		},
		[](void* memory) {
			((LocklessDouble*)memory)->~LocklessDouble();
		}, 
		[](net::Message& msg, void* mem) {
			msg << ((LocklessDouble*)mem)->value;
		},
		[](net::Message& msg, void* mem) {
			msg >> ((LocklessDouble*)mem)->value;
		},
		[](asIScriptGeneric* f, void* mem) {
			f->SetReturnObject(mem);
		});

	//TODO: Support default initialization
	stateValueTypes["vec3d"].setup(sizeof(vec3d), "vec3d",
		copySimple<vec3d>,
		nullptr);

	stateValueTypes["quaterniond"].setup(sizeof(quaterniond), "quaterniond",
		copySimple<quaterniond>,
		nullptr);

	stateValueTypes["string"].setup(sizeof(std::string), "string",
		[](void* dest, void* src) {
			if(src)
				new(dest) std::string(*(std::string*)src);
			else
				new(dest) std::string();
		},
		[](const std::string& str) -> void* {
			return new std::string(str);
		},
		[](void* mem) {
			((std::string*)mem)->~basic_string();
		} );

	stateValueTypes["Empire"].setup(sizeof(Empire*), "Empire@",
		copySimple<Empire*>,
		nullptr,
		nullptr,
		[](net::Message& msg, void* mem) {
			scripts::writeEmpire(msg, *(Empire**)mem);
		},
		[](net::Message& msg, void* mem) {
			scripts::readEmpire(msg, (Empire**)mem);
		},
		[](asIScriptGeneric* f, void* mem) {
			if(mem) {
				Empire* emp = *(Empire**)mem;
				f->SetReturnAddress(emp);
			}
			else {
				f->SetReturnAddress(nullptr);
			}
		});

	stateValueTypes["Object$"].setup(sizeof(Object*), "Object@",
		[](void* dest, void* src) {
			Object*& d = *(Object**)dest;
			if(src) {
				Object* s = *(Object**)src;
				if(s)
					s->grab();
				if(d)
					d->drop();
				d = s;
			}
			else {
				if(d)
					d->drop();
				d = 0;
			}
		}, nullptr, //Object@ cannot have a default value
		[](void* mem) {
			Object* obj = *(Object**)mem;
			if(obj)
				obj->drop();
		},
		[](net::Message& msg, void* mem) {
			scripts::writeObjectScr(msg, *(Object**)mem);
		},
		[](net::Message& msg, void* mem) {
			scripts::readObjectScr(msg, (Object**)mem);
		},
		[](asIScriptGeneric* f, void* mem) {
			if(mem) {
				Object* obj = *(Object**)mem;
				if(obj)
					obj->grab();
				f->SetReturnAddress(obj);
			} else {
				f->SetReturnAddress(nullptr);
			}
		},
		[](void* mem) {
			Object* obj = *(Object**)mem;
			if(obj) {
				obj->drop();
				*(void**)mem = nullptr;
			}
		});

	stateValueTypes["Object"].setup(sizeof(LockedHandle<Object>), "Object@",
		[](void* dest, void* src) {
			if(src)
				new(dest) LockedHandle<Object>(*(LockedHandle<Object>*)src);
			else
				new(dest) LockedHandle<Object>();
		}, nullptr, //Object@ cannot have a default value
		[](void* mem) {
			((LockedHandle<Object>*)mem)->~LockedHandle();
		},
		[](net::Message& msg, void* mem) {
			Object* obj = ((LockedHandle<Object>*)mem)->get();
			scripts::writeObjectScr(msg, obj);
			if(obj)
				obj->drop();
		},
		[](net::Message& msg, void* mem) {
			Object* obj = nullptr;
			scripts::readObjectScr(msg, &obj);
			((LockedHandle<Object>*)mem)->set(obj);
			if(obj)
				obj->drop();
		},
		[](asIScriptGeneric* f, void* mem) {
			Object* obj = ((LockedHandle<Object>*)mem)->get();
			f->SetReturnAddress(obj);
		},
		[](void* mem) {
			((LockedHandle<Object>*)mem)->set(nullptr);
		},
		[](asIScriptGeneric* f, void* mem) {
			Object* obj = (Object*)f->GetArgAddress(0);
			((LockedHandle<Object>*)mem)->set(obj);
		});
	stateValueTypes["Object"].returnType = "Object@";

	stateValueTypes["Blueprint"].setup(sizeof(Blueprint), "Blueprint",
		defaultConstruct<Blueprint>,
		nullptr,
		destruct<Blueprint>,
		nullptr, nullptr,
		[](asIScriptGeneric* f, void* mem) {
			f->SetReturnAddress(mem);
		}, [](void* mem) {
			Blueprint* bp = (Blueprint*)mem;
			if(bp)
				bp->preClear();
		});
	stateValueTypes["Blueprint"].returnType = "Blueprint@";
}

void StateValueDefinition::setup(unsigned Size, std::string Type,
	decltype(init) Init, decltype(parser) Parse, decltype(clear) Clear,
	decltype(writeSync) Write, decltype(readSync) Read, decltype(returnFunc) Return,
	decltype(clearRefs) ClearRefs, decltype(paramSetFunc) ParamSet)
{
	size = Size; type = Type;
	init = Init; parser = Parse;
	clear = Clear;
	writeSync = Write;
	readSync = Read;
	returnFunc = Return;
	clearRefs = ClearRefs;
	paramSetFunc = ParamSet;

	//Align to the size of the largest primitve that could fit into the type
	if(size >= sizeof(void*))
		alignment = sizeof(void*);
	else if(size >= 4)
		alignment = 4;
	else if(size >= 2)
		alignment = 2;
	else
		alignment = 1;
}

void* StateValueDefinition::parse(const std::string& str) const {
	if(parser)
		return parser(str);
	else
		return 0;
}

void StateValueDefinition::alloc(void* memory, void* arg) const {
	memset(memory, 0, size);
	if(init)
		init(memory, arg);
}

void StateValueDefinition::free(void* memory) const {
	if(clear)
		clear(memory);
}

void StateValueDefinition::preClear(void* memory) const {
	if(clearRefs)
		clearRefs(memory);
}
	
bool StateValueDefinition::syncable() const {
	return writeSync != 0 && readSync != 0;
}

bool StateValueDefinition::returnable() const {
	return returnFunc != 0;
}

void StateValueDefinition::syncWrite(net::Message& file, void* memory) const {
	if(writeSync)
		writeSync(file, memory);
}

void StateValueDefinition::syncRead(net::Message& file, void* memory) const {
	if(readSync)
		readSync(file, memory);
}

void StateValueDefinition::setReturn(asIScriptGeneric* gen, void* memory) const {
	if(returnFunc)
		returnFunc(gen, memory);
}

bool StateValueDefinition::isParam() const {
	return (bool)paramSetFunc;
}

void StateValueDefinition::setFromParam(asIScriptGeneric* gen, void* memory) const {
	if(paramSetFunc)
		paramSetFunc(gen, memory);
}

const StateValueDefinition* getStateValueType(const std::string& type) {
	auto iter = stateValueTypes.find(type);
	if(iter != stateValueTypes.end())
		return &iter->second;

	return 0;
}

void clearStateDefinitions() {
	foreach(it, definitions)
		delete it->second;
	definitions.clear();
	stateDefinitions.clear();
}

void loadStateDefinitions(const std::string& filename, const std::string& sharedBase) {
	StateDefinition* def = nullptr;
	std::unordered_set<std::string> used_names;

	scripts::MethodFlags flags;
	flags.restricted = true;

	auto finishDefinition = [&def,&used_names,&flags]() {
		if(def == nullptr)
			return;
		definitions[def->name] = def;
		stateDefinitions.push_back(def);

		StateDefinition* type = def;
		def->asVar.setup(def->totalDataSize, def->name.c_str(), 
			[type](void* dest,void* src) {
				if(src)
					type->copy(dest, src);
				else
					type->prepare(dest);
			},
			nullptr,
			[type](void* mem) {
				type->unprepare(mem);
			});

		used_names.clear();
		def = nullptr;
		flags.reset();
		flags.restricted = true;
	};

	std::ifstream file(filename);
	if(!file.is_open()) {
		error("Could not open '%s'", filename.c_str());
		return;
	}
	skipBOM(file);

	bool inType = false;

	char name[81], dtype[25], value[81];
	char bracket, bracket2;

	while(true) {
		std::string line;
		std::getline(file, line);
		if(file.fail())
			break;

		std::string parse = line.substr(0, line.find("//"));
		if(parse.find_first_not_of(" \t\n\r") == std::string::npos)
			continue;
		
		if(!inType) {
			finishDefinition();

			int args = sscanf(parse.c_str(), " %80s %c %80s %c", name, &bracket, value, &bracket2);
			if((args != 2 && args != 4) ||
				(args == 2 && bracket != '{') ||
				(args == 4 && (bracket != ':' || bracket2 != '{'))) {
				error("Unrecognized line '%s'", line.c_str());
				continue;
			}

			std::string typeName = name;
			auto previous = definitions.find(typeName);
			if(previous != definitions.end()) {
				error("Duplicate type '%s'", name);
				continue;
			}
			
			auto baseType = definitions.find(sharedBase);
			if(baseType == definitions.end()) {
				if(!sharedBase.empty() && sharedBase != name)
					error("Expected definition of base type '%s'", sharedBase.c_str());
				def = new StateDefinition();
			}
			else {
				def = new StateDefinition(*baseType->second);
			}

			if(args == 4)
				def->scriptClass = value;

			used_names.clear();

			def->name = name;
			inType = true;
		}
		else if(def) {
			//Parse flag lines (e.g. restricted:)
			std::string trimmed = trim(parse);
			if(!trimmed.empty() && trimmed.back() == ':') {
				trimmed.back() = ' ';
				flags.reset();
				flags.parse(trimmed);
				continue;
			}

			int args = sscanf(parse.c_str(), " %c", &bracket);
			if(args == 1 && bracket == '}') {
				inType = false;
				continue;
			}

			parse = trimmed;

			//Parse methods
			if(parse.find('(') != std::string::npos) {
				StateDefinition::method method;
				method.flags = flags;
				method.flags.parse(parse);
				method.decl = parse;
				method.wrapped = nullptr;
				def->methods.push_back(method);
				continue;
			}

			bool synced = false;
			if(parse.compare(0, 7, "synced ") == 0) {
				parse = parse.substr(7);
				synced = true;
			}

			bool attribute = false;
			if(parse.compare(0, 10, "attribute ") == 0) {
				parse = parse.substr(10);
				attribute = true;
			}

			args = sscanf(parse.c_str(), " %24s %80s = %80s", dtype, name, value);

			if(args < 2) {
				error("Unrecognized line '%s'", line.c_str());
				continue;
			}

			if(args < 3)
				value[0] = '\0';

			if(used_names.find(name) != used_names.end()) {
				error("Duplicate member '%s'", name);
				continue;
			}

			if(!isIdentifier(name)) {
				error("'%s' is not a valid identifier", name);
				continue;
			}

			StateDefinition::stateDefMember mem;
			mem.name = name;
			mem.defText = value;
			mem.typeName = dtype;
			mem.synced = synced;
			mem.attribute = attribute;
			if(flags.restricted)
				mem.access = SR_Restricted;
			else if(flags.visible)
				mem.access = SR_Visible;
			else
				mem.access = SR_Invisible;
			def->types.push_back(mem);
		}
		else {
			if(parse.find('}') != std::string::npos)
				inType = false;
		}
	}
	
	finishDefinition();
}

void finalizeStateDefinitions() {
	for(auto i = stateDefinitions.begin(), end = stateDefinitions.end(); i != end; ++i) {
		auto& def = **i;

		unsigned offset = 0;

		//Determine data types of all members
		for(auto t = def.types.begin(), tend = def.types.end(); t != tend;) {
			auto& member = *t;

			const StateValueDefinition* valueType = getStateValueType(member.typeName);
			if(valueType == 0 || (member.synced && !valueType->syncable())) {
				if(valueType)
					error("%s error: Type '%s' for member '%s' cannot be synced", def.name.c_str(), member.typeName.c_str(), member.name.c_str());
				else
					error("%s error: Unknown type '%s' for member '%s'", def.name.c_str(), member.typeName.c_str(), member.name.c_str());
				t = def.types.erase(t);
				tend = def.types.end();
				continue;
			}

			member.def = valueType;
			member.defaultValue = valueType->parse(member.defText);
			if(offset & (valueType->alignment - 1)) {
				offset &= ~(unsigned)(valueType->alignment - 1);
				offset += (unsigned)valueType->alignment;
			}
			member.offset = offset;
			offset += valueType->size;

			++t;
		}

		def.totalDataSize = offset;

		//Parse through methods
		unsigned methodIndex = 0;
		for(auto m = def.methods.begin(), mend = def.methods.end(); m != mend; ++m, ++methodIndex) {
			auto& method = *m;
			scripts::GenericCallDesc desc;

			if(method.flags.server || method.flags.shadow)
				desc.parse(method.decl, true, true);
			else
				desc.parse(method.decl, true, false);

			if(!method.flags.local && desc.returnType.type) {
				error("Error: '%s': non-local function cannot return a value.", method.decl.c_str());
				continue;
			}
			else if(desc.returnType == scripts::GT_Custom_Handle) {
				error("Error: '%s': script types cannot be return values.", method.decl.c_str());
				continue;
			}

			scripts::WrappedMethod* wm = new scripts::WrappedMethod();
			wm->fullDeclaration = method.decl;
			wm->index = methodIndex;
			wm->local = method.flags.local;
			wm->server = method.flags.server;
			wm->shadow = method.flags.shadow;
			wm->wrapped = desc;
			wm->restricted = method.flags.restricted;
			wm->async = method.flags.async;
			wm->safe = method.flags.safe;
			wm->relocking = method.flags.relocking;
			wm->isComponentMethod = false;

			if(wm->wrapped.returnsArray) {
				wm->wrapped.returnType.type = scripts::GT_Custom_Handle;
				wm->wrapped.returnType.customName = "DataList";
			}

			wm->desc.append(desc);
			wm->desc.name = desc.name;
			wm->desc.constFunction = false;
			wm->desc.returnType = desc.returnType;
			wm->desc.returnsArray = wm->wrapped.returnsArray;

			method.wrapped = wm;
		}
	}
}

StateDefinition::StateDefinition() : totalDataSize(0), base(0) {}

StateDefinition::StateDefinition(const StateDefinition& other) : types(other.types), totalDataSize(other.totalDataSize), base(&other), methods(other.methods) {
	//TODO: default args are not deleted, so we'll just copy the pointers blindly for now
}

StateDefinition::~StateDefinition() {
	//TODO: default args are not yet deleted, see above
}

void StateDefinition::align(unsigned& offset) {
	unsigned off = offset % sizeof(void*);
	if(off != 0)
		offset += sizeof(void*) - off;
}

void StateDefinition::align(void*& memory) {
	size_t off = (size_t)memory % sizeof(void*);
	if(off != 0)
		memory = (char*)memory + (sizeof(void*) - off);
}

const StateDefinition& getStateDefinition(const std::string& name) {
	auto it = definitions.find(name);
	if(it == definitions.end())
		return errorStateDefinition;
	return *it->second;
}

unsigned StateDefinition::getSize(unsigned atOffset) const {
	unsigned off = atOffset % sizeof(void*);
	if(off == 0)
		return totalDataSize;
	else
		return totalDataSize + (sizeof(void*) - off);
}

void StateDefinition::prepare(void*& memory) const {
	align(memory);

	char* data = (char*)memory;
	for(auto v = types.begin(), end = types.end(); v != end; ++v) {
		auto& type = *v->def;
		type.alloc(data + v->offset, v->defaultValue);
	}

	memory = data + totalDataSize;
}

void StateDefinition::copy(void*& memory, void*& from) const {
	align(memory);
	align(from);

	char* data = (char*)memory, *source = (char*)from;
	for(auto v = types.begin(), end = types.end(); v != end; ++v) {
		auto& type = *v->def;
		type.alloc(data + v->offset, source + v->offset);
	}

	memory = data + totalDataSize;
	from = source + totalDataSize;
}

void StateDefinition::preClear(void*& memory) const {
	align(memory);

	char* data = (char*)memory;
	for(auto v = types.begin(), end = types.end(); v != end; ++v) {
		auto& type = *v->def;
		type.preClear(data + v->offset);
	}

	memory = data + totalDataSize;
}

void StateDefinition::unprepare(void*& memory) const {
	align(memory);

	char* data = (char*)memory;
	for(auto v = types.begin(), end = types.end(); v != end; ++v) {
		auto& type = *v->def;
		type.free(data + v->offset);
	}

	memory = data + totalDataSize;
}

void StateDefinition::syncWrite(net::Message& msg, void* memory) const {
	align(memory);

	char* data = (char*)memory;
	for(auto i = types.begin(), end = types.end(); i != end; ++i) {
		auto& state = *i->def;
		if(i->synced)
			state.syncWrite(msg, data + i->offset);
	}
}

void StateDefinition::syncRead(net::Message& msg, void* memory) const {
	align(memory);

	char* data = (char*)memory;
	for(auto i = types.begin(), end = types.end(); i != end; ++i) {
		auto& state = *i->def;
		if(i->synced)
			state.syncRead(msg, data + i->offset);
	}
}

StateList::StateList() : def(&errorStateDefinition), values(0) {
}

StateList::StateList(const StateDefinition& Def) : def(0), values(0) {
	change(Def);
}

StateList::~StateList() {
	clear();
}

void StateList::change(const StateDefinition& Def) {
	clear();
	def = &Def;
	if(def->totalDataSize == 0)
		return;

	values = new char[def->totalDataSize];
	void* mem = values;
	def->prepare(mem);
}

void StateList::clear() {
	if(values) {
		void* mem = values;
		def->unprepare(mem);
		delete[] values;
		values = 0;
	}

	def = 0;
}

StateList& StateList::operator=(StateList& other) {
	clear();
	def = other.def;
	if(def == 0)
		return *this;

	values = new char[def->totalDataSize];
	void* mem = values, *otherMem = other.values;;
	def->copy(mem, otherMem);
	return *this;
}

unsigned StateList::count() const{
	return (unsigned)def->types.size();
}
