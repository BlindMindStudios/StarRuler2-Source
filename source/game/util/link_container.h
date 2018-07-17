#pragma once
#include <stdint.h>
#include <stdlib.h>
#include <math.h>

enum LinkContainerBehavior {
	LCB_Unordered,
	LCB_Ordered,
};

/* LinkContainer
 * -------------
 * Base type for a set of containers that are thread-safe to read from.
 * Reads can occur at the same time as writes, but writes must not happen simultaneously!
 * 
 * Intended for use with small data structures that need to be read from multiple threads,
 * and can change but do so infrequently enough that the extra write overhead is negligible.
 *
 * CAVEATS:
 *  - Will never shrink in size. Seriously, only use for small sets.
 *  - Iterating over it is sometimes going to skip an element.
 *  - Getting by index is sometimes going to return null even if index < size.
 * */
template<typename T, unsigned char PoolSize, LinkContainerBehavior Behavior>
class LinkContainer {
protected:
	void* start;
	unsigned int count;

	struct PoolHeader {
		unsigned char filledElements;
		bool contiguous;
		void* next;
	};

	struct PoolElem {
		bool filled;
		T data;
	};

	inline PoolHeader& getHeader(void* mem) const {
		return *(PoolHeader*)mem;
	}

	inline PoolElem& getElem(void* mem, unsigned char index) const {
		unsigned char* dataStart = ((unsigned char*)mem) + sizeof(PoolHeader);
		unsigned char* elemData = dataStart + (sizeof(PoolElem) * index);
		return *(PoolElem*)elemData;
	}

	inline PoolElem& getElem(void* at) const
	{
		return *(PoolElem*)at;
	}

	inline void* allocate(const T& data) {
		auto size = sizeof(PoolHeader) + sizeof(PoolElem) * PoolSize;
		void* pool = malloc(size);
		memset(pool, 0, size);
		auto& header = getHeader(pool);
		header.filledElements = 1;
		header.contiguous = true;
		auto& elem = getElem(pool, 0);
		elem.filled = true;
		elem.data = data;
		return pool;
	}

	inline void* getLast() const {
		void* pool = start;
		while(pool)
		{
			auto& header = getHeader(pool);
			if(header.next)
				pool = header.next;
			else
				return pool;
		}
		return nullptr;
	}

	void checkContiguous(void* pool) {
		auto& header = getHeader(pool);
		bool foundEmpty = false;
		for(unsigned char i = 0; i < header.filledElements; ++i) {
			if(!getElem(pool, i).filled) {
				foundEmpty = true;
				break;
			}
		}
		header.contiguous = !foundEmpty;
	}

	void getIndex(unsigned int index, void*& outPool, unsigned char& outElem) const {
		void* pool = start;
		while(pool) {
			auto& header = getHeader(pool);
			unsigned char cnt = header.filledElements;
			if(index < cnt) {
				if(header.contiguous)
				{
					auto& elem = getElem(pool, index);
					if(elem.filled)
					{
						outPool = pool;
						outElem = index;
						return;
					}
				}

				for(unsigned char i = 0; i < PoolSize; ++i)
				{
					auto& elem = getElem(pool, i);
					if(elem.filled) {
						if(index == 0) {
							outPool = pool;
							outElem = i;
							return;
						}
						else {
							index--;
						}
					}
				}
			}
			else
			{
				index -= cnt;
			}
			pool = header.next;
		}
		outPool = nullptr;
		outElem = -1;
	}

public:
	LinkContainer()
		: start(nullptr), count(0) {
	}

	~LinkContainer() {
		auto* pool = start;
		while(pool) {
			void* next = getHeader(pool).next;
			free(pool);
			pool = next;
		}

		start = nullptr;
		count = 0;
	}

