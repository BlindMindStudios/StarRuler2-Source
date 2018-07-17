import elements.WordWrap;
import elements.BaseGuiElement;

export GuiText;

class GuiText : BaseGuiElement {
	string Text;
	WordWrap@ WordWrap;
	double HorizAlign = 0.0;
	double VertAlign = 0.5;
	bool flex = false;
	FontType TextFont = FT_Normal;
	vec2i textOffset;
	Color color;
	Color stroke(0x00000000);
	int strokeWidth = 1;
	
	GuiText(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	GuiText(IGuiElement@ ParentElement, const recti& Rectangle, const string &in Txt, FontType font = FT_Normal) {
		super(ParentElement, Rectangle);
		TextFont = font;
		text = Txt;
	}

	GuiText(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
	}

	GuiText(IGuiElement@ ParentElement, Alignment@ Align, const string& Txt, FontType font = FT_Normal) {
		super(ParentElement, Align);
		TextFont = font;
		text = Txt;
	}

	void set_wordWrap(bool wrap) {
		if(wrap) {
			@WordWrap = WordWrap();
			@WordWrap.font = skin.getFont(TextFont);
			WordWrap.text = Text;
			WordWrap.width = absolutePosition.width;
			WordWrap.update();
		}
		else {
			@WordWrap = null;
		}
		updateAbsolutePosition();
	}

	bool get_wordWrap() {
		return WordWrap !is null;
	}

	void set_text(const string& txt) {
		Text = txt;
		if(WordWrap !is null) {
			WordWrap.text = Text;
			WordWrap.update();
		}
		updateAbsolutePosition();
	}

	string get_text() {
		return Text;
	}

	void set_horizAlign(double align) {
		if(HorizAlign == align)
			return;
		HorizAlign = align;
		updateAbsolutePosition();
	}

	void set_vertAlign(double align) {
		if(VertAlign == align)
			return;
		VertAlign = align;
		updateAbsolutePosition();
	}

	void set_font(FontType type) {
		if(TextFont == type)
			return;
		TextFont = type;
		if(WordWrap !is null) {
			@WordWrap.font = skin.getFont(TextFont);
			WordWrap.update();
		}
		updateAbsolutePosition();
	}

	FontType get_font() {
		return TextFont;
	}

	int get_lineCount() {
		if(WordWrap !is null) {
			return WordWrap.lines.length();
		}
		else {
			return 1;
		}
	}

	vec2i getTextDimension() {
		const Font@ font = skin.getFont(TextFont);
		if(WordWrap !is null) {
			return vec2i(
				WordWrap.maxWidth,
				WordWrap.lines.length() * font.getLineHeight());
		}
		else {
			return font.getDimension(Text);
		}
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		if(skin is null)
			return;

		const Font@ font = skin.getFont(TextFont);
		vec2i textSize;

		if(WordWrap !is null) {
			WordWrap.width = absolutePosition.width;
			WordWrap.update();

			textSize.x = WordWrap.maxWidth;
			textSize.y = WordWrap.lines.length() * font.getLineHeight();
		}
		else {
			textSize = font.getDimension(Text);
		}

		if(flex) {
			textOffset = vec2i();
			textOffset.y += (font.getLineHeight() - font.getBaseline()) / 2;

			textSize.y = font.getLineHeight() + textOffset.y;
			size = textSize;
		}
		else {
			textOffset = (Position.size - textSize);
			textOffset.y += (font.getLineHeight() - font.getBaseline()) / 2;
			textOffset.x *= HorizAlign;
			textOffset.y *= VertAlign;
		}
	}

	void draw() {
		if(stroke.a != 0) {
			//LORD HAVE MERCY ON MY SOUL
			skin.draw(TextFont, AbsolutePosition.topLeft + textOffset + vec2i(strokeWidth, strokeWidth), Text, stroke);
			skin.draw(TextFont, AbsolutePosition.topLeft + textOffset + vec2i(-strokeWidth, -strokeWidth), Text, stroke);
			skin.draw(TextFont, AbsolutePosition.topLeft + textOffset + vec2i(strokeWidth, -strokeWidth), Text, stroke);
			skin.draw(TextFont, AbsolutePosition.topLeft + textOffset + vec2i(-strokeWidth, strokeWidth), Text, stroke);
		}
		skin.draw(TextFont, AbsolutePosition.topLeft + textOffset, Text, color);
		BaseGuiElement::draw();
	}
};
