import elements.BaseGuiElement;

export GuiProgressbar;

class GuiProgressbar : BaseGuiElement {
	const Material@ frontMaterial;
	const Material@ backMaterial;

	SkinStyle frontStyle = SS_ProgressBar;
	SkinStyle backStyle = SS_ProgressBarBG;

	Color frontColor;
	Color backColor;

	float progress = 0.5f;
	double textHorizAlign = 0.5;
	double textVertAlign = 0.5;
	int padding = 1;
	bool invert = false;

	FontType font = FT_Normal;
	string text;
	Color textColor;
	Color strokeColor(0x00000000);
	
	GuiProgressbar(IGuiElement@ ParentElement, const recti& Rectangle, float pct = 0.5f) {
		progress = pct;
		super(ParentElement, Rectangle);
	}

	GuiProgressbar(IGuiElement@ ParentElement, Alignment@ align, float pct = 0.5f) {
		progress = pct;
		super(ParentElement, align);
	}

	void set_color(Color c) {
		frontColor = c;
		backColor = c;
	}

	void draw() {
		recti backPos = AbsolutePosition;
		recti frontPos = backPos.padded(padding);
		frontPos.botRight.x -= float(frontPos.width) * (1.f - progress);

		if(invert){
			frontPos.topLeft.x = backPos.botRight.x - (frontPos.botRight.x - frontPos.topLeft.x);
			frontPos.botRight.x = backPos.botRight.x;
		}

		if(backMaterial !is null)
			backMaterial.draw(backPos, backColor);
		else
			skin.draw(backStyle, FT_Normal, backPos, backColor);

		if(frontMaterial !is null)
			frontMaterial.draw(frontPos, frontColor);
		else
			skin.draw(frontStyle, FT_Normal, frontPos, frontColor);

		if(text.length != 0)
			skin.getFont(font).draw(pos=backPos, text=text, color=textColor, horizAlign=textHorizAlign, vertAlign=textVertAlign, stroke=strokeColor);

		BaseGuiElement::draw();
	}
};
