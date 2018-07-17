import overlays.InfoBar;
import elements.GuiResources;
import elements.GuiIconGrid;
import elements.GuiSprite;
import elements.GuiStatusBox;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.Gui3DObject;
import elements.GuiSkinElement;
import elements.MarkupTooltip;
import constructible;
import resources;
import obj_selection;
import planet_levels;
import util.constructible_view;
import util.formatting;
import icons;
import targeting.ObjectTarget;
import statuses;
from elements.GuiResources import LEVEL_REQ;
from overlays.ContextMenu import openContextMenu;
from overlays.PlanetOverlay import PlanetOverlay;
from tabs.GalaxyTab import zoomTabTo, openOverlay, toggleSupportOverlay;

//Temporary to avoid allocations
Resources available;

Color boxColors(0xffffffff);

class PlanetInfoBar : InfoBar {
	Constructible[] cons;
	array<Status> statuses;

	Planet@ pl;
	PlanetOverlay@ overlay;
	Gui3DObject@ objView;

	GuiSkinElement@ nameBox;
	GuiText@ name;

	GuiSkinElement@ levelBox;
	GuiText@ level;

	GuiSkinElement@ requireBox;
	GuiText@ reqLabel;
	GuiText@ reqTimer;
	GuiMarkupText@ popReq;
	GuiResourceReqGrid@ reqDisplay;

	GuiSkinElement@ resourceBox;
	GuiResourceGrid@ resources;
	GuiMarkupText@ resourceDesc;

	GuiSkinElement@ popBox;
	GuiSprite@ popIcon;
	GuiText@ popValue;

	GuiSkinElement@ consBox;

	GuiSkinElement@ statusBox;
	GuiMarkupText@ statusText;

	GuiSkinElement@ actionBG;
	ActionBar@ actions;

	array<GuiStatusBox@> statusIcons;
	GuiSkinElement@ statusList;

	PlanetInfoBar(IGuiElement@ parent) {
		super(parent);
		@alignment = Alignment(Left, Bottom-228, Left+456, Bottom);

		@actionBG = GuiSkinElement(this, recti_area(vec2i(335, 172), vec2i(100, 60)), SS_Panel);
		actionBG.noClip = true;

		@objView = Gui3DObject(this, Alignment(
			Left-1.f, Top, Right, Bottom+3.f));
		objView.internalRotation = quaterniond_fromAxisAngle(vec3d(0.0, 0.0, 1.0), -0.25*pi);

		@actions = ActionBar(this, vec2i(385, 172));
		actions.noClip = true;

		int y = 40;
		@nameBox = GuiSkinElement(this, Alignment(Left+5, Top+y, Left+0.4f-4, Top+y+34), SS_PlainOverlay);
		nameBox.color = boxColors;
		@name = GuiText(nameBox, Alignment().padded(10, 0));
		name.font = FT_Medium;
		name.stroke = colors::Black;

		y += 40;
		@levelBox = GuiSkinElement(this, Alignment(Left+5, Top+y, Left+0.22f-4, Top+y+34), SS_PlainOverlay);
		levelBox.color = boxColors;
		@level = GuiText(levelBox, Alignment().padded(8, 0));
		level.stroke = colors::Black;
		level.font = FT_Medium;

		@requireBox = GuiSkinElement(this, Alignment(Left+0.22f+4, Top+y, Left+0.55f, Top+y+34), SS_PlainOverlay);
		requireBox.color = boxColors;
		@reqLabel = GuiText(requireBox, Alignment(Left-4, Top-6, Left+96, Top+6), locale::REQUIRED_RESOURCES);
		reqLabel.noClip = true;
		reqLabel.font = FT_Small;
		reqLabel.stroke = colors::Black;
		@reqTimer = GuiText(requireBox, Alignment(Right-96, Top-6, Right+4, Top+6));
		reqTimer.color = Color(0xff0000fff);
		reqTimer.noClip = true;
		reqTimer.font = FT_Small;
		reqTimer.horizAlign = 1.0;
		reqTimer.visible = false;
		reqTimer.stroke = colors::Black;
		@reqDisplay = GuiResourceReqGrid(requireBox, Alignment(Left+8, Top+8, Right-8, Bottom));
		reqDisplay.spacing.x = 6;
		reqDisplay.horizAlign = 0.0;
		reqDisplay.vertAlign = 0.0;
		@popReq = GuiMarkupText(requireBox, Alignment(Left+4, Top+8, Right-4, Bottom));
		popReq.visible = false;

		y += 38;

		@resourceBox = GuiSkinElement(this, Alignment(), SS_PlainOverlay);
		resourceBox.color = boxColors;
		@resources = GuiResourceGrid(resourceBox, Alignment(Left+8, Top+5, Right-8, Bottom-2));
		resources.spacing.x = 6;
		resources.horizAlign = 0.0;
		resources.vertAlign = 0.0;
		@resourceDesc = GuiMarkupText(resourceBox, Alignment(Left+8, Bottom-42, Right-8, Bottom));
		resourceDesc.visible = false;
		resourceDesc.defaultColor = Color(0xaaaaaaff);

		@statusList = GuiSkinElement(this, Alignment(Left+295, Top+118, Left+295+34, Top+118+70), SS_PlainBox);
		statusList.noClip = true;
		statusList.visible = false;

		@statusBox = GuiSkinElement(this, Alignment(Left+5, Top+153, Left+295, Bottom-2), SS_PlainOverlay);
		statusBox.color = boxColors;
		@statusText = GuiMarkupText(statusBox, Alignment().padded(2,0));
		statusBox.visible = false;

		int x = 5;
		y += 72;
		@popBox = GuiSkinElement(this, Alignment(Left, Bottom-32, Left+x+94, Bottom), SS_HorizBar);
		popBox.color = Color(0x80ffffff);
		popBox.padding = recti(0,4,4,4);
		@popIcon = GuiSprite(popBox, Alignment(Left-16, Top-8, Width=50, Height=50));
		popIcon.noClip = true;
		popIcon.desc = icons::Population;
		@popValue = GuiText(popBox, Alignment(Left+32, Top, Right-8, Bottom));
		popValue.horizAlign = 0.5;
		popValue.stroke = colors::Black;

		MarkupTooltip popTT(locale::PLANET_POPULATION_TIP);
		@popIcon.tooltipObject = popTT;
		@popValue.tooltipObject = popTT;

		@consBox = GuiSkinElement(this, Alignment(Left+112, Bottom-33, Left+336, Bottom-2), SS_PlainOverlay);
		consBox.color = boxColors;
		GuiSprite consIcon(consBox, Alignment(Left-16, Top-10, Left+35, Bottom+10), icons::Labor);

		y += 30;

		updateAbsolutePosition();
	}

