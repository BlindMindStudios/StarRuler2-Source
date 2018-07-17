#pragma once
#include "aabbox.h"
#include "util/refcount.h"
#include <vector>
#include <functional>

enum PhysItemType {
	PIT_Object = 0x01,
	PIT_Node = 0x02,
	//A group is both the type of PIT_Group, and the type of objects in the group
	PIT_Group = 0x80,
};

class Object;
struct PhysicsGrid;
struct PhysicsItem;
struct PhysicsGroup;
class SaveFile;

namespace scene {
	class Node;
};

namespace net {
	struct Message;
};

struct PhysicsItem {
	AABBoxd bound;
	union {
		Object* object;
		scene::Node* node;
		PhysicsGroup* group;
	};
	unsigned maskID;
	PhysItemType type;
	PhysicsGrid* gridLocation;
};

struct PhysicsGroup {
	unsigned itemCount;
	PhysicsItem* items;
};

struct PhysBisect {
	std::vector<PhysicsItem*> items;
	PhysBisect *a, *b, *parent;
	unsigned childrenA, childrenB;
	bool xSplit;
	double dimSplit, fuzz;
	unsigned depth;

	PhysBisect() : a(0), b(0), parent(0), depth(0), childrenA(0), childrenB(0), xSplit(true) {}

	inline int classify(const AABBoxd& box) const {
		if(xSplit) {
			if(box.maximum.x < dimSplit - fuzz)
				return -1;
			if(box.minimum.x > dimSplit + fuzz)
				return 1;
			return 0;
		}
		else {
			if(box.maximum.z < dimSplit - fuzz)
				return -1;
			if(box.minimum.z > dimSplit + fuzz)
				return 1;
			return 0;
		}
	}

	int classifyContainer(const AABBoxd& box) const {
		if(xSplit) {
			double center = (box.minimum.x + box.maximum.x) * 0.5;
			if(center >= dimSplit && box.minimum.x > dimSplit - fuzz)
				return 1;
			else if(center < dimSplit && box.maximum.x < dimSplit + fuzz)
				return -1;
			return 0;
		}
		else {
			double center = (box.minimum.z + box.maximum.z) * 0.5;
			if(center >= dimSplit && box.minimum.z > dimSplit - fuzz)
				return 1;
			else if(center < dimSplit && box.maximum.z < dimSplit + fuzz)
				return -1;
			return 0;
		}
	}

	void findInBox(const AABBoxd& box, const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask) const;

	void split();
	void fuse();
	void fuse(std::vector<PhysicsItem*>& into);
};

struct PhysicsGrid {
	PhysBisect groups[32];
	mutable threads::ReadWriteMutex mutex;
	AABBoxd bound, fuzzBound;
	unsigned itemCount;

	void removeItem(PhysicsItem* item);
	void addItem(PhysicsItem* item);
	void updateItem(PhysicsItem* item, const AABBoxd& newBound);
	bool empty() const;
};

class PhysicsWorld : public AtomicRefCounted {
	//Physical space that items exist withing
	PhysicsGrid* grid;
	//Catch-all for items that do not exist within the grid, or can't fit inside the grid
	PhysicsGrid outside;

	//Access mutex
	threads::ReadWriteMutex mutex;

	//Size of a grid square
	double gridSize, halfGridSize;
	//Grid fuzz margin
	double gridFuzz;
	//Number of grid squares on a side
	unsigned gridCount;
	
	unsigned getBox(double x) const;
	unsigned getLowerBound(double x) const;
	unsigned getUpperBound(double x) const;
	
	void findInBoxInZone(const PhysicsGrid& zone, const AABBoxd& box, const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask);
public:
	PhysicsWorld(double GridSize = 3000.0, double GridFuzz = 350.0, unsigned GridCount = 60);
	~PhysicsWorld();

	//Calls <callback> for each of the PhysicsItems within the box
	//Optionally filters by owner of the item (Mask 1 permits unowned objects)
	void findInBox(const AABBoxd& box, const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask = 0xffffffff);

	void updateItem(PhysicsItem& item, const AABBoxd& newBox);
	PhysicsItem* registerItem(const AABBoxd& bounds, Object* obj);
	PhysicsItem* registerItem(const AABBoxd& bounds, scene::Node* node);
	void registerItem(PhysicsItem& item);
	void unregisterItem(PhysicsItem& item);

	void writeSetup(net::Message& msg);
	void writeSetup(SaveFile& file);
	static PhysicsWorld* fromMessage(net::Message& msg);
	static PhysicsWorld* fromSave(SaveFile& file);
};
