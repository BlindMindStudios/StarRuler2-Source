import overlays.Popup;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import elements.GuiProgressbar;
import elements.MarkupTooltip;
import icons;
from overlays.ContextMenu import openContextMenu;

class StarPopup : Popup {
	GuiText@ name;
	Gui3DObject@ objView;
	Star@ obj;
	double lastUpdate = -INFINITY;

	GuiSprite@ defIcon;

	GuiProgressbar@ health;

	StarPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(150, 110);

		@name = GuiText(this, Alignment(Left+4, Top+2, Right-4, Top+24));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+4, Top+25, Right-4, Bottom-4));

		@defIcon = GuiSprite(this, Alignment(Left+4, Top+25, Width=40, Height=40));
		defIcon.desc = icons::Defense;
		setMarkupTooltip(defIcon, locale::TT_IS_DEFENDING);
		defIcon.visible = false;

		@health = GuiProgressbar(this, Alignment(Left+8, Top+28, Right-8, Top+50));
		health.visible = false;

		auto@ healthIcon = GuiSprite(health, Alignment(Left-8, Top-9, Left+24, Bottom-8), icons::Health);
		healthIcon.noClip = true;

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return Obj.isStar;
	}

	void set(Object@ Obj) {
		@obj = cast<Star>(Obj);
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

		Color col;
		Region@ reg = obj.region;
		if(reg !is null) {
			Empire@ other = reg.visiblePrimaryEmpire;
			if(other !is null)
				col = other.color;
		}

		skin.draw(style, flags, bgPos, col);
		if(obj.owner !is null && obj.owner.flag !is null) {
			obj.owner.flag.draw(
				objView.absolutePosition.aspectAligned(1.0, horizAlign=1.0, vertAlign=1.0),
				obj.owner.color * Color(0xffffff30));
		}
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
		if(frameTime - 0.2 < lastUpdate)
			return;

		lastUpdate = frameTime;
		const Font@ ft = skin.getFont(FT_Normal);

		defIcon.visible = playerEmpire.isDefending(obj.region);

		//Update name
		name.text = obj.name;
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;

		//Update health
		if(obj.Health < obj.MaxHealth) {
			health.progress = obj.Health / obj.MaxHealth;
			health.frontColor = colors::Red.interpolate(colors::Green, health.progress);
			health.text = standardize(obj.Health)+" / "+standardize(obj.MaxHealth);
			health.visible = true;
		}
		else {
			health.visible = false;
		}

		Popup::update();
		Popup::updatePosition(obj);
	}
};
