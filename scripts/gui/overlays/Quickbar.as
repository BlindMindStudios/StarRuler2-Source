#priority init -500
import elements.BaseGuiElement;
import elements.GuiIconGrid;
import elements.GuiMarkupText;
import elements.GuiResources;
import elements.GuiButton;
import elements.GuiContextMenu;
import elements.MarkupTooltip;
import elements.GuiOverlay;
import elements.GuiSkinElement;
import elements.GuiSprite;
import elements.GuiPanel;
import elements.GuiInfluenceCard;
import dialogs.MessageDialog;
import util.icon_view;
import util.formatting;
import resources;
import influence;
import traits;
import ftl;
import artifacts;
import statuses;
import abilities;
import targeting.ObjectTarget;
import targeting.PointTarget;
import planet_levels;
from orbitals import getOrbitalModuleID;
from traits import getTraitID;
from overlays.ContextMenu import openContextMenu;
from obj_selection import selectObject, uiObject, selectedObjects;
import tabs.Tab;
import void zoomTabTo(Object@ obj) from "tabs.GalaxyTab";
import void openOverlay(Object@ obj) from "tabs.GalaxyTab";
import void doQuickExport(Object@,bool) from "commands";
import void doQuickExport(const array<Object@>&,bool) from "commands";
from gui import animate_speed;

export Quickbar;

const int QUICKBAR_WIDTH = 256;
const int ANIM_SPEED = 512;

class QuickOption : GuiContextOption {
	Quickbar@ bar;
	uint index;

	QuickOption(Quickbar@ bar, uint index) {
		@this.bar = bar;
		this.index = index;
	}

	void call(GuiContextMenu@ menu) override {
		bar.modes[index].closed = !bar.modes[index].closed;
	}
};

class Quickbar : BaseGuiElement, Savable {
	array<QuickbarMode@> modes;
	GuiButton@ quickButton;
	GuiButton@ helpButton;
	Empire@ prevEmpire;

	Quickbar(IGuiElement@ parent) {
		super(parent, recti());

		@quickButton = GuiButton(this, recti(), "...");
		quickButton.noClip = true;

		@helpButton = GuiButton(this, recti());
		helpButton.setIcon(Sprite(spritesheet::MenuIcons, 3));
		helpButton.noClip = true;

		refresh();
	}

	void refresh() {
		@prevEmpire = playerEmpire;
		for(uint i = 0, cnt = modes.length; i < cnt; ++i)
			modes[i].remove();
		modes.length = 0;

		auto@ flingTrait = getTrait("Fling");
		auto@ scTrait = getTrait("StarChildren");
		auto@ anTrait = getTrait("Ancient");
		auto@ exTrait = getTrait("Extragalactic");

		add(CardMode(this), closed=true);
		if(exTrait !is null && playerEmpire.hasTrait(exTrait.id))
			add(Beacons(this));
		if(anTrait !is null && playerEmpire.hasTrait(anTrait.id))
			add(Replicators(this));
		else
			add(FreeResources(this));
		add(AutoImportMode(this));
		add(DisabledResources(this));
		if((scTrait is null || !playerEmpire.hasTrait(scTrait.id)) && (anTrait is null || !playerEmpire.hasTrait(anTrait.id)))
			add(OverPressurePlanets(this));
		add(NoPopResources(this), closed=true);
		add(DecayingPlanets(this));
		add(ColonizingPlanets(this));
		add(ColonizeSafePlanets(this), closed=true);
		add(SiegePlanets(this));
		add(LaborPlanets(this), closed=true);
		add(DefenseTargets(this), closed=true);
		add(FlingBeacons(this), closed=(flingTrait is null || !playerEmpire.hasTrait(flingTrait.id)));
		add(CombatFleets(this));
		add(LowSupplyFleets(this));
		add(AllFleets(this), closed=true);
		add(CivilianFleets(this), closed=true);
		if(playerEmpire.isUnlocked(subsystem::MothershipHull))
			add(Motherships(this));
		add(DefenseStations(this), closed=true);
		add(ArtifactMode(this));
		updateAbsolutePosition();
	}

	void save(SaveFile& file) {
		uint cnt = modes.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << getClass(modes[i]).name;
			file << modes[i].closed;
		}
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			string name;
			file >> name;
			bool closed = false;
			file >> closed;

			for(uint n = 0, ncnt = modes.length; n < ncnt; ++n) {
				if(getClass(modes[i]).name == name) {
					modes[i].closed = closed;
					break;
				}
			}
		}
	}

	bool get_isRoot() const override {
		return true;
	}

	void add(QuickbarMode@ mode, bool closed = false) {
		mode.closed = closed;
		modes.insertLast(mode);
	}

	void openMenu() {
		GuiContextMenu menu(mousePos);
		for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
			auto@ mode = modes[i];

			auto@ option = QuickOption(this, i);
			option.text = mode.name;

			if(mode.closed)
				option.icon = Sprite(spritesheet::ContextIcons, 10);
			else
				option.icon = Sprite(spritesheet::ContextIcons, 1);

			menu.addOption(option);
		}
		menu.updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is quickButton && evt.type == GUI_Clicked) {
			openMenu();
			return true;
		}
		if(evt.caller is helpButton && evt.type == GUI_Clicked) {
			showHelp();
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void updateAbsolutePosition() override {
		if(size.width != QUICKBAR_WIDTH)
			size = vec2i(QUICKBAR_WIDTH, size.height);
		int height = 4;
		for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
			auto@ mode = modes[i];
			bool visible = mode.show && !mode.closed;
			if(!visible) {
				if(mode.visible && !mode.removing) {
					mode.removing = true;
					mode.moveTo(vec2i(size.width, height));
				}
				continue;
			}
			else {
				if(!mode.visible)
					mode.position = vec2i(size.width, height);
				mode.visible = true;
			}
			mode.updateAbsolutePosition();
			if(mode.collapsed)
				mode.moveTo(vec2i(max(size.width - 32, size.width - mode.size.width), height));
			else
				mode.moveTo(vec2i(max(0, size.width - mode.size.width), height));
			height += mode.size.height + 4;
		}
		if(height != size.height)
			size = vec2i(QUICKBAR_WIDTH, height);
		position = vec2i(parent.size.width-size.width, 0);
		if(quickButton !is null) {
			quickButton.rect = recti_area(size.width-32,height, 32,32);
			if(height+32 > parent.size.height) {
				for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
					if(!modes[i].closed && modes[i].show) {
						quickButton.rect = recti_area(modes[i].position - vec2i(36,0), vec2i(32,32));
						break;
					}
				}
			}
			if(helpButton !is null)
				helpButton.rect = quickButton.rect - vec2i(36, 0);
		}
		BaseGuiElement::updateAbsolutePosition();
	}

	void update(double time) {
		if(prevEmpire !is playerEmpire)
			refresh();
		helpButton.visible = HELP_TEXT.length != 0;
		bool changed = false;
		for(uint i = 0, cnt = modes.length; i < cnt; ++i) {
			auto@ mode = modes[i];
			if(mode.closed) {
				if(mode.visible && !mode.animating)
					changed = true;
				continue;
			}
			mode.update(time);

			if(mode.show != mode.visible)
				changed = true;
		}
		if(changed)
			updateAbsolutePosition();
	}
};

