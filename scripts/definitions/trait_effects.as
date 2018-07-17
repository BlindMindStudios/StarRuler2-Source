import traits;
import influence;
from traits import TraitEffect;
from bonus_effects import BonusEffect;
from planet_effects import GenericEffect;
from map_effects import MapHook;
import bonus_effects;
import research;
import hooks;
import statuses;
import empire_effects;
import util.design_export;

#section server
import object_creation;
from empire import Creeps;
import systems;
import regions.regions;
#section all

class HWData {
	Empire@ prevOwner;
	Region@ prevRegion;
	any data;
};

tidy final class OnHomeworld : TraitEffect {
	GenericEffect@ hook;
	BonusEffect@ bonus;

	Document doc("Apply the specified continuous effect on the homeworld.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(arguments[0].str, "planet_effects::", required=false));
		if(hook is null) {
			@bonus = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
			if(bonus is null)
				return false;
		}
		return TraitEffect::instantiate();
	}

	void init(Empire& emp, any@ data) const override {
		if(hook !is null) {
			HWData dat;
			data.store(@dat);

			hook.enable(emp.Homeworld, dat.data);
			@dat.prevOwner = emp.Homeworld.owner;
			@dat.prevRegion = emp.Homeworld.region;
		}
		else if(bonus !is null) {
			bonus.activate(emp.Homeworld, emp);
		}
	}

	void tick(Empire& emp, any@ data, double time) const override {
		if(hook is null)
			return;

		HWData@ dat;
		data.retrieve(@dat);

		Object@ hw = emp.Homeworld;
		if(hw is null)
			return;

		Empire@ owner = hw.owner;
		if(owner !is dat.prevOwner) {
			hook.ownerChange(hw, dat.data, dat.prevOwner, owner);
			@dat.prevOwner = owner;
		}

		Region@ region = hw.region;
		if(region !is dat.prevRegion) {
			hook.regionChange(hw, dat.data, dat.prevRegion, region);
			@dat.prevRegion = region;
		}

		hook.tick(hw, dat.data, time);
	}

	void save(any@ data, SaveFile& file) const override {
		if(hook is null)
			return;

		HWData@ dat;
		data.retrieve(@dat);

		file << dat.prevOwner;
		file << dat.prevRegion;
		hook.save(dat.data, file);
	}

	void load(any@ data, SaveFile& file) const override {
		if(hook is null)
			return;

		HWData dat;
		data.store(@dat);

		file >> dat.prevOwner;
		file >> dat.prevRegion;
		hook.load(dat.data, file);
	}
};

tidy final class TriggerHomeworld : TraitEffect {
	BonusEffect@ bonus;

	Document doc("Apply the specified one-time trigger effect on the homeworld.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect");
	Argument run_post(AT_Boolean, "False", doc="Whether to run the trigger as a post init event.");

	bool instantiate() override {
		@bonus = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(bonus is null)
			return false;
		return TraitEffect::instantiate();
	}

	void init(Empire& emp, any@ data) const override {
		if(!run_post.boolean) {
			if(emp.Homeworld !is null && emp.Homeworld.valid)
				bonus.activate(emp.Homeworld, emp);
			else if(emp.HomeObj !is null)
				bonus.activate(emp.HomeObj, emp);
		}
	}

	void postInit(Empire& emp, any@ data) const override {
		if(run_post.boolean) {
			if(emp.Homeworld !is null && emp.Homeworld.valid)
				bonus.activate(emp.Homeworld, emp);
			else if(emp.HomeObj !is null)
				bonus.activate(emp.HomeObj, emp);
		}
	}
};

