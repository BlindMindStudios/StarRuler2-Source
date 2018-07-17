#include "obj_group.h"
#include "object.h"
#include "physics/physics_world.h"
#include "main/references.h"
#include "main/logging.h"
#include "util/save_file.h"
#include <map>

threads::ReadWriteMutex groupIDsLock;
threads::atomic_int nextGroupID(1);
std::map<int,ObjectGroup*> groups;

void registerObjectGroup(ObjectGroup* group, int id = -1) {
	groupIDsLock.writeLock();

	group->grab();

	if(id == -1) {
		group->id = nextGroupID++;
	}
	else {
		group->id = id;
		nextGroupID = id+1;
	}

	groups[group->id] = group;
	groupIDsLock.release();
}

void unregisterObjectGroup(ObjectGroup* group) {
	groupIDsLock.writeLock();

	groups.erase(group->id);
	group->drop();

	groupIDsLock.release();
}

ObjectGroup* ObjectGroup::byID(int id) {
	ObjectGroup* group = 0;

	groupIDsLock.readLock();
	auto iter = groups.find(id);
	if(iter != groups.end())
		group = iter->second;

	if(group)
		group->grab();
	groupIDsLock.release();
	return group;
}

ObjectGroup::ObjectGroup(unsigned count, int id) : objectCount(count), origObjectCount(count), objects(new Object*[count]), physItem(new PhysicsItem), owner(0) {
	PhysicsGroup* physGroup = new PhysicsGroup;
	physGroup->itemCount = count;
	physGroup->items = new PhysicsItem[count];

	physItem->type = PhysItemType(PIT_Group | PIT_Object);
	physItem->group = physGroup;

	memset(objects, 0, sizeof(Object*) * count);
	registerObjectGroup(this, id);
}

bool ObjectGroup::postLoad() {
	//Remove invalid objects
	unsigned off = 0;
	for(unsigned i = 0; i < objectCount; ++i) {
		Object* obj = objects[i];
		if(!obj->isValid() || !obj->isInitialized()) {
			physItem->group->items[i].object = 0;
			++off;
		}
		else {
			if(off != 0)
				objects[i-off] = obj;
		}
		obj->drop();
	}
	objectCount -= off;

	//Check if the group should die
	if(objectCount == 0) {
		owner = nullptr;
		return false;
	}

	//Check if the owner is valid
	if(!owner->isValid() || !owner->isInitialized())
		owner = objects[0];
	return true;
}

void ObjectGroup::postInit() {
	//Update physics item
	physItem->bound.reset(objects[0]->physItem->bound);
	for(unsigned i = 1; i < objectCount; ++i)
		physItem->bound.addBox(objects[i]->physItem->bound);

	devices.physics->registerItem(*physItem);
}

ObjectGroup::~ObjectGroup() {
	devices.physics->unregisterItem(*physItem);
	delete[] physItem->group->items;
	delete physItem;
	delete[] objects;
}

unsigned ObjectGroup::getObjectCount() const {
	return objectCount;
}

unsigned ObjectGroup::getMaxObjectCount() const {
	return origObjectCount;
}

Object* ObjectGroup::getObject(unsigned index) {
	return objects[index];
}

const Object* ObjectGroup::getObject(unsigned index) const {
	return objects[index];
}

void ObjectGroup::setObject(unsigned index, Object* obj) {
	objects[index] = obj;
	if(index == 0 && owner == 0)
		owner = obj;
	if(obj)
		obj->grab();
}

unsigned ObjectGroup::setNextObject(Object* obj) {
	for(unsigned i = 0; i < objectCount; ++i) {
		if(objects[i] != 0)
			continue;
		objects[i] = obj;
		if(i == 0 && owner == nullptr)
			owner = obj;
		return i;
	}
	return 0;
}

Object* ObjectGroup::getOwner() {
	return owner;
}

void ObjectGroup::setOwner(Object* obj) {
	owner = obj;
}

vec3d ObjectGroup::getCenter() const {
	return physItem->bound.getCenter();
}

PhysicsItem* ObjectGroup::getPhysicsItem() {
	return physItem;
}

PhysicsItem* ObjectGroup::getPhysicsItem(unsigned index) const {
	return &physItem->group->items[index];
}

bool ObjectGroup::removeOwner() {
	Object* newOwner = 0;
	double nearest = 9.0e40;

	//Move objects down to the lower indices, and find the nearest object to the previous owner to be the new owner
	unsigned j = 0;
	for(unsigned i = 0; i < objectCount; ++i) {
		Object*& obj = objects[i];

		if(!obj) {
			++j;
		}
		else if(obj->isValid() && obj != owner) {
			double dist = owner->position.distanceToSQ(obj->position);
			if(dist < nearest) {
				nearest = dist;
				newOwner = obj;
			}

			if(j != i) {
				objects[j] = obj;
				obj = 0;
			}
			++j;
		}
	}

	objectCount = j;
	if(objectCount != 0) {
		if(newOwner)
			owner = newOwner;
		else
			owner = objects[0];
		return false;
	}
	else {
		owner = 0;
		unregisterObjectGroup(this);
		drop();
		return true;
	}
}

void ObjectGroup::update() {
	AABBoxd box;
	box.reset(owner->physItem->bound);

	unsigned j = 1;
	for(unsigned i = 1; i < objectCount; ++i) {
		if(!objects[i]) {
			++j;
		} else if(objects[i]->isValid()) {
			box.addBox(objects[i]->physItem->bound);
			if(j != i) {
				objects[j] = objects[i];
				objects[i] = 0;
			}
			++j;
		}
	}

	objectCount = j;
	devices.physics->updateItem(*physItem, box);
}

ObjectGroup::ObjectGroup(SaveFile& file) {
	file >> id >> objectCount >> formationFacing;
	objects = new Object*[objectCount];

	for(unsigned i = 0; i < objectCount; ++i)
		file >> objects[i];

	owner = objects[(unsigned short)file];

	PhysicsGroup* physGroup = new PhysicsGroup;
	physGroup->itemCount = objectCount;
	physGroup->items = new PhysicsItem[objectCount];

	physItem = new PhysicsItem;
	physItem->type = PhysItemType(PIT_Group | PIT_Object);
	physItem->group = physGroup;

	registerObjectGroup(this);
}

void ObjectGroup::save(SaveFile& file) {
	file << id;
	file << objectCount;
	file << formationFacing;

	unsigned ownerIndex = 0;
	for(unsigned i = 0; i < objectCount; ++i) {
		file << objects[i];
		if(objects[i] == owner)
			ownerIndex = i;
	}
	file << (unsigned short)ownerIndex;
}
