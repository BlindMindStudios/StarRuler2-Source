#priority init 2000
import tile_resources;
import util.formatting;
import hooks;
from saving import SaveIdentifier, SaveVersion;
import bool readLevelChain(ReadFile& file) from "planet_levels";

const double[] LEVEL_DISTRIBUTION = {0.76, 0.15, 0.06, 0.03};
const double[] RARITY_DISTRIBUTION = {
	0.88, 0.09, 0.02, 0.01, 0.05, 0.00002, //Level 0
	0.73, 0.20, 0.05, 0.02, 0.05, 0.00002, //Level 1
	0.70, 0.20, 0.06, 0.04, 0.05, 0.00002, //Level 2
	0.70, 0.18, 0.08, 0.04, 0.05, 0.00002, //Level 3
};
const int CARGO_WORTH_LEVEL = 10;

//Various ways excess budget may be exchanged into resources
enum WelfareMode {
	WM_Influence,
	WM_Energy,
	WM_Research,
	WM_HW_Labor,
	WM_Defense,
	
	WM_COUNT
};

tidy final class ResourceClass {
	uint id = 0;
	string ident;
	string name;
	array<const ResourceType@> types;
};

enum ResourceMode {
	RM_Normal,
	RM_Universal,
	RM_UniversalUnique,
	RM_NonRequirement,
};

enum ResourceRarity {
	RR_Common,
	RR_Uncommon,
	RR_Rare,
	RR_Epic,
	RR_Unique,
	RR_Mythical,

	RR_COUNT
};

enum VanishMode {
	VM_Never,
	VM_WhenExported,
	VM_Always,
	VM_ExportedInCombat,
	VM_Custom,
};

enum MoneyType {
	MoT_Misc,
	MoT_Construction,
	MoT_Orbitals,
	MoT_Buildings,
	MoT_Ships,
	MoT_Planet_Upkeep,
	MoT_Planet_Income,
	MoT_Colonizers,
	MoT_Handicap,
	MoT_Trade,
	MoT_Vassals,
	//Update save version when adding
	// See: components.ResourceManager

	MoT_COUNT
};

tidy final class ResourceType {
	const ResourceClass@ cls;
	uint id = 0;
	string ident;
	string name;
	string description;
	string blurb;
	string nativeBiome;
	string className;
	string dlc;
	uint level = 0;
	Sprite icon;
	Sprite smallIcon;
	ResourceSheet@ distantSheet;
	uint distantIndex = 0;
	double frequency = 1;
	double distribution = 1;
	double rarityScore = 1;
	double vanishTime = -1.0;
	VanishMode vanishMode = VM_Never;
	bool exportable = true;
	ResourceMode mode = RM_Normal;
	int[] tilePressure = array<int>(TR_COUNT, 0);
	int totalPressure = 0;
	int displayWeight = 0;
	int cargoWorth = 0;
	array<uint> affinities;
	ResourceRarity rarity = RR_Common;
	bool artificial = false;
	bool requirementDisplay = true;
	bool willLock = false;
	bool unique = false;
	double requireContestation = -INFINITY;
	int rarityLevel = -1;
	bool limitlessLevel = false;
	bool canBeTerraformed = true;

	bool get_hasEffect() const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].hasEffect)
				return true;
		}
		if(!exportable)
			return true;
		return false;
	}

	double asteroidFrequency = 0.0;
	double asteroidCost = 0.0;

	int terraformCost = 0;
	double terraformLabor = 0.0;

	array<IResourceHook@> hooks;
	array<Hook@> ai;

	void addAffinity(uint v) {
		affinities.insertLast(v);
	}

	bool isMaterial(uint onLevel) const {
		if(mode == RM_NonRequirement)
			return true;
		if(!exportable)
			return true;
		if(level < onLevel)
			return true;
		return false;
	}

	bool canTerraform(Object@ from, Object@ to) const {
		auto@ curType = getResource(to.primaryResourceType);
		if(curType !is null && !curType.canBeTerraformed)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canTerraform(from, to))
				return false;
		}
		return true;
	}
	
	double get_totalRarity() const {
		return 1.0 / rarityScore;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].hasEffect)
				return hooks[i].formatEffect(obj, hooks);
		}
		if(!exportable)
			return locale::CANNOT_EXPORT;
		return "---";
	}

	bool shouldVanish(Object& obj, Resource@ native) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].shouldVanish(obj, native))
				return true;
		}
		return false;
	}

	void onAdd(Object& obj, Resource@ r) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onAdd(obj, r);
	}

	void onRemove(Object& obj, Resource@ r) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onRemove(obj, r);
	}

	void onTick(Object& obj, Resource@ r, double tick) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onTick(obj, r, tick);
	}

	void onOwnerChange(Object& obj, Resource@ r, Empire@ prevOwner, Empire@ newOwner) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onOwnerChange(obj, r, prevOwner, newOwner);
	}

	void onRegionChange(Object& obj, Resource@ r, Region@ fromRegion, Region@ toRegion) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onRegionChange(obj, r, fromRegion, toRegion);
	}

	void save(Resource@ r, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].save(r, file);
	}

	void load(Resource@ r, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].load(r, file);
	}

	void applyGraphics(Object& obj, Node& node) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].applyGraphics(obj, node);
	}

	void onTerritoryAdd(Object& obj, Resource@ r, Territory@ terr) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onTerritoryAdd(obj, r, terr);
	}

	void onTerritoryRemove(Object& obj, Resource@ r, Territory@ terr) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onTerritoryRemove(obj, r, terr);
	}

	void onGenerate(Object& obj, Resource@ native) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onGenerate(obj, native);
	}

	void onDestroy(Object& obj, Resource@ native) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onDestroy(obj, native);
	}

	void nativeTick(Object& obj, Resource@ native, double time) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].nativeTick(obj, native, time);
	}

	void nativeSave(Resource@ r, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].nativeSave(r, file);
	}

	void nativeLoad(Resource@ r, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].nativeLoad(r, file);
	}
};

