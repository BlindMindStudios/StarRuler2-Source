#pragma once

#ifdef _MSC_VER
    #define Threaded(type) __declspec(thread) type

	#define threadcall __stdcall

#else
	#include <atomic>
	#include <pthread.h>

	#define Threaded(type) __thread type

	#define threadcall
#endif

//#define PROFILE_LOCKS
#ifdef PROFILE_LOCKS
#include <string>
#include <set>
#endif
#include <functional>

namespace threads {

unsigned getNumberOfProcessors();
void async(std::function<int()> f);

void sleep(unsigned int milliseconds);
//Sleep intended for use as a wait in a non-critical busy loop
void idle();

#ifndef _MSC_VER
typedef unsigned int threadreturn;
typedef threadreturn (*threadfunc)(void*);
#else
typedef unsigned long threadreturn;
typedef threadreturn threadcall threadfunc(void*);
#endif

class atomic_int {
#ifdef _MSC_VER
	volatile long value;
#else
	volatile int value;
#endif
public:
	int get_basic();
	void set_basic(int val);

	int operator++();
	int operator++(int);
	int operator--();
	int operator--(int);
	
	int operator+=(int value);
	int operator-=(int value);

	int operator|=(int value);
	int operator&=(int value);

	void operator=(int value);

	int exchange(int value);
	int compare_exchange_strong(int value, int compareTo);

	//Like compare_exchange_strong, but will not return until the value is exchanged
	void wait_compare_exchange(int xchg, int compareTo, const int spinCount);

	int get() const { return value; }
	operator int() const { return value; }

	atomic_int() : value(0) {}
	atomic_int(int v) : value(v) {}
};

//Swap a value atomically
int swap(int* ptr, int newval);
int compare_and_swap(int* ptr, int oldval, int newval);
//long long swap(long long* ptr, long long newval);
long long compare_and_swap(long long* ptr, long long oldval, long long newval);
void* swap(void** ptr, void* newval);
void* compare_and_swap(void** ptr, void* oldval, void* newval);

class _threadlocalPointer {
#ifdef _MSC_VER
	long index;
#elif defined(__GNUC__)
	pthread_key_t key;
#endif
public:
	_threadlocalPointer();
	~_threadlocalPointer();

	void set(void* ptr);
	void* get();
};

template<class T>
class threadlocalPointer  : public _threadlocalPointer {
public:
	inline operator T*() {
		return (T*)get();
	}

	inline void operator=(T* ptr) {
		set((void*)ptr);
	}

	inline T* operator->() {
		return (T*)get();
	}
};

enum ThreadPriority {
	TP_High,
	TP_Normal,
	TP_Low
};

extern const int invalidThreadID;
void createThread(threadfunc func, void* arg);
int getThreadID();
void setThreadPriority(ThreadPriority priority);

struct Mutex {
private:
	atomic_int owningThread;
	unsigned lockCount;
	static const unsigned spinCount;
public:
#ifdef PROFILE_LOCKS
	atomic_int profileCount;
	std::string name;
	bool observed;
	Mutex();
	Mutex(const char* name);
	~Mutex();
#endif

	void lock();
	bool try_lock();
	void release();

	bool hasLock();
};

struct Lock {
private:
	Mutex* mutex;
public:

	Lock(Mutex& mtx) : mutex(&mtx) { mtx.lock(); }
	~Lock() { mutex->release(); }
};

struct ReadWriteMutex {
private:
	atomic_int owningThread;
	atomic_int readCount;
	static const unsigned spinCount;
public:
#ifdef PROFILE_LOCKS
	atomic_int profileReadCount;
	atomic_int profileWriteCount;
	std::string name;
	bool observed;
	ReadWriteMutex();
	~ReadWriteMutex();
#endif

	void writeLock();
	void readLock();
	void release();

	bool hasLock();
	bool hasWriteLock();
};

struct ReadLock {
private:
	ReadWriteMutex* mutex;
public:
	ReadLock(ReadWriteMutex& mtx) : mutex(&mtx) { mtx.readLock(); }
	~ReadLock() { mutex->release(); }
};

struct WriteLock {
private:
	ReadWriteMutex* mutex;
public:
	WriteLock(ReadWriteMutex& mtx) : mutex(&mtx) { mtx.writeLock(); }
	~WriteLock() { mutex->release(); }
};

struct Signal {
private:
	atomic_int flag;
	static const unsigned spinCount;
public:
	Signal(int start = 0);

	//Sets the signal to the specified value
	void signal(int value);
	//Reduces the signal's value by one
	void signalDown();
	//Increases the signal's value by one
	void signalUp();
	//Reduces the signal's value by a value
	void signalDown(int value);
	//Increases the signal's value by a value
	void signalUp(int value);

	//Returns true if the flag is at the value
	bool check(int checkFor) const;
	//Checks if the flag is at value, and sets it if it is
	bool checkAndSignal(int checkFor, int newSignal);

	//Waits until the value is the specified value
	void wait(int waitFor) const;
	//Waits until the value is not the specified value
	void waitNot(int waitForNot) const;
	//Waits until the value is the specified value, then sets it to a new value
	void waitAndSignal(int waitFor, int newSignal);
};

template<class T>
struct SharedData {
	mutable atomic_int count;
	T data;

	SharedData(int startCount = 1) : count(startCount), data() {}

	void grab() const {
		++count;
	}

	void drop() const {
		if(--count == 0)
			delete this;
	}

	T& operator*() {
		return data;
	}

	const T& operator*() const {
		return data;
	}

	T* operator->() {
		return &data;
	}

	const T* operator->() const {
		return &data;
	}
};

#ifdef PROFILE_LOCKS
void profileMutexCycle(std::function<void(Mutex*)> cb);
void profileReadWriteMutexCycle(std::function<void(ReadWriteMutex*)> cb);
#endif

};
