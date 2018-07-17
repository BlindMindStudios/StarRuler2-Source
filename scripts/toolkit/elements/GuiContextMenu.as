import elements.BaseGuiElement;
import elements.GuiListbox;
import elements.GuiMarkupText;
from gui import clearTooltip;

export GuiContextOption, GuiSubMenu, GuiContextMenu;
export GuiMarkupContextOption;

const uint CTX_LEFT_OFF = 12;
const uint CTX_RIGHT_OFF = 12;

class GuiContextOption : GuiListElement {
	Sprite icon;
	Color color;
	string text;
	int height = -1;
	int value = 0;
	bool selectable = true;
	bool separator = false;

	GuiContextOption() {
	}

	GuiContextOption(const string& txt, int val = 0) {
		text = txt;
		value = val;
	}

	void set(const string& txt) {
		text = txt;
		height = -1;
	}

	string get() {
		return text;
	}

	bool get_isSelectable() {
		return selectable;
	}

	void call(GuiContextMenu@ menu) {
	}

	int getWidth(GuiListbox@ ele) {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int w = font.getDimension(text).x + ele.horizPadding * 2;
		if(height == -1)
			height = font.getDimension(text).height;
		if(icon.valid) {
			vec2i iconSize = icon.size;
			if(iconSize.y > height + 8) {
				iconSize.x = double(height + 8) / double(iconSize.y) * double(iconSize.x);
				iconSize.y = height + 8;
			}
			w += iconSize.x + 8;
		}
		return w;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		
		if(height == -1)
			height = font.getDimension(text).height;
		
		vec2i textOffset(ele.horizPadding, (ele.lineHeight - height) / 2);
		
		if(icon.valid) {
			vec2i iconSize = icon.size;
			if(iconSize.y > height + 8) {
				iconSize.x = double(height + 8) / double(iconSize.y) * double(iconSize.x);
				iconSize.y = height + 8;
			}
			vec2i iconOffset(ele.horizPadding, (ele.lineHeight - iconSize.height) / 2);
			icon.draw(recti_area(absPos.topLeft + iconOffset, iconSize));
			textOffset.x += iconSize.width + 8;
		}
		font.draw(absPos.topLeft + textOffset, text, color);
		if(separator)
			drawRectangle(
				recti_area(absPos.topLeft + vec2i(6, absPos.size.height / 2 - 1),
				vec2i(absPos.size.width - 12, 2)),
				Color(0x88888888));
	}
};

class GuiMarkupContextOption : GuiContextOption {
	MarkupRenderer renderer;

	GuiMarkupContextOption() {
	}

	GuiMarkupContextOption(const string& txt, int val = 0) {
		set(txt);
		value = val;
	}

	void set(const string& txt) {
		text = txt;
		height = -1;

		renderer.parseTree(txt);
	}

	int getWidth(GuiListbox@ ele) {
		renderer.update(ele.skin, recti_area(0,0,3000,100));
		return renderer.width + 24;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		
		if(height == -1)
			height = ele.lineHeight;
		vec2i textOffset(ele.horizPadding, (ele.lineHeight - height) / 2);
		
		if(icon.valid) {
			vec2i iconSize = icon.size;
			if(iconSize.y > height + 8) {
				iconSize.x = double(height + 8) / double(iconSize.y) * double(iconSize.x);
				iconSize.y = height + 8;
			}
			vec2i iconOffset(ele.horizPadding, (ele.lineHeight - iconSize.height) / 2);
			icon.draw(recti_area(absPos.topLeft + iconOffset, iconSize));
			textOffset.x += iconSize.width + 8;
		}
		renderer.draw(ele.skin, absPos.padded(textOffset.x, textOffset.y, 4, 4));
	}
};

class GuiSubMenu : GuiContextOption {
	GuiContextMenu@ menu;

	GuiSubMenu(GuiContextMenu@ parent, const string& txt) {
		@menu = GuiContextMenu(parent);
		text = txt;
	}

	void set(const string& txt) {
		text = txt;
	}

	string get() {
		return text;
	}

	void call(GuiContextMenu@ m) {
		menu.open();
	}
};

class GuiContextMenu : BaseGuiElement {
	GuiListbox@ list;
	GuiContextMenu@ parentMenu;
	vec2i origin;
	bool flexWidth = true;

