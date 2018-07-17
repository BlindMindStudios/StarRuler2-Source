#include "include/resource_constants.as"
import elements.BaseGuiElement;
import elements.Gui3DObject;
import elements.GuiOverlay;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiStatusBox;
import elements.GuiButton;
import elements.GuiListbox;
import elements.GuiAccordion;
import elements.GuiPanel;
import elements.GuiDistributionBar;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import planets.PlanetSurface;
import elements.GuiPlanetSurface;
import elements.GuiResources;
import elements.GuiContextMenu;
import planet_levels;
import constructible;
import tile_resources;
import buildings;
import orbitals;
import util.formatting;
import icons;
import systems;
import cargo;
import statuses;
import traits;
import overlays.Construction;
from elements.GuiResources import LEVEL_REQ;
from tabs.PlanetsTab import PlanetTree;
from gui import animate_time;

const double ANIM1_TIME = 0.15;
const double ANIM2_TIME = 0.001;
const uint BORDER = 20;
const uint WIDTH = 500;
const uint S_HEIGHT = 360;
const uint INCOME_HEIGHT = 140;
const uint VAR_H = 40;
const int MIN_TILE_SIZE = 18;
const int MIN_TILE_SIZE_HD = 26;
Resources available;

bool SHOW_PLANET_TREE = false;

// {{{ Overlay
class PlanetOverlay : GuiOverlay, ConstructionParent {
	Gui3DObject@ objView;
	Planet@ obj;
	bool closing = false;

	SurfaceDisplay@ surface;
	ResourceDisplay@ resources;
	ConstructionDisplay@ construction;
	Resource[] resList;

	Alignment@ objTarget;

	PlanetOverlay(IGuiElement@ parent, Planet@ Obj) {
		super(parent);
		fade.a = 0;
		@obj = Obj;

		vec2i parSize;
		if(parent is null)
			parSize = screenSize;
		else
			parSize = parent.size;
		@objView = Gui3DObject(this, recti_area(vec2i(-456, parSize.y-228), vec2i(912, 912)));
		objView.internalRotation = quaterniond_fromAxisAngle(vec3d(0.0, 0.0, 1.0), -0.25*pi);
		@objView.object = obj;

		int plSize = parSize.x * 2;
		@objTarget = Alignment(Left+0.5f-plSize/2, Top+0.5f, Width=plSize, Height=plSize);
		recti targPos = objTarget.resolve(parSize);
		animate_time(objView, targPos, ANIM1_TIME);

		float offset = 0.05f;
		if(parSize.width > 1300)
			offset = 0.1f;

		updateAbsolutePosition();

		vec2i origin = targPos.center;
		@construction = ConstructionDisplay(this, origin, Alignment(Right-offset-WIDTH,
					Top+BORDER, Right-offset, Bottom-BORDER));
		@surface = SurfaceDisplay(this, origin, Alignment(Left+offset,
					Top+BORDER, Right-offset-BORDER-WIDTH, Top+0.6f-BORDER/2));
		@resources = ResourceDisplay(this, origin, Alignment(Left+offset,
					Top+0.6f+BORDER/2, Right-offset-BORDER-WIDTH, Bottom-BORDER));
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) override {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is objView)
			return this;
		return elem;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Animation_Complete:
				if(evt.caller is objView) {
					if(closing) {
						GuiOverlay::close();
						return true;
					}

					//Make sure the object view stays in the right position
					@objView.alignment = objTarget;

					//Start showing all the data
					surface.animate();
					resources.animate();
					construction.animate();

					return true;
				}
				break;
		}
		return GuiOverlay::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		switch(evt.type) {
			case MET_Button_Up:
				if(surface.selBuilding !is null) {
					surface.stopBuild();
					return true;
				}
				else if(resources.tree.isDragging || resources.tree.dragging !is null) {
					resources.tree.stopDragging();
					return true;
				}
				break;
		}

		return GuiOverlay::onMouseEvent(evt, source);
	}

	void close() override {
		if(parent is null || objView is null || closing)
			return;
		closing = true;
		@objView.alignment = null;

		surface.visible = false;
		resources.visible = false;
		construction.visible = false;

		vec2i parSize = parent.size;
		recti targPos = recti_area(vec2i(-456, parSize.y-228), vec2i(912, 912));
		animate_time(objView, targPos, ANIM1_TIME);
	}

	void startBuild(const BuildingType@ type) {
		if(surface !is null)
			surface.startBuild(type);
	}

	Object@ get_object() {
		return obj;
	}

	Object@ get_slaved() {
		return null;
	}

	void triggerUpdate() {
	}

	void update(double time) {
		surface.update(time);
		resources.update(time);
		construction.update(time);
	}

	void draw() {
		if(!settings::bGalaxyBG && objView.Alignment !is null)
			material::Skybox.draw(AbsolutePosition);
		GuiOverlay::draw();
	}
};

class DisplayBox : BaseGuiElement {
	PlanetOverlay@ overlay;
	Alignment@ targetAlign;

	DisplayBox(PlanetOverlay@ ov, vec2i origin, Alignment@ target) {
		@overlay = ov;
		@targetAlign = target;
		super(overlay, recti_area(origin, vec2i(1,1)));
		visible = false;
		updateAbsolutePosition();
	}

	void animate() {
		visible = true;
		animate_time(this, targetAlign.resolve(overlay.size), ANIM2_TIME);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Animation_Complete:
				@alignment = targetAlign;
				return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool pressed = false;
	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0) {
					pressed = true;
					return true;
				}
				break;
			case MET_Button_Up:
				if(evt.button == 0 && pressed) {
					pressed = false;
					return true;
				}
				break;
		}

		return BaseGuiElement::onMouseEvent(evt, source);
	}

	void remove() override {
		@overlay = null;
		BaseGuiElement::remove();
	}

	void update(double time) {
	}

	void draw() {
		skin.draw(SS_OverlayBox, SF_Normal, AbsolutePosition, Color(0x888888ff));
		BaseGuiElement::draw();
	}
};
//}}}

