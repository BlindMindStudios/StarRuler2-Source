#include "util/random.h"
#include "util/threaded_loader.h"
#include "util/name_generator.h"
#include "render/gl_driver.h"
#include "render/lighting.h"
#include "main/profiler.h"
#include "main/initialization.h"
#include "main/logging.h"
#include "main/input_handling.h"
#include "main/version.h"
#include "main/references.h"
#include "main/console.h"
#include "main/game_platform.h"
#include "os/glfw_driver.h"
#include "scripts/manager.h"
#include "scripts/binds.h"
#include "scripts/context_cache.h"
#include "scripts/script_components.h"
#include "constants.h"
#include "files.h"
#include "threads.h"
#include "processing.h"
#include "general_states.h"
#include "empire.h"
#include "empire_stats.h"
#include "scene/node.h"
#include "scene/mesh_node.h"
#include "scene/plane_node.h"
#include "scene/billboard_node.h"
#include "scene/animation/anim_node_sync.h"
#include "scene/scripted_node.h"
#include "obj/universe.h"
#include "obj/lock.h"
#include "as/as_jit.h"
#include "design/hull.h"
#include "design/design.h"
#include "design/subsystem.h"
#include "design/effect.h"
#include "design/projectiles.h"
#include "ISoundDevice.h"
#include "network/network_manager.h"
#include "str_util.h"
#include "physics/physics_world.h"
#include "util/save_file.h"
#include "save_load.h"
#include "render/lighting.h"
#include <stdio.h>
#include <fstream>

namespace scripts {
	void processEvents();
};

#ifdef _WIN32
	#define USE_JIT
#endif
#ifdef __i386__
	#define USE_JIT
#endif
#ifdef __amd64__
	#define USE_JIT
#endif

GameConfig gameConfig;
bool create_window = true;
bool load_resources = true;
bool watch_resources = false;
bool monitor_files = false;
bool use_sound = true;
bool use_steam = true;
bool isLoadedGame = false;
int SAVE_VERSION = -1, START_VERSION = -1;
bool gameEnding = false;
bool fullscreen = false;
bool cancelAssets = false;
#ifdef USE_JIT
bool useJIT = true;
#else
bool useJIT = false;
#endif
std::string loadSaveName;
std::unordered_set<std::string> dlcList;

//Poor mans steam-independent DLC checks
bool hasDLC(const std::string& name) {
	return dlcList.find(name) != dlcList.end();
}

void checkDLC(const std::string& name, const std::string& hashname) {
	//std::string fname("data/dlc/");
	//fname += hashname;
	//if(fileExists(fname) || (devices.cloud && devices.cloud->hasDLC(name)))

	// Open source version always has DLC
	dlcList.insert(name);
}

void checkDLC() {
	dlcList.clear();
	checkDLC("Heralds", "");
}

void checkCloudDLC(const std::string& name, const std::string& hashname) {
	/*std::string fname("data/dlc/");
	fname += hashname;

	if(devices.cloud->hasDLC(name)) {
		if(!fileExists(fname)) {
			makeDirectory("data/dlc/");
			std::fstream file(fname, std::ios_base::out | std::ios_base::binary);
			file << "\n";
			file.close();
		}
		dlcList.insert("Heralds");
	}
	else {
		if(fileExists(fname))
			remove(fname.c_str());
		dlcList.erase(name);
	}*/

	// Open source version always has DLC
	dlcList.insert(name);
}

void checkCloudDLC() {
	if(!devices.cloud)
		return;

	checkCloudDLC("Heralds", "");
}

extern const render::Shader* fsShader;

extern std::set<std::string> validPaths;

extern void prepareShaderStateVars();
extern void clearShaderStateVars();
int threadCount;

extern bool queuedModSwitch;
extern std::vector<std::string> modSetup;

template<resource::ResourceType type>
void loadLibraryFile(const std::string& path) {
	devices.library.load(type, path);
}

#define libraryDir(dir, type) devices.mods.listFiles(dir, "*.txt", loadLibraryFile<type>);

bool processQueuedMeshes();

asCJITCompiler* makeJITCompiler() {
#ifdef USE_JIT
	if(!useJIT)
		return 0;
	unsigned flags = 0;
#ifndef PROFILE_EXECUTION
	return new asCJITCompiler(flags | JIT_NO_SUSPEND | JIT_SYSCALL_FPU_NORESET | JIT_ALLOC_SIMPLE | JIT_FAST_REFCOUNT);
#else
	return new asCJITCompiler(flags | JIT_SYSCALL_FPU_NORESET | JIT_ALLOC_SIMPLE | JIT_FAST_REFCOUNT);
#endif
#else
	return 0;
#endif
}

void loadEngineSettings();
Threaded(std::vector<std::function<void()>>*) cleanupFunctions = 0;

threads::Mutex scriptListLock;
std::map<std::string, std::map<std::string, std::string>*> scriptfiles;

void clearScriptList() {
	threads::Lock lock(scriptListLock);
	for(auto i = scriptfiles.begin(), end = scriptfiles.end(); i != end; ++i)
		delete i->second;
	scriptfiles.clear();
}

const std::map<std::string, std::string>& findScripts(const std::string& path) {
	threads::Lock lock(scriptListLock);
	auto*& m = scriptfiles[path];
	if(!m) {
		m = new std::map<std::string, std::string>;
		devices.mods.listFiles(path, *m, "*.as", true);
	}
	return *m;
}

void onScripts(const std::string& path, std::function<void(const std::pair<std::string,std::string>&)> f) {
	auto& scripts = findScripts(path);
	for(auto i = scripts.cbegin(), end = scripts.cend(); i != end; ++i)
		f(*i);
}

threads::Signal scriptPreloads;

threads::threadreturn threadcall PreloadBatch(void* arg) {
	std::string* pPath = (std::string*)arg;
	std::string& path = *pPath;
	auto preload = [](const std::pair<std::string,std::string>& file) {
		if(file.second.find("/include/") == std::string::npos)
			scripts::preloadScript(file.second);
	};
	onScripts(path, preload);
	scriptPreloads.signalDown();
	delete pPath;
	return 0;
}

void initNewThread() {
	//Start up random number generator
	initRandomizer();

	//Initialize thread-local script context cache
	scripts::initContextCache();
}

void cleanupThread() {
	scripts::freeContextCache();
	asThreadCleanup();

	freeRandomizer();

	if(cleanupFunctions) {
		foreach(it, (*cleanupFunctions))
			(*it)();
		delete cleanupFunctions;
		cleanupFunctions = 0;
	}
}

