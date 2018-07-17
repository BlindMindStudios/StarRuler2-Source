#pragma once
#include <vector>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <functional>

namespace mods {

struct Mod {
	std::string ident;
	std::string name;
	std::string description;
	std::string dirname;
	std::string abspath;

	std::string parentname;
	Mod* parent;
	bool isBase;
	bool listed;
	bool enabled;
	bool isNew;
	bool forced;
	bool forCurrentVersion;

	unsigned short version;
	unsigned compatibility;

	std::unordered_map<unsigned short,std::string> fallbacks;
	std::vector<std::string> overrides;
	std::vector<std::vector<std::string>> override_patterns;
	std::unordered_set<std::string> containedFiles;

	Mod();

	std::string getProfile() const;
	std::string getProfile(const std::string& path) const;

	bool hasOverride(const std::string& path, bool isDirectory = false) const;

	bool resolve(std::string& path) const;

	void resolve(const std::string& path, std::vector<std::string>& check) const;
	void listFiles(const std::string& dir, std::map<std::string, std::string>& out,
					const char* filter = "*", bool recurse = false, bool inherit = true) const;
	void resolveDirectory(const std::string& dir, std::vector<std::string>& out) const;

	void loadFileList();
	bool isCompatible(const Mod* other) const;
	void getConflicts(const Mod* other, std::vector<std::string>& conflicts) const;

	//Returns a mod to use for the requested version (may be this mod)
	// If the required mod is not present, returns null
	const Mod* getFallback(unsigned short version) const;
};

class Manager {
public:
	std::map<std::string, Mod*> modNames;
	std::vector<Mod*> mods, activeMods;
	Mod* baseMod;
	Mod* currentMod;

	Manager();
	~Manager();
	
	void registerMod(const std::string& folder, const std::string& ident);
	void registerDirectory(const std::string& dirname);
	void finalize();
	void saveState();

	void clearMods();
	bool enableMod(const std::string& name);

	const Mod* getMod(const std::string& name) const;

	std::string resolve(const std::string& path) const;
	std::string resolve(const std::string& path, const std::string& indir) const;
	void resolve(const std::string& path, std::vector<std::string>& check) const;

	//Lists all files in a directory, pairing each name to the full path in <out>
	void listFiles(const std::string& dir, std::map<std::string, std::string>& out,
		const char* filter = "*", bool recurse = false) const;

	//Lists all files in a directory, calling <cb> with the full path of each
	void listFiles(const std::string& dir, const char* filter,
		std::function<void(const std::string&)> cb, bool recurse = false) const;

	//Finds all directories that match the passed relative dir and outputs their absolute paths
	void resolveDirectory(const std::string& dir, std::vector<std::string>& out) const;

	std::string getProfile() const;
	std::string getProfile(const std::string& path) const;
	std::string getGlobalProfile(const std::string& path) const;
};
	
};
