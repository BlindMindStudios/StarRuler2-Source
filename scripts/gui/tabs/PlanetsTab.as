import tabs.Tab;
import elements.GuiButton;
import elements.GuiResources;
import elements.GuiPanel;
import elements.GuiSprite;
import elements.GuiSkinElement;
import elements.GuiTextbox;
import elements.BaseGuiElement;
import elements.MarkupTooltip;
import resources;
import tile_resources;
import util.icon_view;
import tabs.tabbar;
import planet_levels;
import icons;
import statuses;
from overlays.PlanetPopup import PlanetPopup;
from overlays.ContextMenu import openContextMenu;
from obj_selection import selectObject, selectedObject, selectedObjects;
import void zoomTo(Object@ obj) from "tabs.GalaxyTab";
import void openOverlay(Object@ obj) from "tabs.GalaxyTab";

const int ICON_SIZE = 46;

Color COLOR_DROP(0xaaffaa80);
Color COLOR_CLEAR(0xaaaaff60);
Color COLOR_HOVER(0xffffff20);
bool SHOW_PLANETS = true;

enum PlanetModes {
	PM_NORMAL,
	PM_MONEY,
	PM_PRODUCTION,
	PM_REQUIREMENTS,
	PM_TILES,
	PM_PRESSURE
};

class PlanetElement {
	Object@ parentObject;
	Object@ obj;

	int width = 0;
	int height = 0;

	PlanetElement@ parent;
	array<PlanetElement@> children;
	array<Status> statuses;

	PlanetModes mode = PM_NORMAL;
	int income = 0;
	int level = 0;

	const ResourceRequirements@ reqs;
	array<int>@ remaining = null;
	array<double>@ production = null;

	int numUsed = -1;
	int numTotal = -1;

	string name;
	string moneyText;
	const ResourceType@ resource;
	Resource@ primary;
	bool isPrimary = true;
	bool excess = false;
	bool locked = false;
	bool focused = false;
	bool decaying = false;
	Resources available;

	int minWidth = 0;
	int coffset = 0;

	bool hovered = false;
	bool showChildren = true;
	Color hoverColor;

	void clear() {
		children.length = 0;
		@parent = null;
	}

	PlanetElement@ get_root() {
		PlanetElement@ par = this;
		while(par.parent !is null)
			@par = par.parent;
		return par;
	}

