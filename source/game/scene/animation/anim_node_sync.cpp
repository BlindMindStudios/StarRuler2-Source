#include "anim_node_sync.h"
#include "scene/node.h"
#include "obj/object.h"
#include "empire.h"
#include "main/references.h"

extern double frameLen_s, frameTime_s;

namespace scene {

void NodeSyncAnimator::animate(Node* node) {
	Object* obj = node->obj;
	if(obj) {
		auto* player = Empire::getPlayerEmpire();

		bool vis = false;
		
		vis = obj->isVisibleTo(player) && obj->position.distanceToSQ(devices.render->cam_pos) < (node->distanceCutoff * obj->radius * obj->radius);
		bool wasVisible = node->visible;

		if(!vis && node->getFlag(NF_Memorable) && (node->remembered || obj->isKnownTo(player))) {
			vis = true;
			node->remembered = true;
		}
		else if(vis) {
			node->remembered = false;
		}

		if(!vis && !wasVisible && node->getFlag(NF_AnimOnlyVisible)) {
			node->visible = false;
			return;
		}

		if(obj->isFocus()) {
			//TODO: This should be handled better/centrally
			obj->setFlag(objFocus, false);
		}

		double interpPct = 1.0;
		if(vis && wasVisible) {
			if(obj->lastTick > node->lastUpdate + 1.0/60.0) {
				interpPct = (frameTime_s - node->lastUpdate)/(obj->lastTick - node->lastUpdate);
				node->position = node->position.interpolate(obj->position, interpPct);
			}
			else {
				//Interpolate to a predicted position based on physics data
				double tDiff = frameTime_s - obj->lastTick;
				vec3d predicted = obj->position + (obj->velocity + obj->acceleration * (tDiff * 0.5)) * tDiff;
				//node->position = node->position.interpolate(predicted, (frameTime_s - node->lastUpdate) / tDiff);
				node->position = predicted;
				interpPct = tDiff / (node->lastUpdate - obj->lastTick);
			}
		}
		else {
			double tDiff = frameTime_s - obj->lastTick;
			node->position = obj->position + (obj->velocity + obj->acceleration * (tDiff * 0.5)) * tDiff;
		}
		node->lastUpdate = frameTime_s;

		node->visible = vis;

		//Some updates only need performed for visible objects
		if(vis || !node->getFlag(NF_AnimOnlyVisible)) {
			if(!node->remembered && !node->getFlag(NF_CustomColor))
				if(Empire* owner = obj->owner)
					node->color = owner->color;

			if(wasVisible)
				node->rotation = node->rotation.slerp(obj->rotation, interpPct);
			else
				node->rotation = obj->rotation;

			node->rebuildTransformation();
		}
	}
}

NodeSyncAnimator syncAnimator;

NodeSyncAnimator* NodeSyncAnimator::getSingleton() {
	return &syncAnimator;
}

};
