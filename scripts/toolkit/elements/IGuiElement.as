final tidy class GuiEvent {
	int type;
	int value;
	IGuiElement@ caller;
	IGuiElement@ other;
};

enum GuiEventType {
	//Triggered when the mouse hovers over an element
	//"caller" is the hovered element
	//"other" is the last element that was hovered (can be null)
	//Returning true absorbs the hover event, preventing it from changing
	GUI_Mouse_Entered,
	
	//Triggered when the mouse leaves an element
	//"caller" is the element that is left
	//"other" is the element that is now hovered (can be null)
	//Returning true absorbs the hover event, preventing it from changing
	GUI_Mouse_Left,
	
	//Triggered when an element is focused (e.g. by being clicked)
	//"caller" is the focused element
	//"other" is the old focus (can be null)
	//Returning true absorbs the focus event, preventing it from changing
	GUI_Focused,
	
	//Triggered when an element is no longer focused
	//"caller" is the element that lost focus
	//"other" is the new focus (can be null)
	//Returning true absorbs the focus event, preventing it from changing
	GUI_Focus_Lost,
	
	//Triggered when an element is clicked (not necessarily all elements)
	//"caller" is the element that was clicked
	GUI_Clicked,

	//Triggered when an element is changed (not necessarily all elements)
	//"caller" is the element that was changed
	//  example: dropdown box changing
	GUI_Changed,

	//Triggered when an element changes internal hover (not necessarily all elements)
	//"caller" is the element that changed
	GUI_Hover_Changed,

	//Triggered when an element has an action confirmed (not necessarily all elements)
	//"caller" is the element that was confirmed
	//  example: enter pressed in a textbox
	GUI_Confirmed,

	//Triggered when a keybind button is pressed down
	//"value" is the keybind that was pressed
	GUI_Keybind_Down,

	//Triggered when a keybind button is released
	//"value" is the keybind that was released
	GUI_Keybind_Up,

	//Triggered when an animation finishes.
	//"value" is a custom identifier that was passed for animation.
	GUI_Animation_Complete,

	//Triggered when navigation (ie the controller focus) hits this element.
	GUI_Navigation_Enter,

	//Triggered when navigation (ie the controller focus) leaves this element.
	GUI_Navigation_Leave,

	//Triggered when a controller button is pressed on this element.
	//"value" is the button code that was pressed for action.
	GUI_Controller_Down,

	//Triggered when a controller button is released on this element.
	//"value" is the button code that was released for action.
	GUI_Controller_Up,
};

final tidy class MouseEvent {
	int type;
	int button;
	int x;
	int y;
};

enum MouseEventType {
	MET_Button_Down,
	MET_Button_Up,
	MET_Scrolled,
	MET_Moved,
};

enum MouseButton {
	MB_Left = 0,
	MB_Right = 1,
	MB_Middle = 2,

	MB_DOUBLE = 0x80,
	MB_DoubleLeft = MB_DOUBLE | MB_Left,
	MB_DoubleRight = MB_DOUBLE | MB_Right,
	MB_DoubleMiddle = MB_DOUBLE | MB_Middle,
};

final tidy class KeyboardEvent {
	int type;
	int key;
};

enum KeyboardEventType {
	KET_Key_Down,
	KET_Key_Up,
	KET_Key_Typed,
};

enum NavigationMode {
	NM_None,
	NM_Action,
	NM_Tooltip,
};

interface ITooltip {
	float get_delay();
	bool get_persist();

	void update(const Skin@ skin, IGuiElement@ elem);
	void show(const Skin@ skin, IGuiElement@ elem);
	void draw(const Skin@ skin, IGuiElement@ elem);
	void hide(const Skin@ skin, IGuiElement@ elem);
}

interface IGuiElement {
	void draw();
	
	bool onGuiEvent(const GuiEvent& event);
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source);
	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source);
	
	IGuiElement@ elementFromPosition(const vec2i& pos);

	void move(const vec2i& moveBy);
	void abs_move(const vec2i& moveBy);
	
	void set_position(const vec2i& pos);
	vec2i get_position() const;
	void set_size(const vec2i& size);
	vec2i get_size() const;
	vec2i get_desiredSize() const;
	void set_rect(const recti& rect);
	recti get_rect() const;

	int get_tabIndex() const;
	void set_tabIndex(int ind);
	
	void updateAbsolutePosition();
	recti get_absolutePosition();
	recti get_updatePosition();
	recti get_absoluteClipRect();

	string get_elementType() const;
	int get_id() const;
	bool get_isRoot() const;

	bool get_visible() const;
	bool get_actuallyVisible() const;
	void set_visible(bool vis);

	bool get_onScreen() const;

	bool get_noClip() const;
	void set_noClip(bool noclip);
	
	IGuiElement@ get_parent() const;
	void set_parent(IGuiElement@ NewParent);
	
	void addChild(IGuiElement@ ele);
	void removeChild(IGuiElement@ ele);
	void remove();

	IGuiElement@ getChild(uint index);
	uint get_childCount() const;
	
	bool isFront();
	void bringToFront();
	void bringToFront(IGuiElement@ childToReorder);

	bool isBack();
	void sendToBack();
	void sendToBack(IGuiElement@ childToReorder);
	
	bool isAncestorOf(const IGuiElement@ element) const;
	bool isChildOf(const IGuiElement@ element) const;
	
	string get_tooltip();
	void set_tooltip(const string& ToolText);
	void set_tooltipObject(ITooltip@ ToolTip);
	ITooltip@ get_tooltipObject() const;

	bool isNavigable(NavigationMode mode) const;
	IGuiElement@ navigate(NavigationMode mode, const vec2d& line);
	IGuiElement@ navigate(NavigationMode mode, const recti& box, const vec2d&in line);
	void closestToLine(NavigationMode mode, const recti& box, const vec2d&in line, float& closestDist, IGuiElement@& closest, IGuiElement@ skip);
};
