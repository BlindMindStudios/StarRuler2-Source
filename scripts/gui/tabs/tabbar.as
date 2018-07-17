#priority render 100
#priority init 5
import tabs.Tab;
import elements.GuiButton;
import version;
from input import lastCamera;

import BaseGuiElement@ createGlobalBar() from "tabs.GlobalBar";

import Tab@ createHomeTab() from "tabs.HomeTab";
import bool isHomeTab(Tab@) from "tabs.HomeTab";
import Tab@ createDiplomacyTab() from "tabs.DiplomacyTab";
import Tab@ createResearchTab() from "tabs.ResearchTab";
import Tab@ createGalaxyTab() from "tabs.GalaxyTab";
import Tab@ createPlanetsTab() from "tabs.PlanetsTab";
import Tab@ createWikiTab() from "tabs.WikiTab";
import Tab@ createCommunityHome() from "community.Home";
import Tab@ createGalaxyTab(Empire@) from "tabs.GalaxyTab";
import Tab@ createDesignOverviewTab() from "tabs.DesignOverviewTab";
import Tab@ createAttitudesTab() from "tabs.AttitudesTab";
import IGuiElement@ getGoDialog() from "navigation.go";
import void toggleGoDialog() from "navigation.go";

const int TAB_HOME_OFFSET = 84;
const int TAB_MAX_WIDTH = 186;
const int BUTTON_NEW_WIDTH = 12;
const int TAB_MIN_WIDTH = 45;
const int TAB_HEIGHT = 26;
const int TAB_SPACING = 8;
const int TAB_SCRUNCH = -18;
const int GLOBAL_BAR_HEIGHT = 50;
const vec2i TAB_ICON_OFFSET(16, 2);
const vec2i TAB_ICON_SIZE(24, 24);
const vec2i TAB_CLOSE_OFFSET(14, 7);
const vec2i TAB_TEXT_OFFSET(44, 5);
const vec2i TAB_PADDING(4, 4);
const string ellipsis = "...";
const uint MAX_STORED_TABS = 8;
const bool ALWAYS_SCRUNCH_TABS = true;
const Color TAB_FLASH_COLOR(0xffffffff);
const double TAB_FLASH_PERIOD = 1.0;

GuiTabBar@ tabBar;
BaseGuiElement@ globalBar;
Tab@[] tabs;
Tab@[] closedTabs;
Tab@ activeTab;

//Tab management public interface
Tab@ newTab() {
	Tab@ tab = createHomeTab();
	newTab(tab);
	return tab;
}

Tab@ get_ActiveTab() {
	return activeTab;
}

uint get_tabCount() {
	return tabs.length;
}

Tab@ get_Tabs(uint i) {
	return tabs[i];
}

Tab@ findTab(int cat) {
	int cnt = tabs.length;
	int index = tabs.find(activeTab);
	int find = max(index, cnt - index);

	for(int i = 0; i <= find; ++i) {
		if(index + i < cnt) {
			if(tabs[index + i].category == cat)
				return tabs[index + i];
		}
		if(index - i >= 0) {
			if(tabs[index - i].category == cat)
				return tabs[index - i];
		}
	}
	return null;
}

Tab@ findTab(IGuiElement@ elem) {
	while(elem !is null) {
		if(cast<Tab>(elem) !is null)
			return cast<Tab>(elem);
		@elem = elem.parent;
	}
	return null;
}

void prepareTab(Tab@ tab) {
	if(tab.initialized)
		return;
	@tab.alignment = Alignment(Left, Top+TAB_HEIGHT + 2 + GLOBAL_BAR_HEIGHT, Right, Bottom);
	tab.updateAbsolutePosition();
	tab.init();
	tab.sendToBack();
	tab.initialized = true;
}

Tab@ newTab(Tab@ tab) {
	prepareTab(tab);
	tabs.insertLast(tab);
	tabBar.refresh();
	return tab;
}

Tab@ newTab(Tab@ from, Tab@ tab) {
	prepareTab(tab);
	int index = tabs.find(from);
	if(index >= 0)
		tabs.insertAt(index+1, tab);
	else
		tabs.insertLast(tab);
	tabBar.refresh();
	return tab;
}

void switchToTab(Tab@ tab) {
	if(tab is null)
		return;
	if(tab is activeTab)
		return;

	Tab@ prev = activeTab;
	@activeTab = tab;

	if(prev !is null)
		prev.hide();
	tab.show();
}

