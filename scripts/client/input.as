//input.as
//--------
//Various script callbacks for global input handling.
//Also handles passing events to the GUI

#priority init 1
import elements.IGuiElement;
import targeting.targeting;
import navigation.SmartCamera;
import util.convar;
from navigation.elevation import getElevationIntersect;

import bool onMouseEvent(const MouseEvent&) from "gui";
import bool onKeyboardEvent(const KeyboardEvent&) from "gui";
import bool onGuiEvent(const GuiEvent&) from "gui";
import void onGuiNavigate(vec2d direction) from "gui";
import IGuiElement@ getGuiFocus() from "gui";
import bool isGuiHovered() from "gui";
import void selectionClick(uint button, bool pressed) from "obj_selection";
import void dragSelect(const recti&) from "obj_selection";
import Object@ get_hoveredObject() from "obj_selection";
import Object@ get_selectedObject() from "obj_selection";
import Object@ get_uiObject() from "obj_selection";
import void updateHoveredObject() from "obj_selection";
import bool objectKeyEvent(int key, bool pressed) from "commands";
import void switchToTab(int pos) from "tabs.tabbar";
import bool tabEscape() from "tabs.tabbar";
import double getAverageElevation() from "navigation.elevation";

ConVar FollowAI("follow_ai", 0);

//TODO: Anything directly using the engine camera should go through the camera module

const double tickZoom = 1.2;
const double zoomPerPixel = 0.01;
const double camAnglesPerPixel = 0.22 * twopi / 360.0;
const double movePerPixel = 0.001;
const double zoomPerSecond = 0.45;
const double rollBorder = 0.4;
const double camMotionPerSecond = 80.0;

vec2i dragArea, dragFrom;
array<double> edgePanDelay = {0.0, 0.0, 0.0, 0.0};
array<double> edgePanRampup = {0.3, 0.3, 0.3, 0.3};
array<double> edgePanTimers = {0.0, 0.0, 0.0, 0.0};
bool doingBoxSelect = false;

Joystick joystick(1);
bool joystickConnected = false;
bool joystickActive = false;

SmartCamera@ ActiveCamera;
SmartCamera PreviousCamera;

SmartCamera@ get_activeCamera() {
	return ActiveCamera;
}

SmartCamera@ get_lastCamera() {
	if(ActiveCamera !is null)
		return ActiveCamera;
	return PreviousCamera;
}

void set_activeCamera(SmartCamera@ cam) {
	if(ActiveCamera !is null)
		PreviousCamera = ActiveCamera;

	@ActiveCamera = cam;
}

void copyPreviousCamera(SmartCamera@ cam) {
	if(ActiveCamera !is null)
		cam = ActiveCamera;
	else
		cam = PreviousCamera;
}

vec3d mouseToGrid(vec2i mpos) {
	double plane = getAverageElevation();
	vec3d dest;
	line3dd ray = ActiveCamera.screenToRay(mpos);
	if(!getElevationIntersect(ray, dest))
		ray.intersectY(dest, plane, false);
	return dest;
}

vec3d mouseToGrid(vec2i mpos, double plane) {
	vec3d dest;
	line3dd ray = ActiveCamera.screenToRay(mpos);
	if(!getElevationIntersect(ray, dest))
		ray.intersectY(dest, plane, false);
	return dest;
}

void take_screenshot(bool pressed) {
	if(!pressed)
		takeScreenshot("screenshot");
}

//Called when the platform overlay (e.g. Steam Overlay) is opened or closed
double prevGameSpeed = 1.0;
void onOverlayChanged(bool overlayOpen) {
	if(!mpServer && !mpClient) {
		if(overlayOpen) {
			prevGameSpeed = gameSpeed;
			gameSpeed = 0.0;
		}
		else {
			gameSpeed = prevGameSpeed;
		}
	}
}

//Called whenever the mouse wheel is used on the 3D view.
// x: Amount scrolled horizontally.
// y: Amount scrolled vertically.
void onMouseWheel(double x, double y) {
	if(isGuiHovered() || ActiveCamera is null) {
		MouseEvent evt;
		evt.type = MET_Scrolled;
		evt.x = int(floor(x));
		evt.y = int(floor(y));
		onMouseEvent(evt);
		return;
	}

	if(targetMouseWheel(x, y))
		return;

	activeCamera.zoom(y);
}

