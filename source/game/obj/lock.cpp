#include "obj/lock.h"
#include "obj/universe.h"
#include "compat/misc.h"
#include "util/random.h"
#include "str_util.h"
#include "main/references.h"
#include "main/logging.h"
#include "network/network_manager.h"
#include "memory/AllocOnlyPool.h"
#include "processing.h"
#include <deque>
#include <assert.h>
#include "empire.h"

#ifdef PROFILE_PROCESSING
namespace processing {
extern Threaded(ProcessingData*) threadProc;
};
#endif

#ifndef LOCK_SWITCH_CHANCE
	#define LOCK_SWITCH_CHANCE 0.1
#endif
#ifndef TARGET_UPDATE_INTERVAL
	#define TARGET_UPDATE_INTERVAL 0.2
#endif
#ifndef SCRIPT_GC_INTERVAL
	#define SCRIPT_GC_INTERVAL 0.05
#endif

threads::atomic_int tickingLocks;
threads::atomic_int remainingMessages, queuedChildren;
std::vector<LockGroup*> lockGroups;

std::deque<LockGroup*> lockQueue;

#ifdef PROFILE_LOCKS
threads::Mutex lockQueueLock("lockQueueLock");
threads::Mutex lockGlobalLock("lockGlobalLock");
threads::Mutex switchedLock("switchedLock");
#else
threads::Mutex lockQueueLock;
threads::Mutex lockGlobalLock;
threads::Mutex switchedLock;
#endif

std::vector<Object*> switchedObjects;
Threaded(LockGroup*) activeLockGroup = 0;
Threaded(Object*) activeObject = 0;
double nextTargetUpdateTime = 0;
double nextScriptGCTime = 0;
double prevTick_s = 0;

threads::Mutex delayedReleaseLock;
std::vector<Object*> delayedReleaseObjects;

void delayObjectRelease(Object* obj) {
	threads::Lock lock(delayedReleaseLock);
	delayedReleaseObjects.push_back(obj);
}

void performDelayedObjectReleases() {
	threads::Lock lock(delayedReleaseLock);
	for(auto it = delayedReleaseObjects.begin(), end = delayedReleaseObjects.end(); it != end; ++it)
		(*it)->drop();
	delayedReleaseObjects.clear();
}

threads::atomic_int switches;
double statTime = 0.0;
bool switchStage = false;

memory::AllocOnlyRegion<threads::Mutex> objMessagePool(4096 * sizeof(void*));

void* ObjectMessage::operator new(size_t bytes) {
	return objMessagePool.alloc(bytes);
}

void ObjectMessage::operator delete(void* p) {
	objMessagePool.dealloc(p);
}

unsigned getLockCount() {
	return (unsigned)lockGroups.size();
}

LockGroup* getLock(unsigned index) {
	return lockGroups[index];
}

LockGroup* getActiveLockGroup() {
	return activeLockGroup;
}

Object* getActiveObject() {
	return activeObject;
}

void setActiveObject(Object* obj) {
	activeObject = obj;
}

threads::Mutex clearLock;
std::vector<Object*> queuedClearObjects;

void queueObjectClear(Object* obj) {
	threads::Lock lock(clearLock);
	obj->grab();
	queuedClearObjects.push_back(obj);
}

void handleObjectClears() {
	if(queuedClearObjects.empty())
		return;

	threads::Lock lock(clearLock);
	for(auto i = queuedClearObjects.begin(), end = queuedClearObjects.end(); i != end; ++i) {
		Object* obj = *i;
		obj->clearScripts();
		obj->drop();
	}
	queuedClearObjects.clear();
}

bool printNextLockStats = false;
void printLockStats() {
	printNextLockStats = true;
}

LockGroup::LockGroup()
	: tickIndex(0) {
#ifdef PROFILE_LOCKS
	mutex.name = "LockGroup "+toString(getLockCount());
	mutex.observed = true;

	addMutex.name = mutex.name+" Add Mutex";
	addMutex.observed = true;
#endif
}

