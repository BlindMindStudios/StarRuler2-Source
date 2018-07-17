import resources;
import util.formatting;
import planet_effects;
import saving;
from bonus_effects import BonusEffect;

//MorphIntoImport()
// Morphs into the first imported resource.
class MorphIntoImport : ResourceHook {
	Document doc("This resource morphs into a copy of the first resource imported to its object.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return locale::UNOBTANIUM_EFFECT;
	}

#section server
	void onTick(Object& obj, Resource@ r, double time) const override {
		uint availCnt = obj.availableResourceCount;
		if(availCnt > 1) {
			for(uint i = 0; i < availCnt; ++i) {
				auto@ type = getResource(obj.availableResourceType[i]);
				if(type !is null && type !is r.type && !type.artificial) {
					obj.removeResource(r.id);
					obj.addResource(type.id);
					break;
				}
			}
		}
	}
#section all
};


//PopResearch(<Per Billion>)
// Produces <Per Billion> tiles worth of research per billion population.
class PopResearch : ResourceHook {
	Document doc("Increases reseearch income by a pressure-equivalent amount based on the amount of population present.");
	Argument per_billion(AT_Decimal, doc="Amount of research to add for each population.");
	
	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return format(locale::EFFECT_POPRESEARCH, toString(1.0 / arguments[0].decimal,0));
	}

#section server
	void onTick(Object& obj, Resource@ r, double time) const override {
		Planet@ pl = cast<Planet>(obj);
		if(pl is null)
			return;
	
		int prev = 0;
		r.data[hookIndex].retrieve(prev);
		
		int amt = int(pl.Population * arguments[0].decimal);
		if(amt != prev) {
			obj.modResource(TR_Research, amt - prev);
			r.data[hookIndex].store(amt);
		}
	}

	void load(Resource@ r, SaveFile& file) const override {
		int amt = 0;
		file >> amt;
		r.data[hookIndex].store(amt);
	}
	
	void save(Resource@ r, SaveFile& file) const override {
		int amt = 0;
		r.data[hookIndex].retrieve(amt);
		file << amt;
	}

	void onAdd(Object& obj, Resource@ r) const override {
		int amt = 0;
		r.data[hookIndex].store(amt);
	}

	void onRemove(Object& obj, Resource@ r) const override {
		int prev = 0;
		r.data[hookIndex].retrieve(prev);
		if(prev != 0) {
			obj.modResource(TR_Research, -prev);
			r.data[hookIndex].store(0);
		}
	}
#section all
};

//AsteroidGraphics()
// Add some floating asteroid graphics around the planet.
class AsteroidGraphics : ResourceHook {
	Document doc("Add some floating asteroid graphics around the planet.");

#section server
	void applyGraphics(Object& obj, Node& node) const {
		if(obj.isPlanet) {
			PlanetNode@ plNode = cast<PlanetNode>(node);
			if(plNode !is null)
				plNode.giveAsteroids();
		}
	}
#section all
};

//AddPermanentFTLStorage(<Amount>)
// Adds <Amount> FTL storage permanently.
class AddPermanentFTLStorage : ResourceHook {
	Document doc("Add permanent FTL storage capacity, even if the resource is later lost.");
	Argument amount(AT_Integer, doc="Amount of FTL storage capacity to add.");

#section server
	void onAdd(Object& obj, Resource@ r) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modFTLCapacity(+arguments[0].integer);
	}

	void onOwnerChange(Object& obj, Resource@ r, Empire@ prevOwner, Empire@ newOwner) const override {
		if(newOwner !is null && newOwner.valid)
			newOwner.modFTLCapacity(+arguments[0].integer);
	}
#section all
};

//VanishWhenConstructing()
// Custom vanish mode for vanishing when the consuming object is constructing something.
class VanishWhenConstructing : ResourceHook {
	Document doc("Used for resources with Vanish Mode: Custom. Only tick down the resource while the planet is actively using labor.");

#section server
	bool shouldVanish(Object& obj, Resource@ native) const override {
		Object@ target = native.exportedTo;
		if(target is null)
			@target = native.origin;
		if(target is null || !target.hasConstruction)
			return false;
		return target.isUsingLabor;
	}
#section all
};

//VanishUnlessFTLFull()
// Custom vanish mode that doesn't vanish if the ftl storage is full.
class VanishUnlessFTLFull : ResourceHook {
	Document doc("Used for resources with Vanish Mode: Custom. Only tick down the resource while the empire's FTL storage is not full.");

#section server
	bool shouldVanish(Object& obj, Resource@ native) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.FTLStored >= owner.FTLCapacity - 0.0001)
			return false;
		return true;
	}
#section all
};

