#pragma once
#include "animator.h"
#include "vec3.h"

namespace scene {

	class LinearMotionAnim : public Animator {
	public:
		vec3d velocity;

		void animate(Node* node);

		LinearMotionAnim(const vec3d& Velocity);
	};

};

