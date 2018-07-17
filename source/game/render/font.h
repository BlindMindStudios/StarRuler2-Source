#pragma once

#include "render/texture.h"
#include "render/render_state.h"
#include "render/driver.h"
#include "color.h"
#include "image.h"
#include <vector>

namespace render {

typedef int fontChar;

class Font {
	//Prevent copying the font
	Font(const Font& other) {}
	void operator=(const Font& other) {}
protected:
	Font() : bold(0), italic(0) {}
public:
	Font* bold;
	Font* italic;

	virtual vec2i getDimension(const char* text) const {
		return vec2i();
	};

	virtual vec2i getDimension(int c, int lastC) const {
		return vec2i();
	}

	virtual unsigned getBaseline() const {
		return 0;
	}

	virtual unsigned getLineHeight() const {
		return 0;
	}

	virtual void draw(render::RenderDriver* driver, const char* text,
		int x, int y, const Color* color = 0, const recti* clip = 0) const {
	};

	virtual vec2i drawChar(render::RenderDriver* driver, int c, int lastC,
				int X, int Y, const Color* color = 0, const recti* clip = 0) const {
		return vec2i();
	}

	virtual ~Font() {
	};

	static Font* createDummyFont();
};

bool clipQuad(rectf pos, rectf source, const rectf* clip, vec2f* verts, vec2f* texcoords);

Font* loadFontFNT(render::RenderDriver* driver, const char* filename);

Font* loadFontFT2(render::RenderDriver& driver, const char* filename,
					std::vector<std::pair<int,int>>& pages, int size);

};