interface IResourceHook {
	void initialize(ResourceType@ type, uint index);
	bool canTerraform(Object@ from, Object@ to) const;
	bool get_hasEffect() const;
	bool mergesEffect(Object& obj, const IResourceHook@ other) const;
	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const;
	const IResourceHook@ get_displayHook() const;
	const IResourceHook@ get_carriedHook() const;
	bool shouldVanish(Object& obj, Resource@ native) const;
	void onAdd(Object& obj, Resource@ r) const;
	void onRemove(Object& obj, Resource@ r) const;
	void onTick(Object& obj, Resource@ r, double tick) const;
	void onOwnerChange(Object& obj, Resource@ r, Empire@ prevOwner, Empire@ newOwner) const;
	void onRegionChange(Object& obj, Resource@ r, Region@ fromRegion, Region@ toRegion) const;
	void save(Resource@ r, SaveFile& file) const;
	void load(Resource@ r, SaveFile& file) const;
	void applyGraphics(Object& obj, Node& node) const;
	void onTerritoryAdd(Object& obj, Resource@ r, Territory@ terr) const;
	void onTerritoryRemove(Object& obj, Resource@ r, Territory@ terr) const;
	void onTradeDeliver(Civilian& civ, Object@ origin, Object@ target) const;
	void onTradeDestroy(Civilian& civ, Object@ origin, Object@ target, Object@ destroyer) const;

	void onGenerate(Object& obj, Resource@ native) const;
	void nativeTick(Object&, Resource@ native, double time) const;
	void onDestroy(Object&, Resource@ native) const;
	void nativeSave(Resource@ native, SaveFile& file) const;
	void nativeLoad(Resource@ native, SaveFile& file) const;
};

class ResourceHook : Hook, IResourceHook {
	uint hookIndex = 0;
	void initialize(ResourceType@ type, uint index) { hookIndex = index; }
	bool canTerraform(Object@ from, Object@ to) const { return true; }
	bool get_hasEffect() const { return false; }
	bool mergesEffect(Object& obj, const IResourceHook@ other) const { return getClass(other) is getClass(this); }
	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const { return "---"; }
	const IResourceHook@ get_displayHook() const { return this; }
	const IResourceHook@ get_carriedHook() const { return null; }
	bool shouldVanish(Object& obj, Resource@ native) const { return false; }
	void onAdd(Object& obj, Resource@ r) const {}
	void onRemove(Object& obj, Resource@ r) const {}
	void onTick(Object& obj, Resource@ r, double tick) const {}
	void onOwnerChange(Object& obj, Resource@ r, Empire@ prevOwner, Empire@ newOwner) const {}
	void onRegionChange(Object& obj, Resource@ r, Region@ fromRegion, Region@ toRegion) const {}
	void save(Resource@ r, SaveFile& file) const {}
	void load(Resource@ r, SaveFile& file) const {}
	void applyGraphics(Object& obj, Node& node) const {}
	void onTerritoryAdd(Object& obj, Resource@ r, Territory@ terr) const {};
	void onTerritoryRemove(Object& obj, Resource@ r, Territory@ terr) const {};
	void onGenerate(Object& obj, Resource@ native) const {}
	void nativeTick(Object&, Resource@ native, double time) const {}
	void onDestroy(Object&, Resource@ native) const {}
	void onTradeDeliver(Civilian& civ, Object@ origin, Object@ target) const {}
	void onTradeDestroy(Civilian& civ, Object@ origin, Object@ target, Object@ destroyer) const {}
	void nativeSave(Resource@ native, SaveFile& file) const {}
	void nativeLoad(Resource@ native, SaveFile& file) const {}
};

int integerSum(array<const IResourceHook@>& hooks, int argument) {
	int amount = 0;
	for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
		amount += cast<const Hook>(hooks[i]).arguments[argument].integer;
	return amount;
}

double decimalSum(array<const IResourceHook@>& hooks, int argument) {
	double amount = 0.0;
	for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
		amount += cast<const Hook>(hooks[i]).arguments[argument].decimal;
	return amount;
}

Color getResourceRarityColor(uint rarity) {
	switch(rarity) {
		case RR_Common: return Color(0xffffffff);
		case RR_Uncommon: return Color(0x0062d6ff);
		case RR_Rare: return Color(0xab00d6ff);
		case RR_Epic: return Color(0xd6ac00ff);
		case RR_Unique: return Color(0xf5ff00ff);
		case RR_Mythical: return Color(0x00ffffff);
	}
	return Color(0xffffffff);
}

