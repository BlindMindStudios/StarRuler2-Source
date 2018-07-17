#include "scripts/binds.h"
#include "scripts/script_components.h"
#include "obj/object.h"
#include "obj/lock.h"
#include "obj/obj_group.h"
#include "empire.h"
#include "main/references.h"
#include "network/network_manager.h"
#include "vec2.h"
#include "obj/blueprint.h"
#include "../as_addons/include/scriptarray.h"
#include "physics/physics_world.h"
#include "util/save_file.h"
#include "util/locked_type.h"
#include "util/link_container.h"
#include "main/logging.h"
#include "scripts/context_cache.h"
#include <algorithm>

namespace scripts {

void RegisterObjectArray(const std::string& objName);
extern net::Message& writeObjectScr(net::Message& msg, Object* obj);

ObjArray::ObjArray() {}
ObjArray::ObjArray(unsigned count) : objs(count) {
}

ObjArray* ObjArray::create() {
	return new ObjArray();
}

ObjArray* ObjArray::create_n(unsigned count) {
	return new ObjArray(count);
}

void ObjArray::operator=(const ObjArray& other) {
	//Clear out any prior values
	resize(0);
	resize(other.objs.size());
	for(unsigned i = 0, cnt = other.objs.size(); i < cnt; ++i) {
		auto* obj = other.objs[i];
		if(obj)
			obj->grab();
		objs[i] = obj;
	}
}

bool ObjArray::empty() const {
	return objs.empty();
}

unsigned ObjArray::size() const {
	return objs.size();
}

void ObjArray::reserve(unsigned size) {
	objs.reserve(size);
}

void ObjArray::resize(unsigned size) {
	//Drop any indices that are being removed
	for(unsigned i = size, cnt = objs.size(); i < cnt; ++i)
		if(auto* obj = objs[i])
			obj->drop();
	objs.resize(size);
}

void ObjArray::clear() {
	resize(0);
}

Object*& ObjArray::operator[](unsigned index) {
	if(index < objs.size())
		return objs[index];
	scripts::throwException("Index out of bounds.");
	return *(Object**)nullptr;
}

Object*& ObjArray::last() {
	if(!objs.empty())
		return objs.back();
	scripts::throwException("Array is empty.");
	return *(Object**)nullptr;
}

Object* ObjArray::index_value(unsigned index) {
	if(index < objs.size()) {
		Object* obj = objs[index];
		if(obj)
			obj->grab();
		return obj;
	}
	scripts::throwException("Index out of bounds.");
	return nullptr;
}

Object* ObjArray::last_value() {
	if(!objs.empty()) {
		Object* obj = objs.back();
		if(obj)
			obj->grab();
		return obj;
	}
	scripts::throwException("Array is empty.");
	return nullptr;
}

void ObjArray::erase(unsigned index) {
	if(index < objs.size()) {
		auto iter = objs.begin() + index;
		if(auto* obj = *iter)
			obj->drop();
		objs.erase(iter);
		return;
	}
	scripts::throwException("Index out of bounds.");
}

void ObjArray::insert(unsigned index, Object* obj) {
	if(index > objs.size()) {
		if(obj)
			obj->drop();
		scripts::throwException("Index out of bounds.");
		return;
	}

	objs.insert(objs.begin() + index, obj);
}

void ObjArray::push_back(Object* obj) {
	objs.push_back(obj);
}

void ObjArray::pop_back() {
	if(objs.size() > 0)
		resize(objs.size() - 1);
}

void ObjArray::sortAsc_bound(unsigned lower, unsigned upper) {
	if(lower > upper || lower >= objs.size() || upper > objs.size()) {
		scripts::throwException("Sorting bounds invalid.");
		return;
	}

	std::sort(objs.begin() + lower, objs.begin() + upper);
}

void ObjArray::sortAsc() {
	sortAsc_bound(0, objs.size());
}

void ObjArray::sortDesc_bound(unsigned lower, unsigned upper) {
	if(lower > upper || lower >= objs.size() || upper > objs.size()) {
		scripts::throwException("Sorting bounds invalid.");
		return;
	}

	std::sort(objs.begin() + lower, objs.begin() + upper,
		[](const Object* a, const Object* b) {
			return b < a;
		} );
}

void ObjArray::sortDesc() {
	sortDesc_bound(0, objs.size());
}

int ObjArray::find(const Object* obj) const {
	if(obj)
		obj->drop();

	for(unsigned i = 0, cnt = objs.size(); i < cnt; ++i)
		if(objs[i] == obj)
			return i;

	return -1;
}

void ObjArray::remove(const Object* obj) {
	if(obj)
		obj->drop();

	for(auto i = objs.begin(), end = objs.end(); i != end; ++i) {
		if(*i == obj) {
			objs.erase(i);
			obj->drop();
			return;
		}
	}
}

int ObjArray::findSorted(const Object* obj) const {
	auto iter = std::lower_bound(objs.begin(), objs.end(), obj);
	if(obj)
		obj->drop();

	if(iter == objs.end() || *iter != obj)
		return -1;
	return iter - objs.begin();
}

void ObjArray::removeSorted(const Object* obj) {
	auto iter = std::lower_bound(objs.begin(), objs.end(), obj);
	if(obj)
		obj->drop();

	if(iter != objs.end() && *iter == obj) {
		obj->drop();
		objs.erase(iter);
	}
}

asITypeInfo* getObjectArrayType() {
	return (asITypeInfo*)asGetActiveContext()->GetEngine()->GetUserData(EDID_objectArray);
}

static Object* objByID(int id) {
	return getObjectByID(id);
}

static Object* createObjByID(int id) {
	if(!devices.network->isClient) {
		scripts::throwException("Invalid function called on server.");
		return 0;
	}
	return getObjectByID(id, true);
}

template<ObjectFlag flag>
static void setObjFlag(Object& obj, bool value) {
	obj.setFlag(flag, value);
}

template<ObjectFlag flag>
static bool getObjFlag(const Object& obj) {
	return obj.getFlag(flag);
}

ObjectGroup* objGroup(Object* obj) {
	if(auto* group = obj->group) {
		group->grab();
		return group;
	}
	else {
		return 0;
	}
}

Object* objGroup_object(ObjectGroup* group, unsigned index) {
	if(index >= group->getObjectCount()) {
		return 0;
	}

	if(Object* obj = group->getObject(index)) {
		obj->grab();
		return obj;
	}
	else {
		return 0;
	}
}

Object* objGroup_owner(ObjectGroup* group) {
	if(Object* obj = group->getOwner()) {
		obj->grab();
		return obj;
	}
	else {
		return 0;
	}
}

Object* objTarget(Object* obj, unsigned num) {
	Object* targ = obj->targets[num % OBJ_TARGETS];
	if(targ)
		targ->grab();
	return targ;
}

bool objVisible(Object* obj) {
	return obj->isVisibleTo(Empire::getPlayerEmpire());
}

bool objKnown(Object* obj) {
	return obj->isKnownTo(Empire::getPlayerEmpire());
}

Empire* objGetOwner(Object* obj) {
	return obj->owner;
}

int objType(Object* obj) {
	return obj->type->id;
}

int findObjectType(const std::string& name) {
	auto* type = getScriptObjectType(name);
	if(type != 0)
		return type->id;
	return -1;
}

const std::string findObjectTypeName(int id) {
	auto* type = getScriptObjectType(id);
	if(type != 0)
		return type->name;
	return "--";
}

bool objIsPhysical(Object* obj) {
	return !obj->getFlag(objNoPhysics);
}

class AsyncTakeover : public ObjectMessage {
	Empire* newOwner;
public:
	AsyncTakeover(Object* obj, Empire* owner)
		: ObjectMessage(obj), newOwner(owner)
	{
		object->grab();
	}

	void process() {
		object->setOwner(newOwner);
	}

	~AsyncTakeover() {
		object->drop();
	}
};


void objSetOwner(Object* obj, Empire* owner) {
	if(obj->lockGroup == nullptr || !obj->isValid())
		return;
	if(!obj->isLocked())
		obj->lockGroup->addMessage(new AsyncTakeover(obj, owner));
	else
		obj->setOwner(owner);
}

class AsyncEffect : public ObjectMessage {
	TimedEffect effect;
public:
	AsyncEffect(Object* obj, const TimedEffect& eff)
		: ObjectMessage(obj), effect(eff)
	{
		object->grab();
	}

