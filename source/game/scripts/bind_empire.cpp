#include "scripts/binds.h"
#include "obj/object.h"
#include "empire.h"
#include "empire_stats.h"
#include "main/references.h"
#include "design/design.h"
#include "vec2.h"
#include "scripts/script_components.h"
#include "util/stat_history.h"
#include "network/network_manager.h"

extern Empire* defaultEmpire;
extern Empire* playerEmpire;
extern Empire* spectatorEmpire;

extern std::unordered_map<std::string,unsigned> statIndices;

namespace scripts {
	
static const Design* getDesignByName(Empire* emp, const std::string& name) {
	return emp->getDesign(name, true);
}

static const Design* getDesignById(Empire* emp, int id) {
	return emp->getDesign(id, true);
}

static unsigned getDesignCount(Empire* emp) {
	return emp->designIds.size();
}

static unsigned getDesignClassCount(Empire* emp) {
	return emp->designClassIds.size();
}

static Empire* empFactory() {
	return new Empire();
}

static Empire* empFactory_b(bool unlisted) {
	return new Empire(unlisted ? INVALID_EMPIRE : UNLISTED_EMPIRE);
}

static void writeDelta(Empire* emp, net::Message& msg) {
	emp->writeDelta(msg);
}

static void readDelta(Empire* emp, net::Message& msg) {
	try {
		emp->readDelta(msg);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
}

static bool ssUnlocked(Empire* emp, const SubsystemDef* def) {
	threads::ReadLock lock(emp->subsystemDataMutex);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);
	return ssdata ? ssdata->unlocked : false;
}

static bool ssModUnlocked(Empire* emp, const SubsystemDef* def, const SubsystemDef::ModuleDesc* mod) {
	threads::ReadLock lock(emp->subsystemDataMutex);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);
	if(!ssdata)
		return false;
	if((int)ssdata->modulesUnlocked.size() <= mod->index)
		return false;
	return ssdata->modulesUnlocked[mod->index];
}

static void ssSetModUnlock(Empire* emp, const SubsystemDef* def, const SubsystemDef::ModuleDesc* mod, bool val) {
	threads::WriteLock lock(emp->subsystemDataMutex);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);
	if(ssdata) {
		if((int)ssdata->modulesUnlocked.size() <= mod->index)
			ssdata->modulesUnlocked.resize(mod->index+1, false);
		ssdata->modulesUnlocked[mod->index] = val;
		ssdata->delta = true;
	}
}

static void ssSetUnlock(Empire* emp, const SubsystemDef* def, bool val) {
	threads::WriteLock lock(emp->subsystemDataMutex);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);
	if(ssdata) {
		ssdata->unlocked = val;
		ssdata->delta = true;
	}
}

static void removeModifier(Empire* emp, const SubsystemDef* def, unsigned id) {
	threads::WriteLock lock(emp->subsystemDataMutex);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);
	if(ssdata) {
		ssdata->stages.erase(id);
		ssdata->delta = true;
	}
}

static void addModifier_d(asIScriptGeneric* f) {
	Empire* emp = (Empire*)f->GetObject();
	threads::WriteLock lock(emp->subsystemDataMutex);
	const SubsystemDef* def = (const SubsystemDef*)f->GetArgAddress(0);
	Empire::SubsystemData* ssdata = emp->getSubsystemData(def);

	if(!ssdata)
		return;

	//Find the modifier
	std::string& modname = *(std::string*)f->GetArgAddress(1);
	auto it = def->modifierIds.find(modname);
	if(it == def->modifierIds.end()) {
		scripts::throwException(
			format("Error: Could not find subsystem modifier '$1.$2'.\n",
				def->id, modname).c_str());
		return;
	}

	const SubsystemDef::ModifyStage* stage = it->second;

	//Check arguments
	if((int)stage->argumentNames.size() != f->GetArgCount() - 2) {
		scripts::throwException(
			format("Error: Subsystem modifier '$1.$2'"
				" expects $3 arguments, got $4.\n",
				def->id, modname,
				(unsigned)stage->argumentNames.size(),
				f->GetArgCount() - 1).c_str());
		return;
	}

	//Create applied stage
	SubsystemDef::AppliedStage as;
	as.stage = stage;

	for(unsigned i = 0, cnt = stage->argumentNames.size(); i < cnt; ++i)
		as.arguments[i] = f->GetArgFloat(i+2);

	//Add stage to data
	unsigned id = ssdata->nextStageId++;
	ssdata->stages[id] = as;
	ssdata->delta = true;
	f->SetReturnDWord(id);
}

