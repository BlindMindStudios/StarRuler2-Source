#include "threads.h"
#include <pthread.h>
#include <unistd.h>

namespace threads {

atomic_int nextThreadID(2);
Threaded(int) threadID = 1;

const int invalidThreadID = 0;

int getThreadID() {
	return threadID;
}

struct threadInfo {
	pthread_t thread;
	threadfunc func;
	void* arg;
};

void* startThread(void* arg) {
	threadInfo* info = (threadInfo*)arg;
	threadID = nextThreadID++;

	info->func(info->arg);

	delete info;
	return 0;
}

void setThreadPriority(ThreadPriority priority) {
	//NOT IMPLEMENTED
}

void createThread(threadfunc func, void* arg) {
	threadInfo* info = new threadInfo();
	info->func = func;
	info->arg = arg;

	pthread_create(&info->thread, 0, &startThread, info);
}

pthread_mutex_t sleepMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t sleepCond = PTHREAD_COND_INITIALIZER;

unsigned getNumberOfProcessors() {
	return sysconf(_SC_NPROCESSORS_ONLN);
}

void sleep(unsigned int milliseconds) {
	struct timespec wait;
	wait.tv_sec = (milliseconds / 1000);
	wait.tv_nsec = (milliseconds % 1000) * 1000 * 1000;

	nanosleep(&wait, 0);
}

void idle() {
#ifdef __APPLE__
	sleep(1);
#else
	sleep(0);
#endif
}

_threadlocalPointer::_threadlocalPointer() {
	pthread_key_create(&key, 0);
}

void _threadlocalPointer::set(void* ptr) {
	pthread_setspecific(key, ptr);
}

void* _threadlocalPointer::get() {
	return pthread_getspecific(key);
}

_threadlocalPointer::~_threadlocalPointer() {
	pthread_key_delete(key);
}

int swap(int* ptr, int newval) {
	return __sync_lock_test_and_set(ptr, newval);
}

int compare_and_swap(int* ptr, int oldval, int newval) {
	return __sync_val_compare_and_swap(ptr, oldval, newval);
}

long long swap(long long* ptr, long long newval) {
	return __sync_lock_test_and_set(ptr, newval);
}

long long compare_and_swap(long long* ptr, long long oldval, long long newval) {
	return __sync_val_compare_and_swap(ptr, oldval, newval);
}

void* swap(void** ptr, void* newval) {
	return __sync_lock_test_and_set(ptr, newval);
}

void* compare_and_swap(void** ptr, void* oldval, void* newval) {
	return __sync_val_compare_and_swap(ptr, oldval, newval);
}

};
