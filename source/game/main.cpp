#ifdef _MSC_VER
#include <Windows.h>
#include <DbgHelp.h>
#endif
#include "main/input_handling.h"
#include "main/initialization.h"
#include "main/tick.h"
#include "main/logging.h"
#include "main/version.h"
#include "main/save_load.h"
#include "main/game_platform.h"
#include "util/format.h"
#include "util/save_file.h"
#include "main/references.h"
#include "scripts/script_bind.h"
#include "scripts/context_cache.h"
#include "obj/lock.h"
#include "files.h"
#include "processing.h"
#include "threads.h"
#include "network/network_manager.h"
#include "util/locked_type.h"
#include "util/lockless_type.h"
#include "network/init.h"
#include "main/version.h"
#include "render/vertexBuffer.h"
#include <stdint.h>
#ifdef __GNUC__
#include <unistd.h>
#endif

bool launchPatcher = false;

namespace scripts {
	void updateGame();
};

unsigned reportVersion = 2;

#ifdef _MSC_VER
MINIDUMP_TYPE mdumpType = (MINIDUMP_TYPE)(MiniDumpWithProcessThreadData | MiniDumpWithIndirectlyReferencedMemory);

LONG WINAPI CrashCallback( LPEXCEPTION_POINTERS pException ) {
	print("Unhandled exception in thread %d", threads::getThreadID());
	flushLog();

	SYSTEMTIME timeStamp;
	GetLocalTime(&timeStamp);
	char buffer[512];
	sprintf_s(buffer, 512, "%.420s\\SR2_%i-%i-%i_%i-%i-%i.mdmp", getProfileRoot().c_str(), timeStamp.wYear, timeStamp.wMonth, timeStamp.wDay, timeStamp.wHour, timeStamp.wMinute, timeStamp.wSecond);
	HANDLE file = CreateFile(buffer, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
	if(file != INVALID_HANDLE_VALUE) {
		print("Building minidump %s", buffer);

		MINIDUMP_EXCEPTION_INFORMATION exception;
		exception.ClientPointers = FALSE;
		exception.ExceptionPointers = pException;
		exception.ThreadId = GetCurrentThreadId();

		if(MiniDumpWriteDump( GetCurrentProcess(), GetCurrentProcessId(), file, mdumpType, (pException != 0) ? &exception : 0, 0, 0) == FALSE) {
			DWORD err = GetLastError();
			    LPVOID lpMsgBuf;
				DWORD dw = GetLastError(); 

				FormatMessage( FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
					NULL, err, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
					(LPTSTR) &lpMsgBuf, 0, NULL );
				appendToErrorLog("Failed to generate Minidump:", true, false);
				appendToErrorLog((char*)lpMsgBuf, false);
				print("Failed to generate Minidump: %s", (char*)lpMsgBuf);

				LocalFree(lpMsgBuf);
		}
		CloseHandle(file);
	}
	else {
		DWORD err = GetLastError();
		print("Could not write out minidump '%' (%d)", buffer, err);
		appendToErrorLog(std::string("Could not open minidump file: ") + toString(err));
	}

	auto* ctx = asGetActiveContext();
	char cloudBuffer[512];
	if(ctx) {
		if(ctx->GetState() == asEXECUTION_EXCEPTION) {
			const char* pSection = nullptr;
			int column = 0;
			int line = ctx->GetExceptionLineNumber(&column,&pSection);
			sprintf_s(cloudBuffer, 512, "%s Script Exception: %.400s (%i:%i)", getSectionName(), pSection, line, column); 
		}
		else if(ctx->GetState() == asEXECUTION_ACTIVE) {
			auto* f = ctx->GetFunction();
			if(f) {
				const char* pSection = nullptr;
				int column = 0;
				int line = ctx->GetLineNumber(0, &column, &pSection);
				sprintf_s(cloudBuffer, 512, "%s Script Active: %.400s (%i:%i)", getSectionName(), pSection, line, column);
			}
			else {
				sprintf_s(cloudBuffer, 512, "%s Script Active, Unknown state",getSectionName());
			}
		}
	}
	else if(threads::getThreadID() != 0 || !scene::renderingNode) {
		sprintf_s(cloudBuffer, 512, "Native: %s", getSectionName());
	}
	else {
		sprintf_s(cloudBuffer, 512, "Native: %s\nRendering %s", getSectionName(), scene::renderingNode->getName());
	}

	print("%s", cloudBuffer);

	if(devices.cloud) {
		devices.cloud->logException(pException->ExceptionRecord->ExceptionCode, pException, reportVersion, cloudBuffer);
		print("Attempted to upload exception to the cloud");
	}

	if(ctx) {
		print("Exception occurred inner to script execution:");
		flushLog();
		scripts::logException();
	}

	storeLog(std::string(buffer) + ".txt");

	return EXCEPTION_CONTINUE_SEARCH;
}

void initCrashDump() {
	SetUnhandledExceptionFilter(CrashCallback);
}
#else
	#include "dump_lin.h"
#endif

#include "util/formula.h"

#include "main/console.h"

#include "render/render_mesh.h"

#include "ISoundDevice.h"
#include "SLoadError.h"

#include "scripts/context_cache.h"
#include "../as_addons/include/scripthelper.h"

#include <unordered_map>

#ifdef PROFILE_LOCKS
	extern bool printLockProfile, requireObserved;
#endif

#ifdef PROFILE_EXECUTION
	namespace scripts {
	void logScriptProfile(asIScriptEngine* engine);
	};
#endif

#ifdef _MSC_VER
extern "C" {
	__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
}
#endif

namespace scripts {
	void takeScreenshot(const std::string& fname, bool increment = true);
};

std::unordered_map<std::string, double> formulaTestVars;
double formulaTest(void*,const std::string* var) {
	auto v = formulaTestVars.find(*var);
	if(v != formulaTestVars.end())
		return v->second;
	else
		return 0;
}

void netErrorMessage(const char* err, int code) {
	error("Network Error: %s (%i)", err, code);
}

int main(int argc, char** argv) {
	std::string launchConnect, launchPassword, launchLobby;

	//Create profile directories
	{
		std::vector<std::string> paths;
		path_split(getProfileRoot(), paths);

		std::string path;
		for(auto i = paths.begin(), end = paths.end(); i != end; ++i) {
			path += *i + "/";
			makeDirectory(path);
		}
	}

	createLog();
	logDate();

	enterSection(NS_Startup);
	net::setErrorCallback(netErrorMessage);

	console.addCommand("volume", [](argList& args) {
		if(!devices.sound)
			return;
		if(args.empty())
			console.printLn(format("Volume: $1", devices.sound->getVolume()));
		else
			devices.sound->setVolume(toNumber<float>(args[0].c_str()));
	} );

	console.addCommand("quit", [](argList&) {
		game_state = GS_Quit;
	} );

	console.addCommand("menu", [](argList&) {
		game_state = GS_Menu;
	} );

	console.addCommand("crash", [](argList&) {
		//Legit.
		*(volatile int*)nullptr = 42;
	} );

	console.addCommand("game", [](argList&) {
		game_state = GS_Game;
	} );

	console.addCommand("update", [](argList&) {
		scripts::updateGame();
	} );

	console.addCommand("host", [](argList&) {
		devices.network->host("", 2048, 0, true);
		if(game_running)
			devices.network->signalServerReady();
	} );

	console.addCommand("connect", [](argList& args) {
		if(args.size() == 0)
			devices.network->connect("127.0.0.1", 2048);
		else if(args.size() == 2)
			devices.network->connect(args[0], toNumber<int>(args[1]));
		else
			devices.network->connect(args[0], 2048);
	} );

	console.addCommand("bw_monitor", [](argList& args) {
		if(args.size() == 0)
			devices.network->monitorBandwidth = true;
		else
			devices.network->monitorBandwidth = toBool(args[0]);
	});

	console.addCommand("bw_incoming", [](argList&) {
		devices.network->dumpIncomingMonitor();
	});

	console.addCommand("bw_outgoing", [](argList&) {
		devices.network->dumpOutgoingMonitor();
	});

	console.addCommand("bw_incoming_total", [](argList&) {
		devices.network->dumpIncomingTotals();
	});

	console.addCommand("bw_outgoing_total", [](argList&) {
		devices.network->dumpOutgoingTotals();
	});

	console.addCommand("clear_cloud", [](argList&) {
		if(devices.cloud)
			devices.cloud->flushCloud();
	});

	console.addCommand("full_gc", [](argList&) {
		extern bool fullGC;
		fullGC = true;
	});

	console.addCommand("async_times", [](argList&) {
		void logAsyncLoad();
		logAsyncLoad();
	});

#ifdef PROFILE_LOCKS
	console.addCommand("print_locks", [](argList& args) {
		requireObserved = args.size() > 0 && toBool(args[0]);
		printLockProfile = true;
	});
#endif
#ifdef PROFILE_PROCESSING
	console.addCommand("print_processing", [](argList& args) {
		processing::printProcessingProfile();
	});
#endif
#ifdef PROFILE_SCRIPT_CALLBACKS
	console.addCommand("print_script_cb", [](argList& args) {
		print("Server:");
		if(devices.scripts.server)
			devices.scripts.server->printProfile();
		print("Client:");
		if(devices.scripts.client)
			devices.scripts.client->printProfile();
		print("Menu:");
		if(devices.scripts.menu)
			devices.scripts.menu->printProfile();
	});
#endif
#ifdef PROFILE_EXECUTION
	console.addCommand("log_script_profile", [](argList& args) {
		std::string engine;
		if(args.size() != 0)
			engine = args[0];

		if(devices.scripts.menu && (engine.empty() || engine == "menu")) {
			print("Menu Script Profile:");
			scripts::logScriptProfile(devices.scripts.menu->engine);
		}

		if(devices.scripts.client && (engine.empty() || engine == "client")) {
			print("Client Script Profile:");
			scripts::logScriptProfile(devices.scripts.client->engine);
		}

		if(devices.scripts.server && (engine.empty() || engine == "server")) {
			print("Server Script Profile:");
			scripts::logScriptProfile(devices.scripts.server->engine);
		}
	});
#endif

	console.addCommand("print_groups", [](argList& args) {
		printLockStats();
	});

	console.addCommand("export_bindings", [](argList& args) {
		if(args.size() == 0)
			console.printLn("Please specify an engine: menu, client, or server");
		else if(args[0] == "menu") {
			if(devices.scripts.menu)
				WriteConfigToFile(devices.scripts.menu->engine, "menu_config.txt");
		}
		else if(args[0] == "client") {
			if(devices.scripts.client)
				WriteConfigToFile(devices.scripts.client->engine, "client_config.txt");
		}
		else if(args[0] == "server") {
			if(devices.scripts.server)
				WriteConfigToFile(devices.scripts.server->engine, "server_config.txt");
		}
		else {
			console.printLn("Please specify an engine: menu, client, or server");
		}
	});

	console.addCommand("gc_types", [](argList& args) {
		if(args.empty()) {
			console.printLn("Please specify an engine: menu, client, or server");
			return;
		}

		unsigned threshold = 5;

		scripts::Manager* manager = 0;
		if(args[0] == "menu")
			manager = devices.scripts.menu;
		else if(args[0] == "client")
			manager = devices.scripts.client;
		else if(args[0] == "server")
			manager = devices.scripts.server;

		if(manager == 0) {
			console.printLn("Engine is not active or is invalid");
			return;
		}

		if(args.size() >= 2)
			threshold = toNumber<unsigned>(args[1]);

		std::map<asITypeInfo*,unsigned> counts;
		asUINT index = 0;
		asITypeInfo* type = 0;

		asUINT end = ~0;
		if(args.size() >= 3 && args[2] == "new") {
			asUINT dummy;
			manager->engine->GetGCStatistics(&dummy,
				nullptr, nullptr, &end);
		}

		while(index < end && manager->engine->GetObjectInGC(index++, 0, 0, &type) == asSUCCESS) {
			if(type != 0)
				counts[type] += 1;
		}

		//Use a multimap to sort the data by count
		std::multimap<unsigned,asITypeInfo*> results;
		for(auto i = counts.begin(), end = counts.end(); i != end; ++i)
			if(i->second >= threshold)
				results.insert(std::pair<unsigned,asITypeInfo*>(i->second, i->first));

		for(auto i = results.rbegin(), end = results.rend(); i != end; ++i) {
			auto* subtype = i->second->GetSubType();
			std::string line = i->second->GetName();
			if(subtype) {
				line += "<";
				line += subtype->GetName();
				line += ">";
			}
			line += ": ";
			line += toString(i->first,0);
			console.printLn(line);
		}
	});

	console.addCommand("formula_var", [](argList& args) {
		if(args.size() == 2) {
			double value = toNumber<double>(args[1]);
			formulaTestVars[args[0]] = value;
			console.printLn(args[0] + " = " + toString(value,5));
		}
	});

	console.addCommand("formula", [](argList& args) {
		try {
			if(!args.empty()) {
				std::string content;
				for(auto i = args.begin(), end = args.end(); i != end; ++i) {
					if(!content.empty())
						content += " ";
					content += *i;
				}
				Formula* formula = Formula::fromInfix(content.c_str());
				console.printLn(std::string(" = ") + toString(formula->evaluate(formulaTest, 0),5));
			}
		}
		catch(FormulaError err) {
			console.printLn(err.msg);
		}
	});

	console.addCommand("screenshot", [](argList& args) {
		scripts::takeScreenshot(args.empty() ? "screenshot" : args[0]);
	});

	console.addCommand("spherize", [](argList& args) {
		if(args.empty()) {
			console.printLn("Need image path and optional output path");
			return;
		}

		Image* source = loadImage(args[0].c_str());
		if(!source) {
			console.printLn("Could not locate file");
			return;
		}

		Image* out = source->sphereDistort();

		try {
			if(!saveImage(out,args.size() > 1 ? args[1].c_str() : args[0].c_str()))
				throw 0;
			console.printLn("Spherized image");
		}
		catch(...) {
			console.printLn("Could not write image");
		}

		delete out;
	});

	console.addCommand("rand_image", [](argList& args) {
		if(args.size() < 3) {
			console.printLn("Need width, height, and output path");
			return;
		}

		Image* out = Image::random(vec2u(toNumber<unsigned>(args[0]),toNumber<unsigned>(args[1])), randomi);

		try {
			if(!saveImage(out,args[2].c_str()))
				throw 0;
			console.printLn("Output image");
		}
		catch(...) {
			console.printLn("Could not write image");
		}

		delete out;
	});

	/*console.addCommand("genetica_planet", [](argList& args) {
		if(args.empty()) {
			console.printLn("Need image path and optional output path");
			return;
		}

		Image* source = loadImage(args[0].c_str());
		if(!source) {
			console.printLn("Could not locate file");
			return;
		}

		//Hack: We need the image to be twice as wide as tall, so we completely violate all sense of sanity to do it easily
		source->height = source->width / 2;

		Image* out = source->sphereDistort();

		try {
			if(!saveImage(out,args.size() > 1 ? args[1].c_str() : args[0].c_str()))
				throw 0;
			console.printLn("Exported spherized genetica planet");
		}
		catch(...) {
			console.printLn("Could not write image");
		}

		delete out;
	});*/

	console.addCommand("save", [](argList& args) {
		if(game_state != GS_Game) {
			error("No game to save.");
			return;
		}
		if(devices.network->isClient) {
			error("Cannot save game from multiplayer clients.");
			return;
		}

		std::string savePath = devices.mods.getGlobalProfile("saves");
		std::string filename = path_join(savePath, args.empty() ? "quicksave.sr2" : args[0]);
		if(!match(filename.c_str(),"*.sr2"))
			filename += ".sr2";

		double start = devices.driver->getAccurateTime();

		processing::pause();
		bool success = saveGame(filename);
		processing::resume();

		if(success) {
			double end = devices.driver->getAccurateTime();
			console.printLn(format("Saved '$1' (Took $2ms)", filename, (end - start) * 1000.0));
		}
	});

	console.addCommand("3d_scale", [](argList& args) {
		extern double scale_3d;
		if(!args.empty()) {
			double scale = toNumber<double>(args[0]);
			if(scale > 0 && scale <= 2.0) {
				scale_3d = scale;
			}
			else {
				console.printLn("3D Render scale must be within (0,2]");
				return;
			}
		}

		console.printLn(format("3D Scale: $1", toString(scale_3d, 2)));
	});

	console.addCommand("gpu_mem", [](argList& args) {
		unsigned long long texMem = 0, meshMem = 0;

		auto& textures = devices.library.textures;
		for(size_t i = 0; i < textures.size(); ++i)
			texMem += textures[i]->getTextureBytes();

		auto& meshes = devices.library.meshes;
		for(auto i = meshes.begin(), end = meshes.end(); i != end; ++i)
			meshMem += i->second->getMeshBytes();

		unsigned long long MB_Bytes = 1024 * 1024;
		console.printLn(format(" GPU Total Mem Estimate: $1MB", (unsigned)((texMem + meshMem) / MB_Bytes)));
		console.printLn(format(" GPU   Tex Mem Estimate: $1MB", (unsigned)(texMem / MB_Bytes)));
		console.printLn(format(" GPU  Mesh Mem Estimate: $1MB", (unsigned)(meshMem / MB_Bytes)));
	});

	console.addCommand("vb_float_limit", [](argList& args) {
		if(!args.empty())
			render::vbFloatLimit = toNumber<unsigned>(args.front());
		console.printLn(toString(render::vbFloatLimit));
	});

	console.addCommand("vb_step_limit", [](argList& args) {
		if(!args.empty())
			render::vbMaxSteps = toNumber<unsigned>(args.front());
		console.printLn(toString(render::vbMaxSteps));
	});

	console.addCommand("reload_gui", [](argList& args) {
		reload_gui = true;
	});

	//Get command line arguments
	std::vector<std::string> mods;
	std::string localeName = "";
	bool loadGraphics = true;
	bool createWindow = true;

	bool handleCrashes = true;

	for(int argi = 1; argi < argc; ++argi) {
		std::string arg = argv[argi];
		if(arg.size() == 1) {
			error("Found '%c', accidental space?", arg[0]);
			continue;
		}

		//Compatibility for switches
		if(arg[0] == '-' && arg[1] == '-')
			arg = arg.substr(2, arg.size() - 2);
		else if(arg[0] == '-' || arg[0] == '+' || arg[0] == '/')
			arg = arg.substr(1, arg.size() - 1);

		//Options
		if(arg == "mod") {
			++argi;
			if(argi < argc)
				mods.push_back(argv[argi]);
			else
				error("Error: mod option requires a mod name.");
		}
		else if(arg == "locale") {
			++argi;
			if(argi < argc)
				localeName = argv[argi];
			else
				error("Error: locale option requires a locale name.");
		}
		else if(arg == "load") {
			++argi;
			if(argi < argc) {
				std::string fname = devices.mods.getGlobalProfile("saves");
				fname = path_join(fname, argv[argi]);
				if(!match(fname.c_str(),"*.sr2"))
					fname += ".sr2";

				SaveFileInfo info;
				if(getSaveFileInfo(fname, info)) {
					mods.clear();
					for(auto i = info.mods.begin(), end = info.mods.end(); i != end; ++i) {
						auto* m = devices.mods.getMod(i->id);
						if(m) m = m->getFallback(i->version);

						mods.push_back(m ? m->ident : i->id);
					}
					loadSaveName = fname;
				}
				game_state = GS_Game;
			}
			else
				error("Error: load option requires a save name.");
		}
		else if(arg == "quickstart") {
			game_state = GS_Game;
		}
		else if(arg == "watch-resources") {
			watch_resources = true;
		}
		else if(arg == "reload-gui") {
			reload_gui = true;
		}
		else if(arg == "test-scripts") {
			game_state = GS_Test_Scripts;
			loadGraphics = false;
		}
		else if(arg == "monitor-scripts") {
			game_state = GS_Monitor_Scripts;
			loadGraphics = false;
			monitor_files = true;
		}
		else if(arg == "no-window") {
			createWindow = false;
		}
		else if(arg == "no-sound") {
			use_sound = false;
		}
		else if(arg == "no-steam") {
			use_steam = false;
		}
		else if(arg == "verbose") {
			setLogLevel(LL_Info);
		}
		else if(arg == "chatty") {
			extern bool LOG_CHATTY;
			LOG_CHATTY = true;
		}
		else if(arg == "no-errorlog") {
			extern bool LOG_ERRORLOG;
			LOG_ERRORLOG = false;
		}
		else if(arg == "fullscreen") {
			fullscreen = true;
		}
		else if(arg == "nojit") {
			useJIT = false;
		}
		else if(arg == "nodump") {
			handleCrashes = false;
		}
		else if(arg == "nomodelcache") {
			extern bool useModelCache;
			useModelCache = false;
		}
		else if(arg == "connect") {
			//NOTE: Added by steam if the player connected through steam
			++argi;
			if(argi < argc)
				launchConnect = argv[argi];
		}
		else if(arg == "password") {
			//NOTE: Added by steam if the player connected through steam to a passworded server
			++argi;
			if(argi < argc)
				launchPassword = argv[argi];
		}
		else if(arg == "connect_lobby") {
			//NOTE: Added by steam if the player connected on a steam lobby
			++argi;
			if(argi < argc)
				launchLobby = argv[argi];
		}
		else if(arg == "version") {
			printf(
			"-- Star Ruler 2 v%s --\nEngine Build: %d\n"
			"Server Script Build: %d\nClient Script Build: %d\n"
			"Menu Script Build: %d\n",
			GAME_VERSION_NAME, ENGINE_BUILD, SERVER_SCRIPT_BUILD,
			CLIENT_SCRIPT_BUILD, MENU_SCRIPT_BUILD);
			return 0;
		}
		else if(arg == "help") {
			printf("Usage: %s [OPTIONS]\n\n"
				"--mod [MOD]              Start the game with a specific mod active.\n"
				"--locale [LANGUAGE]      Start the game in a specific language.\n"
				"--load [SAVEGAME]        Load the specified savegame on start.\n"
				"--quickstart             Immediately start a new game, skipping the menu.\n"
				"--watch-resources        Automatically reload certain data files if changed.\n"
				"--test-scripts           Compile scripts, then exit, logging any errors.\n"
				"--monitor-scripts        Monitor scripts and run --test-scripts if changed.\n"
				"--no-window              Run --test/monitor-scripts in console mode.\n"
				"--no-sound               Disable the sound system from ever running.\n"
				"--no-steam               Disable all steam functionality from running.\n"
				"--verbose                Log more information about the game's state.\n"
				"--fullscreen             Run the game in full screen mode.\n"
				"--version                Display version information of the binary.\n"
				"--help                   Display this help message.\n"
				, argv[0]);
			return 0;
		}
		else {
			error("Unhandled argument: '%s'", arg.c_str());
		}
	}

	//Initialize dumping crash data
	if(handleCrashes)
		initCrashDump();

	//Initialize global stuff
	if(!initGlobal(loadGraphics, createWindow))
		return 1;

	//Initialize threaded variables for this thread
	initNewThread();

	//Use the default locale
	if(!localeName.empty()) {
		game_locale = localeName;
	}
	else {
		auto* loc = devices.settings.engine.getSetting("sLocale");
		if(loc)
			game_locale = loc->toString();
	}

	//Run the default mod
	print("Loading mod(s)");
	initMods(mods);

	//Check for initialization options
	switch(game_state) {
		case GS_Game:
			initGame();
		break;
		case GS_Test_Scripts:
			if(createWindow) {
				game_state = GS_Console_Wait;
			}
			else {
				finishPreload();
				game_state = GS_Quit;
			}
		case GS_Monitor_Scripts:
			processing::end();
			processing::clear();
		break;
	}

	threads::setThreadPriority(threads::TP_High);

	//NOTE: Only supports ipv4 address:port or domain names with implied port; ipv6 will break
	if(!launchLobby.empty()) {
		if(devices.cloud)
			launchConnect = devices.cloud->getLobbyConnectAddress(launchLobby, &launchPassword);
		if(launchConnect.empty())
			error("Error: could not find lobby with id '%s'\n", launchLobby.c_str());
		else
			info("Connecting to lobby '%s'...\n", launchLobby.c_str());
	}
	if(!launchConnect.empty()) {
		unsigned short port = 2048;
		auto portIndex = launchConnect.find_last_of(':');
		if(portIndex != std::string::npos)
			port = toNumber<unsigned>(launchConnect.substr(portIndex+1));

		devices.network->connect(launchConnect.substr(0, portIndex), port, launchPassword, true);
	}

	devices.render->reportErrors("Pre-init");

	//Run the main loop
	while(game_state != GS_Quit) {
		//Render whichever state we're in
		switch(game_state) {
			case GS_Menu:
				tickMenu();
			break;
			case GS_Game:
				if(!game_running)
					initGame();
				tickGame();
			break;
			case GS_Monitor_Scripts:
				if(tickMonitor()) {
					finishPreload();
					destroyMod();
					if(createWindow)
						console.clear();
					else
						printf("\n\n--Reloading--\n\n\n");
					initMods(mods);
				}
				if(!createWindow) {
					threads::sleep(100);
					break;
				}
			case GS_Console_Wait:
				console.show();
				tickConsole();
			break;
			case GS_Load_Prep:
				extern bool loadPrep(const std::string& fname);
				if(!loadPrep(loadSaveName)) {
					loadSaveName.clear();
					if(game_running)
						game_state = GS_Game;
					else
						game_state = GS_Menu;
				}
			break;
			default:
			break;
		}
	}

	destroyMod();
	destroyGlobal();

	if(launchPatcher) {
#ifdef _MSC_VER
		char buffer[1024];
		sprintf_s(buffer, "start \"Star Ruler 2 Patcher\" patcher.exe \"%s\"", getAbsolutePath(".").c_str());
		system(buffer);
#else
		if(fork() == 0) {
#ifdef __amd64__
			execlp("./bin/lin64/Patcher.bin", "./bin/lin64/Patcher.bin", (char*)nullptr);
#else
			execlp("./bin/lin32/Patcher.bin", "./bin/lin32/Patcher.bin", (char*)nullptr);
#endif
			exit(1);
		}
#endif
	}
}
