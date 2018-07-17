#include "util/elevation_map.h"
#include "main/references.h"
#include "compat/misc.h"
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include "BiPatch/bilinear.h"
#include "main/logging.h"

ElevationMap::ElevationMap()
	: generated(false), grid(0) {
}

ElevationMap::~ElevationMap() {
	if(generated)
		free(grid);
}

void ElevationMap::clear() {
	points.clear();
	if(generated) {
		free(grid);
		grid = 0;
		generated = false;
	}
}

void ElevationMap::addPoint(const vec3d& point, double radius) {
	Point p = {point, radius};
	points.push_back(p);
}

void ElevationMap::generate(const vec2d& interval, double power) {
	//Clear previous grid
	if(generated) {
		free(grid);
		grid = 0;
	}

	//A grid with no points is pretty pointless (haha)
	if(points.empty()) {
		generated = true;
		grid = 0;
		gridStart = vec3d();
		gridSize = vec2d();
		gridInterval = vec2d();
		return;
	}

	double start = devices.driver->getAccurateTime();

	//Get the extents of the grid
	vec2d topLeft(points[0].center.x, points[0].center.z);
	vec2d botRight = topLeft;
	double avgHeight = 0.0;

	foreach(p, points) {
		if(p->center.x - p->radius < topLeft.x)
			topLeft.x = p->center.x - p->radius;
		if(p->center.x + p->radius > botRight.x)
			botRight.x = p->center.x + p->radius;
		if(p->center.z - p->radius < topLeft.y)
			topLeft.y = p->center.z - p->radius;
		if(p->center.z + p->radius > botRight.y)
			botRight.y = p->center.z + p->radius;
		avgHeight += p->center.y;
	}

	avgHeight /= points.size();
	gridSize = botRight - topLeft;
	gridStart = vec3d(topLeft.x, avgHeight, topLeft.y);
	gridInterval = interval;
	gridResolution.x = (int)ceil(gridSize.x / gridInterval.x);
	gridResolution.y = (int)ceil(gridSize.y / gridInterval.y);
	minHeight = HUGE_VAL;
	maxHeight = -HUGE_VAL;

	//Create the big grid for optimization
	std::vector<std::vector<Point>> bigGrid;
	unsigned bigGridSize = std::max((unsigned)sqrt((double)points.size()), 1u);
	bigGrid.resize(bigGridSize * bigGridSize);
	double bigInterval = gridSize.x / bigGridSize;

	foreach(p, points) {
		unsigned bigX = std::min((unsigned)((p->center.x - topLeft.x) / bigInterval), bigGridSize - 1);
		unsigned bigY = std::min((unsigned)((p->center.z - topLeft.y) / bigInterval), bigGridSize - 1);

		bigGrid[bigX + (bigY * bigGridSize)].push_back(*p);
	}

	//Interpolate within the grid
	grid = (float*)calloc(gridResolution.x * gridResolution.y, sizeof(float));
	generated = true;

	vec2d realPos;
	double height;
	double totalWeight = 0.0;

	auto calcBucket = [&](unsigned bigX, unsigned bigY) {
		if(bigX >= bigGridSize || bigY >= bigGridSize)
			return;

		auto& bucket = bigGrid[bigX + (bigY * bigGridSize)];
		foreach(it, bucket) {
			//Check if the point is inside a system
			vec2d flatPos(it->center.x, it->center.z);
			double dist = realPos.distanceTo(flatPos);

			if(dist < it->radius) {
				height = it->center.y;
				totalWeight = 1.0;
				break;
			}

			//Do inverse distance weighting
			double w = 1.0 / pow(dist - it->radius, power);
			height += it->center.y * w;
			totalWeight += w;
		}
	};

	for(int iy = 0; iy < gridResolution.y; ++iy) {
		for(int ix = 0; ix < gridResolution.x; ++ix) {
			realPos = vec2d(gridStart.x + ix * gridInterval.x,
						gridStart.z + iy * gridInterval.y);

			height = 0.0;
			totalWeight = 0.0;

			unsigned bigX = std::min((unsigned)((realPos.x - gridStart.x) / bigInterval), bigGridSize - 1);
			unsigned bigY = std::min((unsigned)((realPos.y - gridStart.z) / bigInterval), bigGridSize - 1);

			calcBucket(bigX - 1, bigY - 1);
			calcBucket(bigX, bigY - 1);
			calcBucket(bigX + 1, bigY - 1);

			calcBucket(bigX - 1, bigY);
			calcBucket(bigX, bigY);
			calcBucket(bigX + 1, bigY);

			calcBucket(bigX - 1, bigY + 1);
			calcBucket(bigX, bigY + 1);
			calcBucket(bigX + 1, bigY + 1);

			if(totalWeight == 0) {
				height = avgHeight;
			}
			else {
				height /= totalWeight;
				if(height < minHeight)
					minHeight = height;
				if(height > maxHeight)
					maxHeight = height;
			}

			grid[iy * gridResolution.x + ix] = (float)height;
		}
	}

	if(maxHeight == minHeight) {
		maxHeight += 1.0;
		minHeight -= 1.0;
	}

	double time = devices.driver->getAccurateTime() - start;
	info("Elevation grid took %.3gms to calculate.", time * 1000.0);
}

