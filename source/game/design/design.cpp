#include "design/design.h"
#include "empire.h"
#include "network/message.h"
#include "util/save_file.h"
#include "main/references.h"
#include "main/logging.h"
#include "util/format.h"
#include "network/message.h"
#include <unordered_map>
#include <algorithm>
#include <queue>
#include <assert.h>

Design::Design(const Design::Descriptor& desc)
	: hull(0), stateCount(0), effectorStateCount(0), dataCount(0), effectorCount(0),
		initialized(false), id(-1), owner(0), used(false), obsolete(false), outdated(false), revision(0), cls(0), totalHP(0), forceHull(false), data(nullptr), clientData(nullptr), serverData(nullptr) {
	init(desc);
}

Design::Design(net::Message& msg)
	: hull(0), stateCount(0), effectorStateCount(0), dataCount(0), effectorCount(0),
		initialized(false), id(-1), owner(0), used(false), obsolete(false), outdated(false), revision(0), cls(0), totalHP(0), forceHull(false), data(nullptr), clientData(nullptr), serverData(nullptr) {
	init(msg);
}

Design::Design()
	: hull(0), stateCount(0), effectorStateCount(0), dataCount(0), effectorCount(0),
		initialized(false), id(-1), owner(0), used(false), obsolete(false), outdated(false), revision(0), cls(0), totalHP(0), forceHull(false), data(nullptr), clientData(nullptr), serverData(nullptr) {
}

