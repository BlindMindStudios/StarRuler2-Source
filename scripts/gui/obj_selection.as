import systems;
import navigation.SmartCamera;
from navigation.elevation import getElevationIntersect, getElevation;
from input import activeCamera;
import ftl;
import tabs.Tab;
import orbitals;
import orders;
import resources;
import abilities;
import buildings;
from hooks import Hook;
from generic_effects import AddTurret, GenericRepeatHook, ShowsRange, IfHook;
from targeting.targeting import hoverFilter, lastHoverFilter;

bool debugCursor = false;
double get_DOUBLECLICK_TIME() {
	return double(settings::iDoubleClickMS) / 1000.0;
}
const double HOVER_CONE_SLOPE = 0.02;

import void targetMovement() from "targeting.MoveTarget";
import bool canMove(Object& obj) from "targeting.MoveTarget";
import Tab@ get_ActiveTab() from "tabs.tabbar";
import bool isGuiHovered() from "gui";
import void pinObject(Tab@ _tab, Object@ obj, bool floating) from "tabs.GalaxyTab";
import void zoomTabTo(Object@ obj) from "tabs.GalaxyTab";
import void openOverlay(Object@ obj) from "tabs.GalaxyTab";
import void openSupportOverlay(Object@ obj) from "tabs.GalaxyTab";

set_int selectedIDs;
array<Object@> selection;
array<array<Object@>> groups(9);
Object@ hovered;
Object@ uiobj;

vec2i lastMousePos;

Object@ get_hoveredObject() {
	if(lastMousePos != mousePos || hoverFilter !is lastHoverFilter)
		updateHoveredObject();
	return hovered;
}

Object@ get_uiObject() {
	return uiobj;
}

void set_uiObject(Object@ obj) {
	@uiobj = obj;
}

array<Object@>@ get_selectedObjects() {
	return selection;
}

Object@ get_selectedObject() {
	if(selection.length == 0)
		return null;
	return selection[0];
}

bool isSelected(Object@ obj) {
	return selectedIDs.contains(obj.id);
}

void selectObject(Object@ obj) {
	if(ctrlKey)
		toggleObjectSelect(obj);
	else
		selectObject(obj, shiftKey);
}

void deselectObject(Object@ obj) {
	obj.selected = false;
	selection.remove(obj);
	selectedIDs.erase(obj.id);
	updateBeams();
}

void clearSelection() {
	for(uint i = 0, cnt = selection.length; i < cnt; ++i)
		selection[i].selected = false;
	selection.length = 0;
	selectedIDs.clear();
}

void addToSelection(Object@ obj) {
	if(!selectedIDs.contains(obj.id)) {
		obj.selected = true;
		selection.insertLast(obj);
		selectedIDs.insert(obj.id);
	}
}

void toggleObjectSelect(Object@ obj) {
	if(obj is null)
		return;
	if(isSelected(obj))
		deselectObject(obj);
	else
		selectObject(obj, true);
}

void selectObject(Object@ obj, bool add) {
	if(obj is null) {
		for(uint i = 0, cnt = selection.length; i < cnt; ++i)
			selection[i].selected = false;
		selection.length = 0;
		selectedIDs.clear();
	}
	else if(!add) {
		for(uint i = 0, cnt = selection.length; i < cnt; ++i)
			selection[i].selected = false;
		if(ctrlKey) {
			selection.length = 1;
			@selection[0] = obj;
			obj.selected = true;
			selectedIDs.clear();
			selectedIDs.insert(obj.id);
		}
		else {
			if(obj !is null) {
				obj.selected = true;
				selection.length = 1;
				@selection[0] = obj;
				selectedIDs.clear();
				selectedIDs.insert(obj.id);
			}
			else {
				selection.length = 0;
				selectedIDs.clear();
			}
		}
	}
	else {
		if(ctrlKey) {
			if(!selectedIDs.contains(obj.id)) {
				obj.selected = true;
				selection.insertLast(obj);
				selectedIDs.insert(obj.id);
			}
		}
		else {
			if(obj !is null && !selectedIDs.contains(obj.id)) {
				obj.selected = true;
				selection.insertLast(obj);
				selectedIDs.insert(obj.id);
			}
		}
	}
	updateBeams();
}

int getSelectionScale() {
	int scale = 0;
	for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
		Ship@ ship = cast<Ship>(selection[i]);
		if(ship is null)
			continue;
		int shipScale = ship.blueprint.design.size;
		scale += shipScale;
	}
	return scale;
}

vec3d getSelectionPosition(bool onlyMovable = false) {
	vec3d pos;
	uint j = 0;
	for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
		Object@ obj = selection[i];
		if(onlyMovable) {
			if(!obj.hasMover || !obj.owner.controlled)
				continue;
		}
		pos += selection[i].position;
		++j;
	}
	if(j != 0)
		pos /= j;
	return pos;
}

Object@ pressedObject;
double pressedTime;

