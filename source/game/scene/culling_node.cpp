#include "culling_node.h"
#include "main/references.h"
#include "render/driver.h"
#include "frustum.h"
#include "obj/object.h"

namespace scene {

CullingNode::CullingNode(vec3d pos, double rad) {
	position = pos;
	scale = rad;
	setFlag(NF_Dirty, true);
	setFlag(NF_Transparent, true);
	setFlag(NF_NoMatrix, true);
}

bool CullingNode::preRender(render::RenderDriver& driver) {
	if(!driver.getViewFrustum().overlaps(abs_position,abs_scale))
		return false;
	else {
		sortDistance = driver.cam_pos.distanceTo(abs_position);
		return true;
	}
}

void CullingNode::render(render::RenderDriver& driver) {
}

};
