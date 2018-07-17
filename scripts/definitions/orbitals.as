#priority init 1000
import saving;
import hooks;
import system_pathing;
import resources;
import tile_resources;
#section server-side
from regions.regions import getRegion;
import SystemDesc@ getSystem(Region@ region) from "game_start";
#section all

export OrbitalModule, OrbitalSection;
export getOrbitalModule, getOrbitalModuleCount;
export OrbitalRequirements;
export OrbitalValues, canBuildOrbital;

array<OrbitalModule@> modules;
dictionary idents;

enum OrbitalValues {
	OV_DRY_Design,
	OV_DRY_Progress,
	OV_DRY_Financed,
	OV_DRY_Free,
	OV_DRY_SetFinanced,
	OV_DRY_ModLabor,
	OV_DRY_ETA,
	OV_PackUp,
	OV_Trade,
	OV_FRAME_Usable,
	OV_FRAME_CostFactor,
	OV_FRAME_LaborFactor,
	OV_FRAME_LaborPenaltyFactor,
	OV_FRAME_Target,
};

bool canBuildOrbital(Object@ obj, const vec3d& pos, bool initial = true) {
	//Find target system
	Region@ target = getRegion(pos);
	if(target is null)
		return false;

	//Cannot build without vision
	if(initial && target.MemoryMask & obj.owner.mask == 0 && target.VisionMask & obj.owner.visionMask == 0)
		return false;

	//Check trade pathing
	if(initial || !obj.isShip) {
		if(obj.region is null)
			return false;
		TradePath path(obj.owner);
		path.generate(getSystem(obj.region), getSystem(target));
		if(!path.isUsablePath)
			return false;
	}
	return true;
}

tidy final class OrbitalModule {
	uint id;
	string ident;
	string name;
	string blurb;
	string description;
	Sprite icon;

	Sprite distantIcon;
	Sprite strategicIcon;
	double iconSize = 0.035;
	const Material@ material;
	const Model@ model;
	double size = 10.0;

	int maintenance = 0;
	int buildCost = 0;
	double laborCost = 0;

	double health = 0;
	double armor = 0;
	double spin = 30.0;
	double mass = -1.0;

	bool isCore = true;
	bool isSolid = true;
	bool isStandalone = true;
	bool isUnique = true;

	bool combatRepair = true;
	bool canFling = true;

	array<IOrbitalEffect@> hooks;
	array<Hook@> ai;

	array<uint> affinities(TR_COUNT, 0);
	array<const ResourceType@> requirements;
	uint totalRequirementCount = 0;

	bool canBuildBy(Object@ obj, bool ignoreCost = true) const {
		if(!isCore)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canBuildBy(obj, ignoreCost))
				return false;
		}
		return true;
	}

	bool canBuildAt(Object@ obj, const vec3d& pos) const {
		if(!isCore)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canBuildAt(obj, pos))
				return false;
		}
		return true;
	}

	bool canBuild(Object@ obj, const vec3d& pos, bool initial = true) const {
		if(!canBuildBy(obj))
			return false;
		if(!canBuildAt(obj, pos))
			return false;
		if(!canBuildOrbital(obj, pos, initial))
			return false;
		return true;
	}

	bool canBuildOn(Orbital& orbital) const {
		if(isCore)
			return false;
		if(isUnique) {
			if(orbital.hasModule(id))
				return false;
		}
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canBuildOn(orbital))
				return false;
		}
		return true;
	}

	bool checkRequirements(OrbitalRequirements@ reqs, bool apply) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].checkRequirements(reqs, apply)) {
				if(apply) {
					for(uint n = 0; n < i; ++n)
						hooks[n].revertRequirements(reqs);
				}
				return false;
			}
		}
		return true;
	}

	string getTooltip() const {
		string tip = format("[font=Medium][img=$2;32/] $1[/font]\n$3",
			name, getSpriteDesc(icon), description);
		bool reqs = false;
		for(uint i = 0; i < TR_COUNT; ++i) {
			if(affinities[i] > 0) {
				if(!reqs) {
					tip += "\n";
					reqs = true;
				}

				tip += "\n";
				tip += format(locale::ORB_REQ_AFFINITY,
					affinities[i], getTileResourceName(i),
					getTileResourceSpriteSpec(i));
			}
		}
		for(uint i = 0, cnt = requirements.length; i < cnt; ++i) {
			if(!reqs) {
				tip += "\n";
				reqs = true;
			}

			tip += "\n";
			tip += format(locale::ORB_REQ_RESOURCE,
				requirements[i].name, getSpriteDesc(requirements[i].icon));
		}
		return tip;
	}
};

