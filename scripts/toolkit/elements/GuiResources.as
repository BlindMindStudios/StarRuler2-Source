#section disable menu
import elements.BaseGuiElement;
import elements.GuiText;
import elements.MarkupTooltip;
import elements.GuiIconGrid;
import resources;
import util.formatting;
import planet_levels;

export GuiResources, GuiResourceRequirements;
export GuiResourceGrid, GuiResourceReqGrid;
export drawResource, drawSmallResource;
export getAutoImportIcon;
export getRequirementIcon;

const ResourceClass@ foodClass;
const ResourceClass@ waterClass;
const ResourceType@ waterType;
const ResourceClass@ scalableClass;
void init() {
	@foodClass = getResourceClass("Food");
	@scalableClass = getResourceClass("Scalable");
	@waterClass = getResourceClass("WaterType");
	@waterType = getResource("Water");
}

void drawResource(const ResourceType@ type, const recti& pos) {
	type.icon.draw(pos);

	//Affinities
	uint affCnt = type.affinities.length;
	for(uint i = 0; i < affCnt; ++i) {
		recti affPos = recti_area(vec2i(pos.topLeft.x, pos.botRight.y-i*20-20), vec2i(20, 20));
		getAffinitySprite(type.affinities[i]).draw(affPos);
	}

	//Resource level icon
	if(type.level > 0 && type.level <= 3)
		spritesheet::ResourceIconsMods.draw(2+type.level, pos);

	//Resource class icon
	else if(type.cls is foodClass)
		spritesheet::ResourceIconsMods.draw(6, pos);
}

void drawResource(const Resource@ r, const recti& pos, Object@ drawFrom = null, const Font@ ft = null) {
	const ResourceType@ type = r.type;

	//Origin underlay
	if(r.origin is drawFrom && r.origin !is null) {
		spritesheet::ResourceIconsMods.draw(0, pos);

		//Rarity
		if(type.rarity > 0)
			spritesheet::ResourceIconsMods.draw(6+type.rarity, pos);
	}

	drawResource(r.type, pos);

	if(r.origin is null || r.origin.owner is playerEmpire) {
		//Disabled overlay
		if(!r.usable)
			spritesheet::ResourceIconsMods.draw(2, pos);
	}

	//Export tick
	if(r.origin is drawFrom && r.exportedTo !is null && r.origin !is null && drawFrom.visible)
		spritesheet::ResourceIconsMods.draw(1, pos);

	//Vanish timer
	if(r.type.vanishMode != VM_Never && drawFrom !is null) {
		double timeLeft = r.type.vanishTime - r.vanishTime;
		if(r.exportedTo !is null)
			timeLeft /= r.exportedTo.resourceVanishRate;
		else if(r.origin !is null)
			timeLeft /= r.origin.resourceVanishRate;
		font::DroidSans_11_Bold.draw(pos.topLeft+vec2i(4, 4),
				formatShortTime(timeLeft),
				Color(0xffbb00ff));
	}
}