void Design::init(const Design::Descriptor& desc) {
	if(desc.hull == nullptr)
		throw "Null Hull@ when creating design";

	//Make an appropriate hull
	HullDef* dynHull = nullptr;
	if(!desc.staticHull) {
		vec2i gridSize = desc.gridSize;
		dynHull = new HullDef(*desc.hull);
		dynHull->baseHull = desc.hull->baseHull;
		hull = dynHull;

		dynHull->activeCount = 0;
		dynHull->exteriorCount = 0;

		dynHull->gridSize = gridSize;
		dynHull->gridOffset = recti();

		dynHull->active.resize(gridSize.x, gridSize.y);
		dynHull->active.clear(false);

		dynHull->exterior.resize(gridSize.x, gridSize.y);
		dynHull->exterior.clear(0);
		dynHull->exteriorCount = 0;

		//Add all used hexes to the dynamic hull
		foreach(it, desc.systems) {
			for(size_t i = 0, cnt = it->hexes.size(); i < cnt; ++i) {
				vec2u v = it->hexes[i];
				if(dynHull->active.valid(v)) {
					dynHull->active[v] = true;
					dynHull->activeCount += 1;

					if(it->type->passExterior)
						dynHull->exterior[v] |= HullDef::flagExteriorPass;
					if(it->type->fauxExterior)
						dynHull->exterior[v] |= HullDef::flagExteriorFaux;
				}
			}
		}

		dynHull->calculateExterior();

		//Check for connectedness
		if(!dynHull->checkConnected()) {
			std::string errMsg = devices.locale.localize("ERROR_NOT_CONNECTED");
			errors.push_back(DesignError(true, errMsg));
		}
	}
	else {
		hull = desc.hull;
		hull->grab();
	}

	//Take over simple data
	size = desc.size;
	name = desc.name;
	owner = desc.owner;
	forceHull = desc.forceHull;
	initialized = true;
	numTags.insert(hull->numTags.begin(), hull->numTags.end());

	if(owner && owner->shipset && !owner->shipset->hasHull(hull->baseHull)) {
		std::string errMsg = devices.locale.localize("ERROR_HULL_NOT_IN_SHIPSET");
		errors.push_back(DesignError(true, errMsg));
	}

	if(size < hull->minSize) {
		std::string errMsg = format(devices.locale.localize("ERROR_MINIMUM_SIZE").c_str(),
			hull->name, hull->minSize);
		errors.push_back(DesignError(true, errMsg));
	}
	else if(hull->maxSize > 0 && size > hull->maxSize) {
		std::string errMsg = format(devices.locale.localize("ERROR_MAXIMUM_SIZE").c_str(),
			hull->name, hull->maxSize);
		errors.push_back(DesignError(true, errMsg));
	}

	//Lock the things we need
	if(owner)
		owner->subsystemDataMutex.readLock();

	grid.resize(hull->gridSize);
	grid.clear(-1);

	hexIndex.resize(hull->gridSize);
	hexIndex.clear(-1);

	hexStatusIndex.resize(hull->gridSize);
	hexStatusIndex.clear(-1);

	if(hull->activeCount != 0)
		hexSize = size / (double)hull->activeCount;
	else
		hexSize = 0.0;
	interiorHexes = 0;
	exteriorHexes = 0;
	usedHexCount = 0;
	totalHP = 0.0;
	for(unsigned i = 0; i < 4; ++i)
		quadrantTotalHP[i] = 0.0;

	//Add subsystems from the hull
	std::vector<Descriptor::System> systems = desc.systems;
	foreach(it, hull->subsystems) {
		auto* type = getSubsystemDef(*it);

		if(type) {
			Descriptor::System sys;
			sys.type = type;
			sys.hexes.push_back(vec2u(-1, -1));
			sys.modules.push_back(type->defaultModule);

			systems.push_back(sys);
		}
	}

	//Add applied subsystems
	int appliedTag = desc.appliedSystems.empty() ? -1 : getSysTagIndex("Applied");
	for(size_t i = 0, cnt = desc.appliedSystems.size(); i < cnt; ++i) {
		auto* type = desc.appliedSystems[i];
		if(type) {
			Descriptor::System sys;
			sys.type = type;
			sys.hexes.push_back(vec2u(-1, -1));
			sys.modules.push_back(type->defaultModule);

			systems.push_back(sys);

			if(!type->hasTag(appliedTag)) {
				std::string errMsg = format(devices.locale.localize("ERROR_CANNOT_APPLY").c_str(), type->name);
				errors.push_back(DesignError(true, errMsg));
			}
			else {
				for(unsigned n = 0, ncnt = type->getTagValueCount(appliedTag); n < ncnt; ++n) {
					std::string tag = type->getTagValue(appliedTag, n);
					for(size_t j = 0; j < i; ++j) {
						if(desc.appliedSystems[j] && desc.appliedSystems[j]->hasTagValue(appliedTag, tag)) {
							std::string errMsg = format(devices.locale.localize("ERROR_ONE_APPLIED").c_str(), devices.locale.localize(format("APPLIED_$1", tag)));
							errors.push_back(DesignError(true, errMsg));
						}
					}
				}

			}
		}
	}

	//Initialize subsystems
	HexGrid<bool> connected(grid.width, grid.height);
	subsystems.resize(systems.size());

	cropMin = vec2u(grid.width, grid.height);
	cropMax = vec2u(0, 0);

	for(unsigned index = 0; index < systems.size(); ++index) {
		const Design::Descriptor::System& sd = systems[index];
		if(!sd.type)
			break;

		numTags.insert(sd.type->numTags.begin(), sd.type->numTags.end());
		Subsystem* sys = &subsystems[index];
		sys->init(*sd.type);
		sys->inDesign = this;
		sys->index = index;
		sys->direction = sd.direction;
		sys->hexes.reserve(sd.hexes.size());
		sys->stateOffset = stateCount;
		sys->effectorOffset = effectorCount;

		auto modCnt = sys->type->modules.size();
		sys->moduleCounts.resize(modCnt);
		for(size_t i = 0; i < modCnt; ++i)
			sys->moduleCounts[i] = 0;

		//Set up effector states
		int effStates = 0;
		for(size_t i = 0, cnt = sd.type->effectors.size(); i < cnt; ++i) {
			sys->effectors[i].stateOffset = effectorStateCount;
			effStates += sd.type->effectors[i].type->stateCount;
		}

		//Copy hexes
		int hexInd = 0;
		for(size_t i = 0, cnt = sd.hexes.size(); i < cnt; ++i) {
			vec2u v = sd.hexes[i];
			auto* mod = sd.modules[i];
			if(!mod)
				mod = sys->type->defaultModule;

			if(!sd.type->isHull && !sd.type->isApplied) {
				if(v.x >= grid.width || v.y >= grid.height)
					continue;
				if(!hull->active[v])
					continue;
				if(grid[v] != -1)
					continue;

				if(hull->isExterior(v)) {
					++sys->exteriorHexes;
					++exteriorHexes;
				}
				else {
					++interiorHexes;
				}

				grid[v] = index;
				hexIndex[v] = hexInd++;
				hexStatusIndex[v] = usedHexCount++;

				cropMin.x = std::min(cropMin.x, v.x);
				cropMin.y = std::min(cropMin.y, v.y);
				cropMax.x = std::max(cropMax.x, v.x);
				cropMax.y = std::max(cropMax.y, v.y);
			}

			sys->hexes.push_back(v);
			sys->modules.push_back(mod);
			hexes.push_back(v);

			++sys->moduleCounts[mod->index];
		}

		unsigned efftrCount = (unsigned)sd.type->effectors.size();
		for(unsigned i = 0; i < efftrCount; ++i) {
			sys->effectors[i].inDesign = this;
			sys->effectors[i].subsysIndex = sys->index;
		}

		stateCount += (unsigned)sd.type->states.size();
		effectorCount += efftrCount;
		effectorStateCount += effStates;

		if(sys->type->isContiguous && !sys->type->isHull && !sys->type->isApplied && !sys->hexes.empty()) {
			connected.zero();
			sys->markConnected(connected, sys->hexes[0]);
			for(size_t i = 1, cnt = sys->hexes.size(); i < cnt; ++i) {
				if(!connected[sys->hexes[i]]) {
					std::string errMsg = format(devices.locale.localize("ERROR_NOT_CONTIGUOUS").c_str(), sys->type->name);
					errors.push_back(DesignError(true, errMsg, sys));
					sys->hasErrors = true;
					break;
				}
			}
		}
	}

	//Prepare ship variables
	unsigned shipVarCnt = getShipVariableCount();
	shipVariables = new float[shipVarCnt];
	memset(shipVariables, 0, shipVarCnt * sizeof(float));

	//Store calculated hex size
	if((unsigned)ShV_HexSize < shipVarCnt)
		shipVariables[ShV_HexSize] = hexSize;

	//Evaluate subsystem variables
	std::priority_queue<std::pair<int,Subsystem*>> sysQueue;

	foreach(it, subsystems)
		sysQueue.push(std::pair<int,Subsystem*>(-it->type->ordering, &*it));

	Colorf colf(0.f, 0.f, 0.f, 0.f);

	while(!sysQueue.empty()) {
		auto* sys = sysQueue.top().second;
		sys->initVariables(this);
		sysQueue.pop();

		float* sysSize = sys->variable(SV_Size);
		if(sysSize) {
			float relSize = *sysSize / (float)size;
			Colorf sysColor(sys->type->typeColor);
			sysColor *= sysColor.a;
			sysColor.a = 1.f;
			colf += sysColor * (relSize * relSize);
		}
	}

	colf.a = 1.f;
	float hue = colf.getHue();

	colf.fromHSV(hue, 1.f, 1.f);
	color = Color(colf);

	colf.fromHSV(hue, 0.6f, 0.6f);
	dullColor = Color(colf);

	//Evaluate adjacency mods
	foreach(it, subsystems)
		it->applyAdjacencies(this);

	//Evaluate subsystem asserts
	foreach(it, subsystems)
		it->evaluateAsserts(this);

	//Evaluate subsystem posts
	foreach(it, subsystems)
		it->evaluatePost(this);

	//Evaluate subsystem effects
	foreach(it, subsystems) {
		it->initEffects(this);
		if(owner)
			it->skinEffectors(*owner);

		it->dataOffset = dataCount;
		dataCount += it->hookClasses.size();
	}

	//Calculate total HP
	foreach(it, subsystems) {
		auto& sys = *it;
		unsigned hexCnt = (unsigned)sys.hexes.size();
		for(unsigned j = 0; j < hexCnt; ++j) {
			float* hexVal = sys.hexVariable(HV_HP, j);
			if(hexVal) {
				totalHP += *hexVal;
				quadrantTotalHP[getQuadrant(sys.hexes[j])] += *hexVal;
			}
		}
	}

	//Record possibly altered hex size
	if((unsigned)ShV_HexSize < shipVarCnt)
		hexSize = shipVariables[ShV_HexSize];

	//Unlock the things we locked
	if(owner)
		owner->subsystemDataMutex.release();

	//Create a secondary damage order list for globalDamage events
	buildDamageOrder();
}

