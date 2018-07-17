import elements.BaseGuiElement;

export GuiCheckbox;

interface onCheckboxChange {
	bool onChange(GuiCheckbox@ btn);
};

class GuiCheckbox : BaseGuiElement {
	string text;
	FontType font = FT_Normal;
	Color textColor;
	int vertPadding = 2;
	int separation = 8;
	bool checked;
	bool Hovered = false;
	bool Focused = false;

	SkinStyle style = SS_Checkbox;
	onCheckboxChange@ onChange;
	
	GuiCheckbox(IGuiElement@ ParentElement, const recti& Rectangle, const string &in txt, bool Default = false) {
		checked = Default;
		text = txt;
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	GuiCheckbox(IGuiElement@ ParentElement, Alignment@ align, const string& txt, bool Default = false) {
		checked = Default;
		text = txt;
		super(ParentElement, align);
		updateAbsolutePosition();
	}

	void emitChange() {
		if(onChange !is null && onChange.onChange(this))
			return;
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Button_Down:
					return true;
				case MET_Button_Up:
					if(Focused) {
						if(event.button == 0) {
							if(Hovered) {
								checked = !checked;
								emitChange();
							}
						}
						return true;
					}
					break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hovered = true; break;
				case GUI_Mouse_Left:
					Hovered = false; break;
				case GUI_Focused:
					Focused = true;
				break;
				case GUI_Focus_Lost:
					Focused = false;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this && event.type == KET_Key_Up) {
			if(event.key == KEY_ENTER) {
				checked = !checked;
				emitChange();
				return true;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void draw() {
		const Font@ fnt = skin.getFont(font);

		//Draw checkbox
		uint flags = SF_Normal;
		if(checked)
			flags |= SF_Active;
		if(Hovered)
			flags |= SF_Hovered;

		int size = AbsolutePosition.height - vertPadding * 2;
		recti box = recti_area(
			AbsolutePosition.topLeft + vec2i(0, vertPadding),
			vec2i(size, size));

		skin.draw(style, flags, box);

		//Draw text
		int center = (AbsolutePosition.height - fnt.getBaseline()) / 2;
		vec2i pos = vec2i(size + separation, center);
		skin.draw(font, pos + AbsolutePosition.topLeft, text, textColor);

		BaseGuiElement::draw();
	}
};
