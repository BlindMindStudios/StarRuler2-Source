#include "console.h"
#include "threads.h"
#include "str_util.h"
#include "render/driver.h"
#include "render/render_state.h"
#include "main/references.h"
#include "main/logging.h"
#include "util/format.h"
#include "profile/keybinds.h"
#include "network/network_manager.h"
#include "render/vertexBuffer.h"

threads::Mutex consoleLock;
Console console;

extern double menuTickTime, serverTickTime, clientTickTime, animationTime;
const size_t maxUndoSize = 50;
int baseTimer = 0;

enum LiveStat {
	LS_Menu = 1,
	LS_Server = 2,
	LS_Client = 4,
	LS_Tick = 8,
	LS_Buffers = 16,
	LS_FPS = 32,
	LS_Bandwidth = 64
};

void asGet(const std::string& strEngine, const std::string& strModule,
			asIScriptEngine*& sEngine, asIScriptModule*& sModule) {

	//Find engine
	scripts::Manager* man = 0;
	if(strEngine == "menu")
		man = devices.scripts.menu;
	else if(strEngine == "client")
		man = devices.scripts.client;
	else if(strEngine == "server")
		man = devices.scripts.server;
	else
		return;

	//Find module
	sEngine = man->engine;

	if(strModule.empty()) {
		sModule = sEngine->GetModule("ConsoleInput", asGM_ALWAYS_CREATE);
	}
	else {
		scripts::Module* module = man->getModule(strModule.c_str());

		if(!module)
			return;

		sModule = module->module;
	}
}

void asGlobal(const std::string& strEngine, const std::string& strModule, const std::string& global) {
	asIScriptEngine* sEngine = 0;
	asIScriptModule* sModule = 0;

	asGet(strEngine, strModule, sEngine, sModule);

	if(!sEngine || !sModule)
		return;

	std::string code = global;
	if(code[code.size() - 1] != ';')
		code += ";";

	sModule->CompileGlobalVar("ConsoleGlobal", code.c_str(), 0);
}

void asExec(const std::string& strEngine, const std::string& strModule, const std::string& code)
{
	int r;

	asIScriptEngine* sEngine = 0;
	asIScriptModule* sModule = 0;

	asGet(strEngine, strModule, sEngine, sModule);

	if(!sEngine || !sModule)
		return;

	//Wrap code
	std::string fCode;

	if(code.find(";") == std::string::npos) {
		fCode = "void ConsoleFunction() { print(";
		fCode += code;
		fCode += "); }";
	}
	else {
		fCode = "void ConsoleFunction() { ";
		fCode += code;
		fCode += "; }";
	}
	
	//Compile function
	asIScriptFunction* sFunc = 0;
	r = sModule->CompileFunction("ConsoleFunction", fCode.c_str(), -1, 0, &sFunc);
	if(r < 0)
		return;

	//Prepare context
	asIScriptContext* ctx = sEngine->CreateContext();
	r = ctx->Prepare(sFunc);

	if(r >= 0) {
		//Execute
		r = ctx->Execute();
	}
	
	//Clean
	sFunc->Release();
	ctx->Release();
}