string getResourceTooltip(const ResourceType@ type, const Resource@ r = null, Object@ drawFrom = null, bool showName = true) {
	if(r !is null && drawFrom !is null && r.origin is null)
		return "[color=#aaa]"+locale::QUEUED_AUTO_IMPORT+"[/color]";

	string text;
	int curLevel = -1;
	if(r !is null && r.origin !is null && r.origin.hasSurfaceComponent)
		curLevel = r.origin.level;

	if(showName)
		text = format("[font=Medium][color=$2]$1[/color] [img=$3;24/][/font]\n", type.name,
			toString(getResourceRarityColor(type.rarity)), getSpriteDesc(type.smallIcon));
	if(type.level > 0) {
		text += locale::LEVEL+" "+type.level;
		if(type.affinities.length != 0)
			text += " - ";
	}
	if(type.affinities.length != 0) {
		uint affCnt = type.affinities.length;
		for(uint i = 0; i < affCnt; ++i) {
			uint a = type.affinities[i];
			text += format("[img=$1;20/]", getSpriteDesc(getAffinitySprite(a)));
		}
		text += "\n";
	}
	else if(type.level > 0) {
		text += "\n";
	}

	//Pressure
	if(type.totalPressure > 0) {
		string prs;
		for(uint i = 0; i < TR_COUNT; ++i) {
			int val = type.tilePressure[i];
			if(val > 0) {
				if(prs.length != 0)
					prs += ", ";
				int prod = val;
				if(r !is null && r.origin !is null && r.origin.owner is playerEmpire)
					prod = max(round(float(val) * r.efficiency), 0.f);
				if(prod != val)
					prs += format("$1/$2 [img=$3;20/]", toString(prod), toString(val), getTileResourceSpriteSpec(i));
				else
					prs += format("$1 [img=$2;20/]", toString(val), getTileResourceSpriteSpec(i));
			}
		}
		text += format("$1[offset=80][b]$2[/b][/offset]\n[vspace=8/]", locale::RES_PROVIDES_PRESSURE, prs);
	}

	if(type.description.length == 0)
		text += format(type.blurb, toString(curLevel, 0));
	else
		text += format(type.description, toString(curLevel, 0));
	
	if(type.totalPressure > 0) {
		uint types = 0;
		for(uint i = 0; i < TR_COUNT; ++i)
			if(type.tilePressure[i] > 0)
				types += 1;
		
		if(types <= 2) {
			if(type.description.length > 0 || type.blurb.length > 0)
				text += "\n\n";
			
			bool first = true;
			for(uint i = 0; i < TR_COUNT; ++i) {
				if(type.tilePressure[i] > 0) {
					if(!first)
						text += "\n\n";
					first = false;
					text += format("[img=$1;20/] ", getTileResourceSpriteSpec(i)) + localize("PRESSURE_" + getTileResourceIdent(i));
				}
			}
		}
	}

	//Import marker
	if(r !is null) {
		if(drawFrom !is null) {
			if(r.origin is null) {
				text += "\n\n[color=#aaa]"+locale::QUEUED_AUTO_IMPORT+"[/color]";
			}
			else if(r.origin is drawFrom && r.exportedTo !is null) {
				text += "\n\n[color=#aaa]"+format(locale::RESOURCE_EXPORTED_TO, r.exportedTo.name)+"[/color]";
			}
			else if(r.exportedTo is drawFrom) {
				text += "\n\n[color=#aaa]"+format(locale::RESOURCE_IMPORTED_FROM, r.origin.name)+"[/color]";
			}
		}
	}

	//Warnings
	if(r !is null) {
		if(r.type.vanishMode != VM_Never) {
			double timeLeft = r.type.vanishTime - r.vanishTime;
			if(r.exportedTo !is null)
				timeLeft /= r.exportedTo.resourceVanishRate;
			else if(r.origin !is null)
				timeLeft /= r.origin.resourceVanishRate;

			text += "\n\n";
			if(r.usable && r.origin !is null && r.origin.owner is playerEmpire && (type.vanishMode == VM_Always || r.exportedTo !is null))
				text += "[color=#fb0]"+format(locale::VANISH_TIP, formatTime(timeLeft))+"[/color]";
			else
				text += format(locale::VANISH_TIP_NOUSE, formatTime(timeLeft));
		}
		
		if(!r.usable) {
			string err;
			if(r.origin !is null)
				err = r.origin.getDisabledReason(r.id);
			else if(drawFrom !is null)
				err = drawFrom.getDisabledReason(r.id);
			
			if(err.length > 0) {
				text += "\n\n";
				string base;
				if(r.origin is drawFrom) {
					if(r.exportedTo is null)
						base = locale::EXPBLOCK_USE;
					else
						base = locale::EXPBLOCK_EXPORT;
				}
				else {
					base = locale::EXPBLOCK_IMPORT;
				}
				text += format(base, err);
			}
		}
	}
	else {
		if(type.vanishMode != VM_Never) {
			text += "\n\n";
			text += format(locale::VANISH_TIP_NOUSE, formatTime(type.vanishTime));
		}
	}
	return text;
}


string formatBuildCost(const Design@ dsg, Object@ obj = null, string fmt = "$1 / $2, $3") {
	int buildCost = 0;
	int maintainCost = 0;
	double laborCost = 0;

	getBuildCost(dsg, buildCost, maintainCost, laborCost, -1, obj);
	return format(fmt, formatMoney(buildCost), formatMoney(maintainCost), standardize(laborCost)+" "+locale::RESOURCE_LABOR);
}

void getBuildCost(const Design@ dsg, int&out buildCost, int&out maintainCost, double&out laborCost, int count = 1, Object@ obj = null) {
	double build = 0;
	double maintain = 0;
	double labor = 0;

	uint cnt = dsg.subsystemCount;
	for(uint i = 0; i < cnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		for(uint j = 0, hexCnt = sys.hexCount; j < hexCnt; ++j) {
			if(sys.has(HV_BuildCost))
				build += sys.hexVariable(HV_BuildCost, j);
			if(sys.has(HV_MaintainCost))
				maintain += sys.hexVariable(HV_MaintainCost, j);
			if(sys.has(HV_LaborCost))
				labor += sys.hexVariable(HV_LaborCost, j);
		}
	}
	if(obj !is null) {
		build *= double(obj.shipBuildCost) / 100.0;
		build *= obj.constructionCostMod;
	}

	buildCost = max(ceil(build), 0.0);
	maintainCost = max(ceil(maintain), 0.0);

	if(count >= 0) {
		buildCost *= count;
		maintainCost *= count;
		labor *= count;
	}

	if(buildCost < 0)
		buildCost = INT_MAX>>1;
	if(maintainCost < 0)
		maintainCost = INT_MAX>>1;
	laborCost = labor;
}

int getBuildCost(const Design@ dsg, int count = 1, Object@ buildAt = null) {
	double build = 0;
	uint cnt = dsg.subsystemCount;
	for(uint i = 0; i < cnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		if(!sys.has(HV_BuildCost))
			continue;
		for(uint j = 0, hexCnt = sys.hexCount; j < hexCnt; ++j)
			build += sys.hexVariable(HV_BuildCost, j);
	}
	if(buildAt !is null) {
		build *= double(buildAt.shipBuildCost) / 100.0;
		build *= buildAt.constructionCostMod;
	}

	int v = ceil(build);
	if(count >= 0)
		v *= count;
	if(v < 0)
		v = INT_MAX>>1;
	return v;
}

int getMaintenanceCost(const Design@ dsg, int count = 1) {
	double maintain = 0;
	uint cnt = dsg.subsystemCount;
	for(uint i = 0; i < cnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		if(!sys.has(HV_MaintainCost))
			continue;
		for(uint j = 0, hexCnt = sys.hexCount; j < hexCnt; ++j)
			maintain += sys.hexVariable(HV_MaintainCost, j);
	}

	if(count >= 0)
		maintain *= count;
	int v = max(ceil(maintain), 0.0);
	if(v < 0)
		v = INT_MAX>>1;
	return v;
}

