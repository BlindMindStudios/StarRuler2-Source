#pragma once
#include "animator.h"
#include "vec3.h"

namespace scene {

	class ProjectileAnim : public Animator {
	public:
		vec3d velocity;

		void animate(Node* node);

		ProjectileAnim(const vec3d& Velocity);
	};

	class BeamAnim : public Animator {
		scene::Node* follow;
		vec3d offset;
		float length;
	public:
		void animate(Node* node);
		BeamAnim(Node* Follow, vec3d Offset, float range);
		~BeamAnim();
	};

};