bool LockGroup::hasLock() {
	return mutex.hasLock();
}

void tickSwitchedObjects(double time) {
	switchStage = true;

	foreach(it, switchedObjects) {
		Object* obj = *it;
		ObjectLock olock(obj);

		if(obj->isValid()) {
			//Only tick if the object wants to be ticked
			if(time > obj->nextTick && !obj->getFlag(objStopTicking)) {
				activeObject = obj;
				double delay = obj->think(time - obj->lastTick);

				obj->lastTick = time;
				obj->nextTick = time + delay;
			}
		}
	}

	switchedObjects.clear();
	switchStage = false;
	activeObject = nullptr;
}

double lastLockGlobalUpdate = 0.0;
bool updateLockGlobals(double time) {
	if(lockGroups.empty() || Object::GALAXY_CREATION)
		return false;
	if(time < lastLockGlobalUpdate + 0.001)
		return false;

	lockGlobalLock.lock();
	lockQueueLock.lock();

	double prevUpdate = lastLockGlobalUpdate;
	lastLockGlobalUpdate = time;

	if(lockQueue.size() + tickingLocks != 0) {
		lockGlobalLock.release();
		lockQueueLock.release();
		return true;
	}

	prevTick_s = time - prevUpdate;
	lockQueueLock.release();

#ifdef PROFILE_PROCESSING
	double startTime = devices.driver->getAccurateTime();
	processing::threadProc->globalCount += 1;
	processing::threadProc->switchedCount += switchedObjects.size();
#endif

	//TODO: This should probably be threaded and not
	//block the entire tick cycle.
	tickSwitchedObjects(time);

#ifdef PROFILE_PROCESSING
	double curTime = devices.driver->getAccurateTime();
	processing::threadProc->switchedTime += curTime - startTime;
	startTime = curTime;
#endif

	bool doGC = nextScriptGCTime < devices.driver->getFrameTime();
	if(doGC)
		devices.scripts.server->pauseScriptThreads();
	processing::pauseMessageHandling();

	//Record stats
	if(statTime < time) {
		statTime = time + 1.0;

		for(size_t i = 0, cnt = lockGroups.size(); i < cnt; ++i) {
			LockGroup* grp = lockGroups[i];
			if(printNextLockStats) {
				print("LockGroup %d: %d objects", i, grp->objects.size());
				print("  Bad Locks: %d / %d (%.0g%)",
					grp->badLocks, (grp->goodLocks + grp->badLocks),
					(double)grp->badLocks / (double)(grp->goodLocks
						+ grp->badLocks) * 100.0);
				print("  Gained %d objects, Lost %d objects.",
					grp->gainedObjects, grp->lostObjects);
			}

			grp->gainedObjects = 0;
			grp->lostObjects = 0;
			grp->goodLocks = 0;
			grp->badLocks = 0;
		}

		if(printNextLockStats) {
			print("Total Switches: %d\n", switches);
			printNextLockStats = false;
		}
		switches = 0;
	}

	//Update universe children
	if(devices.universe)
		devices.universe->doQueued();

	//Update target system periodically
	if(nextTargetUpdateTime < time) {
#ifdef PROFILE_PROCESSING
		startTime = devices.driver->getAccurateTime();
		processing::threadProc->targetUpdates += 1;
#endif

		nextTargetUpdateTime = time + TARGET_UPDATE_INTERVAL;

		foreach(it, devices.universe->children) {
			Object* obj = *it;
			if(obj->isValid())
				obj->updateTargets();
		}

		unsigned childCount = (unsigned)devices.universe->children.size();
		for(unsigned i = 0, cnt = (childCount + 255) / 256; i < cnt; ++i)
			devices.universe->setRandomTarget(devices.universe->children[randomi(0, childCount-1)]->targets[randomi(0, OBJ_TARGETS-1)]);

#ifdef PROFILE_PROCESSING
		curTime = devices.driver->getAccurateTime();
		processing::threadProc->targUpdateTime += curTime - startTime;
#endif
	}

	//We need to process deletion of objects' script classes while the server is paused, or component calls could randomly crash
	handleObjectClears();

	//Do server script garbage collection here,
	//so we don't need a lock around object tick calls
	if(doGC) {
		nextScriptGCTime = devices.driver->getFrameTime() + SCRIPT_GC_INTERVAL;
#ifdef PROFILE_PROCESSING
		double gcStart = devices.driver->getAccurateTime();
#endif
		int mode = devices.scripts.server->garbageCollect();
#ifdef PROFILE_PROCESSING
		double gcEnd = devices.driver->getAccurateTime();
		if(gcEnd >= gcStart + 0.01)
			print("Server GC took %dms (mode %d)", (int)((gcEnd - gcStart) * 1000.0), mode);
#endif

		// Do delayed object releases here too
		performDelayedObjectReleases();
	}

	processing::resumeMessageHandling();
	if(doGC)
		devices.scripts.server->resumeScriptThreads();

	//Queue up all locks for ticking again
	lockQueueLock.lock();
	foreach(it, lockGroups)
		lockQueue.push_back(*it);
	lockQueueLock.release();
	lockGlobalLock.release();
	return true;
}