void drawSmallResource(const ResourceType@ type, const Resource@ r, const recti& pos, Object@ drawFrom = null, bool onPlanet = false) {
	if(r !is null) {
		//Origin underlay
		if(r.origin is drawFrom && r.origin !is null && !onPlanet) {
			spritesheet::ResourceIconsSmallMods.draw(0, pos.padded(-2));

			//Rarity
			if(type.rarity > 0)
				spritesheet::ResourceIconsSmallMods.draw(10, pos.padded(-2), getResourceRarityColor(type.rarity));
		}

		if(drawFrom !is null && !r.usable && r.origin is null) {
			if(r.type.cls is foodClass) {
				FOOD_REQ.draw(pos);
			}
			else if(r.type.cls is waterClass) {
				WATER_REQ.draw(pos);
			}
			else if(r.type.level < LEVEL_REQ.length) {
				LEVEL_REQ[r.type.level].draw(pos);
			}
			else {
				UNKNOWN_REQ.draw(pos);
			}
		}
		else {
			type.smallIcon.draw(pos);
		}

		bool lowPop = false;
		if(drawFrom !is null) {
			if(!r.usable) {
				if(r.origin is null) {
					//Queued auto-import
					spritesheet::ResourceIconsSmallMods.draw(13, pos.padded(-2), Color(0xf800ffff));
				}
				else if(drawFrom.owner is playerEmpire || drawFrom !is r.origin) {
					if(r.origin.owner !is playerEmpire) {
						//Queued import
						spritesheet::ResourceIconsSmallMods.draw(13, pos.padded(-2), Color(0xffe400ff));
					}
					else {
						if(r.origin.hasSurfaceComponent && r.origin.resourceLevel >= r.type.level &&
								r.origin.population < getPlanetLevelRequiredPop(r.origin, r.type.level)) {
							//Insufficient population
							spritesheet::ResourceIconsSmallMods.draw(13, pos.padded(-4), Color(0xff6300ff));
							lowPop = true;
						}
						else {
							//Disabled
							spritesheet::ResourceIconsSmallMods.draw(2, pos.padded(-4));
						}
					}
				}
			}
			else if(r.origin is drawFrom && r.origin.hasSurfaceComponent) {
				lowPop = r.origin.resourceLevel > r.origin.level;
				if(lowPop && !r.type.artificial) {
					//Insufficient population
					spritesheet::ResourceIconsSmallMods.draw(13, pos.padded(-4), Color(0xff6300ff));
				}
			}
		}

		//Resource level icon
		if(type.level > 0 && type.level <= 3)
			spritesheet::ResourceIconsSmallMods.draw(3+type.level, pos.padded(-2));

		//Resource class icon
		else if(type.cls is foodClass)
			spritesheet::ResourceIconsSmallMods.draw(7, pos.padded(-2));
		else if(type.cls is scalableClass)
			spritesheet::ResourceIconsSmallMods.draw(16, pos.padded(-2));

		//Export tick
		if(r.origin !is null && r.origin is drawFrom && r.exportedTo !is null && drawFrom.visible)
			spritesheet::ResourceIconsSmallMods.draw(1, pos.padded(-2));

		//Excess tick
		if(r.exportedTo is null && r.origin !is null && r.usable && !lowPop) {
			if(r.origin.owner is playerEmpire && r.origin.hasSurfaceComponent && !r.type.isMaterial(r.origin.level) && r.origin.exportEnabled)
				spritesheet::ResourceIconsSmallMods.draw(3, pos.padded(-2));
		}

		//Lock icon
		if(drawFrom is null || r.origin is drawFrom) {
			if(r.locked)
				spritesheet::ResourceIconsSmallMods.draw(15, pos.padded(-2));
			else if(type.willLock)
				spritesheet::ResourceIconsSmallMods.draw(14, pos.padded(-2));
		}
	}
	else {
		type.smallIcon.draw(pos);

		//Resource level icon
		if(type.level > 0 && type.level <= 3)
			spritesheet::ResourceIconsSmallMods.draw(3+type.level, pos.padded(-2));

		//Resource class icon
		else if(type.cls is foodClass)
			spritesheet::ResourceIconsSmallMods.draw(7, pos.padded(-2));
		else if(type.cls is scalableClass)
			spritesheet::ResourceIconsSmallMods.draw(16, pos.padded(-2));

		//Lock icon
		if(type.willLock)
			spritesheet::ResourceIconsSmallMods.draw(14, pos.padded(-2));
	}
}

class GuiResourceRequirements : BaseGuiElement {
	GuiText@[] text;
	GuiResources@[] resources;

	GuiResourceRequirements(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
	}

	GuiResourceRequirements(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
	}