void addThreadCleanup(std::function<void()> func) {
	if(!cleanupFunctions)
		cleanupFunctions = new std::vector<std::function<void()>>();
	cleanupFunctions->push_back(func);
}

bool initGlobal(bool loadGraphics, bool createWindow) {
	//Create the sound device
	try {
		if(use_sound) {
			print("Initializing sound");
			auto* audioDevice = devices.settings.engine.getSetting("sAudioDevice");
			if(audioDevice)
				devices.sound = audio::createAudioDevice(audioDevice->toString().c_str());
			else
				devices.sound = audio::createAudioDevice();
		}
		
		if(!devices.sound)
			devices.sound = audio::createDummyAudioDevice();
	}
	catch(const char* err) {
		error("Sound Error: %s", err);
		devices.sound = audio::createDummyAudioDevice();
	}

	devices.sound->setVolume(0.5f);
	devices.sound->setRolloffFactor(1.f / 10000.f);

	//Safe AS multithreading
	asPrepareMultithread();

	print("Initializing window system");
	devices.driver = os::getGLFWDriver();
	devices.driver->resetTimer();

	//Load engine settings
	print("Loading engine settings");
	loadEngineSettings();

	console.addCommand("fov", [](argList& args) {
		if(devices.render && !args.empty()) {
			double newFOV = toNumber<double>(args[0]);
			if(newFOV > 0.1 && newFOV < 179.9)
				devices.render->setFOV(newFOV);
			else
				console.printLn("FOV must be within 0.1 and 179.9 degrees");
		}
	} );

	console.addCommand("vsync", [](argList& args) {
		if(devices.driver) {
			if(args.empty())
				devices.driver->setVerticalSync(true);
			else if(streq_nocase(args[0],"adaptive"))
				devices.driver->setVerticalSync(-1);
			else
				devices.driver->setVerticalSync(toBool(args[0]));
		}
	} );

	console.addCommand("load", [](argList& args) {
		std::string savePath = devices.mods.getProfile("saves");
		std::string filename = path_join(savePath, args.empty() ? "quicksave.sr2" : args[0]);
		if(!match(filename.c_str(),"*.sr2"))
			filename += ".sr2";

		scripts::scr_loadGame(filename);
	});

	console.addCommand("maxfps", [](argList& args) {
		extern double* maxfps;
		if(!args.empty())
			*maxfps = toNumber<double>(args[0]);
		console.printLn(toString(maxfps,0));
	} );

	console.addCommand("r", [](argList& args) {
		if(devices.scripts.client && !args.empty())
		devices.scripts.client->reload(args[0]);
	} );

	if(load_resources) {
		print("Initializing OpenGL Engine");
		devices.render = render::createGLDriver();
	}
	else {
		devices.render = nullptr;
	}

	create_window = createWindow;

	load_resources = loadGraphics;

	//Create network driver
	devices.network = new NetworkManager();
	auto* netLimit = devices.settings.engine.getSetting("iNetworkRateLimit");
	net::Transport::RATE_LIMIT = (netLimit ? *netLimit : 250) * 1024;

	devices.scripts.client = nullptr;
	devices.scripts.server = nullptr;
	devices.scripts.cache_server = nullptr;
	devices.scripts.cache_shadow = nullptr;
	devices.scripts.menu = nullptr;
	
	devices.engines.client = nullptr;
	devices.engines.server = nullptr;
	devices.engines.menu = nullptr;

	//Check marked DLCs
	checkDLC();

	//Add mod sources
	print("Registering mods");
	devices.mods.registerDirectory("mods");
	devices.mods.registerDirectory(getProfileRoot() + "mods");
	devices.mods.registerDirectory("../../workshop/content/282590");

	//Shortcut for the scene tree
	if(devices.render)
		devices.scene = &devices.render->rootNode;
	else
		devices.scene = nullptr;
	devices.universe = nullptr;

	//Initialize input handling
	registerInput();

	//Create processing queue
	unsigned cpuCount = devices.driver->getProcessorCount();
	threadCount = std::max(cpuCount+1,1u);
	print("Starting %d threads on %d processors.", threadCount, cpuCount);
	processing::start(threadCount);

	return true;
}

void destroyGlobal() {
	devices.network->disconnect();
	delete devices.network;

	asUnprepareMultithread();

	devices.driver->closeWindow();
	delete devices.driver;
}

void loadLocales(std::string folder, mods::Mod* mod) {
	if(mod->parent != nullptr)
		loadLocales(folder, mod->parent);
	std::map<std::string, std::string> files;
	mod->listFiles(folder, files, "*.txt", true, false);
	foreach(file, files)
		devices.locale.load(file->second);
}

void switchLocale(const std::string& locale) {
	devices.locale.clear();
	foreach(m, devices.mods.activeMods)
		loadLocales("locales/english", *m);
	if(locale != "english") {
		std::string dirname = path_join("locales", locale);
		foreach(m, devices.mods.activeMods)
			loadLocales(dirname, *m);
	}
}

std::string makeModuleName(const std::string& fname) {
	std::string mname;
	std::vector<std::string> components;
	path_split(fname, components);

	for(size_t i = 0, cnt = components.size() - 1; i < cnt; ++i)
		mname += components[i]+".";
	mname += getBasename(fname, false);
	return mname;
}

static threads::Signal jitInit;
void loadServerScripts() {
	std::map<std::string, std::string> scriptfiles;
	double start = devices.driver->getAccurateTime();

	devices.scripts.cache_server = new scripts::Manager(makeJITCompiler());

#ifdef PROFILE_LOCKS
	devices.scripts.cache_server->threadedCallMutex.name = "Server Threaded Call Lock";
	devices.scripts.cache_server->threadedCallMutex.observed = true;
#endif

	devices.scripts.cache_server->addIncludePath("scripts/");
	devices.scripts.cache_server->addIncludePath("scripts/server");
	devices.scripts.cache_server->addIncludePath("scripts/shared");
	devices.scripts.cache_server->addIncludePath("scripts/definitions");
	devices.scripts.cache_server->addIncludePath("maps/");

	scripts::RegisterServerBinds(devices.scripts.cache_server->engine);
	
	auto load = [](const std::pair<std::string,std::string>& file) {
		if(cancelAssets)
			return;
		if(file.second.find("/include/") != std::string::npos)
			return;

		devices.scripts.cache_server->load(
			makeModuleName(file.first),
			file.second);
	};
	
	onScripts("scripts/server", load);
	onScripts("scripts/shared", load);
	onScripts("scripts/definitions", load);
	onScripts("maps", load);

	double load_end = devices.driver->getAccurateTime();
	devices.scripts.cache_server->compile(
		devices.mods.getProfile("as_cache/server"),
		SERVER_SCRIPT_BUILD);

	double compile_end = devices.driver->getAccurateTime();
	print("Server scripts: %dms load, %dms compile",
		int((load_end - start) * 1000.0),
		int((compile_end - load_end) * 1000.0));
}

