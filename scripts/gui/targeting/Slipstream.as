import resources;
import ftl;
from obj_selection import selectedObject, selectedObjects, getSelectionPosition, getSelectionScale;
import targeting.PointTarget;
import targeting.targeting;

class SlipstreamTarget : PointTarget {
	double cost = 0.0;
	int scale = 1;
	Object@ obj;

	SlipstreamTarget(Object@ obj, int totalScale) {
		@this.obj = obj;
		scale = totalScale;
	}

	vec3d get_origin() override {
		if(shiftKey)
			return obj.finalMoveDestination;
		else
			return obj.position;
	}

	bool hover(const vec2i& mpos) override {
		PointTarget::hover(mpos);
		cost = slipstreamCost(obj, scale, distance);
		range = slipstreamRange(obj, scale, playerEmpire.FTLStored);
		return canSlipstreamTo(obj, hovered) && (distance <= range || shiftKey);
	}

	double get_radius() override {
		return slipstreamInaccuracy(obj, hovered);
	}

	bool click() override {
		return distance <= range || shiftKey;
	}
};

class SlipstreamDisplay : PointDisplay {
	void draw(TargetMode@ mode) override {
		PointDisplay::draw(mode);

		SlipstreamTarget@ ht = cast<SlipstreamTarget>(mode);
		if(ht is null)
			return;

		Color color;
		if(ht.distance <= ht.range && ht.valid)
			color = Color(0x00ff00ff);
		else
			color = Color(0xff0000ff);

		font::DroidSans_11_Bold.draw(mousePos + vec2i(16, 0),
			toString(int(ht.cost)) + " " + locale::FTL
			 + " (" + toString(ht.distance, 0) + "u)",
			color);
		
		if(ht.distance > ht.range) {
			font::OpenSans_11_Italic.draw(mousePos + vec2i(16, 16),
				locale::INSUFFICIENT_FTL,
				color);
		}
	}

	void render(TargetMode@ mode) override {
		inColor = Color(0x00c0ffff);
		if(shiftKey)
			outColor = Color(0xffe400ff);
		else
			outColor = colors::Red;
		PointDisplay::render(mode);
	}
};

class SlipstreamCB : TargetCallback {
	void call(TargetMode@ mode) override {
		bool anyOpenedTear = false;
		Object@[]@ selection = selectedObjects;
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(!obj.hasMover || !obj.hasLeaderAI)
				continue;
			if(!canSlipstream(obj))
				continue;
			obj.addSlipstreamOrder(mode.position, shiftKey || obj.inFTL);
			anyOpenedTear = true;
			for(uint j = 0; j < cnt; ++j) {
				if(i == j)
					continue;
				Object@ other = selection[j];
				if(!obj.hasMover || !obj.hasLeaderAI)
					continue;
				other.addWaitOrder(obj, shiftKey || obj.inFTL, moveTo=true);
				obj.addSecondaryToSlipstream(other);
			}
			break;
		}
		
		if(anyOpenedTear)
			sound::order_slipstream.play(priority=true);
	}
};

void targetSlipstream() {
	Object@ sel = selectedObject;
	for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i) {
		if(canSlipstream(selectedObjects[i])) {
			@sel = selectedObjects[i];
			break;
		}
	}
	if(sel.owner is null || !sel.owner.valid)
		return;
	if(!canSlipstream(sel))
		return;

	SlipstreamTarget targ(sel, max(getSelectionScale(), 1));
	SlipstreamDisplay disp;
	SlipstreamCB cb;

	startTargeting(targ, disp, cb);
}