void selectionClick(uint button, bool pressed) {
	Object@ Hovered = hoveredObject;
	bool doubleClicked = false;
	
	//Send clicks to the tab
	if(!pressed) {
		//Check for double clicks
		if(button == 0 && Hovered !is null) {
			sound::objselect.play(priority=true);
			double now = frameTime;
			if(pressedObject is Hovered) {
				if(pressedTime > now - DOUBLECLICK_TIME)  {
					doubleClicked = true;
					@pressedObject = null;
				}
			}
			else {
				@pressedObject = Hovered;
			}
			pressedTime = now;
		}

		//Check for pings
		if(altKey && activeCamera !is null && button == 0) {
			vec3d pingPos;
			if(Hovered !is null)
				pingPos = Hovered.node_position;
			else
				pingPos = activeCamera.screenToPoint(mousePos);
			uint pingType = 0;
			if(ctrlKey)
				pingType = 1;
			if(shiftKey)
				sendPingAll(pingPos, pingType);
			else
				sendPingAllied(pingPos, pingType);
			return;
		}

		Tab@ activeTab = ActiveTab;
		if(activeTab !is null && Hovered !is null)
			if(activeTab.objectInteraction(Hovered, button, doubleClicked))
				return;

		//Actual object selection
		if(button == 0) {
			if(Hovered !is null || !(ctrlKey || shiftKey)) {
				if(ctrlKey)
					toggleObjectSelect(Hovered);
				else
					selectObject(Hovered, shiftKey);
			}
		}
	}
	//Go into movement targeting mode
	else if(button == 1 && Hovered is null) {
		if(selection.length != 0) {
			bool hasMovement = false;
			for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
				Object@ obj = selection[i];
				if(canMove(obj)) {
					hasMovement = true;
					break;
				}
			}

			if(hasMovement)
				targetMovement();
		}
	}
}

enum SelectionType {
ST_Military,
ST_Civilian,
ST_Fleets,
ST_Planets,
ST_Other
};

SelectionType classifyRestrictive(array<Object@>& objs) {
	uint type = ST_Other;

	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		Object@ obj = objs[i];
		if(!obj.owner.controlled)
			continue;
		
		uint newType = ST_Other;
		switch(obj.type) {
			case OT_Ship:
				//Nothing overrides ship selection
				if(obj.hasLeaderAI) {
					if(obj.getFleetStrength() < 1000.0)
						newType = ST_Civilian;
					else
						newType = ST_Military;
				}
			break;
			case OT_Planet:
				newType = ST_Planets;
				break;
		}

		if(newType < type)
			type = newType;
	}
	
	return SelectionType(type);
}

SelectionType classifyRelaxed(array<Object@>& objs) {
	SelectionType type = ST_Fleets;

	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		Object@ obj = objs[i];
		if(!obj.owner.controlled)
			return ST_Other;
		
		switch(obj.type) {
			case OT_Ship:
				//Nothing overrides ship selection
				if(!obj.hasLeaderAI)
					return ST_Other;
				break;
			case OT_Planet:
				if(type == ST_Fleets)
					type = ST_Planets;
				break;
			default:
				return ST_Other;
		}
	}
	
	return type;
}

void filter(array<Object@>& objs, SelectionType type) {
	if(type == ST_Other)
		return;

	array<Object@> output;
	
	switch(type) {
		case ST_Fleets:
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			Object@ obj = objs[i];
			if(!obj.owner.controlled || !obj.isShip || !obj.hasLeaderAI)
				continue;
			output.insertLast(obj);
		}
		break;
		case ST_Civilian:
		case ST_Military:
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			Object@ obj = objs[i];
			if(!obj.owner.controlled || !obj.isShip || !obj.hasLeaderAI)
				continue;
			if((obj.getFleetStrength() < 1000.0) != (type == ST_Civilian))
				continue;
			output.insertLast(obj);
		}
		break;
		case ST_Planets:
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			Object@ obj = objs[i];
			if(!obj.owner.controlled || !obj.isPlanet)
				continue;
			output.insertLast(obj);
		}
		break;
	}
	
	objs = output;
}


void dragSelect(const recti& box) {
	array<Object@> objects = activeCamera.camera.boxSelect(box);
	
	SelectionType selType;
	
	//If we're adding to our current selection, filter by the current selection type
	if(shiftKey)
		selType = classifyRelaxed(selection);
	else
		selType = classifyRestrictive(objects);
	
	filter(objects, selType);
	
	if(!shiftKey)
		clearSelection();
	for(uint i = 0, cnt = objects.length; i < cnt; ++i)
		addToSelection(objects[i]);
	
	updateBeams();
}

/*double getObjectMaxSelectionDistance(Object& obj) {
	switch(obj.type) {
		case OT_Ship:
			if(obj.hasLeaderAI)
				return INFINITY;
			else
				return 300.0 * obj.radius;
		case OT_Planet:
			return 16000.0;
		case OT_Orbital:
			return 16000.0;
		case OT_Asteroid:
		case OT_Anomaly:
		case OT_Pickup:
			return 16000.0;
		case OT_ColonyShip:
			return 2000.0;
		case OT_Star:
			return INFINITY;
	}
	return 16000.0;
}*/

