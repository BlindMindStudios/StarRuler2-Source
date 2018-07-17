import overlays.Popup;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import elements.GuiResources;
import elements.GuiProgressbar;
import elements.GuiSkinElement;
from overlays.ContextMenu import openContextMenu;
import icons;
import resources;
import civilians;

class CivilianPopup : Popup {
	GuiText@ name;
	Gui3DObject@ objView;
	Civilian@ obj;
	double lastUpdate = -INFINITY;
	GuiResourceGrid@ resources;

	GuiText@ cargoLabel;
	GuiMarkupText@ worth;
	GuiMarkupText@ cargoText;

	GuiProgressbar@ health;

	CivilianPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(190, 185);

		@name = GuiText(this, Alignment(Left+4, Top+2, Right-4, Top+24));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+4, Top+25, Right-4, Top+95));

		@health = GuiProgressbar(this, Alignment(Left+3, Bottom-89, Right-4, Bottom-63));
		health.tooltip = locale::HEALTH;
		GuiSprite healthIcon(health, Alignment(Left+2, Top+1, Width=24, Height=24), icons::Health);

		GuiSkinElement band(this, Alignment(Left+3, Bottom-65, Right-4, Bottom-32), SS_SubTitle);
		band.color = Color(0xaaaaaaff);

		@cargoLabel = GuiText(band, Alignment(Left+5, Top+3, Left+70, Bottom-2), locale::SHIP_CARGO);
		cargoLabel.font = FT_Bold;
		cargoLabel.stroke = colors::Black;
		@worth = GuiMarkupText(band, Alignment(Left+70, Top+6, Right-5, Bottom-2));

		GuiSkinElement band2(this, Alignment(Left+3, Bottom-34, Right-4, Bottom-2), SS_SubTitle);

		@cargoText = GuiMarkupText(band2, Alignment(Left+3, Top+4, Right-3, Bottom-2));
		cargoText.defaultFont = FT_Bold;
		@resources = GuiResourceGrid(band2, Alignment(Left+3, Top+3, Right-3, Bottom-2));

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return Obj.isCivilian;
	}

	void set(Object@ Obj) {
		@obj = cast<Civilian>(Obj);
		@objView.object = Obj;
		@resources.drawFrom = obj;
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

		//Update hp display
		double curHP = obj.health;
		double maxHP = obj.maxHealth;

		Color high(0x00ff00ff);
		Color low(0xff0000ff);

		health.progress = curHP / maxHP;
		health.frontColor = low.interpolate(high, health.progress);
		health.text = standardize(curHP)+" / "+standardize(maxHP);

		//Update resources
		uint type = obj.getCargoType();
		int value = obj.getCargoWorth();
		cargoLabel.color = obj.owner.color;
		if(type == CT_Goods) {
			resources.visible = false;
			cargoText.visible = true;
			cargoText.text = locale::CARGO_GOODS;
		}
		else if(type == CT_Resource) {
			const ResourceType@ res = getResource(obj.getCargoResource());
			resources.visible = true;
			cargoText.visible = false;
			if(res !is null) {
				resources.types.length = 1;
				@resources.types[0] = res;
				resources.typeMode = true;
				resources.setSingleMode();
			}
			else {
				resources.types.length = 0;
			}
		}

		worth.text = format(locale::SHIP_CARGO_WORTH, formatMoney(value));

		Popup::update();
		Popup::updatePosition(obj);
	}
};
