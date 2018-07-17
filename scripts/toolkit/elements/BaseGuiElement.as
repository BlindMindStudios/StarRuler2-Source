import elements.IGuiElement;
import elements.Alignment;
from gui import get_nextGuiID, getRootGuiElement, setGuiFocus, setGuiAbsorb, getGuiFocus, isGuiFocusIn, clearGuiHovered, gui_root;

interface IGuiCallback {
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source);
	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source);
	bool onGuiEvent(const GuiEvent& event);
};

class GuiCallback {
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return false;
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		return false;
	}

	bool onGuiEvent(const GuiEvent& event) {
		return false;
	}
};

class SimpleTooltip : ITooltip {
	string text;

	SimpleTooltip(const string& txt) {
		text = txt;
	}

	float get_delay() {
		return 0.5f;
	}

	bool get_persist() {
		return false;
	}

	void update(const Skin@ skin, IGuiElement@ elem) {
		text = elem.get_tooltip();
	}

	void show(const Skin@ skin, IGuiElement@ elem) {
	}

	void hide(const Skin@ skin, IGuiElement@ elem) {
	}

	void draw(const Skin@ skin, IGuiElement@ elem) {
		const Font@ ft = skin.getFont(FT_Normal);
		vec2i size = ft.getDimension(text);
		vec2i pos(mousePos.x + 12, mousePos.y);

		skin.draw(SS_Tooltip, SF_Normal, recti_area(pos, size + vec2i(8, 8)));
		skin.draw(FT_Normal, pos + vec2i(4, 4), text);
	}
};

class BaseGuiElement : IGuiElement {
	int id = nextGuiID;
	IGuiElement@ Parent;
	IGuiElement@[] Children;
	KeybindGroup@ keybinds;
	const Skin@ skin = getSkin(settings::sSkinName);
	Alignment@ Alignment;
	IGuiCallback@ callback;
	recti Position;
	recti ClipRect;
	bool NoClip = false;
	bool Visible = true;
	int TabIndex = -1;
	recti AbsolutePosition;
	recti AbsoluteClipRect;
	ITooltip@ Tooltip;
	bool Navigable = false;
	bool StrictBounds = false;
	
	BaseGuiElement(IGuiElement@ ParentElement, const recti& Rectangle) {
		Position = Rectangle;
		ClipRect = recti(vec2i(), Position.size);

		_BaseGuiElement(ParentElement);
	}

	BaseGuiElement(IGuiElement@ ParentElement, Alignment@ align) {
		@Alignment = align;

		_BaseGuiElement(ParentElement);
	}
	
	BaseGuiElement(bool NoParent) {
		if(!NoParent)
			throw("NoParent must be true");
	}

	void _BaseGuiElement(IGuiElement@ ParentElement) {
		if(ParentElement is null)
			@Parent = getRootGuiElement();
		else
			@Parent = ParentElement;
			
		if(Parent !is null)
			Parent.addChild(this);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(callback !is null)
			if(callback.onMouseEvent(event, source))
				return true;

		if(Parent !is null)
			return Parent.onMouseEvent(event,source);
		else if(callback !is null)
			return callback.onMouseEvent(event,source);
		else
			return false;
	}
	
	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(callback !is null)
			if(callback.onKeyEvent(event, source))
				return true;

		if(keybinds !is null && (event.type == KET_Key_Down || event.type == KET_Key_Up)) {
			int key = modifyKey(event.key);
			Keybind bind = keybinds.getBind(key);

			if(bind != KB_NONE) {
				GuiEvent evt;
				evt.value = bind;
				@evt.caller = this;

				//Emit the right event
				switch(event.type) {
					case KET_Key_Down:
						evt.type = GUI_Keybind_Down;
					break;
					case KET_Key_Up:
						evt.type = GUI_Keybind_Up;
					break;
				}
				onGuiEvent(evt);
				return true;
			}
		}

		if(Parent !is null)
			return Parent.onKeyEvent(event,source);
		else
			return false;
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		if(callback !is null)
			if(callback.onGuiEvent(event))
				return true;

