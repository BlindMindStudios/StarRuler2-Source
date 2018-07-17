bool checkCoreFacingBackwards(Design& design, Subsystem& sys) {
	if(!design.hull.active.valid(sys.core, HEX_UpLeft) || design.hull.isExteriorInDirection(sys.core, HEX_UpLeft))
		return false;
	if(!design.hull.active.valid(sys.core, HEX_DownLeft) || design.hull.isExteriorInDirection(sys.core, HEX_DownLeft))
		return false;
	design.addError(true, format(locale::ERROR_FACE_BACKWARDS, sys.type.name), sys, null, sys.core);
	return true;
}

vec2u getTargetGridSize(const Design@ dsg) {
	return vec2u(max(1, uint(dsg.total(SV_GridWidth))), max(1, uint(dsg.total(SV_GridHeight))));
}

const vec2u FLAGSHIP_GRID_SIZE(28, 23);
const vec2u SUPPORT_GRID_SIZE(19, 16);
const vec2u SATELLITE_GRID_SIZE(21, 17);

vec2u getDesignGridSize(const Hull@ hull, double size) {
	if(hull.hasTag("Support"))
		return SUPPORT_GRID_SIZE;
	if(hull.hasTag("Satellite"))
		return SATELLITE_GRID_SIZE;
	return FLAGSHIP_GRID_SIZE;
}

vec2u getDesignGridSize(const string& type, double size) {
	if(type == "Support")
		return SUPPORT_GRID_SIZE;
	if(type == "Satellite")
		return SATELLITE_GRID_SIZE;
	return FLAGSHIP_GRID_SIZE;
}

bool checkGlobalDesign(Design& design, Subsystem& sys) {
	//Check for the correct grid size
	vec2u target = getTargetGridSize(design);
	if(design.hull.gridSize.x > int(target.x) || design.hull.gridSize.y > int(target.y)) {
		design.addError(true, locale::ERROR_GRID_SIZE, null, null, vec2u());
		return true;
	}
	return false;
}

bool checkCoversAllDirections(Design& design, Subsystem& sys) {
	auto gridSize = design.hull.gridSize;

	//Top & Bottom Lines
	for(uint i = 0, cnt = gridSize.x; i < cnt; ++i) {
		if(checkCovers(sys.type, design, vec2u(i, 0), HEX_DownLeft))
			return true;
		if(checkCovers(sys.type, design, vec2u(i, 0), HEX_Down))
			return true;
		if(checkCovers(sys.type, design, vec2u(i, 0), HEX_DownRight))
			return true;

		if(checkCovers(sys.type, design, vec2u(i, gridSize.y-1), HEX_UpLeft))
			return true;
		if(checkCovers(sys.type, design, vec2u(i, gridSize.y-1), HEX_Up))
			return true;
		if(checkCovers(sys.type, design, vec2u(i, gridSize.y-1), HEX_UpRight))
			return true;
	}

	//Right & Left Lines
	for(uint i = 0, cnt = gridSize.y; i < cnt; ++i) {
		if(checkCovers(sys.type, design, vec2u(0, i), HEX_DownRight))
			return true;
		if(checkCovers(sys.type, design, vec2u(0, i), HEX_UpRight))
			return true;

		if(checkCovers(sys.type, design, vec2u(gridSize.x-1, i), HEX_DownLeft))
			return true;
		if(checkCovers(sys.type, design, vec2u(gridSize.x-1, i), HEX_UpLeft))
			return true;
	}
	return false;
}

bool checkCovers(const SubsystemDef@ def, Design& design, vec2u& pos, HexGridAdjacency direction) {
	while(design.hull.active.valid(pos)) {
		auto@ sys = design.subsystem(pos);
		if(sys !is null) {
			if(sys.type is def)
				return false;
			design.addError(true, format(locale::ERROR_MUST_COVER, def.name), null, null, vec2u());
			return true;
		}
		if(!design.hull.active.advance(pos, direction))
			break;
	}
	return false;
}

bool checkAdjacentToEverything(Design& design, Subsystem& checkSys) {
	bool failed = false;
	for(uint i = 0, cnt = design.subsystemCount; i < cnt; ++i) {
		auto@ sys = design.subsystems[i];
		if(sys is checkSys)
			continue;
		if(sys.type.hasTag(ST_Ephemeral))
			continue;

		for(uint n = 0, ncnt = sys.hexCount; n < ncnt; ++n) {
			vec2u hex = sys.hexagon(n);
			if(!design.hull.active.valid(hex))
				continue;
			bool found = false;
			for(uint d = 0; d < 6; ++d) {
				vec2u other = hex;
				if(design.hull.active.advance(other, HexGridAdjacency(d))) {
					auto@ otherSys = design.subsystem(other);
					if(otherSys !is null && otherSys is checkSys) {
						found = true;
						break;
					}
				}
			}
			if(!found) {
				if(!failed) {
					design.addError(true, format(locale::ERROR_MUST_ADJACENT, checkSys.type.name), null, null, vec2u());
					failed = true;
				}
				design.addErrorHex(hex);
			}
		}
	}
	return failed;
}

