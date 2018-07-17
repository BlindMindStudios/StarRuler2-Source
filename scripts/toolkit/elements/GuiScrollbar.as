import elements.BaseGuiElement;
import elements.GuiButton;

export ScrollOrientation, GuiScrollbar;

enum ScrollOrientation {
	SO_Vertical,
	SO_Horizontal,
};

class GuiScrollbar : BaseGuiElement {
	bool Focused;
	bool Dragging;
	int Orientation;
	vec2i DragFrom;

	GuiButton@ up;
	GuiButton@ down;

	SkinStyle style;
	SkinStyle handleStyle;

	double start;
	double end;

	double page;
	double scroll;
	double pos;
	double bar;

	GuiScrollbar(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		
		start = 0.0;
		end = 1.0;
		page = 0.0;
		bar = 0.2;

		pos = 0.5;
		scroll = 40.0;

		Focused = false;
		Dragging = false;

		@up = GuiButton(this, recti());
		@down = GuiButton(this, recti());

		Orientation = SO_Vertical;
		updateAbsolutePosition();
	}

	void set_orientation(int orient) {
		Orientation = orient;

		if(orient == SO_Vertical) {
			up.alignment.top.set(AS_Top, 0.0, 0);
			up.alignment.left.set(AS_Left, 0.0, 0);
			up.alignment.right.set(AS_Right, 0.0, 0);
			up.alignment.bottom.set(AS_Top, 0.0, AbsolutePosition.width);

			down.alignment.top.set(AS_Bottom, 0.0, AbsolutePosition.width);
			down.alignment.left.set(AS_Left, 0.0, 0);
			down.alignment.right.set(AS_Right, 0.0, 0);
			down.alignment.bottom.set(AS_Bottom, 0.0, 0);

			up.style = SS_ScrollUp;
			down.style = SS_ScrollDown;

			style = SS_ScrollVert;
			handleStyle = SS_ScrollVertHandle;
		}
		else {
			up.alignment.top.set(AS_Top, 0.0, 0);
			up.alignment.left.set(AS_Left, 0.0, 0);
			up.alignment.right.set(AS_Left, 0.0, AbsolutePosition.height);
			up.alignment.bottom.set(AS_Bottom, 0.0, 0);

			down.alignment.top.set(AS_Top, 0.0, 0);
			down.alignment.left.set(AS_Right, 0.0, AbsolutePosition.height);
			down.alignment.right.set(AS_Right, 0.0, 0);
			down.alignment.bottom.set(AS_Bottom, 0.0, 0);

			up.style = SS_ScrollLeft;
			down.style = SS_ScrollRight;

			style = SS_ScrollHoriz;
			handleStyle = SS_ScrollHorizHandle;
		}

		up.updateAbsolutePosition();
		down.updateAbsolutePosition();
	}

	int get_orientation() {
		return Orientation;
	}

