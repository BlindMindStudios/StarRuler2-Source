#pragma once
#include "threads.h"
#include "obj/object.h"
#include <set>
#include <queue>

#define OBJECT_LOCK_NAGGING

struct ObjectMessage;

struct LockGroup {
	int id;
	threads::Mutex mutex;
	threads::atomic_int priorityLocks;
	std::vector<Object*> objects;
	unsigned tickIndex;

	bool hasLock();
	bool hasWriteLock();

	std::vector<Object*> addQueue;
	threads::Mutex addMutex;

	std::deque<ObjectMessage*> messages;
	std::unordered_map<Object*, std::vector<ObjectMessage*>*> deferredMessages;
	threads::Mutex messageLock;

	threads::atomic_int badLocks;
	threads::atomic_int goodLocks;
	threads::atomic_int lostObjects;
	threads::atomic_int gainedObjects;

	LockGroup();

	void addMessage(ObjectMessage* message);
	void add(Object* obj);
	bool process(double time, int limit = 1000);
	void acquireChildren();
	void processMessages(int limit = 100);
};

struct ObjectMessage {
	Object* object;

	ObjectMessage(Object* obj) : object(obj) {}
	virtual void process() = 0;
	virtual ~ObjectMessage() {}

	void* operator new(size_t bytes);
	void operator delete(void* p);
};

LockGroup* getRandomLock();
void initLocks(unsigned lockCount);
void destroyLocks();

unsigned getLockCount();
LockGroup* getLock(unsigned index);
void printLockStats();

void acquireRandomChildren();
bool tickRandomLock(double time, int limit = 1000);
void tickRandomMessages(int limit = 100);
//Attempts to process the messages in a particular group, with no guarantee of any success
void tickLockMessages(LockGroup* lock, int limit = 8);

//If a message can't be processed yet (the object has no lock group), it must be queued for later execution
void queueDeferredMessage(ObjectMessage* msg);

LockGroup* getActiveLockGroup();
Object* getActiveObject();
void setActiveObject(Object* obj);
void queueObjectClear(Object* obj);
void delayObjectRelease(Object* obj);

LockGroup* lockObject(Object* obj, bool priority = false);
void unlockObject(LockGroup* lock);

void lockGroup(LockGroup* group, bool priority = false);
void unlockGroup(LockGroup* lock);

bool hasQueuedChildren();
bool hasRemainingMessages();
