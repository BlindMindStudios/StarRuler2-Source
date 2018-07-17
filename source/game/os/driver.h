#pragma once
#include "os/key_consts.h"
#include <functional>
#include <string>
#include <list>
#include <vector>

namespace os {

enum WindowMode {
	WM_Fullscreen,
	WM_Window,
};

enum KeyAction {
	KA_Pressed  =   1,
	KA_Released =   2,
	KA_Repeated = 1+4,
};

struct WindowData {
	int width, height;
	int redbits, greenbits, bluebits, alphabits;
	int depthbits, stencilbits;
	int aa_samples;
	int refreshRate;
	bool resizable;
	int verticalSync;
	WindowMode mode;
	std::string targetMonitor;
	bool overrideMonitor;

	WindowData()
	 : width(1024), height(768),
	 redbits(8), greenbits(8), bluebits(8),
	 alphabits(8), depthbits(8), stencilbits(8),
	 aa_samples(4), refreshRate(0), resizable(false),
	 verticalSync(1), mode(WM_Window), overrideMonitor(false) {}
};

enum OSCallback {
	OSC_WindowResize,
	OSC_WindowClose,
	OSC_Key,
	OSC_CharKey,
	OSC_MouseMove,
	OSC_MouseButton,
	OSC_MouseWheel,

	OSC_COUNT
};

template<class Arg0,class Arg1>
struct DriverCallbacks_2 {
	typedef std::function<bool(Arg0,Arg1)> cb;
	std::list<cb> callbacks;

	//Adds the callback to the list, earlier if priority
	void add(cb func, bool priority = false) {
		if(priority)
			callbacks.push_front(func);
		else
			callbacks.push_back(func);
	}

	//Removes a callback previously added to the list
	/*void remove(cb func) {
		callbacks.remove_if([func](cb f) {
			return func.template target<bool(Arg0,Arg1)>() == f.template target<bool(Arg0,Arg1)>();
		});
	}*/

	//Calls each callback in order, stopping if true is returned
	void operator()(Arg0 arg0, Arg1 arg1) {
		for(auto i = callbacks.begin(), end = callbacks.end(); i != end; ++i)
			if((*i)(arg0,arg1))
				break;
	}
};

template<class Arg0>
struct DriverCallbacks_1 {
	typedef std::function<bool(Arg0)> cb;
	std::list<cb> callbacks;

	//Adds the callback to the list, earlier if priority
	void add(cb func, bool priority = false) {
		if(priority)
			callbacks.push_front(func);
		else
			callbacks.push_back(func);
	}

	//Removes a callback previously added to the list
	/*void remove(cb func) {
		callbacks.remove_if([func](cb f) {
			return func.template target<bool(Arg0)>() == f.template target<bool(Arg0)>();
		});
	}*/
	//Calls each callback in order, stopping if true is returned
	void operator()(Arg0 arg0) {
		for(auto i = callbacks.begin(), end = callbacks.end(); i != end; ++i)
			if((*i)(arg0))
				break;
	}
};

struct DriverCallbacks {
	typedef std::function<bool()> cb;
	std::list<cb> callbacks;

	//Adds the callback to the list, earlier if priority
	void add(cb func, bool priority = false) {
		if(priority)
			callbacks.push_front(func);
		else
			callbacks.push_back(func);
	}

	//Removes a callback previously added to the list
	/*void remove(cb func) {
		callbacks.remove_if([func](cb f) {
			return func.template target<bool()>() == f.template target<bool()>();
		});
	}*/

	//Calls each callback in order, stopping if true is returned
	void operator()() {
		for(auto i = callbacks.begin(), end = callbacks.end(); i != end; ++i)
			if((*i)())
				break;
	}
};
	
class OSDriver {
public:
	struct VideoMode {
		unsigned width;
		unsigned height;
		unsigned refresh;
	};

	DriverCallbacks onWindowClose;
	DriverCallbacks_1<unsigned> onCharTyped;
	DriverCallbacks_2<double,double> onScroll;
	DriverCallbacks_2<int,int> onResize, onMouseButton, onMouseMoved, onKeyEvent;

	bool shiftKey, altKey, ctrlKey;
	int win_width, win_height;

	int mouse_x, mouse_y;
	int leftButton, rightButton, middleButton;

	virtual bool systemRandom(unsigned char* buffer, unsigned bytes) = 0;

	virtual void setVerticalSync(int waitFrames) = 0;

	virtual void swapBuffers(double minWait_s = 0) = 0;
	//NOTE: If you need to keep the program awake but can't render, use this instead of swapBuffers
	//		Skips the elapsed time with minimal impact on timers
	virtual void handleEvents(unsigned minWait_ms = 100) = 0;

	virtual void createWindow(WindowData& data) = 0;
	virtual void setWindowTitle(const char* str) = 0;
	virtual void setWindowSize(int width, int height) = 0;
	virtual void closeWindow() = 0;
	virtual bool isWindowFocused() = 0;
	virtual bool isWindowMinimized() = 0;
	virtual bool isMouseOver() = 0;
	virtual void flashWindow() = 0;
	virtual void getVideoModes(std::vector<VideoMode>& output) = 0;
	virtual void getMonitorNames(std::vector<std::string>& output) = 0;

	virtual void getDesktopSize(unsigned& width, unsigned& height) = 0;

	virtual void resetTimer() = 0;
	//Returns time since last reset in ms
	virtual int getTime() const = 0;
	//Returns time since last reset in seconds
	virtual double getAccurateTime() const = 0;

	//Returns the current system time for the frame
	virtual double getFrameTime() const = 0;
	
	//Resets the game timer (implied by resetTimer())
	virtual void resetGameTime(double time) = 0;
	//Returns the current game time
	virtual double getGameTime() const = 0;
	//Sets the game speed as a factor of real time
	virtual void setGameSpeed(double factor) = 0;
	//Returns the current game speed
	virtual double getGameSpeed() const = 0;

	virtual unsigned getProcessorCount() = 0;

	virtual void sleep(int milliseconds) = 0;

	virtual unsigned getDoubleClickTime() const = 0;
	virtual void getMousePos(int& x, int& y) = 0;
	virtual void getLastMousePos(int& x, int& y) = 0;
	virtual void setMousePos(int x, int y) = 0;
	virtual void setCursorVisible(bool visible) = 0;
	virtual void setCursorLocked(bool locked) = 0;
	//Sets whether the cursor should currently lock if set to
	virtual void setCursorShouldLock(bool locked) = 0;

	virtual void setClipboard(const std::string& text) = 0;
	virtual std::string getClipboard() = 0;

	virtual int getCharForKey(int key) = 0;
	virtual int getKeyForChar(unsigned char chr) = 0;

	OSDriver() : shiftKey(false), altKey(false), ctrlKey(false),
			win_width(0), win_height(0), mouse_x(0), mouse_y(0),
			leftButton(false), rightButton(false), middleButton(false) {}
	virtual ~OSDriver() {}
};

};
