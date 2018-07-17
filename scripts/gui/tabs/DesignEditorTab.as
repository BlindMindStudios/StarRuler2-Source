import tabs.Tab;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiDropdown;
import elements.GuiSkinElement;
import elements.GuiBlueprint;
import elements.GuiButton;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.GuiAccordion;
import elements.GuiProgressbar;
import elements.MarkupTooltip;
from elements.GuiBlueprint import HEX_SIZE, SysDrawMode;
from dialogs.DesignExportDialog import exportDesign;
import dialogs.InputDialog;
import resources;
import design_stats;
import util.design_export;
import util.design_designer;
import icons;
import heralds_icons;
import designs;
import design_settings;
from traits import getTraitID;

import Tab@ createDesignOverviewTab() from "tabs.DesignOverviewTab";
import const Design@ createRandomDesign(uint type, int size, Empire@ emp) from "util.random_designs";
from tabs.tabbar import browseTab, popTab, ActiveTab;

const double TURRET_TICK_ROTATION = twopi / 36.0;

Color warningColor(0xca4b06ff);
Color errorColor(0xff0000ff);

const int HEAD_XOFF = 12;
const int STAT_XOFF = 12;
const int STAT_COLLAPSE = 0;
const int FILTER_WIDTH = 80;
int buttonHeight = 60;
bool SHOW_ARC_UNDERLAY = false;
bool SHOW_HULL_UNDERLAY = false;
bool SHOW_HULL_WEIGHTS = false;
enum ButtonMask {
	B_LEFT = 1,
	B_RIGHT = 2,
	B_MIDDLE = 4,
}

/** Subsystem list element {{{*/
class SubsystemSelector : BaseGuiElement {
	Construction@ cons;
	int[] subsystems;
	int[] modules;
	int hovered = -1;
	string category;
	array<GuiButton@> applyButtons;

	SubsystemSelector(Construction@ cons, const string& cat) {
		@this.cons = cons;
		super(cons.syslist, recti());
		category = cat;
		updateAbsolutePosition();
		visible = false;
	}

	void remove() {
		@cons = null;
		BaseGuiElement::remove();
	}

	bool contains(const SubsystemDef@ def) {
		if(modules.length > 0)
			return false;
		return subsystems.find(def.index) != -1;
	}

	bool contains(const ModuleDef@ def) {
		if(modules.length == 0)
			return false;
		for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
			auto@ def = getSubsystemDef(subsystems[i]);
			auto@ mod = def.modules[modules[i]];
			if(mod.id == def.id)
				return true;
		}
		return false;
	}

	string get_tooltip() {
		if(hovered >= 0 && hovered < int(subsystems.length)) {
			const SubsystemDef@ def = getSubsystemDef(subsystems[hovered]);
			string name, description;
			Sprite sprt;
			uint drawMode = 0;
			Color color;

			if(uint(hovered) < modules.length) {
				auto@ mod = def.modules[modules[hovered]];
				sprt = mod.sprite;
				name = mod.name;
				description = mod.description;
				color = mod.color;
				drawMode = mod.drawMode;
			}
			else {
				if(def.coreModule !is null) {
					sprt = def.coreModule.sprite;
					drawMode = def.coreModule.drawMode;
				}
				else {
					sprt = def.defaultModule.sprite;
					drawMode = def.defaultModule.drawMode;
				}
				name = def.name;
				description = def.description;
				color = def.color;
			}

			int isize = sprt.size.width;
			double ifac = double(isize) / 128;
			int off = 42 + (sprt.size.height - 128);
			string img;

			if(drawMode == 0) {
				img = format("[vspace=-$2/][center][img=$1;$3/][/center]",
						getSpriteDesc(sprt), toString(off), toString(isize));
			}
			else if(drawMode == 1) {
				sprt.index += 2;
				img = format("[center][img=$1;$3/][/center]",
						getSpriteDesc(sprt), toString(off), toString(isize/2));
			}
			else if(drawMode == 3) {
				img = format("[center][img=$1;55/][/center]",
						getSpriteDesc(sprt));
			}

			return format("[font=Medium][color=$4]$2[/color][/font]$1$3",
				img, name, description, toString(color));
		}
		return "";
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Mouse_Entered:
				if(event.caller is this)
					hovered = -1;
			break;
			case GUI_Mouse_Left:
				if(!isAncestorOf(event.other))
					hovered = -1;
			break;
		}
		if(cast<GuiButton>(event.caller) !is null) {
			if(event.type == GUI_Clicked) {
				emitConfirmed();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	int getOffsetItem(const vec2i& offset) {
		if(offset.x < 0 || offset.y < 0)
			return -1;
		if(offset.x > AbsolutePosition.width || offset.y > AbsolutePosition.height)
			return -1;
			
		uint row = offset.y / buttonHeight;
		if(row >= subsystems.length())
			return -1;

		return int(row);
	}

	void updateAbsolutePosition() {
		size = vec2i(Parent.absolutePosition.width, subsystems.length * buttonHeight);
		BaseGuiElement::updateAbsolutePosition();
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(isAncestorOf(source)) {
			vec2i mouse = vec2i(event.x, event.y);
			vec2i offset = mouse - AbsolutePosition.topLeft;
			int prevHovered = hovered;
			hovered = getOffsetItem(offset);

			if(prevHovered != hovered && Tooltip !is null)
				Tooltip.update(skin, this);

			if(source is this) {
				switch(event.type) {
					case MET_Button_Down:
						if(hovered != -1)
							return true;
					break;
					case MET_Button_Up:
						if(hovered != -1) {
							emitChange();
							return true;
						}
					break;
				}
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		int w = AbsolutePosition.width, h = buttonHeight;
		vec2i pos = AbsolutePosition.topLeft;

		uint applyInd = 0;

		const Font@ fnt = skin.getFont(FT_Bold);
		uint fntHeight = fnt.getLineHeight();
		for(int i = 0, cnt = subsystems.length(); i < cnt; ++i) {
			vec2i btnPos = pos + vec2i(0, i * buttonHeight);
			setClip(recti_area(btnPos, vec2i(w, h)).clipAgainst(AbsoluteClipRect));
			const SubsystemDef@ def = getSubsystemDef(subsystems[i]);

			string name;
			Sprite picture;
			uint drawMode = 0;
			bool selected = false;
			Color color;

			if(uint(i) >= modules.length) {
				name = def.name;
				color = def.color;
				if(def.coreModule !is null) {
					picture = def.coreModule.sprite;
					drawMode = def.coreModule.drawMode;
				}
				else {
					picture = def.defaultModule.sprite;
					drawMode = def.defaultModule.drawMode;
				}
				selected = cons.activeTool !is cons.moduleTool && cons.paintTool.def is def;
			}
			else {
				auto@ module = def.modules[modules[i]];
				name = module.name;
				color = module.color;
				picture = module.sprite;
				drawMode = module.drawMode;
				selected = cons.activeTool is cons.moduleTool && cons.moduleTool.mod.id == module.id;
			}

			//Figure out draw mode
			uint sprite = 0;
			if(i == hovered)
				sprite = 1;

			if(drawMode == 1)
				picture.index += 2;

			//Draw the background
			spritesheet::SubsystemButton.draw(sprite,
				recti_area(btnPos, vec2i(w, h)), color);

			//Modify size to draw size
			double factor = double(h*0.75) / HEX_SIZE.y;
			vec2i hSize = vec2i(h*0.75, h*0.75);
			vec2i modSize = picture.size;
			modSize.x = double(modSize.x) * factor;
			modSize.y = double(modSize.y) * factor;

			if(drawMode == 1)
				modSize = vec2i(double(h)*1.8, double(h)*1.8/picture.aspect);
			else if(drawMode == 3)
				modSize = vec2i(buttonHeight-5, buttonHeight-5);

			//Offset for floating
			vec2i pos = btnPos + vec2i(4,h*0.25);
			if(modSize.y > hSize.y) {
				if(drawMode == 1)
					pos.y -= (modSize.y - hSize.y) / 2 + 10;
				else
					pos.y -= (modSize.y - hSize.y);
			}
			else
				pos.y -= (modSize.y - hSize.y) / 2;

			picture.draw(recti_area(pos, modSize));

			//Draw glow
			if(!def.isApplied) {
				if(selected) {
					material::SubsystemButtonGlow.draw(
						recti_area(btnPos, vec2i(w, h)), color);
				}
			}
			else {
				GuiButton@ btn;
				if(applyInd >= applyButtons.length) {
					@btn = GuiButton(this, recti());
					applyButtons.insertLast(btn);
				}
				else {
					@btn = applyButtons[applyInd];
				}
				++applyInd;

				btn.rect = recti_area(vec2i(w - 140, (i*buttonHeight)+24), vec2i(140, buttonHeight-24));
				bool curApplied = cons.editor.data.appliedSubsystems.find(def) != -1;
				if(curApplied) {
					btn.text = locale::REMOVE;
					btn.buttonIcon = icons::Remove;
					btn.color = colors::Red;
				}
				else {
					btn.text = locale::APPLY;
					btn.buttonIcon = icons::Add;
					btn.color = colors::Green;
				}
				if(curApplied)
					skin.draw(SS_Glow, SF_Normal, recti_area(btnPos, vec2i(w, h)), color);
				btn.draw();
			}

			//Draw the name
			fnt.draw(recti_area(vec2i(4, 1) + btnPos, vec2i(w-10, 20)),
				name,
				color=color,
				horizAlign=1.0, vertAlign=0.5,
				stroke=Color(0x00000080));

			clearClip();
		}

		for(uint i = applyInd, cnt = applyButtons.length; i < cnt; ++i)
			applyButtons[i].remove();
		applyButtons.length = applyInd;
	}
};
/** }}} */
/** Design data representation {{{*/
final class SubsystemData {
	int sysId;
	vec2u core;
	vec2u[] hexes;
	vec3d direction;

	SubsystemData() {
		direction = vec3d_front();
	}

	const SubsystemDef@ get_def() {
		return getSubsystemDef(sysId);
	}
};

final class HexData {
	int subsystem;
	int module;

	HexData() {
		subsystem = -1;
		module = -1;
	}

	HexData(int sys, int mod) {
		subsystem = sys;
		module = mod;
	}
};

class DesignData {
	const Hull@ hull;
	vec2i gridSize;
	double size;
	array<SubsystemData@> subsystems;
	array<const SubsystemDef@> appliedSubsystems;
	HexData[] hexagons;
	Action@ undoHead;
	Action@ redoHead;
	bool forceHull = false;
	bool posChange = false;

	DesignData() {
	}

	void clear() {
		while(undoHead !is null) {
			auto@ tmp = undoHead;
			@undoHead = undoHead.previous;
			@tmp.previous = null;
			@tmp.next = null;
		}
		while(redoHead !is null) {
			auto@ tmp = redoHead;
			@redoHead = redoHead.previous;
			@tmp.previous = null;
			@tmp.next = null;
		}
		subsystems.length = 0;
		hexagons.length = 0;
		forceHull = false;
	}

	void resize(double shipSize) {
		size = shipSize;
	}

	void gridChange(vec2u newSize) {
		gridSize = vec2i(newSize);
		hexagons.length = gridSize.x * gridSize.y;
		posChange = true;
	}

	void load(const Design@ dsg) {
		//Remove previous data
		clear();
		@hull = dsg.hull;
		size = dsg.size;
		forceHull = dsg.forceHull;

		//Create grid
		gridSize = dsg.hull.gridSize;
		hexagons.length = gridSize.x * gridSize.y;

		//Load subsystems
		subsystems.resize(0);
		appliedSubsystems.resize(0);
		for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
			const Subsystem@ sys = dsg.subsystem(i);
			if(sys.type.isHull)
				continue;
			if(sys.type.isApplied) {
				appliedSubsystems.insertLast(sys.type);
				continue;
			}

			SubsystemData@ data = SubsystemData();
			data.sysId = sys.type.index;
			data.core = sys.core;
			data.direction = sys.direction;

			for(uint j = 0, jcnt = sys.hexCount; j < jcnt; ++j) {
				vec2u pos = sys.hexagon(j);
				data.hexes.insertLast(pos);
				HexData@ hdata = hex[pos];

				hdata.subsystem = i;
				hdata.module = sys.module(j).index;
			}

			subsystems.insertLast(data);
		}
	}

	void save(DesignDescriptor& desc) {
		desc.size = size;
		desc.gridSize = vec2u(gridSize);

		//Add subsystems
		for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
			const SubsystemDef@ def = subsystems[i].def;
			desc.addSystem(def);
			desc.setDirection(subsystems[i].direction);

			for(uint j = 0, jcnt = subsystems[i].hexes.length(); j < jcnt; ++j) {
				vec2u pos = subsystems[i].hexes[j];
				HexData@ hdata = hex[pos];

				desc.addHex(pos, def.modules[hdata.module]);
			}
		}

		//Add applied subsystems
		for(uint i = 0, cnt = appliedSubsystems.length; i < cnt; ++i)
			desc.applySubsystem(appliedSubsystems[i]);
	}

	HexData@ get_hex(const vec2u& pos) {
		return hexagons[pos.x + pos.y * gridSize.width];
	}

	SubsystemData@ get_subsystem(const vec2u& pos) {
		int index = hexagons[pos.x + pos.y * gridSize.width].subsystem;
		if(index == -1)
			return null;
		return subsystems[index];
	}

	void startGroup() {
		act(GroupStart());
	}

	void continueGroup() {
		//Continue the previously ended group
		GroupEnd@ grp = cast<GroupEnd>(undoHead);
		if(grp !is null)
			@undoHead = undoHead.previous;
		else
			grabGroup();
	}

	void grabGroup() {
		//Swap the group and the last action to put
		//it in the undo group
		Action@ act = undoHead;
		startGroup();

		if(act !is null) {
			if(act.previous !is null)
				@act.previous.next = undoHead;

			@undoHead.previous = act.previous;
			@undoHead.next = act;

			@act.previous = undoHead;
			@act.next = null;

			@undoHead = act;
		}
	}

	void endGroup() {
		act(GroupEnd());
	}

	void act(Action@ action) {
		@action.previous = undoHead;
		if(undoHead !is null)
			@undoHead.next = action;
		@undoHead = action;
		@redoHead = null;
		action.act(this);
	}

	void undo() {
		if(undoHead is null)
			return;
		@redoHead = undoHead;
		@undoHead = undoHead.previous;
		redoHead.undo(this);
	}

	void redo() {
		if(redoHead is null)
			return;
		@redoHead.previous = undoHead;
		@undoHead = redoHead;
		@redoHead = redoHead.next;
		undoHead.act(this);
	}

	bool hasTag(int tagId) {
		for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
			if(subsystems[i].def.hasTag(tagId))
				return true;
		}
		for(uint i = 0, cnt = appliedSubsystems.length; i < cnt; ++i) {
			if(appliedSubsystems[i].hasTag(tagId))
				return true;
		}
		return false;
	}
};