void switchToTab(int pos) {
	int index = tabs.find(activeTab);
	index = (index + pos) % tabs.length;

	while(index < 0)
		index += tabs.length;

	switchToTab(tabs[index]);
}

bool switchToTab(TabCategory cat) {
	Tab@ tab = findTab(cat);
	if(tab !is null) {
		switchToTab(tab);
		return true;
	}
	return false;
}

void closeTab() {
	closeTab(activeTab);
}

Tab@ reopenTab() {
	//Switch back to the previous tab from the final home tab
	if(tabs.length == 1 && isHomeTab(tabs[0]) && tabs[0].previous !is null) {
		browseTab(tabs[0], tabs[0].previous, false);
		return null;
	}

	//Check if there are any tabs left to reopen
	if(closedTabs.length == 0)
		return null;

	//Set the tabs to reopen
	Tab@ tab = closedTabs[0];
	if(tab !is null)
		tab.reopen();

	//Create the new tab
	@tab = closedTabs[0];
	newTab(tab);
	closedTabs.removeAt(0);
	return tab;
}

void closeTab(Tab@ tab) {
	//Don't close locked tabs
	if(tab.locked)
		return;

	//Check if it is in the list at all
	int index = tabs.find(tab);
	if(index >= 0) {
		//Never close the last tab
		if(tabs.length == 1) {
			browseTab(activeTab, createHomeTab(), false);
			return;
		}

		//Remove from the list
		tabs.removeAt(index);

		//Hide it if it is active
		if(activeTab is tab)
			switchToTab(tabs[max(0, index - 1)]);
	}

	//Store the tab for reopening
	if(tab !is null && (!isHomeTab(tab) || tab.previous !is null)) {
		closedTabs.insertAt(0, tab);
		if(closedTabs.length >=	MAX_STORED_TABS) {
			for(uint i = MAX_STORED_TABS; i < closedTabs.length; ++i)
				closedTabs[i].remove();
			closedTabs.length = MAX_STORED_TABS;
		}	
	}
	
	//Remove it and all previous tabs
	Tab@ first = tab;
	while(tab !is null) {
		//Close the tab
		tab.close();

		//Go to the previous tab
		@tab = tab.previous;
		if(tab is first)
			break;
	}

	//Refresh stuff
	tabBar.refresh();
}

void browseTab(Tab@ to, bool remember = false) {
	browseTab(activeTab, to, remember);
}

void browseTab(Tab@ inside, Tab@ to, bool remember = false) {
	//Make sure our new tab is initialized
	prepareTab(to);

	if(inside.locked && !to.locked)
		to.locked = true;

	//Set it in the list
	int index = tabs.find(inside);
	if(index >= 0)
		@tabs[index] = to;

	//Do showing and hiding
	if(inside is activeTab)
		switchToTab(to);

	//New tab knows where it came from
	if(remember) {
		@to.previous = inside;
	}
	else {
		Tab@ first = inside;
		while(inside !is null) {
			inside.close();
			inside.remove();
			@inside = inside.previous;
			if(inside !is null && inside.parent is null)
				@inside = null;
			if(inside is first)
				break;
		}
	}

	//Refresh stuff
	tabBar.refresh();
}

void browseTab(TabCategory inside, Tab@ to, bool remember = false, bool createNew = true) {
	Tab@ tab = findTab(inside);
	if(tab is null) {
		if(createNew) {
			newTab(to);
			switchToTab(to);
			return;
		}
		else {
			@tab = activeTab;
		}
	}

	browseTab(tab, to, remember);
	switchToTab(to);
}

void popTab(Tab@ top) {
	if(top.previous is null) {
		closeTab(top);
		return;
	}

	//Set it in the list
	int index = tabs.find(top);
	if(index >= 0)
		@tabs[index] = top.previous;

	//Do showing and hiding
	if(top is activeTab)
		switchToTab(top.previous);

	//New tab knows where it came from
	top.close();
	top.remove();

	//Refresh stuff
	tabBar.refresh();
}

//Tab selection gui elements
class GuiTabBar : BaseGuiElement {
	GuiTab@[] tabs;
	GuiButton@ homeButton;
	GuiButton@ goButton;
	GuiButton@ newButton;
	bool leftGo = false;

