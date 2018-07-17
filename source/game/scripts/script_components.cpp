#include "script_components.h"
#include "main/references.h"
#include "main/logging.h"
#include "compat/misc.h"
#include "network.h"
#include "network/network_manager.h"
#include "str_util.h"
#include "empire.h"
#include "util/save_file.h"
#include "obj/lock.h"
#include "obj/object.h"
#include "scene/scripted_node.h"
#include "general_states.h"
#include "context_cache.h"
#include <unordered_map>
#include <assert.h>

extern void writeObject(net::Message& msg, Object* obj, bool includeType = true);
extern Object* readObject(net::Message& msg, bool create, int knownTypeID = -1);

//#define LOG_SLOW_ASYNC_CALLS
//#define PROFILE_ASYNC_CALLS

#ifdef PROFILE_ASYNC_CALLS
threads::atomic_int callCount[4];

void logAsyncLoad() {
	int counts[] = { callCount[0].get_basic(), callCount[1].get_basic(), callCount[2].get_basic(), callCount[3].get_basic() };
	float total = float(counts[0] + counts[1] + counts[2] + counts[3]) / 100.f;

	print("  0us- 10us: %d (%.0f%%)\n 10us-100us: %d (%.0f%%)\n100us-  1ms: %d (%.0f%%)\n  1ms-  inf: %d (%.0f%%)",
		counts[0], float(counts[0]) / total,
		counts[1], float(counts[1]) / total,
		counts[2], float(counts[2]) / total,
		counts[3], float(counts[3]) / total );
}
#else
void logAsyncLoad() {
	print("Async profiling disabled.");
}
#endif

namespace scripts {

void logException();

extern Player SERVER_PLAYER;
std::vector<Component*> components;
std::unordered_map<std::string, Component*> componentNames;
std::unordered_map<const StateValueDefinition*, std::pair<Component*, bool>> componentDefs;

Threaded(bool) RELOCK_SAFE_METHODS = false;
Threaded(bool) PREVENT_RELOCKING = false;

unsigned getComponentCount() {
	return (unsigned)components.size();
}

Component* getComponent(unsigned index) {
	if(index >= components.size())
		return 0;
	return components[index];
}

Component* getComponent(const std::string& name) {
	auto it = componentNames.find(name);
	if(it != componentNames.end())
		return it->second;
	return 0;
}

Component* getComponent(const StateValueDefinition* def, bool* optional) {
	auto it = componentDefs.find(def);
	if(it != componentDefs.end()) {
		if(optional)
			*optional = it->second.second;
		return it->second.first;
	}
	if(optional)
		*optional = false;
	return 0;
}

Component::~Component() {
	for(auto it = methods.begin(), end = methods.end(); it != end; ++it)
		delete *it;
}

void clearComponents() {
	for(auto it = components.begin(), end = components.end(); it != end; ++it)
		delete *it;
	components.clear();
	componentNames.clear();
	componentDefs.clear();
}

void MethodFlags::parse(std::string& flags) {
	while(true) {
		if(flags.compare(0, 11, "restricted ") == 0) {
			restricted = true;
			flags = flags.substr(11);
		}
		else if(flags.compare(0, 7, "remote ") == 0) {
			local = false;
			server = false;
			shadow = false;
			flags = flags.substr(7);
		}
		else if(flags.compare(0, 6, "local ") == 0) {
			local = true;
			server = false;
			shadow = false;
			flags = flags.substr(6);
		}
		else if(flags.compare(0, 7, "server ") == 0) {
			server = true;
			local = true;
			shadow = false;
			flags = flags.substr(7);
		}
		else if(flags.compare(0, 7, "shadow ") == 0) {
			server = false;
			shadow = true;
			local = true;
			flags = flags.substr(7);
		}
		else if(flags.compare(0, 6, "async ") == 0) {
			async = true;
			flags = flags.substr(6);
		}
		else if(flags.compare(0, 5, "safe ") == 0) {
			safe = true;
			flags = flags.substr(5);
		}
		else if(flags.compare(0, 10, "relocking ") == 0) {
			relocking = true;
			flags = flags.substr(10);
		}
		else if(flags.compare(0, 8, "visible ") == 0) {
			visible = true;
			flags = flags.substr(8);
		}
		else if(flags.compare(0, 10, "invisible ") == 0) {
			visible = false;
			flags = flags.substr(10);
		}
		else {
			break;
		}
	}
}

void loadComponents(const std::string& filename) {
	std::ifstream file(filename);
	if(!file.is_open()) {
		error("Could not open '%s'", filename.c_str());
		return;
	}
	skipBOM(file);

	Component* comp = 0;

	auto finishDefinition = [&]() {
		if(!comp)
			return;

		componentNames[comp->name] = comp;
		components.push_back(comp);
		comp = 0;
	};

	bool inType = false;

	char name[80], value[80];
	char bracket;

	MethodFlags flags;
#ifdef DOCUMENT_API
	WrappedMethod* prevMethod = 0;
#endif

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

			int args = sscanf(parse.c_str(), " %79s : %79s {", name, value);
			if(args != 2) {
				error("Unrecognized line '%s'", line.c_str());
				continue;
			}

			std::string typeName = name;
			std::string containing = "Object";

			auto dot = typeName.find('.');
			if(dot != std::string::npos) {
				containing = typeName.substr(0, dot);
				typeName = typeName.substr(dot + 1);
			}

			if(typeName.empty() || containing.empty()) {
				error("Component name specifier '%s' invalid.", name);
				continue;
			}

			if(componentNames.find(typeName) != componentNames.end()) {
				error("Duplicate type '%s'", name);
				continue;
			}

			comp = new Component();
			comp->id = components.size();
			comp->name = typeName;
			comp->typeDecl = value;
			comp->containing = containing;

			if(containing == "Empire")
				comp->containingType = GT_Empire_Ref;
			else
				comp->containingType = GT_Object_Ref;

			inType = true;
		}
		else if(comp) {
			int args = sscanf(parse.c_str(), " %c", &bracket);
			if(args == 1 && bracket == '}') {
				inType = false;
				continue;
			}

			parse = trim(parse);

			if(!parse.empty()) {
				if(parse[parse.size() - 1] == ':') {
					parse[parse.size() - 1] = ' ';

					flags.reset();
					flags.parse(parse);
					continue;
				}

				if(parse[0] == '@') {
#ifdef DOCUMENT_API
					if(prevMethod) {
						if(parse.compare(0, 5, "@doc ") == 0) {
							if(prevMethod->doc_desc.empty()) {
								prevMethod->doc_desc = parse.substr(5);
							}
							else {
								prevMethod->doc_desc += '\n';
								prevMethod->doc_desc += parse.substr(5);
							}
						}
						else if(parse.compare(0, 5, "@arg ") == 0) {
							prevMethod->doc_args.push_back(parse.substr(5));
						}
						else if(parse.compare(0, 8, "@return ") == 0) {
							prevMethod->doc_return = parse.substr(8);
						}
					}
#endif
					continue;
				}
			}

			//Parse declaration
			GenericCallDesc desc;
			MethodFlags curFlags = flags;
			curFlags.parse(parse);

			if(curFlags.server || curFlags.shadow)
				desc.parse(parse, true, true);
			else
				desc.parse(parse, true, false);

			if(!curFlags.local && desc.returnType.type) {
				error("Error: '%s': non-local function cannot return a value.", parse.c_str());
				continue;
			}
			else if(desc.returnType == GT_Custom_Handle) {
				error("Error: '%s': script types cannot be return values.", parse.c_str());
				continue;
			}

			//Create method desc
			WrappedMethod* m = new WrappedMethod();
			m->fullDeclaration = parse;
			m->index = comp->methods.size();
			m->compId = comp->id;
			m->local = curFlags.local;
			m->server = curFlags.server;
			m->shadow = curFlags.shadow;
			m->wrapped = desc;
			m->restricted = curFlags.restricted;
			m->async = curFlags.async;
			m->safe = curFlags.safe;
			m->relocking = curFlags.relocking;
			m->isComponentMethod = true;

			if(m->wrapped.returnsArray) {
				m->wrapped.returnType.type = GT_Custom_Handle;
				m->wrapped.returnType.customName = "DataList";
			}

			m->desc.append(desc);
			m->desc.name = desc.name;
			m->desc.constFunction = false;
			m->desc.returnType = desc.returnType;
			m->desc.returnsArray = m->wrapped.returnsArray;

			comp->methods.push_back(m);
#ifdef DOCUMENT_API
			prevMethod = m;
#endif
		}
		else {
			if(parse.find('}') != std::string::npos)
				inType = false;
		}
	}

	finishDefinition();
}

