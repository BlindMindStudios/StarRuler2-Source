#pragma once
#include "util/refcount.h"

namespace scene {

class Node;

class Animator : public AtomicRefCounted {
public:

	virtual void animate(Node* node) = 0;
};

};