void loadShadowScripts() {
	std::map<std::string, std::string> scriptfiles;
	double start = devices.driver->getAccurateTime();

	devices.scripts.cache_shadow = new scripts::Manager(makeJITCompiler());

#ifdef PROFILE_LOCKS
	devices.scripts.cache_shadow->threadedCallMutex.name = "Shadow Threaded Call Lock";
	devices.scripts.cache_shadow->threadedCallMutex.observed = true;
#endif

	devices.scripts.cache_shadow->addIncludePath("scripts/");
	devices.scripts.cache_shadow->addIncludePath("scripts/shadow");
	devices.scripts.cache_shadow->addIncludePath("scripts/shared");
	devices.scripts.cache_shadow->addIncludePath("scripts/definitions");
	devices.scripts.cache_shadow->addIncludePath("maps/");

	scripts::RegisterShadowBinds(devices.scripts.cache_shadow->engine);
	
	auto load = [](const std::pair<std::string,std::string>& file) {
		if(cancelAssets)
			return;
		if(file.second.find("/include/") != std::string::npos)
			return;

		devices.scripts.cache_shadow->load(
			makeModuleName(file.first),
			file.second);
	};
	
	onScripts("scripts/shadow", load);
	onScripts("scripts/shared", load);
	onScripts("scripts/definitions", load);
	onScripts("maps", load);

	double load_end = devices.driver->getAccurateTime();
	devices.scripts.cache_shadow->compile(
		devices.mods.getProfile("as_cache/shadow"),
		SERVER_SCRIPT_BUILD);

	double compile_end = devices.driver->getAccurateTime();
	print("Shadow scripts: %dms load, %dms compile",
		int((load_end - start) * 1000.0),
		int((compile_end - load_end) * 1000.0));
}

void loadClientScripts() {
	std::map<std::string, std::string> scriptfiles;
	double start = devices.driver->getAccurateTime();

	devices.scripts.client = new scripts::Manager(makeJITCompiler());
	devices.engines.client = devices.scripts.client->engine;

#ifdef PROFILE_LOCKS
	devices.scripts.client->threadedCallMutex.name = "Client Threaded Call Lock";
	devices.scripts.client->threadedCallMutex.observed = true;
#endif

	scripts::RegisterClientBinds(devices.scripts.client->engine);
	devices.scripts.client->addIncludePath("scripts/");
	devices.scripts.client->addIncludePath("scripts/client");
	devices.scripts.client->addIncludePath("scripts/gui");
	devices.scripts.client->addIncludePath("scripts/shared");
	devices.scripts.client->addIncludePath("scripts/toolkit");
	devices.scripts.client->addIncludePath("scripts/definitions");
	devices.scripts.client->addIncludePath("maps/");
	
	auto load = [](const std::pair<std::string,std::string>& file) {
		if(cancelAssets)
			return;
		if(file.second.find("/include/") != std::string::npos)
			return;

		devices.scripts.client->load(
			makeModuleName(file.first),
			file.second);
	};
	
	onScripts("scripts/client", load);
	onScripts("scripts/gui", load);
	onScripts("scripts/shared", load);
	onScripts("scripts/toolkit", load);
	onScripts("scripts/definitions", load);
	onScripts("maps", load);

	double load_end = devices.driver->getAccurateTime();
	devices.scripts.client->compile(
		devices.mods.getProfile("as_cache/client"),
		CLIENT_SCRIPT_BUILD);

	double compile_end = devices.driver->getAccurateTime();
	print("Client scripts: %dms load, %dms compile",
		int((load_end - start) * 1000.0),
		int((compile_end - load_end) * 1000.0));
}

void bindScripts() {
	//Bind all script binds
	scripts::BindEventBinds();
	bindScriptObjectTypes();
	scripts::bindComponentClasses();
	scene::bindScriptNodeTypes();

	//We cannot actually execute things on
	//the shadow, so don't try to bind things
	bindEffectorHooks(devices.network->isClient);
	bindSubsystemHooks();
	if(!devices.network->isClient) {
		bindEffectHooks();
	}
}

volatile bool idleImageActive = false;
threads::threadreturn threadcall idleProcessImages(void*) {
	idleImageActive = true;
	while(devices.library.hasQueuedImages()) {
		devices.library.processImages(INT_MIN,1);
		threads::sleep(1);
	}
	idleImageActive = false;
	return 0;
}

volatile bool idleSoundsActive = false;
threads::threadreturn threadcall idleProcessSounds(void*) {
	idleSoundsActive = true;
	while(devices.library.hasQueuedSounds()) {
		devices.library.processSounds(INT_MIN,1);
		threads::sleep(1);
	}
	idleSoundsActive = false;
	return 0;
}

volatile bool idleHullsActive = false;
threads::threadreturn threadcall idleComputeHulls(void*) {
	double tstart = devices.driver->getAccurateTime();

	idleHullsActive = true;
	initRandomizer();
	while(!isFinishedComputingHulls() && !cancelAssets) {
		computeHulls(1);
		threads::sleep(1);
	}
	idleHullsActive = false;

	double tend = devices.driver->getAccurateTime();
	print("Finished computing hulls in %gms", (tend-tstart)*1000.0);
	return 0;
}

bool preloading = false;
void startPreload() {
	if(preloading)
		return;

	//Preload things for the game
	Loading::prepare(5, initNewThread, cleanupThread);

	Loading::addTask("ServerScripts", 0, [] {
		loadServerScripts();
	});

	Loading::addTask("ShadowScripts", 0, [] {
		loadShadowScripts();
	});

	Loading::addTask("ClientScripts", 0, [] {
		loadClientScripts();
	});

	Loading::addTask("CleanupScripts", "ServerScripts,ShadowScripts,ClientScripts", [] {
		clearScriptList();
		scripts::clearCachedScripts();
	});

	Loading::addTask("ProcessImages", 0, [] {
		devices.library.processImages(-10);
		threads::createThread(idleProcessImages, 0);
	});

	Loading::addTask("ProcessSounds", 0, [] {
		devices.library.processSounds(-10);
		threads::createThread(idleProcessSounds, 0);
	});

	Loading::addTask("ComputeHulls", 0, [] {
		if(load_resources)
			threads::createThread(idleComputeHulls, 0);
	});

#ifdef DOCUMENT_API
	Loading::addTask("Documentation", "ClientScripts,ServerScripts", [] {
		scripts::documentBinds();
	});
#endif

	preloading = true;
}

