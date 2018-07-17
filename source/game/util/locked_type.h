#include "threads.h"

template<class T>
struct LockedType {
	threads::Mutex lock;
	T value;

	LockedType() : value() {}
	LockedType(T v) : value(v) {}
	LockedType(const LockedType& other) : value(other.value) {}
	~LockedType() {}

	T operator+=(T v) {
		lock.lock();
		T r = value + v;
		value = r;
		lock.release();
		return r;
	}

	T operator-=(T v) {
		lock.lock();
		T r = value - v;
		value = r;
		lock.release();
		return r;
	}

	T operator*=(T v) {
		lock.lock();
		T r = value * v;
		value = r;
		lock.release();
		return r;
	}

	T operator/=(T v) {
		lock.lock();
		T r = value / v;
		value = r;
		lock.release();
		return r;
	}

	T operator|=(T v) {
		lock.lock();
		T r = value | v;
		value = v;
		lock.release();
		return r;
	}

	T operator^=(T v) {
		lock.lock();
		T r = value ^ v;
		value = v;
		lock.release();
		return r;
	}

	T operator&=(T v) {
		lock.lock();
		T r = value & v;
		value = v;
		lock.release();
		return r;
	}

	T operator=(T v) {
		lock.lock();
		value = v;
		lock.release();
		return v;
	}

	T minimum(T v) {
		lock.lock();
		T r = v < value ? v : value;
		value = r;
		lock.release();
		return r;
	}

	T maximum(T v) {
		lock.lock();
		T r = v > value ? v : value;
		value = r;
		lock.release();
		return r;
	}

	T avg(T v) {
		lock.lock();
		T r = (T)( ((double)v + (double)value) * 0.5 );
		value = r;
		lock.release();
		return r;
	}

	T consume(T amount) {
		lock.lock();
		T take;
		if(value < amount)
			if(value > 0)
				take = value;
			else
				take = 0;
		else
			take = amount;
		value -= take;
		lock.release();
		return take;
	}

	T interp(T toward, double percent) {
		lock.lock();
		T r = (T)( ((double)(toward - value) * percent) + (double)toward );
		value = r;
		lock.release();
		return r;
	}

	T toggle() {
		lock.lock();
		T r = value == 0 ? T(1) : T(0);
		value = r;
		lock.release();
		return r;
	}
};

template<class T>
struct LockedHandle {
	//Define an invalid pointer as a 'locked' state for a handle. Should be
	//faster than a full mutex and takes less memory.
	static const unsigned spinCount = 5;
	static const size_t INVALID_PTR = (size_t)-1;
	mutable void* value;

	LockedHandle() : value(0) {}
	LockedHandle(T* v) : value(0) { set(v); }
	LockedHandle(const LockedHandle<T>& other) : value(0) { set(other.get()); }
	~LockedHandle() { set(0); }

	T* acquire() const {
		void* ptr = value;
		int spins = 0;
		while(ptr == (void*)INVALID_PTR || threads::compare_and_swap(&value, ptr, (void*)INVALID_PTR) != ptr) {
			ptr = value;

			++spins;
			if(spins == spinCount) {
				threads::sleep(0);
				spins = 0;
			}
		}
		return (T*)ptr;
	}

	void release(T* ptr) const {
		value = ptr;
	}

	LockedHandle& operator=(T* value) {
		set(value);
		return *this;
	}

	//Get the pointer value
	// Will grab a refenence before returning,
	// so make sure you release it when done.
	T* get() const {
		T* ptr = acquire();
		if(ptr)
			ptr->grab();
		release(ptr);
		return ptr;
	}

	//Safe get for when it's assured no writes are taking
	//place. Still needs to avoid other reads, though.
	T* get_safe() const {
		T* ptr;
		do {
			ptr = (T*)value;
		}
		while(ptr == (T*)INVALID_PTR);

		if(ptr)
			ptr->grab();
		return ptr;
	}

	//Set the value, keeping all the reference stuff valid.
	void set(T* ptr) {
		if(ptr)
			ptr->grab();
		set_withref(ptr);
	}

	void set_withref(T* ptr) {
		void* newval = (void*)ptr;
		void* oldval = (void*)value;
		int spins = 0;
		while(true) {
			if(oldval == (void*)INVALID_PTR) {
				oldval = value;

				++spins;
				if(spins == spinCount) {
					threads::sleep(0);
					spins = 0;
				}
				continue;
			}
			void* res = threads::compare_and_swap(&value, oldval, newval);
			if(res == oldval)
				break;
			oldval = res;
		};
		ptr = (T*)oldval;
		if(ptr)
			ptr->drop();
	}
};
