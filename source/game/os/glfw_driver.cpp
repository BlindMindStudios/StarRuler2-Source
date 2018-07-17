#include "os/glfw_driver.h"
#include "compat/misc.h"
#include "compat/gl.h"
#include "main/game_platform.h"
#include "main/references.h"
#include "main/logging.h"
#include "threads.h"
#include "vec2.h"
#include <list>
#include <math.h>
#include <set>
#include <algorithm>

#ifndef WIN_MODE
#include <sys/time.h>
#include <random>
#else

//Undef duplicate macros from glfw
#undef APIENTRY
#undef WINGDIAPI

#include <Windows.h>
#include <WinCrypt.h>
#include "os/resource.h"
#endif

//We use std::max instead
#undef max

extern bool game_running;

namespace os {

void redirectWindowClose(GLFWwindow*);
void redirectWindowResize(GLFWwindow*,int, int);
void redirectSpecialKey(GLFWwindow*,int key, int scan, int action, int mods);
void redirectCharKey(GLFWwindow*,unsigned);
void redirectMouseButton(GLFWwindow*,int button, int action, int mods);
void redirectMouseMove(GLFWwindow*,double x, double y);
void redirectMouseWheel(GLFWwindow*,double x, double y);
void trackMouseOver(GLFWwindow*,int over);
void glfwError(int, const char*);

class GLFWDriver;
GLFWDriver* driver = 0;

class GLFWDriver : public OSDriver {
	union Callback {
		std::function<bool(void)>* f_v;
		std::function<bool(int)>* f_i;
		std::function<bool(int,int)>* f_ii;

		Callback(decltype(f_v) p_f_v) : f_v(p_f_v) {}
		Callback(decltype(f_i) p_f_i) : f_i(p_f_i) {}
		Callback(decltype(f_ii) p_f_ii) : f_ii(p_f_ii) {}
	};

	std::list<Callback> callbacks[OSC_COUNT];
	GLFWwindow* window;

public:
#ifndef WIN_MODE
	timeval start_time;
#else
	ULARGE_INTEGER start_time;

	LARGE_INTEGER start_time_hq, start_time_hq_freq;
#endif

	bool mouseOver;
	bool canLock, shouldLock;

	double frameTime, gameTime, gameSpeed;

	GLFWDriver() : window(0), mouseOver(true), canLock(false), shouldLock(false) {
		glfwSetErrorCallback(glfwError);
		glfwInit();
		resetTimer();
	}

	~GLFWDriver() {
		driver = 0;
		glfwTerminate();
	}
	
	bool systemRandom(unsigned char* buffer, unsigned bytes) {
#ifdef WIN_MODE
		HCRYPTPROV provider;
		
		//Attempt to acquire the context if it exists, then make it if it does not
		BOOL ctx = CryptAcquireContext(&provider, "SR2SysRand", NULL, PROV_RSA_AES, NULL);
		if(!ctx)
			ctx = CryptAcquireContext(&provider, "SR2SysRand", NULL, PROV_RSA_AES, CRYPT_NEWKEYSET);

		if(ctx) {
			BOOL success = CryptGenRandom(provider, bytes, buffer);
			CryptReleaseContext(provider, NULL);

			return success != 0;
		}
		return false;
#else
		std::random_device rd;
		for(unsigned i = 0; i < bytes; ++i)
			buffer[i] = (unsigned char)rd();
		return true;
#endif
	}

	void setVerticalSync(int waitFrames) {
		glfwSwapInterval(waitFrames);
	}

	void swapBuffers(double minWait_s) {
		glfwSwapBuffers(window);
		glfwPollEvents();
		if(devices.cloud)
			devices.cloud->update();

		double waitTill = frameTime + minWait_s;
		double curTime = getAccurateTime();

		while(curTime < waitTill) {
			glfwPollEvents();
			if(devices.cloud)
				devices.cloud->update();
			threads::sleep(0);
			curTime = getAccurateTime();
		}

		if(gameSpeed > 0 && game_running) {
			double delta = curTime - frameTime;
			if(delta > 0.5)
				delta = 0.5;
			gameTime += delta * gameSpeed;
		}

		frameTime = curTime;
	}

