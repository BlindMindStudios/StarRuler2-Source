#include "IAudioReference.h"
#include "threads.h"

namespace audio {

IAudioReference::~IAudioReference() {}

IAudioReference::IAudioReference() : references(1) {}

void IAudioReference::grab() const {
	++(*(threads::atomic_int*)&references);
}

void IAudioReference::drop() const {
	if(--(*(threads::atomic_int*)&references) == 0)
		delete this;
}

};
