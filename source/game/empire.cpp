#include "empire.h"
#include "empire_stats.h"
#include "compat/misc.h"
#include "design/design.h"
#include "main/logging.h"
#include "network/network_manager.h"
#include "main/references.h"
#include "network.h"
#include "assert.h"
#include "util/stat_history.h"
#include <vector>
#include "util/save_file.h"
#include "processing.h"

Empire* defaultEmpire = 0;
Empire* spectatorEmpire = 0;
Empire* playerEmpire = 0;
static std::vector<Empire*> empires;
const StateDefinition* empStates = 0;
static EmpMask nextMask = 2;
static unsigned char nextID = 0;

extern std::vector<SubsystemDef::ModifyStage*> ModifiersByID;

static const vec2i ICON_SIZE(64, 64);
static const vec2i SHEET_PAGE_SIZE(256, 256);
static const unsigned ICONS_PER_SHEET = 9;
static const unsigned ICON_SPACING = 2;

unsigned validEmpireCount;
EmpMask currentVision[32];

Empire* Empire::getDefaultEmpire() {
	return defaultEmpire;
}

Empire* Empire::getSpectatorEmpire() {
	return spectatorEmpire;
}

Empire* Empire::getPlayerEmpire() {
	return playerEmpire;
}

unsigned Empire::getEmpireCount() {
	return empires.size();
}

Empire* Empire::getEmpireByIndex(unsigned index) {
	if(index < empires.size())
		return empires[index];
	else
		return 0;
}

Empire* Empire::getEmpireByID(unsigned char id) {
	if(id == INVALID_EMPIRE)
		return 0;
	if(id == DEFAULT_EMPIRE)
		return defaultEmpire;
	if(id == SPECTATOR_EMPIRE)
		return spectatorEmpire;
	for(unsigned i = 0; i < empires.size(); ++i)
		if(empires[i]->id == id)
			return empires[i];
	return 0;
}

void Empire::setPlayerEmpire(Empire* emp) {
	playerEmpire = emp;
}
	
void* Empire::operator new(size_t size) {
	if(empStates)
		size += empStates->getSize(size);
	return ::operator new(size);
}

void Empire::clearEmpires() {
	for(auto emp = empires.begin(); emp != empires.end(); ++emp)
		delete *emp;
	empires.clear();

	delete defaultEmpire;
	defaultEmpire = 0;
	delete spectatorEmpire;
	spectatorEmpire = 0;
	playerEmpire = 0;

	nextMask = 2;
	nextID = 0;

	memset(currentVision, 0, sizeof(currentVision));
	validEmpireCount = 0;
}

void Empire::initEmpires() {
	if(!defaultEmpire)
		defaultEmpire = new Empire(DEFAULT_EMPIRE);
	if(!spectatorEmpire) {
		spectatorEmpire = new Empire(SPECTATOR_EMPIRE);
		spectatorEmpire->visionMask = ~0;
	}
}

void Empire::registerObject(Object* obj) {
	threads::WriteLock lock(objectLock);
	objects.push_back(obj);
	obj->grab();
}

void Empire::unregisterObject(Object* obj) {
	//TODO: Improve
	threads::WriteLock lock(objectLock);
	for(auto i = objects.begin(), end = objects.end(); i != end; ++i) {
		if(*i == obj) {
			obj->drop();
			objects.erase(i);
			break;
		}
	}
}

unsigned Empire::objectCount() {
	return objects.size();
}

Object* Empire::findObject(unsigned i) {
	threads::ReadLock lock(objectLock);
	if(i < objects.size())
		return objects[i];
	else
		return 0;
}

void Empire::setEmpireStates(const StateDefinition* states) {
	empStates = states;
}

const StateDefinition* Empire::getEmpireStates() {
	return empStates;
}

Empire::Empire(unsigned char ID) : index(-1), background(0), portrait(0), flag(0), flagID(0), player(0), hullIconIndex(0), validEmpIndex(0) {
	if(ID == INVALID_EMPIRE) {
		objects.reserve(1250);
		id = ++nextID;
		mask = nextMask;
		nextMask <<= 1;
	}
	else {
		mask = ID == DEFAULT_EMPIRE ? 1 : 0;
		id = ID;
	}
	visionMask = mask;
	hostileMask = 0;

	unsigned subsysCnt = getSubsystemDefCount();
	subsysData.resize(subsysCnt);
	for(unsigned i = 0; i < subsysCnt; ++i) {
		auto& data = subsysData[i];
		const SubsystemDef* def = getSubsystemDef(i);
		if(def->defaultUnlock)
			data.unlocked = true;
		data.modulesUnlocked.resize(def->modules.size());
		for(unsigned j = 0, jcnt = def->modules.size(); j < jcnt; ++j)
			data.modulesUnlocked[j] = def->modules[j]->defaultUnlock;
	}

	if(valid()) {
		statHistories.resize(getEmpireStatCount());
		for(unsigned i = 0; i < statHistories.size(); ++i)
			statHistories[i] = new StatHistory;
		statLocks.resize(statHistories.size());
	}

	if(empStates) {
		void* mixinMem = this + 1;
		empStates->prepare(mixinMem);
	}

	if(valid()) {
		empires.push_back(this);
		index = empires.size() - 1;
		validEmpIndex = validEmpireCount;
		currentVision[validEmpIndex] = mask;
		++validEmpireCount;
	}

	processing::startEmpireThread(this);
}