	GuiTabBar() {
		super(null, Alignment(Left, Top, Right, Top+TAB_HEIGHT + 3));
			
		@homeButton = GuiButton(this, recti(0, 0, 30, 19));
		homeButton.navigable = false;
		homeButton.style = SS_HomeIcon;
		homeButton.position = vec2i(3, 4);
			
		@goButton = GuiButton(this, recti(0, 0, 30, 19));
		goButton.navigable = false;
		goButton.style = SS_GoIcon;
		goButton.position = vec2i(35, 4);
			
		@newButton = GuiButton(this, recti(0, 0, 30 + BUTTON_NEW_WIDTH, 19));
		newButton.navigable = false;
		newButton.style = SS_GameTabNew;

		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		int w = size.width;
		BaseGuiElement::updateAbsolutePosition();
		if(size.width != w)
			refresh();
	}

	void refresh() {
		uint cnt = ::tabs.length;
		uint oldcnt = tabs.length;

		//Remove old tabs
		for(uint i = cnt; i < oldcnt; ++i)
			tabs[i].remove();
		tabs.length = cnt;

		//Create new tabs
		for(uint i = oldcnt; i < cnt; ++i) {
			@tabs[i] = GuiTab(this);
			tabs[i].sendToBack();
		}

		//Refresh tabs
		int x = TAB_HOME_OFFSET;
		int cat = TC_Invalid;

		//Calculate the total used spacing
		int totalSpacing = 0;
		cat = TC_Invalid;
		for(uint i = 0; i < cnt; ++i) {
			//Scrunch tabs in the same category
			int newCat = ::tabs[i].category;
			if(newCat == cat || ALWAYS_SCRUNCH_TABS)
				totalSpacing += TAB_SCRUNCH;
			else
				totalSpacing += TAB_SPACING;
			cat = newCat;
		}

		//Fit the tab width
		int w = TAB_MAX_WIDTH;
		bool overflow = false;
		int avail = size.width - TAB_HOME_OFFSET - newButton.size.width - TAB_SPACING - 4;
		if(cnt * w + totalSpacing > avail) {
			w = max(TAB_MIN_WIDTH, (avail - totalSpacing) / cnt);
			overflow = true;
		}

		//Position the actual tabs
		cat = TC_Invalid;
		for(uint i = 0; i < cnt; ++i) {
			//Scrunch tabs in the same category
			int newCat = ::tabs[i].category;
			if(newCat == cat || ALWAYS_SCRUNCH_TABS)
				x += TAB_SCRUNCH;
			else
				x += TAB_SPACING;
			cat = newCat;

			//Position the tab
			tabs[i].setTab(::tabs[i]);
			tabs[i].position = vec2i(x, 0);
			tabs[i].size = vec2i(w, TAB_HEIGHT);
			x += w;
		}

		//Set new button
		if(overflow)
			newButton.position = vec2i(size.width - newButton.size.width - 4, 4);
		else
			newButton.position = vec2i(x + TAB_SPACING, 4);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			if(event.type == MET_Button_Up) {
				if(event.button == 2) {
					switchToTab(newTab());
					return true;
				}
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is newButton) {
			if(event.type == GUI_Clicked) {
				switchToTab(newTab());
				return true;
			}
		}
		else if(event.caller is homeButton) {
			if(event.type == GUI_Clicked) {
				bool isHome = isHomeTab(activeTab);
				if(!isHome || activeTab.previous is null) {
					browseTab(activeTab, createHomeTab(), true);
				}
				else {
					popTab(activeTab);
				}
				return true;
			}
		}
		else if(event.caller is goButton) {
			if(event.type == GUI_Clicked) {
				if(leftGo)
					leftGo = false;
				else
					toggleGoDialog();
				return true;
			}
			else if(event.type == GUI_Focused) {
				if(event.other !is null && event.other.isChildOf(getGoDialog())) {
					leftGo = true;
					return false;
				}
			}
			else if(event.type == GUI_Focus_Lost) {
				leftGo = false;
				return false;
			}
		}
		
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		//Draw the tab bar background
		skin.draw(SS_GameTabBar, SF_Normal, AbsolutePosition);

		//Draw build version
		//skin.getFont(FT_Normal).draw(pos=AbsolutePosition.padded(8, 0, 8, 3),
		//		text=SCRIPT_VERSION, horizAlign=1.0, color=Color(0xaaaaaaff));
			
		//Find the active tab to draw on top
		GuiTab@ active = null;
		GuiTab@ dragging = null;
		uint cnt = tabs.length;
		for(uint i = 0; i < cnt; ++i) {
			if(tabs[i].Dragging) {
				@dragging = tabs[i];
				tabs[i].Visible = false;
			}
			else if(tabs[i].tab is activeTab) {
				@active = tabs[i];
				tabs[i].Visible = false;
			}
		}

		BaseGuiElement::draw();
		
		//Draw the separator lines
		drawRectangle(recti_area(
			AbsolutePosition.topLeft + vec2i(0,24),
			vec2i(size.width, 1)), Color(0x202020ff));
		
		drawRectangle(recti_area(
			AbsolutePosition.topLeft + vec2i(0, 25),
			vec2i(size.width, 2)), activeTab.seperatorColor);

		drawRectangle(recti_area(
			AbsolutePosition.topLeft + vec2i(0,27),
			vec2i(size.width, 1)), Color(0x202020ff));
			
		//Draw the active tab
		if(active !is null) {
			active.Visible = true;
			active.draw();
		}

		//Draw the dragging tab
		if(dragging !is null) {
			dragging.Visible = true;
			dragging.draw();
		}
	}
};