	/* Add a new element to the container. If Behavior was set to Ordered, this
	 * will insert at the end. If not, it will insert at an arbitrary point in
	 * the container. */
	void add(const T& data) {
		// Simple case, we are empty
		if(start == nullptr) {
			start = allocate(data);
			count++;
			return;
		}

		// Go through pools and see what to do
		if(Behavior == LCB_Unordered) {
			// See if we have an existing pool we can insert into
			void* pool = start;
			while (pool) {
				auto& header = getHeader(pool);
				if(header.filledElements < PoolSize) {
					for(unsigned char i = 0; i < PoolSize; ++i) {
						auto& elem = getElem(pool, i);
						if(!elem.filled) {
							header.filledElements++;
							elem.data = data;
							elem.filled = true;
							count++;
							if(!header.contiguous) {
								if(header.filledElements == PoolSize || header.filledElements == i+1)
									header.contiguous = true;
								else
									checkContiguous(pool);
							}
							return;
						}
					}
				}

				if(header.next) {
					pool = header.next;
				}
				else {
					// Create a new pool at the end
					header.next = allocate(data);
					count++;
					return;
				}
			}
		}
		else /*if(Behavior == LCB_Ordered)*/
		{
			// We can only insert into the last pool we have, otherwise we need to create a new one
			auto* pool = getLast();
			auto& header = getHeader(pool);
			if(header.filledElements < PoolSize) {
				unsigned char lastFilled = (unsigned char)-1;
				for(unsigned char i = 0; i < PoolSize; ++i) {
					auto& elem = getElem(pool, PoolSize - i - 1);
					if(elem.filled) {
						lastFilled = PoolSize - i - 1;
						break;
					}
				}

				if(lastFilled + 1 >= PoolSize) {
					// Must create a new pool
					header.next = allocate(data);
					count++;
				}
				else {
					// Insert one past the last filled element
					auto& elem = getElem(pool, lastFilled + 1);
					header.filledElements++;
					elem.data = data;
					elem.filled = true;
					count++;
				}
			}
		}
	}

	bool contains(const T& data) const {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled && elem.data == data)
					return true;
			}
			pool = getHeader(pool).next;
		}
		return false;
	}


	void removeAt(unsigned int index) {
		void* pool;
		unsigned char elem;
		getIndex(index, pool, elem);

		if(pool == nullptr || elem < 0)
		{
			return;
		}

		getElem(pool, elem).filled = false;
		getHeader(pool).filledElements--;
		count--;
		checkContiguous(pool);
	}

	int removeAll(const T& value) {
		int removedCount = 0;
		void* pool = start;
		while (pool) {
			auto& header = getHeader(pool);
			bool removed = false;
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled) {
					if(elem.data == value) {
						elem.filled = false;
						removed = true;
						header.filledElements--;
						count--;
						removedCount++;
					}
				}
			}
			if(removed)
				checkContiguous(pool);
			pool = header.next;
		}
		return removedCount;
	}

	void clear() {
		void* pool = start;
		while (pool) {
			auto& header = getHeader(pool);
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled) {
					header.contiguous = false;
					elem.filled = false;
					header.filledElements--;
					count--;
				}
			}
			pool = header.next;
		}
	}

	/**
	 * Note that due to the threaded nature of this data structure,
	 * this may very well return a nullptr even if index < count,
	 * so make sure to always check.
	 *
	 * It can also of course return a stale (already removed) value,
	 * and iteration might temporarily miss an element that was there before.
	 *
	 * The data structure is guaranteed not to segfault from threaded use, but
	 * value may be slightly wrong sometimes.
	 */
	T* getAt(unsigned int index) const {
		void* pool;
		unsigned char elem;
		getIndex(index, pool, elem);
		if(pool != nullptr && elem >= 0)
		{
			return &getElem(pool, elem).data;
		}
		return nullptr;
	}

	unsigned int size() const {
		return count;
	}

	template<typename CB>
	void iterateAll(CB cb) const {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled)
					cb(elem.data);
			}
			pool = getHeader(pool).next;
		}
	}
};

template<typename T, int PoolSize = 16>
class LinkArray : LinkContainer<T, PoolSize, LCB_Ordered> {};

template<typename T, int PoolSize = 16>
class LinkBucket : LinkContainer<T, PoolSize, LCB_Unordered> {};

/**
 * A very simple O(n) map structure for int64 -> int64/double.
 *
 * Should be used for very small maps when the set of keys changes rarely, and
 * threaded reading of key/value pairs is worth the key lookup and change
 * overhead.
 *
 * Also directly supports value delta tracking.
 */
struct LinkMapElem {
	uint64_t key;
	bool dirty;
	union {
		uint64_t value;
		double doubleValue;
	};
	union {
		uint64_t prevValue;
		double prevDoubleValue;
	};
};

template<int PoolSize = 16>
class LinkMapBase : LinkContainer<struct LinkMapElem, 16, LCB_Unordered> {
private:
	unsigned int dirtyCount;
	union {
		uint64_t defaultInt;
		double defaultDouble;
	};