	GuiContextMenu(const vec2i& orig, int width = 200, bool Flex = true) {
		origin = orig;
		flexWidth = Flex;
		super(null, Alignment_Fill());
		@list = GuiListbox(this, recti_area(orig, vec2i(width, 0)));
		list.style = SS_ContextMenu;
		list.itemStyle = SS_ContextMenuItem;
		list.itemHeight = 28;
		setGuiAbsorb(this);
		clearTooltip();
	}

	GuiContextMenu(GuiContextMenu@ parent) {
		super(null, Alignment_Fill());
		@parentMenu = parent;
		@list = GuiListbox(parent.top, recti());
		list.style = SS_ContextMenu;
		list.itemStyle = SS_ContextMenuItem;
		list.itemHeight = parent.list.itemHeight;
		visible = false;
	}

	GuiContextMenu@ get_top() {
		GuiContextMenu@ p = this;
		while(p.parentMenu !is null)
			@p = p.parentMenu;
		return p;
	}

	void open() {
		visible = true;
		int hov = parentMenu.list.hovered;
		vec2i offset = parentMenu.list.getItemOffset(hov);

		list.size = vec2i(parentMenu.list.size.width, 0);
		list.position = parentMenu.position + offset + vec2i(parentMenu.list.size.width);
	}

	void set_width(int width) {
		list.size = vec2i(width, list.size.height);
	}

	void clear() {
		list.clearItems();
	}

	void addOption(const string& text, int value = 0) {
		list.addItem(GuiContextOption(text, value));
	}

	void addOption(GuiContextOption@ opt) {
		list.addItem(opt);
	}

	void addOption(GuiContextOption@ opt, const string& text, int value = 0) {
		opt.text = text;
		opt.value = value;
		opt.set(text);
		list.addItem(opt);
	}

	void addOption(GuiContextOption@ opt, const string& text, const Sprite& sprt, int value = 0) {
		opt.text = text;
		opt.value = value;
		opt.icon = sprt;
		opt.set(text);
		list.addItem(opt);
	}

	void finalize() {
		if(list.itemCount == 0)
			remove();
		else
			updateAbsolutePosition();
	}

	void addLabel(const string& text) {
		GuiContextOption opt(text);
		opt.selectable = false;
		list.addItem(opt);
	}

	void addSeparator() {
		GuiContextOption opt;
		opt.selectable = false;
		opt.separator = true;
		list.addItem(opt);
	}

	GuiContextMenu@ addSubMenu(const string& text) {
		GuiSubMenu sub(this, text);
		addOption(sub);
		return sub.menu;
	}

	void remove() {
		if(parentMenu !is null)
			parentMenu.remove();
		list.remove();
		BaseGuiElement::remove();
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up && source is this) {
			remove();
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_ESC)
					return true;
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					remove();
					return true;
				}
			break;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Changed:
				if(evt.caller is list) {
					int sel = list.selected;
					if(sel != -1) {
						GuiContextOption@ opt = cast<GuiContextOption>(list.getItemElement(sel));
						opt.call(this);
						emitClicked();
					}

					remove();
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void set_itemHeight(int value) {
		list.itemHeight = value;
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		//Calculate correct width
		int width = list.size.width;
		int wantWidth = width;
		if(flexWidth) {
			for(uint i = 0, cnt = list.itemCount; i < cnt; ++i) {
				int w = cast<GuiContextOption>(list.getItemElement(i)).getWidth(list);
				if(w > wantWidth)
					wantWidth = w;
			}
		}

		//Calculate correct height
		int height = list.size.height;
		int wantHeight = list.itemCount * list.lineHeight;
		if(wantHeight > parent.size.height - 40) {
			wantWidth += 20;
			wantHeight = parent.size.height - 40;
		}
		if(height == wantHeight && width == wantWidth)
			return;

		//Resize it to the correct height
		list.size = vec2i(wantWidth, wantHeight);
		width = wantWidth;
		height = wantHeight;

		//Position on the horizontal axis
		vec2i pos;
		vec2i psize = size;
		if(origin.x + CTX_RIGHT_OFF + width > psize.width &&
				origin.x - width - CTX_LEFT_OFF > 0)
			pos.x = origin.x - width - CTX_LEFT_OFF;
		else
			pos.x = origin.x + CTX_RIGHT_OFF;

		//Position on the vertical axis
		if(origin.y + height > psize.y) {
			if(origin.y - height > 0) {
				pos.y = origin.y - height;
			}
			else {
				pos.y = psize.y - height;
			}
		}
		else {
			pos.y = origin.y;
		}

		list.position = pos;
	}
};