// {{{ Surface
class VarBox : BaseGuiElement {
	GuiSprite@ icon;
	GuiText@ value;
	Color color;

	VarBox(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);

		@icon = GuiSprite(this, Alignment(Left+4, Top+2, Left+VAR_H, Bottom-2));
		@value = GuiText(this, Alignment(Left+4, Top+2, Right-4, Bottom-6));
		value.font = FT_Subtitle;
		value.stroke = colors::Black;
		value.vertAlign = 1.0;
		value.horizAlign = 1.0;
	}

	void draw() {
		skin.draw(SS_PlainBox, SF_Normal, AbsolutePosition.padded(-2, 2, -2, 2));

		Color glowCol = color;
		glowCol.a = 0x18;
		drawRectangle(AbsolutePosition.padded(0, 3, 0, 3),
				Color(0x22222218), Color(0x22222218),
				glowCol, glowCol);

		BaseGuiElement::draw();
	}
};

class SurfaceDisplay : DisplayBox {
	Planet@ pl;

	GuiPanel@ surfPanel;
	GuiPlanetSurface@ sdisplay;
	PlanetSurface surface;

	GuiMarkupText@ name;
	GuiText@ level;

	GuiSkinElement@ resDisplay;
	GuiPanel@ varPanel;

	const BuildingType@ selBuilding;

	SurfaceDisplay(PlanetOverlay@ ov, vec2i origin, Alignment@ target) {
		super(ov, origin, target);

		@surfPanel = GuiPanel(this, Alignment(Left+158, Top+38, Right-8, Bottom-8));
		@sdisplay = GuiPlanetSurface(surfPanel, recti());
		@sdisplay.surface = surface;
		sdisplay.maxSize = 0.02 * double(ov.size.width);

		@name = GuiMarkupText(this, Alignment(Left+8, Top-2, Right-8, Top+38));
		name.noClip = true;
		name.defaultFont = FT_Big;
		name.defaultStroke = colors::Black;

		@level = GuiText(this, Alignment(Left+8, Top+8, Right-8, Top+38));
		level.font = FT_Medium;
		level.horizAlign = 1.0;
		level.stroke = colors::Black;
		level.visible = false;

		@resDisplay = GuiSkinElement(this, Alignment(Left+1, Top+38, Left+150, Bottom-2), SS_PatternBox);
		@varPanel = GuiPanel(resDisplay, Alignment().fill());

		@pl = overlay.obj;
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		DisplayBox::updateAbsolutePosition();

		if(sdisplay !is null && pl !is null) {
			int minSize = screenSize.width >= 1910 ? MIN_TILE_SIZE_HD : MIN_TILE_SIZE;
			int sw = max(surfPanel.size.width - (surfPanel.vert.visible ? 20 : 0), minSize * surface.size.width);
			int sh = max(surfPanel.size.height - (surfPanel.horiz.visible ? 20 : 0), minSize * surface.size.height);
			vec2i prevSize = sdisplay.size;
			if(prevSize.x != sw || prevSize.y != sh) {
				sdisplay.size = vec2i(sw, sh);
				surfPanel.updateAbsolutePosition();
			}
		}
	}

	void startBuild(const BuildingType@ type) {
		@selBuilding = type;
		sdisplay.showTooltip = false;
	}

	void stopBuild() {
		@selBuilding = null;
		sdisplay.showTooltip = true;
	}

	void openBuildingMenu(const vec2i& pos, SurfaceBuilding@ bld) {
		GuiContextMenu menu(mousePos);
		if(bld.type.canRemove(pl)) {
			if(bld.completion >= 1.f) {
				if(!pl.isContested)
					menu.addOption(DestroyBuildingOption(pl, format(locale::DESTROY_BUILDING, bld.type.name), pos));
			}
			else {
				menu.addOption(DestroyBuildingOption(pl, format(locale::CANCEL_BUILDING, bld.type.name), pos));
			}
		}
		menu.finalize();
	}

	uint varIndex = 0;
	array<VarBox@> variables;
	void resetVars() {
		varIndex = 0;
	}

	void addVariable(const Sprite& icon, const string& value, const string& tooltip = "", const Color& color = colors::White) {
		if(varIndex >= variables.length)
			variables.insertLast(VarBox(varPanel, recti()));

		int w = min(varPanel.size.width, 149) - 2;
		if(varPanel.vert.visible && varPanel.size.height >= 30)
			w -= 20;

		auto@ box = variables[varIndex];
		box.rect = recti_area(1, 4+varIndex*VAR_H, w, VAR_H);

		box.icon.desc = icon;
		box.value.text = value;
		box.value.color = color;
		box.color = color;
		setMarkupTooltip(box, tooltip, width=399);

		++varIndex;
	}

	void finalizeVars() {
		for(uint i = varIndex, cnt = variables.length; i < cnt; ++i)
			variables[i].remove();
		variables.length = varIndex;
	}

