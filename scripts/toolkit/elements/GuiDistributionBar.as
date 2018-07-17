#section disable menu
import elements.BaseGuiElement;
import tile_resources;

export DistributionElement, GuiDistributionBar, initResourceDistribution;

final class DistributionElement {
	Sprite picture;
	Color color;
	Color textColor;
	string tooltip;
	string text;
	float amount;

	DistributionElement() {
	}

	DistributionElement(const Color& col, string tt, const Sprite& pic) {
		picture = pic;
		tooltip = tt;
		color = col;
	}
};

class GuiDistributionBar : BaseGuiElement {
	DistributionElement@[] elements;
	FontType font = FT_Normal;
	int hovered = -1;
	int padding = 1;

	GuiDistributionBar(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
	}

	GuiDistributionBar(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
	}

	string get_tooltip() override {
		if(hovered < 0 || uint(hovered) >= elements.length)
			return "";
		return elements[hovered].tooltip;
	}

	int getOffsetItem(const vec2i& off) {
		int width = size.width - 4;
		int x = off.x;

		if(off.x < 2 || off.y < 0)
			return -1;
		if(off.x > size.width - 2 || off.y > size.height)
			return -1;

		for(uint i = 0, cnt = elements.length; i < cnt; ++i) {
			DistributionElement@ ele = elements[i];

			int w = 0;
			if(i == cnt - 1 && ele.amount != 0.f)
				w = width - x;
			else
				w = floor(float(width) * ele.amount);

			if(w == 0)
				continue;
			if(x < w)
				return int(i);
			x -= w;
		}

		return -1;
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Left:
					hovered = -1;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(source is this) {
			switch(event.type) {
				case MET_Moved: {
					int prevHovered = hovered;
					hovered = getOffsetItem(mousePos - AbsolutePosition.topLeft);
					if(prevHovered != hovered && tooltipObject !is null)
						tooltipObject.update(skin, this);
				} break;
				case MET_Button_Down:
					if(hovered != -1)
						return true;
				break;
				case MET_Button_Up:
					if(hovered != -1) {
						emitClicked(event.button);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		const Font@ ft = skin.getFont(font);

		//Draw background
		skin.draw(SS_DistributionBar, SF_Normal, AbsolutePosition);

		//Draw bars
		int width = size.width - padding*2;
		int x = padding;
		for(uint i = 0, cnt = elements.length; i < cnt; ++i) {
			DistributionElement@ ele = elements[i];

			int w = 0;
			if(i == cnt - 1 && ele.amount != 0.f)
				w = width - x;
			else
				w = floor(float(width) * ele.amount);
			if(w == 0)
				continue;

			//Bar background
			uint flags = SF_Normal;
			if(hovered == int(i))
				flags |= SF_Hovered;
			skin.draw(SS_DistributionElement, flags,
					recti_area(AbsolutePosition.topLeft + vec2i(x, 1),
						vec2i(w, size.height - 2)), ele.color);


			//Calculate label sizes
			int labelOffset = 0;
			int labelSize = 0;

			vec2i psize; float aspect; vec2i nsize;
			if(ele.picture.valid) {
				psize = ele.picture.size;
				aspect = float(psize.width) / float(psize.height);
				nsize = vec2i(float(size.height - 2) * aspect, size.height - 2);

				labelSize += nsize.x+6;
			}

			vec2i tsize;
			if(ele.text.length != 0) {
				tsize = ft.getDimension(ele.text);
				labelSize += tsize.x;
			}


			labelOffset = max(x + (w - labelSize) / 2, x);

			//Draw icon
			if(ele.picture.valid) {
				vec2i pos = vec2i(labelOffset, (size.height - nsize.height) / 2);
				pos += AbsolutePosition.topLeft;
				ele.picture.draw(recti_area(pos, nsize));
				labelOffset += nsize.x+6;
			}

			//Draw label
			if(ele.text.length != 0) {
				vec2i pos = vec2i(min(labelOffset, x + w - tsize.x - 4), (size.height - tsize.height) / 2);
				pos += AbsolutePosition.topLeft;
				ft.draw(pos, ele.text, ele.textColor);
			}

			x += w;
		}

		BaseGuiElement::draw();
	}
};

const string[] RESOURCE_TOOLTIPS = {
	locale::PLANET_INCOME_TIP,
	locale::PLANET_INFLUENCE_TIP,
	locale::PLANET_ENERGY_TIP,
	locale::PLANET_DEFENSE_TIP,
	locale::PLANET_LABOR_TIP,
	locale::PLANET_RESEARCH_TIP
};

void initResourceDistribution(GuiDistributionBar@ bar) {
	bar.elements.length = TR_COUNT;
	for(uint i = 0, cnt = TR_COUNT; i < cnt; ++i) {
		DistributionElement ele;
		ele.picture = getTileResourceSprite(i);
		ele.tooltip = RESOURCE_TOOLTIPS[i];
		ele.color = getTileResourceColor(i);
		ele.amount = 1.f / float(TR_COUNT);

		@bar.elements[i] = ele;
	}
}
