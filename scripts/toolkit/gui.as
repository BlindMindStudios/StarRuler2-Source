import elements.IGuiElement;
RootElement gui_root;

int next_gui_id = 1;
int get_nextGuiID() {
	return next_gui_id++;
}

IGuiElement@ getRootGuiElement() {
	return gui_root;
}

void setGuiFocus(IGuiElement@ elem) {
	@gui_root.focus = elem;
}

void clearGuiHovered() {
	@gui_root.hovered = null;
}

void setGuiAbsorb(IGuiElement@ elem) {
	@gui_root.AbsorbTo = elem;
	@gui_root.focus = elem;
}

IGuiElement@ getGuiFocus() {
	return gui_root.Focus;
}

bool isGuiFocusIn(IGuiElement@ elem) {
	if(gui_root.Focus is null)
		return false;
	return gui_root.Focus is elem || gui_root.Focus.isChildOf(elem);
}

bool isGuiHovered() {
	if(gui_root.AbsorbTo !is null)
		return true;
	if(gui_root.Hovered is null)
		return false;
	return !gui_root.Hovered.isRoot;
}

void animate_speed(IGuiElement@ ele, const recti& dest, double speed, int value = 0) {
	GuiAnim@ anim;
	uint len = animations.length();
	for(uint i = 0; i < len; ++i) {
		if(animations[i].ele is ele) {
			@anim = animations[i];
			break;
		}
	}

	if(anim is null) {
		animations.resize(len+1);
		@anim = animations[len];
	}
	
	@anim.ele = @ele;
	recti startRect = ele.rect;
	anim.from = rectf(startRect);
	anim.to = dest;
	anim.byTime = false;
	anim.arg = speed;
	anim.value = value;
	anim.completed = false;
}

void animate_time(IGuiElement@ ele, const recti& dest, double time, int value = 0) {
	GuiAnim@ anim;
	uint len = animations.length();
	for(uint i = 0; i < len; ++i) {
		if(animations[i].ele is ele) {
			@anim = animations[i];
			break;
		}
	}

	if(anim is null) {
		animations.resize(len+1);
		@anim = animations[len];
	}
	
	@anim.ele = @ele;
	recti startRect = ele.rect;
	anim.from = rectf(startRect);
	anim.to = dest;
	anim.byTime = true;
	anim.arg = time;
	anim.value = value;
	anim.completed = false;
}

void animate_retarget(IGuiElement@ ele, const recti& dest) {
	uint len = animations.length();
	for(uint i = 0; i < len; ++i) {
		if(animations[i].ele is ele) {
			animations[i].to = dest;
			return;
		}
	}
}

void animate_remove(IGuiElement@ ele) {
	for(int i = animations.length()-1; i >= 0; --i)
		if(animations[i].ele is ele)
			animations.removeAt(i);
}

void animate_snap(IGuiElement@ ele) {
	uint len = animations.length();
	for(uint i = 0; i < len; ++i) {
		if(animations[i].ele is ele) {
			ele.rect = animations[i].to;
			animations.removeAt(i);
			return;
		}
	}
}

ITooltip@ getTooltip(IGuiElement@ ele) {
	ITooltip@ tt;
	while(tt is null && ele !is null) {
		@tt = ele.tooltipObject;
		@ele = ele.parent;
	}
	return tt;
}

void clearTooltip() {
	if(gui_root.Tooltip !is null) {
		gui_root.Tooltip.hide(gui_root.skin, gui_root.Hovered);
		@gui_root.Tooltip = null;
		gui_root.updateHover();
	}
}

void tick(double time) {
	if(gui_root.AbsorbTo !is null && gui_root.AbsorbTo.parent is null)
		@gui_root.AbsorbTo = null;

	if(gui_root.Hovered !is null && gui_root.Tooltip is null && gui_root.AbsorbTo is null) {
		@gui_root.Tooltip = getTooltip(gui_root.Hovered);
		if(gui_root.Tooltip !is null) {
			gui_root.showTooltipDelay = gui_root.Tooltip.delay;
			if(gui_root.showTooltipDelay <= 0.f)
				gui_root.Tooltip.show(gui_root.skin, gui_root.Hovered);
		}
	}

	if(gui_root.Tooltip !is null) {
		if(gui_root.showTooltipDelay > 0.f) {
			gui_root.showTooltipDelay = max(gui_root.showTooltipDelay - float(time), 0.f);
			if(gui_root.showTooltipDelay <= 0.f)
				gui_root.Tooltip.show(gui_root.skin, gui_root.Hovered);
		}
	}

	if(gui_root.Hovered !is null) {
		if(gui_root.Hovered.parent is null)
			gui_root.updateHover();
	}
}

