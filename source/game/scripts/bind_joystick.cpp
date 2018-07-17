#ifdef _WIN32
#include <Windows.h>
#include <XInput.h>
#endif
#include "GLFW/glfw3.h"
#include "binds.h"

#define JOY_AXIS_MAX 16
#define JOY_BUTTON_MAX 64
#define GLFW_DEADZONE 0.1

#ifdef _WIN32

//As XInput is not available on XP, we need to load it manually
struct XInputLibrary {
	HMODULE dll;

	decltype(XInputGetState)* xInputGetState;
	decltype(XInputSetState)* xInputSetState;

	XInputLibrary() : dll(0), xInputGetState(0) {
	}

	~XInputLibrary() {
		if(dll != NULL)
			FreeLibrary(dll);
	}

	bool load() {
		//There are three current variants of the library, we try to get the most recent one
		//XInput1_4.dll from Window 8
		//XInput1_3.dll from DirectX
		//XInput9_1_0.dll on Vista
		dll = LoadLibrary("XInput1_4.dll");
		if(dll == NULL)
			dll = LoadLibrary("XInput1_3.dll");
		if(dll == NULL)
			dll = LoadLibrary("XInput9_1_0.dll");
		if(dll == NULL)
			return false;

		xInputGetState = (decltype(xInputGetState))GetProcAddress(dll, "XInputGetState");
		xInputSetState = (decltype(xInputSetState))GetProcAddress(dll, "XInputSetState");

		return xInputGetState != 0;
	}

	bool getState(DWORD index, XINPUT_STATE& state) {
		if(!dll || !xInputGetState)
			return false;

		return xInputGetState(index, &state) == ERROR_SUCCESS;
	}

	void setVibration(DWORD index, float lowFreq, float hiFreq) {
		if(xInputSetState) {
			XINPUT_VIBRATION vibration;
			ZeroMemory(&vibration, sizeof(vibration));

			if(lowFreq >= 1.f)
				vibration.wLeftMotorSpeed = 65535;
			else if(lowFreq <= 0.f)
				vibration.wLeftMotorSpeed = 0;
			else
				vibration.wLeftMotorSpeed = (WORD)(lowFreq * 65535.f);

			if(hiFreq >= 1.f)
				vibration.wRightMotorSpeed = 65535;
			else if(hiFreq <= 0.f)
				vibration.wRightMotorSpeed = 0;
			else
				vibration.wRightMotorSpeed = (WORD)(hiFreq * 65535.f);

			xInputSetState(index, &vibration);
		}
	}
} xinput;

#endif

namespace scripts {

enum JoystickButtonState {
	JBS_Off = GLFW_RELEASE,
	JBS_On = GLFW_PRESS,
	JBS_Released,
	JBS_Pressed
};

//TODO: This should go through a driver, not directly glfw
class Joystick {
public:
	bool isXInput;
	int index;

	unsigned axisCount;
	float axes[JOY_AXIS_MAX];

	unsigned buttonCount;
	unsigned char buttons[JOY_BUTTON_MAX];

	Joystick(unsigned Index) : axisCount(0), axes(), buttonCount(0), buttons(), isXInput(false) {
#ifdef _WIN32
		XINPUT_STATE state;
		if(xinput.load() && xinput.getState(Index - 1, state)) {
			index = (int)Index - 1;
			isXInput = true;
			poll();
			return;
		}
#endif
		if(Index >= 1 && Index <= 16)
			index = GLFW_JOYSTICK_1 + (int)Index - 1;
		poll();
	}