//ResourceBonding(<Amount> = <Planet Resource>, ....)
// Bonds this resource into creating other resources
final class BondData {
	uint amount = 2;
	string resourceName;
	const ResourceType@ type;

	int opCmp(const BondData& other) const {
		if(amount < other.amount)
			return -1;
		if(amount > other.amount)
			return 1;
		return 0;
	}
};

class ResourceBonding : ResourceHook {
	array<BondData> list;
	Document doc("Generate new resources by bonding with copies of the current resource. Arguments must be added manually.");

	bool parse(const string& name, array<string>& args) {
		list.length = args.length;
		for(uint i = 0, cnt = args.length; i < cnt; ++i) {
			int pos = args[i].findFirst("=");
			if(pos == -1) {
				error("Invalid resource bond argument: "+escape(args[i]));
				return false;
			}
			list[i].amount = max(2, toUInt(args[i].substr(0, pos)));
			list[i].resourceName = args[i].substr(pos+1).trimmed();
		}
		list.sortAsc();
		return true;
	}

#section server
	void initialize(ResourceType@ type, uint index) override {
		ResourceHook::initialize(type, index);
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			@list[i].type = getResource(list[i].resourceName);
			if(list[i].type is null)
				error("Error: ResourceBonding(): could not find resource "+list[i].resourceName);
		}
	}

	void onGenerate(Object& obj, Resource@ r) const {
		int64 id = -1;
		r.data[hookIndex].store(id);
	}

	void onDestroy(Object& obj, Resource@ r) const {
		int64 id = -1;
		r.data[hookIndex].retrieve(id);
		if(id != -1) {
			obj.removeResource(id);
			id = -1;
			r.data[hookIndex].store(id);
		}
	}

	void setResource(Object& obj, Resource@ r, int64& id, any@ data, const ResourceType@ type) {
		if(type is null) {
			if(id == -1)
				return;
		}
		else if(type.id == obj.nativeResourceByID[id])
			return;

		Object@ target;
		if(id != -1) {
			@target = obj.getNativeResourceDestinationByID(obj.owner, id);
			obj.removeResource(id);
		}
		else {
			@target = r.exportedTo;
		}

		if(type !is null) {
			id = obj.addResource(type.id);

			if(target !is null) {
				obj.exportResourceByID(id, target);
				if(r.exportedTo !is null)
					obj.exportResourceByID(r.id, null);
			}
		}
		else {
			id = -1;

			if(target !is null)
				obj.exportResourceByID(r.id, target);
		}
		data.store(id);
	}

	void nativeTick(Object& obj, Resource@ r, double time) const override {
		int64 id = -1;
		r.data[hookIndex].retrieve(id);

		Object@ curExp;
		if(id != -1)
			@curExp = obj.getNativeResourceDestinationByID(obj.owner, id);

		uint count = obj.getAvailableResourceAmount(r.type.id);
		if(r.exportedTo !is null && r.exportedTo is curExp && r.usable)
			count += 1;

		if(count > 1) {
			//Should only work for the first native water
			for(uint i = 0, cnt = obj.nativeResourceCount; i < cnt; ++i) {
				if(obj.nativeResourceType[i] == r.type.id) {
					if(obj.nativeResourceId[i] != r.id)
						count = 0;
					break;
				}
			}
		}

		const ResourceType@ res;
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			if(count >= list[i].amount)
				@res = list[i].type;
			else
				break;
		}

		setResource(obj, r, id, r.data[hookIndex], res);
	}

	void load(Resource@ r, SaveFile& file) const override {
		if(file < SV_0007) {
			int64 id = 0;
			file >> id;
		}
	}

	void nativeSave(Resource@ r, SaveFile& file) const override {
		int64 id = 0;
		r.data[hookIndex].retrieve(id);
		file << id;
	}

	void nativeLoad(Resource@ r, SaveFile& file) const override {
		if(file >= SV_0007) {
			int64 id = 0;
			file >> id;
			r.data[hookIndex].store(id);
		}
	}
#section all
};

//LockOnExport(Destroy Invalid = True)
// Locks the resource whenever it is first exported.
class LockOnExport : ResourceHook {
	Document doc("When the resource is first exported, it is locked and can no longer change its destination.");
	Argument destroy_invalid(AT_Boolean, "True", doc="If set, the resource is destroyed when the locked destination is no longer valid.");

#section server
	void nativeTick(Object& obj, Resource@ native, double time) const {
		if(native.exportedTo !is null && !native.locked)
			obj.setResourceLocked(native.id, true);
		if(arguments[0].boolean) {
			Object@ dest = obj.getNativeResourceDestinationByID(obj.owner, native.id);
			if(dest !is null && (!dest.valid || (dest.owner !is obj.owner && dest.owner.valid)))
				obj.removeResource(native.id);
		}
	}
#section all
};

