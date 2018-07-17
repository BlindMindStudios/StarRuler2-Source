#include "compat/misc.h"
#include "files.h"
#include "mods/mod_manager.h"
#include "main/logging.h"
#include "str_util.h"
#include "main/references.h"
#include <string>

namespace mods {

static const unsigned CUR_COMPATIBILITY = 200;

Mod::Mod() : parent(0), isBase(false), version(1), listed(true), enabled(false), isNew(false), forced(false), compatibility(0), forCurrentVersion(false) {
}

bool Mod::resolve(std::string& path) const {
	const Mod* mod = this;
	while(mod) {
		std::string modPath = path_join(mod->abspath, path);
		if(fileExists(modPath)) {
			path = modPath;
			return true;
		}
		mod = mod->parent;
	}
	return false;
}

void Mod::resolve(const std::string& path, std::vector<std::string>& check) const {
	const Mod* mod = this;
	while(mod) {
		std::string modPath = path_join(mod->abspath, path);
		if(fileExists(modPath))
			check.push_back(modPath);
		mod = mod->parent;
	}
}

bool Mod::hasOverride(const std::string& path, bool isDirectory) const {
	foreach(it, override_patterns) {
		if(match(path.c_str(), *it))
			return true;
	}

	if(isDirectory)
		return hasOverride(path+"/");
	return false;
}

void Mod::listFiles(const std::string& dir, std::map<std::string, std::string>& out,
					const char* filter, bool recurse, bool inherit) const {
	const Mod* mod = this;

	CompiledPattern filterReqs;
	compile_pattern(filter, filterReqs);

	std::function<void(const std::string&, const std::string&, const std::string&)> readDir
			= [&](const std::string& relpath, const std::string& abspath, const std::string& dirpath) {
		std::vector<std::string> filenames;
		listDirectory(abspath, filenames);

		foreach(it, filenames) {
			std::string absfile = path_join(abspath, *it);
			std::string relfile = path_join(relpath, *it);
			std::string dirfile = path_join(dirpath, relfile);
			bool isDir = isDirectory(absfile);

			//if(!dirpath.empty() && hasOverride(dirfile, isDir))
			//	continue;

			//Recurse into directories
			if(recurse && isDir) {
				readDir(relfile, absfile, dirpath);
				continue;
			}

			//Check if it matches the pattern
			if(!match(it->c_str(), filterReqs))
				continue;

			auto fnd = out.find(relfile);
			if(fnd == out.end())
				out[relfile] = absfile;
		}
	};

	while(mod) {
		std::string abspath = path_join(mod->abspath, dir);
		if(isDirectory(abspath))
			readDir("", abspath, mod == this ? "" : dir);

		if(mod == this && (!inherit || hasOverride(dir, true)))
			break;
		mod = mod->parent;
	}
}

void Mod::resolveDirectory(const std::string& dir, std::vector<std::string>& out) const {
	const Mod* mod = this;
	while(mod) {
		std::string path = path_join(mod->abspath, dir);
		if(isDirectory(path))
			out.push_back(path);
		mod = mod->parent;
	}
}

const Mod* Mod::getFallback(unsigned short v) const {
	if(v > version)
		return nullptr;
	if(v == version)
		return this;
	//Look for a version in [v,version)
	for(unsigned short i = v; i < version; ++i) {
		auto fb = fallbacks.find(i);
		if(fb != fallbacks.end())
			return devices.mods.getMod(fb->second);
	}
	return this;
}

void Mod::loadFileList() {
	containedFiles.clear();

	std::function<void(const std::string&, const std::string&)> readDir
			= [&](const std::string& relpath, const std::string& abspath) {
		std::vector<std::string> filenames;
		listDirectory(abspath, filenames);

		foreach(it, filenames) {
			std::string absfile = path_join(abspath, *it);
			std::string relfile = path_join(relpath, *it);
			bool isDir = isDirectory(absfile);

			if(isDir) {
				readDir(relfile, absfile);
			}
			else if(!relpath.empty()){
				containedFiles.insert(relfile);
			}
		}
	};

	readDir("", abspath);
}

void Mod::getConflicts(const Mod* other, std::vector<std::string>& conflicts) const {
	foreach(it, containedFiles) {
		if(other->containedFiles.find(*it) != other->containedFiles.end())
			conflicts.push_back(*it);
	}
}

bool Mod::isCompatible(const Mod* other) const {
	if(isBase || other->isBase)
		return !isBase || !other->isBase;
	foreach(it, containedFiles) {
		if(other->containedFiles.find(*it) != other->containedFiles.end())
			return false;
	}
	return true;
}

std::string Mod::getProfile() const {
	std::string dir = getProfileRoot();

	//Make sure the root profile dir is created
	if(!isDirectory(dir))
		makeDirectory(dir);

	//Create any intermediate directories
	std::vector<std::string> dirs;

	if(dirname.empty())
		dirs.push_back("base");
	else
		dirs.push_back(dirname);

	foreach(it, dirs) {
		dir = path_join(dir, *it);

		if(!isDirectory(dir))
			makeDirectory(dir);
	}

	return dir;
}

std::string Mod::getProfile(const std::string& path) const {
	std::string dir = getProfileRoot();

	//Make sure the root profile dir is created
	if(!isDirectory(dir))
		makeDirectory(dir);

	//Create any intermediate directories
	std::vector<std::string> dirs;

	if(dirname.empty())
		dirs.push_back("base");
	else
		dirs.push_back(dirname);

	if(!path.empty())
		path_split(path, dirs);

	foreach(it, dirs) {
		dir = path_join(dir, *it);

		if(!isDirectory(dir))
			makeDirectory(dir);
	}

	return dir;
}

Manager::Manager() {
	baseMod = new Mod();
	baseMod->ident = "base";
	baseMod->name = "base";
	baseMod->abspath = getAbsolutePath(".");
	baseMod->isBase = true;
	baseMod->listed = false;
	baseMod->version = 3;
	baseMod->fallbacks[0] = "r3444";
	baseMod->fallbacks[1] = "r4257";
	baseMod->fallbacks[2] = "r4676";
	baseMod->compatibility = 200;
	baseMod->forCurrentVersion = true;

	modNames["base"] = baseMod;
	mods.push_back(baseMod);
}

Manager::~Manager() {
	foreach(it, mods)
		delete *it;
}

void Manager::registerMod(const std::string& folder, const std::string& ident) {
	std::string infopath = path_join(folder, "modinfo.txt");
	if(!fileExists(infopath))
		return;

	Mod& mod = *new Mod();
	mod.ident = ident;
	mod.dirname = ident;
	mod.abspath = getAbsolutePath(folder);

	std::string key, value;
	DataReader datafile(infopath);
	while(datafile++) {
		key = datafile.key;
		value = datafile.value;
		if(key == "Name") {
			mod.name = value;
		}
		else if(key == "Description") {
			mod.description = value;
		}
		else if(key == "Override") {
			mod.overrides.push_back(value);

			CompiledPattern compiled;
			compile_pattern(value.c_str(), compiled);

			mod.override_patterns.push_back(compiled);
		}
		else if(key == "Derives From") {
			if(value == "-")
				mod.parentname = "";
			else
				mod.parentname = value;
		}
		else if(key == "Base Mod") {
			mod.isBase = toBool(value);
		}
		else if(key == "Listed") {
			mod.listed = toBool(value);
		}
		else if(key == "Version") {
			mod.version = toNumber<unsigned short>(value);
		}
		else if(key == "Compatibility") {
			mod.compatibility = toNumber<unsigned>(value);
			mod.forCurrentVersion = mod.compatibility >= CUR_COMPATIBILITY;
		}
		else if(key == "Fallback") {
			std::string m, v;
			splitKeyValue(value, m, v, "=");
			mod.fallbacks[toNumber<unsigned short>(v)] = m;
		}
	}

	if(!mod.name.empty()) {
		mods.push_back(&mod);
		if(mod.parentname.empty() && !mod.overrides.empty())
			warn("WARNING: Mod '%s' has overrides declared, but does not derive from any mod.", mod.name.c_str());
		while(modNames.find(mod.name) != modNames.end()) {
			error("Duplicate mod named '%s'", mod.name.c_str());
			mod.name += " (Copy)";
		}
		while(modNames.find(mod.ident) != modNames.end()) {
			error("Duplicate mod ident '%s'", mod.ident.c_str());
			mod.ident += " (Copy)";
		}
		modNames[mod.name] = &mod;
		modNames[mod.ident] = &mod;
	}
	else {
		delete &mod;
	}
}

void Manager::registerDirectory(const std::string& dirname) {
	std::vector<std::string> files;
	listDirectory(dirname, files);

	foreach(it, files) {
		std::string abspath = path_join(dirname, *it);
		std::string infopath = path_join(abspath, "modinfo.txt");

		if(isDirectory(abspath) && fileExists(infopath))
			registerMod(abspath, *it);
	}
}

void Manager::finalize() {
	foreach(it, mods) {
		auto* mod = *it;
		if(!mod->parentname.empty()) {
			auto fnd = modNames.find(mod->parentname);
			if(fnd != modNames.end()) {
				mod->parent = fnd->second;
				if(!mod->isBase && fnd->second->isBase)
					mod->isBase = true;
			}
		}
		if(mod->listed)
			mod->isNew = true;
	}

	//Load enabled and disabled mod files
	std::string filename = path_join(getProfileRoot(), "mods.txt");
	DataReader datafile(filename);
	while(datafile++) {
		auto it = modNames.find(datafile.value);
		if(it != modNames.end()) {
			it->second->enabled = datafile.key == "Enabled" || datafile.key == "Forced";
			it->second->forced = datafile.key == "Forced";
			it->second->isNew = false;

			if(it->second->enabled && it->second->compatibility < CUR_COMPATIBILITY) {
				if(!it->second->forced) {
					it->second->enabled = false;
					it->second->isNew = true;
				}
			}
		}
	}

	//Disable conflicted mods
	for(size_t i = 0, cnt = mods.size(); i < cnt; ++i) {
		auto* mod = mods[i];
		mod->loadFileList();
		if(!mod->enabled)
			continue;
		for(size_t j = 0; j < i; ++j) {
			auto* othermod = mods[j];
			if(!othermod->enabled)
				continue;
			if(!mod->isCompatible(othermod)) {
				error("ERROR: Mod '%s' is not compatible with previously enabled mod '%s'. Disabling.",
					othermod->name.c_str(), mod->name.c_str());
				othermod->enabled = false;
			}
		}
	}
}

void Manager::saveState() {
	std::string filename = path_join(getProfileRoot(), "mods.txt");
	std::ofstream file(filename);

	for(auto it = mods.begin(), end = mods.end(); it != end; ++it) {
		auto* mod = *it;
		if(!mod->listed)
			continue;

		mod->isNew = false;
		if(mod->enabled) {
			if(mod->forced && mod->compatibility < CUR_COMPATIBILITY)
				file << "Forced: ";
			else
				file << "Enabled: ";
		}
		else
			file << "Disabled: ";
		file << mod->ident << "\n";
	}

	file.close();
}

void Manager::clearMods() {
	activeMods.clear();
	activeMods.push_back(baseMod);
	currentMod = baseMod;
}

bool Manager::enableMod(const std::string& name) {
	auto it = modNames.find(name);
	if(it == modNames.end()) {
		error("Could not find mod: %s", name.c_str());
		return false;
	}

	Mod* mod = it->second;
	foreach(chk, activeMods) {
		if(*chk == mod)
			return true;
		if(mod->isBase && (*chk)->isBase) {
			if(*chk == baseMod) {
				activeMods[0] = mod;
				currentMod = mod;
				return true;
			}
			error("Cannot enable mod: %s. A base mod is already loaded.", name.c_str());
			return false;
		}
		if(!mod->isCompatible(*chk)) {
			error("Cannot enable mod: %s. Incompatible with mod %s.", name.c_str(), (*chk)->name.c_str());
			return false;
		}
	}

	activeMods.push_back(mod);
	return true;
}

const Mod* Manager::getMod(const std::string& name) const {
	auto it = modNames.find(name);
	if(it == modNames.end())
		return 0;
	return it->second;
}

std::string Manager::resolve(const std::string& path) const {
	if(path[0] == '~')
		return path.substr(1, path.size() - 1);
	std::string result = path;
	for(int i = (int)activeMods.size() - 1; i >= 0; --i) {
		if(activeMods[i]->resolve(result))
			return result;
	}
	return path;
}

std::string Manager::resolve(const std::string& path, const std::string& indir) const {
	if(path[0] == '~') {
		if(path[1] == '/')
			return path.substr(2, path.size() - 2);
		else
			return path_join(indir, path.substr(1, path.size() - 1));
	}
	if(path[0] == '/')
		return resolve(path.substr(1, path.size() - 1));
	return resolve(path_join(indir, path));
}

void Manager::resolve(const std::string& path, std::vector<std::string>& check) const {
	if(path[0] == '~') {
		check.push_back(path.substr(1, path.size() - 1));
	}
	else {
		for(int i = (int)activeMods.size() - 1; i >= 0; --i)
			activeMods[i]->resolve(path, check);
	}
}

void Manager::listFiles(const std::string& dir, std::map<std::string, std::string>& out,
						const char* filter, bool recurse) const {
	for(int i = (int)activeMods.size() - 1; i >= 0; --i)
		activeMods[i]->listFiles(dir, out, filter, recurse);
}

void Manager::listFiles(const std::string& dir, const char* filter,
						std::function<void(const std::string&)> cb, bool recurse) const {
	std::map<std::string, std::string> result;
	listFiles(dir, result, filter, recurse);

	foreach(it, result)
		cb(it->second);
}

void Manager::resolveDirectory(const std::string& dir, std::vector<std::string>& out) const {
	currentMod->resolveDirectory(dir, out);
}

std::string Manager::getProfile(const std::string& path) const {
	return currentMod->getProfile(path);
}

std::string Manager::getProfile() const {
	return currentMod->getProfile();
}

std::string Manager::getGlobalProfile(const std::string& path) const {
	std::string dir = getProfileRoot();

	//Make sure the root profile dir is created
	if(!isDirectory(dir))
		makeDirectory(dir);

	//Create any intermediate directories
	std::vector<std::string> dirs;

	if(!path.empty())
		path_split(path, dirs);

	foreach(it, dirs) {
		dir = path_join(dir, *it);

		if(!isDirectory(dir))
			makeDirectory(dir);
	}

	return dir;
}

};
