
#include "main/references.h"
#include "main/input_handling.h"
#include "main/logging.h"
#include "main/tick.h"
#include "main/console.h"
#include "scripts/manager.h"
#include "scripts/binds.h"
#include "scripts/context_cache.h"
#include "str_util.h"
#include "files.h"
#include "threads.h"
#include "angelscript.h"
#include "scriptarray.h"
#include "scriptstdstring.h"
#include "scriptmath.h"
#include "scriptdictionary.h"
#include "scriptmap.h"
#include "scriptany.h"
#include "scripthandle.h"
#include "compat/misc.h"
#include "compat/regex.h"
#include "util/save_file.h"
#include <stack>
#include <string>
#include <iostream>
#include <fstream>
#include <queue>
#include <algorithm>
#include <set>
#include "../angelscript/source/as_module.h"
#include "../angelscript/source/as_objecttype.h"

//Fix angelscript including windows.h in an ugly way
#ifdef _MSC_VER
#undef max
#endif

#ifdef _DEBUG

#ifndef SCRIPT_MAX_TICK_FAILS
#define SCRIPT_MAX_TICK_FAILS 1
#endif

#ifndef SCRIPT_MAX_DRAW_FAILS
#define SCRIPT_MAX_DRAW_FAILS 1
#endif

#ifndef SCRIPT_MAX_RENDER_FAILS
#define SCRIPT_MAX_RENDER_FAILS 1
#endif

#else

#ifndef SCRIPT_MAX_TICK_FAILS
#define SCRIPT_MAX_TICK_FAILS 16
#endif

#ifndef SCRIPT_MAX_DRAW_FAILS
#define SCRIPT_MAX_DRAW_FAILS 16
#endif

#ifndef SCRIPT_MAX_RENDER_FAILS
#define SCRIPT_MAX_RENDER_FAILS 16
#endif

#endif

#define DISABLE_SCRIPT_CACHE

namespace scripts {
extern void RegisterEarlyNetworkBinds(asIScriptEngine* engine);

Threaded(asIScriptContext*) clientContext = 0;

threads::Mutex sectionLock;
std::string lastSection;

#ifndef DISABLE_SCRIPT_CACHE
static bool loadCached(Module& mod, const File& fl, const std::string& cache_file, unsigned cache_version);
static void saveCached(Module& mod, const std::string& cache_file, unsigned cache_version);
#endif

void printErrors(asSMessageInfo* msg, void* ptr) {
	if(msg->section) {
		threads::Lock lock(sectionLock);
		if(lastSection != msg->section) {
			lastSection = msg->section;
			error("%s:", msg->section);
		}
	}

	if(msg->type == asMSGTYPE_INFORMATION) {
		error(" %s", msg->message);
	}
	else {
		const char* type;
		if(msg->type == asMSGTYPE_ERROR)
			type = "Error";
		else// if(msg->type == asMSGTYPE_WARNING)
			type = "Warning";
		
		if(msg->col || msg->row)
			error("  %s (%d:%d): %s", type, msg->row, msg->col, msg->message);
		else
			error("  %s: %s", type, msg->message);
	}
}

enum ManagerType {
	MT_Server,
	MT_Shadow,
	MT_Menu,
	MT_GUI,
	MT_Server_Side,
	MT_Client_Side,
	MT_Game,
};

const char* manager_names[MT_Game] = {
	"server",
	"shadow",
	"menu",
	"gui",
};

Manager* getActiveManager() {
	auto* ctx = asGetActiveContext();
	if(!ctx)
		return 0;
	return &Manager::fromEngine(ctx->GetEngine());
}

ManagerType getManagerType(Manager* man) {
	if(man == devices.scripts.cache_server)
		return MT_Server;
	if(man == devices.scripts.cache_shadow)
		return MT_Shadow;
	if(man == devices.scripts.menu)
		return MT_Menu;
	return MT_GUI;
}

void throwException(const char* msg) {
	asGetActiveContext()->SetException(msg);
}

const char* callback_decl[SC_COUNT] = {
	"void preInit()",
	"void init()",
	"void postInit()",
	"void tick(double)",
	"void deinit()",
	"void preRender(double)",
	"void render(double)",
	"void draw()",
	"void onSettingsChanged()",
	"void onGameSettings(Message&)",
	"void syncInitial(Message&)",
	"bool sendPeriodic(Message&)",
	"void recvPeriodic(Message&)",
	"void save(SaveFile&)",
	"void load(SaveFile&)",
	"void saveIdentifiers(SaveFile&)",
	"void onGameStateChange()",
	"void preReload(Message&)",
	"void postReload(Message&)",
};

asIScriptFunction* Module::getFunction(const char* decl) {
	return module->GetFunctionByDecl(decl);
}

Module* Manager::getModule(const char* module) {
	auto it = modules.find(module);
	if(it != modules.end())
		return it->second;
	return 0;
}

asIScriptFunction* Manager::getFunction(int fid) {
	return engine->GetFunctionById(fid);
}

asIScriptFunction* Manager::getFunction(const char* module, const char* decl) {
	auto it = modules.find(module);
	if(it != modules.end())
		return it->second->getFunction(decl);
	return 0;
}

asIScriptFunction* Manager::getFunction(const std::string& def, const char* fin, const char* ret) {
	std::vector<std::string> args;
	split(def, args, "::");
	
	//Find the module the function is in
	scripts::Module* module = nullptr;
	if(args.size() == 1) {
		auto* ctx = asGetActiveContext();
		if(ctx) {
			auto* func = ctx->GetFunction();
			module = getModule(func->GetModuleName());
		}

		if(!module) {
			error("Error: Invalid script module.");
			return 0;
		}
	}
	else if(args.size() == 2) {
		module = getModule(args[0].c_str());

		if(!module) {
			error("Error: Invalid script module '%s'.", args[0].c_str());
			return 0;
		}
	}
	else {
		error("Error: Invalid script function reference '%s'.", def.c_str());
		return 0;
	}

	//Build declaration for function
	std::string decl = std::string(ret)+" "+args[args.size() - 1]+fin;

	//Find the function
	asIScriptFunction* func = module->getFunction(decl.c_str());
	if(!func) {
		error("Error: Unknown script function '%s'.", decl.c_str());
		return 0;
	}

	return func;
}

asITypeInfo* Module::getClass(const char* decl) {
	int id = module->GetTypeIdByDecl(decl);
	return manager->engine->GetTypeInfoById(id);
}

asITypeInfo* Manager::getClass(const char* module, const char* decl) {
	auto it = modules.find(module);
	if(it != modules.end())
		return it->second->getClass(decl);
	return 0;
}

Manager::Manager(asIJITCompiler* Jit) : prevGCSize(5000), pauseScripts(false), clearScripts(false) {
	//Create the engine
	engine = asCreateScriptEngine(ANGELSCRIPT_VERSION);

	if(Jit) {
		engine->SetEngineProperty(asEP_INCLUDE_JIT_INSTRUCTIONS, 1);
		engine->SetJITCompiler(Jit);
	}

	engine->SetEngineProperty(asEP_ALLOW_UNSAFE_REFERENCES, 1);
	engine->SetEngineProperty(asEP_USE_CHARACTER_LITERALS, 1);
	engine->SetEngineProperty(asEP_ALLOW_MULTILINE_STRINGS, 1);
	engine->SetEngineProperty(asEP_SCRIPT_SCANNER, 1);

#ifndef DO_LINE_CALLBACK
	engine->SetEngineProperty(asEP_BUILD_WITHOUT_LINE_CUES, 1);
#endif
	engine->SetEngineProperty(asEP_OPTIMIZE_BYTECODE, 1);

	engine->SetEngineProperty(asEP_AUTO_GARBAGE_COLLECT, 0);
	engine->SetEngineProperty(asEP_ALTER_SYNTAX_NAMED_ARGS, 1);

	engine->SetMessageCallback(asFUNCTION(printErrors), 0, asCALL_CDECL);

	engine->SetUserData(this, EDID_Manager);

	//Bind all addon types
	RegisterScriptAny(engine);
	RegisterScriptHandle(engine);
	RegisterScriptArray(engine, true);

	//HACK: Has to be here so stdstring doesn't instantiate array<string> yet
	scripts::RegisterEarlyNetworkBinds(engine);

	RegisterStdString(engine);
	RegisterStdStringUtils(engine);
	RegisterScriptDictionary(engine);
	RegisterScriptMap(engine);
	RegisterScriptMath(engine);
}

Manager& Manager::fromEngine(asIScriptEngine* engine) {
	return *(Manager*)engine->GetUserData(EDID_Manager);
}

void Manager::addIncludePath(std::string path) {
	includePaths.push_back(path);
}

void Manager::loadDirectory(const std::string& dirname) {
	std::vector<std::string> list;
	listDirectory(dirname, list, "*.as");

	foreach(it, list) {
		std::string& file = *it;
		load(file.substr(0, file.size() - 3), path_join(dirname, file));
	}
}

class CachedScript {
	bool loaded;
	threads::Mutex lock;
	std::string path;
	std::vector<std::string> lines;
public:
	size_t size;

