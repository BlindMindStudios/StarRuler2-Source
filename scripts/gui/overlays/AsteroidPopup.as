import overlays.Popup;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import elements.GuiSkinElement;
import elements.GuiResources;
from overlays.ContextMenu import openContextMenu;
import resources;
import cargo;

class AsteroidPopup : Popup {
	GuiText@ name;
	Gui3DObject@ objView;
	Asteroid@ obj;
	double lastUpdate = -INFINITY;

	GuiSkinElement@ band;
	GuiSprite@ cargoIcon;
	GuiText@ cargoName;
	GuiText@ cargoValue;
	GuiResourceGrid@ resources;

	AsteroidPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(150, 135);

		@name = GuiText(this, Alignment(Left+4, Top+2, Right-4, Top+24));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+4, Top+25, Right-4, Top+95));

		@band = GuiSkinElement(this, Alignment(Left+3, Bottom-35, Right-4, Bottom-2), SS_SubTitle);
		band.color = Color(0xaaaaaaff);

		@resources = GuiResourceGrid(band, Alignment(Left+4, Top+4, Right-3, Bottom-4));
		resources.visible = false;

		@cargoIcon = GuiSprite(band, Alignment(Left+2, Top+2, Left+31, Bottom-2));
		@cargoName = GuiText(band, Alignment(Left+38, Top+4, Right-4, Bottom-4));
		cargoName.font = FT_Bold;
		@cargoValue = GuiText(band, Alignment(Left+38, Top+4, Right-4, Bottom-4));
		cargoValue.horizAlign = 1.0;

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return Obj.isAsteroid;
	}

	void set(Object@ Obj) {
		@obj = cast<Asteroid>(Obj);
		@objView.object = Obj;
		lastUpdate = -INFINITY;
	}

	Object@ get() {
		return obj;
	}

	void draw() {
		Popup::updatePosition(obj);
		recti bgPos = AbsolutePosition;

		uint flags = SF_Normal;
		SkinStyle style = SS_GenericPopupBG;
		if(isSelectable && Hovered)
			flags |= SF_Hovered;
		if(obj.owner !is null) {
			skin.draw(style, flags, bgPos, obj.owner.color);
			if(obj.owner.flag !is null)
				obj.owner.flag.draw(
					objView.absolutePosition.aspectAligned(1.0, horizAlign=1.0, vertAlign=1.0),
					obj.owner.color * Color(0xffffff30));
		}
		else
			skin.draw(style, flags, bgPos, Color(0xffffffff));

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
		if(frameTime - 0.5 < lastUpdate)
			return;

		lastUpdate = frameTime;
		const Font@ ft = skin.getFont(FT_Normal);

		//Update name
		name.text = obj.name;
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;

		if(obj.cargoTypes != 0) {
			auto@ cargo = getCargoType(obj.cargoType[0]);
			band.visible = cargo !is null;
			if(cargo !is null) {
				cargoIcon.desc = cargo.icon;
				cargoName.text = cargo.name+":";
				cargoValue.text = standardize(obj.getCargoStored(cargo.id), true);
			}
			cargoIcon.visible = true;
			cargoName.visible = true;
			cargoValue.visible = true;
			resources.visible = false;
		}
		else if(obj.nativeResourceCount != 0) {
			cargoIcon.visible = false;
			cargoName.visible = false;
			cargoValue.visible = false;
			resources.visible = true;

			resources.resources.syncFrom(obj.getAllResources());
			resources.setSingleMode();

			band.visible = resources.length != 0;
		}
		else {
			band.visible = false;
		}

		Popup::update();
		Popup::updatePosition(obj);
	}
};