double ElevationMap::lookup(int x, int y) {
	if(gridResolution.x == 0 || gridResolution.y == 0)
		return 0.0;
	x = std::max(std::min(x, gridResolution.x - 1), 0);
	y = std::max(std::min(y, gridResolution.y - 1), 0);
	return (double)grid[y * gridResolution.x + x];
}

double ElevationMap::get(vec2d point) {
	return get(point.x, point.y);
}

double ElevationMap::get(double x, double y) {
	//Move coordinates to grid coordinates
	x = (x - gridStart.x) / gridInterval.x;
	y = (y - gridStart.z) / gridInterval.y;

	//Get the coordinates of the nearby points
	int lx = (int)floor(x);
	int ly = (int)floor(y);
	int rx = lx + 1;
	int ry = ly + 1;

	//Interpolate the values
	double value = 0.0;
	value += lookup(lx, ly) * ((double)rx - x) * ((double)ry - y);
	value += lookup(rx, ly) * (x - (double)lx) * ((double)ry - y);
	value += lookup(lx, ry) * ((double)rx - x) * (y - (double)ly);
	value += lookup(rx, ry) * (x - (double)lx) * (y - (double)ly);
	return value;
}

bool ElevationMap::getClosestPoint(const line3dd& inLine, vec3d& closestPoint) {
	if(!generated)
		return false;

	//Limit the line to the confines of the 3d grid
	// Always make sure the end goes to the other plane, or a line that stops before the region will never collide
	vec3d start = inLine.start, end = inLine.end;
	if(inLine.start.y > inLine.end.y) {
		if(start.y > maxHeight)
			inLine.intersectY(start, maxHeight, false);
		inLine.intersectY(end, minHeight, false);
	}
	else {
		if(start.y < minHeight)
			inLine.intersectY(start, minHeight, false);
		inLine.intersectY(end, maxHeight, false);
	}
	line3dd line(start, end);

	vec3d lineDir = line.end - line.start;
	BiPatch::Vector rayOrigin(line.start.x, line.start.y, line.start.z);
	BiPatch::Vector rayDir(lineDir.x, lineDir.y, lineDir.z);
	rayDir.normalize();
	BiPatch::Vector uv;

	//Flatten the line to intelligently chose grid spaces to test
	line3dd flatLine(start, end);
	flatLine.start.y = 0;
	flatLine.end.y = 0;

	vec3d flatPoint = flatLine.start;
	vec3d flatDir = flatLine.getDirection();

	int x =	(int)floor((flatLine.start.x - gridStart.x) / gridInterval.x);
	int y = (int)floor((flatLine.start.z - gridStart.z) / gridInterval.y);

	for(unsigned checks = 0; checks < 1000; ++checks) {
		//See if we have a collision
		double absx = gridStart.x + (gridInterval.x * double(x));
		double absy = gridStart.z + (gridInterval.y * double(y));

		BiPatch::Vector tl(absx, lookup(x, y), absy);
		BiPatch::Vector tr(absx + gridInterval.x, lookup(x+1, y), absy);
		BiPatch::Vector bl(absx, lookup(x, y+1), absy + gridInterval.y);
		BiPatch::Vector br(absx + gridInterval.x, lookup(x+1, y+1), absy + gridInterval.y);

		BiPatch::BilinearPatch bp(tl, tr, bl, br);
		if(bp.RayPatchIntersection(rayOrigin, rayDir, uv)) {
			BiPatch::Vector point = bp.SrfEval(uv.x(), uv.y());
			vec3d intersect(point.x(), point.y(), point.z());

			//Once we have a collision, it must be the closest point
			double dot = (intersect - line.start).dot(line.getDirection());
			if(dot >= -0.0001) {
				closestPoint = intersect;
				return true;
			}
		}

		//Step to the next grid section
		if(flatDir.z > 0) {
			vec3d intersect;
			flatLine.intersectZ(intersect, absy + gridInterval.y, false);
			if(intersect.x < absx + gridInterval.x && intersect.x > absx) {
				y += 1;
			}
			else if(flatDir.x > 0) {
				x += 1;
				flatLine.intersectX(intersect, absx + gridInterval.x, false);
			}
			else {
				x -= 1;
				flatLine.intersectX(intersect, absx, false);
			}
			flatPoint = intersect;
		}
		else {//if(flatDir.z <= 0) {
			vec3d intersect;
			flatLine.intersectZ(intersect, absy, false);
			if(intersect.x < absx + gridInterval.x && intersect.x > absx) {
				y -= 1;
			}
			else if(flatDir.x > 0) {
				x += 1;
				flatLine.intersectX(intersect, absx + gridInterval.x, false);
			}
			else {
				x -= 1;
				flatLine.intersectX(intersect, absx, false);
			}
			flatPoint = intersect;
		}
	}

	return false;
}