interface IOrbitalEffect {
	void onEnable(Orbital& obj, any@ data) const;
	void onDisable(Orbital& obj, any@ data) const;
	void onCreate(Orbital& obj, any@ data) const;
	void onDestroy(Orbital& obj, any@ data) const;
	void onTick(Orbital& obj, any@ data, double time) const;
	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const;
	void onRegionChange(Orbital& obj, any@ data, Region@ prevRegion, Region@ newRegion) const;
	void onMakeGraphics(Orbital& obj, any@ data, OrbitalNode@ node) const;
	bool checkRequirements(OrbitalRequirements@ reqs, bool apply) const;
	void revertRequirements(OrbitalRequirements@ reqs) const;
	bool canBuildBy(Object@ obj, bool ignoreCost = true) const;
	bool canBuildAt(Object@ obj, const vec3d& pos) const;
	bool canBuildOn(Orbital& obj) const;
	string getBuildError(Object@ obj, const vec3d& pos) const;
	bool shouldDisable(Orbital& obj, any@ data) const;
	bool shouldEnable(Orbital& obj, any@ data) const;
	void save(any@ data, SaveFile& file) const;
	void load(any@ data, SaveFile& file) const;
	void onKill(Orbital& obj, any@ data, Empire@ killedBy) const;
	void write(any@ data, Message& msg) const;
	void read(any@ data, Message& msg) const;
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const;
	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const;
	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const;
	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const;
	bool getObject(Player& pl, Orbital& obj, any@ data, uint index, Object@& value) const;
	bool sendObject(Player& pl, Orbital& obj, any@ data, uint index, Object@ value) const;
	bool getData(Orbital& obj, string& txt, bool enabled) const;
	bool getCost(Object& obj, string& value, Sprite& icon) const;
	bool consume(Object& obj) const;
	void reverse(Object& obj, bool cancel) const;
};

class OrbitalEffect : Hook, IOrbitalEffect {
	void onEnable(Orbital& obj, any@ data) const {}
	void onDisable(Orbital& obj, any@ data) const {}
	void onCreate(Orbital& obj, any@ data) const {}
	void onDestroy(Orbital& obj, any@ data) const {}
	void onTick(Orbital& obj, any@ data, double time) const {}
	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {}
	void onRegionChange(Orbital& obj, any@ data, Region@ prevRegion, Region@ newRegion) const {}
	void onMakeGraphics(Orbital& obj, any@ data, OrbitalNode@ node) const {}
	bool checkRequirements(OrbitalRequirements@ reqs, bool apply) const { return true; }
	void revertRequirements(OrbitalRequirements@ reqs) const {}
	bool canBuildBy(Object@ obj, bool ignoreCost) const { return true; }
	bool canBuildAt(Object@ obj, const vec3d& pos) const { return true; }
	bool canBuildOn(Orbital& obj) const { return true; }
	string getBuildError(Object@ obj, const vec3d& pos) const { return ""; }
	bool shouldDisable(Orbital& obj, any@ data) const { return false; }
	bool shouldEnable(Orbital& obj, any@ data) const { return true; }
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}
	void write(any@ data, Message& msg) const {}
	void read(any@ data, Message& msg) const {}
	void onKill(Orbital& obj, any@ data, Empire@ killedBy) const {}
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const { return false; }
	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const { return false; }
	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const { return false; }
	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const { return false; }
	bool getObject(Player& pl, Orbital& obj, any@ data, uint index, Object@& value) const { return false; }
	bool sendObject(Player& pl, Orbital& obj, any@ data, uint index, Object@ value) const { return false; }
	bool getData(Orbital& obj, string& txt, bool enabled) const { return false; }
	bool getCost(Object& obj, string& value, Sprite& icon) const { return false; }
	bool consume(Object& obj) const { return true; }
	void reverse(Object& obj, bool cancel) const {}
};