const std::string nullstr("null");
void addComponentStateValueTypes() {
	//Setup value types
	foreach(it, components) {
		Component& comp = **it;

		std::string name = "Component_";
		name += comp.name;
		name += "@";

		stateValueTypes[comp.name.c_str()].setup(
			sizeof(asIScriptObject*), name,

			//Always create a new component
			[&comp](void* m, void* s) {
				asIScriptObject** dest = (asIScriptObject**)m;
				if(comp.type) {
					asIScriptFunction* func = comp.type->GetFactoryByIndex(0);
					Call cl = devices.scripts.server->call(func);
					cl.call(*dest);

					if(*dest)
						(*dest)->AddRef();
				}
				else {
					*dest = 0;
				}
			},

			//No initialization
			nullptr,

			//Release reference on destruct
			[](void* mem) {
				asIScriptObject* obj = *(asIScriptObject**)mem;
				if(obj)
					obj->Release();
			},

			nullptr, nullptr, nullptr,

			[](void* mem) {
				asIScriptObject* obj = *(asIScriptObject**)mem;
				if(obj) {
					obj->Release();
					*(void**)mem = nullptr;
				}
			}
		);

		std::string optname = comp.name + "@";
		stateValueTypes[optname.c_str()].setup(
			sizeof(asIScriptObject*), name,

			//Always create a new component if not
			//null-initialized
			[&comp](void* m, void* s) {
				asIScriptObject** dest = (asIScriptObject**)m;
				if(s) {
					asIScriptFunction* func = comp.type->GetFactoryByIndex(0);
					Call cl = devices.scripts.server->call(func);
					cl.call(*dest);

					if(*dest)
						(*dest)->AddRef();
				}
				else {
					*dest = 0;
				}
			},

			//Check for initialization
			[](const std::string& str) -> void* {
				if(streq_nocase(str, nullstr))
					return 0;
				return (void*)1;
			},

			//Release reference on destruct
			[](void* mem) {
				asIScriptObject* obj = *(asIScriptObject**)mem;
				if(obj)
					obj->Release();
			},

			nullptr, nullptr, nullptr,

			[](void* mem) {
				asIScriptObject* obj = *(asIScriptObject**)mem;
				if(obj) {
					obj->Release();
					*(void**)mem = nullptr;
				}
			}
		);
	}

	//Get pointers
	foreach(it, components) {
		Component& comp = **it;

		comp.def = getStateValueType(comp.name);
		comp.optDef = getStateValueType(comp.name+"@");
		componentDefs[comp.def] = std::pair<Component*,bool>(&comp, false);
		componentDefs[comp.optDef] = std::pair<Component*,bool>(&comp, true);
	}
}