const double MAX_SUPPORT_SELECT_DIST = 1000.0;
const double MAX_PLANET_SELECT_DIST = 52000.0;
const double MAX_PLANET_PHYS_SEL_DIST = 2000.0;
const double MAX_ORBITAL_SELECT_DIST = 52000.0;
const double MAX_PICKUP_SELECT_DIST = 20000.0;
const double MAX_COLSHIP_SELECT_DIST = 12000.0;
const double MAX_CIVILIAN_SELECT_DIST = 1500.0;

array<Node@> nodes, bestNodes;

void updateHoveredObject() {
	//double start = getExactTime();
	lastMousePos = mousePos;
	@lastHoverFilter = hoverFilter;

	//Outside of the screen, nothing to do
	if(lastMousePos.x < 0 || lastMousePos.y < 0 || lastMousePos.x > screenSize.x || lastMousePos.y > screenSize.y
		|| isGuiHovered()) {
		@hovered = null;
	}
	else if(activeCamera !is null) {
		line3dd line = activeCamera.screenToRay(lastMousePos);
		nodeConeSelect(line, HOVER_CONE_SLOPE, nodes);

		//Find best node
		Node@ best = null;
		double bestScore = 0;
		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			Node@ cur = nodes[i];
			Object@ obj = cur.object;
			if(obj is null)
				continue;
			
			double dist = cur.position.distanceTo(line.start) * config::GFX_DISTANCE_MOD;
			double score = 1.0 / dist;
			Empire@ owner = obj.owner;

			if(hoverFilter is null) {
				if(obj.selected)
					score /= 10.0;
				else if(owner.controlled)
					score *= 1.5;
			}
			else {
				if(!hoverFilter(obj))
					score /= 10.0;
			}
			
			switch(obj.type) {
				case OT_Ship:
					if(!obj.hasLeaderAI) {
						if(dist > MAX_SUPPORT_SELECT_DIST)
							continue;
						score /= 4.0;
					}
					if(owner !is null && !owner.major)
						score /= 10.0;
					break;
				case OT_Planet:
					if(dist > MAX_PLANET_SELECT_DIST)
						continue;
					//Ignore physical planets at great distances, the player will be selecting the icon instead
					if(dist > MAX_PLANET_PHYS_SEL_DIST / 10.0 * obj.radius && cast<PlanetIconNode>(cur) is null)
						continue;
					break;
				case OT_Orbital:
					if(dist > MAX_ORBITAL_SELECT_DIST)
						continue;
					score /= 2.0;
					break;
				case OT_Anomaly:
				case OT_Asteroid:
					score /= 3.0;
					break;
				case OT_Pickup:
					break;
				case OT_ColonyShip:
					if(dist > MAX_COLSHIP_SELECT_DIST)
						continue;
					score /= 20.0;
					break;
				case OT_Civilian:
					if(dist > MAX_CIVILIAN_SELECT_DIST * obj.radius)
						continue;
					score /= 5.0;
					break;
				case OT_Star:
				default:
					score /= 6.0;
					break;
			}
			
			if(score * 4.0 < bestScore)
				continue;
			
			score /= cur.position.distanceTo(line.getClosestPoint(cur.position, true));
			if(score < bestScore)
				continue;
			
			@best = cur;
			bestScore = score;
		}

		//Set hover
		if(best !is null)
			@hovered = best.object;
		else
			@hovered = null;

		//Update beam shown for hovered objects
		updateHoverBeams();
		
		bestNodes.length = 0;
		nodes.length = 0;
	}
	
	//double end = getExactTime();
	//error("Hovered update took " + int((end - start) * 1000.0) + "ms");
}

void clearHoveredObject() {
	@hovered = null;
}

class DebugCursorCommand : ConsoleCommand {
	void execute(const string& args) {
		debugCursor = args.length == 0 || toBool(args);
	}
};

void pinObj(bool pressed) {
	if(!pressed) {
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(obj !is null)
				pinObject(ActiveTab, obj, false);
		}
	}
}

void pinObjFloat(bool pressed) {
	if(!pressed) {
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(obj !is null)
				pinObject(ActiveTab, obj, true);
		}
	}
}

void holdPosition(bool pressed) {
	if(!pressed) {
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(obj.hasLeaderAI)
				obj.setHoldPosition(!shiftKey);
		}
	}
}