Console::Console() : open(false), permaStats(false), bg(new render::RenderState), compact(false), historyItem(history.cbegin()), asMode(false), keybind(0), liveStats(~0) {
	bg->baseMat = render::MAT_Alpha;
	bg->lighting = false;
	bg->culling = render::FC_None;
	bg->depthTest = render::DT_NoDepthTest;

	addCommand("clear", [this](argList&) {
		clear();
	} );

	addCommand("list", [this](argList&) {
		std::string temp;
		for(auto i = functions.cbegin(), end = functions.cend(); i != end; ++i) {
			if(temp.empty()) {
				temp = i->first;
			}
			else {
				temp.insert(temp.size(), 16 - (temp.size() % 16), ' ');
				temp += i->first;
				if(temp.size() >= 16*5) {
					printLn(temp);
					temp.clear();
				}
			}
		}

		if(!temp.empty())
			printLn(temp);
	} );

	addCommand("resize", [this](argList& args) {
		if(args.size() != 2) {
			error("Usage: resize [width] [height]");
			return;
		}

		devices.driver->setWindowSize(
			toNumber<int>(args[0]),
			toNumber<int>(args[1]));
	} );

	addCommand("compact", [this](argList& args) {
		if(args.empty())
			compact = !compact;
		else if(streq_nocase(args[0], "true"))
			compact = true;
		else if(streq_nocase(args[0], "false"))
			compact = false;
	} );

	addCommand("stats", [this](argList& args) {
		if(args.empty())
			permaStats = !permaStats;
		else
			permaStats = toBool(args[0]);
	} );

	addCommand("show", [this](argList& args) {
		if(args.empty()) {
			printLn("Toggles the showing of live data at the right");
			printLn("Choose which piece of data to toggle: all, fps, menu, server, client, tick, buffers, bandwidth");
			return;
		}

		auto& arg = args[0];
		if(arg == "all") {
			//Toggle all off if any are on, otherwise show all
			liveStats = liveStats ? 0 : ~0;
		}
		else if(arg == "fps") {
			liveStats ^= LS_FPS;
		}
		else if(arg == "menu") {
			liveStats ^= LS_Menu;
		}
		else if(arg == "server") {
			liveStats ^= LS_Server;
		}
		else if(arg == "client") {
			liveStats ^= LS_Client;
		}
		else if(arg == "tick") {
			liveStats ^= LS_Tick;
		}
		else if(arg == "buffers") {
			liveStats ^= LS_Buffers;
		}
		else if(arg == "bandwidth") {
			liveStats ^= LS_Bandwidth;
		}
	} );

	addCommand("bind", [this](argList& args) {
		if(args.size() > 1) {
			int key = profile::getKeyFromDisplayName(args[0]);
			if(key == 0) {
				printLn(format("Unrecognized key '$1'", args[0]));
				return;
			}
			else {
				std::string command;
				for(size_t i = 1, cnt = args.size(); i < cnt; ++i) {
					if(!command.empty())
						command += " ";
					if(args[i].find(' ') != std::string::npos) {
						command += "\"";
						command += args[i];
						command += "\"";
					}
					else {
						command += args[i];
					}
				}
				
				binds[key] = command;
			}
		}
		else {
			printLn("Bind requires a key and a command");
		}
	} );

	addCommand("in", [this](argList& args) {
		if(args.empty()) {
			asModule = "";
			asEngine = "client";
		}
		else {
			if(args.size() == 1) {
				asModule = args[0];
				if(devices.scripts.menu && devices.scripts.menu->getModule(asModule.c_str())) {
					asEngine = "menu";
				}
				else if(devices.scripts.client && devices.scripts.client->getModule(asModule.c_str())) {
					asEngine = "client";
				}
				else if(devices.scripts.server && devices.scripts.server->getModule(asModule.c_str())) {
					asEngine = "server";
				}
				else {
					std::string temp;
					temp += "Error: Could not find angelscript module '";
					temp += asModule;
					temp += "' in any engine.";

					printLn(temp);
					return;
				}
			}
			else if(args.size() == 2) {
				asEngine = args[0];
				asModule = args[1];
			}
			else {
				return;
			}
		}

		std::string temp;
		temp += "Setting console to angelscript mode for module '";
		temp += asModule;
		temp += "' in engine '";
		temp += asEngine;
		temp += "'.\n Type 'quit' to return to normal mode.";

		printLn(temp);
		asMode = true;
	} );
}

Console::~Console() {
	delete bg;
}

void Console::addCommand(std::string name, std::function<void(std::vector<std::string>&)> function, bool replace) {
	toLowercase(name);
	if(replace || functions.find(name) == functions.end()) {
		ConsoleFunction& f = functions[name];
		f.line = nullptr;
		f.call = function;
		f.destruct = nullptr;
	}
	else
		error("Duplicate console command '%s'", name.c_str());
}

void Console::addCommand(std::string name, ConsoleFunction& func, bool replace) {
	toLowercase(name);
	if(replace || functions.find(name) == functions.end())
		functions[name] = func;
	else
		error("Duplicate console command '%s'", name.c_str());
}