tidy final class InHomeSystem : TraitEffect {
	MapHook@ hook;

	Document doc("Apply the specified map generation effect on the home system.");
	Argument hookID("Hook", AT_Hook, "map_effects::IMapHook");

	bool instantiate() override {
		@hook = cast<MapHook>(parseHook(arguments[0].str, "map_effects::"));
		if(hook is null)
			return false;
		return TraitEffect::instantiate();
	}

#section server
	void init(Empire& emp, any@ data) const override {
		Region@ region = emp.HomeSystem;
		if(region is null && emp.Homeworld !is null)
			@region = getRegion(emp.Homeworld.position);
		if(region is null && emp.HomeObj !is null)
			@region = getRegion(emp.HomeObj.position);
		if(region is null)
			return;
		SystemDesc@ sys = getSystem(region);
		if(sys is null)
			return;
		Object@ current;
		hook.trigger(null, sys, current);
	}
#section all
};

tidy final class TriggerHomeSystem : TraitEffect {
	BonusEffect@ bonus;

	Document doc("Apply the specified one-time trigger effect on the home system.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect");
	Argument run_post(AT_Boolean, "False", doc="Whether to run the trigger as a post init event.");

	bool instantiate() override {
		@bonus = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(bonus is null)
			return false;
		return TraitEffect::instantiate();
	}

#section server
	void init(Empire& emp, any@ data) const override {
		if(!run_post.boolean) {
			Region@ region = emp.HomeSystem;
			if(region is null && emp.Homeworld !is null)
				@region = getRegion(emp.Homeworld.position);
			if(region is null && emp.HomeObj !is null)
				@region = getRegion(emp.HomeObj.position);
			if(region !is null)
				bonus.activate(region, emp);
		}
	}

	void postInit(Empire& emp, any@ data) const override {
		if(run_post.boolean) {
			Region@ region = emp.HomeSystem;
			if(region is null && emp.Homeworld !is null)
				@region = getRegion(emp.Homeworld.position);
			if(region is null && emp.HomeObj !is null)
				@region = getRegion(emp.HomeObj.position);
			if(region !is null)
				bonus.activate(region, emp);
		}
	}
#section all
};

tidy final class InRandomAdjacentSystem : TraitEffect {
	MapHook@ hook;

	Document doc("Apply the specified map generation effect on a random system adjacent to the home system.");
	Argument hookID("Hook", AT_Hook, "map_effects::IMapHook");

	bool instantiate() override {
		@hook = cast<MapHook>(parseHook(arguments[0].str, "map_effects::"));
		if(hook is null)
			return false;
		return TraitEffect::instantiate();
	}

#section server
	void init(Empire& emp, any@ data) const override {
		Region@ region = emp.HomeSystem;
		if(region is null && emp.Homeworld !is null)
			@region = getRegion(emp.Homeworld.position);
		if(region is null && emp.HomeObj !is null)
			@region = getRegion(emp.HomeObj.position);
		if(region is null)
			return;
		SystemDesc@ sys = getSystem(region);
		if(sys is null)
			return;
		if(sys.adjacent.length == 0)
			return;
		SystemDesc@ adj = getSystem(sys.adjacent[randomi(0, sys.adjacent.length-1)]);
		if(adj is null)
			return;
		Object@ current;
		hook.trigger(null, adj, current);
	}
#section all
};

tidy final class InAllAdjacentSystems : TraitEffect {
	MapHook@ hook;

	Document doc("Apply the specified map generation effect on all systems adjacent to the home system.");
	Argument hookID("Hook", AT_Hook, "map_effects::IMapHook");

	bool instantiate() override {
		@hook = cast<MapHook>(parseHook(arguments[0].str, "map_effects::"));
		if(hook is null)
			return false;
		return TraitEffect::instantiate();
	}

#section server
	void init(Empire& emp, any@ data) const override {
		Region@ region = emp.HomeSystem;
		if(region is null && emp.Homeworld !is null)
			@region = getRegion(emp.Homeworld.position);
		if(region is null && emp.HomeObj !is null)
			@region = getRegion(emp.HomeObj.position);
		if(region is null)
			return;
		SystemDesc@ sys = getSystem(region);
		if(sys is null)
			return;
		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			auto@ other = getSystem(sys.adjacent[i]);
			if(other is null)
				continue;
			Object@ current;
			hook.trigger(null, other, current);
		}
	}
