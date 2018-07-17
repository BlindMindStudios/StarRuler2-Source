#pragma once
#include "compat/misc.h"
#include "render/shader.h"
#include "color.h"
#include <string>

#ifndef RENDER_MAX_TEXTURES
	#define RENDER_MAX_TEXTURES 8
#endif

namespace render {
class Texture;

unsigned_enum(FaceCulling) {
	FC_None,
	FC_Front,
	FC_Back,
	FC_Both
};

unsigned_enum(DepthTest) {
	DT_Never,
	DT_Less,
	DT_Equal,
	DT_LessEqual,
	DT_Greater,
	DT_NotEqual,
	DT_GreaterEqual,
	DT_Always,

	//A depth test that always passes is equivalent to no test
	DT_NoDepthTest = DT_Always,
};

unsigned_enum(TextureWrap) {
	TW_Repeat,
	TW_Clamp,
	TW_ClampEdge,
	TW_Mirror
};

unsigned_enum(TextureFilter) {
	TF_Nearest,
	TF_Linear
};

unsigned_enum(BaseMaterial) {
	MAT_Solid,
	MAT_Add,
	MAT_Alpha,
	MAT_Font,

	MAT_Overlay,
};

unsigned_enum(DrawMode) {
	DM_Fill,
	DM_Line,
};

//Holds the target render state
//=====
//Notes:
// Alpha test is always >0
// Normalize Normals requires uniform scaling
struct RenderState {
	FaceCulling culling : 2;
	DepthTest depthTest : 4;
	BaseMaterial baseMat : 3;
	DrawMode drawMode : 2;
	bool depthWrite : 1;
	bool lighting : 1;
	bool normalizeNormals : 1;
	TextureWrap wrapHorizontal : 2;
	TextureWrap wrapVertical : 2;
	TextureFilter filterMin : 2;
	TextureFilter filterMag : 2;
	bool mipmap : 1;
	bool cachePixels : 1;
	bool constant : 1;

	Colorf diffuse, specular;
	float shininess;

	Texture* textures[RENDER_MAX_TEXTURES];
	const Shader* shader;

	void* operator new(size_t size);
	void operator delete(void* p);

	RenderState();
};

struct MaterialGroup {
	std::string prefix;
	RenderState base;
	std::vector<RenderState*> materials;
	std::vector<std::string> names;
};

};