void Console::clearCommands() {
	for(auto it = functions.begin(); it != functions.end();) {
		if(it->second.destruct) {
			if(it->second.destruct()) {
				it = functions.erase(it);
				continue;
			}
		}
		++it;
	}
}

bool Console::eraseSelection() {
	if(length != 0) {
		if(length > 0)
			currentLine.erase(caret, length);
		else {
			currentLine.erase(caret+length, -length);
			caret += length;
		}
		length = 0;
		return true;
	}
	else {
		return false;
	}
}

bool Console::character(int code) {
	if(!open)
		return false;
	if(devices.keybinds.global.getBind(code) == keybind)
		return false;
	if(devices.driver->ctrlKey)
		return true;
	
	undo.push_back( std::tuple<std::string, size_t, int>(currentLine, caret, length) );

	eraseSelection();

	currentLine.insert(caret++, 1, (char)code);
	return true;
}

bool Console::globalKey(int code, bool pressed) {
	if(open)
		return false;

	auto bind = binds.find(profile::getModifiedKey(code, devices.driver->ctrlKey, devices.driver->altKey, devices.driver->shiftKey));
	if(bind != binds.end()) {
		if(pressed)
			execute(bind->second, false);
		return true;
	}
	else {
		return false;
	}
}

bool Console::key(int code, bool pressed) {
	if(!open)
		return false;
	if(!pressed)
		return true;
	std::tuple<std::string, size_t, int> previous(currentLine, caret, length);

	switch(code) {
	case 'A': //Select all
		if(devices.driver->ctrlKey) {
			caret = 0;
			length = (int)currentLine.size();
			baseTimer = devices.driver->getTime();
		}
		break;
	case 'K':
		//Kill line
		if(devices.driver->ctrlKey) {
			caret = 0;
			currentLine = "";
		}
		break;
	case 'C':
	case 'X':
		if(devices.driver->ctrlKey) {
			if(length > 0)
				devices.driver->setClipboard(currentLine.substr(caret, length));
			else
				devices.driver->setClipboard(currentLine.substr(caret+length, -length));
			if(code == 'X') {
				eraseSelection();
				baseTimer = devices.driver->getTime();
			}
		}
		break;
	case 'V':
		if(devices.driver->ctrlKey) {
			eraseSelection();
			std::string text = devices.driver->getClipboard();
			currentLine.insert(caret, text);
			baseTimer = devices.driver->getTime();
			caret += text.size();
		}
		break;
	case 'Y':
		if(devices.driver->ctrlKey) {
			if(!redo.empty()) {
				undo.push_back(previous);
				if(undo.size() > maxUndoSize)
					undo.pop_front();

				auto& prev = redo.back();
				currentLine = std::get<0>(prev);
				caret = std::get<1>(prev);
				length = std::get<2>(prev);

				redo.pop_back();
			}
			baseTimer = devices.driver->getTime();
			return true; //Return here to prevent handling the line change by the undo system
		}
		break;
	case 'Z':
		if(devices.driver->ctrlKey) {
			if(!undo.empty()) {
				redo.push_back(previous);
				if(redo.size() > maxUndoSize)
					redo.pop_front();

				auto& prev = undo.back();
				currentLine = std::get<0>(prev);
				caret = std::get<1>(prev);
				length = std::get<2>(prev);

				undo.pop_back();
			}
			baseTimer = devices.driver->getTime();
			return true; //Return here to prevent handling the line change by the undo system
		}
		break;
	case os::KEY_BACKSPACE:
		if(!eraseSelection() && caret > 0)
			currentLine.erase(--caret,1);
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_DEL:
		if(!eraseSelection() && caret < currentLine.size())
			currentLine.erase(caret,1);
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_LEFT:
		if(caret > 0) {
			caret -= 1;
			if(devices.driver->shiftKey)
				length += 1;
			else
				length = 0;
		}
		else if(!devices.driver->shiftKey) {
			length = 0;
		}
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_RIGHT:
		if(caret < currentLine.size()) {
			caret += 1;
			if(devices.driver->shiftKey)
				length -= 1;
			else
				length = 0;
		}
		else if(!devices.driver->shiftKey) {
			length = 0;
		}
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_HOME:
		if(caret > 0) {
			if(devices.driver->shiftKey)
				length += (int)caret;
			else
				length = 0;
			caret = 0;
		}
		else if(!devices.driver->shiftKey) {
			length = 0;
		}
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_END:
		if(caret < currentLine.size()) {
			if(devices.driver->shiftKey)
				length -= (int)(currentLine.size() - caret);
			else
				length = 0;
			caret = currentLine.size();
		}
		else if(!devices.driver->shiftKey) {
			length = 0;
		}
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_ENTER:
		if(!currentLine.empty()) {
			execute(currentLine, true);
			history.push_front(currentLine);
			historyItem = history.cend();
			currentLine.clear();
			caret = 0;
			length = 0;
		}
		baseTimer = devices.driver->getTime();
		break;
	case os::KEY_UP:
		if(!history.empty()) {
			if(historyItem != history.cend())
				++historyItem;
			else
				historyItem = history.cbegin();

			if(historyItem != history.end())
				currentLine = *historyItem;
			else
				currentLine.clear();
			caret = currentLine.size();
			length = 0;
		}
		break;
	case os::KEY_DOWN:
		if(!history.empty()) {
			if(historyItem != history.cbegin())
				--historyItem;
			else
				historyItem = history.cend();

			if(historyItem != history.end())
				currentLine = *historyItem;
			else
				currentLine.clear();
			caret = currentLine.size();
			length = 0;
		}
		break;
	case os::KEY_TAB:
		if(!currentLine.empty()) {
			size_t space = currentLine.find(' ');
			if(space == std::string::npos) {
				const std::string* bestMatch = 0;
				unsigned bestScore = (unsigned)-1;

				for(auto i = functions.cbegin(), end = functions.cend(); i != end; ++i) {
					size_t p = i->first.find(currentLine);
					if(p == std::string::npos)
						continue;
					unsigned score = (unsigned)((p * 4) + (i->first.size() - currentLine.size()));
					if(bestScore < score)
						continue;
					bestScore = score;
					bestMatch = &i->first;
				}

				if(bestMatch) {
					currentLine = *bestMatch + (char)' ';
					caret = currentLine.size();
					length = 0;
				}
			}
		}
		break;
	}

	//If the line has changed, store the previous state as an undo entry, and clear the redo list
	if(std::get<0>(previous) != currentLine) {
		redo.clear();
		undo.push_back(previous);
		if(undo.size() > maxUndoSize)
			undo.pop_front();
	}
	return true;
}