bool isPreloading() {
	return preloading;
}

void finishPreload() {
	if(!preloading) {
		startPreload();
		Loading::finalize();
	}

	while(!Loading::finished()) {
		Loading::process();
		devices.driver->handleEvents(1);
	}

	const int priority = -10;
	while(devices.library.processImages(priority)) {}
	while(devices.library.processTextures(priority)) {}
	while(devices.library.processSounds(priority)) {}
	while(devices.library.processMeshes(priority)) {}

	while(!Loading::finished()) {
		Loading::process();
		devices.driver->handleEvents(1);
	}

	Loading::finish();
	preloading = false;
}

namespace resource {
extern threads::Signal unqueuedMeshes;
};
void cancelLoad() {
	cancelAssets = true;

	while(!Loading::finished()) {
		Loading::process();
		devices.driver->handleEvents(1);
	}

	const int priority = INT_MIN;
	while(devices.library.processImages(priority)) {}
	while(idleImageActive) { devices.driver->handleEvents(1); }
	while(devices.library.processTextures(priority)) {}
	while(devices.library.processSounds(priority)) {}
	while(devices.library.processMeshes(priority)) {}
	while(idleSoundsActive) { devices.driver->handleEvents(1); }
	while(idleHullsActive) { devices.driver->handleEvents(1); }
	resource::unqueuedMeshes.wait(0);

	Loading::finish();

	cancelAssets = false;
	preloading = false;
}

void readGameConfig(const std::string& filename) {
	gameConfig.count = 0;
	//delete gameConfig.names;
	//delete gameConfig.values;
	gameConfig.indices.clear();

	std::vector<std::string> names;
	std::vector<double> values;
	DataHandler file;
	file.defaultHandler([&](std::string& key, std::string& value) {
		names.push_back(key);
		values.push_back(toNumber<double>(value));
	});
	file.read(filename);

	gameConfig.count = names.size();
	gameConfig.names = new std::string[gameConfig.count];
	gameConfig.values = new double[gameConfig.count];
	gameConfig.defaultValues = new double[gameConfig.count];

	for(size_t i = 0; i < gameConfig.count; ++i) {
		gameConfig.names[i] = names[i];
		gameConfig.values[i] = values[i];
		gameConfig.defaultValues[i] = values[i];
		gameConfig.indices[names[i]] = i;
	}
}

void resetGameConfig() {
	for(size_t i = 0; i < gameConfig.count; ++i)
		gameConfig.values[i] = gameConfig.defaultValues[i];
}

void readGameConfig(net::Message& msg) {
	for(size_t i = 0; i < gameConfig.count; ++i)
		msg >> gameConfig.values[i];
}

void writeGameConfig(net::Message& msg) {
	for(size_t i = 0; i < gameConfig.count; ++i)
		msg << gameConfig.values[i];
}

void saveGameConfig(SaveFile& file) {
	file << (unsigned)gameConfig.count;
	for(size_t i = 0; i < gameConfig.count; ++i) {
		file << gameConfig.names[i];
		file << gameConfig.values[i];
	}
}

void loadGameConfig(SaveFile& file) {
	unsigned count = 0;
	if(file >= SFV_0003) {
		file >> count;
	}
	else {
		size_t woops = 0;
		file >> woops;
		count = (unsigned)woops;
	}

	for(size_t i = 0; i < count; ++i) {
		std::string name;
		file >> name;

		double value;
		file >> value;

		auto it = gameConfig.indices.find(name);
		if(it != gameConfig.indices.end())
			gameConfig.values[it->second] = value;
	}
}

bool loadPrep(const std::string& fname) {
	if(!scripts::isAccessible(fname))
		return false;

	SaveFileInfo info;
	getSaveFileInfo(fname, info);

	//Check if we need to switch mods
	std::vector<bool> modCheck;
	unsigned modCnt = info.mods.size();
	unsigned activeCnt = devices.mods.activeMods.size();
	modCheck.resize(activeCnt);
	for(unsigned i = 0; i < activeCnt; ++i)
		modCheck[i] = false;

	std::vector<std::string> ids;

	bool shouldSwitch = false;
	for(unsigned i = 0; i < modCnt; ++i) {
		bool found = false;
		auto* mod = devices.mods.getMod(info.mods[i].id);
		if(mod)
			mod = mod->getFallback(info.mods[i].version);

		if(mod == nullptr)
			return false;

		ids.push_back(mod->ident);

		for(unsigned j = 0; j < activeCnt; ++j) {
			if(modCheck[j])
				continue;
			if(devices.mods.activeMods[j] == mod) {
				found = true;
				modCheck[j] = true;
				break;
			}
		}
		if(!found) {
			shouldSwitch = true;
			break;
		}
	}
	for(unsigned i = 0; i < activeCnt; ++i) {
		if(!modCheck[i]) {
			shouldSwitch = true;
			break;
		}
	}

	if(game_running)
		destroyGame();

	//Switch mods if needed
	if(shouldSwitch) {
		::info("Switching mods for savegame...");
		destroyMod();
		initMods(ids);
	}

	//Actually load
	clearGameSettings();
	loadSaveName = fname;
	game_state = GS_Game;
	return true;
}

struct ToggleConsoleBind : profile::Keybind {
	void call(bool pressed) {
		if(!pressed) {
			console.toggle();
		}
	}
};

