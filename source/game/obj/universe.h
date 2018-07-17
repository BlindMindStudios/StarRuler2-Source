#pragma once
#include "obj/object.h"
#include "util/refcount.h"
#include "threads.h"
#include <unordered_set>

class Universe : public AtomicRefCounted {
public:
	mutable threads::Mutex queueLock;
	std::unordered_set<Object*> addQueue;
	std::unordered_set<Object*> removeQueue;

	mutable threads::ReadWriteMutex childLock;
	std::vector<Object*> children;

	void doQueued();
	void addChild(Object* obj);
	void removeChild(Object* obj);
	void destroyAll();

	Object* getRandomTarget(unsigned randVal = 0);
	void setRandomTarget(heldPointer<Object>& targ, unsigned randVal = 0);
	void removeTargetsTo(Object* obj);

	Object* getClosestOnLine(const line3dd& line) const;
};
