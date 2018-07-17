import elements.BaseGuiElement;

export GuiOverlay;

class GuiOverlay : BaseGuiElement {
	Color fade(0x00000090);
	IGuiElement@ prevFocus;
	bool closeSelf = true;
	bool pressed = false;

	GuiOverlay(IGuiElement@ ParentElement, bool grabHover = true) {
		@prevFocus = getGuiFocus();
		
		super(ParentElement, Alignment_Fill());
		updateAbsolutePosition();

		bringToFront();
		if(grabHover)
			clearGuiHovered();
		setGuiFocus(this);
	}

	void close() {
		remove();
		setGuiFocus(prevFocus);
	}

	bool onGuiEvent(const GuiEvent& event) override {
		switch(event.type) {
			case GUI_Navigation_Leave:
				if(!isAncestorOf(event.other)) {
					close();
					return false;
				}
			break;
			case GUI_Controller_Down:
				if(event.value == GP_B)
					return true;
			break;
			case GUI_Controller_Up:
				if(event.value == GP_B) {
					close();
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) override {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_ESC)
					return true;
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					close();
					return true;
				}
			break;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	IGuiElement@ navigate(NavigationMode mode, const recti& box, const vec2d&in line) override {
		float closestDist = FLOAT_INFINITY;
		IGuiElement@ closest;
		closestToLine(mode, box, line.normalized(), closestDist, closest, getGuiFocus());
		return closest;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(event.type == MET_Button_Down) {
			pressed = true;
			return true;
		}
		if(event.type == MET_Button_Up) {
			if(!pressed)
				return false;
			pressed = false;
			if(event.button != 0 && event.button != 1)
				return BaseGuiElement::onMouseEvent(event, source);
			if((!closeSelf && event.button == 0) && source !is this && isAncestorOf(source))
				return true;
			close();
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() override {
		if(fade.a != 0)
			drawRectangle(AbsolutePosition, fade);
		BaseGuiElement::draw();
	}
};