class QuickbarMode : BaseGuiElement {
	GuiSprite@ picture;
	Color color;
	bool closed = false;
	bool collapsed = false;
	bool removing = false;
	bool animating = false;

	QuickbarMode(IGuiElement@ parent) {
		super(parent, recti());
		visible = false;
		@picture = GuiSprite(this, Alignment(Left+2, Top+0.5f-18, Left+31, Top+0.5f+18), icon);
		setMarkupTooltip(picture, name, hoverStyle=false);
	}

	string get_name() {
		return "---";
	}

	Sprite get_icon() {
		return Sprite();
	}

	int get_needHeight() {
		return 32;
	}

	int get_maxHeight() {
		return 400;
	}

	int get_needWidth() {
		return 256;
	}

	bool get_show() {
		return true;
	}

	Color get_tabColor() {
		return Color();
	}

	void moveTo(const vec2i& pos) {
		if(rect == recti()) {
			rect = recti_area(pos, size);
		}
		else {
			animate_speed(this, recti_area(pos, size), ANIM_SPEED);
			animating = true;
		}
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ caller) override {
		recti tabPos = recti_area(AbsolutePosition.topLeft, vec2i(32, size.height));
		if(tabPos.isWithin(mousePos)) {
			if(evt.type == MET_Button_Down && evt.button == 0) {
				return true;
			}
			else if(evt.type == MET_Button_Up && evt.button == 0) {
				collapsed = !collapsed;
				parent.updateAbsolutePosition();
				return true;
			}
			else if(evt.type == MET_Button_Down && evt.button == 1) {
				return true;
			}
			else if(evt.type == MET_Button_Up && evt.button == 1) {
				closed = true;
				parent.updateAbsolutePosition();
				return true;
			}
		}
		return BaseGuiElement::onMouseEvent(evt, caller);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Animation_Complete) {
			animating = false;
			if(removing) {
				visible = false;
				removing = false;
			}
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	double timer = randomd(0.5, 1.0);
	void update(double time) {
		timer -= time;
		if(timer <= 0) {
			longUpdate();
			timer += randomd(0.5, 1.0);
		}

		shortUpdate();

		if(!animating) {
			if(min(needHeight, maxHeight) != size.height || min(needWidth, 256) != size.width)
				parent.updateAbsolutePosition();
		}
	}

	void shortUpdate() {}
	void longUpdate() {}

	void updateAbsolutePosition() override {
		if(parent !is null)
			size = vec2i(min(needWidth, parent.size.width), min(needHeight, maxHeight));
		BaseGuiElement::updateAbsolutePosition();
	}

	void draw() override {
		recti boxPos = recti_area(AbsolutePosition.topLeft, size+vec2i(8, 0));
		skin.draw(SS_Panel, SF_Normal, boxPos);
		skin.draw(SS_SmallHexPattern, SF_Normal, boxPos.padded(3, 3));

		recti tabPos = recti_area(AbsolutePosition.topLeft, vec2i(32, size.height));
		skin.draw(SS_FullTitle, SF_Normal, tabPos, tabColor);

		BaseGuiElement::draw();
	}
};

final class FleetData {
	double fleetStr = 0, fleetMaxStr = 0, nextStrUpdate = -1;
	double fleetSupply = 0, fleetMaxSupply = 0;
	int updateMax = 3;
};

//{{{ Object Modes
class ObjectGrid : GuiIconGrid {
	private array<Resource@> resources;
	private array<FleetData> fleetData;
	array<int> counts;
	bool showFleetSupply = false;
	bool showManage = false;
	string ttip;

	vec2i pressedPos;
	bool pressed = false;

	ObjectGrid(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		iconSize = vec2i(46, 46);
		spacing.y = 0;
	}