bool Empire::valid() {
	return id < UNLISTED_EMPIRE;
}

Empire::~Empire() {
	if(empStates) {
		void* mixinMem = this + 1;
		empStates->unprepare(mixinMem);
	}

	foreach(it, designIds)
		(*it)->drop();
	foreach(it, designClasses)
		delete it->second;
	foreach(it, objects)
		(*it)->drop();
	foreach(it, hullDistantIcons)
		delete *it;
	foreach(it, hullFleetIcons)
		delete *it;
	foreach(it, hullIcons) {
		delete (*it)->material.textures[0];
		delete *it;
	}
	foreach(it, hullImages)
		delete *it;
}

void Empire::cacheVision() {
	if(valid())
		currentVision[validEmpIndex] = visionMask;
}

extern threads::atomic_int remainingMessages;
void Empire::processMessages(unsigned maxMessages) {
	if(messages.empty())
		return;

	if(!processLock.try_lock())
		return;

	while(maxMessages-- && !messages.empty()) {
		msgLock.lock();
		EmpireMessage* msg = nullptr;
		if(!messages.empty()) {
			msg = messages.front();
			messages.pop_front();
		}
		msgLock.release();

		if(msg) {
			msg->process(this);
			delete msg;
		}
		--remainingMessages;
	}

	processLock.release();
}

void Empire::queueMessage(EmpireMessage* msg) {
	if(!msg)
		return;

	msgLock.lock();
	++remainingMessages;
	messages.push_back(msg);
	msgLock.release();
}

void Empire::recordStat(unsigned id, int value) {
	if(id < statHistories.size()) {
		threads::WriteLock lock(statLocks[id]);

		StatHistory* history = statHistories[id];

		StatEntry* entry = history->addStatEntry(unsigned(devices.driver->getGameTime()));
		entry->asInt = value;
	}
}

void Empire::recordStatDelta(unsigned id, int delta) {
	if(id < statHistories.size()) {
		threads::WriteLock lock(statLocks[id]);

		StatHistory* history = statHistories[id];

		unsigned time = unsigned(devices.driver->getGameTime());

		StatEntry* tail = history->getTail();
		if(tail && tail->time == time) {
			tail->asInt += delta;
		}
		else {
			StatEntry* entry = history->addStatEntry(time);
			entry->asInt = entry->prev ? entry->prev->asInt + delta : entry->asInt + delta;
		}
	}
}

void Empire::recordStat(unsigned id, float value) {
	if(id < statHistories.size()) {
		threads::WriteLock lock(statLocks[id]);

		StatHistory* history = statHistories[id];

		StatEntry* entry = history->addStatEntry(unsigned(devices.driver->getGameTime()));
		entry->asFloat = value;
	}
}

void Empire::recordStatDelta(unsigned id, float delta) {
	if(id < statHistories.size()) {
		threads::WriteLock lock(statLocks[id]);

		StatHistory* history = statHistories[id];

		unsigned time = unsigned(devices.driver->getGameTime());

		StatEntry* tail = history->getTail();
		if(tail && tail->time == time) {
			tail->asFloat += delta;
		}
		else {
			StatEntry* entry = history->addStatEntry(time);
			entry->asFloat = entry->prev ? entry->prev->asFloat + delta : entry->asFloat + delta;
		}
	}
}

void Empire::recordEvent(unsigned id, unsigned short type, const std::string& name) {
	if(id < statHistories.size()) {
		threads::WriteLock lock(statLocks[id]);

		StatHistory* history = statHistories[id];

		StatEntry* entry = history->getTail();
		if(!entry)
			entry = history->addStatEntry(unsigned(devices.driver->getGameTime()));
		entry->addEvent(type, name);
	}
}

const StatHistory* Empire::lockStatHistory(unsigned id) {
	if(id < statHistories.size()) {
		statLocks[id].readLock();
		return statHistories[id];
	}
	return 0;
}

void Empire::unlockStatHistory(unsigned id) {
	if(id < statHistories.size())
		statLocks[id].release();
}

bool Empire::addDesign(DesignClass* cls, const Design* design) {
	if(design->hasFatalErrors()) {
		error("Could not add design '%s', design has fatal errors:",
			design->name.c_str());
		for(auto i = design->errors.begin(), end = design->errors.end(); i != end; ++i)
			error("  %s", i->text.c_str());
		return false;
	}

	threads::WriteLock lock(designMutex);
	auto it = designs.find(design->name);
	if(it != designs.end())
		return false;

	design->owner = this;
	design->used = true;
	design->cls = cls;
	design->revision = 1;
	designs.insert(it, std::pair<std::string, const Design*>(design->name, design));
	cls->designs.push_back(design);

	design->grab();
	design->id = designIds.size();
	designIds.push_back(design);

	makeDesignIcon(design);

	if(devices.network->isServer || devices.network->isClient)
		devices.network->sendDesign(this, cls, design);

	return true;
}

