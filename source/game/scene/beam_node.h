#pragma once
#include "scene/node.h"

namespace render {
struct RenderState;
};

namespace scene {
	class BeamNode : public Node {
		const render::RenderState* material;
	public:
		float width, uvLength;
		vec3d endPosition;
		bool staticSize;

		BeamNode(const render::RenderState* Material, float Width, const vec3d& startPoint, const vec3d& endPoint, bool StaticSize = false);

		bool preRender(render::RenderDriver& driver);
		void render(render::RenderDriver& driver);
	};
};
