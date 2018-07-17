import elements.BaseGuiElement;
import elements.GuiListbox;
import elements.GuiButton;

export DropdownAlignment, GuiDropdown;
export from elements.GuiListbox;

enum DropdownAlignment {
	DA_Equal,
	DA_Left,
	DA_Right,
	DA_Center
};

class GuiDropdown : BaseGuiElement, IGuiCallback {
	GuiListbox@ list;
	GuiButton@ arrow;
	int maxItemWidth;
	FontType TextFont;
	bool Hovered;
	bool Focused;
	bool Disabled;

	DropdownAlignment DropAlign;
	bool sizeDown;
	int maxHeight;
	int prevSelected;
	int horizPadding = 6;
	int vertPadding = 3;

	bool showOnHover = false;
	GuiListElement@ showElement;

	SkinStyle style;
	SkinStyle arrowStyle;

	GuiDropdown(IGuiElement@ ParentElement, const recti& Rectangle) {
		_GuiDropdown();
		super(ParentElement, Rectangle);
		@arrow.parent = this;
	}

	GuiDropdown(IGuiElement@ ParentElement, Alignment@ Align) {
		_GuiDropdown();
		super(ParentElement, Align);
		@arrow.parent = this;
	}

	void _GuiDropdown() {
		@list = GuiListbox(null, recti());
		list.required = true;
		list.visible = false;
		list.style = SS_DropdownList;
		list.itemStyle = SS_DropdownListItem;
		@list.callback = this;

		style = SS_Dropdown;

		maxItemWidth = 0;
		maxHeight = 220;
		DropAlign = DA_Equal;
		Hovered = false;
		prevSelected = -1;
		sizeDown = false;
		Focused = false;
		Disabled = false;

		TextFont = FT_Normal;

		@arrow = GuiButton(null, Alignment(Right-20, Top, Right, Bottom));
		arrow.style = SS_DropdownArrow;
	}

	void set_itemHeight(int it) {
		list.itemHeight = it;
	}

	void set_disabled(bool dis) {
		Disabled = dis;
		list.disabled = dis;
	}