double getLaborCost(const Design@ dsg, int count = 1) {
	double time = 0;
	uint cnt = dsg.subsystemCount;
	for(uint i = 0; i < cnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		if(!sys.has(HV_LaborCost))
			continue;
		for(uint j = 0, hexCnt = sys.hexCount; j < hexCnt; ++j)
			time += sys.hexVariable(HV_LaborCost, j);
	}

	if(count >= 0)
		time *= count;
	return time;
}

tidy final class Resources : Serializable, Savable {
	array<uint> types;
	int[] amounts;

	Resources() {
	}

	int modAmount(const ResourceType@ type, int mod, bool remove = true) {
		int index = types.find(type.id);
		if(index == -1) {
			types.insertLast(type.id);
			amounts.insertLast(mod);
			return mod;
		}
		else {
			amounts[index] += mod;
			int amt = amounts[index];
			if(remove && amt == 0) {
				types.removeAt(index);
				amounts.removeAt(index);
			}
			return amt;
		}
	}

	int getAmount(const ResourceType@ type) const {
		int index = types.find(type.id);
		if(index == -1)
			return 0;
		return amounts[index];
	}
	
	void clear() {
		types.length = 0;
		amounts.length = 0;
	}

	uint get_length() const {
		return types.length;
	}

	int get_universalCount() const {
		int amt = 0;
		uint cnt = types.length;
		for(uint i = 0; i < cnt; ++i) {
			auto@ type = getResource(types[i]);
			if(type.mode == RM_Universal)
				amt += amounts[i];
			else if(type.mode == RM_UniversalUnique)
				amt += 1;
		}
		return amt;
	}

	bool get_empty() const {
		return types.length == 0;
	}

	void read(Message& msg) {
		uint allTypeCount = getResourceCount();
		uint cnt = msg.readSmall();
		types.length = cnt;
		amounts.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			types[i] = msg.readLimited(allTypeCount-1);
			amounts[i] = msg.readSignedSmall();
		}
	}

	void write(Message& msg) {
		uint allTypeCount = getResourceCount();
		uint cnt = types.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i) {
			msg.writeLimited(types[i], allTypeCount-1);
			msg.writeSignedSmall(amounts[i]);
		}
	}

	void load(SaveFile& msg) {
		uint cnt = 0;
		msg >> cnt;
		types.length = cnt;
		amounts.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			types[i] = msg.readIdentifier(SI_Resource);
			msg >> amounts[i];
		}
	}

	void save(SaveFile& msg) {
		uint cnt = types.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg.writeIdentifier(SI_Resource, types[i]);
			msg << amounts[i];
		}
	}

	void print() const {
		uint cnt = types.length;
		for(uint i = 0; i < cnt; ++i)
			::print(getResource(types[i]).name+": "+amounts[i]);
	}
};

enum ResourceRequirementType {
	RRT_Resource,
	RRT_Class,
	RRT_Class_Types,
	RRT_Level,
	RRT_Level_Types,
};

tidy final class ResourceRequirement {
	ResourceRequirementType type = RRT_Resource;
	const ResourceClass@ cls;
	const ResourceType@ resource;
	uint level = 0;
	uint amount = 0;

	bool equivalent(const ResourceRequirement@ other) const {
		if(type != other.type)
			return false;
		if(cls !is other.cls)
			return false;
		if(resource !is other.resource)
			return false;
		if(level != other.level)
			return false;
		return true;
	}

	int meetQuality(const ResourceType@ check, bool doneUniversal) const {
		if(check.mode == RM_UniversalUnique) {
			if(doneUniversal)
				return 0;
			return 10;
		}
		if(check.mode == RM_Universal)
			return 11;

		switch(type) {
			case RRT_Resource:
				if(resource is check)
					return 1;
			break;
			case RRT_Class:
				if(check.cls is cls)
					return 2;
			break;
			case RRT_Level:
				if(check.level == level)
					return 3;
			break;
		}
		return 0;
	}

	int opCmp(const ResourceRequirement@ other) const {
		if(type < other.type)
			return -1;
		else if(type > other.type)
			return 1;
		return 0;
	}
};