	string getTooltip() {
		 string ttip = getResourceTooltip(primary.type, primary, obj);
		 for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
			 auto@ status = statuses[i];
			 string title = status.type.name;
			 if(status.stacks > 1 && !status.type.unique)
				 title += format(" ($1x)", toString(status.stacks));
			 ttip += "\n\n";
			 ttip += status.getTooltip(obj);
		 }
		 return ttip;
	}

	void cache(Resource@ res, bool isPrimary) {
		if(res !is null) {
			if(primary is null)
				@primary = Resource();
			primary = res;
			@parentObject = isPrimary ? primary.exportedTo : res.origin;
			@resource = primary.type;
		}
		else {
			@primary = null;
			@parentObject = null;
			@resource = null;
		}
		this.isPrimary = isPrimary;

		bool hasSurface = obj.hasSurfaceComponent;
		name = obj.name;
		level = hasSurface ? obj.level : 0;

		//Load primary resource
		excess = false;
		if(primary !is null && primary.type !is null) {
			excess = primary.exportedTo is null && primary.origin !is null && primary.usable
				&& (!hasSurface || !primary.type.isMaterial(level));
			locked = primary.locked || !primary.type.exportable || !isPrimary;
		}

		//Check resource requirements
		if(isPrimary) {
			if(mode == PM_MONEY && hasSurface) {
				income = obj.income;
				moneyText = formatMoney(income);
			}
			else {
				income = 0;
			}

			decaying = hasSurface && obj.decayTime > 0;
			@reqs = null;
			if(hasSurface) {
				if(decaying && mode == PM_NORMAL) {
					@reqs = getPlanetLevel(obj, level).reqs;
				}
				else if(mode == PM_REQUIREMENTS) {
					if(level < int(getMaxPlanetLevel(obj))) {
						if(primary is null || primary.exportedTo is null || level < int(primary.type.level))
							@reqs = getPlanetLevel(obj, level+1).reqs;
					}
				}

				if(reqs !is null) {
					if(remaining is null)
						@remaining = array<int>();
					available.clear();
					receive(obj.getResourceAmounts(), available);
					reqs.satisfiedBy(available, null, true, remaining);
				}
				else {
					@remaining = null;
				}
			}

			//Check resource production
			if(mode == PM_PRODUCTION && hasSurface) {
				if(production is null)
					@production = array<double>(TR_COUNT);
				for(uint i = 0; i < TR_COUNT; ++i) {
					if(i == TR_Labor)
						production[i] = obj.laborIncome * 60.0;
					else
						production[i] = obj.getResourceProduction(i);
				}
			}
			else {
				@production = null;
			}

			//Check statuses
			if(obj.hasStatuses)
				statuses.syncFrom(obj.getStatusEffects());
			else
				statuses.length = 0;

			//Check surface size
			if(mode == PM_TILES && hasSurface) {
				numTotal = obj.totalSurfaceTiles;
				numUsed = obj.usedSurfaceTiles;
			}
			else if(mode == PM_PRESSURE && hasSurface) {
				numTotal = obj.pressureCap;
				numUsed = obj.totalPressure;
			}
			else {
				numTotal = -1;
				numUsed = -1;
			}
		}
	}

	void export(PlanetElement@ to) {
		if(to is null)
			obj.exportResource(0, null);
		else
			obj.exportResource(0, to.obj);
	}

	void calc() {
		height = 0;
		width = 0;
		if(showChildren) {
			for(uint i = 0, cnt = children.length; i < cnt; ++i) {
				auto@ child = children[i];
				child.calc();
				if(child.height > height)
					height = child.height;
				width += child.width;
			}
		}
		if(width < minWidth) {
			coffset = (minWidth - width) / 2;
			width = minWidth;
		}
		if(width == 0)
			width = 50;
		height += 50;
	}

	void sort() {
		children.sortDesc();
		for(uint i = 0, cnt = children.length; i < cnt; ++i)
			children[i].sort();
	}

	void dump() {
		dump("");
	}

	void click(int button) {
		if(button == 0) {
			if(obj.selected) {
				if(!focused) {
					zoomTo(obj);
					openOverlay(obj);
				}
			}
			else
				selectObject(obj);
		}
		else if(button == 1) {
			if(selectedObject is null)
				openContextMenu(obj, obj);
			else
				openContextMenu(obj);
		}
		else if(button == 2) {
			zoomTo(obj);
		}
	}

	void renderLine(const recti& fromPos, const recti& toPos, const Color& lineColor, bool sourceLine = false) {
		vec2i from = fromPos.center;
		vec2i to = vec2i(from.x, toPos.topLeft.y + 22);
		from += (to - from).normalized(18);

		drawLine(from, to, lineColor, 4);
		if(sourceLine) {
			if(from.x < toPos.topLeft.x)
				drawLine(to - vec2i(2,1), vec2i(toPos.topLeft.x, to.y-1), lineColor, 4);
			else if(from.x > toPos.botRight.x)
				drawLine(vec2i(toPos.botRight.x, to.y-1), to + vec2i(2, -1), lineColor, 4);
		}
	}

	PlanetElement@ planetFromPosition(const vec2i& startPos, const vec2i& offset, bool strict = true) {
		if(!getFullPos(startPos).isWithin(offset))
			return null;
		if(getIconPos(startPos).isWithin(offset))
			return this;
		vec2i pos(startPos.x, startPos.y + 50);
		pos.x += coffset;
		for(uint i = 0, cnt = children.length; i < cnt; ++i) {
			PlanetElement@ elem = children[i].planetFromPosition(pos, offset);
			if(elem !is null)
				return elem;
			pos.x += children[i].width;
		}
		return strict ? null : this;
	}

	recti getIconPos(const vec2i& startPos) {
		return recti_area(startPos.x + ((width - ICON_SIZE) / 2), startPos.y+2, ICON_SIZE,ICON_SIZE);
	}

	recti getFullPos(const vec2i& startPos) {
		return recti_area(startPos, vec2i(width, height));
	}

	void drawTree(const vec2i& startPos) {
		recti iconPos = getIconPos(startPos);
		vec2i pos(startPos.x, startPos.y + 50);

		//Draw the resource lines
		if(children.length != 0 && showChildren) {
			Color lineColor = playerEmpire.color;
			lineColor.a = 0x80;
			if(children.length > 1) {
				drawLine(vec2i(startPos.x + coffset + children[0].width/2 - 3, startPos.y + 23),
						vec2i(startPos.x + width/2 - 22, startPos.y + 23),
						lineColor, 4);
				drawLine(vec2i(startPos.x + width/2 + 22, startPos.y + 23),
						vec2i(startPos.x + width - children.last.width/2 + 2 - coffset, startPos.y + 23),
						lineColor, 4);
			}
			pos.x += coffset;
			for(uint i = 0, cnt = children.length; i < cnt; ++i) {
				auto@ child = children[i];

				Color color = lineColor;
				bool sourceLine = false;
				if(child.primary !is null && (!child.primary.usable || child.decaying)) {
					float pct = abs((frameTime % 1.0) - 0.5f) * 2.f;
					color = colors::Red.interpolate(colors::Orange, pct);
					sourceLine = true;
				}

				recti childPos = child.getIconPos(pos);
				renderLine(childPos, iconPos, color, sourceLine);
				pos.x += child.width;
			}
		}

		//Draw children
		if(showChildren) {
			vec2i pos(startPos.x, startPos.y + 50);
			pos.x += coffset;
			for(uint i = 0, cnt = children.length; i < cnt; ++i) {
				children[i].drawTree(pos);
				pos.x += children[i].width;
			}
		}

		//Draw self
		if(decaying)
			drawRectangle(iconPos, Color(0xff000080));
		if(hovered)
			drawRectangle(iconPos, hoverColor);
		if(focused && isPrimary)
			material::SelectionCircle.draw(iconPos.padded(-2), Color(0xffc0ff80));
		else if(obj.selected && isPrimary)
			material::SelectionCircle.draw(iconPos);
		drawPlanet(iconPos);

		//Draw data
		if(isPrimary) {
			if(statuses.length != 0) {
				vec2i pos(iconPos.botRight.x-12, iconPos.topLeft.y+4);
				int count = int(statuses.length);
				int spacing = min(iconPos.height / count, 22);
				const Font@ ft = font::DroidSans_11_Bold;
				for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
					auto@ status = statuses[i];
					spritesheet::ResourceIconsMods.draw(0, recti_area(pos-vec2i(3), vec2i(26)), status.type.color);
					status.type.icon.draw(recti_area(pos, vec2i(20)));
					if(!status.type.unique && status.stacks > 1)
						ft.draw(
							pos=recti_area(pos-vec2i(3), vec2i(26)),
							horizAlign=1.0, vertAlign=1.0,
							stroke=colors::Black,
							color=status.type.color,
							text=toString(status.stacks)+"x");
					pos.y += spacing;
				}
			}
			if(reqs !is null) {
				uint rCnt = reqs.reqs.length;
				int tot = 0;
				for(uint i = 0; i < rCnt; ++i)
					tot += remaining[i];
				if(tot > 0) {
					int tw = min(width, tot * 20);
					int step = tw / tot;

					vec2i pos(iconPos.center.x - tw/2, iconPos.topLeft.y - 10);
					for(uint i = 0; i < rCnt; ++i) {
						Sprite sprt = getRequirementIcon(reqs.reqs[i]);
						for(uint n = 0, ncnt = remaining[i]; n < ncnt; ++n) {
							sprt.draw(recti_area(pos, vec2i(20)));
							pos.x += step;
						}
					}
				}
			}
			if(mode == PM_MONEY && income != 0) {
				const Font@ ft = font::DroidSans_11_Bold;
				if(income == -100)
					@ft = font::DroidSans_10;
				recti area = recti_area(vec2i(startPos.x, iconPos.topLeft.y - 8), vec2i(width, 20));
				Color color = colors::Red;
				if(income > 0)
					color = colors::Green;
				else if(income == 0)
					color = Color(0xaaaaaaff);
				ft.draw(pos=area+vec2i(-1,-1), text=moneyText, color=colors::Black, horizAlign=0.5);
				ft.draw(pos=area+vec2i(1,-1), text=moneyText, color=colors::Black, horizAlign=0.5);
				ft.draw(pos=area+vec2i(-1,1), text=moneyText, color=colors::Black, horizAlign=0.5);
				ft.draw(pos=area+vec2i(1,1), text=moneyText, color=colors::Black, horizAlign=0.5);
				ft.draw(pos=area, text=moneyText, color=color, horizAlign=0.5);
			}
			if(production !is null) {
				int tot = 0;
				for(uint i = 0; i < TR_COUNT; ++i) {
					if(production[i] > 0.0)
						tot += 1;
				}
				if(tot > 0) {
					int tw = min(width, tot * 40);
					int step = tw / tot;

					vec2i pos(iconPos.center.x - tw/2, iconPos.topLeft.y - 16);
					for(uint i = 0; i < TR_COUNT; ++i) {
						double amt = production[i];
						if(amt > 0) {
							Sprite sprt = getTileResourceSprite(i);
							sprt.draw(recti_area(pos, vec2i(20)));
							string text = standardize(amt, true);
							const Font@ ft = font::DroidSans_11_Bold;
							recti area = recti_area(pos+vec2i(18,-1), vec2i(24));
							Color color = getTileResourceColor(i);
							ft.draw(pos=area+vec2i(-1,-1), text=text, color=colors::Black, horizAlign=0.5);
							ft.draw(pos=area+vec2i(1,-1), text=text, color=colors::Black, horizAlign=0.5);
							ft.draw(pos=area+vec2i(-1,1), text=text, color=colors::Black, horizAlign=0.5);
							ft.draw(pos=area+vec2i(1,1), text=text, color=colors::Black, horizAlign=0.5);
							ft.draw(pos=area, text=text, color=color, horizAlign=0.5);

							pos.x += step;
						}
					}
				}
			}
			if(numTotal != -1) {
				recti area = recti_area(vec2i(startPos.x - 20, iconPos.topLeft.y - 8), vec2i(width+40, 20));
				string txt = format("$1/$2", toString(numUsed), toString(numTotal));
				Color baseColor(0xaaaaaaff);
				const Font@ ft = font::DroidSans_11_Bold;
				if(mode == PM_TILES) {
					if(numTotal < 50)
						@ft = font::DroidSans_8;
					else if(numTotal < 90)
						@ft = font::DroidSans_10;
					else if(numTotal < 150)
						@ft = font::DroidSans_11;
					else
						baseColor = colors::Green;
				}
				else {
					if(numUsed < numTotal)
						baseColor = colors::Green;
					else
						baseColor = colors::Red;
				}
				Color color;
				if(numTotal != 0)
					color = baseColor.interpolate(colors::Orange, float(numUsed) / float(numTotal));
				ft.draw(pos=area, text=txt, color=color, horizAlign=0.5, stroke=colors::Black);
			}
		}
	}

	void drawPlanet(const recti& pos) {
		if(isPrimary) {
			if(primary !is null) {
				if(obj.isPlanet)
					drawPlanetIcon(cast<Planet>(obj), pos, primary, showType = SHOW_PLANETS);
				else
					drawObjectIcon(obj, pos, primary);
			}
			else
				drawObjectIcon(obj, pos);
		}
		else if(primary !is null) {
			drawSmallResource(primary.type, primary,
					pos.padded(0.3 * pos.width, 0.3 * pos.height),
					obj, onPlanet=true);
		}
	}

	void dump(string prefix) {
		print(prefix+"-- "+obj.name);
		for(uint i = 0, cnt = children.length; i < cnt; ++i)
			children[i].dump(prefix+"   ");
	}

	int opCmp(const PlanetElement@ other) const {
		if(focused && !other.focused)
			return 1;
		if(other.focused && !focused)
			return -1;
		//Sort no resources last
		if(other.resource is null) {
			if(resource is null)
				return 0;
			else
				return 1;
		}
		else {
			if(resource is null)
				return -1;
		}
		//Sort by level
		if(level < other.level)
			return -1;
		else if(level > other.level)
			return 1;
		if(resource.level < other.resource.level)
			return -1;
		else if(resource.level > other.resource.level)
			return 1;
		if(resource.id < other.resource.id)
			return -1;
		else if(resource.id > other.resource.id)
			return 1;
		if(obj.id < other.obj.id)
			return -1;
		else if(obj.id > other.obj.id)
			return 1;
		return 0;
	}
}