	void handleEvents(unsigned minWait_ms) {
		glfwPollEvents();
		frameTime = getAccurateTime();
		threads::sleep(minWait_ms);
	}

	void getDesktopSize(unsigned& width, unsigned& height) {
        auto* primary = glfwGetPrimaryMonitor();
        if(primary == nullptr) {
            width = 1280;
            height = 720;
            return;
        }
		auto& desktop = *glfwGetVideoMode(primary);
		width = desktop.width;
		height = desktop.height;
	}

	void createWindow(WindowData& data) {
		glfwWindowHint(GLFW_SAMPLES, data.aa_samples);
		glfwWindowHint(GLFW_REFRESH_RATE, data.refreshRate);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);

		GLFWmonitor* monitor = nullptr;
		if(data.mode == WM_Fullscreen) {
			monitor = glfwGetPrimaryMonitor();

			if(!data.targetMonitor.empty()) {
				int count = 0;
				GLFWmonitor** monitors = glfwGetMonitors(&count);
				for(int i = 0; i < count; ++i) {
					if(data.targetMonitor == glfwGetMonitorName(monitors[i])) {
						monitor = monitors[i];
						break;
					}
				}
			}

			if(monitor && !data.overrideMonitor) {
				int count = 0;
				const GLFWvidmode* modes = glfwGetVideoModes(monitor, &count);
				bool match = false;
				for(int i = 0; i < count; ++i) {
					auto& mode = modes[i];
					if(mode.width == data.width && mode.height == data.height && (data.refreshRate == 0 || data.refreshRate == mode.refreshRate)) {
						match = true;
						break;
					}
				}

				if(!match) {
					monitor = nullptr;
					data.mode = WM_Window;
				}
			}
		}

		if(data.mode != WM_Fullscreen && (data.width == 0 || data.height == 0)) {
			GLFWmonitor* primary = glfwGetPrimaryMonitor();
			const GLFWvidmode* mode = glfwGetVideoMode(primary);

			data.width = mode->width;
			data.height = mode->height;
		}

		window = glfwCreateWindow(data.width, data.height, "Star Ruler 2", monitor, nullptr);

		if(window == 0)
			window = glfwCreateWindow(1024,768, "Star Ruler 2 - Error Creating Window", nullptr, nullptr);

		if(window == 0) {
			error("Could not create window.");
			return;
		}

		glfwMakeContextCurrent(window);

		glfwGetWindowSize(window, &win_width, &win_height);
		glfwSwapInterval( data.verticalSync );

		if(data.mode == WM_Fullscreen)
			setCursorVisible(true);

		glfwSetWindowCloseCallback(window, redirectWindowClose);
		glfwSetWindowSizeCallback(window, redirectWindowResize);
		glfwSetKeyCallback(window, redirectSpecialKey);
		glfwSetCharCallback(window, redirectCharKey);
		glfwSetMouseButtonCallback(window, redirectMouseButton);
		glfwSetScrollCallback(window, redirectMouseWheel);
		glfwSetCursorPosCallback(window, redirectMouseMove);
		glfwSetCursorEnterCallback(window, trackMouseOver);

#ifdef WIN_MODE
		HICON hSmallIcon = (HICON) LoadImage ( 0, "sr2.ico", IMAGE_ICON, 32, 32, LR_LOADFROMFILE | LR_DEFAULTCOLOR );
		SendMessage ( GetActiveWindow(), WM_SETICON, ICON_SMALL, (long)hSmallIcon );
#endif
	}

	void getVideoModes(std::vector<OSDriver::VideoMode>& output) {
		int count = 0;
		const GLFWvidmode* modes;
        auto* primary = glfwGetPrimaryMonitor();
        if(primary)
            modes = glfwGetVideoModes(primary, &count);
		output.reserve(count);
		output.resize(0);

		std::set<uint64_t> sizes;

		for(int i = 0; i < count; ++i) {
			VideoMode m;
			auto& mode = modes[i];
			m.width = mode.width;
			m.height = mode.height;
			m.refresh = mode.refreshRate;

			uint64_t size = (uint64_t)m.width << 16 | (uint64_t)m.height | ((uint64_t)mode.refreshRate << 32);

			if(sizes.find(size) == sizes.end()) {
				sizes.insert(size);
				output.push_back(m);
			}
		}
	}
	
