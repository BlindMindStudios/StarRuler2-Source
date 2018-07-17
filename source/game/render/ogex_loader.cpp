#include "render/ogex_loader.h"
#include "str_util.h"
#include <stdio.h>
#include <string.h>
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <memory>
#include "vec2.h"
#include "matrix.h"

namespace render {

struct GEXGeometry {
	std::vector<vec3f> positions, normals;
	std::vector<vec2f> uvs[3];
	std::vector<Colorf> colors;
	std::vector<Mesh::Face> faces;
};

struct GEXNode {
	Matrix transform;
	std::string meshID;
	std::vector<GEXNode*> nodes;

	GEXNode& makeChild() {
		auto* node = new GEXNode();
		nodes.push_back(node);
		return *node;
	}

	void clear() {
		for(auto i = nodes.begin(), end = nodes.end(); i != end; ++i) {
			(**i).clear();
			delete *i;
		}
	}
};

struct GEXSection {
	std::string id, attrib;
	GEXNode* node;
};

struct StringView {
	std::string str;
	std::string::size_type start;
	
	StringView() : start(0) {
	}

	StringView(const std::string& s) : start(0), str(s) {
	}

	void operator=(const std::string& s) {
		str = s;
		start = 0;
	}

	std::string::size_type find(char c) {
		auto x = str.find(c, start);
		if(x != std::string::npos)
			return x - start;
		else
			return x;
	}

	void substr(std::string& out, std::string::size_type first, std::string::size_type count) {
		out.assign(str.begin() + (start + first), str.begin() + (start + first + count));
	}

