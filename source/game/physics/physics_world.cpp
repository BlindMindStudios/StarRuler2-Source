#include "physics_world.h"
#include <vec2.h>
#include <math.h>
#include "threads.h"
#include "obj/object.h"
#include "empire.h"
#include "network/message.h"
#include "util/save_file.h"
#include <assert.h>

#include "main/references.h"
#include "main/logging.h"

#include "compat/intrin.h"

#define SPLIT_COUNT 16
#define REBALANCE_RATIO 4
#define MAX_DEPTH 8

PhysicsWorld::PhysicsWorld(double GridSize, double GridFuzz, unsigned GridCount)
	: gridSize(GridSize), halfGridSize(GridSize * 0.5), gridFuzz(GridFuzz), gridCount(GridCount)
{
	while(gridCount > 200) {
		gridCount = (gridCount + 1)/2;
		gridSize *= 2.0;
		halfGridSize *= 2.0;
	}

	outside.bound.reset(AABBoxd::fromCircle(vec3d(),1.0e12));
	outside.fuzzBound = outside.bound;
	outside.itemCount = 0;

	grid = new PhysicsGrid[gridCount*gridCount];
	for(unsigned x = 0; x < gridCount; ++x) {
		for(unsigned y = 0; y < gridCount; ++y) {
			auto& zone = grid[x*gridCount + y];
			zone.itemCount = 0;

			for(unsigned i = 0; i < 32; ++i)
				zone.groups[i].fuzz = gridFuzz;

			vec2d pos = vec2d(vec2i(x,y) - vec2i(gridCount / 2)) * gridSize;
			
			zone.bound.reset(vec3d(pos.x,-100000.0,pos.y));
			zone.bound.addPoint(vec3d(pos.x+gridSize,100000.0,pos.y+gridSize));
			
			zone.fuzzBound.reset(zone.bound.minimum - vec3d(gridFuzz));
			zone.fuzzBound.addPoint(zone.bound.maximum + vec3d(gridFuzz));
		}
	}
}

PhysicsWorld::~PhysicsWorld() {
	delete[] grid;
}

//Gets the grid index for x
unsigned PhysicsWorld::getBox(double x) const {
	int index = int(floor(x / gridSize)) + int(gridCount / 2);
	if(index <= 0)
		return 0;
	if(index >= (int)gridCount-1)
		return gridCount-1;
	return index;
}
	
//Gets the smallest grid index that could contain x
unsigned PhysicsWorld::getLowerBound(double x) const {
	double dIndex = floor(x / gridSize);
	double pct = (x / gridSize) - dIndex;

	int index = int(dIndex) + int(gridCount / 2);
	if(pct < gridFuzz / gridSize)
		index -= 1;

	if(index <= 0)
		return 0;
	if(index >= (int)gridCount-1)
		return gridCount-1;
	return index;
}

//Gets the largest grid index that could contain x
unsigned PhysicsWorld::getUpperBound(double x) const {
	double dIndex = floor(x / gridSize);
	double pct = (x / gridSize) - dIndex;

	int index = int(dIndex) + int(gridCount / 2);
	if(pct > 1.0 - (gridFuzz / gridSize))
		index += 1;

	if(index <= 0)
		return 0;
	if(index >= (int)gridCount-1)
		return gridCount-1;
	return index;
}

void PhysBisect::findInBox(const AABBoxd& box, const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask) const {
	if(!items.empty()) {
		auto* pItems = &items.front();
		for(auto* end = pItems + items.size(), *next = pItems + 1; pItems != end; pItems = next, ++next) {
			auto& item = **pItems;
			//Prefetch all 3 cache lines that the next item's bound occupies
			if(next != end) {
				auto* pNextItem = *next;
				PREFETCH((const char*)pNextItem + offsetof(PhysicsItem,bound));
				PREFETCH((const char*)pNextItem + offsetof(PhysicsItem,bound) + (2 * sizeof(double)));
				PREFETCH((const char*)pNextItem + offsetof(PhysicsItem,bound) + (4 * sizeof(double)));
			}
			if(box.overlaps(item.bound))
				callback(item);
		}
	}

	if(a) {
		int dir = classify(box);

		if(dir != 1)
			a->findInBox(box, callback, ownerMask);
		if(dir != -1)
			b->findInBox(box, callback, ownerMask);
	}
}

void PhysBisect::fuse() {
	if(!a)
		return;

	a->fuse(items);
	b->fuse(items);
	a = b = 0;
	childrenA = childrenB = 0;
}

void PhysBisect::fuse(std::vector<PhysicsItem*>& into) {
	if(a) {
		a->fuse(into);
		b->fuse(into);
	}

	into.insert(into.end(), items.begin(), items.end());
	delete this;
}

