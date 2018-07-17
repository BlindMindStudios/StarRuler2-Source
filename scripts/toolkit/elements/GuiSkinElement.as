import elements.BaseGuiElement;

export GuiSkinElement;

class GuiSkinElement : BaseGuiElement {
	SkinStyle style;
	uint flags;
	Color color;
	bool clickThrough = false;
	recti padding;
	
	GuiSkinElement(IGuiElement@ ParentElement, const recti& Rectangle, int Style, uint Flags = 0) {
		style = SkinStyle(Style);
		flags = Flags;
		super(ParentElement, Rectangle);
	}

	GuiSkinElement(IGuiElement@ ParentElement, Alignment@ alignment, int Style, uint Flags = 0) {
		style = SkinStyle(Style);
		flags = Flags;
		super(ParentElement, alignment);
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) {
		uint cCnt = Children.length();
		for(int i = cCnt - 1; i >= 0; --i) {
			if(!Children[i].visible)
				continue;

			IGuiElement@ ele = Children[i].elementFromPosition(pos);

			if(ele !is null)
				return ele;
		}
		
		if(!clickThrough && AbsoluteClipRect.isWithin(pos))
			return this;
		return null;
	}

	void draw() {
		skin.draw(style, flags,
				AbsolutePosition.padded(padding.topLeft.x,
					padding.topLeft.y, padding.botRight.x, padding.botRight.y),
				color);
		BaseGuiElement::draw();
	}
};