	void emitChange() {
		GuiEvent evt;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Focused:
					Focused = true;
				break;
				case GUI_Focus_Lost:
					Focused = false;
					Dragging = false;
				break;
			}
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is up) {
				if(shiftKey)
					pos = max(start, pos - page);
				else
					pos = max(start, pos - scroll);
				emitChange();
			}
			else if(event.caller is down) {
				if(shiftKey)
					pos = min(end - page, pos + page);
				else
					pos = min(end - page, pos + scroll);
				emitChange();
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			vec2i mouse = vec2i(event.x, event.y);

			switch(event.type) {
				case MET_Button_Down: {
					recti handlePos = getBarPosition();
					vec2i offset = mouse - AbsolutePosition.topLeft;
					Dragging = true;
					DragFrom = mouse;
					if(!handlePos.isWithin(offset)) {
						pos = min(end - page, max(start, getOffsetPosition(offset)));
						emitChange();
					}
				} return true;
				case MET_Moved: {
					if(Dragging) {
						vec2i diff = mouse - DragFrom;
						
						if(Orientation == SO_Vertical) {
							int barSize = getBarPosition().height;
							pos += double(diff.y) * (end - start - page) / double(AbsolutePosition.height - barSize - 2 * AbsolutePosition.width);
						}
						else {
							int barSize = getBarPosition().width;
							pos += double(diff.x) * (end - start - page) / double(AbsolutePosition.width - barSize - 2 * AbsolutePosition.height);
						}
						
						if(pos < start)
							pos = start;
						else if(pos > end)
							pos = end;
						
						DragFrom = vec2i(clamp(mouse.x, AbsolutePosition.topLeft.x+size.height, AbsolutePosition.botRight.x-size.height),
								clamp(mouse.y, AbsolutePosition.topLeft.y+size.width, AbsolutePosition.botRight.y-size.width));
						emitChange();
						return true;
					}
				} break;
				case MET_Button_Up:
					if(Focused) {
						Dragging = false;
						return true;
					}
					break;
				case MET_Scrolled:
					pos = min(max(end - page, start), max(start, pos + double(-event.y) * scroll));
					emitChange();
					return true;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				switch(event.key) {
					case KEY_LEFT:
					case KEY_UP:
						pos = max(start, pos - scroll);
						emitChange();
					break;
					case KEY_RIGHT:
					case KEY_DOWN:
						pos = min(end - page, pos + scroll);
						emitChange();
					break;
					case KEY_PAGEUP:
						pos = max(start, pos - page);
						emitChange();
					break;
					case KEY_PAGEDOWN:
						pos = min(end - page, pos + page);
						emitChange();
					break;
				}
			break;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		orientation = Orientation;
	}

	double getOffsetPosition(vec2i offset) {
		double range = end - start;

		if(range < page || range <= 0.0)
			return start;
			
		if(Orientation == SO_Vertical) {
			int buttonsize = AbsolutePosition.width;
			int space = AbsolutePosition.height - buttonsize * 2;
			int barsize = max(int(space * (bar / range)), 16);

			return (double(offset.y - barsize - buttonsize) / double(space - barsize)) * range + start;
		}
		else {
			int buttonsize = AbsolutePosition.height;
			int space = AbsolutePosition.width - buttonsize * 2;
			int barsize = max(int(space * (bar / range)), 16);

			return (double(offset.x - barsize - buttonsize) / double(space - barsize)) * range + start;
		}
	}

	recti getBarPosition() {
		//Initial scrollbar space
		double range = end - start;

		if(range <= page || range <= 0.0)
			return recti();
		
		if(Orientation == SO_Vertical) {
			int buttonsize = AbsolutePosition.width;
			int space = AbsolutePosition.height - buttonsize * 2;

			//Remove space for bar
			int barsize = max(int(space * (bar / range)), 16);
			space -= barsize;

			//Draw bar at correct position
			int barpos = ((pos - start) / (range - page)) * space;
			vec2i barcoord = vec2i(0, barpos + buttonsize);

			return recti(barcoord, barcoord + vec2i(AbsolutePosition.width, barsize));
		}
		else {
			int buttonsize = AbsolutePosition.height;
			int space = AbsolutePosition.width - buttonsize * 2;

			//Remove space for bar
			int barsize = max(int(space * (bar / range)), 16);
			space -= barsize;

			//Draw bar at correct position
			int barpos = ((pos - start) / (range - page)) * space;
			vec2i barcoord = vec2i(barpos + buttonsize, 0);

			return recti(barcoord, barcoord + vec2i(barsize, AbsolutePosition.height));
		}
	}

	void draw() {
		recti barPos = getBarPosition() + AbsolutePosition.topLeft;
		recti bgPos;

		bool enabled = (end - start > page);

		uint handleFlags = SF_Normal;
		uint flags = SF_Normal;

		if(!enabled)
			flags |= SF_Disabled;
		if(Dragging)
			handleFlags |= SF_Active;
		if(barPos.isWithin(mousePos))
			handleFlags |= SF_Hovered;

		if(Orientation == SO_Vertical) {
			bgPos = recti(AbsolutePosition.topLeft + vec2i(0, AbsolutePosition.width),
						AbsolutePosition.botRight - vec2i(0, AbsolutePosition.width));
		}
		else {
			bgPos = recti(AbsolutePosition.topLeft + vec2i(AbsolutePosition.height, 0),
						AbsolutePosition.botRight - vec2i(AbsolutePosition.height, 0));
		}

		skin.draw(style, flags, bgPos);

		if(enabled)
			skin.draw(handleStyle, handleFlags, barPos);
		up.disabled = !enabled;
		down.disabled = !enabled;

		BaseGuiElement::draw();
	}
};
