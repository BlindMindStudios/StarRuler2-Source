#include "binds.h"
#include "constants.h"
#include "main/references.h"
#include "main/initialization.h"
#include "scripts/manager.h"
#include "files.h"
#include <string>
#include "main/logging.h"

namespace scripts {

struct ScriptedKeybind : profile::Keybind {
	scripts::Manager* manager;
	asIScriptFunction* func;

	ScriptedKeybind(scripts::Manager* man, asIScriptFunction* Func)
		: manager(man), func(Func) {
	}

	void call(bool pressed) {
		if(func) {
			Call cl = manager->call(func);
			cl.push(pressed);
			cl.call();
		}
	}
};

static void cb_keybind(profile::BindGroup* grp, const std::string& name, const std::string& str) {
	std::string decl("void ");
	decl += str;
	decl += "(bool)";

	asIScriptContext* ctx = asGetActiveContext();
	asIScriptFunction* func = ctx->GetFunction();

	const char* module = func->GetModuleName();

	Manager* manager = scripts::getActiveManager();
	asIScriptFunction* scrFunc = manager->getFunction(module, decl.c_str());

	if(scrFunc) {
		grp->addBind(name, new ScriptedKeybind(manager, scrFunc));
	}
	else {
		error("Could not locate function '%s::%s'", module, decl.c_str());
	}
}

static void cb_keybind_id(profile::BindGroup* grp, unsigned id, const std::string& str) {
	std::string decl("void ");
	decl += str;
	decl += "(bool)";

	asIScriptContext* ctx = asGetActiveContext();
	asIScriptFunction* func = ctx->GetFunction();

	const char* module = func->GetModuleName();

	Manager* manager = scripts::getActiveManager();
	asIScriptFunction* scrFunc = manager->getFunction(module, decl.c_str());

	if(scrFunc) {
		grp->addBind(id, new ScriptedKeybind(manager, scrFunc));
	}
	else {
		error("Could not locate function '%s::%s'", module, decl.c_str());
	}
}

static void cb_save_kb() {
	std::string bindFile = path_join(devices.mods.getProfile("settings"), "keybinds.txt");
	devices.keybinds.saveBinds(bindFile);
}

static void cb_set_kb(profile::BindGroup* grp, int key, unsigned id) {
	grp->setBind(key, id);
}

static void cb_clear_kb(profile::BindGroup* grp, int key) {
	grp->clearBind(key);
}

static void cb_clear_kb_bind(profile::BindGroup* grp, unsigned id) {
	grp->clearBinds(id);
}

static void cb_setdef_kb(profile::BindGroup* grp, unsigned id) {
	grp->setDefaultBinds(id);
}

static void cb_setdef_kb_all(profile::BindGroup* grp) {
	grp->setDefaultBinds();
}

static unsigned cb_defcount(profile::BindGroup* grp, unsigned id) {
	return grp->getDefaultCount(id);
}

static int cb_defkey(profile::BindGroup* grp, unsigned id, unsigned index) {
	return grp->getDefaultKey(id, index);
}

static unsigned cb_curcount(profile::BindGroup* grp, unsigned id) {
	return grp->getBindCount(id);
}

static int cb_curkey(profile::BindGroup* grp, unsigned id, unsigned index) {
	return grp->getBindKey(id, index);
}

static unsigned cb_count(profile::BindGroup* grp) {
	return grp->descriptors.size();
}

static std::string cb_name(profile::BindGroup* grp, unsigned id) {
	if(id >= grp->descriptors.size()) {
		scripts::throwException("Keybind id out of bounds.");
		return "";
	}

	return grp->descriptors[id].name;
}

static unsigned cb_group_cnt() {
	return devices.keybinds.groups.size();
}

static int cb_getbind(profile::BindGroup* grp, int key) {
	return grp->getBindID(key);
}

static profile::BindGroup* cb_group(unsigned i) {
	if(i >= devices.keybinds.groups.size()) {
		scripts::throwException("Group index out of bounds.");
		return 0;
	}

	return devices.keybinds.groups[i];
}

static int mod_key(int key) {
	int mod_key = key;
	if(mod_key >= 'A' && mod_key <= 'Z')
		mod_key += 'a'-'A';
	if(devices.driver->ctrlKey)
		mod_key |= profile::Mod_Ctrl;
	if(devices.driver->altKey)
		mod_key |= profile::Mod_Alt;
	if(devices.driver->shiftKey)
		mod_key |= profile::Mod_Shift;
	return mod_key;
}

#define stAccess(type) \
	void setSetting_ ## type (const std::string& name, type value) { \
		auto* v = devices.settings.mod.getSetting(name);\
		if(!v)\
			v = devices.settings.engine.getSetting(name);\
		if(!v) {\
			scripts::throwException("Invalid setting name.");\
			return;\
		}\
		*v = value;\
	}\
	type getSetting_ ## type (const std::string& name) { \
		auto* v = devices.settings.mod.getSetting(name);\
		if(!v)\
			v = devices.settings.engine.getSetting(name);\
		if(!v) {\
			scripts::throwException("Invalid setting name.");\
			return 0;\
		}\
		return *v;\
	}\