	void process() {
		object->addTimedEffect(effect);
	}

	~AsyncEffect() {
		object->drop();
	}
};


void sendTimedEffect(Object* obj, const TimedEffect& eff) {
	if(obj->lockGroup == nullptr || !obj->isValid())
		return;
	if(!obj->isLocked())
		obj->lockGroup->addMessage(new AsyncEffect(obj, eff));
	else
		obj->addTimedEffect(eff);
}

static void createObjectLock(ObjectLock* lock, Object* obj, bool priority) {
	new(lock) ObjectLock(obj, priority);
	if(obj)
		obj->drop();
}

static void unlockObjectLock(ObjectLock* lock) {
	lock->~ObjectLock();
}

static void createWaitSafe_e(bool* mem) {
	*mem = getSafeCallWait();
	setSafeCallWait(true);
}

static void createWaitSafe(bool* mem, bool wait) {
	*mem = getSafeCallWait();
	setSafeCallWait(wait);
}

static void destroyWaitSafe(bool* mem) {
	setSafeCallWait(*mem);
}

static double err = 0;
static double& quadrantHP(Blueprint& bp, unsigned index) {
	if(index >= 4)
		return err;
	return bp.quadrantHP[index];
}

static Blueprint::HexStatus* bpHexStatus(Blueprint& bp, unsigned x, unsigned y) {
	if(!bp.design)
		return 0;

	if(x >= bp.design->grid.width || y >= bp.design->grid.height)
		return 0;

	return bp.getHexStatus(x, y);
}

static Blueprint::HexStatus* bpHexStatusInd(Blueprint& bp, unsigned index) {
	if(!bp.design)
		return 0;

	if(index >= bp.design->usedHexCount)
		return 0;

	return bp.getHexStatus(index);
}

static Blueprint::SysStatus* bpSysStatus(Blueprint& bp, unsigned index) {
	if(!bp.design)
		return 0;

	if(index >= bp.design->subsystems.size())
		return 0;

	return bp.getSysStatus(index);
}

static Blueprint::SysStatus* bpHexSysStatus(Blueprint& bp, unsigned x, unsigned y) {
	if(!bp.design)
		return 0;

	if(x >= bp.design->grid.width || y >= bp.design->grid.height)
		return 0;

	return bp.getSysStatus(x, y);
}

static int* bpInt(Blueprint& bp, const Subsystem* sys, unsigned index) {
	if(!sys) {
		scripts::throwException("Invalid subsystem for state access.");
		return 0;
	}
	unsigned abs = index + sys->stateOffset;
	if(index >= sys->type->states.size() || abs >= bp.design->stateCount) {
		scripts::throwException("Subsystem state index out of range.");
		return 0;
	}

	return &bp.states[abs].integer;
}

static double* bpDouble(Blueprint& bp, const Subsystem* sys, unsigned index) {
	if(!sys) {
		scripts::throwException("Invalid subsystem for state access.");
		return 0;
	}
	unsigned abs = index + sys->stateOffset;
	if(index >= sys->type->states.size() || abs >= bp.design->stateCount) {
		scripts::throwException("Subsystem state index out of range.");
		return 0;
	}

	return &bp.states[abs].decimal;
}

static bool* bpBool(Blueprint& bp, const Subsystem* sys, unsigned index) {
	if(!sys) {
		scripts::throwException("Invalid subsystem for state access.");
		return 0;
	}
	unsigned abs = index + sys->stateOffset;
	if(index >= sys->type->states.size() || abs >= bp.design->stateCount) {
		scripts::throwException("Subsystem state index out of range.");
		return 0;
	}

	return &bp.states[abs].boolean;
}

class GetObjNode : public ObjectMessage {
	scene::Node*& node;
	bool& received;
public:
	GetObjNode(Object* obj, scene::Node*& nodePtr, bool& result)
		: ObjectMessage(obj), node(nodePtr), received(result)
	{
		object->grab();
		received = false;
	}
	
	void process() {
		node = object->node;
		if(node)
			node->grab();
		received = true;
		object->drop();
	}
};

static scene::Node* objGetNode(Object* obj) {
	LockGroup* activeGroup = getActiveLockGroup();
	if(obj->lockGroup == activeGroup) {
		scene::Node* node = obj->node;
		if(node)
			node->grab();
		return node;
	}
	else {
		scene::Node* pNode;
		bool received = false;

		obj->lockGroup->addMessage(new GetObjNode(obj, pNode, received));
	
		while(!received) {
			threads::sleep(0);
			if(activeGroup)
				activeGroup->processMessages(4);
			else
				tickRandomMessages(10);
		}

		return pNode;
	}
}

static vec3d objNodePos(Object* obj) {
	if(scene::Node* node = obj->node)
		return node->abs_position;
	else
		return obj->position;
}

static quaterniond objNodeRotation(Object* obj) {
	if(scene::Node* node = obj->node)
		return node->abs_rotation;
	else
		return obj->rotation;
}

class GetObjName : public ObjectMessage {
	std::string& name;
	bool& received;
public:
	GetObjName(Object* obj, std::string& Name, bool& result)
		: ObjectMessage(obj), name(Name), received(result)
	{
		object->grab();
		received = false;
	}
	
	void process() {
		name = object->name;
		received = true;
		object->drop();
	}
};

static std::string objGetName(Object* obj) {
	LockGroup* activeGroup = getActiveLockGroup();
	if(obj->lockGroup == activeGroup) {
		return obj->name;
	}
	else {
		std::string name;
		bool received = false;

		obj->lockGroup->addMessage(new GetObjName(obj, name, received));
	
		while(!received) {
			threads::sleep(0);
			if(activeGroup)
				activeGroup->processMessages(4);
			else
				tickRandomMessages(10);
		}

		return name;
	}
}

class SetObjName : public ObjectMessage {
	std::string* name;
public:
	SetObjName(Object* obj, std::string* pName)
		: ObjectMessage(obj), name(pName)
	{
		object->grab();
	}

	~SetObjName() {
		delete name;
	}
	
	void process() {
		object->name = *name;
		object->drop();
	}
};

static void objSetName(Object* obj, const std::string& name) {
	LockGroup* activeGroup = getActiveLockGroup();
	if(obj->lockGroup == activeGroup)
		obj->name = name;
	else
		obj->lockGroup->addMessage(new SetObjName(obj, new std::string(name)));
}

class SendObjDamage : public ObjectMessage {
	DamageEvent event;
	double position;
	vec2d direction;
public:
	SendObjDamage(Object* obj, const DamageEvent& evt, double position, const vec2d& direction)
		: ObjectMessage(obj), event(evt), position(position), direction(direction)
	{
		object->grab();
	}
	