void initMods(const std::vector<std::string>& mods) {
	auto prevSection = enterSection(NS_Loading);

	//Load global resources
	Loading::prepare(5, initNewThread, cleanupThread);

	Loading::addTask("CloudInit", 0, [] {
#ifndef NSTEAM
			if(use_steam && !devices.cloud)
				devices.cloud = GamePlatform::acquireSteam();
#endif
		} );

	static bool didCloudFiles = false, didCloudMods = false;

	Loading::addTask("CloudMods", "CloudInit", [] {
			if(didCloudMods)
				return;
			didCloudMods = true;

			if(devices.cloud) {
				CloudDownload dl;
				for(unsigned i = 0, cnt = devices.cloud->getDownloadedItemCount(); i < cnt; ++i) {
					if(devices.cloud->getDownloadedItem(i, dl)) {
						validPaths.insert(dl.path);
						auto folderNameEnds = dl.path.find_last_not_of("\\/");
						auto folderNameStarts = dl.path.find_last_of("\\/", folderNameEnds);
						if(folderNameStarts != std::string::npos)
							devices.mods.registerMod(dl.path, dl.path.substr(folderNameStarts+1, folderNameEnds - folderNameStarts));
					}
				}

				checkCloudDLC();
			}
			devices.mods.finalize();
		} );

	Loading::addTask("CloudFiles", "CloudInit", [] {
			if(devices.cloud && !didCloudFiles) {
				didCloudFiles = false;
				devices.cloud->addCloudFolder(getProfileRoot(), "saves");
				devices.cloud->syncCloudFiles(getProfileRoot());
			}
		} );

	Loading::addTask("ModInit", "CloudMods", [&] {
		//Set the mod
		devices.mods.clearMods();
		if(mods.empty()) {
			foreach(mod, devices.mods.mods) {
				if((*mod)->enabled) {
					if(devices.mods.enableMod((*mod)->name))
						info("Loading enabled mod %s", (*mod)->name.c_str());
				}
			}
		}
		else foreach(mod, mods) {
			if(devices.mods.enableMod(*mod))
				info("Loading mod %s", mod->c_str());
		}

		//Initialize the library
		devices.library.prepErrorResources();

		//Load keybind descriptors
		std::vector<std::string> bindfiles;
		devices.mods.resolve("data/keybinds.txt", bindfiles);
		foreach(it, bindfiles)
			devices.keybinds.loadDescriptors(*it);

		//Load keybind values from profile, or set defaults
		std::string bindFile = path_join(devices.mods.getProfile("settings"), "keybinds.txt");
		devices.keybinds.setDefaultBinds();
		if(fileExists(bindFile)) {
			devices.keybinds.loadBinds(bindFile);
		}
		else {
			//Load parent keybinds
			foreach(it, devices.mods.activeMods) {
				mods::Mod* prt = *it;
				while(prt) {
					std::string kfile(prt->getProfile("settings"));
					kfile = path_join(kfile, "keybinds.txt");

					if(fileExists(kfile))
						devices.keybinds.loadBinds(kfile);

					prt = prt->parent;
				}
			}

			devices.keybinds.saveBinds(bindFile);
		}

		//Do console bind
		auto* group = devices.keybinds.getGroup("Global");
		if(group) {
			auto* desc = group->getDescriptor("TOGGLE_CONSOLE");
			if(desc) {
				console.keybind = new ToggleConsoleBind();
				group->addBind(desc->id, console.keybind);
			}
		}

		//Run menu autoexec
		console.executeFile(path_join(getProfileRoot(), "autoexec_menu.txt"));

		//Load the locales
		switchLocale(game_locale);

		//Load setting descriptors
		std::vector<std::string> settingfiles;
		devices.mods.resolve("data/settings.txt", settingfiles);
		foreach(it, settingfiles)
			devices.settings.mod.loadDescriptors(*it);

		//Load setting values from profile, or set defaults
		std::string stFile = path_join(devices.mods.getProfile("settings"), "settings.txt");
		if(fileExists(stFile)) {
			devices.settings.mod.loadSettings(stFile);
		}
		else {
			//Load parent keybinds
			foreach(it, devices.mods.activeMods) {
				mods::Mod* prt = *it;
				while(prt) {
					std::string kfile(prt->getProfile("settings"));
					kfile = path_join(kfile, "settings.txt");

					if(fileExists(kfile))
						devices.settings.mod.loadSettings(kfile);

					prt = prt->parent;
				}
			}

			devices.settings.mod.saveSettings(stFile);
		}
	});

	Loading::addTask("Window", "ModInit", [] {
			if(create_window) {
				os::WindowData windat;
				windat.verticalSync = 1;
				bool cursorCapture = false;

				auto* vsync = devices.settings.engine.getSetting("iVsync");
				if(vsync)
					windat.verticalSync = *vsync;

				extern double ui_scale;
				auto* scale = devices.settings.engine.getSetting("dGUIScale");
				if(scale)
					ui_scale = *scale;

				if(!fullscreen)
					fullscreen = *devices.settings.engine.getSetting("bFullscreen");

				if(fullscreen) {
					windat.mode = os::WM_Fullscreen;

					auto* ovr = devices.settings.engine.getSetting("bOverrideResolution");
					if(ovr)
						windat.overrideMonitor = *ovr;

					unsigned w, h;
					devices.driver->getDesktopSize(w, h);

					auto* screenWidth = devices.settings.engine.getSetting("iFsResolutionX");
					int settingWidth = screenWidth ? *screenWidth : 0;
					windat.width = settingWidth > 0 ? settingWidth : (int)w;
					
					auto* screenHeight = devices.settings.engine.getSetting("iFsResolutionY");
					int settingHeight = screenHeight ? *screenHeight : 0;
					windat.height = settingHeight > 0 ? settingHeight : (int)h;

					auto* fsCapture = devices.settings.engine.getSetting("bFsCursorCapture");
					cursorCapture = fsCapture ? *fsCapture : true;

					auto* mon = devices.settings.engine.getSetting("sMonitor");
					if(mon)
						windat.targetMonitor = mon->toString();
				}
				else {
					auto* screenWidth = devices.settings.engine.getSetting("iResolutionX");
					windat.width = screenWidth ? *screenWidth : 1280;
					
					auto* screenHeight = devices.settings.engine.getSetting("iResolutionY");
					windat.height = screenHeight ? *screenHeight : 720;

					auto* fsCapture = devices.settings.engine.getSetting("bCursorCapture");
					cursorCapture = fsCapture ? *fsCapture : true;
				}

				auto* aa = devices.settings.engine.getSetting("iSamples");
				if(aa)
					windat.aa_samples = *aa;

				auto* ss = devices.settings.engine.getSetting("bSupersample");
				if(ss) {
					extern double scale_3d;
					scale_3d = (bool)*ss ? 2.0 : 1.0;
				}

				auto* refresh = devices.settings.engine.getSetting("iRefreshRate");
				if(refresh)
					windat.refreshRate = *refresh;

				devices.driver->createWindow(windat);
				devices.driver->setCursorLocked(cursorCapture);
				devices.driver->setWindowTitle("Star Ruler 2");

				devices.render->init();

				//We should only make a window once
				create_window = 0;
			}
		}, threads::getThreadID() );
	
	if(load_resources) {
		Loading::addTask("Errors", "Window", [] {
				devices.library.generateErrorResources();
			}, threads::getThreadID() );
	}

	Loading::addTask("EmpireStats", "ModInit", [] {
			loadEmpireStats( devices.mods.resolve("data/stats.txt") );
		} );

	Loading::addTask("ObjectTypes", "ModInit", [] {
			loadStateDefinitions(devices.mods.resolve("data/objects.txt"), "Object");
			prepScriptObjectTypes();
		} );

	Loading::addTask("Generics", "ObjectTypes", [] {
			scripts::initGenericTypes();
			for(unsigned i = 0, cnt = getScriptObjectTypeCount(); i < cnt; ++i) {
				auto* type = getScriptObjectType(i);
				scripts::bindGenericObjectType(type, type->name);
			}
		} );

	Loading::addTask("NodeTypes", "Generics", [] {
			scene::loadScriptNodeTypes(devices.mods.resolve("data/nodes.txt"));
		} );

	Loading::addTask("Components", "Generics", [] {
			devices.mods.listFiles("data/components", "*.txt", [](const std::string& file) {
				scripts::loadComponents(file);
			});
		} );

	Loading::addTask("States", "Components,ObjectTypes", [] {
			resetStateValueTypes();
			addObjectStateValueTypes();
			scripts::addComponentStateValueTypes();
			scripts::addNamespaceState();
			loadStateDefinitions(devices.mods.resolve("data/empire_states.txt"));
			finalizeStateDefinitions();
			Empire::setEmpireStates(&getStateDefinition("Empire"));
			scripts::BindEmpireComponentOffsets();
			scripts::buildEmpAttribIndices();
			setScriptObjectStates();
		} );

	Loading::addTask("GameConfig", "ModInit", [] {
			readGameConfig(devices.mods.resolve("data/game_config.txt"));
		} );

	Loading::addTask("ObjComponentOffsets", "ObjectTypes,Components,States", [] {
			scripts::SetObjectTypeOffsets();
		});

	Loading::addTask("Effects", "ModInit", [] {
			devices.mods.listFiles("data/effects", "*.txt", loadEffectDefinitions, true);
		} );
	Loading::addTask("Effectors", "Effects", [] {
			devices.mods.listFiles("data/effectors", "*.txt", loadEffectorDefinitions, true);
		} );
	Loading::addTask("SubSystems", "Effects,Effectors,GameConfig", [] {
			devices.mods.listFiles("data/subsystems", "*.txt", loadSubsystemDefinitions, true);
			executeSubsystemTemplates();
			finalizeSubsystems();
		} );
	Loading::addTask("Shaders", "ModInit", [] {
			devices.library.clearShaderGlobals();
			libraryDir("data/shaders", resource::RT_Shader);
		});
	Loading::addTask("Materials", "Shaders", [] {
			libraryDir("data/materials", resource::RT_Material);
			devices.mods.listFiles("data/shipsets", "materials.txt", loadLibraryFile<resource::RT_Material>, true);
		});

	if(load_resources) {
		Loading::addTask("CompileShaders", "Shaders,Window", [] {
				devices.library.compileShaders();
			}, threads::getThreadID() );
	}
	
	Loading::addTask("Fonts", "ModInit", [] {
			libraryDir("data/fonts", resource::RT_Font);
		} );

	Loading::addTask("Sounds", "ModInit", [] {
			libraryDir("data/sounds", resource::RT_Sound);
		} );

	Loading::addTask("Particles", "Materials,Sounds", [] {
			devices.mods.listFiles("data/particles", "*.ps", loadLibraryFile<resource::RT_ParticleSystem>, true);
		});

	Loading::addTask("SkinStyles", "Fonts", [] {
			libraryDir("data/skin styles", resource::RT_Skin);
		} );

	Loading::addTask("Events", "Generics", [] {
			devices.mods.listFiles("data/events", "*.txt", [](const std::string& file) {
				scripts::ReadEvents(file);
			});

			scripts::LoadScriptHooks(devices.mods.resolve("data/hooks.txt"));
		} );

	Loading::addTask("MaterialBinds", "Materials,SkinStyles,Particles,SubSystems", [] {
			devices.library.bindSkinMaterials();
			bindSubsystemMaterials();
		} );

	Loading::addTask("ResourceBinds", "Materials,Sounds,Particles", [] {
			bindEffectorResources();
		} );
	
	Loading::addTask("Models", "ModInit", [] {
			libraryDir("data/models", resource::RT_Mesh);
			devices.mods.listFiles("data/shipsets", "models.txt", loadLibraryFile<resource::RT_Mesh>, true);
		} );

	Loading::addTask("Shipsets", "Models,Materials,SubSystems", [] {
			devices.mods.listFiles("data/shipsets", "hulls.txt", loadHullDefinitions, true);
			devices.mods.listFiles("data/shipsets", "shipset.txt", loadShipset, true);
			initAllShipset();
		} );

	if(load_resources) {
		Loading::addTask("ShaderStateVars", "Shaders,ObjectTypes,States", [] {
				prepareShaderStateVars();
			});

		Loading::addTask("ProcessSounds", "Sounds", [] {
				devices.library.processSounds(10);
			});

		Loading::addTask("ProcessImages", "Materials,Fonts,Window", [] {
				devices.library.processImages(10);
			});

		Loading::addTask("ProcessTextures", "ProcessImages,Window", [] {
				devices.library.processTextures(10);
			}, threads::getThreadID() );
				
		Loading::addTask("ProcessModels", "Models,Window,Shipsets", [] {
				devices.library.processMeshes();
			}, threads::getThreadID() );
	}

	Loading::addTask("LocateScripts", "ModInit", [] {
		findScripts("scripts/shared");
		findScripts("scripts/definitions");
		findScripts("maps");
		findScripts("scripts/menu");
		findScripts("scripts/toolkit");
		findScripts("scripts/server");
		findScripts("scripts/client");
	});

	Loading::addTask("PreloadScripts", "LocateScripts", [] {
		scriptPreloads.signal(7);
		threads::createThread(PreloadBatch, new std::string("scripts/shared"));
		threads::createThread(PreloadBatch, new std::string("scripts/definitions"));
		threads::createThread(PreloadBatch, new std::string("scripts/menu"));
		threads::createThread(PreloadBatch, new std::string("maps"));
		threads::createThread(PreloadBatch, new std::string("scripts/toolkit"));
		threads::createThread(PreloadBatch, new std::string("scripts/server"));
		threads::createThread(PreloadBatch, new std::string("scripts/client"));
	});

	Loading::addTask("MenuScripts", "LocateScripts,SkinStyles,Materials,Models,Sounds,SubSystems", [] {
			std::map<std::string, std::string> scriptfiles;
			devices.scripts.menu = new scripts::Manager(makeJITCompiler());
			devices.engines.menu = devices.scripts.menu->engine;

			devices.scripts.menu->addIncludePath("scripts/menu");
			devices.scripts.menu->addIncludePath("scripts/shared");
			devices.scripts.menu->addIncludePath("scripts/toolkin");
			devices.scripts.menu->addIncludePath("scripts/gui");
			devices.scripts.menu->addIncludePath("scripts/definitions");
			devices.scripts.menu->addIncludePath("maps/");

			auto loadScript = [](const std::pair<std::string,std::string>& file) {
				if(file.second.find("/include/") != std::string::npos)
					return;

				devices.scripts.menu->load(
					makeModuleName(file.first),
					file.second);
			};
			
			onScripts("scripts/menu", loadScript);
			onScripts("scripts/toolkit", loadScript);
			onScripts("maps", loadScript);

			scripts::RegisterMenuBinds(devices.scripts.menu->engine);
		
			devices.scripts.menu->compile(
				devices.mods.getProfile("as_cache/menu"),
				MENU_SCRIPT_BUILD);

			devices.scripts.menu->init();
			bindInputScripts(GS_Menu, devices.scripts.menu);
			scripts::BindEventBinds(true);
		} );

	Loading::finalize();

	while(!Loading::finished()) {
		Loading::process();
		devices.driver->handleEvents(1);
	}

	Loading::finish();

	enterSection(prevSection);

	devices.library.bindHotloading();

	startPreload();
	Loading::finalize();
	
	if(devices.scripts.menu)
		devices.scripts.menu->garbageCollect(true);
	if(devices.scripts.client)
		devices.scripts.client->garbageCollect(true);
	if(devices.scripts.server)
		devices.scripts.server->garbageCollect(true);
}

