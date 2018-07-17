#include "obj/universe.h"
#include "empire.h"
#include "compat/misc.h"
#include "util/random.h"
#include "main/references.h"
#include "network/network_manager.h"
#include "physics/physics_world.h"
#include <assert.h>
#include <unordered_set>

void Universe::doQueued() {
	threads::Lock qlock(queueLock);
	threads::WriteLock lock(childLock);

	//Remove queued objects
	unsigned offset = 0;
	if(!removeQueue.empty()) {
		for(unsigned i = 0, cnt = (unsigned)children.size(); i < cnt; ++i) {
			Object* child = children[i];
			if(removeQueue.find(child) != removeQueue.end()) {
				++offset;
				removeTargetsTo(child); //TODO: better
				child->drop();
			}
			else if(offset != 0) {
				children[i - offset] = children[i];
			}
		}
		if(offset != 0)
			children.resize(children.size() - (size_t)offset);
		removeQueue.clear();
	}

	//Add queued objects
	foreach(it, addQueue)
		children.push_back(*it);
	addQueue.clear();
}

void Universe::addChild(Object* obj) {
	threads::Lock qlock(queueLock);

	auto it = removeQueue.find(obj);
	if(it != removeQueue.end())
		removeQueue.erase(obj);
	else
		addQueue.insert(obj);
	obj->grab();
}

void Universe::removeChild(Object* obj) {
	threads::Lock qlock(queueLock);
	auto it = addQueue.find(obj);
	if(it != addQueue.end()) {
		addQueue.erase(obj);
		for(unsigned i = 0; i < OBJ_TARGETS; ++i)
			obj->targets[i] = nullptr;
	}
	else
		removeQueue.insert(obj);
}

void Universe::destroyAll() {
	foreach(child, children) {
		(*child)->destroy(true);
		(*child)->drop();
	}
	children.clear();
}

Object* Universe::getRandomTarget(unsigned randVal) {
	//No child lock needed, guaranteed through lock ticking
	if(children.empty())
		return 0;
	if(randVal == 0)
		randVal = randomi();
	return children[randVal % children.size()];
}

void Universe::setRandomTarget(heldPointer<Object>& targ, unsigned randVal) {
	//No child lock needed, guaranteed through lock ticking
	if(children.empty())
		return;

	if(randVal == 0)
		randVal = randomi();

	Object* child = children[randVal % children.size()];

	if(child->isValid()) {
		auto& other = child->targets[randVal % OBJ_TARGETS];
		if(!other->getFlag(objNoPhysics))
			other.swap(targ);
	}
}

void Universe::removeTargetsTo(Object* obj) {
	//No child lock needed, guaranteed through lock ticking
	unsigned remaining = OBJ_TARGETS;
	unsigned i = 0;
	unsigned cnt = (unsigned)children.size();

	for(unsigned t = 0; t < OBJ_TARGETS; ++t)
		if(obj->targets[t] == obj)
			--remaining;

	if(remaining == 0)
		goto clearTargets;

	for(; i < cnt; ++i) {
		Object* child = children[i];

		for(unsigned j = 0; j < OBJ_TARGETS; ++j) {
			if(child->targets[j] == obj && child != obj) {
				for(unsigned t = 0; t < OBJ_TARGETS; ++t) {
					if(obj->targets[t] != obj) {
						child->targets[j].swap(obj->targets[t]);
						break;
					}
				}
				assert(children[i]->targets[j] != obj);
				--remaining;
				if(remaining == 0)
					goto clearTargets;
			}
		}
	}

	clearTargets:;
	for(unsigned i = 0; i < OBJ_TARGETS; ++i)
		obj->targets[i] = 0;
}

const double coneSlope = 0.02;

Object* Universe::getClosestOnLine(const line3dd& line) const {
	threads::ReadLock lock(childLock);

	Empire* empire = Empire::getPlayerEmpire();
	auto lineDir = line.getDirection();
	double closest_d = 9e32;
	double closest_p = 1.0;
	Object* closest_o = 0;

	//TODO: This should handle the cone more accurately, possibly in multiple steps?
	//Bound should hold the line, and a considerable radius around it to handle the cone
	AABBoxd bound(line.start);
	bound.addBox( AABBoxd::fromCircle(line.end, 1500.0) );

	devices.physics->findInBox(line, [&](const PhysicsItem& item) {
			Object* obj = item.object;
			if(!obj || !obj->isVisibleTo(empire))
				return;

			double distOnLine = (obj->position - line.start).dot(lineDir);
			if(distOnLine <= 0)
				return;

			auto p = line.start + (lineDir * distOnLine);
			double p_d = p.distanceTo(obj->position);
			double c_d = obj->radius + distOnLine * coneSlope;
			if(p_d >= c_d)
				return;

			double pct = p_d / c_d;

			auto dist = p.getLength();
			if(dist < closest_d && pct < closest_p) {
				closest_o = obj;
				closest_d = dist;
				closest_p = pct;
			}
		});

	return closest_o;
}
