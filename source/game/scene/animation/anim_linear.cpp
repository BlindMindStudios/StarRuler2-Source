#include "anim_linear.h"
#include "scene/node.h"

extern double frameTime_s;

namespace scene {

	LinearMotionAnim::LinearMotionAnim(const vec3d& Velocity) : velocity(Velocity) {}

	void LinearMotionAnim::animate(Node* node) {
		node->position += velocity * (frameTime_s - node->lastUpdate);
		node->rebuildTransformation();
		node->lastUpdate = frameTime_s;
	}
};