#section all
};

class RemoveAllCards : TraitEffect {
	Document doc("Remove all influence cards the empire starts with.");

#section server
	void postInit(Empire& emp, any@ data) const override {
		array<InfluenceCard> cards;
		cards.syncFrom(emp.getInfluenceCards());
		for(uint i = 0, cnt = cards.length; i < cnt; ++i)
			emp.takeCardUse(cards[i].id, uint(-1));
	}
#section all
};

class LoadDesigns : TraitEffect {
	Document doc("Load default designs from a particular directory into the empire.");
	Argument directory(AT_Custom, doc="Relative path to the directory to add designs from.");
	Argument limit_shipset(AT_Boolean, "True", doc="Whether to only load designs that have a saved hull that matches the current shipset.");
	Argument retry_without_limit(AT_Boolean, "True", doc="Whether to override the shipset limit and load all designs if no designs were found.");

#section server
	DesignSet designs;

	bool instantiate() override {
		designs.readDirectory("data/designs/"+directory.str);
		designs.limitShipset = limit_shipset.boolean;
		designs.softLimitRetry = retry_without_limit.boolean;
		return TraitEffect::instantiate();
	}

	void init(Empire& emp, any@ data) const override {
		designs.createFor(emp);
	}
#section all
};

class PlanetReqData {
	double timer;
	set_int set;
	array<Planet@> list;
	array<int> ids;
};

class AddStatusPlanetsReqLevel : TraitEffect {
	Document doc("Add a status effect to all planets of a particular level or higher.");
	Argument level(AT_Integer, doc="Minimum level of planets that get the status.");
	Argument status(AT_Status, doc="Type of status to add to planets.");

#section server
	void init(Empire& emp, any@ data) const override {
		PlanetReqData list;
		data.store(@list);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		PlanetReqData@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		list.timer -= time;
		if(list.timer >= 0)
			return;
		uint minLevel = arguments[0].integer;
		list.timer = 5.0;

		//Check old
		for(int i = list.list.length - 1; i >= 0; --i) {
			Planet@ pl = list.list[i];
			if(pl.level < minLevel || pl.owner !is emp) {
				pl.removeStatus(list.ids[i]);
				list.list.removeAt(uint(i));
				list.ids.removeAt(uint(i));
				list.set.erase(pl.id);
			}
		}

		//Check new
		DataList@ objs = emp.getPlanets();
		Object@ obj;
		while(receive(objs, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(!list.set.contains(pl.id) && pl.level >= minLevel) {
				int id = pl.addStatus(-1.0, arguments[1].integer);
				list.list.insertLast(pl);
				list.ids.insertLast(id);
				list.set.insert(pl.id);
			}
		}
	}

	void save(any@ data, SaveFile& file) const override {
		PlanetReqData@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		file << list.timer;
		file << list.list.length;
		for(uint i = 0, cnt = list.list.length; i < cnt; ++i) {
			file << list.list[i];
			file << list.ids[i];
		}
	}

	void load(any@ data, SaveFile& file) const override {
		if(file >= SV_0043 && file.readBit()) {
			PlanetReqData list;
			data.store(@list);
			file >> list.timer;
			uint cnt = 0;
			file >> cnt;
			list.list.length = cnt;
			list.ids.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				file >> list.list[i];
				file >> list.ids[i];
				list.set.insert(list.list[i].id);
			}
		}
	}
#section all
};

class SetColonizerInfo : TraitEffect {
	Document doc("Change the properties of what this race's colonizers look like.");
	Argument name(AT_Locale, "#COLONY_SHIP", doc="Name of a colonizer.");
	Argument model(AT_Custom, EMPTY_DEFAULT, doc="Model to use for the colonizer.");
	Argument material(AT_Custom, EMPTY_DEFAULT, doc="Material to use for the colonizer.");

