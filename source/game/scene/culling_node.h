#pragma once
#include "scene/node.h"

namespace scene {

class CullingNode : public Node {
public:
	CullingNode(vec3d position, double radius);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);

	NodeType getType() const override { return NT_Culling; };
};

};
