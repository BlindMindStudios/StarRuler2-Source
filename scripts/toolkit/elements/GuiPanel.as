import elements.BaseGuiElement;
import elements.GuiScrollbar;

export GuiPanel, ScrollType;

enum ScrollType {
	ST_Always,
	ST_Never,
	ST_Auto,
};

class GuiPanel : BaseGuiElement {
	recti RealAbsolutePosition;
	vec2i virtualSize;
	vec2d scrollOffset;
	vec2i Origin;
	recti minPanelSize;
	recti sizePadding;

	ScrollType horizType;
	ScrollType vertType;

	GuiScrollbar@ horiz;
	GuiScrollbar@ vert;

	bool ScrollPane = false;
	bool ShowPaneScroll = false;
	int dragThreshold = 5;
	bool allowScrollDrag = true;

	vec2i dragStart;
	bool heldLeft = false;
	bool isDragging = false;
	bool animating = false;
	bool LeftDrag = true;
	bool MiddleDrag = true;

	GuiPanel(IGuiElement@ Parent, const recti& Rectangle) {
		super(Parent, Rectangle);
		_GuiPanel();
	}

	GuiPanel(IGuiElement@ Parent, Alignment@ Align) {
		super(Parent, Align);
		_GuiPanel();
	}

	void _GuiPanel() {
		@horiz = GuiScrollbar(null, recti());
		horiz.orientation = SO_Horizontal;
		horiz.scroll = 40;
		horiz.alignment.left.set(AS_Left, 0.0, 0);
		horiz.alignment.right.set(AS_Right, 0.0, 0);
		horiz.alignment.top.set(AS_Bottom, 0.0, 0);
		horiz.alignment.bottom.set(AS_Bottom, 0.0, -20);

		@vert = GuiScrollbar(null, recti());
		vert.scroll = 40;
		vert.alignment.left.set(AS_Right, 0.0, 0);
		vert.alignment.right.set(AS_Right, 0.0, -20);
		vert.alignment.top.set(AS_Top, 0.0, 0);
		vert.alignment.bottom.set(AS_Bottom, 0.0, 0);

		horizType = ST_Auto;
		vertType = ST_Auto;

		@horiz.parent = this;
		@vert.parent = this;
	}

	void addChild(IGuiElement@ ele) {
		BaseGuiElement::addChild(ele);
		updateAbsolutePosition();
	}

	void removeChild(IGuiElement@ ele) {
		BaseGuiElement::removeChild(ele);
		updateAbsolutePosition();
	}

	void scrollToVert(int position) {
		vert.pos = clamp(position, vert.start, vert.end-vert.page);
		updateAbsolutePosition();
	}

	void setScrollPane(bool value, bool showScrollbars = false) {
		ShowPaneScroll = showScrollbars;
		if(ScrollPane == value)
			return;
		ScrollPane = value;
		scrollOffset = vec2d();
		updateAbsolutePosition();
	}

	void center() {
		updateAbsolutePosition();
		scrollOffset = (vec2d(virtualSize) - vec2d(size)) / 2 + vec2d(Origin);
		updateAbsolutePosition();
	}

	void centerAround(const vec2i& pos) {
		updateAbsolutePosition();
		scrollOffset = vec2d(pos) - vec2d(size) / 2;
		updateAbsolutePosition();
	}

