#pragma once
#include "threads.h"

template <class T>
class _RefCounted {
public:
	mutable T refs;
	_RefCounted() : refs(1) {}
	void grab() const { ++refs; }
	void drop() const { if(!--refs) delete this; }
	virtual ~_RefCounted() {}
};

typedef _RefCounted<int> RefCounted;
typedef _RefCounted<threads::atomic_int> AtomicRefCounted;

template<class _T>
struct heldPointer {
	//Actual Pointer - do not directly alter without handling the grab/drop yourself
	_T* ptr;

	//Handles all grabbing and dropping when a pointer changes value
	inline void operator= (_T* newPtr) {
		//Grabs the new first, incase new == old
		//We don't explicitly check, because that's a relatively unlikely case, and only adds overhead where not necessary
		if(newPtr)
			newPtr->grab();

		if(ptr)
			ptr->drop();

		ptr = newPtr;
	}

	inline void operator= (const heldPointer<_T>& other) {
		//Grabs the new first, incase new == old
		//We don't explicitly check, because that's a relatively unlikely case, and only adds overhead where not necessary
		if(other.ptr)
			other.ptr->grab();

		if(ptr)
			ptr->drop();

		ptr = other.ptr;
	}

	inline void operator= (heldPointer<_T>&& other) {
		if(ptr)
			ptr->drop();
		ptr = other.ptr;
		other.ptr = 0;
	}

	inline bool operator< (const heldPointer<_T>& other) {
		return ptr < other.ptr;
	}

	//Only drop()s the previous pointer, does not grab the new pointer
	inline void set(_T* newPtr) {
		if(ptr)
			ptr->drop();

		ptr = newPtr;
	}

	//Clears the value of the pointer, not handling reference counting
	inline void reset() {
		ptr = 0;
	}

	inline _T* operator-> () {
		return ptr;
	}

	inline const _T* operator-> () const {
		return ptr;
	}

	inline operator _T*() {
		return ptr;
	}

	inline operator const _T*() const {
		return ptr;
	}

	inline void swap(heldPointer<_T>& other) {
		_T* swap_ptr = ptr;
		ptr = other.ptr;
		other.ptr = swap_ptr;
	}

	//Checks if the object pointed to is valid ( via ->isValid() )
	//If it isn't drop the object, and return false
	bool validate() {
		if(ptr) {
			if(ptr->isValid())
				return true;
			ptr->drop();
			ptr = 0;
		}
		return false;
	}

	heldPointer() : ptr(0) {}

	heldPointer(_T& start) : ptr(&start) {
		ptr->grab();
	}

	heldPointer(_T* start) : ptr(start) {
		if(ptr)
			ptr->grab();
	}

	heldPointer(const heldPointer<_T>& copy) : ptr(copy.ptr) {
		if(ptr)
			ptr->grab();
	}

	heldPointer(heldPointer<_T>&& move) : ptr(move.ptr) {
		move.ptr = 0;
	}

	~heldPointer() {
		if(ptr)
			ptr->drop();
	}
};
