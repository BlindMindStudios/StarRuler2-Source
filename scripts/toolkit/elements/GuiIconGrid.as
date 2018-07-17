import elements.BaseGuiElement;
import elements.MarkupTooltip;

export GuiIconGrid;
export GuiSpriteGrid;

class GuiIconGrid : BaseGuiElement {
	int hovered = -1;
	vec2i iconSize(18, 18);
	vec2i spacing(3, 3);
	vec2i padding(2, 2);
	double horizAlign = 0.5;
	double vertAlign = 0.5;
	bool fallThrough = true;
	bool clickable = true;
	bool forceHover = false;

	GuiIconGrid(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
	}

	GuiIconGrid(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Left:
					if(hovered != -1) {
						int prev = hovered;
						hovered = -1;
						setHovered(prev, -1);
					}
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) override {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is this && fallThrough) {
			int item = getOffsetItem(pos - AbsolutePosition.topLeft);
			if(item == -1 || !clickable)
				return null;
		}
		return elem;
	}

	void setHovered(int previous, int current) {
	}

	void updateHover() {
		int prevHovered = hovered;
		hovered = getOffsetItem(mousePos - AbsolutePosition.topLeft);
		if(prevHovered != hovered && tooltipObject !is null)
			tooltipObject.update(skin, this);
		setHovered(prevHovered, hovered);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(source is this) {
			switch(event.type) {
				case MET_Moved:
					updateHover();
				break;
				case MET_Button_Down:
					if(uint(hovered) < length)
						return true;
				break;
				case MET_Button_Up:
					if(uint(hovered) < length) {
						emitClicked(event.button);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	int getOffsetItem(const vec2i& off) {
		int def = -1;
		uint len = length;
		if(forceHover && len >= 1)
			def = 0;

		vec2i start, step, offset = off;
		uint perRow = 0;
		calcPositions(start, step, perRow);
		uint rows = ceil(double(len) / double(perRow));

		if(offset.x < start.x || offset.y < start.y || step.x == 0 || step.y == 0)
			return def;
		offset -= start;
		int x = offset.x / step.x;
		int y = offset.y / step.y;

		if(x < 0 || uint(x) >= perRow)
			return def;
		if(y < 0 || uint(y) >= rows)
			return def;
		if(offset.x - (step.x * x) >= iconSize.x)
			return def;
		if(offset.y - (step.y * y) >= iconSize.y)
			return def;

		uint index = y*perRow + x;
		if(index >= len)
			return def;
		return index;
	}

	recti getItemPosition(uint index) {
		vec2i start, step;
		uint perRow = 0;
		calcPositions(start, step, perRow);

		uint y = index / perRow;
		uint x = index % perRow;
		return recti_area(start + vec2i(step.x*x, step.y*y), iconSize);
	}

	void calcPositions(vec2i& start, vec2i& step, uint& perRow) {
		perRow = max((size.width - spacing.x) / (iconSize.width + spacing.x), 1);
		uint maxRows = max((size.height - spacing.y) / (iconSize.height + spacing.y), 1);

		start = padding;

		step = vec2i();
		step.y = iconSize.height;

		uint amt = length;
		if(maxRows * perRow < amt) {
			perRow = ceil(double(amt) / double(maxRows));
			step.x = size.width / perRow;
		}
		else {
			step.x = iconSize.width + spacing.x;
		}

		uint rows = ceil(double(length) / double(perRow));
		if(rows == 0)
			return;

		double excess = double(size.height - 4 - (rows * step.y + spacing.y));
		if(excess > 0) {
			step.y += excess / double(rows);
			start.y += excess / double(rows) * vertAlign;
		}

		if(amt > perRow)
			start.x += double(size.width - 4 - (perRow * step.x + spacing.x)) * horizAlign;
		else
			start.x += double(size.width - 4 - (amt * step.x + spacing.x)) * horizAlign;
	}

	uint get_length() {
		return 0;
	}

	void drawElement(uint index, const recti& pos) {
	}

	void draw() override {
		vec2i start, step;
		uint perRow = 0;
		calcPositions(start, step, perRow);

		recti hovPos;
		recti pos = recti_area(start+AbsolutePosition.topLeft, iconSize);
		uint n = 0;
		for(uint i = 0, cnt = length; i < cnt; ++i) {
			if(n >= perRow) {
				n -= perRow;

				pos.topLeft.x = start.x + AbsolutePosition.topLeft.x;
				pos.botRight.x = start.x + iconSize.x + AbsolutePosition.topLeft.x;
				pos.topLeft.y += step.y;
				pos.botRight.y += step.y;
			}

			if(int(i) == hovered)
				hovPos = pos;
			else
				drawElement(i, pos);

			pos.topLeft.x += step.x;
			pos.botRight.x += step.x;
			++n;
		}

		if(hovered != -1 && uint(hovered) < length)
			drawElement(hovered, hovPos);

		BaseGuiElement::draw();
	}
};

class GuiSpriteGrid : GuiIconGrid {
	array<Sprite> sprites;
	array<string> tooltips;
	array<Color> colors;

	GuiSpriteGrid(IGuiElement@ parent, Alignment@ align, const vec2i& size = vec2i(24, 24)) {
		super(parent, align);
		iconSize = size;
	}

	void clear() {
		sprites.length = 0;
		tooltips.length = 0;
		colors.length = 0;
	}

	void add(const Sprite& sprite, const string& tooltip = "", const Color& color = colors::White) {
		sprites.insertLast(sprite);
		tooltips.insertLast(tooltip);
		colors.insertLast(color);

		if(tooltip.length > 0 && Tooltip is null)
			addLazyMarkupTooltip(this, width=350);
	}

	uint get_length() override {
		return sprites.length;
	}

	void drawElement(uint index, const recti& pos) override {
		sprites[index].draw(pos, color=colors[index]);
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		return tooltips[hovered];
	}
};
