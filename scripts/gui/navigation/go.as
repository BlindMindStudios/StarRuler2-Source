#priority init -1
import tabs.Tab;
import elements.GuiTextbox;
import systems;
/*import research;*/
import resources;
from input import ActiveCamera;

import uint get_tabCount() from "tabs.tabbar";
import Tab@ get_Tabs(uint i) from "tabs.tabbar";
import Tab@ get_ActiveTab() from "tabs.tabbar";
import void switchToTab(Tab@) from "tabs.tabbar";
import Tab@ newTab(Tab@) from "tabs.tabbar";
import void browseTab(Tab@,Tab@,bool) from "tabs.tabbar";
import void browseTab(Tab@,bool) from "tabs.tabbar";
import Tab@ findTab(int cat) from "tabs.tabbar";
import Tab@ createResearchTab() from "tabs.ResearchTab";
import Tab@ createDesignOverviewTab() from "tabs.DesignOverviewTab";
import Tab@ createDesignEditorTab(const Design@) from "tabs.DesignEditorTab";
import Tab@ createGalaxyTab() from "tabs.GalaxyTab";
import Tab@ createGalaxyTab(Object@) from "tabs.GalaxyTab";
import Tab@ createGalaxyTab(vec3d) from "tabs.GalaxyTab";
/*import Tab@ createResearchTab(ResearchNode@ node) from "tabs.ResearchTab";*/
/*import void researchTabView(Tab@ tab, ResearchNode@ node) from "tabs.ResearchTab";*/
import void zoomTabTo(vec3d pos) from "tabs.GalaxyTab";
import void zoomTo(Object@ obj) from "tabs.GalaxyTab";

const uint ITEM_COUNT = 5;

class GoItem {
	Sprite get_icon() {
		return Sprite();
	}

	SkinStyle get_skinIcon() {
		return SS_NULL;
	}

	int match(const string&) {
		return 0;
	}

	string get_text() {
		return "(null)";
	}

	string get_type() {
		return "";
	}

	void go() {
	}

	bool go(TabCategory cat) {
		Tab@ found = findTab(cat);
		if(shiftKey || found is null) {
			return false;
		}
		else {
			switchToTab(found);
			return true;
		}
	}

	void go(Tab@ tab, TabCategory cat) {
		if(shiftKey) {
			newTab(tab);
			switchToTab(tab);
		}
		else {
			Tab@ found = findTab(cat);
			if(ctrlKey || found is null) {
				browseTab(tab, false); //TODO: History
			}
			else {
				browseTab(found, tab, false); //TODO: History
				switchToTab(tab);
			}
		}
	}

	void go(Tab@ tab) {
		if(shiftKey) {
			newTab(tab);
			switchToTab(tab);
		}
		else {
			browseTab(tab, false); //TODO: History
		}
	}
};

string str_galaxy = locale::GALAXY_CAMERA;
class GoGalaxy : GoItem {
	int match(const string& str) {
		if(str_galaxy.startswith_nocase(str))
			return 5;
		return 0;
	}

	SkinStyle get_skinIcon() {
		return SS_GalaxyIcon;
	}

	string get_text() {
		return str_galaxy;
	}

	void go() {
		go(createGalaxyTab());
	}
};

string str_research = locale::RESEARCH_OVERVIEW;
class GoResearch : GoItem {
	int match(const string& str) {
		if(str_research.startswith_nocase(str))
			return 3;
		return 0;
	}

	SkinStyle get_skinIcon() {
		return SS_ResearchIcon;
	}

	string get_text() {
		return str_research;
	}

	void go() {
		go(createResearchTab());
	}
};

string str_designs = locale::DESIGN_OVERVIEW;
class GoDesigns : GoItem {
	int match(const string& str) {
		if(str_designs.startswith_nocase(str))
			return 5;
		return 0;
	}

	SkinStyle get_skinIcon() {
		return SS_DesignsIcon;
	}

	string get_text() {
		return str_designs;
	}

	void go() {
		go(createDesignOverviewTab());
	}
};

class GoConsole : GoItem {
	int match(const string& str) {
		if(locale::CONSOLE.startswith_nocase(str))
			return 5;
		return 0;
	}