	void updateVars() {
		resetVars();

		if(pl.visible) {
			if(pl.owner.valid && pl.owner.HasPopulation != 0) {
				Color popColor = colors::White;
				if(!pl.primaryResourceUsable) {
					if(pl.population < getPlanetLevelRequiredPop(pl, pl.resourceLevel) && !pl.inCombat) {
						popColor = colors::Orange;
					}
				}
				string popText = standardize(pl.population, true) + " / " + standardize(pl.maxPopulation, true);
				addVariable(icons::Population, popText, locale::PLANET_POPULATION_TIP, popColor);
			}
		}
		if(pl.owner is playerEmpire) {
			auto@ scTrait = getTrait("StarChildren");
			auto@ anTrait = getTrait("Ancient");
			if((scTrait is null || !pl.owner.hasTrait(scTrait.id)) && (anTrait is null || !pl.owner.hasTrait(anTrait.id))) {
				Color color = colors::White;
				if(int(surface.totalPressure) > int(surface.pressureCap))
					color = colors::Red;
				string value = standardize(surface.totalPressure, true) + " / " + standardize(surface.pressureCap, true);
				string ttip = format(locale::PLANET_PRESSURE_TIP, standardize(surface.totalPressure, true), standardize(surface.totalSaturate, true), standardize(surface.pressureCap, true));
				addVariable(icons::Pressure, value, ttip, color);
			}
			{
				Color color = colors::Money;
				int income = pl.income;
				if(income < 0)
					color = colors::Red;
				string value = formatMoney(income);
				string ttip = format(locale::PLANET_INCOME_TIP, standardize(surface.pressures[TR_Money], true), standardize(surface.resources[TR_Money], true));
				addVariable(icons::Money, value, ttip, color);
			}

		}
		if(pl.owner.valid) {
			string loyText = toString(pl.currentLoyalty, 0);
			addVariable(icons::Loyalty, loyText, locale::PLANET_LOYALTY_TIP, colors::White);
		}
		if(pl.owner is playerEmpire) {
			if(surface.resources[TR_Energy] > 0 || surface.pressures[TR_Energy] > 0) {
				Color color = colors::Energy;
				string value = "+"+formatRate(surface.resources[TR_Energy] * TILE_ENERGY_RATE * pl.owner.EnergyEfficiency);
				string ttip = format(locale::PLANET_ENERGY_TIP, standardize(surface.pressures[TR_Energy], true), standardize(surface.saturates[TR_Energy], true));
				addVariable(icons::Energy, value, ttip, color);
			}

			if(surface.resources[TR_Defense] > 0 || surface.pressures[TR_Defense] > 0) {
				Color color = colors::Defense;
				string value = standardize(surface.resources[TR_Defense], true);
				string ttip = format(locale::PLANET_DEFENSE_TIP, standardize(surface.pressures[TR_Defense], true), standardize(surface.saturates[TR_Defense], true));
				addVariable(icons::Defense, value, ttip, color);
			}

			if(surface.resources[TR_Influence] > 0 || surface.pressures[TR_Influence] > 0) {
				Color color = colors::Influence;
				string value = standardize(surface.resources[TR_Influence], true);
				string ttip = format(locale::PLANET_INFLUENCE_TIP, standardize(surface.pressures[TR_Influence], true), standardize(surface.saturates[TR_Influence], true));
				addVariable(icons::Influence, value, ttip, color);
			}

			if(surface.resources[TR_Research] > 0 || surface.pressures[TR_Research] > 0) {
				Color color = colors::Research;
				string value = "+"+formatRate(surface.resources[TR_Research] * TILE_RESEARCH_RATE * pl.owner.ResearchEfficiency);
				string ttip = format(locale::PLANET_RESEARCH_TIP, standardize(surface.pressures[TR_Research], true), standardize(surface.saturates[TR_Research], true));
				addVariable(icons::Research, value, ttip, color);
			}

			if(pl.laborIncome > 0) {
				Color color = colors::Labor;
				string value = formatMinuteRate(pl.laborIncome);
				string ttip = format(locale::PLANET_LABOR_TIP, standardize(surface.pressures[TR_Labor], true), standardize(surface.saturates[TR_Labor], true));
				addVariable(icons::Labor, value, ttip, color);
			}

			uint cargoCnt = pl.cargoTypes;
			for(uint i = 0; i < cargoCnt; ++i) {
				auto@ type = getCargoType(pl.cargoType[i]);
				if(type is null)
					continue;
				string value = standardize(pl.getCargoStored(type.id), true);
				string ttip = format("[font=Medium]$1[/font]\n$2", type.name, type.description);
				addVariable(type.icon, value, ttip, type.color);
			}
		}

		finalizeVars();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is sdisplay) {
					if(evt.value == 1) {
						auto@ bld = sdisplay.surface.getBuilding(sdisplay.hovered.x, sdisplay.hovered.y);
						if(selBuilding !is null)
							stopBuild();
						else if(sdisplay.surface.isValidPosition(sdisplay.hovered)) {
							if(bld !is null && !bld.type.civilian)
								openBuildingMenu(sdisplay.hovered, bld);
						}
						else
							overlay.close();
						return true;
					}

					if(selBuilding !is null) {
						pl.buildBuilding(selBuilding.id, sdisplay.hovered);
						if(!shiftKey) {
							stopBuild();
							overlay.construction.deselect();
							overlay.construction.updateTimer = 0.0;
						}
					}
					return true;
				}
				break;
		}
		return DisplayBox::onGuiEvent(evt);
	}

	double updateTimer = 0.0;
	void update(double time) override {
		updateTimer -= time;
		if(updateTimer <= 0) {
			updateTimer = randomd(0.1,0.9);

			Empire@ owner = pl.visibleOwner;
			bool owned = owner is playerEmpire;
			bool colonized = owner !is null && owner.valid;

			//Update name
			name.text = format("[center][obj_icon=$1;42/] $2[/center]", pl.id, pl.name);;
			if(owner !is null)
				name.defaultColor = owner.color;

			//Update level
			uint lv = pl.level;
			level.text = locale::LEVEL+" "+lv;

			//Update surface
			@sdisplay.obj = pl;
			receive(pl.getPlanetSurface(), surface);
			if(!pl.visible)
				surface.clearState();
			updateVars();
		}
	}

	void draw() override {
		Empire@ owner = pl.visibleOwner;
		Color color;
		if(owner !is null)
			color = owner.color;

		skin.draw(SS_OverlayBox, SF_Normal, AbsolutePosition.padded(0,36,0,0), Color(0x888888ff));
		skin.draw(SS_FullTitle, SF_Normal, recti_area(AbsolutePosition.topLeft, vec2i(AbsolutePosition.width, 38)), color);
		BaseGuiElement::draw();

		if(selBuilding !is null) {
			clearClip();
			drawHoverBuilding(pl, skin, selBuilding, mousePos, sdisplay.hovered, sdisplay);
		}
	}
};

