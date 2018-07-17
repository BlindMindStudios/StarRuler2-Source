#pragma once
#include "scene/node.h"

namespace render {
struct RenderState;
class RenderMesh;
class SpriteSheet;
};

namespace scene {
	
class MeshIconNode : public Node {
public:
	static bool render3DIcons;
	const render::RenderMesh* mesh;
	const render::RenderState* material;
	const render::SpriteSheet* iconSheet;
	unsigned iconIndex;

	MeshIconNode(
		const render::RenderMesh* mesh, const render::RenderState* material,
		const render::SpriteSheet* sheet, unsigned index);

	bool preRender(render::RenderDriver& driver) override;
	void render(render::RenderDriver& driver) override;

	NodeType getType() const override { return NT_MeshIconNode; };
};

};