bool Empire::changeDesign(const Design* older, const Design* newer, DesignClass* cls) {
	if(newer->hasFatalErrors()) {
		error("Could not update design '%s', new design has fatal errors.",
			newer->name.c_str());
		return false;
	}

	//TODO: Print sensible error messages
	if(older->owner != this || !older->used) {
		error("Could not update design '%s', old design not owned by this empire.",
			newer->name.c_str());
		return false;
	}

	threads::WriteLock lock(designMutex);
	setDesign(older, newer, cls);

	if(devices.network->isServer || devices.network->isClient)
		devices.network->sendDesignUpdate(this, older, newer, cls);

	return true;
}

void Empire::setDesign(const Design* older, const Design* newer, DesignClass* cls) {
	if(older->owner != this)
		return;
	threads::WriteLock lock(designMutex);
	if(older->original != nullptr)
		older = older->original;
	if(cls == nullptr)
		cls = older->cls;
	
	if(newer->id == (unsigned)-1) {
		newer->grab();
		newer->id = designIds.size();
		designIds.push_back(newer);
	}

	newer->owner = this;
	newer->used = true;
	newer->cls = cls;

	makeDesignIcon(newer);

	//Replace indicated older
	older->newer = newer;
	newer->revision = older->revision + 1;

	//Deal with changing name
	if(older->name == newer->name) {
		designs[older->name] = newer;

		if(cls == older->cls) {
			//Replace it in its class
			for(size_t i = 0, cnt = older->cls->designs.size(); i < cnt; ++i) {
				if(older->cls->designs[i]->base() == older) {
					older->cls->designs[i] = newer;
					break;
				}
			}
		}
		else {
			//Remove from previous class
			foreach(it, older->cls->designs) {
				if((*it)->base() == older) {
					older->cls->designs.erase(it);
					break;
				}
			}

			//Add to new class
			cls->designs.push_back(newer);
		}
	}
	else {
		//Remove previous from class
		foreach(it, older->cls->designs) {
			if((*it)->base() == older) {
				older->cls->designs.erase(it);
				break;
			}
		}

		//Also replace the design we're overwriting
		auto it = designs.find(newer->name);
		if(it != designs.end()) {
			const Design* other = it->second->base();
			other->newer = newer;
			newer->revision = std::max(newer->revision, other->revision + 1);

			designs[other->name] = newer;

			if(cls == other->cls) {
				//Replace it in its class too
				bool found = false;
				for(size_t i = 0, cnt = other->cls->designs.size(); i < cnt; ++i) {
					if(other->cls->designs[i]->base() == other) {
						other->cls->designs[i] = newer;
						found = true;
						break;
					}
				}

				if(!found) {
					//Add to new class
					cls->designs.push_back(newer);
				}
			}
			else {
				//Remove from previous class
				foreach(it, other->cls->designs) {
					if((*it)->base() == other) {
						other->cls->designs.erase(it);
						break;
					}
				}

				//Add to new class
				cls->designs.push_back(newer);
			}
		}
		else {
			designs[newer->name] = newer;

			//Add to class as new design
			cls->designs.push_back(newer);
		}
	}
}

const Design* Empire::updateDesign(const Design* dsg, bool onlyOutdated) {
	if(devices.network->isClient)
		return 0;
	if(dsg->owner != this)
		return dsg;
	if(!dsg->updated && !dsg->outdated && onlyOutdated)
		return dsg;

	threads::WriteLock lock(designMutex);

	//Mark all designs in this design path as no longer outdated
	while(true) {
		if(dsg->updated) {
			dsg->outdated = false;
			dsg = dsg->updated;
		}
		else {
			if(onlyOutdated && !dsg->outdated) {
				dsg->grab();
				return dsg;
			}
			dsg->outdated = false;
			break;
		}
	}

	Design::Descriptor desc;
	dsg->toDescriptor(desc);

	const Design* newDesign = new Design(desc);
	if(newDesign->hasFatalErrors()) {
		newDesign->drop();
		dsg->grab();
		return dsg;
	}

	setDesignUpdate(dsg, newDesign);

	if(devices.network->isServer)
		devices.network->sendDesignUpdate(this, dsg, newDesign);

	newDesign->grab();
	return newDesign;
}

void Empire::setDesignUpdate(const Design* dsg, const Design* newDesign) {
	dsg->updated = newDesign;
	newDesign->data = dsg->data;
	newDesign->clientData = dsg->clientData;
	newDesign->serverData = dsg->serverData;
	newDesign->original = dsg->original ? dsg->original.ptr : dsg;
	newDesign->revision = dsg->revision;
	newDesign->obsolete = dsg->obsolete;
	newDesign->distantIcon = dsg->distantIcon;
	newDesign->icon = dsg->icon;
	newDesign->fleetIcon = dsg->fleetIcon;

	if(newDesign->id == (unsigned)-1) {
		newDesign->id = designIds.size();
		designIds.push_back(newDesign); //transfer original ref
	}
	newDesign->owner = this;
	newDesign->used = true;
	newDesign->cls = dsg->cls;

	for(size_t i = 0, cnt = newDesign->cls->designs.size(); i < cnt; ++i) {
		if(newDesign->cls->designs[i]->base() == dsg->base()) {
			newDesign->cls->designs[i] = newDesign;
			break;
		}
	}

	auto it = designs.find(newDesign->name);
	if(it != designs.end()) {
		if(it->second->base() == newDesign->base())
			designs[newDesign->name] = newDesign;
	}
}

