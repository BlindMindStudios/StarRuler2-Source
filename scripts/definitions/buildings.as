#priority init 2000
import tile_resources;
from saving import SaveIdentifier, SaveVersion;
import util.formatting;
import biomes;
import hooks;

export BuildingClass;
export BuildingType;
export SurfaceBuilding;
export getBuildingTypeCount, getBuildingType;

namespace buildings {
	::array<::BuildingType@> types;
	::dictionary typeIdents;
};

enum BuildingClass {
	BC_Building,
	BC_Civilian,
	BC_City,
};

tidy class BiomeAffinity {
	const Biome@ biome;
	double factor = 0.0;
	string def;

	BiomeAffinity(const string& spec) {
		int pos = spec.findFirst(" ");
		if(pos == -1) {
			def = spec;
		}
		else {
			def = spec.substr(0, pos);
			factor = toDouble(spec.substr(pos+1));
		}
	}

	void init() {
		@biome = getBiome(def);
		if(biome is null)
			error("Invalid affinity biome: "+def);
	}
};

tidy final class BuildingType {
	uint id = 0;
	string ident;

	string name;
	string description;
	string category;
	Sprite sprite;

	string upgradesFrom;
	const BuildingType@ base;
	array<const BuildingType@> upgrades;

	array<IBuildingHook@> hooks;
	array<Hook@> ai;

	array<BiomeAffinity@> buildAffinities;
	array<BiomeAffinity@> maintainAffinities;

	float hubWeight = 1.f;
	BuildingClass cls = BC_Building;

	double[] resources = double[](TR_COUNT, 0.f);
	float[] saturates = float[](TR_COUNT, 0.f);

	double totalResource = 0.f;
	float totalSaturate = 0.f;
	int pressureCapTaken = 0;

	vec2u size(1, 1);

	int baseBuildCost = 0;
	int tileBuildCost = 0;
	int baseMaintainCost = 0;
	int tileMaintainCost = 0;

	double buildTime = 3.0 * 60.0;
	double laborCost = 0;
	bool buildInQueue = false;

	double getBuildTime(Object& obj) const {
		double time = buildTime;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].modBuildTime(obj, time);
		return time;
	}

	string getTooltip(bool showName = true, bool showCost = true, bool showSize = true, bool showAffinity = true, Object@ valueObject = null, bool isOption = false) const {
		string tt;
		if(showName)
			tt += format("[font=Medium][b]$1[/b][/font]\n", name);
		tt += format("[vspace=4/][center][img=$1;$2x$3/][/center][vspace=4/]",
				getSpriteDesc(sprite), toString(40*size.x,0), toString(40*size.y,0));
		tt += description;

		string vname, vvalue;
		Sprite vicon;
		Color color;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].getVariable(valueObject, vicon, vname, vvalue, color, isOption)) {
				tt += format("[nl/]\n[img=$1;22][b][color=$4]$2[/color][/b] [offset=120]$3[/offset][/img]",
					getSpriteDesc(vicon), vname, vvalue, toString(color));
				color = colors::White;
			}
		}
		if(showCost && !civilian) {
			tt += "[nl/]\n";
			if(showSize && (size.x > 1 || size.y > 1))
				tt += format(locale::BLD_TT_SIZE, toString(size.x), toString(size.y))+"\n";

			int bld = buildCostEst, mnt = maintainCostEst;
			if(bld != 0 || mnt != 0)
				tt += format(locale::BLD_TT_COST, formatMoney(bld, mnt));

			if(showAffinity) {
				for(uint n = 0, ncnt = buildAffinities.length; n < ncnt; ++n) {
					auto@ aff = buildAffinities[n];
					if(aff.biome is null)
						continue;
					if(aff.factor > 1)
						tt += "[nl/]\n"+format(locale::BLD_TT_AFFINITY_BUILD_NEG, toString((aff.factor-1.0)*100,0)+"%", toString(aff.biome.color), aff.biome.name, getSpriteDesc(icons::Minus));
					else
						tt += "[nl/]\n"+format(locale::BLD_TT_AFFINITY_BUILD, toString((1.0-aff.factor)*100,0)+"%", toString(aff.biome.color), aff.biome.name, getSpriteDesc(icons::Plus));
				}
				for(uint n = 0, ncnt = maintainAffinities.length; n < ncnt; ++n) {
					auto@ aff = maintainAffinities[n];
					if(aff.biome is null)
						continue;
					if(aff.factor > 1)
						tt += "[nl/]\n"+format(locale::BLD_TT_AFFINITY_MAINT_NEG, toString((aff.factor-1.0)*100,0)+"%", toString(aff.biome.color), aff.biome.name, getSpriteDesc(icons::Minus));
					else
						tt += "[nl/]\n"+format(locale::BLD_TT_AFFINITY_MAINT, toString((1.0-aff.factor)*100,0)+"%", toString(aff.biome.color), aff.biome.name, getSpriteDesc(icons::Plus));
				}
				if(!civilian && (tileBuildCost != 0 || tileMaintainCost != 0))
					tt += "[nl/]\n"+locale::BLD_TT_DEV;
			}
		}
		else {
			if(showSize && (size.x > 1 || size.y > 1)) {
				tt += "[nl/]\n";
				tt += format(locale::BLD_TT_SIZE, toString(size.x), toString(size.y));
			}
		}
		return tt;
	}

	bool canProgress(Object& obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canProgress(obj))
				return false;
		}
		return true;
	}

	bool consume(Object& obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].consume(obj)) {
				for(uint j = 0; j < i; ++j)
					hooks[j].reverse(obj);
				return false;
			}
		}
		return true;
	}

	void reverseConsume(Object& obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].reverse(obj);
	}

	double getMaintenanceFor(const Biome@ biome) const {
		double cost = tileMaintainCost;
		for(uint i = 0, cnt = maintainAffinities.length; i < cnt; ++i) {
			if(maintainAffinities[i].biome is biome)
				cost *= maintainAffinities[i].factor;
		}
		return cost;
	}

	bool get_civilian() const {
		return cls != BC_Building;
	}

	bool canBuildOn(Object@ obj, bool ignoreState = false) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canBuildOn(obj, ignoreState))
				return false;
		}
		return true;
	}

	bool canRemove(Object@ obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canRemove(obj))
				return false;
		}
		return true;
	}

	int get_buildCostEst() const {
		return baseBuildCost + size.x * size.y * tileBuildCost;
	}

	int get_maintainCostEst() const {
		return baseMaintainCost + size.x * size.y * tileMaintainCost;
	}

	vec2u getCenter() const {
		vec2u center(floor(float(size.x) / 2.f), floor(float(size.y) / 2.f));
		center.x = clamp(center.x, 0, size.x-1);
		center.y = clamp(center.y, 0, size.y-1);
		return center;
	}

	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].startConstruction(obj, bld);
	}

	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].cancelConstruction(obj, bld);
	}

	void complete(Object& obj, SurfaceBuilding@ bld) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].complete(obj, bld);
	}

	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].ownerChange(obj, bld, prevOwner, newOwner);
	}

	void remove(Object& obj, SurfaceBuilding@ bld) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].remove(obj, bld);
	}

	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].tick(obj, bld, time);
	}

	void save(SurfaceBuilding@ bld, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].save(bld, file);
	}

	void load(SurfaceBuilding@ bld, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].load(bld, file);
	}
};

