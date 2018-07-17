import elements.BaseGuiElement;
import elements.Gui3DObject;
import elements.GuiOverlay;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiButton;
import elements.GuiListbox;
import elements.GuiPanel;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import elements.GuiResources;
import elements.GuiIconGrid;
import orbitals;
import util.formatting;
import icons;
import buildings;
import resources;
import tile_resources;
import overlays.Construction;
from gui import animate_time;

const double ANIM1_TIME = 0.15;
const double ANIM2_TIME = 0.001;
const uint BORDER = 20;
const uint WIDTH = 500;
const uint R_HEIGHT = 256;

// {{{ Overlay
class OrbitalOverlay : GuiOverlay, ConstructionParent {
	Gui3DObject@ objView;
	Orbital@ obj;
	bool closing = false;

	ResourceDisplay@ resources;
	ModuleDisplay@ modules;
	ConstructionDisplay@ construction;

	Alignment@ objTarget;

	OrbitalRequirements reqs;
	array<OrbitalSection> sections;
	array<Resource> resList;

	OrbitalOverlay(IGuiElement@ parent, Orbital@ Obj) {
		super(parent);
		fade.a = 0;
		@obj = Obj;

		vec2i parSize = parent.size;
		@objView = Gui3DObject(this, recti_area(vec2i(-456, parSize.y-228), vec2i(912, 912)));
		objView.internalRotation = quaterniond_fromAxisAngle(vec3d(0.0, 0.0, 1.0), -0.25*pi);
		@objView.object = obj;

		int plSize = parSize.x * 2;
		@objTarget = Alignment(Left+0.5f-plSize/2, Top+0.5f, Width=plSize, Height=plSize);
		recti targPos = objTarget.resolve(parSize);
		animate_time(objView, targPos, ANIM1_TIME);

		updateAbsolutePosition();

		vec2i origin = targPos.center;
		@resources = ResourceDisplay(this, origin, Alignment(Left+0.5f-BORDER/2-WIDTH,
								Top+BORDER, Left+0.5f-BORDER/2, Top+BORDER+R_HEIGHT));
		resources.visible = false;
		@modules = ModuleDisplay(this, origin, Alignment(Left+0.5f-BORDER/2-WIDTH,
								Top+BORDER, Left+0.5f-BORDER/2, Bottom-BORDER));

		@construction = ConstructionDisplay(this, origin, Alignment(Right-0.5f+BORDER/2,
					Top+BORDER, Right-0.5f+BORDER/2+WIDTH, Bottom-BORDER));
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
					resources.animate();
					modules.animate();
					construction.animate();

					return true;
				}
			break;
			case GUI_Confirmed:
				triggerUpdate();
			break;
		}
		return GuiOverlay::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		return GuiOverlay::onMouseEvent(evt, source);
	}

	void close() override {
		if(parent is null)
			return;
		closing = true;
		@objView.alignment = null;

		modules.visible = false;
		resources.visible = false;
		construction.visible = false;

		vec2i parSize = parent.size;
		recti targPos = recti_area(vec2i(-456, parSize.y-228), vec2i(912, 912));
		animate_time(objView, targPos, ANIM1_TIME);
	}

	void startBuild(const BuildingType@ type) {
	}

	Object@ get_object() {
		return obj;
	}

	Object@ get_slaved() {
		return null;
	}

	void updateData() {
		resList.syncFrom(obj.getAllResources());
		sections.syncFrom(obj.getSections());

		reqs.init(resList);
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			if(sections[i].enabled)
				reqs.add(sections[i].type);
		}

		for(uint i = 0, cnt = construction.modulesList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(construction.modulesList.items[i]);
			for(uint n = 0, ncnt = list.itemCount; n < ncnt; ++n) {
				auto@ item = cast<BuildElement>(list.getItemElement(n));
				if(item !is null && item.orb !is null) {
					item.incomplete = !reqs.check(item.orb);
					item.update(construction);
				}
			}
		}
	}

	double updateTimer = 0.0;
	void update(double time) {
		construction.update(time);

		updateTimer -= time;
		if(updateTimer <= 0 || construction.longTimer == 5.0) {
			updateData();
			updateTimer = 1.0;
		}

		resources.update(time);
		modules.update(time);
	}

	void triggerUpdate() {
		updateData();
		updateTimer = 0.0;
		resources.updateTimer = 0.0;
		modules.updateTimer = 0.0;
		construction.updateTimer = 0.0;
		construction.longTimer = 0.0;
	}

	void draw() {
		if(!settings::bGalaxyBG && objView.Alignment !is null)
			material::Skybox.draw(AbsolutePosition);
		GuiOverlay::draw();
	}
};

class DisplayBox : BaseGuiElement {
	OrbitalOverlay@ overlay;
	Alignment@ targetAlign;

	DisplayBox(OrbitalOverlay@ ov, vec2i origin, Alignment@ target) {
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

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0)
					return true;
			break;
			case MET_Button_Up:
				if(evt.button == 0)
					return true;
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

// {{{ Resources
class ResourceDisplay : DisplayBox {
	GuiText@ resourceLabel;
	GuiSkinElement@ resourceBox;
	GuiResources@ resources;

	GuiText@ affinityLabel;
	GuiSpriteGrid@ affinities;