tidy final class OrbitalSection : Serializable, Savable {
	const OrbitalModule@ type;
	int id = -1;
	array<any> data;
	bool enabled = true;

	OrbitalSection() {
	}

	OrbitalSection(const OrbitalModule@ type) {
		@this.type = type;
		data.length = type.hooks.length;
	}

	void write(Message& msg) {
		msg.writeSmall(type.id);
		msg.writeSmall(id);
		msg.writeBit(enabled);
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].write(data[i], msg);
	}

	void read(Message& msg) {
		@type = getOrbitalModule(msg.readSmall());
		id = msg.readSmall();
		enabled = msg.readBit();
		data.length = type.hooks.length;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].read(data[i], msg);
	}

	OrbitalSection(SaveFile& file) {
		load(file);
	}

	void save(SaveFile& file) {
		file << id;
		file.writeIdentifier(SI_Orbital, type.id);
		file << enabled;
		if(enabled) {
			for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
				type.hooks[i].save(data[i], file);
		}
	}

	void load(SaveFile& file) {
		file >> id;
		@type = getOrbitalModule(file.readIdentifier(SI_Orbital));
		file >> enabled;
		data.length = type.hooks.length;
		if(enabled) {
			for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
				type.hooks[i].load(data[i], file);
		}
	}

	void enable(Orbital& obj) {
		enabled = true;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onEnable(obj, data[i]);
	}

	void disable(Orbital& obj) {
		enabled = false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onDisable(obj, data[i]);
	}

	void create(Orbital& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onCreate(obj, data[i]);
	}

	void destroy(Orbital& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onDestroy(obj, data[i]);
	}

	void tick(Orbital& obj, double time) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onTick(obj, data[i], time);
	}

	void ownerChange(Orbital& obj, Empire@ prevOwner, Empire@ newOwner) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onOwnerChange(obj, data[i], prevOwner, newOwner);
	}

	void regionChange(Orbital& obj, Region@ prevRegion, Region@ newRegion) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onRegionChange(obj, data[i], prevRegion, newRegion);
	}

	void makeGraphics(Orbital& obj, OrbitalNode@ node) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onMakeGraphics(obj, data[i], node);
	}

	bool shouldDisable(Orbital& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].shouldDisable(obj, data[i]))
				return true;
		}
		return false;
	}

	void kill(Orbital& obj, Empire@ killedBy) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onKill(obj, data[i], killedBy);
	}

	bool shouldEnable(Orbital& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].shouldEnable(obj, data[i]))
				return false;
		}
		return true;
	}

	string getData(Orbital& obj) const {
		string txt;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].getData(obj, txt, enabled))
				return txt;
		}
		return txt;
	}
};

const OrbitalModule@ getOrbitalModule(uint id) {
	if(id >= modules.length)
		return null;
	return modules[id];
}

const OrbitalModule@ getOrbitalModule(const string& ident) {
	OrbitalModule@ mod;
	if(idents.get(ident, @mod))
		return mod;
	return null;
}

uint getOrbitalModuleCount() {
	return modules.length;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = modules.length; i < cnt; ++i) {
		auto type = modules[i];
		file.addIdentifier(SI_Orbital, type.id, type.ident);
	}
}