void checkConnected(HexGridb& conn, DesignData& data, const vec2u& hex, int sys) {
	if(conn.get(hex))
		return;
	conn.get(hex) = true;

	for(uint i = 0; i < 6; ++i) {
		HexGridAdjacency adj = HexGridAdjacency(i);
		vec2u pos = hex;

		if(conn.advance(pos, adj)) {
			if(data.hex[pos].subsystem == sys) {
				checkConnected(conn, data, pos, sys);
			}
		}
	}
}
/** }}} */
/** Actions {{{*/
class Action {
	Action@ previous;
	Action@ next;

	void act(DesignData@ data) {
	}

	void undo(DesignData@ data) {
	}
};

class GroupStart : Action {
	void act(DesignData@ data) {
		if(next is null)
			return;
		Action@ act = next;
		while(cast<GroupEnd@>(act) is null) {
			act.act(data);
			@act = act.next;
		}
		@data.undoHead = act;
		@data.redoHead = act.next;
	}
};

class GroupEnd : Action {
	void undo(DesignData@ data) {
		Action@ act = previous;
		while(cast<GroupStart@>(act) is null) {
			act.undo(data);
			@act = act.previous;
		}
		@data.redoHead = act;
		@data.undoHead = act.previous;
	}
};

class PaintAction : Action {
	vec2u hex;
	HexData to;

	PaintAction(const vec2u& Hex, const HexData& To) {
		hex = Hex;
		to = To;
	}

	void act(DesignData@ data) {
		data.hex[hex] = to;

		SubsystemData@ sdata = data.subsystems[to.subsystem];
		sdata.hexes.insertLast(hex);

		if(sdata.def.hasCore && to.module == sdata.def.coreModule.index)
			sdata.core = hex;
	}

	void undo(DesignData@ data) {
		data.subsystems[to.subsystem].hexes.remove(hex);
		data.hex[hex].subsystem = -1;
	}
};

class ModuleAction : Action {
	vec2u hex;
	int prev;
	int mod;

	ModuleAction(const vec2u& Hex, int module) {
		hex = Hex;
		mod = module;
	}

	void act(DesignData@ data) {
		HexData@ hdata = data.hex[hex];
		prev = hdata.module;
		hdata.module = mod;
	}

	void undo(DesignData@ data) {
		data.hex[hex].module= prev;
	}
};

class ClearAction : Action {
	vec2u hex;
	HexData from;

	ClearAction(const vec2u& Hex) {
		hex = Hex;
	}

	void act(DesignData@ data) {
		from = data.hex[hex];
		if(from.subsystem != -1)
			data.subsystems[from.subsystem].hexes.remove(hex);
		data.hex[hex] = HexData(-1, -1);
	}

	void undo(DesignData@ data) {
		if(from.subsystem != -1) {
			SubsystemData@ sdata = data.subsystems[from.subsystem];
			sdata.hexes.insertLast(hex);

			if(sdata.def.hasCore && from.module == sdata.def.coreModule.index)
				sdata.core = hex;
		}
		data.hex[hex] = from;
	}
};

class SizeChangeAction : Action {
	double fromSize;
	double toSize;

	SizeChangeAction(double from, double to) {
		fromSize = from;
		toSize = to;
	}

	void act(DesignData@ data) {
		data.resize(toSize);
	}

	void undo(DesignData@ data) {
		data.resize(fromSize);
	}
};

class GridChangeAction : Action {
	vec2u fromSize;
	vec2u toSize;

	GridChangeAction(vec2u from, vec2u to) {
		fromSize = from;
		toSize = to;
	}

	void act(DesignData@ data) {
		data.gridChange(toSize);
	}

	void undo(DesignData@ data) {
		data.gridChange(fromSize);
	}
};


class CreateSubsystemAction : Action {
	const SubsystemDef@ def;
	vec2u core;
	vec3d direction;

	CreateSubsystemAction(const SubsystemDef@ sys, const vec2u& Core, const vec3d& direction = vec3d()) {
		@def = sys;
		core = Core;
		this.direction = direction;
	}

	void act(DesignData@ data) {
		SubsystemData ss;
		ss.sysId = def.index;
		ss.core = core;

		if(!direction.zero) {
			ss.direction = direction;
		}
		else if(def.hasTag(ST_HexLimitArc) && !data.hasTag(ST_OverrideHexArcLimit)) {
			if((data.hull.active.valid(core, HEX_UpRight) && data.hull.active.get(core, HEX_UpRight))
					|| (data.hull.active.valid(core, HEX_DownRight) && data.hull.active.get(core, HEX_DownRight))) {
				for(uint i = 0; i < 6; ++i) {
					int d = 3;
					if(i % 2 == 0)
						d += i/2;
					else
						d -= i/2+1;

					auto adj = HexGridAdjacency(d);
					vec2u pos = core;
					if(data.hull.active.advance(pos, adj)) {
						if(data.hull.active[pos])
							continue;
					}

					double rad = hexToRadians(adj);
					vec2d offset = vec2d(1.0,0.0).rotate(rad);
					ss.direction.x = offset.x;
					ss.direction.z = -offset.y;
					break;
				}
			}
		}

		data.subsystems.insertLast(ss);
	}

	void undo(DesignData@ data) {
		int index = data.subsystems.length - 1;
		data.subsystems.removeAt(index);

		for(uint i = 0, cnt = data.hexagons.length; i < cnt; ++i) {
			if(data.hexagons[i].subsystem == index)
				data.hexagons[i].subsystem = -1;
		}
	}
};

class RemoveSubsystemAction : Action {
	int index;
	SubsystemData prevData;

	RemoveSubsystemAction(int sysIndex) {
		index = sysIndex;
	}

	void act(DesignData@ data) {
		prevData = data.subsystems[index];
		data.subsystems.removeAt(index);
		for(uint i = 0, cnt = data.hexagons.length; i < cnt; ++i) {
			HexData@ hdata = data.hexagons[i];
			if(hdata.subsystem > index)
				--hdata.subsystem;
		}
	}

	void undo(DesignData@ data) {
		SubsystemData newData;
		newData = prevData;

		data.subsystems.insertAt(index, newData);
		for(uint i = 0, cnt = data.hexagons.length; i < cnt; ++i) {
			HexData@ hdata = data.hexagons[i];
			if(hdata.subsystem >= index)
				++hdata.subsystem;
		}
	}
};

class RotateAction : Action {
	int sysIndex;
	double rotation;

	RotateAction(int sysId, double rot) {
		sysIndex = sysId;
		rotation = rot;
	}

	void rotate(DesignData@ data, double amt) {
		SubsystemData@ sys = data.subsystems[sysIndex];
		vec2d base(sys.direction.x, sys.direction.z);
		base.rotate(double(amt));
		sys.direction.x = base.x;
		sys.direction.z = base.y;
	}

	void act(DesignData@ data) {
		rotate(data, rotation);
	}

	void undo(DesignData@ data) {
		rotate(data, -rotation);
	}
};

class ApplySubsystem : Action {
	const SubsystemDef@ type;

	ApplySubsystem(const SubsystemDef@ type) {
		@this.type = type;
	}

	void act(DesignData@ data) {
		data.appliedSubsystems.insertLast(type);
	}

	void undo(DesignData@ data) {
		data.appliedSubsystems.remove(type);
	}
};

class RemoveAppliedSubsystem : Action {
	const SubsystemDef@ type;

	RemoveAppliedSubsystem(const SubsystemDef@ type) {
		@this.type = type;
	}

	void act(DesignData@ data) {
		data.appliedSubsystems.remove(type);
	}

	void undo(DesignData@ data) {
		data.appliedSubsystems.insertLast(type);
	}
};
/** }}} */
/** Tools {{{*/
class Tool {
	void grab(DesignData@ data, const vec2u& hex, int button) {
	}

	void hover(DesignData@ data, const vec2u& hex, int pressed) {
	}

	void release(DesignData@ data, const vec2u& hex, int button) {
	}

	void release(DesignData@ data, int button) {
	}

	bool scroll(DesignData@ data, const vec2u& hex, int amount) {
		return false;
	}

	void cancel(DesignData@ data, int button) {
	}

	void draw(DesignData@ data, DesignEditor@ editor) {
	}
};

bool checkSubsystemConsistency(DesignData@ data, int index, bool createGroup, bool& destroyed) {
	SubsystemData@ sdata = data.subsystems[index];
	bool createdGroup = false;

	//Noncontiguous subsystems skip these checks
	if(sdata.def.isContiguous) {
		//Clear any hexes that are not connected
		HexGridb conn;
		conn.resize(data.gridSize.width, data.gridSize.height);
		conn.clear(false);

		//Check outward from the core (if it exists)
		if(data.hex[sdata.core].subsystem == index)
			checkConnected(conn, data, sdata.core, index);

		//Remove any hexes that are no longer connected
		for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
			vec2u pos = sdata.hexes[i];
			if(!conn.get(pos)) {
				if(createGroup) {
					data.grabGroup();
					createdGroup = true;
					createGroup = false;
				}
				data.act(ClearAction(pos));
				--i; --cnt;
			}
		}
	}

	//Remove the subsystem if no hexes are remaining
	if(sdata.hexes.length == 0) {
		if(createGroup) {
			data.grabGroup();
			createdGroup = true;
			createGroup = false;
		}
		data.act(RemoveSubsystemAction(index));
		destroyed = true;
	}
	else {
		destroyed = false;
	}

	return createdGroup;
}

class EyedropperTool : Tool {
	int sysId;
	int moduleId;

	EyedropperTool() {
		sysId = -1;
	}

	void release(DesignData@ data, const vec2u& hex, int button) {
		SubsystemData@ sdata = data.subsystem[hex];
		sysId = sdata.sysId;
		moduleId = -1;
		if(sysId != -1) {
			auto@ def = sdata.def;
			int mod = data.hex[hex].module;
			if(mod != -1 && mod != def.coreModule.index && mod != def.defaultModule.index)
				moduleId = mod;
		}
	}
};

class ReplaceTool : Tool {
	const SubsystemDef@ def;

	void release(DesignData@ data, const vec2u& hex, int button) {
		if(button != B_LEFT)
			return;

		HexData@ hdata = data.hex[hex];
		if(hdata is null || hdata.subsystem == -1)
			return;

		SubsystemData@ sdata = data.subsystems[hdata.subsystem];
		auto@ prevDef = sdata.def;

		if(prevDef is def || def is null || prevDef is null)
			return;

		array<Action@> actions;
		for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i)
			actions.insertLast(ClearAction(sdata.hexes[i]));
		actions.insertLast(RemoveSubsystemAction(hdata.subsystem));

		int newSys = data.subsystems.length-1;
		actions.insertLast(CreateSubsystemAction(def, sdata.core, direction=sdata.direction));
		for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
			const ModuleDef@ mod = def.defaultModule;

			if(def.coreModule !is null && prevDef.coreModule !is null && data.hex[sdata.hexes[i]].module == prevDef.coreModule.index)
				@mod = def.coreModule;
			if(prevDef.coreModule is null && def.coreModule !is null && i == 0)
				@mod = def.coreModule;
			actions.insertLast(PaintAction(sdata.hexes[i], HexData(newSys, mod.index)));
		}

		data.startGroup();
		for(uint i = 0, cnt = actions.length; i < cnt; ++i)
			data.act(actions[i]);
		data.endGroup();
	}
};

class PaintTool : Tool {
	const SubsystemDef@ def;
	int draggingSystem;
	int firstButton;
	bool started;
	bool modified;
	bool moduleRemove;

	PaintTool() {
		draggingSystem = -1;
		firstButton = 0;
		started = false;
		modified = false;
		moduleRemove = false;
	}

	void clearHex(DesignData@ data, const vec2u& hex, bool checkModule = false) {
		HexData@ hdata = data.hex[hex];
		int sys = hdata.subsystem;
		if(sys == -1)
			return;

		if(modified && !started) {
			started = true;
			data.grabGroup();
		}

		bool isModule = false;
		const SubsystemDef@ def = data.subsystems[sys].def;
		if(checkModule || moduleRemove) {
			isModule = (!def.hasCore || hdata.module != def.coreModule.index) &&
					hdata.module != def.defaultModule.index;
		}

		if(checkModule)
			moduleRemove = isModule;

		if(moduleRemove) {
			if(isModule) {
				data.act(ModuleAction(hex, def.defaultModule.index));
				modified = true;
			}
		}
		else {
			data.act(ClearAction(hex));
			modified = true;
		}

		bool destroyed = false;
		if(checkSubsystemConsistency(data, sys, !started, destroyed))
			started = true;
	}

