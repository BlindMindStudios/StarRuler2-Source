import elements.BaseGuiElement;
import elements.GuiButton;
import elements.MarkupTooltip;
import elements.GuiContextMenu;
import abilities;
import tabs.Tab;
import util.formatting;
import targeting.ObjectTarget;
import targeting.PointTarget;
import ftl;
import icons;
import systems;
import ship_groups;
from obj_selection import selectObject, selectedObjects;
from targeting.Hyperdrive import targetHyperdrive;
from targeting.Jumpdrive import targetJumpdrive;
from targeting.Fling import targetFling;
from targeting.Slipstream import targetSlipstream;

import InfoBar@ makeOrbitalInfoBar(IGuiElement@ parent, Object@ obj) from "overlays.OrbitalInfoBar";
import InfoBar@ makePlanetInfoBar(IGuiElement@ parent, Object@ obj) from "overlays.PlanetInfoBar";
import InfoBar@ makeShipInfoBar(IGuiElement@ parent, Object@ obj) from "overlays.ShipInfoBar";
import InfoBar@ makeAsteroidInfoBar(IGuiElement@ parent, Object@ obj) from "overlays.AsteroidInfoBar";
import InfoBar@ makeArtifactInfoBar(IGuiElement@ parent, Object@ obj) from "overlays.ArtifactInfoBar";
import void toggleSupportOverlay(Object@ obj) from "tabs.GalaxyTab";
import void openOverlay(Object@ obj) from "tabs.GalaxyTab";

export InfoBar, createInfoBar;
export BarAction, ActionBar;

class InfoBar : BaseGuiElement {
	InfoBar(IGuiElement@ parent) {
		super(parent, Alignment(Left+0.1f, Bottom-68, Right-0.1f, Bottom));
		updateAbsolutePosition();
	}

	bool compatible(Object@ obj) {
		return true;
	}

	Object@ get() {
		return null;
	}

	void set(Object@ obj) {
	}

	bool displays(Object@ obj) {
		return get() is obj;
	}

	void update(double time) {
	}

	bool showManage(Object@ obj) {
		return false;
	}

	bool get_showingManage() {
		return false;
	}

	IGuiElement@ findTab() {
		IGuiElement@ check = parent;
		while(check !is null && cast<Tab>(check) is null)
			@check = check.parent;
		return check;
	}
};

const int BTN_SIZE = 40;
const int BTN_PADD = 12;
const int BTN_SPACE = 12;
class BarAction : GuiButton {
	Object@ obj;
	Sprite icon;

	BarAction() {
		super(NoParent=true);
	}

	int get_needWidth() {
		return BTN_SIZE;
	}

	void set_tooltip(const string& text) override {
		setMarkupTooltip(this, text, width=400, hoverStyle=true);
	}

	void update(double time) {
	}

	bool opEquals(const BarAction& other) const {
		return getClass(this) is getClass(other);
	}

	void init() {
	}

	void postInit() {
	}

	void call() {
	}

	void from(BarAction@ act) {
	}

	bool onGuiEvent(const GuiEvent& evt) override{
		if(evt.type == GUI_Clicked) {
			call();
			return true;
		}
		return GuiButton::onGuiEvent(evt);
	}

	void draw() override {
		GuiButton::draw();
		icon.draw(AbsolutePosition.padded(4));
	}
};

funcdef void TrivialCB();
class TrivialAction : BarAction {
	TrivialCB@ cb;
	bool doSelect;

	TrivialAction(TrivialCB@ cb, const string& text, const Sprite& icon, bool doSelect = true) {
		super();
		@this.cb = cb;
		this.tooltip = text;
		this.icon = icon;
		this.doSelect = doSelect;
	}

	void call() {
		if(doSelect && !obj.selected)
			selectObject(obj);
		cb();
	}
}

class AbilityAction : BarAction {
	Ability@ abl;
	string str;
	Object@ objCast;
	bool expanded = false;
	bool independent = false;