	void init(Empire& emp, any@ data) const override {
		emp.ColonizerName = name.str;
		if(model.str.length != 0) {
			emp.ColonizerModel = model.str;
			emp.ColonizerMaterial = material.str;
		}
	}
};

tidy final class IfHaveTrait : TraitEffect {
	Document doc("Only apply the inner hook if the empire also has another trait. Cannot be used for continuous effects, only ones applied once at game start.");
	Argument trait(AT_Trait, doc="Trait to check for.");
	Argument hookID("Hook", AT_Hook, "trait_effects::TraitEffect");
	Argument elseID("Else", AT_Hook, "", "trait_effects::TraitEffect");
	ITraitEffect@ hook;
	ITraitEffect@ elseHook;

	bool instantiate() override {
		@hook = cast<ITraitEffect>(parseHook(hookID.str, "trait_effects::"));
		if(elseID.str.length != 0)
			@elseHook = cast<ITraitEffect>(parseHook(elseID.str, "trait_effects::"));
		return TraitEffect::instantiate();
	}

	void preInit(Empire& emp, any@ data) const {
		if(emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.preInit(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.preInit(emp, data);
		}
	}

	void init(Empire& emp, any@ data) const {
		if(emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.init(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.init(emp, data);
		}
	}

	void postInit(Empire& emp, any@ data) const {
		if(emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.postInit(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.postInit(emp, data);
		}
	}
};

tidy final class IfNotHaveTrait : TraitEffect {
	Document doc("Only apply the inner hook if the empire does not have another trait. Cannot be used for continuous effects, only ones applied once at game start.");
	Argument trait(AT_Trait, doc="Trait to check for.");
	Argument hookID("Hook", AT_Hook, "trait_effects::TraitEffect");
	Argument elseID("Else", AT_Hook, "", "trait_effects::TraitEffect");
	ITraitEffect@ hook;
	ITraitEffect@ elseHook;

	bool instantiate() override {
		@hook = cast<ITraitEffect>(parseHook(hookID.str, "trait_effects::"));
		if(elseID.str.length != 0)
			@elseHook = cast<ITraitEffect>(parseHook(elseID.str, "trait_effects::"));
		return TraitEffect::instantiate();
	}

	void preInit(Empire& emp, any@ data) const {
		if(!emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.preInit(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.preInit(emp, data);
		}
	}

	void init(Empire& emp, any@ data) const {
		if(!emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.init(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.init(emp, data);
		}
	}

	void postInit(Empire& emp, any@ data) const {
		if(!emp.hasTrait(trait.integer)) {
			if(hook !is null)
				hook.postInit(emp, data);
		}
		else {
			if(elseHook !is null)
				elseHook.postInit(emp, data);
		}
	}
};

class AddRandomTrait : TraitEffect {
	Document doc("Add a random trait with a particular unique tag to the empire.");
	Argument unique_type(AT_Custom, doc="'Unique' tag to select a trait from.");
	Argument ignore_trait(AT_Trait, EMPTY_DEFAULT, doc="A trait to ignore in the randomization.");
	Argument only_available(AT_Boolean, "True", doc="Whether to only choose from traits that are normally available to be chosen.");

#section server
	void preInit(Empire& emp, any@ data) const {
		const Trait@ ourType;
		const Trait@ type;
		double total = 0;
		const ITraitEffect@ cmp = this;
		for(uint i = 0, cnt = getTraitCount(); i < cnt; ++i) {
			auto@ other = getTrait(i);
			for(uint n = 0, ncnt = other.hooks.length; n < ncnt; ++n) {
				const ITraitEffect@ oth = other.hooks[n];
				if(oth is cmp) {
					@ourType = other;
					break;
				}
			}
			if(only_available.boolean && !other.available)
				continue;
			if(other is ourType)
				continue;
			if(other.cost != 0)
				continue;
			if(other.id == uint(ignore_trait.integer))
				continue;
			if(other.unique == unique_type.str) {
				total += 1;
				if(randomd() < 1.0 / total)
					@type = other;
			}
		}

		if(type !is null)
			emp.addTrait(type.id, doPreInit=true);
	}
#section all
};

tidy final class RepeatLargestFlagshipBuiltSize : TraitEffect {
	Document doc("Repeat a trigger every time a flagship larger than the previously biggest flagship is built, repeats depending on size.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::EmpireTrigger");
	EmpireTrigger@ hook;
	Argument repeat_per(AT_Decimal, "10", doc="Repeat once for every time the largest ever design goes up by this amount.");
	Argument start_from(AT_Decimal, "100", doc="Don't count size increments below this total size (starting ships).");

#section server
	bool instantiate() override {
		@hook = cast<EmpireTrigger>(parseHook(hookID.str, "bonus_effects::"));
		return TraitEffect::instantiate();
	}

	void init(Empire& emp, any@ data) const override {
		double maxSize = 0;
		data.store(maxSize);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		double previous = 0;
		data.retrieve(previous);

		uint ind = randomi(0, emp.fleetCount-1);
		Ship@ fleet = cast<Ship>(emp.fleets[ind]);
		if(fleet !is null && !fleet.isStation) {
			const Design@ dsg = fleet.blueprint.design;
			if(dsg !is null && dsg.owner is emp) {
				double flSize = floor(dsg.size / repeat_per.decimal) * repeat_per.decimal;
				if(flSize > previous) {
					int repeats = floor(flSize / repeat_per.decimal);
					repeats -= floor(max(previous, start_from.decimal) / repeat_per.decimal);

					if(repeats > 0) {
						for(uint i = 0; i < uint(repeats); ++i)
							hook.activate(null, emp);
					}

					data.store(flSize);
				}
			}
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double val = 0;
		data.retrieve(val);
		file << val;
	}

	void load(any@ data, SaveFile& file) const override {
		double val = 0;
		file >> val;
		data.store(val);
	}
#section all
};

class ClearFirstBudget : TraitEffect {
	Document doc("Make sure the first budget of the game for this empire is 0.");

#section server
	void tick(Empire& emp, any@ data, double time) const override {
		if(gameTime < 2.0)
			emp.consumeBudget(emp.RemainingBudget, false);
	}
#section all
};

class PeaceWithRemnants : TraitEffect {
	Document doc("This empire will not be attacked by remnants.");

#section server
	void init(Empire& emp, any@ data) const override {
		Creeps.setHostile(emp, false);
		emp.setHostile(Creeps, false);
	}
#section all
};

class VisData {
	set_int visionSystems;
	array<int> list;
	uint index = 0;
}

class GrantVisionTradeRange : TraitEffect {
	Document doc("You automatically get vision over all systems within your trade range, even if you have no objects there.");

#section server
	void init(Empire& emp, any@ data) const override {
		VisData info;
		data.store(@info);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		VisData@ info;
		data.retrieve(@info);

		for(uint n = 0; n < 50; ++n) {
			info.index = (info.index+1) % systemCount;
			auto@ sys = getSystem(info.index);

			bool has = info.visionSystems.contains(info.index);
			bool should = hasTradeAdjacent(emp, sys.object);

			if(has != should) {
				if(should) {
					info.visionSystems.insert(info.index);
					info.list.insertLast(info.index);
					sys.object.grantVision(emp);
				}
				else {
					info.visionSystems.erase(info.index);
					info.list.remove(info.index);
					sys.object.revokeVision(emp);
				}
			}
		}
	}

	void save(any@ data, SaveFile& file) const override {
		VisData@ info;
		data.retrieve(@info);

		uint cnt = info.list.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << info.list[i];
	}

	void load(any@ data, SaveFile& file) const override {
		VisData info;
		data.store(@info);

		uint cnt = 0;
		file >> cnt;
		info.list.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			file >> info.list[i];
			info.visionSystems.insert(info.list[i]);
		}
	}
#section all
};