	string get_text() {
		return locale::CONSOLE;
	}

	void go() {
		toggleConsole();
	}
};

class GoSystem : GoItem {
	SystemDesc@ sys;

	GoSystem(SystemDesc@ _sys) {
		@sys = _sys;
	}

	int match(const string& str) {
		if(playerEmpire.valid && sys.object.ExploredMask & playerEmpire.mask == 0)
			return 0;
		if(sys.object.name.contains_nocase(str))
			return 5;
		return 0;
	}

	SkinStyle get_skinIcon() {
		return SS_GalaxyIcon;
	}

	string get_text() {
		return sys.object.name;
	}

	string get_type() {
		return locale::SYSTEM;
	}

	void go() {
		if(go(TC_Galaxy))
			zoomTabTo(sys.position);
		else
			go(createGalaxyTab(sys.position));
	}
}

string str_tab = locale::TAB;
class GoTab : GoItem {
	Tab@ tab;

	GoTab(Tab@ _tab) {
		@tab = _tab;
	}

	Sprite get_icon() {
		return tab.icon;
	}

	string get_text() {
		return tab.title;
	}

	string get_type() {
		return str_tab;
	}

	void go() {
		switchToTab(tab);
	}
}

string str_design = locale::DESIGN;
class GoDesign : GoItem {
	const Design@ dsg;

	GoDesign(const Design@ _dsg) {
		@dsg = _dsg;
	}

	SkinStyle get_skinIcon() {
		return SS_DesignsIcon;
	}

	string get_text() {
		return dsg.name;
	}

	string get_type() {
		return str_design;
	}

	void go() {
		go(createDesignEditorTab(dsg), TC_Designs);
	}
}

string str_planet = locale::PLANET;
class GoPlanet : GoItem {
	Object@ obj;

	GoPlanet(Object@ _obj) {
		@obj = _obj;
	}

	SkinStyle get_skinIcon() {
		return SS_GalaxyIcon;
	}

	string get_text() {
		return obj.name;
	}

	string get_type() {
		return str_planet;
	}

	void go() {
		go(createGalaxyTab(obj), TC_Galaxy);
	}
}

string str_ship = locale::SHIP;
class GoShip : GoItem {
	Object@ obj;

	GoShip(Object@ _obj) {
		@obj = _obj;
	}

	SkinStyle get_skinIcon() {
		return SS_GalaxyIcon;
	}

	string get_text() {
		return obj.name;
	}

	string get_type() {
		return str_ship;
	}

	void go() {
		go(createGalaxyTab(obj), TC_Galaxy);
	}
}

/*string str_technology = locale::TECHNOLOGY;*/
/*class GoTechnology : GoItem {*/
/*	ResearchNode@ node;*/

/*	GoTechnology(ResearchNode@ _node) {*/
/*		@node = _node;*/
/*	}*/

/*	SkinStyle get_skinIcon() {*/
/*		return SS_ResearchIcon;*/
/*	}*/

/*	string get_text() {*/
/*		return node.tech.name;*/
/*	}*/

/*	string get_type() {*/
/*		return str_technology;*/
/*	}*/

/*	void go() {*/
/*		go(createResearchTab(node), TC_Research);*/
/*	}*/
/*}*/

class GoResource : GoItem {
	const ResourceType@ resType;

	GoResource(const ResourceType@ type) {
		@this.resType = type;
	}

	int match(const string& str) {
		if(resType.name.contains_nocase(str) && str.length >= 3) {
			if(str.equals_nocase(resType.name))
				return 10;
			return 4;
		}
		return 0;
	}

	Sprite get_icon() {
		return resType.smallIcon;
	}

	string get_text() {
		return format(locale::GO_RESOURCE, resType.name);
	}

	string get_type() {
		return format(locale::GO_RESOURCE_TYPE, resType.name);
	}

