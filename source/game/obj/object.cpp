#include "empire.h"
#include "obj/object.h"
#include "obj/universe.h"
#include "obj/obj_group.h"
#include "constants.h"
#include "quaternion.h"
#include "util/random.h"
#include "main/references.h"
#include "network/network_manager.h"
#include "network.h"
#include "obj/lock.h"
#include "design/effect.h"
#include "str_util.h"
#include "compat/misc.h"
#include "util/format.h"
#include "main/logging.h"
#include "processing.h"
#include <unordered_map>
#include "assert.h"
#include "physics/physics_world.h"
#include "general_states.h"
#include <float.h>

threads::ReadWriteMutex objectsLock;
std::unordered_map<unsigned,Object*> objects;

bool Object::GALAXY_CREATION = false;

unsigned ObjectTypeCount = 0;

extern void writeObject(net::Message& msg, Object* obj, bool includeType = true);
extern Object* readObject(net::Message& msg, bool create, int knownType = -1);

Object* getObjectByID(unsigned id, bool create) {
	{
		threads::ReadLock lock(objectsLock);
		auto obj = objects.find(id);
		if(obj != objects.end()) {
			obj->second->grab();
			return obj->second;
		}
	}

	if(create && id != 0) {
		threads::WriteLock wl(objectsLock);
		auto obj = objects.find(id);
		if(obj != objects.end()) {
			obj->second->grab();
			return obj->second;
		}
		if(create && id != 0) {
			Object* obj = Object::create(getObjectTypeFromID(id), 0, id);
			obj->grab();
			return obj;
		}
	}
	return 0;
}

void invalidateUninitializedObjects() {
	{
		threads::ReadLock lock(objectsLock);
		foreach(it, objects) {
			auto* child = it->second;
			if(child->getFlag(objUninitialized))
				child->setFlag(objValid, false);
		}
	}
}

ScriptObjectType* getObjectTypeFromID(unsigned id) {
	return getScriptObjectType(id >> ObjectTypeBitOffset);
}

void registerObject(Object* obj) {
	threads::WriteLock lock(objectsLock);
	objects[obj->id] = obj;
}

void unregisterObject(Object* obj) {
	threads::WriteLock lock(objectsLock);
	objects.erase(obj->id);
}

const char* obj_callback_decl[SOC_COUNT] = {
	"void init($1& obj)",
	"void postInit($1& obj)",
	"void destroy($1& obj)",
	"void groupDestroyed($1& obj)",
	"double tick($1& obj, double time)",
	"bool onOwnerChange($1& obj, Empire@ prevOwner)",
	"void damage($1& obj, DamageEvent& evt, double position, const vec2d& direction)",
	"void repair($1& obj, double amount)",
	"void syncInitial(const $1&, Message&)",
	"void syncDetailed(const $1&, Message&)",
	"bool syncDelta(const $1&, Message&)",
	"void syncInitial($1&, Message&)",
	"void syncDetailed($1&, Message&, double tDiff)",
	"void syncDelta($1&, Message&, double tDiff)",
	"void save($1&, SaveFile&)",
	"void load($1&, SaveFile&)",
	"void postLoad($1&)",
};

static std::unordered_map<std::string, ScriptObjectType*> objTypes;
std::vector<ScriptObjectType*> objTypeList;

void clearObjects() {
	objects.clear();
	foreach(it, objTypeList)
		(*it)->nextID = 1;
}

ScriptObjectType* getScriptObjectType(int index) {
	if(index >= 0 && index < (int)objTypeList.size())
		return objTypeList[index];
	return 0;
}

unsigned getScriptObjectTypeCount() {
	return (unsigned)objTypeList.size();
}

void prepScriptObjectTypes() {
	foreach(it, objTypes)
		delete it->second;
	objTypes.clear();
	objTypeList.clear();

	auto& baseObjType = getStateDefinition("Object");
	for(auto i = stateDefinitions.begin(), end = stateDefinitions.end(); i != end; ++i) {
		auto& type = **i;
		if(type.base != &baseObjType)
			continue;

		ScriptObjectType* objType = new ScriptObjectType();
		objType->name = type.name;
		objType->script = type.scriptClass;
		objType->id = (unsigned)objTypeList.size();

		objTypes[type.name] = objType;
		objTypeList.push_back(objType);
	}

	ObjectTypeCount = objTypeList.size();
}

