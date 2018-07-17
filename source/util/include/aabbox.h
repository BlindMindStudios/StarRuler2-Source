#pragma once
#include "vec3.h"
#include "line3d.h"
#include "matrix.h"
#include "sse.h"
#include <algorithm>

//Axis-Aligned Bounding Box
template<class T>
struct AABBox {
	vec3<T> minimum, maximum;

	AABBox() {}
	AABBox(const AABBox& other) : minimum(other.minimum), maximum(other.maximum) {}
	AABBox(const vec3<T>& start) : minimum(start), maximum(start) {}
	AABBox(const vec3<T>& minvec, const vec3<T>& maxvec) : minimum(minvec), maximum(maxvec) {}
	AABBox(T minX, T minY, T minZ, T maxX, T maxY, T maxZ) : minimum(minX, minY, minZ), maximum(maxX, maxY, maxZ) {}
	AABBox(const line3d<T>& line) : minimum(line.start), maximum(line.end) { fix(); }

	AABBox(const line3d<T>& line, double width) : minimum(line.start), maximum(line.end) {
		fix();
		minimum -= vec3d(width);
		maximum += vec3d(width);
	}

	inline static AABBox fromCircle(const vec3<T>& center, T radius) {
		return AABBox(center.x - radius, center.y - radius, center.z - radius,
					center.x + radius, center.y + radius, center.z + radius);
	}

	bool operator==(const AABBox& other) const {
		return minimum == other.minimum && maximum != other.maximum;
	}

	bool operator!=(const AABBox& other) const {
		return !(*this == other);
	}

	vec3<T> getSize() const {
		return maximum - minimum;
	}

	vec3<T> getCenter() const {
		return (minimum + maximum) * 0.5;
	}

	bool overlaps(const vec3<T>& point) const {
		return (point.x >= minimum.x && point.x <= maximum.x &&
				point.y >= minimum.y && point.y <= maximum.y &&
				point.z >= minimum.z && point.z <= maximum.z);
	}

	bool isWithin(const AABBox& other) const {
		return  minimum.x >= other.minimum.x &&
				minimum.y >= other.minimum.y &&
				minimum.z >= other.minimum.z &&
				maximum.x <= other.maximum.x &&
				maximum.y <= other.maximum.y &&
				maximum.z <= other.maximum.z;
	}

	bool overlaps(const vec3<T>& center, double radius) const {
		if(overlaps(center))
			return true;
		vec3<T> axisDist;

		if(center.x < minimum.x)
			axisDist.x = minimum.x - center.x;
		else if(center.x > maximum.x)
			axisDist.x = maximum.x - center.x;

		if(axisDist.x > radius)
			return false;

		if(center.y < minimum.y)
			axisDist.y = minimum.y - center.y;
		else if(center.y > maximum.y)
			axisDist.y = maximum.y - center.y;

		if(axisDist.y > radius)
			return false;

		if(center.z < minimum.z)
			axisDist.z = minimum.z - center.z;
		else if(center.z > maximum.z)
			axisDist.z = maximum.z - center.z;

		if(axisDist.z > radius)
			return false;

		return axisDist.getLengthSQ() <= radius * radius;
	}

	bool overlaps(const AABBox& other) const {
		if( minimum.x > other.maximum.x ||
			minimum.z > other.maximum.z ||
			maximum.x < other.minimum.x ||
			maximum.z < other.minimum.z ||
			minimum.y > other.maximum.y ||
			maximum.y < other.minimum.y )
			return false;
		return true;
	}

	//Resets the bounding box to bound around a single point (0,0,0 by default)
	void reset(vec3<T> initialize = vec3<T>(0,0,0)) {
		minimum = initialize;
		maximum = initialize;
	}

	void reset(const AABBox& initialize) {
		minimum = initialize.minimum;
		maximum = initialize.maximum;
	}

	void reset(const line3d<T>& initialize) {
		minimum = initialize.start;
		maximum = initialize.end;
		fix();
	}

	//Expands the bounding box to contain a point
	void addPoint(const vec3<T>& point) {
#define BBOX_POINTDIM(dim) if(point.dim < minimum.dim) minimum.dim = point.dim;\
					else if(point.dim > maximum.dim) maximum.dim = point.dim;
		
		BBOX_POINTDIM(x);
		BBOX_POINTDIM(y);
		BBOX_POINTDIM(z);
	}

	void addBox(const AABBox& box) {
#define BBOX_BOXDIM(dim) if(box.minimum.dim < minimum.dim) minimum.dim = box.minimum.dim;\
						 if(box.maximum.dim > maximum.dim) maximum.dim = box.maximum.dim;
		
		BBOX_BOXDIM(x);
		BBOX_BOXDIM(y);
		BBOX_BOXDIM(z);
	}

	void addLine(const line3d<T>& line) {
		addPoint(line.start);
		addPoint(line.end);
	}

	//Flips any bounds where Minimum > Maximum
	void fix() {
		if(minimum.x > maximum.x) {
			T temp = maximum.x;
			maximum.x = minimum.x;
			minimum.x = temp;
		}
		
		if(minimum.y > maximum.y) {
			T temp = maximum.y;
			maximum.y = minimum.y;
			minimum.y = temp;
		}
		
		if(minimum.z > maximum.z) {
			T temp = maximum.z;
			maximum.z = minimum.z;
			minimum.z = temp;
		}
	}

	//Get a rectangle size after a projection
	vec3d getProjectedSize(const Matrix& transform) const {
		AABBox result;

		for(int i = 0; i < 8; ++i) {
			vec3d point;
			point.x = (i & 1) ? minimum.x : maximum.x;
			point.y = (i & 2) ? minimum.y : maximum.y;
			point.z = (i & 4) ? minimum.z : maximum.z;
			point = transform * point;

			if(i == 0)
				result.reset(point);
			else
				result.addPoint(point);
		}

		return result.getSize();
	}
};

typedef AABBox<double> AABBoxd;
typedef AABBox<float> AABBoxf;