	void set(const ResourceRequirements@ reqs, const Resources@ available = null, bool allowUniversal = true) {
		//Do calculations
		array<int>@ remaining = null;
		if(available !is null) {
			@remaining = array<int>();
			reqs.satisfiedBy(available, null, allowUniversal, remaining);
		}

		//Remove previous
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			resources[i].remove();
		resources.length = 0;
		for(uint i = 0, cnt = text.length; i < cnt; ++i)
			text[i].remove();
		text.length = 0;

		//Add all groups
		uint rCnt = reqs.reqs.length;
		int x = 0;
		int rsize = size.height - 15;
		for(uint i = 0; i < rCnt; ++i) {
			const ResourceRequirement@ req = reqs.reqs[i];
			int amount = req.amount;
			if(remaining !is null)
				amount = remaining[i];
			if(amount == 0)
				continue;

			GuiResources r(this, recti());
			string caption;

			//Find which resources and caption to display
			switch(req.type) {
				case RRT_Resource:
					r.types.insertLast(req.resource);
					caption = toString(amount)+"x";
				break;
				case RRT_Class:
					for(uint i = 0, cnt = req.cls.types.length; i < cnt; ++i) {
						const ResourceType@ restype = req.cls.types[i];
						if(!restype.exportable || restype.mode != RM_Normal || !restype.requirementDisplay)
							continue;
						r.types.insertLast(restype);
					}
					if(r.types.length == 1)
						caption = toString(amount)+"x";
					else
						caption = format(locale::RESOURCES_OF, toString(amount));
				break;
				case RRT_Class_Types:
					for(uint i = 0, cnt = req.cls.types.length; i < cnt; ++i) {
						const ResourceType@ restype = req.cls.types[i];
						if(!restype.exportable || restype.mode != RM_Normal || !restype.requirementDisplay)
							continue;
						if(available !is null && available.getAmount(restype) != 0)
							continue;
						r.types.insertLast(restype);
					}
					if(r.types.length == 1)
						caption = toString(amount)+"x";
					else
						caption = format(locale::TYPES_OF, toString(amount));
				break;
				case RRT_Level:
					for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
						const ResourceType@ res = getResource(i);
						if(!res.exportable || res.mode != RM_Normal || !res.requirementDisplay)
							continue;
						if(res.level == req.level)
							r.types.insertLast(res);
					}
					if(r.types.length == 1)
						caption = toString(amount)+"x";
					else
						caption = format(locale::RESOURCES_OF, toString(amount));
				break;
				case RRT_Level_Types:
					for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
						const ResourceType@ res = getResource(i);
						if(res.level != req.level)
							continue;
						if(!res.exportable || res.mode != RM_Normal || !res.requirementDisplay)
							continue;
						if(available !is null && available.getAmount(res) != 0)
							continue;
						r.types.insertLast(res);
					}
					if(r.types.length == 1)
						caption = toString(amount)+"x";
					else
						caption = format(locale::TYPES_OF, toString(amount));
				break;
			}

			if(r.types.length == 0) {
				r.remove();
				continue;
			}
			
			//Scrunch icons if multiple
			int w = 0;
			if(r.types.length == 1)
				w = rsize;
			else
				w = (float(rsize) * 0.9f) * float(r.types.length);

			//Create the caption
			GuiText ctext(this, Alignment(Left+x, Top, Left+x+w, Top+15));
			ctext.horizAlign = 0.5;
			ctext.font = FT_Small;
			ctext.text = caption;
			text.insertLast(ctext);

			//Position the resources element
			r.typeMode = true;
			@r.alignment = Alignment(Left+x, Top+15, Left+x+w, Bottom);
			resources.insertLast(r);
			x += w+16;
		}
		updateAbsolutePosition();
	}

	void draw() {
		BaseGuiElement::draw();
	}
};

class GuiResources : BaseGuiElement {
	Object@ drawFrom;
	array<const ResourceType@> types;
	Resource[] resources;
	bool typeMode = false;
	bool vertical = false;
	bool shrink = false;
	double horizAlign = 0.5;
	double vertAlign = 0.5;
	int spacing = 0;
	int hovered = -1;

	GuiResources(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
		_GuiResources();
	}

	GuiResources(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
		_GuiResources();
	}