	bool poll() {
		if(isXInput) {
#ifdef _WIN32
			XINPUT_STATE state;
			auto buttonUpdate = [this,&state](unsigned btn, bool pressed) {
				auto& button = buttons[btn];
				if(pressed) {
					if(button == JBS_Pressed)
						button = JBS_On;
					else if(button != JBS_On)
						button = JBS_Pressed;
				}
				else {
					if(button == JBS_Released)
						button = JBS_Off;
					else if(button != JBS_Off)
						button = JBS_Released;
				}
			};

			auto deadZone = [](int value, int deadzone, int scale) -> float {
				if(value >= -deadzone && value <= deadzone)
					return 0;
				bool neg = value < 0;
				if(neg)
					value = -value;

				float result = (float)(value - deadzone) / (float)(scale - deadzone);
				return neg ? -result : result;
			};

			if(xinput.getState(index, state)) {
				buttonCount = 16;
				buttonUpdate(0, state.Gamepad.wButtons & XINPUT_GAMEPAD_A);
				buttonUpdate(1, state.Gamepad.wButtons & XINPUT_GAMEPAD_B);
				buttonUpdate(2, state.Gamepad.wButtons & XINPUT_GAMEPAD_X);
				buttonUpdate(3, state.Gamepad.wButtons & XINPUT_GAMEPAD_Y);
				buttonUpdate(4, state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_UP);
				buttonUpdate(5, state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT);
				buttonUpdate(6, state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN);
				buttonUpdate(7, state.Gamepad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT);
				buttonUpdate(8, state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER);
				buttonUpdate(9, state.Gamepad.bLeftTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD);
				buttonUpdate(10, state.Gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB);
				buttonUpdate(11, state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER);
				buttonUpdate(12, state.Gamepad.bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD);
				buttonUpdate(13, state.Gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB);
				buttonUpdate(14, state.Gamepad.wButtons & XINPUT_GAMEPAD_BACK);
				buttonUpdate(15, state.Gamepad.wButtons & XINPUT_GAMEPAD_START);
				
				axisCount = 6;
				axes[0] = deadZone(state.Gamepad.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE, 32768);
				axes[1] = deadZone(state.Gamepad.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE, 32768);
				axes[2] = deadZone(state.Gamepad.sThumbRX, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE, 32768);
				axes[3] = deadZone(state.Gamepad.sThumbRY, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE, 32768);
				axes[4] = deadZone(state.Gamepad.bLeftTrigger, XINPUT_GAMEPAD_TRIGGER_THRESHOLD, 255);
				axes[5] = deadZone(state.Gamepad.bRightTrigger, XINPUT_GAMEPAD_TRIGGER_THRESHOLD, 255);

				return true;
			}
#endif
			return false;
		}
#ifdef LIN_MODE
		else if(true) {
			//Statically figured out button/axes numbers from the xboxdrv linux driver.
			int btnCnt;
			auto* newState = glfwGetJoystickButtons(index, &btnCnt);

			int axCnt;
			const float* glfwAxes = glfwGetJoystickAxes(index, &axCnt);

			auto setButton = [this](unsigned btn, bool pressed) {
				auto& button = buttons[btn];
				if(pressed) {
					if(button == JBS_Pressed)
						button = JBS_On;
					else if(button != JBS_On)
						button = JBS_Pressed;
				}
				else {
					if(button == JBS_Released)
						button = JBS_Off;
					else if(button != JBS_Off)
						button = JBS_Released;
				}
			};

			auto buttonUpdate = [&](unsigned btn, unsigned index) {
				if((int)index >= btnCnt) {
					buttons[btn] = JBS_Off;
					return;
				}
				setButton(btn, newState[index]);
			};

			auto buttonFromAxis = [&](unsigned btn, unsigned index, float thresMin, float thresMax) {
				if((int)index >= axCnt) {
					buttons[btn] = JBS_Off;
					return;
				}

				setButton(btn, glfwAxes[index] >= thresMin && glfwAxes[index] <= thresMax);
			};

			auto axisUpdate = [&](unsigned ax, unsigned index) {
				if((int)index >= axCnt) {
					axes[ax] = 0.f;
					return;
				}

				float val = glfwAxes[index];
				if(val >= -GLFW_DEADZONE && val <= GLFW_DEADZONE)
					axes[ax] = 0.f;
				else if(val < 0)
					axes[ax] = -((-val - GLFW_DEADZONE) / (1.f - GLFW_DEADZONE));
				else
					axes[ax] = (val - GLFW_DEADZONE) / (1.f - GLFW_DEADZONE);
			};

			auto triggerAxis = [&](unsigned ax, unsigned index, float mult) {
				if((int)index >= axCnt) {
					axes[ax] = 0.f;
					return;
				}

				float val = glfwAxes[index] * mult;
				if(val <= -0.9f)
					axes[ax] = 0.f;
				else
					axes[ax] = (val + 0.9f) / 1.9f;
			};

			buttonUpdate(0, 0);
			buttonUpdate(1, 1);
			buttonUpdate(2, 2);
			buttonUpdate(3, 3);
			buttonFromAxis(4, 7, 0.1f, 1.f);
			buttonFromAxis(5, 6, -1.f, -0.1f);
			buttonFromAxis(6, 7, -1.f, -0.1f);
			buttonFromAxis(7, 6, 0.1f, 1.f);
			buttonUpdate(8, 4);
			buttonFromAxis(9, 5, -1.f, 0.f);
			buttonUpdate(10, 9);
			buttonUpdate(11, 5);
			buttonFromAxis(12, 4, 0.f, 1.f);
			buttonUpdate(13, 10);
			buttonUpdate(14, 6);
			buttonUpdate(15, 7);
			buttonCount = 16;

			axisUpdate(0, 0);
			axisUpdate(1, 1);
			axisUpdate(2, 2);
			axisUpdate(3, 3);
			triggerAxis(4, 5, -1.f);
			triggerAxis(5, 4, 1.f);
			axisCount = 6;

			return true;
		}
#endif
		else {
			int cnt;
			auto* newState = glfwGetJoystickButtons(index, &cnt);
			buttonCount = cnt;

			if(buttonCount == 0)
				return false;

			for(unsigned i = 0; i < JOY_BUTTON_MAX; ++i) {
				if(buttons[i] == newState[i])
					continue;

				if(newState[i] == GLFW_PRESS) {
					if(buttons[i] == JBS_Pressed)
						buttons[i] = JBS_On;
					else
						buttons[i] = JBS_Pressed;
				}
				else {
					if(buttons[i] == JBS_Released)
						buttons[i] = JBS_Off;
					else
						buttons[i] = JBS_Released;
				}
			}

			const float* glfwAxes = glfwGetJoystickAxes(index, &cnt);
			axisCount = cnt;

			for(int i = 0; i < cnt && i < JOY_AXIS_MAX; ++i) {
				//Static deadzone, because glfw
				float val = glfwAxes[i];
				if(val >= -GLFW_DEADZONE && val <= GLFW_DEADZONE)
					axes[i] = 0.f;
				else if(val < 0)
					axes[i] = -((-val - GLFW_DEADZONE) / (1.f - GLFW_DEADZONE));
				else
					axes[i] = (val - GLFW_DEADZONE) / (1.f - GLFW_DEADZONE);
			}
			return buttonCount > 0;
		}
	}