void group_key(bool pressed, uint groupIndex) {
	if(!pressed)
		return;
	
	array<Object@>@ group = groups[groupIndex];
	if(ctrlKey && shiftKey) {
		//Add current selection to group
		if(selection.length == 0)
			return;
	
		set_int groupObjs;
		for(uint i = 0, cnt = group.length; i < cnt; ++i)
			groupObjs.insert(group[i].id);
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			Object@ obj = selection[i];
			if(groupObjs.contains(obj.id))
				continue;
			group.insertLast(obj);
			groupObjs.insert(obj.id);
		}
		
		sound::objselect.play(priority=true);
	}
	else if(shiftKey) {
		//Add group to selection
		for(uint i = 0, cnt = group.length; i < cnt; ++i)
			addToSelection(group[i]);
		
		if(group.length != 0)
			sound::objselect.play(priority=true);
	}
	else if(ctrlKey) {
		//Set group to selection
		if(selection.length != 0) {
			group = selection;
			sound::objselect.play(priority=true);
		}
	}
	else {
		//Switch to selection
		// If the group is already (fully) selected, instead move the camera to that group
		bool sameGroup = false;
		if(selection.length == group.length) {
			sameGroup = true;
			for(uint i = 0, cnt = group.length; i < cnt; ++i) {
				if(!isSelected(group[i])) {
					sameGroup = false;
					break;
				}
			}
		}
		
		if(sameGroup) {
			if(selection.length != 0)
				zoomTabTo(selection[0]);
		}
		else {
			clearSelection();
			for(uint i = 0, cnt = group.length; i < cnt; ++i)
				addToSelection(group[i]);
			sound::objselect.play(priority=true);
		}
	}
}

void group_1(bool pressed) { group_key(pressed, 0); }
void group_2(bool pressed) { group_key(pressed, 1); }
void group_3(bool pressed) { group_key(pressed, 2); }
void group_4(bool pressed) { group_key(pressed, 3); }
void group_5(bool pressed) { group_key(pressed, 4); }
void group_6(bool pressed) { group_key(pressed, 5); }
void group_7(bool pressed) { group_key(pressed, 6); }
void group_8(bool pressed) { group_key(pressed, 7); }
void group_9(bool pressed) { group_key(pressed, 8); }

bool SHOW_FIREARCS = false;
void toggleFireArcs(bool pressed) {
	if(!pressed)
		SHOW_FIREARCS = !SHOW_FIREARCS;
}

void manage_obj(bool pressed) {
	if(!pressed) {
		if(selectedObject !is null)
			openOverlay(selectedObject);
		else if(hoveredObject !is null)
			openOverlay(hoveredObject);
	}
}

void manage_support(bool pressed) {
	if(!pressed) {
		if(selectedObject !is null)
			openSupportOverlay(selectedObject);
		else if(hoveredObject !is null)
			openSupportOverlay(hoveredObject);
	}
}

void init() {
	addConsoleCommand("debug_cursor", DebugCursorCommand());
	keybinds::Global.addBind(KB_MANAGE, "manage_obj");
	keybinds::Global.addBind(KB_MANAGE_SUPPORT, "manage_support");
	keybinds::Global.addBind(KB_PIN, "pinObj");
	keybinds::Global.addBind(KB_HOLD_POSITION, "holdPosition");
	keybinds::Global.addBind(KB_PIN_FLOATING, "pinObjFloat");
	keybinds::Global.addBind(KB_TOGGLE_FIREARCS, "toggleFireArcs");
	hoverBeams.isHover = true;
	
	keybinds::Global.addBind(KB_GROUP_1, "group_1");
	keybinds::Global.addBind(KB_GROUP_2, "group_2");
	keybinds::Global.addBind(KB_GROUP_3, "group_3");
	keybinds::Global.addBind(KB_GROUP_4, "group_4");
	keybinds::Global.addBind(KB_GROUP_5, "group_5");
	keybinds::Global.addBind(KB_GROUP_6, "group_6");
	keybinds::Global.addBind(KB_GROUP_7, "group_7");
	keybinds::Global.addBind(KB_GROUP_8, "group_8");
	keybinds::Global.addBind(KB_GROUP_9, "group_9");

	keybinds::Global.addBind(KB_PING, "ping_allied");
	keybinds::Global.addBind(KB_PING_ALL, "ping_all");
}

void ping_allied(bool pressed) {
	if(pressed)
		return;

	vec3d pingPos;
	if(hoveredObject !is null)
		pingPos = hoveredObject.node_position;
	else if(activeCamera !is null)
		pingPos = activeCamera.screenToPoint(mousePos);
	else
		return;

	uint pingType = 0;
	if(ctrlKey)
		pingType = 1;

	sendPingAllied(pingPos, pingType);
}

void ping_all(bool pressed) {
	if(pressed)
		return;

	vec3d pingPos;
	if(hoveredObject !is null)
		pingPos = hoveredObject.node_position;
	else if(activeCamera !is null)
		pingPos = activeCamera.screenToPoint(mousePos);
	else
		return;

	uint pingType = 0;
	if(ctrlKey)
		pingType = 1;

	sendPingAll(pingPos, pingType);
}