	void process() {
		object->damage(event, position, direction);
	}
};

static void sendObjDamage(Object* obj, DamageEvent& evt, double position, const vec2d& direction) {
	if(obj == getActiveObject())
		obj->damage(evt, position, direction);
	else
		obj->lockGroup->addMessage(new SendObjDamage(obj, evt, position, direction));
}

static ObjArray* findInBox(const vec3d& minBound, const vec3d& maxBound, unsigned mask) {
	ObjArray* results = new ObjArray();
	results->reserve(100);

	AABBoxd box(minBound, maxBound); box.fix();

	devices.physics->findInBox(box, [results](const PhysicsItem& item) {
		Object* object = item.object;
		if(object) {
			object->grab();
			results->push_back(object);
		}
	}, mask == 0 ? ~0 : mask);

	return results;
}

static Object* trace(const line3dd& ray, unsigned mask) {
	Object* obj = nullptr;
	double closest;
	vec3d dir = ray.getDirection();

	devices.physics->findInBox(ray, [&](const PhysicsItem& item) {
		Object* const o = item.object;
		if(!o->isValid())
			return;

		const auto pt = ray.getClosestPoint(o->position, false);
		const double rSq = o->radius * o->radius;
		const double dSq = pt.distanceToSQ(o->position);
		if(dSq > rSq)
			return;

		if(!obj) {
			o->grab();
			obj = o;
			closest = dir.dot(pt - dir * sqrt(rSq - dSq));
			return;
		}

		double dO = dir.dot(pt - ray.start);
		if(dO - o->radius < closest) {
			dO = dir.dot(pt - dir * sqrt(rSq - dSq));
			if(dO < closest) {
				o->grab();
				obj->drop();
				obj = o;
				closest = dO;
			}
		}
	}, mask ? mask : ~0);

	return obj;
}

void finalizeObject(Object* obj) {
	if(obj->getFlag(objStopTicking) == true) {
		obj->postInit();
		obj->setFlag(objStopTicking, false);
	}
}

void loadBlueprint(Blueprint& bp, Object* obj, SaveMessage& msg) {
	try {
		bp.load(obj, msg);
	}
	catch(SaveFileError err) {
		throwException(err.text);
	}
}

static void createLockedHandle(LockedHandle<Object>* mem) {
	new(mem) LockedHandle<Object>();
}

static void createLockedHandle_v(LockedHandle<Object>* mem, Object* obj) {
	new(mem) LockedHandle<Object>(obj);
	if(obj)
		obj->drop();
}

static void createLockedHandle_c(LockedHandle<Object>* mem, LockedHandle<Object>& other) {
	new(mem) LockedHandle<Object>(other);
}

static void destroyLockedHandle(LockedHandle<Object>* mem) {
	mem->~LockedHandle();
}

static void loadObjectType(asIScriptGeneric* f) {
	Object** handle = (Object**)f->GetArgAddress(0);
	loadObject(*(SaveMessage*)f->GetObject(), handle);

	if(*handle) {
		if((*handle)->type != f->GetFunction()->GetUserData()) {
			(*handle)->drop();
			*handle = nullptr;
		}
	}

	f->SetReturnAddress(f->GetObject());
}

static void readObjectType(asIScriptGeneric* f) {
	Object** handle = (Object**)f->GetArgAddress(0);
	Object* prev = *handle;
	*handle = readObject(*(net::Message*)f->GetObject());

	if(*handle) {
		if((*handle)->type != f->GetFunction()->GetUserData()) {
			(*handle)->drop();
			*handle = nullptr;
		}
	}

	if(prev)
		prev->drop();
	f->SetReturnAddress(f->GetObject());
}

static asIScriptFunction* hexLineFunc;
static void runHexLine(Blueprint* bp, Object* obj, asIScriptObject* cb, const vec2d& direction) {
	const Design* design = bp->design;
	if(!design || (direction.x == 0.0 && direction.y == 0.0))
		return;

	//Find a position for this direction that ensures something gets damaged
	unsigned count = (unsigned)design->hexes.size();
	unsigned index = randomi(0, count-1);

	unsigned w = design->grid.width;
	unsigned h = design->grid.height;

	vec2d dirline = direction.normalized((double)(w+h) * 2.0);

	vec2u goal(-1, -1);
	for(unsigned i = 0; i < count; ++i, index = (index+1) % count) {
		goal = design->hexes[index];
		Blueprint::HexStatus* status = bp->getHexStatus(goal.x, goal.y);
		if(status && status->hp != 0)
			break;
	}

	if(!design->grid.valid(goal))
		return;

	vec2u hex = goal;

	//We found a hex that can take damage, now run
	//the line through here.

	vec2d effPos = design->grid.getEffectivePosition(hex);
	vec2d startPos = effPos + dirline;
	vec2d endPos = effPos - dirline;

	//Advance toward the edge in the direction of the source
	while(hex.x > 0 && hex.x < w-1 && hex.y > 0 && hex.y < h-1) {
		vec2d diff = design->grid.getEffectivePosition(hex);
		diff.y = -diff.y;
		diff = startPos - diff;
		
		double dir = diff.radians();
		HexGridAdjacency adj = HexGrid<>::AdjacencyFromRadians(dir);

		if(!design->grid.advance(hex, adj))
			break;
	}

	bool reachedTarget = false;

	//Run forward from the starting position to the end position
	unsigned n = 0;
	for(; n < 1000; ++n) {
		if(hexLineFunc && design->grid.valid(hex) && design->grid[hex] >= 0) {
			bool cntnue = true;
			auto cl = devices.scripts.server->call(hexLineFunc);
			cl.setObject(cb);
			cl.push(&hex);
			cl.call(cntnue);
			if(!cntnue)
				break;
		}

		if(!reachedTarget && hex == goal)
			reachedTarget = true;

		//Find next hex
		vec2d diff = design->grid.getEffectivePosition(hex);
		if(reachedTarget)
			diff = endPos - diff;
		else
			diff = effPos - diff;
		diff.y = -diff.y;

		double dir = diff.radians();
		auto adj = HexGrid<>::AdjacencyFromRadians(dir);

		if(!design->grid.advance(hex, adj))
			break;
	}
}

class ObjectBucket : public LinkContainer<Object*,10,LCB_Unordered> {
public:
	mutable threads::atomic_int refs;
	bool inGC;

	ObjectBucket(asITypeInfo* type) : inGC(false), refs(1) {
	}

	~ObjectBucket() {
		// We know nobody references us anymore, so there's no way we're being
		// queried right now, so all these releases should be fine.
		void* pool = start;
		while(pool) {
			for(int i = 0; i < 10; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.data != nullptr && elem.filled) {
					elem.data->drop();
					elem.data = nullptr;
				}
			}
			pool = getHeader(pool).next;
		}
	}

	void grab() const { ++refs; }
	void drop() const { if(!--refs) delete this; }

	bool has(Object* obj) const {
		return contains(obj);
	}

	void insert(Object* obj) {
		if(obj == nullptr)
		{
			return;
		}

		obj->grab();
		add(obj);
	}

	void eraseAll(Object* obj, asITypeInfo* type) {
		void* pool = start;
		while(pool) {
			for(int i = 0; i < 10; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.data != nullptr && elem.filled) {
					delayObjectRelease(elem.data);
					elem.data = nullptr;
					elem.filled = false;
				}
			}
			pool = getHeader(pool).next;
		}
	}

	void erase(Object* obj, asITypeInfo* type) {
		int removed = removeAll(obj);

		// Object releases are delayed until GC time, so we cannot possibly be
		// getting queried for a dead object.
		if(removed != 0 && obj) {
			for(int i = 0; i < removed; ++i)
				delayObjectRelease(obj);
		}
	}

	Object* opInd(unsigned int index) {
		Object** ptr = getAt(index);
		if(ptr) {
			Object* obj = *ptr;
			if(obj)
				obj->grab();
			return obj;
		}
		return nullptr;
	}
};

void ob_factory(asIScriptGeneric* f) {
	auto* type = (asITypeInfo*)f->GetFunction()->GetUserData();
	auto* bucket = new ObjectBucket(type);
	*(ObjectBucket**)f->GetAddressOfReturnLocation() = bucket;
}

double objGetStatDouble(Object& obj, uint64_t id) {
	return obj.stats.getDouble(id);
}

uint64_t objGetStatInt(Object& obj, uint64_t id) {
	return obj.stats.get(id);
}

uint64_t objGetStatId_index(Object& obj, unsigned int index) {
	return obj.stats.getKeyAtIndex(index);
}

uint64_t objGetStatInt_index(Object& obj, unsigned int index) {
	return obj.stats.getAtIndex(index);
}

unsigned int objGetStatCount(Object& obj) {
	return obj.stats.size();
}

enum ObjectStatMode {
	OSM_Set,
	OSM_Add,
	OSM_Multiply,
};

class ModObjStat : public ObjectMessage {
public:
	bool isDouble;
	uint64_t id;
	union {
		double doubleValue;
		int64_t value;
	};
	ObjectStatMode mode;
	union {
		double dirtyResolutionDouble;
		int64_t dirtyResolution;
	};

	ModObjStat(Object* obj)
		: ObjectMessage(obj)
	{
		object->grab();
	}

	static void doModInt(Object* obj, uint64_t id, ObjectStatMode mode, int64_t value, int64_t dirtyRes) {
		switch(mode)
		{
			case OSM_Set:
				obj->stats.set(id, value, dirtyRes);
			break;
			case OSM_Add:
				obj->stats.set(id, obj->stats.get(id) + value, dirtyRes);
			break;
			case OSM_Multiply:
				obj->stats.set(id, obj->stats.get(id) * value, dirtyRes);
			break;
		}
	}

