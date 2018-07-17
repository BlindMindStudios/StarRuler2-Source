import hooks;
import statuses;
from statuses import StatusHook;
import artifacts;
import planet_effects;
import tile_resources;
from bonus_effects import BonusEffect;
import listed_values;
from resources import MoneyType;

#section server
from empire import Creeps;
from objects.Artifact import createArtifact;
#section all

//ArtifactOnDestroy(<Type>, <Destroy Chance> = 0)
// Create an artifact of <Type> if the object gets destroyed.
class ArtifactOnDestroy : StatusHook {
	Document doc("When the object carrying this status is destroyed, spawn an artifact at its position.");
	Argument type(AT_Artifact, doc="Type of artifact to spawn.");
	Argument destroy_chance(AT_Decimal, "0", doc="Chance that the artifact is destroyed instead of dropping from the ship.");

#section server
	void onObjectDestroy(Object& obj, Status@ status, any@ data) {
		if(randomd() > arguments[1].decimal) {
			auto@ type = getArtifactType(arguments[0].integer);
			vec3d pos = obj.position + random3d(type.physicalSize * 4.0, type.physicalSize * 12.0);
			auto@ artifact = createArtifact(pos, type);
			if(obj.region !is null)
				artifact.orbitAround(obj.region.position);
		}
	}
#section all
};


//BombardEffect()
//	Applies the bombardment status on a planet
class BombardEffect : StatusHook {
	Document doc("Applies the bombardment effect on a planet.");

#section server
	void onAddStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null)
			pl.modBombardment(1);
	}
	
	void onRemoveStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null)
			pl.modBombardment(-1);
	}
#section all
};