void tickRandomMessages(int limit) {
	if(lockGroups.empty())
		return;
	if(activeLockGroup)
		throw "Can't lock multiple lock groups.";

	unsigned count = lockGroups.size();
	unsigned off = randomi(0, count-1);

	for(unsigned i = 0; i < count; ++i) {
		LockGroup* lock = lockGroups[(i+off) % count];

		if(!lock->messages.empty() && !lock->hasLock()) {
			devices.scripts.server->threadedCallMutex.readLock();
			if(lock->mutex.try_lock()) {
				activeLockGroup = lock;
				lock->processMessages(limit);
				activeLockGroup = 0;
				lock->mutex.release();
			}
			devices.scripts.server->threadedCallMutex.release();
			break;
		}
	}
}

void acquireRandomChildren() {
	if(lockGroups.empty())
		return;
	if(activeLockGroup)
		throw "Can't lock multiple lock groups.";

	LockGroup* lock = lockGroups[randomi(0,(int)lockGroups.size()-1)];

	if(!lock->addQueue.empty()) {
		devices.scripts.server->threadedCallMutex.readLock();
		lock->acquireChildren();
		devices.scripts.server->threadedCallMutex.release();
	}
}

void tickLockMessages(LockGroup* lock, int limit) {
	if(activeLockGroup)
		throw "Can't lock multiple lock groups.";

	if(!lock->messages.empty()) {
		devices.scripts.server->threadedCallMutex.readLock();
		if(lock->mutex.try_lock()) {
			activeLockGroup = lock;
			lock->processMessages(limit);
			activeLockGroup = 0;
			lock->mutex.release();
		}
		devices.scripts.server->threadedCallMutex.release();
	}
}

//Find a random lock group that's still queued up for ticking and tick it, or
//update global data and requeue if the queue is empty.
bool tickRandomLock(double time, int limit) {
	if(lockQueue.empty()) {
		if(tickingLocks == 0)
			return updateLockGlobals(time);
		else
			return false;
	}

	lockQueueLock.lock();
	LockGroup* lock = nullptr;
	if(!lockQueue.empty()) {
		for(unsigned i = 0, cnt = lockQueue.size(); i < cnt; ++i) {
			lock = lockQueue.front();
			lockQueue.pop_front();
			if(!lock->hasLock())
				break;
			lockQueue.push_back(lock);
			lock = nullptr;
		}
		if(lock)
			++tickingLocks;
	}
	lockQueueLock.release();

	if(!lock)
		return false;

#ifdef TRACE_GC_LOCK
	devices.scripts.server->markGCImpossible();
#endif

	if(!lock->process(time, limit)) {
		lockQueueLock.lock();
		lockQueue.push_back(lock);
		lockQueueLock.release();
	}

#ifdef TRACE_GC_LOCK
	devices.scripts.server->markGCPossible();
#endif

	--tickingLocks;
	return true;
}

