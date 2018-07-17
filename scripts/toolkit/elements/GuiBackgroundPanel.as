import elements.BaseGuiElement;
from elements.GuiMarkupText import GuiMarkupText;

export GuiBackgroundPanel;

class GuiBackgroundPanel : BaseGuiElement {
	string Title;
	FontType titleFont = FT_Medium;
	Color titleColor;
	Sprite picture;
	Color pictureColor(0xffffff10);
	GuiMarkupText@ markupBox;
	SkinStyle titleStyle = SS_PanelTitle;
	float titleWidth = 0.5f;
	int titleHeight = 30;
	vec2f maxSize(2.f, 2.f);

	GuiBackgroundPanel(IGuiElement@ Parent, recti pos) {
		super(Parent, pos);
	}

	GuiBackgroundPanel(IGuiElement@ Parent, Alignment@ align) {
		super(Parent, align);
	}

	void set_markup(bool value) {
		if(value) {
			if(markupBox is null) {
				@markupBox = GuiMarkupText(this, Alignment(Left+12, Top, Left+0.7f-12, Height=28));
				markupBox.text = Title;
				markupBox.visible = Title.length != 0;
				markupBox.defaultFont = FT_Medium;
			}
		}
		else {
			if(markupBox !is null) {
				markupBox.remove();
				@markupBox = null;
			}
		}
	}

	void set_title(const string& text) {
		Title = text;
		if(markupBox !is null) {
			markupBox.text = text;
			markupBox.visible = text.length != 0;
		}
	}

	const string& get_title() {
		return Title;
	}

	void draw() {
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition);

		if(title.length != 0) {
			skin.draw(titleStyle, SF_Normal,
					recti_area(AbsolutePosition.topLeft + vec2i(1,1),
						vec2i(size.width - 3, titleHeight)), titleColor);

			if(markupBox is null) {
				const Font@ ft = skin.getFont(titleFont);
				ft.draw(pos=recti_area(AbsolutePosition.topLeft+vec2i(12, 4), vec2i(size.width*titleWidth, titleHeight-10)),
						ellipsis=locale::ELLIPSIS, text=title, vertAlign=0.5);
			}
		}

		if(picture.valid) {
			vec2i psize = picture.size;
			recti pos = recti(AbsolutePosition.botRight - vec2i(
						min(size.width * 0.5, float(psize.x) * maxSize.x - 8),
						min(float(size.height - 40), float(psize.y) * maxSize.y - 8)),
								AbsolutePosition.botRight - vec2i(8, 8));
			pos = pos.aspectAligned(float(psize.width) / float(psize.height), 1.0, 1.0);
			picture.draw(pos, pictureColor);
		}

		BaseGuiElement::draw();
	}
};
