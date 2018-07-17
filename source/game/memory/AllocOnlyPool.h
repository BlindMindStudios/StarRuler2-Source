#pragma once
#include <memory>

namespace memory {

//A pre-allocated pool of uniformly sized objects
//Allocated memory is only cleared when all objects in the pool are deleted
//When all memory is used up, falls back on global operator new/delete
template<class T, class L>
class AllocOnlyPool {
	L lock;
	T* pStart, *pNext, *pEnd;
	unsigned allocated;

public:
	AllocOnlyPool(unsigned count) : allocated(0) {
		pStart = (T*)new unsigned char[count * sizeof(T)];
		pNext = pStart;
		pEnd = pStart + count;
	}

	~AllocOnlyPool() {
		delete[] (unsigned char*)pStart;
	}

	void* alloc() {
		lock.lock();

		void* r;
		if(pNext != pEnd) {
			++allocated;
			r = pNext++;
			lock.release();
		}
		else {
			lock.release();
			r = ::operator new(sizeof(T));
		}

		return r;
	}

	void dealloc(T* p) {
		if(p >= pStart && p < pEnd) {
			lock.lock();
			if(--allocated == 0)
				pNext = pStart;
			lock.release();
		}
		else {
			::operator delete(p);
		}
	}
};

//A pre-allocated region for any data types
//Allocated memory is only cleared when all objects in the pool are deleted
//When all memory is used up, falls back on global operator new/delete
template<class Lock>
class AllocOnlyRegion {
	unsigned char* pStart, *pNext, *pEnd;
	unsigned allocated;
	Lock lock;
public:
	AllocOnlyRegion(unsigned bytes) : allocated(0) {
		pStart = new unsigned char[bytes];
		pNext = pStart;
		pEnd = pStart + bytes;
	}

	~AllocOnlyRegion() {
		delete[] (unsigned char*)pStart;
	}

	void* alloc(size_t size) {
		lock.lock();
		if(size < (size_t)(pEnd - pNext)) {
			++allocated;
			auto pCopy = pNext;
			pNext += size;
			lock.release();
			return pCopy;
		}
		else {
			lock.release();
			return ::operator new(size);
		}
	}

	void dealloc(void* p) {
		if(p >= pStart && p < pEnd) {
			lock.lock();
			if(--allocated == 0)
				pNext = pStart;
			lock.release();
		}
		else {
			::operator delete(p);
		}
	}
};

};
