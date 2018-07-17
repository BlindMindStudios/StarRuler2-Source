#pragma once
#include "compat/misc.h"
#include <string>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace profile {

const int Mod_Ctrl = 0x1 << 30;
const int Mod_Alt = 0x1 << 29;
const int Mod_Shift = 0x1 << 28;

struct Keybind {
	virtual void call(bool pressed) = 0;
	virtual ~Keybind() {};
};

struct BindDescriptor {
	int id;
	std::string name;
	Keybind* bind;
	std::vector<int> defaults;
	std::vector<int> current;
};

struct BindGroup {
	std::string name;
	std::vector<BindDescriptor> descriptors;
	umap<std::string, int> descriptorIDs;
	umap<int, int> binds;

	void addDescriptor(BindDescriptor desc);
	void addBind(const std::string& name, Keybind* bind);
	void addBind(unsigned id, Keybind* bind);
	void setBind(int key, const std::string& name);
	void setBind(int key, unsigned id);
	void clearBind(int key);
	void setDefaultBinds();

	unsigned getDefaultCount(unsigned id);
	int getDefaultKey(unsigned id, unsigned index);

	unsigned getBindCount(unsigned id);
	int getBindKey(unsigned id, unsigned index);

	void setDefaultBinds(unsigned id);
	void clearBinds(unsigned id);

	BindDescriptor* getDescriptor(const std::string& name);
	Keybind* getBind(int key);
	int getBindID(int key);

	void save();

	void clear();
	~BindGroup();
};

class Keybinds {
public:
	BindGroup global;
	std::vector<BindGroup*> groups;
	umap<std::string, BindGroup*> groupNames;

	Keybinds();
	void clear();

	BindGroup* getGroup(const std::string& name);
	void loadDescriptors(const std::string& filename);
	void setDefaultBinds();

	void loadBinds(const std::string& filename);
	void saveBinds(const std::string& filename);
};

int getModifiedKey(int key, bool ctrlKey, bool altKey, bool shiftKey);

//Physical key name
std::string getKeyName(int key);
int getKey(std::string name);

//Logical key name
std::string getKeyDisplayName(int key);
int getKeyFromDisplayName(std::string name);
	
};
