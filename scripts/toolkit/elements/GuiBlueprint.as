#section game
import elements.BaseGuiElement;
import design_stats;
import util.design_export;
import elements.GuiSprite;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiPanel;
import elements.GuiSkinElement;
import elements.MarkupTooltip;
import util.formatting;
from resources import getBuildCost;

export GuiBlueprint;
export GuiDownloadedBlueprint;
export GuiBlueprintStats;

/* {{{ Blueprints display */
enum HexSprite {
	HS_Hex = 0,
	HS_ElevEast = 1,
	HS_ElevSouth = 2,
	HS_ElevWest = 3,
	HS_Borders = 4,
	HS_Selection = 10,
};

enum SysDrawMode {
	SDM_Static,
	SDM_Rotatable,
};

const array<uint> BORDER_DRAW_ORDER = {
	HEX_Up,
	HEX_UpLeft,
	HEX_UpRight,
	HEX_DownLeft,
	HEX_DownRight,
	HEX_Down
};

const double BORDER_HEIGHT = 4.0;
const double BORDER_OFFSET = 8.0;
const vec2i HEX_SIZE(126, 65);
const double WIDTH_SCRUNCH = 92;
const double HEIGHT_SCRUNCH = 33;
const vec2d WALL_RATIO(253.0 / 253.0, 162.0 / 130.0);

const Color DAMAGE_BASE(0x000000ff);
const Color DAMAGE_GLOWING(0xff0000ff);
const Color DAMAGE_TILE(0x444444ff);
const Color DAMAGE_PIC(0x111111ff);
const Color REPAIR_GLOW(0x00ff00ff);
const double GLOW_PERIOD = 1.0;

const Color ARC_CENTER_COLOR(0x00ff00ff);
const Color ARC_BOUND_COLOR(0xff0000ff);

class GuiBlueprint : BaseGuiElement {
	//Position of the start of the hex grid
	vec2i hexPos;
	//Real size of the hex grid
	vec2i gridSize;
	//Real size of a hexagon
	vec2i hexSize;
	//Hexagon size factor
	double hexFactor;

	//Hovered hexagon
	vec2i hexHovered(-1, -1);
	//Whether all hexagons should be used,
	//even ones marked inactive
	bool activateAll = false;
	//Whether to display empty hexagons
	bool displayEmpty = false;
	//Whether to display inactive hexagons
	bool displayInactive = false;
	//Whether to highlight the hovered hex
	bool displayHovered = true;
	//Whether to highlight exterior hexes
	bool displayExterior = false;
	//Whether to display the hull's model in the background
	bool displayHull = false;
	//Whether to pop out hovered hexes
	bool popHover = false;
	//Size of the popped out hex
	vec2i popSize(102,53);
	//Whether to show firing arcs
	bool hoverArcs = false;
	//Whether to show hull hex use weights
	bool displayHullWeights = false;
	//Alignment of blueprint into area
	double horizAlign = 0.5;
	double vertAlign = 0.5;

	//Necessary: Hull type to draw
	const Hull@ hull;
	//Optional: Current design
	const Design@ design;
	//Optional: Current blueprint
	const Blueprint@ bp;
	//Optional: Object of blueprint
	Object@ obj;

	//Current frame damage color
	float glowPct = 0.f;
	Color damColor;

	//Damage storage
	array<uint8> prevDamage;
	array<double> damagedAt;

	//Draw buffers
	array<recti> emptyFloors;
	array<Color> emptyColors;

	array<recti> hexFloors;
	array<Color> floorColors;

	GuiBlueprint(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
	}

	GuiBlueprint(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
	}

	void display(const Hull@ Hull) {
		@hull = Hull;
		@design = null;
		@bp = null;
		@obj = null;
		hexHovered = vec2i(-1, -1);
		calculate();

		prevDamage.length = 0;
		damagedAt.length = 0;
	}

	void display(const Design@ dsg) {
		@hull = dsg.hull;
		@design = dsg;
		@bp = null;
		@obj = null;
		hexHovered = vec2i(-1, -1);
		calculate();

		prevDamage.length = 0;
		damagedAt.length = 0;
	}

	void display(Ship@ ship) {
		@bp = ship.blueprint;
		if(bp !is null)
			@design = bp.design;
		else
			@design = null;
		if(design !is null)
			@hull = design.hull;
		else
			@hull = null;
		@obj = ship;
		hexHovered = vec2i(-1, -1);
		calculate();

		ObjectLock lock(obj, true);
		prevDamage.length = design.usedHexCount;
		damagedAt.length = design.usedHexCount;
		for(uint i = 0; i < design.usedHexCount; ++i) {
			prevDamage[i] = bp.getHexStatus(i).hp;
			damagedAt[i] = 0.0;
		}
	}

	float hexDist(const vec2u& hex, const vec2i&in offset) {
		int seg = floor(BORDER_HEIGHT * hexFactor);
		vec2i pos = getHexPos(hex);
		int elev = getElevation(hex);

		pos.y -= elev * seg;
		return recti_area(pos, hexSize).center.distanceTo(offset);
	}