	void getMonitorNames(std::vector<std::string>& output) {
		int count = 0;
		GLFWmonitor** monitors = glfwGetMonitors(&count);
		output.resize(count);
		for(int i = 0; i < count; ++i)
			output[i] = glfwGetMonitorName(monitors[i]);
	}

	bool isWindowFocused() override {
		return glfwGetWindowAttrib(window, GLFW_FOCUSED) != 0;
	}

	bool isWindowMinimized() override {
		return glfwGetWindowAttrib(window, GLFW_ICONIFIED) != 0;
	}

	void flashWindow() override {
		glfwFlashWindow(window);
	}
	
	bool isMouseOver() {
		return mouseOver;
	}

	void setClipboard(const std::string& text) {
		glfwSetClipboardString(window, text.c_str());
	}

	std::string getClipboard() {
		 const char* str = glfwGetClipboardString(window);
		 if(str)
			 return std::string(str);
		 return std::string();
	}

	int getCharForKey(int key) {
		return glfwGetCharForKey(key);
	}

	int getKeyForChar(unsigned char chr) {
		return glfwGetKeyForChar(chr);
	}

	unsigned getDoubleClickTime() const {
#ifdef _MSC_VER
		return GetDoubleClickTime();
#else
		//TODO: Get user's setting on linux
		return 200;
#endif
	}
	
	void getLastMousePos(int& x, int& y) {
		x = mouse_x;
		y = mouse_y;
	}

	void getMousePos(int& x, int& y) {
		double dx, dy;
		glfwGetCursorPos(window, &dx,&dy);
		x = (int)floor(dx);
		y = (int)floor(dy);
	}

	void setMousePos(int x, int y) {
		glfwSetCursorPos(window, x,y);
	}

	void setCursorVisible(bool visible) {
		glfwSetInputMode(window, GLFW_CURSOR, visible ? GLFW_CURSOR_NORMAL : GLFW_CURSOR_HIDDEN);
	}

	void setCursorLocked(bool locked) {
		if(canLock == locked)
			return;
		canLock = locked;
		if(shouldLock) {
			if(locked)
				glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_CAPTURED);
			else
				glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_FREE);
		}
	}
	
	void setCursorShouldLock(bool locked) {
		if(shouldLock == locked)
			return;
		shouldLock = locked;
		if(canLock) {
			if(locked)
				glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_CAPTURED);
			else
				glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_FREE);
		}
	}

	void sleep(int milliseconds) {
		threads::sleep(milliseconds);
	}

	void resetTimer() {
#ifndef WIN_MODE
		gettimeofday(&start_time, 0);
#else
		FILETIME cur_time;
		GetSystemTimeAsFileTime(&cur_time);
		start_time.HighPart = cur_time.dwHighDateTime;
		start_time.LowPart = cur_time.dwLowDateTime;

		QueryPerformanceFrequency(&start_time_hq_freq);
		QueryPerformanceCounter(&start_time_hq);
#endif
		frameTime = 0.0;
		resetGameTime(0);
	}

	int getTime() const {
#ifndef WIN_MODE
		timeval cur_time;
		gettimeofday(&cur_time, 0);

		return (int)(
			1000 * (cur_time.tv_sec - start_time.tv_sec)
			+ (cur_time.tv_usec - start_time.tv_usec) / 1000);
#else

		FILETIME cur_ftime;
		GetSystemTimeAsFileTime(&cur_ftime);
		ULARGE_INTEGER cur_time;
		cur_time.HighPart = cur_ftime.dwHighDateTime;
		cur_time.LowPart = cur_ftime.dwLowDateTime;

		const double ticksPerSecond = 10000000.0;
		auto timeInSeconds = (double)(cur_time.QuadPart - start_time.QuadPart) / ticksPerSecond;

		return int(timeInSeconds * 1000.0);
#endif
	}

	double getAccurateTime() const {
#ifndef WIN_MODE
		timeval cur_time;
		gettimeofday(&cur_time, 0);

		return (double)(cur_time.tv_sec - start_time.tv_sec)
			+ (double)(cur_time.tv_usec - start_time.tv_usec)/1000000.0;
#else
		LARGE_INTEGER cur_time, cur_freq;
		QueryPerformanceCounter(&cur_time);
		QueryPerformanceFrequency(&cur_freq);

		return (double)cur_time.QuadPart / (double)cur_freq.QuadPart - (double)start_time_hq.QuadPart / (double)start_time_hq_freq.QuadPart;
#endif
	}

	void resetGameTime(double time) {
		//Game time starts slightly ahead of render time
		gameTime = time;
		gameSpeed = 1;
	}

	double getGameTime() const {
		return gameTime;
	}
	
	double getFrameTime() const {
		return frameTime;
	}

	double getGameSpeed() const {
		return gameSpeed;
	}

	void setGameSpeed(double speed) {
		gameSpeed = speed;
	}

	unsigned getProcessorCount() {
		return std::max(threads::getNumberOfProcessors(),1u);
	}

	void setWindowTitle(const char* str) {
		glfwSetWindowTitle(window, str);
	}

	void setWindowSize(int width, int height){
		glfwSetWindowSize(window, width, height);
	}

	void closeWindow() {
		glfwDestroyWindow(window);
	}
};

