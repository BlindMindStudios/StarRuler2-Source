import elements.BaseGuiElement;
import elements.GuiScrollbar;
import elements.GuiMarkupText;

export GuiListElement, GuiListText, GuiListbox;
export GuiMarkupListText;

class GuiListElement {
	void set(const string& txt) {
		throw("Setting item text on a non-textual list element.");
	}

	string get() {
		return "";
	}

	string get_tooltipText() {
		return "";
	}

	ITooltip@ get_tooltip() {
		return null;
	}

	bool get_isSelectable() {
		return true;
	}

	bool onMouseEvent(const MouseEvent& event) {
		return false;
	}

	void onSelect() {
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
	}

	int opCmp(const GuiListElement@ other) const {
		return 0;
	}
};

class GuiListText : GuiListElement {
	string text;
	Sprite icon;

	GuiListText(const string& txt, const Sprite& icon = Sprite()) {
		text = txt;
		this.icon = icon;
	}

	void set(const string& txt) {
		text = txt;
	}

	string get() {
		return text;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();
		vec2i textOffset(ele.horizPadding, (absPos.size.height - baseLine) / 2);

		if(ele.itemStyle == SS_NULL)
			ele.skin.draw(SS_ListboxItem, flags, absPos);

		if(icon.valid) {
			vec2i iconSize = icon.size;
			if(iconSize.y > absPos.height) {
				iconSize.x = double(absPos.height) / double(iconSize.y) * double(iconSize.x);
				iconSize.y = absPos.height;
			}
			vec2i iconOffset(ele.horizPadding, (absPos.height - iconSize.height) / 2);
			icon.draw(recti_area(absPos.topLeft + iconOffset, iconSize));
			textOffset.x += iconSize.width + 8;
		}

		font.draw(absPos.topLeft + textOffset, text);
	}
};

class GuiMarkupListText : GuiListElement {
	string text;
	string basicText;
	MarkupRenderer renderer;

	GuiMarkupListText(const string& txt, FontType font = FT_Normal) {
		text = txt;
		renderer.parseTree(txt);
		renderer.defaultFont = font;
	}

	void set(const string& txt) {
		text = txt;
		renderer.parseTree(txt);
	}

	string get() {
		return basicText.length == 0 ? text : basicText;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		if(ele.itemStyle == SS_NULL)
			ele.skin.draw(SS_ListboxItem, flags, absPos);
		renderer.draw(ele.skin, absPos.padded(ele.horizPadding, ele.vertPadding));
	}
};

class GuiListbox : BaseGuiElement {
	FontType TextFont = FT_Normal;

	GuiListElement@[] items;
	int selected = -1;
	int hovered = -1;
	int lineHeight = 0;
	int horizPadding = 6;
	int vertPadding = 5;
	bool Required = false;
	bool hoverSelect = false;
	bool ElementHovered = false;
	bool ElementFocused = false;

	bool Multiple = false;
	bool autoMultiple = true;
	bool[] SelectedItems;
	bool DblClickConfirm = true;
	int SelectedCount = 0;
	int PrevSelected = -1;
	int itemHeight = -1;
	bool disabled = false;

	string search;
	double searchTime = 0;
	double doubleTime = 0;

	SkinStyle style = SS_Listbox;
	SkinStyle itemStyle = SS_NULL;

	GuiScrollbar@ scroll;
	
	GuiListbox(IGuiElement@ ParentElement, const recti& Rectangle) {
		_GuiListbox();
		super(ParentElement, Rectangle);
		@scroll.parent = this;
	}

	GuiListbox(IGuiElement@ ParentElement, Alignment@ Align) {
		_GuiListbox();
		super(ParentElement, Align);
		@scroll.parent = this;
	}

	void sortAsc() {
		items.sortAsc();
	}

	void sortDesc() {
		items.sortDesc();
	}

	void scrollToEnd() {
		scroll.pos = max(0.0, scroll.end - scroll.page);
	}

	void _GuiListbox() {
		@scroll = GuiScrollbar(null, recti());
		scroll.alignment.set(
			AS_Right, 0.0, 20,   AS_Top, 0.0, 0,
			AS_Right, 0.0, 0,    AS_Bottom, 0.0, 0);
	}
	
	void addItem(GuiListElement@ elem, uint where) {
		items.insertAt(where, elem);

		if(multiple) {
			if(Required && SelectedCount <= 0) {
				SelectedItems.insertLast(true);
				SelectedCount = 1;
			}
			else
				SelectedItems.insertLast(false);
		}
		else if(Required && selected == -1) {
			selected = 0;
		}

		updateAbsolutePosition();
	}

	void addItem(GuiListElement@ elem) {
		addItem(elem, items.length);
	}

	void addItem(const string& item, uint where) {
		addItem(GuiListText(item), where);
	}