class GuiTab : BaseGuiElement {
	GuiTabBar@ bar;
	GuiButton@ closeButton;
	Tab@ tab;
	bool Hovered;
	bool Focused;
	bool Pressed;
	bool LeftHeld = false;
	bool Dragging;
	vec2i dragStart;

	GuiTab(GuiTabBar@ Bar) {
		@bar = Bar;
		Hovered = false;
		Focused = false;
		Pressed = false;
		Dragging = false;

		super(bar, recti_area(0, 0, TAB_MAX_WIDTH, TAB_HEIGHT));

		vec2i size = skin.getSize(SS_GameTabClose, SF_Normal);
		@closeButton = GuiButton(this, recti());
		closeButton.navigable = false;
		closeButton.style = SS_GameTabClose;
		@closeButton.alignment = Alignment(Right-TAB_CLOSE_OFFSET.x-size.x, Top+TAB_CLOSE_OFFSET.y, Right-TAB_CLOSE_OFFSET.x, Top+TAB_CLOSE_OFFSET.y+size.y);
			
		updateAbsolutePosition();
	}

	void setTab(Tab@ forTab) {
		if(tab is forTab)
			return;
		@tab = forTab;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is closeButton) {
			if(event.type == GUI_Clicked) {
				close();
				return true;
			}
		}
		else if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hovered = true;
				break;
				case GUI_Mouse_Left:
					Hovered = false;
					Pressed = false;
					LeftHeld = false;
				break;
				case GUI_Focused:
					Focused = true;
				return false;
				case GUI_Focus_Lost:
					Focused = false;
					Pressed = false;
					LeftHeld = false;
					Dragging = false;
				return false;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void click() {
		switchToTab(tab);
	}