tidy final class ResourceRequirements {
	ResourceRequirement@[] reqs;

	void addRequirement(ResourceRequirement@ req) {
		reqs.insertLast(req);
		reqs.sortAsc();
	}

	bool satisfiedBy(const Resources@ res, array<int>@ remaining = null,
			bool allowUniversal = true, array<int>@ reqRemaining = null) const {
		int universal = res.universalCount;
		int unsatisfied = 0;
		if(remaining is null)
			@remaining = array<int>();
		remaining = res.amounts;

		uint reqCnt = reqs.length;
		uint resCnt = res.length;
		if(reqRemaining !is null)
			reqRemaining.length = reqCnt;
		for(uint i = 0; i < reqCnt; ++i) {
			ResourceRequirement@ r = reqs[i];
			uint total = r.amount;

			switch(r.type) {
				case RRT_Resource: {
					if(r.resource.mode == RM_Normal) {
						for(uint j = 0; j < resCnt; ++j) {
							if(res.types[j] == r.resource.id) {
								uint take = min(remaining[j], total);
								remaining[j] -= take;
								total -= take;
								if(total <= 0)
									break;
							}
						}
					}
					if(reqRemaining !is null)
						reqRemaining[i] = total;
					unsatisfied += total;
				} break;
				case RRT_Class:
					for(uint j = 0; j < resCnt; ++j) {
						auto@ type = getResource(res.types[j]);
						if(type.mode != RM_Normal)
							continue;
						const ResourceClass@ cls = type.cls;
						if(cls is r.cls) {
							uint take = min(remaining[j], total);
							remaining[j] -= take;
							total -= take;
							if(total <= 0)
								break;
						}
					}
					if(reqRemaining !is null)
						reqRemaining[i] = total;
					unsatisfied += total;
				break;
				case RRT_Class_Types:
					for(uint j = 0; j < resCnt; ++j) {
						auto@ type = getResource(res.types[j]);
						if(type.mode != RM_Normal)
							continue;
						const ResourceClass@ cls = type.cls;
						if(cls is r.cls) {
							total -= 1;
							remaining[j] -= 1;
							if(total <= 0)
								break;
						}
					}
					if(reqRemaining !is null)
						reqRemaining[i] = total;
					unsatisfied += total;
				break;
				case RRT_Level:
					for(uint j = 0; j < resCnt; ++j) {
						auto@ type = getResource(res.types[j]);
						if(type.mode != RM_Normal)
							continue;
						if(type.level == r.level) {
							uint take = min(remaining[j], total);
							remaining[j] -= take;
							total -= take;
							if(total <= 0)
								break;
						}
					}
					if(reqRemaining !is null)
						reqRemaining[i] = total;
					unsatisfied += total;
				break;
				case RRT_Level_Types:
					for(uint j = 0; j < resCnt; ++j) {
						auto@ type = getResource(res.types[j]);
						if(type.mode != RM_Normal)
							continue;
						if(type.level == r.level) {
							total -= 1;
							remaining[j] -= 1;
							if(total <= 0)
								break;
						}
					}
					if(reqRemaining !is null)
						reqRemaining[i] = total;
					unsatisfied += total;
				break;
			}
		}

		if(allowUniversal)
			return unsatisfied <= universal;
		else
			return unsatisfied == 0;
	}

	void parse(string text) {
		string[] parts = text.split(",");
		for(uint i = 0, cnt = parts.length; i < cnt; ++i) {
			string spec = parts[i].trimmed();
			int space = spec.findFirst(" ");
			if(space == -1) {
				error("Invalid resource specifier: "+parts[i]);
				continue;
			}

			ResourceRequirement req;
			req.amount = toUInt(spec.substr(0, space));
			string resource = spec.substr(space+1);

			//Detect types of modifier
			bool typesOf = false;
			if(resource.startswith_nocase("types of ")) {
				resource = resource.substr(9);
				typesOf = true;
			}

			//Detect resource level
			if(resource.startswith_nocase("level")) {
				req.level = toUInt(resource.substr(5));
				if(typesOf)
					req.type = RRT_Level_Types;
				else
					req.type = RRT_Level;

				reqs.insertLast(req);
				continue;
			}

			//Detect single resource amount
			const ResourceType@ res = getResource(resource);
			if(res !is null) {
				if(typesOf) {
					error("Invalid resource specifier: "+parts[i]);
					error("  Cannot take types of specific resource.");
					continue;
				}

				req.type = RRT_Resource;
				@req.resource = res;

				reqs.insertLast(req);
				continue;
			}

			//Detect resource class
			const ResourceClass@ cls = getResourceClass(resource);
			if(cls !is null) {
				if(typesOf)
					req.type = RRT_Class_Types;
				else
					req.type = RRT_Class;
				@req.cls = cls;

				reqs.insertLast(req);
				continue;
			}

			error("Invalid resource specifier: "+parts[i]);
			error("  Unknown resource '"+resource+"'.");
		}

		reqs.sortAsc();
	}
};

tidy class Resource : Serializable, Savable {
	int id = -1;
	const ResourceType@ type;
	Object@ origin;
	Object@ exportedTo;
	bool usable = true;
	bool locked = false;
	uint8 disabled = 0;
	double vanishTime;
	float efficiency = 1.f;
	any[] data;

	void write(Message& msg) {
		msg.writeLimited(type.id, resources::resources.length-1);
		msg.writeSmall(id);
		msg << origin;
		msg << exportedTo;
		msg << usable;
		msg << disabled;
		msg << efficiency;
		msg << locked;
		if(type.vanishMode != VM_Never)
			msg << float(vanishTime);
	}

	void read(Message& msg) {
		@type = getResource(msg.readLimited(resources::resources.length-1));
		id = msg.readSmall();
		msg >> origin;
		msg >> exportedTo;
		msg >> usable;
		msg >> disabled;
		msg >> efficiency;
		msg >> locked;
		if(type.vanishMode != VM_Never)
			vanishTime = msg.read_float();
	}

	void save(SaveFile& msg) {
		msg.writeIdentifier(SI_Resource, type.id);
		msg << id;
		msg << origin;
		msg << exportedTo;
		msg << usable;
		msg << disabled;
		msg << vanishTime;
		msg << efficiency;
		msg << locked;
	}

	void load(SaveFile& msg) {
		uint res = msg.readIdentifier(SI_Resource);
		@type = getResource(res);
		data.length = type.hooks.length;

		msg >> id;
		msg >> origin;
		msg >> exportedTo;
		msg >> usable;
		msg >> disabled;
		msg >> vanishTime;
		msg >> efficiency;

		if(msg >= SV_0027)
			msg >> locked;
	}

	void descFrom(const Resource@ other) {
		if(other is null) {
			id = -1;
			@type = null;
			@exportedTo = null;
			return;
		}
		id = other.id;
		@type = other.type;
		@origin = other.origin;
		@exportedTo = other.exportedTo;
		usable = other.usable;
		locked = other.locked;
		disabled = other.disabled;
		vanishTime = other.vanishTime;
		efficiency = other.efficiency;
	}

	int opCmp(const Resource& other) const {
#section client
		if(exportedTo is null && other.exportedTo !is null)
			return 1;
		if(exportedTo !is null && other.exportedTo is null)
			return -1;
		if(other.exportedTo is origin)
			return 1;
		if(exportedTo is other.origin)
			return -1;
#section all
		if(type is null || other.type is null)
			return 0;
		if(type.displayWeight > other.type.displayWeight)
			return 1;
		else if(type.displayWeight < other.type.displayWeight)
			return -1;
		if(type.level < other.type.level)
			return -1;
		if(type.level > other.type.level)
			return 1;
		if(type.rarityScore > other.type.rarityScore)
			return -1;
		if(type.rarityScore < other.type.rarityScore)
			return 1;
		if(type.id < other.type.id)
			return -1;
		if(type.id > other.type.id)
			return 1;
		return 0;
	}
};

tidy final class QueuedImport : Resource {
	Empire@ forEmpire;

	void save(SaveFile& msg) {
		Resource::save(msg);
		msg << forEmpire;
	}

	void load(SaveFile& msg) {
		Resource::load(msg);
		msg >> forEmpire;
	}

	void writeQueued(Message& msg) {
		Resource::write(msg);
		msg << forEmpire;
	}

	void readQueued(Message& msg) {
		Resource::read(msg);
		msg >> forEmpire;
	}
};

