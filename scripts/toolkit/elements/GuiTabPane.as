import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiPanel;

export GuiTabPane;

class GuiTabPane : BaseGuiElement {
	GuiButton@[] TabButtons;
	GuiPanel@[] TabPanels;
	SkinStyle TabStyle = SS_Tab;
	uint TabHeight = 22;
	uint Selected = 0;
	bool Fill = true;

	GuiTabPane(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	uint addTab(const string& name) {
		uint num = TabButtons.length();

		GuiButton@ btn = GuiButton(this, recti(), name);
		btn.style = TabStyle;
		btn.toggleButton = true;

		GuiPanel@ pnl = GuiPanel(this, recti());
		@pnl.alignment = Alignment(Left, Top+TabHeight, Right, Bottom);

		pnl.visible = num == Selected;
		btn.pressed = pnl.visible;

		TabButtons.insertLast(btn);
		TabPanels.insertLast(pnl);
		alignTabs();
		return num;
	}

	void setTabName(uint num, const string& name) {
		if(num >= TabButtons.length())
			throw("Tab index out of bounds.");
		TabButtons[num].text = name;
	}

	void removeTab(uint num) {
		if(num >= TabPanels.length())
			throw("Tab index out of bounds.");
		TabButtons[num].remove();
		TabPanels[num].remove();
		TabButtons.removeAt(num);
		TabPanels.removeAt(num);
		alignTabs();

		if(num == Selected)
			--num;
	}

	GuiPanel@ getTab(uint num) {
		if(num >= TabPanels.length())
			throw("Tab index out of bounds.");
		return TabPanels[num];
	}

	string getTabName(uint num) {
		if(num >= TabButtons.length())
			throw("Tab index out of bounds.");
		return TabButtons[num].text;
	}

	uint get_selected() {
		return Selected;
	}

	void set_selected(uint num) {
		if(Selected == num)
			return;
		if(Selected <= TabButtons.length()) {
			TabButtons[Selected].pressed = false;
			TabPanels[Selected].visible = false;
		}
		if(num <= TabButtons.length()) {
			TabButtons[num].pressed = true;
			TabPanels[num].visible = true;
		}
		Selected = num;
	}

	void set_tabHeight(int height) {
		TabHeight = height;
		alignTabs();
		alignPanels();
	}

	void set_tabStyle(SkinStyle style) {
		TabStyle = style;
		for(uint i = 0, cnt = TabButtons.length(); i < cnt; ++i)
			TabButtons[i].style = TabStyle;
	}

	void alignTabs() {
		//Make sure the tab buttons are positioned right
		uint w = 0;
		uint tabCnt = TabButtons.length();
		if(tabCnt == 0)
			return;

		uint size = absolutePosition.width / tabCnt;
		for(uint i = 0, cnt = TabButtons.length(); i < cnt; ++i) {
			GuiButton@ btn = TabButtons[i];
			if(!Fill)
				size = max(160, btn.textSize.width + 8);

			btn.position = vec2i(w, 0);
			btn.size = vec2i(size, TabHeight);

			w += size;
		}
	}

	void updateAbsolutePosition() {
		vec2i prevSize = absolutePosition.size;
		BaseGuiElement::updateAbsolutePosition();

		if(absolutePosition.size.width != prevSize.width)
			alignTabs();
	}

	void alignPanels() {
		//Align the panels correctly to the parent
		for(uint i = 0, cnt = TabPanels.length(); i < cnt; ++i) {
			GuiPanel@ pnl = TabPanels[i];
			pnl.alignment.set(
				AS_Left, 0.f, 0,
				AS_Top, 0.f, TabHeight,
				AS_Right, 0.f, 0,
				AS_Bottom, 0.f, 0);
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			for(uint i = 0, cnt = TabButtons.length(); i < cnt; ++i) {
				if(TabButtons[i] is cast<GuiButton@>(event.caller)) {
					selected = i;
					return true;
				}
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		BaseGuiElement::draw();
	}
};
