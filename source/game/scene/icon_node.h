#pragma once
#include "scene/node.h"

namespace render {
class SpriteSheet;
};

namespace scene {

class IconNode : public Node {
public:
	const render::SpriteSheet* sheet;
	unsigned index;

	IconNode(const render::SpriteSheet* spriteSheet, unsigned spriteIndex);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

};