	void paintHex(DesignData@ data, const vec2u& hex, int mod) {
		HexData@ hdata = data.hex[hex];
		if(hdata.subsystem == draggingSystem)
			return;

		//Add the clear action for previous hex
		int oldsys = hdata.subsystem;
		if(oldsys != -1) {
			if(!started) {
				if(modified)
					data.grabGroup();
				else
					data.startGroup();
				started = true;
			}

			data.act(ClearAction(hex));

			bool destroyed = false;
			checkSubsystemConsistency(data, oldsys, false, destroyed);

			if(destroyed) {
				if(draggingSystem >= oldsys)
					--draggingSystem;
			}
		}

		//Add the paint action
		data.act(PaintAction(hex, HexData(draggingSystem, mod)));
	}

	bool canPaint(DesignData@ data, const vec2u& hex, bool initial) {
		if(def is null)
			return false;
		if(!initial) {
			//Make sure we're painting a contiguous subsystem
			if(def.isContiguous) {
				bool found = false;
				for(uint i = 0; i < 6; ++i) {
					HexGridAdjacency adj = HexGridAdjacency(i);
					vec2u pos = hex;
					if(!advanceHexPosition(pos, vec2u(data.gridSize), adj))
						continue;
					HexData@ other = data.hex[pos];
					if(other.subsystem == draggingSystem) {
						found = true;
						break;
					}
				}

				if(!found)
					return false;
			}
		}
		return true;
	}

	void grab(DesignData@ data, const vec2u& hex, int button) {
		if(firstButton != 0)
			return;
		firstButton = button;
		started = false;
		modified = false;
		if(button == B_LEFT) {
			if(def is null)
				return;
			//Find the system to drag from or create
			draggingSystem = -1;
			if(!def.isContiguous) {
				for(uint i = 0, cnt = data.subsystems.length; i < cnt; ++i) {
					if(data.subsystems[i].sysId == def.index) {
						draggingSystem = i;
						break;
					}
				}
			}
			else {
				//Check if we're dragging from a start point
				//in a valid subsystem
				HexData@ hdata = data.hex[hex];
				if(hdata.subsystem != -1 && data.subsystems[hdata.subsystem].sysId == def.index && !ctrlKey) {
					draggingSystem = hdata.subsystem;
					return;
				}
				else {
					//Check if adjacent to the same subsystem to connect to
					if(!ctrlKey) {
						double closestDist = -1.0;

						for(uint i = 0; i < 6; ++i) {
							HexGridAdjacency adj = HexGridAdjacency(i);
							vec2u pos = hex;
							if(!advanceHexPosition(pos, vec2u(data.gridSize), adj))
								continue;
							HexData@ other = data.hex[pos];
							if(other.subsystem != -1 && data.subsystems[other.subsystem].sysId == def.index) {
								vec2u core = data.subsystems[other.subsystem].core;
								double dist = getHexPosition(hex).distanceTo(getHexPosition(core));
								if(draggingSystem == -1 || dist < closestDist) {
									draggingSystem = other.subsystem;
									closestDist = dist;
								}
							}
						}
					}
				}
			}

			if(!canPaint(data, hex, true)) {
				started = false;
				modified = false;
			}
			else if(draggingSystem == -1) {
				started = true;
				modified = true;
				data.startGroup();
				const ModuleDef@ mod;

				if(def.hasCore)
					@mod = def.coreModule;
				else
					@mod = def.defaultModule;

				draggingSystem = data.subsystems.length;
				data.act(CreateSubsystemAction(def, hex));
				paintHex(data, hex, mod.index);
			}
			else {
				paintHex(data, hex, def.defaultModule.index);
				modified = true;
			}
		}
		else if(button == B_RIGHT) {
			clearHex(data, hex, true);
		}
	}

	void hover(DesignData@ data, const vec2u& hex, int pressed) {
		if(firstButton == B_LEFT) {
			if(def is null)
				return;
			HexData@ hdata = data.hex[hex];
			if(hdata.subsystem == draggingSystem)
				return;
			if(!canPaint(data, hex, false))
				return;

			//Start the group if needed
			if(modified && !started) {
				started = true;
				data.grabGroup();
			}

			paintHex(data, hex, def.defaultModule.index);
			modified = true;
		}
		else if(firstButton == B_RIGHT) {
			clearHex(data, hex);
		}
	}

	void release(DesignData@ data, const vec2u& hex, int button) {
		if(button != firstButton)
			return;
		if(button == B_LEFT)
			draggingSystem = -1;
		if(started)
			data.endGroup();
		started = false;
		firstButton = 0;
	}

	void cancel(DesignData@ data, int button) {
		if(button != firstButton)
			return;
		if(button == B_LEFT)
			draggingSystem = -1;
		if(started)
			data.endGroup();
		started = false;
		firstButton = 0;
	}

	bool scroll(DesignData@ data, const vec2u& hex, int amount) {
		HexData@ hdata = data.hex[hex];
		int sysId = hdata.subsystem;
		if(sysId == -1)
			return false;

		SubsystemData@ sys = data.subsystems[sysId];
		const SubsystemDef@ def = sys.def;
		if(!def.hasTag(ST_Rotatable))
			return false;
		if(hex != sys.core)
			return false;

		double amt = double(amount) * TURRET_TICK_ROTATION;
		if(data.undoHead !is null) {
			RotateAction@ act = cast<RotateAction>(data.undoHead);
			if(act !is null && act.sysIndex == sysId) {
				act.rotate(data, amt);
				act.rotation += amt;
				return true;
			}
		}

		data.act(RotateAction(sysId, amt));
		return true;
	}
};

class MoveTool : Tool {
	vec2u origin;
	bool moving;
	bool valid;
	bool lastShift;
	bool lastControl;
	vec2u lastHex;

	MoveTool() {
		moving = false;
		valid = false;
		lastShift = false;
		lastControl = false;
	}

	void grab(DesignData@ data, const vec2u& hex, int button) {
		if(button != B_LEFT)
			return;
		HexData@ hdata = data.hex[hex];
		if(hdata.subsystem == -1)
			return;
		origin = hex;
		moving = true;
		valid = true;
	}

	void release(DesignData@ data, const vec2u& hex, int button) {
		if(button != B_LEFT)
			return;

		checkValid(data, hex);
		moving = false;

		if(!valid) {
			sound::error.play(priority=true);
			return;
		}
		if(hex == origin)
			return;

		if(shiftKey) {
			//Move an entire subsystem
			vec2i offset = vec2i(hex) - vec2i(origin);
			SubsystemData@ sdata = data.subsystem[origin];

			Action@[] queue;
			HexGridb conn;
			conn.resize(data.gridSize.width, data.gridSize.height);
			conn.clear(false);

			if(ctrlKey)
				queue.insertLast(CreateSubsystemAction(sdata.def, vec2u()));

			//Queue moves for all the hexes
			for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
				vec2u pos = sdata.hexes[i];
				vec2u newPos = vec2u(vec2i(pos) + offset);

				if(hex.x % 2 != origin.x % 2) {
					if(pos.x % 2 != origin.x % 2) {
						if(pos.x % 2 == 0) {
							newPos.y -= 1;
						}
						else {
							newPos.y += 1;
						}
					}
				}

				if(!ctrlKey && !conn.get(pos))
					queue.insertLast(ClearAction(pos));

				if(data.hex[newPos].subsystem != -1)
					queue.insertLast(ClearAction(newPos));

				if(ctrlKey)
					queue.insertLast(PaintAction(newPos,
						HexData(data.subsystems.length,
								data.hex[pos].module)));
				else
					queue.insertLast(PaintAction(newPos, data.hex[pos]));
				conn.get(newPos) = true;
			}

			//Execute the queued actions
			data.startGroup();
			for(uint i = 0, cnt = queue.length; i < cnt; ++i)
				data.act(queue[i]);

			//Check all subsystems for consistency
			for(uint i = 0, cnt = data.subsystems.length; i < cnt; ++i) {
				bool destroyed = false;
				checkSubsystemConsistency(data, i, false, destroyed);

				if(destroyed) {
					--i;
					--cnt;
				}
			}
			data.endGroup();
		}
		else {
			HexData from = data.hex[origin];
			HexData to = data.hex[hex];

			if(from.subsystem == -1)
				return;

			data.startGroup();

			//Clear previous hexes
			if(!ctrlKey)
				data.act(ClearAction(origin));

			if(to.subsystem != -1)
				data.act(ClearAction(hex));

			//Paint next hex
			data.act(PaintAction(hex, from));

			//When moving inside the same subsystem,
			//we swap the tiles
			if(to.subsystem == from.subsystem)
				data.act(PaintAction(origin, to));

			//Do consistency checks on both subsystems
			bool destroyed = false;
			checkSubsystemConsistency(data, from.subsystem, false, destroyed);

			if(destroyed && to.subsystem > from.subsystem)
				--to.subsystem;

			if(to.subsystem != -1 && to.subsystem != from.subsystem)
				checkSubsystemConsistency(data, to.subsystem, false, destroyed);
			data.endGroup();
		}
	}

	void checkConnected(HexGridb& conn, DesignData& data, const vec2u& hex, int sys, const vec2u&in toHex) {
		if(conn.get(hex))
			return;
		conn.get(hex) = true;

		for(uint i = 0; i < 6; ++i) {
			HexGridAdjacency adj = HexGridAdjacency(i);
			vec2u pos = hex;

			if(conn.advance(pos, adj)) {
				if(!ctrlKey && pos == origin)
					continue;
				if(data.hex[pos].subsystem == sys || pos == toHex) {
					checkConnected(conn, data, pos, sys, toHex);
				}
			}
		}
	}

	void checkValid(DesignData@ data, const vec2u& hex) {
		if(!moving)
			return;

		HexData@ from = data.hex[origin];
		HexData@ to = data.hex[hex];
		SubsystemData@ sdata = data.subsystems[from.subsystem];
		lastShift = shiftKey;
		lastControl = ctrlKey;
		lastHex = hex;

		if(shiftKey) {
			//Moving an entire subsystem is always valid unless
			//moved out of bounds
			vec2i offset = vec2i(hex) - vec2i(origin);

			for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
				vec2u pos = sdata.hexes[i];
				vec2i newPos = vec2i(pos) + offset;

				if(hex.x % 2 != origin.x % 2) {
					if(pos.x % 2 != origin.x % 2) {
						if(pos.x % 2 == 0) {
							newPos.y -= 1;
						}
						else {
							newPos.y += 1;
						}
					}
				}

				if(newPos.x < 0 || newPos.x >= data.gridSize.width ||
						newPos.y < 0 || newPos.y >= data.gridSize.height) {
					valid = false;
					return;
				}
			}

			valid = true;
		}
		else {
			//Cannot duplicate unique modules
			if(ctrlKey) {
				const ModuleDef@ mod = sdata.def.modules[from.module];
				if(mod.unique) {
					valid = false;
					return;
				}
			}

			//Can always move for noncontiguous systems
			if(!sdata.def.isContiguous) {
				valid = true;
				return;
			}

			//Can always move within a subsystem
			if(to.subsystem == from.subsystem) {
				valid = true;
				return;
			}

			//Check if anything would be deleted
			HexGridb conn;
			conn.resize(data.gridSize.width, data.gridSize.height);
			conn.clear(false);

			if(origin == sdata.core)
				checkConnected(conn, data, hex, from.subsystem, hex);
			else
				checkConnected(conn, data, sdata.core, from.subsystem, hex);

			//If the target hex is disconnected, the move is invalid
			if(!conn.get(hex)) {
				valid = false;
				return;
			}

			//If any hex would be cleared by this move, it is invalid
			for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
				vec2u pos = sdata.hexes[i];
				if(pos != origin && !conn.get(pos)) {
					valid = false;
					return;
				}
			}

			valid = true;
		}
	}

	void hover(DesignData@ data, const vec2u& hex, int pressed) {
		checkValid(data, hex);
	}

	void cancel(DesignData@ data, int button) {
		if(button == B_LEFT)
			moving = false;
	}

	void drawHex(DesignData@ data, DesignEditor@ editor, const vec2u& hex, const vec2u&in forOrigin) {
		HexData@ hdata = data.hex[hex];
		if(hdata.subsystem == -1)
			return;

		SubsystemData@ sdata = data.subsystems[hdata.subsystem];
		recti pos = recti_area(vec2i(
			mousePos.x - (editor.construction.display.hexSize.width / 2),
			mousePos.y - (editor.construction.display.hexSize.height / 2)),
			vec2i(editor.construction.display.hexSize.width,
				  editor.construction.display.hexSize.height));

		if(hex != forOrigin) {
			vec2d relOff = getHexPosition(hex) - getHexPosition(forOrigin);
			relOff.x *= editor.construction.display.hexSize.width;
			relOff.y *= editor.construction.display.hexSize.height;

			pos += vec2i(relOff);
		}

		const SubsystemDef@ def = sdata.def;
		const ModuleDef@ mod = def.modules[hdata.module];

		//Module picture
		vec2i modSize = mod.sprite.size;
		vec2i hexSize = editor.construction.display.hexSize;
		double factor = editor.construction.display.hexFactor;
		modSize.x = double(modSize.x) * factor;
		modSize.y = double(modSize.y) * factor;

		vec2i modPos = pos.topLeft;
		modPos.x -= (modSize.x - hexSize.x) / 2;
		if(modSize.y > hexSize.y)
			modPos.y -= (modSize.y - hexSize.y);
		else
			modPos.y -= (modSize.y - hexSize.y) / 2;

		double rotation = 0.0;
		if(mod is def.coreModule && def.hasTag(ST_Rotatable)) {
			vec3d rot = sdata.direction;
			vec2d rightvec(1.0, 0.0);
			vec2d rotvec(rot.x, rot.z);
			rotation = rightvec.getRotation(rotvec);
		}

		Color color;
		if(valid)
			color = Color(0xffffffd0);
		else
			color = Color(0xff808080);

		switch(mod.drawMode) {
			case SDM_Static:
				if(rotation != 0)
					mod.sprite.draw(recti_area(modPos, modSize), color, rotation);
				else
					mod.sprite.draw(recti_area(modPos, modSize), color);
			break;
			case SDM_Rotatable: {
				vec3d rot = sdata.direction;
				vec2d rightvec(1.0, 0.0);
				vec2d rotvec(rot.x, -rot.z);
				rotation = rightvec.getRotation(rotvec);

				if(modSize.y > hexSize.y)
					modPos.y += (modSize.y - hexSize.y) / 2;

				Sprite sprt = mod.sprite;
				sprt.index += HexGridAdjacency(radiansToHex(rotation));

				double diffrot = hexToRadians(HexGridAdjacency(sprt.index)) - rotation;
				sprt.draw(recti_area(modPos, modSize), color, diffrot);
			} break;
		}
	}

	void draw(DesignData@ data, DesignEditor@ editor) {
		if(!moving)
			return;

		if(lastShift != shiftKey || lastControl != ctrlKey)
			checkValid(data, lastHex);

		drawHex(data, editor, origin, origin);

		if(shiftKey) {
			SubsystemData@ sdata = data.subsystem[origin];
			for(uint i = 0, cnt = sdata.hexes.length; i < cnt; ++i) {
				vec2u hex = sdata.hexes[i];
				if(hex != origin)
					drawHex(data, editor, hex, origin);
			}
		}
	}
};