void Design::buildDamageOrder() {
	damageOrder.clear();
	foreach(it, subsystems) {
		auto* sys = &*it;
		if(sys->hasGlobalDamage())
			damageOrder.push_back(sys);
	}
	std::sort(damageOrder.begin(), damageOrder.end(), [](Subsystem* first, Subsystem* second) -> bool {
		return first->type->damageOrder < second->type->damageOrder;
	});
}

bool Design::hasFatalErrors() const {
	foreach(it, errors)
		if(it->fatal)
			return true;
	return false;
}

bool Design::hasTag(const std::string& tag) const {
	foreach(it, subsystems)
		if(it->type->hasTag(tag))
			return true;
	return false;
}

bool Design::hasTag(int index) const {
	auto it = numTags.find(index);
	return it != numTags.end();
}

const Design* Design::newest() const {
	const Design* cur = this;
	if(original)
		cur = original;
	while(cur->newer)
		cur = cur->newer;
	while(cur->updated)
		cur = cur->updated;
	return cur;
}

const Design* Design::next() const {
	if(original)
		return original->newer;
	return newer;
}

const Design* Design::mostUpdated() const {
	const Design* cur = this;
	while(cur->updated)
		cur = cur->updated;
	return cur;
}

const Design* Design::base() const {
	return original ? original.ptr : this;
}

Design::~Design() {
	delete[] shipVariables;
	hull->drop();
	
	if(original == nullptr || original == this) {
		if(data) {
			delete data;
			data = nullptr;
		}
		if(clientData) {
			clientData->Release();
			clientData = nullptr;
		}
		if(serverData) {
			serverData->Release();
			serverData = nullptr;
		}
	}
}

unsigned Design::getQuadrant(const vec2u& pos) const {
	unsigned quad = 0;
	int dist = pos.y - cropMin.y;

	int d = cropMax.x - pos.x;
	if(d < dist) {
		quad = 1;
		dist = d;
	}

	d = cropMax.y - pos.y;
	if(d < dist) {
		quad = 2;
		dist = d;
	}

	d = pos.x - cropMin.x;
	if(d < dist) {
		quad = 3;
		dist = d;
	}

	return quad;
}

