#pragma once
#include "vec3.h"
#include "vec2.h"
#include "quaternion.h"
#include "line3d.h"
#include "util/refcount.h"
#include "util/link_container.h"
#include "threads.h"
#include "general_states.h"
#include "util/random.h"
#include <vector>
#include <string>

#ifndef OBJ_TARGETS
#define OBJ_TARGETS 3
#endif

const unsigned ObjectTypeBitOffset = 26;
const unsigned ObjectTypeMask = 0xFFU << ObjectTypeBitOffset;
const unsigned ObjectIDMask = 0xFFFFFFFF >> (32 - ObjectTypeBitOffset);
extern unsigned ObjectTypeCount;

class Object;
class ObjectGroup;
struct PhysicsItem;
struct ObjectMessage;

class asIScriptFunction;
class asIScriptObject;
class asITypeInfo;

class SaveFile;

enum ScriptObjectCallback {
	SOC_init,
	SOC_postInit,
	SOC_destroy,
	SOC_groupDestroyed,
	SOC_tick,
	SOC_ownerChange,
	SOC_damage,
	SOC_repair,
	SOC_syncInitial,
	SOC_syncDetailed,
	SOC_syncDelta,
	SOC_recvInitial,
	SOC_recvDetailed,
	SOC_recvDelta,
	SOC_save,
	SOC_load,
	SOC_postLoad,

	SOC_COUNT
};

struct ScriptObjectType {
	unsigned id;
	std::string name;
	std::string script;
	mutable threads::atomic_int nextID;

	asITypeInfo* scriptType;
	asIScriptFunction* functions[SOC_COUNT];

	const StateDefinition* states;
	std::vector<size_t> componentOffsets;
	std::vector<bool> optionalComponents;
	size_t blueprintOffset;

	scripts::GenericType* refType;
	scripts::GenericType* handleType;

	ScriptObjectType();
	void bind(const char* module, const char* decl);
	asIScriptObject* create() const;
};

void prepScriptObjectTypes();
void addObjectStateValueTypes();
void setScriptObjectStates();
void bindScriptObjectTypes();
ScriptObjectType* getScriptObjectType(const std::string& name);

ScriptObjectType* getScriptObjectType(int index);
unsigned getScriptObjectTypeCount();

//Retrieve the object referred to by the given id.
// Grabs the object before returning it, so it needs
// to be dropped afterwards
Object* getObjectByID(unsigned id, bool create = false);
ScriptObjectType* getObjectTypeFromID(unsigned id);
void invalidateUninitializedObjects();

enum ObjectFlag : unsigned {
	//Object is not in the process of being deleted
	objValid = 0x1,
	//Object needs to go to sleep (going invalid)
	objStopTicking = 0x2,
	//Object has something to do and should ignore timeout delay
	objWakeUp = 0x4,
	//Object has been allocated as a reference-only object, and does not yet have data
	objUninitialized = 0x8,
	//Object has been flagged to send a data delta the next time it can
	objSendDelta = 0x10,
	//Object has been flagged as a focus object, this has various
	//effects for interpolation and multiplayer
	objFocus = 0x20,
	//Object is currently engaged in combat
	objEngaged = 0x40,
	//Object does not have physics
	objNoPhysics = 0x80,
	//Object is selected
	objSelected = 0x100,
	//Object is considered as in combat
	objCombat = 0x200,
	//Multiplayer clients should be able to get information even out of vision
	objMemorable = 0x400,
	//Whether it has been given a name
	objNamed = 0x800,
	//Whether the object should nudge movable objects (enforced by scripts)
	objNoCollide = 0x1000,
	//Whether the object can not receive damage by being hit by projectiles
	objNoDamage = 0x2000,


	objQueueDestroy = 0x80000000
};

const unsigned objFlagSaveMask = ~(objSelected);

namespace net {
	struct Message;
};

namespace scene {
	class Node;
};

class Empire;
struct LockGroup;
class TimedEffect;
class DamageEvent;

struct DeferredObjMessage {
	DeferredObjMessage* next, *prev;
	ObjectMessage* msg;
};

class Object {
public:
	static bool GALAXY_CREATION;

	mutable threads::atomic_int references;
	heldPointer<Object> targets[OBJ_TARGETS];

	//Object tree
	unsigned id;
	ObjectGroup* group;

	//Locking
	LockGroup* lockGroup;
	LockGroup* originalLock;
	unsigned lockHint;

