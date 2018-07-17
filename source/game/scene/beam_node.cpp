#include "beam_node.h"
#include "render/driver.h"
#include "aabbox.h"
#include "frustum.h"
#include "render/vertexBuffer.h"

extern double pixelSizeRatio;

namespace scene {
	
BeamNode::BeamNode(const render::RenderState* Material, float Width, const vec3d& startPoint, const vec3d& endPoint, bool StaticSize)
	: material(Material), width(Width), endPosition(endPoint), staticSize(StaticSize), uvLength(1.f)
{
	position = abs_position = startPoint;
	setFlag(NF_NoMatrix, true);
	if(Material->baseMat != render::MAT_Solid)
		setFlag(NF_Transparent, true);
}

bool BeamNode::preRender(render::RenderDriver& driver) {
	auto& cam_pos = driver.cam_pos;

	if(!visible)
		return false;

	line3dd line(abs_position, endPosition);
	AABBoxd box(line);

	if(box.overlaps(driver.getViewFrustum().bound)) {
		sortDistance = line.getClosestPoint(cam_pos, false).distanceTo(cam_pos);
		return true;
	}
	else {
		return false;
	}
}

void BeamNode::render(render::RenderDriver& driver) {
	auto& cam_pos = driver.cam_pos;

	double size = width * abs_scale;
	if(staticSize)
		size *= sortDistance /  pixelSizeRatio;

	vec3d offset = (endPosition - abs_position).cross(driver.cam_facing).normalized(size);

	auto* buffer = render::VertexBufferTCV::fetch(material);
	auto* verts = buffer->request(1, render::PT_Quads);

	Color col = color;

	verts[0].pos = vec3f(abs_position + offset - cam_pos);
	verts[0].uv = vec2f(0,0);
	verts[0].col = col;

	verts[1].pos = vec3f(endPosition + offset - cam_pos);
	verts[1].uv = vec2f(uvLength,0);
	verts[1].col = col;

	verts[2].pos = vec3f(endPosition - offset - cam_pos);
	verts[2].uv = vec2f(uvLength,1);
	verts[2].col = col;

	verts[3].pos = vec3f(abs_position - offset - cam_pos);
	verts[3].uv = vec2f(0,1);
	verts[3].col = col;
}

};