void Empire::flagDesignOld(const Design* design) {
	if(devices.network->isClient)
		return;
	//NOTE: This can use a readlock as outdated is only used by updateDesign which can't be writing at the same time
	threads::ReadLock lock(designMutex);
	design->mostUpdated()->outdated = true;
}

const Design* Empire::getDesign(const std::string& name, bool grab) {
	threads::ReadLock lock(designMutex);
	auto it = designs.find(name);
	if(it == designs.end())
		return 0;
	if(grab)
		it->second->grab();
	return it->second;
}

const Design* Empire::getDesign(unsigned id, bool grab) {
	threads::ReadLock lock(designMutex);
	if(id >= (unsigned)designIds.size())
		return 0;
	const Design* dsg = designIds[id];
	if(grab && dsg)
		dsg->grab();
	return dsg;
}

Design* Empire::getDesignMake(unsigned id) {
	threads::WriteLock lock(designMutex);
	unsigned cnt = designIds.size();
	if(id < cnt) {
		if(!designIds[id]) {
			Design* dsg = new Design();
			dsg->id = id;
			designIds[id] = dsg;
		}
		return (Design*)designIds[id];
	}
	else {
		designIds.resize(id+1);
		for(unsigned i = cnt; i < unsigned(id); ++i)
			designIds[i] = 0;
		Design* dsg = new Design();
		dsg->id = id;
		designIds[id] = dsg;
		return dsg;
	}
}

DesignClass* Empire::getDesignClass(int id) {
	threads::ReadLock lock(designMutex);
	if(id < (int)designClassIds.size())
		return designClassIds[id];
	else
		return 0;
}

DesignClass* Empire::getDesignClass(const std::string& name, bool add) {
	{
		threads::ReadLock lock(designMutex);
		auto it = designClasses.find(name);
		if(it != designClasses.end())
			return it->second;
	}

	if(add) {
		threads::WriteLock lock(designMutex);
		DesignClass* cls = new DesignClass;
		cls->id = designClassIds.size();
		designClassIds.push_back(cls);
		cls->name = name;
		designClasses[name] = cls;
		return cls;
	}
	else {
		return 0;
	}
}

void Empire::makeDesignIcon(const Design* design) {
	threads::WriteLock lock(designMutex);

	Image* img;
	render::SpriteSheet* sheet;
	render::SpriteSheet* distantSheet;
	render::SpriteSheet* fleetSheet;

	if(hullIcons.empty() || hullIconIndex >= ICONS_PER_SHEET) {
		hullIconIndex = 0;

		auto* tex = render::RenderDriver::createTexture();

		img = new Image(SHEET_PAGE_SIZE.x, SHEET_PAGE_SIZE.y, FMT_RGBA);
		memset(img->rgba, 0x00, sizeof(Color) * img->width * img->height);

		sheet = new render::SpriteSheet();
		sheet->material = devices.library.getMaterial("ShipIcon");
		sheet->width = ICON_SIZE.x;
		sheet->height = ICON_SIZE.y;
		sheet->spacing = ICON_SPACING;
		sheet->material.textures[0] = tex;
		hullIcons.push_back(sheet);

		distantSheet = new render::SpriteSheet();
		distantSheet->material = devices.library.getMaterial("ShipDistantIcon");
		distantSheet->width = ICON_SIZE.x;
		distantSheet->height = ICON_SIZE.y;
		distantSheet->material.textures[0] = tex;
		distantSheet->spacing = ICON_SPACING;
		hullDistantIcons.push_back(distantSheet);

		fleetSheet = new render::SpriteSheet();
		fleetSheet->material = devices.library.getMaterial("FleetIcon");
		fleetSheet->width = ICON_SIZE.x;
		fleetSheet->height = ICON_SIZE.y;
		fleetSheet->material.textures[0] = tex;
		fleetSheet->spacing = ICON_SPACING;
		hullFleetIcons.push_back(fleetSheet);

		hullImages.push_back(img);
	}
	else {
		sheet = hullIcons[hullIcons.size() - 1];
		distantSheet = hullDistantIcons[hullIcons.size() - 1];
		fleetSheet = hullFleetIcons[hullIcons.size() - 1];
		img = hullImages[hullIcons.size() - 1];
	}

	unsigned perLine = (SHEET_PAGE_SIZE.x - sheet->spacing) / (sheet->width + sheet->spacing);
	vec2i source(hullIconIndex % perLine, hullIconIndex / perLine);
	source.x = source.x * (sheet->width + sheet->spacing) + sheet->spacing;
	source.y = source.y * (sheet->height + sheet->spacing) + sheet->spacing;

	design->makeDistanceMap(*img, source, ICON_SIZE);

	int prior = -hullImages.size() * ICONS_PER_SHEET - hullIconIndex;
	resource::queueTextureUpdate(sheet->material.textures[0], new Image(*img), prior, sheet->material.mipmap);
	design->icon = render::Sprite(sheet, hullIconIndex);
	design->distantIcon = render::Sprite(distantSheet, hullIconIndex);
	design->fleetIcon = render::Sprite(fleetSheet, hullIconIndex);

	hullIconIndex += 1;
}