class AsyncScriptCall : public ObjectMessage {
	WrappedMethod* method;
	GenericCallData args;
	size_t compOffset;
	bool fromGUI;
	GenericValue* retValue;

public:

#ifdef LOG_SLOW_ASYNC_CALLS
	double* retTime;
#endif

	AsyncScriptCall(WrappedMethod* Method, GenericCallData& arguments, size_t offset,
					bool FromGUI, GenericValue* pReturn = 0
#ifdef LOG_SLOW_ASYNC_CALLS
					, double* RetTime = 0
#endif
					)
		: ObjectMessage((Object*)arguments.object), method(Method), args(arguments),
			compOffset(offset), fromGUI(FromGUI), retValue(pReturn)
	{
		object->grab();
#ifdef LOG_SLOW_ASYNC_CALLS
		retTime = RetTime;
#endif
	}

	void process() {
		asIScriptObject* script;
		if(method->isComponentMethod)
			script = *(asIScriptObject**)((size_t)object + compOffset);
		else
			script = object->script;
		if(!script || (fromGUI && method->restricted && !devices.network->getCurrentPlayer().controls(object->owner))) {
			if(retValue) {
				retValue->asyncReturned = true;

#ifdef LOG_SLOW_ASYNC_CALLS
				if(retTime) *retTime = devices.driver->getAccurateTime();
#endif
			}
			return;
		}

		if(!object->isValid())
			return;

		Call cl = devices.scripts.server->call(method->func);
		cl.setObject(script);
		if(method->passPlayer) {
			if(fromGUI)
				cl.push((void*)&devices.network->getCurrentPlayer());
			else
				cl.push((void*)&SERVER_PLAYER);
		}
		if(method->passContaining)
			cl.push((void*)object);
		args.pushTo(cl);

		//Save relocking values
		bool prevPrevent = PREVENT_RELOCKING;
		bool prevSafe = RELOCK_SAFE_METHODS;

		PREVENT_RELOCKING = !method->relocking;
		RELOCK_SAFE_METHODS = false;

		if(retValue) {
			GenericValue ret = method->desc.call(cl);
			auto* type = method->desc.returnType.type;
			if(type)
				type->copy(*retValue, ret);
			else
				*retValue = ret;

#ifdef LOG_SLOW_ASYNC_CALLS
			if(retTime) *retTime = devices.driver->getAccurateTime();
#endif
			retValue->asyncReturned = true;
		}
		else {
			method->desc.call(cl);
		}

		//Restore relocking values
		PREVENT_RELOCKING = prevPrevent;
		RELOCK_SAFE_METHODS = prevSafe;
	}

	~AsyncScriptCall() {
		object->drop();
	}
};