const Color MOVE_BEAM_COLOR(0x00ff00ff);
const Color RALLY_BEAM_COLOR(0x00ffaaff);
const Color FTL_BEAM_COLOR(0x00c0ffff);
const Color HEIGHT_BEAM_COLOR(0xaaaaaaff);
const Color IMPORT_BEAM_COLOR(0x0000ffff);
const Color EXPORT_BEAM_COLOR(0x76e0e0ff);
const Color QUEUED_EXPORT_BEAM_COLOR(0xffe400ff);
const Color QUEUED_IMPORT_BEAM_COLOR(0xffe400ff);
const Color LINK_BEAM_COLOR(0xff00bbff);
const Color PROJECT_BEAM_COLOR(0xdcc35fff);
const Color TRADE_LINK_BEAM_COLOR(0x888888ff);

const Color DISABLED_BEAM_COLOR(0xff0000ff);
const Color DISABLED_BEAM_COLOR2(0xff9000ff);

vec3d strategicPosition(Object& obj) {
	if(obj.isPlanet)
		return obj.planetIconPosition;
	if(obj.isAsteroid)
		return cast<Asteroid>(obj).strategicIconPosition;
	if(obj.isOddity)
		return cast<Oddity>(obj).strategicIconPosition;
	if(obj.isOrbital)
		return cast<Orbital>(obj).strategicIconPosition;
	return obj.node_position;
}

class BEAMS {
	BeamNode@ heightBeam;
	BeamNode@ linkBeam;
	BeamNode@ projectBeam;
	BeamNode@ rallyBeam;
	array<BeamNode@> moveBeams;
	array<BeamNode@> resourceBeams;
	array<PlaneNode@> ranges;
	bool primary = false;
	bool isHover = false;

	Object@ cacheObj;
	array<OrbitalSection>@ sectionCache;
	double sectCacheTime = -INFINITY;
	array<const BuildingType@>@ bldCache;
	double bldCacheTime = -INFINITY;

	BeamNode@ makeBeam(const Color& color) {
		BeamNode@ beam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		beam.visible = false;
		beam.color = color;
		return beam;
	}

	void updateBeam(BeamNode@& node, const vec3d& from, const vec3d& to,
			const Color& color) {
		BeamNode@ check = node;
		if(check is null) {
			@check = makeBeam(color);
			@node = check;
		}
		check.position = from;
		check.rebuildTransform();
		check.endPosition = to;
		check.color = color;
		check.visible = true;
	}

	void hideBeam(BeamNode@& node) {
		BeamNode@ check = node;
		if(check !is null) {
			check.visible = false;
			check.markForDeletion();
			@node = null;
		}
	}

	PlaneNode@ makePlane(const Color& color, const Material@ mat = material::RangeCircle) {
		PlaneNode@ plane = PlaneNode(mat, 0.0);
		plane.visible = false;
		plane.color = color;
		return plane;
	}

	void updatePlane(PlaneNode@& node, const vec3d& pos, double size,
			const Color& color, const Material@ mat = material::RangeCircle) {
		PlaneNode@ check = node;
		if(check is null) {
			@check = makePlane(color, mat);
			@node = check;
		}
		check.position = pos;
		check.scale = size;
		check.rebuildTransform();
		check.color = color;
		@check.material = mat;
		check.visible = true;
	}

	void hidePlane(PlaneNode@& node) {
		PlaneNode@ check = node;
		if(check !is null) {
			check.visible = false;
			check.markForDeletion();
			@node = null;
		}
	}

	void remove() {
		if(heightBeam !is null)
			heightBeam.markForDeletion();
		if(linkBeam !is null)
			linkBeam.markForDeletion();
		if(projectBeam !is null)
			projectBeam.markForDeletion();
		if(rallyBeam !is null)
			rallyBeam.markForDeletion();
		for(uint i = 0, cnt = resourceBeams.length; i < cnt; ++i)
			if(resourceBeams[i] !is null)
				resourceBeams[i].markForDeletion();
		for(uint i = 0, cnt = moveBeams.length; i < cnt; ++i)
			if(moveBeams[i] !is null)
				moveBeams[i].markForDeletion();
		for(uint i = 0, cnt = ranges.length; i < cnt; ++i)
			if(ranges[i] !is null)
				ranges[i].markForDeletion();
	}

	void hideAll() {
		hideBeam(heightBeam);
		hideBeam(linkBeam);
		hideBeam(projectBeam);
		hideBeam(rallyBeam);
		for(uint i = 0, cnt = resourceBeams.length; i < cnt; ++i)
			hideBeam(resourceBeams[i]);
		resourceBeams.length = 0;
		for(uint i = 0, cnt = moveBeams.length; i < cnt; ++i)
			hideBeam(moveBeams[i]);
		moveBeams.length = 0;
		for(uint i = 0, cnt = ranges.length; i < cnt; ++i)
			hidePlane(ranges[i]);
		ranges.length = 0;
	}

	void addBeam(array<BeamNode@>& beams, uint& index, const vec3d& from, const vec3d& to,
				const Color& color) {
		if(beams.length <= index) {
			BeamNode@ node;
			updateBeam(node, from, to, color);
			beams.insertLast(node);
		}
		else {
			updateBeam(beams[index], from, to, color);
		}
		index += 1;
	}

