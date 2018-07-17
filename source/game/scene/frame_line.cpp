#include "frame_line.h"
#include "render/driver.h"
#include "render/vertexBuffer.h"
#include <algorithm>

extern double frameLen_s;

namespace scene {
FrameLineNode::FrameLineNode(const render::RenderState& material, float duration) : mat(material), interpDuration(duration), age(0), life(1000.f), fadeAge(1000.f) {
	setFlag(NF_NoMatrix, true);
}

bool FrameLineNode::preRender(render::RenderDriver& driver) {
	if(frameLen_s > 0) {
		age += (float)frameLen_s;
		endPos = abs_position.interpolate(prevPos, interpDuration / frameLen_s);
		prevPos = abs_position;
	}

	vec3d off = abs_position - driver.cam_pos;
	sortDistance = off.getLength();
	return off.dot(driver.cam_facing) > 0;
}

void FrameLineNode::render(render::RenderDriver& driver) {
	auto& camPos = driver.cam_pos;

	auto* verts = render::VertexBufferTCV::fetch(&mat)->request(1, render::PT_Lines);

	float alpha = age > fadeAge ? 1.f - std::min((age-fadeAge)/(life-fadeAge), 1.f) : 1.f;

	verts[0].col = startCol;
	verts[0].col.a *= alpha;
	verts[0].pos = vec3f(abs_position - camPos);
	verts[0].uv = vec2f(0,0);

	verts[1].col = endCol;
	verts[1].col.a *= alpha;
	verts[1].pos = vec3f(endPos - camPos);
	verts[1].uv = vec2f(1,0);
}
};