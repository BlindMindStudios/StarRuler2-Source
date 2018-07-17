#include "binds.h"
#include "main/references.h"
#include "main/initialization.h"
#include "main/tick.h"
#include "network/network_manager.h"
#include "processing.h"
#include "main/save_load.h"
#include "main/logging.h"
#include "util/save_file.h"
#include "files.h"
#include "../../as_addons/include/scriptarray.h"

extern bool watch_resources;
bool queuedModSwitch = false;
std::vector<std::string> modSetup;

void startNewGame(net::Message& msg) {
	if(game_running)
		destroyGame();
	setGameSettings(msg);
	game_state = GS_Game;
}

void startNewGame() {
	if(game_running)
		destroyGame();
	clearGameSettings();
	game_state = GS_Game;
}

void stopGame() {
	if(!game_running)
		return;
	destroyGame();
	clearGameSettings();
	game_state = GS_Menu;
}

namespace scripts {

static void switchToMods(CScriptArray* arr) {
	if(!arr)
		return;
	if(game_running)
		stopGame();
	modSetup.clear();
	for(unsigned i = 0, cnt = arr->GetSize(); i < cnt; ++i)
		modSetup.push_back(*(std::string*)arr->At(i));
	queuedModSwitch = true;
	devices.network->disconnect();
}

static void quickstartGame() {
	if(game_running)
		destroyGame();
	clearGameSettings();
	game_state = GS_Game;
}

static void toMenu() {
	game_state = GS_Menu;
}

static void toGame() {
	game_state = GS_Game;
}

static void quitGame() {
	game_state = GS_Quit;
}

static void preRenderClient() {
	if(devices.scripts.client && game_running)
		devices.scripts.client->preRender(realFrameLen);
}

static void renderClient() {
	if(devices.scripts.client && game_running)
		devices.scripts.client->render(realFrameLen);
}

bool scr_saveGame(const std::string& fname) {
	if(!game_running) {
		scripts::throwException("No game to save.");
		return false;
	}
	if(devices.network->isClient) {
		scripts::throwException("Cannot save game from multiplayer clients.");
		return false;
	}
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return false;
	}

	processing::pause();
	bool success = saveGame(fname);
	processing::resume();
	return success;
}

void scr_loadGame(const std::string& fname) {
	loadSaveName = fname;
	game_state = GS_Load_Prep;
}

struct ThreadedImageData {
	Image img;
	std::string filename;

	ThreadedImageData(const std::string& fname) : filename(fname) {}
};

static threads::threadreturn threadcall SaveImage(void* arg) {
	ThreadedImageData& data = *(ThreadedImageData*)arg;

	try {
		if(!saveImage(&data.img, data.filename.c_str(), true))
			throw 0;
	}
	catch(...) {
		error("Could not write image");
	}

	delete &data;
	return 0;
}

static void saveWorldScreen(const std::string& fname) {
	auto* data = new ThreadedImageData(fname);
	getFrameRender(data->img);
	threads::createThread(SaveImage, data);
}

static unsigned saveVersion(const std::string& fname) {
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return (unsigned)-1;
	}
	SaveFileInfo info;
	getSaveFileInfo(fname, info);
	return info.version;
}

static bool saveInfo(const std::string& fname, SaveFileInfo& info) {
	if(!isAccessible(fname)) {
		scripts::throwException("Cannot access file outside game or profile directories.");
		return (unsigned)-1;
	}
	return getSaveFileInfo(fname, info);
}

static void makeSaveFileInfo(SaveFileInfo* dat) {
	new(dat) SaveFileInfo();
}

static void dtorSaveFileInfo(SaveFileInfo* dat) {
	dat->~SaveFileInfo();
}

static void copySaveFileInfo(SaveFileInfo* into, SaveFileInfo* from) {
	new(into) SaveFileInfo();
	*into = *from;
}

static mods::Mod* getTopMod() {
	if(devices.mods.activeMods.empty())
		return nullptr;
	return devices.mods.activeMods[devices.mods.activeMods.size()-1];
}

static const mods::Mod* getMod(unsigned index) {
	if(index < devices.mods.mods.size())
		return devices.mods.mods[index];
	else
		return nullptr;
}

static const mods::Mod* getMod_id(const std::string& name) {
	return devices.mods.getMod(name);
}

static unsigned getModCount() {
	return devices.mods.mods.size();
}

static void saveModState() {
	devices.mods.saveState();
}

static bool createNewMod(const std::string& ident) {
	if(!isIdentifier(ident, " ") || ident.empty())
		return false;
	std::string dirname = path_join("mods", ident);
	std::string infoPath = path_join(dirname, "modinfo.txt");

	makeDirectory(dirname);
	std::ofstream file(infoPath);
	file << "Name: " << ident << "\n";
	file << "Compatibility: 200\n";
	file.close();

	devices.mods.registerMod(dirname, ident); //Nothing could possibly go wrong here
	return true;
}