	void truncateBeams(array<BeamNode@>& beams, uint index) {
		uint cnt = beams.length;
		for(uint i = index; i < cnt; ++i)
			hideBeam(beams[i]);
		beams.length = index;
	}

	PlaneNode@ addPlane(array<PlaneNode@>& planes, uint& index, const vec3d& pos, double size,
				const Color& color, const Material@ mat = material::RangeCircle) {
		if(planes.length <= index) {
			PlaneNode@ node;
			updatePlane(node, pos, size, color, mat);
			planes.insertLast(node);
			index += 1;
			return node;
		}
		else {
			updatePlane(planes[index], pos, size, color, mat);
			index += 1;
			return planes[index-1];
		}
	}

	void truncatePlanes(array<PlaneNode@>& planes, uint index) {
		uint cnt = planes.length;
		for(uint i = index; i < cnt; ++i)
			hidePlane(planes[i]);
		planes.length = index;
	}

	void setWeaponArc(PlaneNode@ node, Object@ obj, const Effector@ efftr) {
		if(efftr !is null && efftr.fireArc < pi) {
			vec3d offset = obj.node_rotation * efftr.turretAngle;
			double rad = vec2d(offset.x, offset.z).radians();
			node.minRad = rad - efftr.fireArc;
			node.maxRad = rad + efftr.fireArc;
		}
		else {
			node.minRad = -pi;
			node.maxRad = +pi;
		}
	}

	void addWeapon(array<PlaneNode@>& planes, uint& index, Object@ obj, Hook@ hook, bool showWeapons = true) {
		auto@ shows = cast<ShowsRange>(hook);
		if(shows !is null) {
			double range = 0;
			Color color;
			if(shows.getShowRange(obj, range, color)) {
				auto@ node = addPlane(planes, index, obj.node_position, range, color);
				setWeaponArc(node, obj, null);
			}
			return;
		}
		if(!showWeapons)
			return;
		AddTurret@ turr;
		@turr = cast<AddTurret>(hook);
		if(turr is null) {
			auto@ ifh = cast<IfHook>(hook);
			if(ifh !is null)
				@hook = ifh.hook;
			auto@ rep = cast<GenericRepeatHook>(hook);
			if(rep !is null)
				@turr = cast<AddTurret>(rep.hook);
		}
		if(turr is null)
			return;

		auto@ node = addPlane(planes, index, obj.node_position,
			turr.range, turr.def.trailStart);
		setWeaponArc(node, obj, null);
	}