	void close() {
		closeTab(tab);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Moved: {
					vec2i mouse(event.x, event.y);
					if(Dragging) {
						if(!mouseLeft) {
							Dragging = false;
							LeftHeld = false;
							return true;
						}
						if(mouse.x < AbsolutePosition.topLeft.x - 5) {
							int index = tabs.find(tab);
							if(index > 0) {
								@tabs[index] = tabs[index - 1];
								@tabs[index - 1] = tab;
								@bar.tabs[index] = bar.tabs[index - 1];
								@bar.tabs[index - 1] = this;
								swap(bar.tabs[index]);
								bar.refresh();
							}
						}
						else if(mouse.x > AbsolutePosition.botRight.x + 5) {
							int index = tabs.find(tab);
							if(index < int(tabs.length - 1)) {
								@tabs[index] = tabs[index + 1];
								@tabs[index + 1] = tab;
								@bar.tabs[index] = bar.tabs[index + 1];
								@bar.tabs[index + 1] = this;
								swap(bar.tabs[index]);
								bar.refresh();
							}
						}
					}
					else if(Pressed && LeftHeld) {
						if(abs(dragStart.x - mouse.x) > 5 || abs(dragStart.y - mouse.y) > 5) {
							Pressed = false;
							Dragging = true;
							closeButton.visible = false;
							dragStart = dragStart - AbsolutePosition.topLeft;
						}
					}
				} break;
				case MET_Button_Down:
					Pressed = true;
					if(event.button == 0) {
						dragStart = mousePos;
						LeftHeld = true;
					}
					return true;
				case MET_Button_Up:
					if(Dragging) {
						if(event.button == 0) {
							Dragging = false;
							LeftHeld = false;
							closeButton.visible = true;
							return true;
						}
					}
					else if(Pressed) {
						if(Hovered) {
							if(event.button == 2) {
								close();
							}
							else if(event.button == 0) {
								if(Hovered)
									click();
							}
						}
						Pressed = false;
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw(const recti& pos) {
		Color color(0xffffffff);

		uint flags = SF_Normal;
		if(Pressed)
			flags |= SF_Pressed;
		if(Hovered)
			flags |= SF_Hovered;
		if(Focused)
			flags |= SF_Focused;

		if(tab is activeTab) {
			flags |= SF_Active;
			color = tab.activeColor;
		}
		else {
			color = tab.inactiveColor;
		}

		const Font@ fnt = skin.getFont(FT_Normal);

		//Do flashing
		if(tab.flashing) {
			double cycleTime = frameTime % TAB_FLASH_PERIOD;
			float pct = 0.f;

			if(cycleTime < TAB_FLASH_PERIOD * 0.5)
				pct = (cycleTime / (0.5 * TAB_FLASH_PERIOD));
			else
				pct = 1.0 - ((cycleTime - (0.5 * TAB_FLASH_PERIOD)) * 2.0);

			color = color.interpolate(TAB_FLASH_COLOR, pct);
		}

		//Tab background
		skin.draw(SS_GameTab, flags, pos, color);

		//Category icon
		tab.icon.draw(recti_area(
			pos.topLeft + TAB_ICON_OFFSET,
			TAB_ICON_SIZE));

		//Title text
		fnt.draw(recti_area(
			pos.topLeft + TAB_TEXT_OFFSET,
			vec2i(size.width - TAB_CLOSE_OFFSET.x - TAB_PADDING.x - TAB_TEXT_OFFSET.x,
				  size.height - TAB_PADDING.y - TAB_TEXT_OFFSET.y)), tab.title, ellipsis);
	}
	
	void draw() {
		closeButton.visible = !tab.locked;
		if(Dragging) {
			clearClip();
			int maxPos = bar.tabs[bar.tabs.length - 1].AbsolutePosition.topLeft.x;
			int pos = clamp(mousePos.x - dragStart.x, TAB_HOME_OFFSET, maxPos);

			draw(recti_area( vec2i(pos, AbsolutePosition.topLeft.y), size));
		}
		else {
			draw(AbsolutePosition);
			BaseGuiElement::draw();
		}
	}
};

//Tab internal management
void tab_next(bool pressed) {
	if(pressed)
		switchToTab(1);
}

void tab_previous(bool pressed) {
	if(pressed)
		switchToTab(-1);
}

void tab_new(bool pressed) {
	if(pressed)
		switchToTab(newTab());
}

void tab_close(bool pressed) {
	if(pressed)
		closeTab();
}

void tab_reopen(bool pressed) {
	if(pressed)
		switchToTab(reopenTab());
}

void tab_1(bool pressed) {
	if(pressed)
		switchToTab(tabs[0]);
}

void tab_2(bool pressed) {
	if(pressed)
		switchToTab(tabs[1 % tabs.length]);
}

void tab_3(bool pressed) {
	if(pressed)
		switchToTab(tabs[2 % tabs.length]);
}

void tab_4(bool pressed) {
	if(pressed)
		switchToTab(tabs[3 % tabs.length]);
}

void tab_5(bool pressed) {
	if(pressed)
		switchToTab(tabs[4 % tabs.length]);
}

void tab_6(bool pressed) {
	if(pressed)
		switchToTab(tabs[5 % tabs.length]);
}

void tab_7(bool pressed) {
	if(pressed)
		switchToTab(tabs[6 % tabs.length]);
}

void tab_8(bool pressed) {
	if(pressed)
		switchToTab(tabs[7 % tabs.length]);
}

void tab_9(bool pressed) {
	if(pressed)
		switchToTab(tabs[8 % tabs.length]);
}

bool tabEscape() {
	if(!settings::bEscapeGalaxyTab)
		return false;
	if(ActiveTab.category == TC_Galaxy)
		return false;
	auto@ otherTab = findTab(TC_Galaxy);
	if(otherTab is null)
		return false;
	switchToTab(otherTab);
	return true;
}

void init() {
	//Create the tabbar
	@tabBar = GuiTabBar();

	//Create the global bar
	@globalBar = createGlobalBar();
	@globalBar.alignment = Alignment(Left, Top+TAB_HEIGHT + 2, Right, Top+TAB_HEIGHT + 2 + GLOBAL_BAR_HEIGHT);

	//Create initial galaxy view
	auto defaultTab = createGalaxyTab(playerEmpire);
	newTab(defaultTab);
	switchToTab(defaultTab);

	newTab(createDiplomacyTab());
	if(hasDLC("Heralds"))
		newTab(createAttitudesTab());
	newTab(createResearchTab());
	newTab(createDesignOverviewTab());
	newTab(createPlanetsTab());
	newTab(createCommunityHome());

	//Bind keybinds
	keybinds::Global.addBind(KB_TAB_NEW, "tab_new");
	keybinds::Global.addBind(KB_TAB_CLOSE, "tab_close");
	keybinds::Global.addBind(KB_TAB_REOPEN, "tab_reopen");
	keybinds::Global.addBind(KB_TAB_NEXT, "tab_next");
	keybinds::Global.addBind(KB_TAB_PREVIOUS, "tab_previous");

	keybinds::Global.addBind(KB_TAB_1, "tab_1");
	keybinds::Global.addBind(KB_TAB_2, "tab_2");
	keybinds::Global.addBind(KB_TAB_3, "tab_3");
	keybinds::Global.addBind(KB_TAB_4, "tab_4");
	keybinds::Global.addBind(KB_TAB_5, "tab_5");
	keybinds::Global.addBind(KB_TAB_6, "tab_6");
	keybinds::Global.addBind(KB_TAB_7, "tab_7");
	keybinds::Global.addBind(KB_TAB_8, "tab_8");
	keybinds::Global.addBind(KB_TAB_9, "tab_9");
}

void preReload(Message& msg) {
	tabBar.remove();
	globalBar.remove();
}

void postReload(Message& msg) {
	init();
}

void tick(double time) {
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i)
		tabs[i].tick(time);
}

const Shader@ getFullscreenShader() {
	if(settings::bBloom || settings::bChromaticAberration || settings::bFilmGrain || settings::bGodRays || settings::bVignette)
		return shader::FullscreenPostProcess;
	return null;
}

//Render last view for menu if requested
void preRender(double time) {
	if(game_state == GS_Menu) {
		@fullscreenShader = shader::MenuRender;

		lastCamera.camera.animate(time);
		updateRenderCamera(lastCamera.camera);
	}
	else {
		@fullscreenShader = getFullscreenShader();
		activeTab.preRender(time);
	}
}

void render(double time) {
	if(game_state == GS_Menu) {
		prepareRender(lastCamera.camera);
		renderWorld();
	}
	else {
		activeTab.render(time);
	}
}

void deinit() {
	@fullscreenShader = null;
}

void save(SaveFile& file) {
	uint cnt = tabs.length;
	uint mainTab = 0;
	file << cnt;
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		uint cat = tabs[i].category;
		file << cat;
		tabs[i].save(file);
		if(tabs[i] is activeTab)
			mainTab = i;
	}
	file << mainTab;
}

void load(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;

	for(uint i = 0, cnt = tabs.length; i < cnt; ++i)
		tabs[i].close();
	tabs.length = 0;

	for(uint i = 0; i < cnt; ++i) {
		Tab@ t;
		uint cat = 0;
		file >> cat;

		switch(cat) {
			case TC_Galaxy: @t = createGalaxyTab(); break;
			case TC_Designs: @t = createDesignOverviewTab(); break;
			case TC_Home: @t = createHomeTab(); break;
			case TC_Research: @t = createResearchTab(); break;
			case TC_Planets: @t = createPlanetsTab(); break;
			case TC_Diplomacy: @t = createDiplomacyTab(); break;
			case TC_Wiki: @t = createCommunityHome(); break;
			case TC_Attitudes: @t = createAttitudesTab(); break;
		}

		if(t !is null) {
			t.load(file);
			newTab(t);
		}
	}

	uint mainTab = 0;
	file >> mainTab;
	switchToTab(tabs[mainTab]);
}