class DestroyBuildingOption : GuiContextOption {
	Object@ obj;
	vec2i pos;

	DestroyBuildingOption(Object@ obj, const string& text, const vec2i& pos) {
		this.pos = pos;
		this.text = text;
		@this.obj = obj;
	}

	void call(GuiContextMenu@ menu) override {
		obj.destroyBuilding(pos);
	}
};
// }}}

// {{{ Resources
class EffectBox : BaseGuiElement {
	GuiResources@ resources;
	GuiMarkupText@ text;
	array<const IResourceHook@> hooks;
	Object@ obj;

	GuiResources@ carryList;

	EffectBox(IGuiElement@ elem, const recti& pos) {
		super(elem, pos);
		@resources = GuiResources(this, recti_area(
					vec2i(2, 7), vec2i(100, pos.height-14)));
		resources.horizAlign = 0.0;
		@text = GuiMarkupText(this, recti(
					vec2i(52, 0), pos.size - vec2i(16, 0)));
	}

	void add(Resource@ r, const IResourceHook@ hook, Resource@ carry = null) {
		resources.resources.insertLast(r);
		hooks.insertLast(hook);

		if(carry !is null) {
			if(carryList is null) {
				@carryList = GuiResources(this, Alignment(Right-25, Bottom-25, Right+5, Bottom+5));
				carryList.sendToBack();
				carryList.horizAlign = 0.0;
			}

			bool found = false;
			for(uint i = 0, cnt = carryList.resources.length; i < cnt; ++i) {
				if(carryList.resources[i].type is carry.type) {
					found = true;
					break;
				}
			}

			if(!found)
				carryList.resources.insertLast(carry);
		}
	}

	void update(Resource@ r) {
		for(uint i = 0, cnt = resources.resources.length; i < cnt; ++i) {
			Resource@ other = resources.resources[i];
			if(other.id == r.id && other.origin is r.origin)
				other = r;
		}
	}

	void update() {
		int rSize = min(60, resources.length * 48);
		resources.size = vec2i(rSize, 30);
		text.position = vec2i(rSize+8, 0);
		text.size = size - vec2i(rSize+24+(carryList is null ? 0 : 20), 0);

		text.text = hooks[0].formatEffect(obj, hooks);

		const ResourceType@ type;
		for(uint i = 0, cnt = resources.resources.length; i < cnt; ++i) {
			if(i == 0) {
				@type = resources.resources[i].type;
			}
			else {
				if(type !is resources.resources[i].type) {
					@type = null;
					break;
				}
				else {
					@type = resources.resources[i].type;
				}
			}
		}

		if(type !is null)
			setMarkupTooltip(this, getResourceTooltip(type));
		else
			setMarkupTooltip(this, "");

		updateAbsolutePosition();
	}

	void draw() override {
		skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class ResBox : BaseGuiElement {
	const ResourceRequirement@ req;
	Resource@ resource;
	Planet@ planet;
	bool hovered = false;
	uint forLevel = 0;

	ResBox(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	string get_tooltip() {
		string tt;
		if(req !is null) {
			string sprt = getSpriteDesc(getRequirementIcon(req));
			switch(req.type) {
				case RRT_Class:
					tt = "[color=#ccc]"+format(locale::REQ_TYPE, req.cls.name, sprt)+"[/color]";
				break;
				case RRT_Level:
					tt = "[color=#ccc]"+format(locale::REQ_LEVEL, toString(req.level), sprt)+"[/color]";
				break;
			}
		}
		if(resource !is null) {
			if(tt.length != 0)
				tt += "[font=Subtitle][color=#ccc]:[/color][/font]\n[hr/][vspace=6/]";
			tt += getResourceTooltip(resource.type, resource, planet);
		}
		return tt;
	}

	void update() {
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Mouse_Entered)
			hovered = true;
		else if(evt.type == GUI_Mouse_Left)
			hovered = false;
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ caller) override {
		if(evt.type == MET_Button_Down) {
			return true;
		}
		if(evt.type == MET_Button_Up) {
			if(hovered)
				openMenu();
			return true;
		}
		return BaseGuiElement::onMouseEvent(evt, caller);
	}

	void openMenu() {
		if(!planet.owner.controlled)
			return;
		GuiContextMenu menu(mousePos);
		if(resource !is null) {
			if(resource.origin !is planet && resource.origin !is null) {
				menu.addOption(UnexportOption(planet, resource));
			}
			else if(resource.origin is planet && resource.exportedTo !is null) {
				menu.addOption(UnexportOption(planet, resource));
			}
			else if(resource.origin is null && req !is null) {
				menu.addOption(CancelAutoImportOption(planet, req));
				menu.addOption(CancelAllAutoImportOption(planet));
			}
		}
		else if(req !is null) {
			menu.addOption(AutoImportOption(planet, req));
			if(planet.resourceLevel < forLevel)
				menu.addOption(AutoImportLevelOption(planet, forLevel));
		}
		menu.finalize();
	}

	void draw() {
		if(resource !is null) {
			skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition);
			drawSmallResource(resource.type, resource, AbsolutePosition.padded(9), planet);
		}
		else if(req !is null) {
			skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition, Color(0x666666ff));
			getRequirementIcon(req).draw(AbsolutePosition.padded(4), Color(0xffffff80));
		}

		BaseGuiElement::draw();

		if(hovered)
			drawRectangle(AbsolutePosition.padded(2), Color(0xffffff10), Color(0xffffff10), Color(0xffffff20), Color(0xffffff20));
	}
};