	CachedScript(const std::string& filename) : loaded(false), path(filename), size(0) {
	}

	const std::vector<std::string>& get() {
		threads::Lock l(lock);
		if(!loaded) {
			std::ifstream file(path.c_str(), std::ios_base::in);
			skipBOM(file);

			std::string line;
			while(file.good()) {
				std::getline(file, line);
				size += line.size() + 1;
				lines.push_back(line);
			}

			loaded = true;
		}
		return lines;
	}
};

threads::Mutex loadedScriptsLock;
std::unordered_map<std::string, CachedScript*> cachedScripts;

const std::vector<std::string>& loadScript(const std::string& filename, size_t& size) {
	auto path = getAbsolutePath(filename);
	CachedScript* script = nullptr;
	{
		threads::Lock l(loadedScriptsLock);
		auto i = cachedScripts.find(path);
		if(i != cachedScripts.end()) {
			script = i->second;
		}
		else {
			script = new CachedScript(path);
			cachedScripts[path] = script;
		}
	}
	assert(script);
	size = script->size;
	return script->get();
}

void clearCachedScripts() {
	threads::Lock l(loadedScriptsLock);
	for(auto i = cachedScripts.begin(), end = cachedScripts.end(); i != end; ++i)
		delete i->second;
	cachedScripts.clear();
}

void preloadScript(const std::string& filename) {
	size_t dummy;
	loadScript(filename, dummy);
}

threads::Mutex reg_compile_lock;

void parseFile(Manager* man, File& fl, const std::string& filename, bool cacheFiles = true) {
	std::string path = getAbsolutePath(filename);
	size_t size;
	auto& lines = loadScript(path, size);

	fl.path = path;

	std::string& output = fl.contents;
	output.reserve(size);

	ManagerType curType = getManagerType(man);
	ManagerType selType = curType;

	reg_compile_lock.lock();
	reg_compile(pre_include, "^[ \t]*#include[ \t]+\"(.+)\"[ \t]*");
	reg_compile(pre_priority, "^[ \t]*#priority[ \t]+(.+)[ \t]+(.+)[ \t]*");
	reg_compile(pre_section, "^[ \t]*#section[ \\t]+(.+)[ \t]*");
	reg_compile(pre_import_from, "^[ \t]*from[ \t]+([A-Za-z0-9._-]+)[ \t]+import[ \t]+([^;]+);");
	reg_compile(pre_import_all, "^[ \t]*import[ \t]+(([A-Za-z0-9._-]|, )+);");
	reg_compile(pre_export, "^[ \t]*export[ \t]+(([A-Za-z0-9._-]|,* )+);");
	reg_compile_lock.release();
	reg_result match;


	for(auto iLine = lines.begin(), end = lines.end(); iLine != end; ++iLine) {
		const std::string& line = *iLine;

		auto lineStart = line.find_first_not_of(" \t");
		if(lineStart == std::string::npos) {
			output.append(1, '\n');
			continue;
		}

		bool mayBeDirective = line[lineStart] == '#';

		if(mayBeDirective && reg_match(line, match, pre_section)) {
			std::string type = trim(reg_str(line, match, 1));
			if(type == "server")
				selType = MT_Server;
			else if(type == "server-side")
				selType = MT_Server_Side;
			else if(type == "client-side")
				selType = MT_Client_Side;
			else if(type == "client")
				selType = MT_Client_Side;
			else if(type == "shadow")
				selType = MT_Shadow;
			else if(type == "gui")
				selType = MT_GUI;
			else if(type == "game")
				selType = MT_Game;
			else if(type == "menu")
				selType = MT_Menu;
			else if(type == "all")
				selType = curType;
			else if(type == "disable menu") {
				if(curType == MT_Menu)
					break;
			}
			else
				selType = MT_Client_Side;

			output += "\n";
			continue;
		}
		else {
			switch(selType) {
				case MT_Server:
				case MT_Shadow:
				case MT_GUI:
				case MT_Menu:
					if(selType != curType) {
						output += "\n";
						continue;
					}
				break;
				case MT_Game:
					if(curType != MT_GUI && curType != MT_Server && curType != MT_Shadow) {
						output += "\n";
						continue;
					}
				break;
				case MT_Client_Side:
					if(curType != MT_Menu && curType != MT_GUI) {
						output += "\n";
						continue;
					}
				break;
				case MT_Server_Side:
					if(curType != MT_Shadow && curType != MT_Server) {
						output += "\n";
						continue;
					}
				break;
			}
		}

		if(line[lineStart] == 'f' && reg_match(line, match, pre_import_from)) {
			std::string mod = reg_str(line, match, 1);
			std::string def = reg_str(line, match, 2);

			fl.imports.insert(ImportSpec(mod, def));
			output += "\n";
			continue;
		}

		if(line[lineStart] == 'i' && reg_match(line, match, pre_import_all)) {
			std::string mod = reg_str(line, match, 1);

			if(mod.find(",") != std::string::npos) {
				std::vector<std::string> modules;
				split(mod, modules, ",", true);

				foreach(m, modules)
					fl.imports.insert(ImportSpec(*m, "*"));
			}
			else {
				fl.imports.insert(ImportSpec(mod, "*"));
			}

			output += "\n";
			continue;
		}

		if(line[lineStart] == 'e' && reg_match(line, match, pre_export)) {
			std::string sym = reg_str(line, match, 1);
			auto* lst = &fl.exports;

			if(sym.compare(0, 5, "from ") == 0) {
				sym = sym.substr(5);
				lst = &fl.exportsFrom;
			}

			if(sym.find(",") != std::string::npos) {
				std::vector<std::string> symbols;
				split(sym, symbols, ",", true);

				foreach(s, symbols)
					lst->insert(*s);
			}
			else {
				lst->insert(sym);
			}

			output += "\n";
			continue;
		}

		if(mayBeDirective && reg_match(line, match, pre_priority)) {
			std::string type = reg_str(line, match, 1);
			std::string prior = reg_str(line, match, 2);
			int priority = toNumber<int>(prior);

			if(type == "init") {
				fl.priority_init = priority;
			}
			else if(type == "render") {
				fl.priority_render = priority;
			}
			else if(type == "draw") {
				fl.priority_draw = priority;
			}
			else if(type == "sync") {
				fl.priority_sync = priority;
			}
			else {
				error("ERROR: In File %s:\n  Invalid priority directive '%s'.",
					filename.c_str(), type.c_str());
			}

			output += "\n";
		}
		else if(mayBeDirective && reg_match(line, match, pre_include)) {
			std::string filePart = reg_str(line, match, 1);

			//Check include relative to current file first
			std::string includeFile = getAbsolutePath(devices.mods.resolve(
				filePart, getDirname(filename)));

			//Load the included file contents
			if(!fileExists(includeFile)) {
				//Then check include paths
				bool exists = false;
				foreach(it, man->includePaths) {
					includeFile = getAbsolutePath(devices.mods.resolve(
						filePart, *it));

					if(fileExists(includeFile)) {
						exists = true;
						break;
					}
				}

				if(!exists) {
					error("ERROR: In File %s:\n  Could not find file '%s' to include.",
						filename.c_str(), filePart.c_str());

					foreach(it, man->includePaths) {
						includeFile = getAbsolutePath(devices.mods.resolve(
							filePart, *it));
						error("  Tried %s", includeFile.c_str());
					}
					output += "\n";
					continue;
				}
			}

			//Don't include the same file multiple times
			if(fl.includes.find(includeFile) != fl.includes.end()) {
				output += "\n";
				continue;
			}

			if(!cacheFiles) {
				std::string path = getAbsolutePath(includeFile);
				File& incl = *new File();
				parseFile(man, incl, includeFile, false);

				fl.includes[path] = &incl;
			}
			else {
				man->load("", includeFile);

				//Update and flatten include file tree
				auto it = man->files.find(includeFile);
				if(it != man->files.end()) {
					fl.includes[it->first] = it->second;

					foreach(inc, it->second->includes)
						fl.includes[inc->first] = inc->second;
				}
			}
			
			output.append(1,'\n');
		}
		else {
			output += line;
			output.append(1,'\n');
		}
	}
}

void Manager::load(const std::string& modulename, const std::string& filename) {
	std::string path = getAbsolutePath(filename);

	auto ex = files.find(path);
	if(ex != files.end()) {
		//If a file was included before, give it its
		//proper module name afterwards
		if(ex->second->module.empty())
			ex->second->module = modulename;
		return;
	}
	
	File& fl = *new File();
	fl.module = modulename;
	parseFile(this, fl, filename, true);

	files[path] = &fl;
}

void importSymbol(Module& mod, Module& otherMod, const std::string& symbol) {
	auto* self = (asCModule*)mod.module;
	auto* other = (asCModule*)otherMod.module;

	//Check if it's a type
	auto* type = other->GetType(symbol.c_str(), other->defaultNamespace);
	if(type) {
		self->ImportType(type);
		return;
	}

	//Check if it's a global
	int glob = other->GetGlobalVarIndexByName(symbol.c_str());
	if(glob != asNO_GLOBAL_VAR) {
		self->ImportGlobalVariable(other, (asUINT)glob);
		return;
	}

	glob = other->importedGlobals.GetFirstIndex(self->defaultNamespace, symbol.c_str());
	if(glob != -1) {
		mod.globalExports.push_back(other->scriptGlobals.GetSize() + (unsigned)glob);
		return;
	}

	//Check if it's a function
	bool foundFunction = false;
	{
		const asCArray<unsigned int>& idxs = other->globalFunctions.GetIndexes(other->defaultNamespace, symbol.c_str());
		for(unsigned i = 0; i < idxs.GetLength(); ++i) {
			asCScriptFunction* func = other->globalFunctions.Get(idxs[i]);
			if(func) {
				self->ImportGlobalFunction(func);
				foundFunction = true;
			}
		}
	}
	{
		const asCArray<unsigned int>& idxs = other->importedGlobalFunctions.GetIndexes(other->defaultNamespace, symbol.c_str());
		for(unsigned i = 0; i < idxs.GetLength(); ++i) {
			asCScriptFunction* func = other->importedGlobalFunctions.Get(idxs[i]);
			if(func) {
				self->ImportGlobalFunction(func);
				foundFunction = true;
			}
		}
	}

	if(!foundFunction) {
		//Check if it's a global accessor
		auto* getAcc = (asCScriptFunction*)other->GetFunctionByName((std::string("get_")+symbol).c_str());
		auto* setAcc = (asCScriptFunction*)other->GetFunctionByName((std::string("set_")+symbol).c_str());

		if(getAcc || setAcc) {
			if(getAcc)
				self->ImportGlobalFunction(getAcc);
			if(setAcc)
				self->ImportGlobalFunction(setAcc);
		}
		else {
			error("ERROR: %s: Cannot find '%s' to import from '%s'.",
					mod.name.c_str(), symbol.c_str(), otherMod.name.c_str());
		}
	}
}

void buildModule(Manager* man, File& fl, Module& mod) {
	//Create the module in the script engine
	mod.manager = man;
	mod.file = &fl;
	mod.module = man->engine->GetModule(mod.name.c_str(), asGM_ALWAYS_CREATE);

	//Add the script sections and imports
	mod.module->AddScriptSection(fl.path.c_str(),
		fl.contents.c_str(), fl.contents.size());
	mod.imports = fl.imports;
	mod.exports = fl.exports;
	mod.exportsFrom = fl.exportsFrom;

	foreach(inc, fl.includes) {
		mod.module->AddScriptSection(inc->second->path.c_str(),
			inc->second->contents.c_str(), inc->second->contents.size());

		foreach(s, inc->second->imports)
			mod.imports.insert(*s);
		foreach(s, inc->second->exports)
			mod.exports.insert(*s);
		foreach(s, inc->second->exportsFrom)
			mod.exportsFrom.insert(*s);

		fl.priority_init = std::max(fl.priority_init, inc->second->priority_init);
		fl.priority_render = std::max(fl.priority_render, inc->second->priority_render);
		fl.priority_draw = std::max(fl.priority_draw, inc->second->priority_draw);
		fl.priority_tick = std::max(fl.priority_init, inc->second->priority_tick);
		fl.priority_sync = std::max(fl.priority_init, inc->second->priority_sync);
	}
}

bool compileModule(Manager* man, Module& mod) {
	if(mod.compiled)
		return true;
	mod.compiled = true;
	mod.compiling = true;

	//Prepare all dependencies
	bool foundImports = true;
	foreach(it, mod.imports) {
		auto f = man->modules.find(it->first);
		if(f == man->modules.end()) {
			error("ERROR: %s: Cannot find module '%s' to import from.", mod.name.c_str(), it->first.c_str());
			continue;
		}

		Module& impMod = *f->second;
		mod.dependencies.insert(&impMod);

		//Build dependent module
		if(!impMod.compiled) {
			impMod.compiledBy = mod.name;
			compileModule(man, impMod);
		}
		if(impMod.module == nullptr) {
			//Silently fail here, we already reported errors before
			foundImports = false;
			continue;
		}

		//Inject imports
		auto* self = (asCModule*)mod.module;
		auto* other = (asCModule*)impMod.module;

		//Check cyclic imports
		if(impMod.compiling) {
			error("ERROR: %s: Cannot import from module '%s', circular import.", mod.name.c_str(), it->first.c_str());

			Module* cur = &mod;
			std::string prefix;
			while(cur) {
				error("%s^-- %s", prefix.c_str(), cur->name.c_str());
				prefix += "  ";

				if(!cur->compiledBy.empty()) {
					auto it = man->modules.find(cur->compiledBy);
					if(it != man->modules.end()) {
						cur = it->second;
					}
					else {
						cur = nullptr;
						error("??? %s\n", cur->compiledBy.c_str());
					}
				}
				else
					cur = nullptr;
			}
			continue;
		}

		if(it->second == "*") {
			//Check if the module defined any exports
			if(!impMod.exports.empty()) {
				foreach(tp, impMod.typeExports)
					self->ImportType(*tp);
				foreach(fun, impMod.funcExports)
					self->ImportGlobalFunction(*fun);
				foreach(var, impMod.globalExports)
					self->ImportGlobalVariable(impMod.module, *var);
			}
			else {
				//Import types
				for(unsigned i = 0, cnt = other->classTypes.GetLength(); i < cnt; ++i)
					self->ImportType(other->classTypes[i]);

				for(unsigned i = 0, cnt = other->enumTypes.GetLength(); i < cnt; ++i)
					self->ImportType(other->enumTypes[i]);

				for(unsigned i = 0, cnt = other->typeDefs.GetLength(); i < cnt; ++i)
					self->ImportType(other->typeDefs[i]);

				for(unsigned i = 0, cnt = other->funcDefs.GetLength(); i < cnt; ++i)
					self->ImportType(other->funcDefs[i]);

				//This is recursive: also import things that were imported
				for(unsigned i = 0, cnt = other->importedClassTypes.GetLength(); i < cnt; ++i)
					self->ImportType(other->importedClassTypes[i]);

				for(unsigned i = 0, cnt = other->importedEnumTypes.GetLength(); i < cnt; ++i)
					self->ImportType(other->importedEnumTypes[i]);

				for(unsigned i = 0, cnt = other->importedTypeDefs.GetLength(); i < cnt; ++i)
					self->ImportType(other->importedTypeDefs[i]);

				for(unsigned i = 0, cnt = other->importedFuncDefs.GetLength(); i < cnt; ++i)
					self->ImportType(other->importedFuncDefs[i]);

				//Import global functions
				for(unsigned i = 0, cnt = other->GetFunctionCount(); i < cnt; ++i) {
					auto* func = (asCScriptFunction*)other->GetFunctionByIndex(i);

					//Don't star-import any callback global functions
					bool isCallback = false;
					for(int i = 0; i < SC_COUNT; ++i) {
						if(func == impMod.callbacks[i]) {
							isCallback = true;
							break;
						}
					}

					if(isCallback)
						continue;

					//Inject into the new module
					self->ImportGlobalFunction(func);
				}

				for(unsigned i = 0, cnt = other->importedGlobalFunctions.GetSize(); i < cnt; ++i) {
					auto* func = (asCScriptFunction*)other->importedGlobalFunctions.Get(i);
					self->ImportGlobalFunction(func);
				}

				//Import global values
				for(unsigned i = 0, cnt = other->scriptGlobals.GetSize(); i < cnt; ++i)
					self->ImportGlobalVariable(other, i);
				for(unsigned i = 0, cnt = other->importedGlobals.GetSize(); i < cnt; ++i)
					self->ImportGlobalVariable(other, i+other->scriptGlobals.GetSize());
			}
		}
		else {
			std::vector<std::string> declarations;
			split(it->second, declarations, ',', true);

			foreach(imp, declarations)
				importSymbol(mod, impMod, *imp);
		}
	}

	//Build the module
	mod.compiling = false;
	int code;
	if(foundImports) {
		code = mod.module->Build();
		if(code != asSUCCESS) {
			error("ERROR: Failed to build module '%s' in manager '%s' (code %d).",
					mod.name.c_str(), manager_names[getManagerType(man)], code);
			mod.module = nullptr;
		}
	}
	else {
		mod.module = nullptr;
	}

	//Cache exports
	if(mod.module) {
		for(int i = 0; i < SC_COUNT; ++i)
			mod.callbacks[i] = mod.getFunction(callback_decl[i]);

		foreach(exp, mod.exports) {
			auto* self = (asCModule*)mod.module;
			const std::string& symbol = *exp;

			//Check if it's a type
			auto* type = self->GetType(symbol.c_str(), self->defaultNamespace);
			if(type) {
				mod.typeExports.push_back(type);
				continue;
			}

			//Check if it's a global
			int glob = self->GetGlobalVarIndexByName(symbol.c_str());
			if(glob != asNO_GLOBAL_VAR) {
				mod.globalExports.push_back((unsigned)glob);
				continue;
			}

			glob = self->importedGlobals.GetFirstIndex(self->defaultNamespace, symbol.c_str());
			if(glob != -1) {
				mod.globalExports.push_back(self->scriptGlobals.GetSize() + (unsigned)glob);
				continue;
			}

			//Check if it's a function
			bool foundExports = false;
			{
				const asCArray<unsigned int>& idxs = self->globalFunctions.GetIndexes(self->defaultNamespace, symbol.c_str());
				for(unsigned i = 0; i < idxs.GetLength(); ++i) {
					asCScriptFunction* func = self->globalFunctions.Get(idxs[i]);
					if(func) {
						mod.funcExports.push_back(func);
						foundExports = true;
					}
				}
			}

			{
				const asCArray<unsigned int>& idxs = self->globalFunctions.GetIndexes(self->defaultNamespace, symbol.c_str());
				for(unsigned i = 0; i < idxs.GetLength(); ++i) {
					asCScriptFunction* func = self->globalFunctions.Get(idxs[i]);
					if(func) {
						mod.funcExports.push_back(func);
						foundExports = true;
					}
				}
			}

			if(!foundExports) {
				//Check if it's a global accessor
				auto* getAcc = (asCScriptFunction*)self->GetFunctionByName((std::string("get_")+symbol).c_str());
				auto* setAcc = (asCScriptFunction*)self->GetFunctionByName((std::string("set_")+symbol).c_str());

				if(getAcc || setAcc) {
					if(getAcc)
						mod.funcExports.push_back(getAcc);
					if(setAcc)
						mod.funcExports.push_back(setAcc);
				}
				else {
					error("ERROR: %s: Cannot find '%s' to export.",
							mod.name.c_str(), symbol.c_str());
				}
			}
		}

		foreach(exp, mod.exportsFrom) {
			auto f = man->modules.find(*exp);
			if(f == man->modules.end()) {
				error("ERROR: %s: Cannot find module '%s' to export from.",
						mod.name.c_str(), exp->c_str());
			}

			foreach(it, f->second->typeExports)
				mod.typeExports.push_back(*it);
			foreach(it, f->second->funcExports)
				mod.funcExports.push_back(*it);
			foreach(it, f->second->globalExports)
				mod.globalExports.push_back(*it);
		}
	}
	else {
		for(int i = 0; i < SC_COUNT; ++i)
			mod.callbacks[i] = nullptr;
	}

	return mod.module != nullptr;
}

void bindImports(Manager* man, Module& mod) {
	auto* tMod = mod.module;
	if(tMod == nullptr)
		return;
	unsigned fcnt = tMod->GetImportedFunctionCount();
	for(unsigned i = 0; i < fcnt; ++i) {
		const char* decl = tMod->GetImportedFunctionDeclaration(i);
		const char* sourcemod = tMod->GetImportedFunctionSourceModule(i);

		auto it = man->modules.find(sourcemod);
		if(it == man->modules.end()) {
			error("ERROR: '%s': Cannot import function '%s': module '%s' does not exist.",
				tMod->GetName(), decl, sourcemod);
			continue;
		}

		auto* sMod = it->second->module;
		if(sMod == nullptr)
			continue;
		asIScriptFunction* func = sMod->GetFunctionByDecl(decl);

		if(func == 0) {
			error("ERROR: '%s': Cannot import function '%s' from module '%s': function does not exist.",
				tMod->GetName(), decl, sourcemod);
			continue;
		}

		tMod->BindImportedFunction(i, func);
	}
}

void sortPriorities(Manager* man) {
	man->priority_init.clear();
	man->priority_render.clear();
	man->priority_draw.clear();
	man->priority_tick.clear();
	man->priority_sync.clear();

	for(auto it = man->modules.begin(); it != man->modules.end(); ++it) {
		Module& mod = *it->second;
		File& fl = *mod.file;

		if(mod.callbacks[SC_init] || mod.callbacks[SC_preInit] || mod.callbacks[SC_postInit])
			man->priority_init.insert(std::pair<int,Module*>(-fl.priority_init, &mod));

		if(mod.callbacks[SC_render])
			man->priority_render.insert(std::pair<int,Module*>(-fl.priority_render, &mod));

		if(mod.callbacks[SC_draw])
			man->priority_draw.insert(std::pair<int,Module*>(-fl.priority_draw, &mod));

		if(mod.callbacks[SC_tick])
			man->priority_tick.insert(std::pair<int,Module*>(-fl.priority_tick, &mod));

		if(mod.callbacks[SC_sync_initial])
			man->priority_sync.insert(std::pair<int,Module*>(-fl.priority_sync, &mod));
	}
}

void Manager::compile(const std::string& cache_root, unsigned cache_version) {
	//Generate all the modules
	for(auto it = files.begin(); it != files.end(); ++it) {
		File& fl = *it->second;

		//Skip over empty module names, they're included files
		if(fl.path.empty() || fl.module.empty())
			continue;

		//Find unused module name
		std::string modname = fl.module;
		int i = 2;
		while(modules.find(modname) != modules.end()) {
			modname = fl.module + toString(i);
			++i;
		}

		//Display a warning when we have duplicate module names
		if(i != 2) {
			warn("WARNING: File '%s' has duplicate module name '%s'."
			 " Using temporary module name '%s' instead.", fl.path.c_str(),
			 fl.module.c_str(), modname.c_str());
		}

		//Create the module
		Module& mod = *new Module();
		mod.name = modname;
		buildModule(this, fl, mod);
		modules[modname] = &mod;
	}

	//Compile the modules
	for(auto it = modules.begin(); it != modules.end(); ++it) {
		Module& mod = *it->second;

		//Build the module dependency tree
		compileModule(this, mod);
	}
			
	//Bind all imported functions
	for(auto mod = modules.begin(); mod != modules.end(); ++mod) {
		bindImports(this, *mod->second);
	}

	//Erase modules that didn't compile succesfully
	for(auto it = modules.begin(); it != modules.end();) {
		if(it->second->module == nullptr)
			it = modules.erase(it);
		else
			++it;
	}

	//Sort by priority
	sortPriorities(this);
}

void reloadModule(Manager* man, Module& curMod) {
	//Load the file
	std::string filename = curMod.file->path;
	std::string module = curMod.name;

	File& fl = *new File();
	fl.module = module+"__reload";
	parseFile(man, fl, filename, false);

	//Build the module
	Module& mod = *new Module();
	mod.name = module+"__reload";

	buildModule(man, fl, mod);

	print("Reloading module %s", module.c_str());

	if(!compileModule(man, mod)) {
		man->engine->DiscardModule(mod.name.c_str());
		delete &fl;
		delete &mod;
		console.show();
		return;
	}

	net::Message msg;

	//Call pre-reload
	if(curMod.callbacks[SC_preReload]) {
		Call cl = curMod.call(SC_preReload);
		cl.push(&msg);
		cl.call();
	}

	//Replace successful
	Module& oldMod = *man->modules[module];
	((asCModule*)oldMod.module)->name = (module+"__old").c_str();
	((asCModule*)mod.module)->name = module.c_str();
	fl.module = module;
	mod.name = module;

	//Overwrite in manager for ticks
	man->files[fl.path] = &fl;
	man->modules[module] = &mod;

	//Bind imports for this module
	bindImports(man, mod);

	//Call post-reload
	if(mod.callbacks[SC_postReload]) {
		Call cl = mod.call(SC_postReload);
		cl.push(&msg);
		cl.call();
	}
	else if(mod.callbacks[SC_init]) {
		Call cl = mod.call(SC_init);
		cl.call();
	}

	//Special stuff
	if(module == "input")
		bindInputScripts(GS_Game, devices.scripts.client);
}

void renderRebuildSet(Manager* man, Module& curMod, std::unordered_set<Module*>& totalSet) {
	//Queue up dependencies
	for(auto it = man->modules.begin(); it != man->modules.end(); ++it) {
		Module* mod = it->second;
		if(mod->dependencies.find(&curMod) == mod->dependencies.end())
			continue;
		totalSet.insert(mod);
		renderRebuildSet(man, *mod, totalSet);
	}
}

void visitRebuildSet(Manager* man, Module& mod, std::unordered_set<Module*>& totalSet, std::vector<Module*>& queue) {
	if(totalSet.find(&mod) == totalSet.end())
		return;

	totalSet.erase(&mod);
	foreach(it, mod.dependencies)
		visitRebuildSet(man, **it, totalSet, queue);

	queue.push_back(&mod);
}

void Manager::reload(const std::string& module) {
	//Clear cached stuff
	clearCachedScripts();

	auto it = modules.find(module);
	if(it == modules.end())
		return;

	Module& curMod = *it->second;

	std::unordered_set<Module*> totalSet;
	totalSet.insert(&curMod);

	renderRebuildSet(this, curMod, totalSet);

	std::vector<Module*> queue;
	while(!totalSet.empty()) {
		Module* mod = *totalSet.begin();
		visitRebuildSet(this, *mod, totalSet, queue);
	}

	foreach(it, queue) {
		reloadModule(this, **it);
	}

	//Rebind all explicit imports
	for(auto mod = modules.begin(); mod != modules.end(); ++mod)
		bindImports(this, *mod->second);

	//Resort hook priorities
	sortPriorities(this);
}

void Manager::init() {
	foreach(it, priority_init) {
		Module& mod = *it->second;
		Call cl = mod.call(SC_preInit);
		cl.call();
	}

	foreach(it, priority_init) {
		Module& mod = *it->second;
		Call cl = mod.call(SC_init);
		cl.call();
	}

	foreach(it, priority_init) {
		Module& mod = *it->second;
		Call cl = mod.call(SC_postInit);
		cl.call();
	}
}

void Manager::deinit() {
	foreach(it, modules) {
		Module& mod = *it->second;
		Call cl = mod.call(SC_deinit);
		cl.call();
	}
}

void Manager::tick(double time) {
	foreach(it, priority_tick) {
		Module& mod = *it->second;
		if(mod.tickFails < SCRIPT_MAX_TICK_FAILS) {
			Call cl = mod.call(SC_tick);
			cl.push(time);
#ifdef PROFILE_SCRIPT_CALLBACKS
			double startTime = devices.driver->getAccurateTime();
#endif
			if(!cl.call()) {
				mod.tickFails++;

				if(mod.tickFails == SCRIPT_MAX_TICK_FAILS)
					error("Module '%s' failed its tick too many times, disabling.",
						mod.module->GetName());
			}

#ifdef PROFILE_SCRIPT_CALLBACKS
			double endTime = devices.driver->getAccurateTime();
			mod.tickTime = endTime - startTime;
#endif
		}
	}
}

void Manager::draw() {
	foreach(it, priority_draw) {
		Module& mod = *it->second;
		if(mod.drawFails < SCRIPT_MAX_DRAW_FAILS) {
			Call cl = mod.call(SC_draw);
#ifdef PROFILE_SCRIPT_CALLBACKS
			double startTime = devices.driver->getAccurateTime();
#endif
			if(!cl.call()) {
				mod.drawFails++;

				if(mod.drawFails == SCRIPT_MAX_DRAW_FAILS)
					error("Module '%s' failed its draw too many times, disabling.",
						mod.module->GetName());
			}

#ifdef PROFILE_SCRIPT_CALLBACKS
			double endTime = devices.driver->getAccurateTime();
			mod.drawTime = endTime - startTime;
#endif
		}
	}
}

void Manager::render(double frameTime) {
	foreach(it, priority_render) {
		Module& mod = *it->second;
		if(mod.renderFails < SCRIPT_MAX_RENDER_FAILS) {
			Call cl = mod.call(SC_render);
			cl.push(frameTime);
#ifdef PROFILE_SCRIPT_CALLBACKS
			double startTime = devices.driver->getAccurateTime();
#endif
			if(!cl.call()) {
				mod.renderFails++;

				if(mod.renderFails == SCRIPT_MAX_RENDER_FAILS)
					error("Module '%s' failed its render too many times, disabling.",
						mod.module->GetName());
			}

#ifdef PROFILE_SCRIPT_CALLBACKS
			double endTime = devices.driver->getAccurateTime();
			mod.renderTime = endTime - startTime;
#endif
		}
	}
}

#ifdef PROFILE_SCRIPT_CALLBACKS
void Manager::printProfile() {
	foreach(it, modules) {
		Module& mod = *it->second;
		if(mod.tickTime > 0 || mod.drawTime > 0 || mod.renderTime > 0) {
			print(" %s -- tick: %.3gms -- draw: %.3gms -- render: %.3gms",
				mod.name.c_str(), mod.tickTime * 1000.0,
				mod.drawTime * 1000.0, mod.renderTime * 1000.0);
		}
	}
}
#endif

void Manager::preRender(double frameTime) {
	foreach(it, modules) {
		Module& mod = *it->second;
		if(mod.callbacks[SC_preRender]) {
			Call cl = mod.call(SC_preRender);
			cl.push(frameTime);
			cl.call();
		}
	}
}

void Manager::save(SaveFile& file) {
	foreach(it, modules) {
		Module& mod = *it->second;

		SaveMessage msg(file);

		Call cl = mod.call(SC_save);
		cl.push(&msg);
		if(cl.call() && msg.size() > 0) {
			file << mod.name;

			char* pData; net::msize_t size;
			msg.getAsPacket(pData, size);

			file << size;
			file.write(pData, size);
		}
	}

	file << "";
}

void Manager::load(SaveFile& file) {
	while(true) {
		std::string moduleName;
		file >> moduleName;
		if(moduleName.empty())
			return;

		SaveMessage msg(file);
		net::msize_t size = file;
		if(size > 0) {
			char* buffer = (char*)malloc(size);
			file.read(buffer, size);
			msg.setPacket(buffer, size);
			free(buffer);
		}

		auto iter = modules.find(moduleName);
		if(iter != modules.end()) {
			Module& mod = *iter->second;

			if(mod.callbacks[SC_load]) {
				Call cl = mod.call(SC_load);
				cl.push(&msg);
				cl.call();
			}
		}
	}
}

void Manager::saveIdentifiers(SaveFile& file) {
	SaveMessage msg(file);

	foreach(it, modules) {
		Module& mod = *it->second;

		Call cl = mod.call(SC_saveIdentifiers);
		cl.push(&msg);
		cl.call();
	}
}

void Manager::stateChange() {
	foreach(it, modules) {
		Module& mod = *it->second;

		Call cl = mod.call(SC_stateChange);
		if(cl.valid())
			cl.call();
	}
}

#ifdef TRACE_GC_LOCK
void Manager::markGCImpossible() {
	if(gcPossible == nullptr)
		gcPossible = (bool*)malloc(sizeof(bool));
	*gcPossible = false;
}

void Manager::markGCPossible() {
	if(gcPossible == nullptr)
		gcPossible = (bool*)malloc(sizeof(bool));
	*gcPossible = true;
}
#endif

int Manager::garbageCollect(bool full) {
	asUINT size, newObjects, detected;
	engine->GetGCStatistics(&size, 0, &detected, &newObjects, 0);

	if(full/* || size > prevGCSize + (prevGCSize / 2)*/) {
		engine->GarbageCollect(asGC_FULL_CYCLE);
		engine->GetGCStatistics(&prevGCSize, 0, 0, 0, 0);
		return 2;
	}
	else if(newObjects > 500) {
		asUINT runs = (asUINT)(log((double)(newObjects + detected + 2)) / log(2.0)) * 10;

		for(asUINT i = 0; i < runs; ++i)
			if(engine->GarbageCollect() == 0)
				break;
		return 1;
	}
	else {
		asUINT runs = (asUINT)(log((double)(newObjects + detected + 2)) / log(2.0)) * 50;

		for(asUINT i = 0; i < runs; ++i)
			if(engine->GarbageCollect(asGC_ONE_STEP) == 0)
				break;
		return 0;
	}
}

Call Manager::call(int funcID) {
	if(funcID <= 0)
		return Call();
	return call(engine->GetFunctionById(funcID));
}

Call Manager::call(asIScriptFunction* func) {
	if(func == 0)
		return Call();

	asIScriptContext* ctx = asGetActiveContext();
	bool nested;

	if(ctx && ctx->GetEngine() == engine) {
		nested = true;
	}
	else {
		ctx = fetchContext(engine);
		nested = ctx->GetState() == asEXECUTION_ACTIVE;
	}

	if(nested) {
		ctx->PushState();
		int status = ctx->Prepare(func);
		if(status != asSUCCESS) {
			ctx->PopState();
			ctx = 0;
		}
	}
	else {
		ctx->Prepare(func);
	}

	return Call(this, ctx, nested);
}

Call Manager::call(const char* module, const char* decl) {
	return call(getFunction(module, decl));
}

MultiCall::MultiCall() {}

MultiCall Manager::call(ScriptCallback cb) {
	MultiCall calls;
	
	for(auto it = modules.begin(), end = modules.end(); it != end; ++it) {
		Module& mod = *it->second;
		if(mod.callbacks[cb] != nullptr)
			calls.calls.push_back(mod.call(cb));
	}

	return calls;
}

Call Module::call(ScriptCallback cb) {
	asIScriptFunction* func = callbacks[cb];
	if(func == nullptr)
		return Call();

	asIScriptEngine* engine = module->GetEngine();

	auto* ctx = fetchContext(engine);
	ctx->Prepare(func);
	return Call(manager, ctx);
}

void Manager::clear() {
	for(auto it = modules.begin(), end = modules.end(); it != end; ++it) {
		if(engine->DiscardModule(it->first.c_str()) != asSUCCESS)
			error("Failed to discard module '%s'", it->first.c_str());
	}

	foreach(it, modules)
		delete it->second;
	modules.clear();

	foreach(it, files)
		delete it->second;
	files.clear();
}

Manager::~Manager() {
	clear();
	delete engine->GetJITCompiler();
}

void Manager::clearScriptThreads() {
	clearScripts = true;
	pauseScripts = false;
	while(scriptThreadsExistent != 0)
		threads::idle();
	clearScripts = false;
}

void Manager::scriptThreadCreate() {
	++scriptThreadsExistent;
}

void Manager::scriptThreadDestroy() {
	--scriptThreadsExistent;
}

void Manager::pauseScriptThreads() {
	pauseScripts = true;
	while(scriptThreadsActive != 0)
		threads::idle();
}

void Manager::resumeScriptThreads() {
	pauseScripts = false;
}

bool Manager::scriptThreadStart() {
	retry:
	while(pauseScripts && !clearScripts)
		threads::idle();
	if(clearScripts)
		return false;

	++scriptThreadsActive;
	if(pauseScripts) {
		--scriptThreadsActive;
		goto retry;
	}
	return true;
}

void Manager::scriptThreadEnd() {
	--scriptThreadsActive;
}

Call::Call()
	: manager(0), ctx(0), arg(0), nested(false) {
}

Call::Call(Manager* man, asIScriptContext* Ctx, bool Nested)
	: manager(man), ctx(Ctx), arg(0), nested(Nested) {
}

Call::~Call() {
	if(ctx) {
		if(nested)
			ctx->PopState();
	}
}

void Call::setObject(void* obj) {
	if(ctx)
		ctx->SetObject((void*)obj);
}

void* Call::getReturnObject() {
	if(!ctx)
		return 0;
	return ctx->GetReturnObject();
}

void Call::push(int value) {
	if(ctx)
		ctx->SetArgDWord(arg++, value);
}

void Call::push(long long value) {
	if(ctx)
		ctx->SetArgQWord(arg++, value);
}

void Call::push(unsigned value) {
	if(ctx)
		ctx->SetArgDWord(arg++, value);
}

void Call::push(float value) {
	if(ctx)
		ctx->SetArgFloat(arg++, value);
}

void Call::push(double value) {
	if(ctx)
		ctx->SetArgDouble(arg++, value);
}

void Call::push(bool value) {
	if(ctx)
		ctx->SetArgByte(arg++, value);
}

bool Call::call() {
	if(!ctx) {
		return false;
	}
	status = ctx->Execute();
	return status == asSUCCESS;
}

bool Call::call(unsigned& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnDWord();
	return true;
}

bool Call::call(int& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnDWord();
	return true;
}

bool Call::call(long long& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnQWord();
	return true;
}

bool Call::call(float& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnFloat();
	return true;
}

bool Call::call(double& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnDouble();
	return true;
}

bool Call::call(bool& value) {
	if (!call()) {
		value = 0;
		return false;
	}

	value = ctx->GetReturnByte() != 0;
	return true;
}

void MultiCall::setObject(void* obj) {
	foreach(call, calls)
		call->setObject(obj);
}

void MultiCall::push(int value) {
	foreach(call, calls)
		call->push(value);
}

void MultiCall::push(float value) {
	foreach(call, calls)
		call->push(value);
}

void MultiCall::push(double value) {
	foreach(call, calls)
		call->push(value);
}

void MultiCall::push(bool value) {
	foreach(call, calls)
		call->push(value);
}

void MultiCall::push(void* value) {
	foreach(call, calls)
		call->push(value);
}

void MultiCall::call() {
	foreach(call, calls)
		call->call();
}

struct ReadBytecode : public asIBinaryStream {
	std::ifstream& stream;