	int get_needWidth() {
		return expanded ? 160 : BTN_SIZE;
	}

	AbilityAction(Ability@ abl, const string& opt, Object@ objCast = null, bool expanded = false) {
		@this.abl = abl;
		@this.objCast = objCast;
		this.expanded = expanded;
		@abl.emp = playerEmpire;
		str = opt;
	}

	void init() override {
		tooltip = abl.formatTooltip();

		bool usable = true;
		if(abl.cooldown > 0)
			usable = false;
		if(!abl.canActivate())
			usable = false;

		if(usable) {
			double cost = abl.getEnergyCost();
			if(cost > 0) {
				double have = abl.emp.EnergyStored;
				if(cost > have)
					usable = false;
			}
		}

		if(abl.obj !is null && abl.obj.isArtifact) {
			auto@ reg = abl.obj.region;
			if(reg is null)
				usable = false;
			else if(reg.PlanetsMask != 0)
				usable = usable ? (reg.PlanetsMask & playerEmpire.mask != 0) : false;
			else
				usable = usable ? hasTradeAdjacent(playerEmpire, reg) : false;
		}

		disabled = !usable;

		if(expanded || independent) {
			if(disabled)
				color = colors::Red;
			else
				color = colors::Energy;
		}
		else
			color = colors::White;
	}

	void call() override {
		if(abl.type.targets.length == 0) {
			if(abl.obj !is null)
				abl.obj.activateAbility(abl.id);
			else
				abl.emp.activateAbility(abl.id);
			if(abl.type.activateSound !is null)
				abl.type.activateSound.play(priority=true);
		}
		else if(abl.type.targets[0].type == TT_Point) {
			targetPoint(AbilityTargetPoint(abl));
		}
		else if(abl.type.targets[0].type == TT_Object) {
			if(objCast !is null) {
				abl.emp.activateAbility(abl.id, objCast);
			}
			else {
				targetObject(AbilityTargetObject(abl));
			}
		}
	}

	void from(BarAction@ act) override {
		@abl = cast<AbilityAction>(act).abl;
		str = cast<AbilityAction>(act).str;
		expanded = cast<AbilityAction>(act).expanded;
		init();
	}

	void draw() override {
		GuiButton::draw();
		const Font@ ft = skin.getFont(FT_Small);
		recti pos = AbsolutePosition.padded(4);
		if(expanded || independent)
			pos = recti_area(vec2i(4,4) + AbsolutePosition.topLeft,
					vec2i(AbsolutePosition.height-4, AbsolutePosition.height-4));
		if(abl.cooldown <= 0) {
			abl.type.icon.draw(pos.aspectAligned(abl.type.icon.aspect));
		}
		else {
			if(abl.cooldown > 0) {
				if(abl.type.cooldown == 0)
					shader::PROGRESS = 1.f - clamp(abl.cooldown / abl.type.cooldown, 0.f, 1.f);
				else
					shader::PROGRESS = 0.f;
				shader::DIM_FACTOR = 0.2f;
				abl.type.icon.draw(pos.aspectAligned(abl.type.icon.aspect), color=colors::White, shader=shader::RadialDimmed);
				ft.draw(pos=pos, text=formatShortTime(abl.cooldown), color=colors::Red, horizAlign=0.5, vertAlign=1.0);
			}
			else if(abl.type.cooldown > 0) {
				abl.type.icon.draw(pos.aspectAligned(abl.type.icon.aspect));
				ft.draw(pos=pos, text=formatShortTime(abl.type.cooldown), color=colors::Green, horizAlign=0.5, vertAlign=1.0);
			}
		}

		if(expanded) {
			pos = recti_area(vec2i(AbsolutePosition.topLeft.x+AbsolutePosition.height, AbsolutePosition.topLeft.y+2),
					vec2i(AbsolutePosition.width-AbsolutePosition.height, AbsolutePosition.height-4));

			auto cost = abl.getEnergyCost();

			if(cost <= 0) {
				@ft = skin.getFont(FT_Bold);
				ft.draw(pos=pos, horizAlign=0.0, vertAlign=0.1, text=abl.type.name);
			}
			else {
				@ft = skin.getFont(FT_Bold);
				ft.draw(pos=pos, horizAlign=0.0, vertAlign=0.1, text=locale::ACTIVATE);

				string txt = format("$1 $2", toString(cost, 0), locale::RESOURCE_ENERGY);
				ft.draw(pos=pos, horizAlign=0.5, vertAlign=0.85, text=txt, color=colors::Energy);
			}
		}
		else if(independent) {
			pos = recti_area(vec2i(AbsolutePosition.topLeft.x+AbsolutePosition.height, AbsolutePosition.topLeft.y+2),
					vec2i(AbsolutePosition.width-AbsolutePosition.height, AbsolutePosition.height-4));

			@ft = skin.getFont(FT_Bold);
			ft.draw(pos=pos, horizAlign=0.5, vertAlign=0.5, text=abl.type.name);
		}
	}
};

