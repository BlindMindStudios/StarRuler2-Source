import elements.BaseGuiElement;

export GuiAligned;

class GuiAligned : BaseGuiElement {
	double horizAlign = 0.5;
	double vertAlign = 0.5;
	
	GuiAligned(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	GuiAligned(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		vec2i _min = size;
		vec2i _max;

		for(uint i = 0, cnt = Children.length; i < cnt; ++i) {
			IGuiElement@ child = Children[i];
			if(!child.visible)
				continue;

			recti pos = child.rect;
			_min.x = min(_min.x, pos.topLeft.x);
			_min.y = min(_min.y, pos.topLeft.y);
			_max.x = max(_max.x, pos.botRight.x);
			_max.y = max(_max.y, pos.botRight.y);
		}

		int w = _max.x - _min.x;
		int h = _max.y - _min.y;

		vec2i sz = size;
		vec2i off;
		off.x = double(sz.width - w) * horizAlign;
		off.y = double(sz.height - h) * vertAlign;

		for(uint i = 0, cnt = Children.length; i < cnt; ++i) {
			IGuiElement@ child = Children[i];
			vec2i pos = child.position;
			pos = (pos - _min) + off;
			child.position = pos;
		}
	}
};