	inline LinkMapElem* getMapElem(uint64_t key) const {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled && elem.data.key == key)
					return &elem.data;
			}
			pool = getHeader(pool).next;
		}
		return nullptr;
	}

	template<typename T, bool isDouble>
	inline void setTyped(uint64_t key, uint64_t value, T dirtyResolution) {
		void* emptyElem = nullptr;
		void* emptyPool = nullptr;
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled) {
					if(elem.data.key == key) {
						if(!elem.data.dirty && dirtyResolution >= 0) {
							if(dirtyResolution == 0) {
								elem.data.dirty = true;
							}
							else if(isDouble) {
								elem.data.value = value;
								if(fabs(elem.data.doubleValue - elem.data.prevDoubleValue) >= dirtyResolution) {
									elem.data.dirty = true;
									dirtyCount++;
								}
							}
							else {
								elem.data.value = value;
								if(llabs((int64_t)elem.data.value - (int64_t)elem.data.prevValue) >= dirtyResolution) {
									elem.data.dirty = true;
									dirtyCount++;
								}
							}
						}
						else {
							elem.data.value = value;
						}
						return;
					}
				}
				else {
					emptyElem = &elem;
					emptyPool = pool;
				}
			}
			pool = getHeader(pool).next;
		}

		if(emptyElem) {
			auto& header = getHeader(emptyPool);
			header.filledElements++;
			auto& elem = getElem(emptyElem);
			elem.data.key = key;
			elem.data.dirty = true;
			elem.data.value = value;
			elem.data.prevValue = value;
			elem.filled = true;

			count++;
			dirtyCount++;
		}
		else {
			auto* pool = getLast();

			LinkMapElem newElem;
			newElem.key = key;
			newElem.dirty = true;
			newElem.value = value;
			newElem.prevValue = value;
			if(pool)
				getHeader(pool).next = allocate(newElem);
			else
				start = allocate(newElem);

			count++;
			dirtyCount++;
		}
	}
public:
	LinkMapBase() : defaultInt(0), dirtyCount(0) {
	}

	LinkMapBase(uint64_t defaultValue) : defaultInt(defaultValue), dirtyCount(0) {
	}

	LinkMapBase(double defaultValue) : defaultDouble(defaultValue), dirtyCount(0) {
	}

	void setDefaultValue(uint64_t newValue) {
		defaultInt = newValue;
	}

	uint64_t getDefaultValue() const {
		return defaultInt;
	}

	void setDefaultDouble(double newValue) {
		defaultDouble = newValue;
	}

	double getDefaultDouble() const {
		return defaultDouble;
	}

	unsigned int size() const {
		return count;
	}

	uint64_t getKeyAtIndex(unsigned int index) const {
		if(auto* elem = getAt(index))
			return elem->key;
		return -1;
	}

	uint64_t getAtIndex(unsigned int index) const {
		if(auto* elem = getAt(index))
			return elem->value;
		return defaultInt;
	}

	double getDoubleAtIndex(unsigned int index) const {
		if(auto* elem = getAt(index))
			return elem->doubleValue;
		return defaultDouble;
	}

	uint64_t get(uint64_t key) const {
		auto* elem = getMapElem(key);
		if(elem)
			return elem->value;
		else
			return defaultInt;
	}

	double getDouble(uint64_t key) const {
		auto* elem = getMapElem(key);
		if(elem)
			return elem->doubleValue;
		else
			return defaultDouble;
	}

	template<typename CB>
	void iterateAll(CB cb) const {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled)
					cb(elem.data.key, elem.data.value);
			}
			pool = getHeader(pool).next;
		}
	}

	template<typename CB>
	void iterateDirty(CB cb) const {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled && elem.data.dirty)
					cb(elem.data.key, elem.data.value);
			}
			pool = getHeader(pool).next;
		}
	}

	template<typename CB>
	void handleDirty(CB cb) {
		void* pool = start;
		while(pool) {
			for(unsigned char i = 0; i < PoolSize; ++i) {
				auto& elem = getElem(pool, i);
				if(elem.filled && elem.data.dirty) {
					if(cb(elem.data.key, elem.data.value)) {
						elem.data.prevValue = elem.data.value;
						elem.data.dirty = false;
						dirtyCount--;
					}
				}
			}
			pool = getHeader(pool).next;
		}
	}

	bool getDirtyCount() const {
		return dirtyCount;
	}

	bool hasDirty() const {
		return dirtyCount != 0;
	}

	bool isDirty(uint64_t key) const {
		auto* elem = getMapElem(key);
		return elem != nullptr && elem->dirty;
	}

	bool contains(uint64_t key) const {
		return getMapElem(key) != nullptr;
	}

	void set(uint64_t key, uint64_t value, int64_t dirtyResolution = 0) {
		setTyped<int64_t,true>(key, value, dirtyResolution);
	}

	void setDouble(uint64_t key, double value, double dirtyResolution = 0.0) {
		setTyped<double,true>(key, reinterpret_cast<uint64_t&>(value), dirtyResolution);
	}
};

typedef LinkMapBase<> LinkMap;
