#pragma once

namespace audio {

template<class T>
struct SAutoDrop {
	T* pRef;

	void clear() { pRef = 0; }

	SAutoDrop(T* object) : pRef(object) {}

	~SAutoDrop() {
		if(pRef) pRef->drop();
	}
};

};