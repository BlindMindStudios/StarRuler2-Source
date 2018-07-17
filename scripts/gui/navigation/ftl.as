from obj_selection import selectedObjects, selectedObject;
import ftl;

import void targetHyperdrive() from "targeting.Hyperdrive";
import void targetJumpdrive() from "targeting.Jumpdrive";
import void targetFling() from "targeting.Fling";
import void targetSlipstream() from "targeting.Slipstream";

bool canMove() {
	Object@[]@ selected = selectedObjects;
	if(selected.length == 0)
		return false;
	for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
		if(!selected[i].hasMover)
			return false;
		if(!selected[i].owner.controlled)
			return false;
	}
	return true;
}

bool canHyperdrive() {
	Object@[]@ selected = selectedObjects;
	if(selected.length == 0)
		return false;
	for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
		if(!canHyperdrive(selected[i]))
			return false;
	}
	return true;
}

bool canJumpdrive() {
	Object@[]@ selected = selectedObjects;
	if(selected.length == 0)
		return false;
	for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
		if(!canJumpdrive(selected[i]))
			return false;
	}
	return true;
}

bool canFling() {
	Object@[]@ selected = selectedObjects;
	if(selected.length == 0 || !playerEmpire.hasFlingBeacons)
		return false;
	for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
		Object@ obj = selected[i];
		if(obj.owner is null || !obj.owner.valid)
			return false;
		if(!canFling(obj))
			return false;
	}
	return true;
}

bool canSlipstream() {
	Object@[]@ selected = selectedObjects;
	for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
		Object@ obj = selected[i];
		if(canSlipstream(obj))
			return true;
	}
	return false;
}

bool targetFTL() {
	if(!canMove())
		return false;

	//Check for fling
	if(canFling()) {
		targetFling();
		return true;
	}

	//Check for hyperdrive
	if(canHyperdrive()) {
		targetHyperdrive();
		return true;
	}

	//Check for jumpdrive
	if(canJumpdrive()) {
		targetJumpdrive();
		return true;
	}

	//Check for slipstream
	if(canSlipstream()) {
		targetSlipstream();
		return true;
	}

	return false;
}

void FTLBind(bool pressed) {
	if(!pressed) {
		if(!targetFTL())
			sound::error.play(priority=true);
	}
}

void init() {
	keybinds::Global.addBind(KB_FTL, "FTLBind");
}
