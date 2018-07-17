#pragma once
#include "render/shader.h"

namespace render {
Shader* createGLShader();
ShaderProgram* createGLShaderProgram(const char* vertex_shader, const char* fragment_shader);
};