/* Components registered to objects */
static GenericValue wrapperFunc(void* arg, GenericCallData& args) {
	GenericValue retVal;
	WrappedMethod* method = (WrappedMethod*)arg;

	Object* obj = (Object*)args.object;
	asIScriptObject* script;
	size_t offset;

	if(!obj->isValid())
		return retVal;

	if(method->isComponentMethod) {
		offset = obj->type->componentOffsets[method->compId];

		if(offset == 0) {
			throwException(format("Object of type '$1' does not have component '$2'.",
					obj->type->name, getComponent(method->compId)->name).c_str());
			return retVal;
		}

		script = *(asIScriptObject**)((size_t)obj + offset);
	}
	else {
		script = obj->script;
		offset = 0;
	}

	if(!script)
		return retVal;

	if(!method->local && devices.network->isClient) {
		net::Message msg(MT_Object_Component_Call, net::MF_Managed);
		writeObject(msg, obj);
		msg.writeBit(method->isComponentMethod);
		msg.writeAlign();
		if(method->isComponentMethod)
			msg.writeSmall(method->compId);
		msg.writeSmall(method->index);
		args.write(msg);

		devices.network->send(msg);
		obj->focus();
	}

	if(method->func) {
		bool isGUI = scripts::getActiveManager() != devices.scripts.server;
		bool hasReturn = method->desc.returnsArray || method->desc.returnType.type;
		LockGroup* activeGroup = getActiveLockGroup();

		//Check relocking requirement
		if(PREVENT_RELOCKING) {
			if(method->relocking && (!method->async || hasReturn)) {
				throwException("Cannot call relocking method from non-relocking outer function.");
				return retVal;
			}
			if(hasReturn && (!method->safe || RELOCK_SAFE_METHODS) && activeGroup && obj != getActiveObject()) {
				throwException("Cannot call methods with return data on different objects unless the outer function is declared relocking.");
				return retVal;
			}
		}

		bool initialized = obj->isInitialized();

		if((obj->isLocked() || (method->safe && !RELOCK_SAFE_METHODS)) && !method->async && initialized) {
			Call cl = devices.scripts.server->call(method->func);
			cl.setObject(script);
			if(method->passPlayer) {
				if(isGUI)
					cl.push((void*)&devices.network->getCurrentPlayer());
				else
					cl.push((void*)&SERVER_PLAYER);
			}
			if(method->passContaining)
				cl.push((void*)obj);
			args.pushTo(cl);
		
			//Check restriction
			if(method->restricted && isGUI) {
				if(!devices.network->getCurrentPlayer().controls(obj->owner)) {
					info(format("Cannot call method '$1' on unowned objects.", method->wrapped.name).c_str());
					return retVal;
				}
			}

			//Save relocking values
			bool prevPrevent = PREVENT_RELOCKING;
			bool prevSafe = RELOCK_SAFE_METHODS;
			Object* prevObj = getActiveObject();

			setActiveObject(obj);
			PREVENT_RELOCKING = !method->relocking;
			RELOCK_SAFE_METHODS = false;

			//Run method
			retVal = method->desc.call(cl);

			//Restore relocking values
			setActiveObject(prevObj);
			PREVENT_RELOCKING = prevPrevent;
			RELOCK_SAFE_METHODS = prevSafe;

			if(cl.status != asSUCCESS) {
				throwException("Wrapped script call unsuccessful.");
				return retVal;
			}
		}
		else {
			//Prepare an asynchronous call
			//TODO: Avoid destructing empty GenericCallData
			if(hasReturn) {
				if(initialized) {
#if defined(LOG_SLOW_ASYNC_CALLS) || defined(PROFILE_ASYNC_CALLS)
					double start = devices.driver->getAccurateTime();
					double retTime;
					bool wasFast = true;
#endif

					obj->lockGroup->addMessage(
						new AsyncScriptCall(method, args, offset, isGUI, &retVal
#ifdef LOG_SLOW_ASYNC_CALLS
						, &retTime
#endif
						)
					);

					//Attempt to process the message immediately where possible (typically the GUI, which needs the fast response)
					const unsigned ASYNC_SPIN_COUNT = 24;
					const unsigned FAST_SPIN_COUNT = 2500;

					if(!activeGroup) {
						unsigned spins = ASYNC_SPIN_COUNT;
						while(!retVal.asyncReturned) {
							if(!obj->lockGroup->hasLock())
								tickLockMessages(obj->lockGroup);
							else
								tickRandomMessages(1);

							if(--spins == 0) {
								threads::sleep(0);
								if(!obj->isValid())
									return retVal;
								spins = ASYNC_SPIN_COUNT;
								continue;
							}
						}
					}
					else {
						//Fast path: Often, the ret value will have been produced by the end of the loop
						unsigned spins = 0;
						while(!retVal.asyncReturned) {
							++spins;
							if(spins == FAST_SPIN_COUNT)
								break;
						}

						//Slow path: Perhaps it can't be resolved, or will take a lot longer than we'd like
						// This can involve a lot of other messages taking a very long time to return
						while(!retVal.asyncReturned) {
#ifdef LOG_SLOW_ASYNC_CALLS
							wasFast = false;
#endif
							if(!activeGroup->messages.empty())
								activeGroup->processMessages(1);
							else
								threads::sleep(0);

							if(!obj->isValid())
								return retVal;
						}
					}
					
#if defined(LOG_SLOW_ASYNC_CALLS) || defined(PROFILE_ASYNC_CALLS)
					double end = devices.driver->getAccurateTime();
					double dur = end - start;
#ifdef PROFILE_ASYNC_CALLS
					if(dur < 1.e-4)
						if(dur < 1.e-5)
							callCount[0]++;
						else
							callCount[1]++;
					else
						if(dur < 1.e-3)
							callCount[2]++;
						else
							callCount[3]++;
#endif
#ifdef LOG_SLOW_ASYNC_CALLS
					if(dur > 1.0e-3) {
						error("Long wait (%.1fms, wasted %.1fms%s) for %s", (end-start) * 1.0e3, (end-retTime) * 1.0e3, (activeGroup && wasFast) ? " fast" : "", method->func->GetName());
						auto* ctx = asGetActiveContext();
						if(ctx)
							error(getStackTrace(ctx, false));
					}
#endif
#endif
				}
			}
			else if(initialized) {
				obj->lockGroup->addMessage(new AsyncScriptCall(method, args, offset, isGUI));
			}
			else {
				obj->queueDeferredMessage(new AsyncScriptCall(method, args, offset, isGUI));
			}
		}
	}
	else if(method->shadow || !devices.network->isClient) {
		throwException("Unbound function called.");
		return retVal;
	}

	return retVal;
}

class ObjectWaitMessage : public ObjectMessage {
public:
	volatile bool* done;

	ObjectWaitMessage(Object* obj, volatile bool* done)
		: ObjectMessage(obj), done(done) {
		object->grab();
	}

	void process() {
		*done = true;
	}

	~ObjectWaitMessage() {
		object->drop();
		*done = true;
	}
};

void objectWait(Object* obj) {
	//Check relocking requirement
	if(PREVENT_RELOCKING) {
		throwException("Cannot call relocking Object.wait() method from non-relocking outer function.");
		return;
	}

	if(!obj->isInitialized())
		return;

	volatile bool done = false;
	auto* msg = new ObjectWaitMessage(obj, &done);
	obj->lockGroup->addMessage(msg);

	LockGroup* activeGroup = getActiveLockGroup();
	while(!done) {
		threads::sleep(0);
		if(activeGroup)
			activeGroup->processMessages(4);
		else
			tickRandomMessages(10);
	}
}