Empire::SubsystemData* Empire::getSubsystemData(const SubsystemDef* def) {
	if(def->index >= (int)subsysData.size())
		return 0;
	return &subsysData[def->index];
}

static inline void sendDetails(net::Message& msg, Empire& emp) {
	msg << emp.name;
	msg << emp.visionMask;
	msg << emp.hostileMask;
	msg << emp.color;
}

static inline void recvDetails(net::Message& msg, Empire& emp) {
	msg >> emp.name;
	msg >> emp.visionMask;
	msg >> emp.hostileMask;
	msg >> emp.color;
}

void Empire::sendDesign(net::Message& msg, const Design* dsg, bool fromServer) {
	msg.writeSmall(dsg->id);
	if(fromServer)
		dsg->writeData(msg);
	else
		dsg->write(msg);
}

Design* Empire::recvDesign(net::Message& msg, bool fromServer) {
	unsigned id = msg.readSmall();
	Design* dsg = getDesignMake(id);
	if(dsg->initialized)
		return dsg;

	if(fromServer) {
		dsg->initData(msg);
	}
	else {
		dsg->init(msg);
		dsg->used = true;
	}

	return dsg;
}

void Empire::SubsystemData::write(net::Message& msg) {
	msg.writeBit(unlocked);
	msg.writeSmall(modulesUnlocked.size());
	for(size_t i = 0, cnt = modulesUnlocked.size(); i < cnt; ++i)
		msg.writeBit(modulesUnlocked[i]);
	msg.writeSmall(stages.size());
	foreach(it, stages) {
		msg.writeSmall(it->first);
		msg.writeSmall(it->second.stage->index);
		for(size_t i = 0; i < MODIFY_STAGE_MAXARGS; ++i)
			msg << it->second.arguments[i];
	}
}

void Empire::SubsystemData::read(const SubsystemDef* def, net::Message& msg) {
	unlocked = msg.readBit();
	modulesUnlocked.resize(msg.readSmall());
	for(size_t i = 0, cnt = modulesUnlocked.size(); i < cnt; ++i)
		modulesUnlocked[i] = msg.readBit();

	unsigned stageCnt = msg.readSmall();
	stages.clear();
	for(unsigned i = 0; i < stageCnt; ++i) {
		unsigned id = msg.readSmall();
		unsigned index = msg.readSmall();
		if(index >= def->modifiers.size()) {
			assert(false);
			return;
		}

		SubsystemDef::AppliedStage as;
		as.stage = def->modifiers[index];
		for(size_t i = 0; i < MODIFY_STAGE_MAXARGS; ++i)
			msg >> as.arguments[i];

		stages[id] = as;
	}
}

void Empire::writeDelta(net::Message& msg) {
	threads::ReadLock lock(subsystemDataMutex);
	msg.writeAlign();
	auto pos = msg.reserve<unsigned>();
	unsigned amount = 0;
	for(unsigned i = 0, cnt = subsysData.size(); i < cnt; ++i) {
		if(subsysData[i].delta) {
			msg.writeSmall(i);
			subsysData[i].write(msg);
			subsysData[i].delta = false;
			++amount;
		}
	}
	msg.fill<unsigned>(pos, amount);
	for(unsigned i = 0, cnt = statHistories.size(); i < cnt; ++i) {
		auto* stat = lockStatHistory(i);
		if(!stat) {
			msg.write0();
			continue;
		}
		auto* s = stat->getTail();
		if(s) {
			msg.write1();
			msg << s->asInt;
		}
		else {
			msg.write0();
		}
		unlockStatHistory(i);
	}
}

void Empire::readDelta(net::Message& msg) {
	threads::WriteLock lock(subsystemDataMutex);
	msg.readAlign();

	unsigned amount = 0;
	msg >> amount;
	for(unsigned i = 0; i < amount; ++i) {
		unsigned index = msg.readSmall();
		if(index >= subsysData.size()) {
			assert(false);
			return;
		}

		subsysData[index].read(getSubsystemDef(index), msg);
	}

	for(unsigned i = 0, cnt = statHistories.size(); i < cnt; ++i) {
		if(!msg.readBit())
			continue;
		if(statIsint(i))
			recordStat(i, msg.readIn<int>());
		else
			recordStat(i, msg.readIn<float>());
	}
}