	void go() {
		uint sysCnt = systemCount;
		Planet@ best;
		double closestDist = INFINITY;
		bool foundOwned = false;
		vec3d camPos = ActiveCamera.lookAt;

		for(uint i = 0; i < sysCnt; ++i) {
			auto@ sys = getSystem(i);
			uint plCnt = sys.object.planetCount;
			for(uint n = 0; n < plCnt; ++n) {
				Planet@ pl = sys.object.planets[n];
				if(pl.known) {
					auto@ type = getResource(pl.nativeResourceType[0]);
					if(type !is null && type is resType) {
						Empire@ owner = pl.visibleOwner;
						if(owner is playerEmpire) {
							Object@ dest = pl.nativeResourceDestination[0];
							if(dest !is null)
								continue;
							if(type.isMaterial(pl.level))
								continue;
							double dist = camPos.distanceToSQ(pl.position);
							if(dist < closestDist || !foundOwned) {
								@best = pl;
								closestDist = dist;
								foundOwned = true;
							}
						}
						else if(owner is null || !owner.valid) {
							if(!foundOwned) {
								double dist = camPos.distanceToSQ(pl.position);
								if(dist < closestDist) {
									@best = pl;
									closestDist = dist;
								}
							}
						}
					}
				}
			}
		}

		if(best !is null)
			zoomTo(best);
	}
};

class GoResourceClass : GoItem {
	const ResourceClass@ resType;

	GoResourceClass(const ResourceClass@ type) {
		@this.resType = type;
	}

	int match(const string& str) {
		if(resType.name.contains_nocase(str) && str.length >= 3) {
			if(str.equals_nocase(resType.name))
				return 9;
			return 4;
		}
		return 0;
	}

	string get_text() {
		return format(locale::GO_RESOURCE, resType.name);
	}

	string get_type() {
		return format(locale::GO_RESOURCE_TYPE, resType.name);
	}

	void go() {
		uint sysCnt = systemCount;
		Planet@ best;
		double closestDist = INFINITY;
		bool foundOwned = false;
		vec3d camPos = ActiveCamera.lookAt;

		for(uint i = 0; i < sysCnt; ++i) {
			auto@ sys = getSystem(i);
			uint plCnt = sys.object.planetCount;
			for(uint n = 0; n < plCnt; ++n) {
				Planet@ pl = sys.object.planets[n];
				if(pl.known) {
					auto@ type = getResource(pl.nativeResourceType[0]);
					if(type !is null && type.cls is resType) {
						Empire@ owner = pl.visibleOwner;
						if(owner is playerEmpire) {
							Object@ dest = pl.nativeResourceDestination[0];
							if(dest !is null)
								continue;
							if(type.isMaterial(pl.level))
								continue;
							double dist = camPos.distanceToSQ(pl.position);
							if(dist < closestDist || !foundOwned) {
								@best = pl;
								closestDist = dist;
								foundOwned = true;
							}
						}
						else if(owner is null || !owner.valid) {
							if(!foundOwned) {
								double dist = camPos.distanceToSQ(pl.position);
								if(dist < closestDist) {
									@best = pl;
									closestDist = dist;
								}
							}
						}
					}
				}
			}
		}

		if(best !is null)
			zoomTo(best);
	}
};


GoItem@[] staticItems;

bool WouldInsert(uint amount, int match, int[]& priorities) {
	if(match < 0)
		return false;
	if(priorities[amount - 1] == -1)
		return true;
	if(priorities[amount - 1] >= match)
		return false;
	return true;
}

void GoInsert(GoItem@ item, uint amount, int match, GoItem@[]& list, int[]& priorities) {
	if(list[amount - 1] !is null && priorities[amount - 1] >= match)
		return;

	for(int j = amount - 1; j >= 0; --j) {
		//Push it up
		if(j < int(amount) - 1) {
			priorities[j + 1] = priorities[j];
			@list[j + 1] = list[j];
		}

		//Check if we should insert here
		if(j == 0 || match < priorities[j - 1]) {
			//Insert here
			priorities[j] = match;
			@list[j] = item;
			return;
		}
	}
}

