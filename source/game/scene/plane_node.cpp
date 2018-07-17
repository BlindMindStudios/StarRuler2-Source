#include "scene/plane_node.h"
#include "render/driver.h"

void shader_plane_minrad(float* value,unsigned short,void*) {
	if(auto* node = dynamic_cast<scene::PlaneNode*>(scene::renderingNode))
		*value = (float)node->minRad;
	else
		*value = 0.f;
}

void shader_plane_maxrad(float* value,unsigned short,void*) {
	if(auto* node = dynamic_cast<scene::PlaneNode*>(scene::renderingNode))
		*value = (float)node->maxRad;
	else
		*value = 0.f;
}

namespace scene {
PlaneNode::PlaneNode(const render::RenderState* Material, double Size)
	: material(Material), minRad(-3.2f), maxRad(3.2f) {
	setFlag(NF_NoMatrix, true);
	if(Material->baseMat != render::MAT_Solid)
		setFlag(NF_Transparent, true);
	scale = Size;
}

bool PlaneNode::preRender(render::RenderDriver& driver) {
	auto fromCamera = abs_position - driver.cam_pos;
	if(fromCamera.dot(driver.cam_facing) > 0) {
		sortDistance = fromCamera.getLength();
		return true;
	}
	else {
		return false;
	}
}

void PlaneNode::render(render::RenderDriver& driver) {
	driver.setTransformation(transformation);
	driver.switchToRenderState(*material);

	vec3d verts[4];
	vec3d vsize = vec3d(scale, 0, scale);

	vec3d topLeft = abs_position - vsize;
	vec3d botRight = abs_position + vsize;

	verts[0] = topLeft;
	verts[1] = topLeft + vec3d(vsize.x * 2, 0, 0);
	verts[2] = botRight;
	verts[3] = botRight - vec3d(vsize.x  * 2, 0, 0);

	vec2f tcs[4] = { vec2f(0,0), vec2f(1,0), vec2f(1,1), vec2f(0,1) };
	Color colors[4] = { color, color, color, color };

	driver.drawQuad(verts, tcs, colors);
	driver.resetTransformation();
}
	
};