class PlanetTree : BaseGuiElement {
	MarkupTooltip@ tip;
	array<PlanetElement@> planets;

	Object@ focusObject;
	bool showExcess = true;

	PlanetPopup@ popup;
	PlanetModes mode = PM_NORMAL;
	PlanetElement@ focusEle;
	PlanetElement@ hovered;
	PlanetElement@ covered;
	PlanetElement@ dragging;
	recti dragElemStart;
	vec2i dragMouseStart;

	bool heldLeft = false;
	bool isDragging = false;
	bool moved = false;
	vec2d scroll;
	vec2i dragStart;
	vec2i prevScroll;

	int totalWidth = 0;
	int totalHeight = 0;

	PlanetTree(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		_PlanetTree();
	}

	PlanetTree(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		_PlanetTree();
	}

	~PlanetTree() {
		if(popup !is null) {
			popup.visible = false;
			popup.remove();
			@popup = null;
		}
	}

	void _PlanetTree() {
		@popup = PlanetPopup(null);
		popup.mouseLinked = true;
		popup.visible = false;

		@tip = MarkupTooltip("", width=400, delay=0.f);
		tip.wrapAroundElement = false;
	}
	
	void remove() {
		if(popup !is null) {
			popup.visible = false;
			popup.remove();
			@popup = null;
		}
		for(uint i = 0, cnt = planets.length; i < cnt; ++i)
			planets[i].clear();
		planets.length = 0;
		BaseGuiElement::remove();
	}