//ReduceProductionPerStack(<Per Stack> = 1)
// Reduces any non-money income by <Per Stack> per stack.
class ReduceProductionPerStack : StatusHook {
	Document doc("Reduce random non-money incomes by a pressure-equivalent amount for every stack of this status.");
	Argument per_stack(AT_Decimal, "1", doc="Amount of pressure-equivalent income to remove per stack.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		if(!obj.isPlanet)
			return;
		array<double> current(TR_COUNT, 0.0);

		data.store(@current);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		if(!obj.isPlanet)
			return;
		array<double>@ current;
		data.retrieve(@current);
		for(uint i = 1; i < TR_COUNT; ++i) {
			if(current[i] > 0)
				obj.modResource(i, +current[i]);
		}
		@current = null;
		data.store(@current);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(!obj.isPlanet)
			return true;
		double target = arguments[0].decimal * double(status.stacks);
		double currentTotal = 0.0;
		array<double>@ current;
		data.retrieve(@current);
		for(uint i = 1; i < TR_COUNT; ++i) {
			double prod = obj.getResourceProduction(i);
			double cur = current[i];
			if(prod < 0) {
				if(cur > 0) {
					double amt = min(-prod, cur);
					obj.modResource(i, +amt);
					prod += amt;
					cur -= amt;
				}
			}
			currentTotal += cur;
		}
		if(currentTotal < target - 0.001) {
			uint base = randomi(0, TR_COUNT-1);
			for(uint i = 0; i < TR_COUNT-1 && currentTotal < target; ++i) {
				uint index = 1 + (base + i) % (TR_COUNT-1);
				double prod = obj.getResourceProduction(index);
				double cur = current[index];
				if(prod > 0) {
					double amt = min(prod, target - currentTotal);
					obj.modResource(index, -amt);
					currentTotal += amt;
					current[index] += amt;
				}
			}
		}
		else if(currentTotal > target + 0.001) {
			uint base = randomi(0, TR_COUNT-1);
			for(uint i = 0; i < TR_COUNT-1 && currentTotal > target; ++i) {
				uint index = 1 + (base + i) % (TR_COUNT-1);
				double prod = obj.getResourceProduction(index);
				double cur = current[index];
				if(cur > 0) {
					double amt = min(cur, currentTotal - target);
					obj.modResource(index, +amt);
					currentTotal -= amt;
					current[index] -= amt;
				}
			}
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		array<double>@ current;
		data.retrieve(@current);
		for(uint i = 1; i < TR_COUNT; ++i)
			file << current[i];
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		array<double> current(TR_COUNT, 0.0);
		data.store(@current);
		for(uint i = 1; i < TR_COUNT; ++i)
			file >> current[i];
	}
#section all
};

//ApplyToFlagships()
// Only apply this status to flagships.
class ApplyToFlagships : StatusHook {
	Document doc("When this status is added to a system, it applies to flagships only.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return obj !is null && obj.isShip && obj.hasLeaderAI;
	}
};

class ApplyToPlanets : StatusHook {
	Document doc("When this status is added to a system, it applies to planets only.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return obj !is null && obj.isPlanet;
	}
};

class ApplyToUncolonizedPlanets : StatusHook {
	Document doc("When this status is added to a system, it applies to uncolonized planets only.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return obj !is null && obj.isPlanet && (obj.owner is null || !obj.owner.valid);
	}
};

class ApplyToColonizedPlanets : StatusHook {
	Document doc("When this status is added to a system, it applies to colonized planets only.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return obj !is null && obj.isPlanet && (obj.owner !is null && obj.owner.valid);
	}
};

tidy final class RepeatStacks : StatusHook {
	Document doc("Repeat a generic hook for every stack present.");
	Argument code(AT_Hook, "status_effects::IStatusHook", doc="Hook to repeat.");
	Argument per_stack(AT_Integer, "1", doc="Amount of times to repeat per stack.");
	Argument max_repeats(AT_Integer, "0", doc="If set to more than 0, the hook will never repeat more than that amount of times.");

	IStatusHook@ hook;

	bool instantiate() override {
		@hook = cast<IStatusHook>(parseHook(arguments[0].str, "status_effects::"));
		if(hook is null) {
			error("RepeatStacks(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return StatusHook::instantiate();
	}

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		array<any> datlist;
		data.store(@datlist);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return true;

		uint oldCnt = datlist.length;
		uint newCnt = per_stack.integer * status.stacks;
		if(max_repeats.integer > 0 && newCnt > uint(max_repeats.integer))
			newCnt = max_repeats.integer;
		for(uint i = newCnt; i < oldCnt; ++i)
			hook.onDestroy(obj, status, datlist[i]);
		datlist.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			hook.onCreate(obj, status, datlist[i]);
		for(uint i = 0; i < newCnt; ++i)
			hook.onTick(obj, status, datlist[i], time);
		return true;
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.onDestroy(obj, status, datlist[i]);
		datlist.length = 0;
		@datlist = null;
		data.store(@datlist);
	}

	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return true;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.onOwnerChange(obj, status, datlist[i], prevOwner, newOwner);
		return true;
	}

	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion) override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return true;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.onRegionChange(obj, status, datlist[i], prevRegion, newRegion);
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		uint cnt = 0;
		if(datlist is null) {
			file << cnt;
			return;
		}

		cnt = datlist.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			hook.save(status, datlist[i], file);
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		array<any> datlist;
		uint cnt = 0;
		file >> cnt;
		datlist.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			hook.load(status, datlist[i], file);
		data.store(@datlist);
	}
#section all
};

tidy final class TriggerCreate : StatusHook {
	BonusEffect@ eff;
	Argument hook(AT_Hook, "bonus_effects::BonusEffect", doc="Hook to call.");

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::"));
		if(eff is null) {
			error("TriggerCreate(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return StatusHook::instantiate();
	}

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		eff.activate(obj, obj.owner);
	}
#section all
};

class ConditionSinglePressureType : StatusHook {
	Document doc("This condition can only be on planets with a primary resource with a single pressure type.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasResources)
			return false;
		auto@ type = getResource(obj.primaryResourceType);
		if(type is null)
			return false;

		uint count = 0;
		for(uint i = 0, cnt = type.tilePressure.length; i < cnt; ++i) {
			if(type.tilePressure[i] > 0)
				count += 1;
		}
		return count == 1;
	}
};

