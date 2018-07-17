import elements.BaseGuiElement;

export GuiResizeHandle;

class GuiResizeHandle : BaseGuiElement {
	IGuiElement@ element;
	bool dragging = false;
	vec2i startPos;
	vec2i startSize;
	vec2i minSize(0, 0);
	vec2i maxSize(INT_MAX, INT_MAX);
	SkinStyle style = SS_ResizeHandle;

	GuiResizeHandle(IGuiElement@ ParentElement, Alignment@ Align, IGuiElement@ drag = null) {
		super(ParentElement, Align);
		if(drag !is null)
			@element = drag;
		else
			@element = ParentElement;
		updateAbsolutePosition();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		switch(event.type) {
			case MET_Button_Down:
				if(event.button == 0) {
					dragging = true;
					startPos = mousePos;
					startSize = element.size;
					return true;
				}
			break;
			case MET_Button_Up:
				if(event.button == 0) {
					dragging = false;
					return true;
				}
			break;
			case MET_Moved:
				if(dragging) {
					vec2i diff = mousePos - startPos;
					vec2i newSize = startSize + diff;
					newSize.x = clamp(newSize.x, minSize.x, maxSize.x);
					newSize.y = clamp(newSize.y, minSize.y, maxSize.y);
					element.size = newSize;
					return true;
				}
			break;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		uint flags = SF_Normal;
		if(dragging)
			flags |= SF_Active;
		skin.draw(style, flags, AbsolutePosition);
		BaseGuiElement::draw();
	}
};
