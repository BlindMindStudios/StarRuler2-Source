#pragma once
#include <functional>
#include <unordered_map>
#include <vector>
#include <list>
#include <string>
#include <tuple>

namespace render {
	class RenderDriver;
	struct RenderState;
};

namespace profile {
	struct Keybind;
};

typedef std::vector<std::string> argList;

class Console {
public:
	struct ConsoleFunction {
		std::function<bool(std::string&)> line;
		std::function<void(argList&)> call;
		std::function<bool()> destruct;
	};
private:
	std::unordered_map<std::string, ConsoleFunction> functions;
	std::unordered_map<int, std::string> binds;

	std::list<std::string> lines, history;
	std::list<std::string>::const_iterator historyItem;

	std::list<std::tuple<std::string, size_t, int>> undo, redo;

	std::string currentLine;
	size_t caret;
	int length;

	bool open;
	bool permaStats;
	render::RenderState *bg;

	bool compact;
	unsigned liveStats;

	bool asMode;
	std::string asModule;
	std::string asEngine;

	bool eraseSelection();
public:
	void addCommand(std::string name, std::function<void(argList&)> function, bool replace = false);
	void addCommand(std::string name, ConsoleFunction& func, bool replace = false);
	void clearCommands();

	void printLn(const std::string& line);
	void execute(const std::string& command, bool echo);
	void executeFile(const std::string& filename);

	profile::Keybind* keybind;

	void toggle();
	void show();
	void clear();

	Console();
	~Console();

	bool preRender();
	void render(render::RenderDriver& driver);

	bool character(int code);
	bool key(int code, bool pressed);
	bool globalKey(int code, bool pressed);
};

extern Console console;