	ReadBytecode(std::ifstream& is)
		: stream(is) {
	}

	void Read(void* ptr, asUINT size) {
		if(stream.eof())
			memset(ptr, 0, size);
		else
			stream.read((char*)ptr, size);
	}

	void Write(const void* ptr, asUINT size) {
	}
};

#ifndef DISABLE_SCRIPT_CACHE
static bool loadCached(Module& mod, const File& fl, const std::string& cache_file, unsigned cache_version) {
	//Make sure the file exists
	if(!fileExists(cache_file))
		return false;

	//Make sure the cache is new enough
	time_t cache_time = getModifiedTime(cache_file);

	if(getModifiedTime(fl.path) > cache_time)
		return false;

	foreach(inc, fl.includes)
		if(getModifiedTime(inc->second->path) > cache_time)
			return false;
	
	//Open the file
	std::ifstream stream(cache_file, std::ios::in | std::ios::binary);

	//Read build version from cache
	unsigned file_version;
	stream.read((char*)&file_version, sizeof(unsigned));

	//Needs to be the same version to load the cache
	if(cache_version != file_version) {
		stream.close();
		return false;
	}

	//Write the bytecode
	printf("Load %s from cache\n", cache_file.c_str());
	ReadBytecode read(stream);

	int code = mod.module->LoadByteCode(&read);
	if(code != asSUCCESS) {
		//Discard the module and recreate it, we're in
		//an inconsistent state otherwise
		asIScriptEngine* eng = mod.module->GetEngine();
		eng->DiscardModule(mod.module->GetName());
		mod.module = eng->GetModule(mod.name.c_str(), asGM_ALWAYS_CREATE);

		//Warn the user
		warn("WARNING: Failed to load bytecode cache for"
			" module '%s' (code %d).", mod.name.c_str(), code);
		stream.close();
		return false;
	}

	//Close the file
	stream.close();
	return true;
}

struct WriteBytecode : public asIBinaryStream {
	std::ofstream& stream;

	WriteBytecode(std::ofstream& os)
		: stream(os) {
	}

	void Read(void* ptr, asUINT size) {
	}

	void Write(const void* ptr, asUINT size) {
		stream.write((const char*)ptr, size);
	}
};


static void saveCached(Module& mod, const std::string& cache_file, unsigned cache_version) {
	//Open the file
	std::ofstream stream(cache_file, std::ios::out | std::ios::binary);

	//Write build version to cache
	stream.write((const char*)&cache_version, sizeof(unsigned));

	//Write the bytecode
	printf("Save %s to cache\n", cache_file.c_str());
	WriteBytecode write(stream);
	int code = mod.module->SaveByteCode(&write);
	if(code < 0)
		error("Failed to save bytecode for '%s'", mod.name.c_str());

	//Close the file
	stream.close();
}
#endif
	
};