bool getSafeCallWait() {
	return RELOCK_SAFE_METHODS;
}

void setSafeCallWait(bool wait) {
	RELOCK_SAFE_METHODS = wait;
}

void handleObjectComponentMessage(Player* from, net::Message& msg) {
	Object* obj = readObject(msg, false);
	if(obj) {
		bool componentCall = msg.readBit();
		unsigned compId, index;

		msg.readAlign();
		if(componentCall)
			compId = msg.readSmall();
		index = msg.readSmall();

		WrappedMethod* method;
		asIScriptObject* script;

		if(componentCall) {
			Component* comp = getComponent(compId);
			if(!comp || index >= comp->methods.size())
				return;
			if(comp->containingType != GT_Object_Ref)
				return;
			method = comp->methods[index];
			if(!method->func)
				return;
			size_t offset = obj->type->componentOffsets[method->compId];
			script = *(asIScriptObject**)((size_t)obj + offset);
		}
		else {
			if(index >= obj->type->states->methods.size())
				return;
			method = obj->type->states->methods[index].wrapped;
			if(!method || !method->func)
				return;
			script = obj->script;
		}

		if(!script)
			return;

		GenericCallData args(method->wrapped);
		if(!args.read(msg)) {
			obj->drop();
			return;
		}

		Call cl = devices.scripts.server->call(method->func);
		cl.setObject(script);
		if(method->passPlayer)
			cl.push((void*)from);
		if(method->passContaining)
			cl.push((void*)obj);

		args.pushTo(cl);

		{
			//Check restriction
			ObjectLock lock(obj);
			if(!method->restricted || from->controls(obj->owner))
				cl.call();
		}

		obj->drop();
	}
}

static void hasComponent(asIScriptGeneric* f) {
	bool has = false;

	Component* comp = (Component*)f->GetFunction()->GetUserData();

	Object* obj = (Object*)f->GetObject();

	size_t offset = obj->type->componentOffsets[comp->id];

	if(offset != 0) {
		asIScriptObject* scr = *(asIScriptObject**)((size_t)obj + offset);

		if(scr != 0) {
			has = true;
		}
	}

	f->SetReturnByte(has);
}

static void getComponentPtr(asIScriptGeneric* f) {
	asIScriptObject* addr = 0;

	Component* comp = (Component*)f->GetFunction()->GetUserData();

	Object* obj = (Object*)f->GetObject();

	size_t offset = obj->type->componentOffsets[comp->id];

	if(offset != 0) {
		addr = *(asIScriptObject**)((size_t)obj + offset);

		if(addr)
			addr->AddRef();
	}

	f->SetReturnAddress((void*)addr);
}

static void getKnownComponentPtr(asIScriptGeneric* f) {
	asIScriptObject* addr = 0;

	size_t offset = (size_t)f->GetFunction()->GetUserData();
	Object* obj = (Object*)f->GetObject();

	if(offset != 0) {
		addr = *(asIScriptObject**)((size_t)obj + offset);

		if(addr)
			addr->AddRef();
	}

	f->SetReturnAddress((void*)addr);
}

static void activateComponent(asIScriptGeneric* f) {
	Component* comp = (Component*)f->GetFunction()->GetUserData();
	Object* obj = (Object*)f->GetObject();

	size_t offset = obj->type->componentOffsets[comp->id];

	if(offset != 0) {
		asIScriptObject** addr = (asIScriptObject**)((size_t)obj + offset);

		if(*addr)
			return;

		asIScriptFunction* func = comp->type->GetFactoryByIndex(0);
		Call cl = devices.scripts.server->call(func);
		cl.call(*addr);

		if(*addr)
			(*addr)->AddRef();
	}
}

static void deactivateComponent(asIScriptGeneric* f) {
	Component* comp = (Component*)f->GetFunction()->GetUserData();
	Object* obj = (Object*)f->GetObject();

	size_t offset = obj->type->componentOffsets[comp->id];

	if(offset != 0) {
		asIScriptObject** addr = (asIScriptObject**)((size_t)obj + offset);

		if(*addr == 0)
			return;

		(*addr)->Release();
		*addr = 0;
	}
}