void Console::printLn(const std::string& line) {
	consoleLock.lock();
	if(line.find('\n') == std::string::npos)
		lines.push_back(line);
	else {
		std::vector<std::string> split_lines;
		split(line, split_lines, '\n');
		for(unsigned i = 0; i < split_lines.size(); ++i)
			lines.push_back(split_lines[i]);
	}
	consoleLock.release();
}

void Console::clear() {
	consoleLock.lock();
	lines.clear();
	consoleLock.release();
}

void Console::execute(const std::string& command, bool echo) {
	if(asMode) {
		if(echo)
			printLn(std::string("# ") + command);

		if(command == "quit" || command == "q") {
			asMode = false;
		}
		else if(command.compare(0, 7, "global ") == 0) {
			asGlobal(asEngine, asModule, command.substr(7));
		}
		else {
			asExec(asEngine, asModule, command);
		}
	}
	else {
		auto argStart = command.find_first_of(" \t");
		std::string function = command.substr(0, argStart);
		toLowercase(function);

		auto func = functions.find(function);
		if(func == functions.end()) {
			if(echo)
				printLn(std::string("Unrecognized command '") + function + "'");
			return;
		}

		if(echo)
			printLn(std::string("> ") + command);

		if(func->second.line) {
			std::string line;
			if(argStart != std::string::npos)
				line = command.substr(argStart + 1);

			if(func->second.line(line))
				return;
		}

		if(func->second.call) {
			std::vector<std::string> args;
			if(argStart != std::string::npos) {
				auto end = argStart;
				while(end != std::string::npos) {
					auto start = command.find_first_not_of(" \t", end);
					if(start == std::string::npos)
						break;
					if(command[start] == '\"') {
						start += 1;
						end = command.find('\"', start);
					}
					else {
						end = command.find(' ', start);
					}

					args.push_back(command.substr(start, end-start));
				}
			}

			func->second.call(args);
		}
	}
}

