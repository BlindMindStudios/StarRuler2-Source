#include "mesh.h"
#include "constants.h"

Mesh* generateSphereMesh(unsigned int vertical, unsigned int horizontal) {
	if(vertical < 2)
		vertical = 2;
	if(horizontal < 2)
		horizontal = 2;

	float vf = (float)vertical, hf = (float)horizontal;

	Mesh& mesh = *(new Mesh());
	mesh.vertices.reserve((vertical+1) * (horizontal+1));

	//v == 0
	for(unsigned int h = 0; h <= horizontal; ++h) {
		Vertex vert;

		vert.position = vec3f(0,1,0);
		vert.normal = vert.position;
		vert.u = (float)h/hf;
		vert.v = 0;

		mesh.vertices.push_back(vert);
	}
	
	for(unsigned int v = 1; v < vertical; ++v) {
		float sinz = (float)sin(pi/2.f - (pi * (float)v/vf));
		float cosz = (float)cos(pi/2.f - (pi * (float)v/vf));

		for(unsigned int h = 0; h <= horizontal; ++h) {
			float angle = (float)twopi * (float)(h % horizontal)/hf; //Force angle on both ends to be identical
			Vertex vert;

			vert.position = vec3f(cos(angle) * cosz, sinz, sin(angle) * cosz);
			vert.normal = vert.position;
			vert.u = (float)h/hf;
			vert.v = (float)v/vf;

			mesh.vertices.push_back(vert);
		}
	}

	//v == vertical
	for(unsigned int h = 0; h <= horizontal; ++h) {
		Vertex vert;

		vert.position = vec3f(0,-1,0);
		vert.normal = vert.position;
		vert.u = (float)h/hf;
		vert.v = 1.f;

		mesh.vertices.push_back(vert);
	}
	
	mesh.faces.reserve((2 * (vertical-2) * horizontal) + (2 * horizontal));
	for(unsigned int v = 0; v < vertical; ++v) {
		unsigned int stride = horizontal+1, line = v * stride, nextline = (v+1) * stride;
		for(unsigned int h = 0; h < horizontal; ++h) {
			if(v != 0)
				mesh.faces.push_back(Mesh::Face(h+line,h+line+1,h+nextline));
			if(v != vertical-1)
				mesh.faces.push_back(Mesh::Face(h+line+1,h+nextline+1,h+nextline));
		}
	}

	return &mesh;
}