bool checkAdjacentToAllInterior(Design& design, Subsystem& checkSys) {
	bool failed = false;
	for(uint i = 0, cnt = design.subsystemCount; i < cnt; ++i) {
		auto@ sys = design.subsystems[i];
		if(sys is checkSys)
			continue;
		if(sys.type.hasTag(ST_Ephemeral))
			continue;
		if(sys.type.hasTag(ST_ExternalSpace))
			continue;

		for(uint n = 0, ncnt = sys.hexCount; n < ncnt; ++n) {
			vec2u hex = sys.hexagon(n);
			if(!design.hull.active.valid(hex))
				continue;
			bool found = false;
			for(uint d = 0; d < 6; ++d) {
				vec2u other = hex;
				if(design.hull.active.advance(other, HexGridAdjacency(d))) {
					auto@ otherSys = design.subsystem(other);
					if(otherSys !is null && otherSys is checkSys) {
						found = true;
						break;
					}
				}
			}
			if(!found) {
				if(!failed) {
					design.addError(true, format(locale::ERROR_MUST_ADJACENT_INTERIOR, checkSys.type.name), null, null, vec2u());
					failed = true;
				}
				design.addErrorHex(hex);
			}
		}
	}
	return failed;
}

bool checkContiguous(Design& design, Subsystem& sys) {
	HexGridb checked(design.hull.active.width, design.hull.active.height);
	checked.clear(false);
	if(sys.hexCount > 0)
		markContiguous(design, sys, checked, sys.hexagon(0));
	for(uint i = 0, cnt = sys.hexCount; i < cnt; ++i) {
		if(!checked[sys.hexagon(i)]) {
			design.addError(true, format(locale::ERROR_CONTIGUOUS, sys.type.name), null, null, vec2u());
			return true;
		}
	}
	return false;
}

void markContiguous(Design& design, Subsystem& sys, HexGridb& grid, const vec2u& hex) {
	if(grid[hex])
		return;
	grid[hex] = true;
	for(uint d = 0; d < 6; ++d) {
		vec2u other = hex;
		if(design.hull.active.advance(other, HexGridAdjacency(d))) {
			auto@ otherSys = design.subsystem(other);
			if(otherSys is sys)
				markContiguous(design, sys, grid, other);
		}
	}
}

bool checkSinew(Design& design, Subsystem& sys) {
	bool errors = false;
	if(checkAdjacentToAllInterior(design, sys))
		errors = true;
	if(checkContiguous(design, sys))
		errors = true;
	return errors;
}

bool checkExposedLeftRight(Design& design, Subsystem& sys) {
	array<bool> hasExposed(6, false);
	for(uint i = 0, cnt = sys.hexCount; i < cnt; ++i) {
		vec2u hex = sys.hexagon(i);
		for(uint n = 0; n < 6; ++n) {
			if(design.hull.isExteriorInDirection(hex, HexGridAdjacency(n)))
				hasExposed[n] = true;
		}
	}
	if(!hasExposed[HEX_UpLeft] && !hasExposed[HEX_DownLeft]) {
		design.addError(true, format(locale::ERROR_EXPOSE_LEFT_RIGHT, sys.type.name), sys, null, vec2u());
		return true;
	}
	if(!hasExposed[HEX_UpRight] && !hasExposed[HEX_DownRight]) {
		design.addError(true, format(locale::ERROR_EXPOSE_LEFT_RIGHT, sys.type.name), sys, null, vec2u());
		return true;
	}
	return false;
}

#section server-side
void getDesignMesh(Empire@ owner, const Design& design, MeshDesc& mesh) {
	const Shipset@ ss;
	const ShipSkin@ skin;
	if(owner !is null)
		@ss = owner.shipset;

	if(ss !is null) {
		bool isCivilian = !design.hasTag(ST_Weapon) && !design.hasTag(ST_SupportCap);
		if(isCivilian) {
			if(design.hasSubsystem(subsystem::TractorBeam))
				@skin = ss.getSkin("Tractor");
			else if(design.hasSubsystem(subsystem::MiningLaser))
				@skin = ss.getSkin("Miner");
		}
		if(design.hasTag(ST_Gate) && design.hasTag(ST_Station))
			@skin = ss.getSkin("Gate");
	}

	if(skin !is null) {
		@mesh.model = skin.model;
		@mesh.material = skin.material;
	}
	else if(design.hasTag(ST_Gate) && design.hasTag(ST_Station)) {
		@mesh.model = model::Warpgate;
		@mesh.material = material::GenericPBR_Gate;
	}
	else {
		@mesh.model = design.hull.model;
		@mesh.material = design.hull.material;
	}

	@mesh.iconSheet = design.distantIcon.sheet;
	mesh.iconIndex = design.distantIcon.index;
}