	static void doModDouble(Object* obj, uint64_t id, ObjectStatMode mode, double value, double dirtyRes) {
		switch(mode)
		{
			case OSM_Set:
				obj->stats.setDouble(id, value, dirtyRes);
			break;
			case OSM_Add:
				obj->stats.setDouble(id, obj->stats.getDouble(id) + value, dirtyRes);
			break;
			case OSM_Multiply:
				obj->stats.setDouble(id, obj->stats.getDouble(id) * value, dirtyRes);
			break;
		}
	}

	void process() {
		if(isDouble)
			doModDouble(object, id, mode, doubleValue, dirtyResolutionDouble);
		else
			doModInt(object, id, mode, value, dirtyResolution);
	}

	~ModObjStat() {
		object->drop();
	}
};


void objModStatDouble(Object* obj, uint64_t id, ObjectStatMode mode, double value, double dirtyResolution) {
	if(obj->lockGroup == nullptr || !obj->isValid())
		return;
	if(!obj->isLocked() || Object::GALAXY_CREATION) {
		auto* msg = new ModObjStat(obj);
		msg->isDouble = true;
		msg->id = id;
		msg->doubleValue = value;
		msg->mode = mode;
		msg->dirtyResolutionDouble = value;
		obj->lockGroup->addMessage(msg);
	}
	else {
		ModObjStat::doModDouble(obj, id, mode, value, dirtyResolution);
	}
}

void objModStatInt(Object* obj, uint64_t id, ObjectStatMode mode, int64_t value, int64_t dirtyResolution) {
	if(obj->lockGroup == nullptr || !obj->isValid())
		return;
	if(!obj->isLocked() || Object::GALAXY_CREATION) {
		auto* msg = new ModObjStat(obj);
		msg->isDouble = false;
		msg->id = id;
		msg->value = value;
		msg->mode = mode;
		msg->dirtyResolution = value;
		obj->lockGroup->addMessage(msg);
	}
	else {
		ModObjStat::doModInt(obj, id, mode, value, dirtyResolution);
	}
}

void bindObject(ClassBind& object, ScriptObjectType* type, bool server) {
	//The basic Object array will have already been registered
	if(type != nullptr)
		RegisterObjectArray(object.name);

	object.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(Object,grab));
	object.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(Object,drop));
	
#if defined(_DEBUG) && !defined(DOCUMENT_API)
	object.addMember("const int refs", offsetof(Object,references));
	//object.addMember("IAnyObject@ script", offsetof(Object,script));