	void activateTooltip(string text) {
		ttip = text;

		MarkupTooltip tt(400, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		auto@ obj = resources[hovered].origin;
		return format(ttip, obj.name);
	}

	uint get_length() override {
		return resources.length;
	}

	void setHovered(int prev, int current) {
		if(prev != hovered) {
			if(hovered == -1 || uint(hovered) >= resources.length)
				@uiObject = null;
			else
				@uiObject = resources[hovered].origin;
		}
	}

	void drawElement(uint index, const recti& pos) override {
		if(hovered == int(index) || resources[index].origin.selected)
			drawRectangle(pos.padded(2, 3), color=Color(0xffffff30));
		Object@ obj = resources[index].origin;
		if(obj !is null) {
			if(obj.isShip && obj.hasLeaderAI) {
				FleetData@ data = fleetData[index];
				if(gameTime >= data.nextStrUpdate) {
					if(data.nextStrUpdate >= 0) {
						if(data.updateMax <= 0) {
							data.fleetMaxStr = obj.getFleetMaxStrength();
							data.updateMax = 3;
						}
						else {
							data.fleetStr = obj.getFleetStrength();
							data.updateMax -= 1;
						}
						data.fleetSupply = cast<Ship>(obj).Supply;
						data.fleetMaxSupply = cast<Ship>(obj).MaxSupply;
					}
					else {
						data.fleetStr = obj.getFleetStrength();
						data.fleetMaxStr = obj.getFleetMaxStrength();
					}
					data.nextStrUpdate = gameTime + randomd(1.8,2.2);
				}
				
				if(!showFleetSupply)
					drawFleetIcon(cast<Ship>(obj), pos, data.fleetStr*0.001, data.fleetMaxStr*0.001);
				else
					drawFleetIcon(cast<Ship>(obj), pos, data.fleetSupply, data.fleetMaxSupply,
						Color(0x4a9487ff), Color(0x4a9487ff));
			}
			else {
				drawObjectIcon(obj, pos, resources[index]);
			}
			int count = counts[index];
			if(count != 1) {
				Colorf shifted;
				Empire@ owner = obj.owner;
				if(owner !is null)
					shifted = Colorf(owner.color);
				shifted.fromHSV((shifted.hue + 180.f)%360.f, shifted.saturation, shifted.value);
				skin.getFont(FT_Bold).draw(horizAlign=0.85, vertAlign=0.85, text=count,
						pos=pos, color=Color(shifted),
						stroke=colors::Black);
			}
		}
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked) {
			if(hovered == -1)
				return true;
			auto@ r = resources[hovered];
			if(evt.value == 0) {
				if(r.origin.selected || ctrlKey) {
					selectObject(r.origin);
					zoomTabTo(r.origin);
					if(showManage || ctrlKey)
						openOverlay(r.origin);
				}
				else
					selectObject(r.origin);
			}
			else if(evt.value == 1) {
				openContextMenu(r.origin);
			}
			else if(evt.value == 2) {
				zoomTabTo(r.origin);
			}
			return true;
		}
		return GuiIconGrid::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		if(source is this) {
			if(evt.type != MET_Moved)
				updateHover();
			switch(evt.type) {
				case MET_Moved:
					if(hovered != -1 && uint(hovered) <= resources.length && pressed) {
						Object@ obj = resources[hovered].origin;
						if(evt.type == MET_Moved && pressedPos.distanceTo(mousePos) > 4 && mouseLeft) {
							if(obj !is null && obj.selected)
								doQuickExport(selectedObjects, true);
							else if(obj !is null && obj.hasResources && getResource(obj.primaryResourceType) !is null)
								doQuickExport(obj, true);
							pressed = false;
						}
					}
					updateHover();
				break;
				case MET_Button_Down:
					if(uint(hovered) < length && evt.button == 0) {
						pressed = true;
						pressedPos = mousePos;
					}
				break;
				case MET_Button_Up:
					if(evt.button == 0)
						pressed = false;
				break;
			}
		}
		return GuiIconGrid::onMouseEvent(evt, source);
	}

	void add(Object@ obj) {
		set(resources.length, obj);
	}

	void set(uint index, Object@ obj) {
		if(index >= resources.length) {
			resources.insertLast(Resource());
			counts.insertLast(1);
			fleetData.length = fleetData.length + 1;
		}
		counts[index] = 1;

		if(!obj.hasResources || !receive(obj.getNativeResources(), resources[index])) {
			@resources[index].type = null;
			@resources[index].origin = obj;
		}
	}

	void set(uint index, ObjectData@ dat) {
		if(index >= resources.length) {
			resources.insertLast(dat.resource);
			counts.insertLast(1);
			fleetData.length = fleetData.length + 1;
		}
			
		@resources[index] = dat.resource;
		@resources[index].origin = dat.obj;
		fleetData[index] = FleetData();
		counts[index] = 1;
	}

	void truncate(uint index, bool sort = true) {
		if(resources.length > index) {
			resources.length = index;
			fleetData.length = index;
			counts.length = index;
		}
		if(sort)
			resources.sortDesc();
		updateHover();
	}
};

class ObjectMode : QuickbarMode {
	ObjectGrid@ grid;

	ObjectMode(IGuiElement@ parent) {
		super(parent);
		@grid = ObjectGrid(this, Alignment(Left+32, Top, Right, Bottom-4));
		grid.horizAlign = 1.0;
	}

	bool get_show() override {
		return grid.length != 0;
	}

	int get_needHeight() override {
		int perRow = size.width / 40;
		if(perRow == 0)
			return 20;
		return max(ceil(double(grid.length) / double(perRow)), 1.0) * 49;
	}

	int get_needWidth() override {
		return grid.length * 50 + 40;
	}

	bool filter(ObjectData@ obj) {
		return true;
	}

	void longUpdate() override {
		uint index = 0;
		for(uint i = 0, cnt = empirePlanets.length; i < cnt; ++i) {
			if(!filter(empirePlanets[i]))
				continue;
			grid.set(index, empirePlanets[i]);
			++index;
		}
		grid.truncate(index);
	}
};

bool sentFreePlanetsWarning = false;
int freeWarningDelay = 180;

class FreeResources : ObjectMode {
	FreeResources(IGuiElement@ parent) {
		super(parent);
		color = Color(0x00fa99ff);
	}

	string get_name() override {
		return locale::FREE_RESOURCES;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 2);
	}

