import elements.BaseGuiElement;
import elements.GuiButton;
from input import activeCamera;

enum PopupAction {
	PA_Select,
	PA_Manage,
	PA_Zoom,
};

class Popup : BaseGuiElement {
	GuiButton@ pinButton;
	GuiButton@ closeButton;

	bool Hovered = false;
	bool separated = false;
	bool dragging = false;
	bool dragged = false;
	bool mouseLinked = false;
	bool objLinked = false;
	bool findPin = false;
	bool isSelectable = false;
	double zDist = 0;
	vec2i dragStart;
	vec2i objOffset;
	vec2i mouseOffset;

	Popup(BaseGuiElement@ parent) {
		super(parent, recti(0, 0, 190, 115));

		@closeButton = GuiButton(this, Alignment(Right-18, Top+6, Right-4, Top+20));
		closeButton.style = SS_GameTabClose;
	}

	bool compatible(Object@ obj) {
		return false;
	}

	Object@ get() {
		return null;
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) {
		//Make sure we can zoom over this
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0) {
					if(isSelectable) {
						return true;
					}
					else {
						dragging = true;
						dragged = false;
						dragStart = mousePos;
						return true;
					}
				}
			break;
			case MET_Button_Up:
				if(evt.button == 0) {
					if(dragging) {
						dragging = false;
						dragged = false;
					}
					else if(isSelectable) {
						emitClicked(PA_Select);
					}
					return true;
				}
				else if(evt.button == 1 && !isSelectable) {
					if(separated)
						remove();
					else
						visible = false;
					return true;
				}
			break;
			case MET_Scrolled:
				if(!isSelectable)
					activeCamera.zoom(evt.y);
				return true;
			case MET_Moved:
				if(dragging) {
					if(separated) {
						vec2i moved = mousePos - dragStart;
						if(!dragged) {
							if(moved.x < 2 && moved.y < 2)
								return false;
						}

						dragged = true;
						objLinked = false;
						move(moved);
						dragStart = mousePos;
						return true;
					}
					else {
						vec2i moved = mousePos - dragStart;
						if(moved.x < 2 && moved.y < 2)
							return false;

						separated = true;
						objLinked = false;
						mouseLinked = false;
						dragStart = mousePos;
						return true;
					}
				}
			break;
		}

		return BaseGuiElement::onMouseEvent(evt, source);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				if(evt.caller is this)
					Hovered = true;
			break;
			case GUI_Mouse_Left:
				if(evt.caller is this)
					Hovered = false;
			break;
			case GUI_Clicked:
				if(evt.caller is closeButton) {
					remove();
					return true;
				}
				else if(evt.caller is pinButton) {
					separated = true;
					objLinked = shiftKey;
					mouseLinked = false;
					findPin = true;
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void set(Object@ obj) {
	}

	bool displays(Object@ obj) {
		return get() is obj;
	}

	void update() {
		if(pinButton !is null)
			pinButton.visible = !mouseLinked && !separated;
		if(closeButton !is null)
			closeButton.visible = separated;
	}

	vec2i objPos(Object@ obj) {
		if(parent is null)
			return vec2i();
		vec2i pos = activeCamera.camera.screenPos(obj.node_position);
		pos -= parent.absolutePosition.topLeft;
		pos.x += 16;
		return pos;
	}

	void updatePosition(Object@ obj) {
		if(parent is null)
			return;
		zDist = 0;
		if(obj !is null)
			obj.focus();
		if(objLinked && obj !is null) {
			vec2i newPos = objPos(obj);
			newPos += objOffset;
			position = newPos;
			zDist = obj.node_position.distanceToSQ(activeCamera.camera.position);
		}
		else if(mouseLinked) {
			vec2i newPos = mousePos;
			newPos -= parent.absolutePosition.topLeft;
			newPos.x += 16;
			newPos += mouseOffset;
			position = newPos;
		}
		if(closeButton !is null)
			closeButton.bringToFront();
	}

	int opCmp(const Popup@ other) const {
		if(other is null)
			return 0;
		double diff = zDist - other.zDist;
		if(diff < 0)
			return -1;
		else if(diff > 0)
			return 1;
		else
			return 0;
	}
};