//OnTradeDeliver(<Hook>())
// Triggers a bonus effect when delivering the resource with a civilian trade ship.
class OnTradeDeliver : ResourceHook {
	BonusEffect@ hook;

	Document doc("The inner hook is triggered when a civilian ship carrying this resource delivers its cargo.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(hook is null) {
			error("OnTradeDeliver(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return ResourceHook::instantiate();
	}

#section server
	void onTradeDeliver(Civilian& civ, Object@ origin, Object@ target) const override {
		if(target is null || !target.isRegion)
			hook.activate(target, civ.owner);
	}
#section all
};

//OnTradeDeliver(<Hook>())
// Triggers a bonus effect when delivering the resource with a civilian trade ship.
class OnTradeDestroy : ResourceHook {
	BonusEffect@ hook;

	Document doc("The inner hook is triggered when a civilian ship carrying this resource is destroyed.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(hook is null) {
			error("OnTradeDeliver(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return ResourceHook::instantiate();
	}

#section server
	void onTradeDestroy(Civilian& civ, Object@ origin, Object@ target, Object@ destroyer) const override {
		hook.activate(target, civ.owner);
	}
#section all
};

class RegenSurface : ResourceHook {
	Document doc("When the planet this resource is on is generated, create a new surface with a particular size and biome count.");
	Argument width(AT_Integer, doc="Surface grid width.");
	Argument height(AT_Integer, doc="Surface grid width.");
	Argument biome_count(AT_Integer, "3", doc="Amount of biomes on the planet.");
	Argument force_biome(AT_PlanetBiome, EMPTY_DEFAULT, doc="Force a particular biome as the planet's base biome.");

#section server
	void onGenerate(Object& obj, Resource@ native) const {
		obj.regenSurface(width.integer, height.integer, biome_count.integer);
		if(force_biome.str.length != 0) {
			auto@ type = getBiome(force_biome.str);
			if(type !is null)
				obj.replaceFirstBiomeWith(type.id);
		}
	}
#section all
};

class ForcePlanetType : ResourceHook {
	Document doc("Force the planet this is on to be a particular type.");
	Argument planet_type(AT_Custom, doc="Planet type identifier.");

#section server
	void onGenerate(Object& obj, Resource@ native) const {
		if(!obj.isPlanet)
			return;
		Planet@ pl = cast<Planet>(obj);
		const PlanetType@ planetType = getPlanetType(planet_type.str);
		if(planetType is null)
			return;
		pl.PlanetType = planetType.id;
		PlanetNode@ plNode = cast<PlanetNode>(pl.getNode());
		if(plNode !is null)
			plNode.planetType = planetType.id;
	}
#section all
};

class OnNative : ResourceHook {
	GenericEffect@ hook;
	Document doc("Run this hook on the resource's native planet, regardless of whether or to where it's being exported.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::"));
		if(hook is null) {
			error("OnNative(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return ResourceHook::instantiate();
	}

#section server
	void onGenerate(Object& obj, Resource@ native) const override {
		if(hook !is null)
			hook.enable(obj, native.data[hookIndex]);
	}

	void nativeTick(Object& obj, Resource@ native, double time) const override {
		if(hook !is null)
			hook.tick(obj, native.data[hookIndex], time);
	}

	void onDestroy(Object& obj, Resource@ native) const override {
		if(hook !is null)
			hook.disable(obj, native.data[hookIndex]);
	}

	void nativeSave(Resource@ native, SaveFile& file) const override {
		if(hook !is null)
			hook.save(native.data[hookIndex], file);
	}

	void nativeLoad(Resource@ native, SaveFile& file) const override {
		if(hook !is null)
			hook.load(native.data[hookIndex], file);
	}
#section all
};

class OnExportMoveLocalCargo : ResourceHook {
	Document doc("All cargo of a particular type on this object is moved to wherever this resource is exported.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to move.");

#section server
	void nativeTick(Object& obj, Resource@ native, double time) const override {
		Object@ targ = native.exportedTo;
		if(targ !is null && obj.getCargoStored(cargo_type.integer) > 0
				&& targ.hasCargo && targ.cargoCapacity > targ.cargoStored) {
			obj.transferCargoTo(cargo_type.integer, targ);
		}
	}
#section all
};

class NativeLevelChain : GenericEffect {
	Document doc("Change the native resource planet's level chain and requirements.");
	Argument chain(AT_Custom, doc="Chain to change to.");
	uint chainId = 0;

	bool instantiate() override {
		chainId = getLevelChainID(chain.str);
		if(chainId == uint(-1)) {
			chainId = 0;
			error("Cannot find planet level chain: "+chain.str);
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void onGenerate(Object& obj, Resource@ r) const {
		obj.setLevelChain(chainId);
	}
#section all
};