tidy final class QueuedResource : Serializable, Savable {
	Empire@ forEmpire;
	int id = -1;
	Object@ to;
	bool locked;

	void write(Message& msg) {
		msg << forEmpire;
		msg << id;
		msg << to;
		msg << locked;
	}

	void read(Message& msg) {
		msg >> forEmpire;
		msg >> id;
		msg >> to;
		msg >> locked;
	}

	void save(SaveFile& msg) {
		msg << forEmpire;
		msg << id;
		msg << to;
		msg << locked;
	}

	void load(SaveFile& msg) {
		msg >> forEmpire;
		msg >> id;
		msg >> to;
		if(msg >= SV_0027)
			msg >> locked;
	}
};

tidy class AutoImportDesc : Serializable {
	Object@ to;
	const ResourceType@ type;
	const ResourceClass@ cls;
	int level = -1;
	bool handled = false;

	void write(Message& msg) {
		msg << to;
		if(type !is null) {
			msg.write1();
			msg.writeSmall(type.id);
		}
		else {
			msg.write0();
		}
		if(cls !is null) {
			msg.write1();
			msg.writeSmall(cls.id);
		}
		else {
			msg.write0();
		}
		msg.writeSignedSmall(level);
		msg << handled;
	}

	void read(Message& msg) {
		msg >> to;
		if(msg.readBit())
			@type = getResource(msg.readSmall());
		else
			@type = null;
		if(msg.readBit())
			@cls = getResourceClass(msg.readSmall());
		else
			@cls = null;
		level = msg.readSignedSmall();
		msg >> handled;
	}

	bool equivalent(const AutoImportDesc& other) const {
		return type is other.type && cls is other.cls && level == other.level;
	}

	bool satisfies(const ResourceType@ type, bool alreadyPresent = false) {
		if(type.mode != RM_Normal)
			return false;
		if(!alreadyPresent && !type.exportable)
			return false;
		if(level != -1 && type.level != uint(level))
			return false;
		if(cls !is null && type.cls !is cls)
			return false;
		if(this.type !is null && type !is this.type)
			return false;
		return true;
	}
};

int getGroupSize(const Design@ dsg) {
	return ceil(40.0 / sqrt(dsg.size));
}

namespace resources {
	::dictionary resourceIdents;
	::ResourceType@[] resources;
	double totalFrequency = 0.0;
	double asteroidFrequency = 0.0;

	::dictionary classIdents;
	::ResourceClass@[] resClasses;
};

tidy final class RarityFrequency {
	double totalDistribution = 0.0;
	array<ResourceType@> types;
};
tidy final class LevelFrequency {
	double totalDistribution = 0.0;
	array<ResourceType@> types;
	array<RarityFrequency> rarities(6);
};
array<LevelFrequency> LevelFrequencies(4);

uint getResourceCount() {
	return resources::resources.length;
}

const ResourceType@ getResource(uint id) {
	if(id >= resources::resources.length)
		return null;
	return resources::resources[id];
}

int getResourceID(const string& ident) {
	ResourceType@ type;
	resources::resourceIdents.get(ident, @type);
	if(type !is null)
		return int(type.id);
	return -1;
}

string getResourceIdent(int id) {
	if(id < 0 || id >= int(resources::resources.length))
		return "-";
	return resources::resources[id].ident;
}

const ResourceType@ getResource(const string& ident) {
	ResourceType@ type;
	resources::resourceIdents.get(ident, @type);
	return type;
}

const ResourceType@ getDistributedResourceContest(double contestation) {
	uint tries = 0;
	const ResourceType@ type;
	do {
		@type = getDistributedResource();
		++tries;
	}
	while(tries < 10 && type.requireContestation > contestation);
	return type;
}

const ResourceType@ getDistributedResource() {
	double num = randomd(0, resources::totalFrequency);
	double orig = num;
	for(uint i = 0, cnt = resources::resources.length; i < cnt; ++i) {
		const ResourceType@ type = resources::resources[i];
		double freq = type.rarityScore;

		if(num <= freq)
			return type;
		num -= freq;
	}
	return resources::resources[resources::resources.length-1];
}

const ResourceType@ getDistributedResource(uint level) {
	auto@ lFreq = LevelFrequencies[level];
	double num = randomd(0, lFreq.totalDistribution);
	double orig = num;
	for(uint i = 0, cnt = lFreq.types.length; i < cnt; ++i) {
		const ResourceType@ type = lFreq.types[i];
		double freq = type.distribution;

		if(num <= freq)
			return type;
		num -= freq;
	}
	return lFreq.types[lFreq.types.length-1];
}

const ResourceType@ getRandomResource(uint level) {
	auto@ lFreq = LevelFrequencies[level];
	if(lFreq.types.length == 0)
		return null;
	return lFreq.types[randomi(0,lFreq.types.length-1)];
}

const ResourceType@ getDistributedAsteroidResource() {
	double num = randomd(0, resources::asteroidFrequency);
	const ResourceType@ type;
	for(uint i = 0, cnt = resources::resources.length; i < cnt; ++i) {
		@type = resources::resources[i];
		if(type.asteroidFrequency <= 0.0)
			continue;

		double freq = type.asteroidFrequency;
		if(num <= freq)
			return type;
		num -= freq;
	}
	return type;
}

void markResourceUsed(const ResourceType@ type) {
	if(type.unique) {
		ResourceType@ mut = resources::resources[type.id];

		uint lev = clamp(type.level, 0, 3);
		if(type.rarityLevel != -1)
			lev = clamp(type.rarityLevel, 0, 3);

		uint rar = clamp(uint(type.rarity), 0, 3);
		LevelFrequencies[lev].totalDistribution -= type.distribution;
		LevelFrequencies[lev].rarities[rar].totalDistribution -= type.distribution;

		resources::totalFrequency -= mut.rarityScore;
		resources::asteroidFrequency -= mut.asteroidFrequency;
		mut.rarityScore = 0;
		mut.distribution = 0;
		mut.asteroidFrequency = 0;
	}
}

const ResourceClass@ getResourceClass(uint id) {
	if(id >= resources::resClasses.length)
		return null;
	return resources::resClasses[id];
}

const ResourceClass@ getResourceClass(string ident) {
	ResourceClass@ type;
	resources::classIdents.get(ident, @type);
	return type;
}

uint getResourceClassCount() {
	return resources::resClasses.length;
}