void GoSearch(const string& text, GoItem@[]& list, uint amount = 5) {
	//Cache of priorities
	int[] priorities;
	priorities.length = amount;

	//Clear the list
	list.length = amount;
	for(uint i = 0; i < amount; ++i) {
		@list[i] = null;
		priorities[i] = -1;
	}

	//Empty text matches nothing
	if(text.length == 0)
		return;

	//Search static items
	uint cnt = staticItems.length;
	for(uint i = 0; i < cnt; ++i) {
		int match = staticItems[i].match(text);
		if(match > 0)
			GoInsert(staticItems[i], amount, match, list, priorities);
	}

	//Search tabs
	cnt = tabCount;
	for(uint i = 0; i < cnt; ++i) {
		Tab@ tab = Tabs[i];
		if(tab.title.contains_nocase(text)) {
			if(WouldInsert(amount, 50, priorities))
				GoInsert(GoTab(tab), amount, 50, list, priorities);
		}
	}

	//Search designs
	{
		ReadLock lock(playerEmpire.designMutex);
		cnt = playerEmpire.designCount;
		for(uint i = 0; i < cnt; ++i) {
			const Design@ dsg = playerEmpire.designs[i];
			if(dsg.name.contains_nocase(text)) {
				int p = text.length > 3 ? 10 : 2;
				if(dsg.name.equals_nocase(text))
					p += 100;
				if(WouldInsert(amount, p, priorities))
					GoInsert(GoDesign(dsg), amount, p, list, priorities);
			}
		}
	}

	//Search empire objects
	//cnt = playerEmpire.objectCount;
	//for(uint i = 0; i < cnt; ++i) {
		//Object@ obj = playerEmpire.objects[i];
		//Ship@ ship = cast<Ship@>(obj);
		//Planet@ pl = cast<Planet@>(obj);

		//int prior = -1;
		//if(ship !is null || pl !is null) {
			//if(obj.name.contains_nocase(text)) {
				//if(pl !is null)
					//prior = text.length > 3 ? 16 : 4;
				//else
					//prior = text.length > 3 ? 6 : 4;
			//}
			//if(obj.name.equals_nocase(text))
				//prior += 100;
		//}

		//if(WouldInsert(amount, prior, priorities)) {
			//GoItem@ it;
			//if(pl !is null)
				//@it = GoPlanet(obj);
			//else if(ship !is null)
				//@it = GoShip(obj);

			//if(it !is null)
				//GoInsert(it, amount, prior, list, priorities);
		//}
	//}

	//Search research
	/*cnt = getResearchNodeCount();*/
	/*for(uint i = 0; i < cnt; ++i) {*/
	/*	ResearchNode@ node = getResearchNode(i);*/
	/*	if(node.tech.name.contains_nocase(text)) {*/
	/*		int p = text.length > 3 ? 7 : 1;*/
	/*		if(node.tech.name.equals_nocase(text))*/
	/*			p += 100;*/
	/*		if(!node.unlocked)*/
	/*			p += 1;*/

	/*		if(WouldInsert(amount, p, priorities))*/
	/*			GoInsert(GoTechnology(node), amount, p, list, priorities);*/
	/*	}*/
	/*}*/
}

class GoDialog : BaseGuiElement {
	GuiTextbox@ box;
	GoItem@[] items;
	uint selected;
	int hovered;

	GoDialog() {
		super(null, recti());
		alignment.left.set(AS_Left, 0.1f, 0);
		alignment.right.set(AS_Right, 0.1f, 0);
		alignment.top.set(AS_Top, 0.5f, -32 - int(ITEM_COUNT * 15));
		alignment.bottom.set(AS_Top, 0.5f, int(ITEM_COUNT * 15) + 40);

		@box = GuiTextbox(this, recti(0, 0, 100, 48), "");
		box.font = FT_Big;
		@box.alignment = Alignment(Left+8, Top+8, Right-8, Top+56);

		selected = 0;
		hovered = -1;
		items.length = ITEM_COUNT;

		updateAbsolutePosition();
	}

	void clear() {
		box.text = "";
		for(uint i = 0; i < ITEM_COUNT; ++i)
			@items[i] = null;
		selected = 0;
		hovered = -1;
	}

	void hide() {
		visible = false;
		clear();
	}

	void next() {
		if(selected < ITEM_COUNT - 1) {
			if(items[selected + 1] !is null)
				selected += 1;
		}
	}