class ConditionBiome : StatusHook {
	Document doc("This condition can only be on planets that have a particular biome.");
	Argument biome(AT_PlanetBiome, doc="Biome to check for.");

#section server
	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasSurfaceComponent)
			return false;
		return obj.hasBiome(biome.integer);
	}
#section all
};

class ConditionMaxLevel : StatusHook {
	Document doc("This effect only applies on planets with resources at or below a maximum level.");
	Argument max_level(AT_Integer, doc="Highest level this can apply to.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasResources)
			return false;
		auto@ type = getResource(obj.primaryResourceType);
		if(type is null)
			return false;
		return int(type.level) <= max_level.integer;
	}
};

class ConditionMinLevel : StatusHook {
	Document doc("This effect only applies on planets with resources at or above a minimum level.");
	Argument min_level(AT_Integer, doc="Lowest level this can apply to.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasResources)
			return false;
		auto@ type = getResource(obj.primaryResourceType);
		if(type is null)
			return false;
		return int(type.level) >= min_level.integer;
	}
};

class ConditionDLC : StatusHook {
	Document doc("This condition can only be generated when a dlc is present.");
	Argument dlc(AT_Custom, doc="DLC to check for.");

	bool activated = false;
	bool instantiate() override {
		if(!StatusHook::instantiate())
			return false;
		activated = hasDLC(dlc.str);
		return true;
	}

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		return activated;
	}
};

class ConditionMinPressure : StatusHook {
	Document doc("This effect only applies on planets with resources with at least a certain amount of pressure.");
	Argument min_pressure(AT_Integer, doc="Least amount of pressure this can apply to.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasResources)
			return false;
		auto@ type = getResource(obj.primaryResourceType);
		if(type is null)
			return false;
		return type.totalPressure >= min_pressure.integer;
	}
};

class ConditionMaxPressure : StatusHook {
	Document doc("This effect only applies on planets with resources up to a certain amount of pressure.");
	Argument max_pressure(AT_Integer, doc="Maximum amount of pressure this can apply to.");

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const override {
		if(!obj.hasResources)
			return false;
		auto@ type = getResource(obj.primaryResourceType);
		if(type is null)
			return false;
		return type.totalPressure <= max_pressure.integer;
	}
};

tidy final class TriggerColonized : StatusHook {
	BonusEffect@ eff;
	Argument hook(AT_Hook, "bonus_effects::BonusEffect", doc="Hook to call.");

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::"));
		if(eff is null) {
			error("TriggerColonized(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return StatusHook::instantiate();
	}

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(!obj.isPlanet)
			return false;

		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return true;
		if(obj.population < 0.9999)
			return true;

		eff.activate(obj, owner);
		return false;
	}
#section all
};

class VisibleToOriginEmpire : StatusHook {
	Document doc("The object is always visible to the origin empire of this status.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(status.originEmpire !is null)
			obj.donatedVision |= status.originEmpire.mask;
		return true;
	}
#section all
};

class GivesVisionToOriginEmpire : StatusHook {
	Document doc("The object gives vision in the system it is in to the origin empire of this status.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		Region@ reg = obj.region;
		if(status.originEmpire !is null && reg !is null)
			reg.grantVision(status.originEmpire);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		Region@ reg = obj.region;
		if(status.originEmpire !is null && reg !is null)
			reg.revokeVision(status.originEmpire);
	}

	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion) override {
		if(status.originEmpire !is null && prevRegion !is null)
			prevRegion.revokeVision(status.originEmpire);
		if(status.originEmpire !is null && newRegion !is null)
			newRegion.grantVision(status.originEmpire);
		return true;
	}
#section all
};