interface IBuildingHook {
	void initialize(BuildingType@ type, uint index);
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const;
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const;
	void complete(Object& obj, SurfaceBuilding@ bld) const;
	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const;
	void remove(Object& obj, SurfaceBuilding@ bld) const;
	void tick(Object& obj, SurfaceBuilding@ bld, double time) const;
	void save(SurfaceBuilding@ bld, SaveFile& file) const;
	void load(SurfaceBuilding@ bld, SaveFile& file) const;
	bool canBuildOn(Object& obj, bool ignoreState = false) const;
	bool canRemove(Object& obj) const;
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const;
	bool getCost(Object& obj, string& value, Sprite& icon) const;
	bool consume(Object& obj) const;
	void reverse(Object& obj) const;
	void modBuildTime(Object& obj, double& time) const;
	bool canProgress(Object& obj) const;
};

class BuildingHook : Hook, IBuildingHook {
	uint hookIndex = 0;
	void initialize(BuildingType@ type, uint index) { hookIndex = index; }
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void complete(Object& obj, SurfaceBuilding@ bld) const {}
	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const {}
	void remove(Object& obj, SurfaceBuilding@ bld) const {}
	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {}
	void save(SurfaceBuilding@ bld, SaveFile& file) const {}
	void load(SurfaceBuilding@ bld, SaveFile& file) const {}
	bool canBuildOn(Object& obj, bool ignoreState = false) const { return true; }
	bool canRemove(Object& obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const {
		return false;
	}
	bool consume(Object& obj) const { return true; }
	void reverse(Object& obj) const {}
	bool getCost(Object& obj, string& value, Sprite& icon) const {
		return false;
	}
	void modBuildTime(Object& obj, double& time) const {}
	bool canProgress(Object& obj) const { return true; }
};

tidy final class SurfaceBuilding : Serializable, Savable {
	vec2u position;
	const BuildingType@ type;
	float completion = 0.f;
	bool disabled = false;
	bool upgrading = false;
	bool delta = false;
	int cost = 0;
	int cycle = -1;
	Object@ tied;
	array<any>@ data;

	SurfaceBuilding() {}
	SurfaceBuilding(const BuildingType@ Type) {
		@type = Type;
		if(type.hooks.length > 0)
			@data = array<any>(type.hooks.length);
	}

	void write(Message& msg) {
		msg.writeSmall(position.x);
		msg.writeSmall(position.y);
		msg.writeSmall(type.id);
		msg << disabled;
		msg << upgrading;
		if(tied !is null) {
			msg.write1();
			msg << tied;
		}
		else {
			msg.write0();
		}
		
		if(completion < 1.f) {
			msg.write1();
			msg.writeFixed(completion, 0, 1.f, 7);
		}
		else {
			msg.write0();
		}
	}

	void read(Message& msg) {
		position.x = msg.readSmall();
		position.y = msg.readSmall();

		@type = getBuildingType(msg.readSmall());

		msg >> disabled;
		msg >> upgrading;
		
		if(msg.readBit())
			msg >> tied;
		else
			@tied = null;
		
		if(msg.readBit()) {
			completion = msg.readFixed(0, 1.f, 7);
		}
		else {
			completion = 1.f;
		}
	}

	void save(SaveFile& msg) {
		msg << position;
		msg.writeIdentifier(SI_Building, type.id);
		msg << completion;
		msg << disabled;
		msg << upgrading;
		msg << tied;
		msg << cost;
		msg << cycle;

		if(completion >= 1.f)
			type.save(this, msg);
	}

	void load(SaveFile& msg) {
		msg >> position;

		uint tid = msg.readIdentifier(SI_Building);
		@type = getBuildingType(tid);
		if(type.hooks.length > 0)
			@data = array<any>(type.hooks.length);

		msg >> completion;
		msg >> disabled;
		msg >> upgrading;
		msg >> tied;

		if(msg >= SV_0072) {
			msg >> cost;
			msg >> cycle;
		}

		if(completion >= 1.f || msg < SV_0136)
			type.load(this, msg);
	}

	string getTooltip(Object@ obj = null) {
		return type.getTooltip(showCost=false, showSize=false, valueObject=obj);
	}
};

void parseLine(ReadFile& file, string& line, BuildingType@ bld) {
	if(line.findFirst("(") == -1) {
		//Resource line
		array<string>@ decls = line.split(",");
		for(uint i = 0, cnt = decls.length; i < cnt; ++i) {
			array<string>@ parts = decls[i].split(" ");
			if(parts.length != 3) {
				file.error("Invalid building effect: "+escape(decls[i].trimmed()));
				continue;
			}

			uint resource = getTileResource(parts[1]);
			if(resource == TR_INVALID) {
				file.error("Invalid building effect: "+escape(decls[i].trimmed()));
				continue;
			}

			double amt = toDouble(parts[0]);
			string type = parts[2].trimmed();
			if(type.equals_nocase("saturation")) {
				bld.saturates[resource] += amt;
			}
			else if(type.equals_nocase("production")) {
				bld.resources[resource] += amt;
			}
			else {
				file.error("Invalid building effect: "+escape(decls[i].trimmed()));
				continue;
			}
		}
	}
	else {
		//Hook line
		auto@ hook = cast<IBuildingHook@>(parseHook(line, "building_effects::", instantiate=false, file=file));
		if(hook !is null) {
			hook.initialize(bld, bld.hooks.length);
			bld.hooks.insertLast(hook);
		}
	}
}

void loadBuildings(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	BuildingType@ bld;
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			if(bld is null) {
				file.error("Missing 'Building: ID' line");
				continue;
			}

			string line = file.line;
			parseLine(file, line, bld);
		}
		else if(key == "Building") {
			if(bld !is null)
				addBuildingType(bld);
			@bld = BuildingType();
			bld.ident = value;
		}
		else if(bld is null) {
			error("Missing 'Building: ID' line in " + filename);
		}
		else if(key == "Name") {
			bld.name = localize(value);
		}
		else if(key == "Description") {
			bld.description = localize(value);
		}
		else if(key == "Sprite") {
			bld.sprite = getSprite(value);
		}
		else if(key == "Upgrades From") {
			bld.upgradesFrom = value;
		}
		else if(key == "Category") {
			bld.category = value;
		}
		else if(key == "Civilian") {
			if(toBool(value)) {
				bld.cls = BC_Civilian;
				bld.pressureCapTaken = 1;
			}
		}
		else if(key == "City") {
			if(toBool(value)) {
				bld.cls = BC_City;
				bld.pressureCapTaken = 0;
			}
		}
		else if(key == "Size") {
			array<string>@ split = value.split("x");
			if(split.length != 2) {
				error("Invalid building size: "+escape(file.line));
			}
			else {
				bld.size.x = toUInt(split[0]);
				bld.size.y = toUInt(split[1]);
			}
		}
		else if(key == "Base Cost") {
			bld.baseBuildCost = toInt(value);
		}
		else if(key == "Tile Cost") {
			bld.tileBuildCost = toInt(value);
		}
		else if(key == "Base Maintenance") {
			bld.baseMaintainCost = toInt(value);
		}
		else if(key == "Tile Maintenance") {
			bld.tileMaintainCost = toInt(value);
		}
		else if(key == "Build Time") {
			bld.buildTime = toDouble(value);
		}
		else if(key == "Labor Cost") {
			bld.laborCost = toDouble(value);
			bld.buildInQueue = true;
		}
		else if(key == "Pressure Cap") {
			bld.pressureCapTaken = toInt(value);
		}
		else if(key == "Build Affinity") {
			bld.buildAffinities.insertLast(BiomeAffinity(value));
		}
		else if(key == "Maintenance Affinity") {
			bld.maintainAffinities.insertLast(BiomeAffinity(value));
		}
		else if(key == "In Queue") {
			bld.buildInQueue = toBool(value);
		}
		else if(key == "Saturation") {
			array<string>@ decls = value.split(",");
			for(uint i = 0, cnt = decls.length; i < cnt; ++i) {
				array<string>@ parts = decls[i].split(" ");
				if(parts.length != 2) {
					file.error("Invalid saturation spec: "+escape(decls[i]));
					continue;
				}

				uint resource = getTileResource(parts[1]);
				if(resource == TR_INVALID) {
					file.error("Invalid pressure spec: "+escape(decls[i]));
					continue;
				}

				double amt = toDouble(parts[0]);
				bld.saturates[resource] += amt;
			}
		}
		else if(key == "Production") {
			array<string>@ decls = value.split(",");
			for(uint i = 0, cnt = decls.length; i < cnt; ++i) {
				array<string>@ parts = decls[i].split(" ");
				if(parts.length != 2) {
					file.error("Invalid saturation spec: "+escape(decls[i]));
					continue;
				}

				uint resource = getTileResource(parts[1]);
				if(resource == TR_INVALID) {
					file.error("Invalid pressure spec: "+escape(decls[i]));
					continue;
				}

				double amt = toDouble(parts[0]);
				bld.resources[resource] += amt;
			}
		}
		else if(key.equals_nocase("AI")) {
			auto@ hook = parseHook(value, "ai.buildings::", instantiate=false, file=file);
			if(hook !is null)
				bld.ai.insertLast(hook);
			else
				file.error("Could not find AI hook "+value);
		}
		else {
			string line = file.line;
			parseLine(file, line, bld);
		}
	}
	
	if(bld !is null)
		addBuildingType(bld);
}