	void prev() {
		if(selected > 0)
			selected -= 1;
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_UP) {
					prev();
					return true;
				}
				else if(event.key == KEY_DOWN) {
					next();
					return true;
				}
				else if(event.key == KEY_TAB) {
					if(shiftKey)
						prev();
					else
						next();
					return true;
				}
				else if(event.key == KEY_ESC) {
					return true;
				}
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					hide();
					setGuiFocus(ActiveTab);
					return true;
				}
				else if(event.key == KEY_UP) {
					return true;
				}
				else if(event.key == KEY_DOWN) {
					return true;
				}
				else if(event.key == KEY_TAB) {
					return true;
				}
			break;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void updateHovered() {
		vec2i rel = mousePos - AbsolutePosition.topLeft;
		if(rel.x < 4 || rel.x > size.width - 4) {
			hovered = -1;
			return;
		}

		hovered = (rel.y - 64) / 30;
		if(hovered < 0 || hovered >= ITEM_COUNT || items[hovered] is null) {
			hovered = -1;
			return;
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Focus_Lost:
				if(event.other is null || !event.other.isChildOf(this)) {
					hide();
					return false;
				}
			break;
			case GUI_Changed:
				search();
			break;
			case GUI_Confirmed:
				if(box.text != "" && items[selected] !is null)
					items[selected].go();
				hide();
				if(getGuiFocus() !is null && getGuiFocus().isChildOf(this))
					setGuiFocus(ActiveTab);
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Button_Up:
					if(hovered >= 0)
						items[hovered].go();
					hide();
					return true;
				case MET_Moved:
					updateHovered();
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void search() {
		GoSearch(box.text, items);
		selected = 0;
		hovered = -1;
	}

	void drawItem(uint i, const recti& absPos) {
		GoItem@ item = items[i];

		uint flags = SF_Normal;
		if(i == selected)
			flags |= SF_Active;
		if(int(i) == hovered)
			flags |= SF_Hovered;

		skin.draw(SS_GoItem, flags, absPos);

		recti iconPos = recti_area(
			absPos.topLeft + vec2i(4, 6),
			vec2i(20, 18));

		Sprite sprt = item.icon;

		if(sprt.valid)
			sprt.draw(iconPos);
		else if(item.skinIcon != SS_NULL)
			skin.draw(item.skinIcon, SF_Normal, iconPos);

		skin.draw(FT_Medium, absPos.topLeft + vec2i(28, 4), item.text);
		skin.draw(FT_Medium, absPos.botRight - vec2i(204, 26), item.type);
	}

	void draw() {
		//Draw the background
		skin.draw(SS_GoDialog, SF_Normal, AbsolutePosition);

		//Draw the items
		for(uint i = 0; i < ITEM_COUNT; ++i) {
			if(items[i] is null)
				break;
			drawItem(i, recti_area(
				AbsolutePosition.topLeft + vec2i(8, 64 + i * 30),
				vec2i(size.width - 16, 30)));
		}

		BaseGuiElement::draw();
	}
};

void gogogo(bool pressed) {
	if(pressed) {
		dialog.visible = true;
		dialog.bringToFront();
		setGuiFocus(dialog.box);
	}
}

void toggleGoDialog() {
	if(!dialog.visible) {
		dialog.visible = true;
		dialog.bringToFront();
		setGuiFocus(dialog.box);
	}
	else {
		dialog.hide();
	}
}

GoDialog@ dialog;
IGuiElement@ getGoDialog() {
	return dialog;
}

void init() {
	//Initialize dialog
	@dialog = GoDialog();
	dialog.visible = false;

	//Initialize static items
	staticItems.insertLast(GoResearch());
	staticItems.insertLast(GoDesigns());
	staticItems.insertLast(GoGalaxy());
	staticItems.insertLast(GoConsole());

	//Add systems to static items
	for(uint i = 0, cnt = systemCount; i < cnt; ++i)
		staticItems.insertLast(GoSystem(getSystem(i)));

	//Add resource finds
	for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
		auto@ type = getResource(i);
		if(!type.artificial)
			staticItems.insertLast(GoResource(type));
	}

	//Add resource classes
	for(uint i = 0, cnt = getResourceClassCount(); i < cnt; ++i) {
		auto@ type = getResourceClass(i);
		staticItems.insertLast(GoResourceClass(type));
	}

	keybinds::Global.addBind(KB_GO_MENU, "gogogo");
}
