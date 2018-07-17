#pragma once
#include "vec3.h"

template<class T>
struct plane {
	vec3<T> dir;
	T dist;

	plane() : dist(0) {}

	plane(const vec3<T>& direction, T distance) : dir(direction), dist(distance) {
	}

	plane(const vec3<T>& point, const vec3<T>& direction) : dir(direction), dist((T)point.dot(direction)) {
	}

	//Creates a plane from a triangle specified in clockwise order (looking at the plane)
	plane(const vec3<T>& vertA, const vec3<T>& vertB, const vec3<T>& vertC) {
		vec3<T> legOne = vertA - vertB, legTwo = vertC - vertB;

		dir = legOne.cross(legTwo).normalized();
		dist = (T)dir.dot(vertA);
	}

	double distanceFromPlane(const vec3<T>& point) const {
		return dir.dot(point) - dist;
	}

	bool pointInFront(const vec3<T>& point) const {
		return distanceFromPlane(point) >= 0.0;
	}
};

typedef plane<double> planed;