void redirectWindowClose(GLFWwindow*) {
	driver->onWindowClose();
}

void redirectWindowResize(GLFWwindow*, int w, int h) {
	driver->onResize(w,h);
	driver->win_width = w;
	driver->win_height = h;
	glViewport(0, 0, w, h);
}

void redirectSpecialKey(GLFWwindow*, int key, int scan, int action, int mods) {
	driver->shiftKey = (mods & GLFW_MOD_SHIFT) != 0;
	driver->ctrlKey = (mods & GLFW_MOD_CONTROL) != 0;
	driver->altKey = (mods & GLFW_MOD_ALT) != 0;

	bool pressed;
	int keyaction;
	switch(action) {
		case GLFW_PRESS:
			pressed = true;
			keyaction = KA_Pressed;
		break;
		case GLFW_RELEASE:
			pressed = false;
			keyaction = KA_Released;
		break;
		case GLFW_REPEAT:
			pressed = true;
			keyaction = KA_Repeated;
		break;
		default:
			return;
	}

	switch(key) {
		case GLFW_KEY_LEFT_SHIFT:
		case GLFW_KEY_RIGHT_SHIFT:
			driver->shiftKey = pressed;
		break;

		case GLFW_KEY_LEFT_CONTROL:
		case GLFW_KEY_RIGHT_CONTROL:
			driver->ctrlKey = pressed;
		break;

		case GLFW_KEY_LEFT_ALT:
		case GLFW_KEY_RIGHT_ALT:
			driver->altKey = pressed;
		break;
	}

	driver->onKeyEvent(key, keyaction);
}

void redirectCharKey(GLFWwindow*, unsigned key) {
	driver->onCharTyped(key);
}

void redirectMouseButton(GLFWwindow*, int button, int action, int mods) {
	bool pressed = action == GLFW_PRESS;
	
	driver->shiftKey = (mods & GLFW_MOD_SHIFT) != 0;
	driver->ctrlKey = (mods & GLFW_MOD_CONTROL) != 0;
	driver->altKey = (mods & GLFW_MOD_ALT) != 0;

	switch(button) {
		case GLFW_MOUSE_BUTTON_LEFT:
			driver->leftButton = pressed;
		break;

		case GLFW_MOUSE_BUTTON_RIGHT:
			driver->rightButton = pressed;
		break;

		case GLFW_MOUSE_BUTTON_MIDDLE:
			driver->middleButton = pressed;
		break;
	}

	driver->onMouseButton(button, pressed);
}

void redirectMouseMove(GLFWwindow*, double x, double y) {
	driver->onMouseMoved((int)x, (int)y);
	driver->mouse_x = (int)x;
	driver->mouse_y = (int)y;
}

void redirectMouseWheel(GLFWwindow*, double x, double y) {
	driver->onScroll(x, y);
}

void trackMouseOver(GLFWwindow*,int over) {
	driver->mouseOver = over == GL_TRUE;
}

void glfwError(int code, const char* msg) {
	error("GLFW Error %d: %s", code, msg);
}

OSDriver* getGLFWDriver() {
	if(!driver)
		driver = new GLFWDriver();
	return driver;
}

};