	float getAxis(unsigned axis) const {
		if(axis < JOY_AXIS_MAX)
			return axes[axis];
		else
			return 0;
	}

	unsigned char getButton(unsigned id) const {
		if(id < JOY_BUTTON_MAX)
			return buttons[id];
		else
			return JBS_Off;
	}

	bool getPressed(unsigned id) const {
		auto state = getButton(id);
		return state == JBS_On || state == JBS_Pressed;
	}

	bool connected() const {
		return glfwJoystickPresent(index) == GL_TRUE;
	}

	void setVibration(float lowFreq, float hiFreq) {
#ifdef _WIN32
		if(isXInput) {
			xinput.setVibration(index, lowFreq, hiFreq);
		}
#endif
	}

	static void construct(void* memory, unsigned index) {
		new(memory) Joystick(index);
	}
};

void RegisterJoystickBinds() {
	ClassBind joystick("Joystick", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(Joystick));

	joystick.addConstructor("void f(uint)", asFUNCTION(Joystick::construct));
	
	joystick.addMethod("bool connected() const", asMETHOD(Joystick,connected));
	joystick.addMethod("bool poll()", asMETHOD(Joystick,poll));
	joystick.addMethod("float get_axis(uint index) const", asMETHOD(Joystick,getAxis));
	joystick.addMethod("uint8 get_button(uint index) const", asMETHOD(Joystick,getButton));
	joystick.addMethod("bool get_pressed(uint index) const", asMETHOD(Joystick,getPressed));
	joystick.addMethod("void setVibration(float low, float high) const", asMETHOD(Joystick,setVibration));
	
	joystick.addMember("uint axisCount", offsetof(Joystick,axisCount));
	joystick.addMember("uint buttonCount", offsetof(Joystick,buttonCount));

	EnumBind buttonStates("JoystickButtonState");
	buttonStates["JBS_On"] = JBS_On;
	buttonStates["JBS_Off"] = JBS_Off;
	buttonStates["JBS_Pressed"] = JBS_Pressed;
	buttonStates["JBS_Released"] = JBS_Released;

	EnumBind gamepad("GamepadKeys");
	gamepad["GP_A"] = 0;
	gamepad["GP_B"] = 1;
	gamepad["GP_X"] = 2;
	gamepad["GP_Y"] = 3;
	gamepad["GP_UP"] = 4;
	gamepad["GP_LEFT"] = 5;
	gamepad["GP_DOWN"] = 6;
	gamepad["GP_RIGHT"] = 7;
	gamepad["GP_LB"] = 8;
	gamepad["GP_LT"] = 9;
	gamepad["GP_L3"] = 10;
	gamepad["GP_RB"] = 11;
	gamepad["GP_RT"] = 12;
	gamepad["GP_R3"] = 13;
	gamepad["GP_BACK"] = 14;
	gamepad["GP_START"] = 15;
	
	gamepad["GP_AXIS_LX"] = 0;
	gamepad["GP_AXIS_LY"] = 1;
	gamepad["GP_AXIS_RX"] = 2;
	gamepad["GP_AXIS_RY"] = 3;
	gamepad["GP_AXIS_LT"] = 4;
	gamepad["GP_AXIS_RT"] = 5;
}

};