void addObjectStateValueTypes() {
	for(auto it = objTypes.begin(), end = objTypes.end(); it != end; ++it) {
		ScriptObjectType& type = *it->second;
		std::string stateName = type.name;
		std::string safeStateName = type.name+"$";
		std::string scriptName = type.name+"@";

		{
			StateValueDefinition& def = stateValueTypes[stateName.c_str()];
			def = *getStateValueType("Object");
			def.type = scriptName;
			def.returnType = scriptName;
		}

		{
			StateValueDefinition& def = stateValueTypes[safeStateName.c_str()];
			def = *getStateValueType("Object$");
			def.type = scriptName;
			def.returnType = scriptName;
		}
	}
}

void setScriptObjectStates() {
	const StateDefinition* objData = &getStateDefinition("Object");

	for(auto it = objTypes.begin(), end = objTypes.end(); it != end; ++it) {
		ScriptObjectType& type = *it->second;
		
		const StateDefinition* states = &getStateDefinition(type.name);
		if(states == &errorStateDefinition) {
			states = objData;
		}
		else {
			if(states->base) {
				if(states->base != objData) {
					states = objData;
					error("ERROR: %s does not inherit from Object.",
						type.name.c_str());
				}
			}
			else if(objData != &errorStateDefinition){
				error("ERROR: %s does not inherit from Object.",
					type.name.c_str());
				states = objData;
			}
		}
		type.states = states;
	}
}

void bindScriptObjectTypes() {
	for(auto it = objTypes.begin(), end = objTypes.end(); it != end; ++it) {
		ScriptObjectType& type = *it->second;

		//Bind script
		std::vector<std::string> args;
		split(type.script, args, "::");

		if(args.size() == 2)
			type.bind(args[0].c_str(), args[1].c_str());
	}
}

ScriptObjectType* getScriptObjectType(const std::string& name) {
	auto it = objTypes.find(name);
	if(it == objTypes.end())
		return 0;
	return it->second;
}

void Object::grab() const {
	++references;
}

void Object::drop() const {
	if(--references == 0) {
		this->~Object();
		free((void*)this);
	}
}

Object* Object::create(ScriptObjectType* type, LockGroup* lock, int id) {
	size_t bytes = sizeof(Object);
	if(type)
		bytes += type->states->getSize(sizeof(Object));

	void* mem = malloc(bytes);
	return new(mem) Object(type, lock, id);
}

void Object::addTimedEffect(const TimedEffect& eff) {
	TimedEffect* timedEffect = new TimedEffect(eff);
	timedEffect->call(EH_Start);
	effects.push_back(timedEffect);
}

void Object::queueDeferredMessage(ObjectMessage* msg) {
	auto* defer = new DeferredObjMessage();
	defer->msg = msg;
	auto* prev = deferredMessages;
	defer->next = prev;
	while(threads::compare_and_swap((void**)&deferredMessages, (void*)prev, (void*)defer) != prev) {
		prev = deferredMessages;
		defer->next = prev;
	}
}

DeferredObjMessage* Object::fetchMessages() {
	auto* prev = deferredMessages;
	while(threads::compare_and_swap((void**)&deferredMessages, (void*)prev, (void*)nullptr) != prev)
		prev = deferredMessages;
	return prev;
}

unsigned Object::updateVision(Object* target, unsigned depth) {
	unsigned mask = 0;
	if(target->owner && target->owner != owner) {
		double distSQ = position.distanceToSQ(target->position);
		if(distSQ < target->sightRange * target->sightRange)
			mask |= target->owner->mask;
		if(distSQ < sightRange * sightRange)
			target->donatedVision |= owner->mask;
	}

	if(depth > 0)
		for(unsigned i = 0; i < OBJ_TARGETS; ++i)
			mask |= updateVision(target->targets[i], depth-1);

	return mask;
}