		if(Parent !is null)
			return Parent.onGuiEvent(event);
		else
			return false;
	}
	
	string get_elementType() const {
		return "unknown";
	}
	
	int get_id() const {
		return id;
	}
	
	IGuiElement@ elementFromPosition(const vec2i& pos) {
		if(StrictBounds) {
			if(!AbsoluteClipRect.isWithin(pos))
				return null;
		}

		uint cCnt = Children.length();
		for(int i = cCnt - 1; i >= 0; --i) {
			if(!Children[i].visible)
				continue;

			IGuiElement@ ele = Children[i].elementFromPosition(pos);

			if(ele !is null)
				return ele;
		}
		
		if(noClip) {
			if(AbsolutePosition.isWithin(pos))
				return this;
		}
		else {
			if(AbsoluteClipRect.isWithin(pos))
				return this;
		}
		return null;
	}

	void updateAbsolutePosition() {
		if(Parent !is null) {
			if(Alignment !is null) {
				Position = Alignment.resolve(Parent.updatePosition.size);
				ClipRect = recti(vec2i(), Position.size);
			}

			AbsolutePosition = Position + Parent.updatePosition.topLeft;
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

		if(noClip)
			AbsoluteClipRect = AbsolutePosition;
		
		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].updateAbsolutePosition();
	}
	
	recti get_absolutePosition() {
		return AbsolutePosition;
	}

	recti get_updatePosition() {
		return AbsolutePosition;
	}
	
	recti get_absoluteClipRect() {
		return AbsoluteClipRect;
	}

	void swap(BaseGuiElement@ other) {
		recti prevPos = Position;
		recti prevClip = ClipRect;
		recti prevAPos = AbsolutePosition;
		recti prevAClip = AbsoluteClipRect;

		Position = other.Position;
		ClipRect = other.ClipRect;
		AbsolutePosition = other.AbsolutePosition;
		AbsoluteClipRect = other.AbsoluteClipRect;

		other.AbsolutePosition = prevAPos;
		other.AbsoluteClipRect = prevAClip;
		other.Position = prevPos;
		other.ClipRect = prevClip;

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].updateAbsolutePosition();

		cCnt = other.Children.length();
		for(uint i = 0; i != cCnt; ++i)
			other.Children[i].updateAbsolutePosition();
	}
	
	void set_position(const vec2i& pos) {
		if(Position.topLeft == pos)
			return;
		move(pos - Position.topLeft);
	}

	void move(const vec2i& moveBy) {
		Position += moveBy;
		AbsolutePosition += moveBy;
		AbsoluteClipRect = ClipRect + AbsolutePosition.topLeft;
		if(Parent !is null)
			AbsoluteClipRect = AbsoluteClipRect.clipAgainst(Parent.absoluteClipRect);

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].abs_move(moveBy);
	}

	void abs_move(const vec2i& moveBy) {
		AbsolutePosition += moveBy;
		AbsoluteClipRect = ClipRect + AbsolutePosition.topLeft;
		if(Parent !is null)
			AbsoluteClipRect = AbsoluteClipRect.clipAgainst(Parent.absoluteClipRect);

		uint cCnt = Children.length();
		for(uint i = 0; i != cCnt; ++i)
			Children[i].abs_move(moveBy);
	}
	
	vec2i get_position() const {
		if(Alignment !is null)
			if(Parent !is null)
				return Alignment.resolve(Parent.updatePosition.size).topLeft;
			else
				return Alignment.resolve(screenSize).topLeft;
		else
			return Position.topLeft;
	}
	
	void set_size(const vec2i& _size) {
		if(Position.get_size() == _size)
			return;
		Position = recti_area(Position.topLeft, _size);
		ClipRect = recti(vec2i(), _size);
		if(Alignment is null)
			updateAbsolutePosition();
	}
	
	vec2i get_size() const {
		if(Alignment !is null)
			if(Parent !is null)
				return Alignment.resolve(Parent.updatePosition.size).size;
			else
				return Alignment.resolve(screenSize).size;
		else
			return Position.size;
	}

	vec2i get_desiredSize() const {
		return size;
	}

	Alignment@ get_alignment() {
		if(Alignment is null)
			@Alignment = Alignment(Position);
		return Alignment;
	}

	void set_alignment(Alignment@ align) {
		@Alignment = align;
		updateAbsolutePosition();
	}

	bool get_visible() const {
		return Visible;
	}

	bool get_actuallyVisible() const {
		if(!Visible)
			return false;

		IGuiElement@ ele = Parent;
		while(ele !is null && ele !is gui_root) {
			if(!ele.visible)
				return false;
			@ele = ele.parent;
		}
		return ele !is null;
	}

	bool get_isRoot() const {
		return false;
	}

	bool get_onScreen() const {
		return AbsolutePosition.overlaps(recti(vec2i(), screenSize));
	}

	void set_visible(bool vis) {
		bool prevVisible = Visible;
		Visible = vis;

		if(prevVisible && !Visible && isAncestorOf(getGuiFocus())) {
			IGuiElement@ ele = parent;
			while(ele !is null && !ele.visible)
				@ele = @ele.parent;
			setGuiFocus(ele);
		}
	}

	void set_rect(const recti& rect) {
		size = rect.size;
		position = rect.topLeft;
	}
	
	recti get_rect() const {
		return Position;
	}
	
	void draw() {
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
		}
		clearClip();
	}
	
	IGuiElement@ get_parent() const {
		return Parent;
	}
	
	void set_parent(IGuiElement@ NewParent) {
		if(Parent is NewParent)
			return;
		if(Parent !is null)
			Parent.removeChild(this);
		@Parent = @NewParent;
		if(NewParent !is null)
			NewParent.addChild(this);
		updateAbsolutePosition();
	}

	void addChild(IGuiElement@ ele) {
		Children.insertLast(ele);
	}

	void preserveReparent(IGuiElement@ newParent) {
		recti abs = absolutePosition;
		@parent = newParent;
		if(newParent !is null)
			rect = abs - newParent.absolutePosition.topLeft;
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
		if(Parent !is null) {
			Parent.removeChild(this);
			@Parent = null;

			while(Children.length > 0)
				Children[Children.length - 1].remove();
		}
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
		const IGuiElement@ us = this;
		while(us !is null) {
			if(us is ele)
				return true;
			@us = @us.parent;
		}
		return false;
	}

	bool isFront() {
		if(Parent is null)
			return true;
		return (Parent.getChild(Parent.childCount - 1) is this);
	}

	bool isBack() {
		if(Parent is null)
			return true;
		return (Parent.getChild(0) is this);
	}
	
	void bringToFront() {
		if(Parent !is null)
			Parent.bringToFront(this);
	}

	void sendToBack() {
		if(Parent !is null)
			Parent.sendToBack(this);
	}
	
	void bringToFront(IGuiElement@ ele) {
		if(Children.length != 0)
			if(Children[Children.length - 1] is ele)
				return;
		Children.remove(ele);
		Children.insertLast(ele);
	}

	void sendToBack(IGuiElement@ ele) {
		if(Children.length != 0 && Children[0] is ele)
			return;
		uint offset = 0;
		for(int i = Children.length() - 1; i >= 0; --i) {
			if(Children[i] is ele)
				offset = 1;
			else if(offset != 0)
				@Children[i + offset] = Children[i];
		}
		@Children[0] = ele;
	}

	string get_tooltip() {
		SimpleTooltip@ st = cast<SimpleTooltip@>(Tooltip);
		if(st !is null)
			return st.text;
		else
			return "";
	}
	
	void set_tooltip(const string& ToolText) {
		SimpleTooltip@ st = cast<SimpleTooltip@>(Tooltip);
		if(st !is null)
			st.text = ToolText;
		else
			@Tooltip = SimpleTooltip(ToolText);
	}

	void set_tooltipObject(ITooltip@ tp) {
		@Tooltip = tp;
	}

	ITooltip@ get_tooltipObject() const {
		return Tooltip;
	}

	bool get_noClip() const {
		return NoClip;
	}

	void set_noClip(bool noclip) {
		NoClip = noclip;
	}

	int get_tabIndex() const {
		return TabIndex;
	}

	void set_tabIndex(int ind) {
		TabIndex = ind;
	}

	IGuiElement@ getChild(uint index) {
		if(index >= Children.length())
			return null;
		return Children[index];
	}

	uint get_childCount() const {
		return Children.length();
	}

	void emitChanged(int value = 0) {
		GuiEvent evt;
		evt.value = value;
		evt.type = GUI_Changed;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void emitClicked(int value = 0) {
		GuiEvent evt;
		evt.type = GUI_Clicked;
		evt.value = value;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void emitConfirmed(int value = 0) {
		GuiEvent evt;
		evt.type = GUI_Confirmed;
		evt.value = value;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void emitHoverChanged(int value = 0) {
		GuiEvent evt;
		evt.type = GUI_Hover_Changed;
		evt.value = value;
		@evt.caller = this;
		onGuiEvent(evt);
	}

	void set_navigable(bool value) {
		Navigable = value;
	}

	bool isNavigable(NavigationMode mode) const {
		switch(mode) {
			case NM_None: return false;
			case NM_Action: return Navigable;
			case NM_Tooltip: return tooltipObject !is null;
		}
		return false;
	}

	IGuiElement@ navigate(NavigationMode mode, const vec2d& line) {
		return navigate(mode, absolutePosition, line);
	}

	void clipParent() {
		if(parent is null)
			clearClip();
		else
			setClip(parent.absoluteClipRect);
	}

	void clipParent(const recti& clip) {
		if(parent is null)
			setClip(clip);
		else
			setClip(clip.clipAgainst(parent.absoluteClipRect));
	}

	void resetClip() {
		if(noClip)
			clearClip();
		else
			setClip(absoluteClipRect);
	}

	IGuiElement@ navigate(NavigationMode mode, const recti& box, const vec2d&in line) {
		//Bump the navigation upwards for overriding
		if(Parent !is null)
			return Parent.navigate(mode, box, line);

		float closestDist = FLOAT_INFINITY;
		IGuiElement@ closest;
		closestToLine(mode, box, line.normalized(), closestDist, closest, getGuiFocus());
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