void LockGroup::addMessage(ObjectMessage* message) {
	remainingMessages++;
	messageLock.lock();
	messages.push_back(message);
	messageLock.release();
}

void LockGroup::add(Object* obj) {
	obj->grab();

	addMutex.lock();
	++queuedChildren;
	addQueue.push_back(obj);
	addMutex.release();
}

void LockGroup::processMessages(int limit) {
	while(!messages.empty() && limit--) {
		messageLock.lock();
			if(messages.empty()) {
				messageLock.release();
				return;
			}

			ObjectMessage* msg = messages.front();
			messages.pop_front();
		messageLock.release();

		if(msg->object->lockGroup == this) {
			//Only execute messages that are
			//actually for this group
			Object* prevObj = activeObject;
			activeObject = msg->object;
			msg->process();
			activeObject = prevObj;
			delete msg;
			remainingMessages--;
		}
		else {
			//Sometimes, an object will have switched
			//lock groups before we get to a message
			LockGroup* lockGroup = msg->object->lockGroup;
			if(lockGroup) {
				lockGroup->addMessage(msg);
				remainingMessages--;
			}
			else {
				//The object was trashed, we don't care
				//about this message anymore
				delete msg;
				remainingMessages--;
			}
		}
	}
}

void LockGroup::acquireChildren() {
	if(addQueue.empty())
		return;

	lockGroup(this);

	addMutex.lock();
	int offset = 0;
	for(int i = 0, size = (int)addQueue.size(); i < size; ++i) {
		Object* obj = addQueue[i];

		if(auto* messages = obj->fetchMessages()) {
			DeferredObjMessage* prev = nullptr;
			while(messages) {
				messages->prev = prev;
				prev = messages;
				messages = messages->next;
			}

			messages = prev;
			while(messages) {
				auto* msg = messages;

				Object* prevObj = activeObject;
				activeObject = msg->msg->object;
				msg->msg->process();
				activeObject = prevObj;

				delete msg->msg;
				messages = msg->prev;
				delete msg;
			}
		}

		//Remove objects we already have or that are not ours
		//any longer.
		if(obj->originalLock == this || obj->lockGroup != this) {
			++offset;
			continue;
		}

		//Wait for the other group to release it
		if(obj->originalLock != 0) {
			//Since we're skipping this tick, put it in the switched
			//objects queue to tick it.
			switchedLock.lock();
			switchedObjects.push_back(obj);
			switchedLock.release();

			if(offset > 0)
				addQueue[i - offset] = obj;
			continue;
		}

		//Don't do anything until the object has started ticking
		if(obj->getFlag(objStopTicking)) {
			if(offset > 0)
				addQueue[i - offset] = obj;
			continue;
		}

		//Add object to list
		objects.push_back(obj);
		obj->originalLock = this;
		if(devices.network->isServer && devices.network->hasSyncedClients)
			devices.network->sendObject(obj);
		++offset;
	}

	queuedChildren -= offset;
	addQueue.resize(addQueue.size() - offset);
	addMutex.release();

	unlockGroup(this);
}