stAccess(int);
stAccess(double);
stAccess(bool);

#define stMinMax(type, v_min, v_max) \
	type getSetting_min_ ##type (const std::string& name) { \
		auto* v = devices.settings.mod.getSetting(name);\
		if(!v)\
			v = devices.settings.engine.getSetting(name);\
		if(!v) {\
			scripts::throwException("Invalid setting name.");\
			return 0;\
		}\
		return v->v_min;\
	}\
	type getSetting_max_ ##type (const std::string& name) { \
		auto* v = devices.settings.mod.getSetting(name);\
		if(!v)\
			v = devices.settings.engine.getSetting(name);\
		if(!v) {\
			scripts::throwException("Invalid setting name.");\
			return 0;\
		}\
		return v->v_max;\
	}\

stMinMax(int, num_min, num_max);
stMinMax(double, flt_min, flt_max);

void setSetting_str(const std::string& name, const std::string& value) {
	auto* v = devices.settings.mod.getSetting(name);
	if(!v)
		v = devices.settings.engine.getSetting(name);
	if(!v) {
		scripts::throwException("Invalid setting name.");
		return;
	}
	v->setString(value);
}

const std::string errstr("ERR");
const std::string& getSetting_str(const std::string& name) {
	auto* v = devices.settings.mod.getSetting(name);
	if(!v)
		v = devices.settings.engine.getSetting(name);
	if(!v) {
		scripts::throwException("Invalid setting name.");
		return errstr;
	}
	std::string* str = v->getString();
	if(!str) {
		scripts::throwException("Setting is not a string setting.");
		return errstr;
	}
	return *str;
}

void applySettings() {
	if(game_running && devices.scripts.client) {
		scripts::MultiCall cl = devices.scripts.client->call(SC_settings_changed);
		cl.call();
	}
	else if(devices.scripts.menu) {
		scripts::MultiCall cl = devices.scripts.menu->call(SC_settings_changed);
		cl.call();
	}
}

void saveSettings() {
	devices.settings.engine.saveSettings(path_join(getProfileRoot(), "settings.txt"));
	devices.settings.mod.saveSettings(path_join(devices.mods.getProfile("settings"), "settings.txt"));
}