	bool shouldShow(PlanetElement@ elem){ 
		if(focusObject !is null && elem.obj !is focusObject) {
			if(showExcess && elem.excess)
				return true;
			return false;
		}
		return true;
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		if(focusEle !is null) {
			focusEle.minWidth = size.width - 20;
			focusEle.calc();
		}
	}

	vec2i prevMousePos = vec2i();
	bool prevVisible = false;
	double timer = 1.0;
	void tick(double time) {
		if(!actuallyVisible) {
			if(popup !is null && popup.visible)
				popup.visible = false;
			prevVisible = false;
			return;
		}
		timer += time;
		if(timer >= 1.0) {
			if(dragging is null)
				update();
			timer = 0.0;
		}
		if(prevMousePos != mousePos) {
			updateHover();
			prevMousePos = mousePos;
		}
		if(!prevVisible) {
			while(progressing)
				progressUpdate();
		}
		else {
			progressUpdate();
		}
		popup.update();
		prevVisible = true;
	}

	map elemLookup;
	array<Object@> list;
	array<PlanetElement@> allElems;
	bool progressing = false;
	uint progressIndex = 0;
	bool forceProgress = false;
	array<Resource> resources;

	void progressUpdate(bool force = false) {
		if(!progressing)
			return;
		if(forceProgress)
			force = true;
		timer = 0.0;
		if(progressIndex < list.length) {
			//First pass: generate planet elements
			uint count = min(list.length/10, 10);
			if(force)
				count = list.length;
			count = max(count, 1);
			for(uint n = 0; n < count; ++n) {
				uint i = progressIndex++;
				if(i >= list.length)
					break;
				Object@ pl = list[i];
				if(pl is null)
					continue;

				resources.syncFrom(pl.getNativeResources());
				for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
					if(i != 0 && resources[i].exportedTo !is null)
						continue;
					PlanetElement ele;
					@ele.obj = pl;
					ele.mode = mode;

					if(ele.obj is focusObject && i == 0) {
						@focusEle = ele;
						ele.focused = true;
						ele.minWidth = size.width - 20;
					}
					ele.showChildren = focusObject is null || ele.root.obj is focusObject;

					ele.cache(resources[i], i == 0);

					allElems.insertLast(ele);
					if(i == 0)
						elemLookup.set(pl.id, @ele);
				}
				if(resources.length == 0) {
					PlanetElement ele;
					@ele.obj = pl;
					ele.mode = mode;

					if(ele.obj is focusObject && i == 0) {
						@focusEle = ele;
						ele.focused = true;
						ele.minWidth = size.width - 20;
					}
					ele.showChildren = focusObject is null || ele.root.obj is focusObject;

					ele.cache(null, true);

					allElems.insertLast(ele);
					elemLookup.set(pl.id, @ele);
				}
			}
			if(!force)
				return;
		}

