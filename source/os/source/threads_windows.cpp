#include "threads.h"
#include <Windows.h>
#include <intrin.h>

namespace threads {

atomic_int nextThreadID(1);
const int invalidThreadID = 0;
Threaded(int) threadID = invalidThreadID;

int getThreadID() {
	if(threadID == invalidThreadID) {
		threadID = nextThreadID++;
		return threadID;
	}
	else {
		return threadID;
	}
}

void setThreadPriority(ThreadPriority priority) {
	int priority_val;
	switch(priority) {
	case TP_High:
		priority_val = THREAD_PRIORITY_ABOVE_NORMAL; break;
	case TP_Normal: default:
		priority_val = THREAD_PRIORITY_NORMAL; break;
	case TP_Low:
		priority_val = THREAD_PRIORITY_BELOW_NORMAL; break;
	}

	SetThreadPriority(GetCurrentThread(), priority_val);
}

void createThread(unsigned long threadcall entry(void*), void* arg) {
	CreateThread(NULL, 0, entry, arg, 0, NULL);
}

_threadlocalPointer::_threadlocalPointer() : index(TlsAlloc()) {
}

_threadlocalPointer::~_threadlocalPointer() {
	TlsFree(index);
}

void _threadlocalPointer::set(void* ptr) {
	TlsSetValue(index, ptr);
}

void* _threadlocalPointer::get() {
	return TlsGetValue(index);
}

unsigned getNumberOfProcessors() {
	SYSTEM_INFO info;
	GetSystemInfo(&info);
	return info.dwNumberOfProcessors;
}

void sleep(unsigned int milliseconds) {
	Sleep(milliseconds);
}

void idle() {
	Sleep(1);
}

int swap(int* ptr, int newval) {
	return (int)_InterlockedExchange((long*)ptr, (long)newval);
}

int compare_and_swap(int* ptr, int oldval, int newval) {
	return (int)_InterlockedCompareExchange((long*)ptr, (long)newval, (long)oldval);
}

//long long swap(long long* ptr, long long newval) {
//	return _InterlockedExchange64(ptr, newval);
//}

long long compare_and_swap(long long* ptr, long long oldval, long long newval) {
	return _InterlockedCompareExchange64(ptr, newval, oldval);
}

#ifdef _M_AMD64
void* swap(void** ptr, void* newval) {
	return (void*)_InterlockedExchange64((long long*)ptr, (long long)newval);
}

void* compare_and_swap(void** ptr, void* oldval, void* newval) {
	return (void*)_InterlockedCompareExchange64((long long*)ptr, (long long)newval, (long long)oldval);
}
#else
void* swap(void** ptr, void* newval) {
	return (void*)_InterlockedExchange((long*)ptr, (long)newval);
}

void* compare_and_swap(void** ptr, void* oldval, void* newval) {
	return (void*)_InterlockedCompareExchange((long*)ptr, (long)newval, (long)oldval);
}
#endif

};