//Called when the mouse is dragged with one or more buttons
//pressed on the 3D view.
// buttons: Bitmask of pressed buttons (0x1 << button_num)
// x: Mouse x position.
// y: Mouse y position.
// dx: Movement in the x dimension since last event.
// dy: Movement in the y dimension since last event.
void onMouseDragged(int buttons, int x, int y, int dx, int dy) {
	if(activeCamera is null)
		return;
	if(targetMouseDragged(buttons, x, y, dx, dy))
		return;

	Camera@ cam = activeCamera.camera;
	vec2i screen = screenSize;

	if(buttons == 0x1) {
		doingBoxSelect = true;
		dragArea += vec2i(dx,-dy);
		dragFrom = vec2i(x,y);
	}
	else if(buttons == 0x2) {
		double dist = sqrt(sqr(double(x)/double(screen.x) - 0.5)
							+ sqr(double(y)/double(screen.y) - 0.5));

		if(settings::bEdgeRoll && rollBorder < dist) {
			if(x < screen.x / 2)
				activeCamera.roll(dy);
			else
				activeCamera.roll(-dy);
		}
		else {
			activeCamera.rotate(dx, dy);
		}
	}
	else if(buttons == 0x3) {
		//-- Left and right buttons
		if(settings::bInvertHorizRot)
			dx = -dx;

		//Horizontal movement does an absolute yaw
		if(cam.inverted)
			cam.abs_yaw(double(-dx) * camAnglesPerPixel);
		else
			cam.abs_yaw(double(dx) * camAnglesPerPixel);

		//Vertical movement zooms
		cam.zoom(1.0 + zoomPerPixel * double(-dy));
		CAM_ZOOMED = true;
	}
	else if(buttons == 0x4) {
		//-- Only middle button
		//Pan the world
		activeCamera.pan(dx, dy);
	}
}

//Called when a drag event thas ended
bool onMouseDragEnd(int button) {
	if(targetMouseDragEnd(button))
		return true;
	if(doingBoxSelect) {
		if(button != 0) {
			doingBoxSelect = false;
			return false;
		}
		recti box = recti_area(dragFrom, dragArea);
		
		//Make sure the rect is oriented top-down, left-right
		if(box.topLeft.x > box.botRight.x) {
			int temp = box.topLeft.x;
			box.topLeft.x = box.botRight.x;
			box.botRight.x = temp;
		}
		if(box.topLeft.y > box.botRight.y) {
			int temp = box.topLeft.y;
			box.topLeft.y = box.botRight.y;
			box.botRight.y = temp;
		}
		
		dragSelect(box);
		
		//Place the cursor to the dragged destination
		doingBoxSelect = false;
		mousePos = dragFrom + dragArea;
		return false;
	}
	return true;
}

//Called when the mouse is moved over the 3d view without
//any buttons being held.
// x: Mouse x position.
// y: Mouse y position.
void onMouseMoved(int x, int y) {
	MouseEvent evt;
	evt.type = MET_Moved;
	evt.x = x;
	evt.y = y;
	if(onMouseEvent(evt))
		return;
	if(targetMouseMoved(x, y))
		return;
}

//Called when a mouse button is clicked
// buttons: Button that was clicked.
//void onMouseClicked(int button) {
//}

//Called when a mouse button is double-clicked
// buttons: Button that was clicked.
//void onMouseDoubleClicked(int button) {
//}

//General handler for when a mouse button event occurs
// button: Button that the event pertains to.
// pressed: Whether the button was pressed or released.
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
	
	bool fromTarget = uiObject !is null;
	if(fromTarget && targetMouseButton(button, pressed))
		return false;
	if(onMouseEvent(evt))
		return true;
	if(!fromTarget && targetMouseButton(button, pressed))
		return false;
	if(pressed)
		dragArea = vec2i(0,0);
	selectionClick(button, pressed);
	return false;
}

//Called when a unicode char is typed into the main 3D view.
// chr: Unicode code point that was typed.
bool onCharTyped(int chr) {
	KeyboardEvent evt;
	evt.type = KET_Key_Typed;
	evt.key = chr;
	return onKeyboardEvent(evt);
}

//Called when a key event occurs when the 3D view has focus.
// key: Keyboard key that was pressed.
// pressed: Whether the key was pressed or released.
bool onKeyEvent(int key, int keyaction) {
	KeyboardEvent evt;
	bool pressed = (keyaction & KA_Pressed) != 0;
	if(pressed)
		evt.type = KET_Key_Down;
	else
		evt.type = KET_Key_Up;
	evt.key = key;
	if(onKeyboardEvent(evt))
		return true;
	if(objectKeyEvent(key, pressed))
		return true;
	if(targetKeyEvent(key, pressed))
		return true;
	if(pressed && key == KEY_ESC) {
		if(tabEscape())
			return true;
	}
	return false;
}

