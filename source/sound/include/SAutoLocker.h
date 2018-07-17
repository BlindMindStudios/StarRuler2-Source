#pragma once

namespace audio {
	template<class T>
	struct SAutoLocker {
		T* obj;

		SAutoLocker(T* Object) { obj = Object; obj->lock(); }
		~SAutoLocker() { obj->unlock(); }
	};
};