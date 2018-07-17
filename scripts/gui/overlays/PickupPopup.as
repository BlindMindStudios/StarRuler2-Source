import overlays.Popup;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.Gui3DObject;
import util.formatting;
import pickups;
import icons;
from overlays.ShipPopup import ShipPopup;
from overlays.ContextMenu import openContextMenu;

class PickupPopup : Popup {
	GuiText@ title;
	GuiText@ name;
	GuiMarkupText@ description;
	Gui3DObject@ objView;
	Pickup@ obj;
	double lastUpdate = -INFINITY;
	ShipPopup@ ship;

	PickupPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(180, 220);

		@title = GuiText(this, Alignment(Left+4, Top+4, Right-4, Top+24), locale::PICKUP_PROTECTING);
		title.font = FT_Bold;
		title.vertAlign = 0.0;

		@name = GuiText(this, Alignment(Left+4, Top+20, Right-4, Top+46));
		name.horizAlign = 0.5;

		@objView = Gui3DObject(this, Alignment(Left+3, Top+46, Right-4, Top+130));

		@description = GuiMarkupText(this, Alignment(Left+8, Top+134, Right-8, Bottom-4));

		@ship = ShipPopup(null);
		ship.mouseLinked = true;
		ship.updateAbsolutePosition();

		updateAbsolutePosition();
	}

	void remove() {
		ship.remove();
		Popup::remove();
	}

	void set_visible(bool v) {
		ship.visible = v;
		Popup::set_visible(v);
	}

	bool compatible(Object@ Obj) {
		return Obj.isPickup;
	}

	void set(Object@ Obj) {
		@obj = cast<Pickup>(Obj);
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
		skin.draw(SS_BG3D, SF_Normal, objView.absolutePosition);
		skin.draw(SS_SubTitle, SF_Normal, recti_area(bgPos.topLeft+vec2i(2,1), vec2i(bgPos.width-5, 45)));
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
		Ship@ prot = cast<Ship>(obj.getProtector());
		if(!separated && prot !is null && prot.valid) {
			if(ship.get() !is prot)
				ship.set(prot);
			ship.update();
			ship.visible = true;

			objOffset = vec2i(200, 0);
			mouseOffset = objOffset;

			title.text = locale::PICKUP_PROTECTING;
			title.color = colors::Artifact;
		}
		else {
			ship.visible = false;

			objOffset = vec2i();
			mouseOffset = objOffset;

			title.text = locale::PICKUP_UNPROTECTED;
			title.color = colors::Green;
		}

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

		const PickupType@ type = getPickupType(obj.PickupType);
		if(type !is null)
			description.text = type.description;
		else
			description.text = "--";

		Popup::update();
		Popup::updatePosition(obj);
	}
};