bool LockGroup::process(double time, int limit) {
#ifdef OBJECT_LOCK_NAGGING
	if(activeLockGroup && activeLockGroup != this)
		throw "Trying to process a LockGroup with an object locked.";
#endif
	lockGroup(this);

	if(tickIndex >= objects.size()) {
		//Add queued objects
		addMutex.lock();
		int offset = 0;
		for(int i = 0, size = (int)addQueue.size(); i < size; ++i) {
			Object* obj = addQueue[i];

			if(auto* messages = obj->fetchMessages()) {
				DeferredObjMessage* prev = nullptr;
				while(messages) {
					messages->prev = prev;
					prev = messages;
					messages = messages->next;
				}

				messages = prev;
				while(messages) {
					auto* msg = messages;

					Object* prevObj = activeObject;
					activeObject = msg->msg->object;
					msg->msg->process();
					activeObject = prevObj;

					delete msg->msg;
					messages = msg->prev;
					delete msg;
				}
			}

			//Remove objects we already have or that are not ours
			//any longer.
			if(obj->originalLock == this || obj->lockGroup != this) {
				++offset;
				continue;
			}

			//Wait for the other group to release it
			if(obj->originalLock != 0) {
				//Since we're skipping this tick, put it in the switched
				//objects queue to tick it.
				switchedLock.lock();
				switchedObjects.push_back(obj);
				switchedLock.release();

				if(offset > 0)
					addQueue[i - offset] = obj;
				continue;
			}

			//Don't do anything until the object has started ticking
			if(obj->getFlag(objStopTicking)) {
				if(offset > 0)
					addQueue[i - offset] = obj;
				continue;
			}

			//Add object to list
			objects.push_back(obj);
			obj->originalLock = this;
			if(devices.network->isServer && devices.network->hasSyncedClients)
				devices.network->sendObject(obj);
			++offset;
		}

		queuedChildren -= offset;
		addQueue.resize(addQueue.size() - offset);
		addMutex.release();

		//Reset ticking
		tickIndex = 0;
	}

#ifdef PROFILE_PROCESSING
	double procStart;
	int procType = -1;
	int procCount = 0;
#endif

	processMessages();

	bool isNetServer = devices.network->isServer;

	//Tick objects
	int i = 0;
	unsigned char rnd = (unsigned char)randomi();
	while(tickIndex < objects.size()) {
		//Caller can limit amount of ticked objects
		if(i >= limit)
			break;

		//Break when a priority lock is detected
		if(priorityLocks.get() > 0)
			break;

		//Tick object
		Object* obj = objects[tickIndex];

		if(obj->lockGroup != this) {
			//Ignore locks that have switched already
			obj->originalLock = 0;
			objects[tickIndex] = objects.back();
			objects.pop_back();
		}
		else if(!obj->isValid()) {
			//Remove invalid objects from the list
			obj->originalLock = 0;
			obj->drop();
			objects[tickIndex] = objects.back();
			objects.pop_back();
		}
		else {
			//Only tick if the object wants to be ticked
			if((time > obj->nextTick || obj->getFlag(objWakeUp)) && !obj->getFlag(objStopTicking)) {
#ifdef PROFILE_PROCESSING
				if(obj->type->id != procType) {
					double curTime = devices.driver->getAccurateTime();
					if(procType != -1) {
						processing::threadProc->measureType(
							procType,
							curTime - procStart,
							procCount);
					}
					procStart = curTime;
					procType = obj->type->id;
					procCount = 0;
				}
				++procCount;
#endif
				if(obj->deferredMessages) {
					if(auto* messages = obj->fetchMessages()) {
						DeferredObjMessage* prev = nullptr;
						while(messages) {
							messages->prev = prev;
							prev = messages;
							messages = messages->next;
						}

						messages = prev;
						while(messages) {
							auto* msg = messages;

							Object* prevObj = activeObject;
							activeObject = msg->msg->object;
							msg->msg->process();
							activeObject = prevObj;

							delete msg->msg;
							messages = msg->prev;
							delete msg;
						}
					}
				}

				activeObject = obj;
				double delay = obj->think(time - obj->lastTick);

				rnd ^= (unsigned char)obj->id;
				delay *= 0.85f + ((float)rnd / 255.f) * 0.15f;

				obj->lastTick = time;
				obj->nextTick = time + delay;

				if(isNetServer)
					devices.network->sendObjectDelta(obj);

				++i;

				if(!messages.empty())
					processMessages();

				//We need to sleep periodically to guarantee progress at high cpu utilization
				if(i % 1024 == 0) {
					unlockGroup(this);
					threads::sleep(1);
					lockGroup(this);
				}
			}

			++tickIndex;
		}
	}

#ifdef PROFILE_PROCESSING
	if(procType != -1) {
		double curTime = devices.driver->getAccurateTime();
		processing::threadProc->measureType(
			procType,
			curTime - procStart,
			procCount);
	}
#endif

	unlockGroup(this);
	activeObject = nullptr;
	return tickIndex >= objects.size();
}