class LevelRow : BaseGuiElement {
	Planet@ planet;

	GuiText@ reqCaption;
	GuiText@ levelCaption;

	const PlanetLevel@ reqLevel;
	array<ResBox@> reqs;

	Color bg;
	Color line;

	LevelRow(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		@levelCaption = GuiText(this, Alignment(Left, Top, Left+80, Bottom));
		levelCaption.horizAlign = 0.5;
		levelCaption.vertAlign = 0.5;
		levelCaption.stroke = colors::Black;
	}

	void take(array<Resource@>& resources, bool& doneUniversal, Resources& available) {
		for(uint i = 0, cnt = reqs.length; i < cnt; ++i) {
			int minSpec = INT_MAX;
			Resource@ res;
			reqs[i].visible = true;
			for(uint n = 0, ncnt = resources.length; n < ncnt; ++n) {
				int spec = reqs[i].req.meetQuality(resources[n].type, doneUniversal);
				if(spec == 0 || spec >= minSpec)
					continue;
				auto@ r = resources[n];
				if(r.exportedTo !is null && r.origin is planet)
					continue;
				if(!r.usable || r.origin is null)
					spec += 1;

				minSpec = spec;
				@res = resources[n];
			}

			@reqs[i].resource = res;
			if(res !is null) {
				if(res.type.mode == RM_UniversalUnique)
					doneUniversal = true;
				resources.remove(res);
				if(res.usable)
					available.modAmount(res.type, -1);
			}
			else {
				const ResourceType@ takeType;
				uint takeSpec = 0;
				for(uint n = 0, ncnt = available.types.length; n < ncnt; ++n) {
					if(available.amounts[n] <= 0)
						continue;
					auto@ rtype = getResource(available.types[n]);
					int spec = reqs[i].req.meetQuality(rtype, doneUniversal);
					if(spec == 0 || spec >= minSpec)
						continue;

					minSpec = spec;
					@takeType = rtype;
				}

				if(takeType !is null) {
					if(takeType.mode == RM_UniversalUnique)
						doneUniversal = true;
					available.modAmount(takeType, -1);
					reqs[i].visible = false;
				}
			}
		}
	}

	void update() {
		uint resLevel = planet.resourceLevel;
		uint curLevel = planet.level;

		if(reqLevel.level == curLevel) {
			levelCaption.color = Color(0x80ff80ff);
			levelCaption.stroke = colors::Black;
			levelCaption.font = FT_Bold;
			bg = Color(0x80ff80ff);
			line = Color(0x80ff80ff);
		}
		else if(reqLevel.level <= resLevel) {
			levelCaption.color = Color(0xffffffff);
			levelCaption.stroke = colors::Black;
			levelCaption.font = FT_Normal;
			bg = Color(0xffffffff);
			line = Color(0x00000000);
		}
		else if(reqLevel.level == resLevel+1 && !planet.primaryResourceExported) {
			levelCaption.color = Color(0xff8000ff);
			levelCaption.stroke = colors::Black;
			levelCaption.font = FT_Italic;
			bg = Color(0xffbb88ff);
			line = Color(0x00000000);
		}
		else {
			levelCaption.color = Color(0x666666ff);
			levelCaption.stroke = Color(0x111111ff);
			levelCaption.font = FT_Italic;
			bg = Color(0xffffffff);
			line = Color(0x00000000);
		}
	}

	void set(const PlanetLevel@ prev, const PlanetLevel@ lv) {
		if(reqLevel is lv)
			return;

		@reqLevel = lv;
		levelCaption.text = locale::LEVEL+" "+lv.level;

		array<ResourceRequirement@> pending;
		for(uint i = 0, cnt = lv.reqs.reqs.length; i < cnt; ++i) {
			auto@ p = lv.reqs.reqs[i];

			ResourceRequirement cpy;
			cpy = p;
			pending.insertLast(cpy);
		}

		for(uint i = 0, cnt = prev.reqs.reqs.length; i < cnt; ++i) {
			auto@ c = prev.reqs.reqs[i];
			uint total = c.amount;
			for(uint i = 0, cnt = pending.length; i < cnt; ++i) {
				if(!pending[i].equivalent(c))
					continue;
				uint take = min(pending[i].amount, total);
				pending[i].amount -= take;
				total -= take;

				if(pending[i].amount <= 0) {
					pending.removeAt(i);
					--i; --cnt;
				}

				if(total <= 0)
					break;
			}
		}

		uint r = 0;
		for(uint i = 0, cnt = pending.length; i < cnt; ++i) {
			auto@ p = pending[i];

			for(uint n = 0; n < p.amount; ++n) {
				ResBox@ disp;
				if(r < reqs.length) {
					@disp = reqs[r];
				}
				else {
					@disp = ResBox(this, Alignment(Left+80+r*47, Top+3, Width=44, Height=44));
					reqs.insertLast(disp);
				}

				@disp.planet = planet;
				@disp.req = p;
				disp.forLevel = lv.level;
				disp.update();
				r += 1;
			}
		}
		for(uint i = r, cnt = reqs.length; i < cnt; ++i)
			reqs[i].remove();
		reqs.length = r;
	}

	void draw() {
		skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition, bg);
		BaseGuiElement::draw();