struct StatReader {
	const StatHistory* history;
	const StatEntry* entry;
	const StatEvent* evt;

	Empire* emp;
	unsigned id;

	StatReader(const StatHistory* History, Empire* Emp, unsigned ID) : history(History), entry(0), evt(0), emp(Emp), id(ID) {}
	~StatReader() {
		if(emp)
			emp->unlockStatHistory(id);
	}

	int get_int() const {
		if(entry)
			return entry->asInt;
		else
			return 0;
	}

	float get_float() const {
		if(entry)
			return entry->asFloat;
		else
			return 0;
	}

	unsigned get_time() const {
		if(entry)
			return entry->time;
		else
			return 0;
	}

	unsigned get_evt_type() const {
		if(evt)
			return evt->type;
		else
			return 0;
	}

	std::string get_evt_name() const {
		if(evt)
			return evt->name;
		else
			return "";
	}

	bool toHead() {
		if(!history)
			return false;

		if(const StatEntry* head = history->getHead()) {
			entry = head;
			evt = 0;
			return true;
		}
		else {
			return false;
		}
	}

	bool toTail() {
		if(!history)
			return false;

		if(const StatEntry* tail = history->getTail()) {
			entry = tail;
			evt = 0;
			return true;
		}
		else {
			return false;
		}
	}

	bool advance(int amount) {
		if(!history)
			return false;

		if(amount > 0) {
			evt = 0;

			if(entry == 0) {
				entry = history->getHead();

				if(entry)
					return advance(amount-1);
				else
					return false;
			}

			do {
				entry = entry->next;
				if(entry == 0)
					return false;
			} while(--amount != 0);

			return entry != 0;
		}
		else if(amount < 0) {
			evt = 0;

			if(entry == 0) {
				entry = history->getTail();

				if(entry)
					return advance(amount+1);
				else
					return false;
			}

			do {
				entry = entry->prev;
				if(entry == 0)
					return false;
			} while(--amount != 0);

			return entry != 0;
		}
		else {
			evt = 0;
			return entry != 0;
		}
	}

	bool advanceEvent() {
		if(!history)
			return false;

		if(entry) {
			if(evt == 0) {
				evt = entry->evt;
				return evt != 0;
			}
			else if(evt->next) {
				evt = evt->next;
				return true;
			}
			else {
				return false;
			}
		}
		return false;
	}

	static void destroy(StatReader* reader) {
		delete reader;
	}
};

StatReader* getStatHistory(Empire* emp, unsigned id) {
	const StatHistory* history = emp->lockStatHistory(id);
	if(!history) {
		return new StatReader(0, 0, 0);
	}
	else {
		return new StatReader(history, emp, id);
	}
}

bool empIsHostile(Empire& from, Empire* to) {
	if(to == nullptr)
		return false;
	return from.hostileMask & to->mask;
}

bool empIsHostile_restricted(Empire& from, Empire* to) {
	if(to == nullptr)
		return false;
	//if(&from != playerEmpire && to != playerEmpire)
	//	return false;
	return from.hostileMask & to->mask;
}

void empSetHostile(Empire& from, Empire& to, bool value) {
	threads::Lock lock(from.maskMutex);
	if(value)
		from.hostileMask |= to.mask;
	else
		from.hostileMask &= ~to.mask;
}

static bool empControlled(Empire& emp) {
	return devices.network->getCurrentPlayer().controls(&emp);
}

static bool empViewed(Empire& emp) {
	return devices.network->getCurrentPlayer().views(&emp);
}