	void stopDrag() {
		heldLeft = false;
		isDragging = false;
		dragStart = vec2i();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(ScrollPane) {
			if(source is this || isAncestorOf(source)) {
				switch(event.type) {
					case MET_Button_Down:
						if((LeftDrag && event.button == 0) || (MiddleDrag && event.button == 2)) {
							heldLeft = true;
							dragStart = mousePos;
							return true;
						}
					break;
					case MET_Moved: {
						vec2i d = mousePos - dragStart;

						if(isDragging) {
							scroll(d.x, d.y);
							dragStart = mousePos;
						}
						else if(heldLeft) {
							if(abs(d.x) >= dragThreshold || abs(d.y) >= dragThreshold) {
								isDragging = true;
								scroll(d.x, d.y);
								dragStart = mousePos;
							}
						}
					} break;
					case MET_Button_Up:
						if((LeftDrag && event.button == 0) || (MiddleDrag && event.button == 2)) {
							heldLeft = false;
							dragStart = vec2i();
							if(isDragging) {
								isDragging = false;
								return true;
							}
						}
					break;
				}
			}
			if(event.type == MET_Scrolled && allowScrollDrag) {
				if(virtualSize.height > size.height) {
					if(ctrlKey && virtualSize.width > size.width)
						scroll(event.y * 30, 0);
					else
						scroll(0, event.y * 30);
					return true;
				}
				else if(virtualSize.width > size.width) {
					scroll(event.y * 30, 0);
					return true;
				}
			}
		}
		else {
			if(event.type == MET_Scrolled) {
				if(horiz.visible && (horiz.AbsolutePosition.isWithin(mousePos) || !vert.visible))
					return horiz.onMouseEvent(event, horiz);
				else if(vert.visible)
					return vert.onMouseEvent(event, vert);
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source !is horiz && source !is vert) {
			switch(event.key) {
				case KEY_LEFT:
				case KEY_RIGHT:
					if(horiz.visible)
						return horiz.onKeyEvent(event, horiz);
				break;
				case KEY_UP:
				case KEY_DOWN:
				case KEY_PAGEUP:
				case KEY_PAGEDOWN:
					if(vert.visible)
						return vert.onKeyEvent(event, vert);
				break;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Changed) {
			if(event.caller is vert || event.caller is horiz) {
				updateAbsolutePosition();
				return true;
			}
		}

		return BaseGuiElement::onGuiEvent(event);
	}

	bool get_onScreen() const {
		return RealAbsolutePosition.overlaps(recti(vec2i(), screenSize));
	}

	void scroll(double dx, double dy) {
		vec2i delta = vec2i(scrollOffset);
		scrollOffset -= vec2d(dx, dy);
		scrollOffset.x = clamp(scrollOffset.x, double(Origin.x),
				max(double(virtualSize.width - size.width + Origin.x), double(Origin.x)));
		scrollOffset.y = clamp(scrollOffset.y, double(Origin.y),
				max(double(virtualSize.height - size.height + Origin.y), double(Origin.y)));

		delta -= vec2i(scrollOffset);

		if(delta.x != 0 || delta.y != 0) {
			AbsolutePosition += delta;
			for(uint i = 0, cnt = Children.length; i < cnt; ++i) {
				auto@ chld = Children[i];
				if(chld is vert || chld is horiz)
					continue;
				chld.abs_move(delta);
			}
		}

		if(ShowPaneScroll) {
			horiz.pos = scrollOffset.x - Origin.x;
			vert.pos = scrollOffset.y - Origin.y;
		}
	}

	void setAnimating(bool value) {
		animating = value;
	}

	void updateAbsolutePosition() {
		if(horiz is null || vert is null)
			return;
		//Resize actual panel
		if(Parent !is null) {
			if(Alignment !is null) {
				Position = Alignment.resolve(Parent.absolutePosition.size);
				ClipRect = recti(vec2i(), Position.size);
			}

			AbsolutePosition = Position + Parent.absolutePosition.topLeft;
			AbsoluteClipRect = (ClipRect + AbsolutePosition.topLeft).clipAgainst(Parent.absoluteClipRect);
		}
		else {
			if(Alignment !is null) {
				Position = Alignment.resolve(screenSize);
				ClipRect = recti(vec2i(), Position.size);
			}

			AbsolutePosition = Position;
			AbsoluteClipRect = ClipRect + Position.topLeft;
		}

		//Figure out virtual size of canvas
		uint cCnt = Children.length();
		Origin = AbsolutePosition.topLeft + minPanelSize.topLeft;
		vec2i realSize = AbsolutePosition.size;
		virtualSize = minPanelSize.size;

		if(vert.visible)
			AbsolutePosition.botRight.x -= 20;
		if(horiz.visible)
			AbsolutePosition.botRight.y -= 20;

		for(uint i = 0; i != cCnt; ++i) {
			IGuiElement@ child = Children[i];
			if(child is horiz || child is vert || !child.visible)
				continue;

			child.updateAbsolutePosition();
			vec2i topLeft = child.absolutePosition.topLeft;
			if(topLeft.x < Origin.x)
				Origin.x = topLeft.x;
			if(topLeft.y < Origin.y)
				Origin.y = topLeft.y;
		}

		for(uint i = 0; i != cCnt; ++i) {
			IGuiElement@ child = Children[i];
			if(child is horiz || child is vert || !child.visible)
				continue;

			vec2i botRight = child.absolutePosition.botRight;
			virtualSize.width = max(virtualSize.width, botRight.x - Origin.x);
			virtualSize.height = max(virtualSize.height, botRight.y - Origin.y);
		}

		Origin -= sizePadding.topLeft;
		virtualSize += sizePadding.topLeft;
		virtualSize += sizePadding.botRight;

		//Update scrollbars
		Origin -= AbsolutePosition.topLeft;
		if(!ScrollPane || ShowPaneScroll) {
			horiz.end = virtualSize.width;
			horiz.page = AbsolutePosition.width;
			horiz.bar = horiz.page;
			horiz.pos = max(horiz.start, min(horiz.end-horiz.page, horiz.pos));

			vert.end = virtualSize.height;
			vert.page = AbsolutePosition.height;
			vert.bar = vert.page;
			vert.pos = max(vert.start, min(vert.end-vert.page, vert.pos));
			
			scrollOffset = vec2d(horiz.pos + Origin.x, vert.pos + Origin.y);

			//Check which scrollbars should be visible
			bool prevHoriz = horiz.visible;
			bool prevVert = vert.visible;

			if(animating) {
				vert.visible = false;
				horiz.visible = false;
			}
			else {
				vert.visible = (virtualSize.height > realSize.height && vertType != ST_Never) || vertType == ST_Always;
				horiz.visible = (virtualSize.width > realSize.width && horizType != ST_Never) || horizType == ST_Always;
				if(horiz.visible && !vert.visible)
					vert.visible = (virtualSize.height > realSize.height - 20 && vertType != ST_Never) || vertType == ST_Always;
			}

			if(prevHoriz != horiz.visible || prevVert != vert.visible) {
				updateAbsolutePosition();
				return;
			}

			//Update scrollbar positions
			horiz.updateAbsolutePosition();
			vert.updateAbsolutePosition();
		}
		else {
			scroll(0, 0);
			horiz.visible = false;
			vert.visible = false;
		}

		//Fake absolute position and reposition children
		RealAbsolutePosition = AbsolutePosition;
		AbsolutePosition -= vec2i(scrollOffset);

		if(horiz.visible)
			AbsoluteClipRect.botRight.y -= 20;
		if(vert.visible)
			AbsoluteClipRect.botRight.x -= 20;
		
		for(uint i = 0; i != cCnt; ++i) {
			if(Children[i] is horiz || Children[i] is vert)
				continue;
			Children[i].updateAbsolutePosition();
		}
	}

	void move(const vec2i& moveBy) {
		Position += moveBy;
		AbsolutePosition += moveBy;
		RealAbsolutePosition += moveBy;
		AbsoluteClipRect = ClipRect + RealAbsolutePosition.topLeft;
		if(Parent !is null)
			AbsoluteClipRect = AbsoluteClipRect.clipAgainst(Parent.absoluteClipRect);

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].abs_move(moveBy);
	}

	void abs_move(const vec2i& moveBy) {
		AbsolutePosition += moveBy;
		RealAbsolutePosition += moveBy;
		AbsoluteClipRect = ClipRect + RealAbsolutePosition.topLeft;
		if(Parent !is null)
			AbsoluteClipRect = AbsoluteClipRect.clipAgainst(Parent.absoluteClipRect);

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].abs_move(moveBy);
	}

	void set_horizPosition(int pos) {
		horiz.pos = min(double(pos), horiz.end - horiz.page);
		updateAbsolutePosition();
	}

	void set_vertPosition(int pos) {
		vert.pos = min(double(pos), vert.end - vert.page);
		updateAbsolutePosition();
	}

	recti get_absolutePosition() {
		return RealAbsolutePosition;
	}

	void draw() {
		if(!visible)
			return;

		clearClip();
		if(horiz.visible)
			horiz.draw();

		if(vert.visible)
			vert.draw();

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i) {
			if(Children[i] is horiz || Children[i] is vert)
				continue;

			IGuiElement@ ele = Children[i];

			if(!ele.visible || !RealAbsolutePosition.overlaps(ele.absolutePosition))
				continue;

			if(ele.noClip)
				clearClip();
			else
				setClip(ele.absoluteClipRect);

			ele.draw();

			if(!ele.noClip)
				clearClip();
		}
	}
};
