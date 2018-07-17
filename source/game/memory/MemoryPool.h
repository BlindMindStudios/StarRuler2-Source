#pragma once
#include <memory>

namespace memory {

//A pre-allocated pool of uniformly sized objects
template<class T>
class MemoryPool {
	T* pPool, *pEnd;
	unsigned short* indices;
	unsigned nextIndex;

public:
	MemoryPool(unsigned count) {
		if(count > 65535)
			count = 65535;
		nextIndex = count-1;

		pPool = (T*)new unsigned char[count * sizeof(T)];
		pEnd = pPool + count;

		indices = new unsigned short[count];
		for(unsigned short i = 0; i < count; ++i)
			indices[i] = count-i;
	}

	~MemoryPool() {
		delete[] (unsigned char*)pPool;
		delete[] indices;
	}

	void* alloc() {
		if(nextIndex != 0xffffffff) {
			return pPool + indices[nextIndex--];
		}
		else {
			return ::operator new(sizeof(T));
		}
	}

	void dealloc(T* p) {
		if(p >= pPool && p < pEnd) {
			indices[++nextIndex] = p - pPool;
		}
		else {
			::operator delete(p);
		}
	}
};

};