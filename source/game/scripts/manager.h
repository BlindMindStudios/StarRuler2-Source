#pragma once
#include "angelscript.h"
#include "threads.h"
#include <string>
#include <vector>
#include <stack>
#include <map>
#include <set>

//#define PROFILE_SCRIPT_CALLBACKS
//#define TRACE_GC_LOCK

class SaveFile;
class asCObjectType;
class asCScriptFunction;
class asCGlobalProperty;

namespace scripts {

enum EngineDataIDs {
	EDID_Manager,
	EDID_SerializableType,
	EDID_SerializableWrite,
	EDID_SerializableRead,
	EDID_objectArray,
	EDID_playerArray,
	EDID_nodeArray,
	EDID_stringArray,
	EDID_consoleCommand,
	EDID_SavableType,
	EDID_SavableWrite,
	EDID_SavableRead,
};

enum ScriptCallback {
	SC_preInit,
	SC_init,
	SC_postInit,
	SC_tick,
	SC_deinit,
	SC_preRender,
	SC_render,
	SC_draw,
	SC_settings_changed,
	SC_game_settings,
	SC_sync_initial,
	SC_sync_periodic,
	SC_recv_periodic,
	SC_save,
	SC_load,
	SC_saveIdentifiers,
	SC_stateChange,
	SC_preReload,
	SC_postReload,

	SC_COUNT
};

class Manager;
struct Call {
	Manager* manager;
	asIScriptContext* ctx;
	asUINT arg;
	bool nested;
	int status;

	Call();
	Call(Manager* man, asIScriptContext* Ctx, bool nested = false);
	~Call();

	inline bool valid() { return ctx != 0; }

	void setObject(void* obj);
	void* getReturnObject();

	void push(int value);
	void push(unsigned value);
	void push(long long value);
	void push(float value);
	void push(double value);
	void push(bool value);

	bool call();
	bool call(int& value);
	bool call(unsigned& value);
	bool call(float& value);
	bool call(double& value);
	bool call(bool& value);
	bool call(long long& value);

	template<class T>
	void push(T* value) {
		if(ctx)
			ctx->SetArgAddress(arg++, (void*)value);
	}

	template<class T>
	void pushObj(T* value) {
		if(ctx)
			ctx->SetArgObject(arg++, (void*)value);
	}

	template<class T>
	bool call(T*& value) {
		if (!call()) {
			value = 0;
			return false;
		}

		value = (T*)ctx->GetReturnAddress();
		return true;
	}

	template<class T>
	bool callObjRet(T*& value) {
		if (!call()) {
			value = 0;
			return false;
		}

		value = (T*)ctx->GetReturnObject();
		return true;
	}
};

struct MultiCall {
	std::vector<Call> calls;

	MultiCall();

	void setObject(void* obj);

	void push(int value);
	void push(float value);
	void push(double value);
	void push(bool value);
	void push(void* value);

	void call();
};

typedef std::pair<std::string,std::string> ImportSpec;

struct File {
	std::string module, path, contents;
	std::map<std::string, File*> includes;
	std::set<ImportSpec> imports;
	std::set<std::string> exports;
	std::set<std::string> exportsFrom;
	int priority_init, priority_render;
	int priority_draw, priority_tick;
	int priority_sync;

	File() : priority_init(0), priority_render(0),
		priority_draw(0), priority_tick(0), priority_sync(0) {}
};

struct Module {
	std::string name;
	std::string compiledBy;
	File* file;
	Manager* manager;
	asIScriptModule* module;
	asIScriptFunction* callbacks[SC_COUNT];
	unsigned tickFails;
	unsigned drawFails;
	unsigned renderFails;
	bool compiled;
	bool compiling;
	std::set<ImportSpec> imports;
	std::set<Module*> dependencies;
	std::set<std::string> exports;
	std::set<std::string> exportsFrom;
	std::vector<asITypeInfo*> typeExports;
	std::vector<asCScriptFunction*> funcExports;
	std::vector<unsigned> globalExports;

#ifdef PROFILE_SCRIPT_CALLBACKS
	double tickTime;
	double drawTime;
	double renderTime;
	Module() : tickFails(0), drawFails(0), renderFails(0),
		tickTime(0), drawTime(0), renderTime(0), compiled(false), compiling(false) {}
#else
	Module() : tickFails(0), drawFails(0), renderFails(0), compiled(false), compiling(false) {}
#endif

	Call call(ScriptCallback cb);
	asIScriptFunction* getFunction(const char* decl);
	asITypeInfo* getClass(const char* decl);
};

class Manager {
public:
	threads::ReadWriteMutex threadedCallMutex;
	asIScriptEngine* engine;
	std::map<std::string, Module*> modules;
	std::map<std::string, File*> files;

	threads::atomic_int scriptThreadsActive;
	threads::atomic_int scriptThreadsExistent;
	volatile bool pauseScripts;
	volatile bool clearScripts;

	asUINT prevGCSize;

	std::multimap<int, Module*> priority_init;
	std::multimap<int, Module*> priority_render;
	std::multimap<int, Module*> priority_draw;
	std::multimap<int, Module*> priority_tick;
	std::multimap<int, Module*> priority_sync;

	Manager(asIJITCompiler* jit = 0);
	~Manager();

	Module* getModule(const char* module);
	asIScriptFunction* getFunction(int fid);
	asIScriptFunction* getFunction(const char* module, const char* decl);
	asIScriptFunction* getFunction(const std::string& def, const char* args, const char* ret);
	asITypeInfo* getClass(const char* module, const char* decl);

	std::vector<std::string> includePaths;
	void addIncludePath(std::string path);

	void loadDirectory(const std::string& dirname);
	void load(const std::string& modulename, const std::string& filename);
	
	Call call(int funcID);
	Call call(asIScriptFunction* func);
	Call call(const char* module, const char* decle);
	MultiCall call(ScriptCallback cb);

	void compile(const std::string& cache_root = "", unsigned cache_version = 0);
	void reload(const std::string& module);
	
	void init();
	void deinit();
	void tick(double time);
	void draw();
	void preRender(double frameTime);
	void render(double frameTime);
	void save(SaveFile& file);
	void load(SaveFile& file);
	void saveIdentifiers(SaveFile& file);
	void stateChange();

	void pauseScriptThreads();
	void resumeScriptThreads();

	bool scriptThreadStart();
	void scriptThreadEnd();

	void clearScriptThreads();
	void scriptThreadCreate();
	void scriptThreadDestroy();

#ifdef PROFILE_SCRIPT_CALLBACKS
	void printProfile();
#endif

#ifdef TRACE_GC_LOCK
	threads::threadlocalPointer<bool> gcPossible;
	void markGCImpossible();
	void markGCPossible();
#endif

	void clear();

	int garbageCollect(bool full = false);

	static Manager& fromEngine(asIScriptEngine* engine);
};

Manager* getActiveManager();
void throwException(const char* msg);

void clearCachedScripts();
void preloadScript(const std::string& filename);

};
