#pragma once
#include "vec2.h"
#include "vec3.h"
#include "line3d.h"
#include <vector>

/*
 * An elevation map takes an irregularly spaced
 * set of points, precalculates a regular grid of
 * smoothly interpolated heights and then allows
 * for elevation lookup for arbitrary locations.
 */

class ElevationMap {
public:
	struct Point {
		vec3d center;
		double radius;
	};
	std::vector<Point> points;
	bool generated;
	float* grid;

	vec3d gridStart;
	vec2d gridSize;
	vec2d gridInterval;
	vec2i gridResolution;
	double minHeight;
	double maxHeight;

	void clear();
	void addPoint(const vec3d& point, double radius = 0.0);
	void generate(const vec2d& interval, double power = 2.0);

	double lookup(int x, int y);

	double get(vec2d point);
	double get(double x, double y);

	bool getClosestPoint(const line3dd& line, vec3d& point);

	ElevationMap();
	~ElevationMap();
};
