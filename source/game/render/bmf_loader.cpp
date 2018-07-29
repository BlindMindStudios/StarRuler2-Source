#include "bmf_loader.h"
#include <fstream>
#include <map>
#include <string.h>

//BMF Specification (version 0):
//uint32 == "BMF "
//uint32: version number (0 for current version)
//
//uint32: vertex count
//Repeat <vertex count>:
//	float x,y,z: vertex[n] coordinates
//
//uint32: normal count
//Repeat <normal count>:
//	float x,y,z: normal[n] values
//
//uint32: uv count
//Repeat <uv count>:
//	float u,v: uv[n] coordinates
//
//uint32: face count
//Repeat <face count>:
//	If <vertex count> <= 0xffff
//		uint16 v1,v2,v3: face[n] vertex indices
//	Else
//		uint32 v1,v2,v3: face[n] vertex indices
//
//	If <normal count> > 0
//		If <normal count> <= 0xffff
//			uint16 n1,n2,n3: face[n] normal indices
//		Else
//			uint32 n1,n2,n3: face[n] normal indices
//
//	If <uv count> > 0
//		If <uv count> <= 0xffff
//			uint16 u1,u2,u3: face[n] uv indices
//		Else
//			uint32 u1,u2,u3: face[n] uv indices

//First 4 characters of any Binary Mesh File
const char* bmfHead = "BMF ";

namespace render {

namespace bmf {
struct VertexIndex {
	unsigned a, b, c;

	VertexIndex() : a(0), b(0), c(0) {}
	VertexIndex(unsigned A, unsigned B, unsigned C) : a(A), b(B), c(C) {}

	bool operator<(const VertexIndex& other) const {
		return memcmp(this, &other, sizeof(unsigned) * 3) < 0;
	}
};
}

using namespace bmf;


struct UV {
	float u, v;
};

void loadBinaryMesh(const char* filename, Mesh& mesh) {
	static_assert(sizeof(vec3f) == 12, "vec3f must be the size of 3 floats");
	static_assert(sizeof(UV) == 8, "UV must be the size of 2 floats");

	std::vector<vec3f> vertices;
	std::vector<vec3f> normals;
	std::vector<UV> uvs;
	
	std::ifstream file(filename, std::ios_base::binary | std::ios_base::in);
	if(!file.is_open())
		return;

	char buff[4];
	file.read(buff, 4);
	if(file.fail() || strncmp(bmfHead, buff, 4) != 0)
		return;

	unsigned version;
	file.read((char*)&version, sizeof(version));
	if(file.fail() || version != 0)
		return;

	//Vertices
	unsigned count;
	file.read((char*)&count, sizeof(count));
	if(file.fail() || count == 0)
		return;

	vertices.resize(count);
	file.read((char*)&vertices.front(), sizeof(vec3f) * count);

	//Normals
	file.read((char*)&count, sizeof(count));
	if(file.fail())
		return;

	normals.resize(count);
	file.read((char*)&normals.front(), sizeof(vec3f) * count);

	//UVs
	file.read((char*)&count, sizeof(count));
	if(file.fail())
		return;

	uvs.resize(count);
	file.read((char*)&uvs.front(), sizeof(UV) * count);

	//Faces
	file.read((char*)&count, sizeof(count));
	if(file.fail())
		return;

	std::map<VertexIndex,unsigned> vertexMap;

	mesh.faces.reserve(count);
	mesh.vertices.reserve(count);
	for(unsigned i = 0; i < count; ++i) {
		Mesh::Face face;
		Vertex vertex[3];
		VertexIndex vertIndices[3];

		//Load vertex position indices
		for(unsigned j = 0; j < 3; ++j) {
			unsigned index;

			if(vertices.size() <= 0xffff) {
				unsigned short v;
				file.read((char*)&v, sizeof(v));
				index = v;
			}
			else {
				file.read((char*)&index, sizeof(index));
			}

			if(index >= vertices.size())
				index = 0;

			vertex[j].position = vertices[index];
			vertIndices[j].a = index;
		}

		//Load vertex normal indices
		if(!normals.empty()) {
			for(unsigned j = 0; j < 3; ++j) {
				unsigned index;

				if(normals.size() <= 0xffff) {
					unsigned short v;
					file.read((char*)&v, sizeof(v));
					index = v;
				}
				else {
					file.read((char*)&index, sizeof(index));
				}

				if(index >= normals.size())
					index = 0;

				vertex[j].normal = normals[index];
				vertIndices[j].b = index;
			}
		}

		//Load vertex uv indices
		if(!uvs.empty()) {
			for(unsigned j = 0; j < 3; ++j) {
				unsigned index;

				if(uvs.size() <= 0xffff) {
					unsigned short v;
					file.read((char*)&v, sizeof(v));
					index = v;
				}
				else {
					file.read((char*)&index, sizeof(index));
				}

				if(index >= uvs.size())
					index = 0;
				
				vertex[j].u = uvs[index].u;
				vertex[j].v = uvs[index].v;
				vertIndices[j].c = index;
			}
		}

		if(file.fail())
			return;

		//Automatically fuse identical vertices and store results in mesh
		unsigned indices[3];
		for(unsigned j = 0; j < 3; ++j) {
			auto previous = vertexMap.find(vertIndices[j]);
			if(previous != vertexMap.end()) {
				indices[j] = previous->second;
			}
			else {
				indices[j] = (unsigned)mesh.vertices.size();
				mesh.vertices.push_back(vertex[j]);
				vertexMap[vertIndices[j]] = indices[j];
			}
		}
		
		face.a = indices[0];
		face.b = indices[1];
		face.c = indices[2];
		mesh.faces.push_back(face);
	}
}

bool saveBinaryMesh(const char* filename, Mesh& mesh) {
	std::ofstream file(filename, std::ios_base::binary | std::ios_base::out);
	if(!file.is_open())
		return false;

	file.write(bmfHead, 4);
	unsigned version = 0;
	file.write((char*)&version, sizeof(version));

	//TODO: Writes duplicate data unnecessarily

	unsigned count;

	count = (unsigned)mesh.vertices.size();
	file.write((char*)&count, sizeof(count));
	for(unsigned i = 0; i < count; ++i)
		file.write((char*)&mesh.vertices[i].position, sizeof(vec3f));

	count = (unsigned)mesh.vertices.size();
	file.write((char*)&count, sizeof(count));
	for(unsigned i = 0; i < count; ++i)
		file.write((char*)&mesh.vertices[i].normal, sizeof(vec3f));

	count = (unsigned)mesh.vertices.size();
	file.write((char*)&count, sizeof(count));
	for(unsigned i = 0; i < count; ++i) {
		file.write((char*)&mesh.vertices[i].u, sizeof(float));
		file.write((char*)&mesh.vertices[i].v, sizeof(float));
	}

	bool shortIndices = mesh.vertices.size() <= 0xffff;

	count = (unsigned)mesh.faces.size();
	file.write((char*)&count, sizeof(count));
	for(unsigned i = 0; i < count; ++i) {
		Mesh::Face face = mesh.faces[i];
		if(shortIndices) {
			unsigned short data[] = {face.a, face.b, face.c, face.a, face.b, face.c, face.a, face.b, face.c};
			file.write((char*)data, sizeof(data));
		}
		else {
			unsigned data[] = {face.a, face.b, face.c, face.a, face.b, face.c, face.a, face.b, face.c};
			file.write((char*)data, sizeof(data));
		}
	}

	return true;
}

};
