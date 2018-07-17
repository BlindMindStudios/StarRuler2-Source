#include "profile/keybinds.h"
#include "main/logging.h"
#include "os/key_consts.h"
#include "str_util.h"
#include "main/references.h"
#include "main/input_handling.h"
#include <unordered_map>
#include <unordered_set>

namespace profile {
	
void BindGroup::clear() {
	clearPressedKeys();
	foreach(bind, descriptors)
		delete bind->bind;

	descriptors.clear();
	descriptorIDs.clear();
	binds.clear();
}

BindGroup::~BindGroup() {
	clear();
}

Keybinds::Keybinds() {
	global.name = "Global";
	groups.push_back(&global);
	groupNames["Global"] = &global;
}

void Keybinds::clear() {
	clearPressedKeys();
	global.clear();
	foreach(it, groups) {
		if(*it != &global)
			delete *it;
	}
	groups.clear();
	groupNames.clear();
	groups.push_back(&global);
	groupNames["Global"] = &global;
}

void Keybinds::loadBinds(const std::string& filename) {
	DataReader datafile(filename);
	BindGroup* grp = &global;
	while(datafile++) {
		if(datafile.key == "Group") {
			auto it = groupNames.find(datafile.value);
			if(it != groupNames.end()) {
				grp = it->second;
			}
			continue;
		}

		int key = getKey(datafile.key);
		if(datafile.value == "-") {
			grp->clearBind(key);
		}
		else {
			auto it = grp->descriptorIDs.find(datafile.value);
			if(it != grp->descriptorIDs.end())
				grp->setBind(key, it->second);
		}
	}
}

void Keybinds::saveBinds(const std::string& filename) {
	std::ofstream file(filename);
	foreach(it, groups) {
		BindGroup* grp = *it;
		std::unordered_set<int> writtenKeys;

		file << "Group: " << grp->name << "\n";

		//Set all the binds we have
		foreach(it, grp->binds) {
			BindDescriptor& desc = grp->descriptors[it->second];
			std::string line = getKeyName(it->first);
			line += ": ";
			line += desc.name;
			line += "\n";

			file << line;
			writtenKeys.insert(it->first);
		}

		//Clear out all default binds we no longer have
		foreach(it, grp->descriptors) {
			BindDescriptor& desc = *it;

			foreach(k, desc.defaults) {
				int key = *k;
				if(writtenKeys.find(key) == writtenKeys.end()) {
					file << "\t" << getKeyName(key) << ": -\n";
					writtenKeys.insert(key);
				}
			}
		}

		file << "\n";
	}

	file.close();
}

BindGroup* Keybinds::getGroup(const std::string& name) {
	auto it = groupNames.find(name);
	if(it == groupNames.end())
		return 0;
	return it->second;
}

void Keybinds::loadDescriptors(const std::string& filename) {
	BindGroup* grp = &global;
	DataReader datafile(filename);
	while(datafile++) {
		if(datafile.key == "Group") {
			if(datafile.value == "Global") {
				grp = &global;
			}
			else {
				grp = new BindGroup();
				grp->name = datafile.value;
				groups.push_back(grp);
				groupNames[grp->name] = grp;
			}
			continue;
		}

		if(grp->descriptorIDs.find(datafile.key) != grp->descriptorIDs.end())
			continue;

		BindDescriptor bind;
		bind.name = datafile.key;
		bind.bind = 0;

		if(datafile.value != "-" && !datafile.value.empty()) {
			std::vector<std::string> keys;
			split(datafile.value, keys, ',');

			foreach(key, keys) {
				if(int num = getKey(*key))
					bind.defaults.push_back(num);
			}
		}

		grp->addDescriptor(bind);
	}
}

void Keybinds::setDefaultBinds() {
	foreach(it, groups)
		(*it)->setDefaultBinds();
}

void BindGroup::addDescriptor(BindDescriptor desc) {
	desc.id = (int)descriptors.size();
	descriptors.push_back(desc);
	descriptorIDs[desc.name] = desc.id;
}

void BindGroup::addBind(const std::string& name, Keybind* bind) {
	auto it = descriptorIDs.find(name);
	if(it == descriptorIDs.end()) {
		error(std::string("Error (addBind): Could not find keybind with name: ")+name);
		return;
	}

	BindDescriptor& desc = descriptors[it->second];
	clearPressedKeys();
	delete desc.bind;
	desc.bind = bind;
}

void BindGroup::addBind(unsigned id, Keybind* bind) {
	if(id >= (unsigned)descriptors.size()) {
		error(std::string("Error (addBind): Descriptor id out of range: ")+toString(id));
		return;
	}

	BindDescriptor& desc = descriptors[id];
	clearPressedKeys();
	delete desc.bind;
	desc.bind = bind;
}

void BindGroup::setBind(int key, const std::string& name) {
	auto it = descriptorIDs.find(name);
	if(it == descriptorIDs.end()) {
		error(std::string("Error (setBind): Could not find keybind with name: ")+name);
		return;
	}

	setBind(key, it->second);
}

void BindGroup::setBind(int key, unsigned id) {
	if(id >= descriptors.size()) {
		error(std::string("Error (setBind): Descriptor id out of range: ")+toString(id));
		return;
	}

	clearBind(key);

	binds[key] = id;
	descriptors[id].current.push_back(key);
}

void BindGroup::clearBind(int key) {
	auto it = binds.find(key);
	if(it != binds.end()) {
		if(it->second < (int)descriptors.size()) {
			foreach(kb, descriptors[it->second].current) {
				if(*kb == key) {
					descriptors[it->second].current.erase(kb);
					break;
				}
			}
		}
		binds.erase(it);
	}
}

void BindGroup::setDefaultBinds() {
	for(unsigned i = 0; i < descriptors.size(); ++i) {
		foreach(key, descriptors[i].defaults)
			setBind(*key, i);
	}
}

BindDescriptor* BindGroup::getDescriptor(const std::string& name) {
	auto it = descriptorIDs.find(name);
	if(it == descriptorIDs.end())
		return 0;
	return &descriptors[it->second];
}

Keybind* BindGroup::getBind(int key) {
	auto it = binds.find(key);
	if(it == binds.end()) {
		//SPECIAL: Try it without shift
		if(key & Mod_Shift) {
			key &= ~Mod_Shift;
			it = binds.find(key);
			if(it == binds.end())
				return 0;
		}
		else {
			return 0;
		}
	}
	return descriptors[it->second].bind;
}

int BindGroup::getBindID(int key) {
	auto it = binds.find(key);
	if(it == binds.end()) {
		//SPECIAL: Try it without shift
		if(key & Mod_Shift) {
			key &= ~Mod_Shift;
			it = binds.find(key);
			if(it == binds.end())
				return -1;
		}
		else {
			return -1;
		}
	}
	return descriptors[it->second].id;
}

unsigned BindGroup::getDefaultCount(unsigned id) {
	if(id >= descriptors.size()) {
		error("Error (getDefaultCount): Descriptor id out of range: %d", id);
		return 0;
	}

	return (unsigned)descriptors[id].defaults.size();
}

int BindGroup::getDefaultKey(unsigned id, unsigned index) {
	if(id >= descriptors.size()) {
		error("Error (getDefaultKey): Descriptor id out of range: %d", id);
		return 0;
	}

	if(index >= descriptors[id].defaults.size()) {
		error("Error (getDefaultKey): Key index out of range: %d", index);
		return 0;
	}

	return descriptors[id].defaults[index];
}

unsigned BindGroup::getBindCount(unsigned id) {
	if(id >= descriptors.size()) {
		error("Error (getBindCount): Descriptor id out of range: %d", id);
		return 0;
	}

	return (unsigned)descriptors[id].current.size();
}

int BindGroup::getBindKey(unsigned id, unsigned index) {
	if(id >= descriptors.size()) {
		error("Error (getBindKey): Descriptor id out of range: %d", id);
		return 0;
	}

	if(index >= descriptors[id].current.size()) {
		error("Error (getBindKey): Key index out of range: %d", index);
		return 0;
	}

	return descriptors[id].current[index];
}

void BindGroup::clearBinds(unsigned id) {
	if(id >= descriptors.size()) {
		error("Error (clearBinds): Descriptor id out of range: %d", id);
		return;
	}

	foreach(it, descriptors[id].current)
		binds.erase(*it);
	descriptors[id].current.clear();
}

void BindGroup::setDefaultBinds(unsigned id) {
	if(id >= descriptors.size()) {
		error("Error (setDefaultBinds): Descriptor id out of range: %d", id);
		return;
	}

	clearBinds(id);
	foreach(it, descriptors[id].defaults)
		setBind(*it, id);
}

std::unordered_map<std::string, int> keyNames;
std::unordered_map<int, std::string> keyValues;
#define keyName(name, value)\
	keyNames[name] = value;\
	keyValues[value] = name;
bool init_keyNames = true;

inline void initKeyNames() {
	if(init_keyNames) {
		init_keyNames = false;

		keyName("esc", os::KEY_ESC);
		keyName("f1", os::KEY_F1);
		keyName("f2", os::KEY_F2);
		keyName("f3", os::KEY_F3);
		keyName("f4", os::KEY_F4);
		keyName("f5", os::KEY_F5);
		keyName("f6", os::KEY_F6);
		keyName("f7", os::KEY_F7);
		keyName("f8", os::KEY_F8);
		keyName("f9", os::KEY_F9);
		keyName("f10", os::KEY_F10);
		keyName("f11", os::KEY_F11);
		keyName("f12", os::KEY_F12);
		keyName("f13", os::KEY_F13);
		keyName("f14", os::KEY_F14);
		keyName("f15", os::KEY_F15);
		keyName("f16", os::KEY_F16);
		keyName("f17", os::KEY_F17);
		keyName("f18", os::KEY_F18);
		keyName("f19", os::KEY_F19);
		keyName("f20", os::KEY_F20);
		keyName("f21", os::KEY_F21);
		keyName("f22", os::KEY_F22);
		keyName("f23", os::KEY_F23);
		keyName("f24", os::KEY_F24);
		keyName("f25", os::KEY_F25);
		keyName("up", os::KEY_UP);
		keyName("down", os::KEY_DOWN);
		keyName("left", os::KEY_LEFT);
		keyName("right", os::KEY_RIGHT);
		keyName("lshift", os::KEY_LSHIFT);
		keyName("rshift", os::KEY_RSHIFT);
		keyName("lctrl", os::KEY_LCTRL);
		keyName("rctrl", os::KEY_RCTRL);
		keyName("lalt", os::KEY_LALT);
		keyName("ralt", os::KEY_RALT);
		keyName("tab", os::KEY_TAB);
		keyName("enter", os::KEY_ENTER);
		keyName("backspace", os::KEY_BACKSPACE);
		keyName("space", ' ');
		keyName("insert", os::KEY_INSERT);
		keyName("del", os::KEY_DEL);
		keyName("pageup", os::KEY_PAGEUP);
		keyName("pagedown", os::KEY_PAGEDOWN);
		keyName("home", os::KEY_HOME);
		keyName("end", os::KEY_END);
		keyName("kp_0", os::KEY_KP_0);
		keyName("kp_1", os::KEY_KP_1);
		keyName("kp_2", os::KEY_KP_2);
		keyName("kp_3", os::KEY_KP_3);
		keyName("kp_4", os::KEY_KP_4);
		keyName("kp_5", os::KEY_KP_5);
		keyName("kp_6", os::KEY_KP_6);
		keyName("kp_7", os::KEY_KP_7);
		keyName("kp_8", os::KEY_KP_8);
		keyName("kp_9", os::KEY_KP_9);
		keyName("kp_divide", os::KEY_KP_DIVIDE);
		keyName("kp_multiply", os::KEY_KP_MULTIPLY);
		keyName("kp_subtract", os::KEY_KP_SUBTRACT);
		keyName("kp_add", os::KEY_KP_ADD);
		keyName("kp_decimal", os::KEY_KP_DECIMAL);
		keyName("kp_equal", os::KEY_KP_EQUAL);
		keyName("kp_enter", os::KEY_KP_ENTER);
		keyName("num_lock", os::KEY_NUM_LOCK);
		keyName("caps_lock", os::KEY_CAPS_LOCK);
		keyName("scroll_lock", os::KEY_SCROLL_LOCK);
		keyName("pause", os::KEY_PAUSE);
		keyName("lsuper", os::KEY_LSUPER);
		keyName("rsuper", os::KEY_RSUPER);
		keyName("menu", os::KEY_MENU);
	}
}

int getKey(std::string name) {
	initKeyNames();
	int key = 0;
	name = trim(name);
	toLowercase(name);
	while(!name.empty()) {
		if(name.compare(0, 5, "ctrl+") == 0) {
			name = name.substr(5, name.size() - 5);
			key |= Mod_Ctrl;
			continue;
		}
		if(name.compare(0, 4, "alt+") == 0) {
			name = name.substr(4, name.size() - 4);
			key |= Mod_Alt;
			continue;
		}
		if(name.compare(0, 6, "shift+") == 0) {
			name = name.substr(6, name.size() - 6);
			key |= Mod_Shift;
			continue;
		}
		if(name[0] == '#') {
			key |= toNumber<int>(name.substr(1, name.size() - 1));
			break;
		}

		auto it = keyNames.find(name);
		if(it != keyNames.end()) {
			key |= (int)it->second;
			break;
		}

		u8it ch(name);
		key |= ch++;
		break;
	}

	return key;
}

int getKeyFromDisplayName(std::string name) {
	initKeyNames();

	int key = 0;
	name = trim(name);
	toLowercase(name);
	while(!name.empty()) {
		if(name.compare(0, 5, "ctrl+") == 0) {
			name = name.substr(5, name.size() - 5);
			key |= Mod_Ctrl;
			continue;
		}
		if(name.compare(0, 4, "alt+") == 0) {
			name = name.substr(4, name.size() - 4);
			key |= Mod_Alt;
			continue;
		}
		if(name.compare(0, 6, "shift+") == 0) {
			name = name.substr(6, name.size() - 6);
			key |= Mod_Shift;
			continue;
		}
		if(name[0] == '#') {
			key |= toNumber<int>(name.substr(1, name.size() - 1));
			break;
		}

		auto it = keyNames.find(name);
		if(it != keyNames.end()) {
			key |= (int)it->second;
			break;
		}

		u8it ch(name);
		int chr = ch++;

		int lookup = devices.driver->getKeyForChar(chr);
		if(lookup >= 'A' && lookup <= 'Z')
			lookup -= 'A'-'a';
		if(lookup == -1)
			key |= chr;
		else
			key |= lookup;
		break;
	}

	return key;
}

std::string getKeyName(int key) {
	std::string name;
	
	if(key & Mod_Ctrl) {
		name += "ctrl+";
		key &= ~Mod_Ctrl;
	}

	if(key & Mod_Alt) {
		name += "alt+";
		key &= ~Mod_Alt;
	}

	if(key & Mod_Shift) {
		name += "shift+";
		key &= ~Mod_Shift;
	}

	auto it = keyValues.find(key);
	if(it != keyValues.end()) {
		name += it->second;
		return name;
	}

	u8append(name, key);
	return name;
}

std::string getKeyDisplayName(int key) {
	std::string name;
	
	if(key & Mod_Ctrl) {
		name += "ctrl+";
		key &= ~Mod_Ctrl;
	}

	if(key & Mod_Alt) {
		name += "alt+";
		key &= ~Mod_Alt;
	}

	if(key & Mod_Shift) {
		name += "shift+";
		key &= ~Mod_Shift;
	}

	auto it = keyValues.find(key);
	if(it != keyValues.end()) {
		name += it->second;
		return name;
	}

	int chr = devices.driver->getCharForKey(key);
	if(chr == -1)
		u8append(name, key);
	else
		u8append(name, chr);
	return name;
}

int getModifiedKey(int key, bool ctrlKey, bool altKey, bool shiftKey) {
	int mod_key = key;
	if(mod_key >= 'A' && mod_key <= 'Z')
		mod_key += 'a'-'A';
	if(ctrlKey)
		mod_key |= profile::Mod_Ctrl;
	if(altKey)
		mod_key |= profile::Mod_Alt;
	if(shiftKey)
		mod_key |= profile::Mod_Shift;
	return mod_key;
}

};