	ResourceDisplay(OrbitalOverlay@ ov, vec2i origin, Alignment@ target) {
		super(ov, origin, target);

		@resourceLabel = GuiText(this, Alignment(Left+8, Top+8, Right-8, Top+30), locale::LAB_RESOURCES);
		resourceLabel.font = FT_Bold;

		@resourceBox = GuiSkinElement(this, Alignment(Left+20, Top+34, Right-20, Top+78), SS_PlainOverlay);
		@resources = GuiResources(resourceBox, Alignment().fill());
		resources.horizAlign = 0.0;
		@resources.drawFrom = overlay.obj;

		@affinityLabel = GuiText(this, Alignment(Left+8, Top+88, Right-8, Top+110), locale::LAB_AVAIL_AFFINITIES);
		affinityLabel.font = FT_Bold;

		@affinities = GuiSpriteGrid(this, Alignment(Left+20, Top+114, Right-20, Bottom-8), vec2i(40, 40));
		affinities.horizAlign = 0.0;
		affinities.vertAlign = 0.0;
	}

	void updateData() {
		resources.resources = overlay.resList;

		affinities.clear();
		for(uint i = 0, cnt = overlay.reqs.available.length; i < cnt; ++i) {
			if(overlay.reqs.used[i])
				continue;
			auto@ res = overlay.reqs.available[i];
			for(uint n = 0, ncnt = res.affinities.length; n < ncnt; ++n)
				affinities.add(getAffinitySprite(res.affinities[n]));
		}
		affinityLabel.visible = affinities.sprites.length != 0;
	}

	double updateTimer = 0.0;
	void update(double time) override {
		updateTimer -= time;
		if(updateTimer <= 0) {
			updateData();
			updateTimer = 1.0;
		}
	}
}
// }}}

// {{{ Modules
class ModuleElement : BaseGuiElement {
	Orbital@ obj;
	OrbitalSection section;

	GuiSprite@ icon;
	GuiText@ name;
	GuiMarkupText@ blurb;
	GuiMarkupText@ data;
	Color color;
	GuiButton@ removeButton;

	ModuleElement(IGuiElement@ disp, OrbitalSection@ section, Orbital@ obj) {
		super(disp, Alignment(Left+8, Top, Right-8, Top+76));
		@icon = GuiSprite(this, recti_area(8, 13, 50, 50));
		@name = GuiText(this, Alignment(Left+70, Top+4, Right-4, Top+28));
		name.font = FT_Bold;
		@blurb = GuiMarkupText(this, Alignment(Left+68, Top+26, Right-4, Top+48));
		@data = GuiMarkupText(this, Alignment(Left+68, Top+48, Right-4, Bottom-4));
		data.defaultFont = FT_Italic;
		@removeButton = GuiButton(this, Alignment(Right-40, Bottom-26, Right, Bottom), "-");
		removeButton.color = colors::Red;

		set(section, obj);
		updateAbsolutePosition();
	}

	int prevY = 0;
	void setPos(int y) {
		alignment.top.pixels = y;
		alignment.bottom.pixels = y + 76;
		if(prevY != y)
			updateAbsolutePosition();
		prevY = y;
	}

	void set(OrbitalSection@ section, Orbital@ obj) {
		@this.obj = obj;
		this.section = section;
		icon.desc = section.type.icon;
		name.text = section.type.name;
		blurb.text = section.type.blurb;
		data.text = section.getData(obj);
		if(section.enabled) {
			color = colors::White;
			name.color = colors::White;
		}
		else {
			color = colors::Red;
			name.color = colors::Red;
		}
		setMarkupTooltip(this, section.type.getTooltip());
		removeButton.visible = !section.type.isCore && !obj.isContested;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is removeButton) {
			if(evt.type == GUI_Clicked) {
				obj.destroyModule(section.id);
				emitConfirmed();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() override {
		skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition, color=color);
		BaseGuiElement::draw();

		int x = AbsolutePosition.width - 32;
		for(uint i = 0; i < TR_COUNT; ++i) {
			for(uint n = 0, ncnt = section.type.affinities[i]; n < ncnt; ++n) {
				getTileResourceSprite(i).draw(
					recti_area(AbsolutePosition.topLeft + vec2i(x, 4), vec2i(26, 26)));
				x -= 30;
			}
		}
		for(uint i = 0, cnt = section.type.requirements.length; i < cnt; ++i) {
			section.type.requirements[i].icon.draw(
				recti_area(vec2i(x, 4)+AbsolutePosition.topLeft, vec2i(26, 26)));
			x -= 30;
		}
		if(section.type.maintenance != 0) {
			x -= 60;
			skin.getFont(FT_Bold).draw(
					pos=recti_area(vec2i(x, 4)+AbsolutePosition.topLeft, vec2i(86, 26)),
					text=formatMoney(section.type.maintenance),
					color=Color(0xd1cb6aff),
					horizAlign=1.0);
		}
	}
};

class ModuleDisplay : DisplayBox {
	GuiPanel@ panel;
	array<ModuleElement@> modules;

	ModuleDisplay(OrbitalOverlay@ ov, vec2i origin, Alignment@ target) {
		super(ov, origin, target);
		@panel = GuiPanel(this, Alignment().fill());
		updateAbsolutePosition();
	}

	void updateData() {
		uint oldCnt = modules.length;
		uint newCnt = overlay.sections.length;
		for(uint i = newCnt; i < oldCnt; ++i)
			modules[i].remove();
		modules.length = newCnt;
		int y = 8;
		for(uint i = 0; i < newCnt; ++i) {
			if(modules[i] is null)
				@modules[i] = ModuleElement(panel, overlay.sections[i], overlay.obj);
			else
				modules[i].set(overlay.sections[i], overlay.obj);
			modules[i].setPos(y);
			y += 80;
		}
	}

	double updateTimer = 0.0;
	void update(double time) override {
		updateTimer -= time;
		if(updateTimer <= 0) {
			updateData();
			updateTimer = 1.0;
		}
	}
}
// }}}