double Object::think(double seconds) {
	if(!getFlag(objValid))
		return 5.0;

	setFlag(objWakeUp, false);

	vec3d prevPos = position;

	double objDelay = 5.0;

	if(type && script) {
		if(auto* scr_tick = type->functions[SOC_tick]) {
			scripts::Call cl = devices.scripts.server->call(scr_tick);
			if(cl.valid()) {
				cl.setObject((asIScriptObject*)script);
				cl.push((void*)this);
				cl.push(seconds);
				if(!cl.call(objDelay))
					objDelay = 5.0;
			}
		}
	}

	if(getFlag(objQueueDestroy)) {
		destroy();
		return 5.0;
	}

	//Calculate vision updates
	if(!devices.network->isClient) {
		if(alwaysVisible) {
			visibleMask = sightedMask = ~0x0;
		}
		//Find nearby objects we can see
		else {
			if(owner && owner->valid() && sightRange > 0.0) {
				unsigned sightCheckSteps = unsigned(100.0 * seconds);
				if(sightDelay <= sightCheckSteps) {
					unsigned mask = owner->mask;

					vec3d from = position; double dist = sightRange;

					devices.physics->findInBox(AABBoxd::fromCircle(position,sightRange),
						[mask,from,dist](const PhysicsItem& item) {
							if(item.type != PIT_Object)
								return;
							Object* other = item.object;
							if(other->alwaysVisible || (other->donatedVision & mask))
								return;

							double distance = from.distanceToSQ(other->position);
							if(distance < (dist + other->radius) * (dist + other->radius)) {
								if(distance < (other->seeableRange + other->radius) * (other->seeableRange + other->radius))
									other->donatedVision |= mask;
							}
						},
						~owner->mask );

					//Delay psuedo-randomly by 1.5-2.8 seconds (vision persists for 3 seconds)
					sightDelay = 150 + id % 64;
				}
				else {
					sightDelay -= sightCheckSteps;
				}
			}

			//Find nearby objects that can see us
			unsigned newVisionMask = 1;
			if(owner && owner->visionMask) {
				newVisionMask |= donatedVision | owner->mask;
				donatedVision = owner->mask;
			}
			else {
				newVisionMask |= donatedVision;
			}

			unsigned sightMask = newVisionMask;
			
			unsigned sightDecaySteps = (unsigned)(seconds * (255.0 / 3.0));
			unsigned char decay = sightDecaySteps >= 255 ? 255 : sightDecaySteps;
			for(unsigned i = 0, mask = 2; i < validEmpireCount; ++i, mask <<= 1) {
				unsigned char& v = visionTimes[i];
				if((newVisionMask & currentVision[i]) != 0) {
					v = 255;
					sightMask |= mask;
				}
				else if(v > decay) {
					v -= decay;
					newVisionMask |= mask;
				}
				else {
					v = 0;
				}
			}

			visibleMask = newVisionMask;
			sightedMask |= sightMask;
		}
	}
	else if(alwaysVisible) {
		visibleMask = sightedMask = ~0x0;
	}

	//Tick effects
	{
		unsigned cnt = (unsigned)effects.size();
		for(unsigned i = 0; i < cnt; ++i) {
			TimedEffect& eff = *effects[i];
			EffectStatus pre = eff.event.status;

			//Set tick values
			eff.tick(seconds);

			//Call suspend, continue and end
			if(eff.event.status == ES_Ended) {
				eff.call(EH_End);
				delete &eff;

				if(effects.size() > 1) {
					effects[i] = effects[effects.size()-1];
					if(effects.size() <= cnt) {
						--i;
						--cnt;
					}
					effects.resize(effects.size() - 1);
				}
				else {
					effects.resize(0);
					break;
				}
			}
			else {
				if(pre == ES_Suspended) {
					if(eff.event.status != ES_Suspended)
						eff.call(EH_Continue);
				}
				else {
					if(eff.event.status == ES_Suspended)
						eff.call(EH_Suspend);
				}
			}
		}
	}

	if(physItem) {
		if(!group) {
			//Update physics positon (this can move across a grid boundary, which needs access to the world)
			if(position != prevPos)
				devices.physics->updateItem(*physItem, AABBoxd::fromCircle(position, radius));
		}
		else {
			//Update our position without informing the group
			if(position != prevPos)
				physItem->bound = AABBoxd::fromCircle(position, radius);
			//If we are the group's owner, update the group to match the members' locations (touches world)
			if(group->getOwner() == this)
				group->update();
		}
	}

	if(devices.network->isServer && devices.network->hasSyncedClients) {
		unsigned newEmpireVisibleMask = 0;
		for(unsigned i = 0, cnt = Empire::getEmpireCount(); i < cnt; ++i) {
			Empire* emp = Empire::getEmpireByIndex(i);
			if(!emp->valid())
				continue;
			auto* pl = emp->player;
			if(!pl || !pl->wantsDeltas)
				continue;
			if(emp->visionMask & visibleMask)
				newEmpireVisibleMask |= emp->mask;
		}
		//Inform about vision changes
		if(newEmpireVisibleMask != prevVisibleMask) {
			devices.network->sendObjectVisionDelta(this, prevVisibleMask, newEmpireVisibleMask);
			prevVisibleMask = newEmpireVisibleMask;
		}
	}

	return objDelay;
}

