#pragma once
#include "mesh.h"

namespace render {

void loadBinaryMesh(const char* filename, Mesh& mesh);
bool saveBinaryMesh(const char* filename, Mesh& mesh);

};