void RegisterProfileBinds() {
	//Bind dynamic enum for registered keybinds
	EnumBind kb("Keybind");
	kb["KB_NONE"] = -1;
	foreach(it, devices.keybinds.groups) {
		profile::BindGroup* grp = *it;
		for(unsigned i = 0; i < grp->descriptors.size(); ++i) {
			auto& bind = grp->descriptors[i];
			kb[std::string("KB_")+bind.name] = i;
		}
	}

	kb["MASK_CTRL"] = profile::Mod_Ctrl;
	kb["MASK_ALT"] = profile::Mod_Alt;
	kb["MASK_SHIFT"] = profile::Mod_Shift;

	ClassBind grp("KeybindGroup", asOBJ_REF | asOBJ_NOCOUNT, 0);
	grp.addMember("string name", offsetof(profile::BindGroup, name));
	grp.addExternMethod("void addBind(const string &in, const string &in)", asFUNCTION(cb_keybind));
	grp.addExternMethod("void addBind(Keybind, const string &in)", asFUNCTION(cb_keybind_id));

	grp.addExternMethod("uint getBindCount()", asFUNCTION(cb_count));
	grp.addExternMethod("string getBindName(uint index)", asFUNCTION(cb_name));

	grp.addExternMethod("void setBind(int key, Keybind bind)", asFUNCTION(cb_set_kb));
	grp.addExternMethod("void clearBin(int key)", asFUNCTION(cb_clear_kb));
	grp.addExternMethod("void clearBinds(Keybind bind)", asFUNCTION(cb_clear_kb_bind));

	grp.addExternMethod("void setDefaultBinds(Keybind bind)", asFUNCTION(cb_setdef_kb));
	grp.addExternMethod("void setDefaultBinds()", asFUNCTION(cb_setdef_kb_all));

	grp.addExternMethod("uint getDefaultKeyCount(Keybind bind)", asFUNCTION(cb_defcount));
	grp.addExternMethod("int getDefaultKey(Keybind bind, uint index)", asFUNCTION(cb_defkey));

	grp.addExternMethod("uint getCurrentKeyCount(Keybind bind)", asFUNCTION(cb_curcount));
	grp.addExternMethod("int getCurrentKey(Keybind bind, uint index)", asFUNCTION(cb_curkey));

	grp.addExternMethod("Keybind getBind(int key)", asFUNCTION(cb_getbind));

	bind("int getKey(string key)", asFUNCTION(profile::getKey));
	bind("string getKeyName(int key)", asFUNCTION(profile::getKeyName));

	bind("int getKeyFromDisplayName(string key)", asFUNCTION(profile::getKeyFromDisplayName));
	bind("string getKeyDisplayName(int key)", asFUNCTION(profile::getKeyDisplayName));

	bind("void saveKeybinds()", asFUNCTION(cb_save_kb));

	bind("KeybindGroup@ get_keybindGroup(uint index)", asFUNCTION(cb_group));
	bind("uint get_keybindGroupCount()", asFUNCTION(cb_group_cnt));
	bind("int modifyKey(int key)", asFUNCTION(mod_key));

	{
		Namespace ns("keybinds");
		foreach(it, devices.keybinds.groups)
			bindGlobal(format("::KeybindGroup $1", (*it)->name).c_str(), *it);
	}

	//Settings
	bind("void setSettingInt(const string &in, int)", asFUNCTION(setSetting_int));
	bind("void setSettingBool(const string &in, bool)", asFUNCTION(setSetting_bool));
	bind("void setSettingDouble(const string &in, double)", asFUNCTION(setSetting_double));
	bind("void setSettingStr(const string &in, const string &in)", asFUNCTION(setSetting_str));

	bind("int getSettingInt(const string &in)", asFUNCTION(getSetting_int));
	bind("bool getSettingBool(const string &in)", asFUNCTION(getSetting_bool));
	bind("double getSettingDouble(const string &in)", asFUNCTION(getSetting_double));
	bind("const string& getSettingStr(const string &in)", asFUNCTION(getSetting_str));

	bind("int getSettingMaxInt(const string &in)", asFUNCTION(getSetting_max_int));
	bind("int getSettingMinInt(const string &in)", asFUNCTION(getSetting_min_int));
	bind("double getSettingMaxDouble(const string &in)", asFUNCTION(getSetting_max_double));
	bind("double getSettingMinDouble(const string &in)", asFUNCTION(getSetting_min_double));

	bind("void saveSettings()", asFUNCTION(saveSettings));
	bind("void applySettings()", asFUNCTION(applySettings));

	auto bindSetting = [](NamedGeneric& set) {
		switch(set.type) {
			case GT_Bool:
				bindGlobal((std::string("bool ")+set.name).c_str(), &set.check);
			break;
			case GT_Integer:
				bindGlobal((std::string("int ")+set.name).c_str(), &set.num);
			break;
			case GT_Double:
				bindGlobal((std::string("double ")+set.name).c_str(), &set.flt);
			break;
			case GT_String:
				bindGlobal((std::string("string ")+set.name).c_str(), set.str);
			break;
			case GT_Enum: {
				std::string ename = set.name;
				ename += "_OPTION";

				EnumBind bnd(ename.c_str());
				for(unsigned i = 0; i < set.values->size(); ++i)
					bnd[(*set.values)[i]] = i;
	
				bindGlobal(("::"+ename+" "+set.name).c_str(), &set.value);
			} break;
		}
	};

	{ Namespace ns("settings");

		//Bind settings to global variables
		foreach(it, devices.settings.engine.settings)
			bindSetting((*it->second));

		foreach(it, devices.settings.mod.settings)
			bindSetting((*it->second));
	}
}

};