void Design::makeDistanceMap(Image& img, vec2i pos, vec2i size) const {
	int xspac = 1;
	int yspac = 1 + ceil(double(size.y) * 0.1);

	double xrat = double(size.x-xspac-xspac) / double(hull->active.width) / 0.75;
	double yrat = double(size.y-yspac-yspac) / double(hull->active.height);
	double distFact = 40.0 / yrat;

	for(int y = yspac; y < size.y-yspac; ++y) {
		for(int x = xspac; x < size.x-xspac; ++x) {
			vec2d pctPos(double(x-xspac) / double(size.x-xspac-xspac), double(y-yspac) / double(size.y-yspac-yspac));
			vec2d grid(double(x-xspac) / xrat, double(y-yspac) / yrat);
			vec2i gridPos = hull->active.getGridPosition(grid);

			double dist = 100.0;

			if(hull->active.valid(gridPos) && hull->active[gridPos]) {
				vec2d gridPct = hull->active.getEffectivePosition(gridPos);
				gridPct.x += 0.75 * 0.5;
				gridPct.y += 0.5;
				gridPct.x /= 0.75 * double(hull->active.width);
				gridPct.y /= double(hull->active.height);
				dist = std::min(pctPos.distanceTo(gridPct), dist);
			}
			
			for(unsigned i = 0; i < 6; ++i) {
				vec2u pos = vec2u(gridPos);
				if(hull->active.advance(pos.x, pos.y, (HexGridAdjacency)i)) {
					if(hull->active.valid(pos) && hull->active[pos]) {
						vec2d gridPct = hull->active.getEffectivePosition(pos);
						gridPct.x += 0.75 * 0.5;
						gridPct.y += 0.5;
						gridPct.x /= 0.75 * double(hull->active.width);
						gridPct.y /= double(hull->active.height);
						dist = std::min(pctPos.distanceTo(gridPct), dist);
					}
				}
			}

			Color& col = img.get_rgba(x+pos.x, pos.y+y);
			col.color = 0xff0000ff;
			dist *= distFact;

			if(dist < 0.8)
				col.a = 0xff;
			else
				col.a = 0x00;

			if(dist > 0.6 && dist < 1.5)
				col.b = 0xff;
			else
				col.b = 0x00;

			if(dist < 0.5)
				col.g = 0xff;
			else
				col.g = 255.0 * std::max(1.0 - (dist-0.5)*2.0, 0.0);
		}
	}
}

void Design::toDescriptor(Design::Descriptor& desc) const {
	desc.owner = owner;
	desc.hull = hull;
	if(hull)
		hull->grab();
	desc.name = name;
	desc.size = size;
	desc.forceHull = forceHull;
	desc.gridSize = hull->gridSize;

	if(cls)
		desc.className = cls->name;
	else
		desc.className = "";

	unsigned short sysCnt = (unsigned short)subsystems.size();
	desc.systems.reserve(sysCnt);
	for(unsigned short i = 0; i < sysCnt; ++i) {
		auto& sys = subsystems[i];
		if(sys.type->isHull)
			continue;
		if(sys.type->isApplied) {
			desc.appliedSystems.push_back(sys.type);
			continue;
		}

		desc.systems.push_back(Design::Descriptor::System());
		Design::Descriptor::System& sdesc = desc.systems.back();
		sdesc.direction = sys.direction;
		sdesc.type = sys.type;

		unsigned short hexCnt = (unsigned short)sys.hexes.size();
		sdesc.hexes.resize(hexCnt);
		sdesc.modules.resize(hexCnt);

		for(unsigned short j = 0; j < hexCnt; ++j) {
			sdesc.hexes[j] = sys.hexes[j];
			sdesc.modules[j] = sys.modules[j];
		}
	}
}

void Design::write(net::Message& msg) const {
	if(owner)
		msg << owner->id;
	else
		msg << INVALID_EMPIRE;
	msg.writeSmall(hull->baseHull->id);
	msg << name;
	msg << size;
	msg << forceHull;
	msg << obsolete;
	msg << revision;
	msg.writeSmall(hull->gridSize.width);
	msg.writeSmall(hull->gridSize.height);

	msg.writeSmall((unsigned)subsystems.size());
	for(unsigned i = 0, sysCnt = (unsigned)subsystems.size(); i < sysCnt; ++i) {
		auto& sys = subsystems[i];
		if(sys.type->isHull) {
			msg.writeSignedSmall(-1);
			continue;
		}
		msg.writeSignedSmall(sys.type->index);
		if(sys.type->isApplied)
			continue;

		msg.writeDirection(sys.direction.x, sys.direction.y, sys.direction.z);

		msg.writeSmall((unsigned)sys.hexes.size());

		vec2u gridSize = vec2u(hull->gridSize);
		for(unsigned short j = 0, hexCnt = (unsigned)sys.hexes.size(); j < hexCnt; ++j) {
			vec2u pos = sys.hexes[j];
			msg.writeLimited(pos.x, gridSize.width);
			msg.writeLimited(pos.y, gridSize.height);
			msg.writeSignedSmall(sys.modules[j]->index);
		}
	}

	//Script data
	if(data != nullptr) {
		msg.write1();

		char* pData; net::msize_t size;
		data->getAsPacket(pData, size);

		msg.writeSmall(size);
		msg.write(pData, size);
	}
	else {
		msg.write0();
	}
}