void parseLine(string& line, ResourceType@ r, ReadFile@ file) {
	if(line.findFirst("(") == -1) {
		//Pressure line
		array<string>@ decls = line.split(",");
		for(uint i = 0, cnt = decls.length; i < cnt; ++i) {
			array<string>@ parts = decls[i].split(" ");
			if(parts.length != 3 || !parts[2].trimmed().equals_nocase("pressure")) {
				error("Invalid pressure spec: "+escape(decls[i]));
				continue;
			}

			uint resource = getTileResource(parts[1]);
			if(resource == TR_INVALID) {
				error("Invalid pressure spec: "+escape(decls[i]));
				continue;
			}

			int amt = toInt(parts[0]);
			r.tilePressure[resource] += amt;
		}
	}
	else {
		//Hook line
		auto@ hook = cast<IResourceHook>(parseHook(line, "resource_effects::", instantiate=false, file=file));
		if(hook !is null)
			r.hooks.insertLast(hook);
	}
}

void loadResources(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	ResourceType@ r;
	bool advance = true;
	while(!advance || file++) {
		key = file.key;
		value = file.value;
		advance = true;
		
		if(file.fullLine) {
			if(r is null) {
				error("Missing 'Resource: ID' line in " + filename);
				continue;
			}

			string line = file.line;
			parseLine(line, r, file);
		}
		else if(key == "Resource") {
			if(r !is null)
				addResourceType(r);
			@r = ResourceType();
			r.ident = value;
		}
		else if(key == "Level Chain") {
			advance = !readLevelChain(file);
		}
		else if(r is null) {
			error("Missing 'Resource: ID' line in " + filename);
		}
		else if(key == "Name") {
			r.name = localize(value);
		}
		else if(key == "Description") {
			r.description = localize(value);
		}
		else if(key == "Blurb") {
			r.blurb = localize(value);
		}
		else if(key == "Native Biome") {
			r.nativeBiome = value;
		}
		else if(key == "Class") {
			r.className = value;
		}
		else if(key == "DLC") {
			r.dlc = value;
		}
		else if(key == "Level") {
			r.level = toUInt(value);
			if(r.cargoWorth == 0)
				r.cargoWorth = (r.level+1) * CARGO_WORTH_LEVEL;
		}
		else if(key == "Rarity Level") {
			r.rarityLevel = toInt(value);
		}
		else if(key == "Limitless Level") {
			r.limitlessLevel = toBool(value);
		}
		else if(key == "Can Be Terraformed") {
			r.canBeTerraformed = toBool(value);
		}
		else if(key == "Frequency") {
			r.frequency = toDouble(value);
		}
		else if(key == "Distribution") {
			r.distribution = toDouble(value);
		}
		else if(key == "Vanish Time") {
			r.vanishTime = toDouble(value);
		}
		else if(key == "Cargo Worth") {
			r.cargoWorth = toInt(value);
		}
		else if(key == "Vanish Mode") {
			if(value == "Never")
				r.vanishMode = VM_Never;
			else if(value == "When Exported")
				r.vanishMode = VM_WhenExported;
			else if(value == "Always")
				r.vanishMode = VM_Always;
			else if(value == "Exported In Combat")
				r.vanishMode = VM_ExportedInCombat;
			else if(value == "Custom")
				r.vanishMode = VM_Custom;
			else
				error("Invalid vanish mode: "+value);
		}
		else if(key == "Artificial") {
			r.artificial = toBool(value);
			if(r.artificial)
				r.distribution = 0.0;
		}
		else if(key == "Exportable") {
			r.exportable = toBool(value);
		}
		else if(key == "Unique") {
			r.unique = toBool(value);
		}
		else if(key == "Require Contestation") {
			r.requireContestation = toDouble(value);
		}
		else if(key == "Mode") {
			if(value == "Normal")
				r.mode = RM_Normal;
			else if(value == "Universal")
				r.mode = RM_Normal;
			else if(value == "Universal Unique")
				r.mode = RM_UniversalUnique;
			else if(value == "Non Requirement")
				r.mode = RM_NonRequirement;
			else
				error("Invalid resource mode: "+value);
		}
		else if(key == "Affinity") {
			uint aff = getAffinityFromDesc(value);
			if(aff != A_NULL)
				r.addAffinity(aff);
		}
		else if(key == "Rarity") {
			if(value == "Common")
				r.rarity = RR_Common;
			else if(value == "Uncommon")
				r.rarity = RR_Uncommon;
			else if(value == "Rare")
				r.rarity = RR_Rare;
			else if(value == "Epic")
				r.rarity = RR_Epic;
			else if(value == "Mythical")
				r.rarity = RR_Mythical;
			else if(value == "Unique") {
				r.rarity = RR_Unique;
				r.unique = true;
			}
			else
				error("Invalid resource rarity: "+value);
		}
		else if(key == "Display Requirement") {
			r.requirementDisplay = toBool(value);
		}
		else if(key == "Will Lock") {
			r.willLock = toBool(value);
		}
		else if(key == "Display Weight") {
			r.displayWeight = toDouble(value);
		}
		else if(key == "Asteroid Frequency") {
			r.asteroidFrequency = toDouble(value);
		}
		else if(key == "Asteroid Labor") {
			r.asteroidCost = toDouble(value);
		}
		else if(key == "Terraform Cost") {
			r.terraformCost = toInt(value);
		}
		else if(key == "Terraform Labor") {
			r.terraformLabor = toDouble(value);
		}
		else if(key == "Icon") {
			r.icon = getSprite(value);
		}
		else if(key == "Small Icon") {
			r.smallIcon = getSprite(value);
		}
		else if(key == "Distant Icon") {
			//TODO
		}
		else if(key == "Pressure") {
			array<string>@ decls = value.split(",");
			for(uint i = 0, cnt = decls.length; i < cnt; ++i) {
				array<string>@ parts = decls[i].split(" ");
				if(parts.length != 2) {
					error("Invalid pressure spec: "+escape(decls[i]));
					continue;
				}

				uint resource = getTileResource(parts[1]);
				if(resource == TR_INVALID) {
					error("Invalid pressure spec: "+escape(decls[i]));
					continue;
				}

				int amt = toInt(parts[0]);
				r.tilePressure[resource] += amt;
			}
		}
		else if(key.equals_nocase("AI")) {
			auto@ hook = parseHook(value, "ai.resources::", instantiate=false, file=file);
			if(hook !is null)
				r.ai.insertLast(hook);
			else
				file.error("Could not find AI hook "+value);
		}
		else {
			string line = file.line;
			parseLine(line, r, file);
		}
	}
	
	if(r !is null)
		addResourceType(r);
}

