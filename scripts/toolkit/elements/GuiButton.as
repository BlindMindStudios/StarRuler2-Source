import elements.BaseGuiElement;
import elements.GuiSprite;

export GuiButton, onButtonClick;

interface onButtonClick {
	bool onClick(GuiButton@ btn);
};

class GuiButton : BaseGuiElement {
	string Text;
	FontType TextFont = FT_Button;
	vec2i textOffset;
	vec2i textSize;
	double HorizAlign = 0.5;
	double VertAlign = 0.5;
	bool Pressed = false;
	bool Hovered = false;
	bool Focused = false;
	bool disabled = false;
	bool Toggle = false;
	bool allowOtherButtons = false;
	Color textColor = colors::Invisible;
	Color color;
	Sprite Icon;
	GuiSprite@ fullIcon;

	onButtonClick@ onClick;

	SkinStyle style = SS_Button;
	Sprite spriteStyle;
	
	GuiButton(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
		navigable = true;
	}

	GuiButton(IGuiElement@ ParentElement, const recti& Rectangle, const string&in DefaultText) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
		text = DefaultText;
		navigable = true;
	}
	
	GuiButton(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
		navigable = true;
	}

	GuiButton(IGuiElement@ ParentElement, Alignment@ Align, const string& DefaultText) {
		super(ParentElement, Align);
		updateAbsolutePosition();
		text = DefaultText;
		navigable = true;
	}

	GuiButton(IGuiElement@ ParentElement, const recti& Rectangle, const Sprite& sprt) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
		setIcon(sprt);
		navigable = true;
	}

	GuiButton(IGuiElement@ ParentElement, Alignment@ Align, const Sprite& sprt) {
		super(ParentElement, Align);
		updateAbsolutePosition();
		setIcon(sprt);
		navigable = true;
	}
	
	GuiButton(bool NoParent) {
		super(NoParent);
	}
	
	string get_elementType() const {
		return "button";
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Mouse_Entered:
				if(event.caller is this) {
					if(!skin.isIrregular(style))
						Hovered = true;
				}
			break;
			case GUI_Mouse_Left:
				if(event.caller is this) {
					Hovered = false;
					if(!Toggle)
						Pressed = false;
				}
			break;
			case GUI_Focused:
				Focused = true;
			break;
			case GUI_Focus_Lost:
				if(!isAncestorOf(event.other)) {
					Focused = false;
					if(!Toggle)
						Pressed = false;
				}
			break;
			case GUI_Controller_Down:
				if(event.caller is this) {
					if(event.value == GP_A) {
						if(Toggle) {
							Pressed = !Pressed;
							emitClick();
						}
						else {
							Pressed = true;
						}
						return true;
					}
				}
			break;
			case GUI_Controller_Up:
				if(Focused) {
					if(event.value == GP_A) {
						if(Pressed && !Toggle) {
							Pressed = false;
							emitClick();
						}
						return true;
					}
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void emitClick(int btn = 0) {
		if(onClick !is null && onClick.onClick(this))
			return;
		GuiEvent evt;
		evt.type = GUI_Clicked;
		@evt.caller = this;
		evt.value = btn;
		onGuiEvent(evt);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source.isChildOf(this)) {
			if(disabled) {
				if(event.type == MET_Button_Down && (event.button == 0 || allowOtherButtons))
					return true;
				if(event.type == MET_Button_Up && (event.button == 0 || allowOtherButtons)) {
					sound::error.play(priority=true);
					return true;
				}
			}
			else switch(event.type) {
				case MET_Moved:
					if(skin.isIrregular(style)) {
						if(AbsolutePosition.isWithin(mousePos)) {
							Hovered = skin.isPixelActive(
									style, flags, AbsolutePosition,
									mousePos - AbsolutePosition.topLeft);
						}
					}
				break;
				case MET_Button_Down:
					if(!Hovered)
						return true;
					if(event.button == 0 || allowOtherButtons) {
						if(Toggle) {
							Pressed = !Pressed;
							emitClick(event.button);
						}
						else {
							Pressed = true;
						}
						return true;
					}
				break;
				case MET_Button_Up:
					if(Focused) {
						if(event.button == 0 || allowOtherButtons) {
							if(Pressed && !Toggle) {
								Pressed = false;
								if(Hovered)
									emitClick(event.button);
							}
							return true;
						}
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this || source.isChildOf(this)) {
			if(disabled) {
				if(event.key == KEY_ENTER) {
					if(event.type == KET_Key_Up) {
						sound::error.play(priority=true);
						return true;
					}
					else if(event.type == KET_Key_Down) {
						return true;
					}
				}
			}
			else switch(event.type) {
				case KET_Key_Down:
					if(event.key == KEY_ENTER) {
						if(Toggle) {
							Pressed = !Pressed;
							emitClick();
						}
						else {
							Pressed = true;
						}
						return true;
					}
				break;
				case KET_Key_Up:
					if(event.key == KEY_ENTER) {
						if(Pressed && !Toggle) {
							Pressed = false;
							emitClick();
						}
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void set_horizAlign(double align) {
		HorizAlign = align;
		centerText();
	}

	void set_vertAlign(double align) {
		VertAlign = align;
		centerText();
	}

	void centerText() {
		const Font@ font = skin.getFont(TextFont);
		vec2i textSize = font.getDimension(Text);
		int metric = min(size.height - 6, textSize.y + 8);

		if(Icon.valid)
			textSize.x += metric + 6;
		textOffset = Position.size - textSize;
		textOffset.x = double(textOffset.x - 8) * HorizAlign + 4;
		textOffset.y = double(textOffset.y) * VertAlign;
		textOffset.y += (textSize.y - font.getBaseline()) / 2;
		if(Icon.valid)
			textOffset.x += metric + 4;
	}
	
	void set_font(FontType type) {
		if(TextFont == type)
			return;
		TextFont = type;
		centerText();
	}

	void set_buttonIcon(const Sprite& sprt) {
		Icon = sprt;
		centerText();
	}

	GuiSprite@ setIcon(const Sprite& sprt, int padding = 5) {
		if(Text.length != 0) {
			buttonIcon = sprt;
			return null;
		}
		else {
			if(!sprt.valid) {
				if(fullIcon !is null)
					fullIcon.remove();
				return null;
			}
			if(fullIcon is null)
				@fullIcon = GuiSprite(this, Alignment().padded(padding));
			fullIcon.desc = sprt;
			return fullIcon;
		}
	}
	
	void set_text(const string& text) {
		Text = text;
		centerText();
	}

	string get_text() {
		return Text;
	}

	vec2i get_textSize() {
		const Font@ font = skin.getFont(TextFont);
		return font.getDimension(Text);
	}

	void set_toggleButton(bool t) {
		Toggle = t;
		Pressed = false;
	}

	bool get_toggleButton() {
		return Toggle;
	}

	bool get_pressed() {
		return Toggle ? Pressed : false;
	}

	void set_pressed(bool p) {
		if(Toggle)
			Pressed = p;
	}
	
	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		if(Text.length() > 0)
			centerText();
	}

	uint get_flags() {
		uint flags = SF_Normal;
		if(disabled)
			flags |= SF_Disabled;
		if(Pressed)
			flags |= SF_Active;
		if(Hovered)
			flags |= SF_Hovered;
		if(Focused)
			flags |= SF_Focused;
		return flags;
	}

	void draw() {
		if(spriteStyle.valid) {
			spriteStyle.index = 0;
			if(Hovered)
				spriteStyle.index = 1;
			spriteStyle.draw(AbsolutePosition, color);
		}
		else {
			skin.draw(style, flags, AbsolutePosition, color);
		}

		Color textCol = textColor;
		if(textCol.a == 0) {
			if(disabled)
				textCol = skin.getColor(SC_Disabled);
			else
				textCol = skin.getColor(SC_ButtonText);
		}

		if(Icon.valid) {
			int metric = min(size.height - 6, textSize.y + 8);
			recti pos = recti_area(AbsolutePosition.topLeft +
					vec2i(textOffset.x - metric - 6, (AbsolutePosition.height - metric) / 2 + 1 ), vec2i(metric, metric));
			Icon.draw(pos);
		}
		skin.draw(TextFont, AbsolutePosition.topLeft + textOffset, Text, textCol);
		BaseGuiElement::draw();
	}
};