void Empire::sendInitial(net::Message& msg) {
	assert(devices.network->isServer);
	
	//Write static data
	msg << id;
	msg << mask;
	
	unsigned shipsetID = shipset ? shipset->id : 0;
	msg << shipsetID;

	//Write other data
	sendDetails(msg, *this);

	//Write designs
	unsigned clsCnt = designClassIds.size();
	msg.writeSmall(clsCnt);
	for(unsigned i = 0; i < clsCnt; ++i) {
		DesignClass* cls = designClassIds[i];
		msg << cls->name;
	}

	unsigned dsgCnt = designIds.size();
	msg.writeSmall(dsgCnt);
	for(unsigned j = 0; j < dsgCnt; ++j) {
		const Design* dsg = designIds[j];
		sendDesign(msg, dsg, true);
	}

	//Write subsystem data
	for(unsigned i = 0, cnt = subsysData.size(); i < cnt; ++i)
		subsysData[i].write(msg);

	for(unsigned i = 0, cnt = statHistories.size(); i < cnt; ++i) {
		auto& stat = *lockStatHistory(i);
		bool isInt = statIsint(i);

		unsigned lastTime = 0;

		int prevInt = 0;
		float fMin = 0.f, fMax = 128.f;

		auto* s = stat.getHead();
		while(s) {
			msg.write1();
			unsigned dT = s->time - lastTime;
			if(dT < 15)
				msg.writeLimited(dT, 0, 15);
			else {
				msg.writeLimited(15, 0, 15);
				msg.writeSmall(dT-15);
			}
			lastTime = s->time;
			if(isInt) {
				msg.writeSignedSmall(s->asInt - prevInt);
				prevInt = s->asInt;
			}
			else {
				float v = s->asFloat;
				if(v >= fMin && v <= fMax) {
					msg.write0();
					msg.writeFixed(v, fMin, fMax, 10);
				}
				else {
					msg.write1();
					msg << v;
					if(v < fMin)
						fMin = v - 64.f - v/16.f;
					if(v > fMax)
						fMax = v + 64.f + v/16.f;
				}
			}

			auto* e = s->evt;
			while(e) {
				msg.write1();
				msg << e->type;
				msg << e->name;
				e = e->next;
			}
			msg.write0();

			s = s->next;
		}
		msg.write0();

		unlockStatHistory(i);
	}
}

Empire* recvEmpireInitial(net::Message& msg) {
	assert(devices.network->isClient);
	Empire* emp = new Empire();
	
	//Receive static data
	msg >> emp->id;
	msg >> emp->mask;

	emp->shipset = getShipset(msg.readIn<unsigned>());

	//Receive other data
	recvDetails(msg, *emp);

	//Receive designs
	unsigned clsCnt = msg.readSmall();
	for(unsigned i = 0; i < clsCnt; ++i) {
		DesignClass* cls = new DesignClass;
		cls->id = emp->designClassIds.size();
		msg >> cls->name;

		emp->designClassIds.push_back(cls);
		emp->designClasses[cls->name] = cls;
	}

	unsigned dsgCnt = msg.readSmall();
	for(unsigned j = 0; j < dsgCnt; ++j) {
		Design* dsg = emp->recvDesign(msg, true);

		if(!dsg->original || dsg->original == dsg) {
			emp->makeDesignIcon(dsg);
		}
		else if(dsg->original) {
			dsg->icon = dsg->original->icon;
			dsg->distantIcon = dsg->original->distantIcon;
			dsg->fleetIcon = dsg->original->fleetIcon;
		}

		if(!dsg->newer && !dsg->updated)
			dsg->cls->designs.push_back(dsg);
		if(!dsg->updated)
			emp->designs[dsg->name] = dsg;
	}

	for(unsigned i = 0, cnt = emp->subsysData.size(); i < cnt; ++i)
		emp->subsysData[i].read(getSubsystemDef(i), msg);

	for(unsigned i = 0, cnt = emp->statHistories.size(); i < cnt; ++i) {
		auto& stat = *(StatHistory*)emp->lockStatHistory(i);
		if(&stat == 0)
			break;
		bool isInt = statIsint(i);

		unsigned lastTime = 0;

		int prevInt = 0;
		float fMin = 0.f, fMax = 128.f;

		while(msg.readBit()) {
			unsigned dT = msg.readLimited(0, 15);
			if(dT == 15)
				dT = msg.readSmall() + 15;

			auto* s = stat.addStatEntry(lastTime + dT);
			lastTime = s->time;

			if(isInt) {
				s->asInt = prevInt + msg.readSignedSmall();
				prevInt = s->asInt;
			}
			else {
				if(!msg.readBit()) {
					s->asFloat = msg.readFixed(fMin, fMax, 10);
				}
				else {
					float v = msg.readIn<float>();
					s->asFloat = v;
					if(v < fMin)
						fMin = v - 64.f - v/16.f;
					if(v > fMax)
						fMax = v + 64.f + v/16.f;
				}
			}

			while(msg.readBit()) {
				unsigned short id = 0;
				std::string text;
				msg >> id >> text;
				s->addEvent(id, text);
			}

			s = s->next;
		}

		emp->unlockStatHistory(i);
	}

	info("Received empire '%s' (%d).",
		emp->name.c_str(), emp->id);

	return emp;
}