void Design::init(net::Message& msg) {
	Descriptor desc;

	//Read empire
	unsigned char empID;
	msg >> empID;
	desc.owner = Empire::getEmpireByID(empID);

	//Read hull
	desc.hull = getHullDefinition(msg.readSmall());
	if(desc.hull)
		desc.hull->grab();

	//Get other blueprint data
	msg >> desc.name;
	msg >> desc.size;
	msg >> desc.forceHull;
	msg >> obsolete;
	msg >> revision;

	desc.gridSize.x = msg.readSmall();
	desc.gridSize.y = msg.readSmall();

	//Read subsystems
	unsigned sysCnt = msg.readSmall();
	desc.systems.reserve(sysCnt);

	for(unsigned i = 0; i < sysCnt; ++i) {
		int sysIndex = msg.readSignedSmall();
		if(sysIndex == -1)
			continue;
		auto* type = getSubsystemDef(sysIndex);
		if(type->isApplied) {
			desc.appliedSystems.push_back(type);
			continue;
		}

		desc.systems.push_back(Design::Descriptor::System());
		Design::Descriptor::System& sys = desc.systems.back();
		sys.type = type;
		msg.readDirection(sys.direction.x, sys.direction.y, sys.direction.z);
		
		unsigned hexCnt = msg.readSmall();
		sys.hexes.resize(hexCnt);
		sys.modules.resize(hexCnt);
		for(unsigned j = 0; j < hexCnt; ++j) {
			unsigned x = msg.readLimited(desc.gridSize.width);
			unsigned y = msg.readLimited(desc.gridSize.height);
			sys.hexes[j] = vec2u(x, y);

			int modIndex = msg.readSignedSmall();

			if(sys.type == 0 || modIndex < 0 || modIndex >= (int)sys.type->modules.size())
				sys.modules[j] = 0;
			else
				sys.modules[j] = sys.type->modules[modIndex];
		}
	}

	//Initialize design
	init(desc);

	//Script data
	if(msg.readBit()) {
		net::msize_t size = msg.readSmall();
		data = new net::Message();
		if(size > 0) {
			char* buffer = (char*)malloc(size);
			msg.read(buffer, size);
			data->setPacket(buffer, size);
			free(buffer);
		}
		bindData();
	}
}

static asIScriptObject* buildDataForEngine(scripts::Manager* man, void* msg, unsigned call) {
	//Create the object
	asITypeInfo* cls = man->getClass("design_settings", "DesignSettings");
	if(cls == nullptr)
		return nullptr;

	asIScriptFunction* func = cls->GetFactoryByIndex(0);
	if(!func)
		return nullptr;

	asIScriptObject* ptr = 0;
	{
		scripts::Call cl = man->call(func);
		cl.call(ptr);
		if(ptr)
			ptr->AddRef();
	}

	//Read the mesasge
	auto* readFunc = (asIScriptFunction*)man->engine->GetUserData(call);
	if(ptr && readFunc) {
		scripts::Call cl = man->call(readFunc);
		cl.setObject(ptr);
		cl.push(msg);
		cl.call();
	}

	return ptr;
}

void Design::bindData() {
	if(data) {
		data->rewind();
		clientData = buildDataForEngine(devices.scripts.client, data, scripts::EDID_SerializableRead);
		data->rewind();
		serverData = buildDataForEngine(devices.scripts.server, data, scripts::EDID_SerializableRead);
		data->rewind();
	}
}

