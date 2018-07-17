#pragma once
#include "render/render_mesh.h"
#include "mesh.h"

namespace render {
RenderMesh* createGLMesh(const Mesh& mesh);
};