class SupportsAction : BarAction {
	void init() override {
		icon = icons::ManageSupports;
		tooltip = locale::TT_MANAGE_PLANET_SUPPORTS;
	}

	void call() override {
		selectObject(obj);
		toggleSupportOverlay(obj);
	}
};

class ConstructionAction : BarAction {
	void init() override {
		icon = icons::Labor;
		tooltip = locale::TT_OPEN_CONSTRUCTION;
	}

	void call() override {
		selectObject(obj);
		openOverlay(obj);
	}
};

class ScoutAction : BarAction {
	bool useFTL = false;
	
	ScoutAction(bool ftl) {
		useFTL = ftl;
	}

	void init() override {
		if(useFTL) {
			icon = icons::HyperExplore;
			tooltip = locale::TT_EXPLORE_FTL;
		}
		else {
			icon = icons::Explore;
			tooltip = locale::TT_EXPLORE;
		}
	}

	void call() override {
		obj.addAutoExploreOrder(useFTL, shiftKey);
	}
};

class ModeAction : BarAction {
	uint mode = 0;
	array<string> names;
	array<string> descriptions;
	array<Sprite> icons;

	void init() override {
		value = get();
	}

	void set_value(uint v) {
		mode = min(v, names.length-1);
		icon = icons[mode];
		tooltip = format("[img=$1;42][font=Subtitle][b]$2[/b][/font]\n$3[/img]",
			getSpriteDesc(icons[mode]), names[mode], descriptions[mode]);
	}

	void update(double time) {
		uint val = get();
		if(val != mode)
			this.value = val;
	}

	void call() override {
		GuiContextMenu menu(mousePos, 400);
		menu.itemHeight = 64;

		for(uint i = 0, cnt = names.length; i < cnt; ++i) {
			string text = format("[font=Subtitle][b]$1[/b][/font]\n$2",
				names[i], descriptions[i]);
			menu.addOption(ModeOption(this), text, icons[i], i);
		}

		menu.finalize();
	}

	void call(uint type) {
		value = type;
		set(type);
		for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i) {
			Object@ other = selectedObjects[i];
			if(other !is obj)
				setSecondary(other, type);
		}
	}

	uint get() {
		return 0;
	}

	void set(uint type) {
		set(obj, type);
	}

	void set(Object& obj, uint type) {
	}

	void setSecondary(Object& obj, uint type) {
		set(obj, type);
	}
};

class ModeOption : GuiMarkupContextOption {
	ModeAction@ act;
	ModeOption(ModeAction@ act) {
		@this.act = act;
	}

	void call(GuiContextMenu@ menu) override {
		act.call(value);
	}
};