tidy final class OrbitalRequirements {
	array<const ResourceType@> available;
	array<bool> used;
	array<uint> tmp;

	void init(const array<Resource>& list) {
		uint cnt = list.length;
		available.length = 0;
		used.length = 0;
		available.reserve(cnt);
		used.reserve(cnt);
		for(uint i = 0; i < cnt; ++i) {
			if(list[i].usable) {
				available.insertLast(list[i].type);
				used.insertLast(false);
			}
		}
	}

	void init(const array<Resource@>& list) {
		uint cnt = list.length;
		available.length = 0;
		used.length = 0;
		available.reserve(cnt);
		used.reserve(cnt);
		for(uint i = 0; i < cnt; ++i) {
			if(list[i].usable) {
				available.insertLast(list[i].type);
				used.insertLast(false);
			}
		}
	}

	void init(Object& obj, bool direct = false) {
		if(!obj.hasResources) {
			available.length = 0;
			used.length = 0;
			return;
		}
		if(direct) {
			uint cnt = obj.availableResourceCount;
			available.length = 0;
			used.length = 0;
			available.reserve(cnt);
			used.reserve(cnt);
			for(uint i = 0; i < cnt; ++i) {
				if(obj.availableResourceUsable[i]) {
					available.insertLast(getResource(obj.availableResourceType[i]));
					used.insertLast(false);
				}
			}
		}
		else {
			array<Resource> resources;
			resources.syncFrom(obj.getAvailableResources());
			init(resources);
		}
	}

	void _revert() {
		for(uint i = 0, cnt = tmp.length; i < cnt; ++i)
			used[tmp[i]] = false;
		tmp.length = 0;
	}

	bool add(const OrbitalModule@ mod) {
		return check(mod, true);
	}

	bool check(const OrbitalModule@ mod, bool apply = false) {
		tmp.length = 0;
		tmp.reserve(16);

		//First, compute specific resource requirements
		for(uint i = 0, cnt = mod.requirements.length; i < cnt; ++i) {
			bool found = false;
			for(uint n = 0, ncnt = available.length; n < ncnt; ++n) {
				if(used[n])
					continue;
				if(available[n] is mod.requirements[i]) {
					found = true;
					used[n] = true;
					tmp.insertLast(n);
				}
			}
			if(!found) {
				_revert();
				return false;
			}
		}

		//Find matches for affinities
		for(uint i = 0; i < TR_COUNT; ++i) {
			uint amount = mod.affinities[i];
			for(uint c = 0; c < amount; ++c) {
				uint mask = 1<<i;
				uint found = uint(-1);
				bool specif = false;
				for(uint n = 0, ncnt = available.length; n < ncnt; ++n) {
					if(used[n])
						continue;
					auto@ res = available[n];
					for(uint j = 0, jcnt = res.affinities.length; j < jcnt; ++j) {
						uint aff = res.affinities[j];
						if(aff & mask != 0) {
							bool isSpecif = aff == mask;
							if(found == uint(-1) || (isSpecif && !specif)) {
								found = n;
								specif = isSpecif;
							}
						}
					}
				}
				if(found == uint(-1)) {
					_revert();
					return false;
				}

				used[found] = true;
				tmp.insertLast(found);
			}
		}

		//Hook requirements
		if(!mod.checkRequirements(this, apply)) {
			_revert();
			return false;
		}
		if(!apply)
			_revert();
		return true;
	}
};

void addOrbitalModule(OrbitalModule@ mod) {
	mod.id = modules.length;
	modules.insertLast(mod);
	idents.set(mod.ident, @mod);
}

void parseLine(string& line, OrbitalModule@ mod, ReadFile@ file) {
	//Hook line
	auto@ hook = cast<IOrbitalEffect>(parseHook(line, "orbital_effects::", instantiate=false, file=file));
	if(hook !is null)
		mod.hooks.insertLast(hook);
}

