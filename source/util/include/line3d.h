#pragma once
#include "vec3.h"

template<class T>
struct line3d {
	vec3<T> start, end;

	line3d() {};
	line3d(const vec3<T>& Start, const vec3<T>& End) : start(Start), end(End) {}

	double getLength() const {
		return start.distanceTo(end);
	}

	double getLengthSQ() const {
		return start.distanceToSQ(end);
	}

	vec3<T> getDirection() const {
		return (end-start).normalized();
	}

	vec3<T> getCenter() const {
		return (end+start) / 2;
	}

	bool intersectX(vec3<T>& point, T x = 0.0, bool segment = true) const {
		vec3<T> dir = end - start;
		if(dir.x == 0)
			return false;
		double pct = (x - start.x) / dir.x;
		if(segment && (pct < 0 || pct > 1))
			return false;
		point = start + dir * pct;
		return true;
	}

	bool intersectY(vec3<T>& point, T y = 0.0, bool segment = true) const {
		vec3<T> dir = end - start;
		if(dir.y == 0)
			return false;
		double pct = (y - start.y) / dir.y;
		if(segment && (pct < 0 || pct > 1))
			return false;
		point = start + dir * pct;
		return true;
	}

	bool intersectZ(vec3<T>& point, T z = 0.0, bool segment = true) const {
		vec3<T> dir = end - start;
		if(dir.z == 0)
			return false;
		double pct = (z - start.z) / dir.z;
		if(segment && (pct < 0 || pct > 1))
			return false;
		point = start + dir * pct;
		return true;
	}

	vec3<T> getClosestPoint(const vec3<T>& p, bool wholeLine = true) const {
		auto ps = p - start;
		auto es = end - start;

		auto lenSQ = getLengthSQ();
		auto psDot = ps.dot(es);

		auto t = psDot / lenSQ;

		if(!wholeLine) {
			if(t <= 0.0)
				return start;
			else if(t >= 1.0)
				return end;
		}
		
		return start + (es * t);
	}

	bool intersectTriangle(const vec3d& v1, const vec3d& v2, const vec3d& v3, vec3d& output) const {
		vec3d direction = end - start;
		vec3d edge1 = v2 - v1;
		vec3d edge2 = v3 - v1;

		vec3d p = direction.cross(edge2);
		double det = edge1.dot(p);
		if(det > -0.00001 && det < 0.00001)
			return false;

		det = 1.0 / det;

		vec3d t = start - v1;
		double u = t.dot(p) * det;
		if(u < 0.0 || u > 1.0)
			return false;

		vec3d q = t.cross(edge1);
		double v = direction.dot(q) * det;
		if(v < 0.0 || u + v > 1.0)
			return false;

		double w = edge2.dot(q) * det;
		if(w > 0.0001) {
			output = start + direction * w;
			return true;
		}

		return false;
	}
};

typedef line3d<int> line3di;
typedef line3d<float> line3df;
typedef line3d<double> line3dd;