void draw() {
	for(int i = animations.length()-1; i >= 0; --i)
		if(animations[i].update(frameLength))
			animations.removeAt(i);
	gui_root.draw();
}

bool onGuiEvent(const GuiEvent& evt) {
	return gui_root.postGuiEvent(evt);
}

bool onMouseEvent(const MouseEvent& event) {
	return gui_root.postMouseEvent(event);
}

bool onKeyboardEvent(const KeyboardEvent& event) {
	return gui_root.postKeyEvent(event);
}

void onGuiNavigate(vec2d direction) {
	gui_root.navigateTo(direction);
}

IGuiElement@ getNavChild(IGuiElement@ ele, NavigationMode mode) {
	for(uint i = 0, cnt = ele.childCount; i < cnt; ++i) {
		IGuiElement@ child = ele.getChild(i);
		if(!child.visible)
			continue;
		if(child.isNavigable(mode))
			return child;

		@child = getNavChild(child, mode);
		if(child !is null)
			return child;
	}
	return null;
}

void navigateInto(IGuiElement@ elem) {
	if(elem.isNavigable(gui_root.NavMode)) {
		setGuiFocus(elem);
	}
	else {
		IGuiElement@ child = getNavChild(elem, gui_root.NavMode);
		if(child !is null)
			setGuiFocus(child);
		else
			setGuiFocus(elem);
	}
}

//A special element that has only children, no parent
//Acts as the parent of all elements
class RootElement : IGuiElement {
	IGuiElement@[] Children;
	IGuiElement@ Focus;
	IGuiElement@ Hovered;
	IGuiElement@ AbsorbTo;
	recti absRect;
	ITooltip@ Tooltip;
	const Skin@ skin = getSkin(settings::sSkinName);
	float showTooltipDelay = -1;
	IGuiElement@ prevTabFocus;
	bool Visible = true;
	bool NoClip = true;
	NavigationMode NavMode = NM_None;
	GuiEvent guiEvent;
	