void Object::damage(DamageEvent& evt, double position, const vec2d& direction) {
	if(type && script) {
		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_damage]);
		if(cl.valid()) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.push((void*)&evt);
			cl.push(position);
			cl.push((void*)&direction);
			cl.call();
		}
	}
}

void Object::repair(double amount) {
	if(type && script) {
		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_repair]);
		if(cl.valid()) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.push(amount);
			cl.call();
		}
	}
}


Object::Object(ScriptObjectType* Type, LockGroup* group, int ID)
	:   references(1), id(0), group(0),
		lockGroup(group ? group : getRandomLock()), originalLock(0), lockHint(0), deferredMessages(0),
		owner(Empire::getDefaultEmpire()),
		alwaysVisible(false), sightRange(1500.f), seeableRange(FLT_MAX), visionTimes(),
		visibleMask(0), donatedVision(0), prevVisibleMask(0), sightedMask(0), sightDelay(0),
		flags(objValid | objUninitialized), physItem(0),
		radius(0), lastTick(devices.driver->getGameTime()),
		node(0), script(0), type(Type)
{
	if(ID != 0) {
		id = ID;
	}
	else {
		id = type->nextID++;
		id |= type->id << 26;
	}

	//Vary the first tick by roughly a quarter second psuedo-randomly
	nextTick = lastTick + ((double)(unsigned char)ID)/1000.0;

	registerObject(this);
	for(unsigned i = 0; i < OBJ_TARGETS; ++i)
		targets[i] = this;

	//Dynamic memory is always a full object size past 'this'
	if(Type)
		memset(this + 1, 0, Type->states->getSize(sizeof(Object)));
}

Object::~Object() {
	if(type) {
		void* mixinMem = this + 1;
		type->states->unprepare(mixinMem);
	}
}

bool Object::isVisibleTo(Empire* emp) const {
	return (emp->visionMask & visibleMask) != 0;
}

bool Object::isKnownTo(Empire* emp) const {
	return (emp->mask & sightedMask) != 0;
}

bool Object::isLocked() const {
	return getActiveLockGroup() == lockGroup
		|| !processing::isRunning() || getFlag(objUninitialized);
}

void Object::init() {
	if(type) {
		void* mixinMem = this + 1;
		type->states->prepare(mixinMem);

		script = type->create();
		lockGroup->add(this);
		setFlag(objUninitialized, false);

		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_init]);
		if(cl.valid() && script) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.call();
		}
	}
}

void Object::postInit() {
	if(type) {
		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_postInit]);
		if(cl.valid() && script) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.call();
		}
	}
}

void Object::setOwner(Empire* newOwner) {
	if(newOwner == owner)
		return;
	Empire* prevOwner = owner;
	owner = newOwner;

	if(owner)
		visibleMask |= owner->mask;

	if(type) {
		scripts::Call cl = devices.scripts.server->call(type->functions[SOC_ownerChange]);
		if(cl.valid() && script) {
			cl.setObject(script);
			cl.push((void*)this);
			cl.push((void*)prevOwner);
			bool ret = false;
			cl.call(ret);

			if(ret)
				owner = prevOwner;
		}
	}

	if(owner != prevOwner) {
		if(prevOwner)
			prevOwner->unregisterObject(this);
		if(owner)
			owner->registerObject(this);

		if(!GALAXY_CREATION)
			setFlag(objSendDelta, true);

		if(physItem)
			devices.physics->updateItem(*physItem, AABBoxd::fromCircle(position, radius));
	}
}

void Object::clearScripts() {
	assert(!getFlag(objValid));

	//Kill the script object
	if(script) {
		script->Release();
		script = nullptr;
	}

	//Clear all references in the states
	if(type) {
		void* mixinMem = this + 1;
		type->states->preClear(mixinMem);
	}
}

