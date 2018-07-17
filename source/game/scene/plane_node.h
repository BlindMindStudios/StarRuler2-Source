#pragma once
#include "scene/node.h"

namespace render {
struct RenderState;
};

namespace scene {
	
class PlaneNode : public Node {
public:
	const render::RenderState* material;
	float minRad, maxRad;

	PlaneNode(const render::RenderState* material, double size);

	virtual bool preRender(render::RenderDriver& driver);
	virtual void render(render::RenderDriver& driver);
};

};