void destroyMod() {
	//Make sure we finish loading, or we could de-initialize while adding resources
	cancelLoad();

	stopProjectiles();

	//End processing
	processing::end();
	processing::clear();

	//Remove input script binds
	clearInputScripts(GS_Menu);

	//Clear any active game
	if(game_running)
		destroyGame();

	clearEmpireStats();

	//Remove script nodes
	scene::clearScriptNodeTypes();

	//Clear keybinds
	devices.keybinds.clear();

	//Destroy skin indices
	gui::skin::clearDynamicIndices();

	//Clear shader state vars
	clearShaderStateVars();

	//Clear resources
	devices.library.clear();
	fsShader = nullptr;

	//Clear menu scripts
	delete devices.scripts.menu;
	devices.scripts.menu = 0;
	devices.engines.menu = 0;
	scripts::resetContextCache(true);

	//Stop playing sounds
	if(devices.sound)
		devices.sound->stopAllSounds();

	//Clear console commands
	console.clearCommands();

	//Clear state definitions (For objects, empires)
	clearStateDefinitions();

	//Clear other definitions
	clearHullDefinitions();
	clearShipsets();
	scripts::ClearEvents();
	scripts::clearComponents();
	clearEffectDefinitions();
	clearEffectorDefinitions();
	clearEffectors();
	clearSubsystemDefinitions();
	Empire::setEmpireStates(0);
}