void Object::destroy(bool fromUniverse) {
	if(getFlag(objValid)) {
		setFlag(objStopTicking, true);

		//Inform network clients
		if(devices.network->isServer)
			devices.network->destroyObject(this);

		//Inform the script of the destruction
		if(type && !fromUniverse && script) {
			scripts::Call cl = devices.scripts.server->call(type->functions[SOC_destroy]);
			if(cl.valid()) {
				cl.setObject((asIScriptObject*)script);
				cl.push((void*)this);
				cl.call();
			}
		}

		//Invalidate the object
		setFlag(objValid, false);

		//Clear the physics item
		if(!group) {
			if(physItem) {
				devices.physics->unregisterItem(*physItem);

				auto* it = physItem;
				physItem = nullptr;
				delete it;
			}
		}
		else {
			if(physItem) {
				physItem->object = 0;
				physItem = 0;
			}
			if(group->getOwner() == this) {
				if(group->removeOwner()) {
					scripts::Call cl = devices.scripts.server->call(type->functions[SOC_groupDestroyed]);
					if(cl.valid() && script) {
						cl.setObject((asIScriptObject*)script);
						cl.push((void*)this);
						cl.call();
					}
				}
			}
			group->drop();
			group = 0;

			//Clear phys item's reference
			drop();
		}

		//Stop all timed effects
		for(unsigned i = 0, cnt = effects.size(); i < cnt; ++i) {
			TimedEffect* eff = effects[i];
			eff->call(EH_Destroy);
			delete eff;
		}

		//Remove object from universe
		if(!fromUniverse)
			devices.universe->removeChild(this);

		//Clear the object's graphics
		if(node) {
			node->markForDeletion();
			node = 0;
		}

		if(fromUniverse)
			clearScripts();
		else
			queueObjectClear(this);

		//Remove object from empire
		if(owner) {
			if(!fromUniverse)
				owner->unregisterObject(this);
			else
				drop();
		}

		if(!fromUniverse)
			unregisterObject(this);

		drop();
	}
}

bool Object::getFlag(ObjectFlag flag) const {
	return (flags & flag) != 0;
}

void Object::setFlag(ObjectFlag flag, bool value) {
	if(value)
		flags |= flag;
	else
		flags &= ~flag;
}

bool Object::setFlagSecure(ObjectFlag flag, bool flagOn) {
	int prevVal, newVal;
	do {

		//If the flag is already set, give up
		prevVal = flags;
		if(((prevVal & flag) != 0) == flagOn)
			return false;

		//See what the new value would be, and keep trying until we are sure of the result
		newVal = flagOn ? (prevVal | flag) : (prevVal & ~flag);

	} while(flags.compare_exchange_strong(newVal, prevVal) != prevVal);

	return true;
}

bool Object::isValid() const {
	return getFlag(objValid);
}

bool Object::isFocus() const {
	return getFlag(objFocus);
}

void Object::focus() {
	setFlag(objFocus, true);
	//TODO: Keep a global list of focused objects
}

bool Object::isInitialized() const {
	return !getFlag(objUninitialized);
}

void Object::wake() {
	setFlag(objWakeUp,true);
}

void Object::sleep(double seconds) {
	nextTick += seconds;
}

void Object::updateTargets() {
	//Non-physical objects don't track targets.
	//However, we may load an old save where they did, so try to collect our pointers.
	if(getFlag(objNoPhysics)) {
		unsigned index = OBJ_TARGETS;
		for(unsigned i = 0; i < OBJ_TARGETS; ++i) {
			if(targets[i] != this) {
				index = i;
				break;
			}
		}

		if(index == OBJ_TARGETS)
			return;

		auto& targ = targets[index];
		for(unsigned i = 0; i < OBJ_TARGETS; ++i) {
			if(targ->targets[i] == this) {
				targ.swap(targ->targets[i]);
				break;
			}
		}

		return;
	}

	//Identify our worst target and try to locate an object to send it to
	double worst = position.distanceToSQ(targets[0]->position);
	unsigned worstIndex = 0;

	for(unsigned i = 1; i < OBJ_TARGETS; ++i) {
		double d = position.distanceToSQ(targets[i]->position);
		if(d > worst) {
			worst = d;
			worstIndex = i;
		}
	}

	auto& worstTarget = targets[worstIndex];
	auto& targPos = worstTarget->position;
	double bestNet = 0;
	heldPointer<Object>* best = 0;

	//Look for the best net difference we can achieve via this swap
	for(unsigned i = 0; i < OBJ_TARGETS; ++i) {
		heldPointer<Object>& targ = targets[i];

		if(targ == this) {
			devices.universe->setRandomTarget(targ);
			continue;
		}
		else if(i != worstIndex && targ != worstTarget) {
			for(unsigned j = 0; j < OBJ_TARGETS; ++j) {
				heldPointer<Object>& test = targ->targets[j];
				if(test == this)
					continue;
				double d = position.distanceToSQ(test->position);
				double o_d = targ->position.distanceToSQ(test->position);
				double o_targ_d = targ->position.distanceToSQ(targPos);

				double our_new = d - worst, their_new = o_targ_d - o_d;
				double net = our_new + their_new;
				if(net < bestNet) {
					best = &test;
					bestNet = net;
				}
			}
		}
	}

	//If we have a better object to swap with, do so. Otherwise, occasionally swap to a random target to prevent stagnation
	if(best)
		worstTarget.swap(*best);
}