uint[] worldMove = {0, 0, 0, 0};
void world_forward(bool pressed) {
	worldMove[3] = pressed ? 1 : 0;
}

void world_left(bool pressed) {
	worldMove[0] = pressed ? 1 : 0;
}

void world_right(bool pressed) {
	worldMove[2] = pressed ? 1 : 0;
}

void world_backward(bool pressed) {
	worldMove[1] = pressed ? 1 : 0;
}

void reset_cam(bool pressed) {
	if(!pressed && activeCamera !is null) {
		Camera@ cam = activeCamera.camera;
		activeCamera.reset();
		Object@ hw = playerEmpire.Homeworld;
		if(hw is null)
			@hw = selectedObject;
		if(hw !is null)
			activeCamera.zoomTo(hw);
		else
			activeCamera.zoomTo(vec3d());
		cam.snap();
	}
}

uint[] zoom = {0, 0};
void zoom_in(bool pressed) {
	zoom[0] = pressed ? 1 : 0;
}

void zoom_out(bool pressed) {
	zoom[1] = pressed ? 1 : 0;
}

void zoom_object(bool pressed) {
	if(!pressed && ActiveCamera !is null) {
		Object@ sel = selectedObject;
		if(sel !is null && sel.visible)
			ActiveCamera.zoomLockObject(sel);
	}
}

double threshold(double x, double thresh) {
	if(abs(x) < thresh)
		return 0.0;
	else
		return x;
}

bool leftCannon = false;
bool movePressed = false;

void onControllerButton(int i, bool pressed) {
	joystickActive = true;
	if(pressed) {
		if(i == GP_LB)
			switchToTab(-1);
		else if(i == GP_RB)
			switchToTab(+1);
	}
}

GuiEvent joyGuiEvent;

vec3d lastAIFocus;