tidy final class RoamSystems : StatusHook {
	Document doc("Roam through systems, triggering a bonus hook for each visited.");
	Argument hook(AT_Hook, "bonus_effects::BonusEffect");
	Argument origin_empires(AT_Boolean, "False", doc="Whether to only visit empires that are related to the origin object.");

#section server
	BonusEffect@ eff;
	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::"));
		if(eff is null) {
			error("RoamOccupiedSystems(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return StatusHook::instantiate();
	}

	void onCreate(Object& obj, Status@ status, any@ data) override {
		if(status.originObject !is null) {
			obj.addGotoOrder(status.originObject, true);
			if(origin_empires.boolean) {
				uint mask = 0;
				if(status.originObject.isRegion)
					mask = cast<Region>(status.originObject).PlanetsMask;
				else {
					Empire@ owner = status.originObject.owner;
					if(owner !is null)
						mask = owner.mask;
				}
				data.store(mask);
			}
		}
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(!obj.valid)
			return false;
		if(obj.orderCount == 0) {
			//Trigger for this system
			Region@ reg = obj.region;
			if(reg !is null)
				eff.activate(obj.region, status.originEmpire);

			//Find next system to go to
			if(reg is null) {
				if(status.originObject is null || !status.originObject.isRegion)
					return false;
				obj.addGotoOrder(status.originObject, true);
			}

			uint mask = ~0;
			if(origin_empires.boolean)
				data.retrieve(mask);
			auto@ sys = getSystem(reg);
			array<SystemDesc@> poss;
			for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
				auto@ other = getSystem(sys.adjacent[i]);
				if(mask == ~0 || other.object.PlanetsMask & mask != 0)
					poss.insertLast(other);
			}

			SystemDesc@ target;
			if(poss.length == 0) {
				if(sys.adjacent.length == 0) {
					if(status.originObject is null || !status.originObject.isRegion)
						return false;
					obj.addGotoOrder(status.originObject, true);
					return true;
				}
				else {
					@target = getSystem(sys.adjacent[randomi(0, sys.adjacent.length-1)]);
				}
			}
			else {
				@target = poss[randomi(0, poss.length-1)];
			}

			obj.addGotoOrder(target.object, true);
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		uint mask = 0;
		data.retrieve(mask);
		file << mask;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		uint mask = 0;
		file >> mask;
		data.store(mask);
	}
#section all
};

class RemoveOnOwnerChange : StatusHook {
	Document doc("This status is removed when the object changes owners.");

#section server
	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) override {
		return false;
	}
#section all
};

class IsTriggerStatus : StatusHook {
	Document doc("This status is removed immediately after triggering.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		return false;
	}
#section all
};