void RegisterEmpireBinds(bool declarations, bool server) {
	if(declarations) {
		ClassBind emp("Empire", asOBJ_REF | asOBJ_NOCOUNT);
		return;
	}

	ClassBind emp("Empire");
	emp.addFactory("Empire@ f()", asFUNCTION(empFactory));
	emp.addFactory("Empire@ f(bool unlisted)", asFUNCTION(empFactory_b));
	emp.addMember("string name", offsetof(Empire,name));
	emp.addMember("Player@ player", offsetof(Empire,player));
	emp.addMember("uint8 id", offsetof(Empire,id));
	emp.addMember("int index", offsetof(Empire,index));
	emp.addMember("uint mask", offsetof(Empire,mask));
	emp.addMember("uint visionMask", offsetof(Empire,visionMask));
	emp.addMember("Color color", offsetof(Empire,color));
	emp.addMember("const Material@ background", offsetof(Empire,background));
	emp.addMember("const Material@ portrait", offsetof(Empire,portrait));
	emp.addMember("const Material@ flag", offsetof(Empire,flag));
	emp.addMember("string backgroundDef", offsetof(Empire,backgroundDef));
	emp.addMember("string portraitDef", offsetof(Empire,portraitDef));
	emp.addMember("string flagDef", offsetof(Empire,flagDef));
	emp.addMember("uint flagID", offsetof(Empire,flagID));
	emp.addMember("const Shipset@ shipset", offsetof(Empire, shipset));
	emp.addMember("string effectorSkin", offsetof(Empire, effectorSkin));

	if(server) {
		emp.addMember("uint hostileMask", offsetof(Empire,hostileMask));
		emp.addExternMethod("bool isHostile(Empire@ emp)", asFUNCTION(empIsHostile));
		emp.addExternMethod("void setHostile(Empire& emp, bool value)", asFUNCTION(empSetHostile));
		emp.addMethod("void cacheVision()", asMETHOD(Empire,cacheVision));
	}
	else {
		emp.addExternMethod("bool isHostile(Empire@ emp)", asFUNCTION(empIsHostile_restricted));
		emp.addExternMethod("bool get_controlled() const", asFUNCTION(empControlled));
		emp.addExternMethod("bool get_viewable() const", asFUNCTION(empViewed));
	}

	emp.addMethod("uint get_objectCount()", asMETHOD(Empire, objectCount));
	emp.addMethod("Object@+ get_objects(uint i)", asMETHOD(Empire, findObject));

	//Stats
	{
		Namespace ns("stat");
		EnumBind statTypes("EmpireStat");
		for(auto i = statIndices.begin(), end = statIndices.end(); i != end; ++i)
			statTypes[i->first] = i->second;
	}

	bind("string get_statName(stat::EmpireStat)", asFUNCTION(getEmpireStatName));

	ClassBind stats("StatHistory", asOBJ_REF | asOBJ_SCOPED);
	classdoc(stats, "Accesses the history of an empire's stat. Locks the stat, so limit access to these histories.");

	stats.addFactory("StatHistory@ f(Empire&, stat::EmpireStat)", asFUNCTION(getStatHistory));
	stats.addExternBehaviour(asBEHAVE_RELEASE, "void f()", asFUNCTION(StatReader::destroy));
	
	stats.addMethod("bool toTail()", asMETHOD(StatReader,toTail))
		doc("Advances to the most recent stat entry.", "True if there was a tail to move to.");
	stats.addMethod("bool toHead()", asMETHOD(StatReader,toHead))
		doc("Advances to the earliest stat entry.", "True if there was a head to move to.");

	stats.addMethod("bool advance(int offset = 1)", asMETHOD(StatReader,advance))
		doc("Advances to another stat entry.", "Number of entries to move. Positive is later in time, negative is earlier. Advancing 0 resets the event reader. If not on a valid entry, advances to a valid entry at the correspending head or tail. ", "Returns true if an entry existed at the offset.");
	stats.addMethod("int get_intVal() const", asMETHOD(StatReader,get_int))
		doc("Returns the stat's value as an integer.", "");
	stats.addMethod("float get_floatVal() const", asMETHOD(StatReader,get_float))
		doc("Returns the stat's value as a float.", "");
	stats.addMethod("uint get_time() const", asMETHOD(StatReader,get_time))
		doc("Returns the stat's timestamp in seconds from the start of the game.", "");
	
	stats.addMethod("bool advanceEvent()", asMETHOD(StatReader,advanceEvent))
		doc("Advances to the next event for the current stat.", "True if there was an event to advance to.");
	stats.addMethod("uint get_eventType() const", asMETHOD(StatReader,get_evt_type))
		doc("Returns the current event's type identifier.", "");
	stats.addMethod("string get_eventName() const", asMETHOD(StatReader,get_evt_name))
		doc("Returns the current event's name.", "");

	if(server) {
		emp.addMethod("void recordStat(stat::EmpireStat, int)", asMETHODPR(Empire,recordStat,(unsigned,int),void))
			doc("Records an int value for the specified empire stat at the current game time", "Stat index.", "Stat value.");
		emp.addMethod("void recordStat(stat::EmpireStat, float)", asMETHODPR(Empire,recordStat,(unsigned,float),void))
			doc("Records a float value for the specified empire stat at the current game time", "Stat index.", "Stat value.");
		emp.addMethod("void recordStatDelta(stat::EmpireStat, int)", asMETHODPR(Empire,recordStatDelta,(unsigned,int),void))
			doc("Records an int delta for the specified empire stat at the current game time", "Stat index.", "Stat delta.");
		emp.addMethod("void recordStatDelta(stat::EmpireStat, float)", asMETHODPR(Empire,recordStatDelta,(unsigned,float),void))
			doc("Records a float delta for the specified empire stat at the current game time", "Stat index.", "Stat delta.");
		emp.addMethod("void recordEvent(stat::EmpireStat, uint16, const string &in)", asMETHOD(Empire,recordEvent))
			doc("Records an event for the specified empire stat at the current game time", "Stat index.", "Event type.", "Event name.");
	}


	//Designs
	emp.addMember("ReadWriteMutex designMutex", offsetof(Empire, designMutex));
	emp.addExternMethod("uint get_designCount() const", asFUNCTION(getDesignCount));
	emp.addExternMethod("const Design@ getDesign(const string &in)", asFUNCTION(getDesignByName));
	emp.addExternMethod("const Design@ getDesign(int id)", asFUNCTION(getDesignById));
	emp.addExternMethod("const Design@ get_designs(int)", asFUNCTION(getDesignById));

	emp.addExternMethod("uint get_designClassCount() const", asFUNCTION(getDesignClassCount));
	emp.addMethod("const DesignClass@ getDesignClass(int id)", asMETHODPR(Empire, getDesignClass, (int), DesignClass*));
	emp.addMethod("const DesignClass@ getDesignClass(const string &in, bool add = true)", asMETHODPR(Empire, getDesignClass, (const std::string&, bool), DesignClass*));
	emp.addMethod("bool addDesign(const DesignClass& cls, const Design&)", asMETHOD(Empire, addDesign));
	emp.addMethod("bool changeDesign(const Design&, const Design&, const DesignClass@ cls = null)", asMETHODPR(Empire, changeDesign, (const Design*, const Design*, DesignClass*), bool));
	emp.addMethod("const Design@+ updateDesign(const Design&, bool onlyOutdated = false)", asMETHODPR(Empire, updateDesign, (const Design*, bool), const Design*));
	emp.addMethod("void flagDesignOld(const Design&)", asMETHODPR(Empire, flagDesignOld, (const Design*), void))
		doc("Marks a design as out of date, to be updated whenever it is requested for construction.", "");

	emp.addMethod("bool get_valid()", asMETHOD(Empire, valid));

	//Subsystem modifiers
	emp.addMember("ReadWriteMutex subsystemDataMutex", offsetof(Empire, subsystemDataMutex));
	emp.addExternMethod("bool isUnlocked(const SubsystemDef& sys, const ModuleDef& mod)", asFUNCTION(ssModUnlocked));
	emp.addExternMethod("bool isUnlocked(const SubsystemDef& sys)", asFUNCTION(ssUnlocked));
	emp.addExternMethod("void setUnlocked(const SubsystemDef& sys, const ModuleDef& mod, bool unlocked)", asFUNCTION(ssSetModUnlock));
	emp.addExternMethod("void setUnlocked(const SubsystemDef& sys, bool unlocked)", asFUNCTION(ssSetUnlock));
	emp.addExternMethod("void removeModifier(const SubsystemDef& sys, uint id)", asFUNCTION(removeModifier));

	emp.addExternMethod("void writeDelta(Message& msg)", asFUNCTION(writeDelta));
	emp.addExternMethod("void readDelta(Message& msg)", asFUNCTION(readDelta));

	std::string dargs;
	for(unsigned i = 0; i <= MODIFY_STAGE_MAXARGS; ++i) {
		emp.addGenericMethod(
				format("uint addModifier(const SubsystemDef& def, const string&in$1)", dargs).c_str(),
				asFUNCTION(addModifier_d));
		dargs += ", float";
	}

	//Global empire lists
	bindGlobal("Empire@ playerEmpire", &playerEmpire)
		doc("The player's current empire.");

	bindGlobal("Empire@ spectatorEmpire", &spectatorEmpire);
	bindGlobal("Empire@ defaultEmpire", &defaultEmpire);

	bind("uint getEmpireCount()", asFUNCTION(Empire::getEmpireCount));
	bind("Empire@ getEmpire(uint index)", asFUNCTION(Empire::getEmpireByIndex));
	bind("Empire@ getEmpireByID(uint8 id)", asFUNCTION(Empire::getEmpireByID));

	RegisterEmpireComponentWrappers(emp, server);
}

};