class ModuleTool : Tool {
	const ModuleDef@ mod;
	bool valid;
	bool multiple;

	ModuleTool() {
		valid = false;
	}

	void checkValid(DesignData@ data, const vec2u& hex) {
		HexData@ hdata = data.hex[hex];
		if(hdata.subsystem == -1) {
			valid = false;
			return;
		}

		//Can only place modules within the right
		//subsystem
		SubsystemData@ sdata = data.subsystems[hdata.subsystem];
		if(sdata.def is null || sdata.def.module(mod.id) is null) {
			valid = false;
			return;
		}

		//Cannot overwrite the core
		if(sdata.def.hasCore && hdata.module == sdata.def.coreModule.index) {
			valid = false;
			return;
		}

		valid = true;
	}

	void clearHex(DesignData@ data, const vec2u& hex) {
		HexData@ hdata = data.hex[hex];
		int sys = hdata.subsystem;
		if(sys == -1)
			return;

		const SubsystemDef@ def = data.subsystems[sys].def;
		bool isModule = (!def.hasCore || hdata.module != def.coreModule.index) &&
					hdata.module != def.defaultModule.index;

		if(isModule)
			data.act(ModuleAction(hex, def.defaultModule.index));
	}

	void grab(DesignData@ data, const vec2u& hex, int pressed) override {
		checkValid(data, hex);

		if(pressed == B_RIGHT)
			clearHex(data, hex);
	}

	void hover(DesignData@ data, const vec2u& hex, int pressed) override {
		checkValid(data, hex);

		if(pressed == B_RIGHT)
			clearHex(data, hex);
	}

	void release(DesignData@ data, const vec2u& hex, int pressed) override {
		if(pressed != B_LEFT)
			return;

		checkValid(data, hex);
		if(!valid) {
			sound::error.play(priority=true);
			return;
		}

		HexData@ hdata = data.hex[hex];
		SubsystemData@ sdata = data.subsystems[hdata.subsystem];
		data.act(ModuleAction(hex, sdata.def.module(mod.id).index));
	}

	void draw(DesignData@ data, DesignEditor@ editor) override {
		recti pos = recti_area(vec2i(
			mousePos.x - (editor.construction.display.hexSize.width / 2),
			mousePos.y - (editor.construction.display.hexSize.height / 2)),
			vec2i(editor.construction.display.hexSize.width,
				  editor.construction.display.hexSize.height));

		if(valid) {
			mod.sprite.draw(pos.aspectAligned(mod.sprite.aspect));
		}
		else {
			drawRectangle(pos, Color(0xff000040));
			mod.sprite.draw(pos.aspectAligned(mod.sprite.aspect));
		}
	}
};
/** }}} */
/** Construction page {{{*/
class FilterButton : GuiButton {
	Construction@ cons;
	string tag;

	FilterButton(Construction@ parent, const string& text, const string&in Tag,
			int w = FILTER_WIDTH, bool Pressed = false) {
		@cons = parent;
		tag = Tag;
		int x = 0;
		if(!parent.filterButtons.isEmpty())
			x = parent.filterButtons.last.absolutePosition.botRight.x;
		super(parent, recti_area(
			vec2i(4 + x, 3),
			vec2i(w, 22)),
			text);
		toggleButton = true;
		pressed = Pressed;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this && !disabled) {
			switch(event.type) {
				case MET_Button_Down:
					if(!Hovered)
						return true;
					if(event.button == 0) {
						for(uint i = 0, cnt = cons.filterButtons.length; i < cnt; ++i)
							if(cons.filterButtons[i] !is this)
								cons.filterButtons[i].pressed = false;
					}
					if(tag.length != 0)
						Pressed = !Pressed;
					else
						Pressed = true;
					cons.updateSubsystems();
					return true;
			}
		}
		return GuiButton::onMouseEvent(event, source);
	}
};

class RandomConfig : InputDialogCallback {
	int weaponCount;
	double engineSize;
	double hyperSize;
	bool supplies;
	bool support;

	RandomConfig() {
		reset();
	}

	void reset() {
		weaponCount = -1;
		engineSize = 1.0;
		hyperSize = 1.0;
		supplies = true;
		support = true;
	}

	void apply(Designer& d) {
		d.weaponCount = weaponCount;
		d.supplies = supplies;
		d.support = support;
		d.engineSize = (engineSize - 1.0) * (d.grid.width * d.grid.height) / 30;
		d.hyperSize = (hyperSize - 1.0) * (d.grid.width * d.grid.height) / 30;
	}

	void prompt(IGuiElement@ parent, const Design@ dsg) {
		InputDialog@ dialog = InputDialog(this, parent);
		dialog.addTitle(locale::DESIGN_CONFIGURE);

		dialog.addSpinboxInput(locale::DESIGN_RND_WEAPONCOUNT, weaponCount, 1, -1, 10, 0);
		dialog.addSpinboxInput(locale::DESIGN_RND_ENGINESIZE, engineSize, 0.1, 1, 10, 1);
		if(dsg.hull.hasTag("Flagship")) {
			if(playerEmpire.isUnlocked(subsystem::Hyperdrive) || playerEmpire.isUnlocked(subsystem::Jumpdrive))
				dialog.addSpinboxInput(locale::DESIGN_RND_HYPERSIZE, hyperSize, 0.1, 1, 10, 1);
			dialog.addToggle(locale::DESIGN_RND_SUPPLIES, supplies);
			dialog.addToggle(locale::DESIGN_RND_SUPPORT, support);
		}

		addDialog(dialog);
		dialog.focusInput();
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			uint i = 0;
			weaponCount = dialog.getSpinboxInput(i++);
			engineSize = dialog.getSpinboxInput(i++);

			if(dialog.inputCount >= 4) {
				if(playerEmpire.isUnlocked(subsystem::Hyperdrive) || playerEmpire.isUnlocked(subsystem::Jumpdrive))
					hyperSize = dialog.getSpinboxInput(i++);
				else
					hyperSize = 1.0;

				supplies = dialog.getToggle(i++);
				support = dialog.getToggle(i++);
			}
		}
	}
};

const string shipsetALL = "ALL";
class HullElement : GuiListText {
	const Hull@ hull;

	HullElement(const Hull@ hull) {
		@this.hull = hull;

		string hname = hull.name;
		if(playerEmpire.shipset.ident == shipsetALL) {
			for(uint i = 0, cnt = getShipsetCount(); i < cnt; ++i) {
				auto@ sset = getShipset(i);
				if(!sset.available)
					continue;
				if(sset.hasHull(hull)) {
					hname += " ("+sset.name+")";
					break;
				}
			}
		}

		super(format(locale::FORCE_HULL, hname));
	}
};

class Construction : BaseGuiElement {
	DesignEditor@ editor;
	vec2i shownHexStats;
	RandomConfig randomConfig;

	GuiPanel@ displayPanel;
	GuiBlueprint@ display;
	GuiAccordion@ syslist;
	GuiProgressbar@ sizeBar;

	GuiButton@ hullButton;
	GuiButton@ arcButton;
	GuiButton@ centerButton;

	GuiButton@ randomButton;
	GuiButton@ configButton;

	GuiButton@ undoButton;
	GuiButton@ redoButton;

	GuiButton@ paintButton;
	GuiButton@ moveButton;
	GuiButton@ dropButton;
	GuiButton@ replaceButton;

	GuiButton@ clearButton;

	PaintTool paintTool;
	MoveTool moveTool;
	EyedropperTool dropTool;
	ModuleTool moduleTool;
	ReplaceTool replaceTool;
	Tool@ activeTool;
	Tool@ prevTool;

	GuiDropdown@ hullList;

	GuiSkinElement@ statsPopup;
	GuiPanel@ statsPanel;
	GuiBlueprintStats@ globalStats;
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

	GuiMarkupText@ tip;

	GuiMarkupText@ cost;
	GuiMarkupText@ buildTime;

	FilterButton@[] filterButtons;

	int prevSelected;
	int pressed;

	Construction(DesignEditor@ ed, Alignment@ align) {
		@editor = ed;
		super(editor, align);
		
		@activeTool = paintTool;

		pressed = 0;
		prevSelected = 0;

		@hullList = GuiDropdown(this, Alignment(Left+270, Top+1, Right-686-36-36-60-20, Height=32));
		hullList.visible = false;
		updateHullList();

		@arcButton = GuiButton(this, Alignment(Right-686-36-36-60, Top+2, Width=32, Height=32), spritesheet::ActionBarIcons+20);
		arcButton.style = SS_IconToggle;
		arcButton.color = Color(0x80a0ffff);
		arcButton.toggleButton = true;
		arcButton.pressed = SHOW_ARC_UNDERLAY;
		setMarkupTooltip(arcButton, locale::DESIGN_SHOW_ARCS);

		@hullButton = GuiButton(this, Alignment(Right-686-36-60, Top+2, Width=32, Height=32),
				Sprite(spritesheet::ShipIcons, 1, Color(0x8080ffff)));
		hullButton.style = SS_IconToggle;
		hullButton.color = Color(0x80a0ffff);
		hullButton.toggleButton = true;
		hullButton.pressed = SHOW_HULL_UNDERLAY;
		setMarkupTooltip(hullButton, locale::DESIGN_SHOW_HULL);

		@centerButton = GuiButton(this, Alignment(Right-686-60, Top+2, Width=32, Height=32), Sprite(material::TabPlanets));
		centerButton.style = SS_IconButton;
		centerButton.color = Color(0x80a0ffff);
		setMarkupTooltip(centerButton, locale::DESIGN_CENTER);

		@randomButton = GuiButton(this, Alignment(Right-650-26, Top+2, Width=32, Height=32), Sprite(spritesheet::MenuIcons, 4, Color(0xff8040ff)));
		randomButton.style = SS_IconButton;
		randomButton.color = Color(0x80a0ffff);
		randomButton.visible = !playerEmpire.hasTrait(getTraitID("Verdant"));
		setMarkupTooltip(randomButton, locale::DESIGN_RANDOMIZE);

		@configButton = GuiButton(this, Alignment(Right-650, Top+2, Width=32, Height=32), Sprite(spritesheet::MenuIcons, 7, Color(0xff8040ff)));
		configButton.style = SS_IconButton;
		configButton.color = Color(0xa080ffff);
		configButton.visible = false;
		setMarkupTooltip(configButton, locale::DESIGN_RANDOMIZE_CONFIGURE);

		@undoButton = GuiButton(this, Alignment(Right-568, Top+2, Width=32, Height=32), icons::Undo);
		undoButton.style = SS_IconButton;
		setMarkupTooltip(undoButton, format(locale::DESIGN_UNDO, getKey(KB_DESIGN_UNDO)));

		@redoButton = GuiButton(this, Alignment(Right-532, Top+2, Width=32, Height=32), icons::Redo);
		redoButton.style = SS_IconButton;
		setMarkupTooltip(redoButton, format(locale::DESIGN_REDO, getKey(KB_DESIGN_REDO)));

		@paintButton = GuiButton(this, Alignment(Right-476, Top+2, Width=32, Height=32), icons::Paint);
		paintButton.style = SS_IconToggle;
		paintButton.toggleButton = true;
		paintButton.pressed = true;
		paintButton.color = colors::Green;
		setMarkupTooltip(paintButton, format(locale::DESIGN_PAINT_TOOL, getKey(KB_DESIGN_TOOL_PAINT)));

		@moveButton = GuiButton(this, Alignment(Right-440, Top+2, Width=32, Height=32), icons::Move);
		moveButton.style = SS_IconToggle;
		moveButton.toggleButton = true;
		moveButton.color = colors::Green;
		setMarkupTooltip(moveButton, format(locale::DESIGN_MOVE_TOOL, getKey(KB_DESIGN_TOOL_MOVE)));

		@dropButton = GuiButton(this, Alignment(Right-404, Top+2, Width=32, Height=32), icons::Eyedrop);
		dropButton.style = SS_IconToggle;
		dropButton.toggleButton = true;
		dropButton.color = colors::Green;
		setMarkupTooltip(dropButton, format(locale::DESIGN_DROP_TOOL, getKey(KB_DESIGN_TOOL_DROP)));

		@replaceButton = GuiButton(this, Alignment(Right-368, Top+2, Width=32, Height=32), icons::Replace);
		replaceButton.style = SS_IconToggle;
		replaceButton.toggleButton = true;
		replaceButton.pressed = false;
		replaceButton.color = colors::Green;
		setMarkupTooltip(replaceButton, format(locale::DESIGN_REPLACE_TOOL, getKey(KB_DESIGN_TOOL_REPLACE)));

		@clearButton = GuiButton(this, Alignment(Right-300, Top+2, Width=32, Height=32), icons::Clear);
		clearButton.style = SS_IconButton;
		clearButton.color = colors::Red;
		setMarkupTooltip(clearButton, locale::DESIGN_CLEAR);

		@displayPanel = GuiPanel(this, Alignment(Left+258+12, Top+32+12, Right-258-12, Bottom-44));
		displayPanel.setScrollPane(true, true);
		displayPanel.allowScrollDrag = false;
		displayPanel.LeftDrag = false;

		@display = GuiBlueprint(displayPanel, recti());
		display.hoverArcs = true;
		display.displayInactive = true;
		display.activateAll = true;

		@sizeBar = GuiProgressbar(this, Alignment(Left+258+12, Bottom-38, Right-258-12, Bottom-4));
		sizeBar.strokeColor = colors::Black;
		sizeBar.font = FT_Bold;
		sizeBar.backColor = Color(0xffffff80);
		setMarkupTooltip(sizeBar, locale::TT_DESIGN_HEX_LIMIT);

		@tip = GuiMarkupText(this, Alignment(Left+258, Bottom-78, Right-258, Bottom));
		tip.defaultColor = Color(0xaaaaaaff);
		tip.defaultFont = FT_Italic;
		tip.text = format("[align=0.5][img=MenuIcons::3;20/] $1[/align]", locale::TIP_ROTATE);
		tip.visible = false;

		//Stat panel
		@statsPanel = GuiPanel(this, Alignment(Right-256, Top, Right-6, Bottom-4));

		@globalStats = GuiBlueprintStats(statsPanel,
			recti(vec2i(0, 4), vec2i(250, 230)));

		@statsPopup = GuiSkinElement(this, recti_area(0, 0, 250, 200), SS_PlainBox);
		statsPopup.visible = false;

		@sysNameBG = GuiSkinElement(statsPopup,
			recti(0, 0, 246, 30), SS_SubTitle);
		@sysName = GuiText(sysNameBG,
			recti(HEAD_XOFF, 0, 250, 30));
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
			recti(HEAD_XOFF, 0, 250, 30));
		hexName.font = FT_Medium;

