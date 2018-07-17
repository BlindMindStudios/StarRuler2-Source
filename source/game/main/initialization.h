#pragma once
#include <string>
#include <functional>
#include <vector>
#include <unordered_map>

//Initialized global data, should be done once per startup
bool initGlobal(bool loadGraphics = true, bool createWindow = true);
void destroyGlobal();

//Creates any thread local variables,
//should be called after initializing global
void initNewThread();
//Frees thread local variables
void cleanupThread();
//Add a cleanup stage to the current thread
void addThreadCleanup(std::function<void()> func);

//Switches over to a different mod
void initMods(const std::vector<std::string>& mods);
void destroyMod();
bool isPreloading();
void finishPreload();
void cancelLoad();

//Switches over to a different locale
void switchLocale(const std::string& locale);

//Initialize game state variables
extern bool game_running;
extern bool load_resources;
extern bool watch_resources;
extern bool use_sound;
extern bool use_steam;
extern bool monitor_files;
extern bool fullscreen;
extern bool useJIT;
extern std::string loadSaveName;
void initGame();
void destroyGame();

namespace net {
	struct Message;
};
void setGameSettings(net::Message& msg);
void clearGameSettings();

struct GameConfig {
	size_t count;
	std::string* names;
	double* values;
	double* defaultValues;
	std::unordered_map<std::string, size_t> indices;

	GameConfig() : count(0), names(nullptr), values(nullptr) {
	}
};
extern GameConfig gameConfig;
void readGameConfig(net::Message& msg);
void writeGameConfig(net::Message& msg);

class SaveFile;
void saveGameConfig(SaveFile& file);
void loadGameConfig(SaveFile& file);

bool hasDLC(const std::string& name);