	void longUpdate() override {
		uint unusedPlanets = 0;
	
		array<uint> types(getResourceCount(), UINT_MAX);
	
		uint index = 0;
		for(uint i = 0, cnt = empirePlanets.length; i < cnt; ++i) {
			auto@ dat = empirePlanets[i];
			if(!filter(dat))
				continue;
			if(dat.obj.level == 0)
				++unusedPlanets;
			if(dat.resource.type !is null) {
				uint tID = dat.resource.type.id;
				if(types[tID] != UINT_MAX) {
					grid.counts[types[tID]]++;
					continue;
				}
				types[tID] = index;
			}
			grid.set(index, dat);
			++index;
		}
		
		if(!sentFreePlanetsWarning) {
			if(unusedPlanets >= 5 && playerEmpire.TotalBudget < playerEmpire.MaintenanceBudget) {
				if(--freeWarningDelay == 0) {
					auto@ msg = message(locale::HINT_USE_PLANETS);
					msg.addTitle(locale::HINT_USE_PLANETS_TITLE);
					sentFreePlanetsWarning = true;
				}
			}
			else {
				freeWarningDelay = 180;
			}
		}

		array<Asteroid@> list;
		DataList@ objs = playerEmpire.getAsteroids();
		Object@ obj;
		while(receive(objs, obj)) {
			Asteroid@ asteroid = cast<Asteroid>(obj);
			if(asteroid !is null && asteroid.nativeResourceCount != 0)
				list.insertLast(asteroid);
		}
		
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ dat = cache(list[i]);
			if(!filter(dat))
				continue;
			grid.set(index, dat);
			++index;
		}
		
		grid.truncate(index, sort=false);
	}

	bool filter(ObjectData@ dat) {
		Object@ obj = dat.obj;
		auto@ type = dat.resource.type;
		if(type is null)
			return false;
		Object@ dest = dat.destination;
		if(dest !is null) {
			Empire@ destOwner = dest.owner;
			if(destOwner is playerEmpire || destOwner is null || !destOwner.valid)
				return false;
		}
		if(!dat.resource.usable)
			return false;
		if(obj.isPlanet) {
			if(type.isMaterial(obj.level))
				return false;
			if(obj.decayTime > 0)
				return false;
			if(obj.resourceLevel > obj.level)
				return false;
			if(!obj.exportEnabled)
				return false;
		}
		if(!type.exportable || type.mode == RM_NonRequirement)
			return false;
		return true;
	}
};

class DisabledResources : ObjectMode {
	DisabledResources(IGuiElement@ parent) {
		super(parent);
		color = Color(0xfa0099ff);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 3);
	}

	bool filter(ObjectData@ dat) {
		auto@ type = dat.resource.type;
		if(type is null)
			return false;
		if(!dat.resource.usable) {
			double pop = dat.obj.population;
			if(!dat.obj.inCombat && pop < getPlanetLevelRequiredPop(dat.obj, dat.obj.resourceLevel))
				return false;
			if(dat.obj.population < 1.0)
				return false;
			return true;
		}
		return false;
	}

	string get_name() override {
		return locale::DISABLED_RESOURCES;
	}
};

class OverPressurePlanets : ObjectMode {
	OverPressurePlanets(IGuiElement@ parent) {
		super(parent);
		color = Color(0xfa0099ff);
	}

	Sprite get_icon() override {
		return icons::Pressure;
	}

	bool filter(ObjectData@ dat) {
		if(!dat.obj.isPlanet)
			return false;
		if(dat.obj.level == 0)
			return false;
		return dat.obj.isOverPressure;
	}

	string get_name() override {
		return locale::OVERPRESSURE_PLANETS;
	}
};

class Replicators : ObjectMode {
	uint statusId = uint(-1);
	uint orbId = uint(-1);

	Replicators(IGuiElement@ parent) {
		super(parent);

		auto@ status = getStatusType("AncientReplicator");
		if(status !is null)
			statusId = status.id;

		orbId = getOrbitalModuleID("AncientReplicator");
	}

	Sprite get_icon() override {
		return spritesheet::GuiOrbitalIcons+20;
	}

	bool filter(ObjectData@ dat) {
		if(!dat.obj.isPlanet)
			return false;
		return dat.obj.hasStatusEffect(statusId);
	}

	string get_name() override {
		return locale::REPLICATORS;
	}

	void longUpdate() override {
		uint index = 0;
		for(uint i = 0, cnt = empirePlanets.length; i < cnt; ++i) {
			if(!filter(empirePlanets[i]))
				continue;
			grid.set(index, empirePlanets[i]);
			++index;
		}

		DataList@ objs = playerEmpire.getOrbitals();
		Object@ obj;
		while(receive(objs, obj)) {
			Orbital@ orb = cast<Orbital>(obj);
			if(orb !is null && uint(orb.coreModule) == orbId) {
				if(!orb.inOrbit && !orb.hasLockedOrbit()) {
					auto@ dat = cache(orb);
					grid.set(index, dat);
					++index;
				}
			}
		}
		grid.truncate(index);
	}
};

class NoPopResources : ObjectMode {
	NoPopResources(IGuiElement@ parent) {
		super(parent);
		color = Color(0xfa0099ff);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 3, colors::Green);
	}

	bool filter(ObjectData@ dat) {
		auto@ type = dat.resource.type;
		if(type is null)
			return false;
		if(!dat.resource.usable) {
			if(dat.obj.population >= getPlanetLevelRequiredPop(dat.obj, dat.obj.resourceLevel))
				return false;
			if(dat.obj.inCombat)
				return false;
			return true;
		}
		return false;
	}

	string get_name() override {
		return locale::NO_POP_RESOURCES;
	}
};

class DecayingPlanets : ObjectMode {
	DecayingPlanets(IGuiElement@ parent) {
		super(parent);
		color = Color(0xfaf099ff);
	}

	bool filter(ObjectData@ dat) {
		if(dat.obj.decayTime > 0)
			return true;
		return false;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 4);
	}

	string get_name() override {
		return locale::DECAYING_PLANETS;
	}
};

bool shownColonizeWarning = false;
uint colonizeWarningDelay = 100;

class ColonizingPlanets : ObjectMode {
	ColonizingPlanets(IGuiElement@ parent) {
		super(parent);
		color = Color(0x8060ffff);
	}

