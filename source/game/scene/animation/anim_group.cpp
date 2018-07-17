#include "anim_group.h"
#include "scene/node.h"
#include "obj/obj_group.h"
#include "obj/object.h"
#include "empire.h"

extern double frameLen_s, frameTime_s;

namespace scene {
	void GroupAnim::animate(Node* node) {
		if(group && group->getObjectCount() != 0) {
			double tickTime = std::min(node->sortDistance * 3e-5, 3.0);

			Object* obj = group->getOwner();
			if(node->obj != obj)
				node->setObject(obj);

			if(obj) {
				if(Empire* owner = obj->owner)
					node->color = owner->color;

				if(obj->lastTick > node->lastUpdate + tickTime) {
					node->position = node->position.interpolate(group->getCenter(), frameLen_s/(obj->lastTick - node->lastUpdate));
					node->rotation = node->rotation.slerp(group->formationFacing, frameLen_s/(obj->lastTick - node->lastUpdate));

					node->lastUpdate = frameTime_s;
					node->rebuildTransformation();
					node->visible = obj->isVisibleTo(Empire::getPlayerEmpire());
				}
				else {
					node->position = group->getCenter();
					node->rotation = group->formationFacing;
					node->rebuildTransformation();
					node->visible = obj->isVisibleTo(Empire::getPlayerEmpire());
				}
			}
			else {
				node->visible = false;
			}
		}
		else {
			node->markForDeletion();
			if(group) {
				group->drop();
				group = 0;
			}
		}
	}

	GroupAnim::~GroupAnim() {
		if(group)
			group->drop();
	}

	GroupAnim::GroupAnim(ObjectGroup* Group) : group(Group) {
		group->grab();
	}
};