	void updateActions() {
		actions.clear();
		
		if(pl.owner is playerEmpire) {
			actions.add(ManageAction());
			actions.addBasic(pl);
			actions.addFTL(pl);

			if(pl.population > 1.0 && playerEmpire.ForbidColonization == 0)
				actions.add(ColonizeAction());

			actions.addAbilities(pl);
			actions.addEmpireAbilities(playerEmpire, pl);
		}
		else {
			if((pl.owner is null || !pl.owner.valid) && !pl.quarantined && playerEmpire.ForbidColonization == 0)
				actions.add(ColonizeThisAction());
		}

		actions.init(pl);
		actionBG.size = vec2i(actions.size.width + 50, 60);
		actionBG.visible = actions.visible;
	}

	bool compatible(Object@ obj) override {
		return obj.isPlanet;
	}

	Object@ get() override {
		return pl;
	}

	void remove() override {
		if(overlay !is null)
			overlay.remove();
		InfoBar::remove();
	}

	void set(Object@ obj) override {
		@pl = cast<Planet>(obj);
		@objView.object = obj;
		@resources.drawFrom = obj;
		updateTimer = 0.0;
		modID = 0;
		updateActions();
	}

	bool displays(Object@ obj) override {
		if(obj is pl)
			return true;
		return false;
	}

	bool get_showingManage() override {
		return overlay !is null;
	}

