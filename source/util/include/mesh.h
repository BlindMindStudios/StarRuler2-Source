#pragma once
#include "vertex.h"
#include "vec4.h"
#include "color.h"
#include <vector>

struct Mesh {
public:
	struct Face {
		unsigned short a, b, c;

		Face() : a(0), b(0), c(0) {};
		
		Face(unsigned short A, unsigned short B, unsigned short C)
			: a(A), b(B), c(C) {};

		Face(const Face& other) {
			a = other.a;
			b = other.b;
			c = other.c;
		};
	};

	std::vector<Vertex> vertices;
	std::vector<Face> faces;

	std::vector<vec4f> tangents;
	std::vector<Colorf> colors;
	std::vector<vec4f> uvs2;
};
