import overlays.Popup;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import util.formatting;
import artifacts;
import abilities;
import icons;
from overlays.ContextMenu import openContextMenu;

class ArtifactPopup : Popup {
	GuiText@ name;
	GuiMarkupText@ description;
	GuiText@ cost;
	GuiSprite@ icon;
	Gui3DObject@ objView;
	Artifact@ obj;
	double lastUpdate = -INFINITY;

	ArtifactPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(210, 220);

		@name = GuiText(this, Alignment(Left+4, Top+4, Right-4, Top+30));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+3+4, Top+30+4, Right-4-4, Top+110-4));

		@description = GuiMarkupText(this, Alignment(Left+8, Top+110, Right-8, Bottom-4));

		@icon = GuiSprite(this, Alignment(Left+8, Bottom-34, Left+35, Bottom-7));

		@cost = GuiText(this, Alignment(Left+35, Bottom-34, Right, Bottom-4));
		cost.horizAlign = 0.5;
		cost.font = FT_Bold;
		cost.color = colors::Energy;

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return Obj.isArtifact;
	}

	void set(Object@ Obj) {
		@obj = cast<Artifact>(Obj);
		@objView.object = Obj;
		lastUpdate = -INFINITY;
	}

	Object@ get() {
		return obj;
	}

	void draw() {
		Popup::updatePosition(obj);
		recti bgPos = AbsolutePosition;

		skin.draw(SS_Panel, SF_Normal, bgPos);
		skin.draw(SS_BG3D, SF_Normal, objView.absolutePosition.padded(-4));
		skin.draw(SS_SubTitle, SF_Normal, recti_area(bgPos.topLeft+vec2i(2,1), vec2i(bgPos.width-5, 30)));
		if(cost.visible)
			skin.draw(SS_SubTitle, SF_Normal, cost.absolutePosition.padded(-31,-3,4,-1), colors::Energy);
		BaseGuiElement::draw();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is objView) {
					dragging = false;
					if(!dragged) {
						switch(evt.value) {
							case OA_LeftClick:
								emitClicked(PA_Select);
								return true;
							case OA_RightClick:
								openContextMenu(obj);
								return true;
							case OA_MiddleClick:
							case OA_DoubleClick:
								if(isSelectable)
									emitClicked(PA_Select);
								else
									emitClicked(PA_Manage);
								return true;
						}
					}
				}
			break;
		}
		return Popup::onGuiEvent(evt);
	}

	void update() {
		if(frameTime - 1.0 < lastUpdate)
			return;

		lastUpdate = frameTime;
		const Font@ ft = skin.getFont(FT_Normal);

		//Update name
		name.text = obj.name;
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;

		const ArtifactType@ type = getArtifactType(obj.ArtifactType);
		if(type !is null)
			description.text = type.description;
		else
			description.text = "--";

		//Update cost
		array<Ability> abilities;
		abilities.syncFrom(obj.getAbilities());

		if(abilities.length != 0) {
			icon.visible = true;
			cost.visible = true;

			double energyCost = abilities[0].getEnergyCost();

			@abilities[0].emp = playerEmpire;
			icon.desc = abilities[0].type.icon;
			cost.text = format("$1 $2", energyCost, locale::RESOURCE_ENERGY);

			cost.visible = energyCost != 0;
			icon.visible = cost.visible;
		}
		else {
			icon.visible = false;
			cost.visible = false;
		}

		Popup::update();
		Popup::updatePosition(obj);
	}
};
