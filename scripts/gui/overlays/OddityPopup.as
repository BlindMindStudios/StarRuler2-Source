import overlays.Popup;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import util.formatting;
from overlays.ContextMenu import openContextMenu;

class OddityPopup : Popup {
	GuiText@ name;
	Gui3DObject@ objView;
	Object@ obj;
	double lastUpdate = -INFINITY;
	GuiText@ timerBox;

	OddityPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(150, 110);

		@name = GuiText(this, Alignment(Left+4, Top+2, Right-4, Top+24));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+4, Top+25, Right-4, Top+95));
		@timerBox = GuiText(this, Alignment(Left+10, Top+10, Right-10, Bottom-10));
		timerBox.horizAlign = 1.0;
		timerBox.vertAlign = 1.0;
		timerBox.visible = false;

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return Obj.isOddity;
	}

	void set(Object@ Obj) {
		@obj = Obj;
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
		if(obj.isStar) {
			Region@ reg = obj.region;
			if(reg !is null) {
				Empire@ other = reg.visiblePrimaryEmpire;
				if(other !is null)
					col = other.color;
			}
		}
		else if(obj.owner !is null)
			col = obj.owner.color;

		skin.draw(style, flags, bgPos, col);
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

		//Update name
		name.text = obj.name;
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;

		//Update timer
		Oddity@ odd = cast<Oddity>(obj);
		if(odd !is null) {
			double timer = odd.getTimer();
			if(timer <= 0.0) {
				timerBox.visible = false;
			}
			else {
				timerBox.visible = true;
				timerBox.text = formatTime(timer);
			}
		}

		Popup::update();
		Popup::updatePosition(obj);
	}
};