void modConflicts(mods::Mod* mine, mods::Mod* other, CScriptArray* arr) {
	std::vector<std::string> conflicts;
	mine->getConflicts(other, conflicts);

	unsigned index = arr->GetSize();
	arr->Resize(index + conflicts.size());
	foreach(it, conflicts)
		*(std::string*)arr->At(index++) = *it;
}

static bool saveFileHasMods(SaveFileInfo* info) {
	for(size_t i = 0, cnt = info->mods.size(); i < cnt; ++i) {
		auto* mod = devices.mods.getMod(info->mods[i].id);
		if(mod)
			mod = mod->getFallback(info->mods[i].version);
		if(mod == nullptr)
			return false;
	}
	return true;
}

void RegisterMenuBinds(bool ingame) {
	//Start a game
	bind("void startNewGame(Message&)", asFUNCTIONPR(startNewGame, (net::Message&), void));
	bind("void startNewGame()", asFUNCTION(quickstartGame));
	bind("void stopGame()", asFUNCTION(stopGame));
	bind("void loadGame(const string& fname)", asFUNCTION(scr_loadGame));
	bind("bool saveGame(const string& fname)", asFUNCTION(scr_saveGame));
	bind("void saveWorldScreen(const string& fname)", asFUNCTION(saveWorldScreen));
	bind("void switchToMenu()", asFUNCTION(toMenu));
	bind("void switchToGame()", asFUNCTION(toGame));
	bind("void quitGame()", asFUNCTION(quitGame));

	ClassBind saveData("SaveFileInfo", asOBJ_VALUE | asOBJ_APP_CLASS_CDK, sizeof(SaveFileInfo));
	saveData.addConstructor("void f()", asFUNCTION(makeSaveFileInfo));
	saveData.addDestructor("void f()", asFUNCTION(dtorSaveFileInfo));
	saveData.addConstructor("void f(const SaveFileInfo& other)", asFUNCTION(copySaveFileInfo));
	saveData.addExternMethod("bool hasMods()", asFUNCTION(saveFileHasMods));
	saveData.addMember("uint version", offsetof(SaveFileInfo, version));
	saveData.addMember("uint startVersion", offsetof(SaveFileInfo, startVersion));
	bind("void getSaveFileInfo(const string& fname, SaveFileInfo& dat)", asFUNCTION(saveInfo));
	bind("uint getSaveVersion(const string& fname)", asFUNCTION(saveVersion));

	EnumBind gs("GameState");
	gs["GS_Game"] = GS_Game;
	gs["GS_Menu"] = GS_Menu;
	gs["GS_Quit"] = GS_Quit;

	bindGlobal("GameState game_state", &game_state);

	//Menu rendering
	bind("void preRenderClient()", asFUNCTION(preRenderClient));
	bind("void renderClient()", asFUNCTION(renderClient));

	//Mod listing
	ClassBind mod("Mod", asOBJ_REF | asOBJ_NOCOUNT, 0);
	mod.addMember("string ident", offsetof(mods::Mod, ident));
	mod.addMember("string name", offsetof(mods::Mod, name));
	mod.addMember("string dirname", offsetof(mods::Mod, dirname));
	mod.addMember("string abspath", offsetof(mods::Mod, abspath));
	mod.addMember("string parentname", offsetof(mods::Mod, parentname));
	mod.addMember("string description", offsetof(mods::Mod, description));
	mod.addMember("bool listed", offsetof(mods::Mod, listed));
	mod.addMember("bool enabled", offsetof(mods::Mod, enabled));
	mod.addMember("bool isNew", offsetof(mods::Mod, isNew));
	mod.addMember("bool forced", offsetof(mods::Mod, forced));
	mod.addMember("bool isBase", offsetof(mods::Mod, isBase));
	mod.addMember("uint compatibility", offsetof(mods::Mod, compatibility));
	mod.addMember("bool forCurrentVersion", offsetof(mods::Mod, forCurrentVersion));
	mod.addMember("Mod@ parent", offsetof(mods::Mod, parent));
	mod.addMethod("bool isCompatible(Mod& other)", asMETHOD(mods::Mod, isCompatible));
	mod.addExternMethod("void getConflicts(Mod& other, array<string>& files)", asFUNCTION(modConflicts));

	bindGlobal("bool watchResources", &watch_resources);

	bindGlobal("Mod@ currentMod", &devices.mods.currentMod);
	bindGlobal("Mod@ baseMod", &devices.mods.currentMod);
	bind("Mod& get_topMod()", asFUNCTION(getTopMod));
	bind("Mod@ getMod(uint index)", asFUNCTION(getMod));
	bind("Mod@ getMod(const string& id)", asFUNCTION(getMod_id));
	bind("uint get_modCount()", asFUNCTION(getModCount));
	bind("void saveModState()", asFUNCTION(saveModState));

	bind("bool createNewMod(const string& ident)", asFUNCTION(createNewMod));
	bind("void switchToMods(const array<string>& mods)", asFUNCTION(switchToMods));
}

};