inline double sqr(double x) {
	return x*x;
}

static inline void sendDetails(net::Message& msg, Object& obj, bool sendStates = true, bool sendPosition = true) {
	if(obj.owner)
		msg << obj.owner->id;
	else
		msg << INVALID_EMPIRE;

	msg << obj.alwaysVisible;
	msg << obj.visibleMask;
	msg << obj.sightRange;
	msg << obj.seeableRange;

	if(sendPosition) {
		if(obj.velocity.getLengthSQ() < 0.001) {
			msg.write1();
			msg.writeMedVec3(obj.position.x, obj.position.y, obj.position.z);
		}
		else {
			msg.write0();
		}
	}

	if(sendStates)
		obj.type->states->syncWrite(msg, &obj + 1);

	int count = obj.stats.size();
	msg.writeSmall(count);
	obj.stats.iterateAll([&msg,&count](uint64_t id, int64_t value) {
		if(count <= 0)
			return;
		int type = int((id & 0xFF00000000000000) >> 56);
		int left = int((id & 0x00FFFFFF00000000) >> 32);
		int right = int((id & 0x00000000FFFFFFFF));
		msg.writeSmall(type);
		msg.writeSmall(left);
		msg.writeSmall(right);
		msg << value;
		count--;
	});
}

static inline void recvDetails(net::Message& msg, Object& obj, bool recvStates = true, bool recvPosition = true) {
	unsigned char empID;
	msg >> empID;

	Empire* newOwner = Empire::getEmpireByID(empID);
	if(newOwner != obj.owner) {
		if(obj.getFlag(objUninitialized))
			obj.owner = newOwner;
		else
			obj.setOwner(newOwner);
	}

	msg >> obj.alwaysVisible;
	msg >> obj.visibleMask;
	obj.sightedMask |= obj.visibleMask;
	msg >> obj.sightRange;
	msg >> obj.seeableRange;

	if(recvPosition) {
		if(msg.readBit()) {
			msg.readMedVec3(obj.position.x, obj.position.y, obj.position.z);
			obj.velocity = vec3d();
			obj.acceleration = vec3d();
		}
	}

	if(recvStates)
		obj.type->states->syncRead(msg, &obj + 1);

	int count = msg.readSmall();
	for(int i = 0; i < count; ++i) {
		int type = msg.readSmall();
		int left = msg.readSmall();
		int right = msg.readSmall();
		int64_t value;
		msg >> value;

		obj.stats.set(uint64_t(type) << 56 | uint64_t(left) << 32 | uint64_t(right), value);
	}

	//TODO: Optimize with changes?
}

void Object::sendInitial(net::Message& msg) {
	assert(devices.network->isServer);
	writeObject(msg, this);

	msg << (float)radius;
	msg << name;
	msg << sightedMask;

	sendDetails(msg, *this, false, false);

	msg.writeMedVec3(position.x, position.y, position.z);
	if(velocity.zero()) {
		msg.write0();
	}
	else {
		msg.write1();
		msg.writeSmallVec3(velocity.x, velocity.y, velocity.z);
	}

	if(acceleration.zero()) {
		msg.write0();
	}
	else {
		msg.write1();
		msg.writeSmallVec3(acceleration.x, acceleration.y, acceleration.z);
	}

	msg.writeRotation(rotation.xyz.x, rotation.xyz.y, rotation.xyz.z, rotation.w);
	msg.writeBit(getFlag(objNoPhysics));
	msg.writeBit(getFlag(objMemorable));
	msg.writeBit(getFlag(objNoDamage));

	//TODO: Group sync is hackish, not finalized
	//due to groups probably changing in the future
	if(group) {
		msg.write1();
		msg << group->id;
		msg << group->getObjectCount();
		msg.writeBit(group->getOwner() == this);
	}
	else {
		msg.write0();
	}
	type->states->syncWrite(msg, this + 1);
	msg.writeAlign();

	auto* func = type->functions[SOC_syncInitial];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)script);
		cl.push((void*)this);
		cl.push((void*)&msg);
		cl.call();
	}
}

void Object::sendDetailed(net::Message& msg) {
	assert(devices.network->isServer);
	sendDetails(msg, *this);

	auto* func = type->functions[SOC_syncDetailed];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)script);
		cl.push((void*)this);
		cl.push((void*)&msg);
		cl.call();
	}
}