		if(line.a != 0) {
			vec2i left = levelCaption.absolutePosition.topLeft + levelCaption.textOffset + vec2i(0, 18);
			vec2i right = vec2i(levelCaption.absolutePosition.botRight.x - levelCaption.textOffset.x, left.y);
			drawLine(left, right, line, 2);
		}
	}
};

class ResourceDisplay : DisplayBox {
	Planet@ pl;

	GuiSkinElement@ levelBar;
	GuiText@ level;

	GuiSkinElement@ requireBox;
	GuiText@ reqLabel;
	GuiText@ reqTimer;
	GuiMarkupText@ popReq;
	GuiResourceReqGrid@ reqDisplay;

	GuiSkinElement@ statusBox;
	array<GuiStatusBox@> statusIcons;

	PlanetTree@ tree;
	bool doCenter = false;

	GuiText@ reqCaption;
	array<LevelRow@> levelDisp;
	array<ResBox@> looseDisp;

	GuiPanel@ resPanel;

	GuiSkinElement@ resourceBox;
	GuiMarkupText@ resourceDesc;
	GuiMarkupText@ resourcePressure;

	GuiButton@ toggleButton;
	bool showLevels = true;
	int statusPos = 0;

	ResourceDisplay(PlanetOverlay@ ov, vec2i origin, Alignment@ target) {
		super(ov, origin, target);
		@pl = ov.obj;

		//Level indicator
		@levelBar = GuiSkinElement(this, Alignment(Left+1, Top+1, Left+192, Top+42), SS_PlainOverlay);
		@level = GuiText(levelBar, Alignment(Left+8, Top+4, Right-8, Bottom-4));
		level.font = FT_Medium;

		//Requirements
		statusPos = 513;
		if(screenSize.width < 1900)
			statusPos = 400;
		@statusBox = GuiSkinElement(this, Alignment(Left+statusPos, Top+1, Right-44, Top+42), SS_PlainOverlay);
		@requireBox = GuiSkinElement(this, Alignment(Left+200, Top+1, Left+statusPos-10, Top+42), SS_PlainOverlay);
		setMarkupTooltip(requireBox, locale::PLANET_REQUIREMENTS_TIP, width=400);
		@reqLabel = GuiText(requireBox, Alignment(Left-4, Top-6, Left+96, Top+6), locale::REQUIRED_RESOURCES);
		reqLabel.noClip = true;
		reqLabel.font = FT_Small;
		@reqTimer = GuiText(requireBox, Alignment(Right-96, Top-6, Right+4, Top+6));
		reqTimer.color = Color(0xff0000fff);
		reqTimer.noClip = true;
		reqTimer.font = FT_Small;
		reqTimer.horizAlign = 1.0;
		reqTimer.visible = false;
		@reqDisplay = GuiResourceReqGrid(requireBox, Alignment(Left+8, Top+8, Right-8, Bottom));
		reqDisplay.iconSize = vec2i(30, 30);
		reqDisplay.spacing.x = 6;
		reqDisplay.horizAlign = 0.0;
		reqDisplay.vertAlign = 0.0;
		@popReq = GuiMarkupText(requireBox, Alignment(Left+4, Top+8, Right-4, Bottom));
		popReq.visible = false;

		//Tree of local planets
		@tree = PlanetTree(this, Alignment().padded(8, 42, 8, 8));
		@tree.focusObject = pl;
		tree.visible = false;

		//Requirements display
		@resPanel = GuiPanel(this, Alignment().padded(0, 42, 0, 0));
		resPanel.horizType = ST_Never;

		showLevels = screenSize.width >= 1800;
		if(showLevels)
			@resourceBox = GuiSkinElement(resPanel, Alignment(Left+10, Top+10, Left+0.5f-5, Top+94), SS_PlainOverlay);
		else
			@resourceBox = GuiSkinElement(resPanel, Alignment(Left+10, Top+10, Right-10, Top+94), SS_PlainOverlay);
		@resourceDesc = GuiMarkupText(resourceBox, Alignment().padded(6, 6, 100, 6));
		@resourcePressure = GuiMarkupText(resourceBox, Alignment(Right-85, Top+3, Right-6, Bottom-3));

		//Display toggle button
		@toggleButton = GuiButton(this, Alignment(Right-40, Top, Right, Top+43));
		toggleButton.toggleButton = true;
		toggleButton.color = Color(0xaaaaaaff);
		toggleButton.setIcon(Sprite(material::TabPlanets, Color(0xffffff80)));
		toggleButton.pressed = SHOW_PLANET_TREE;
	}

	double updateTimer = 0.0;
	uint modID = uint(-1);
	uint reqModID = uint(-1);