net::Message game_settings;

void setGameSettings(net::Message& msg) {
	game_settings = msg;
}

void clearGameSettings() {
	game_settings.clear();
}

void passSettings(scripts::Manager* man) {
	auto& modules = man->modules;
	for(auto it = modules.begin(); it != modules.end(); ++it) {
		scripts::Module& mod = *it->second;
		if(mod.callbacks[scripts::SC_game_settings] != nullptr) {
			game_settings.rewind();
			scripts::Call cl = mod.call(scripts::SC_game_settings);
			cl.push(&game_settings);
			cl.call();
		}
	}
}

void initGame() {
	if(queuedModSwitch) {
		queuedModSwitch = false;
		destroyMod();
		initMods(modSetup);
	}

	//Tell all the clients to start the game
	if(devices.network->isServer)
		devices.network->startSignal();

	//Wait for all the preloading to finish
	finishPreload();

	//Set the correct server engine to use
	if(devices.network->isClient)
		devices.scripts.server = devices.scripts.cache_shadow;
	else
		devices.scripts.server = devices.scripts.cache_server;
	devices.engines.server = devices.scripts.server->engine;

	bindScripts();

	//Initialize default empire
	processing::resume();
	if(!processing::isRunning()) {
		unsigned cpuCount = devices.driver->getProcessorCount();
		threadCount = std::max(cpuCount+1,1u);
		processing::start(cpuCount);
	}
	Empire::initEmpires();

	//Enable projectile processing
	initProjectiles();

	//Create lock groups
	processing::pause();
	initLocks(threadCount);

	Object::GALAXY_CREATION = true;
	processing::resume();

	//Create the universe
	devices.driver->resetGameTime(0.0);
	resetGameTime();
	resetGameConfig();
	devices.universe = new Universe();

	isLoadedGame = false;
	bool loaded = false;

	if(devices.network->isClient) {
		//Tell the server we're ready to receive
		devices.network->signalClientReady();

		//Initialize server scripts
		devices.scripts.server->init();

		//Wait for the galaxy to be received before
		//starting all the scripts
		while(!devices.network->currentPlayer.hasGalaxy) {
			if(!devices.network->client || !devices.network->client->active) {
				devices.scripts.client->init();
				destroyGame();
				clearGameSettings();
				game_state = GS_Menu;
				return;
			}
			game_state = GS_Menu;
			tickMenu();
			game_state = GS_Game;
		}

		//Pass in game settings after objects
		passSettings(devices.scripts.server);
		passSettings(devices.scripts.client);

		//Initialize client scripts
		devices.scripts.client->init();
	}
	else {
		isLoadedGame = !loadSaveName.empty();

		//Create the universe by passing game settings
		passSettings(devices.scripts.server);
		passSettings(devices.scripts.client);
		
		volatile bool done = false;

		if(isLoadedGame) {
			//LoadGame does script init() in the right place
			threads::async([&done,&loaded]() -> int {
				initNewThread();
				pauseProjectiles();
				loaded = loadGame(loadSaveName);
				resumeProjectiles();
				done = true;
				cleanupThread();
				return 0;
			});
		}
		else {
			threads::async([&done]() -> int {
				initNewThread();
				devices.scripts.server->init();
				devices.scripts.client->init();
				done = true;
				cleanupThread();
				return 0;
			});
		}

		while(!done) {
			tickMenu();
			threads::sleep(1);
		}
	}

	loadSaveName.clear();
	if(isLoadedGame && !loaded) {
		game_state = GS_Menu;
		return;
	}

	bindInputScripts(GS_Game, devices.scripts.client);

	//Run console autoexec
	console.executeFile(path_join(getProfileRoot(), "autoexec.txt"));

	//Tell the clients we're ready to transmit galaxies
	Object::GALAXY_CREATION = false;
	devices.network->currentPlayer.emp = Empire::getPlayerEmpire();
	Empire::getPlayerEmpire()->player = &devices.network->currentPlayer;
	if(devices.network->isServer)
		devices.network->signalServerReady();

	game_running = true;

	//Process events that were deferred until client scripts were initialized
	scripts::processEvents();
}

