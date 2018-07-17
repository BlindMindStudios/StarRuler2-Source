#pragma once
#include "compat/gl.h"
#include "render/texture.h"
#include "image.h"
#include "rect.h"
#include <vector>

namespace render {
class GLTexture : public Texture {
	GLuint glName;
	unsigned pixelDepth;
	std::vector<bool> activePixels;
public:
	bool isPixelActive(vec2i px) const;
	void load(Image& image, bool mipmap = true, bool cachePixels = false);

	void loadStart(Image& image, bool mipmap = true, bool cachePixels = false, unsigned lod = 0);
	void loadPartial(Image& image, const recti& pixels, bool cachePixels = false, unsigned lod = 0);
	void loadFinish(bool mipmap, unsigned lod = 0);
	unsigned getTextureBytes() const;

	void save(Image& image) const;
	void bind();
	unsigned getID() const;

	GLTexture(Image& image, bool mipmap = true, bool cachePixels = false);
	GLTexture();

	~GLTexture();
};

class GLCubeMap : public Texture {
	GLuint glName;
	unsigned pixelDepth;
public:
	bool isPixelActive(vec2i px) const;
	void load(Image& image, bool mipmap = true, bool cachePixels = false);
	void loadStart(Image& image, bool mipmap = true, bool cachePixels = false, unsigned lod = 0);
	void loadPartial(Image& image, const recti& pixels, bool cachePixels = false, unsigned lod = 0);
	void loadFinish(bool mipmap, unsigned lod = 0);

	unsigned getTextureBytes() const;

	void save(Image& image) const;
	void bind();
	unsigned getID() const;

	GLCubeMap(Image& image, bool mipmap = true);
	GLCubeMap();

	~GLCubeMap();
};
};