void RegisterObjectComponentWrappers(ClassBind& obj, bool server, ScriptObjectType* type) {
	if(type) {
		auto* states = type->states;
		if(states) {
			foreach(it, states->methods) {
				WrappedMethod* method = it->wrapped;
				if(!method)
					continue;
			
				if(server || (!method->server && !method->shadow))
					bindGeneric(obj, method->wrapped, wrapperFunc, (void*)method, true);
			}
		}
	}

	//Register wrapper class for each component correctly
	foreach(it, components) {
		Component& comp = **it;

		//Skip over things that are not in objects
		if(comp.containingType != GT_Object_Ref)
			continue;
		//Skip over things not in this object type
		if(type != nullptr && type->componentOffsets[comp.id] == 0)
			continue;

		//Add interface to the object
		foreach(m, comp.methods) {
			WrappedMethod* method = *m;

			if(server || (!method->server && !method->shadow)) {

#ifdef DOCUMENT_API
				int fid = bindGeneric(obj, method->wrapped, wrapperFunc, (void*)method, true);
				auto* doc = new Documentor(fid, method->fullDeclaration);
				doc->documented = !method->doc_desc.empty() || !method->doc_return.empty() || !method->doc_args.empty();
				doc->funcDoc = method->doc_desc;
				doc->retDoc = method->doc_return;
				doc->argDoc = method->doc_args;
#else
				bindGeneric(obj, method->wrapped, wrapperFunc, (void*)method, true);
#endif
			}
		}

		if(type) {
			//Check whether a component exists
			if(type->optionalComponents[comp.id]) {
				obj.addGenericMethod(format("bool get_has$1() const", comp.name).c_str(), asFUNCTION(hasComponent), &comp)
					doc("Returns true if the object has the associated component.", "");

				obj.addGenericMethod(format("void activate$1()", comp.name).c_str(), asFUNCTION(activateComponent), &comp)
					doc("Activates an optional component if not already activated.");

				obj.addGenericMethod(format("void deactivate$1()", comp.name).c_str(), asFUNCTION(deactivateComponent), &comp)
					doc("Deactivates an optional component.");
			}

			//Get the component pointer
			obj.addGenericMethod(format("Component_$1@ get_$1()", comp.name, comp.name).c_str(), asFUNCTION(getKnownComponentPtr), (void*)(size_t)type->componentOffsets[comp.id])
				doc("Returns the component handle for this type of component.", "");
		}
		else {
			//Check whether a component exists
			obj.addGenericMethod(format("bool get_has$1() const", comp.name).c_str(), asFUNCTION(hasComponent), &comp)
				doc("Returns true if the object has the associated component.", "");

			//Get the component pointer
			obj.addGenericMethod(format("Component_$1@ get_$1()", comp.name, comp.name).c_str(), asFUNCTION(getComponentPtr), &comp)
				doc("Returns the component handle for this type of component.", "Can be null if no component of this type exists for this object.");
		}
	}
}

class AsyncEmpireScriptCall : public EmpireMessage {
	WrappedMethod* method;
	GenericCallData args;
	size_t compOffset;
	bool fromGUI;
	GenericValue* retValue;

public:
	AsyncEmpireScriptCall(WrappedMethod* Method, GenericCallData& arguments, size_t offset,
					bool FromGUI, GenericValue* pReturn = 0)
		: method(Method), args(arguments),
			compOffset(offset), fromGUI(FromGUI), retValue(pReturn)
	{
	}

	void process(Empire* emp) override {
		asIScriptObject* script = *(asIScriptObject**)((size_t)emp + compOffset);

		if(!script || (fromGUI && method->restricted && !devices.network->getCurrentPlayer().controls(emp))) {
			if(script) //Attempted to call restricted method
				info( format("Cannot call method '$1' on other empires.", method->wrapped.name).c_str() );
			if(retValue)
				retValue->asyncReturned = true;
			return;
		}

		Call cl = devices.scripts.server->call(method->func);
		cl.setObject(script);
		if(method->passPlayer) {
			if(fromGUI)
				cl.push((void*)&devices.network->getCurrentPlayer());
			else
				cl.push((void*)&SERVER_PLAYER);
		}
		if(method->passContaining)
			cl.push((void*)emp);
		args.pushTo(cl);

		//Save relocking values
		bool prevPrevent = PREVENT_RELOCKING;
		bool prevSafe = RELOCK_SAFE_METHODS;
		Object* prevObj = getActiveObject();

		PREVENT_RELOCKING = !method->relocking;
		RELOCK_SAFE_METHODS = false;

		if(retValue) {
			GenericValue ret = method->desc.call(cl);
			auto* type = method->desc.returnType.type;
			if(type)
				type->copy(*retValue, ret);
			else
				*retValue = ret;
			retValue->asyncReturned = true;
		}
		else {
			method->desc.call(cl);
		}

		//Restore relocking values
		setActiveObject(prevObj);
		PREVENT_RELOCKING = prevPrevent;
		RELOCK_SAFE_METHODS = prevSafe;
	}
};

/* Components registered to other empires */
static std::vector<size_t> empComponentOffsets;