void PhysBisect::split() {
	if(depth == MAX_DEPTH)
		return;
	a = new PhysBisect();
	b = new PhysBisect();

	a->fuzz = b->fuzz = fuzz * 0.5;
	a->depth = b->depth = depth + 1;

	a->parent = b->parent = this;
	a->xSplit = b->xSplit = !xSplit;

	if(xSplit) {
		//Estimate a median value to split around
		double values[10];
		if(items.size() <= 10) {
			for(unsigned i = 0, cnt = (unsigned)items.size(); i < cnt; ++i) {
				auto* item = items[i];
				values[i] = (item->bound.minimum.x + item->bound.maximum.x) * 0.5;
			}
			std::sort(values, values + items.size());
			dimSplit = values[items.size() / 2];
		}
		else {
			unsigned step = (unsigned)items.size() / 10;
			for(unsigned i = 0; i < 10; ++i) {
				auto* item = items[i * step];
				values[i] = (item->bound.minimum.x + item->bound.maximum.x) * 0.5;
			}
			std::sort(values, values + 10);
			dimSplit = values[5];
		}

		for(int i = (int)items.size() - 1; i >= 0; --i) {
			PhysicsItem* item = items[i];
			int location = classifyContainer(item->bound);
			if(location == -1) {
				a->items.push_back(item);
				items.erase(items.begin() + i);
				childrenA++;
			}
			else if(location == 1) {
				b->items.push_back(item);
				items.erase(items.begin() + i);
				childrenB++;
			}
		}
	}
	else {
		double values[10];
		if(items.size() <= 10) {
			for(unsigned i = 0, cnt = (unsigned)items.size(); i < cnt; ++i) {
				auto* item = items[i];
				values[i] = (item->bound.minimum.z + item->bound.maximum.z) * 0.5;
			}
			std::sort(values, values + items.size());
			dimSplit = values[items.size() / 2];
		}
		else {
			unsigned step = (unsigned)items.size() / 10;
			for(unsigned i = 0; i < 10; ++i) {
				auto* item = items[i * step];
				values[i] = (item->bound.minimum.z + item->bound.maximum.z) * 0.5;
			}
			std::sort(values, values + 10);
			dimSplit = values[5];
		}

		for(int i = (int)items.size() - 1; i >= 0; --i) {
			PhysicsItem* item = items[i];
			int location = classifyContainer(item->bound);
			if(location == -1) {
				a->items.push_back(item);
				items.erase(items.begin() + i);
				childrenA++;
			}
			else if(location == 1) {
				b->items.push_back(item);
				items.erase(items.begin() + i);
				childrenB++;
			}
		}
	}

	if(a->items.size() > SPLIT_COUNT)
		a->split();
	if(b->items.size() > SPLIT_COUNT)
		b->split();
}

void PhysicsWorld::findInBoxInZone(const PhysicsGrid& zone, const AABBoxd& box,
 const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask) {
	threads::ReadLock lock(zone.mutex);
	//if(ownerMask == ~0u) {
		//findInBoxInZone(zone, box, callback);
	//	zone.findInBox(box, callback, ~0);
	//	return;
	//}

	for(unsigned i = 0; i < 32; ++i)
		if(ownerMask & (1 << i))
			zone.groups[i].findInBox(box, callback, 0);
}

void PhysicsWorld::findInBox(const AABBoxd& box, const std::function<void(const PhysicsItem&)>& callback, unsigned ownerMask) {
	//double start = devices.driver->getAccurateTime();
	unsigned fromX = getLowerBound(box.minimum.x), toX = getUpperBound(box.maximum.x);
	unsigned fromY = getLowerBound(box.minimum.z), toY = getUpperBound(box.maximum.z);

	for(unsigned x = fromX; x <= toX; ++x) {
		for(unsigned y = fromY; y <= toY; ++y) {
			const PhysicsGrid& zone = grid[x * gridCount + y];
			if(!zone.empty() && box.overlaps(zone.fuzzBound))
				findInBoxInZone(zone, box, callback, ownerMask);
		}
	}

	if(!outside.empty())
		findInBoxInZone(outside, box, callback, ownerMask);
	//double end = devices.driver->getAccurateTime();
	//error("%d\n", (int)((end - start) * 1e6));
}

bool PhysicsGrid::empty() const {
	return itemCount == 0;
}

void PhysicsGrid::removeItem(PhysicsItem* item) {
	mutex.writeLock();
	itemCount -= 1;
	PhysBisect* bisect = &groups[item->maskID];
	while(bisect->a) {
		int location = bisect->classifyContainer(item->bound);
		if(location == -1) {
			bisect->childrenA--;
			bisect = bisect->a;
		}
		else if(location == 1) {
			bisect->childrenB--;
			bisect = bisect->b;
		}
		else
			break;
	}

	bool itemRemoved = false;

	for(auto i = bisect->items.begin(), end = bisect->items.end(); i != end; ++i) {
		if((*i) == item) {
			itemRemoved = true;
			bisect->items.erase(i);

			while(bisect->items.empty() && bisect->parent && bisect->a == 0) {
				auto parent = bisect->parent;
				parent->fuse();
				if(parent->items.size() > SPLIT_COUNT)
					parent->split();
				bisect = parent;
			}

			break;
		}
	}

	mutex.release();

	if(!itemRemoved)
		throw "Unable to locate physics item";
}