class RemoveIfInCombat : StatusHook {
	Document doc("Remove this status when the object is in combat.");
	Argument timer(AT_Decimal, "0", doc="Time to wait after creation of the status before checking for combat.");
	Argument skip_timer_nocombat(AT_Boolean, "True", doc="Whether to skip the wait timer if the ship was not in combat when the status was created.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double delay = timer.decimal;
		if(skip_timer_nocombat.boolean && !obj.inCombat)
			delay = 0;
		data.store(delay);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double delay = 0;
		data.retrieve(delay);

		if(delay > 0) {
			delay -= time;
			data.store(delay);
		}
		else {
			if(obj.inCombat)
				return false;
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		double delay = 0;
		data.retrieve(delay);
		file << delay;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		double delay = 0;
		file >> delay;
		data.store(delay);
	}
#section all
};

class RemoveOnAttackOrder : StatusHook {
	Document doc("Remove the status when the ship receives an attack order.");
	Argument remove_when_range(AT_Boolean, "True", doc="Only remove the status when in range.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(!obj.hasLeaderAI)
			return true;
		Object@ targ = obj.getAttackTarget();
		if(targ is null)
			return true;
		if(!remove_when_range.boolean)
			return false;
		return obj.getAttackDistance() > obj.getEngagementRange() + obj.radius + targ.radius;
	}
#section all
};

class EnergyMaintenance : StatusHook {
	Document doc("This status requires an amount of energy per second in maintenance, or it will fail.");
	Argument amount(AT_Decimal, "0", doc="Base amount of energy per second it costs.");
	Argument per_shipsize(AT_Decimal, "0", doc="When on a ship, increase the energy per second by the ship design size multiplied by this.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double amt = amount.decimal;
		if(per_shipsize.decimal != 0 && obj.isShip)
			amt += cast<Ship>(obj).blueprint.design.size * per_shipsize.decimal;

		if(obj.owner !is null)
			obj.owner.modEnergyUse(amt);
		data.store(amt);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		double amt = 0;
		data.retrieve(amt);

		if(obj.owner !is null)
			obj.owner.modEnergyUse(-amt);
	}

	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) override {
		double amt = 0;
		data.retrieve(amt);
		if(prevOwner !is null)
			prevOwner.modEnergyUse(-amt);
		if(newOwner !is null)
			newOwner.modEnergyUse(amt);
		return true;
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(obj.owner !is null && obj.owner.EnergyShortage)
			return false;
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class ConstructOrbital : StatusHook {
	Document doc("This status automatically constructs the orbital it is on over time.");
	Argument duration(AT_Decimal, doc="Time that the orbital takes before it finishes construction.");
	Argument remove_status(AT_Boolean, "True", doc="Whether to remove this status after the construction finishes.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double timer = 0;
		data.store(timer);

		if(obj.isOrbital)
			cast<Orbital>(obj).setDisabled(true);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		if(obj.isOrbital)
			cast<Orbital>(obj).setDisabled(false);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double timer = 0;
		data.retrieve(timer);

		if(timer < duration.decimal) {
			timer += time;
			data.store(timer);

			if(obj.isOrbital)
				cast<Orbital>(obj).setBuildPct(timer / duration.decimal);

			if(timer >= duration.decimal) {
				if(obj.isOrbital)
					cast<Orbital>(obj).setDisabled(false);
				if(remove_status.boolean)
					return false;
			}
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		double time = 0;
		data.retrieve(time);
		file << time;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		double time = 0;
		file >> time;
		data.store(time);
	}
#section all
};

class AbandonOnDisableIfSameOrigin : StatusHook {
	Document doc("If this status has the same origin empire as the object's owner, abandon the planet when it gets disabled.");

#section server
	void onDestroy(Object& obj, Status@ status, any@ data) override {
		if(obj.hasSurfaceComponent) {
			if(obj.owner is status.originEmpire)
				obj.forceAbandon();
		}
	}
#section all
};

class ForcePopulationToStacks : StatusHook {
	Document doc("Force the planet to always have the same amount of population as this status' stack count.");
	Argument factor(AT_Decimal, "1.0", doc="Multiplication factor to stack count.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(obj.hasSurfaceComponent) {
			double curPop = obj.population;
			double targPop = double(status.stacks) * factor.decimal;
			if(curPop != targPop)
				obj.addPopulation(targPop - curPop);
		}
		return true;
	}
#section all
};

tidy final class EnabledData {
	bool enabled = false;
	any data;
};

tidy final class OnOriginEmpire : StatusHook {
	EmpireEffect@ eff;

	Document doc("Apply an effect on the origin empire of the status, if it has one.");
	Argument hookID("Hook", AT_Hook, "empire_effects::EmpireEffect");
	Argument allow_same(AT_Boolean, "True", doc="Whether to also apply the effect if the origin empire is the object's current owner.");

	bool instantiate() override {
		@eff = cast<EmpireEffect>(parseHook(hookID.str, "empire_effects::", required=false));
		if(eff is null) {
			error("OnOriginEmpire(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return StatusHook::instantiate();
	}

	bool check(Object& obj, Status@ status) {
		if(status.originEmpire is null)
			return false;
		if(!allow_same.boolean && obj.owner is status.originEmpire)
			return false;
		return true;
	}

	void onCreate(Object& obj, Status@ status, any@ data) {
		EnabledData enab;
		data.store(@enab);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) {
		EnabledData@ enab;
		data.retrieve(@enab);
		if(enab !is null && enab.enabled)
			eff.disable(status.originEmpire, enab.data);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) {
		EnabledData@ enab;
		data.retrieve(@enab);

		bool shouldEnable = check(obj, status);
		if(enab.enabled != shouldEnable) {
			if(shouldEnable) {
				eff.enable(status.originEmpire, enab.data);
				enab.enabled = true;
			}
			else {
				eff.disable(status.originEmpire, enab.data);
				enab.enabled = false;
			}
		}

		if(enab.enabled)
			eff.tick(status.originEmpire, enab.data, time);
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) {
		EnabledData@ enab;
		data.retrieve(@enab);

		file << enab.enabled;
		if(enab.enabled)
			eff.save(enab.data, file);
	}

	void load(Status@ status, any@ data, SaveFile& file) {
		EnabledData enab;
		data.store(@enab);

		file >> enab.enabled;
		if(enab.enabled)
			eff.load(enab.data, file);
	}
};

tidy final class TriggerWithOriginEmpire : StatusHook {
	Document doc("Trigger the effect with the empire set to the origin empire of this status.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect", doc="Hook to call.");

	BonusEffect@ hook;

	bool instantiate() override {
		if(hookID.str != "bonus_effects::BonusEffect")
			@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::"));
		return StatusHook::instantiate();
	}

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		if(hook !is null)
			hook.activate(obj, status.originEmpire);
	}
#section all
};

tidy final class RemoveOnWarWithOriginEmpire : StatusHook {
	Document doc("This status is removed when the empire goes to war with the origin empire.");
	Argument trigger_owner(AT_Hook, "bonus_effects::EmpireTrigger", doc="Hook to call on the owner empire when it happens.");
	Argument trigger_origin(AT_Hook, "bonus_effects::EmpireTrigger", doc="Hook to call on the origin empire when it happens.");

	BonusEffect@ ownerHook;
	BonusEffect@ originHook;

	bool instantiate() override {
		if(trigger_owner.str != "bonus_effects::EmpireTrigger")
			@ownerHook = cast<BonusEffect>(parseHook(trigger_owner.str, "bonus_effects::"));
		if(trigger_origin.str != "bonus_effects::EmpireTrigger")
			@originHook = cast<BonusEffect>(parseHook(trigger_origin.str, "bonus_effects::"));
		return StatusHook::instantiate();
	}

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(status.originEmpire is null)
			return true;
		if(obj.owner.isHostile(status.originEmpire)) {
			if(ownerHook !is null)
				ownerHook.activate(obj, obj.owner);
			if(originHook !is null)
				originHook.activate(obj, status.originEmpire);
			return false;
		}
		return true;
	}
#section all
};

class GivePlanetIncomeToOriginEmpire : StatusHook {
	Document doc("Give a percentage of this planet's income to the origin empire.");
	Argument percentage(AT_Decimal, doc="Percentage of planet income to give.");
	Argument allow_same(AT_Boolean, "False", doc="Whether to also apply the effect if the origin empire is the object's current owner.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) {
		int amount = 0;
		data.store(amount);
	}

	void onDestroy(Object& obj, Status@ status, any@ data) {
		int amount = 0;
		data.retrieve(amount);

		if(amount != 0 && status.originEmpire !is null)
			status.originEmpire.modTotalBudget(-amount, MoT_Misc);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) {
		if(status.originEmpire is null)
			return true;

		int curAmount = 0;
		data.retrieve(curAmount);

		int newAmount = 0;
		if(obj.owner !is status.originEmpire || allow_same.boolean) {
			if(obj.hasSurfaceComponent)
				newAmount = max(double(obj.income) * percentage.decimal, 0.0);
		}

		if(newAmount != curAmount) {
			status.originEmpire.modTotalBudget(newAmount - curAmount, MoT_Misc);
			data.store(newAmount);
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) {
		int amount = 0;
		data.retrieve(amount);
		file << amount;
	}

	void load(Status@ status, any@ data, SaveFile& file) {
		int amount = 0;
		file >> amount;
		data.store(amount);
	}
#section all
};

class OnlyOriginEmpireCanCapture : StatusHook {
	Document doc("While this status is active, only the origin empire can capture the planet through siege.");
	Argument allow_same(AT_Boolean, "True", doc="Whether to allow the protection even if the owner is the same as the origin.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) {
		uint mask = ~0;
		if(status.originEmpire !is null) {
			if(allow_same.boolean || obj.owner !is status.originEmpire)
				mask &= ~status.originEmpire.mask;
		}
		if(mask != 0 && obj.hasSurfaceComponent)
			obj.protectFrom(mask);
		return true;
	}

	void onDestroy(Object& obj, Status@ status, any@ data) {
		if(obj.hasSurfaceComponent)
			obj.clearProtectedFrom();
	}
#section all
};

class SiegeFromOrigin : StatusHook {
	Document doc("This status is considered equivalent to a sieging fleet in orbit for the origin empire of the status.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(status.originEmpire !is null) {
			obj.fakeSiege(status.originEmpire.mask);
			if(obj.getLoyaltyFacing(status.originEmpire) <= 0)
				obj.annex(status.originEmpire);
		}
		return true;
	}

	void onDestroy(Object& obj, Status@ status, any@ data) {
		if(status.originEmpire !is null)
			obj.clearFakeSiege(status.originEmpire.mask);
	}
#section all
};

class RemoveIfNotWar : StatusHook {
	Document doc("Remove this status if the owner is not at war with the status origin empire.");

#section server
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(status.originEmpire !is null) {
			if(!status.originEmpire.isHostile(obj.owner))
				return false;
		}
		return true;
	}
#section all
};

class RemoveIfNoRemnantsInSystem : StatusHook {
	Document doc("Remove this status if there are no remnants in the system.");
	Argument timer(AT_Decimal, "30", doc="Don't remove the status for this amount of time after it is created.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double delay = timer.decimal;
		data.store(delay);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double delay = 0;
		data.retrieve(delay);

		if(delay > 0) {
			delay -= time;
			data.store(delay);
		}
		else {
			Region@ reg = obj.region;
			if(reg !is null && reg.getStrength(Creeps) <= 0)
				return false;
		}
		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		double delay = 0;
		data.retrieve(delay);
		file << delay;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		double delay = 0;
		file >> delay;
		data.store(delay);
	}
#section all
};

class ProduceNativePressurePct : StatusHook {
	Document doc("Produce a percentage of the native resource's pressure.");
	Argument base(AT_Decimal, "0", doc="Percentage to produce.");
	Argument per_stack(AT_Decimal, "0", doc="Percentage to add per stack.");

#section server
	void onCreate(Object& obj, Status@ status, any@ data) override {
		double pct = 0.0;
		data.store(pct);
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		double prevPct = 0.0;
		data.retrieve(prevPct);

		double newPct = base.decimal;
		newPct += per_stack.decimal * status.stacks;

		if(newPct != prevPct) {
			auto@ resource = getResource(obj.primaryResourceType);
			if(resource is null) {
				newPct = 0.0;
			}
			else {
				for(uint i = 0; i < TR_COUNT; ++i) {
					double prev = double(resource.tilePressure[i]) * prevPct;
					double cur = double(resource.tilePressure[i]) * newPct;
					if(prev != cur)
						obj.modResource(i, cur - prev);
				}
			}

			data.store(newPct);
		}

		return true;
	}

	void onDestroy(Object& obj, Status@ status, any@ data) override {
		double pct = 0;
		data.retrieve(pct);

		auto@ resource = getResource(obj.primaryResourceType);
		if(resource !is null) {
			for(uint i = 0; i < TR_COUNT; ++i) {
				double prev = double(resource.tilePressure[i]) * pct;
				obj.modResource(i, -prev);
			}
		}
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		double pct = 0;
		data.retrieve(pct);
		file << pct;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		double pct = 0;
		file >> pct;
		data.store(pct);
	}
#section all
};

tidy final class OnRemoveStatusAttribLT : StatusHook {
	Document doc("When this status is removed and an attribute is lower than a specified value, trigger the effect.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Value to check.");

	BonusEffect@ eff;
	Argument hook(AT_Hook, "bonus_effects::BonusEffect", doc="Hook to call.");

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::"));
		if(eff is null) {
			error("TriggerCreate(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return StatusHook::instantiate();
	}

#section server
	void onDestroy(Object& obj, Status@ status, any@ data) {
		if(obj.owner.getAttribute(attribute.integer) < value.decimal)
			eff.activate(obj, obj.owner);
	}
#section all
};