bool Object::sendDelta(net::Message& msg) {
	assert(devices.network->isServer);

	//Check if we're flagged to send
	bool send = false;
	if(getFlag(objSendDelta)) {
		msg.write1();
		sendDetails(msg, *this);

		send = true;
		setFlag(objSendDelta, false);
	}
	else {
		msg.write0();
	}

	//See if we should sync any stats
	if(stats.hasDirty()) {
		msg.write1();
		send = true;

		int count = stats.getDirtyCount();
		msg.writeSmall(count);

		stats.handleDirty([&msg,&count](uint64_t id, int64_t value) -> bool {
			if(count <= 0)
				return false;
			int left = int((id & 0xFFFFFFFF00000000) >> 32);
			int right = int((id & 0x00000000FFFFFFFF));
			msg.writeSmall(left);
			msg.writeSmall(right);
			msg << value;
			count--;
			return true;
		});
	}
	else {
		msg.write0();
	}

	//See if the scripts want to send anything
	auto* func = type->functions[SOC_syncDelta];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)script);
		cl.push((void*)this);
		cl.push((void*)&msg);

		bool scriptsend = false;
		cl.call(scriptsend);
		if(scriptsend)
			send = true;
	}

	return send;
}

void Object::recvDetailed(net::Message& msg, double fromTime) {
	assert(devices.network->isClient);
	recvDetails(msg, *this);

	auto* func = type->functions[SOC_recvDetailed];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)script);
		cl.push((void*)this);
		cl.push((void*)&msg);
		cl.push(fromTime - lastTick);
		cl.call();
	}
}

void Object::recvDelta(net::Message& msg, double fromTime) {
	assert(devices.network->isClient);

	if(msg.readBit())
		recvDetails(msg, *this);

	if(msg.readBit()) {
		int count = msg.readSmall();
		for(int i = 0; i < count; ++i) {
			int left = msg.readSmall();
			int right = msg.readSmall();
			int64_t value;
			msg >> value;

			stats.set(uint64_t(left) << 32 | uint64_t(right), value);
		}
	}

	auto* func = type->functions[SOC_recvDelta];
	if(func && script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)script);
		cl.push((void*)this);
		cl.push((void*)&msg);
		cl.push(fromTime - lastTick);
		cl.call();
	}
}

extern threads::ReadWriteMutex groupIDsLock;
Object* recvObjectInitial(net::Message& msg, double fromTime) {
	assert(devices.network->isClient);

	Object* obj = readObject(msg, true);

	float rad = 1.f; msg >> rad;
	obj->radius = rad;
	msg >> obj->name;
	msg >> obj->sightedMask;

	recvDetails(msg, *obj, false, false);

	msg.readMedVec3(obj->position.x, obj->position.y, obj->position.z);
	if(msg.readBit())
		msg.readSmallVec3(obj->velocity.x, obj->velocity.y, obj->velocity.z);
	if(msg.readBit())
		msg.readSmallVec3(obj->acceleration.x, obj->acceleration.y, obj->acceleration.z);

	obj->lastTick = fromTime;
	obj->nextTick = obj->lastTick;

	msg.readRotation(obj->rotation.xyz.x, obj->rotation.xyz.y, obj->rotation.xyz.z, obj->rotation.w);
	obj->setFlag(objNoPhysics, msg.readBit());
	obj->setFlag(objMemorable, msg.readBit());
	obj->setFlag(objNoDamage, msg.readBit());

	//TODO: Group sync is hackish, not finalized
	//due to groups probably changing in the future
	if(msg.readBit()) {
		unsigned inGroup = 0;
		LockGroup* locked = 0;

		int groupId;
		msg >> groupId;

		unsigned objCount;
		msg >> objCount;

		groupIDsLock.writeLock();

		obj->setFlag(objStopTicking, true);
		ObjectGroup* group = ObjectGroup::byID(groupId);
		if(!group) {
			group = new ObjectGroup(objCount, groupId);
			group->grab();
			group->grab();
			groupIDsLock.release();

			group->setObject(0, obj);
			group->grab();
			locked = lockObject(obj);
		}
		else {
			groupIDsLock.release();
			locked = lockObject(group->getOwner());
			inGroup = group->setNextObject(obj);
		}

		if(msg.readBit()) {
			group->setOwner(obj);
			unlockObject(locked);
			locked = lockObject(obj);
		}

		obj->group = group;
		if(!obj->getFlag(objNoPhysics)) {
			obj->physItem = group->getPhysicsItem(inGroup);
			obj->physItem->bound = AABBoxd::fromCircle(obj->position, obj->radius);
			obj->physItem->gridLocation = 0;
			obj->physItem->type = PIT_Object;
			obj->physItem->object = obj;
		}
		obj->grab();

		if(inGroup == group->getObjectCount() - 1) {
			group->postInit();

			for(unsigned i = 0, cnt = group->getObjectCount(); i < cnt; ++i) {
				Object* mem = group->getObject(i);
				if(mem->isValid())
					mem->setFlag(objStopTicking, false);
				mem->drop();
			}
		}

		unlockObject(locked);
	}
	else if(!obj->getFlag(objNoPhysics)) {
		obj->physItem = devices.physics->registerItem(AABBoxd::fromCircle(obj->position, obj->radius), obj);
	}

	ObjectLock lock(obj);
	if(obj->owner)
		obj->owner->registerObject(obj);
	devices.universe->addChild(obj);
	obj->init();
	obj->type->states->syncRead(msg, obj + 1);
	msg.readAlign();

	auto* func = obj->type->functions[SOC_recvInitial];
	if(func && obj->script) {
		scripts::Call cl = devices.scripts.server->call(func);
		cl.setObject((asIScriptObject*)obj->script);
		cl.push((void*)obj);
		cl.push((void*)&msg);
		cl.call();
	}

	obj->drop();
	return obj;
}