void Console::executeFile(const std::string& filename) {
	std::ifstream stream(filename);
	std::string line;
	while(stream.is_open() && stream.good()) {
		std::getline(stream, line);
		execute(line, false);
	}
}

void Console::show() {
	open = true;
}

void Console::toggle() {
	open = !open;
}

Color bgCols[4] = {Color(0,0,0,230), Color(0,0,0,230), Color(0,0,0,230), Color(0,0,0,230) };
Color selCols[4] = {Color(0,0,255,80), Color(0,0,255,80), Color(0,0,255,80), Color(0,0,255,80) };

void Console::render(render::RenderDriver& driver) {
	if(!open && !permaStats)
		return;
	vec2i screenSize(devices.driver->win_width,devices.driver->win_height);
	if(screenSize.width == 0 || screenSize.height == 0)
		return;

	if(open && !compact)
		driver.drawRectangle(recti(vec2i(0,0), screenSize), bg, 0, bgCols);

	const gui::skin::Skin& skin = devices.library["Debug"];
	auto& font = skin.getFont(gui::skin::getFontIndex("Normal"));
	int lineHeight = font.getLineHeight();

	if(!compact && (open || permaStats)) {
		//FPS indicator
		const float average_pct = 0.15f;
		static float fps = 60;
		static float tps = 4.f;

		extern double realFrameLen, animation_s, render_s, present_s;
		extern double prevTick_s;

		int y = 1;
		
		if(liveStats & LS_FPS) {
			if(realFrameLen > 0.00001) {
				fps = (1.f - average_pct) * fps + (average_pct * (float)(1.0 / realFrameLen));

				if(prevTick_s > 0.00001) {
					double gs = devices.driver->getGameSpeed();
					if(gs > 0)
						tps = (1.f - average_pct) * tps + (average_pct * (float)(1.0 / (prevTick_s / gs)));
				}

				char buffer[256];
				sprintf(buffer, "%.1ftps %.1ffps (a=%4.1fms r=%4.1fms p=%4.1fms)", tps, fps, animation_s*1000.0, render_s*1000.0, present_s*1000.0);
				font.draw(devices.render, buffer, screenSize.width - font.getDimension(buffer).width, 1);
			}
			else {
				font.draw(devices.render, "inf fps", screenSize.width - font.getDimension("inf fps").width ,1);
			}

			y += 39;
		}

		int x = screenSize.width - 260;

		if(liveStats & LS_FPS) {
			devices.render->drawFPSGraph(recti(vec2i(x,y), vec2i(x + 240, y+60)));
			y += 60 + lineHeight;
		}

		asUINT gc_size, gc_destroyed, gc_detected, gc_new, gc_newDestroyed;

		if(devices.scripts.menu && (liveStats & LS_Menu)) {
			devices.scripts.menu->engine->GetGCStatistics(&gc_size, &gc_destroyed, &gc_detected, &gc_new, &gc_newDestroyed);
			std::string gc_state = format("Menu GC Entities: $1\n  Destroyed: $2\n  Detected: $3\n  New: $4\n  New Destroyed: $5", gc_size, gc_destroyed, gc_detected, gc_new, gc_newDestroyed);
			font.draw(devices.render, gc_state.c_str(), x, y);
			y += lineHeight * 6;
		}

		if(devices.scripts.client && (liveStats & LS_Client)) {
			devices.scripts.client->engine->GetGCStatistics(&gc_size, &gc_destroyed, &gc_detected, &gc_new, &gc_newDestroyed);
			std::string gc_state = format("Client GC Entities: $1\n  Destroyed: $2\n  Detected: $3\n  New: $4\n  New Destroyed: $5", gc_size, gc_destroyed, gc_detected, gc_new, gc_newDestroyed);
			font.draw(devices.render, gc_state.c_str(), x, y);
			y += lineHeight * 6;
		}

		if(devices.scripts.server && (liveStats & LS_Server)) {
			devices.scripts.server->engine->GetGCStatistics(&gc_size, &gc_destroyed, &gc_detected, &gc_new, &gc_newDestroyed);
			std::string gc_state = format("Server GC Entities: $1\n  Destroyed: $2\n  Detected: $3\n  New: $4\n  New Destroyed: $5", gc_size, gc_destroyed, gc_detected, gc_new, gc_newDestroyed);
			font.draw(devices.render, gc_state.c_str(), x, y);
			y += lineHeight * 6;
		}
		
		if(liveStats & LS_Tick) {
			static double lastServerTick = 0, lastClientTick = 0;
			if(serverTickTime > 0.0001)
				lastServerTick = serverTickTime;
			if(clientTickTime > 0.0001)
				lastClientTick = clientTickTime;

			std::string tickTimes = format("Server Script Tick: $1ms\nClient Script Tick: $2ms", toString(lastServerTick * 1000.0,2), toString(lastClientTick * 1000.0,2));
			font.draw(devices.render, tickTimes.c_str(), x, y);
			y += lineHeight * 3;
		}

		if(liveStats & LS_Buffers) {
			extern unsigned drawnSteps, bufferFlushes;
			std::string vbData = format("VB Steps: $1\nVB Flushes: $2\n Verts= $3\n Steps= $4\n Shader= $5", toString(drawnSteps), toString(bufferFlushes),
				toString(render::vbFlushCounts[render::FC_VertexLimit]), toString(render::vbFlushCounts[render::FC_StepLimit]), toString(render::vbFlushCounts[render::FC_ShaderLimit]));
			font.draw(devices.render, vbData.c_str(), x, y);
			y += lineHeight * 6;
		}

		if(liveStats & LS_Bandwidth && devices.network->monitorBandwidth) {
			std::string bwData = format("Incoming: $1/s\nOutgoing: $2/s\nQueued: $3",
				toSize(devices.network->currentIncoming), toSize(devices.network->currentOutgoing), toString(devices.network->queuedPackets));
			font.draw(devices.render, bwData.c_str(), x, y);
			y += lineHeight * 4;
		}
	}

	if(!open)
		return;

	int y = screenSize.height - (2 * lineHeight);

	consoleLock.lock();
	vec2i lineStart;

	if(asMode) {
		lineStart = font.getDimension("# ");
		font.draw(&driver, "# ", 0, y+lineHeight);
	}
	else {
		lineStart = font.getDimension("> ");
		font.draw(&driver, "> ", 0, y+lineHeight);
	}

	font.draw(&driver, currentLine.c_str(), lineStart.width, y+lineHeight);
	if(length != 0) {
		driver.switchToRenderState(*bg);

		vec2i corner(lineStart.x, y+lineHeight);
		vec2i size;
		if(length > 0) {
			corner.x += font.getDimension(currentLine.substr(0, caret).c_str()).width;
			size = font.getDimension(currentLine.substr(caret, length).c_str());
		}
		else {
			corner.x += font.getDimension(currentLine.substr(0, caret+length).c_str()).width;
			size =	font.getDimension(currentLine.substr(caret+length, -length).c_str());
		}

		driver.drawRectangle(recti(corner, corner + size), bg, 0, selCols);
	}

	if((devices.driver->getTime() - baseTimer) % 2000 < 1000) {
		int caret_x = font.getDimension(currentLine.substr(0, caret).c_str()).width + lineStart.width;
		font.drawChar(&driver, '|', '\0', caret_x - 4, y+lineHeight);
	}

	if(!compact)
		for(auto line = lines.rbegin(), end = lines.rend(); line != end && (y+lineHeight) > 0; ++line, y-=lineHeight)
			font.draw(&driver, line->c_str(), 0, y);
	consoleLock.release();
}