Design::Design(SaveFile& file) : initialized(true), data(nullptr), clientData(nullptr), serverData(nullptr) {
	file >> name >> size >> hexSize >> interiorHexes >> exteriorHexes
		 >> stateCount >> effectorStateCount >> effectorCount >> usedHexCount
		 >> used >> obsolete >> id >> revision >> totalHP >> color >> dullColor;
	if(file >= SFV_0002)
		file >> outdated;
	else
		outdated = false;
	built.set_basic(file);
	active.set_basic(file);

	if(file >= SFV_0008)
		file >> dataCount;
	else
		dataCount = 0;

	if(file >= SFV_0016)
		file >> forceHull;
	else
		forceHull = false;

	unsigned hullID;
	if(file >= SFV_0004) {
		hullID = file.readIdentifier(SI_Hull);
	}
	else {
		unsigned oldID = file;
		auto* set = getShipset("Original_r3000");
		hullID = set->hulls[oldID]->id;
	}

	hull = getHullDefinition(hullID);
	if(hull == 0)
		throw SaveFileError("Design lacks hull");
	numTags.insert(hull->numTags.begin(), hull->numTags.end());

	owner = Empire::getEmpireByID(file);
	if(owner == 0)
		throw SaveFileError("Design lacks owner");
	//if(owner->shipset && !owner->shipset->hasHull(hull))
	//	throw SaveFileError("Hull is not present in the owner's shipset");

	if(file >= SFV_0013) {
		bool dynamic = file;
		if(dynamic) {
			auto* dynHull = new HullDef(*hull);

			file >> dynHull->gridSize;
			file >> dynHull->activeCount;
			file >> dynHull->exteriorCount;

			dynHull->gridOffset = recti();
			dynHull->active.resize(dynHull->gridSize.x, dynHull->gridSize.y);
			dynHull->active.clear(false);

			dynHull->exterior.resize(dynHull->gridSize.x, dynHull->gridSize.y);
			dynHull->exterior.clear(0);

			for(size_t i = 0, cnt = dynHull->active.length(); i < cnt; ++i) {
				file >> dynHull->active[i];
				file >> dynHull->exterior[i];
			}

			dynHull->baseHull = hull;
			hull = dynHull;
		}
		else {
			hull->grab();
		}
	}
	else {
		hull->grab();
	}

	//Hex grids
	grid.resize(hull->gridSize);
	hexIndex.resize(hull->gridSize);
	hexStatusIndex.resize(hull->gridSize);

	file.read(grid.data, sizeof(int) * grid.width * grid.height);
	file.read(hexIndex.data, sizeof(int) * hexIndex.width * hexIndex.height);
	file.read(hexStatusIndex.data, sizeof(int) * hexStatusIndex.width * hexStatusIndex.height);

	unsigned hexesCount = file;
	hexes.resize(hexesCount);
	file.read(hexes.data(), sizeof(vec2u) * hexesCount);

	cropMin = vec2u(grid.width, grid.height);
	cropMax = vec2u(0, 0);
	foreach(h, hexes) {
		if(hull->active.valid(*h)) {
			cropMin.x = std::min(cropMin.x, h->x);
			cropMin.y = std::min(cropMin.y, h->y);
			cropMax.x = std::max(cropMax.x, h->x);
			cropMax.y = std::max(cropMax.y, h->y);
		}
	}

	unsigned shipVarCount = getShipVariableCount();
	shipVariables = new float[shipVarCount]();

	unsigned cnt = file;
	for(unsigned i = 0; i < cnt; ++i) {
		int index = file.readIdentifier(SI_ShipVar);
		if(index != -1)
			file >> shipVariables[index];
		else
			file.read<float>();
	}

	//Subsystems
	unsigned subsysCount = file;
	subsystems.resize(subsysCount);
	for(unsigned i = 0; i < subsysCount; ++i) {
		auto& sys = subsystems[i];
		sys.init(file);
		sys.inDesign = this;
		sys.index = i;

		auto efftrcnt = sys.type->effectors.size();
		for(size_t j = 0; j < efftrcnt; ++j) {
			sys.effectors[j].inDesign = this;
			sys.effectors[j].subsysIndex = i;
		}

		numTags.insert(sys.type->numTags.begin(), sys.type->numTags.end());
	}

	if(file >= SFV_0020) {
		for(unsigned i = 0; i < 4; ++i)
			file >> quadrantTotalHP[i];
	}
	else {
		for(unsigned i = 0; i < 4; ++i)
			quadrantTotalHP[i] = 0.0;
		foreach(it, subsystems) {
			auto& sys = *it;
			unsigned hexCnt = (unsigned)sys.hexes.size();
			for(unsigned j = 0; j < hexCnt; ++j) {
				float* hexVal = sys.hexVariable(HV_HP, j);
				if(hexVal)
					quadrantTotalHP[getQuadrant(sys.hexes[j])] += *hexVal;
			}
		}
	}

	for(unsigned i = 0; i < subsysCount; ++i)
		subsystems[i].postLoad(this);

	//Script data
	if(file >= SFV_0018) {
		if(file.read<bool>()) {
			unsigned size = file;
			SaveMessage msg(file);
			if(size > 0) {
				char* buffer = (char*)malloc(size);
				file.read(buffer, size);
				msg.setPacket(buffer, size);
				free(buffer);
			}

			serverData = buildDataForEngine(devices.scripts.server, &msg, scripts::EDID_SavableRead);

			data = new net::Message();
			auto* writeFunc = (asIScriptFunction*)devices.scripts.server->engine->GetUserData(scripts::EDID_SerializableWrite);
			if(writeFunc) {
				scripts::Call cl = devices.scripts.server->call(writeFunc);
				cl.setObject(serverData);
				cl.push(data);
				cl.call();
			}

			clientData = buildDataForEngine(devices.scripts.client, data, scripts::EDID_SerializableRead);
		}
	}

	buildDamageOrder();
}