	bool get_disabled() {
		return Disabled;
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void addItem(const string& item) {
		list.addItem(item);
		updateItemLength();
	}

	void addItem(GuiListElement@ elem) {
		list.addItem(elem);
		updateItemLength();
	}

	void setItem(uint index, const string& item) {
		list.setItem(index, item);
		updateItemLength();
	}

	void setItem(uint index, GuiListElement@ elem) {
		list.setItem(index, elem);
		updateItemLength();
	}

	void removeItem(uint index) {
		list.removeItem(index);
		updateItemLength();
	}

	void removeItemsFrom(uint index) {
		list.removeItemsFrom(index);
		updateItemLength();
	}

	void clearItems() {
		list.clearItems();
		updateItemLength();
	}

	string getItem(uint index) {
		return list.getItem(index);
	}

	GuiListElement@ getItemElement(uint index) {
		return list.getItemElement(index);
	}

	int get_selected() {
		return list.selected;
	}

	void set_selected(int sel) {
		list.selected = sel;
	}

	void set_font(FontType type) {
		if(TextFont == type)
			return;
		TextFont = type;
		list.font = type;
		updateItemLength();
	}

	uint get_itemCount() {
		return list.itemCount;
	}

	FontType get_font() const {
		return TextFont;
	}

	void set_dropAlign(DropdownAlignment align) {
		if(DropAlign == align)
			return;
		DropAlign = align;
		updateAbsolutePosition();
	}

	DropdownAlignment get_dropAlign() const {
		return DropAlign;
	}

	void toggleList() {
		list.visible = !list.visible;
		if(list.visible) {
			prevSelected = selected;
			list.selected = -1;
			list.required = false;
			list.bringToFront();
			updateAbsolutePosition();
		}
		else {
			if(list.selected == -1 && prevSelected != -1) {
				list.selected = prevSelected;
				list.required = true;
			}
			else {
				emitChange();
			}
		}
	}

	GuiListElement@ get_selectedItem() {
		return list.selectedItem;
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
					if(event.other !is list && list.visible)
						toggleList();
				break;
			}
		}
		else if(event.caller is list) {
			switch(event.type) {
				case GUI_Changed:
					if(list.searchTime < frameTime - 0.5) {
						list.visible = false;
						prevSelected = list.selected;
					}
					emitChange();
				break;
				case GUI_Focus_Lost:
					if(event.other !is this && list.visible) {
						Focused = false;
						toggleList();
					}
				break;
			}
		}
		else if(event.caller is arrow) {
			switch(event.type) {
				case GUI_Clicked:
					toggleList();
					return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Button_Down:
					return true;
				case MET_Button_Up:
					if(!showOnHover || !disabled)
						toggleList();
					else
						emitClicked();
					return true;
				case MET_Scrolled:
					if(!list.visible && !Disabled && !showOnHover) {
						if(event.y > 0) {
							if(list.selected > 0) {
								list.selected -= 1;
								emitChange();
							}
						}
						else {
							if(list.selected < int(list.itemCount) - 1) {
								list.selected += 1;
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

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(Focused && source is this) {
			if(event.key == KEY_BACKSPACE) {
				return list.onKeyEvent(event, list);
			}
			else if(event.type== KET_Key_Down) {
				switch(event.key) {
					case KEY_ENTER:
						return true;
				}
			}
			else if(event.type == KET_Key_Up) {
				switch(event.key) {
					case KEY_ENTER:
						toggleList();
					return true;
					case KEY_DOWN:
						if(Disabled)
							return true;
						if(list.selected == -1)
							list.selected = 0;
						else
							list.nextItem();
					return true;
					case KEY_UP:
						if(Disabled)
							return true;
						if(list.selected == -1)
							list.selected = list.itemCount - 1;
						else
							list.prevItem();
					return true;
				}
			}
			else if(event.type == KET_Key_Typed) {
				return list.onKeyEvent(event, list);
			}
		}
		else if(source is list) {
			switch(event.key) {
				case KEY_ENTER:
					toggleList();
				return true;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void updateItemLength() {
		const Font@ font = skin.getFont(TextFont);
		maxItemWidth = 0;

		for(uint i = 0, cnt = list.itemCount; i < cnt; ++i) {
			int length = font.getDimension(list.getItem(i)).width;

			if(length > maxItemWidth)
				maxItemWidth = length;
		}

		maxItemWidth += 20 + list.horizPadding * 2;
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		arrow.alignment.left.pixels = size.height;
		BaseGuiElement::updateAbsolutePosition();

		int height = min(maxHeight, list.lineHeight * list.itemCount);
		vec2i pos, size;

		switch(DropAlign) {
			case DA_Equal:
				pos = vec2i(0, AbsolutePosition.height);
				size = vec2i(AbsolutePosition.width, height);
			break;
			case DA_Left: {
				int width = min(maxItemWidth, screenSize.width - AbsolutePosition.topLeft.x);

				if(!sizeDown)
					width = max(AbsolutePosition.width, width);

				pos = vec2i(0, AbsolutePosition.height);
				size = vec2i(width, height);
			} break;
			case DA_Right: {
				int width = min(maxItemWidth, AbsolutePosition.botRight.x);

				if(!sizeDown)
					width = max(AbsolutePosition.width, width);

				pos = vec2i(AbsolutePosition.width - width, AbsolutePosition.height);
				size = vec2i(width, height);
			} break;
			case DA_Center: {
				int width = min(maxItemWidth, AbsolutePosition.center.x * 2);
				width = min(width, (screenSize.width - AbsolutePosition.center.x) * 2);

				if(!sizeDown)
					width = max(AbsolutePosition.width, width);

				pos = vec2i((AbsolutePosition.width - width) / 2, AbsolutePosition.height);
				size = vec2i(width, height);
			} break;
		}

		list.position = vec2i(
				clamp(pos.x + AbsolutePosition.topLeft.x, 0, screenSize.width-size.x),
				clamp(pos.y + AbsolutePosition.topLeft.y, 0, screenSize.height-size.y));
		list.size = size;
		list.updateAbsolutePosition();
	}

	void move(const vec2i& moveBy) {
		list.abs_move(moveBy);
		BaseGuiElement::move(moveBy);
	}

	void abs_move(const vec2i& moveBy) {
		list.abs_move(moveBy);
		BaseGuiElement::abs_move(moveBy);
	}

	void draw() {
		const Font@ font = skin.getFont(TextFont);
		int sel = list.visible ? prevSelected : selected;

		uint flags = SF_Normal;
		if(Hovered)
			flags |= SF_Hovered;
		if(list.visible)
			flags |= SF_Active;
		if(Disabled)
			flags |= SF_Disabled;

		if(!showOnHover || ((Hovered || list.visible) && !Disabled)) {
			arrow.visible = true;
			skin.draw(style, flags, AbsolutePosition);
		}
		else {
			arrow.visible = false;
		}

		if(showElement !is null) {
			showElement.draw(list, SF_Normal, AbsolutePosition.padded(horizPadding, vertPadding));
		}
		else if(sel >= 0) {
			auto@ elem = list.getItemElement(sel);
			if(elem !is null)
				elem.draw(list, SF_Normal, AbsolutePosition.padded(horizPadding, vertPadding));
		}

		BaseGuiElement::draw();
	}
};