void preInit() {
	//Load resources
	FileList list("data/resources", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadResources(list.path[i]);

	//Calculate resource frequencies
	double rarTotal = 0;
	resources::totalFrequency = 0.0;
	for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
		ResourceType@ type = resources::resources[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			type.hooks[n].initialize(type, n);

		uint lev = clamp(type.level, 0, 3);
		if(type.rarityLevel != -1)
			lev = clamp(type.rarityLevel, 0, 3);
		uint rar = clamp(uint(type.rarity), 0, 5);

		LevelFrequency@ lFreq = LevelFrequencies[lev];
		RarityFrequency@ rFreq = lFreq.rarities[rar];

		double freq = 0.0;
		if(type.distribution > 0 && rFreq.totalDistribution > 0) {
			freq = LEVEL_DISTRIBUTION[lev] * RARITY_DISTRIBUTION[rar+lev*6] *
				(type.distribution / rFreq.totalDistribution) * type.frequency;

		}
		if(type.unique)
			freq *= config::UNIQUE_RESOURCE_OCCURANCE / 0.3;

		resources::totalFrequency += freq;
		type.rarityScore = freq;
	}
}

tidy final class ResourceSheet {
#section gui
	Sprite sprt;
	array<Material> mats;

	ResourceSheet(const Sprite& sprt) {
		this.sprt = sprt;

		mats.length = 6;
		mats[0] = material::PlanetLevel0;
		mats[1] = material::PlanetLevel1;
		mats[2] = material::PlanetLevel2;
		mats[3] = material::PlanetLevel3;
		mats[4] = material::PlanetLevel4;
		mats[5] = material::PlanetLevel5;
		for(uint i = 0; i < 6; ++i) {
			if(sprt.mat !is null)
				@mats[i].texture2 = sprt.mat.texture0;
			else if(sprt.sheet !is null)
				@mats[i].texture2 = sprt.sheet.material.texture0;
			mats[i].constant = true;
		}
	}

	~ResourceSheet() {
		for(uint i = 0; i < 6; ++i)
			mats[i].constant = false;
	}

	void getUV(uint resourceIcon, vec4f& uvs) {
		if(resourceIcon < 0xffffffff) {
			if(sprt.sheet !is null)
				sprt.sheet.getSourceUV(resourceIcon, uvs);
			else
				uvs = vec4f(0.f, 0.f, 1.f, 1.f);
		}
		else
			uvs = vec4f();
	}

	Material@ getMaterial(uint level) {
		return mats[clamp(level, 0, 5)];
	}
#section all
};

array<ResourceSheet@> sheets;
void init() {
	auto@ list = resources::resources;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
		if(type.smallIcon.valid) {
			if(!type.icon.valid)
				type.icon = type.smallIcon;
		}
		else if(type.icon.valid) {
			type.smallIcon = type.icon;
		}
		for(uint n = 0, ncnt = type.ai.length; n < ncnt; ++n) {
			if(!type.ai[n].instantiate())
				error("Could not instantiate AI hook: "+addrstr(type.ai[n])+" in resource "+type.ident);
		}
	}

#section gui
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ r = list[i];
		if(!r.smallIcon.valid)
			continue;

		//Find associated resource sheet
		ResourceSheet@ rs;
		for(uint n = 0, ncnt = sheets.length; n < ncnt; ++n) {
			if((sheets[n].sprt.sheet is r.smallIcon.sheet && r.smallIcon.sheet !is null)
					|| (sheets[n].sprt.mat is r.smallIcon.mat && r.smallIcon.mat !is null)) {
				@rs = sheets[n];
				break;
			}
		}

		if(rs is null) {
			@rs = ResourceSheet(r.smallIcon);
			sheets.insertLast(rs);
		}

		@r.distantSheet = rs;
	}
#section all
}

ThreadLocal<Resource@> res;
Resource@ _tempResource() {
	Resource@ r = res.get();
	if(r is null) {
		@r = Resource();
		res.set(r);
	}
	return r;
}

void addResourceType(ResourceType@ type) {
	//Add resource
	type.id = resources::resources.length;
	resources::resources.insertLast(@type);
	resources::resourceIdents.set(type.ident, @type);

	if(type.dlc.length != 0 && !hasDLC(type.dlc)) {
		type.distribution = 0.0;
		type.frequency = 0.0;
	}

	if(type.asteroidFrequency > 0) {
		if(type.vanishMode == VM_Never)
			type.asteroidFrequency *= config::ASTEROID_PERMANENT_FREQ;
		resources::asteroidFrequency += type.asteroidFrequency;
	}

	uint lev = type.level;
	if(type.rarityLevel != -1)
		lev = clamp(type.rarityLevel, 0, 3);

	LevelFrequency@ lFreq = LevelFrequencies[clamp(lev, 0, 3)];
	RarityFrequency@ rFreq = lFreq.rarities[clamp(uint(type.rarity), 0, 5)];

	lFreq.totalDistribution += type.distribution;
	lFreq.types.insertLast(type);
	rFreq.totalDistribution += type.distribution;
	rFreq.types.insertLast(type);
	
	//Figure out class
	if(type.className.length != 0) {
		ResourceClass@ cls;
		resources::classIdents.get(type.className, @cls);

		if(cls is null) {
			@cls = ResourceClass();
			cls.id = resources::resClasses.length;
			cls.ident = type.className;
			cls.name = localize("RESOURCE_CLASS_"+cls.ident);

			resources::resClasses.insertLast(cls);
			resources::classIdents.set(cls.ident, @cls);
		}

		@type.cls = cls;
		cls.types.insertLast(type);
	}

	//Calculate total pressure
	for(uint i = 0; i < TR_COUNT; ++i)
		type.totalPressure += type.tilePressure[i];
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = resources::resources.length; i < cnt; ++i) {
		ResourceType type = resources::resources[i];
		file.addIdentifier(SI_Resource, type.id, type.ident);
	}
}
