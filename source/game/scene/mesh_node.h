#pragma once
#include "scene/node.h"

namespace render {
struct RenderState;
class RenderMesh;
};

namespace scene {
	
class MeshNode : public Node {
public:
	const render::RenderMesh* mesh;
	const render::RenderState* material;

	MeshNode(const render::RenderMesh* mesh, const render::RenderState* material);

	bool preRender(render::RenderDriver& driver) override;
	void render(render::RenderDriver& driver) override;

	NodeType getType() const override { return NT_MeshNode; };
};

};