	bool showManage(Object@ obj) override {
		if(overlay !is null)
			overlay.remove();
		@overlay = PlanetOverlay(findTab(), cast<Planet>(obj));
		visible = false;
		return false;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is objView) {
					switch(evt.value) {
						case OA_LeftClick:
							selectObject(pl, shiftKey);
							return true;
						case OA_RightClick:
							if(selectedObject is null)
								openContextMenu(pl, pl);
							else
								openContextMenu(pl);
							return true;
						case OA_MiddleClick:
							zoomTabTo(pl);
							return true;
						case OA_DoubleClick:
							showManage(pl);
							return true;
					}
				}
			break;
		}
		return InfoBar::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		if(source !is objView) {
			switch(evt.type) {
				case MET_Button_Up:
				case MET_Button_Down:
					return objView.onMouseEvent(evt, objView);
			}
		}

		return BaseGuiElement::onMouseEvent(evt, source);
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) override {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is this)
			return null;
		if(elem is objView) {
			int height = AbsolutePosition.size.height;
			vec2i origin(AbsolutePosition.topLeft.x, AbsolutePosition.botRight.y);
			origin.y += height;
			if(pos.distanceTo(origin) > height * 2)
				return null;
		}
		return elem;
	}

	double updateTimer = 1.0;
	uint modID = 0;
	void update(double time) override {
		if(overlay !is null) {
			if(overlay.parent is null) {
				@overlay = null;
				visible = true;
			}
			else
				overlay.update(time);
		}

		if(actions !is null)
			actions.update(time);

		updateTimer -= time;
		if(updateTimer <= 0) {
			updateTimer = randomd(0.1,0.9);
			Empire@ owner = pl.visibleOwner;
			bool owned = owner is playerEmpire;
			bool colonized = owner !is null && owner.valid;

			updateActions();

			//Update name
			name.text = pl.name;
			if(owner !is null)
				name.color = owner.color;

			//Update level
			uint lv = pl.level;
			level.text = locale::LEVEL+" "+lv;

			//Update resource display
			resources.resources.syncFrom(pl.getAllResources());
			if(!colonized)
				resources.resources.length = min(resources.resources.length, 1);
			else
				resources.resources.sortDesc();
			resources.setSingleMode(align=0.0);

			auto@ primary = getResource(pl.primaryResourceType);
			if(resources.resources.length == 1 || (primary !is null && primary.limitlessLevel)) {
				resources.alignment.bottom.pixels = 40;

				auto@ type = resources.resources[0].type;
				string desc = format(type.blurb, toString(pl.level, 0));
				if(desc.length == 0)
					desc = format(type.description, toString(pl.level, 0));
				if(desc.length == 0) {
					if(type.level > 0) {
						desc = format(locale::RESOURCE_TIER_DESC,
							toString(type.level),
							type.level < LEVEL_REQ.length ? getSpriteDesc(LEVEL_REQ[type.level]) : "ResourceClassIcons::5");
					}
				}
				resourceDesc.text = desc;
				resourceDesc.visible = true;
			}
			else {
				resources.alignment.bottom.pixels = 2;
				resourceDesc.visible = false;
			}

			//Update statuses
			if(pl.statusEffectCount > 0)
				statuses.syncFrom(pl.getStatusEffects());
			else
				statuses.length = 0;

			//Update condition display
			levelBox.visible = colonized;
			popBox.visible = colonized && owner.HasPopulation != 0;
			if(colonized || statuses.length == 0) {
				if(statuses.length != 0) {
					uint prevCnt = statusIcons.length, cnt = statuses.length;
					for(uint i = cnt; i < prevCnt; ++i)
						statusIcons[i].remove();
					statusIcons.length = cnt;
					for(uint i = 0; i < cnt; ++i) {
						auto@ icon = statusIcons[i];
						if(icon is null) {
							@icon = GuiStatusBox(statusList, recti_area(2, 2+32*i, 30, 30));
							@statusIcons[i] = icon;
						}
						@icon.fromObject = pl;
						icon.update(statuses[i]);
					}
					statusList.visible = true;
				}
				else {
					statusList.visible = false;
				}
				resourceBox.alignment = Alignment(Left+5, Top+118, Left+295, Top+118+70);
				resourceBox.updateAbsolutePosition();
				statusBox.visible = false;
				resourceBox.visible = resources.length != 0;
			}
			else {
				resourceBox.alignment = Alignment(Left+5, Top+80, Left+295, Top+80+70);
				resourceBox.updateAbsolutePosition();
				statusList.visible = false;
				statusBox.visible = true;
				resourceBox.visible = resources.length != 0;

				auto@ status = statuses[0].type;
				for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
					if(statuses[i].type.conditionFrequency > 0) {
						@status = statuses[i].type;
						break;
					}
				}

				statusText.text = format("[b][img=$3;22x22/] [color=$4][vspace=3]$1[/vspace][/color][/b]"
						"\n[offset=6][vspace=4][color=#aaa]$2[/color][/vspace][/offset]",
					status.name, status.description,
					getSpriteDesc(status.icon), toString(status.color));
			}

			//Update population display
			if(colonized) {
				popValue.text = standardize(pl.population, true) + "/" + standardize(pl.maxPopulation, true);
				popValue.color = Color(0xffffffff);
			}
			else {
				popValue.text = "-";
			}

			//Update construction
			if(owned)
				cons.syncFrom(pl.getConstructionQueue(1));
			else
				cons.length = 0;

			consBox.visible = cons.length != 0;

			//Update level requirements
			double decay = pl.decayTime;
			uint maxLevel = getMaxPlanetLevel(pl);
			if(!owned || (lv == maxLevel && decay <= 0) || (lv >= uint(pl.maxLevel) && decay <= 0)) {
				requireBox.visible = false;
			}
			else if(decay > 0) {
				requireBox.visible = true;
				reqTimer.visible = true;
				reqTimer.text = formatTime(decay);
				reqLabel.color = Color(0xff0000ff);
				reqLabel.tooltip = format(locale::REQ_STOP_DECAY, toString(lv-1), formatTime(decay));
				reqLabel.text = format(locale::REQUIRED_RESOURCES, toString(lv));

				uint newMod = pl.resourceModID;
				if(modID != newMod) {
					available.clear();
					receive(pl.getResourceAmounts(), available);

					const PlanetLevel@ lvl = getPlanetLevel(pl, lv);
					reqDisplay.set(lvl.reqs, available);
					reqDisplay.visible = true;
					reqLabel.visible = true;

					popReq.visible = reqDisplay.length == 0;
					if(popReq.visible)
						popReq.text = format(locale::POP_REQ, standardize(lvl.requiredPop, true));

					reqLabel.tooltip = format(locale::REQ_FOR_LEVEL, toString(lv + 1));
					modID = newMod;
				}
			}
			else {
				requireBox.visible = pl.nativeResourceDestination[0] is null || !pl.nativeResourceUsable[0];
				reqTimer.visible = false;
				reqLabel.color = Color(0xffffffff);

				uint newMod = pl.resourceModID;
				if(modID != newMod) {
					available.clear();
					receive(pl.getResourceAmounts(), available);

					const PlanetLevel@ lvl = getPlanetLevel(pl, lv + 1);
					reqDisplay.set(lvl.reqs, available);
					reqDisplay.visible = true;
					reqLabel.visible = true;
					reqLabel.text = format(locale::REQUIRED_RESOURCES, toString(lv+1));

					popReq.visible = reqDisplay.length == 0;
					if(popReq.visible)
						popReq.text = format(locale::POP_REQ, standardize(lvl.requiredPop, true));

					reqLabel.tooltip = format(locale::REQ_FOR_LEVEL, toString(lv + 1));
					modID = newMod;
				}
			}
		}

		InfoBar::update(time);
	}

	void draw() override {
		BaseGuiElement::draw();
		const Font@ ft = skin.getFont(FT_Normal);

		//Construction display
		if(cons.length != 0) {
			recti pos = consBox.AbsolutePosition.padded(4);
			drawConstructible(cons[0], consBox.AbsolutePosition, isBox=true);
			ft.draw(pos=pos, text=formatTime(cons[0].getETA(pl)), horizAlign=1.0, vertAlign=1.0, stroke=colors::Black);

			if(ft.bold !is null)
				@ft = ft.bold;
			ft.draw(pos=pos, text=cons[0].name, horizAlign=0.0, vertAlign=0.0, stroke=colors::Black);
		}
	}
};