class AutoModeAction : ModeAction {
	AutoModeAction() {
		names.insertLast(locale::HOLD_POSITION);
		descriptions.insertLast(locale::HOLD_POSITION_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+12);

		names.insertLast(locale::AREA_BOUND);
		descriptions.insertLast(locale::AREA_BOUND_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+13);

		names.insertLast(locale::REGION_BOUND);
		descriptions.insertLast(locale::REGION_BOUND_DESC);
		icons.insertLast((spritesheet::ActionBarIcons+13)*Color(0xff8080ff));

		names.insertLast(locale::HOLD_FIRE);
		descriptions.insertLast(locale::HOLD_FIRE_DESC);
		icons.insertLast(Sprite(material::Minus));
	}

	uint get() override {
		switch(obj.getAutoMode()) {
			case AM_HoldPosition: return 0;
			case AM_AreaBound: return 1;
			case AM_RegionBound: return 2;
			case AM_HoldFire: return 3;
		}
		return 0;
	}

	void set(Object& obj, uint type) override {
		uint autoMode = AM_AreaBound;
		switch(type) {
			case 0: autoMode = AM_HoldPosition; break;
			case 1: autoMode = AM_AreaBound; break;
			case 2: autoMode = AM_RegionBound; break;
			case 3: autoMode = AM_HoldFire; break;
		}
		obj.setAutoMode(autoMode);
	}
};

class EngageBehaveAction : ModeAction {
	EngageBehaveAction() {
		names.insertLast(locale::BEH_CLOSE_IN);
		descriptions.insertLast(locale::BEH_CLOSE_IN_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+16);

		names.insertLast(locale::BEH_KEEP_DISTANCE);
		descriptions.insertLast(locale::BEH_KEEP_DISTANCE_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+17);
	}

	uint get() override {
		return obj.getEngageBehave();
	}

	void set(Object& obj, uint type) override {
		obj.setEngageBehave(type);
	}
};

class EngageTypeAction : ModeAction {
	EngageTypeAction() {
		names.insertLast(locale::ENG_FLAGSHIP_MIN);
		descriptions.insertLast(locale::ENG_FLAGSHIP_MIN_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+20);

		names.insertLast(locale::ENG_FLAGSHIP_MAX);
		descriptions.insertLast(locale::ENG_FLAGSHIP_MAX_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+21);

		names.insertLast(locale::ENG_SUPPORT_MIN);
		descriptions.insertLast(locale::ENG_SUPPORT_MIN_DESC);
		icons.insertLast(spritesheet::ActionBarIcons+22);

		names.insertLast(locale::ENG_RAIDING_ONLY);
		descriptions.insertLast(locale::ENG_RAIDING_ONLY_DESC);
		icons.insertLast(Sprite(spritesheet::ActionBarIcons, 22, Color(0xff0000ff)));
	}

	uint get() override {
		return obj.getEngageType();
	}

	void set(Object& obj, uint type) override {
		obj.setEngageType(type);
	}
};

class ActionBar : BaseGuiElement {
	array<BarAction@> actions;
	uint index = 0;

	ActionBar(IGuiElement@ bar, vec2i pos) {
		super(bar, recti_area(pos, vec2i(100, BTN_SIZE+BTN_PADD*2)));
	}

	void clear() {
		index = 0;
	}

	void add(BarAction@ act) {
		if(index >= actions.length) {
			@act.parent = this;
			actions.insertLast(act);
		}
		else {
			if(act != actions[index]) {
				actions[index].remove();
				@act.parent = this;
				@actions[index] = act;
			}
			else {
				actions[index].from(act);
			}
		}
		++index;
	}

	void init(Object@ obj) {
		for(uint i = index, cnt = actions.length; i < cnt; ++i)
			actions[i].remove();

		actions.length = index;
		for(uint i = 0, cnt = actions.length; i < cnt; ++i) {
			@actions[i].obj = obj;
			actions[i].init();
			actions[i].postInit();
		}
		visible = actions.length != 0;
		updateAbsolutePosition();
	}

	void update(double time) {
		for(uint i = 0, cnt = actions.length; i < cnt; ++i)
			actions[i].update(time);
	}