void destroyGame() {
	gameEnding = true;

	stopProjectiles();

	//Wait for all processing jobs to finish
	processing::end();
	processing::clear();

	//Inform the network
	if(devices.network->serverReady)
		devices.network->endGame();

	//Clear game scripts
	if(devices.scripts.server)
		devices.scripts.server->deinit();
	if(devices.scripts.client)
		devices.scripts.client->deinit();

	//Disconnect network interface if multiplayer
	if(devices.network->isClient || devices.network->serverReady)
		devices.network->disconnect();

	//Clear all lights
	render::light::destroyLights();

	//Remove lock groups
	destroyLocks();

	//Remove input script binds
	clearInputScripts(GS_Game);

	//Clear all object IDs
	clearObjects();

	//Destroy universe
	if(devices.universe) {
		devices.universe->destroyAll();
		devices.universe->drop();
		devices.universe = 0;
	}

	if(devices.physics) {
		devices.physics->drop();
		devices.physics = 0;
	}

	if(devices.nodePhysics) {
		devices.nodePhysics->drop();
		devices.nodePhysics = 0;
	}
	
	//Destroy scene
	extern void endAnimation();
	endAnimation();

	extern void clearProjectileBatches();
	clearProjectileBatches();

	devices.scene->destroyTree();

	scene::clearNodeEvents();

	//Delete existing empires
	Empire::clearEmpires();

	scripts::resetContextCache();
	delete devices.scripts.cache_server;
	delete devices.scripts.cache_shadow;
	delete devices.scripts.client;

	devices.scripts.cache_server = 0;
	devices.scripts.cache_shadow = 0;
	devices.scripts.client = 0;
	devices.scripts.server = 0;
	devices.engines.client = 0;
	devices.engines.server = 0;

	gameEnding = false;

	console.clearCommands();
	game_running = false;

	if(devices.network->isClient || devices.network->serverReady)
		devices.network->resetNetState();
}

void loadEngineSettings() {
	//Hardcoded engine settings go here
	{
		profile::SettingCategory* cat = new profile::SettingCategory("Graphics");
		cat->settings.push_back(new NamedGeneric("iSamples", 4));
		cat->settings.push_back(new NamedGeneric("bSupersample", false));
		cat->settings.push_back(new NamedGeneric("iRefreshRate", (int)0));
		cat->settings.push_back(new NamedGeneric("iResolutionX", 1280));
		cat->settings.push_back(new NamedGeneric("iResolutionY", 720));
		cat->settings.push_back(new NamedGeneric("iFsResolutionX", (int)0));
		cat->settings.push_back(new NamedGeneric("iFsResolutionY", (int)0));
		cat->settings.push_back(new NamedGeneric("bFullscreen", true));
		cat->settings.push_back(new NamedGeneric("bOverrideResolution", false));
		cat->settings.push_back(new NamedGeneric("iVsync", 1));
		cat->settings.push_back(new NamedGeneric("sMonitor", ""));
		cat->settings.push_back(new NamedGeneric("bShaderFallback", false));

		auto* guiScale = new NamedGeneric("dGUIScale", 1.0);
		guiScale->flt_min = 0.25;
		guiScale->flt_max = 4.0;
		cat->settings.push_back(guiScale);

		auto* fps = new NamedGeneric("dMaxFPS", 65.0);
		fps->flt_min = 24.0;
		fps->flt_max = 200.0;
		extern double* maxfps;
		maxfps = &fps->flt;
		cat->settings.push_back(fps);

		auto* tq = new NamedGeneric("iTextureQuality", 3);
		tq->num_min = 2;
		tq->num_max = 5;
		cat->settings.push_back(tq);

		auto* sl = new NamedGeneric("iShaderLevel", 3);
		sl->num_min = 1;
		sl->num_max = 4;
		cat->settings.push_back(sl);

		devices.settings.engine.addCategory(cat);
	}

	{
		profile::SettingCategory* cat = new profile::SettingCategory("Sound");
		cat->settings.push_back(new NamedGeneric("sAudioDevice", ""));
		devices.settings.engine.addCategory(cat);
	}

	{
		profile::SettingCategory* cat = new profile::SettingCategory("Input");
		cat->settings.push_back(new NamedGeneric("bCursorCapture", true));
		cat->settings.push_back(new NamedGeneric("bFsCursorCapture", true));
		cat->settings.push_back(new NamedGeneric("iDoubleClickMS", (int)devices.driver->getDoubleClickTime()));
		devices.settings.engine.addCategory(cat);
	}

	{
		profile::SettingCategory* cat = new profile::SettingCategory("General");
		cat->settings.push_back(new NamedGeneric("sLocale", "english"));
		cat->settings.push_back(new NamedGeneric("sAPIToken", ""));

		auto* autosave = new NamedGeneric("dAutosaveMinutes", 3.0);
		autosave->flt_min = 0.0;
		autosave->flt_max = 60.0;
		cat->settings.push_back(autosave);

		auto* count = new NamedGeneric("iAutosaveCount", (int)0);
		count->num_min = 1;
		count->num_max = 10;
		cat->settings.push_back(count);


		cat->settings.push_back(new NamedGeneric("iNetworkRateLimit", (int)250));
		devices.settings.engine.addCategory(cat);
	}

	//Save to profile
	std::string file = path_join(getProfileRoot(), "settings.txt");

	if(fileExists(file))
		devices.settings.engine.loadSettings(file);
	else
		devices.settings.engine.saveSettings(file);

	//Generate new tokens
	{
		auto* token = devices.settings.engine.getSetting("sAPIToken");
		if(token && (token->toString().empty() || token->toString() == "JGeaaKcaaa")) {
			std::string pass;
			do {
				pass.clear();
				uint64_t pw = (uint64_t)sysRandomi() << 32 | (uint64_t)sysRandomi();
				const char* base64 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-+=!~$%#&^*";

				for(unsigned i = 0; i < 10; ++i) {
					auto v = (pw % 64);
					pw >>= 6;
					pass.append(1, base64[v]);
				}
			} while(pass == "JGeaaKcaaa");

			token->setString(pass);
			devices.settings.engine.saveSettings(file);
		}
	}
}
