#include "main/references.h"
#include "main/input_handling.h"
#include "main/initialization.h"
#include "main/tick.h"
#include "main/console.h"
#include "os/driver.h"
#include <set>

#include "processing.h"

#define func(x) std::function<decltype(x)>(x)

enum InputCall {
	IC_MouseWheel,
	IC_MouseDrag,
	IC_MouseDragEnd,
	IC_MouseMove,
	IC_MouseClick,
	IC_MouseButton,
	IC_CharTyped,
	IC_KeyEvent,
	IC_DoubleClick,
	IC_Overlay,

	IC_COUNT
};

const char* InputCallDecls[IC_COUNT] = {
	"void onMouseWheel(double,double)",
	"void onMouseDragged(int, int, int, int, int)",
	"bool onMouseDragEnd(int)",
	"void onMouseMoved(int, int)",
	"void onMouseClicked(int)",
	"bool onMouseButton(int, bool)",
	"bool onCharTyped(int)",
	"bool onKeyEvent(int, int)",
	"void onMouseDoubleClicked(int)",
	"void onOverlayChanged(bool)",
};

asIScriptFunction* inputCalls[GS_COUNT][IC_COUNT];
scripts::Manager* manager[GS_COUNT];

INIT_FUNC(clear_input) {
	memset(inputCalls, 0, IC_COUNT * GS_COUNT * sizeof(asIScriptFunction*));
	memset(manager, 0, GS_COUNT * sizeof(scripts::Manager*));
} INIT_FUNC_END;

void clearInputScripts(GameState state) {
	memset(inputCalls[state], 0,  IC_COUNT * sizeof(asIScriptFunction*));
	manager[state] = 0;
}

void bindInputScripts(GameState state, scripts::Manager* Manager) {
	if(Manager)
		manager[state] = Manager;

	if(!Manager) {
		clearInputScripts(state);
		return;
	}

	for(unsigned i = 0; i < IC_COUNT; ++i)
		inputCalls[state][i] = manager[state]->getFunction("input", InputCallDecls[i]);
}

void onOverlayToggle(bool state) {
	if(manager[game_state] && inputCalls[game_state][IC_Overlay]) {
		auto call = manager[game_state]->call(inputCalls[game_state][IC_Overlay]);
		call.push(state);
		call.call();
	}
}

bool onWindowClose() {
	game_state = GS_Quit;
	return true;
}

bool onCharTyped(int key) {
	if(console.character(key))
		return true;
	//Inform the script
	bool ret = true;
	if(manager[game_state] && inputCalls[game_state][IC_CharTyped]) {
		auto call = manager[game_state]->call(inputCalls[game_state][IC_CharTyped]);
		call.push(key);
		call.call(ret);
	}
	return ret;
}

std::set<profile::Keybind*> pressedKeys;
void onModifiersChanged() {
	foreach(key, pressedKeys)
		(*key)->call(false);
	pressedKeys.clear();
}

void clearPressedKeys() {
	pressedKeys.clear();
}

bool onKeyEvent(int key, int keyaction) {
	bool pressed = keyaction & os::KA_Pressed;

	//Figure out if the modifier mask was changed
	switch(key) {
		case os::KEY_LCTRL:
		case os::KEY_RCTRL:
		case os::KEY_LALT:
		case os::KEY_RALT:
		case os::KEY_LSHIFT:
		case os::KEY_RSHIFT:
			onModifiersChanged();
		break;
	}

	//Build key with modifiers
	int mod_key = key;
	if(mod_key >= 'A' && mod_key <= 'Z')
		mod_key += 'a'-'A';
	profile::Keybind* bind = devices.keybinds.global.getBind(mod_key);

	if(devices.driver->ctrlKey)
		mod_key |= profile::Mod_Ctrl;
	if(devices.driver->altKey)
		mod_key |= profile::Mod_Alt;
	if(devices.driver->shiftKey)
		mod_key |= profile::Mod_Shift;
	profile::Keybind* mod_bind = devices.keybinds.global.getBind(mod_key);
	if(mod_bind)
		bind = mod_bind;

	if(bind != console.keybind && console.key(key, pressed))
		return true;

	//Inform the script
	if(manager[game_state] && inputCalls[game_state][IC_KeyEvent]) {
		bool ret = false;
		auto call = manager[game_state]->call(inputCalls[game_state][IC_KeyEvent]);
		call.push(key);
		call.push(keyaction);
		call.call(ret);
		if(ret)
			return true;
	}

	if(console.globalKey(key, pressed))
		return true;

	//Trigger Keybinds
	if(bind) {
		bind->call(pressed);
		if(pressed)
			pressedKeys.insert(bind);
		else
			pressedKeys.erase(bind);
		return true;
	}
	return true;
}

