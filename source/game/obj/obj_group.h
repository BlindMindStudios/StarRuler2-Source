#pragma once
#include "util/refcount.h"
#include "quaternion.h"

class Object;
class SaveFile;
struct PhysicsItem;

class ObjectGroup : public AtomicRefCounted {
	PhysicsItem* physItem;
	unsigned objectCount, origObjectCount;
	Object** objects;
	Object* owner;
public:
	int id;
	quaterniond formationFacing;

	ObjectGroup(unsigned count, int id = -1);

	bool postLoad();
	void postInit();
	ObjectGroup(SaveFile& file);
	void save(SaveFile& file);
	~ObjectGroup();

	unsigned getObjectCount() const;
	unsigned getMaxObjectCount() const;
	Object* getObject(unsigned index);
	const Object* getObject(unsigned index) const;
	void setObject(unsigned index, Object* obj);
	unsigned setNextObject(Object* obj);
	Object* getOwner();
	void setOwner(Object* obj);
	vec3d getCenter() const;

	PhysicsItem* getPhysicsItem();
	PhysicsItem* getPhysicsItem(unsigned index) const;

	//Removes the owner; Returns true if the group is now empty
	bool removeOwner();
	void update();

	//Note: grabs the group before returning it
	static ObjectGroup* byID(int id);
};