#endif

	if(!server) {
		object.addMember("const bool alwaysVisible", offsetof(Object,alwaysVisible))
			doc("Whether the object can be seen from any distance.");

		object.addMember("const float sightRange", offsetof(Object,sightRange))
			doc("Radius around which the object can see other objects.");

		object.addMember("const float seeableRange", offsetof(Object,seeableRange))
			doc("Radius around which this object can be seen by other objects.");

		object.addMember("const vec3d position", offsetof(Object,position))
			doc("Current position in space.");

		object.addMember("const vec3d velocity", offsetof(Object,velocity))
			doc("Current momentary velocity.");

		object.addMember("const vec3d acceleration", offsetof(Object,acceleration))
			doc("Current acceleration vector.");

		object.addMember("const quaterniond rotation", offsetof(Object,rotation))
			doc("Rotation/facing expressed as a quaternion.");

		object.addMember("const double radius", offsetof(Object,radius))
			doc("Radius of the object's bounding sphere and size of its visuals.");

		object.addExternMethod("Empire@ get_owner() const", asFUNCTION(objGetOwner))
			doc("", "The empire that owns this object.");
	}
	else {
		object.addMember("bool alwaysVisible", offsetof(Object,alwaysVisible))
			doc("Whether the object can be seen from any distance.");

		object.addMember("uint visibleMask", offsetof(Object,visibleMask))
			doc("Empire mask of which empires can see this object.");

		object.addMember("uint memoryMask", offsetof(Object,sightedMask))
			doc("Empire mask of which empires have any memory of this object.");

		object.addMember("float sightRange", offsetof(Object,sightRange))
			doc("Radius around which the object can see other objects.");

		object.addMember("float seeableRange", offsetof(Object,seeableRange))
			doc("Radius around which the object can be seen by other objects.");

		object.addMember("vec3d position", offsetof(Object,position))
			doc("Current position in space.");

		object.addMember("vec3d velocity", offsetof(Object,velocity))
			doc("Current momentary velocity.");

		object.addMember("vec3d acceleration", offsetof(Object,acceleration))
			doc("Current acceleration vector.");

		object.addMember("uint donatedVision", offsetof(Object,donatedVision))
			doc("Mask of empires that this object will become visible to.");

		object.addMember("quaterniond rotation", offsetof(Object,rotation))
			doc("Rotation/facing expressed as a quaternion.");

		object.addMember("double radius", offsetof(Object,radius))
			doc("Radius of the object's bounding sphere and size of its visuals.");

		object.addExternMethod("void set_name(const string &in Name)", asFUNCTION(objSetName))
			doc("", "New name for the object.");

		object.addExternMethod("Empire@ get_owner() const", asFUNCTION(objGetOwner))
			doc("", "The empire that owns this object.");

		object.addExternMethod("void set_owner(Empire@ emp)", asFUNCTION(objSetOwner))
			doc("Set a new owner for the object.", "Empire that should own the object.");

		object.addExternMethod("void finalizeCreation()", asFUNCTION(finalizeObject))
			doc("Finalize the creation of this object. Should only be called on"
				" objects that were created with delayedCreation set to true.");
	}

	object.addMember("const double lastTick", offsetof(Object,lastTick))
		doc("Game time of the last time the object ticked.");

	object.addExternMethod("string get_name() const", asFUNCTION(objGetName))
		doc("", "Name of the object.");

	object.addMember("const int id", offsetof(Object,id))
		doc("Unique identifier referring to this object.");

	object.addMethod("bool get_valid() const", asMETHOD(Object, isValid))
		doc("", "Whether the object is valid and not a zombie. "
				"Zombies are objects that have already been destroyed "
				"but are awaiting disposal.");

	object.addExternMethod("bool get_engaged() const", asFUNCTION(getObjFlag<objEngaged>))
		doc("", "Whether the object is engaged.");

	object.addExternMethod("bool get_named() const", asFUNCTION(getObjFlag<objNamed>))
		doc("", "Whether the object has been named..");

	object.addExternMethod("bool get_inCombat() const", asFUNCTION(getObjFlag<objCombat>))
		doc("", "Whether the object is considered in combat.");

	object.addMethod("bool isFocus() const", asMETHOD(Object, isFocus))
		doc("", "Whether the object is a focus object. "
				"Focus objects have higher priority for interpolation and syncing.");

	object.addMethod("void focus()", asMETHOD(Object, focus))
		doc("Mark the object as a focus object. "
			"Focus decays and should be set periodically on accessed objects.");

	object.addMethod("bool get_initialized() const", asMETHOD(Object, isInitialized))
		doc("", "Whether the object has been fully initialized "
				"in its creation step.");

	object.addExternMethod("ObjectType get_type() const", asFUNCTION(objType))
		doc("", "The type of this object.");

	object.addExternMethod("bool get_selected() const", asFUNCTION(getObjFlag<objSelected>))
		doc("", "Whether the object is currently selected.");

	object.addExternMethod("void set_selected(bool value)", asFUNCTION(setObjFlag<objSelected>))
		doc("", "Whether the object is currently selected.");

	object.addExternMethod("bool get_isPhysical() const", asFUNCTION(objIsPhysical))
		doc("", "Whether the object is a physical object.");

	object.addExternMethod("bool get_notDamageable() const", asFUNCTION(getObjFlag<objNoDamage>))
		doc("", "Whether the object cannot be damaged at all by projectiles.");

	if(server) {
		object.addMethod("void wake()", asMETHOD(Object, wake))
			doc("Tells the processing threads to tick the object next time (ignoring requested timeout)");
		object.addMethod("void sleep(double seconds)", asMETHOD(Object, sleep))
			doc("Adds a number of seconds to the object's requested timeout.", "");

		object.addExternMethod("bool get_memorable() const", asFUNCTION(getObjFlag<objMemorable>))
			doc("", "Whether the object should have past vision state tracked.");

		object.addExternMethod("void set_noCollide(bool value)", asFUNCTION(setObjFlag<objNoCollide>))
			doc("Set whether the object should not be collided with (enforced by scripts).", "");

		object.addExternMethod("void set_notDamageable(bool value)", asFUNCTION(setObjFlag<objNoDamage>))
			doc("Set whether the object cannot be damaged at all by projectiles.", "");

		object.addExternMethod("bool get_noCollide() const", asFUNCTION(getObjFlag<objNoCollide>))
			doc("", "Whether the object should not be collided with.");

		object.addExternMethod("void set_engaged(bool value)", asFUNCTION(setObjFlag<objEngaged>))
			doc("Set whether the object is engaged.", "");

		object.addExternMethod("void set_named(bool value)", asFUNCTION(setObjFlag<objNamed>))
			doc("Set whether the object is named.", "");

		object.addExternMethod("void set_inCombat(bool value)", asFUNCTION(setObjFlag<objCombat>))
			doc("Set whether the object is considered in combat.", "");

		object.addExternMethod("void wait()", asFUNCTION(objectWait))
			doc("Waits for all asynchronous messages to finish on this object. This is considered a relocking operation.");

		object.addMethod("void destroy()", asMETHOD(Object, flagDestroy))
			doc("Flag the object for destruction and eventual disposal.");

		object.addExternMethod("bool get_destroying()", asFUNCTION(getObjFlag<objQueueDestroy>))
			doc("Whether the object is waiting to be destroyed.", "");

		object.addExternMethod("void damage(DamageEvent& evt, double position, const vec2d&in direction)", asFUNCTION(sendObjDamage))
			doc("Deal damage to the object from a particular direction.",
					"Event relating information about the damage dealt.",
					"Position between 0 and 1 on the side that is hit.",
					"Direction vector towards the object of the damage.");

		object.addMethod("void repair(double amount)", asMETHOD(Object, repair));

		object.addExternMethod("void addTimedEffect(const TimedEffect &in eff)", asFUNCTION(sendTimedEffect))
			doc("Add an effect to the object that executes then finishes after a particular amount of time.",
				"The effect to add.");

		object.addMethod("bool isVisibleTo(Empire& emp) const", asMETHOD(Object,isVisibleTo))
			doc("Returns true if the specified empire can see the object.", "Empire to check vision for.", "");

		object.addMethod("bool isKnownTo(Empire& emp) const", asMETHOD(Object,isKnownTo))
			doc("Returns true if the specified empire has ever seen the object.", "Empire to check vision for.", "");

		object.addExternMethod("Object@ get_targets(uint index) const", asFUNCTION(objTarget))
			doc("Retrieve one of the targeting system targets the object is holding.",
				"Index of the object to retrieve (maximum TARGET_COUNT).",
				"Held object by the targetting system.");
	}
	else {
		object.addExternMethod("bool get_visible() const", asFUNCTION(objVisible))
			doc("Returns true if the player empire can see this object.", "");

		object.addExternMethod("bool get_known() const", asFUNCTION(objKnown))
			doc("Returns true if the player empire has ever seen this object.", "");
	}

	object.addExternMethod("ObjectGroup@ get_group()", asFUNCTION(objGroup))
		doc("", "The object group associated with the object.");

	object.addExternMethod("const ObjectGroup@ get_group() const", asFUNCTION(objGroup))
		doc("", "The object group associated with the object.");

	object.addExternMethod("Node@ getNode() const", asFUNCTION(objGetNode))
		doc("Returns the node associated with the object. Asynchronous.", "");

	object.addExternMethod("uint getStatCount() const", asFUNCTION(objGetStatCount));
	object.addExternMethod("int64 getStatValueByIndex(uint index) const", asFUNCTION(objGetStatInt_index));
	object.addExternMethod("uint64 getStatIdByIndex(uint index) const", asFUNCTION(objGetStatId_index));

	object.addExternMethod("double getStatDouble(uint64 id) const", asFUNCTION(objGetStatDouble));
	object.addExternMethod("int64 getStatInt(uint64 id) const", asFUNCTION(objGetStatInt));

	object.addExternMethod("void modStatDouble(uint64 id, ObjectStatMode mode, double value, double dirtyResolution = 0.0) const", asFUNCTION(objModStatDouble));
	object.addExternMethod("void modStatInt(uint64 id, ObjectStatMode mode, int64 value, int64 dirtyResolution = 0) const", asFUNCTION(objModStatInt));

	if(!server) {
		object.addExternMethod("vec3d get_node_position()", asFUNCTION(objNodePos))
			doc("", "The absolute physical position of the object's graphics node this frame."
					" Can be different from the object position due to graphics interpolation.");

		object.addExternMethod("quaterniond get_node_rotation()", asFUNCTION(objNodeRotation))
			doc("", "The absolute physical rotation of the object's graphics node this frame."
					" Can be different from the object rotation due to graphics interpolation.");
	}

	//Locked handle classes
	std::string obj_name(object.name);
	std::string handle_name("locked_");
	handle_name += obj_name;

	if(server)
		object.addFactory(format("$1@ f(const ObjectDesc& desc)", obj_name).c_str(),
				asFUNCTION(makeObject));

	ClassBind lh(handle_name.c_str(), asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CDK, sizeof(LockedHandle<Object>));
	lh.addConstructor("void f()", asFUNCTION(createLockedHandle));
	lh.addConstructor(format("void f($1@ obj)", obj_name).c_str(), asFUNCTION(createLockedHandle_v));
	lh.addConstructor(format("void f(const $1& other)", handle_name).c_str(), asFUNCTION(createLockedHandle_c));
	lh.addDestructor("void f()", asFUNCTION(destroyLockedHandle));

	lh.addMethod(format("$1@ get() const", obj_name).c_str(), asMETHOD(LockedHandle<Object>, get));
	lh.addMethod(format("$1@ get_safe() const", obj_name).c_str(), asMETHOD(LockedHandle<Object>, get_safe));
	lh.addMethod(format("void set($1@ value)", obj_name).c_str(), asMETHOD(LockedHandle<Object>, set_withref));

	//Bucket class
	{
		std::string bucket_name;
		bucket_name += obj_name;
		bucket_name += "Bucket";

		ClassBind ob(bucket_name.c_str(), asOBJ_REF);
		auto* scriptType = ob.getType();
		ob.setReferenceFuncs(asMETHOD(ObjectBucket,grab), asMETHOD(ObjectBucket,drop));
		ob.addGenericFactory(format("$1@ f()", bucket_name.c_str()).c_str(), asFUNCTION(ob_factory), scriptType);

		ob.addMethod("uint get_length() const", asMETHOD(ObjectBucket, size));
		ob.addMethod(format("$1@ get_opIndex(uint index) const", obj_name.c_str()).c_str(), asMETHOD(ObjectBucket, opInd));

		ob.addMethod("void clear()", asMETHOD(ObjectBucket, eraseAll));
		ob.addMethod(format("void add($1& obj)", obj_name).c_str(), asMETHOD(ObjectBucket, insert));
		ob.addMethod(format("void remove($1& obj)", obj_name).c_str(), asMETHOD(ObjectBucket, erase));
		ob.addMethod(format("bool contains($1& obj) const", obj_name).c_str(), asMETHOD(ObjectBucket, has));
	}

	//Reading and writing to messages
	if(type) {
		ClassBind savefile("SaveFile");
		savefile.addExternMethod(format("SaveFile& opShl($1@+)", obj_name).c_str(), asFUNCTION(saveObject));
		savefile.addGenericMethod(format("SaveFile& opShr($1@&)", obj_name).c_str(), asFUNCTION(loadObjectType), type);

		ClassBind message("Message");
		message.addExternMethod(format("Message& opShl($1@+)", obj_name).c_str(), asFUNCTION(writeObjectScr));
		message.addGenericMethod(format("Message& opShr($1@&)", obj_name).c_str(), asFUNCTION(readObjectType), type);
	}
}

