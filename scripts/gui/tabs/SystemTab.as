import tabs.Tab;
import elements.GuiAccordion;
import elements.GuiPanel;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiMarkupText;
from elements.Gui3DObject import Gui3DObject, ObjectAction;
from elements.GuiResources import GuiResources;
import planet_types;
import planet_levels;
import resources;
import systems;
import util.formatting;
from obj_selection import selectObject;
import overlays.Popup;
from overlays.PlanetPopup import PlanetPopup;

from overlays.ContextMenu import openContextMenu;
from tabs.tabbar import get_ActiveTab, browseTab, popTab;
import void zoomTabTo(Object@ obj) from "tabs.GalaxyTab";
import void openOverlay(Object@ obj) from "tabs.GalaxyTab";

const vec2i SIZE_PER_PX(5.0, 8.0);

final class SystemBox {
	SystemDesc@ desc;
	recti pos;
};

final class LineBox {
	SystemBox@ from;
	SystemBox@ to;
	vec2i fromPos;
	vec2i toPos;
	recti area;
};

array<SystemBox> systemBoxes;
array<LineBox@> systemLines;
void createSystemBoxes() {
	uint sysCnt = systemCount;
	systemBoxes.length = sysCnt;
	for(uint i = 0,cnt = sysCnt; i < cnt; ++i) {
		SystemDesc@ desc = getSystem(i);
		vec2i pos = vec2i(desc.position.x / SIZE_PER_PX.x, desc.position.z / SIZE_PER_PX.y);
		vec2i size = vec2i(desc.object.planetCount*160+40, 220);

		SystemBox@ box = systemBoxes[i];
		@box.desc = desc;
		box.pos = recti_area(pos-(size/2), size);

		for(uint j = 0, jcnt = desc.adjacent.length; j < jcnt; ++j) {
			uint adj = desc.adjacent[j];
			if(adj < i) {
				LineBox line;
				@line.from = box;
				@line.to = systemBoxes[adj];
				line.fromPos = line.from.pos.center;
				line.toPos = line.to.pos.center;

				line.area.topLeft.x = min(line.fromPos.x - 5, line.toPos.x - 5);
				line.area.topLeft.y = min(line.fromPos.y - 5, line.toPos.y - 5);
				line.area.botRight.x = max(line.fromPos.x + 5, line.toPos.x + 5);
				line.area.botRight.y = max(line.fromPos.y + 5, line.toPos.y + 5);

				systemLines.insertLast(line);
			}
		}
	}
}

class SystemTab : Tab {
	Region@ sys;
	const SystemDesc@ desc;

	array<PlanetPopup@> popups;

	bool heldLeft = false;
	bool dragging = false;
	bool moved = false;
	vec2d scroll;
	vec2i dragStart;
	vec2i prevScroll;

	set_int instantiated;

	SystemTab() {
		super();
		title = locale::SYSTEM_TAB;
		if(systemBoxes.length == 0)
			createSystemBoxes();
	}

	void display(Object@ system) {
		for(uint i = 0, cnt = systemBoxes.length; i < cnt; ++i) {
			SystemBox@ box = systemBoxes[i];
			if(system is box.desc.object) {
				scroll = vec2d(box.pos.center);
				prevScroll = vec2i(scroll);
				moved = true;
				break;
			}
		}
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();
	}

	Color get_activeColor() {
		return Color(0xfcb44eff);
	}

	Color get_inactiveColor() {
		return Color(0xff9600ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x8c642bff);
	}

	TabCategory get_category() {
		return TC_Galaxy;
	}

	void instantiate(const recti& relArea, SystemBox@ box) {
		instantiated.insert(box.desc.index);

		vec2i startPos = box.pos.topLeft - relArea.topLeft + vec2i(20, 36);
		uint plCnt = box.desc.object.planetCount;

		for(uint i = 0; i < plCnt; ++i) {
			Planet@ pl = box.desc.object.planets[i];
			PlanetPopup pop(this);
			pop.set(pl);
			pop.mouseLinked = false;
			pop.isSelectable = true;
			pop.update();

			pop.visible = pl.visible;
			pop.position = startPos + vec2i(160*i, 0);
			popups.insertLast(pop);
		}
	}

	void deinstantiate(SystemBox@ box) {
		instantiated.erase(box.desc.index);
		for(int i = popups.length - 1; i >= 0; --i) {
			if(popups[i].pl.region is box.desc.object) {
				popups[i].remove();
				popups.removeAt(i);
			}
		}
	}

