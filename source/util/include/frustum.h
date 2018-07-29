#pragma once
#include "plane.h"
#include "line3d.h"
#include "aabbox.h"

struct frustum {
	//Planes are: Near, Left, Right, Top, Bottom, Far
	planed planes[6];
	AABBoxd bound;

	frustum() {}

	frustum(const line3dd& topLeft, const line3dd& topRight, const line3dd& botLeft, const line3dd& botRight) {
		planes[0] = planed(topLeft.start,  botLeft.start,  topRight.start);
		planes[1] = planed(topLeft.start,  topLeft.end,    botLeft.start);
		planes[2] = planed(topRight.end,   topRight.start, botRight.start);
		planes[3] = planed(topLeft.start,  topRight.start, topRight.end);
		planes[4] = planed(botRight.start, botLeft.start,  botRight.end);
		planes[5] = planed(topLeft.end,    topRight.end,   botLeft.end);
		
		bound.reset(topLeft);
		bound.addLine(topRight);
		bound.addLine(botLeft);
		bound.addLine(botRight);
	}

	void operator=(const frustum& other) {
		memcpy(reinterpret_cast<void *>(this), &other, sizeof(frustum));
	}

	bool overlaps(const vec3d& center, double radius) const {
		for(unsigned i = 0; i < 6; ++i)
			if(planes[i].distanceFromPlane(center) <= -radius)
				return false;
		return true;
	}
};