void RegisterObjectArray(const std::string& objName) {
	std::string arrName = "array<"; arrName += objName + "@>";
	ClassBind arr(arrName.c_str(), asOBJ_REF);
	
	arr.setReferenceFuncs(asMETHOD(ObjArray,grab), asMETHOD(ObjArray,drop));
	
	arr.addFactory(format("$1@ f()", arrName).c_str(), asFUNCTION(ObjArray::create));
	arr.addFactory(format("$1@ f(uint count)", arrName).c_str(), asFUNCTION(ObjArray::create_n));

	arr.addMethod(format("$1& opAssign(const $1&)", arrName).c_str(), asMETHOD(ObjArray,operator=));
	
	arr.addMethod(format("$1@& opIndex(uint)", objName).c_str(), asMETHOD(ObjArray,operator[]));
	arr.addMethod(format("$1@ opIndex(uint) const", objName).c_str(), asMETHOD(ObjArray,index_value));
	arr.addMethod(format("$1@& get_last()", objName).c_str(), asMETHOD(ObjArray,last));
	arr.addMethod(format("$1@ get_last() const", objName).c_str(), asMETHOD(ObjArray,last_value));
	
	arr.addMethod(format("void insertAt(uint, $1@)", objName).c_str(), asMETHOD(ObjArray, insert));
	arr.addMethod(format("void insertLast($1@)", objName).c_str(), asMETHOD(ObjArray, push_back));
	arr.addMethod(format("void remove(const $1@)", objName).c_str(), asMETHOD(ObjArray, remove));
	arr.addMethod(       "void removeLast()", asMETHOD(ObjArray, pop_back));
	arr.addMethod(       "void removeAt(uint)", asMETHOD(ObjArray, erase));
	arr.addMethod(format("int find(const $1@) const", objName).c_str(), asMETHOD(ObjArray, find));
	
	arr.addMethod("bool isEmpty() const", asMETHOD(ObjArray, empty));
	arr.addMethod("uint length() const", asMETHOD(ObjArray, size));
	arr.addMethod("uint get_length() const", asMETHOD(ObjArray, size));
	arr.addMethod("void set_length(uint)", asMETHOD(ObjArray, resize));
	arr.addMethod("void resize(uint)", asMETHOD(ObjArray, resize));
	arr.addMethod("void reserve(uint)", asMETHOD(ObjArray, reserve));
	
	arr.addMethod("void sortAsc()", asMETHOD(ObjArray, sortAsc));
	arr.addMethod("void sortAsc(uint, uint)", asMETHOD(ObjArray, sortAsc_bound));
	arr.addMethod("void sortDesc()", asMETHOD(ObjArray, sortDesc));
	arr.addMethod("void sortDesc(uint, uint)", asMETHOD(ObjArray, sortDesc_bound));
	arr.addMethod(format("int findSorted(const $1@) const", objName).c_str(), asMETHOD(ObjArray, findSorted));
	arr.addMethod(format("void removeSorted(const $1@)", objName).c_str(), asMETHOD(ObjArray, removeSorted));
}