		progressing = false;
		forceProgress = false;
		planets.length = 0;
		planets.reserve(allElems.length);

		//Second pass: create proper child relations
		for(uint i = 0, cnt = allElems.length; i < cnt; ++i) {
			PlanetElement@ ele = allElems[i];
			if(ele.parentObject !is null) {
				PlanetElement@ other;
				elemLookup.get(ele.parentObject.id, @other);

				//Break cycles
				auto@ check = other;
				while(check !is null) {
					if(check is ele) {
						@other = null;
						break;
					}
					@check = check.parent;
				}

				//Add in the right spot
				if(other !is null) {
					@ele.parent = other;
					other.children.insertLast(ele);
				}
				else {
					@ele.parentObject = null;
					planets.insertLast(ele);
				}
			}
			else {
				planets.insertLast(ele);
			}
		}

		if(focusEle !is null && !shouldShow(focusEle.root))
			planets.insertLast(focusEle);

		//Third pass: sort
		planets.sortDesc();
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			planets[i].sort();
			planets[i].calc();
		}
		updateHover();
	}

	void update(bool force = false) {
		if(progressing && !force)
			return;

		if(force)
			forceProgress = true;

		progressing = true;
		list.length = 0;
		elemLookup.deleteAll();
		allElems.length = 0;

		{
			Object@ obj;

			DataList@ objs = playerEmpire.getPlanets();
			while(receive(objs, obj))
				list.insertLast(obj);

			DataList@ roids = playerEmpire.getAsteroids();
			while(receive(roids, obj)) {
				if(obj.nativeResourceCount != 0)
					list.insertLast(obj);
			}
		}

		allElems.reserve(list.length);
		progressIndex = 0;
	}

	void updateHover() {
		auto@ newHover = planetFromPosition(mousePos - AbsolutePosition.topLeft);
		if(newHover !is hovered) {
			if(hovered !is null)
				hovered.hovered = false;
			if(newHover !is null)
				newHover.hovered = true;
			@hovered = newHover;
		}
		if(hovered !is null) {
			if(dragging !is null && dragging !is hovered)
				hovered.hoverColor = COLOR_DROP;
			else
				hovered.hoverColor = COLOR_HOVER;
		}
		@covered = planetFromPosition(mousePos - AbsolutePosition.topLeft, strict=false);
		if(popup !is null) {
			popup.visible = hovered !is null && dragging is null && hovered.obj !is null && hovered.obj.isPlanet;
			if(popup.visible) {
				popup.set(hovered.obj);
				popup.updatePosition(hovered.obj);
				tip.offset.y = 140;
			}
			else {
				tip.offset.y = 0;
			}
		}
		else {
			tip.offset.y = 0;
		}
	}

	void center() {
		scroll.x = double(totalWidth - size.width) / 2.0;
		scroll.y = double(totalHeight - size.height + 40) / 2.0;
		scroll.x = clamp(scroll.x, 0.0, max(double(totalWidth - size.width), 0.0));
		scroll.y = clamp(scroll.y, 0.0, max(double(totalHeight - size.height + 60.0), 0.0));
	}

	void scrollPane(double dx, double dy) {
		scroll -= vec2d(dx, dy);
		scroll.x = clamp(scroll.x, 0.0, max(double(totalWidth - size.width), 0.0));
		scroll.y = clamp(scroll.y, 0.0, max(double(totalHeight - size.height + 60.0), 0.0));
	}

	PlanetElement@ planetFromPosition(const vec2i& offset, bool strict = true) {
		if(offset.y > size.height)
			return null;
		vec2i pos = vec2i(12,16) - vec2i(scroll);
		vec2i origPos = pos;
		int lineHeight = 0;
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			auto@ pl = planets[i];
			if(!shouldShow(pl))
				continue;
			if(pl.width + pos.x - origPos.x > size.width - 24) {
				pos = vec2i(origPos.x, pos.y + lineHeight + 20);
				lineHeight = 0;
			}
			PlanetElement@ elem = planets[i].planetFromPosition(pos, offset, strict);
			if(elem !is null)
				return elem;
			if(pl.height > lineHeight)
				lineHeight = pl.height;
			pos += vec2i(pl.width+20, 0);
		}
		return null;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Focus_Lost) {
			if(!isAncestorOf(event.caller)) {
				heldLeft = false;
				isDragging = false;
				@dragging = null;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void stopDragging() {
		heldLeft = false;
		isDragging = false;
		@dragging = null;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case MET_Button_Down:
				if(event.button == 0 && source is this) {
					if(hovered !is null) {
						if(!hovered.locked) {
							@dragging = hovered;
							dragMouseStart = mousePos;
						}
						else {
							@dragging = null;
						}
					}
					else {
						heldLeft = true;
						dragStart = vec2i(event.x, event.y);
					}
					return true;
				}
			break;
			case MET_Moved: {
				vec2i mouse = vec2i(event.x, event.y);
				vec2i d = mouse - dragStart;
				updateHover();
				if(isDragging || dragging !is null) {
					if(!mouseLeft)
						stopDragging();
				}
				if(isDragging) {
					scrollPane(d.x, d.y);
					dragStart = mouse;
					moved = true;
				}
				else if(heldLeft) {
					if(abs(d.x) >= 5 || abs(d.y) >= 5) {
						isDragging = true;
						moved = true;
						scrollPane(d.x, d.y);
						dragStart = mouse;
					}
				}
			} break;
			case MET_Button_Up:
				if(event.button == 0) {
					bool wasDragging = isDragging || dragging !is null;
					if(dragging !is null) {
						if(dragMouseStart.distanceTo(mousePos) <= 6) {
							if(hovered !is null)
								hovered.click(0);
						}
						else if(hovered !is null && hovered !is dragging) {
							if(selectedObjects.length > 1 && dragging.obj.selected) {
								for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i) {
									if(selectedObjects[i].hasResources)
										selectedObjects[i].exportResource(0, hovered.obj);
								}
							}
							else
								dragging.export(hovered);
						}
						else if(dragElemStart.distanceTo(mousePos) > 50
								&& covered is null) {
							if(selectedObjects.length > 1 && dragging.obj.selected) {
								for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i) {
									if(selectedObjects[i].hasResources)
										selectedObjects[i].exportResource(0, null);
								}
							}
							else
								dragging.export(null);
						}
						@dragging = null;
						update(force=true);
						timer = 0.08;
						return true;
					}
					else {
						if(!isDragging) {
							if(hovered !is null) {
								hovered.click(0);
							}
							else
								selectObject(null);
						}
						heldLeft = false;
						isDragging = false;
						dragStart = vec2i();
					}
					if(source is this || wasDragging)
						return true;
				}
				else {
					if(hovered !is null) {
						hovered.click(event.button);
						return true;
					}
				}
			break;
			case MET_Scrolled:
				if(source is this) {
					if(totalHeight > size.height)
						scrollPane(0, 20*event.y);
					else if(totalWidth > size.width)
						scrollPane(20*event.y, 0);
				}
			break;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		if(dragging !is null && hovered is null
				&& dragElemStart.distanceTo(mousePos) > 50
				&& covered is null) {
			drawRectangle(recti_area(mousePos - vec2i(50), vec2i(100)), COLOR_CLEAR);
		}

		vec2i pos = AbsolutePosition.topLeft + vec2i(12,16) - vec2i(scroll);
		vec2i origPos = pos;
		int lineHeight = 0;
		totalWidth = 0;
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			auto@ pl = planets[i];
			if(!shouldShow(pl))
				continue;
			if(pl.width + pos.x - origPos.x > size.width - 24) {
				totalWidth = max(pos.x - origPos.x, totalWidth);
				pos = vec2i(origPos.x, pos.y + lineHeight + 20);
				lineHeight = 0;
			}
			if(pl is dragging)
				dragElemStart = pl.getFullPos(pos);
			pl.drawTree(pos);
			if(pl.height > lineHeight)
				lineHeight = pl.height;
			pos += vec2i(pl.width+20, 0);
		}
		totalWidth = max(pos.x - origPos.x, totalWidth);
		totalHeight = pos.y + lineHeight - origPos.y;
		clearClip();
		if(dragging !is null) {
			vec2i pos = vec2i(mousePos.x - dragging.width/2, mousePos.y-ICON_SIZE/2);
			if(dragMouseStart.distanceTo(mousePos) > 6)
				dragging.drawTree(pos);
		}
		if(hovered !is null && hovered.primary !is null) {
			tip.text = hovered.getTooltip();

			vec2i mpos = mousePos;
			vec2i offset(10, 0);
			if(mpos.x + 300 > screenSize.x)
				offset.x -= 350;
			int h = popup.visible ? popup.size.height+4 : 0;
			h += tip.height + 20;
			if(mpos.y + h > screenSize.y)
				offset.y -= (h - (screenSize.y - mpos.y));
			if(popup.visible) {
				popup.mouseOffset = offset;
				tip.offset = offset + vec2i(16, popup.size.height+4);
			}
			else {
				tip.offset = offset + vec2i(16, 0);
			}

			tip.draw(skin, this);
		}
		BaseGuiElement::draw();
	}
};