	vec2i getGridPosition(const vec2i& offset, bool selectInactive = false) {
		//Find the closest flat hex
		vec2d pos;
		pos.x = double(offset.x) / (floor(double(WIDTH_SCRUNCH) * hexFactor) / 0.75);
		pos.y = double(offset.y) / double(hexSize.y);
		vec2i hex = getHexGridPosition(pos);

		//Check all surrounding hexes
		float lowest = hexDist(vec2u(hex), offset);
		vec2i closest = hex;

		if(lowest != 0.f) {
			for(uint i = 0; i < 6; ++i) {
				vec2u other(hex);
				if(!advanceHexPosition(other, vec2u(hull.gridSize), HexGridAdjacency(i)))
					continue;
				float dist = hexDist(other, offset);
				if(dist < lowest) {
					lowest = dist;
					closest = vec2i(other);

					if(lowest == 0.f)
						break;
				}
			}
		}

		hex = closest;

		//Make sure the hex is active
		if(uint(hex.x) >= hull.active.width || uint(hex.y) >= hull.active.height)
			return vec2i(-1, -1);
		if(!selectInactive && !hull.active.get(hex.x, hex.y))
			return vec2i(-1, -1);
		return hex;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this && hull !is null) {
			switch(event.type) {
				case MET_Moved: {
					vec2i mouse = vec2i(event.x, event.y);
					vec2i offset = mouse - hexPos - AbsolutePosition.topLeft;

					vec2i prev = hexHovered;
					hexHovered = getGridPosition(offset, activateAll);
					if(obj !is null && hexHovered != vec2i(-1,-1)) {
						ObjectLock lock(obj, true);
						if(!activateAll && bp !is null) {
							auto@ status = bp.getHexStatus(hexHovered.x, hexHovered.y);
							if(status !is null && status.flags & HF_Gone != 0)
								hexHovered = vec2i(-1, -1);
						}
					}

					if(prev.x != hexHovered.x || prev.y != hexHovered.y) {
						GuiEvent evt;
						evt.type = GUI_Hover_Changed;
						@evt.caller = this;
						Parent.onGuiEvent(evt);
					}
				} break;
				case MET_Button_Up: {
					if(hexHovered.x < 0 || hexHovered.y < 0)
						break;
					if(hexHovered.x >= hull.gridSize.width ||
						hexHovered.y >= hull.gridSize.height)
						break;
					if(!activateAll && !hull.active.get(hexHovered.x, hexHovered.y))
						break;

					GuiEvent evt;
					evt.type = GUI_Clicked;
					evt.value = event.button;
					@evt.caller = this;
					Parent.onGuiEvent(evt);
				} break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					hexHovered = vec2i(-1,-1);
					return false;
				case GUI_Mouse_Left:
					if(hexHovered.x < 0 || hexHovered.y < 0)
						return false;
					hexHovered = vec2i(-1,-1);
					emitHoverChanged();
					return false;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	int getElevation(const vec2u& pos) {
		if(pos.x >= uint(hull.gridSize.x) || pos.y >= uint(hull.gridSize.y))
			return -3;
		if(!hull.active[pos])
			return -3;
		if(design !is null) {
			const Subsystem@ sys = design.subsystem(pos);
			if(sys !is null)
				return sys.type.elevation;
		}
		return 0;
	}

	void drawElevation(const vec2u& hex, vec2i& pos, double hexFactor, const vec2i& hexSize, bool floating = false, bool second=true) {
		int seg = floor(BORDER_HEIGHT * hexFactor);

		//Find surrounding elevation
		int elev = getElevation(hex);
		int s_elev = 0;
		int se_elev = 0, sw_elev = 0;
		if(!floating) {
			s_elev = getElevation(vec2u(hex.x, hex.y+1));
			if(hex.x % 2 == 0) {
				se_elev = getElevation(vec2u(hex.x+1, hex.y));
				sw_elev = getElevation(vec2u(hex.x-1, hex.y));
			}
			else {
				se_elev = getElevation(vec2u(hex.x+1, hex.y+1));
				sw_elev = getElevation(vec2u(hex.x-1, hex.y+1));
			}
		}
		else {
			elev += 1;
		}

		//Draw the borders
		int cur = min(s_elev, min(se_elev, sw_elev));
		if(elev < cur) {
			pos.y -= elev * seg;
			return;
		}

		pos.y -= cur * seg;

		recti wallPos = recti_centered(pos + vec2i(hexSize.x / 2, hexSize.y / 2 - BORDER_OFFSET * hexFactor),
				vec2i(hexSize.x * WALL_RATIO.x, hexSize.y * WALL_RATIO.y));
		while(cur < elev) {
			if(elev != -3) {
				if(sw_elev <= cur && (second ? sw_elev >= 0 : sw_elev < 0))
					spritesheet::HexRiser.draw(0, wallPos);
				if(s_elev <= cur && (second ? s_elev >= 0 : s_elev < 0))
					spritesheet::HexRiser.draw(1, wallPos);
				if(se_elev <= cur && (second ? se_elev >= 0 : se_elev < 0))
					spritesheet::HexRiser.draw(2, wallPos);
			}

			cur += 1;
			pos.y -= seg;
			wallPos -= vec2i(0, seg);
		}
	}

	vec2i getHexPos(const vec2u& hex, bool applyElevation = false) {
		vec2i pos;
		pos.x += hex.x * floor(WIDTH_SCRUNCH * hexFactor);
		pos.y += hex.y * hexSize.y;
		if(hex.x % 2 != 0)
			pos.y += ceil(HEIGHT_SCRUNCH * hexFactor);
		if(applyElevation)
			pos.y -= getElevation(hex) * floor(BORDER_HEIGHT * hexFactor);
		return pos;
	}

	void drawHexFloor(const vec2u& hex, const vec2i& atPos, const vec2i& size, bool floating = false) {
		bool active = hull.active[hex];
		if(!displayInactive && !active)
			return;

		uint hexIndex = 0;
		const HexStatus@ status;
		if(bp !is null) {
			hexIndex = uint(design.hexStatusIndex(hex));
			@status = bp.getHexStatus(hexIndex);
			if(status is null || status.flags & HF_Gone != 0)
				return;
		}

		vec2i pos = atPos;
		double factor = 0;
		if(floating)
			factor = double(size.x) / double(HEX_SIZE.x);
		else
			factor = hexFactor;

		const Subsystem@ subsys = null;
		if(design !is null)
			@subsys = design.subsystem(hex);
		if(subsys !is null && subsys.type.hasTag(ST_NoFloor))
			return;

		//Draw the elevation border
		drawElevation(hex, pos, factor, size, second=false);

		//Draw the actual hexagon
		Color color(0xffffffff);

		const Subsystem@ sys = null;
		if(design !is null)
			@sys = design.subsystem(hex);

		if(sys !is null)
			color = sys.type.color;
		else if(!active)
			color = Color(0x4040404f);
		else if(displayExterior && hull.isExterior(hex))
			color = Color(0xccccccff);

		//Display health
		float health = 0.f;
		bool inactive = false, repairing = false, damaging = false;

		if(bp !is null) {
			if(hexIndex != uint(-1)) {
				const SysStatus@ sys = bp.getSysStatus(hex.x, hex.y);
				if(sys !is null) {
					if(sys.status != ES_Active) {
						inactive = true;
						color = Color(0x909090ff).interpolate(color, 0.3f);
					}
				}
				if(status !is null && status.flags & HF_NoHP == 0) {
					repairing = int(hex.x) == bp.repairingHex.x
						&& int(hex.y) == bp.repairingHex.y;

					if(prevDamage[hexIndex] > status.hp) {
						damagedAt[hexIndex] = frameTime;
						damaging = true;
						prevDamage[hexIndex] = status.hp;
					}
					else {
						damaging = damagedAt[hexIndex] > frameTime - 3.0;
					}

					health = status.hp / float(0xff);
					if(repairing && health > 0.01f)
						color = DAMAGE_GLOWING.interpolate(color, health);
					else if(health < 0.01f)
						color = DAMAGE_TILE;
					else if(damaging)
						color = damColor.interpolate(color, health);
					else
						color = DAMAGE_TILE.interpolate(color, health);

					if(repairing)
						color = color.interpolate(REPAIR_GLOW, 1.f-glowPct);
				}
			}
		}

		recti drawPos = recti_area(pos, size);
		if(sys is null) {
			emptyFloors.insertLast(drawPos);
			emptyColors.insertLast(color);
		}
		else {
			hexFloors.insertLast(drawPos);
			floorColors.insertLast(color);
		}

		/*if(sys is null)*/
		/*	material::HexEmpty.draw(drawPos, color);*/
		/*else*/
		/*	material::HexFloor.draw(drawPos, color);*/
	}

	void drawHexWalls(const vec2u& hex, const vec2i& atPos, const vec2i& size, bool second = false) {
		bool active = hull.active[hex];
		if(!active)
			return;

		const Subsystem@ sys = null;
		if(design !is null)
			@sys = design.subsystem(hex);

		if(sys is null)
			return;
		if(sys.type.hasTag(ST_IsArmor) || sys.type.hasTag(ST_NoWall))
			return;

		bool isCore = sys !is null && hex == sys.core;
		bool noWallBack = false;
		bool noWallFront = false;
		if(sys !is null) {
			const ModuleDef@ mod = design.module(hex);
			if(isCore) {
				if(sys.type.hasTag(ST_NoBackWall))
					noWallBack = true;
				if(sys.type.hasTag(ST_NoFrontWall))
					noWallFront = true;
			}
			else if(mod !is sys.type.defaultModule && mod !is sys.type.coreModule && mod.defaultUnlock) {
				if(sys.type.hasTag(ST_ModuleNoFrontWall))
					noWallFront = true;
			}
		}

		double turretRadians = INFINITY;
		if(isCore && sys.type.hasTag(ST_Rotatable) && sys.effectorCount != 0) {
			vec2d dir(sys.direction.x, -sys.direction.z);
			turretRadians = dir.radians();
		}

		//Get the color of the wall
		Color color(0xffffffff);
		if(sys !is null)
			color = sys.type.color;
		else if(!active)
			color = Color(0x4040404f);
		else if(displayExterior && hull.isExterior(hex))
			color = Color(0xccccccff);
		float health = 1.f;
		bool inactive = false, repairing = false, damaging = false;

		uint hexIndex = 0;
		const HexStatus@ status;
		if(bp !is null) {
			hexIndex = uint(design.hexStatusIndex(hex));
			@status = bp.getHexStatus(hexIndex);

			if(status !is null) {
				const SysStatus@ sysstatus = bp.getSysStatus(hex.x, hex.y);
				if(sysstatus !is null) {
					if(sysstatus.status != ES_Active) {
						inactive = true;
						color = Color(0x909090ff).interpolate(color, 0.3f);
					}
				}
				if(status !is null && status.flags & HF_NoHP == 0) {
					repairing = int(hex.x) == bp.repairingHex.x
						&& int(hex.y) == bp.repairingHex.y;

					if(prevDamage[hexIndex] > status.hp) {
						damagedAt[hexIndex] = frameTime;
						damaging = true;
						prevDamage[hexIndex] = status.hp;
					}
					else {
						damaging = damagedAt[hexIndex] > frameTime - 3.0;
					}

					health = status.hp / float(0xff);
					if(repairing && health > 0.01f)
						color = DAMAGE_GLOWING.interpolate(color, health);
					else if(health < 0.01f)
						color = DAMAGE_TILE;
					else if(damaging)
						color = damColor.interpolate(color, health);
					else
						color = DAMAGE_TILE.interpolate(color, health);

					if(repairing)
						color = color.interpolate(REPAIR_GLOW, 1.f-glowPct);
				}
			}
		}

		vec2i pos = atPos;
		pos.y -= getElevation(hex) * floor(BORDER_HEIGHT * hexFactor);

		//Draw the subsystem borders
		vec2u grid(design.hull.gridSize);
		recti drawPos = recti_area(pos, size);
		recti wallPos = recti_centered(drawPos.center, vec2i(size.x * WALL_RATIO.x, size.y * WALL_RATIO.y));

		uint startAt = 0;
		uint endAt = 3;
		if(second) {
			startAt = 3;
			endAt = 6;
		}

		for(uint i = startAt; i < endAt; ++i) {
			uint edge = BORDER_DRAW_ORDER[i];
			vec2u other = hex;
			const Subsystem@ otherSys = null;
			if(advanceHexPosition(other, grid, HexGridAdjacency(edge)))
				@otherSys = design.subsystem(other);
			if(otherSys is null) {
				if(turretRadians != INFINITY && abs(angleDiff(turretRadians, hexToRadians(HexGridAdjacency(edge)))) < pi / 3.0)
					continue;
				if(noWallBack && (edge == HEX_UpLeft || edge == HEX_DownLeft))
					continue;
				if(noWallFront && (edge == HEX_UpRight || edge == HEX_DownRight))
					continue;
			}
			if(sys !is otherSys)
				spritesheet::HexWall.draw(edge, wallPos, color);
		}
	}

	void drawHex(const vec2u& hex, const vec2i& atPos, const vec2i& size, bool floating = false, bool drawFloor = true, bool drawWalls = true) {
		bool active = hull.active[hex];
		if(!displayInactive && !active)
			return;

		if(drawFloor)
			drawHexFloor(hex, atPos, size, floating);

		uint hexIndex = 0;
		const HexStatus@ status;
		if(bp !is null) {
			hexIndex = uint(design.hexStatusIndex(hex));
			@status = bp.getHexStatus(hexIndex);
			if(status.flags & HF_Gone != 0)
				return;
		}

		vec2i pos = atPos;
		double factor = 0;
		if(floating)
			factor = double(size.x) / double(HEX_SIZE.x);
		else
			factor = hexFactor;
		/*drawElevation(hex, pos, factor, size, floating, second=true);*/
		pos.y -= getElevation(hex) * floor(BORDER_HEIGHT * hexFactor);

		const Subsystem@ sys = null;
		if(design !is null)
			@sys = design.subsystem(hex);

		recti drawPos = recti_area(pos, size);
		bool isCore = sys !is null && hex == sys.core;
		drawWalls = drawWalls && (sys is null || (!sys.type.hasTag(ST_IsArmor) && !sys.type.hasTag(ST_NoWall)));
		bool noWallBack = sys !is null && isCore && sys.type.hasTag(ST_NoBackWall);
		double turretRadians = INFINITY;

		Color color(0xffffffff);
		if(sys !is null)
			color = sys.type.color;
		else if(!active)
			color = Color(0x4040404f);
		else if(displayExterior && hull.isExterior(hex))
			color = Color(0xccccccff);
		float health = 1.f;
		bool inactive = false, repairing = false, damaging = false;
		if(bp !is null) {
			if(hexIndex != uint(-1)) {
				const SysStatus@ sysstatus = bp.getSysStatus(hex.x, hex.y);
				if(sysstatus !is null) {
					if(sysstatus.status != ES_Active) {
						inactive = true;
						color = Color(0x909090ff).interpolate(color, 0.3f);
					}
				}
				if(status !is null && status.flags & HF_NoHP == 0) {
					repairing = int(hex.x) == bp.repairingHex.x
						&& int(hex.y) == bp.repairingHex.y;

					if(prevDamage[hexIndex] > status.hp) {
						damagedAt[hexIndex] = frameTime;
						damaging = true;
						prevDamage[hexIndex] = status.hp;
					}
					else {
						damaging = damagedAt[hexIndex] > frameTime - 3.0;
					}

					health = status.hp / float(0xff);
					if(repairing && health > 0.01f)
						color = DAMAGE_GLOWING.interpolate(color, health);
					else if(health < 0.01f)
						color = DAMAGE_TILE;
					else if(damaging)
						color = damColor.interpolate(color, health);
					else
						color = DAMAGE_TILE.interpolate(color, health);

					if(repairing)
						color = color.interpolate(REPAIR_GLOW, 1.f-glowPct);
				}
			}
		}
		if(sys !is null && isCore && sys.type.hasTag(ST_Rotatable) && sys.effectorCount != 0) {
			vec2d dir(sys.direction.x, -sys.direction.z);
			turretRadians = dir.radians();
		}

		//Draw the subsystem borders
		if(sys !is null && drawWalls) {
			vec2u grid(design.hull.gridSize);
			recti wallPos = recti_centered(drawPos.center, vec2i(size.x * WALL_RATIO.x, size.y * WALL_RATIO.y));
			for(uint i = 0; i < 3; ++i) {
				uint edge = BORDER_DRAW_ORDER[i];
				vec2u other = hex;
				const Subsystem@ otherSys = null;
				if(advanceHexPosition(other, grid, HexGridAdjacency(edge)))
					@otherSys = design.subsystem(other);
				if(otherSys is null) {
					if(turretRadians != INFINITY && abs(angleDiff(turretRadians, hexToRadians(HexGridAdjacency(edge)))) < pi / 3.0)
						continue;
					if(noWallBack && (edge == HEX_UpLeft || edge == HEX_DownLeft))
						continue;
				}
				if(sys !is otherSys)
					spritesheet::HexWall.draw(edge, wallPos, color);
			}
		}

		//Draw the picture
		if(design !is null) {
			const ModuleDef@ mod = design.module(hex);
			Color color;
			if(bp !is null) {
				if(inactive)
					color = Color(0x606060ff).interpolate(color, 0.5f);
				if(repairing && health > 0.01f)
					color = DAMAGE_GLOWING.interpolate(color, health);
				else if(health < 0.01f)
					color = DAMAGE_PIC;
				else if(damaging)
					color = damColor.interpolate(color, health);
				else
					color = DAMAGE_PIC.interpolate(color, health);

				if(repairing)
					color = color.interpolate(REPAIR_GLOW, 1.f-glowPct);
			}

			if(mod !is null && mod.sprite.valid) {
				//Modify size to draw size
				vec2i modSize = mod.sprite.size;
				modSize.x = double(modSize.x) * factor;
				modSize.y = double(modSize.y) * factor;

				//Offset for floating
				pos.x -= (modSize.x - size.x) / 2;
				if(modSize.y > size.y)
					pos.y -= (modSize.y - size.y);
				else
					pos.y -= (modSize.y - size.y) / 2;

				double rotation = 0.0;
				if(mod is sys.type.coreModule && sys.type.hasTag(ST_Rotatable)) {
					vec3d rot = sys.direction;
					vec2d rightvec(1.0, 0.0);
					vec2d rotvec(rot.x, rot.z);
					rotation = rightvec.getRotation(rotvec);
				}

				//Draw the image
				switch(mod.drawMode) {
					case SDM_Static:
						if(rotation != 0)
							mod.sprite.draw(recti_area(pos, modSize), color, rotation);
						else
							mod.sprite.draw(recti_area(pos, modSize), color);
					break;
					case SDM_Rotatable: {
						vec3d rot = sys.direction;
						vec2d rightvec(1.0, 0.0);
						vec2d rotvec(rot.x, -rot.z);
						rotation = rightvec.getRotation(rotvec);

						if(modSize.y > size.y)
							pos.y += (modSize.y - size.y) / 2;

						Sprite sprt = mod.sprite;
						sprt.index += HexGridAdjacency(radiansToHex(rotation));

						double diffrot = hexToRadians(HexGridAdjacency(sprt.index)) - rotation;
						sprt.draw(recti_area(pos, modSize), color, diffrot);
					} break;
				}
			}
		}

		//Draw the subsystem borders
		recti wallPos = recti_centered(drawPos.center, vec2i(size.x * WALL_RATIO.x, size.y * WALL_RATIO.y));
		if(sys !is null && drawWalls) {
			vec2u grid(design.hull.gridSize);
			for(uint i = 3; i < 6; ++i) {
				uint edge = BORDER_DRAW_ORDER[i];
				vec2u other = hex;
				const Subsystem@ otherSys = null;
				if(advanceHexPosition(other, grid, HexGridAdjacency(edge)))
					@otherSys = design.subsystem(other);
				if(otherSys is null) {
					if(turretRadians != INFINITY && abs(angleDiff(turretRadians, hexToRadians(HexGridAdjacency(edge)))) < pi / 3.0)
						continue;
					if(noWallBack && (edge == HEX_UpLeft || edge == HEX_DownLeft))
						continue;
				}
				if(sys !is otherSys)
					spritesheet::HexWall.draw(edge, wallPos, color);
			}
		}

		//Draw hex use weight
		if(displayHullWeights) {
			vec2d pctPos = getHexPosition(hex.x, hex.y);
			pctPos.x += 0.75 * 0.5;
			pctPos.y += 0.5;
			pctPos.x /= double(hull.gridSize.width) * 0.75;
			pctPos.y /= double(hull.gridSize.height);

			double w = hull.getMatchDistance(pctPos);
			skin.getFont(FT_Small).draw(
				pos=wallPos, horizAlign=0.5, vertAlign=0.5,
				stroke=colors::Black, text=toString(w, 0));
		}

		//Draw hex errors
		if(design !is null && design.isErrorHex(hex))
			material::HexError.draw(drawPos);
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		calculate();
	}

	void calculate() {
		if(hull is null)
			return;

		//Sizes before zoom
		vec2i bSize = size;
		if(bSize.width == 0 || bSize.height == 0)
			return;
		double bAspect = double(bSize.width) / double(bSize.height);
		double hAspect = double(HEX_SIZE.width) / double(HEX_SIZE.height);

		vec2i grid = hull.gridSize;

		//Calculate necessary zoom
		double xneed = double(bSize.width) / (double(grid.width) * 0.75);
		double yneed = double(bSize.height) / double(grid.height) * hAspect;
		hexSize.x = floor(min(xneed, yneed));
		hexSize.y = max(ceil(double(hexSize.x) / hAspect), 1.0);
		hexFactor = double(hexSize.x) / double(HEX_SIZE.x);

		gridSize.x = floor(WIDTH_SCRUNCH * hexFactor) * double(grid.width);
		gridSize.y = hexSize.y * double(grid.height);

		hexPos = vec2i(
				double(bSize.width - gridSize.x) * horizAlign,
				double(bSize.height - gridSize.y - floor(HEIGHT_SCRUNCH*hexFactor*0.5)) * vertAlign);
	}

	void draw() {
		if(hull is null)
			return;

		//Lock the object when displaying an
		//active blueprint so we can safely
		//pull data from its status members
		if(obj !is null) {
			ObjectLock lock(obj, true);
			drawAll();
		}
		else {
			drawAll();
		}
	}

	void drawPopped(vec2u hex, const vec2i& start) {
		bool active = hull.active[hex];
		if(!displayInactive && !active)
			return;

		recti around = recti_area(getHexPos(hex) + start, hexSize);
		around = recti_centered(around.center, popSize);
		drawHex(hex, around.topLeft, around.size, true);
	}

	void drawFireArc(const vec2u& hex, float alpha = 1.f) {
		if(design is null)
			return;

		const Subsystem@ sys = design.subsystem(hex);
		const ModuleDef@ mod = design.module(hex);

		if(sys !is null && mod !is null && mod is sys.type.coreModule && sys.effectorCount != 0) {
			auto@ eff = sys.effectors[0];
			if(eff.fireArc < pi || sys.type.hasTag(ST_HexLimitArc)) {
				vec3d dir = eff.turretAngle;
				vec2d flatDir(dir.x, dir.z);
				double rad = flatDir.radians();

				double arc = eff.fireArc;
				Color color = sys.type.color;
				color.a *= alpha;

				recti pos = recti_centered(getHexPos(hex) + hexPos + AbsolutePosition.topLeft + (hexSize / 2), vec2i(hexSize.width * 7));
				shader::MIN_RAD = rad - arc;
				shader::MAX_RAD = rad + arc;

				clearClip();
				material::FireArc2D.draw(pos, color);
			}
		}
	}

	void drawAll() {
		emptyFloors.length = 0;
		emptyColors.length = 0;
		hexFloors.length = 0;
		floorColors.length = 0;

		if(hexSize.width == 0)
			calculate();
		float glowTime = frameTime % GLOW_PERIOD;
		glowPct = 0.f;
		if(glowTime < GLOW_PERIOD * 0.5f)
			glowPct = glowTime / (GLOW_PERIOD * 0.5f);
		else
			glowPct = 1.f - ((glowTime - GLOW_PERIOD * 0.5f) / (GLOW_PERIOD * 0.5f));

		damColor = DAMAGE_BASE.interpolate(DAMAGE_GLOWING, glowPct);

		//Draw the background
		vec2i topLeft = AbsolutePosition.topLeft;
		recti gridPos = recti_area(topLeft + hexPos, gridSize);
		if(displayHull)
			hull.model.draw(hull.background, gridPos,
					quaterniond_fromAxisAngle(vec3d_front(), pi * -0.5),
					hull.backgroundScale);

		//Draw all the hexes
		uint width = hull.gridSize.width;
		uint height = hull.gridSize.height;
		vec2i start = hexPos + topLeft;
		for(uint y = 0; y < height; ++y) {
			for(uint x = 0; x < width; x += 2)
				drawHexFloor(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize);
			for(uint x = 1; x < width; x += 2)
				drawHexFloor(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize);
		}
		for(uint i = 0, cnt = emptyFloors.length; i < cnt; ++i)
			material::HexEmpty.draw(emptyFloors[i], emptyColors[i]);
		for(uint i = 0, cnt = hexFloors.length; i < cnt; ++i)
			material::HexFloor.draw(hexFloors[i], floorColors[i]);

		/*for(uint y = 0; y < height; ++y) {*/
		/*	for(uint x = 0; x < width; x += 2)*/
		/*		drawHex(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, drawFloor=false, drawWalls=true);*/
		/*	for(uint x = 1; x < width; x += 2)*/
		/*		drawHex(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, drawFloor=false, drawWalls=true);*/
		/*}*/

		for(uint y = 0; y < height; ++y) {
			for(uint x = 0; x < width; x += 2)
				drawHexWalls(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize);
			for(uint x = 0; x < width; x += 2)
				drawHex(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, drawFloor=false, drawWalls=false);
			for(uint x = 0; x < width; x += 2)
				drawHexWalls(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, second=true);

			for(uint x = 1; x < width; x += 2)
				drawHexWalls(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize);
			for(uint x = 1; x < width; x += 2)
				drawHex(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, drawFloor=false, drawWalls=false);
			for(uint x = 1; x < width; x += 2)
				drawHexWalls(vec2u(x, y), getHexPos(vec2u(x, y)) + start, hexSize, second=true);
		}

		if(hexHovered.x >= 0 && hexHovered.y >= 0 && (design is null || design.validHex(vec2u(hexHovered)))) {
			//Draw popped hex
			if(popHover) {
				drawPopped(vec2u(hexHovered), start);
			}

			//Draw selection
			else if(displayHovered) {
				material::SubsystemCursor.draw(recti_centered(
					getHexPos(vec2u(hexHovered), true) + start + (hexSize / 2),
					vec2i(hexSize.x * WALL_RATIO.x, hexSize.y * WALL_RATIO.y)));
			}

			//Draw firing arcs when hovering turrets
			if(hoverArcs && design !is null) {
				vec2u hex = vec2u(hexHovered);
				drawFireArc(hex);
			}
		}

		BaseGuiElement::draw();
	}
};
/* }}} */
/* {{{ Blueprints from the net */
class DownloadedComment {
	string author;
	string ctime;
	string content;
};

class GuiDownloadedBlueprint : BaseGuiElement {
	GuiBlueprint@ bp = GuiBlueprint(this, Alignment().fill());
	DesignDescriptor desc;
	WebData data;
	int designId;
	const Design@ dsg;
	bool loaded = false;
	bool started = false;
	bool statsShown = false;
	recti padding;

	string author;
	string description;
	string ctime;

	bool hasUpvoted = false;
	uint upvotes = 0;
	bool isMine = false;

	uint commentCount = 0;
	array<DownloadedComment> comments;

	GuiPanel@ statPanel;
	GuiSkinElement@ shipCostBG;
	GuiMarkupText@ shipCost;
	GuiBlueprintStats@ globalStats;
	GuiSkinElement@ statsPopup;
	GuiSkinElement@ sysNameBG;
	GuiText@ sysName;
	GuiSkinElement@ sysCostBG;
	GuiMarkupText@ sysCost;
	GuiBlueprintStats@ sysStats;
	GuiSkinElement@ hexNameBG;
	GuiText@ hexName;
	GuiBlueprintStats@ hexStats;
	GuiSkinElement@ hexCostBG;
	GuiMarkupText@ hexCost;

	GuiDownloadedBlueprint(IGuiElement@ elem, const recti& pos) {
		super(elem, pos);
	}

	GuiDownloadedBlueprint(IGuiElement@ elem, Alignment@ align) {
		super(elem, align);
	}

	void load(int id) {
		if(started && !loaded)
			return;
		clear();
		started = true;
		designId = id;

		webAPICall("design/"+toString(id), this.data);
	}

	void update() {
		if(started && !loaded && data.completed && !data.error) {
			loaded = true;

			JSONTree tree;
			tree.parse(data.result);
			finishLoad(tree.root);
		}
	}

	void finishLoad(JSONNode@ root) {
		if(root is null || !root.isObject())
			return;

		loaded = true;
		started = true;

		JSONNode@ data = root.findMember("data");
		if(!data.isString())
			return;
		JSONTree dsgTree;
		dsgTree.parse(data.getString());

		if(unserialize_design(dsgTree, desc)) {
			@desc.hull = getBestHull(desc, getHullTypeTag(desc.hull));
			@dsg = makeDesign(desc);
			bp.display(dsg);
			updateGlobalStats();
		}

		@data = root.findMember("id");
		if(data !is null && data.isInt())
			designId = data.getInt();

		@data = root.findMember("author");
		if(data !is null && data.isString())
			author = data.getString();
		else
			author = "N/A";

		@data = root.findMember("description");
		if(data !is null && data.isString())
			description = data.getString();
		else
			description = "";

		@data = root.findMember("ctime");
		if(data !is null && data.isString())
			ctime = data.getString();
		else
			ctime = "";

		@data = root.findMember("isMine");
		if(data !is null && data.isBool())
			isMine = data.getBool();
		else
			isMine = false;

		@data = root.findMember("hasUpvoted");
		if(data !is null && data.isBool())
			hasUpvoted = data.getBool() || isMine;
		else
			hasUpvoted = isMine;

		@data = root.findMember("commentCount");
		if(data !is null && data.isNumber())
			commentCount = data.getNumber();
		else
			commentCount = 0;

		@data = root.findMember("comments");
		if(data !is null && data.isArray()) {
			comments.length = data.size();
			for(uint i = 0, cnt = data.size(); i < cnt; ++i) {
				auto@ c = comments[i];
				auto@ dat = data[i];
				if(!dat.isObject())
					continue;

				auto@ n = dat.findMember("author");
				if(n !is null && n.isString())
					c.author = n.getString();

				@n = dat.findMember("ctime");
				if(n !is null && n.isString())
					c.ctime = n.getString();

				@n = dat.findMember("content");
				if(n !is null && n.isString())
					c.content = n.getString();
			}
		}
		else {
			comments.length = 0;
		}

		@data = root.findMember("upvotes");
		if(data !is null && data.isNumber())
			upvotes = data.getNumber();
		else
			upvotes = 0;
	}

	void set_showStats(bool value) {
		if(statsShown == value)
			return;

		statsShown = value;

		if(statsShown) {
			if(statPanel is null) {
				@statPanel = GuiPanel(this, Alignment(Right-250, Top, Right, Bottom));

				@shipCostBG = GuiSkinElement(statPanel, recti(0,4,246,38), SS_HorizBar);
				shipCostBG.color = Color(0x888888ff);
				shipCostBG.padding = recti(0,-4,0,-4);
				@shipCost = GuiMarkupText(shipCostBG, Alignment().padded(8,0,0,4));
				shipCost.text = "--";

				@globalStats = GuiBlueprintStats(statPanel,
					recti(vec2i(0, 30), vec2i(250, 230)));

				@statsPopup = GuiSkinElement(this, recti_area(0, 30, 250, 200), SS_PlainBox);
				statsPopup.visible = false;

				@sysNameBG = GuiSkinElement(statsPopup,
					recti(0, 0, 246, 30), SS_SubTitle);
				@sysName = GuiText(sysNameBG,
					recti(12, 0, 250, 30));
				sysName.font = FT_Medium;

				@sysCostBG = GuiSkinElement(statsPopup, recti(0,0,246,30), SS_HorizBar);
				sysCostBG.color = Color(0x888888ff);
				sysCostBG.padding = recti(0,-4,0,-4);
				@sysCost = GuiMarkupText(sysCostBG, Alignment().padded(8,0,0,4));
				sysCost.text = "--";

				@sysStats = GuiBlueprintStats(statsPopup,
					recti(vec2i(0, 30), vec2i(246, 200)));

				@hexNameBG = GuiSkinElement(statsPopup,
					recti(0, 0, 246, 30), SS_SubTitle);
				@hexName = GuiText(hexNameBG,
					recti(12, 0, 250, 30));
				hexName.font = FT_Medium;

				@hexCostBG = GuiSkinElement(statsPopup, recti(0,0,246,30), SS_HorizBar);
				hexCostBG.color = Color(0x888888ff);
				hexCostBG.padding = recti(0,-4,0,-4);
				@hexCost = GuiMarkupText(hexCostBG, Alignment().padded(8,0,0,4));
				hexCost.text = "--";

				@hexStats = GuiBlueprintStats(statsPopup,
					recti(vec2i(0, 30), vec2i(246, 200)));
			}

			statPanel.visible = true;
		}
		else {
			if(statPanel !is null)
				statPanel.visible = false;
		}

		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		if(bp !is null) {
			updateStatsPos();
			if(statPanel !is null && statPanel.visible) {
				bp.alignment = Alignment(Left, Top, Right-250, Bottom).padded(padding.topLeft.x,
						padding.topLeft.y, padding.botRight.x, padding.botRight.y);
			}
			else {
				bp.alignment = Alignment().padded(padding.topLeft.x,
						padding.topLeft.y, padding.botRight.x, padding.botRight.y);
			}
		}
		BaseGuiElement::updateAbsolutePosition();
	}

	void updateGlobalStats() {
		if(globalStats !is null && dsg !is null) {
			globalStats.setStats(getDesignStats(dsg));

			int build = 0, maintain = 0;
			double labor = 0.0;
			getBuildCost(dsg, build, maintain, labor);
			shipCost.text = format("[offset=4][img=ResourceIcon::0;24/] [vspace=4]$1"
					"[/vspace][offset=140][img=ResourceIcon::6;24/] [vspace=4]$2[/vspace][/offset][/offset]",
				formatMoney(build, maintain), standardize(labor, dsg.size >= 16));

		}
	}

	void updateStats() {
		if(statsPopup is null)
			return;
		if(dsg is null) {
			statsPopup.visible = false;
			return;
		}

		vec2i hex = bp.hexHovered;
		if(hex.x < 0 || hex.y < 0
				|| hex.x >= dsg.hull.gridSize.x
				|| hex.y >= dsg.hull.gridSize.y) {
			statsPopup.visible = false;
			return;
		}

		const Subsystem@ sys = dsg.subsystem(vec2u(hex));
		if(sys is null) {
			statsPopup.visible = false;
			return;
		}

		statsPopup.visible = true;
		statsPopup.color = sys.type.color;

		sysNameBG.position = vec2i(2, 0);
		sysName.text = sys.type.name;
		sysNameBG.color = sys.type.color;

		sysCostBG.position = vec2i(2, 30);
		sysStats.position = vec2i(2, 28 + 26);
		sysStats.setStats(getSubsystemStats(dsg, sys));

		hexNameBG.position = vec2i(2, sysStats.Position.botRight.y + 6);
		hexNameBG.color = sys.type.color;

		auto@ mod = dsg.module(vec2u(hex));
		string txt;
		if(mod !is null && mod !is sys.type.defaultModule) {
			if(mod is sys.type.coreModule)
				txt = locale::SUBSYS_CORE+locale::SUBSYS_AT;
			else
				txt = mod.name+locale::SUBSYS_AT;
		}
		else {
			txt = locale::SUBSYS_HEX;
		}
		txt += hex.x+", "+hex.y;
		hexName.text = txt;

		hexCostBG.position = vec2i(2, sysStats.Position.botRight.y + 36);
		hexStats.position = vec2i(2, sysStats.Position.botRight.y + 34 + 26);
		hexStats.setStats(getHexStats(dsg, vec2u(hex)));

		statsPopup.size = vec2i(250, hexStats.Position.botRight.y);
		updateStatsPos();

		double build = 0, maintain = 0, labor = 0;

		if(sys.has(HV_BuildCost))
			build = sys.total(HV_BuildCost);
		if(sys.has(HV_MaintainCost))
			maintain = sys.total(HV_MaintainCost);
		if(sys.has(HV_LaborCost))
			labor = sys.total(HV_LaborCost);
		sysCost.text = format("[color=#ccc][offset=16][img=ResourceIcon::0;24/] [vspace=4]$1"
				"[/vspace][offset=130][img=ResourceIcon::6;24/] [vspace=4]$2[/vspace][/offset][/offset][/color]",
			formatMoney(ceil(build), ceil(maintain)), standardize(labor, dsg.size >= 16));

		if(sys.has(HV_BuildCost))
			build = dsg.variable(vec2u(hex), HV_BuildCost);
		if(sys.has(HV_MaintainCost))
			maintain = dsg.variable(vec2u(hex), HV_MaintainCost);
		if(sys.has(HV_LaborCost))
			labor = dsg.variable(vec2u(hex), HV_LaborCost);
		hexCost.text = format("[color=#ccc][offset=16][img=ResourceIcon::0;24;#ffffffaa/] [vspace=4]$1"
				"[/vspace][offset=130][img=ResourceIcon::6;24;#ffffffaa/] [vspace=4]$2[/vspace][/offset][/offset][/color]",
			formatMoney(ceil(build), ceil(maintain)), standardize(labor, dsg.size >= 16));

		updateStatsPos();
	}

	void updateStatsPos() {
		if(statPanel is null)
			return;
		vec2i center = AbsolutePosition.center;
		vec2i pos;
		if(statPanel.size.height - globalStats.size.height - 60 > statsPopup.size.height) {
			pos.x = statPanel.rect.topLeft.x;
			pos.y = statPanel.rect.topLeft.y + globalStats.size.height + 30;
		}
		else {
			pos.x = bp.rect.botRight.x - statsPopup.size.width;
			pos.y = bp.rect.topLeft.y;
			if(mousePos.x > bp.absolutePosition.center.x)
				pos.x = bp.rect.topLeft.x;
		}
		statsPopup.position = pos;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is bp) {
			switch(event.type) {
				case GUI_Clicked:
					return true;

				case GUI_Hover_Changed:
					updateStats();
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void clear() {
		@dsg = null;
		const Hull@ hl = null;
		bp.display(hl);
		started = false;
		loaded = false;
	}

	void draw() {
		update();
		if(statPanel !is null)
			skin.draw(SS_PlainBox, SF_Normal, statPanel.absolutePosition);
		BaseGuiElement::draw();
	}
}
/* }}} */
/* Stat display list element {{{*/
class GuiBlueprintStats : BaseGuiElement {
	array<StatBox@> boxes;

	GuiBlueprintStats(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		uint h = 6;
		for(uint i = 0, cnt = boxes.length; i < cnt; ++i) {
			boxes[i].updateAbsolutePosition();
			boxes[i].position = vec2i(0, h);
			h += boxes[i].size.height;
		}
		size = vec2i(size.width, h+12);
		BaseGuiElement::updateAbsolutePosition();
	}

	void setStats(DesignStats@ stats) {
		uint oldCnt = boxes.length;
		uint newCnt = 0;

		for(uint i = 0, cnt = stats.stats.length; i < cnt; ++i) {
			if(stats.stats[i].secondary != -1)
				continue;
			if(newCnt >= boxes.length)
				boxes.insertLast(StatBox(this));
			boxes[newCnt].update(stats, i);
			newCnt += 1;
		}

		for(uint i = newCnt; i < oldCnt; ++i)
			boxes[i].remove();
		boxes.length = newCnt;
		updateAbsolutePosition();
	}
};

string shipStat(double value) {
	uint decimals = 0;
	if(value <= 10.0)
		decimals = 2;
	else if(value <= 100.0)
		decimals = 1;

	if(decimals == 2 && abs(value - round(value)) < 0.01)
		decimals = 0;
	if(decimals == 1 && abs(value - round(value)) < 0.1)
		decimals = 0;

	string fmt = toString(value, decimals);
	int index = fmt.length - decimals - 3;
	while(index > 0) {
		fmt = fmt.substr(0,index) + "," + fmt.substr(index);
		index -= 3;
	}
	return fmt;
}

class StatBox : BaseGuiElement {
	DesignStats@ stats;
	uint index;
	float pct = 0.f;

	GuiSprite@ icon;
	GuiText@ name;
	GuiText@ value;
	Color color;

	StatBox(GuiBlueprintStats@ disp) {
		super(disp, recti(0,0,100,40));

		@icon = GuiSprite(this, Alignment(Left+2, Top+2, Left+38, Bottom-2));

		@name = GuiText(this, Alignment(Left+46, Top+5, Right-8, Bottom-5));
		name.font = FT_Bold;
		name.vertAlign = 0.0;

		@value = GuiText(this, Alignment(Left+46, Top+5, Right-8, Bottom-5));
		value.vertAlign = 1.0;
		value.horizAlign = 1.0;
		value.stroke = colors::Black;

		addLazyMarkupTooltip(this, width = 400);

		updateAbsolutePosition();
	}

	string get_tooltip() override {
		string tt = "";
		int globIndex = stats.stats[index].index;
		for(uint i = 0, cnt = stats.stats.length; i < cnt; ++i) {
			auto@ stat = stats.stats[i];
			if(i != index && stat.secondary != globIndex)
				continue;

			string val;
			if(i < stats.used.length && stats.used[i] >= 0.f)
				val = shipStat(stats.used[i]) + " / " + shipStat(stats.values[i]);
			else
				val = shipStat(stats.values[i]);
			if(stat.suffix.length != 0) {
				val += " ";
				val += stat.suffix;
			}

			if(tt.length != 0)
				tt += "\n\n";
			tt += format("[img=$1;40][font=Subtitle][color=$4]$2[/color][offset=200]$5[/offset][/font]\n[vspace=6/]$3[/img]",
				getSpriteDesc(stat.icon), stat.name, stat.description,
				toString(stat.color), val);
		}
		return tt;
	}

	void updateAbsolutePosition() {
		size = vec2i(parent.size.width, size.height);
		BaseGuiElement::updateAbsolutePosition();
	}

	void update(DesignStats@ stats, uint index) {
		@this.stats = stats;
		this.index = index;
		auto@ stat = stats.stats[index];
		float val = stats.values[index];
		float used = -1.f;
		if(stats.used.length > index)
			used = stats.used[index];

		uint height = 40;
		if(stat.display == SDM_Short)
			height = 28;
		size = vec2i(size.width, height);

		icon.desc = stat.icon;
		name.text = stat.name;
		color = stat.color;
		name.color = color;

		value.color = colors::White;
		string txt;
		if(used >= 0.f) {
			txt = shipStat(used) + " / " + shipStat(val);
			if(used > val) {
				value.color = colors::Red;
				value.font = FT_Bold;
			}
			else {
				value.font = FT_Normal;
			}
			pct = clamp(used / val, 0.0, 1.0);
		}
		else {
			if(stat.display == SDM_Short && val >= 100000)
				txt = standardize(val, true);
			else
				txt = shipStat(val);
			value.font = FT_Normal;
			pct = 0.f;
		}

		if(stat.suffix.length != 0) {
			txt += " ";
			txt += stat.suffix;
		}
		value.text = txt;
	}

	void draw() {
		skin.draw(SS_HorizBar, SF_Normal, AbsolutePosition, color);
		if(pct > 0.f) {
			recti pos = AbsolutePosition.padded(46, 30, 4, 4);
			skin.draw(SS_ProgressBarBG, SF_Normal, pos, Color(0x000000ff));
			pos.botRight.x = pos.topLeft.x + (double(pos.width) * pct);
			skin.draw(SS_ProgressBar, SF_Normal, pos.padded(1), color);
		}

		BaseGuiElement::draw();
	}
};
/** }}} */
