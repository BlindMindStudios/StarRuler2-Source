import elements.BaseGuiElement;

export GuiDraggable;

class GuiDraggable : BaseGuiElement {
	bool Dragging;
	bool allowPassthrough;
	bool btnDown = false;
	vec2i dragPos;
	vec2i dragOffset;

	GuiDraggable(IGuiElement@ ParentElement, const recti& Rectangle) {
		Dragging = false;
		allowPassthrough = true;
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || allowPassthrough) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0) {
						btnDown = true;
						dragPos = Position.topLeft;
						dragOffset = mousePos;
						bringToFront();
						return true;
					}
				break;
				case MET_Moved:
					if(Dragging) {
						position = mousePos - dragOffset + dragPos;
						return true;
					}
					else if(btnDown) {
						if((mousePos - dragOffset).length > 2)
							Dragging = true;
						return true;
					}
				break;
				case MET_Button_Up:
					if(event.button == 0) {
						btnDown = false;
						if(Dragging) {
							if(Position.topLeft != dragPos)
								emitChange();
							Dragging = false;
							return true;
						}
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Left:
				case GUI_Focus_Lost:
					if(Dragging)
						return true;
					break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};
