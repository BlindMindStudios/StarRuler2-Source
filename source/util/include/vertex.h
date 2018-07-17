#pragma once
#include "vec3.h"

struct Vertex {
	float u, v;
	vec3f normal, position;

	Vertex() : u(0), v(0) {}
	explicit Vertex(const vec3f& pos) : position(pos), normal(pos.normalized()), u(0), v(0) {}
	explicit Vertex(const vec3f& pos, float U, float V) : position(pos), normal(pos.normalized()), u(U), v(V) {}
};
