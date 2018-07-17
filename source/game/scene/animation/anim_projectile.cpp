#include "anim_projectile.h"
#include "scene/node.h"
#include "scene/beam_node.h"
#include <stdio.h>

extern double frameTime_s;

namespace scene {

	ProjectileAnim::ProjectileAnim(const vec3d& Velocity) : velocity(Velocity) {
	}

	void ProjectileAnim::animate(Node* node) {
		node->position += velocity * (frameTime_s - node->lastUpdate);
		node->rebuildTransformation();
		node->lastUpdate = frameTime_s;
	}

	void BeamAnim::animate(Node* node) {
		BeamNode* beam = (BeamNode*)node;
		if(beam->endPosition.zero())
			return;
		node->visible = true;

		if(follow) {
			node->position = follow->abs_position + offset;
			node->rebuildTransformation();
		}

		float curLength = beam->abs_position.distanceTo(beam->endPosition);
		beam->uvLength = curLength / length;
	}

	BeamAnim::BeamAnim(Node* Follow, vec3d Offset, float range) : follow(Follow), offset(Offset), length(range) {
		if(Follow)
			Follow->grab();
	}

	BeamAnim::~BeamAnim() {
		if(follow)
			follow->drop();
	}
};