	void addItem(const string& item) {
		addItem(GuiListText(item), items.length);
	}

	void removeItem(uint index) {
		if(index < items.length()) {
			items.removeAt(index);

			if(multiple) {
				if(SelectedItems[index])
					SelectedCount -= 1;
				SelectedItems.removeAt(index);
			}
			else {
				if(selected >= int(items.length()))
					selected = items.length() - 1;
			}
		}

		updateAbsolutePosition();
	}

	void removeItemsFrom(uint index) {
		if(items.length > index)
			items.length = index;
		if(selected > 0 && selected >= int(index))
			selected = index - 1;
		updateAbsolutePosition();
	}

	void clearItems() {
		SelectedItems.length = 0;
		items.length = 0;
		selected = -1;
		hovered = -1;
		if(Tooltip !is null)
			Tooltip.update(skin, this);
		updateAbsolutePosition();
	}

	void setItem(uint index, const string& item) {
		if(index < items.length())
			items[index].set(item);
		else
			addItem(item);
	}

	void setItem(uint index, GuiListElement@ elem) {
		if(index < items.length())
			@items[index] = elem;
		else
			addItem(elem);
	}

	string getItem(uint index) {
		if(index < items.length())
			return items[index].get();
		return "";
	}

	GuiListElement@ getItemElement(uint index) {
		if(index < items.length())
			return items[index];
		return null;
	}

	GuiListElement@ get_selectedItem() {
		if(selected == -1 || Multiple)
			return null;
		return items[selected];
	}

	GuiListElement@ get_hoveredItem() {
		if(hovered == -1)
			return null;
		return items[hovered];
	}

	uint get_itemCount() {
		return items.length();
	}

	bool isSelected(uint index) {
		if(index >= items.length())
			return false;

		if(multiple)
			return SelectedItems[index];
		else
			return int(index) == selected;
	}

	uint get_selectedCount() {
		if(multiple)
			return SelectedCount;
		else
			return selected == -1 ? 0 : 1;
	}

	void clearSelection() {
		if(multiple) {
			for(uint i = 0, cnt = items.length(); i < cnt; ++i)
				SelectedItems[i] = false;

			if(Required && SelectedItems.length() > 0) {
				SelectedCount = 1;
				SelectedItems[0] = true;
			}
			else {
				SelectedCount = 0;
			}
		}
		else {
			selected = -1;
		}
	}

	ITooltip@ get_tooltipObject() {
		if(hovered >= 0 && hovered < int(items.length)) {
			ITooltip@ tt = items[hovered].tooltip;
			if(tt !is null)
				return tt;
		}
		return Tooltip;
	}

	string get_tooltip() {
		if(hovered != -1 && uint(hovered) < items.length) {
			string tt = items[hovered].tooltipText;
			if(tt.length != 0)
				return tt;
		}
		return BaseGuiElement::get_tooltip();
	}

	void set_multiple(bool mult) {
		if(Multiple == mult)
			return;
		Multiple = mult;

		if(Multiple) {
			SelectedItems.resize(items.length());
			for(uint i = 0, cnt = items.length(); i < cnt; ++i)
				SelectedItems[i] = false;

			if(selected != -1) {
				SelectedItems[selected] = true;
				SelectedCount = 1;
			}
			else {
				if(Required && SelectedItems.length() > 0) {
					SelectedItems[0] = true;
					SelectedCount = 1;
				}
				else {
					SelectedCount = 0;
				}
			}
		}
		else {
			SelectedItems.resize(0);

			if(Required && items.length() > 0)
				selected = 0;
			else
				selected = -1;
		}
	}

	bool get_multiple() {
		return Multiple;
	}
	
	void set_font(FontType type) {
		if(TextFont == type)
			return;
		TextFont = type;
		updateAbsolutePosition();
	}

	FontType get_font() const {
		return TextFont;
	}

	void set_required(bool req) {
		Required = req;

		if(Required) {
			if(Multiple) {
				if(SelectedCount <= 0 && items.length() > 0) {
					SelectedCount = 1;
					SelectedItems[0] = true;
				}
			}
			else {
				if(selected == -1 && items.length() > 0)
					selected = 0;
			}
		}
	}

