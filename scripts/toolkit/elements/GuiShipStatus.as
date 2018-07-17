import elements.BaseGuiElement;

export GuiShipStatus;

void drawShipStatus(const recti& pos, const Blueprint@ bp) {
	drawShipStatus(pos, bp, bp.design);
}

void drawShipStatus(const recti& pos, const Design@ dsg) {
	drawShipStatus(pos, null, dsg);
}

void drawShipStatus(const recti& pos, const Blueprint@ bp, const Design@ design) {
	if(design is null)
		return;

	Color deadColor(0x000000cc);
	const Hull@ hull = design.hull;

	const Material@ hex = material::StatusHex;
	vec2i hexSize = hex.size;
	vec2i cellSize = hexSize + vec2i(0, 1);

	vec2i bpSize(hull.gridSize.width * cellSize.x,
				hull.gridSize.height * cellSize.y);

	vec2i offset = pos.topLeft;
	offset += (pos.size - bpSize) / 2;

	for(int y = 0; y < hull.gridSize.height; ++y) {
		for(int x = 0; x < hull.gridSize.width; ++x) {
			if(!hull.active.get(x, y))
				continue;

			Color color(0xffffffff);
			vec2i hexPos(x * cellSize.x, y * cellSize.y);
			if(x % 2 != 0)
				hexPos.y += cellSize.y / 2;
			hexPos += offset;

			const Subsystem@ sys;
			if(design !is null)
				@sys = design.subsystem(x, y);

			if(sys !is null) {
				//Color hex to represent damage
				color = sys.type.color;

				if(bp !is null) {
					const HexStatus@ status = bp.getHexStatus(x, y);
					const SysStatus@ ss = bp.getSysStatus(x, y);
					float pct = float(status.hp) / 255.0;
					color = deadColor.getInterpolated(color, pct);
				}
			}
			else {
				color = deadColor;
			}

			hex.draw(recti_area(hexPos, hexSize), color);
		}
	}
}

class GuiShipStatus : BaseGuiElement {
	const Blueprint@ bp;
	const Design@ design;
	Object@ obj;
	
	GuiShipStatus(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
	}

	GuiShipStatus(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		return BaseGuiElement::onGuiEvent(event);
	}

	void display(Object@ Obj) {
		if(!Obj.isShip)
			return;
		@obj = Obj;
		Ship@ ship = cast<Ship@>(obj);
		@bp = ship.blueprint;
	}

	void draw() {
		if(bp is null)
			return;

		if(bp !is null) {
			ObjectLock lock(obj, true);
			drawShipStatus(AbsolutePosition, bp);
		}
		else if(design !is null)
			drawShipStatus(AbsolutePosition, design);
		BaseGuiElement::draw();
	}
};
