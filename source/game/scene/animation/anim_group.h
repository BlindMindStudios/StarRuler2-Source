#pragma once
#include "animator.h"

class ObjectGroup;

namespace scene {

	class GroupAnim : public Animator {
		ObjectGroup* group;
	public:
		void animate(Node* node);

		GroupAnim(ObjectGroup* group);
		~GroupAnim();
	};

};
