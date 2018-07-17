import resources;
import ftl;
from obj_selection import selectedObject, selectedObjects, getSelectionPosition, getSelectionScale;
import targeting.PointTarget;
import targeting.targeting;
from targeting.MoveTarget import getFleetTargetPositions;

class HyperdriveTarget : PointTarget {
	double cost = 0.0;
	Object@ obj;
	array<vec3d>@ offsets;
	array<Object@> objs;

	HyperdriveTarget(Object@ Obj) {
		@obj = Obj;
		objs = selectedObjects;
	}

	vec3d get_origin() override {
		if(shiftKey) {
			Object@ obj = selectedObject;
			if(obj is null)
				return vec3d();
			return obj.finalMoveDestination;
		}
		else {
			return getSelectionPosition(true);
		}
	}

	bool hover(const vec2i& mpos) override {
		PointTarget::hover(mpos);

		//if(selectedObjects.length > 1) {
			auto@ positions = getFleetTargetPositions(objs, hovered);
			cost = 0;
			for(uint i = 0, cnt = objs.length; i < cnt; ++i)
				cost += hyperdriveCost(objs[i], positions[i]);
			range = cost > playerEmpire.FTLStored ? 0.0 : INFINITY;
		//}
		//else {
		//	range = hyperdriveRange(obj);
		//	cost = hyperdriveCost(obj, hovered);
		//}
		return canHyperdriveTo(obj, hovered) && (distance <= range || shiftKey);
	}

	bool click() override {
		return distance <= range || shiftKey;
	}
};

class HyperdriveDisplay : PointDisplay {
	void draw(TargetMode@ mode) override {
		PointDisplay::draw(mode);

		HyperdriveTarget@ ht = cast<HyperdriveTarget>(mode);
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

class HyperdriveCB : TargetCallback {
	void call(TargetMode@ mode) override {
		bool anyDidFTL = false;
		Object@[] selection = selectedObjects;
		auto@ positions = getFleetTargetPositions(selection, mode.position);
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(!obj.hasMover || !obj.hasLeaderAI || !canHyperdrive(obj))
				continue;
			anyDidFTL = true;
			obj.addHyperdriveOrder(positions[i], shiftKey || obj.inFTL);
		}
		
		if(anyDidFTL)
			sound::order_hyperdrive.play(priority=true);
		
		if(shiftKey) {
			HyperdriveTarget targ(selectedObject);
			targ.isShifted = true;
			HyperdriveDisplay disp;
			HyperdriveCB cb;
			startTargeting(targ, disp, cb);
		}
	}
};

void targetHyperdrive() {
	HyperdriveTarget targ(selectedObject);
	HyperdriveDisplay disp;
	HyperdriveCB cb;

	startTargeting(targ, disp, cb);
}
