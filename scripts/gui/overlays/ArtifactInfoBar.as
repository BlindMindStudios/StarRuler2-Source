import overlays.InfoBar;
import elements.BaseGuiElement;
import elements.GuiResources;
import elements.Gui3DObject;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiProgressbar;
import elements.GuiGroupDisplay;
import elements.GuiBlueprint;
import elements.GuiSkinElement;
import elements.GuiMarkupText;
import ship_groups;
import util.formatting;
import artifacts;
from obj_selection import isSelected, selectObject, clearSelection, addToSelection;

class ArtifactInfoBar : InfoBar {
	Artifact@ obj;
	Gui3DObject@ objView;

	GuiSkinElement@ nameBox;
	GuiText@ name;

	GuiSkinElement@ descBox;
	GuiMarkupText@ desc;

	ActionBar@ actions;

	ArtifactInfoBar(IGuiElement@ parent) {
		super(parent);
		@alignment = Alignment(Left, Bottom-228, Left+395, Bottom);

		@objView = Gui3DObject(this, Alignment(
			Left-1.f, Top, Right, Bottom+3.f));
		objView.objectRotation = false;
		objView.internalRotation = quaterniond_fromAxisAngle(vec3d(0.0, 0.0, 1.0), -0.15*pi);

		@actions = ActionBar(this, vec2i(315, 172));
		actions.noClip = true;

		int y = 104;
		@nameBox = GuiSkinElement(this, Alignment(Left+4, Top+y, Left+266, Top+y+34), SS_PlainOverlay);
		@name = GuiText(nameBox, Alignment().padded(8, 0));
		name.font = FT_Medium;

		y += 40;
		@descBox = GuiSkinElement(this, Alignment(Left+4, Top+y, Left+266, Top+y+80), SS_PlainOverlay);
		@desc = GuiMarkupText(descBox, Alignment().padded(3));

		updateAbsolutePosition();
	}

	void updateActions() {
		actions.clear();
		if(obj.owner is playerEmpire || obj.owner is null || !obj.owner.valid)
			actions.addAbilities(obj, expanded=true);
		actions.init(obj);
	}

	bool compatible(Object@ obj) override {
		return obj.isArtifact;
	}

	Object@ get() override {
		return obj;
	}

	void set(Object@ obj) override {
		@this.obj = cast<Artifact>(obj);
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

			auto@ type = getArtifactType(obj.ArtifactType);
			if(type !is null)
				desc.text = type.description;

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
			skin.draw(SS_Panel, SF_Normal, recti(pos.topLeft - vec2i(80, 0), pos.botRight + vec2i(0, 20)));
		}
		InfoBar::draw();
	}
};

InfoBar@ makeArtifactInfoBar(IGuiElement@ parent, Object@ obj) {
	ArtifactInfoBar bar(parent);
	bar.set(obj);
	return bar;
}
