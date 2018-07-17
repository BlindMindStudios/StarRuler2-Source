#pragma once
#include "animator.h"

namespace scene {

class NodeSyncAnimator : public Animator {
public:
	void animate(Node* node);

	static NodeSyncAnimator* getSingleton();
};

};