int getOrbitalModuleID(const string& ident) {
	auto@ type = getOrbitalModule(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getOrbitalModuleIdent(int id) {
	auto@ type = getOrbitalModule(id);
	if(type is null)
		return "";
	return type.ident;
}

void loadOrbitalModules(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	OrbitalModule@ mod;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			string line = file.line;
			parseLine(line, mod, file);
		}
		else if(key.equals_nocase("Module")) {
			if(mod !is null)
				addOrbitalModule(mod);
			@mod = OrbitalModule();
			mod.ident = value;
		}
		else if(mod is null) {
			file.error("Missing Module: 'ID' line");
		}
		else if(key.equals_nocase("Name")) {
			mod.name = localize(value);
		}
		else if(key.equals_nocase("Blurb")) {
			mod.blurb = localize(value);
		}
		else if(key.equals_nocase("Description")) {
			mod.description = localize(value);
		}
		else if(key.equals_nocase("Icon")) {
			mod.icon = getSprite(value);
		}
		else if(key.equals_nocase("Icon Size")) {
			mod.iconSize = toDouble(value);
		}
		else if(key.equals_nocase("Distant Icon")) {
			mod.distantIcon = getSprite(value);
		}
		else if(key.equals_nocase("Strategic Icon")) {
			mod.strategicIcon = getSprite(value);
		}
		else if(key.equals_nocase("Spin")) {
			mod.spin = toDouble(value);
		}
		else if(key.equals_nocase("Core")) {
			mod.isCore = toBool(value);
		}
		else if(key.equals_nocase("Standalone")) {
			mod.isStandalone = toBool(value);
			if(mod.isStandalone)
				mod.isCore = true;
		}
		else if(key.equals_nocase("Solid")) {
			mod.isSolid = toBool(value);
		}
		else if(key.equals_nocase("Unique")) {
			mod.isUnique = toBool(value);
		}
		else if(key.equals_nocase("Maintenance")) {
			mod.maintenance = toInt(value);
		}
		else if(key.equals_nocase("Build Cost")) {
			mod.buildCost = toInt(value);
		}
		else if(key.equals_nocase("Labor Cost")) {
			mod.laborCost = toDouble(value);
		}
		else if(key.equals_nocase("Health")) {
			mod.health = toDouble(value);
		}
		else if(key.equals_nocase("Armor")) {
			mod.armor = toDouble(value);
		}
		else if(key.equals_nocase("Size")) {
			mod.size = toDouble(value);
		}
		else if(key.equals_nocase("Model")) {
			@mod.model = getModel(value);
		}
		else if(key.equals_nocase("Material")) {
			@mod.material = getMaterial(value);
		}
		else if(key.equals_nocase("Combat Repair")) {
			mod.combatRepair = toBool(value);
		}
		else if(key.equals_nocase("Can Fling")) {
			mod.canFling = toBool(value);
		}
		else if(key.equals_nocase("Mass")) {
			mod.mass = toDouble(value);
		}
		else if(key.equals_nocase("Require Affinity")) {
			array<string>@ parts = value.split(" ");
			if(parts.length != 2) {
				file.error("Invalid affinity requirement: "+value);
				return;
			}
			uint res = getTileResource(parts[1]);
			if(res == TR_NULL) {
				file.error("Invalid affinity resource: "+parts[1]);
				return;
			}

			uint amt = toUInt(parts[0]);
			mod.affinities[res] += amt;
			mod.totalRequirementCount += amt;
		}
		else if(key.equals_nocase("Require Resource")) {
			auto@ res = getResource(value);
			if(res is null) {
				file.error("Invalid resource: "+value);
				return;
			}
			mod.requirements.insertLast(res);
			mod.totalRequirementCount += 1;
		}
		else if(key.equals_nocase("AI")) {
			auto@ hook = parseHook(value, "ai.orbitals::", instantiate=false, file=file);
			if(hook !is null)
				mod.ai.insertLast(hook);
			else
				file.error("Could not find AI hook "+value);
		}
		else {
			string line = file.line;
			parseLine(line, mod, file);
		}
	}
	
	if(mod !is null)
		addOrbitalModule(mod);
}

void preInit() {
	FileList list("data/orbitals", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadOrbitalModules(list.path[i]);
}

void init() {
	auto@ list = modules;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
		for(uint n = 0, ncnt = type.ai.length; n < ncnt; ++n) {
			if(!type.ai[n].instantiate())
				error("Could not instantiate AI hook: "+addrstr(type.ai[n])+" in orbital "+type.ident);
		}
	}
}