	//Messages
	DeferredObjMessage* deferredMessages;
	void queueDeferredMessage(ObjectMessage* msg);
	DeferredObjMessage* fetchMessages();

	//Ownership
	Empire* owner;

	//Vision
	bool alwaysVisible;
	float sightRange;
	float seeableRange;
	unsigned char visionTimes[32];
	unsigned visibleMask, donatedVision, prevVisibleMask, sightedMask, sightDelay;

	//State variables
	threads::atomic_int flags;

	//Object spatial variables
	PhysicsItem* physItem;
	vec3d position, velocity, acceleration;
	quaterniond rotation;
	double radius;

	//The last time this Object ran its think()
	// - the parent is responsible for updating this
	double lastTick;
	double nextTick;

	//Effects
	std::vector<TimedEffect*> effects;
	void addTimedEffect(const TimedEffect& eff);

	//Generic stats
	LinkMap stats;

	//Graphics tree
	scene::Node* node;

	std::string name;

	asIScriptObject* script;

	const ScriptObjectType* type;

	void init();
	void postInit();
	void setOwner(Empire* newOwner);
	bool isLocked() const;

	static Object* create(ScriptObjectType* type, LockGroup* lock = 0, int id = 0);
	void grab() const;
	void drop() const;

	inline const ScriptObjectType* GetType() const { return type; }

	void setFlag(ObjectFlag flag, bool val);
	bool getFlag(ObjectFlag flag) const;
	//Like set flag, but only succeeds if this call set the flag to that value
	bool setFlagSecure(ObjectFlag flag, bool val);

	//Flag access wrappers
	bool isValid() const;
	bool isInitialized() const;
	void wake();
	void sleep(double seconds);

	//Focus is an object property to indicate
	//priority syncing and calculations.
	//The focus flag decays after a while and needs to
	//be set repeatedly on accessed objects.
	bool isFocus() const;
	void focus();

	bool isVisibleTo(Empire* emp) const;
	bool isKnownTo(Empire* emp) const;
	unsigned updateVision(Object* target, unsigned depth);

	//Damage events
	void damage(DamageEvent& evt, double position, const vec2d& direction);
	void repair(double amount);

	//Targeting
	void updateTargets();

	template<class T>
	bool findTargets(T& cb, int depth) {
		for(unsigned i = 0; i < OBJ_TARGETS; ++i) {
			Object* targ = targets[i].ptr;
			if(targ == this)
				continue;
			if(cb.result(targ))
				return true;
			if(depth != 0) {
				if(targ->findTargets(cb, depth-1))
					return true;
			}
		}
		return false;
	}

	static const unsigned char RANDOMIZE_TARGETS = 0;
	template<class T>
	bool findTargets(T& cb, int depth, unsigned char randomizer) {
		if(randomizer == RANDOMIZE_TARGETS)
			randomizer = (unsigned char)randomi();
		else
			randomizer ^= (unsigned char)id;
		unsigned index = randomizer % OBJ_TARGETS;
		for(unsigned i = 0; i < OBJ_TARGETS; ++i, index = (index+1) % OBJ_TARGETS) {
			Object* targ = targets[index].ptr;
			if(targ == this)
				continue;
			if(cb.result(targ))
				return true;
			if(depth != 0) {
				if(targ->findTargets(cb, depth-1, randomizer))
					return true;
			}
		}
		return false;
	}

	//Network syncing
	void sendInitial(net::Message& msg);
	void sendDetailed(net::Message& msg);
	bool sendDelta(net::Message& msg);

	void recvDetailed(net::Message& msg, double fromTime);
	void recvDelta(net::Message& msg, double fromTime);

	//Saving & loading
	void save(SaveFile& file);
	void load(SaveFile& file);
	void postLoad();

	//Management
	Object(ScriptObjectType* Type, LockGroup* group = 0, int id = 0);
	~Object();

	double think(double seconds);
	void flagDestroy() { setFlag(objQueueDestroy, true); setFlag(objWakeUp, true); }

	friend class Universe;

	void clearScripts();
private:
	void destroy(bool fromUniverse = false);
};

Object* recvObjectInitial(net::Message& msg, double fromTime);
void clearObjects();

struct ObjectLock {
	LockGroup* group;
	bool released;

	ObjectLock(Object* Obj, bool priority = false);
	void release();
	~ObjectLock();
};