	void update(Object@ obj) {
		//Deal with not displaying any object
		if(obj is null) {
			hideAll();
			return;
		}

		//Update movement beams
		uint movInd = 0;
		if(obj.owner.controlled) {
			vec3d atPos = obj.node_position;
			uint ordCnt = 0;
			bool wasPath = false;
			if(obj.hasLeaderAI && obj.hasOrders)
				ordCnt = obj.orderCount;
			if(obj.hasMover) {
				if(obj.isMoving) {
					if(obj.hasMovePath) {
						DataList@ objs = obj.getMovePath();
						Object@ current;
						bool wasEven = obj.inFTL;
						while(receive(objs, current)) {
							if(current !is null) {
								vec3d dest = strategicPosition(current);
								addBeam(moveBeams, movInd,
										atPos, dest,
										wasEven ? FTL_BEAM_COLOR : MOVE_BEAM_COLOR);
								atPos = dest;
								wasPath = true;
								wasEven = !wasEven;
							}
						}
					}
					if(wasPath || ordCnt == 0) {
						vec3d dest = obj.moveDestination;
						addBeam(moveBeams, movInd,
								atPos, dest,
								MOVE_BEAM_COLOR);
						atPos = dest;
					}
				}
			}
			if(obj.hasLeaderAI) {
				for(uint i = wasPath ? 1 : 0; i < ordCnt; ++i) {
					if(obj.orderHasMovement[i]) {
						vec3d dest = obj.orderMoveDestination[i];
						uint type = obj.orderType[i];
						bool isFTL = isFTLOrder(type);

						addBeam(moveBeams, movInd,
								atPos, dest,
								isFTL ? FTL_BEAM_COLOR : MOVE_BEAM_COLOR);
						atPos = dest;
					}
				}
			}
		}
		truncateBeams(moveBeams, movInd);

		//Update height beam
		Region@ region = obj.region;
		vec3d myPos = strategicPosition(obj);
		double myY = obj.position.y;
		double regionY;
		if(region !is null)
			regionY = region.position.y;
		else
			regionY = myY;
		uint rangeInd = 0;
		bool showWeapons = (altKey || SHOW_FIREARCS) && (!isHover || !obj.selected);

		bool hasHeight = obj.region !is null && abs(myY - regionY) >= 1.0;
		if(hasHeight) {
			vec3d from = obj.node_position;
			vec3d to = from;
			to.y = regionY;

			updateBeam(heightBeam, from, to,
				HEIGHT_BEAM_COLOR);
		}
		else {
			hideBeam(heightBeam);
		}

		//Update link beam
		Object@ link;
		if(obj.isAsteroid) {
			Asteroid@ roid = cast<Asteroid>(obj);
			@link = roid.origin;
		}
		else if(obj.isOddity) {
			@link = cast<Oddity>(obj).getLink();
		}

		if(link !is null && (link.visible || link.known)) {
			vec3d linkPos = strategicPosition(link);
			updateBeam(linkBeam, myPos, linkPos,
				LINK_BEAM_COLOR);
		}
		else {
			hideBeam(linkBeam);
		}

		//Update project beam
		Object@ project;
		if(project !is null)
			updateBeam(projectBeam, myPos, project.position, PROJECT_BEAM_COLOR);
		else
			hideBeam(projectBeam);
		
		if(obj.hasConstruction && obj.owner.controlled && obj.isRallying)
			updateBeam(rallyBeam, myPos, obj.rallyPosition, RALLY_BEAM_COLOR);
		else
			hideBeam(rallyBeam);

		if(obj.isStar) {
			//Update trade link beams
			uint tradeInd = 0;
			Region@ reg = obj.region;
			if(reg !is null) {
				SystemDesc@ origin = getSystem(reg);
				Empire@ originPrimary = origin.object.visiblePrimaryEmpire;
				for(uint i = 0, cnt = origin.adjacent.length; i < cnt; ++i) {
					SystemDesc@ other = getSystem(origin.adjacent[i]);
					if(playerEmpire !is null && playerEmpire.valid && other.object.ExploredMask & playerEmpire.visionMask == 0)
						continue;

					Empire@ otherPrimary = other.object.visiblePrimaryEmpire;

					Color col = TRADE_LINK_BEAM_COLOR;
					if(originPrimary !is null && originPrimary is otherPrimary && otherPrimary.valid)
						col = originPrimary.color;
					col.a = 0x80;
					
					vec3d offset = origin.position - other.position;
					offset.y = 0.0;
					offset.normalize();

					addBeam(resourceBeams, tradeInd, origin.position - offset * origin.radius,
							other.position + offset * other.radius, col);
				}
			}
			truncateBeams(resourceBeams, tradeInd);
		}
		else {
			//Update resource beams
			uint resInd = 0;
			if(obj.hasResources) {
				array<Resource> resources;
				resources.syncFrom(obj.getNativeResources());
				
				uint nativeCnt = obj.nativeResourceCount;
				
				for(uint i = 0; i < resources.length; ++i) {
					auto@ res = resources[i];
					if(res.origin !is obj)
						continue;
				
					Object@ dest = res.exportedTo;
					if(dest is null)
						@dest = obj.nativeResourceDestination[i];
					if(dest is null || dest is obj)
						continue;
					if(dest is hovered || dest.selected)
						continue;

					vec3d theirPos = strategicPosition(dest);

					Color color = EXPORT_BEAM_COLOR;
					if(obj.owner !is playerEmpire || dest.owner !is playerEmpire)
						color = QUEUED_EXPORT_BEAM_COLOR;
					else if(!res.usable)
						color = GlowBeamColor;

					addBeam(resourceBeams, resInd,
						myPos, theirPos, color);
				}

				if(obj.owner.controlled) {
					resources.syncFrom(obj.getAvailableResources());
					for(uint i = 0; i < resources.length; ++i) {
						auto@ res = resources[i];
						Object@ origin = res.origin;
						if(origin is null || origin is obj)
							continue;

						vec3d theirPos = strategicPosition(origin);

						Color color = IMPORT_BEAM_COLOR;
						if(!res.usable)
							color = GlowBeamColor;

						addBeam(resourceBeams, resInd,
							theirPos, myPos,
							color);

						if(showWeapons) {
							auto@ type = res.type;
							if(type !is null) {
								for(uint j = 0, jcnt = type.hooks.length; j < jcnt; ++j)
									addWeapon(ranges, rangeInd, obj, cast<Hook>(type.hooks[j]));
							}
						}
					}
				}

				if(obj.queuedImportCount > 0) {
					resources.syncFrom(obj.getQueuedImports());
					for(uint i = 0; i < resources.length; ++i) {
						auto@ res = resources[i];
						Object@ origin = res.origin;
						if(origin is null || origin is obj)
							continue;

						vec3d theirPos = strategicPosition(origin);

						addBeam(resourceBeams, resInd,
							theirPos, myPos,
							QUEUED_IMPORT_BEAM_COLOR);
					}
				}
			}
			truncateBeams(resourceBeams, resInd);
		}

		//Weapon ranges
		if(!isHover || !obj.selected) {
			if(showWeapons && obj.isShip) {
				Ship@ ship = cast<Ship>(obj);
				auto@ bp = ship.blueprint;
				if(bp is null)
					return;
				auto@ dsg = bp.design;
				if(dsg is null)
					return;
				uint resInd = 0;
				for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
					auto@ ss = dsg.subsystems[i];
					if(ss.has(SV_Range)) {
						auto@ node = addPlane(ranges, rangeInd, obj.node_position,
							ss[SV_Range], ss.type.typeColor);

						if(ss.effectorCount > 0) {
							auto@ efftr = ss.effectors[0];
							setWeaponArc(node, obj, ss.effectors[0]);
						}
						else {
							setWeaponArc(node, obj, null);
						}
					}

				}
			}
			if(obj.isOrbital) {
				auto@ type = getOrbitalModule("FlingCore");
				if(type !is null && cast<Orbital>(obj).coreModule == type.id) {
					addPlane(ranges, rangeInd, obj.node_position,
						FLING_BEACON_RANGE, Color(0x2bff0cff));
				}
				if(cacheObj !is obj || sectionCache is null || sectCacheTime < frameTime - 3.0) {
					if(sectionCache is null)
						@sectionCache = array<OrbitalSection>();
					sectionCache.syncFrom(cast<Orbital>(obj).getSections());
					sectCacheTime = frameTime;
					@cacheObj = obj;
				}
				for(uint i = 0, cnt = sectionCache.length; i < cnt; ++i) {
					auto@ sect = sectionCache[i];
					for(uint j = 0, jcnt = sect.type.hooks.length; j < jcnt; ++j)
						addWeapon(ranges, rangeInd, obj, cast<Hook>(sect.type.hooks[j]), showWeapons);
				}
			}
			if(obj.isShip) {
				Ship@ ship = cast<Ship>(obj);
				auto@ bp = ship.blueprint;
				if(bp !is null) {
					auto@ dsg = bp.design;
					if(dsg !is null) {
						if(dsg.hasTag(ST_Slipstream)) {
							addPlane(ranges, rangeInd, obj.node_position,
								dsg.average(SV_SlipstreamOptimalDistance), Color(0x67a7ad));
						}
					}
				}
			}
			if(showWeapons && obj.isPlanet && obj.getBuildingCount() > 0) {
				if(cacheObj !is obj || bldCache is null || bldCacheTime < frameTime - 2.9) {
					if(bldCache is null)
						@bldCache = array<const BuildingType@>();
					bldCacheTime = frameTime;
					@cacheObj = obj;
					uint cnt = obj.getBuildingCount();
					bldCache.length = 0;
					bldCache.reserve(cnt);
					for(uint i = 0, cnt = obj.getBuildingCount(); i < cnt; ++i) {
						auto@ type = getBuildingType(obj.buildingType[i]);
						if(type !is null)
							bldCache.insertLast(type);
					}
				}
				for(uint i = 0, cnt = bldCache.length; i < cnt; ++i) {
					auto@ type = bldCache[i];
					for(uint j = 0, jcnt = type.hooks.length; j < jcnt; ++j)
						addWeapon(ranges, rangeInd, obj, cast<Hook>(type.hooks[j]), showWeapons);
				}
			}
		}
		truncatePlanes(ranges, rangeInd);
	}
};

