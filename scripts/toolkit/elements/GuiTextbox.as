import elements.BaseGuiElement;
import elements.WordWrap;

export GuiTextbox;

class GuiTextbox : BaseGuiElement {
	string Text;
	string emptyText;
	WordWrap@ wordWrap;
	FontType TextFont = FT_Normal;
	vec2i textOffset;
	vec2i textSize;
	bool Focused = false;
	bool Hovered = false;
	bool Dragging = false;
	bool MultiLine = false;
	bool EnterPressed = false;
	bool disabled = false;
	Color bgColor = colors::White;
	Color textColor = skin.getColor(SC_Text);
	Color selectionColor = skin.getColor(SC_Selected);

	set_int characterLimit;
	set_int characterExclude;
	SkinStyle style = SS_Textbox;

	int curs = 0;
	int selpos = -1;
	int scroll = 0;
	int HorizPadding = 7;
	int VertPadding = 3;
	int lineHeight = 1;
	int numLines = 0;
	int textWidth = 0;
	int fakeScrollX = -1;
	double cursAct = 0.0;
	
	GuiTextbox(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}
	
	GuiTextbox(IGuiElement@ ParentElement, const recti& Rectangle, const string &in DefaultText) {
		super(ParentElement, Rectangle);
		text = DefaultText;
		curs = DefaultText.length();
		updateAbsolutePosition();
	}

	GuiTextbox(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
	}
	