void PhysicsGrid::addItem(PhysicsItem* item) {
	mutex.writeLock();
	itemCount += 1;
	PhysBisect* bisect = &groups[item->maskID];
	while(bisect->a) {
		int location = bisect->classifyContainer(item->bound);
		if(location == -1) {
			bisect->childrenA++;
			bisect = bisect->a;
		}
		else if(location == 1) {
			bisect->childrenB++;
			bisect = bisect->b;
		}
		else
			break;
	}

	bisect->items.push_back(item);
	if(bisect->a) {
		PhysBisect* refuse = 0;
		while(bisect->childrenA > REBALANCE_RATIO * bisect->childrenB || bisect->childrenB > REBALANCE_RATIO * bisect->childrenA) {
			refuse = bisect;
			bisect = bisect->parent;
			if(bisect == 0)
				break;
		}

		if(refuse) {
			refuse->fuse();
			if(refuse->items.size() > SPLIT_COUNT)
				refuse->split();
		}
	}
	else if(bisect->items.size() > SPLIT_COUNT) {
		bisect->split();
	}
	mutex.release();
}

void PhysicsGrid::updateItem(PhysicsItem* item, const AABBoxd& newBound) {
	unsigned maskID = 1;
	if(item->type == PIT_Object)
		maskID = (item->object->owner ? item->object->owner->id : 1);
	if(maskID >= 32)
		maskID = 0;

	if(maskID == item->maskID) {
		PhysBisect* bisect = &groups[item->maskID];

		bool sameLocation = true;

		mutex.readLock();
		while(bisect->a) {
			int location = bisect->classifyContainer(item->bound);
			int newLoc = bisect->classifyContainer(newBound);
			if(location != newLoc) {
				sameLocation = false;
				break;
			}

			if(location == -1)
				bisect = bisect->a;
			else if(location == 1)
				bisect = bisect->b;
			else
				break;
		}

		if(sameLocation) {
			item->bound = newBound;
			mutex.release();
			return;
		}

		mutex.release();
	}

	//Container has changed
	mutex.writeLock();

	removeItem(item);
	item->bound = newBound;
	item->maskID = maskID;
	addItem(item);

	mutex.release();
}

//TODO: Handle things too big for the grid, or outside the grid
void PhysicsWorld::updateItem(PhysicsItem& item, const AABBoxd& newBox) {
	if(newBox.isWithin(item.gridLocation->fuzzBound)) {
		//TODO: Handle transition back from 'outside' if it is now able to be positioned in the grid
		item.gridLocation->updateItem(&item, newBox);
	}
	else {
		item.gridLocation->removeItem(&item);

		vec3d center = newBox.getCenter();
		unsigned x = getBox(center.x), y = getBox(center.z);
		item.bound = newBox;

		PhysicsGrid* newGrid = &grid[x*gridCount + y];
		if(!newBox.isWithin(newGrid->fuzzBound))
			newGrid = &outside;
		item.gridLocation = newGrid;
		newGrid->addItem(&item);
	}
}

void PhysicsWorld::registerItem(PhysicsItem& item) {
	assert((item.type & PIT_Object) == 0 || item.object);

	vec3d center = item.bound.getCenter();
	unsigned x = getBox(center.x), y = getBox(center.z);
	
	PhysicsGrid* newGrid = &grid[x*gridCount + y];
	if(!item.bound.isWithin(newGrid->fuzzBound))
		newGrid = &outside;

	item.gridLocation = newGrid;
	newGrid->addItem(&item);
}

PhysicsItem* PhysicsWorld::registerItem(const AABBoxd& bounds, Object* obj) {
	PhysicsItem* item = new PhysicsItem;
	item->bound = bounds;
	item->object = obj;
	item->type = PIT_Object;

	unsigned maskID = (obj->owner ? obj->owner->id : 1);
	if(maskID >= 32)
		maskID = 0;
	item->maskID = maskID;

	registerItem(*item);

	return item;
}

PhysicsItem* PhysicsWorld::registerItem(const AABBoxd& bounds, scene::Node* node) {
	PhysicsItem* item = new PhysicsItem;
	item->bound = bounds;
	item->node = node;
	item->type = PIT_Node;
	item->maskID = 0;

	registerItem(*item);

	return item;
}

void PhysicsWorld::unregisterItem(PhysicsItem& item) {
	item.gridLocation->removeItem(&item);
}

PhysicsWorld* PhysicsWorld::fromMessage(net::Message& msg) {
	double gridSize, gridFuzz;
	unsigned gridCount;

	msg >> gridSize;
	msg >> gridFuzz;
	msg >> gridCount;

	return new PhysicsWorld(gridSize, gridFuzz, gridCount);
}

PhysicsWorld* PhysicsWorld::fromSave(SaveFile& file) {
	double gridSize, gridFuzz;
	unsigned gridCount;

	file >> gridSize;
	file >> gridFuzz;
	file >> gridCount;

	return new PhysicsWorld(gridSize, gridFuzz, gridCount);
}

void PhysicsWorld::writeSetup(net::Message& msg) {
	msg << gridSize;
	msg << gridFuzz;
	msg << gridCount;
}

void PhysicsWorld::writeSetup(SaveFile& file) {
	file << gridSize;
	file << gridFuzz;
	file << gridCount;
}