static GenericValue emp_wrapperFunc(void* arg, GenericCallData& args) {
	GenericValue retVal;
	WrappedMethod* method = (WrappedMethod*)arg;

	Empire* emp = (Empire*)args.object;
	size_t offset = empComponentOffsets[method->compId];

	if(offset == 0) {
		throwException(format("Empire does not have component '$2'.",
					getComponent(method->compId)->name).c_str());
		return retVal;
	}

	asIScriptObject* comp = *(asIScriptObject**)((size_t)emp + offset);
	if(!comp)
		return retVal;

	//Check restriction
	bool isGUI = scripts::getActiveManager() != devices.scripts.server;
	if(method->restricted) {
		if(!devices.network->getCurrentPlayer().controls(emp) && isGUI) {
			info(
				format("Cannot call method '$1' on other empires.",
				method->wrapped.name).c_str());
			return retVal;
		}
	}

	if(!method->local && devices.network->isClient) {
		net::Message msg(MT_Empire_Component_Call, net::MF_Managed);
		msg << emp->id;
		msg << method->compId;
		msg << method->index;
		args.write(msg);

		devices.network->send(msg);
	}

	if(method->func) {
		bool hasReturn = method->desc.returnsArray || method->desc.returnType.type;
		auto* activeGroup = getActiveLockGroup();

		if(!method->async || !activeGroup) {
			Call cl = devices.scripts.server->call(method->func);
			cl.setObject(comp);
			if(method->passPlayer) {
				if(isGUI)
					cl.push((void*)&devices.network->getCurrentPlayer());
				else
					cl.push((void*)&SERVER_PLAYER);
			}
			if(method->passContaining)
				cl.push((void*)emp);
			args.pushTo(cl);

			if(hasReturn) {
				GenericValue ret = method->desc.call(cl);
				auto* type = method->desc.returnType.type;
				if(type)
					type->copy(retVal, ret);
				else
					retVal = ret;
			}
			else {
				method->desc.call(cl);
			}
		}
		else {
			if(PREVENT_RELOCKING) {
				if(hasReturn || method->relocking) {
					throwException("Cannot call relocking method from non-relocking outer function.");
					return retVal;
				}
			}

			emp->queueMessage(new AsyncEmpireScriptCall(method, args, offset, isGUI, hasReturn ? &retVal : nullptr));

			//Wait for async data return
			if(hasReturn) {
				auto* activeGroup = getActiveLockGroup();
				while(!retVal.asyncReturned) {
					threads::sleep(0);
					if(activeGroup)
						activeGroup->processMessages(4);
				}
			}
		}
	}
	else if(method->shadow || !devices.network->isClient) {
		throwException("Unbound function called.");
		return retVal;
	}

	return retVal;
}

void handleEmpireComponentMessage(Player* from, net::Message& msg) {
	unsigned char id;
	msg >> id;

	Empire* emp = Empire::getEmpireByID(id);
	if(emp) {
		unsigned compId, index;
		msg >> compId;
		msg >> index;

		Component* comp = getComponent(compId);
		if(index >= comp->methods.size())
			return;
		if(comp->containingType != GT_Empire_Ref)
			return;
		WrappedMethod* method = comp->methods[index];
		if(!method->func)
			return;

		//Check restriction
		if(method->restricted && !from->controls(emp))
			return;

		size_t offset = empComponentOffsets[method->compId];
		asIScriptObject* script = *(asIScriptObject**)((size_t)emp + offset);

		GenericCallData args(method->wrapped);
		if(!args.read(msg))
			return;

		Call cl = devices.scripts.server->call(method->func);
		cl.setObject(script);
		if(method->passPlayer)
			cl.push((void*)from);
		if(method->passContaining)
			cl.push((void*)emp);

		args.pushTo(cl);
		cl.call();
	}
}

static void emp_hasComponent(asIScriptGeneric* f) {
	bool has = false;

	Component* comp = (Component*)f->GetFunction()->GetUserData();
	Empire* emp = (Empire*)f->GetObject();

	size_t offset = empComponentOffsets[comp->id];

	if(offset != 0) {
		asIScriptObject* scr = *(asIScriptObject**)((size_t)emp + offset);

		if(scr != 0) {
			has = true;
		}
	}

	f->SetReturnByte(has);
}

static void emp_getComponentPtr(asIScriptGeneric* f) {
	asIScriptObject* addr = 0;

	Component* comp = (Component*)f->GetFunction()->GetUserData();
	Empire* emp = (Empire*)f->GetObject();

	size_t offset = empComponentOffsets[comp->id];

	if(offset != 0) {
		addr = *(asIScriptObject**)((size_t)emp + offset);

		if(addr)
			addr->AddRef();
	}

	f->SetReturnAddress((void*)addr);
}

//TODO: Optimize this knowing the Empire at bind-time
void BindEmpireComponentOffsets() {
	const StateDefinition& def = *Empire::getEmpireStates();
	unsigned bytes = sizeof(Empire);
	StateDefinition::align(bytes);

	//Zero all empire component offsets
	unsigned compCnt = getComponentCount();
	empComponentOffsets.resize(compCnt);
	for(unsigned i = 0; i < compCnt; ++i)
		empComponentOffsets[i] = 0;

	//Find the component offsets for the empire
	for(auto var = def.types.begin(), endvar = def.types.end(); var != endvar; ++var) {
		auto& type = *var->def;
		Component* comp = getComponent(&type);
		if(comp) {
			if(empComponentOffsets[comp->id] != 0)
				error("ERROR: Empire has two components of type '%s'.", comp->name.c_str());
			else
				empComponentOffsets[comp->id] = bytes;
		}

		bytes += type.size;
	}
}

void RegisterEmpireComponentWrappers(ClassBind& emp, bool server) {
	//Register wrapper class for each component correctly
	foreach(it, components) {
		Component& comp = **it;

		//Skip over things that are not in empires
		if(comp.containingType != GT_Empire_Ref)
			continue;

		//Add interface to the empire
		foreach(m, comp.methods) {
			WrappedMethod* method = *m;

			if(server || (!method->server && !method->shadow)) {
#ifdef DOCUMENT_API
				int fid = bindGeneric(emp, method->wrapped, emp_wrapperFunc, (void*)method, true);
				auto* doc = new Documentor(fid, method->fullDeclaration);
				doc->documented = !method->doc_desc.empty() || !method->doc_return.empty() || !method->doc_args.empty();
				doc->funcDoc = method->doc_desc;
				doc->retDoc = method->doc_return;
				doc->argDoc = method->doc_args;
#else
				bindGeneric(emp, method->wrapped, emp_wrapperFunc, (void*)method, true);
#endif
			}
		}

		//Check whether a component exists
		int fid = getEngine()->RegisterObjectMethod(emp.name.c_str(),
			format("bool get_has$1() const", comp.name).c_str(),
			asFUNCTION(emp_hasComponent), asCALL_GENERIC);

		if(fid > 0)
			getEngine()->GetFunctionById(fid)->SetUserData(&comp);
		else
			assert(false);

		//Get the component pointer
		fid = getEngine()->RegisterObjectMethod(emp.name.c_str(),
			format("Component_$1@ get_$1()", comp.name, comp.name).c_str(),
			asFUNCTION(emp_getComponentPtr), asCALL_GENERIC);

		if(fid > 0)
			getEngine()->GetFunctionById(fid)->SetUserData(&comp);
		else
			assert(false);
	}
}