	GuiTextbox(IGuiElement@ ParentElement, Alignment@ Align, const string& DefaultText) {
		super(ParentElement, Align);
		text = DefaultText;
		curs = DefaultText.length();
		updateAbsolutePosition();
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hovered = true;
				break;
				case GUI_Mouse_Left:
					Hovered = false;
				break;
				case GUI_Focused:
					Focused = true;
					cursAct = frameTime;
				break;
				case GUI_Focus_Lost:
					Focused = false;
					Dragging = false;
					selpos = -1;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void setIdentifierLimit() {
		characterLimit.clear();
		for(int i = 'a'; i <= 'z'; ++i)
			characterLimit.insert(i);
		for(int i = 'A'; i <= 'Z'; ++i)
			characterLimit.insert(i);
		for(int i = '0'; i <= '9'; ++i)
			characterLimit.insert(i);
		characterLimit.insert('_');
	}

	void setFilenameLimit() {
		characterExclude.insert('/');
		characterExclude.insert('\\');
		characterExclude.insert('"');
		characterExclude.insert('>');
		characterExclude.insert('<');
		characterExclude.insert(':');
		characterExclude.insert('?');
		characterExclude.insert('|');
		characterExclude.insert('*');
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void focus(bool selectAll = false) {
		setGuiFocus(this);
		curs = Text.length;
		if(selectAll)
			selpos = 0;
		else
			selpos = -1;
	}

	void clear() {
		text = "";
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {

			switch(event.type) {
				case MET_Button_Down: {
					vec2i offset = vec2i(event.x, event.y) - AbsolutePosition.topLeft;
					int pos = getOffsetChar(offset);

					if(shiftKey && curs != pos) {
						if(selpos == -1) {
							selpos = curs;
							curs = pos;
						}
						else {
							curs = pos;
						}
					}
					else {
						curs = pos;
						selpos = -1;
					}
					Dragging = true;
				} return true;
				case MET_Moved: {
					if (Dragging) {
						vec2i offset = vec2i(event.x, event.y) - AbsolutePosition.topLeft;
						int pos = getOffsetChar(offset);

						if(pos != curs) {
							if(selpos == -1) {
								selpos = curs;
								curs = pos;
							}
							else {
								curs = pos;
							}
						}

						updateTextPosition();
						cursAct = frameTime;
						return true;
					}
				} break;
				case MET_Button_Up:
					if(Focused) {
						Dragging = false;
						return true;
					}
					break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void type(int code) {
		if(characterLimit.size() != 0 && !characterLimit.contains(code)) {
			sound::error.play();
			return;
		}
		if(characterExclude.size() != 0 && characterExclude.contains(code)) {
			sound::error.play();
			return;
		}
		cursAct = frameTime;
		int len = Text.length();
		int tmp;

		if(selpos >= 0) {
			string newText;
			int sell = -1, selr = -1;

			if(selpos > curs) {
				sell = curs;
				selr = selpos;
			}
			else {
				sell = selpos;
				selr = curs;
			}

			if(sell > 0)
				newText += Text.substr(0, sell);

			u8append(newText, code);

			if(len - selr > 0)
				newText += Text.substr(selr, len - selr);

			text = newText;
			selpos = -1;
			curs = sell;
			updateTextPosition();
			cursAct = frameTime;

			u8next(Text, curs, tmp);
			if(curs < 0)
				curs = Text.length();
		}
		else {
			if(curs == len) {
				string newText = Text;
				u8append(newText, code);
				text = newText;
			}
			else if(curs == 0) {
				string newText;
				u8append(newText, code);
				newText += Text;

				text = newText;
			}
			else {
				string newText;
				newText += Text.substr(0, curs);
				u8append(newText, code);
				newText += Text.substr(curs, len - curs);

				text = newText;
			}

			u8next(Text, curs, tmp);

			len = Text.length();
			if(curs < 0 || curs > len)
				curs = len;

			updateTextPosition();
		}
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(Focused && !disabled) {
			int tmp;
			int len = Text.length();

			switch(event.type) {
				case KET_Key_Typed:
					if(ctrlKey)
						return false;
					fakeScrollX = -1;
					type(event.key);
					emitChange();
					return true;
				case KET_Key_Down:
					switch(event.key) {
						case KEY_LOGICAL_A:
							if(ctrlKey) {
								curs = Text.length;
								selpos = 0;
								return true;
							}
							break;
						case KEY_LOGICAL_C:
							if(ctrlKey) {
								if(selpos >= curs)
									setClipboard(Text.substr(curs, selpos - curs));
								else
									setClipboard(Text.substr(selpos, curs - selpos));
								return true;
							}
							break;
						case KEY_LOGICAL_X:
							if(ctrlKey) {
								if(selpos >= 0 && curs >= 0) {
									if(selpos >= curs)
										setClipboard(Text.substr(curs, selpos - curs + 1));
									else
										setClipboard(Text.substr(selpos, curs - selpos));
										
									//Remove current selection
									if(selpos < curs) {
										tmp = selpos;
										selpos = curs;
										curs = tmp;
									}
									
									text = Text.substr(0, curs) + Text.substr(selpos, len - selpos);
									selpos = -1;
									
									updateTextPosition();
									cursAct = frameTime;
									emitChange();
								}
								return true;
							}
							break;
						case KEY_LOGICAL_V:
							if(ctrlKey) {
								//Remove current selection
								if(selpos != -1) {
									if(selpos < curs) {
										tmp = selpos;
										selpos = curs;
										curs = tmp;
									}
									
									text = Text.substr(0, curs) + Text.substr(selpos, len - selpos);
									selpos = -1;
								}
							
								//Insert clipboard text and advance cursor
								string clipText = getClipboard();
								text = Text.substr(0, curs) + clipText + Text.substr(curs, len - curs);
								curs += clipText.length();
								updateTextPosition();
								emitChange();
								return true;
							}
							break;
						case KEY_BACKSPACE: {
							if(curs <= 0 && selpos == -1)
								break;
							if(selpos == -1) {
								int prevPos = curs;
								u8prev(Text, prevPos, tmp);

								string newText;

								if(prevPos > 0)
									newText += Text.substr(0, prevPos);

								if(len - curs > 0)
									newText += Text.substr(curs, len - curs);

								text = newText;

								curs = prevPos;
								updateTextPosition();
								cursAct = frameTime;
								emitChange();
								return true;
							}
						}
						case KEY_DEL: {
							fakeScrollX = -1;
							if(selpos >= 0) {
								string newText;
								int sell = -1, selr = -1;

								if(selpos > curs) {
									sell = curs;
									selr = selpos;
								}
								else {
									sell = selpos;
									selr = curs;
								}

								if(sell > 0)
									newText += Text.substr(0, sell);

								if(len - selr > 0)
									newText += Text.substr(selr, len - selr);

								text = newText;
								selpos = -1;
								curs = sell;
								updateTextPosition();
								cursAct = frameTime;
								emitChange();
								return true;
							}
							else if(curs < len) {
								int prevPos = curs;
								u8next(Text, prevPos, tmp);

								string newText;

								if(curs > 0)
									newText += Text.substr(0, curs);

								if(len - prevPos > 0)
									newText += Text.substr(prevPos, len - prevPos);

								text = newText;

								updateTextPosition();
								cursAct = frameTime;
								emitChange();
								return true;
							}
						} break;
						case KEY_ESC:
							if(selpos != -1) {
								return true;
							}
						return BaseGuiElement::onKeyEvent(event, source);
						case KEY_LEFT: {
							cursAct = frameTime;
							fakeScrollX = -1;
							if(curs > 0) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								u8prev(Text, curs, tmp);

								if(curs < 0 || curs > len)
									curs = 0;

								updateTextPosition();
							}
						} return true;
						case KEY_DOWN: {
							if(curs >= 0 && MultiLine) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								vec2i offset = getCharOffset(curs);

								int line = getCharLine(curs);
								if(line == scroll + numLines - 1) {
									if(line == wordWrap.lineCount - 1)
										break;
									scroll += 1;
								}
								else {
									offset.y += lineHeight;
								}

								if(fakeScrollX != -1)
									offset.x = fakeScrollX;
								else
									fakeScrollX = offset.x;

								curs = getOffsetChar(offset);

								cursAct = frameTime;
								updateTextPosition();
								return true;
							}
						} return BaseGuiElement::onKeyEvent(event, source);
						case KEY_UP: {
							if(curs > 0 && MultiLine) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								vec2i offset = getCharOffset(curs);
								int line = getCharLine(curs);

								if(line == scroll) {
									if(line == 0)
										break;
									scroll -= 1;
								}
								else {
									offset.y -= lineHeight;
								}

								if(fakeScrollX != -1)
									offset.x = fakeScrollX;
								else
									fakeScrollX = offset.x;

								curs = getOffsetChar(offset);

								cursAct = frameTime;
								updateTextPosition();
								return true;
							}
						} return BaseGuiElement::onKeyEvent(event, source);
						case KEY_PAGEDOWN: {
							if(curs >= 0 && MultiLine) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								vec2i offset = getCharOffset(curs);

								scroll = min(wordWrap.lineCount - numLines, scroll + numLines);

								if(fakeScrollX != -1)
									offset.x = fakeScrollX;
								else
									fakeScrollX = offset.x;

								curs = getOffsetChar(offset);

								cursAct = frameTime;
								updateTextPosition();
							}
						} return true;
						case KEY_PAGEUP: {
							if(curs > 0 && MultiLine) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								vec2i offset = getCharOffset(curs);

								scroll = max(0, scroll - numLines);

								if(fakeScrollX != -1)
									offset.x = fakeScrollX;
								else
									fakeScrollX = offset.x;

								curs = getOffsetChar(offset);

								cursAct = frameTime;
								updateTextPosition();
							}
						} return true;
						case KEY_HOME: {
							if(shiftKey) {
								if(selpos == -1)
									selpos = curs;
							}
							else {
								selpos = -1;
							}

							fakeScrollX = -1;
							cursAct = frameTime;
							if(MultiLine) {
								int line = getCharLine(curs);
								curs = wordWrap.positions[line];
							}
							else {
								curs = 0;
							}
							updateTextPosition();
						} return true;
						case KEY_END: {
							if(shiftKey) {
								if(selpos == -1)
									selpos = curs;
							}
							else {
								selpos = -1;
							}

							fakeScrollX = -1;
							cursAct = frameTime;
							if(MultiLine) {
								int line = getCharLine(curs);
								curs = wordWrap.ends[line];
							}
							else {
								curs = Text.length();
							}
							updateTextPosition();
						} return true;
						case KEY_RIGHT: {
							cursAct = frameTime;
							fakeScrollX = -1;
							if(curs < len) {
								if(shiftKey) {
									if(selpos == -1)
										selpos = curs;
								}
								else {
									selpos = -1;
								}

								u8next(Text, curs, tmp);

								if(curs < 0 || curs > len)
									curs = len;

								updateTextPosition();
							}
						} return true;
						case KEY_ENTER: {
							fakeScrollX = -1;
							if(MultiLine) {
								type('\n');
								emitChanged();
							}
							else {
								EnterPressed = true;
							}
						} return true;
						case KEY_TAB:
							if(!MultiLine)
								return BaseGuiElement::onKeyEvent(event, source);
					}
				return !ctrlKey;
				case KET_Key_Up:
					switch(event.key) {
						case KEY_F1: {
							print("char:");
							for(int i = 0; i < len; ++i) {
								string debug = ""+Text[i]+": ";
								u8append(debug, Text[i]);
								print(debug);
							}

							print("utf8:");
							int pos = 0, ch = 0;
							while(pos >= 0) {
								u8next(Text, pos, ch);

								if(ch != 0) {
									string debug = ""+ch+": ";
									u8append(debug, ch);
									print(debug);
								}
							}
						} break;
						case KEY_F2:
							if(MultiLine) {
								print("cursor: "+curs);
								print("lines:");
								for(uint i = 0, cnt = wordWrap.lineCount; i < cnt; ++i) {
									print("Line "+i+": '"+wordWrap.lines[i]+"'");
									print(""+wordWrap.positions[i]+" to "+wordWrap.ends[i]);
								}
							}
						break;
						case KEY_DOWN:
						case KEY_UP:
							if(!MultiLine)
								return BaseGuiElement::onKeyEvent(event, source);
						break;
						case KEY_ESC:
							if(selpos != -1) {
								selpos = -1;
								return true;
							}
						return BaseGuiElement::onKeyEvent(event, source);
						case KEY_ENTER: {
							if(!MultiLine && EnterPressed) {
								GuiEvent evt;
								evt.type = GUI_Confirmed;
								@evt.caller = this;
								onGuiEvent(evt);
								EnterPressed = false;
							}
						} return true;
						case KEY_TAB:
							if(!MultiLine)
								return BaseGuiElement::onKeyEvent(event, source);
					}
				return !ctrlKey;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void centerText() {
		const Font@ font = skin.getFont(TextFont);

		if(!Focused && Text.length == 0)
			textSize = font.getDimension(emptyText);
		else
			textSize = font.getDimension(Text);

		textOffset.x = HorizPadding;

		lineHeight = font.getLineHeight();
		textWidth = AbsolutePosition.width - HorizPadding * 2;
		
		if(MultiLine) {
			wordWrap.width = textWidth;
			textOffset.y = VertPadding;
		}
		else {
			textOffset.y = (Position.height - font.getBaseline()) / 2;
		}
	}

	void updateTextPosition() {
		const Font@ font = skin.getFont(TextFont);
		centerText();

		if(!MultiLine) {
			numLines = 1;
			if(curs < scroll) {
				scroll = curs;
			}
			else {
				vec2i charOffset = getCharOffset(curs);
				if(charOffset.x >= AbsolutePosition.width - padding)
					scroll = getOffsetChar(vec2i(charOffset.x - textWidth + padding, 0));
			}
		}
		else {
			scroll = max(0, min(wordWrap.lineCount - 1, scroll));
			numLines = max(floor(double(AbsolutePosition.height - 2 * VertPadding) / double(lineHeight)), 0.f);
			while(curs < wordWrap.positions[scroll])
				scroll -= 1;
			while(scroll + numLines <= wordWrap.lineCount - 1 && curs >= wordWrap.positions[scroll + numLines])
				scroll += 1;
		}
	}

	int getOffsetChar(vec2i offset) {
		const Font@ font = skin.getFont(TextFont);

		int pos, line;
		int c = 0, lastC = 0;
		offset -= textOffset;

		if(MultiLine) {
			line = floor(double(offset.y - VertPadding) / double(lineHeight)) + scroll;
			line = max(0, line);
			line = min(wordWrap.lineCount - 1, line);

			pos = wordWrap.positions[line];
		}
		else {
			pos = scroll;
		}

		do {
			if(MultiLine) {
				if(line < wordWrap.lineCount - 1 && pos >= wordWrap.positions[line + 1]) {
					int pos = wordWrap.positions[line + 1];
					int tmp;
					u8prev(Text, pos, tmp);
					return pos;
				}
			}

			int prevPos = pos;
			u8next(Text, pos, c);
			int w = font.getDimension(c, lastC).x;
			lastC = c;

			if(MultiLine && pos == -1)
				return wordWrap.ends[line];

			if(offset.x < w / 2)
				return prevPos;

			offset.x -= w;
		}
		while (pos >= 0 && pos < int(Text.length()));

		return Text.length();
	}

	int getCharLine(int pos) {
		if(!MultiLine)
			return 0;

		int line = scroll;
		while(line < wordWrap.lineCount - 1 && pos >= wordWrap.positions[line + 1])
			line += 1;

		return line;
	}

	vec2i getCharOffset(int pos) {
		const Font@ font = skin.getFont(TextFont);

		if(MultiLine) {
			if(pos < wordWrap.positions[scroll])
				return vec2i();

			//Find the line it's on
			int line = getCharLine(pos);

			//Find the position of the character
			int x = padding;
			int start = wordWrap.positions[line];
			
			int c = 0, lastC = 0;
			while(start < int(Text.length()) && start < pos) {
				u8next(Text, start, c);
				x += font.getDimension(c, lastC).x;

				if(start == -1)
					break;

				lastC = c;
			}

			return vec2i(x, padding + (line - scroll) * lineHeight);
		}
		else {
			if(pos < scroll)
				return vec2i();

			//Find the position of the character
			int x = padding;
			int start = scroll;
			
			int c = 0, lastC = 0;
			while(start < int(Text.length()) && start < pos) {
				u8next(Text, start, c);
				x += font.getDimension(c, lastC).x;

				if(start == -1)
					break;

				lastC = c;
			}

			return vec2i(x, padding);
		}
	}
	
	void set_font(FontType type) {
		if(TextFont == type)
			return;
		TextFont = type;
		centerText();
		if(MultiLine) {
			@wordWrap.font = skin.getFont(type);
			wordWrap.update();
		}
	}
	
	void set_text(const string& text) {
		Text = text;
		centerText();
		if(MultiLine) {
			wordWrap.text = text;
			wordWrap.update();
		}
		if(text.length == 0)
			scroll = 0;
		else
			scroll = clamp(scroll, 0, text.length-1);
	}

	string get_text() {
		return Text;
	}

	void set_multiLine(bool multi) {
		MultiLine = multi;
		if(MultiLine) {
			scroll = 0;

			@wordWrap = WordWrap();
			@wordWrap.font = skin.getFont(TextFont);
			wordWrap.text = Text;
			wordWrap.width = textWidth;
			wordWrap.update();
		}
		else {
			@wordWrap = null;
		}
		updateTextPosition();
	}

	void set_padding(int pad) {
		HorizPadding = pad;
		VertPadding = pad;
		updateTextPosition();
		if(MultiLine)
			wordWrap.update();
	}

	int get_padding() {
		return HorizPadding;
	}
	
	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		if(Text.length != 0 || emptyText.length != 0) {
			centerText();

			if(MultiLine)
				wordWrap.update();
		}
	}
	
	void draw() {
		uint flags = SF_Normal;
		if(Focused)
			flags |= SF_Focused;
		if(Hovered)
			flags |= SF_Hovered;
		if(disabled)
			flags |= SF_Disabled;

		skin.draw(style, flags, AbsolutePosition, bgColor);

		int sell = -1, selr = -1;

		if(selpos >= 0) {
			if(selpos > curs) {
				sell = curs;
				selr = selpos;
			}
			else {
				sell = selpos;
				selr = curs;
			}
		}

		int pos = 0, ch = 0, prevCh = 0;
		int bgOffset = (Position.height - textSize.y) / 2;
		const Font@ font = skin.getFont(TextFont);
		Color color = textColor;
		if(Text.length == 0)
			color.a = 0x80;
		Color selColor = selectionColor;
		vec2i drawPos = AbsolutePosition.topLeft + textOffset;

		recti cursPos;
		bool setCursor = false;

		if(MultiLine) {
			clipParent(recti(AbsolutePosition.topLeft + vec2i(HorizPadding, VertPadding),
						  AbsolutePosition.botRight - vec2i(HorizPadding, VertPadding)));
		}
		else {
			clipParent(recti(AbsolutePosition.topLeft + vec2i(HorizPadding, 0),
						  AbsolutePosition.botRight - vec2i(HorizPadding, 0)));
		}

		double time = frameTime;
		bool drawCurs = Focused && (time - floor(time) < 0.5 || time - cursAct < 0.5);

		int line;
		if(MultiLine) {
			if(wordWrap.positions.length > uint(scroll))
				pos = wordWrap.positions[scroll];
			else
				pos = 0;
			line = scroll;
		}

		int startPos = pos;
		while(pos >= 0) {
			int prevPos = pos;
			if(MultiLine) {
				if(line < wordWrap.lineCount - 1 && pos >= wordWrap.positions[line + 1]) {
					//Emit fake newlines if crossing line boundaries for wordwrap
					line += 1;
					prevPos -= 1;
					ch = '\n';
				}
				else {
					//Suppress actual newlines
					if(!Focused && Text.length == 0)
						u8next(emptyText, pos, ch);
					else
						u8next(Text, pos, ch);

					if(ch == '\n' && pos != -1)
						continue;
				}
			}
			else {
				if(!Focused && Text.length == 0)
					u8next(emptyText, pos, ch);
				else
					u8next(Text, pos, ch);
			}

			if(ch != 0 && (MultiLine || prevPos >= scroll)) {
				if(ch == 10 && MultiLine) {
					if(!setCursor && drawCurs && curs == prevPos) {
						cursPos = recti_area(drawPos, vec2i(1, lineHeight));
						setCursor = true;
					}

					drawPos.y += lineHeight;
					drawPos.x = AbsolutePosition.topLeft.x + textOffset.x;
					prevCh = ch;

					if(drawPos.y > AbsolutePosition.botRight.y)
						break;
					else
						continue;
				}

				int width = font.getDimension(ch, prevCh).x;

				if(drawPos.x + width > AbsolutePosition.botRight.x) {
					if(MultiLine)
						continue;
					else
						break;
				}

				if(prevPos >= sell && prevPos < selr) {
					recti selPos = recti_area(drawPos, vec2i(width, lineHeight));
					drawRectangle(selPos, selColor);
				}

				if(!setCursor && drawCurs && curs == prevPos) {
					cursPos = recti_area(drawPos, vec2i(1, lineHeight));
					setCursor = true;
				}

				skin.draw(TextFont, drawPos, ch, prevCh, color);

				drawPos.x += width;
				prevCh = ch;

			}
		}

		if(drawCurs) {
			clipParent();
			if(!setCursor)
				cursPos = recti_area(drawPos, vec2i(1, lineHeight));
			drawRectangle(cursPos, color);
		}
		
		BaseGuiElement::draw();
	}
};