void tick(double time) {
	if(game_state != GS_Game)
		return;
	
	if(FollowAI.value != 0) {
		vec3d to = playerEmpire.aiFocus;
		if(to != lastAIFocus) {
			activeCamera.zoomTo(to);
			lastAIFocus = to;
		}
	}
	
	double tickMotion = time * camMotionPerSecond * 60.0;

	//Polling a disconnected joystick on Windows takes ~10ms, so avoid it
	if(joystickConnected && joystick.poll()) {	
		//Send buttons to gui
		for(uint i = 0, cnt = joystick.buttonCount; i < cnt; ++i) {
			uint8 state = joystick.button[i];
			if(state == JBS_Pressed) {
				//GUI Event
				joyGuiEvent.type = GUI_Controller_Down;
				joyGuiEvent.value = i;
				@joyGuiEvent.caller = getGuiFocus();
				if(!onGuiEvent(joyGuiEvent))
					onControllerButton(i, true);
			}
			else if(state == JBS_Released) {
				//GUI Event
				joyGuiEvent.type = GUI_Controller_Up;
				joyGuiEvent.value = i;
				@joyGuiEvent.caller = getGuiFocus();
				if(!onGuiEvent(joyGuiEvent))
					onControllerButton(i, false);
			}
		}

		if(activeCamera !is null) {
			//Panning with left analog
			vec2d pan = vec2d(-joystick.axis[GP_AXIS_LX], joystick.axis[GP_AXIS_LY]);
			if(pan.length > 0.05) {
				pan.normalize(tickMotion * 0.7);
				activeCamera.pan(pan);
				mousePos = screenSize * 0.5;
				joystickActive = true;
			}
			
			//Zoom and rotate with right analog
			double zoom = -joystick.axis[GP_AXIS_RY];
			if(abs(zoom) > 0)
				activeCamera.camera.zoom(1.0 + 7.0 * zoomPerSecond * zoom * time * settings::dZoomSpeed);
			
			double yaw = -joystick.axis[GP_AXIS_RX];
			if(abs(yaw) > 0)
				activeCamera.rotate(600.0 * yaw * time, 0);
		}
		else {
			//Navigate gui with left stick
			vec2d dir = vec2d(joystick.axis[GP_AXIS_LX], -joystick.axis[GP_AXIS_LY]);
			if(dir.length > 0.25) {
				if(!movePressed)
					onGuiNavigate(dir);
				movePressed = true;
			}
			else {
				movePressed = false;
			}
		}

		/*for(uint i = 0; i < joystick.buttonCount; ++i) {
			uint8 state = joystick.button[i];
			if(state == JBS_Pressed)
				print("Joystick 1, key " + i + " pressed");
			else if(state == JBS_Released)
				print("Joystick 1, key " + i + " released");
		}
		
		for(uint i = 0; i < joystick.axisCount; ++i) {
			double axis = joystick.axis[i];
			if(abs(axis) > 0.01)
				print("Joystick axis " + i + ": " + axis);
		}*/
		
		if(joystickActive)
			updateHoveredObject();
	}

	if(activeCamera is null)
		return;

	Camera@ cam = activeCamera.camera;
	bool inverted = cam.inverted;
	
	vec2d move;

	//Handle edge panning
	vec2i mouse = mousePos;
	if(settings::bEdgePan && windowFocused && mouseOverWindow) {
		vec2i screen = screenSize;

		if(mouse.x <= 0) {
			edgePanTimers[0] += time;
			if(edgePanTimers[0] >= edgePanDelay[0]) {
				move.x += 1;
				if(edgePanRampup[0] > 0)
					tickMotion *= clamp((edgePanTimers[0] - edgePanDelay[0]) / edgePanRampup[0], 0.0, 1.0);
			}
		}
		else {
			edgePanTimers[0] = 0.0;
		}

		if(mouse.x >= screen.x - 2) {
			edgePanTimers[1] += time;
			if(edgePanTimers[1] >= edgePanDelay[1]) {
				move.x -= 1;
				if(edgePanRampup[1] > 0)
					tickMotion *= clamp((edgePanTimers[1] - edgePanDelay[1]) / edgePanRampup[1], 0.0, 1.0);
			}
		}
		else {
			edgePanTimers[1] = 0.0;
		}

		if(mouse.y <= 0) {
			edgePanTimers[2] += time;
			if(edgePanTimers[2] >= edgePanDelay[2]) {
				move.y += 1;
				if(edgePanRampup[2] > 0)
					tickMotion *= clamp((edgePanTimers[2] - edgePanDelay[2]) / edgePanRampup[2], 0.0, 1.0);
			}
		}
		else {
			edgePanTimers[2] = 0.0;
		}

		if(mouse.y >= screen.y - 2) {
			edgePanTimers[3] += time;
			if(edgePanTimers[3] >= edgePanDelay[3]) {
				move.y -= 1;
				if(edgePanRampup[0] > 0)
					tickMotion *= clamp((edgePanTimers[3] - edgePanDelay[3]) / edgePanRampup[3], 0.0, 1.0);
			}
		}
		else {
			edgePanTimers[3] = 0.0;
		}
	}

	//Move the world in the direction the keys were pressed
	if(worldMove[0] ^ worldMove[2] != 0) {
		if(worldMove[0] != 0)
			move.x += 1;
		else
			move.x += -1;
	}
	if(worldMove[1] ^ worldMove[3] != 0) {
		if(worldMove[1] != 0)
			move.y += -1;
		else
			move.y += 1;
	}

	if(move.x != 0 || move.y != 0) {
		move.normalize(tickMotion);
		activeCamera.pan(move);
	}

	//Zoom the camera appropriately
	if(zoom[0] ^ zoom[1] != 0) {
		if(zoom[0] != 0)
			cam.zoom(1.0 - zoomPerSecond * time * settings::dZoomSpeed);
		else
			cam.zoom(1.0 + zoomPerSecond * time * settings::dZoomSpeed);
	}
}

void init() {
	keybinds::Global.addBind(KB_WORLD_FORWARD, "world_forward");
	keybinds::Global.addBind(KB_WORLD_LEFT, "world_left");
	keybinds::Global.addBind(KB_WORLD_RIGHT, "world_right");
	keybinds::Global.addBind(KB_WORLD_BACKWARD, "world_backward");

	keybinds::Global.addBind(KB_ZOOM_IN, "zoom_in");
	keybinds::Global.addBind(KB_ZOOM_OUT, "zoom_out");

	keybinds::Global.addBind(KB_RESET_CAM, "reset_cam");
	keybinds::Global.addBind(KB_TAKE_SCREENSHOT, "take_screenshot");

	keybinds::Global.addBind(KB_ZOOM_LOCK_OBJECT, "zoom_object");
	
	//joystickConnected = joystick.connected();
	PreviousCamera.reset();

	if(settings::bDelayTopEdge) {
		edgePanDelay[2] = 0.3;
		edgePanRampup[2] = 0.0;
	}
}

void draw() {
	if(doingBoxSelect)
		drawRectangle(recti_area(dragFrom, dragArea), Color(0x00ff0040));
}