	bool filter(ObjectData@ dat) {
		if(dat.obj.population < 1.0 || dat.obj.isBeingColonized)
			return true;
		return false;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 5);
	}

	string get_name() override {
		return locale::COLONIZING_PLANETS;
	}

	void longUpdate() override {
		uint index = 0;
		for(uint i = 0, cnt = empirePlanets.length; i < cnt; ++i) {
			if(!filter(empirePlanets[i]))
				continue;
			grid.set(index, empirePlanets[i]);
			++index;
		}
		
		if(!shownColonizeWarning) {
			int colonyCost = -playerEmpire.getMoneyFromType(0);
			int budget = playerEmpire.TotalBudget;
			int netBudget = budget - playerEmpire.MaintenanceBudget;
			
			if(netBudget < 0 && colonyCost > 200 && colonyCost > budget/6) {
				if(--colonizeWarningDelay == 0) {
					auto@ msg = message(locale::HINT_COLONIZE);
					msg.addTitle(locale::HINT_COLONIZE_TITLE);
					shownColonizeWarning = true;
				}
			}
			else {
				colonizeWarningDelay = 100;
			}
		}
		
		set_int listed;
		array<Planet@> list;
		DataList@ objs = playerEmpire.getQueuedColonizations();
		Object@ obj;
		while(receive(objs, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(pl !is null && !listed.contains(pl.id)) {
				listed.insert(pl.id);
				list.insertLast(pl);
			}
		}

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ dat = cache(list[i]);
			if(!filter(dat))
				continue;
			grid.set(index, dat);
			++index;
		}
		grid.truncate(index, sort=false);
	}
};

class ColonizeSafePlanets : ObjectMode {
	ColonizeSafePlanets(IGuiElement@ parent) {
		super(parent);
	}

	bool filter(ObjectData@ dat) {
		return dat.obj.canSafelyColonize;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 5, Color(0x00ff00ff));
	}

	string get_name() override {
		return locale::COLONIZE_SAFE_PLANETS;
	}
};

class LaborPlanets : ObjectMode {
	LaborPlanets(IGuiElement@ parent) {
		super(parent);
		color = Color(0x606080ff);
		grid.showManage = true;
	}