void preInit() {
	FileList list("data/buildings", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadBuildings(list.path[i]);

	for(uint i = 0, cnt = buildings::types.length; i < cnt; ++i) {
		BuildingType@ type = buildings::types[i];
		if(type.upgradesFrom.length != 0) {
			BuildingType@ par;
			buildings::typeIdents.get(type.upgradesFrom, @par);

			if(par !is null) {
				par.upgrades.insertLast(type);
				@type.base = par;
			}
			else {
				error("Error: "+type.ident+": Could not find base building "+type.upgradesFrom);
			}
		}
	}
}

void init() {
	auto@ list = buildings::types;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
		for(uint n = 0, ncnt = type.buildAffinities.length; n < ncnt; ++n)
			type.buildAffinities[n].init();
		for(uint n = 0, ncnt = type.maintainAffinities.length; n < ncnt; ++n)
			type.maintainAffinities[n].init();
		for(uint n = 0, ncnt = type.ai.length; n < ncnt; ++n) {
			if(!type.ai[n].instantiate())
				error("Could not instantiate AI hook: "+addrstr(type.ai[n])+" in building "+type.ident);
		}
	}
}

uint getBuildingTypeCount() {
	return buildings::types.length;
}

string getBuildingIdent(int id) {
	if(uint(id) < buildings::types.length)
		return buildings::types[id].ident;
	return "";
}

int getBuildingID(const string& ident) {
	BuildingType@ def;
	buildings::typeIdents.get(ident, @def);
	if(def is null)
		return -1;
	return def.id;
}

const BuildingType@ getBuildingType(uint id) {
	if(id < buildings::types.length)
		return buildings::types[id];
	return null;
}

const BuildingType@ getBuildingType(const string& ident) {
	BuildingType@ def;
	buildings::typeIdents.get(ident, @def);
	return def;
}

void addBuildingType(BuildingType@ def) {
	def.id = buildings::types.length;
	buildings::typeIdents.set(def.ident, @def);
	buildings::types.insertLast(def);

	for(uint i = 0; i < TR_COUNT; ++i) {
		def.totalResource += def.resources[i];
		def.totalSaturate += def.saturates[i];
	}
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = buildings::types.length; i < cnt; ++i) {
		BuildingType@ type = buildings::types[i];
		file.addIdentifier(SI_Building, type.id, type.ident);
	}
}