	void advance(std::string::size_type off) {
		start += off;
	}
};

static std::string& extractSegment(StringView& data, std::string& out) {
	out.clear();
	auto start = data.find('{');
	auto pos = data.find('}');
	if(pos == std::string::npos || start == std::string::npos || start > pos)
		return out;
	data.substr(out, start+1,pos-(start+1));
	data.advance(pos+1);
	return out;
}

void loadMeshOGEX(const char* filename, Mesh& mesh) {
	std::string line, segment;
	StringView data;
	std::ifstream file(filename);

	if(!file.is_open())
		return;

	unsigned row = 0;

	GEXSection section;
	GEXNode root;
	GEXNode* node = &root;

	std::stack<GEXSection> sections;
	std::unordered_map<std::string, std::unique_ptr<GEXGeometry>> parts;
	GEXGeometry* part = nullptr;

	char name[129], buffer[129];

	std::function<bool(std::string&)> innerParse;

	while(file.good()) {
		std::getline(file, line);
		line = trim(line);

		if(line.size() == 0)
			continue;
		data = line;

		if(line == "{") {
			sections.push(section);
			section.id.clear();
			section.attrib.clear();
			section.node = nullptr;
		}
		else if(line == "}") {
			if(!sections.empty())
				sections.pop();
			if(sections.empty())
				node = &root;
			else if(sections.top().node)
				node = sections.top().node;
			innerParse = nullptr;
		}
		else if(line == "float[16]" || line == "float[3]" || line == "float[2]") {
			//Simplify parsing
		}
		else if(innerParse) {
			if(innerParse(line))
				innerParse = nullptr;
		}
		else if(sections.size() >= 0) {
			std::string head, tail;

			if(line[0] != '{' && splitKeyValue(line, head, tail, " ") && !tail.empty()) {
				StringView value(tail);

				//Parse x {...}, x (...) {...}, and x $...\n{
				if(tail[0] == '{') {
					if(head == "ObjectRef") {
						if(tail.front() == '{' && tail.back() == '}')
							tail = tail.substr(1, tail.size()-2);
						value.advance(1);
						auto id = trim(extractSegment(value, segment), "\"$");
						if(!id.empty() && node)
							node->meshID = id;
					}
				}
				else if(tail[0] == '$') {
					if(sscanf(tail.c_str(), "$%128s", buffer) == 1)
						section.attrib = buffer;

					section.id = head;
					if(head == "Node" || head == "GeometryNode") {
						node = &node->makeChild();
						section.node = node;
					}
				}
				else if(tail[0] == '(') {
					if(sscanf(tail.c_str() + 1, "attrib = \"%128s", buffer) == 1)
						section.attrib = trim(std::string(buffer), "\")");

					if(head == "Mesh") {
						section.id = "Mesh";
						part = new GEXGeometry();
						parts[sections.top().attrib].reset(part);
					}
					else if(head == "VertexArray") {
						section.id = head;
						if(section.attrib == "position") {
							innerParse = [&](std::string& line) -> bool {
								std::vector<std::string> values;
								extractSegment(data, segment);
								while(!segment.empty()) {
									split(segment, values, ",", true);
									if(values.size() == 3)
										part->positions.push_back(vec3f(atof(values[0].c_str()), atof(values[1].c_str()), atof(values[2].c_str())));
									values.clear();

									extractSegment(data, segment);
								}
								return false;
							};
						}
						else if(section.attrib == "normal") {
							innerParse = [&](std::string& line) -> bool {
								std::vector<std::string> values;
								extractSegment(data, segment);
								while(!segment.empty()) {
									split(segment, values, ",", true);
									if(values.size() == 3)
										part->normals.push_back(vec3f(atof(values[0].c_str()), atof(values[1].c_str()), atof(values[2].c_str())));
									values.clear();

									extractSegment(data, segment);
								}
								return false;
							};
						}
						else if(section.attrib == "texcoord" || section.attrib == "texcoord[1]" || section.attrib == "texcoord[2]") {
							int index = 0;
							if(section.attrib == "texcoord")
								index = 0;
							else if(section.attrib == "texcoord[1]")
								index = 1;
							else if(section.attrib == "texcoord[2]")
								index = 2;

							innerParse = [&,index](std::string& line) -> bool {
								std::vector<std::string> values;
								extractSegment(data, segment);
								while(!segment.empty()) {
									split(segment, values, ",", true);
									if(values.size() == 2) {
										vec2f uv = vec2f(atof(values[0].c_str()), atof(values[1].c_str()));
										part->uvs[index].push_back(uv);
									}
									values.clear();

									extractSegment(data, segment);
								}
								return false;
							};
						}
						else if(section.attrib == "color") {
							innerParse = [&](std::string& line) -> bool {
								std::vector<std::string> values;
								extractSegment(data, segment);
								while(!segment.empty()) {
									split(segment, values, ",", true);
									if(values.size() == 3)
										part->colors.push_back(Colorf(atof(values[0].c_str()), atof(values[1].c_str()), atof(values[2].c_str())));
									values.clear();

									extractSegment(data, segment);
								}
								return false;
							};
						}
					}
					else if(head == "IndexArray") {
						section.id = head;
						goto readIndexArray;
					}
				}
			}
			else if(line == "IndexArray") {
				section.id = "IndexArray";
				readIndexArray:
				innerParse = [&](std::string& line) -> bool {
					std::vector<std::string> values;
					extractSegment(data, segment);
					while(!segment.empty()) {
						split(segment, values, ",", true);
						if(values.size() == 3)
							part->faces.push_back(Mesh::Face(atoi(values[0].c_str()), atoi(values[1].c_str()), atoi(values[2].c_str())));
						values.clear();
								
						extractSegment(data, segment);
					}
					return false;
				};
			}
			else if(line == "Transform") {
				row = 0;
				innerParse = [&](std::string& line) -> bool {
					if(!node)
						return true;
					line = trim(line, "{}");
					std::vector<std::string> values;
					split(line, values, ",", true);
					if(values.size() == 4)
						for(unsigned i = 0; i < 4; ++i)
							node->transform[row*4 + i] = toNumber<double>(values[i]);
					++row;
					return false;
				};
			}
		}
	}

	std::function<void(GEXNode&,Matrix)> processNode;

	auto process = [&](GEXNode& n, Matrix transform) {
		Matrix mat = n.transform * transform;

		auto p = parts.find(n.meshID);
		if(p != parts.end()) {
			auto& part = *p->second.get();
			unsigned short indexBase = mesh.vertices.size();

			for(size_t i = 0; i < part.positions.size(); ++i) {
				Vertex vert;
				vert.position = mat * part.positions[i];
				if(i < part.normals.size())
					vert.normal = mat.rotate(part.normals[i]);
				else
					vert.normal = vert.position.normalized();
				if(i < part.uvs[0].size()) {
					vert.u = part.uvs[0][i].x;
					vert.v = part.uvs[0][i].y;
				}
				mesh.vertices.push_back(vert);

				//Optional second/thid uv
				{
					auto& uvs = part.uvs[1];
					auto& uvs2 = part.uvs[2];
					if(i < uvs.size() || i < uvs2.size()) {
						if(mesh.uvs2.size() < indexBase)
							mesh.uvs2.resize(indexBase);
						vec4f uv;
						if(i < uvs.size()) {
							uv.x = uvs[i].x;
							uv.y = uvs[i].y;
						}
						if(i < uvs2.size()) {
							uv.z = uvs2[i].x;
							uv.w = uvs2[i].y;
						}
						mesh.uvs2.push_back(uv);
					}
				}

				//Optional vertex color
				if(i < part.colors.size()) {
					if(mesh.colors.size() < indexBase)
						mesh.colors.resize(indexBase);
					mesh.colors.push_back(part.colors[i]);
				}
			}

			for(size_t i = 0; i < part.faces.size(); ++i) {
				Mesh::Face face = part.faces[i];
				face.a += indexBase;
				face.b += indexBase;
				face.c += indexBase;

				if(face.a < mesh.vertices.size() && face.b < mesh.vertices.size() && face.c < mesh.vertices.size())
					mesh.faces.push_back(face);
			}
		}

		for(auto i = n.nodes.begin(), end = n.nodes.end(); i != end; ++i)
			processNode(**i, mat);
	};
	
	processNode = process;
	process(root, Matrix());
	root.clear();
}

}