class PlanetsTab : Tab {
	PlanetTree@ tree;

	GuiButton@ normalMode;
	GuiButton@ moneyMode;
	GuiButton@ productionMode;
	GuiButton@ reqsMode;
	GuiButton@ tilesMode;
	GuiButton@ pressureMode;

	GuiButton@ bgButton;

	GuiTextbox@ searchBar;

	GuiSkinElement@ bar;

	PlanetsTab() {
		super();
		title = locale::PLANETS_TAB;

		@tree = PlanetTree(this, Alignment().padded(0,0,0,50));
		@bar = GuiSkinElement(this, Alignment(Left-4, Bottom-42, Right+4, Bottom+4), SS_PlanetBar);

		int w = 160;
		int c = 6;
		int off = (c * w) / 2;
		@normalMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_NORMAL);
		normalMode.buttonIcon = Sprite(spritesheet::MenuIcons, 0);
		normalMode.toggleButton = true;
		normalMode.pressed = true;
		off -= w;

		@moneyMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_MONEY);
		moneyMode.buttonIcon = icons::Money;
		moneyMode.toggleButton = true;
		moneyMode.pressed = false;
		off -= w;

		@productionMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_PRODUCTION);
		productionMode.buttonIcon = icons::Add;
		productionMode.toggleButton = true;
		productionMode.pressed = false;
		off -= w;

		@reqsMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_REQS);
		reqsMode.buttonIcon = Sprite(spritesheet::ResourceClassIcons, 0);
		reqsMode.toggleButton = true;
		reqsMode.pressed = false;
		off -= w;

		@pressureMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_PRESSURE);
		pressureMode.buttonIcon = icons::Pressure;
		pressureMode.toggleButton = true;
		pressureMode.pressed = false;
		pressureMode.disabled = playerEmpire.HasPopulation == 0;
		off -= w;

		@tilesMode = GuiButton(bar, Alignment(Left+0.5f-off, Top+4, Width=w, Height=34), locale::PLANETS_MODE_TILES);
		tilesMode.buttonIcon = Sprite(spritesheet::PlanetType, 0);
		tilesMode.toggleButton = true;
		tilesMode.pressed = false;
		off -= w;

		@bgButton = GuiButton(bar, Alignment(Right-38, Top+4, Width=34, Height=34));
		GuiSprite sprt(bgButton, Alignment().padded(4), Sprite(spritesheet::PlanetType, 2));
		bgButton.toggleButton = true;
		bgButton.pressed = true;
	}

	void show() {
		tree.update();
		Tab::show();
	}

	void hide() {
		if(previous !is null)
			popTab(this);
		Tab::hide();
	}

	Color get_activeColor() {
		return Color(0xdafc4eff);
	}

	Color get_inactiveColor() {
		return Color(0xccff00ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x798c2bff);
	}

	Sprite get_icon() {
		return Sprite(material::TabPlanets);
	}

	TabCategory get_category() {
		return TC_Planets;
	}

	void tick(double time) override {
		tree.tick(time);
		if(!visible)
			return;
		if(!tree.isDragging && settings::bEdgePan && windowFocused && mouseOverWindow) {
			if(mousePos.x <= 2) {
				tree.scrollPane(+1000.0 * time, 0);
			}
			else if(mousePos.x >= screenSize.width - 2) {
				tree.scrollPane(-1000.0 * time, 0);
			}
			if(mousePos.y <= 2) {
				tree.scrollPane(0, +1000.0 * time);
			}
			else if(mousePos.y >= screenSize.height - 2) {
				tree.scrollPane(0, -1000.0 * time);
			}
		}
	}

	void switchMode(PlanetModes mode) {
		normalMode.pressed = mode == PM_NORMAL;
		moneyMode.pressed = mode == PM_MONEY;
		productionMode.pressed = mode == PM_PRODUCTION;
		reqsMode.pressed = mode == PM_REQUIREMENTS;
		tilesMode.pressed = mode == PM_TILES;
		pressureMode.pressed = mode == PM_PRESSURE;
		if(tree.mode != mode) {
			tree.mode = mode;
			tree.update();
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is normalMode) {
				switchMode(PM_NORMAL);
				return true;
			}
			if(event.caller is moneyMode) {
				switchMode(PM_MONEY);
				return true;
			}
			if(event.caller is productionMode) {
				switchMode(PM_PRODUCTION);
				return true;
			}
			if(event.caller is reqsMode) {
				switchMode(PM_REQUIREMENTS);
				return true;
			}
			if(event.caller is tilesMode) {
				switchMode(PM_TILES);
				return true;
			}
			if(event.caller is pressureMode) {
				switchMode(PM_PRESSURE);
				return true;
			}
			if(event.caller is bgButton) {
				SHOW_PLANETS = bgButton.pressed;
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createPlanetsTab() {
	return PlanetsTab();
}
