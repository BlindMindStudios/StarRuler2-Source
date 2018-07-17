import elements.IGuiElement;
from gui import onMouseEvent, onKeyboardEvent;

void onMouseMoved(int x, int y) {
	MouseEvent evt;
	evt.type = MET_Moved;
	evt.x = x;
	evt.y = y;
	onMouseEvent(evt);
}

bool onMouseButton(int button, bool pressed) {
	MouseEvent evt;
	if(pressed)
		evt.type = MET_Button_Down;
	else
		evt.type = MET_Button_Up;
	evt.button = button;
	vec2i mpos = mousePos;
	evt.x = mpos.x;
	evt.y = mpos.y;
	return onMouseEvent(evt);
}

bool onCharTyped(int chr) {
	KeyboardEvent evt;
	evt.type = KET_Key_Typed;
	evt.key = chr;
	return onKeyboardEvent(evt);
}

bool onKeyEvent(int key, int keyaction) {
	KeyboardEvent evt;
	bool pressed = (keyaction & KA_Pressed) != 0;
	if(pressed)
		evt.type = KET_Key_Down;
	else
		evt.type = KET_Key_Up;
	evt.key = key;
	return onKeyboardEvent(evt);
}

void onMouseWheel(double x, double y) {
	MouseEvent evt;
	evt.type = MET_Scrolled;
	evt.x = int(floor(x));
	evt.y = int(floor(y));
	onMouseEvent(evt);
}

void main_menu(bool pressed) {
	if(pressed) {
		if(game_state == GS_Menu) {
			if(game_running)
				switchToGame();
		}
		else
			switchToMenu();
	}
}

void init() {
	keybinds::Global.addBind(KB_TOGGLE_MENU, "main_menu");
}