void RegisterObjectBinds(bool declarations, bool server, bool shadow) {
	if(declarations) {
		ClassBind object("Object", asOBJ_REF);
		ClassBind objectGroup("ObjectGroup", asOBJ_REF);
		ClassBind hs("HexStatus", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind ss("SysStatus", asOBJ_REF | asOBJ_NOCOUNT, 0);
		ClassBind bp("Blueprint", asOBJ_REF | asOBJ_NOCOUNT, 0);

		EnumBind objLimits("ObjectType");

		RegisterObjectArray("Object");
		return;
	}

	if(void* objArray = getEngine()->GetTypeInfoById(getEngine()->GetTypeIdByDecl("array<Object@>")))
		getEngine()->SetUserData(objArray, EDID_objectArray);

	EnumBind statMode("ObjectStatMode");
	statMode["OSM_Set"] = OSM_Set;
	statMode["OSM_Add"] = OSM_Add;
	statMode["OSM_Multiply"] = OSM_Multiply;

	EnumBind objLimits("ObjectLimits");
	objLimits["TARGET_COUNT"] = OBJ_TARGETS;

	EnumBind objFlags("ObjectFlags");
	objFlags["objValid"] = objValid;
	objFlags["objStopTicking"] = objStopTicking;
	objFlags["objWakeUp"] = objWakeUp;
	objFlags["objUninitialized"] = objUninitialized;
	objFlags["objSendDelta"] = objSendDelta;
	objFlags["objFocus"] = objFocus;
	objFlags["objSelected"] = objSelected;
	objFlags["objEngaged"] = objEngaged;
	objFlags["objNoPhysics"] = objNoPhysics;
	objFlags["objMemorable"] = objMemorable;
	objFlags["objNoDamage"] = objNoDamage;
	objFlags["objNoCollide"] = objNoCollide;

	ClassBind objectGroup("ObjectGroup");
	objectGroup.addMember("quaterniond formationFacing", offsetof(ObjectGroup,formationFacing));
	objectGroup.setReferenceFuncs(asMETHOD(ObjectGroup,grab), asMETHOD(ObjectGroup,drop));
	objectGroup.addExternMethod("Object@ get_objects(uint index)", asFUNCTION(objGroup_object));
	objectGroup.addExternMethod("const Object@ get_objects(uint index) const", asFUNCTION(objGroup_object));
	objectGroup.addExternMethod("Object@ get_owner()", asFUNCTION(objGroup_owner));
	objectGroup.addExternMethod("const Object@ get_owner() const", asFUNCTION(objGroup_owner));
	objectGroup.addMethod("uint get_objectCount() const", asMETHOD(ObjectGroup,getObjectCount));
	objectGroup.addMethod("vec3d get_center() const", asMETHOD(ObjectGroup,getCenter));
	objectGroup.addMethod("uint get_maxObjectCount() const", asMETHOD(ObjectGroup,getMaxObjectCount))
		doc("Returns the maximum number of objects ever in this group (Usually the original number the group was created with).", "");

	ClassBind object("Object");
	classdoc(object, "Abstract class for all game objects, implemented "
		"by various subclasses using different states and components. "
		"Note that not all methods listed here are accessible on all objects, so "
		"before using a component call, check whether the object has the "
		"right component for that call using the has[Component] accessors.");

	bindObject(object, nullptr, server);
	RegisterObjectComponentWrappers(object, server);

	bind("Object@ getObjectByID(int id)", asFUNCTION(objByID))
		doc("Returns the Object associated with the ID.", "Unique identifier of the object to retrieve.",
			"Null if the object doesn't exist.");

	if(server)
		bind("Object@ getOrCreateObject(int id)", asFUNCTION(createObjByID))
			doc("Get the object belonging to the identifier, or create a dummy object"
				" with that id for later initialization. Should only be used for"
				" synchronization of objects in multiplayer or during save game loading.",
				  "Unique identifier of the object.",
				  "Object with that identifier.");

	//Blueprint data
	EnumBind hf("HexFlags");
	classdoc(hf, "Bitmask flags used in individual hexagon status on blueprints.");
	hf["HF_Active"] = HF_Active;
	hf["HF_Destroyed"] = HF_Destroyed;
	hf["HF_NoHP"] = HF_NoHP;
	hf["HF_Gone"] = HF_Gone;
	hf["HF_NoRepair"] = HF_NoRepair;

	ClassBind hs("HexStatus");
	classdoc(hs, "Indication of the status of an individual hexagon on a blueprint.");
	hs.addMember("uint8 flags", offsetof(Blueprint::HexStatus, flags))
		doc("Flags mask, see HexFlags enumeration.");
	hs.addMember("uint8 hp", offsetof(Blueprint::HexStatus, hp))
		doc("Percentage hitpoints of the hexagon from 0 to 255.");

	ClassBind ss("SysStatus");
	classdoc(ss, "Indication of the status of a subsystem on a blueprint.");
	ss.addMember("uint16 workingHexes", offsetof(Blueprint::SysStatus, workingHexes))
		doc("Amount of hexes of the subsystem that are still active and not destroyed.");
	ss.addMember("EffectStatus status", offsetof(Blueprint::SysStatus, status))
		doc("Status of the subsystem's condition.");

	ClassBind bp("Blueprint");
	classdoc(bp, "A physical instance of a design. A blueprint belongs to one ship and"
			" holds all the information about the internals of that particular ship.");

	bp.addMember("double currentHP", offsetof(Blueprint, currentHP))
		doc("The current hp of the ship.");
	bp.addMember("double topHP", offsetof(Blueprint, quadrantHP[0]));
	bp.addMember("double rightHP", offsetof(Blueprint, quadrantHP[1]));
	bp.addMember("double bottomHP", offsetof(Blueprint, quadrantHP[2]));
	bp.addMember("double leftHP", offsetof(Blueprint, quadrantHP[3]));
	bp.addExternMethod("double& quadrantHP(uint index)", asFUNCTION(quadrantHP));

	bp.addMember("bool holdFire", offsetof(Blueprint, holdFire))
		doc("Whether the ship should hold its weapons fire.");
	bp.addMember("float hpFactor", offsetof(Blueprint, hpFactor))
		doc("A multiplier to the design's health on every hex.");
	bp.addMember("float removedHP", offsetof(Blueprint, removedHP))
		doc("The amount of HP removed from the ship.");
	bp.addMember("double shipEffectiveness", offsetof(Blueprint, shipEffectiveness))
		doc("The effectiveness of the ship as a whole.");
	bp.addMember("uint destroyedHexes", offsetof(Blueprint, destroyedHexes))
		doc("The amount of hexes that have been destroyed.");
	bp.addMember("const Design@ design", offsetof(Blueprint, design))
		doc("The design that this particular blueprint is based on.");

	bp.addMember("vec2i repairingHex", offsetof(Blueprint, repairingHex))
		doc("The hexagon that is currently being repaired.");
	
	if(server) {
		bp.addMember("uint statusID", offsetof(Blueprint, statusID))
			doc("An ID that increments whenever a change to the blueprint occurs.");

		bp.addMember("bool delta", offsetof(Blueprint, hpDelta))
			doc("Flag for whether the blueprint should be delta synced.");

		bp.addMethod("float tick(Object&, double)", asMETHOD(Blueprint, think))
			doc("Tick function to handle the blueprint, should be called from the"
				" object script handler's tick.", "Object this blueprint is for.",
				"Time passed since last tick.", "Suggestion for the amount of"
				" time to wait until the next tick.");

		bp.addMethod("void destroy(Object&)", asMETHOD(Blueprint, destroy))
			doc("Call when the object holding the blueprint is destroyed.",
				"Object this blueprint is for.");

		bp.addMethod("void ownerChange(Object&, Empire@, Empire@)", asMETHOD(Blueprint, ownerChange))
			doc("Call when the blueprint changes owners.", "Object this blueprint is for.",
				"Previous empire.", "New Empire.");

		bp.addExternMethod("HexStatus@ getHexStatus(uint x, uint y)", asFUNCTION(bpHexStatus))
			doc("", "X coordinate of the hex.", "Y coordinate of the hex.",
				"Current status of the hex on this blueprint.");

		bp.addExternMethod("SysStatus@ getSysStatus(uint index)", asFUNCTION(bpSysStatus))
			doc("", "Index of the subsystem", "Current status of the subsystem.");

		bp.addExternMethod("SysStatus@ getSysStatus(uint x, uint y)", asFUNCTION(bpHexSysStatus))
			doc("", "X coordinate of the hex.", "Y coordinate of the hex.",
				"Current status of the subsystem the hex belongs to.");
	}

	bp.addMethod("bool hasTagActive(SubsystemTag tag)", asMETHOD(Blueprint, hasTagActive))
		doc("", "Tag to check for.", "Whether any subsystems with this tag are present and active.");

	bp.addMethod("double getTagEfficiency(SubsystemTag tag, bool ignoreInactive = true)", asMETHOD(Blueprint, getTagEfficiency))
		doc("Calculate the total efficiency of subsystems with a particular tag.",
				"Tag to check for.", "Whether to ignore remaining efficiency on subsystems that are disabled.",
				"Total efficiency.");

	bp.addMethod("double getEfficiencySum(SubsystemVariable var, SubsystemTag tag = ST_NULL, bool ignoreInactive = true)", asMETHOD(Blueprint, getEfficiencySum))
		doc("Calculate the total value of a subsystem variable as affected by subsystem efficiency.",
				"Variable to total.", "Tag to filter subsystems by.", "Whether to ignore remaining efficiency on subsystems that are disabled.",
				"Total value.");

	bp.addMethod("double getEfficiencyFactor(SubsystemVariable var, SubsystemTag tag = ST_NULL, bool ignoreInactive = true)", asMETHOD(Blueprint, getEfficiencyFactor))
		doc("Calculate the total percentage efficiency with respect to a variable.",
				"Variable to use.", "Tag to filter subsystems by.", "Whether to ignore remaining efficiency on subsystems that are disabled.",
				"Efficiency factor..");

	bp.addMethod("vec3d getOptimalFacing(SubsystemVariable var, SubsystemTag tag = ST_NULL, bool ignoreInactive = true)", asMETHOD(Blueprint, getOptimalFacing))
		doc("Calculate the optimal facing so that effectors in this blueprint can fire with optimal value for the passed variable.",
				"Variable to use.", "Tag to filter subsystems by.", "Whether to ignore remaining efficiency on subsystems that are disabled.",
				"Optimal facing.");

	bp.addMethod("Object@ getCombatTarget()", asMETHOD(Blueprint, getCombatTarget))
		doc("Find a target this ship is firing on.", "");

	bp.addExternMethod("const HexStatus@ getHexStatus(uint index) const", asFUNCTION(bpHexStatusInd))
		doc("", "Hex index.",
			"Current status of the hex on this blueprint.");

	bp.addExternMethod("const HexStatus@ getHexStatus(uint x, uint y) const", asFUNCTION(bpHexStatus))
		doc("", "X coordinate of the hex.", "Y coordinate of the hex.",
			"Current status of the hex on this blueprint.");

	bp.addExternMethod("const SysStatus@ getSysStatus(uint index) const", asFUNCTION(bpSysStatus))
		doc("", "X coordinate of the hex.", "Y coordinate of the hex.",
			"Current status of the subsystem the hex belongs to.");

	bp.addExternMethod("const SysStatus@ getSysStatus(uint x, uint y) const", asFUNCTION(bpHexSysStatus))
			doc("", "X coordinate of the hex.", "Y coordinate of the hex.",
				"Current status of the subsystem the hex belongs to.");

	bp.addMethod("bool canTarget(Object& obj, Object& target)",
			asMETHOD(Blueprint, canTarget))
		doc("Check whether the effectors in this blueprint can target an object.",
			"Object this blueprint is for.", "Object to check targeting for.",
			"Whether the object can be targeted.");

	bp.addMethod("bool doesAutoTarget(Object& obj, Object& target)",
			asMETHOD(Blueprint, doesAutoTarget))
		doc("Check whether the effectors in this blueprint can auto-target an object.",
			"Object this blueprint is for.", "Object to check auto-targeting for.",
			"Whether the object can be auto-targeted.");

	if(server) {
		bp.addMethod("void save(Object& obj, SaveFile& file)", asMETHOD(Blueprint, save));
		bp.addExternMethod("void load(Object& obj, SaveFile& file)", asFUNCTION(loadBlueprint));

		bp.addMethod("void target(Object& obj, Object& target, uint flags = 0)",
				asMETHODPR(Blueprint, target, (Object*,Object*,TargetFlags), void))
			doc("Set all effectors in this blueprint to target a particular object.",
				"Object this blueprint is for.", "Object to target with all effectors.",
				"Flags for the effector target.");

		bp.addMethod("void target(Object& obj, uint efftrIndex, Object& target, uint flags = 0)",
				asMETHODPR(Blueprint, target, (Object*,unsigned,Object*,TargetFlags), void))
			doc("Set an effector in this blueprint to target a particular object.",
				"Object this blueprint is for.", "Index of the effector to target for.",
				"Object to target with the effector.", "Flags for the effector target.");

		bp.addMethod("void target(Object& obj, const Subsystem@ sys, Object& target, uint flags = 0)",
				asMETHODPR(Blueprint, target, (Object*,const Subsystem*,Object*,TargetFlags), void))
			doc("Set all effectors in a subsystem to target a particular object.",
				"Object this blueprint is for.", "Subsystem to set targets for.",
				"Object to target with all effectors.", "Flags for the effector target.");

		bp.addMethod("void clearTracking(Object& obj)",
				asMETHODPR(Blueprint, clearTracking, (Object*), void))
			doc("Clear the turret tracking for all effectors, letting them retrack fast.",
				"Object this blueprint is for.");

		bp.addMethod("void sendDetails(Object& obj, Message& msg) const", asMETHOD(Blueprint, sendDetails))
			doc("For networking: sends the details of this blueprint through the message.",
				"Object this blueprint is for.", "Message to add details to.");

		bp.addMethod("void recvDetails(Object& obj, Message& msg)", asMETHOD(Blueprint, recvDetails))
			doc("For networking: read the details of this blueprint from a message.",
				"Object this blueprint is for.", "Message to read details from.");

		bp.addMethod("bool sendDelta(Object& obj, Message& msg) const", asMETHOD(Blueprint, sendDelta))
			doc("For networking: sends a delta of this blueprint through the message.",
				"Object this blueprint is for.", "Message to add delta to.",
				"Whether a delta was needed/written.");

		bp.addMethod("void recvDelta(Object& obj, Message& msg)", asMETHOD(Blueprint, recvDelta))
			doc("For networking: read the delta of this blueprint from a message.",
				"Object this blueprint is for.", "Message to read delta from.");

		bp.addMethod("void create(Object& obj, const Design@ design)", asMETHOD(Blueprint, create))
		doc("Initialize this blueprint.", "Object this blueprint is for.",
				"Design to initialize the blueprint with.");

		bp.addMethod("void start(Object& obj, bool fromRetrofit = false)", asMETHOD(Blueprint, start))
		doc("Start the blueprint's effects.", "Object this blueprint is for.",
				"Whether this was started from a retrofit event.");

		bp.addMethod("void retrofit(Object& obj, const Design@ toDesign)", asMETHOD(Blueprint, retrofit))
		doc("Retrofit the blueprint to a new design.", "Object this blueprint is for.",
				"Design to retrofit to.");

		bp.addMethod("any@+ getHookData(uint index)", asMETHOD(Blueprint, getHookData))
		doc("Get data storage for a hook index.", "Hook index", "Data for that hook.");

		bp.addExternMethod("int& integer(const Subsystem@ sys, uint num)", asFUNCTION(bpInt))
			doc("", "Subsystem to retrieve the state for.", "Index of the state to get.",
				"Integer state value for the subsystem.");

		bp.addExternMethod("double& decimal(const Subsystem@ sys, uint num)", asFUNCTION(bpDouble))
			doc("", "Subsystem to retrieve the state for.", "Index of the state to get.",
				"Decimal state value for the subsystem.");

		bp.addExternMethod("bool& boolean(const Subsystem@ sys, uint num)", asFUNCTION(bpBool))
			doc("", "Subsystem to retrieve the state for.", "Index of the state to get.",
				"Boolean state value for the subsystem.");

		bp.addMethod("void damage(Object& obj, DamageEvent& evt, const vec2d&in direction)",
			asMETHODPR(Blueprint, damage, (Object*,DamageEvent&,const vec2d&), void))
			doc("Handle damage to the blueprint from a particular direction.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Direction vector towards the object of the damage.");

		bp.addMethod("void damage(Object& obj, DamageEvent& evt, double position, const vec2d&in direction)",
			asMETHODPR(Blueprint, damage, (Object*,DamageEvent&,double,const vec2d&), void))
			doc("Handle damage to the blueprint from a particular direction.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Position between 0 and 1 on the side that is hit.",
					"Direction vector towards the object of the damage.");

		bp.addMethod("void damage(Object& obj, DamageEvent& evt, const vec2u&in position)",
			asMETHODPR(Blueprint, damage, (Object*,DamageEvent&,const vec2u&), void))
			doc("Handle damage to a particular hex on the blueprint.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Hexagon position to deal damage to.");

		bp.addMethod("void damage(Object& obj, DamageEvent& evt, const vec2u&in position, HexGridAdjacency direction, bool runGlobal = true)",
			asMETHODPR(Blueprint, damage, (Object*,DamageEvent&,const vec2u&,HexGridAdjacency,bool), void))
			doc("Create a line of damage beginning at a particular hex and continuing in a straight line.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Hexagon position to start the damage line at.",
					"Direction to continue the damage line in.",
					"Whether to allow global damage reactors to respond to the damage.");

		bp.addMethod("bool globalDamage(Object& obj, DamageEvent& evt)",
			asMETHODPR(Blueprint, globalDamage, (Object*,DamageEvent&), bool))
			doc("Trigger blueprint global damage events only.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Whether the global damage events canceled the damage altogether.");

		bp.addMethod("void damageHex(Object& obj, DamageEvent& evt, const vec2u&in position, bool runGlobal = true)",
			asMETHODPR(Blueprint, damage, (Object*,DamageEvent&,const vec2u&,bool), void))
			doc("Create a damage event against a particular hex.",
					"Object the blueprint is for.",
					"Event relating information about the damage dealt.",
					"Hexagon position to deal the damage at.",
					"Whether to allow global damage reactors to respond to the damage.");

		bp.addMethod("double repair(Object& obj, double amount)",
			asMETHODPR(Blueprint, repair, (Object*,double), double))
			doc("Add generic repair to the blueprint.",
					"Object the blueprint is for.",
					"Amount of hp to repair.",
					"Amount of repair that was left over after this call.");

		bp.addMethod("double repair(Object& obj, const vec2u&in position, double amount)",
			asMETHODPR(Blueprint, repair, (Object*,const vec2u&,double), double))
			doc("Add repair to a particular hex on the blueprint.",
					"Object the blueprint is for.",
					"Position on the blueprint to repair.",
					"Amount of hp to repair.",
					"Amount of repair that was left over after this call.");

		if(!shadow) {
			InterfaceBind line("BlueprintHexLine");
			line.addMethod("bool process(const vec2u& pos)", &hexLineFunc);
			bp.addExternMethod("void runHexLine(Object& obj, BlueprintHexLine& line, const vec2d& direction)", asFUNCTION(runHexLine));
		}
	}

	//Objects can be locked easily with raii
	ClassBind lock("ObjectLock", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CD, sizeof(ObjectLock));
	lock.addConstructor("void f(const Object@ obj, bool priority = false)", asFUNCTION(createObjectLock));
	lock.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(unlockObjectLock));
	lock.addMethod("void release()", asMETHOD(ObjectLock, release));

	//Structure for setting whether to wait for safe calls to finish
	ClassBind waitsafe("WaitForSafeCalls", asOBJ_VALUE | asOBJ_APP_CLASS_CD, sizeof(bool));
	waitsafe.addConstructor("void f()", asFUNCTION(createWaitSafe_e));
	waitsafe.addConstructor("void f(bool wait)", asFUNCTION(createWaitSafe));
	waitsafe.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(destroyWaitSafe));

	bind("bool getSafeCallWait()", asFUNCTION(getSafeCallWait));
	bind("void setSafeCallWait(bool value)", asFUNCTION(setSafeCallWait));
	bind("int getObjectTypeId(const string& type)", asFUNCTION(findObjectType));
	bind("string getObjectTypeName(int id)", asFUNCTION(findObjectTypeName));

	//Physics searches
	bind("array<Object@>@ findInBox(const vec3d &in min, const vec3d &in max, uint ownerFilter = 0)", asFUNCTION(findInBox))
		doc("Returns an array of objects within the specified region.", "Minimum bound of the region.", "Maximum bound of the region.", "Optional owner filter mask. Bit 1 filters for objects not owned by a player.", "");

	bind("Object@ trace(const line3dd &in ray, uint ownerFilter = 0)", asFUNCTION(trace))
		doc("Returns the first object located along a line.", "Line to trace along.", "Optional owner filter mask. Bit 1 filters for objects not owned by a player.", "First object (if any) hit by the trace.");
}

};
