import elements.BaseGuiElement;

enum TabCategory {
	TC_Invalid,
	TC_Other,
	TC_Galaxy,
	TC_Designs,
	TC_Home,
	TC_Research,
	TC_Graphics,
	TC_Diplomacy,
	TC_Planets,
	TC_Wiki,
	TC_Attitudes,
};

class Tab : BaseGuiElement {
	string title;
	Tab@ previous;
	IGuiElement@ prevFocus = this;
	bool initialized = false;
	bool flashing = false;
	bool locked = false;

	Tab() {
		super(null, recti());
		visible = false;
	}

	//Called when the tab is first created and positioned
	void init() {
	}

	//Called when the tab is asked to close
	// hide() will also be called first when closing a visible tab
	void close() {
		@prevFocus = null;
	}

	//Called when a closed tab needs to be reopened
	// show() will also be called afterwards
	void reopen() {
	}

	//Call to flash the tab in the tabbar until focused
	void flash() {
		if(!visible)
			flashing = true;
	}

	//Get the title for the tab
	string& get_title() {
		return title;
	}

	void set_title(const string& newTitle) {
		title = newTitle;
	}

	//Get the icon for the tab
	Sprite get_icon() {
		return Sprite();
	}

	//Get the colors for the tab
	Color get_activeColor() {
		return Color(0xffffffff);
	}

	Color get_inactiveColor() {
		return Color(0xffffffff);
	}
	
	Color get_seperatorColor() {
		return Color(0xffffffff);
	}

	//Get the tab category
	TabCategory get_category() {
		return TC_Other;
	}

	//Show the tab and do any necessary syncing
	void show() {
		updateAbsolutePosition();
		visible = true;
		flashing = false;
		setGuiFocus(prevFocus);
	}

	//Hide the tab and do any necessary cleanup
	void hide() {
		@prevFocus = getGuiFocus();
		visible = false;
	}

	//Tick the tab. This is called regardless
	//of whether the tab is visible, so the tab itself
	//needs to figure what it needs to update
	void tick(double time) {
	}
	
	//Called before any ticks, rendering or node animation
	//Should update camera position for the next frame when necessary
	void preRender(double time) {
	}

	//Called when the 3D scene should be rendered,
	//if any exists in this tab
	void render(double time) {
	}
	
	//Called whenever an object is clicked
	//Return true to prevent whatever other behaviors would normally occur
	bool objectInteraction(Object& object, uint mouseButton, bool doubleClick) {
		return false;
	}

	//Called for utilising the joystick. Return true if the joystick is grabbed.
	bool joystick(Joystick& joystick) {
		return false;
	}

	void save(SaveFile& file) {
	}

	void load(SaveFile& file) {
	}
};