	RootElement() {
		updateAbsolutePosition();
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return false;
	}
	
	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		return false;
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		return false;
	}
	
	int get_id() const {
		return 0;
	}

	bool postGuiEvent(const GuiEvent& event) {
		if(Focus !is null && Focus.actuallyVisible && Focus.onGuiEvent(event))
			return true;
		return false;
	}

	void updateHover() {
		vec2i pos = mousePos;
		@hovered = elementFromPosition(vec2i(pos.x, pos.y));
	}
	
	bool postMouseEvent(const MouseEvent& event) {	
		if(Tooltip !is null) {
			if(Tooltip.persist) {
				if(event.type == MET_Moved && showTooltipDelay > 0.f)
					showTooltipDelay = Tooltip.delay;
			}
			else {
				if(showTooltipDelay <= 0.f)
					Tooltip.hide(skin, Hovered);
				if(event.type == MET_Moved)
					showTooltipDelay = Tooltip.delay;
				else
					@Tooltip = null;
			}
		}

		if(event.type == MET_Moved)
			@hovered = elementFromPosition(vec2i(event.x, event.y));
			
		if(event.type == MET_Button_Down) {
			if(NavMode != NM_None)
				NavMode = NM_None;
			@focus = elementFromPosition(vec2i(event.x, event.y));
		}

		if(Hovered !is null && Hovered !is Focus && Hovered.onMouseEvent(event,Hovered)) {
			return true;
		}

		if(Focus !is null && Focus.actuallyVisible && Focus.onMouseEvent(event,Focus)) {
			return true;
		}
		
		return Hovered !is null && !Hovered.isRoot;
	}
	
	bool postKeyEvent(const KeyboardEvent& event) {
		if(Focus !is null && Focus.actuallyVisible && Focus.onKeyEvent(event,Focus))
			return true;
		
		if(Hovered !is null && Hovered !is Focus && Hovered.onKeyEvent(event,Hovered))
			return true;

		if(event.type == KET_Key_Down && event.key == KEY_TAB) {
			if(prevTabFocus !is null) {
				if(shiftKey)
					@focus = prevTabElement(prevTabFocus);
				else
					@focus = nextTabElement(prevTabFocus);
				return true;
			}
		}
		
		return false;
	}
	
	void set_focus(IGuiElement@ ele) {
		if(Focus is ele)
			return;
			
		if(Focus !is null) {
			guiEvent.type = GUI_Focus_Lost;
			@guiEvent.caller = Focus;
			@guiEvent.other = ele;
			if(Focus.onGuiEvent(guiEvent))
				return;
		}
		if(ele !is null) {
			guiEvent.type = GUI_Focused;
			@guiEvent.caller = ele;
			@guiEvent.other = Focus;
			if(ele.onGuiEvent(guiEvent))
				return;
		}
		@Focus = @ele;

		if(Focus !is null) {
			if(Focus.tabIndex >= 0) {
				@prevTabFocus = Focus;
			}
			else if(prevTabFocus !is null) {
				IGuiElement@ oldGroup = findParentGroup(prevTabFocus);
				@prevTabFocus = findParentGroup(Focus);
				if(prevTabFocus !is oldGroup)
					@prevTabFocus = null;
			}
		}
	}
	
	void set_hovered(IGuiElement@ ele) {
		if(Hovered is ele)
			return;
		if(Hovered !is null) {
			if(ele is null || !ele.isChildOf(Hovered)) {
				guiEvent.type = GUI_Mouse_Left;
				@guiEvent.caller = Hovered;
				@guiEvent.other = ele;
				if(Hovered.onGuiEvent(guiEvent))
					return;

				if(ele !is null) {
					IGuiElement@ check = Hovered.parent;
					while(check !is null) {
						if(check.isAncestorOf(ele))
							break;

						@guiEvent.caller = check;
						if(check.onGuiEvent(guiEvent))
							return;

						@check = check.parent;
					}
				}
			}
		}
		
		if(ele !is null) {
			if(Hovered is null || !Hovered.isChildOf(ele)) {
				guiEvent.type = GUI_Mouse_Entered;
				@guiEvent.caller = ele;
				@guiEvent.other = Hovered;
				if(ele.onGuiEvent(guiEvent))
					return;

				IGuiElement@ check = ele.parent;
				while(check !is null) {
					if(check.isAncestorOf(Hovered))
						break;

					@guiEvent.caller = check;
					if(check.onGuiEvent(guiEvent))
						return;

					@check = check.parent;
				}
			}
			
			ITooltip@ prevTooltip = Tooltip;
			@Tooltip = getTooltip(ele);
			if(prevTooltip !is Tooltip) {
				if(prevTooltip !is null)
					prevTooltip.hide(skin, Hovered);
				if(Tooltip !is null) {
					showTooltipDelay = Tooltip.delay;
					if(showTooltipDelay <= 0.f)
						Tooltip.show(skin, ele);
				}
			}
		}
		else {
			if(Tooltip !is null)
				Tooltip.hide(skin, Hovered);
			@Tooltip = null;
		}
		
		@Hovered = @ele;
	}
	
	IGuiElement@ get_parent() const {
		return null;
	}
	
	void set_parent(IGuiElement@ NewParent) {
		throw("Attempted to set parent of Root GUI Element");
	}
	
	void updateAbsolutePosition() {
		vec2i newSize = screenSize;
		if(newSize != absRect.size && newSize.width != 0 && newSize.height != 0) {
			absRect = recti_area(vec2i(0,0), screenSize);
			uint cCnt = Children.length();
			for(uint i = 0; i != cCnt; ++i)
				Children[i].updateAbsolutePosition();
		}
	}
	
	IGuiElement@ elementFromPosition(const vec2i& pos) {
		uint cCnt = Children.length();
		for(int i = cCnt - 1; i >= 0; --i) {
			if(!Children[i].visible)
				continue;

			IGuiElement@ ele = Children[i].elementFromPosition(pos);

			if(ele !is null)
				return ele;
		}
		
		return null;
	}
	
	recti get_absolutePosition() {
		return absRect;
	}

	recti get_updatePosition() {
		return absRect;
	}
	
	recti get_absoluteClipRect() {
		return absRect;
	}
	
	string get_elementType() const {
		return "root";
	}

	bool get_isRoot() const {
		return true;
	}

	bool get_visible() const {
		return Visible;
	}

	bool get_actuallyVisible() const {
		return Visible;
	}

	bool get_onScreen() const {
		return true;
	}

	void set_visible(bool vis) {
		Visible = vis;
	}
	
	void addChild(IGuiElement@ ele) {
		Children.insertLast(ele);
	}
	
	void removeChild(IGuiElement@ ele) {
		for(uint i = 0; i < Children.length(); ++i) {
			if(Children[i] is ele) {
				Children.removeAt(i);
				return;
			}
		}
	}

	void remove() {
		throw("Error: attempting to remove gui root.");
	}
	
	bool isAncestorOf(const IGuiElement@ ele) const {
		while(ele !is null) {
			if(ele is this)
				return true;
			@ele = @ele.parent;
		}
		return false;
	}
	
	bool isChildOf(const IGuiElement@ ele) const {
		return false;
	}

	bool isFront() { return true; }
	
	void bringToFront() {}
	
	void bringToFront(IGuiElement@ ele) {
		if(Children.length != 0)
			if(Children[Children.length - 1] is ele)
				return;
		Children.remove(ele);
		Children.insertLast(ele);
	}

	bool isBack() { return true; }

	void sendToBack() {}

	void sendToBack(IGuiElement@ ele) {
		uint offset = 0;
		for(int i = Children.length() - 1; i >= 0; --i) {
			if(Children[i] is ele)
				offset = 1;
			else if(offset != 0)
				@Children[i + offset] = Children[i];
		}
		@Children[0] = ele;
	}
	
	void draw() {
		updateAbsolutePosition();
		if(!Visible)
			return;
		
		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i) {
			IGuiElement@ ele = Children[i];
			if(!ele.visible || !ele.onScreen)
				continue;

			if(ele.noClip)
				clearClip();
			else
				setClip(ele.absoluteClipRect);

			ele.draw();

			if(!ele.noClip)
				clearClip();
		}

		if(Focus !is null && NavMode != NM_None && Focus.isNavigable(NavMode) && Focus.actuallyVisible) {
			clearClip();
			drawRectangle(Focus.absolutePosition.padded(-8), Color(0xffffff40));

			setClip(Focus.absoluteClipRect);
			Focus.draw();
			clearClip();
		}
		
		if(Tooltip !is null && showTooltipDelay <= 0.f)
			Tooltip.draw(skin, Hovered);
	}
	
	void set_position(const vec2i& pos) {}
	void move(const vec2i& moveBy) {}
	void abs_move(const vec2i& moveBy) {}
	
	vec2i get_position() const {
		return absRect.topLeft;
	}
	
	void set_size(const vec2i& _size) {}
	
	vec2i get_size() const {
		return absRect.get_size();
	}

	vec2i get_desiredSize() const {
		return size;
	}
	
	void set_rect(const recti& rect) {}
	
	recti get_rect() const {
		return absRect;
	}
	
	void set_tooltip(const string& ToolText) {
	}

	string get_tooltip() {
		return "";
	}

	void set_tooltipObject(ITooltip@ tp) {
	}

	ITooltip@ get_tooltipObject() const {
		return null;
	}

	bool get_noClip() const {
		return NoClip;
	}

	void set_noClip(bool noclip) {
		NoClip = noclip;
	}

	int get_tabIndex() const {
		return -1;
	}

	void set_tabIndex(int ind) {
	}

	IGuiElement@ getChild(uint index) {
		if(index >= Children.length())
			return null;
		return Children[index];
	}

	uint get_childCount() const {
		return Children.length();
	}

	//Find the first parent with a tab index (or the root)
	IGuiElement@ findParentGroup(IGuiElement@ ele) {
		IGuiElement@ parent = ele.parent;
		while(parent !is null && parent.tabIndex == -1)
			@parent = parent.parent;

		if(parent is null)
			return this;
		else
			return parent;
	}

	//Within the same tab group parent, find the next element to tab to
	IGuiElement@ nextTabElement(IGuiElement@ from) {
		int minIndex = from.tabIndex;
		IGuiElement@ minElement;

		IGuiElement@ parent = findParentGroup(from);
		nextTabElement(parent, minIndex, minIndex, minElement);

		return minElement;
	}

	void nextTabElement(IGuiElement@ ele, int index, int& minIndex, IGuiElement@& minElement) {
		int ind = ele.tabIndex;
		if(ind >= 0) {
			if(minIndex > index) {
				if(ind > index && ind < minIndex) {
					minIndex = ind;
					@minElement = ele;
				}
			}
			else if(ind > index || ind < minIndex) {
				minIndex = ind;
				@minElement = ele;
			}
		}

		for(uint i = 0, cnt = ele.childCount; i < cnt; ++i)
			nextTabElement(ele.getChild(i), index, minIndex, minElement);
	}

	//Within the same tab group parent, find the previous element to tab to
	IGuiElement@ prevTabElement(IGuiElement @from) {
		int maxIndex = from.tabIndex;
		IGuiElement@ maxElement;

		IGuiElement@ parent = findParentGroup(from);
		prevTabElement(parent, maxIndex, maxIndex, maxElement);

		return maxElement;
	}

	void prevTabElement(IGuiElement@ ele, int index, int& maxIndex, IGuiElement@& maxElement) {
		int ind = ele.tabIndex;
		if(ind >= 0) {
			if(maxIndex < index) {
				if(ind < index && ind > maxIndex) {
					maxIndex = ind;
					@maxElement = ele;
				}
			}
			else if(ind < index || ind > maxIndex) {
				maxIndex = ind;
				@maxElement = ele;
			}
		}

		for(uint i = 0, cnt = ele.childCount; i < cnt; ++i)
			prevTabElement(ele.getChild(i), index, maxIndex, maxElement);
	}

	bool isNavigable(NavigationMode mode) const {
		return false;
	}

	void navigateTo(vec2d line) {
		//Jump into the right navigation mode
		if(NavMode != NM_Action) {
			@focus = null;
			NavMode = NM_Action;
		}

		//Find element to navigate to
		IGuiElement@ nav;
		if(Focus !is null && Focus.actuallyVisible && Focus.parent !is null)
			@nav = Focus.navigate(NavMode, line);
		else
			@nav = navigate(NavMode, line);

		//Focus it
		GuiEvent evt;
		if(nav !is null && nav !is Focus) {
			if(Focus !is null) {
				evt.type = GUI_Navigation_Leave;
				@evt.caller = Focus;
				@evt.other = nav;
				Focus.onGuiEvent(evt);
			}
			@focus = nav;

			evt.type = GUI_Navigation_Enter;
			@evt.caller = Focus;
			Focus.onGuiEvent(evt);
		}
	}

	IGuiElement@ navigate(NavigationMode mode, const vec2d& line) {
		return navigate(mode, absolutePosition, line);
	}

	IGuiElement@ navigate(NavigationMode mode, const recti& box, const vec2d&in line) {
		float closestDist = FLOAT_INFINITY;
		IGuiElement@ closest;
		closestToLine(mode, box, line.normalized(), closestDist, closest, Focus);
		return closest;
	}

	void closestToLine(NavigationMode mode, const recti& box, const vec2d&in line, float& closestDist, IGuiElement@& closest, IGuiElement@ skip) {
		vec2d origin = vec2d(box.center);
		for(uint i = 0, cnt = Children.length; i < cnt; ++i) {
			IGuiElement@ child = Children[i];
			if(!child.visible)
				continue;
			if(child.isNavigable(mode)) {
				if(child is skip)
					continue;
				recti pos = child.absolutePosition;
				vec2d dir = vec2d(pos.center) - origin;
				double t = (dir.x*line.x + dir.y*line.y);
				if(t < 0 && skip !is null)
					continue;

				vec2d point = origin + line * t;
				float dist = pos.distanceTo(vec2i(point));
				dist += 0.001f * point.distanceTo(origin);

				if(dist < closestDist) {
					closestDist = dist;
					@closest = child;
					if(dist == 0.f)
						break;
				}
			}
			else {
				child.closestToLine(mode, box, line, closestDist, closest, skip);
				if(closestDist == 0.f)
					break;
			}
		}
	}
};

class GuiAnim {
	IGuiElement@ ele;
	rectf from;
	recti to;
	bool byTime;
	double arg;
	int value;
	bool completed;
	
	bool update(double time) {
		double interp;
		if(byTime) {
			interp = time / arg;
			arg -= time;
		}
		else {
			rectf to_f(to);
			
			float dist = max(to_f.topLeft.distanceTo(from.topLeft), to_f.topLeft.distanceTo(from.topLeft));
			if(dist > 0)
				interp = (arg * time) / dist;
			else
				interp = 1.0;
		}
		
		if(interp >= 1.0) {
			ele.rect = to;
			ele.updateAbsolutePosition();
			completed = true;

			GuiEvent evt;
			evt.type = GUI_Animation_Complete;
			evt.value = value;
			@evt.caller = ele;
			ele.onGuiEvent(evt);

			return completed;
		}
		
		from = from.interpolate(rectf(to), interp);
		ele.rect = recti(from);
		ele.updateAbsolutePosition();
		return false;
	}
};

GuiAnim[] animations;