class ManageAction : BarAction {
	void init() override {
		icon = icons::Manage;
		tooltip = locale::TT_MANAGE_PLANET;
	}

	void call() override {
		selectObject(obj);
		openOverlay(obj);
	}
};

class ColonizeAction : BarAction {
	void init() override {
		icon = icons::Colonize;
		tooltip = locale::TT_COLONIZE;
	}

	void call() override {
		targetObject(ColonizeTarget(obj));
	}
};

class ColonizeTarget : ObjectTargeting {
	Object@ obj;

	ColonizeTarget(Object@ obj) {
		@this.obj = obj;
	}

	void call(Object@ target) {
		obj.colonize(target);
	}

	string message(Object@ obj, bool valid) {
		return locale::COLONIZE;
	}

	bool valid(Object@ obj) {
		if(!obj.isPlanet)
			return false;
		if(obj.quarantined)
			return false;
		return obj.owner is null || !obj.owner.valid;
	}
};

class ColonizeThisAction : BarAction {
	void init() override {
		icon = icons::ColonizeThis;
		tooltip = locale::TT_COLONIZE_THIS;
	}

	void call() override {
		playerEmpire.autoColonize(obj);
	}
};

InfoBar@ makePlanetInfoBar(IGuiElement@ parent, Object@ obj) {
	PlanetInfoBar bar(parent);
	bar.set(obj);
	return bar;
}