	void movePopups() {
		vec2i roundedScroll(scroll);
		if(prevScroll == roundedScroll)
			return;

		vec2i moveBy = prevScroll - roundedScroll;
		prevScroll = roundedScroll;
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			PlanetPopup@ pop = popups[i];
			pop.move(moveBy);
		}
	}

	void updatePopups() {
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			popups[i].visible = popups[i].pl.visible;
			if(popups[i].visible)
				popups[i].update();
		}
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) {
		if(dragging) {
			//Cannot access inner elements while dragging,
			if(AbsoluteClipRect.isWithin(pos))
				return this;
			return null;
		}
		else {
			return Tab::elementFromPosition(pos);
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked: {
				PlanetPopup@ pop = cast<PlanetPopup>(evt.caller);
				if(pop !is null && pop.parent is this) {
					switch(evt.value) {
						case PA_Select:
							selectObject(pop.pl, shiftKey);
							return true;
						case PA_Manage:
							popTab(this);
							zoomTabTo(pop.pl);
							openOverlay(pop.pl);
							return true;
						case PA_Zoom:
							popTab(this);
							zoomTabTo(pop.pl);
							return true;
					}
					return true;
				}
			} break;
		}
		return Tab::onGuiEvent(evt);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_ESC)
					return true;
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					if(previous !is null) {
						popTab(this);
						return true;
					}
				}
			break;
		}
		return Tab::onKeyEvent(event, source);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Up) {
			if(event.button == 1) {
				if(previous !is null) {
					popTab(this);
					return true;
				}
			}
		}
		if(source is this) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0) {
						heldLeft = true;
						dragStart = vec2i(event.x, event.y);
					}
				break;
				case MET_Moved: {
					vec2i mouse = vec2i(event.x, event.y);
					vec2i d = mouse - dragStart;

					if(dragging) {
						scroll -= vec2d(double(d.x), double(d.y));
						dragStart = mouse;
						moved = true;
					}
					else if(heldLeft) {
						if(abs(d.x) >= 5 || abs(d.y) >= 5) {
							dragging = true;
							moved = true;
							scroll -= vec2d(double(d.x), double(d.y));
							dragStart = mouse;
						}
					}
				} break;
				case MET_Button_Up:
					if(event.button == 0) {
						if(!dragging) {
							//Do stuff
						}
						heldLeft = false;
						dragging = false;
						dragStart = vec2i();
					}
				break;
			}
		}
		return Tab::onMouseEvent(event, source);
	}

	void tick(double time) {
		if(!visible)
			return;

		if(moved) {
			movePopups();
			moved = false;

			recti relArea = recti_area(vec2i(scroll) - (size/2), size);
			for(uint i = 0, cnt = systemBoxes.length; i < cnt; ++i) {
				SystemBox@ box = systemBoxes[i];
				bool inst = instantiated.contains(i);

				if(box.pos.overlaps(relArea)) {
					if(!inst)
						instantiate(relArea, box);
				}
				else {
					if(inst)
						deinstantiate(box);
				}
			}
		}

		updatePopups();
	}

	void drawSystemLine(const recti& relArea, LineBox@ box) {
		Color col(0xffffff30);
		vec2i from = box.fromPos - relArea.topLeft + AbsolutePosition.topLeft;
		vec2i to = box.toPos - relArea.topLeft + AbsolutePosition.topLeft;

		bool canTrade = (box.to.desc.object.TradeMask & playerEmpire.mask) != 0
			|| (box.from.desc.object.TradeMask & playerEmpire.mask) != 0;
		if(canTrade) {
			col = playerEmpire.color;
			col.a = 0x60;
		}

		drawLine(from, to, col, 10);
	}

	void drawSystemBox(const recti& relArea, SystemBox@ box) {
		recti bpos = box.pos - relArea.topLeft + AbsolutePosition.topLeft;
		const Font@ ft = skin.getFont(FT_Medium);
		Color col;

		Empire@ prim = box.desc.object.visiblePrimaryEmpire;
		if(prim !is null)
			col = prim.color;

		skin.draw(SS_SystemPanel, SF_Normal, bpos, col);
		ft.draw(bpos.topLeft+vec2i(8, 5), box.desc.name);
	}

	void draw() {
		skin.draw(SS_SystemListBG, SF_Normal, AbsolutePosition);

		recti relArea = recti_area(vec2i(scroll) - (size/2), size);

		//Draw the lines
		for(uint i = 0, cnt = systemLines.length; i < cnt; ++i) {
			LineBox@ box = systemLines[i];
			if(box.area.overlaps(relArea))
				drawSystemLine(relArea, box);
		}

		//Draw the boxes
		for(uint i = 0, cnt = systemBoxes.length; i < cnt; ++i) {
			SystemBox@ box = systemBoxes[i];
			if(box.pos.overlaps(relArea))
				drawSystemBox(relArea, box);
		}

		Tab::draw();
	}
};

Tab@ createSystemTab() {
	return SystemTab();
}

Tab@ createSystemTab(Object@ system) {
	SystemTab tab;
	tab.display(system);

	return tab;
}
