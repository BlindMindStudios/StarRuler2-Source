#include "render/obj_loader.h"
#include "compat/misc.h"
#include <stdio.h>
#include <string.h>
#include <iostream>
#include <fstream>
#include <string>
#include <map>

namespace render {

struct VertexIndex {
	unsigned int a, b, c;

	VertexIndex(int A, int B, int C) : a(A), b(B), c(C) {}

	bool operator<(const VertexIndex& other) const {
		return memcmp(this, &other, sizeof(int) * 3) < 0;
	}
};

void loadMeshOBJ(const char* filename, Mesh& mesh) {
	// Read all the appropriate separate data arrays
	std::vector<vec3f> vertices;
	std::vector<vec3f> normals;
	std::vector<float> ucoord;
	std::vector<float> vcoord;

	float scale = 1.f;

	std::string line;
	std::ifstream file(filename);
	vec3f vec;

	std::map<VertexIndex, unsigned> vertex_map;

	if(file.is_open()) {
		while(file.good()) {
			std::getline(file, line);

			if(line.size() == 0)
				continue;

			switch(line[0]) {
				case 's':
					if(line[1] == 'c') { //Non-standard extension 'scaling factor'
						sscanf(line.c_str(), "sc %f", &scale);
					}
					break;

				case 'v':
					switch(line[1]) {
						case ' ':
							// Vertex
							sscanf(line.c_str(), "v %f %f %f", &vec.x, &vec.y, &vec.z);
							vec *= scale;
							vertices.push_back(vec);
						break;
						case 'n':
							// Normal
							sscanf(line.c_str(), "vn %f %f %f", &vec.x, &vec.y, &vec.z);
							normals.push_back(vec);
						break;
						case 't':
							// Texture
							float u, v;
							sscanf(line.c_str(), "vt %f %f", &u, &v);
							ucoord.push_back(u);
							vcoord.push_back(v);
						break;
					}
				break;

				case 'f':
					// Face
					int vertsThisLine = 3;
					int vertexIndex[4];
					int uvIndex[4];
					int normalIndex[4];

					int elemIndex[4];

					int items = sscanf(line.c_str(), "f %d/%d/%d %d/%d/%d %d/%d/%d %d/%d/%d",
						&vertexIndex[0], &uvIndex[0], &normalIndex[0],
						&vertexIndex[1], &uvIndex[1], &normalIndex[1],
						&vertexIndex[2], &uvIndex[2], &normalIndex[2],
						&vertexIndex[3], &uvIndex[3], &normalIndex[3]);
					vertsThisLine = items / 3;

					int vertCount = (int)vertices.size();
					int normCount = (int)normals.size();
					int uvCount = (int)ucoord.size();

					for(int i = 0; i < vertsThisLine; ++i) {
						if(vertexIndex[i] > 0)
							vertexIndex[i] -= 1;
						if(normalIndex[i] > 0)
							normalIndex[i] -= 1;
						if(uvIndex[i] > 0)
							uvIndex[i] -= 1;

						if(vertexIndex[i] >= vertCount || vertexIndex[i] < -vertCount)
							goto ignoreFace;
						if(normalIndex[i] >= normCount || normalIndex[i] < -normCount)
							goto ignoreFace;
						if(uvIndex[i] >= uvCount || uvIndex[i] < -uvCount)
							goto ignoreFace;

						if(vertexIndex[i] < 0)
							vertexIndex[i] = vertCount + vertexIndex[i];

						if(normalIndex[i] < 0)
							normalIndex[i] = normCount + normalIndex[i];

						if(uvIndex[i] < 0)
							uvIndex[i] = uvCount + uvIndex[i];

						VertexIndex ind(vertexIndex[i], normalIndex[i], uvIndex[i]);

						auto it = vertex_map.find(ind);
						if(it == vertex_map.end()) {
							Vertex v;
							v.position = vertices[vertexIndex[i]];
							v.normal = normals[normalIndex[i]];
							v.u = ucoord[uvIndex[i]];
							v.v = 1.f - vcoord[uvIndex[i]];

							elemIndex[i] = mesh.vertices.size();
							mesh.vertices.push_back(v);
							vertex_map[ind] = elemIndex[i];
						}
						else {
							elemIndex[i] = it->second;
						}
					}

					if(vertsThisLine >= 3)
						mesh.faces.push_back(Mesh::Face(elemIndex[0], elemIndex[1], elemIndex[2]));
					if(vertsThisLine >= 4)
						mesh.faces.push_back(Mesh::Face(elemIndex[0], elemIndex[2], elemIndex[3]));
					ignoreFace:
				break;
			}
		}
		file.close();
	}
}

};
