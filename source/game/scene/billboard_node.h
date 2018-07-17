#pragma once
#include "scene/node.h"
#include "render/spritesheet.h"

namespace render {
struct RenderState;
};

namespace scene {

class BillboardNode : public Node {
	const render::RenderState* material;
	double width;
public:
	BillboardNode(const render::RenderState* Material, double Width);
	void setWidth(double Width);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

class SpriteNode : public Node {
public:
	render::Sprite sprite;
	double width;

	SpriteNode(const render::Sprite& sprt, double Width);
	void setWidth(double Width);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

};