array<BEAMS@> selectedBeams;
BEAMS hoverBeams;

void updateHoverBeams() {
	hoverBeams.update(hovered);
}

void updateBeams() {
	uint oldCnt = selectedBeams.length;
	uint cnt = selection.length;

	for(uint i = cnt; i < oldCnt; ++i)
		selectedBeams[i].remove();

	selectedBeams.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		if(selectedBeams[i] is null)
			@selectedBeams[i] = BEAMS();
		selectedBeams[i].primary = i == 0;
		selectedBeams[i].update(selection[i]);
	}
}

Color GlowBeamColor;
void tick(double time) {
	float pct = abs((frameTime % 1.0) - 0.5f) * 2.f;
	GlowBeamColor = DISABLED_BEAM_COLOR.interpolate(DISABLED_BEAM_COLOR2, pct);

	updateBeams();
	updateHoverBeams();
	for(int i = selection.length - 1; i >= 0; --i) {
		if(!selection[i].valid)
			selection.removeAt(i);
	}
}

void render(double time) {
	if(debugCursor) {
		vec3d mpos;
		if(getElevationIntersect(activeCamera.screenToRay(mousePos), mpos)) {
			double size = activeCamera.distance / 80.0;
			renderBillboard(material::PlanetImage, mpos, size);
			mpos.y = getElevation(mpos.x, mpos.z);
			renderBillboard(material::SmallLogo, mpos, size);
		}
	}
}

void save(SaveFile& file) {
	for(uint i = 0; i < 9; ++i) {
		uint cnt = groups[i].length;
		file << cnt;
		for(uint j = 0; j < cnt; ++j)
			file << groups[i][j];
	}
}

void load(SaveFile& file) {
	for(uint i = 0; i < 9; ++i) {
		uint cnt = 0;
		file >> cnt;
		groups[i].length = cnt;
		for(uint j = 0; j < cnt; ++j)
			file >> groups[i][j];
	}
}