Empire::Empire(SaveFile& file) : background(0), portrait(0), flag(0), flagID(0), player(0) {
	file >> id >> index >> name >> mask >> visionMask >> hostileMask >> color;
	file >> backgroundDef >> portraitDef >> flagDef;
	if(file >= SFV_0019)
		file >> flagID;

	if(valid()) {
		validEmpIndex = validEmpireCount;
		currentVision[validEmpIndex] = visionMask;
		++validEmpireCount;
	}

	//Push this empire immediately so designs can locate us
	empires.push_back(this);

	if(empStates) {
		void* mixinMem = this + 1;
		empStates->prepare(mixinMem);
	}

	file.boundary();

	//Load owned objects
	unsigned objectCount = file;
	objects.resize(objectCount);
	for(unsigned i = 0; i < objectCount; ++i)
		file >> objects[i];

	if(file < SFV_0004)
		shipset = getShipset("Original_r3000");
	else
		shipset = getShipset(file.readIdentifier(SI_Shipset));

	if(file >= SFV_0007)
		file >> effectorSkin;

	//Load designs
	unsigned dsgnCount = file;
	designIds.resize(dsgnCount, 0);
	for(unsigned i = 0; i < designIds.size(); ++i) {
		Design* design = new Design(file);
		designIds[i] = design;
		designs[design->name] = design;
		if(i != design->id) {
			//Try and fix old saves. probably futile in most situations.
			design->id = i;
		}
	}

	//Load design classes
	unsigned dsgnClassCount = file;
	designClassIds.reserve(dsgnClassCount);
	for(unsigned i = 0; i < dsgnClassCount; ++i) {
		DesignClass* dsgnClass = new DesignClass;
		dsgnClass->id = designClassIds.size();
		designClassIds.push_back(dsgnClass);
		file >> dsgnClass->name;
		designClasses[dsgnClass->name] = dsgnClass;

		unsigned classDesignCount = file;
		dsgnClass->designs.reserve(classDesignCount);

		for(unsigned j = 0; j < classDesignCount; ++j) {
			int designID = file;
			const Design* dsg = getDesign(designID);
			if(dsg)
				dsgnClass->designs.push_back(dsg);
		}
	}

	//Load design links
	for(unsigned i = 0; i < designIds.size(); ++i) {
		Design* dsg = (Design*)designIds[i];

		unsigned id;
		file >> id;
		if(id < designClassIds.size())
			dsg->cls = designClassIds[id];
		else
			dsg->cls = designClassIds[0];

		file >> id;
		if(id == (unsigned)-1 || id >= designIds.size())
			dsg->newer = nullptr;
		else
			dsg->newer = designIds[id];

		file >> id;
		if(id == (unsigned)-1 || id >= designIds.size())
			dsg->updated = nullptr;
		else
			dsg->updated = designIds[id];

		file >> id;
		if(id == (unsigned)-1 || id >= designIds.size())
			dsg->original = nullptr;
		else
			dsg->original = designIds[id];

		if(!dsg->original || dsg->original == dsg) {
			makeDesignIcon(dsg);
		}
		else if(dsg->original) {
			dsg->icon = dsg->original->icon;
			dsg->distantIcon = dsg->original->distantIcon;
			dsg->fleetIcon = dsg->original->fleetIcon;

			dsg->data = dsg->original->data;
			dsg->clientData = dsg->original->clientData;
			dsg->serverData = dsg->original->serverData;
		}
	}

	file.boundary();

	//Initialize subsystem data
	unsigned subsysCnt = getSubsystemDefCount();
	subsysData.resize(subsysCnt);
	for(unsigned i = 0; i < subsysCnt; ++i) {
		auto& data = subsysData[i];
		const SubsystemDef* def = getSubsystemDef(i);
		if(def->defaultUnlock)
			data.unlocked = true;
		data.modulesUnlocked.resize(def->modules.size());
		for(unsigned j = 0, jcnt = def->modules.size(); j < jcnt; ++j)
			data.modulesUnlocked[j] = def->modules[j]->defaultUnlock;
	}

	//Load subsystem data
	unsigned cnt = file;
	for(unsigned n = 0; n < cnt; ++n) {
		int i = file.readIdentifier(SI_Subsystem);
		if(i == -1)
			throw SaveFileError("Subsystem was removed.");

		SubsystemData& dat = subsysData[i];
		file >> dat.unlocked;
		file >> dat.nextStageId;

		unsigned modCnt = file;
		dat.modulesUnlocked.resize(modCnt);
		for(unsigned j = 0; j < modCnt; ++j)
			dat.modulesUnlocked[j] = (bool)file;

		//Assumptions: empire stages are always
		//from modifiers in the subsystem root,
		//and cannot have formula modifiers.
		// (Currently satisfied)
		const SubsystemDef* def = getSubsystemDef(i);
		unsigned stageCnt = file;
		for(unsigned j = 0; j < stageCnt; ++j) {
			SubsystemDef::AppliedStage stg;
			unsigned id = file;
			unsigned index = 0;
			if(file >= SFV_0015) {
				unsigned uid = (unsigned)file.readIdentifier(SI_SubsystemModifier);
				if(uid < ModifiersByID.size())
					index = ModifiersByID[uid]->index;
				else
					index = (unsigned)-1;
			}
			else
				index = file;
			file.read(stg.arguments, MODIFY_STAGE_MAXARGS * sizeof(float));

			if(index >= def->modifiers.size())
				continue;
			stg.stage = def->modifiers[index];
			dat.stages[id] = stg;
		}
	}
	
	statHistories.resize(getEmpireStatCount());
	statLocks.resize(statHistories.size());
	for(unsigned i = 0; i < statHistories.size(); ++i)
		statHistories[i] = new StatHistory();

	if(file >= SFV_0014) {
		unsigned count = 0;
		file >> count;

		while(count--) {
			std::string name;
			file >> name;

			StatHistory* stat = nullptr;
			StatEntry dummy;
			StatEvent evt;

			auto getEntry = [&](unsigned time) -> StatEntry* {
				if(stat)
					return stat->addStatEntry(time);
				else
					return &dummy;
			};

			auto addEvent = [&](StatEntry* entry, const std::string& text, unsigned short id) {
				if(stat)
					entry->addEvent(id, text);
			};

			unsigned index = getStatID(name);
			if(index < statHistories.size())
				stat = statHistories[index];

			while(true) {
				unsigned time = 0;
				file >> time;
				if(time == 0xffffffff)
					break;

				auto* h = getEntry(time);
				file >> h->asInt;

				while(true) {
					unsigned short evtID = 0;
					file >> evtID;
					if(evtID == 0xffff)
						break;

					std::string text;
					file >> text;
					addEvent(h, text, evtID);
				}
			}
			
		}
	}

	file.boundary();

	bool isPlayer = file;
	if(isPlayer) {
		playerEmpire = this;
		devices.network->currentPlayer.emp = playerEmpire;
		devices.network->currentPlayer.controlMask = playerEmpire->mask;
		devices.network->currentPlayer.viewMask = playerEmpire->mask;
	}

	processing::startEmpireThread(this);
}

