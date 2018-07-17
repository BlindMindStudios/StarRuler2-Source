#pragma once
#include "../../util/include/vec3.h"

typedef vec3f snd_vec;

//Correct the dimensions to be in the soundcard's space
static inline snd_vec sync(const snd_vec& v) {
	//return snd_vec(-v.x, v.y, -v.z);
	return v;
}

static inline void sync(float& x, float& y, float& z) {
	//x = -x;
	//z = -z;
}

static inline bool valid(const snd_vec& v) {
	if(v.x != v.x || v.y != v.y || v.z != v.z)
		return false;
	if(v.x > 1e32f || v.y > 1e32f || v.z > 1e32f)
		return false;
	return true;
}

static inline bool valid(float x, float y, float z) {
	if(x != x || y != y || z != z)
		return false;
	if(x > 1e32f || y > 1e32f || z > 1e32f)
		return false;
	return true;
}