void Design::save(SaveFile& file) const {
	file << name << size << hexSize << interiorHexes << exteriorHexes
		 << stateCount << effectorStateCount << effectorCount << usedHexCount
		 << used << obsolete << id << revision << totalHP << color << dullColor;
	file << outdated;
	file << built.get() << active.get();
	file << dataCount;
	file << forceHull;

	file.writeIdentifier(SI_Hull, hull->baseHull->id);
	file << owner->id;

	if(hull != hull->baseHull) {
		file << true;
		file << hull->gridSize;
		file << hull->activeCount << hull->exteriorCount;
		for(size_t i = 0, cnt = hull->active.length(); i < cnt; ++i) {
			file << hull->active[i];
			file << hull->exterior[i];
		}
	}
	else
		file << false;

	//Hex grids
	file.write(grid.data, sizeof(int) * grid.width * grid.height);
	file.write(hexIndex.data, sizeof(int) * hexIndex.width * hexIndex.height);
	file.write(hexStatusIndex.data, sizeof(int) * hexStatusIndex.width * hexStatusIndex.height);

	file << (unsigned)hexes.size();
	file.write(hexes.data(), sizeof(vec2u) * (unsigned)hexes.size());

	unsigned cnt = getShipVariableCount();
	file << cnt;
	for(unsigned i = 0; i < cnt; ++i) {
		file.writeIdentifier(SI_ShipVar, i);
		file << shipVariables[i];
	}

	//Subsystems
	file << unsigned(subsystems.size());
	for(unsigned i = 0; i < subsystems.size(); ++i)
		subsystems[i].save(file);

	for(unsigned i = 0; i < 4; ++i)
		file << quadrantTotalHP[i];

	//Script data
	if(serverData != nullptr && (original == nullptr || original == this)) {
		SaveMessage msg(file);
		auto* writeFunc = (asIScriptFunction*)devices.scripts.server->engine->GetUserData(scripts::EDID_SavableWrite);
		if(writeFunc) {
			file << true;

			{
				scripts::Call cl = devices.scripts.server->call(writeFunc);
				cl.setObject(serverData);
				cl.push(&msg);
				cl.call();
			}

			char* pData; net::msize_t size;
			msg.getAsPacket(pData, size);

			file << size;
			file.write(pData, size);
		}
		else {
			file << false;
		}
	}
	else {
		file << false;
	}
}

void Design::writeData(net::Message& msg) const {
	msg.writeSmall(hull->baseHull->id);
	msg << name;
	msg << size;
	msg << hexSize;
	msg.writeSmall(interiorHexes);
	msg.writeSmall(exteriorHexes);
	msg.writeSmall(usedHexCount);
	msg.writeSmall(stateCount);
	msg.writeSmall(effectorStateCount);
	msg.writeSmall(effectorCount);
	msg << initialized;
	msg << totalHP;
	for(unsigned i = 0; i < 4; ++i)
		msg << quadrantTotalHP[i];
	msg << color;
	msg << dullColor;
	msg << forceHull;

	if(hull != hull->baseHull) {
		msg.write1();
		msg.writeSmall(hull->gridSize.x);
		msg.writeSmall(hull->gridSize.y);
	}
	else {
		msg.write0();
	}

	msg.writeSmall((unsigned)numTags.size());
	foreach(it, numTags)
		msg.writeSmall(*it);

	msg.writeSmall((unsigned)subsystems.size());
	foreach(it, subsystems)
		it->writeData(msg);

	for(unsigned i = 0, cnt = (unsigned)grid.length(); i < cnt; ++i) {
		if(grid[i] == -1) {
			msg.write0();
		}
		else {
			msg.write1();
			msg.writeSmall(grid[i]);
		}

		if(hexIndex[i] == -1) {
			msg.write0();
		}
		else {
			msg.write1();
			msg.writeSmall(hexIndex[i]);
		}

		if(hexStatusIndex[i] == -1) {
			msg.write0();
		}
		else {
			msg.write1();
			msg.writeSmall(hexStatusIndex[i]);
		}
	}

	msg.writeSmall((unsigned)hexes.size());
	foreach(it, hexes) {
		msg.writeSmall(it->x);
		msg.writeSmall(it->y);
	}

	for(size_t i = 0, cnt = getShipVariableCount(); i < cnt; ++i)
		msg << shipVariables[i];

	msg << id;
	msg.writeSmall(owner->id);
	msg << used;
	msg << obsolete;
	msg << revision;
	msg.writeSmall(built.get());
	msg.writeSmall(active.get());

	if(newer) {
		msg.write1();
		msg.writeSmall(newer->id);
	}
	else {
		msg.write0();
	}

	if(original) {
		msg.write1();
		msg.writeSmall(original->id);
	}
	else {
		msg.write0();
	}

	if(updated) {
		msg.write1();
		msg.writeSmall(updated->id);
	}
	else {
		msg.write0();
	}

	msg << cls->name;

	//Script data
	if(data != nullptr) {
		msg.write1();

		char* pData; net::msize_t size;
		data->getAsPacket(pData, size);

		msg.writeSmall(size);
		msg.write(pData, size);
	}
	else {
		msg.write0();
	}
}

