#pragma once
#include "vec2.h"
#include "image.h"
#include "rect.h"
#include "render_state.h"

namespace render {

enum TextureType {
	TT_2D,
	TT_Cubemap
};

class Texture {
public:
	TextureType type;
	vec2i size;
	bool loaded;
	bool hasMipMaps;
	mutable RenderState prevRenderState;

	virtual bool isPixelActive(vec2i px) const = 0;

	virtual void loadStart(Image& image, bool mipmap = true, bool cachePixels = false, unsigned lod = 0) = 0;
	virtual void loadPartial(Image& image, const recti& pixels, bool cachePixels = false, unsigned lod = 0) = 0;
	virtual void loadFinish(bool mipmap, unsigned lod = 0) = 0;

	virtual void load(Image& image, bool mipmap = true, bool cachePixels = false) = 0;
	virtual void save(Image& image) const = 0;
	virtual void bind() = 0;
	virtual unsigned getID() const = 0;

	virtual unsigned getTextureBytes() const = 0;

	virtual ~Texture() {}
};

};
