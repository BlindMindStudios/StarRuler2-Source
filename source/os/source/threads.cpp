#include "threads.h"
#include <assert.h>

namespace threads {

threadreturn threadcall asyncWrapper(void* pData) {
	std::function<int()>* pFunc = (std::function<int()>*)pData;

	int r = (*pFunc)();

	delete pFunc;
	return r;
}

void async(std::function<int()> f) {
	createThread(asyncWrapper, new std::function<int()>(f));
}

const unsigned Mutex::spinCount = 5;
const unsigned ReadWriteMutex::spinCount = 8;
const unsigned Signal::spinCount = 3;

void Mutex::lock() {
	int id = getThreadID();
	if(owningThread != id) {
		owningThread.wait_compare_exchange(id, invalidThreadID, spinCount);
		lockCount = 1;
	}
	else {
		++lockCount;
	}

#ifdef PROFILE_LOCKS
		++profileCount;
#endif
}

bool Mutex::try_lock() {
	int id = getThreadID();
	if(owningThread != id) {
		for(unsigned i = 0; i < spinCount; ++i) {
			int invalidThreadIdCopy = invalidThreadID;
			if(owningThread.compare_exchange_strong(invalidThreadIdCopy, id)) {
				lockCount = 1;
#ifdef PROFILE_LOCKS
				++profileCount;
#endif
				return true;
			}
		}
		return false;
	}
	else {
		++lockCount;
#ifdef PROFILE_LOCKS
		++profileCount;
#endif
		return true;
	}
}

void Mutex::release() {
	assert(lockCount > 0);
	if(--lockCount == 0)
		owningThread = invalidThreadID;
}

bool Mutex::hasLock() {
	return owningThread == getThreadID();
}

Threaded(ReadWriteMutex*) rw_locks[8];
Threaded(unsigned) rw_lockCounts[8];
Threaded(int) rw_head = -1;

unsigned& get_rw_thread_lockCount(ReadWriteMutex* lock) {
	for(int i = rw_head; i >= 0; --i)
		if(rw_locks[i] == lock)
			return rw_lockCounts[i];
	++rw_head;
	rw_locks[rw_head] = lock;
	rw_lockCounts[rw_head] = 0;
	assert(rw_head < 8);
	return rw_lockCounts[rw_head];
}

void remove_rw_thread_lockCount(ReadWriteMutex* lock) {
	for(int i = rw_head; i >= 0; --i) {
		if(rw_locks[i] == lock)  {
			for(int j = i; j < rw_head; ++j) {
				rw_locks[j] = rw_locks[j+1];
				rw_lockCounts[j] = rw_lockCounts[j+1];
			}
			--rw_head;
		}
	}
}

void ReadWriteMutex::writeLock() {
	auto id = getThreadID();
	unsigned& threadLockCount = get_rw_thread_lockCount(this);
	if(owningThread != id) {
		//Acquire right to increase readCount
		owningThread.wait_compare_exchange(id, invalidThreadID, spinCount);

		//Cannot upgrade locks to write locks, this creates deadlocks
		if(threadLockCount > 0)
			throw "Upgrading a read lock is invalid.";

		//Wait until reading threads are done
		unsigned spins = 0;
		while(readCount > (int)threadLockCount) {
			++spins;
			if(spins == spinCount) {
				sleep(0);
				spins = 0;
			}
		}

		++readCount;
	}
	else {
		++readCount;
	}

	++threadLockCount;

#ifdef PROFILE_LOCKS
	++profileWriteCount;
#endif
}

bool ReadWriteMutex::hasLock() {
	for(int i = rw_head; i >= 0; --i)
		if(rw_locks[i] == this)
			return rw_lockCounts[i] != 0;
	return false;
}

bool ReadWriteMutex::hasWriteLock() {
	return owningThread == getThreadID();
}

void ReadWriteMutex::readLock() {
	auto id = getThreadID();
	unsigned& threadLockCount = get_rw_thread_lockCount(this);

	if(owningThread != id && threadLockCount == 0) {
		owningThread.wait_compare_exchange(id, invalidThreadID, spinCount);
		++readCount;
		owningThread = invalidThreadID;
	}
	else {
		++readCount;
	}

	++threadLockCount;

#ifdef PROFILE_LOCKS
	++profileReadCount;
#endif
}

void ReadWriteMutex::release() {
	if(--readCount == 0 && owningThread == getThreadID())
		owningThread = invalidThreadID;
	auto& threadLockCount = get_rw_thread_lockCount(this);
	if(--threadLockCount == 0)
		remove_rw_thread_lockCount(this);
}

Signal::Signal(int start) : flag(start) {
}

void Signal::signal(int value) {
	flag.set_basic(value);
}

void Signal::signalDown() {
	--flag;
}

void Signal::signalUp() {
	++flag;
}

void Signal::signalDown(int value) {
	flag -= value;
}

void Signal::signalUp(int value) {
	flag += value;
}

bool Signal::check(int checkFor) const {
	return flag == checkFor;
}

bool Signal::checkAndSignal(int waitFor, int newSignal) {
	return flag.compare_exchange_strong(waitFor, newSignal);
}

void Signal::wait(int waitFor) const {
	unsigned spins = 0;
	while(flag != waitFor) {
		if(spins++ == spinCount) {
			sleep(1);
			spins = 0;
		}
	}
}

void Signal::waitNot(int waitForNot) const {
	unsigned spins = 0;
	while(flag == waitForNot) {
		if(spins++ == spinCount) {
			sleep(1);
			spins = 0;
		}
	}
}

void Signal::waitAndSignal(int waitFor, int newSignal) {
	flag.wait_compare_exchange(newSignal, waitFor, spinCount);
}

#ifdef PROFILE_LOCKS
std::set<Mutex*>* mutexes = 0;
std::set<ReadWriteMutex*>* rwMutexes = 0;
Mutex listMutex;

Mutex::Mutex() : observed(false) {
	if(this != &listMutex) {
		threads::Lock lock(listMutex);
		if(!mutexes)
			mutexes = new std::set<Mutex*>();
		mutexes->insert(this);
	}

	char buff[256];
	sprintf(buff, "Mutex %p", this);
	name = buff;
}

Mutex::Mutex(const char* mtxName) : observed(false) {
	if(this != &listMutex) {
		threads::Lock lock(listMutex);
		if(!mutexes)
			mutexes = new std::set<Mutex*>();
		mutexes->insert(this);
	}

	name = mtxName;
}

Mutex::~Mutex() {
	if(this != &listMutex) {
		threads::Lock lock(listMutex);
		mutexes->erase(this);
	}
}

ReadWriteMutex::ReadWriteMutex() : observed(false) {
	{
		threads::Lock lock(listMutex);
		if(!rwMutexes)
			rwMutexes = new std::set<ReadWriteMutex*>();
		rwMutexes->insert(this);
	}

	char buff[256];
	sprintf(buff, "ReadWriteMutex %p", this);
	name = buff;
}

ReadWriteMutex::~ReadWriteMutex() {
	threads::Lock lock(listMutex);
	rwMutexes->erase(this);
}

void profileMutexCycle(std::function<void(Mutex*)> cb) {
	threads::Lock lock(listMutex);
	for(auto it = mutexes->begin(), end = mutexes->end(); it != end; ++it) {
		if(cb)
			cb(*it);
		(*it)->profileCount = 0;
	}
}

void profileReadWriteMutexCycle(std::function<void(ReadWriteMutex*)> cb) {
	threads::Lock lock(listMutex);
	for(auto it = rwMutexes->begin(), end = rwMutexes->end(); it != end; ++it) {
		if(cb)
			cb(*it);
		(*it)->profileReadCount = 0;
		(*it)->profileWriteCount = 0;
	}
}
#endif

};