	bool filter(ObjectData@ dat) {
		if(dat.obj.getResourceProduction(TR_Labor) > 0)
			return true;
		return false;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 1);
	}

	string get_name() override {
		return locale::LABOR_PLANETS;
	}

	void longUpdate() override {
		uint index = 0;
		for(uint i = 0, cnt = empirePlanets.length; i < cnt; ++i) {
			if(!filter(empirePlanets[i]))
				continue;
			grid.set(index, empirePlanets[i]);
			++index;
		}

		DataList@ objs = playerEmpire.getOrbitals();
		Object@ obj;
		while(receive(objs, obj)) {
			Orbital@ orb = cast<Orbital>(obj);
			if(orb !is null && orb.hasConstruction) {
				auto@ dat = cache(orb);
				grid.set(index, dat);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class DefenseTargets : ObjectMode {
	DefenseTargets(IGuiElement@ parent) {
		super(parent);
		color = Color(0x606080ff);

		grid.activateTooltip(format("[font=Medium]$1[/font]\n$2",
				"$1", locale::TT_IS_DEFENDING));
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 8);
	}

	string get_name() override {
		return locale::DEFENSE_TARGETS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getDefending();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			if(obj !is null) {
				auto@ dat = cache(obj);
				grid.set(index, dat);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class SiegePlanets : ObjectMode {
	SiegePlanets(IGuiElement@ parent) {
		super(parent);
		color = Color(0xfaf099ff);
	}

	bool filter(ObjectData@ dat) {
		Empire@ captEmp = dat.obj.captureEmpire;
		if(captEmp is null || captEmp is playerEmpire)
			return false;
		return true;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 7);
	}

	Color get_tabColor() override {
		return Color(0xff0000ff);
	}

	string get_name() override {
		return locale::UNDER_SIEGE_PLANETS;
	}
};

class FlingBeacons : ObjectMode {
	FlingBeacons(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::GuiOrbitalIcons, 0);
	}

	string get_name() override {
		return locale::FLING_BEACONS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlingBeacons();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Orbital@ beacon = cast<Orbital>(obj);
			if(beacon !is null) {
				auto@ dat = cache(beacon);
				grid.set(index, dat);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class Beacons : ObjectMode {
	Beacons(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::GuiOrbitalIcons, 0);
	}

	string get_name() override {
		return locale::ORB_BEACON;
	}

	void longUpdate() override {
		auto@ core = getOrbitalModule("Beacon");
		uint index = 0;
		DataList@ objs = playerEmpire.getOrbitals();
		Object@ obj;
		while(receive(objs, obj)) {
			Orbital@ orb = cast<Orbital>(obj);
			if(orb !is null && core !is null && orb.coreModule == core.id) {
				auto@ dat = cache(orb);
				grid.set(index, dat);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class AllFleets : ObjectMode {
	AllFleets(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ShipIcons, 0);
	}

	string get_name() override {
		return locale::ALL_FLEETS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlagships();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null && !ship.blueprint.design.hasTag(ST_Mothership)) {
				if(ship.getFleetMaxStrength() < 1000.0)
					continue;
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class CivilianFleets : ObjectMode {
	CivilianFleets(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ShipIcons, 0);
	}

	string get_name() override {
		return locale::CIVILIAN_FLEETS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlagships();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null && !ship.blueprint.design.hasTag(ST_Mothership)) {
				if(ship.getFleetMaxStrength() > 1000.0)
					continue;
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class Motherships : ObjectMode {
	Motherships(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ShipIcons, 0);
	}

	string get_name() override {
		return locale::MOTHERSHIPS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlagships();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null && ship.blueprint.design.hasTag(ST_Mothership)) {
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class DefenseStations : ObjectMode {
	DefenseStations(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::GuiOrbitalIcons, 0);
	}

	string get_name() override {
		return locale::DEFENSE_STATIONS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getStations();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null) {
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class LowSupplyFleets : ObjectMode {
	LowSupplyFleets(IGuiElement@ parent) {
		super(parent);
		grid.showFleetSupply = true;
	}

	Sprite get_icon() override {
		return icons::Supply;
	}

	string get_name() override {
		return locale::FLEETS_LOW_SUPPLY;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlagships();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null && ship.Supply < ship.MaxSupply * 0.5) {
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class CombatFleets : ObjectMode {
	CombatFleets(IGuiElement@ parent) {
		super(parent);
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ShipIcons, 0);
	}

	Color get_tabColor() override {
		return Color(0xff0000ff);
	}

	string get_name() override {
		return locale::COMBAT_FLEETS;
	}

	void longUpdate() override {
		DataList@ objs = playerEmpire.getFlagships();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null && ship.inCombat) {
				grid.set(index, ship);
				++index;
			}
		}
		grid.truncate(index);
	}
};

class ObjectData {
	Object@ obj;
	int resMod;
	Resource resource;
	Object@ destination;
};

double timer = randomd(0.5, 2.0);
dictionary objCache;
array<ObjectData@> empirePlanets;

void update(ObjectData@ dat) {
	if(dat.obj.hasResources) {
		receive(dat.obj.getNativeResources(), dat.resource);
		@dat.destination = dat.obj.nativeResourceDestination[0];
	}
}

ObjectData@ cache(Object@ obj) {
	ObjectData@ dat;
	if(objCache.get(obj.id, @dat)) {
		int newMod = obj.hasResources ? obj.resourceModID : 0;
		if(newMod != dat.resMod) {
			dat.resMod = newMod;
			update(dat);
		}
		return dat;
	}

	@dat = ObjectData();
	@dat.obj = obj;
	dat.resMod = obj.hasResources ? obj.resourceModID : 0;
	objCache.set(obj.id, @dat);
	update(dat);
	return dat;
}

void tick(double time) {
	timer -= time;
	if(timer <= 0) {
		empirePlanets.length = 0;
		DataList@ objs = playerEmpire.getPlanets();
		Object@ obj;
		while(receive(objs, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(pl !is null)
				empirePlanets.insertLast(cache(pl));
		}

		timer += randomd(0.5, 2.0);
	}
}
//}}}
//{{{ Influence Mode
const int CARD_W = 55;
const int CARD_H = 36;

class CardGrid : GuiIconGrid {
	array<StackInfluenceCard@> cards;

	CardGrid(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		iconSize = vec2i(CARD_W, CARD_H);
		spacing.y = 0;

		MarkupTooltip tt(400, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	uint get_length() override {
		return cards.length;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		return cards[hovered].formatTooltip(playerEmpire);
	}

	void drawElement(uint index, const recti& pos) override {
		if(hovered == int(index))
			drawRectangle(pos.padded(2, 2), color=Color(0xffffff30));
		auto@ card  = cards[index];

		Color col;
		if(card.purchasedBy !is null)
			col = card.purchasedBy.color;
		skin.draw(SS_LightPanel, SF_Normal, pos.padded(3, 3), col);

		drawCardIcon(card, pos);
	}

	IGuiElement@ findTab() {
		IGuiElement@ elem = parent;
		while(elem !is null && cast<Tab>(elem) is null)
			@elem = elem.parent;
		return elem;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked) {
			if(hovered == -1)
				return true;
			if(ctrlKey) {
				sound::card_draw.play(priority=true);
				buyCardFromInfluenceStack(cards[hovered].id);
				emitConfirmed();
			}
			else {
				sound::card_examine.play(priority=true);
				StackInfluenceCard card = cards[hovered];
				GuiInfluenceCardPopup(findTab(), parent, card);
			}
			return true;
		}
		return GuiIconGrid::onGuiEvent(evt);
	}

	void add(StackInfluenceCard@ card) {
		set(cards.length, card);
	}

	void set(uint index, StackInfluenceCard@ card) {
		if(index >= cards.length)
			cards.insertLast(card);
		else
			@cards[index] = card;
	}

	void truncate(uint index) {
		if(cards.length > index)
			cards.length = index;
		updateHover();
	}
};

class CardMode : QuickbarMode {
	CardGrid@ grid;
	array<StackInfluenceCard> cards;
	double stackTimer = 0.0;

	CardMode(IGuiElement@ parent) {
		super(parent);
		@grid = CardGrid(this, Alignment(Left+36, Top+1, Right-4, Bottom-4));
		color = Color(0x20adffff);
	}

	bool get_show() override {
		return grid.length != 0;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::QuickbarIcons, 0);
	}

	string get_name() override {
		return locale::INFLUENCE_STACK;
	}

	int get_needHeight() {
		int perRow = size.width / (CARD_W + 4);
		if(perRow == 0)
			return CARD_H + 4;
		return max(ceil(double(grid.length) / double(perRow)), 1.0) * (CARD_H + 4);
	}

	int get_needWidth() {
		return min(grid.length, 3) * (CARD_W + 4) + 40;
	}

	void shortUpdate() {
		QuickbarMode::shortUpdate();

		double prevTimer = stackTimer;
		stackTimer = getInfluenceDrawTimer();
		if(prevTimer < stackTimer)
			longUpdate();
	}

	void longUpdate() {
		cards.syncFrom(getInfluenceCardStack());
		uint i = 0;
		for(uint cnt = cards.length; i < cnt; ++i)
			grid.set(i, cards[i]);
		grid.truncate(i);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Confirmed) {
			longUpdate();
			timer = 0.15;
			return true;
		}
		return QuickbarMode::onGuiEvent(evt);
	}

	void draw() override {
		QuickbarMode::draw();

		string timeText = formatEstTime(stackTimer);
		const Font@ ft = skin.getFont(FT_Small);
		ft.draw(pos=picture.absolutePosition.padded(0, 3), text=timeText, horizAlign=0.5, vertAlign=1.0);
	}
};
//}}}
//{{{ Auto Imports Mode
class AutoImportGrid : GuiIconGrid {
	array<AutoImportDesc> list;
	array<uint> counts;

	AutoImportGrid(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		iconSize = vec2i(36, 36);
		spacing.y = 0;

		MarkupTooltip tt(400, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		auto@ desc = list[hovered];
		string type;
		if(desc.type !is null)
			type = desc.type.name;
		else if(desc.cls !is null)
			type = desc.cls.name;
		else if(desc.level != -1)
			type = locale::LEVEL+" "+desc.level;
		return format(locale::TT_AUTO_IMPORTS, toString(counts[hovered]), type,
				getSpriteDesc(getAutoImportIcon(desc)));
	}

	uint get_length() override {
		return list.length;
	}

	void drawElement(uint index, const recti& pos) override {
		auto@ desc = list[index];
		getAutoImportIcon(desc).draw(pos.padded(4));

		uint count = counts[index];
		if(count > 1) {
			skin.getFont(FT_Bold).draw(horizAlign=0.85, vertAlign=0.85, text=count,
					pos=pos, color=Color(0xf268ffff),
					stroke=colors::Black);
		}
	}

	void add(AutoImportDesc@ desc, uint& index) {
		for(uint i = 0; i < index; ++i) {
			if(list[i].equivalent(desc)) {
				counts[i] += 1;
				return;
			}
		}
		set(index, desc);
		index += 1;
	}

	void set(uint index, AutoImportDesc@ desc) {
		if(index >= list.length) {
			list.insertLast(desc);
			counts.insertLast(1);
		}
		else {
			list[index] = desc;
			counts[index] = 1;
		}
	}

	void truncate(uint index) {
		if(list.length > index) {
			list.length = index;
			counts.length = index;
		}
		updateHover();
	}
};

class AutoImportMode : QuickbarMode {
	AutoImportGrid@ grid;

	AutoImportMode(IGuiElement@ parent) {
		super(parent);
		@grid = AutoImportGrid(this, Alignment(Left+36, Top+1, Right-4, Bottom-4));
	}

	bool get_show() override {
		return grid.length != 0;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ContextIcons, 0);
	}

	string get_name() override {
		return locale::AUTO_IMPORTS;
	}

	int get_needHeight() override {
		int perRow = size.width / 30;
		if(perRow == 0)
			return 20;
		return max(ceil(double(grid.length) / double(perRow)), 1.0) * 39;
	}

	int get_needWidth() override {
		return grid.length * 40 + 30;
	}

	AutoImportDesc desc;
	void longUpdate() {
		DataList@ list = playerEmpire.getAutoImports();
		uint index = 0;
		while(receive(list, desc))
			grid.add(desc, index);
		grid.truncate(index);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Confirmed) {
			longUpdate();
			timer = 0.15;
			return true;
		}
		return QuickbarMode::onGuiEvent(evt);
	}
};
//}}}
//{{{ Artifact Mode
const int ARTIF_W = 45;
const int ARTIF_H = 36;
dictionary ablCache;

class ArtifDesc {
	Artifact@ artif;
	uint count = 1;
	const ArtifactType@ type;
	Ability@ ability;

	ArtifDesc(Artifact@ obj) {
		set(obj);
	}

	ArtifDesc() {
	}

	void set(Artifact@ obj) {
		@artif = obj;
		@type = getArtifactType(obj.ArtifactType);
		if(!ablCache.get(obj.id, @ability)) {
			@ability = Ability();
			receive(obj.getAbilities(), ability);
			@ability.emp = playerEmpire;
			ablCache.set(obj.id, @ability);
		}
		count = 1;
	}

	int opCmp(const ArtifDesc@ other) const {
		if(ability.type is null)
			return -1;
		if(other.ability.type is null)
			return 1;

		double myCost = ability.getEnergyCost();
		double theirCost = other.ability.getEnergyCost();
		if(myCost > theirCost)
			return 1;
		if(theirCost > myCost)
			return -1;
		return 0;
	}
};

class ArtifGrid : GuiIconGrid {
	array<ArtifDesc@> list;

	ArtifGrid(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		iconSize = vec2i(ARTIF_W, ARTIF_H);
		spacing.y = 0;

		MarkupTooltip tt(400, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	uint get_length() override {
		return list.length;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		auto@ desc = list[hovered];
		if(desc.ability.type is null)
			return "";
		string tt = format("[font=Medium][b]$1[/b][/font] [img=$2;24/]\n",
				desc.type.name, getSpriteDesc(desc.type.icon));
		tt += desc.ability.formatTooltip(playerEmpire);
		return tt;
	}

	void drawElement(uint index, const recti& pos) override {
		auto@ desc = list[index];
		Color col(0xffffffff);
		if(desc.ability !is null && desc.ability.type !is null) {
			auto@ abl = desc.ability;
			if(abl.cooldown > 0 || abl.getEnergyCost() > playerEmpire.EnergyStored)
				col = Color(0xff0000ff);
		}

		if(hovered == int(index))
			drawRectangle(pos, Color(0xffffff30));
		skin.draw(SS_LightPanel, SF_Normal, pos.padded(3, 3), col);

		desc.type.icon.draw(recti_area(pos.topLeft + vec2i(5, 5), vec2i(ARTIF_H - 14, ARTIF_H - 14)));
		if(desc.ability !is null && desc.ability.type !is null) {
			auto@ abl = desc.ability;
			abl.type.icon.draw(recti_area(pos.topLeft + vec2i(ARTIF_W - ARTIF_H + 9, 9), vec2i(ARTIF_H - 14, ARTIF_H - 14)));

		}

		//Draw amount
		if(desc.count > 1) {
			int x = pos.size.x - 9;
			if(desc.count > 5) {
				font::DroidSans_11_Bold.draw(
					pos=recti_area(vec2i(pos.topLeft.x + x - 30, pos.topLeft.y + 4), vec2i(35, 10)),
					text=toString(desc.count),
					color=Color(0xe32020ff),
					horizAlign=1.0);
			}
			else {
				for(uint i = 0; i < desc.count; ++i) {
					drawRectangle(recti_area(vec2i(pos.topLeft.x+x, pos.topLeft.y+4), vec2i(5, 5)), Color(0x991c1cff));
					x -= 8;
				}
			}
		}
	}

	void activate(ArtifDesc@ desc) {
		if(desc.ability is null && desc.ability.type !is null)
			return;
		Ability abl = desc.ability;
		if(abl.cooldown > 0 || abl.getEnergyCost() > playerEmpire.EnergyStored) {
			zoomTabTo(desc.artif);
			selectObject(desc.artif);
			return;
		}
		@abl.emp = playerEmpire;
		if(abl.type.targets.length == 0 || desc.artif.abilityCount > 1) {
			zoomTabTo(desc.artif);
			selectObject(desc.artif);
		}
		else if(abl.type.targets[0].type == TT_Point) {
			targetPoint(AbilityTargetPoint(abl));
		}
		else if(abl.type.targets[0].type == TT_Object) {
			targetObject(AbilityTargetObject(abl));
		}
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked) {
			if(hovered == -1)
				return true;
			auto@ desc = list[hovered];
			if(evt.value == 0)
				activate(desc);
			else if(evt.value == 2)
				zoomTabTo(desc.artif);
			return true;
		}
		return GuiIconGrid::onGuiEvent(evt);
	}

	void add(Artifact@ obj, uint& index) {
		auto@ type = getArtifactType(obj.ArtifactType);
		if(type.collapses) {
			for(uint i = 0, cnt = min(list.length, index); i < cnt; ++i) {
				if(list[i].type is type) {
					list[i].count += 1;
					return;
				}
			}
		}
		set(index, obj);
		index += 1;
	}

	void set(uint index, Artifact@ obj) {
		if(index >= list.length)
			list.insertLast(ArtifDesc(obj));
		else
			list[index].set(obj);
	}

	void truncate(uint index) {
		if(list.length > index)
			list.length = index;
		list.sortDesc();
		updateHover();
	}
};

class ArtifactMode : QuickbarMode {
	ArtifGrid@ grid;

	ArtifactMode(IGuiElement@ parent) {
		super(parent);
		@grid = ArtifGrid(this, Alignment(Left+36, Top+1, Right-4, Bottom-4));
		@picture.alignment = Alignment(Left+1, Top+0.5f-15, Left+31, Top+0.5f+15);
	}

	bool get_show() override {
		return grid.length != 0;
	}

	Sprite get_icon() override {
		return Sprite(spritesheet::ArtifactIcon, 0);
	}

	string get_name() override {
		return locale::AVAIL_ARTIFACTS;
	}

	int get_needHeight() {
		int perRow = size.width / (ARTIF_W + 4);
		if(perRow == 0)
			return ARTIF_H + 4;
		return max(ceil(double(grid.length) / double(perRow)), 1.0) * (ARTIF_H + 4);
	}

	int get_needWidth() {
		return min(grid.length, 4) * (ARTIF_W + 4) + 40;
	}

	void longUpdate() {
		DataList@ objs = playerEmpire.getArtifacts();
		Object@ obj;
		uint index = 0;
		while(receive(objs, obj)) {
			Artifact@ artif = cast<Artifact>(obj);
			if(artif !is null)
				grid.add(artif, index);
		}
		grid.truncate(index);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Confirmed) {
			longUpdate();
			timer = 0.15;
			return true;
		}
		return QuickbarMode::onGuiEvent(evt);
	}
};
//}}}
// {{{ Game help popup
class HelpOverlay : GuiOverlay {
	GuiSkinElement@ bg;
	GuiPanel@ panel;
	GuiMarkupText@ page;

	GuiButton@ okButton;
	double prevGameSpeed = -1.0;

	HelpOverlay() {
		super(null);
		closeSelf = false;

		@bg = GuiSkinElement(this, Alignment(Left+0.2f, Top+0.1f, Right-0.2f, Bottom-0.1f), SS_PlainOverlay);
		@panel = GuiPanel(bg, Alignment(Left, Top+2, Right-2, Bottom-60));
		updateAbsolutePosition();

		@page = GuiMarkupText(panel, recti_area(8, 2, panel.size.width-25, 100));
		page.text = HELP_TEXT;

		@okButton = GuiButton(bg, Alignment(Left+0.5f-100, Bottom-56, Left+0.5f+100, Bottom-4), locale::GOT_IT);

		updateAbsolutePosition();
	}

	void close() {
		if(prevGameSpeed >= 0) {
			gameSpeed = prevGameSpeed;
			prevGameSpeed = -1.0;
		}
		GuiOverlay::close();
	}

	void remove() {
		if(prevGameSpeed >= 0) {
			gameSpeed = prevGameSpeed;
			prevGameSpeed = -1.0;
		}
		GuiOverlay::remove();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is okButton && evt.type == GUI_Clicked) {
			close();
			return true;
		}
		return GuiOverlay::onGuiEvent(evt);
	}
};

string HELP_TEXT;
HelpOverlay@ overlay;
void addHelpText(const string& str) {
	if(HELP_TEXT.length != 0)
		HELP_TEXT += "\n\n\n[hr/]\n";
	HELP_TEXT += str;

	if(!isLoadedSave) {
		if(overlay is null || overlay.parent is null) {
			showHelp();
		}
		else {
			overlay.page.text = HELP_TEXT;
			overlay.updateAbsolutePosition();
		}
	}
}

void showHelp() {
	@overlay = HelpOverlay();
	if(!isServer && gameTime < 5.0 && gameSpeed != 0 && !isClient) {
		overlay.prevGameSpeed = gameSpeed;
		gameSpeed = 0;
	}
}

void init() {
	checkHelp();
}

void checkHelp() {
	if(hasInvasionMap())
		addHelpText(locale::HELP_INVASION);
	if(playerEmpire.hasTrait(getTraitID("Ancient")))
		addHelpText(locale::HELP_ANCIENT);
	else if(playerEmpire.hasTrait(getTraitID("Extragalactic")))
		addHelpText(locale::HELP_EXTRAGALACTIC);
}

void postReload(Message& msg) {
	checkHelp();
}
// }}}