ObjectLock::ObjectLock(Object* Obj, bool priority)
	: released(false) {
	group = lockObject(Obj, priority);
}

ObjectLock::~ObjectLock() {
	if(!released)
		unlockObject(group);
}

void ObjectLock::release() {
	unlockObject(group);
	released = true;
}

ScriptObjectType::ScriptObjectType() : nextID(1), states(0), scriptType(0), blueprintOffset(0) {
	for(int i = 0; i < SOC_COUNT; ++i)
		functions[i] = 0;
}

void ScriptObjectType::bind(const char* module, const char* decl) {
	//Make sure the type exists, and is a script type
	scriptType = devices.scripts.server->getClass(module, decl);
	if(scriptType == 0) {
		error("Type %s::%s was not found", module, decl);
		return;
	}
	else if((scriptType->GetTypeId() & asTYPEID_SCRIPTOBJECT) == 0) {
		error("Type %s is not a script type", decl);
		scriptType = 0;
		return;
	}

	//Bind system methods
	for(int i = 0; i < SOC_COUNT; ++i)
		functions[i] = scriptType->GetMethodByDecl(format(obj_callback_decl[i],name).c_str());

	//Bind type methods
	if(states) {
		for(size_t i = 0; i < states->methods.size(); ++i) {
			auto& m = states->methods[i];
			auto* method = m.wrapped;
			if(!method)
				continue;

			method->objTypeId = id;
			if(!method->func)
				method->origDesc = method->desc;
			scripts::GenericCallDesc desc = method->origDesc;
			
			if(method->wrapped.constFunction) {
				desc.constFunction = true;
				method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
				if(method->func)
					continue;

				//Prepend the containing object to see if we need it
				desc.prepend(scripts::ArgumentDesc(scripts::GT_Object_Ref, method->wrapped.constFunction));

				method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
				if(method->func) {
					method->desc = desc;
					method->passContaining = true;
					continue;
				}

				//Prepend the player to see if we need it
				desc.prepend(scripts::GT_Player_Ref);

				method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
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

			method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
			if(method->func)
				continue;

			//Prepend the containing object to see if we need it
			desc.prepend(scripts::ArgumentDesc(refType, method->wrapped.constFunction));

			method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
			if(method->func) {
				method->desc = desc;
				method->passContaining = true;
				continue;
			}

			//Prepend the player to see if we need it
			desc.prepend(scripts::GT_Player_Ref);

			method->func = scriptType->GetMethodByDecl(desc.declaration().c_str());
			if(method->func) {
				method->desc = desc;
				method->passContaining = true;
				method->passPlayer = true;
				continue;
			}

			if(!devices.network->isClient || method->shadow || (method->local && !method->server))
				error("Could not find %s method '%s'", name.c_str(), desc.declaration().c_str());
		}
	}
}

asIScriptObject* ScriptObjectType::create() const {
	asIScriptObject* ptr = 0;

	if(scriptType) {
		asIScriptFunction* func = scriptType->GetFactoryByIndex(0);
		scripts::Call cl = devices.scripts.server->call(func);
		cl.call(ptr);

		if(ptr)
			ptr->AddRef();
	}

	return ptr;
}