		@hexCostBG = GuiSkinElement(statsPopup, recti(0,0,246,30), SS_HorizBar);
		hexCostBG.color = Color(0x888888ff);
		hexCostBG.padding = recti(0,-4,0,-4);
		@hexCost = GuiMarkupText(hexCostBG, Alignment().padded(8,0,0,4));
		hexCost.text = "--";

		@hexStats = GuiBlueprintStats(statsPopup,
			recti(vec2i(0, 30), vec2i(246, 200)));

		//Create subsystem list
		@syslist = GuiAccordion(this, Alignment(Left+4, Top, Left+254, Bottom-4));
		updateSubsystems();

		@paintTool.def = getSubsystemDef(0);
		
		updateAbsolutePosition();
	}

	string getKey(uint bind) {
		int key = keybinds::DesignEditor.getCurrentKey(Keybind(bind), 0);
		return getKeyDisplayName(key);
	}

	void updateDisplayPanel() {
		if(display.hull is null)
			return;

		vec2i minim;
		if(screenSize.x >= 1900)
			minim = vec2i(30, 22);
		else
			minim = vec2i(24, 16);

		vec2i psize;
		psize.width = max(display.hull.active.width * minim.width, displayPanel.size.width - 20);
		psize.height = max(display.hull.active.height * minim.height, displayPanel.size.height - 20);
		displayPanel.MiddleDrag = psize.width > displayPanel.size.width || psize.height > displayPanel.size.height;
		display.rect = recti(vec2i(), psize);
		displayPanel.updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		updateStatsPos();
		BaseGuiElement::updateAbsolutePosition();
		updateDisplayPanel();
	}

	bool get_ready() {
		return editor.design.subsystemCount != 0;
	}

	void updateHullList() {
		const Hull@ sel = null;
		string type = "Flagship";
		if(editor.data.hull !is null) {
			if(editor.data.forceHull)
				@sel = editor.data.hull.baseHull;
			type = getHullTypeTag(editor.data.hull);
		}
		else {
			type = editor.concept.getSelectedTypeTag();
		}

		hullList.clearItems();
		hullList.addItem(GuiListText(locale::AUTO_SELECT_HULL));
		hullList.selected = 0;

		auto@ shipset = playerEmpire.shipset;
		if(shipset !is null) {
			for(uint i = 0, cnt = shipset.hullCount; i < cnt; ++i) {
				auto@ hull = shipset.hulls[i];
				if(getHullTypeTag(hull) != type)
					continue;
				hullList.addItem(HullElement(hull));
				if(hull is sel)
					hullList.selected = hullList.itemCount-1;
			}
		}
	}

	void update() {
		undoButton.disabled = editor.data.undoHead is null;
		if(undoButton.disabled)
			undoButton.setIcon(icons::UndoDisabled);
		else
			undoButton.setIcon(icons::Undo);

		redoButton.disabled = editor.data.redoHead is null;
		if(redoButton.disabled)
			redoButton.setIcon(icons::RedoDisabled);
		else
			redoButton.setIcon(icons::Redo);

		//randomButton.visible = editor.concept.getSelectedTypeTag() != "Station";
		//configButton.visible = randomButton.visible;

		globalStats.setStats(getDesignStats(editor.design));

		updateHexStats(shownHexStats, force=true);

		double usedHexes = editor.design.usedHexCount;
		usedHexes -= editor.design.variable(ShV_ExternalHexes);

		double hexLimit = floor(max(editor.design.total(SV_HexLimit), 1.0));
		double fillPct = clamp(usedHexes / hexLimit, 0.0, 1.0);

		if(usedHexes > hexLimit)
			sizeBar.frontColor = colors::Red;
		else
			sizeBar.frontColor = Color(0xff8080ff).interpolate(Color(0x80ff80ff), fillPct);

		sizeBar.text = format(locale::DESIGN_HEX_LIMIT, toString(usedHexes, 0), toString(hexLimit, 0));
		sizeBar.progress = fillPct;
		updateDisplayPanel();
	}

	void updateHexStats(const vec2i& hex, bool force = false) {
		if(hex == shownHexStats && !force)
			return;

		if(hex.x < 0 || hex.y < 0
				|| hex.x >= display.hull.gridSize.x
				|| hex.y >= display.hull.gridSize.y) {
			shownHexStats = vec2i(-1,-1);
			statsPopup.visible = false;
			globalStats.visible = true;
			tip.visible = false;
			return;
		}

		shownHexStats = hex;
		const Subsystem@ sys = editor.design.subsystem(vec2u(hex));

		if(sys is null) {
			statsPopup.visible = false;
			globalStats.visible = true;
			tip.visible = false;
			return;
		}

		statsPopup.visible = true;
		statsPopup.color = sys.type.color;

		sysNameBG.position = vec2i(2, 0);
		sysName.text = sys.type.name;
		sysNameBG.color = sys.type.color;

		sysCostBG.position = vec2i(2, 30);
		sysStats.position = vec2i(2, 28 + 26);
		sysStats.setStats(getSubsystemStats(editor.design, sys));

		hexNameBG.position = vec2i(2, sysStats.Position.botRight.y + 6);
		hexNameBG.color = sys.type.color;

		auto@ mod = editor.design.module(vec2u(hex));
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
		hexStats.setStats(getHexStats(editor.design, vec2u(hex)));

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
			formatMoney(ceil(build), ceil(maintain)), standardize(labor, editor.design.size >= 16));

		if(sys.has(HV_BuildCost))
			build = editor.design.variable(vec2u(hex), HV_BuildCost);
		if(sys.has(HV_MaintainCost))
			maintain = editor.design.variable(vec2u(hex), HV_MaintainCost);
		if(sys.has(HV_LaborCost))
			labor = editor.design.variable(vec2u(hex), HV_LaborCost);
		hexCost.text = format("[color=#ccc][offset=16][img=ResourceIcon::0;24;#ffffffaa/] [vspace=4]$1"
				"[/vspace][offset=130][img=ResourceIcon::6;24;#ffffffaa/] [vspace=4]$2[/vspace][/offset][/offset][/color]",
			formatMoney(ceil(build), ceil(maintain)), standardize(labor, editor.design.size >= 16));

		//Update tip
		if(mod is sys.type.coreModule && sys.type.hasTag(ST_Rotatable))
			tip.visible = true;
		else
			tip.visible = false;
	}

	array<SubsystemSelector@> selectors;
	void updateSubsystems() {
		updateHullList();
		selectors.length = 0;
		selectors.insertLast(SubsystemSelector(this, "Hulls"));
		selectors.insertLast(SubsystemSelector(this, "Control"));
		selectors.insertLast(SubsystemSelector(this, "Weapons"));
		selectors.insertLast(SubsystemSelector(this, "Propulsion"));
		selectors.insertLast(SubsystemSelector(this, "Defense"));
		selectors.insertLast(SubsystemSelector(this, "FTL"));
		selectors.insertLast(SubsystemSelector(this, "Misc"));

		SubsystemSelector modifiers(this, "Modifiers");
		dictionary haveModifiers;
		selectors.insertLast(modifiers);

		//Update list of subsystems
		int subsysCount = getSubsystemDefCount();

		for(int i = 0; i < subsysCount; ++i) {
			const SubsystemDef@ def = getSubsystemDef(i);
			if(!playerEmpire.isUnlocked(def))
				continue;
			if(editor.design !is null && !def.canUseOn(editor.design.hull))
				continue;
			if(def.isHull)
				continue;

			//Find selector
			string cat;
			if(def.hasTag(ST_Category))
				cat = def.getTagValue(ST_Category);
			if(cat.length == 0)
				cat = "Misc";

			SubsystemSelector@ sel;
			for(uint n = 0, ncnt = selectors.length; n < ncnt; ++n) {
				if(selectors[n].category == cat) {
					@sel = selectors[n];
					break;
				}
			}
			if(sel is null) {
				@sel = SubsystemSelector(this, cat);
				selectors.insertAt(selectors.length-1, sel);
			}

			//Add to selector
			sel.subsystems.insertLast(i);

			//Add modules
			for(uint n = 0, ncnt = def.moduleCount; n < ncnt; ++n) {
				auto@ mod = def.modules[n];
				if(mod is def.coreModule || mod is def.defaultModule)
					continue;
				if(!playerEmpire.isUnlocked(def, mod))
					continue;

				bool have = false;
				if(haveModifiers.get(mod.id, have)) {
					if(have)
						continue;
				}

				have = true;
				haveModifiers.set(mod.id, have);

				modifiers.subsystems.insertLast(i);
				modifiers.modules.insertLast(n);
			}
		}

		MarkupTooltip tt(350, 0.f, true, false);
		tt.StaticPosition = true;
		tt.offset = vec2i(256, 158);
		tt.LazyUpdate = false;
		tt.Padding = 10;

		syslist.clearSections();
		for(uint i = 0, cnt = selectors.length; i < cnt; ++i) {
			if(selectors[i].subsystems.length == 0) {
				selectors[i].remove();
				continue;
			}

			@selectors[i].tooltipObject = tt;
			GuiPanel panel(syslist, recti());
			@selectors[i].parent = panel;
			selectors[i].size = vec2i(syslist.size.width, 100);
			selectors[i].visible = true;

			GuiButton header(syslist, recti(0,0,100,40));
			header.style = SS_AccordionHeader;

			GuiMarkupText text(header, Alignment().padded(10, 4));
			text.defaultFont = FT_Subtitle;
			string txt = localize("#SC_"+selectors[i].category);
			if(txt[0] == '#')
				txt = selectors[i].category;
			text.text = txt;

			syslist.addSection_r(header, panel);
		}
		if(syslist.sectionCount > 0)
			syslist.openSection(0);
		syslist.updateAbsolutePosition();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is display) {
			vec2u hex(display.hexHovered.x, display.hexHovered.y);
			switch(event.type) {
				case MET_Button_Down: {
					//Ignore presses outside of bounds
					if(display.hexHovered.x < 0 || display.hexHovered.y < 0)
						return BaseGuiElement::onMouseEvent(event, source);

					if(event.button == 0) {
						if(altKey) {
							@prevTool = paintTool;
							@activeTool = dropTool;
						}
						else if(activeTool is paintTool) {
							HexData@ hdata = editor.data.hex[vec2u(display.hexHovered)];

							if(hdata.subsystem != -1) {
								SubsystemData@ sdata = editor.data.subsystems[hdata.subsystem];
								if(hdata.module != sdata.def.defaultModule.index) {
									switchTool(moveTool);
									@prevTool = paintTool;
								}
							}
						}
					}
					else if(event.button == 2) {
						SubsystemData@ sdata = editor.data.subsystem[hex];
						if(sdata !is null) {
							int moduleId = -1;
							int sysId = sdata.sysId;
							if(sysId != -1) {
								auto@ def = sdata.def;
								int mod = editor.data.hex[hex].module;
								if(mod != -1 && (def.coreModule is null || mod != def.coreModule.index) && mod != def.defaultModule.index)
									moduleId = mod;
							}
							switchBrush(sysId, moduleId);
						}
					}

					int mask = 1 << event.button;
					activeTool.grab(editor.data, vec2u(display.hexHovered), mask);
					pressed |= mask;
					editor.updateDesign();
				} return true;
				case MET_Button_Up: {
					if(displayPanel.horiz.Dragging || displayPanel.vert.Dragging)
						return BaseGuiElement::onMouseEvent(event, source);
					int mask = 1 << event.button;
					bool skipprev = false;
					if(display.hexHovered.x < 0 || display.hexHovered.y < 0) {
						activeTool.cancel(editor.data, mask);
					}
					else {
						activeTool.release(editor.data, vec2u(display.hexHovered), mask);
						if(activeTool is dropTool)
							switchBrush(dropTool.sysId, dropTool.moduleId);
					}
					if(!skipprev && prevTool !is null) {
						switchTool(prevTool);
						@prevTool = null;
					}
					editor.updateDesign();
					pressed &= ~mask;
				} return true;
				case MET_Scrolled: {
					int amount = event.y;

					//Ignore presses outside of bounds
					if(display.hexHovered.x < 0 || display.hexHovered.y < 0)
						return BaseGuiElement::onMouseEvent(event, source);

					if(activeTool.scroll(editor.data, vec2u(display.hexHovered), amount))
						editor.updateDesign();
				} return true;
				case MET_Moved: {
					if(statsPopup.visible)
						updateStatsPos();
				};
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void updateStatsPos() {
		vec2i center = display.absolutePosition.center;
		vec2i pos;
		if(statsPanel.size.height - globalStats.size.height - 30 > statsPopup.size.height) {
			pos.x = statsPanel.rect.topLeft.x;
			pos.y = statsPanel.rect.topLeft.y + globalStats.size.height + 30;
			globalStats.visible = true;
		}
		else {
			pos.x = statsPanel.rect.topLeft.x;
			pos.y = statsPanel.rect.topLeft.y;
			globalStats.visible = false;
		}
		statsPopup.position = pos;
	}

	void clearBrush() {
		@paintTool.def = null;
		@replaceTool.def = null;
	}

	void switchBrush(int sysId, int modId = -1) {
		if(sysId == -1) {
			@paintTool.def = null;
			@replaceTool.def = null;
			@moduleTool.mod = null;
			if(prevTool is moduleTool)
				@prevTool = paintTool;
			return;
		}

		const SubsystemDef@ def = getSubsystemDef(sysId);
		if(modId != -1) {
			auto@ module = def.modules[modId];
			if(moduleTool.mod !is module) {
				@moduleTool.mod = module;
				uint index = 0;
				for(uint i = 0, cnt = selectors.length; i < cnt; ++i) {
					if(selectors[i].contains(module)) {
						syslist.openSection(index, snap=false);
						break;
					}
					if(selectors[i].visible)
						++index;
				}
			}

			@paintTool.def = null;
			@replaceTool.def = null;
			if(prevTool !is moduleTool)
				@prevTool = moduleTool;
		}
		else {
			if(paintTool.def !is def) {
				@paintTool.def = def;
				@replaceTool.def = def;
				uint index = 0;
				for(uint i = 0, cnt = selectors.length; i < cnt; ++i) {
					if(selectors[i].contains(def)) {
						syslist.openSection(index, snap=false);
						break;
					}
					if(selectors[i].visible)
						++index;
				}
			}
			if(prevTool !is paintTool && prevTool !is replaceTool)
				@prevTool = paintTool;
		}
	}

	void switchTool(Tool@ tool) {
		paintButton.pressed = tool is paintTool;
		moveButton.pressed = tool is moveTool;
		dropButton.pressed = tool is dropTool;
		replaceButton.pressed = tool is replaceTool;

		@activeTool = tool;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is display) {
			switch(event.type) {
				case GUI_Clicked:
					return true;

				case GUI_Hover_Changed:
					//Do hover stats
					updateHexStats(display.hexHovered);

					//Do painting
					if(pressed != 0) {
						if(display.hexHovered.x < 0 || display.hexHovered.y < 0)
							return true;
						activeTool.hover(editor.data, vec2u(display.hexHovered), pressed);
						editor.updateDesign();
					}
					else {
						if(display.hexHovered.x < 0 || display.hexHovered.y < 0)
							return true;
						activeTool.hover(editor.data, vec2u(display.hexHovered), 0);
					}
				break;
			}
		}
		else if(cast<SubsystemSelector>(event.caller) !is null) {
			auto@ sel = cast<SubsystemSelector>(event.caller);
			switch(event.type) {
				case GUI_Changed:
					if(sel.hovered != -1) {
						auto@ def = getSubsystemDef(sel.subsystems[sel.hovered]);
						if(!def.isApplied) {
							if(uint(sel.hovered) >= sel.modules.length) {
								if(activeTool !is replaceTool)
									switchTool(paintTool);
								@paintTool.def = def;
								@replaceTool.def = def;
							}
							else {
								auto@ mod = def.modules[sel.modules[sel.hovered]];
								@moduleTool.mod = mod;
								switchTool(moduleTool);
							}
						}
					}
				break;
				case GUI_Confirmed:
					if(sel.hovered != -1) {
						auto@ def = getSubsystemDef(sel.subsystems[sel.hovered]);
						if(def.isApplied) {
							if(editor.data.appliedSubsystems.find(def) == -1) {
								bool grouped = false;
								for(uint i = 0, cnt = editor.data.appliedSubsystems.length; i < cnt; ++i) {
									auto@ other = editor.data.appliedSubsystems[i];
									for(uint n = 0, ncnt = def.getTagValueCount(ST_Applied); n < ncnt; ++n) {
										if(other.hasTagValue(ST_Applied, def.getTagValue(ST_Applied, n))) {
											grouped = true;
											editor.data.startGroup();
											editor.data.act(RemoveAppliedSubsystem(other));
										}
									}
								}
								editor.data.act(ApplySubsystem(def));
								if(grouped)
									editor.data.endGroup();
							}
							else {
								editor.data.act(RemoveAppliedSubsystem(def));
							}
							editor.updateDesign();
							editor.updateAbsolutePosition();
						}
					}
				break;
			}
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is arcButton) {
				SHOW_ARC_UNDERLAY = arcButton.pressed;
				return true;
			}
			else if(event.caller is hullButton) {
				SHOW_HULL_UNDERLAY = hullButton.pressed;
				return true;
			}
			else if(event.caller is centerButton) {
				editor.construction.centerDesign();
				return true;
			}
			else if(event.caller is randomButton) {
				editor.construction.randomizeDesign();
				return true;
			}
			else if(event.caller is configButton) {
				randomConfig.prompt(this, editor.design);
				return true;
			}
			else if(event.caller is undoButton) {
				editor.data.undo();
				editor.updateDesign();
				return true;
			}
			else if(event.caller is redoButton) {
				editor.data.redo();
				editor.updateDesign();
				return true;
			}
			else if(event.caller is paintButton) {
				switchTool(paintTool);
			}
			else if(event.caller is replaceButton) {
				switchTool(replaceTool);
			}
			else if(event.caller is moveButton) {
				switchTool(moveTool);
			}
			else if(event.caller is dropButton) {
				switchTool(dropTool);
			}
			else if(event.caller is clearButton) {
				clearDesign();
			}
		}
		if(event.caller is hullList && event.type == GUI_Changed) {
			editor.updateDesign();
			if(!SHOW_HULL_UNDERLAY && hullList.selected != 0) {
				SHOW_HULL_UNDERLAY = true;
				hullButton.pressed = true;
			}
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void fillDesign(const Design@ design, bool group = true) {
		if(group)
			editor.data.startGroup();

		for(uint i = 0, cnt = design.subsystemCount; i < cnt; ++i) {
			auto@ sys = design.subsystems[i];
			if(sys.type.isHull)
				continue;

			editor.data.act(CreateSubsystemAction(sys.type, sys.core, sys.direction));
			for(uint j = 0, jcnt = sys.hexCount; j < jcnt; ++j) {
				vec2u pos = sys.hexagon(j);

				HexData hdat;
				hdat.subsystem = i;
				hdat.module = sys.module(j).index;
				editor.data.act(PaintAction(pos, hdat));
			}
		}

		if(group) {
			editor.data.endGroup();
			editor.updateDesign();
		}
	}

	void clearDesign(bool group = true) {
		if(group)
			editor.data.startGroup();

		for(int i = editor.data.subsystems.length - 1; i >= 0; --i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			for(int j = sdata.hexes.length - 1; j >= 0; --j)
				editor.data.act(ClearAction(sdata.hexes[j]));
			editor.data.act(RemoveSubsystemAction(i));
		}

		if(group) {
			editor.data.endGroup();
			editor.updateDesign();
		}
	}

	void randomizeDesign(bool group = true) {
		auto type = DT_Flagship;
		auto ttag = editor.concept.getSelectedTypeTag();
		if(ttag == "Support")
			type = DT_Support;
		else if(ttag == "Station")
			type = DT_Station;
		else if(ttag == "Satellite")
			type = DT_Satellite;

		double t = getExactTime();

		//Designer rnd;
		//rnd.prepare(type, editor.data.size, playerEmpire, "");
		//randomConfig.apply(rnd);
		//const Design@ dsg = rnd.design();

		const Design@ dsg = createRandomDesign(type, editor.data.size, playerEmpire);
		if(dsg is null)
			return;

		print("design: "+(getExactTime()-t)*1000.0+"ms");

		if(group)
			editor.data.startGroup();

		clearDesign(group=false);
		fillDesign(dsg, group=false);

		if(editor.concept.nameBox.text.length == 0)
			editor.concept.nameBox.text = dsg.name;

		if(group) {
			editor.data.endGroup();
			editor.updateDesign();
		}
	}

	void clearInvalid(bool group = true) {
		if(group)
			editor.data.startGroup();

		string tagName = editor.concept.getSelectedTypeTag()+"Hull";
		for(int i = editor.data.subsystems.length - 1; i >= 0; --i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			if(sdata.def.hasTag(tagName))
				continue;
			for(int j = sdata.hexes.length - 1; j >= 0; --j)
				editor.data.act(ClearAction(sdata.hexes[j]));
			editor.data.act(RemoveSubsystemAction(i));
		}

		if(group) {
			editor.data.endGroup();
			editor.updateDesign();
		}
	}

	vec2i getCenterOffset(vec2i gridSize) {
		vec2d minPos(gridSize), maxPos(0, 0);
		for(int i = editor.data.subsystems.length - 1; i >= 0; --i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			for(int j = sdata.hexes.length - 1; j >= 0; --j) {
				auto hex = getHexPosition(sdata.hexes[j]);
				if(hex.x < minPos.x)
					minPos.x = hex.x;
				if(hex.y < minPos.y)
					minPos.y = hex.y;
				if(hex.x > maxPos.x)
					maxPos.x = hex.x;
				if(hex.y > maxPos.y)
					maxPos.y = hex.y;
			}
		}

		vec2d pSize = maxPos - minPos;
		if(pSize.x <= 0 || pSize.y <= 0)
			return vec2i();

		vec2d shift = (vec2d(gridSize.x*0.75, gridSize.y) - pSize) / 2 - minPos;
		shift.x /= 0.75;

		vec2i offset = vec2i(shift);
		if(offset.x % 2 != 0)
			offset.x -= 1;
		return offset;
	}

	void centerDesign(bool group = true) {
		if(group)
			editor.data.startGroup();

		array<Action@> acts;

		//Find the offsets
		vec2i offset = getCenterOffset(editor.data.gridSize);

		//Cache the new stuff
		for(uint i = 0, cnt = editor.data.subsystems.length; i < cnt; ++i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			acts.insertLast(CreateSubsystemAction(sdata.def, sdata.core, direction=sdata.direction));
			for(int j = sdata.hexes.length - 1; j >= 0; --j) {
				auto hex = sdata.hexes[j];
				auto@ hdat = editor.data.hex[hex];
				if(hdat !is null)
					acts.insertLast(PaintAction(vec2u(vec2i(hex) + offset), hdat));
			}
		}

		//Clear old stuff
		clearDesign(false);

		//Apply new stuff
		for(uint i = 0, cnt = acts.length; i < cnt; ++i)
			editor.data.act(acts[i]);

		if(group) {
			editor.data.endGroup();
			editor.updateDesign(true);
		}
	}

	void changeSize(double newSize, bool group = true) {
		editor.data.act(SizeChangeAction(editor.data.size, newSize));
		editor.updateDesign(true);
		editor.updateAbsolutePosition();
	}

	void changeGrid(vec2i newGrid, bool group = true) {
		if(group)
			editor.data.startGroup();

		array<Action@> acts;
		vec2i oldGrid = editor.data.gridSize;

		//Find the offset
		vec2d minPos(oldGrid), maxPos(0, 0);
		for(int i = editor.data.subsystems.length - 1; i >= 0; --i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			for(int j = sdata.hexes.length - 1; j >= 0; --j) {
				auto hex = getHexPosition(sdata.hexes[j]);
				if(hex.x < minPos.x)
					minPos.x = hex.x;
				if(hex.y < minPos.y)
					minPos.y = hex.y;
				if(hex.x > maxPos.x)
					maxPos.x = hex.x;
				if(hex.y > maxPos.y)
					maxPos.y = hex.y;
			}
		}

		vec2d shift = (vec2d(newGrid.x*0.75, newGrid.y) - vec2d(oldGrid.x*0.75, oldGrid.y)) / 2;
		shift.x = clamp(shift.x, 1.0 - minPos.x, double(newGrid.x)*0.75 - maxPos.x - 1);
		shift.y = clamp(shift.y, 1.0 - minPos.y, newGrid.y - maxPos.y - 1);
		shift.x /= 0.75;

		vec2i offset = vec2i(shift);
		if(offset.x % 2 != 0)
			offset.x -= 1;

		//Cache the new stuff
		for(uint i = 0, cnt = editor.data.subsystems.length; i < cnt; ++i) {
			SubsystemData@ sdata = editor.data.subsystems[i];
			acts.insertLast(CreateSubsystemAction(sdata.def, sdata.core, direction=sdata.direction));
			bool haveHexes = false;
			for(int j = sdata.hexes.length - 1; j >= 0; --j) {
				auto hex = sdata.hexes[j];
				auto@ hdat = editor.data.hex[hex];

				vec2u newhex = vec2u(vec2i(hex) + offset);
				if(hdat !is null && newhex.x < uint(newGrid.x) && newhex.y < uint(newGrid.y)) {
					acts.insertLast(PaintAction(newhex, hdat));
					haveHexes = true;
				}
			}
			if(!haveHexes)
				acts.removeLast();
		}

		//Clear and resize
		clearDesign(false);
		editor.data.act(GridChangeAction(vec2u(oldGrid), vec2u(newGrid)));

		//Apply new stuff
		for(uint i = 0, cnt = acts.length; i < cnt; ++i)
			editor.data.act(acts[i]);

		if(group) {
			editor.data.endGroup();
			editor.updateDesign(true);
			editor.updateAbsolutePosition();
		}
	}

	vec2i drawError(const vec2i& pos, DesignError@ err) {
		const Font@ fnt = skin.getFont(FT_Normal);
		vec2i textSize = fnt.getDimension(err.text);
		int width = textSize.x + 80;

		Color col = warningColor;
		if(err.fatal)
			col = errorColor;

		skin.draw(SS_Panel, SF_Normal, recti_area(pos, vec2i(width, 20)), col);
		fnt.draw(pos + vec2i(5, 2), err.fatal ? locale::ERROR : locale::WARNING);
		fnt.draw(pos + vec2i(75, 2), err.text);

		return vec2i(width, 20);
	}

	void draw() {
		vec2i topLeft = AbsolutePosition.topLeft;
		vec2i botRight = AbsolutePosition.botRight;

		////Filter bar
		//skin.draw(SS_LightPanel, SF_Normal, recti(
		//	topLeft, vec2i(botRight.x, topLeft.y + 28)));

		////Cost bar
		//skin.draw(SS_LightPanel, SF_Normal, recti(
		//	vec2i(botRight.x - 700, topLeft.y),
		//	vec2i(botRight.x, topLeft.y + 28)));

		//Subsystem bar
		skin.draw(SS_PlainBox, SF_Normal, syslist.absolutePosition.padded(0,-8));

		skin.draw(SS_PlainBox, SF_Normal, recti(
			botRight.x-688-36-36-60, topLeft.y-2,
			botRight.x-250, topLeft.y+35));

		//Stat bar
		skin.draw(SS_PlainBox, SF_Normal, recti(
			vec2i(botRight.x - 258, topLeft.y),
			vec2i(botRight.x - 4, botRight.y + 4)));

		//Firing arcs
		if(SHOW_ARC_UNDERLAY) {
			for(uint i = 0, cnt = editor.design.subsystemCount; i < cnt; ++i) {
				auto@ sys = editor.design.subsystems[i];
				if(sys.type.hasTag(ST_Rotatable) && sys.effectorCount != 0)
					display.drawFireArc(sys.core, 0.35f);
			}
		}
		display.displayHull = SHOW_HULL_UNDERLAY;
		display.displayHullWeights = SHOW_HULL_WEIGHTS;
		hullList.visible = SHOW_HULL_UNDERLAY || hullList.selected != 0;

		BaseGuiElement::draw();
		clearClip();

		uint errCnt = editor.design.errorCount;

		//Draw error list
		vec2i pos(topLeft.x + 271, topLeft.y+20);
		DesignError@ hovErr = null;
		for(uint i = 0; i < errCnt; ++i) {
			DesignError@ err = editor.design.errors[i];

			Color col = Color(0xff8000ff);
			if(err.fatal)
				col = colors::Red;

			skin.getFont(FT_Subtitle).draw(pos=recti_area(pos, vec2i(size.width-500, 64)),
					text=err.text, horizAlign=0.0, vertAlign=0.5,
					color=col, stroke=colors::Black);

			pos.y += 30;
		}

		//TODO:Draw the borders for errors
		//for(uint i = 0; i < errCnt; ++i) {
			//DesignError@ err = editor.design.errors[i];

			////Use the correct color for the warning/error
			//Color col = warningColor;
			//if(err is hovErr)
				//col = Color(0xffff00ff);
			//else if(err.fatal)
				//col = errorColor;

			////Display subsystem errors
			//if(err.subsys !is null) {
				//display.drawSubsystemBorder(err.subsys, col, 4.0);
			//}

			////Display hex errors
			//if(err.hex.x >= 0 && err.hex.y >= 0) {
				//display.drawHexBorder(vec2u(err.hex), col, 6.0);
			//}
		//}

		//Draw hovered error
		if(display.hexHovered.x >= 0 && display.hexHovered.y >= 0) {
			vec2u hov(display.hexHovered);
			const Subsystem@ hovSys = editor.design.subsystem(hov);

			vec2i pos = mousePos + vec2i(32, 0);
			for(uint i = 0; i < errCnt; ++i) {
				DesignError@ err = editor.design.errors[i];

				if((hovSys is null || err.subsys !is hovSys) && err.hex != display.hexHovered)
					continue;

				vec2i size = drawError(pos, err);
				pos.y += size.height + 4;
			}
		}

		//Draw tool
		activeTool.draw(editor.data, editor);
	}
};
/** }}} */
/** Concept page {{{*/
class Concept : BaseGuiElement {
	DesignEditor@ editor;
	bool finalized = true;

	GuiText@ nameLabel;
	GuiTextbox@ nameBox;

	GuiDropdown@ typeBox;

	GuiText@ sizeLabel;
	GuiTextbox@ sizeBox;
	bool autoSize = false;

	GuiText@ classLabel;
	GuiDropdown@ classBox;

	GuiSprite@ moneyIcon;
	GuiText@ moneyValue;

	GuiSprite@ laborIcon;
	GuiText@ laborValue;

	GuiButton@ roleButton;
	GuiMarkupText@ roleText;

	GuiSkinElement@ roleBox;
	GuiPanel@ rolePanel;
	array<GuiButton@> roleChoice;
	GuiDropdown@ rangeChoice;

	DesignSettings settings;

	Concept(DesignEditor@ ed, Alignment@ align) {
		@editor = ed;
		super(editor, align);
		updateAbsolutePosition();

		@nameBox = GuiTextbox(this, Alignment(Left+145, Top+8, Left+500, Height=30));
		nameBox.font = FT_Subtitle;
		nameBox.tabIndex = 1;
		nameBox.emptyText = locale::DSG_INSERT_NAME;

		nameBox.setFilenameLimit();

		@typeBox = GuiDropdown(this, Alignment(Left+145, Top+44, Left+322, Height=30));
		typeBox.addItem(GuiListText(locale::DESIGN_FLAGSHIP, Sprite(spritesheet::AttributeIcons, 1, Color(0x00e5f7ff))));
		typeBox.addItem(GuiListText(locale::DESIGN_SUPPORT, icons::ManageSupports));
		typeBox.addItem(GuiListText(locale::DESIGN_STATION, Sprite(spritesheet::GuiOrbitalIcons, 0, Color(0x00e5f7ff))));
		if(hasDLC("Heralds"))
			typeBox.addItem(GuiListText(locale::DESIGN_SATELLITE, Sprite(spritesheet::GuiOrbitalIcons, 14, Color(0xe759ffff))));

		@sizeLabel = GuiText(this, Alignment(Left+330, Top+44, Left+370, Height=30),
				locale::DESIGN_SIZE_INPUT);

		@sizeBox = GuiTextbox(this, Alignment(Left+370, Top+44, Left+500, Height=30));
		sizeBox.font = FT_Subtitle;
		sizeBox.tabIndex = 2;

		@classLabel = GuiText(this, Alignment(Right-436, Top+9, Width=52, Height=30),
				locale::DESIGN_CLASS_INPUT);

		@classBox = GuiDropdown(this, Alignment(Right-436+52, Top+8, Right-140, Height=30));
		classBox.font = FT_Subtitle;
		classBox.tabIndex = 3;

		@moneyIcon = GuiSprite(this, Alignment(Right-732-20, Top+42, Width=30, Height=30), icons::Money);
		@moneyValue = GuiText(this, Alignment(Right-692-20, Top+44, Width=110, Height=28));

		@laborIcon = GuiSprite(this, Alignment(Right-582-20, Top+42, Width=30, Height=30), icons::Labor);
		@laborValue = GuiText(this, Alignment(Right-542-20, Top+44, Width=60, Height=28));

		@roleButton = GuiButton(this, recti_area(vec2i(512, 8), vec2i(270, 66)));
		roleButton.style = SS_AccordionHeader;
		@roleText = GuiMarkupText(roleButton, Alignment().padded(8, 3));

		@roleBox = GuiSkinElement(this, Alignment(Left+512-250, Top+74, Width=(270+500), Height=325), SS_Panel);
		roleBox.visible = false;
		roleBox.noClip = true;

		@rolePanel = GuiPanel(roleBox, Alignment(Left+4, Top+4, Right-4, Bottom-40));
		for(uint i = 0; i < SG_COUNT; ++i) {
			GuiButton btn(rolePanel, recti_area(6+(i%2)*380, 4+(i/2)*92, 370, 88));
			btn.style = SS_AccordionHeader;
			GuiMarkupText txt(btn, Alignment().padded(8, 3));
			roleChoice.insertLast(btn);

			string roleName = SUPPORT_BEHAVIOR_NAMES[clamp(i, 0, SUPPORT_BEHAVIOR_NAMES.length-1)];
			Sprite roleIcon = SUPPORT_BEHAVIOR_ICONS[clamp(i, 0, SUPPORT_BEHAVIOR_ICONS.length-1)];
			txt.text = format("[img=$1;42][font=Subtitle]$2[/font]\n[i][color=#aaa]$3[/color][/i][/img]",
					getSpriteDesc(roleIcon), localize("#BEH_"+roleName), localize("#BEH_"+roleName+"_DESC"));
		}

		GuiText rangeLabel(roleBox, Alignment(Left+0.5f-200, Bottom-40, Left+0.5f, Bottom-12));
		rangeLabel.text = locale::SUPPORT_RANGE;

		@rangeChoice = GuiDropdown(roleBox, Alignment(Left+0.5f, Bottom-40, Left+0.5f+200, Bottom-12));
		rangeChoice.addItem(locale::RANGE_Auto);
		rangeChoice.addItem(locale::RANGE_Far);
		rangeChoice.addItem(locale::RANGE_Close);
	}

	void updateAbsolutePosition() {
		if(roleButton !is null) {
			if(size.width >= 1600)
				roleButton.size = vec2i(270, 66);
			else
				roleButton.size = vec2i(270, 30);
		}
		BaseGuiElement::updateAbsolutePosition();
	}

	bool get_ready() {
		if(nameBox.text.length == 0)
			return false;
		return true;
	}

	string getSelectedTypeTag() {
		switch(typeBox.selected) {
			case 0: return "Flagship";
			case 1: return "Support";
			case 2: return "Station";
			case 3: return "Satellite";
		}
		return "Flagship";
	}

	void load(const Design@ dsg) {
		update();

		nameBox.text = dsg.name;
		sizeBox.text = toString(dsg.size, 0);

		if(dsg.hull.hasTag("Support"))
			typeBox.selected = 1;
		else if(dsg.hull.hasTag("Satellite")) {
			if(typeBox.itemCount < 4)
				typeBox.selected = 1;
			else
				typeBox.selected = 3;
		}
		else if(dsg.hull.hasTag("Station"))
			typeBox.selected = 2;
		else
			typeBox.selected = 0;

		for(uint i = 0, cnt = classBox.itemCount; i < cnt; ++i) {
			if(playerEmpire.getDesignClass(i) is editor.targetClass) {
				classBox.selected = i;
				break;
			}
		}

		if(dsg.settings !is null)
			settings = cast<const DesignSettings>(dsg.settings);
		else
			settings = DesignSettings();
	}

	void generateDesign(DesignDescriptor& desc, bool checkHull = false) {
		desc.name = nameBox.text;

		//Find the most appropriate hull
		auto@ elem = cast<HullElement>(editor.construction.hullList.selectedItem);
		if(elem is null) {
			desc.forceHull = false;
			editor.data.forceHull = false;
			string hullTag = getSelectedTypeTag();
			if(desc.hull is null || checkHull || SHOW_HULL_UNDERLAY || hullTag != getHullTypeTag(desc.hull)) {
				@desc.hull = editor.data.hull;
				@desc.hull = getBestHull(desc, hullTag);
				@editor.data.hull = desc.hull;
			}
		}
		else {
			desc.forceHull = true;
			editor.data.forceHull = true;
			@editor.data.hull = elem.hull;
			@desc.hull = elem.hull;
		}
	}

	void update() {
		//Update classes
		uint cnt = playerEmpire.designClassCount;
		if(classBox.itemCount != cnt) {
			classBox.clearItems();
			classBox.selected = 0;
			for(uint i = 0; i < cnt; ++i) {
				const DesignClass@ cls = playerEmpire.getDesignClass(i);
				classBox.addItem(cls.name);
				if(cls is editor.targetClass)
					classBox.selected = i;
			}
		}

		//Size box validity
		sizeBox.text = toString(editor.data.size, 0);
		if(editor.data.size < editor.data.hull.minSize-0.001 || (editor.data.size > editor.data.hull.maxSize+0.001 && editor.data.hull.maxSize > 0))
			sizeBox.bgColor = colors::Red;
		else
			sizeBox.bgColor = colors::White;

		//Update cost
		int buildCost = 0;
		int maintainCost = 0;
		double laborCost = 0;
		getBuildCost(editor.design, buildCost, maintainCost, laborCost);

		moneyValue.text = formatMoney(buildCost, maintainCost);
		laborValue.text = standardize(laborCost, true);

		roleButton.visible = editor.design.hasTag(ST_Support);
		string roleName = SUPPORT_BEHAVIOR_NAMES[clamp(settings.behavior, 0, SUPPORT_BEHAVIOR_NAMES.length-1)];
		Sprite roleIcon = SUPPORT_BEHAVIOR_ICONS[clamp(settings.behavior, 0, SUPPORT_BEHAVIOR_ICONS.length-1)];
		if(size.width >= 1600) {
			roleText.text = format("[img=$1;$4][vspace=$5]$3:\n[offset=15][font=Subtitle][b]$2[/b][/font][/offset][/vspace][/img]", getSpriteDesc(roleIcon), localize("#BEH_"+roleName), locale::SUPPORT_BEH,
					toString(roleButton.size.height-6), toString(max((roleButton.size.height-50)/2, 0)));
		}
		else {
			roleText.text = format("[img=$1;$4][vspace=$5][vspace=4]$3:[/vspace] [font=Subtitle][b]$2[/b][/font][/vspace][/img]", getSpriteDesc(roleIcon), localize("#BEH_"+roleName), locale::SUPPORT_BEH,
					toString(roleButton.size.height-6), toString(max((roleButton.size.height-36)/2, 0)));
		}
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Changed) {
			if(event.caller is typeBox) {
				if(!editor.design.hull.hasTag(getSelectedTypeTag())) {
					editor.construction.clearInvalid();
					editor.construction.clearBrush();
				}
				editor.data.forceHull = false;
				editor.construction.hullList.selected = 0;
				editor.updateDesign(checkHull=true);
				editor.construction.updateHullList();
			}
			else if(event.caller is classBox) {
				string value = classBox.getItem(classBox.selected);
				const DesignClass@ cls = playerEmpire.getDesignClass(value, false);
				if(cls !is null)
					@editor.targetClass = cls;
				editor.updateDesign();
			}
			else if(event.caller is nameBox) {
				editor.updateDesign();
			}
			else if(event.caller is rangeChoice) {
				settings.range = uint(rangeChoice.selected);
				update();
				setGuiFocus(roleBox);
			}
			return true;
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is roleButton) {
				roleBox.visible = !roleBox.visible;
				if(roleBox.visible)
					setGuiFocus(roleBox);
				return true;
			}
			for(uint i = 0, cnt = roleChoice.length; i < cnt; ++i) {
				if(event.caller is roleChoice[i]) {
					settings.behavior = i;
					roleBox.visible = false;
					update();
					return true;
				}
			}
		}
		else if(roleBox.visible && event.type == GUI_Focus_Lost && !roleBox.isAncestorOf(event.other)) {
			if(roleButton.isAncestorOf(event.other) || event.other is rangeChoice.list || event.other is gui_root)
				return false;
			roleBox.visible = false;
			return false;
		}
		else if(roleBox.visible && event.type == GUI_Focused && !roleBox.isAncestorOf(event.caller)) {
			if(roleButton.isAncestorOf(event.caller) || event.caller is rangeChoice.list || event.caller is gui_root)
				return false;
			roleBox.visible = false;
			return false;
		}
		else if(event.type == GUI_Confirmed || event.type == GUI_Focus_Lost) {
			if(event.caller is sizeBox) {
				autoSize = false;
				double size = max(floor(toDouble(sizeBox.text)), 1.0);
				if(size != editor.data.size)
					editor.construction.changeSize(size);
			}
			else if(event.caller is nameBox) {
				editor.updateDesign();
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		BaseGuiElement::draw();
	}
};
/** }}} */
/** Editor {{{*/
class DesignEditor : Tab {
	const Design@ originalDesign;
	const Design@ design;
	const DesignClass@ targetClass;

	DesignData data;

	GuiButton@ duplicateButton;
	GuiButton@ exportButton;
	GuiButton@ saveButton;
	GuiButton@ backButton;

	Construction@ construction;
	Concept@ concept;

	DesignEditor() {
		super();
		//Set the keybind group to use
		@keybinds = keybinds::DesignEditor;

		//Create the subpanels
		@concept = Concept(this, Alignment(Left, Top, Right, Top+78));
		@construction = Construction(this, Alignment(Left, Top+78, Right, Bottom));
		concept.bringToFront();

		//Create the global buttons
		@backButton = GuiButton(this, Alignment(Left+4, Top+10, Left+134, Height=60),
				locale::BACK);
		backButton.buttonIcon = icons::Back;

		@duplicateButton = GuiButton(this, Alignment(Right-436, Top+43, Right-292, Height=30),
				locale::DUPLICATE_DESIGN);
		duplicateButton.buttonIcon = icons::Forward;
		duplicateButton.color = Color(0xeeeeeeff);

		@exportButton = GuiButton(this, Alignment(Right-288, Top+43, Right-140, Height=30),
				locale::EXPORT_DESIGN);
		exportButton.buttonIcon = icons::Export;
		exportButton.color = Color(0xeeeeeeff);

		@saveButton = GuiButton(this, Alignment(Right-134, Top+10, Right-4, Height=60),
				locale::SAVE);
		saveButton.buttonIcon = icons::Save;
		saveButton.font = FT_Bold;
		saveButton.color = Color(0x88ff88ff);
	}

	Color get_activeColor() {
		return Color(0x83cfffff);
	}

	Color get_inactiveColor() {
		return Color(0x009cffff);
	}

	Color get_seperatorColor() {
		return Color(0x49738dff);
	}		

	TabCategory get_category() {
		return TC_Designs;
	}

	Sprite get_icon() {
		return Sprite(material::TabDesigns);
	}

	void show() {
		concept.update();
		Tab::show();
	}

	void close() {
		data.clear();
		Tab::close();
	}

	void showDesignOverview() {
		//Overview should be kept in previous
		if(previous is null)
			@previous = createDesignOverviewTab();
		if(previous.category != TC_Designs) {
			popTab(this);
		}
		else {
			browseTab(this, previous, true);
			data.clear();
		}
	}

	void duplicate() {
		if(originalDesign is null)
			return;

		concept.nameBox.text = uniqueDesignName(concept.nameBox.text, playerEmpire);
		@originalDesign = null;
		updateDesign();

		concept.nameBox.focus(true);
	}

	void loadDesign(const Design@ dsg, bool isOriginal = true) {
		//Display this design
		if(isOriginal && dsg.used && dsg.owner is playerEmpire)
			@originalDesign = dsg;
		else
			@originalDesign = null;

		if(isOriginal || dsg.cls !is null) {
			@targetClass = dsg.cls;
			if(targetClass is null)
				@targetClass = playerEmpire.getDesignClass(0);
		}

		title = dsg.name;
		@design = dsg;
		if(construction.display.hull !is dsg.hull) {
			@construction.display.hull = dsg.hull;
			updateAbsolutePosition();
		}
		construction.updateSubsystems();
		@construction.display.design = dsg;

		data.load(dsg);
		concept.load(dsg);
		construction.updateHullList();

		construction.update();
		concept.update();
		updateProgress();
		construction.clearBrush();
	}

	void loadDesign(const Hull@ hull, const DesignClass@ cls, const string& name, uint size) {
		if(hull is null) {
			if(cls !is null && cls.designCount != 0) {
				ReadLock lock(playerEmpire.designMutex);
				auto@ tDsg = cls.designs[0];
				@hull = tDsg.hull;
			}
			else if(playerEmpire.shipset is null)
				@hull = getHullDefinition(0);
			else
				@hull = playerEmpire.shipset.hulls[0];
		}
		if(cls is null)
			@cls = playerEmpire.getDesignClass(0);
		if(size < 1)
			size = 1;
		if(size < uint(hull.minSize))
			size = hull.minSize;
		@targetClass = cls;

		DesignDescriptor desc;
		@desc.hull = hull;
		desc.size = size;
		desc.gridSize = getDesignGridSize(desc.hull, desc.size);
		desc.name = name;
		title = name.length != 0 ? name : locale::CREATE_DESIGN;

		const Design@ dsg = makeDesign(desc);
		vec2u targGrid = getTargetGridSize(dsg);
		if(targGrid != vec2u(dsg.hull.gridSize)) {
			desc.gridSize = targGrid;
			@dsg = makeDesign(desc);
		}

		loadDesign(makeDesign(desc), false);
		construction.clearBrush();
		
		concept.autoSize = true;
		concept.nameBox.focus(true);
		construction.updateSubsystems();
	}

	void saveDesign() {
		const Design@ newDesign = generateDesign(checkHull=true);
		newDesign.setSettings(getDesignSettings());

		bool success = false;
		const Design@ orig = originalDesign;
		if(orig is null)
			@orig = playerEmpire.getDesign(newDesign.name);
		if(orig is null)
			success = playerEmpire.addDesign(targetClass, newDesign);
		else
			success = playerEmpire.changeDesign(orig, newDesign, targetClass);
		if(success) {
			@originalDesign = newDesign;
			concept.update();
		}
	}

	DesignSettings@ getDesignSettings() {
		return concept.settings;
	}

	void updateDesign(bool checkHull = false) {
		@design = generateDesign(checkHull=checkHull);
		if(data.gridSize != design.hull.gridSize) {
			data.continueGroup();
			construction.changeGrid(design.hull.gridSize, group = false);
			data.endGroup();
			updateDesign(true);
			updateAbsolutePosition();
			return;
		}

		@construction.display.design = design;
		if(construction.display.hull !is design.hull) {
			auto@ prevHull = construction.display.hull;
			@construction.display.hull = design.hull;
			if(getHullTypeTag(prevHull) != getHullTypeTag(design.hull)) {
				construction.updateSubsystems();
				updateAbsolutePosition();
			}
		}
		saveButton.disabled = !concept.ready || !construction.ready
								|| design.hasFatalErrors();

		construction.update();
		concept.update();
		updateProgress();
		if(data.posChange) {
			data.posChange = false;
			updateAbsolutePosition();
		}
	}

	const Design@ generateDesign(bool checkHull = false) {
		DesignDescriptor desc;

		data.save(desc);
		concept.generateDesign(desc, checkHull=checkHull);

		const Design@ dsg = makeDesign(desc);
		vec2u targGrid = getTargetGridSize(dsg);
		if(targGrid != vec2u(dsg.hull.gridSize)) {
			desc.gridSize = targGrid;
			@dsg = makeDesign(desc);
		}
		return dsg;
	}

	void updateProgress() {
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is saveButton) {
			switch(event.type) {
				case GUI_Clicked:
					saveDesign();
					if(!shiftKey)
						showDesignOverview();
				return true;
			}
		}
		else if(event.caller is backButton) {
			switch(event.type) {
				case GUI_Clicked:
					showDesignOverview();
				return true;
			}
		}
		else if(event.caller is duplicateButton) {
			switch(event.type) {
				case GUI_Clicked:
					duplicate();
				return true;
			}
		}
		else if(event.caller is exportButton) {
			switch(event.type) {
				case GUI_Clicked:
					updateDesign();
					design.setSettings(getDesignSettings());
					exportDesign(design, targetClass, this);
				return true;
			}
		}
		else if(event.type == GUI_Keybind_Down) {
			switch(event.value) {
				case KB_DESIGN_DUPLICATE:
					duplicate();
				break;
				case KB_DESIGN_EXPORT:
					updateDesign();
					design.setSettings(getDesignSettings());
					exportDesign(design, targetClass, this);
				break;
				case KB_DESIGN_UNDO:
					if(construction.visible) {
						data.undo();
						updateDesign();
					}
				break;
				case KB_DESIGN_REDO:
					if(construction.visible) {
						data.redo();
						updateDesign();
					}
				break;
				case KB_DESIGN_TOOL_PAINT:
					if(construction.visible)
						construction.switchTool(construction.paintTool);
				break;
				case KB_DESIGN_TOOL_REPLACE:
					if(construction.visible)
						construction.switchTool(construction.replaceTool);
				break;
				case KB_DESIGN_TOOL_MOVE:
					if(construction.visible)
						construction.switchTool(construction.moveTool);
				break;
				case KB_DESIGN_TOOL_DROP:
					if(construction.visible)
						construction.switchTool(construction.dropTool);
				break;
				case KB_DESIGN_SAVE:
					if(saveButton.disabled)
						sound::error.play(priority=true);
					else
						saveDesign();
				break;
				case KB_DESIGN_SAVE_CLOSE:
					if(saveButton.disabled)
						sound::error.play(priority=true);
					else {
						saveDesign();
						showDesignOverview();
					}
				break;
			}
		}
		else if(event.type == GUI_Clicked) {
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		//Draw the global background
		skin.draw(SS_DesignEditorBG, SF_Normal, AbsolutePosition);

		//Top bar
		vec2i topLeft = AbsolutePosition.topLeft;
		vec2i botRight = AbsolutePosition.botRight;

		Color color;
		if(design !is null)
			color = design.color;

		skin.draw(SS_PlainOverlay, SF_Normal, recti(
			topLeft-vec2i(10,12), vec2i(botRight.x+10, topLeft.y + 78)),
			color);

		BaseGuiElement::draw();
	}
};

Tab@ createDesignEditorTab() {
	return DesignEditor();
}

Tab@ createDesignEditorTab(const Design@ dsg) {
	DesignEditor tab;
	tab.loadDesign(dsg);
	return tab;
}

void loadDesignEditor(Tab@ tab, const Design@ dsg) {
	cast<DesignEditor@>(tab).loadDesign(dsg);
}

void loadDesignEditor(Tab@ tab, const Hull@ hull, const DesignClass@ cls, const string& name, uint size) {
	cast<DesignEditor@>(tab).loadDesign(hull, cls, name, size);
}

void preReload(Message& msg) {
	const Design@ dsg;
	auto@ tab = cast<DesignEditor>(ActiveTab);
	if(tab !is null)
		@dsg = tab.originalDesign;
	msg << dsg;
}

void postReload(Message& msg) {
	const Design@ dsg;
	msg >> dsg;

	if(dsg !is null)
		browseTab(ActiveTab, createDesignEditorTab(dsg));
}
/** }}} */
