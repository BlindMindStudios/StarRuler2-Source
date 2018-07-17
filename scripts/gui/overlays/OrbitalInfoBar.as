import overlays.InfoBar;
import elements.BaseGuiElement;
import elements.GuiResources;
import elements.Gui3DObject;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiProgressbar;
import elements.GuiGroupDisplay;
import elements.GuiBlueprint;
import elements.GuiSprite;
import elements.GuiSkinElement;
import elements.GuiIconGrid;
import elements.MarkupTooltip;
import ship_groups;
import orbitals;
import util.formatting;
import icons;
from overlays.ContextMenu import openContextMenu, FinanceDryDock;
from overlays.Construction import ConstructionOverlay;
from obj_selection import isSelected, selectObject, clearSelection, addToSelection, selectedObject;
from tabs.GalaxyTab import zoomTabTo, openOverlay;

class ModuleGrid : GuiIconGrid {
	array<OrbitalSection> sections;

	ModuleGrid(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
	}

	uint get_length() override {
		return sections.length;
	}

	void drawElement(uint index, const recti& pos) override {
		sections[index].type.icon.draw(pos);
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		return sections[hovered].type.getTooltip();
	}
};

class OrbitalInfoBar : InfoBar {
	Orbital@ obj;
	Gui3DObject@ objView;
	ConstructionOverlay@ overlay;

	GuiSkinElement@ nameBox;
	GuiText@ name;

	GuiSkinElement@ moduleBox;
	GuiMarkupText@ moduleText;
	GuiSprite@ moduleIcon;

	ActionBar@ actions;

	OrbitalInfoBar(IGuiElement@ parent) {
		super(parent);
		@alignment = Alignment(Left, Bottom-228, Left+395, Bottom);

		@objView = Gui3DObject(this, Alignment(
			Left-0.5f, Top, Right+0.15f, Bottom));

		@actions = ActionBar(this, vec2i(305, 172));
		actions.noClip = true;

		int y = 90;
		@nameBox = GuiSkinElement(this, Alignment(Left+12, Top+y, Left+256, Top+y+34), SS_PlainOverlay);
		@name = GuiText(nameBox, Alignment().padded(8, 0, 30, 0));
		name.font = FT_Medium;
		@moduleIcon = GuiSprite(nameBox, Alignment(Right-30, Top, Right, Bottom));

		y += 40;
		@moduleBox = GuiSkinElement(this, Alignment(Left+12, Top+y, Left+256, Top+y+94), SS_PlainOverlay);
		@moduleText = GuiMarkupText(moduleBox, Alignment().padded(6, 3, 6, 0));

		updateAbsolutePosition();
	}

	void updateActions() {
		actions.clear();
		
		if(obj.owner is playerEmpire) {
			auto@ core = getOrbitalModule(obj.coreModule);
			if(!core.isStandalone)
				actions.add(ManageAction());
			if(obj.getDesign(OV_PackUp) !is null)
				actions.add(PackUpAction());
			actions.addBasic(obj);
			actions.addFTL(obj);
			actions.addAbilities(obj);
			actions.addEmpireAbilities(playerEmpire, obj);
		}
		else {
		}

		actions.init(obj);
	}

	void draw() override {
		if(actions.visible) {
			recti pos = actions.absolutePosition;
			skin.draw(SS_Panel, SF_Normal, recti(vec2i(-5, pos.topLeft.y), pos.botRight + vec2i(0, 20)));
		}
		InfoBar::draw();
	}

	void remove() override {
		if(overlay !is null)
			overlay.remove();
		InfoBar::remove();
	}

	bool compatible(Object@ obj) override {
		return obj.isOrbital;
	}

	Object@ get() override {
		return obj;
	}

	void set(Object@ obj) override {
		@this.obj = cast<Orbital>(obj);
		@objView.object = obj;
		updateTimer = 0.0;
		updateActions();
	}

	bool displays(Object@ obj) override {
		if(obj is this.obj)
			return true;
		return false;
	}

	bool showManage(Object@ obj) override {
		if(overlay !is null)
			overlay.remove();
		if(cast<Orbital>(obj).getDesign(OV_DRY_Design) !is null) {
			FinanceDryDock(obj);
			return false;
		}
		if(obj.hasConstruction) {
			@overlay = ConstructionOverlay(findTab(), obj);
			visible = false;
		}
		return false;
	}

	double updateTimer = 1.0;
	void update(double time) override {
		if(overlay !is null) {
			if(overlay.parent is null) {
				@overlay = null;
				visible = true;
			}
			else
				overlay.update(time);
		}

		updateTimer -= time;
		if(updateTimer <= 0) {
			updateTimer = randomd(0.1,0.9);
			Empire@ owner = obj.owner;

			//Update name
			name.text = obj.name;
			if(obj.isDisabled)
				name.color = colors::Red;
			else if(owner !is null)
				name.color = owner.color;
			else
				name.color = colors::White;

			const Font@ ft = skin.getFont(FT_Medium);
			if(ft.getDimension(name.text).x > name.size.width)
				name.font = FT_Bold;
			else
				name.font = FT_Medium;

			//Update description
			auto@ core = getOrbitalModule(obj.coreModule);
			if(core !is null) {
				moduleText.text = core.blurb;
				moduleIcon.desc = core.icon;
				setMarkupTooltip(moduleBox, format("[font=Medium]$1[/font]\n$2", core.name, core.description), width=350);
				setMarkupTooltip(nameBox, format("[font=Medium]$1[/font]\n$2", core.name, core.description), width=350);
			}

			updateActions();
		}
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) override {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is this)
			return null;
		if(elem is objView) {
			int height = AbsolutePosition.size.height;
			vec2i origin(AbsolutePosition.topLeft.x, AbsolutePosition.botRight.y);
			origin.y += height;
			if(pos.distanceTo(origin) > height * 1.6)
				return null;
		}
		return elem;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is objView) {
					switch(evt.value) {
						case OA_LeftClick:
							selectObject(obj, shiftKey);
							return true;
						case OA_RightClick:
							if(selectedObject is null)
								openContextMenu(obj, obj);
							else
								openContextMenu(obj);
							return true;
						case OA_MiddleClick:
							zoomTabTo(obj);
							return true;
						case OA_DoubleClick:
							showManage(obj);
							return true;
					}
				}
			break;
		}
		return InfoBar::onGuiEvent(evt);
	}
};

class ManageAction : BarAction {
	void init() override {
		icon = icons::Manage;
		tooltip = locale::TT_MANAGE_ORBITAL;
	}

	void call() override {
		selectObject(obj);
		openOverlay(obj);
	}
};

class PackUpAction : BarAction {
	void init() override {
		icon = icons::Gate;
		tooltip = locale::TT_PACKUP_ORBITAL;
	}

	void call() override {
		cast<Orbital>(obj).sendValue(OV_PackUp);
	}
};

InfoBar@ makeOrbitalInfoBar(IGuiElement@ parent, Object@ obj) {
	OrbitalInfoBar bar(parent);
	bar.set(obj);
	return bar;
}