/* Node Method Wrappers */
class AsyncNodeCall : public scene::NodeEvent {
	WrappedMethod* method;
	GenericCallData args;

public:
	AsyncNodeCall(scene::ScriptedNode* node, WrappedMethod* Method, GenericCallData& Args) : NodeEvent(node), method(Method), args(Args) {
	}

	void process() {
		//Nodes that are being destroyed will have a null script object
		scene::ScriptedNode* scriptedNode = (scene::ScriptedNode*)node;
		if(scriptedNode->scriptObject) {
			Call cl = devices.scripts.client->call(method->func);
			cl.setObject(scriptedNode->scriptObject);
			if(method->passContaining)
				cl.push((void*)scriptedNode);
			args.pushTo(cl);
			method->desc.call(cl);
		}
	}
};

static GenericValue nodeWrapperFunc(void* arg, GenericCallData& args) {
	GenericValue retVal;
	WrappedMethod* method = (WrappedMethod*)arg;

	scene::ScriptedNode* node = (scene::ScriptedNode*)args.object;

	if(method->func) {
		//Prepare an asynchronous call
		//TODO: Avoid destructing empty GenericCallData
		scene::queueNodeEvent(new AsyncNodeCall(node, method, args));
	}
	else {
		throwException("Unbound function called.");
		return retVal;
	}

	return retVal;
}

void RegisterNodeMethodWrappers(ClassBind& cls, bool server, scene::scriptNodeType* type) {
	foreach(m, type->methods) {
		WrappedMethod* method = *m;
		bindGeneric(cls, method->wrapped, nodeWrapperFunc, (void*)method, false);
	}
}

/* Component interface registration */
void RegisterComponentInterfaces(bool server) {
	//Register interface for each component correctly
	foreach(it, components) {
		Component& comp = **it;

		std::string name = "Component_";
		name += comp.name;

		InterfaceBind intf(name.c_str());
	}
}

/* Retrieve the function pointers for the interfaces */
void bindComponentClasses() {
	//Find classes to instantiate for each component
	foreach(it, components) {
		Component& comp = **it;

		std::vector<std::string> args;
		split(comp.typeDecl, args, "::");

		if(args.size() != 2) {
			error("Invalid script class specifier: '%s'", comp.typeDecl.c_str());
			continue;
		}

		comp.type = devices.scripts.server->getClass(args[0].c_str(), args[1].c_str());
		if(!comp.type) {
			error("Script class not found: '%s'", comp.typeDecl.c_str());
			continue;
		}

		comp.save = comp.type->GetMethodByDecl("void save(SaveFile&)");

		std::string loadFactoryDecl = comp.name + "@ " + comp.name + "(SaveFile&)";
		comp.load = comp.type->GetFactoryByDecl(loadFactoryDecl.c_str());

		foreach(m, comp.methods) {
			WrappedMethod* method = *m;

			if(!devices.network->isClient) {
				if(method->shadow)
					continue;
			}

			if(!method->func)
				method->origDesc = method->desc;
			GenericCallDesc desc = method->origDesc;

			//Try to find the const version first
			if(method->wrapped.constFunction) {
				desc.constFunction = true;
				method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
				if(method->func) {
					continue;
				}

				//Prepend the containing object to see if we need it
				desc.prepend(ArgumentDesc(comp.containingType, method->wrapped.constFunction));

				method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
				if(method->func) {
					method->desc = desc;
					method->passContaining = true;
					continue;
				}

				//Prepend the player to see if we need it
				desc.prepend(GT_Player_Ref);

				method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
				if(method->func) {
					method->desc = desc;
					method->passContaining = true;
					method->passPlayer = true;
					continue;
				}

				desc = method->origDesc;
				desc.constFunction = false;

				method->passContaining = false;
				method->passPlayer = false;
			}

			method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
			if(method->func)
				continue;

			//Prepend the containing object to see if we need it
			desc.prepend(ArgumentDesc(comp.containingType, method->wrapped.constFunction));

			method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
			if(method->func) {
				method->desc = desc;
				method->passContaining = true;
				continue;
			}

			//Prepend the player to see if we need it
			desc.prepend(GT_Player_Ref);

			method->func = comp.type->GetMethodByDecl(desc.declaration().c_str());
			if(method->func) {
				method->desc = desc;
				method->passContaining = true;
				method->passPlayer = true;
				continue;
			}

			//Give an error if nothing resolved
			if(!devices.network->isClient || method->shadow || (method->local && !method->server))
				error("Method not found: %s -> %s",
						comp.typeDecl.c_str(),
						method->desc.declaration().c_str());
		}
	}
}

};