	void _GuiResources() {
		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	uint get_length() {
		if(typeMode)
			return types.length;
		else
			return resources.length;
	}

	string get_tooltip() {
		if(hovered < 0 || hovered >= int(length))
			return "";

		Resource@ r;
		const ResourceType@ type;
		if(typeMode) {
			@type = types[hovered];
		}
		else {
			@r = resources[hovered];
			@type = r.type;
		}

		return getResourceTooltip(type, r, drawFrom);
	}

	void calcOffset(vec2i& pos, vec2i& offset, vec2i& rsize) {
		uint cnt = length;
		uint isize = min(size.width, size.height);
		rsize = vec2i(isize, isize);
		pos = vec2i();
		offset = vec2i();

		if(vertical) {
			pos.x = double(size.width - isize) * horizAlign;

			int tot = (isize + spacing) * cnt - spacing;
			if(tot < size.height) {
				pos.y = double(size.height - tot) * vertAlign;
				offset.y = isize + spacing;
			}
			else {
				if(shrink) {
					isize = double(size.height) / double(cnt);
					rsize.x = isize;
					rsize.y = isize;
					offset.y = isize;
				}
				else if(cnt > 1) {
					offset.y = double(size.height - isize) / double(cnt - 1);
				}
				else {
					offset.y = isize;
				}
			}
		}
		else {
			pos.y = double(size.height - isize) * vertAlign;

			int tot = (isize + spacing) * cnt - spacing;
			if(tot < size.width) {
				pos.x = double(size.width - tot) * horizAlign;
				offset.x = isize + spacing;
			}
			else {
				if(shrink) {
					isize = double(size.width) / double(cnt);
					rsize.x = isize;
					rsize.y = isize;
					offset.x = isize;
				}
				else if(cnt > 1) {
					offset.x = double(size.width - isize) / double(cnt - 1);
				}
				else {
					offset.x = isize;
				}
			}
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Left:
					hovered = -1;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Moved: {
					int prevHovered = hovered;
					hovered = getOffsetItem(mousePos - AbsolutePosition.topLeft);
					if(prevHovered != hovered)
						tooltipObject.update(skin, this);
				} break;
				case MET_Button_Down:
					if(hovered != -1)
						return true;
				break;
				case MET_Button_Up:
					if(hovered != -1) {
						if(event.button == 2 && uint(hovered) < resources.length)
							zoomTo(resources[hovered].origin);
						emitClicked(event.button);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	int getOffsetItem(const vec2i& off) {
		vec2i pos, ioff, rsize, offset = off;
		calcOffset(pos, ioff, rsize);

		offset -= pos;
		if(offset.x < 0 || offset.y < 0)
			return -1;

		int num = 0;
		if(vertical) {
			num = floor(double(offset.y) / double(ioff.y));
			if(offset.y - (num * ioff.y) > rsize.y)
				return -1;
		}
		else {
			num = floor(double(offset.x) / double(ioff.x));
			if(offset.y - (num * ioff.y) > rsize.y)
				return -1;
		}

		if(num >= int(length))
			return -1;
		return num;
	}

	void draw() {
		vec2i pos, offset, rsize;
		calcOffset(pos, offset, rsize);

		vec2i hovPos;
		const Font@ ft = skin.getFont(FT_Normal);
		if(rsize.width < 32)
			@ft = skin.getFont(FT_Small);

		//Draw everything but the hovered resource
		for(uint i = 0, cnt = length; i < cnt; ++i) {
			if(hovered != int(i)) {
				if(typeMode)
					drawResource(types[i], recti_area(pos + AbsolutePosition.topLeft, rsize));
				else
					drawResource(resources[i], recti_area(pos + AbsolutePosition.topLeft, rsize), drawFrom, ft);
			}
			else
				hovPos = pos;
			pos += offset;
		}

		//Draw hovered last so it's on top
		if(hovered != -1 && uint(hovered) < this.length) {
			if(typeMode)
				drawResource(types[hovered], recti_area(hovPos + AbsolutePosition.topLeft, rsize));
			else
				drawResource(resources[hovered], recti_area(hovPos + AbsolutePosition.topLeft, rsize), drawFrom, ft);
		}
		BaseGuiElement::draw();
	}
};

class GuiResourceGrid : GuiIconGrid {
	Object@ drawFrom;
	array<const ResourceType@> types;
	Resource[] resources;
	bool typeMode = false;
	bool singleMode = false;

	GuiResourceGrid(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
		_GuiResourceGrid();
	}

	GuiResourceGrid(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
		_GuiResourceGrid();
	}

	void _GuiResourceGrid() {
		iconSize = vec2i(21, 21);
		spacing = vec2i(5, 5);
		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	uint get_length() override {
		if(typeMode)
			return types.length;
		else
			return resources.length;
	}

	void setSingleMode(bool mode = true, double align = 0.5) {
		singleMode = mode && length == 1;
		forceHover = singleMode;
		horizAlign = singleMode ? 0.0 : align;
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Clicked:
					if(uint(hovered) < resources.length) {
						if(event.value == 2) {
							zoomTo(resources[hovered].origin);
							return true;
						}
					}
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";

		Resource@ r;
		const ResourceType@ type;
		if(typeMode) {
			@type = types[hovered];
		}
		else {
			@r = resources[hovered];
			@type = r.type;
		}

		return getResourceTooltip(type, r, drawFrom);
	}

	void drawElement(uint i, const recti& pos) override {
		clearClip();
		if(typeMode)
			drawSmallResource(types[i], null, pos, drawFrom);
		else
			drawSmallResource(resources[i].type, resources[i], pos, drawFrom);
	}

	void draw() override {
		GuiIconGrid::draw();

		if(singleMode && length == 1) {
			Resource@ r;
			const ResourceType@ type;
			if(typeMode) {
				@type = types[0];
			}
			else {
				@r = resources[0];
				@type = r.type;
			}
			if(typeMode || drawFrom is null || r.origin is drawFrom) {
				uint affCnt = type.affinities.length;

				Color textColor;
				if(!typeMode && !r.usable && r.origin.owner is playerEmpire) {
					if(r.exportedTo !is null) {
						float pct = abs((frameTime % 1.0) - 0.5f) * 2.f;
						textColor = colors::Red.interpolate(colors::Orange, pct);
					}
					else {
						textColor = colors::Red;
					}
				}

				const Font@ ft = skin.getFont(FT_Bold);
				recti pos = AbsolutePosition.padded(34, 0, 0, 0);
				ft.draw(text=type.name, ellipsis=locale::ELLIPSIS,
					pos=pos.padded(0, 0, affCnt*28, 0), vertAlign=0.5, color=textColor);

				int x = 28;
				for(uint i = 0; i < affCnt; ++i) {
					uint aff = type.affinities[i];
					getAffinitySprite(aff).draw(recti_area(vec2i(pos.botRight.x-x, pos.topLeft.y), vec2i(24, 24)));
					x += 28;
				}
			}
		}
	}
};

const Sprite FOOD_REQ(spritesheet::ResourceClassIcons, 3);
const Sprite WATER_REQ(spritesheet::ResourceClassIcons, 4);
const Sprite UNKNOWN_REQ(spritesheet::ResourceClassIcons, 5);
const Sprite[] LEVEL_REQ = {
	Sprite(),
	Sprite(spritesheet::ResourceClassIcons, 0),
	Sprite(spritesheet::ResourceClassIcons, 1),
	Sprite(spritesheet::ResourceClassIcons, 2)
};

Sprite getAutoImportIcon(const AutoImportDesc& desc) {
	if(desc.type !is null) {
		if(desc.type is waterType)
			return WATER_REQ;
		return desc.type.smallIcon;
	}
	else if(desc.cls !is null) {
		if(desc.cls is foodClass)
			return FOOD_REQ;
		else if(desc.cls is waterClass)
			return WATER_REQ;
		return Sprite();
	}
	else if(desc.level != -1 && uint(desc.level) < LEVEL_REQ.length) {
		return LEVEL_REQ[desc.level];
	}
	return UNKNOWN_REQ;
}

Sprite getRequirementIcon(const ResourceRequirement@ req) {
	switch(req.type) {
		case RRT_Resource:
			if(req.resource is waterType)
				return WATER_REQ;
			else
				return req.resource.smallIcon;
		case RRT_Class:
		case RRT_Class_Types:
			if(req.cls is foodClass)
				return FOOD_REQ;
			else if(req.cls is waterClass)
				return WATER_REQ;
			else
				return UNKNOWN_REQ;
		case RRT_Level:
		case RRT_Level_Types:
			if(req.level < LEVEL_REQ.length)
				return LEVEL_REQ[req.level];
			else
				return UNKNOWN_REQ;
	}
	return Sprite();
}

class GuiResourceReqGrid : GuiIconGrid {
	Sprite[] sprites;
	string[] tooltips;

	GuiResourceReqGrid(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
		iconSize = vec2i(26,26);
		padding = vec2i(-2);
		spacing = vec2i(1);
		noClip = true;
	}

	GuiResourceReqGrid(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
		iconSize = vec2i(26,26);
		padding = vec2i(-2);
		spacing = vec2i(1);
		noClip = true;
	}

	string get_tooltip() override {
		if(hovered < 0 || uint(hovered) >= tooltips.length)
			return "";
		return tooltips[hovered];
	}

	uint get_length() override {
		return sprites.length;
	}

	void drawElement(uint i, const recti& pos) override {
		sprites[i].draw(pos.padded(-2));
	}

	void set(const ResourceRequirements@ reqs, const Resources@ available = null, bool allowUniversal = true) {
		//Do calculations
		array<int>@ remaining = null;
		if(available !is null) {
			@remaining = array<int>();
			reqs.satisfiedBy(available, null, allowUniversal, remaining);
		}

		sprites.length = 0;
		tooltips.length = 0;

		//Add all groups
		uint rCnt = reqs.reqs.length;
		for(uint i = 0; i < rCnt; ++i) {
			const ResourceRequirement@ req = reqs.reqs[i];
			int amount = req.amount;
			if(remaining !is null)
				amount = remaining[i];
			if(amount == 0)
				continue;

			//Find which icon to display
			switch(req.type) {
				case RRT_Resource:
					for(int i = 0; i < amount; ++i) {
						if(req.resource is waterType)
							sprites.insertLast(WATER_REQ);
						else
							sprites.insertLast(req.resource.smallIcon);
						tooltips.insertLast(req.resource.name);
					}
				break;
				case RRT_Class: {
					Sprite sprt;

					if(req.cls is foodClass)
						sprt = FOOD_REQ;
					else if(req.cls is waterClass)
						sprt = WATER_REQ;
					else
						sprt = UNKNOWN_REQ;

					string tip = format(locale::REQ_TYPE, req.cls.name, getSpriteDesc(sprt))+"\n";
					for(uint i = 0, cnt = req.cls.types.length; i < cnt; ++i) {
						const ResourceType@ restype = req.cls.types[i];
						if(!restype.exportable || restype.mode != RM_Normal || !restype.requirementDisplay)
							continue;
						if(restype.frequency == 0.0 || restype.rarity >= RR_Rare)
							continue;
						tip += format("[img=$1;28/]", getSpriteDesc(restype.smallIcon));
					}

					for(int i = 0; i < amount; ++i) {
						sprites.insertLast(sprt);
						tooltips.insertLast(tip);
					}
				} break;
				case RRT_Class_Types: {
					Sprite sprt;
					if(req.cls is foodClass)
						sprt = FOOD_REQ;
					else if(req.cls is waterClass)
						sprt = WATER_REQ;
					else
						sprt = UNKNOWN_REQ;

					string tip = format(locale::REQ_TYPE_UNIQUE, req.cls.name, getSpriteDesc(sprt))+"\n";
					for(uint i = 0, cnt = req.cls.types.length; i < cnt; ++i) {
						const ResourceType@ restype = req.cls.types[i];
						if(!restype.exportable || restype.mode != RM_Normal || !restype.requirementDisplay)
							continue;
						if(restype.frequency == 0.0 || restype.rarity >= RR_Rare)
							continue;
						if(available !is null && available.getAmount(restype) != 0)
							continue;
						tip += format("[img=$1;28/]", getSpriteDesc(restype.smallIcon));
					}

					for(int i = 0; i < amount; ++i) {
						sprites.insertLast(sprt);
						tooltips.insertLast(tip);
					}
				} break;
				case RRT_Level: {
					Sprite sprt;
					if(req.level < LEVEL_REQ.length)
						sprt = LEVEL_REQ[req.level];
					else
						sprt = UNKNOWN_REQ;

					string tip = format(locale::REQ_LEVEL, toString(req.level), getSpriteDesc(sprt))+"\n";
					for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
						const ResourceType@ res = getResource(i);
						if(res.level != req.level)
							continue;
						if(res.frequency == 0.0 || res.rarity >= RR_Rare)
							continue;
						if(!res.exportable || res.mode != RM_Normal || !res.requirementDisplay)
							continue;
						tip += format("[img=$1;28/]", getSpriteDesc(res.smallIcon));
					}

					for(int i = 0; i < amount; ++i) {
						sprites.insertLast(sprt);
						tooltips.insertLast(tip);
					}
				} break;
				case RRT_Level_Types: {
					Sprite sprt;
					if(req.level < LEVEL_REQ.length)
						sprt = LEVEL_REQ[req.level];
					else
						sprt = UNKNOWN_REQ;

					string tip = format(locale::REQ_LEVEL_UNIQUE, toString(req.level), getSpriteDesc(sprt))+"\n";
					for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
						const ResourceType@ res = getResource(i);
						if(res.level != req.level)
							continue;
						if(!res.exportable || res.mode != RM_Normal || !res.requirementDisplay)
							continue;
						if(res.frequency == 0.0 || res.rarity >= RR_Rare)
							continue;
						if(available !is null && available.getAmount(res) != 0)
							continue;
						tip += format("[img=$1;28/]", getSpriteDesc(res.smallIcon));
					}

					for(int i = 0; i < amount; ++i) {
						sprites.insertLast(sprt);
						tooltips.insertLast(tip);
					}
				} break;
			}
		}
		updateAbsolutePosition();
	}
};

#section game
import void zoomTo(Object@ obj) from "tabs.GalaxyTab";
#section menu
void zoomTo(Object@ obj) {}
#section all