LockGroup* getRandomLock() {
	assert(!lockGroups.empty());
	return lockGroups[randomi(0, (int)lockGroups.size() - 1)];
}

void initLocks(unsigned lockCount) {
	assert(tickingLocks == 0);
	lockQueueLock.lock();
	for(unsigned i = 0; i < lockCount; ++i) {
		LockGroup* lock = new LockGroup();
		lock->id = i;
		lockGroups.push_back(lock);
		lockQueue.push_back(lock);
	}
	lockQueueLock.release();
}

void destroyLocks() {
	foreach(it, lockGroups)
		delete *it;
	lockGroups.clear();
	lockQueue.clear();
}

LockGroup* lockObject(Object* obj, bool priority) {
	LockGroup* other;
	if(!obj)
		return 0;

changedGroup:
	other = obj->lockGroup;
	if(!other)
		return 0;

	lockGroup(other, priority);
	if(obj->lockGroup != other) {
		unlockGroup(other);
		goto changedGroup;
	}
	return other;

	//TODO: Reimplement this for secondary locks
	//if(other == activeLockGroup) {
		//++other->goodLocks;
		//return 0;
	//}

	//if(activeLockGroup)
		//++other->badLocks;
	//else
		//++other->goodLocks;

	////Chance to switch locks
	//if(write && activeLockGroup) {
		//if(randomf() < LOCK_SWITCH_CHANCE) {
			//++switches;
			//++obj->lockGroup->lostObjects;
			//++activeLockGroup->gainedObjects;

			//if(activeLockGroup != obj->originalLock)
				//activeLockGroup->add(obj);
			//obj->lockGroup = activeLockGroup;

			////Queue a tick if this is the first switch
			//if(!switchStage && obj->originalLock == other) {
				//switchedLock.lock();
				//switchedObjects.push_back(obj);
				//switchedLock.release();
			//}

			//other->mutex.release();
			//return 0;
		//}
	//}
}

void lockError(const char* ch) {
	if(scripts::getActiveManager())
		scripts::throwException(ch);
	else
		throw ch;
}

inline void doLock(LockGroup* group, bool priority) {
	if(priority)
		++group->priorityLocks;

	group->mutex.lock();

	if(priority)
		--group->priorityLocks;
}

void lockGroup(LockGroup* group, bool priority) {
	//Check if we already have the group locked
	if(activeLockGroup) {
		if(group == activeLockGroup) {
			group->mutex.lock();
		}
		else {
#ifdef OBJECT_LOCK_NAGGING
			lockError("Cannot lock object with another object already locked.");
			return;
#else
			//Compatibility. This is a potential deadlock, but silently
			//do it anyway if not in nagging mode.
			doLock(group, priority);
#endif
		}
	}
	else {
		activeLockGroup = group;
		doLock(group, priority);
	}
}

inline void _unlockGroup(LockGroup* lock) {
	if(lock) {
		lock->mutex.release();

		if(!lock->hasLock()) {
			if(lock == activeLockGroup)
				activeLockGroup = 0;
		}
	}
}

void unlockObject(LockGroup* lock) {
	_unlockGroup(lock);
}

void unlockGroup(LockGroup* lock) {
	_unlockGroup(lock);
}

bool hasQueuedChildren() {
	return queuedChildren != 0;
}

bool hasRemainingMessages() {
	return remainingMessages != 0;
}