	bool get_required() const {
		return Required;
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					ElementHovered = true;
				break;
				case GUI_Mouse_Left:
					ElementHovered = false;
				break;
				case GUI_Focused:
					ElementFocused = true;
				break;
				case GUI_Focus_Lost:
					ElementFocused = false;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void updateHover() {
		vec2i offset = mousePos - AbsolutePosition.topLeft;
		int prevHovered = hovered;
		hovered = getOffsetItem(offset);

		if(prevHovered != hovered)
			emitHoverChanged(hovered);
		if(hovered != prevHovered && Tooltip !is null)
			Tooltip.update(skin, this);
		if(hoverSelect && hovered >= 0 && !disabled)
			selected = hovered;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			updateHover();
			if(hovered >= 0 && items[hovered].onMouseEvent(event))
				return true;

			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0)
						return true;
				break;
				case MET_Button_Up: {
					if(disabled)
						return true;
					if(hoverSelect || !ElementFocused || event.button != 0)
						break;
					
					bool wasConfirmation = false;
					if(hovered == -1 || !items[hovered].isSelectable) {
						if(!Required)
							clearSelection();
					}
					else if(Multiple) {
						if(shiftKey && PrevSelected != -1) {
							int from = PrevSelected <= hovered ? PrevSelected : hovered;
							int to = PrevSelected > hovered ? PrevSelected : hovered;

							bool doSelected = SelectedItems[PrevSelected];

							for(int i = from; i <= to; ++i) {
								if(doSelected) {
									if(!SelectedItems[i]) {
										SelectedItems[i] = true;
										SelectedCount += 1;
									}
								}
								else {
									if(SelectedItems[i] && (!Required || SelectedCount > 1)) {
										SelectedItems[i] = false;
										SelectedCount -= 1;
									}
								}
							}
						}
						else {
							PrevSelected = hovered;

							if(SelectedItems[hovered]) {
								if(!ctrlKey && DblClickConfirm && frameTime < doubleTime + double(settings::iDoubleClickMS) * 0.001) {
									wasConfirmation = true;
									emitConfirmed(hovered);
									doubleTime = -INFINITY;
								}
								else if(ctrlKey || autoMultiple) {
									if(!Required || SelectedCount > 1) {
										SelectedItems[hovered] = false;
										SelectedCount -= 1;
									}
								}
								else {
									for(uint i = 0, cnt = items.length(); i < cnt; ++i)
										SelectedItems[i] = false;

									if(Required || SelectedCount > 1) {
										SelectedItems[hovered] = true;
										SelectedCount = 1;
									}
									else {
										SelectedCount = 0;
									}
								}
							}
							else {
								if(ctrlKey || autoMultiple) {
									SelectedItems[hovered] = true;
									SelectedCount += 1;
									doubleTime = frameTime;
								}
								else {
									for(uint i = 0, cnt = items.length(); i < cnt; ++i)
										SelectedItems[i] = false;
									SelectedItems[hovered] = true;
									SelectedCount = 1;
									doubleTime = frameTime;
								}
							}
						}
					}
					else {
						if(selected == hovered && DblClickConfirm && frameTime < doubleTime + double(settings::iDoubleClickMS) * 0.001) {
							wasConfirmation = true;
							emitConfirmed(hovered);
							doubleTime = -INFINITY;
						}
						else if(selected == hovered && !Required)
							selected = -1;
						else if(!Required || hovered != -1)
							selected = hovered;
					}
					
					if(!wasConfirmation)
						doubleTime = frameTime;

					if(selected >= 0 && !wasConfirmation)
						items[selected].onSelect();
						
					emitChange();
				} return true;
				case MET_Scrolled:
					if(scroll.visible)
						return scroll.onMouseEvent(event, scroll);
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void nextItem() {
		if(selected >= 0 && selected < int(items.length()) - 1) {
			selected += 1;

			if((selected + 1) * lineHeight - scroll.pos >= AbsolutePosition.height)
				scroll.pos = min(scroll.end - scroll.page, scroll.pos + lineHeight);
		}
	}

	void prevItem() {
		if(selected > 0) {
			selected -= 1;

			if(selected * lineHeight - scroll.pos < 0)
				scroll.pos = max(0.0, scroll.pos - lineHeight);
		}
	}

	void updateScroll() {
		if(selected * lineHeight - scroll.pos < 0)
			scroll.pos = max(0.0, double(selected * lineHeight));
		else if((selected + 1) * lineHeight - scroll.pos >= AbsolutePosition.height)
			scroll.pos = min(scroll.end - scroll.page, double(selected * lineHeight));
	}

	void doSearch() {
		searchTime = frameTime;

		uint start = selected == -1 ? 0 : uint(selected);
		int found = -1;
		for(uint i = 0, cnt = items.length; i < cnt; ++i) {
			int index = int((start + i) % cnt);
			string text = items[index].get();
			if(text.length == 0)
				continue;
			if(text.startswith_nocase(search)) {
				found = index;
				break;
			}
		}
		if(found != -1 && selected != found) {
			selected = found;
			emitChange();
			updateScroll();
		}
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this) {
			if(!Multiple) {
				if(event.type == KET_Key_Down) {
					int pageItems = ceil(double(AbsolutePosition.height) / double(lineHeight));

					switch(event.key) {
						case KEY_UP:
							if(!disabled)
								prevItem();
							return true;
						case KEY_DOWN:
							if(!disabled)
								nextItem();
							return true;
						case KEY_ENTER:
							return true;
						case KEY_PAGEUP:
							if(selected > 0) {
								if(disabled)
									return true;
								selected = max(0, selected - pageItems);
								scroll.pos = max(0.0, scroll.pos - AbsolutePosition.height);
								return true;
							}
						break;
						case KEY_PAGEDOWN:
							if(selected >= 0) {
								if(disabled)
									return true;
								selected = min(items.length() - 1, selected + pageItems);
								scroll.pos = min(scroll.end - scroll.page, scroll.pos + AbsolutePosition.height);
								return true;
							}
						break;
						case KEY_BACKSPACE: {
							if(disabled)
								return true;
							int len = search.length;
							int curs = len;
							int prevPos = len;
							int tmp = 0;
							if(prevPos == 0)
								return true;
							u8prev(search, prevPos, tmp);
							string newText;
							if(prevPos > 0)
								newText += search.substr(0, prevPos);
							if(len - curs > 0)
								newText += search.substr(curs, len - curs);
							search = newText;
							doSearch();
							return true;
						}
					}
				}
				else if(event.type == KET_Key_Up) {
					switch(event.key) {
						case KEY_UP:
							return true;
						case KEY_DOWN:
							return true;
						case KEY_ENTER:
							emitChange();
							emitConfirmed();
							return true;
						case KEY_PAGEUP:
							if(selected > 0)
								return true;
						break;
						case KEY_PAGEDOWN:
							if(selected >= 0)
								return true;
						break;
						case KEY_BACKSPACE:
							return true;
					}
				}
				else if(event.type == KET_Key_Typed) {
					if(disabled)
						return true;
					if(searchTime < frameTime - 0.5)
						search = "";

					u8append(search, event.key);
					doSearch();
					return true;
				}
			}
			return scroll.onKeyEvent(event, scroll);
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		if(skin is null)
			return;

		const Font@ font = skin.getFont(TextFont);

		if(itemHeight == -1)
			lineHeight = font.getLineHeight() + vertPadding * 2;
		else
			lineHeight = itemHeight;
		scroll.scroll = lineHeight * 2;

		scroll.page = AbsolutePosition.height;
		scroll.bar = scroll.page;
		scroll.end = lineHeight * items.length();
		scroll.pos = max(0.0, min(scroll.end - scroll.page, scroll.pos));
		scroll.visible = scroll.end > scroll.page;
		scroll.updateAbsolutePosition();
	}

	vec2i get_desiredSize() const {
		return vec2i(size.width, lineHeight * items.length);
	}

	int getOffsetItem(const vec2i& offset) {
		if(offset.x < 0 || offset.x > AbsolutePosition.width)
			return -1;

		int item = floor(double(offset.y + scroll.pos) / double(lineHeight));

		if(item < 0 || item >= int(items.length()))
			return -1;
		else
			return item;
	}

	vec2i getItemOffset(int item) {
		if(item < 0 || item >= int(items.length))
			return vec2i();
		return vec2i(0, (item * lineHeight) - int(scroll.pos));
	}

	void draw() {
		//Draw element background
		uint flags = SF_Normal;
		if(ElementHovered)
			flags |= SF_Hovered;
		if(ElementFocused)
			flags |= SF_Focused;
		if(disabled)
			flags |= SF_Disabled;
		skin.draw(style, SF_Normal, AbsoluteClipRect);

		//Draw items
		int itemWidth = AbsolutePosition.width;

		if(scroll.visible)
			itemWidth -= 20;

		recti itemPos = recti_area(
			AbsolutePosition.topLeft - vec2i(0, scroll.pos),
			vec2i(itemWidth, lineHeight));

		for(uint i = 0, cnt = items.length(); i < cnt; ++i) {
			//Don't display completely invisible items
			if(itemPos.botRight.y < AbsolutePosition.topLeft.y) {
				itemPos += vec2i(0, lineHeight);
				continue;
			}

			if(itemPos.topLeft.y > AbsolutePosition.botRight.y)
				break;

			//Figure correct style to use
			uint itFlags = SF_Normal;
			if(items[i].isSelectable) {
				if(int(i) == hovered && !disabled) {
					if(ElementHovered)
						itFlags |= SF_Hovered;
					if(ElementFocused)
						itFlags |= SF_Focused;
				}
				if(Multiple) {
					if(SelectedItems[i])
						itFlags |= SF_Active;
				}
				else if(int(i) == selected) {
					itFlags |= SF_Active;
				}
			}

			//Draw item
			if(itemStyle != SS_NULL)
				skin.draw(itemStyle, itFlags, itemPos);
			items[i].draw(this, itFlags, itemPos);
			itemPos += vec2i(0, lineHeight);
		}

		BaseGuiElement::draw();
	}
};
