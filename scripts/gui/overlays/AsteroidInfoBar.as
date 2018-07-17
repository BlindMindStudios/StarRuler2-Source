import overlays.InfoBar;
import elements.BaseGuiElement;
import elements.GuiResources;
import elements.Gui3DObject;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.GuiProgressbar;
import elements.GuiGroupDisplay;
import elements.GuiBlueprint;
import elements.GuiSkinElement;
import elements.GuiResources;
import cargo;
import resources;
import ship_groups;
import util.formatting;
from obj_selection import isSelected, selectObject, clearSelection, addToSelection;

class AsteroidInfoBar : InfoBar {
	Asteroid@ obj;
	Gui3DObject@ objView;

	GuiSkinElement@ nameBox;
	GuiText@ name;

	GuiSkinElement@ resourceBox;
	GuiSprite@ cargoIcon;
	GuiText@ cargoName;
	GuiText@ cargoValue;
	GuiResourceGrid@ resources;
	
	GuiSkinElement@ stateBox;
	GuiMarkupText@ state;

	ActionBar@ actions;

	AsteroidInfoBar(IGuiElement@ parent) {
		super(parent);
		@alignment = Alignment(Left, Bottom-228, Left+395, Bottom);

		@objView = Gui3DObject(this, Alignment(
			Left-1.f, Top, Right, Bottom+3.f));
		objView.objectRotation = false;
		objView.internalRotation = quaterniond_fromAxisAngle(vec3d(0.0, 0.0, 1.0), -0.15*pi);

		@actions = ActionBar(this, vec2i(305, 172));
		actions.noClip = true;

		int y = 56;
		@nameBox = GuiSkinElement(this, Alignment(Left+12, Top+y, Left+156, Top+y+34), SS_PlainOverlay);
		@name = GuiText(nameBox, Alignment().padded(8, 0));
		name.font = FT_Medium;

		y += 40;
		@resourceBox = GuiSkinElement(this, Alignment(Left+12, Top+y, Left+226, Top+y+34), SS_PlainOverlay);
		@resources = GuiResourceGrid(resourceBox, Alignment(Left+8, Top+5, Right-8, Bottom-5));
		resources.visible = false;
		resources.spacing.x = 6;
		resources.horizAlign = 0.0;
		@cargoIcon = GuiSprite(resourceBox, Alignment(Left+2, Top+2, Left+31, Bottom-2));
		@cargoName = GuiText(resourceBox, Alignment(Left+38, Top+4, Right-4, Bottom-4));
		cargoName.font = FT_Bold;
		@cargoValue = GuiText(resourceBox, Alignment(Left+38, Top+4, Right-12, Bottom-4));
		cargoValue.horizAlign = 1.0;

		y += 40;
		@stateBox = GuiSkinElement(this, Alignment(Left+12, Top+y, Left+236, Bottom-4), SS_PlainOverlay);
		@state = GuiMarkupText(stateBox, Alignment(Left+8, Top+4, Right-4, Bottom));
		state.memo = true;

		updateAbsolutePosition();
	}

	void updateActions() {
		actions.clear();
		
		if(obj.owner is playerEmpire) {
			actions.addBasic(obj);
			actions.addEmpireAbilities(playerEmpire, obj);
		}

		actions.init(obj);
	}

	bool compatible(Object@ obj) override {
		return obj.isAsteroid;
	}

	Object@ get() override {
		return obj;
	}

	void set(Object@ obj) override {
		@this.obj = cast<Asteroid>(obj);
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
		return false;
	}

	double updateTimer = 1.0;
	void update(double time) override {
		updateTimer -= time;
		if(updateTimer <= 0) {
			updateTimer = randomd(0.1,0.9);
			Empire@ owner = obj.owner;

			//Update name
			name.text = obj.name;
			if(owner !is null)
				name.color = owner.color;
			
			if(obj.cargoTypes != 0) {
				//Update cargo display
				auto@ cargo = getCargoType(obj.cargoType[0]);
				resourceBox.visible = cargo !is null;
				if(cargo !is null) {
					cargoIcon.desc = cargo.icon;
					cargoName.text = cargo.name+":";
					cargoValue.text = standardize(obj.getCargoStored(cargo.id), true);
				}

				cargoIcon.visible = true;
				cargoName.visible = true;
				cargoValue.visible = true;
				resources.visible = false;

				state.text = locale::ASTEROID_MINING;
			}
			else if(obj.nativeResourceCount != 0) {
				//Update resource display
				resources.resources.syncFrom(obj.getAllResources());
				resources.resources.sortDesc();
				resources.setSingleMode(align=0.0);

				resourceBox.visible = resources.length != 0;

				cargoIcon.visible = false;
				cargoName.visible = false;
				cargoValue.visible = false;
				resources.visible = true;

				if(owner.valid && obj.visible)
					state.text = locale::ASTEROID_OWNED;
				else
					state.text = locale::ASTEROID_UNOWNED;
			}
			else {
				resourceBox.visible = false;
			}

			//Update action bar
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

	void draw() override {
		if(actions.visible) {
			recti pos = actions.absolutePosition;
			skin.draw(SS_Panel, SF_Normal, recti(pos.topLeft - vec2i(70, 0), pos.botRight + vec2i(0, 20)));
		}
		InfoBar::draw();
	}
};

InfoBar@ makeAsteroidInfoBar(IGuiElement@ parent, Object@ obj) {
	AsteroidInfoBar bar(parent);
	bar.set(obj);
	return bar;
}