void Empire::save(SaveFile& file) {
	file << id << index << name << mask << visionMask << hostileMask << color;
	file << backgroundDef << portraitDef << flagDef << flagID;

	file.boundary();

	//Save owned objects
	file << unsigned(objects.size());
	for(unsigned i = 0; i < objects.size(); ++i) {
		Object* obj = objects[i];
		file << obj;
	}

	if(shipset)
		file.writeIdentifier(SI_Shipset, shipset->id);
	else
		file.writeIdentifier(SI_Shipset, (unsigned)-1);

	file << effectorSkin;

	//Save designs
	file << unsigned(designIds.size());
	for(unsigned i = 0; i < designIds.size(); ++i) {
		designIds[i]->save(file);
	}

	//Save design classes
	file << unsigned(designClassIds.size());
	for(unsigned i = 0; i < designClassIds.size(); ++i) {
		DesignClass* dsgnClass = designClassIds[i];
		file << dsgnClass->name;

		file << unsigned(dsgnClass->designs.size());
		for(unsigned j = 0; j < dsgnClass->designs.size(); ++j)
			file << dsgnClass->designs[j]->id;
	}

	//Save design links
	for(unsigned i = 0; i < designIds.size(); ++i) {
		const Design* dsg = designIds[i];
		file << dsg->cls->id;

		if(dsg->newer)
			file << dsg->newer->id;
		else
			file << (unsigned)-1;

		if(dsg->updated)
			file << dsg->updated->id;
		else
			file << (unsigned)-1;

		if(dsg->original)
			file << dsg->original->id;
		else
			file << (unsigned)-1;
	}

	file.boundary();

	//Save subsystem data
	unsigned cnt = subsysData.size();
	file << cnt;
	for(unsigned i = 0; i < cnt; ++i) {
		SubsystemData& dat = subsysData[i];
		file.writeIdentifier(SI_Subsystem, i);
		file << dat.unlocked;
		file << dat.nextStageId;

		unsigned modCnt = dat.modulesUnlocked.size();
		file << modCnt;
		for(unsigned j = 0; j < modCnt; ++j)
			file << (bool)dat.modulesUnlocked[j];

		//Assumptions: empire stages are always
		//from modifiers in the subsystem root,
		//and cannot have formula modifiers.
		// (Currently satisfied)
		unsigned stageCnt = dat.stages.size();
		file << stageCnt;
		foreach(it, dat.stages) {
			file << it->first;
			auto& stg = it->second;
			file.writeIdentifier(SI_SubsystemModifier, stg.stage->umodifid);
			file.write(stg.arguments, MODIFY_STAGE_MAXARGS * sizeof(float));
		}
	}

	cnt = statHistories.size();
	file << cnt;

	unsigned statID = 0;
	for(auto i = statHistories.begin(), end = statHistories.end(); i != end; ++i, ++statID) {
		StatHistory& stat = **i;

		file << getEmpireStatName(statID);

		auto* s = stat.getHead();
		while(s) {
			file << s->time;
			file << s->asInt;
			auto* e = s->evt;
			while(e) {
				file << e->type;
				file << e->name;
				e = e->next;
			}
			unsigned short evtEnd = 0xffff;
			file << evtEnd;

			s = s->next;
		}

		unsigned statEnd = 0xffffffff;
		file << statEnd;
	}

	file.boundary();
	
	file << (playerEmpire == this);
}

void Empire::saveEmpires(SaveFile& file) {
	file << unsigned(empires.size());

	for(unsigned i = 0; i < empires.size(); ++i)
		empires[i]->save(file);
}

void Empire::loadEmpires(SaveFile& file) {
	initEmpires();
	unsigned empireCount = file;

	for(unsigned i = 0; i < empireCount; ++i)
		new Empire(file);
	if(playerEmpire == nullptr)
		playerEmpire = spectatorEmpire;
}