	void addBasic(Object@ obj) {
		if(obj.hasLeaderAI) {
			if(obj.SupplyCapacity > 0)
				add(SupportsAction());
			if(obj.hasMover && !obj.hasOrbit) {
				add(AutoModeAction());
				add(EngageBehaveAction());
				add(EngageTypeAction());
			}
			if(!obj.isPlanet && obj.hasConstruction)
				add(ConstructionAction());
		}
	}
	
	void addScouting(Object@ obj) {
		if(obj.hasLeaderAI && obj.getFleetMaxStrength() < 5000.0 && obj.owner.ForbidDeepSpace == 0) {
			add(ScoutAction(ftl=false));
			if(obj.owner.hasFlingBeacons || canHyperdrive(obj) || canJumpdrive(obj))
				add(ScoutAction(ftl=true));
		}
	}

	void addAbilities(Object@ obj, bool expanded = false) {
		if(!obj.hasAbilities)
			return;

		array<Ability> abilities;
		abilities.syncFrom(obj.getAbilities());

		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			Ability@ abl = abilities[i];
			if(abl.disabled)
				continue;

			string option = format(locale::ABILITY_TRIGGER, abl.type.name);
			double cost = abl.getEnergyCost();
			if(cost > 0)
				option += format(locale::ABILITY_ENERGY, standardize(cost));

			add(AbilityAction(abl, option, expanded=expanded));
		}
	}

	void addEmpireAbilities(Empire@ emp, Object@ obj) {
		array<Ability> abilities;
		abilities.syncFrom(emp.getAbilities());

		Targets targs;
		@targs.add(TT_Object, fill=true).obj = obj;

		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			Ability@ abl = abilities[i];
			if(abl.disabled)
				continue;
			if(obj is null) {
				if(abl.type.objectCast != -1)
					continue;
				if(abl.type.hideGlobal)
					continue;
			}
			else {
				if(abl.type.objectCast == -1)
					continue;
				if(!abl.canActivate(targs, ignoreCost=true))
					continue;
			}

			string option = format(locale::ABILITY_TRIGGER, abl.type.name);
			double cost = abl.getEnergyCost();
			if(cost > 0)
				option += format(locale::ABILITY_ENERGY, standardize(cost));

			add(AbilityAction(abl, option, obj));
		}
	}

	void addFTL(Object@ obj) {
		if(canHyperdrive(obj))
			add(TrivialAction(targetHyperdrive, locale::TT_HYPERDRIVE, icons::Hyperdrive));
		if(canJumpdrive(obj))
			add(TrivialAction(targetJumpdrive, locale::TT_JUMPDRIVE, icons::Hyperdrive));
		if(canFling(obj) && obj.owner.getFlingBeacon(obj.position) !is null)
			add(TrivialAction(targetFling, locale::TT_FLING, icons::Fling));
		if(canSlipstream(obj))
			add(TrivialAction(targetSlipstream, locale::TT_SLIPSTREAM, icons::Slipstream));
	}

	void updateAbsolutePosition() override {
		int w = BTN_PADD;
		for(uint i = 0, cnt = actions.length; i < cnt; ++i) {
			if(i != 0)
				w += BTN_SPACE;
			int size = actions[i].needWidth;
			actions[i].size = vec2i(size, BTN_SIZE);
			actions[i].position = vec2i(w, 8);
			w += size;
		}

		w += BTN_PADD;
		size = vec2i(w, BTN_SIZE + BTN_PADD*2);
		BaseGuiElement::updateAbsolutePosition();
	}
};

InfoBar@ createInfoBar(IGuiElement@ parent, Object& obj) {
	if(obj.isPlanet)
		return makePlanetInfoBar(parent, obj);
	if(obj.isShip)
		return makeShipInfoBar(parent, obj);
	if(obj.isOrbital)
		return makeOrbitalInfoBar(parent, obj);
	if(obj.isAsteroid)
		return makeAsteroidInfoBar(parent, obj);
	if(obj.isArtifact)
		return makeArtifactInfoBar(parent, obj);
	return null;
}
