#pragma once
#include "vec2.h"
#include "vec4.h"
#include "render/driver.h"
#include "render/render_state.h"

namespace render {

enum SpriteMode {
	SM_Horizontal,
	SM_Vertical,
};

class SpriteSheet {
public:
	static const SpriteSheet* current;
	static unsigned currentIndex;

	RenderState material;
	SpriteMode mode;
	int width, height;
	int spacing;
	mutable int perLine;
	mutable bool dirty;

	unsigned getCount() const;

	SpriteSheet();

	bool isPixelActive(unsigned index, const vec2i& px) const;
	vec4f getSourceUV(unsigned index) const;
	recti getSource(unsigned index) const;
	void getSource(unsigned index, vec2f* out) const;
	void render(RenderDriver& driver, unsigned index, const vec3d* vertices, const Color* color = 0) const;
	void render(RenderDriver& driver, unsigned index, recti rectangle, const Color* color = 0, const recti* clip = 0, const render::Shader* shader = 0, double rotation = 0.0) const;
};

class Sprite {
public:
	const SpriteSheet* sheet;
	const RenderState* mat;
	unsigned index;
	Color color;

	Sprite() : sheet(0), mat(0), index(0) {
	}

	Sprite(const SpriteSheet* Sheet, unsigned Index)
		: sheet(Sheet), mat(0), index(Index) {
	}

	Sprite(const RenderState* Material)
		: sheet(0), mat(Material), index(0) {
	}
};

};
