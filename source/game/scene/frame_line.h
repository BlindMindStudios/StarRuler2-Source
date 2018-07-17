#include "node.h"
#include "render/render_state.h"

namespace scene {

class FrameLineNode : public Node {
	//Stored previous positions so a trail can be rendered

	const render::RenderState& mat;

public:
	vec3d endPos, prevPos;
	float interpDuration;
	Color startCol, endCol;
	float age, life, fadeAge;

	FrameLineNode(const render::RenderState& material, float duration);

	bool preRender(render::RenderDriver& driver);
	void render(render::RenderDriver& driver);
};

};