void Design::initData(net::Message& msg) {
	hull = getHullDefinition(msg.readSmall());
	msg >> name;
	msg >> size;
	msg >> hexSize;
	interiorHexes = msg.readSmall();
	exteriorHexes = msg.readSmall();
	usedHexCount = msg.readSmall();
	stateCount = msg.readSmall();
	effectorStateCount = msg.readSmall();
	effectorCount = msg.readSmall();
	dataCount = 0;
	msg >> initialized;
	msg >> totalHP;
	for(unsigned i = 0; i < 4; ++i)
		msg >> quadrantTotalHP[i];
	msg >> color;
	msg >> dullColor;
	msg >> forceHull;

	HullDef* dynHull = nullptr;
	if(msg.readBit()) {
		dynHull = new HullDef(*hull);
		dynHull->baseHull = hull;
		hull = dynHull;

		dynHull->gridSize.x = msg.readSmall();
		dynHull->gridSize.y = msg.readSmall();

		dynHull->activeCount = 0;
		dynHull->exteriorCount = 0;

		dynHull->gridOffset = recti();

		dynHull->active.resize(dynHull->gridSize.x, dynHull->gridSize.y);
		dynHull->active.clear(false);

		dynHull->exterior.resize(dynHull->gridSize.x, dynHull->gridSize.y);
		dynHull->exterior.clear(0);
	}


	unsigned cnt = msg.readSmall();
	for(unsigned i = 0; i < cnt; ++i)
		numTags.insert(msg.readSmall());

	subsystems.resize(msg.readSmall());
	for(size_t i = 0, cnt = subsystems.size(); i < cnt; ++i) {
		auto* sys = &subsystems[i];
		sys->~Subsystem();
		new(sys) Subsystem(msg);
		sys->inDesign = this;
		sys->index = (unsigned)i;

		unsigned efftrCount = (unsigned)sys->type->effectors.size();
		for(unsigned n = 0; n < efftrCount; ++n) {
			sys->effectors[n].inDesign = this;
			sys->effectors[n].subsysIndex = (unsigned)i;
			sys->effectors[n].effectorIndex = n;
		}
	}

	grid.resize(hull->gridSize);
	hexIndex.resize(hull->gridSize);
	hexStatusIndex.resize(hull->gridSize);
	for(unsigned i = 0, cnt = (unsigned)grid.length(); i < cnt; ++i) {
		if(msg.readBit()) {
			grid[i] = msg.readSmall();
			assert(grid[i] < 0 || grid[i] < (int)subsystems.size());
		}
		else
			grid[i] = -1;

		if(msg.readBit())
			hexIndex[i] = msg.readSmall();
		else
			hexIndex[i] = -1;

		if(msg.readBit())
			hexStatusIndex[i] = msg.readSmall();
		else
			hexStatusIndex[i] = -1;
	}

	cropMin = vec2u(grid.width, grid.height);
	cropMax = vec2u(0, 0);

	hexes.resize(msg.readSmall());
	for(size_t i = 0, cnt = hexes.size(); i < cnt; ++i) {
		hexes[i].x = msg.readSmall();
		hexes[i].y = msg.readSmall();

		if(dynHull) {
			if(dynHull->active.valid(hexes[i]))
				dynHull->active[hexes[i]] = true;
		}

		if(hull->active.valid(hexes[i])) {
			cropMin.x = std::min(cropMin.x, hexes[i].x);
			cropMin.y = std::min(cropMin.y, hexes[i].y);
			cropMax.x = std::max(cropMax.x, hexes[i].x);
			cropMax.y = std::max(cropMax.y, hexes[i].y);
		}
	}

	shipVariables = new float[getShipVariableCount()];
	for(size_t i = 0, cnt = getShipVariableCount(); i < cnt; ++i)
		msg >> shipVariables[i];

	msg >> id;
	unsigned ownerId = msg.readSmall();
	owner = Empire::getEmpireByID(ownerId);
	msg >> used;
	msg >> obsolete;
	msg >> revision;

	built = msg.readSmall();
	active = msg.readSmall();

	if(msg.readBit())
		newer = owner->getDesignMake(msg.readSmall());

	if(msg.readBit())
		original = owner->getDesignMake(msg.readSmall());

	if(msg.readBit())
		updated = owner->getDesignMake(msg.readSmall());

	std::string clsname;
	msg >> clsname;
	cls = owner->getDesignClass(clsname);

	if(dynHull)
		dynHull->calculateExterior();

	//Script data
	if(msg.readBit()) {
		net::msize_t size = msg.readSmall();
		data = new net::Message();
		if(size > 0) {
			char* buffer = (char*)malloc(size);
			msg.read(buffer, size);
			data->setPacket(buffer, size);
			free(buffer);
		}
		bindData();
	}

	buildDamageOrder();
}
