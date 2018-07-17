from designs import checkCoreFacingBackwards;

bool checkRamjet(Design& design, Subsystem& sys) {
	if(checkCoreFacingBackwards(design, sys))
		return true;

	//Check all the scoops
	auto@ scoop = sys.type.module("Scoop");
	bool failed = false;
	for(uint i = 0, cnt = sys.hexCount; i < cnt; ++i) {
		vec2u hex = sys.hexagon(i);
		if(sys.module(i) is scoop) {
			if(!design.hull.active.valid(hex, HEX_UpRight) || design.hull.isExteriorInDirection(hex, HEX_UpRight))
				continue;
			if(!design.hull.active.valid(hex, HEX_DownRight) || design.hull.isExteriorInDirection(hex, HEX_DownRight))
				continue;
			design.addErrorHex(hex);
			failed = true;
		}
	}

	if(failed) {
		design.addError(true, locale::ERROR_SCOOP_FACE_FRONT, null, null, vec2u());
		return true;
	}
	return false;
}

bool checkSurroundedInSystem(Design& design, Subsystem& sys, const vec2u& hex) {
	bool valid = true;
	for(uint d = 0; d < 6; ++d) {
		vec2u other = hex;
		if(design.hull.active.advance(other, HexGridAdjacency(d))) {
			auto@ otherSys = design.subsystem(other);
			auto@ otherMod = design.module(other);
			if(otherSys !is sys || (otherMod !is sys.type.defaultModule && otherMod !is sys.type.coreModule)) {
				design.addErrorHex(other);
				valid = false;
			}
		}
	}

	if(!valid) {
		auto@ mod = design.module(hex.x, hex.y);
		design.addErrorHex(hex);
		design.addError(true, format(locale::ERROR_MUST_SURROUND, mod.name, sys.type.name), null, mod, hex);
		return true;
	}
	return false;
}
