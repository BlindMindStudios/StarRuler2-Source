#include "render/x_loader.h"
#include <stdio.h>
#include <string>
#include <fstream>
#include <vector>
#include <deque>
#include "matrix.h"
#include "vec2.h"
#include "mesh.h"
#include "str_util.h"

namespace render {

bool startsWith(const std::string& str, const std::string& start) {
	return str.compare(0, start.size(), start) == 0;
}

void loadXNormals(std::ifstream& file, std::vector<unsigned>& normIndices, std::vector<vec3f>& normals, Matrix& matrix) {
	std::string line;
	std::getline(file, line);
	unsigned norms = 0;
	sscanf(line.c_str(), " %u", &norms);
	normals.reserve(norms);

	//Normals
	for(unsigned i = 0; i < norms; ++i) {
		std::getline(file, line);

		vec3d norm;
		sscanf(line.c_str(), " %lf;%lf;%lf;,", &norm.x, &norm.y, &norm.z);
		normals.push_back(vec3f(matrix.rotate(norm).normalized()));
	}
	
	std::getline(file, line);
	unsigned faces = 0;
	sscanf(line.c_str(), " %u", &faces);
	normIndices.reserve(norms * 4);

	//Face normals
	for(unsigned i = 0; i < faces; ++i) {
		std::getline(file, line);

		unsigned type, indices[4];
		auto args = sscanf(line.c_str(), " %u;%u,%u,%u,%u", &type, &indices[0], &indices[1], &indices[2], &indices[3]);
		if(args >= 4) {
			normIndices.push_back(indices[0]);
			normIndices.push_back(indices[1]);
			normIndices.push_back(indices[2]);

			if(args == 5) {
				normIndices.push_back(indices[0]);
				normIndices.push_back(indices[2]);
				normIndices.push_back(indices[3]);
			}
		}
	}

	do {
		std::getline(file, line);
	} while(file.good() && line.find('}') == std::string::npos);
}

void loadXUVs(std::ifstream& file, std::vector<vec2f>& uvs) {
	std::string line;
	std::getline(file, line);
	unsigned uvCount = 0;
	sscanf(line.c_str(), " %u", &uvCount);
	uvs.reserve(uvCount);

	//Normals
	for(unsigned i = 0; i < uvCount; ++i) {
		std::getline(file, line);

		vec2f uv;
		sscanf(line.c_str(), " %f;%f;,", &uv.x, &uv.y);
		uvs.push_back(uv);
	}

	do {
		std::getline(file, line);
	} while(file.good() && line.find('}') == std::string::npos);
}

void loadXMesh(std::ifstream& file, Mesh& mesh, Matrix& matrix) {
	std::vector<vec2f> uvs;
	std::vector<vec3f> positions, normals;
	std::vector<unsigned> posIndices, normIndices;
	
	std::string line;

	std::getline(file, line);
	unsigned verts = 0;
	sscanf(line.c_str(), " %u", &verts);
	positions.reserve(verts);

	//Vertices
	for(unsigned i = 0; i < verts; ++i) {
		std::getline(file, line);

		vec3d vert;
		sscanf(line.c_str(), " %lf;%lf;%lf;,", &vert.x, &vert.y, &vert.z);
		positions.push_back(vec3f(matrix * vert));
	}

	std::getline(file, line);
	unsigned faces = 0;
	sscanf(line.c_str(), " %u", &faces);
	posIndices.reserve(verts * 4);

	//Faces
	for(unsigned i = 0; i < faces; ++i) {
		std::getline(file, line);

		unsigned type, indices[4];
		auto args = sscanf(line.c_str(), " %u;%u,%u,%u,%u", &type, &indices[0], &indices[1], &indices[2], &indices[3]);
		if(args >= 4) {
			posIndices.push_back(indices[0]);
			posIndices.push_back(indices[1]);
			posIndices.push_back(indices[2]);

			if(args == 5) {
				posIndices.push_back(indices[0]);
				posIndices.push_back(indices[2]);
				posIndices.push_back(indices[3]);
			}
		}
	}

	//Load normals and texture coords
	std::getline(file, line);
	do {
		line = trim(line, " \t");
		if(startsWith(line, "MeshNormals")) {
			loadXNormals(file, normIndices, normals, matrix);
		}
		else if(startsWith(line, "MeshTextureCoords")) {
			loadXUVs(file, uvs);
		}
		else if(line.find('{') != std::string::npos) {
			//Skip unknown { ... } blocks
			unsigned depth = 1;
			while(depth > 0 && file.good()) {
				std::getline(file, line);
				auto pos = line.find_first_of("{}");
				if(pos == std::string::npos)
					continue;
				if(line[pos] == '{')
					++depth;
				else
					--depth;
			}
		}

		std::getline(file, line);
	} while(file.good() && line.find('}') == std::string::npos);
	
	for(unsigned int i = 0; i + 2 < posIndices.size() && i + 2 < normIndices.size(); i += 3) {
		Vertex verts[3];
		for(unsigned v = 0; v < 3; ++v) {
			unsigned pInd = posIndices[i+v], nInd = normIndices[i+v];

			if(pInd >= positions.size() || nInd >= normals.size())
				return; //Out of bounds on our inputs, return what we've gotten so far

			verts[v].position = positions[pInd];
			verts[v].normal = normals[nInd];

			if(pInd < uvs.size()) {
				verts[v].u = uvs[pInd].x;
				verts[v].v = uvs[pInd].y;
			}
		}

		unsigned short base = (unsigned short)mesh.vertices.size();
		mesh.vertices.push_back(verts[0]);
		mesh.vertices.push_back(verts[1]);
		mesh.vertices.push_back(verts[2]);
								
		mesh.faces.push_back(Mesh::Face(base, base+1, base+2));
	}
}

void loadXFrame(std::ifstream& file, Mesh& mesh, Matrix* baseMatrix = 0) {
	Matrix matrix;
	if(baseMatrix)
		matrix = *baseMatrix;

	while(file.good()) {
		std::string line;
		std::getline(file, line);
		line = trim(line, " \t");
		if(line.empty())
			continue;

		if(startsWith(line, "FrameTransformMatrix")) {
			std::getline(file, line);
			Matrix lineMatrix;
			sscanf(line.c_str(), " %lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf;;",
				&lineMatrix[0], &lineMatrix[1], &lineMatrix[2], &lineMatrix[3],
				&lineMatrix[4], &lineMatrix[5], &lineMatrix[6], &lineMatrix[7],
				&lineMatrix[8], &lineMatrix[9], &lineMatrix[10], &lineMatrix[11],
				&lineMatrix[12], &lineMatrix[13], &lineMatrix[14], &lineMatrix[15] );

			if(baseMatrix)
				matrix = *baseMatrix * lineMatrix;
			else
				matrix = lineMatrix;
			std::getline(file, line); //Read the } line off
		}
		else if(startsWith(line, "Frame")) {
			loadXFrame(file, mesh, &matrix);
		}
		else if(startsWith(line, "Mesh")) {
			loadXMesh(file, mesh, matrix);
		}
		else if(line.find('}') != std::string::npos) {
			return;
		}
	}
}

void loadMeshX(const char* filename, Mesh& mesh) {
	std::ifstream file(filename);

	if(file.is_open()) {
		while(file.good()) {
			std::string line;
			std::getline(file, line);
			line = trim(line, " \t");
			if(line.empty())
				continue;

			if(startsWith(line, "Frame"))
				loadXFrame(file, mesh);
		}
	}
}

};