struct MouseKey {
	bool pressed;
	int pressed_time;

	MouseKey() : pressed(false), pressed_time(0) {}
} mouseButtons[3];

int dragging = 0;
int pressed_x = 0, pressed_y = 0;
int cur_x = 0, cur_y = 0;
int tot_drag = 0;
const int dblClickTimeout = 200;

bool onMouseButton(int button, int pressed) {
	//When the mouse is being dragged at the system level, don't pass it to the GUI
	if(dragging) {
		if(pressed) {
			dragging |= (0x1 << button);
			mouseButtons[button].pressed = true;
		}
		else {
			dragging &= ~(0x1 << button);
			mouseButtons[button].pressed = false;
		}

		if(!dragging) {
			devices.driver->setCursorVisible(true);

			if(tot_drag > 4) {
				tot_drag = 0;
				bool resetMouse = true;

				if(manager[game_state] && inputCalls[game_state][IC_MouseDragEnd]) {
					auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseDragEnd]);
					call.push(button);
					call.call(resetMouse);
				}

				if(resetMouse)
					devices.driver->setMousePos(pressed_x, pressed_y);
				return true;
			}

			tot_drag = 0;
		}
	}

	if(pressed == 0)
		mouseButtons[button].pressed = false;

	bool eventAbsorbed = false;
	if(manager[game_state]) {
		//Pass button event to scripts
		if(inputCalls[game_state][IC_MouseButton]) {
			auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseButton]);
			call.push(button);
			call.push(pressed == 1);
			call.call(eventAbsorbed);
		}

		//Pass click events to scripts
		if(!pressed) {
			int time = devices.driver->getTime();
			if(mouseButtons[button].pressed_time > time - dblClickTimeout) {
				mouseButtons[button].pressed_time = 0;

				if(inputCalls[game_state][IC_DoubleClick]) {
					auto call = manager[game_state]->call(inputCalls[game_state][IC_DoubleClick]);
					call.push(button);
					call.call();
				}
			}
			else {
				mouseButtons[button].pressed_time = time;

				if(inputCalls[game_state][IC_MouseClick]) {
					auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseClick]);
					call.push(button);
					call.call();
				}
			}
		}
	}

	if(pressed != 0 && !eventAbsorbed) {
		mouseButtons[button].pressed = true;

		if(!dragging) {
			devices.driver->getMousePos(pressed_x, pressed_y);
			cur_x = pressed_x;
			cur_y = pressed_y;
		}
	}
	return false;
}

bool onMouseMoved(int x, int y) {
	int prevDragging = dragging;
	dragging = (mouseButtons[0].pressed ? 0x1 : 0)
			| (mouseButtons[1].pressed ? 0x2 : 0)
			| (mouseButtons[2].pressed ? 0x4 : 0);

	if(dragging) {
		if(!prevDragging)
			devices.driver->setCursorVisible(false);

		if(manager[game_state] && inputCalls[game_state][IC_MouseDrag]) {
			int dx = x-cur_x, dy = cur_y-y;
			tot_drag += abs(dx) + abs(dy);

			if(dx || dy) {
				auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseDrag]);
				call.push(dragging);
				call.push((int)(pressed_x / ui_scale));
				call.push((int)(pressed_y / ui_scale));
				call.push(dx);
				call.push(dy);
				call.call();

				cur_y = y;
				cur_x = x;
			}
			return true;
		}
	}

	if(manager[game_state] && inputCalls[game_state][IC_MouseMove]) {
		//Pass move event to scripts
		auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseMove]);
		call.push((int)(x / ui_scale));
		call.push((int)(y / ui_scale));
		call.call();
	}
	return true;
}

bool onMouseWheel(double x, double y) {
	if(manager[game_state] && inputCalls[game_state][IC_MouseWheel]) {
		auto call = manager[game_state]->call(inputCalls[game_state][IC_MouseWheel]);
		call.push(x);
		call.push(y);
		call.call();
	}
	return true;
}


void registerInput() {
	//Add base callbacks for os driver
	devices.driver->onWindowClose.add(onWindowClose);
	//devices.driver->onResize.add(onWindowClose);
	devices.driver->onScroll.add(onMouseWheel);
	devices.driver->onMouseButton.add(onMouseButton);
	devices.driver->onMouseMoved.add(onMouseMoved);
	devices.driver->onCharTyped.add(onCharTyped);
	devices.driver->onKeyEvent.add(onKeyEvent);
}

void inputTick() {
	if(dragging) {
		cur_x = pressed_x;
		cur_y = pressed_y;
		devices.driver->setMousePos(pressed_x, pressed_y);
	}
}
