#pragma once
#include "threads.h"
#include <functional>

//Implements a 'lockless' data type. Operations can still
//take longer amounts of time depending on concurrency, but
//are not as expensive as a full locked type.
#define LOCKLESS_PRE \
	union { swappable s; T real; } local, stored;\
	stored.s = swap;\
	local.s = 0;\
	T& previous = stored.real;\
	do {

#define LOCKLESS_POST\
		swappable chk = threads::compare_and_swap(&swap, stored.s, local.s);\
		if(chk == stored.s)\
			break;\
		stored.s = chk;\
	}\
	while (true);

template<class T, class swappable = long long>
struct LocklessType {
	static_assert(sizeof(T) <= sizeof(swappable), "type too big");
	union {
	swappable swap;
	T value;
	};

	LocklessType() : swap(0) {}
	LocklessType(T v) : swap(0) { set(v); }
	LocklessType(const LocklessType& other) : value(other.value) {}
	~LocklessType() {}

	//Atomically perform an operation on the value
	//The operation should be pure (no side effects) and
	//efficient (can be executed multiple times viably).
	//  Returns the new value that was placed.
	T set(const std::function<T(T)>& operation) {
		union { swappable s; T real; } local, stored;
		stored.s = swap;
		local.s = 0;
		do {
			local.real = operation(stored.real);
			swappable chk = threads::compare_and_swap(&swap, stored.s, local.s);
			if(chk == stored.s)
				break;
			stored.s = chk;
		} while(true);
		return stored.s;
	}

	T get() {
		return value;
	}

	T set(T v) {
		value = v;
		return v;
	}

	operator T() {
		return get();
	}

	T operator+=(T v) {
		return set([v](T p) -> T { return p + v; });
	}

	T operator-=(T v) {
		return set([v](T p) -> T { return p - v; });
	}

	T operator*=(T v) {
		return set([v](T p) -> T { return p * v; });
	}

	T operator/=(T v) {
		return set([v](T p) -> T { return p / v; });
	}

	T operator|=(T v) {
		return set([v](T p) -> T { return p | v; });
	}

	T operator^=(T v) {
		return set([v](T p) -> T { return p ^ v; });
	}

	T operator&=(T v) {
		return set([v](T p) -> T { return p & v; });
	}

	T operator=(T v) {
		return set(v);
	}

	T operator|(T v) {
		return value | v;
	}

	T operator&(T v) {
		return value & v;
	}

	T minimum(T v) {
		return set([v](T p) -> T { return v < p ? v : p; });
	}

	T maximum(T v) {
		return set([v](T p) -> T { return v > p ? v : p; });
	}

	T avg(T v) {
		return set([v](T p) -> T { return (T)(((double)v + (double)p) * 0.5); });
	}

	T consume(T amount) {
		T take;
		set([&](T p) -> T { 
			if(p < amount)
				if(p > 0)
					take = p;
				else
					take = 0;
			else
				take = amount;
			return p - take;
		});
		return take;
	}

	T interp(T toward, double percent) {
		return set([&](T p) -> T { 
			return (T)(((double)(toward - p) * percent) + (double)toward);
		});
	}

	T toggle() {
		return set([&](T p) -> T { 
			return p == 0 ? (T)1 : (T)0;
		});
	}
};

typedef LocklessType<int,int> LocklessInt;
typedef LocklessType<float,int> LocklessFloat;
typedef LocklessType<double,long long> LocklessDouble;
