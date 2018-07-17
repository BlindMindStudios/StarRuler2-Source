import resources;
import ftl;
from obj_selection import selectedObject, selectedObjects, getSelectionPosition, getSelectionScale;
import targeting.PointTarget;
import targeting.targeting;
from targeting.MoveTarget import getFleetTargetPositions;
import system_flags;

class JumpdriveTarget : PointTarget {
	double cost = 0.0;
	Object@ obj;
	array<Object@> objs;

	JumpdriveTarget(Object@ obj) {
		@this.obj = obj;
		objs = selectedObjects;
		range = INFINITY;
	}

	vec3d get_origin() override {
		if(shiftKey) {
			Object@ obj = selectedObject;
			return obj.finalMoveDestination;
		}
		else {
			return getSelectionPosition(true);
		}
	}

	bool hover(const vec2i& mpos) override {
		if(selectedObjects.length > 1) {
			auto@ positions = getFleetTargetPositions(objs, hovered, isFTL=true);
			cost = 0;
			for(uint i = 0, cnt = objs.length; i < cnt; ++i)
				cost += jumpdriveCost(objs[i], positions[i]);
		}
		else {
			cost = jumpdriveCost(obj, hovered);
		}
		if(cost <= playerEmpire.FTLStored)
			range = INFINITY;
		else
			range = 0;
		PointTarget::hover(mpos);
		return canFlingTo(obj, hovered);
	}

	bool click() override {
		return true;
	}
};

class JumpdriveDisplay : PointDisplay {
	PlaneNode@ range;
	double jumpRange;

	~JumpdriveDisplay() {
		if(range !is null) {
			range.visible = false;
			range.markForDeletion();
			@range = null;
		}
	}

	void draw(TargetMode@ mode) override {
		PointDisplay::draw(mode);

		JumpdriveTarget@ ht = cast<JumpdriveTarget>(mode);
		if(ht is null)
			return;

		if(range is null) {
			jumpRange = cast<Ship>(ht.obj).blueprint.getEfficiencySum(SV_JumpRange);
			@range = PlaneNode(material::RangeCircle, jumpRange);
			range.visible = false;
			range.position = ht.obj.node_position;
			range.rebuildTransform();
			range.color = Color(0xff2b0cff);
			range.visible = true;
		}

		bool isSafe = false;
		Region@ reg = getRegion(ht.hovered);
		if(reg !is null)
			isSafe = reg.getSystemFlag(playerEmpire, safetyFlag);

		Color color;
		if(!ht.valid || ht.cost > playerEmpire.FTLStored)
			color = Color(0xff0000ff);
		else if(ht.distance >= jumpRange && !isSafe)
			color = Color(0xff8000ff);
		else
			color = Color(0x00ff00ff);

		font::DroidSans_11_Bold.draw(mousePos + vec2i(16, 0),
			toString(int(ht.cost)) + " " + locale::FTL
			 + " (" + toString(ht.distance, 0) + "u)",
			color);
		
		if(ht.cost > playerEmpire.FTLStored) {
			font::OpenSans_11_Italic.draw(mousePos + vec2i(16, 16),
				locale::INSUFFICIENT_FTL,
				color);
		}
		else if(ht.distance >= jumpRange && !isSafe) {
			if(ht.distance >= jumpRange * 2.0) {
				font::DroidSans_11_Bold.draw(mousePos + vec2i(16, 16),
					locale::JUMPDRIVE_SAFETY_WARNING_SEVERE,
					Color(0xff0000ff));
			}
			else {
				font::DroidSans_11.draw(mousePos + vec2i(16, 16),
					locale::JUMPDRIVE_SAFETY_WARNING,
					Color(0xff0000ff));
			}
		}
	}

	void render(TargetMode@ mode) override {
		JumpdriveTarget@ ht = cast<JumpdriveTarget>(mode);
		if(ht !is null && range !is null) {
			range.position = ht.obj.node_position;
			range.rebuildTransform();
		}
		PointDisplay::render(mode);
	}
};

class JumpdriveCB : TargetCallback {
	void call(TargetMode@ mode) override {
		bool anyFTL = false;
		Object@[] selection = selectedObjects;
		auto@ positions = getFleetTargetPositions(selection, mode.position, isFTL=true);
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(!obj.hasMover || !obj.hasLeaderAI || !canJumpdrive(obj))
				continue;
			obj.addJumpdriveOrder(positions[i], shiftKey || obj.inFTL);
			anyFTL = true;
		}
		
		if(anyFTL)
			sound::order_fling.play(priority=true);
	}
};

void targetJumpdrive() {
	Object@ sel = selectedObject;
	if(sel.owner is null || !sel.owner.valid)
		return;
	if(!selectedObject.isShip)
		return;

	JumpdriveTarget targ(selectedObject);
	JumpdriveDisplay disp;
	JumpdriveCB cb;

	startTargeting(targ, disp, cb);
}

int safetyFlag = -1;
void init() {
	safetyFlag = getSystemFlag("JumpdriveSafety");
}