	void update(double time) override {
		tree.visible = pl.owner is playerEmpire && SHOW_PLANET_TREE;
		resPanel.visible = !tree.visible;
		if(tree.visible)
			tree.tick(time);

		updateTimer -= time;
		uint newModID = pl.resourceModID;
		if(updateTimer <= 0 || reqModID != newModID) {
			updateTimer = randomd(0.1,0.9);
			level.text = locale::LEVEL+" "+pl.visibleLevel;

			Empire@ owner = pl.owner;
			bool owned = owner is playerEmpire;
			bool colonized = owner !is null && owner.valid;
			bool wasVis = requireBox.visible;

			//Update level requirements
			array<Resource>@ resList = overlay.resList;
			if(owned)
				resList.syncFrom(pl.getAllResources());
			else
				resList.syncFrom(pl.getNativeResources());

			uint lv = pl.level;
			double decay = pl.decayTime;
			uint maxLevel = getMaxPlanetLevel(pl);

			//Update statuses
			{
				array<Status> statuses;
				if(pl.statusEffectCount > 0)
					statuses.syncFrom(pl.getStatusEffects());
				if(!pl.visible) {
					for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
						if(statuses[i].type.conditionFrequency <= 0) {
							statuses.removeAt(i);
							--i; --cnt;
						}
					}
				}
				uint prevCnt = statusIcons.length, cnt = statuses.length;
				for(uint i = cnt; i < prevCnt; ++i)
					statusIcons[i].remove();
				statusIcons.length = cnt;
				for(uint i = 0; i < cnt; ++i) {
					auto@ icon = statusIcons[i];
					if(icon is null) {
						@icon = GuiStatusBox(statusBox, recti_area(2+40*i, 2, 38, 38));
						icon.noClip = true;
						@statusIcons[i] = icon;
					}
					icon.update(statuses[i]);
				}
			}

			//Update level display
			if(reqModID != newModID) {
				reqModID = newModID;

				available.clear();
				receive(pl.getResourceAmounts(), available);

				int chain = pl.levelChain;
				uint maxLevel = getMaxPlanetLevel(chain);
				int plMax = pl.maxLevel;
				if(plMax >= 0)
					maxLevel = min(plMax, maxLevel);
				if(!showLevels)
					maxLevel = 0;
				uint y = 10;
				for(uint i = 0; i < maxLevel; ++i) {
					LevelRow@ row;
					if(i < levelDisp.length) {
						@row = levelDisp[i];
					}
					else {
						@row = LevelRow(resPanel, Alignment(Left+0.5f+5, Top+y+(i*54), Right-10, Height=50));
						levelDisp.insertLast(row);
					}

					@row.planet = pl;
					row.set(getPlanetLevel(chain, i), getPlanetLevel(chain, i+1));
					row.update();
				}
				for(uint i = maxLevel, cnt = levelDisp.length; i < cnt; ++i)
					levelDisp[i].remove();
				levelDisp.length = maxLevel;

				array<Resource@> take;
				for(uint i = 0, cnt = resList.length; i < cnt; ++i) {
					take.insertLast(resList[i]);
				}

				bool doneUniversal = false;
				Resources checkList;
				checkList = available;
				for(uint i = 0, cnt = levelDisp.length; i < cnt; ++i)
					levelDisp[i].take(take, doneUniversal, checkList);

				bool needUpdate = false;
				for(uint i = 0, cnt = take.length; i < cnt; ++i) {
					ResBox@ disp;
					if(i < looseDisp.length) {
						@disp = looseDisp[i];
					}
					else {
						@disp = ResBox(resPanel, null);
						looseDisp.insertLast(disp);
						needUpdate = true;
					}

					@disp.planet = pl;
					@disp.resource = take[i];
					disp.update();
				}
				for(uint i = take.length, cnt = looseDisp.length; i < cnt; ++i)
					looseDisp[i].remove();
				looseDisp.length = take.length;
				if(needUpdate)
					updateLoosePositions();

				if(resList.length > 0) {
					//Update native resource description box
					auto@ type = resList[0].type;
					auto@ res = resList[0];
					string desc = format("[img=$2;20/] [font=Bold]$1[/font]\n[color=#aaa]", type.name, getSpriteDesc(type.smallIcon));

					if(type.blurb.length == 0)
						desc += format(type.description, toString(pl.level, 0));
					else
						desc += format(type.blurb, toString(pl.level, 0));
					if(type.blurb.length == 0 && type.description.length == 0) {
						if(type.level > 0) {
							desc += format(locale::RESOURCE_TIER_DESC,
								toString(type.level),
								type.level < LEVEL_REQ.length ? getSpriteDesc(LEVEL_REQ[type.level]) : "ResourceClassIcons::5");
						}
					}
					desc += "[/color]";
					resourceDesc.text = desc;

					string pres;
					int iconSize = 26;
					uint presCount = 0;
					for(uint i = 0; i < TR_COUNT; ++i) {
						if(type.tilePressure[i] != 0)
							presCount += 1;
					}
					if(presCount >= 3)
						iconSize = 16;
					else if(presCount > 2)
						iconSize = 20;

					uint c = 0;
					for(uint i = 0; i < TR_COUNT; ++i) {
						if(type.tilePressure[i] == 0)
							continue;

						int maxpres = type.tilePressure[i];
						int curpres = max(round(float(maxpres) * res.efficiency), 0.f);
						if(!owned)
							curpres = maxpres;

						if(curpres == maxpres)
							pres += format("[img=$2;$3/]  $1", toString(maxpres), getTileResourceSpriteSpec(i), toString(iconSize));
						else
							pres += format("[img=$3;$4/]  $1/$2", toString(curpres), toString(maxpres), getTileResourceSpriteSpec(i), toString(iconSize));

						c += 1;
						if(presCount < 3 || c%2 == 0)
							pres += "\n";
						else
							pres += "  ";
					}

					if(presCount >= 3)
						resourcePressure.text = pres;
					else
						resourcePressure.text = "[font=Medium]"+pres+"[/font]";

					setMarkupTooltip(resourceBox, getResourceTooltip(type, res, pl), width=350);
					resourceBox.visible = true;
				}
				else {
					resourceBox.visible = false;
				}
			}

			if(!owned || (lv == maxLevel && decay <= 0) || (lv >= uint(pl.maxLevel) && decay <= 0)) {
				requireBox.visible = false;
			}
			else if(decay > 0) {
				requireBox.visible = true;
				reqTimer.visible = true;
				reqTimer.text = formatTime(decay);
				reqLabel.color = Color(0xff0000ff);
				reqLabel.tooltip = format(locale::REQ_STOP_DECAY, toString(lv-1), formatTime(decay));

				uint newMod = pl.resourceModID;
				if(newMod != modID) {
					const PlanetLevel@ lvl = getPlanetLevel(pl, lv);
					reqDisplay.set(lvl.reqs, available);
					reqDisplay.visible = true;
					reqLabel.visible = true;

					popReq.visible = reqDisplay.length == 0 && owner.HasPopulation != 0;
					if(popReq.visible)
						popReq.text = format(locale::POP_REQ, standardize(lvl.requiredPop, true));

					reqLabel.tooltip = format(locale::REQ_FOR_LEVEL, toString(lv + 1));
					modID = newMod;
				}
			}
			else {
				requireBox.visible = true;
				reqTimer.visible = false;
				reqLabel.color = Color(0xffffffff);

				uint newMod = pl.resourceModID;
				if(newMod != modID) {
					const PlanetLevel@ lvl = getPlanetLevel(pl, lv + 1);
					reqDisplay.set(lvl.reqs, available);
					reqDisplay.visible = true;
					reqLabel.visible = true;

					popReq.visible = reqDisplay.length == 0 && owner.HasPopulation != 0;
					if(popReq.visible)
						popReq.text = format(locale::POP_REQ, standardize(lvl.requiredPop, true));

					reqLabel.text = format(locale::REQUIRED_RESOURCES, toString(lv+1));
					reqLabel.tooltip = format(locale::REQ_FOR_LEVEL, toString(lv + 1));
					modID = newMod;
				}
			}

			if(wasVis != requireBox.visible || !statusBox.visible) {
				if(requireBox.visible)
					statusBox.alignment.left.pixels = statusPos;
				else
					statusBox.alignment.left.pixels = 200;
				statusBox.visible = true;
				statusBox.updateAbsolutePosition();
			}
		}
	}

	void updateAbsolutePosition() {
		DisplayBox::updateAbsolutePosition();
		updateLoosePositions();
	}

	void updateLoosePositions() {
		if(resPanel is null)
			return;
		int perRow = (resPanel.size.width/2 - 10) / 47;
		if(!showLevels)
			perRow = (resPanel.size.width - 30) / 47;
		if(perRow == 0)
			perRow = 1;

		int start = 10;
		for(uint i = 0, cnt = looseDisp.length; i < cnt; ++i) {
			looseDisp[i].rect = recti_area(
				vec2i(start+(i%perRow)*47, 100+(i/perRow)*47),
				vec2i(44, 44));
		}
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Animation_Complete:
				updateAbsolutePosition();
				tree.update();
				updateAbsolutePosition();
				doCenter = true;
			break;
			case GUI_Clicked:
				if(evt.caller is toggleButton) {
					SHOW_PLANET_TREE = toggleButton.pressed;
					return true;
				}
			break;
		}
		return DisplayBox::onGuiEvent(evt);
	}

	void draw() {
		DisplayBox::draw();
		if(doCenter) {
			doCenter = false;
			tree.center();
		}
	}
};

class UnexportOption : GuiContextOption {
	Resource r;

	UnexportOption(Planet@ pl, Resource@ res) {
		this.r = res;
		if(res.origin is pl)
			this.text = format(locale::OPT_CANCEL_EXPORT, r.type.name);
		else
			this.text = format(locale::OPT_CANCEL_IMPORT, r.type.name, r.origin.name);
	}

	void call(GuiContextMenu@ menu) override {
		r.origin.exportResource(r.id, null);
	}
};

class AutoImportOption : GuiContextOption {
	Planet@ planet;
	ResourceRequirement req;

	AutoImportOption(Planet@ pl, const ResourceRequirement@ req) {
		@this.planet = pl;
		this.req = req;
		this.text = locale::OPT_IMPORT_AUTO;
	}

	void call(GuiContextMenu@ menu) override {
		if(req.type == RRT_Class)
			planet.owner.autoImportResourceOfClass(planet, req.cls.id);
		else if(req.type == RRT_Level)
			planet.owner.autoImportResourceOfLevel(planet, req.level);
		else if(req.type == RRT_Resource)
			planet.owner.autoImportResourceOfType(planet, req.resource.id);
	}
};

class AutoImportLevelOption : GuiContextOption {
	Planet@ planet;
	uint toLevel;

	AutoImportLevelOption(Planet@ pl, uint level) {
		@this.planet = pl;
		this.toLevel = level;
		this.text = format(locale::AUTO_IMPORT_LEVEL, toString(level));
	}

	void call(GuiContextMenu@ menu) override {
		planet.owner.autoImportToLevel(planet, toLevel);
	}
};

class CancelAutoImportOption : GuiContextOption {
	Planet@ planet;
	ResourceRequirement req;

	CancelAutoImportOption(Planet@ pl, const ResourceRequirement@ req) {
		@this.planet = pl;
		this.req = req;
		this.text = locale::OPT_IMPORT_AUTO_CANCEL;
	}

	void call(GuiContextMenu@ menu) override {
		if(req.type == RRT_Class)
			planet.owner.cancelAutoImportClassTo(planet, req.cls.id);
		else if(req.type == RRT_Level)
			planet.owner.cancelAutoImportLevelTo(planet, req.level);
		else if(req.type == RRT_Resource)
			planet.owner.cancelAutoImportTo(planet, req.resource.id);
	}
};

class CancelAllAutoImportOption : GuiContextOption {
	Planet@ planet;

	CancelAllAutoImportOption(Planet@ pl) {
		@this.planet = pl;
		this.text = locale::OPT_IMPORT_AUTO_CANCEL_ALL;
	}

	void call(GuiContextMenu@ menu) override {
		planet.owner.cancelAutoImportTo(planet);
	}
};
// }}}

import void openOverlay(Object@) from "tabs.GalaxyTab";
import void resetInfoBar() from "tabs.GalaxyTab";
import void resetGalaxyTabs() from "tabs.GalaxyTab";
from obj_selection import selectedObject;
void postReload(Message& msg) {
	resetGalaxyTabs();
	resetInfoBar();
	openOverlay(selectedObject);
}
