import hooks;
import abilities;
import artifacts;
from abilities import AbilityHook;
import orbitals;
import target_filters;
from generic_effects import GenericEffect;
import systems;
import bonus_effects;
from map_effects import MakePlanet, MakeStar;
import listed_values;
import orders;
import attitudes;
#section server
import util.target_search;
from objects.Artifact import createArtifact;
import bool getCheatsEverOn() from "cheats";
from game_start import generateNewSystem;
from oddity_navigation import getPathDistance;
#section all

//SpawnOrbitalAt(<Destination>, <Core>, <Set Design> = False)
// Spawn an orbital at <Point Target> with <Core>.
// If <Set Design> is true, the design will be passed for packing.
class SpawnOrbitalAt : AbilityHook {
	Document doc("Creates an orbital at a 3D destination.");
	Argument destination(TT_Point);
	Argument core(AT_OrbitalModule, doc="Orbital core to create the orbital with.");
	Argument set_design(AT_Boolean, "False", doc="Whether this orbital should be able to unpack into the creating ship's design.");
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="Status effect to add to the orbital after it is created.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		vec3d point = destination.fromConstTarget(targs).point;
		Orbital@ orb = createOrbital(point, getOrbitalModule(core.integer), abl.emp);
		if(set_design.boolean) {
			const Design@ dsg;
			if(abl.obj !is null && abl.obj.isShip)
				@dsg = cast<Ship>(abl.obj).blueprint.design;
			if(dsg !is null)
				orb.sendDesign(OV_PackUp, dsg);
		}
		if(add_status.integer != -1)
			orb.addStatus(add_status.integer);
	}
#section all
};

class ReplaceWithOrbital : AbilityHook {
	Document doc("Replace the ability's object with a newly spawned orbital.");
	Argument type(AT_OrbitalModule, doc="Type of orbital core to use.");
	Argument creep_owned(AT_Boolean, "False", doc="Whether the orbital should be owned by the creeps.");
	Argument free(AT_Boolean, "False", doc="Whether to make the orbital free of maintenance.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;

		auto@ def = getOrbitalModule(type.integer);
		vec3d pos = abl.obj.position;
		auto@ orb = createOrbital(pos, def, creep_owned.boolean ? Creeps : abl.emp);
		if(free.boolean && !creep_owned.boolean)
			orb.makeFree();

		@abl.obj = orb;
	}
#section all
};

//GiveAchievement(<Achievement ID>)
// Unlocks the specified achievement for the empire's player, when activated
class GiveAchievement : AbilityHook {
	Document doc("Grants an achievement when the ability is activated.");
	Argument achievement(AT_Custom, doc="ID of the achievement.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		Empire@ owner = abl.emp;
		if(!owner.valid || getCheatsEverOn())
			return;
		if(owner is playerEmpire)
			unlockAchievement(achievement.str);
		if(mpServer && owner.player !is null)
			clientAchievement(owner.player, achievement.str);
	}
#section all
};

//ConsumeFTL(<Amount>)
// Consume an amount of FTL energy to activate this ability.
class ConsumeFTL : AbilityHook {
	Document doc("Requires a payment of FTL to activate this ability.");
	Argument cost("Amount", AT_Decimal, doc="FTL Cost.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost)
			return true;
		return abl.emp.FTLStored >= cost.decimal;
	}

	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override {
		value = format(locale::FTL_COST, toString(cost.decimal, 0));
		return true;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.emp.consumeFTL(cost.decimal, partial=false, record=false) == 0.0)
			return false;
		return true;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		abl.emp.modFTLStored(cost.decimal);
	}
#section all
};

class ConsumeMoney : AbilityHook {
	Document doc("Activating this ability requires a payment of money.");
	Argument cost("Amount", AT_Integer, doc="Money cost to activate.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost)
			return true;
		return abl.emp.canPay(cost.integer);
	}

	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override {
		value = formatMoney(cost.integer);
		return true;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.emp.consumeBudget(cost.integer) == -1)
			return false;
		return true;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		abl.emp.refundBudget(cost.integer, abl.emp.BudgetCycleId);
	}
#section all
};

class ConsumeStatus : AbilityHook {
	Document doc("Consumes an instance of a status on the object.");
	Argument type(AT_Status, doc="Type of status to take.");
	Argument amount(AT_Integer, "1", doc="Amount of cargo taken to build per status.");
	Argument hide(AT_Boolean, "False", doc="If the object has _no_ statuses of this type, hide the option.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		Object@ obj = abl.obj;
		if(obj is null || !obj.hasStatuses)
			return false;

		int val = obj.getStatusStackCountAny(type.integer);
		if(hide.boolean && val < amount.integer)
			return false;
		if(ignoreCost)
			return true;
		return val >= amount.integer;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		Object@ obj = abl.obj;
		if(obj is null || !obj.hasStatuses)
			return false;

		int count = obj.getStatusStackCount(type.integer);
		if(count < amount.integer)
			return false;

		for(int i = 0; i < amount.integer; ++i)
			obj.removeStatusInstanceOfType(type.integer);
		return true;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		Object@ obj = abl.obj;
		if(obj !is null && obj.hasStatuses)
			obj.addStatus(type.integer);
	}
#section all
};

class DistanceMoneyCost : AbilityHook {
	Document doc("This ability costs money to cast based on distance.");
	Argument destination(TT_Any, doc="Point to play them at.");
	Argument base_cost(AT_Decimal, "0", doc="Base cost per distance.");
	Argument sqrt_cost(AT_Decimal, "0", doc="Cost per square root of distance.");
	Argument square_cost(AT_Decimal, "0", doc="Cost per squared distance.");
	Argument extra_cost(AT_Decimal, "0", doc="Extra cost independent of distance.");

	int get(const Ability@ abl, const Targets@ targs) const {
		if(abl.obj is null || targs is null)
			return 0;
		auto@ tt = destination.fromConstTarget(targs);
		vec3d point;
		if(tt.type == TT_Point)
			point = tt.point;
		else if(tt.type == TT_Object && tt.obj !is null)
			point = tt.obj.position;
		double dist = point.distanceTo(abl.obj.position);
		double cost = extra_cost.decimal;
		if(base_cost.decimal != 0)
			cost += base_cost.decimal * dist;
		if(sqrt_cost.decimal != 0)
			cost += sqrt_cost.decimal * sqrt(dist);
		if(square_cost.decimal != 0)
			cost += square_cost.decimal * sqr(dist);
		return round(cost);
	}

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost)
			return true;
		return abl.emp.canPay(get(abl, targs));
	}

	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override {
		value = formatMoney(get(abl, targs));
		return true;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.emp.consumeBudget(get(abl, targs)) == -1)
			return false;
		return true;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		abl.emp.refundBudget(get(abl, targs), abl.emp.BudgetCycleId);
	}
#section all
};

class ConsumeInfluence : AbilityHook {
	Document doc("Activating this ability requires a payment of influence.");
	Argument cost("Amount", AT_Integer, doc="Influence cost to activate.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost)
			return true;
		return abl.emp.Influence >= cost.integer;
	}

	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override {
		value = toString(cost.integer, 0)+" "+locale::RESOURCE_INFLUENCE;
		return true;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.emp.consumeInfluence(cost.integer))
			return true;
		return false;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		abl.emp.modInfluence(+cost.integer);
	}
#section all
};

class ConsumeDistanceFTL : AbilityHook {
	Document doc("Ability consumes FTL based on the distance to the target.");
	Argument targ(TT_Object);
	Argument base_cost(AT_Decimal, "0", doc="Base FTL Cost.");
	Argument distance_cost(AT_Decimal, "0", doc="FTL Cost per unit of distance.");
	Argument sqrt_cost(AT_Decimal, "0", doc="FTL Cost per square root unit of distance.");
	Argument obey_free_ftl(AT_Boolean, "True", doc="Whether to reduce the cost to 0 if departing from a free ftl system.");
	Argument obey_block_ftl(AT_Boolean, "True", doc="Whether to disable the ability if departing or arriving in a blocked ftl system.");
	Argument path_distance(AT_Boolean, "False", doc="If set, use total path distance taking into account gates, slipstreams and wormholes.");

	double getCost(const Ability@ abl, const Targets@ targs) const{
		double cost = base_cost.decimal;
		auto@ t = targ.fromConstTarget(targs);
		if(t !is null && t.obj !is null && abl.obj !is null) {
			double dist = t.obj.position.distanceTo(abl.obj.position);
			if(path_distance.boolean) {
#section server
				dist = getPathDistance(abl.emp, t.obj.position, abl.obj.position);
#section client
				dist = getPathDistance(t.obj.position, abl.obj.position);
#section all
			}
			cost += distance_cost.decimal * dist;
			cost += sqrt_cost.decimal * sqrt(dist);
		}
		if(obey_free_ftl.boolean && abl.emp !is null && abl.obj !is null) {
			Region@ myReg = abl.obj.region;
			if(myReg !is null && myReg.FreeFTLMask & abl.emp.mask != 0)
				return 0.0;
		}
		return cost;
	}

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost || targs is null)
			return true;
		if(obey_block_ftl.boolean && abl.emp !is null) {
			auto@ t = targ.fromConstTarget(targs);
			if(t !is null && t.obj !is null && abl.obj !is null) {
				Region@ myReg = abl.obj.region;
				if(myReg !is null && myReg.BlockFTLMask & abl.emp.mask != 0)
					return false;
				Region@ targReg = t.obj.region;
				if(targReg !is null && targReg.BlockFTLMask & abl.emp.mask != 0)
					return false;
			}
		}
		return abl.emp.FTLStored >= getCost(abl, targs);
	}

	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override {
		if(targs is null)
			return false;
		value = format(locale::FTL_COST, toString(getCost(abl, targs), 0));
		return true;
	}

#section server
	bool consume(Ability@ abl, any@ data, const Targets@ targs) const override {
		double cost = getCost(abl, targs);
		if(cost == 0)
			return true;
		if(abl.emp.consumeFTL(cost, partial=false) == 0.0)
			return false;
		return true;
	}

	void reverse(Ability@ abl, any@ data, const Targets@ targs) const override {
		abl.emp.modFTLStored(getCost(abl, targs));
	}
#section all
};

//EnergyCostFromSubsystem(<Var = "EnergyCost">)
//	Sets the energy cost based on the subsystem variable
class EnergyCostFromSubsystem : AbilityHook {
	Document doc("Bases ability energy cost on a subsystem variable.");
	Argument varName("Variable", AT_Custom, doc="Name of subsystem variable.");
	SubsystemVariable var = SubsystemVariable(-1);

	bool instantiate() override {
		int ind = getSubsystemVariable(varName.str);
		if(ind < 0) {
			error("EnergyCostFromSubsystem(): No Subsystem variable '" + varName.str + "'");
			return false;
		}
		var = SubsystemVariable(ind);
		return AbilityHook::instantiate();
	}
	
	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.subsystem is null || !abl.subsystem.has(var))
			return;
		cost = abl.subsystem[var];
	}
};

//EmergencyResupply(<Var = "Resupply">)
//	Resupplies the fleet using this ability based on a subsystem's variable
class EmergencyResupply : AbilityHook {
	Document doc("Resupplies a fleet an amount based on a subsystem variable.");
	Argument varName("Variable", AT_Custom, doc="Name of subsystem variable.");
	SubsystemVariable var = SubsystemVariable(-1);

	bool instantiate() override {
		int ind = getSubsystemVariable(varName.str);
		if(ind < 0) {
			error("EmergencyResupply(): No Subsystem variable '" + varName.str + "'");
			return false;
		}
		var = SubsystemVariable(ind);
		return AbilityHook::instantiate();
	}
	
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		Ship@ ship = cast<Ship>(abl.obj);
		if(ship is null)
			return false;
		return ship.Supply < ship.MaxSupply;
	}
	
#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.subsystem is null || !abl.subsystem.has(var))
			return;
		Ship@ ship = cast<Ship>(abl.obj);
		if(ship is null)
			return;
		ship.refundSupply(abl.subsystem[var]);
	}
#section all
};

//RemotePlanetSiege(<Target>, <Time Per Loyalty> = 60.0)
// Gradually remotely siege <Target>.
class RemotePlanetSiege : AbilityHook {
	Document doc("Remotely sieges a target.");
	Argument planet(TT_Object);
	Argument time_per_loyalty(AT_Custom, doc="Seconds sieging takes per target loyalty.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		data.store(@planet.fromConstTarget(targs).obj);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		Object@ curTarget;
		data.retrieve(@curTarget);
		if(curTarget is null)
			return;

		curTarget.absoluteSiege(abl.emp, time * 1.0 / time_per_loyalty.decimal);
		if(curTarget.getLoyaltyFacing(abl.emp) <= 0) {
			curTarget.annex(abl.emp);
			@curTarget = null;
		}
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		Object@ targ;
		data.retrieve(@targ);
		file << targ;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		Object@ targ;
		file >> targ;
		data.store(@targ);
	}
#section all
};

//Trigger(<Object>, <Hook>(...))
// Run <Hook> as a single-time effect hook on <Planet>.
tidy final class Trigger : AbilityHook {
	Document doc("Runs a triggered hook on the target when the ability activates.");
	Argument targ(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("Trigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(hook !is null)
			hook.activate(objTarg.obj, abl.emp);
		else if(eff !is null)
			eff.enable(objTarg.obj, null);
	}
#section all
};

tidy final class TriggerIfOwnedOrSpace : AbilityHook {
	Document doc("Runs a triggered hook on the target when the ability activates, but only if the target is owned by space or the triggering empire.");
	Argument targ(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("Trigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(objTarg.obj.owner.valid && objTarg.obj.owner !is abl.emp)
			return;
		if(hook !is null)
			hook.activate(objTarg.obj, abl.emp);
		else if(eff !is null)
			eff.enable(objTarg.obj, null);
	}
#section all
};

tidy final class TriggerIfSpace : AbilityHook {
	Document doc("Runs a triggered hook on the target when the ability activates, but only if the target is owned by space.");
	Argument targ(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("Trigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(objTarg.obj.owner.valid)
			return;
		if(hook !is null)
			hook.activate(objTarg.obj, abl.emp);
		else if(eff !is null)
			eff.enable(objTarg.obj, null);
	}
#section all
};

tidy final class IfTargetOwnedOrSpace : AbilityHook {
	Document doc("Runs a trigger on the object CASTING the ability, but only if the target object is owned by space or the triggering empire.");
	Argument targ(TT_Object);
	Argument hookID("Hook", AT_Hook, "ability_effects::IAbilityHook", doc="Hook to run.");
	IAbilityHook@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<IAbilityHook>(parseHook(hookID.str, "ability_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("Trigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

	bool initTargets(Targets@ targets) override {
		if(hook !is null)
			cast<Hook>(hook).initTargets(targets);
		return AbilityHook::initTargets(targets);
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(objTarg.obj.owner.valid && objTarg.obj.owner !is abl.emp)
			return;
		if(hook !is null)
			hook.activate(abl, data, targs);
		else if(eff !is null)
			eff.enable(abl.obj, null);
	}
#section all
};

tidy final class SpendStatusForTrigger : AbilityHook {
	Document doc("Run triggered hooks whenever a status instance can be spent to do so.");
	Argument status(AT_Status, doc="Status effect to consume.");
	Argument objTarg(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	Argument interval(AT_Decimal, "0", doc="Minimum interval between activations for toggle targets.");
	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("SpendStatusForTrigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void create(Ability@ abl, any@ data) const override {
		double interval = 0;
		data.store(interval);
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		double interval = 0;
		data.store(interval);
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;
		auto@ objTarg = objTarg.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(abl.obj.getStatusStackCount(status.integer) == 0)
			return;
		if(hook is null)
			return;
		hook.activate(objTarg.obj, abl.emp);
		abl.obj.removeStatusInstanceOfType(status.integer);

		double interval = 0;
		data.store(interval);
	}

	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;

		double timer = 0;
		data.retrieve(timer);
		timer += time;
		data.store(timer);

		if(timer < interval.decimal)
			return;
		timer = 0;
		data.store(timer);

		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;
		if(target.valid && abl.canActivate(abl.targets, ignoreCost=true))
			activate(abl, data, abl.targets);
	}
#section all
};

tidy final class TriggerEffectOnce : AbilityHook {
	Document doc("Triggers the enabling of a generic hook on the target object. Note that any effects triggered will be static single time and permanent, due to the triggered nature.");
	Argument planet(TT_Object);
	Argument hookID("Hook", AT_Hook, "planet_effects::TriggerableGeneric", doc="Hook to run.");
	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(eff is null) {
			error("OnPlanet(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = planet.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(eff !is null)
			eff.enable(objTarg.obj, null);
	}
#section all
};

//RequirePositiveBudget()
// Ability can only be used at positive budget.
class RequirePositiveBudget : AbilityHook {
	Document doc("Require positive budget to activate this ability.");
	
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		return abl.emp.RemainingBudget > 0;
	}
};

//Repeat(<Amount>, <Hook>)
// Execute hook <Hook> multiple times.
tidy final class Repeat : AbilityHook {
	Document doc("Runs another type of hook repeatedly.");
	Argument repeats(AT_Range, doc="Number of times to run the hook.");
	Argument hookID("Hook", AT_Hook, "ability_effects::IAbilityHook", doc="Hook to run.");
	IAbilityHook@ hook;

	bool instantiate() override {
		@hook = cast<IAbilityHook>(parseHook(hookID.str, "ability_effects::"));
		if(hook is null) {
			error("Repeat(): could not find inner ability hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const {
		uint amount = int(repeats.fromRange());
		for(uint i = 0; i < amount; ++i)
			hook.activate(abl, data, targs);
	}
#section all
};


//MorphResourceIntoNative(<Target>)
// Morph the native resource of the source into the native resource of the target.
class MorphResourceIntoNative : AbilityHook {
	Document doc("Copies the target's native resource over the activating object's native resource.");
	Argument object(TT_Object);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		Object@ source = abl.obj;
		Object@ target = object.fromConstTarget(targs).obj;
		if(source is null || target is null)
			return;

		auto@ type = getResource(target.nativeResourceType[0]);
		if(type is null)
			return;

		source.startTerraform();
		source.terraformTo(type.id);
	}
#section all
};

class IsToggleTarget : AbilityHook {
	Document doc("Track the target as a toggle effect.");
	Argument objTarg(TT_Object);
	Argument check_range(AT_Boolean, "True", doc="Whether to deactivate when out of range.");
	Argument range_margin(AT_Decimal, "1.5", doc="The factor of activate range at which it deactivates.");
	Argument channels(AT_Boolean, "True", doc="Whether to wait until the target is lost before completing the ability order.");

	bool isChanneling(const Ability@ abl, const any@ data) const override {
		const Target@ storeTarg = objTarg.fromConstTarget(abl.targets);
		return channels.boolean && storeTarg !is null && storeTarg.obj !is null;
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		const Target@ trigTarg = objTarg.fromConstTarget(targs);
		Target storeTarg = objTarg.fromTarget(abl.targets);

		if(trigTarg is null || storeTarg is null)
			return;

		if(trigTarg.obj is storeTarg.obj || trigTarg.obj is abl.obj)
			@storeTarg.obj = null;
		else
			storeTarg = trigTarg;

		abl.changeTarget(objTarg, storeTarg);
	}

	void destroy(Ability@ abl, any@ data) const {
		Target storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		@storeTarg.obj = null;
		abl.changeTarget(objTarg, storeTarg);
	}

	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;
		if(!target.valid || (check_range.boolean && target.position.distanceToSQ(abl.obj.position) > sqr(abl.type.range*range_margin.decimal + target.radius + abl.obj.radius)) || !abl.canActivate(abl.targets, ignoreCost=true)) {
			Target newTarg = storeTarg;
			@newTarg.obj = null;
			abl.changeTarget(objTarg, newTarg);
		}
	}
};

double getMassFor(Object& obj) {
#section server
	switch(obj.type) {
		case OT_Artifact:
			return getArtifactType(cast<Artifact>(obj).ArtifactType).mass;
		case OT_Asteroid:
			return config::ASTEROID_MASS;
		case OT_Ship:
			return cast<Ship>(obj).getBaseMass();
		case OT_Orbital: {
			auto@ mod = getOrbitalModule(cast<Orbital>(obj).coreModule);
			if(mod !is null && mod.mass >= 0)
				return mod.mass;
		}
	}
#section all
	return 20 * sqr(obj.radius);
}

class TargetFilterAllowTractor : TargetFilter {
	Argument objTarget(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::ABL_TRACTOR_NO;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(targ.obj.isArtifact)
			return true;
		if(targ.obj.isAsteroid)
			return true;
		if(targ.obj.isShip)
			return targ.obj.owner !is null && targ.obj.owner.major;
		if(targ.obj.isOrbital)
			return true;
		return false;
	}
};

class PersistentBeamEffect : AbilityHook {
	Document doc("Display a beam effect towards a stored target.");
	Argument objTarg(TT_Object);
	Argument color(AT_Color, "#ff0000", doc="Color of the beam.");
	Argument material(AT_Material, "MoveBeam", doc="Material to use for the beam.");
	Argument width(AT_Decimal, "1", doc="Width of the beam.");
	Argument modified_width(AT_Boolean, "True", doc="Whether the width of the beam is modified by the caster's size.");

	Color bColor;

	bool instantiate() override {
		bColor = toColor(color.str);
		return AbilityHook::instantiate();
	}

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;
		if(abl.obj is null)
			return;

		int64 effId = abl.obj.id << 32 | 0x1 << 24 | abl.id << 8 | index;
		double bWidth = width.decimal;
		if(modified_width.boolean)
			bWidth *= abl.obj.radius;

		if(newTarget.obj !is null)
			makeBeamEffect(ALL_PLAYERS, effId, abl.obj, newTarget.obj, bColor.color, bWidth, material.str, -1.0);
		else if(oldTarget.obj !is null)
			removeGfxEffect(ALL_PLAYERS, effId);
	}
#section all
};

class TriggerBeamEffect : AbilityHook {
	Document doc("Display a temporary beam effect towards a target when triggered.");
	Argument objTarg(TT_Object);
	Argument duration(AT_Decimal, doc="Duration of the beam effect.");
	Argument color(AT_Color, "#ff0000", doc="Color of the beam.");
	Argument material(AT_Material, "MoveBeam", doc="Material to use for the beam.");
	Argument width(AT_Decimal, "1", doc="Width of the beam.");
	Argument modified_width(AT_Boolean, "True", doc="Whether the width of the beam is modified by the caster's size.");

	Color bColor;

	bool instantiate() override {
		bColor = toColor(color.str);
		return AbilityHook::instantiate();
	}

#section server
	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.obj is null || targs is null)
			return;
		const Target@ trigTarg = objTarg.fromConstTarget(targs);
		if(trigTarg is null || trigTarg.obj is null)
			return;

		int64 effId = abl.obj.id << 32 | 0x1 << 24 | abl.id << 8 | objTarg.integer;
		double bWidth = width.decimal;
		if(modified_width.boolean)
			bWidth *= abl.obj.radius;
		makeBeamEffect(ALL_PLAYERS, effId, abl.obj, trigTarg.obj, bColor.color, bWidth, material.str, duration.decimal);
	}
#section all
};

tidy final class TractorData {
	bool hasOffset = false;
	vec3d offset;
	bool hasPath = false;
	vec3d pathDest;
	vec3d prevPosition;
};

class TractorObject : AbilityHook {
	Document doc("The object tracked in the specified target is tractored continually.");
	Argument objTarg(TT_Object);
	Argument max_distance(AT_Decimal, "200", doc="Maximum distance to tractor.");
	Argument allow_ftl(AT_Boolean, "False", doc="Whether to allow tractoring in FTL.");
	Argument allow_portal(AT_Boolean, "True", doc="Whether to allow tractoring through portals like slipstreams, wormholes, gates.");

#section server
	void create(Ability@ abl, any@ data) const override {
		TractorData td;
		td.prevPosition = vec3d(INFINITY, INFINITY, INFINITY);
		data.store(@td);
	}

	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;

		Object@ prev = oldTarget.obj;
		Object@ next = newTarget.obj;

		if(prev is next)
			return;

		if(prev !is null) {
			if(prev.hasOrbit) {
				prev.velocity = vec3d();
				prev.acceleration = vec3d();
				prev.remakeStandardOrbit();
			}
			if(abl.obj !is null && abl.obj.isShip)
				cast<Ship>(abl.obj).modMass(-getMassFor(prev));
		}
		if(next !is null) {
			if(abl.obj !is null && abl.obj.isShip)
				cast<Ship>(abl.obj).modMass(getMassFor(next));
		}

		TractorData@ td;
		data.retrieve(@td);

		td.hasOffset = false;
		td.hasPath = false;
		td.prevPosition = vec3d(INFINITY, INFINITY, INFINITY);
	}

	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		TractorData@ td;
		data.retrieve(@td);

		bool wasPortal = false;
		if(allow_portal.boolean) {
			if(td.hasPath && td.pathDest.distanceTo(abl.obj.position) < (abl.obj.velocity.length + abl.obj.radius) * 2.0)
				wasPortal = true;
			td.hasPath = abl.obj.hasMovePortal;
			if(td.hasPath)
				td.pathDest = abl.obj.getMovePortal();
		}

		double dist = target.position.distanceTo(abl.obj.position) - abl.obj.velocity.length * 2.0;
		if(dist < max_distance.decimal) {
			wasPortal = false;
		}
		else if(!wasPortal) {
			if(dist > max_distance.decimal) {
				if(!td.hasOffset || target.position.distanceToSQ(td.prevPosition) > 0.1) {
					Target newTarg = storeTarg;
					@newTarg.obj = null;
					abl.changeTarget(objTarg, newTarg);
					return;
				}
			}
		}

		if(!allow_ftl.boolean && abl.obj.inFTL) {
			Target newTarg = storeTarg;
			@newTarg.obj = null;
			abl.changeTarget(objTarg, newTarg);
			return;
		}

		if(!td.hasOffset) {
			td.offset = target.position - abl.obj.position;
			td.hasOffset = true;
		}

		target.donatedVision |= abl.obj.visibleMask;
		if(target.hasOrbit) {
			if(target.inOrbit) {
				target.stopOrbit();
			}
			else if(wasPortal) {
				vec3d targPos = abl.obj.position + td.offset;
				if(target.hasLeaderAI)
					target.teleportTo(targPos);
				else
					target.position = targPos;
				target.velocity = vec3d();
				target.acceleration = vec3d();

			}
			else if(target.position.distanceToSQ(td.prevPosition) > 0.1) {
				double interp = 1.0 - pow(0.2, time * abl.obj.radius / target.radius);
				target.position = target.position.interpolate(abl.obj.position + td.offset, interp);
				target.velocity = target.velocity.interpolate(abl.obj.velocity, interp);
				target.acceleration = target.acceleration.interpolate(abl.obj.acceleration, interp);
			}
			else {
				vec3d targPos = abl.obj.position + td.offset;
				target.position = targPos;
				target.velocity = abl.obj.velocity;
				target.acceleration = abl.obj.acceleration;
			}
		}
		else if(target.hasMover) {
			vec3d targPos = abl.obj.position + td.offset;
			if(wasPortal) {
				if(target.hasLeaderAI)
					target.teleportTo(targPos);
				else
					target.position = targPos;
				return;
			}
			vec3d dir = targPos - target.position;

			double tracForce = 0.0;
			if(abl.obj.hasMover)
				tracForce = abl.obj.maxAcceleration * time;

			vec3d force = dir.normalized(min(tracForce, dir.length));
			target.impulse(force);
		}
		td.prevPosition = target.position;
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		TractorData@ td;
		data.retrieve(@td);

		file << td.hasOffset;
		file << td.offset;
		file << td.hasPath;
		file << td.pathDest;
		file << td.prevPosition;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		TractorData td;
		data.store(@td);

		if(file >= SV_0122) {
			file >> td.hasOffset;
			file >> td.offset;
			file >> td.hasPath;
			file >> td.pathDest;
			if(file >= SV_0129)
				file >> td.prevPosition;
			else
				td.prevPosition = vec3d(INFINITY, INFINITY, INFINITY);
		}
	}
#section all
};

tidy final class OnAnyEmpireAttributeLT : AbilityHook {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when any empire's attribute is lower than the specified value.");
	Argument attribute(AT_EmpAttribute);
	Argument value(AT_Decimal);
	Argument function(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnEnable(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp.getAttribute(attribute.integer) < value.decimal)
				hook.activate(abl.obj, abl.emp);
		}
	}
#section all
};

class SpawnPlanetAt : AbilityHook {
	Document doc("Spawn a new planet at the target position.");
	Argument destination(TT_Point);
	Argument resource(AT_Custom, "distributed");
	Argument owned(AT_Boolean, "False", doc="Whether the planet starts colonized.");
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="Status effect to add to the planet after it is created.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		vec3d point = destination.fromConstTarget(targs).point;
		auto@ reg = getRegion(point);
		auto@ sys = getSystem(reg);

		MakePlanet plHook;
		plHook.initClass();
		plHook.resource.str = resource.str;
		plHook.distribute_resource.boolean = true;
		plHook.instantiate();

		Object@ current;
		plHook.trigger(null, sys, current);

		cast<Planet>(current).orbitAround(point, sys.position);
		if(owned.boolean)
			cast<Planet>(current).colonyShipArrival(abl.emp, 1.0);
		if(add_status.integer != -1)
			current.addStatus(add_status.integer);
	}
#section all
};

class SpawnArtifactAround : AbilityHook {
	Document doc("Spawn a new planet at the target position.");
	Argument destination(TT_Point);
	Argument radius(AT_Range);
	Argument type(AT_Custom, "distributed");

#section server
	const ArtifactType@ artifType;

	bool instantiate() {
		if(!type.str.equals_nocase("distributed")) {
			@artifType = getArtifactType(type.str);
			if(artifType is null) {
				error("SpawnArtifactAround() Error: Could not find artifact type: "+type.str);
				return false;
			}
		}
		return AbilityHook::instantiate();
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		vec3d center = destination.fromConstTarget(targs).point;
		vec3d point = center;
		vec2d offset = random2d(radius.fromRange());
		point.x += offset.x;
		point.z += offset.y;

		Artifact@ obj = createArtifact(point, artifType);
		obj.orbitAround(center);
	}
#section all
};

class ApplyTargetStatusEffect : AbilityHook {
	Document doc("The object tracked in the specified target gets a status effect while there.");
	Argument objTarg(TT_Object);
	Argument type(AT_Status, doc="Type of status effect to add.");

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;

		Object@ prev = oldTarget.obj;
		Object@ next = newTarget.obj;

		if(prev is next)
			return;

		if(prev !is null && prev.hasStatuses)
			prev.removeStatusInstanceOfType(type.integer);
		if(next !is null && next.hasStatuses)
			next.addStatus(type.integer);
	}
#section all
};

class OffensiveToTarget : AbilityHook {
	Document doc("The action is considered offensive towards the indicated target.");
	Argument objTarg(TT_Object);

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;
		if(newTarget.obj is null)
			return;
		if(newTarget.obj.owner is null || !newTarget.obj.owner.valid || newTarget.obj.owner is abl.emp)
			return;
		if(abl.obj !is null)
			abl.obj.engaged = true;
		newTarget.obj.engaged = true;
	}

	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		if(!target.isStar && (target.owner is null || !target.owner.valid || target.owner is abl.obj.owner))
			return;
		abl.obj.engaged = true;
		target.engaged = true;
	}
#section all
};

class SpawnStarAt : AbilityHook {
	Document doc("Spawn a new star at the target position.");
	Argument destination(TT_Point);
	Argument system_radius(AT_Range, "1500", doc="Radius of the created system, if in open space.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		NameGenerator sysNames;
		sysNames.read("data/system_names.txt");
		string name = sysNames.generate();

		vec3d point = destination.fromConstTarget(targs).point;
		auto@ reg = getRegion(point);
		if(reg is null)
			generateNewSystem(point, system_radius.fromRange(), name=name);

		MakeStar hook;
		hook.initClass();
		hook.instantiate();
		hook.arguments[0].set(14000, 29800);
		hook.arguments[1].set(85, 125);

		Object@ current;
		hook.trigger(null, null, current);
		Star@ star = cast<Star>(current);
		star.name = format(locale::SYSTEM_STAR, name);
		star.position = point;
	}
#section all
};

class TeleportTo : AbilityHook {
	Document doc("Teleport the casting object to a new position.");
	Argument destination(TT_Point);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		vec3d point = destination.fromConstTarget(targs).point;

		if(abl.obj.hasOrbit && abl.obj.inOrbit) {
			abl.obj.stopOrbit();
			abl.obj.position = point;
			abl.obj.remakeStandardOrbit();
		}
		else if(abl.obj.hasLeaderAI) {
			abl.obj.teleportTo(point);
		}
	}
#section all
};

class PlayParticles : AbilityHook {
	Document doc("Play particles at the object's position when activated.");
	Argument type(AT_Custom, doc="Which particle effect to play.");
	Argument scale(AT_Decimal, "1.0", doc="Scale of the particle effect.");
	Argument object_scale(AT_Boolean, "True", doc="Whether to scale the particle effect to the object's scale as well.");
	Argument object_tied(AT_Boolean, "True", doc="Whether the particle effect is tied to the object.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;

		double size = scale.decimal;
		if(object_scale.boolean)
			size *= abl.obj.radius;
		if(object_tied.boolean)
			playParticleSystem(type.str, vec3d(), quaterniond(), size, abl.obj);
		else
			playParticleSystem(type.str, abl.obj.position, quaterniond(), size);
	}
#section all
};

class PlayParticlesAt : AbilityHook {
	Document doc("Play particles at the target position when activated.");
	Argument destination(TT_Point, doc="Point to play them at.");
	Argument type(AT_Custom, doc="Which particle effect to play.");
	Argument scale(AT_Decimal, "1.0", doc="Scale of the particle effect.");
	Argument object_scale(AT_Boolean, "True", doc="Whether to scale the particle effect to the object's scale as well.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		double size = scale.decimal;
		if(object_scale.boolean && abl.obj !is null)
			size *= abl.obj.radius;
		vec3d point = destination.fromConstTarget(targs).point;
		playParticleSystem(type.str, point, quaterniond(), size);
	}
#section all
};

class DistanceEnergyCost : AbilityHook {
	Document doc("Increase the energy cost dependent on the distance to target.");
	Argument destination(TT_Any, doc="Point to play them at.");
	Argument base_cost(AT_Decimal, "0", doc="Base cost per distance.");
	Argument sqrt_cost(AT_Decimal, "0", doc="Cost per square root of distance.");
	Argument square_cost(AT_Decimal, "0", doc="Cost per squared distance.");

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.obj is null || targs is null)
			return;
		auto@ tt = destination.fromConstTarget(targs);
		vec3d point;
		if(tt.type == TT_Point)
			point = tt.point;
		else if(tt.type == TT_Object && tt.obj !is null)
			point = tt.obj.position;
		double dist = point.distanceTo(abl.obj.position);
		if(base_cost.decimal != 0)
			cost += base_cost.decimal * dist;
		if(sqrt_cost.decimal != 0)
			cost += sqrt_cost.decimal * sqrt(dist);
		if(square_cost.decimal != 0)
			cost += square_cost.decimal * sqr(dist);
	}
};

class MultiplyEnergyCost : AbilityHook {
	Document doc("Increase the energy cost by a factor, potentially taken from a subsystem variable.");
	Argument factor(AT_SysVar, doc="Energy cost factor.");

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		cost *= factor.fromSys(abl.subsystem);
	}
};

class SizeEnergyCost : AbilityHook {
	Document doc("Add to the energy cost of the ability based on the size of the target.");
	Argument targ(TT_Object, doc="Object to compare to");
	Argument factor(AT_Decimal, "1.0", doc="Factor multiplied to the radius.");

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.obj is null || targs is null)
			return;
		const Target@ trigTarg = targ.fromConstTarget(targs);
		if(trigTarg is null || trigTarg.obj is null)
			return;

		double theirScale = sqr(trigTarg.obj.radius);
		if(trigTarg.obj.isShip)
			theirScale = cast<Ship>(trigTarg.obj).blueprint.design.size;
		cost += theirScale * factor.decimal;
	}
};

class RelativeSizeEnergyCost : AbilityHook {
	Document doc("Multiply the energy cost of the ability based on a factor of the radius ratio.");
	Argument targ(TT_Object, doc="Object to compare to");
	Argument factor(AT_Decimal, "1.0", doc="Factor multiplied to the radius ratio.");
	Argument min_pct(AT_Decimal, "0");
	Argument max_pct(AT_Decimal, "1000.0");

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.obj is null || targs is null)
			return;
		const Target@ trigTarg = targ.fromConstTarget(targs);
		if(trigTarg is null || trigTarg.obj is null)
			return;

		double myScale = sqr(abl.obj.radius);
		if(abl.obj.isShip)
			myScale = cast<Ship>(abl.obj).blueprint.design.size;
		double theirScale = sqr(trigTarg.obj.radius);
		if(trigTarg.obj.isShip)
			theirScale = cast<Ship>(trigTarg.obj).blueprint.design.size;

		double rat = theirScale / myScale;
		cost *= clamp(rat * factor.decimal, min_pct.decimal, max_pct.decimal);
	}
};

class DealPlanetDamageOverTime : AbilityHook {
	Document doc("Deal damage to the stored target planet over time.");
	Argument objTarg(TT_Object);
	Argument dmg_per_second(AT_Decimal, "200", doc="Damage to deal per second.");

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		Planet@ pl = cast<Planet>(target);
		if(pl is null)
			return;

		pl.dealPlanetDamage(time * dmg_per_second.decimal);
	}
#section all
};

class DealStellarDamageOverTime : AbilityHook {
	Document doc("Deal damage to the stored target stellar object over time. Damages things like stars and planets.");
	Argument objTarg(TT_Object);
	Argument dmg_per_second(AT_SysVar, doc="Damage to deal per second.");

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ obj = storeTarg.obj;
		if(obj is null)
			return;

		double amt = dmg_per_second.fromSys(abl.subsystem, efficiencyObj=abl.obj) * time;
		if(obj.isPlanet)
			cast<Planet>(obj).dealPlanetDamage(amt);
		else if(obj.isStar)
			cast<Star>(obj).dealStarDamage(amt);
	}
#section all
};

tidy final class PeriodicData {
	double timer = 0;
	uint count = 0;
};
tidy final class TriggerTargetPeriodic : AbilityHook {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect every set interval on the indicated stored target.");
	Argument objTarg(TT_Object, doc="Target to trigger the effect on.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");
	Argument interval(AT_Decimal, "60", doc="Interval in seconds between triggers.");
	Argument max_triggers(AT_Integer, "-1", doc="Maximum amount of times to trigger the hook before stopping. -1 indicates no maximum triggers.");
	Argument trigger_immediate(AT_Boolean, "False", doc="Whether to first trigger the effect right away before starting the timer.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerTargetPeriodic(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;

		PeriodicData@ dat;
		data.retrieve(@dat);

		if(dat !is null) {
			if(trigger_immediate.boolean)
				dat.timer = interval.decimal;
			else
				dat.timer = 0;
			dat.count = 0;
		}
	}

	void create(Ability@ abl, any@ data) const override {
		PeriodicData dat;
		data.store(@dat);

		if(trigger_immediate.boolean)
			dat.timer = interval.decimal;
		else
			dat.timer = 0;
		dat.count = 0;
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		PeriodicData@ dat;
		data.retrieve(@dat);

		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null || storeTarg.obj is null) {
			if(trigger_immediate.boolean)
				dat.timer = interval.decimal;
			else
				dat.timer = 0;
			dat.count = 0;
			return;
		}

		Object@ target = storeTarg.obj;
		if(dat.timer >= interval.decimal) {
			if(max_triggers.integer < 0 || dat.count < uint(max_triggers.integer)) {
				if(hook !is null)
					hook.activate(target, target.owner);
				dat.count += 1;
			}
			dat.timer = 0.0;
		}
		else {
			dat.timer += time;
		}
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		PeriodicData@ dat;
		data.retrieve(@dat);

		file << dat.timer;
		file << dat.count;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		PeriodicData dat;
		data.store(@dat);

		file >> dat.timer;
		if(file >= SV_0096)
			file >> dat.count;
	}
#section all
};

class CooldownOnDeactivate : AbilityHook {
	Document doc("Trigger the cooldown when the ability deactivates its target.");
	Argument objTarg(TT_Object);
	Argument cooldown(AT_Decimal, doc="Cooldown to give.");

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {
		if(index != uint(objTarg.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;
		if(oldTarget.obj !is null)
			abl.cooldown = cooldown.decimal;
	}
#section all
};

class SpawnCreepShipFor : AbilityHook {
	Document doc("Spawn a creep ship against a particular system.");
	Argument destination(TT_Object, doc="System to play it against.");
	Argument design(AT_Custom);
	Argument status(AT_Status, doc="Type of status effect to add to the creep ship.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;
		Object@ target = destination.fromConstTarget(targs).obj;
		Region@ region = cast<Region>(target);
		if(region is null)
			@region = target.region;
		if(region is null)
			return;

		auto@ dsg = Creeps.getDesign(design.str);
		Ship@ leader = createShip(abl.obj.position, dsg, Creeps, free=true);
		leader.addStatus(status.integer, -1.0, originEmpire=abl.emp, originObject=region);
	}
#section all
};

class AddStatusSelf : AbilityHook {
	Document doc("Add a status to the target object.");
	Argument type(AT_Status, doc="Type of status effect to add.");
	Argument duration(AT_SysVar, "-1", doc="Duration to add the status for, -1 for permanent.");
	Argument duration_efficiency(AT_Boolean, "False", doc="Whether the duration added should be dependent on subsystem efficiency state. That is, a damaged subsystem will create a shorter duration status.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		Object@ target = abl.obj;
		if(target is null)
			return;
		if(!target.hasStatuses)
			return;

		Object@ effObj = null;
		if(duration_efficiency.boolean)
			@effObj = abl.obj;
		double timer = duration.fromSys(abl.subsystem, efficiencyObj=effObj);
		if(timer > 0)
			target.addStatus(uint(type.integer), timer);
	}
#section all
};

class AddStatusTo : AbilityHook {
	Document doc("Add a status to the target object.");
	Argument targObj(TT_Object, doc="Target object to add status to.");
	Argument type(AT_Status, doc="Type of status effect to add.");
	Argument duration(AT_SysVar, "-1", doc="Duration to add the status for, -1 for permanent.");
	Argument duration_efficiency(AT_Boolean, "False", doc="Whether the duration added should be dependent on subsystem efficiency state. That is, a damaged subsystem will create a shorter duration status.");
	Argument set_origin_empire(AT_Boolean, "False", doc="Whether to record the empire triggering this hook into the origin empire field of the resulting status. If not set, any hooks that refer to Origin Empire cannot not apply. Status effects with different origin empires set do not collapse into stacks.");
	Argument set_origin_object(AT_Boolean, "False", doc="Whether to record the object triggering this hook into the origin object field of the resulting status. If not set, any hooks that refer to Origin Object cannot not apply. Status effects with different origin objects set do not collapse into stacks.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ targ = targObj.fromConstTarget(targs);
		if(targ is null)
			return;
		Object@ target = targ.obj;
		if(target is null)
			return;
		if(!target.hasStatuses)
			return;

		Empire@ origEmp = null;
		if(set_origin_empire.boolean)
			@origEmp = abl.emp;
		Object@ origObj = null;
		if(set_origin_object.boolean)
			@origObj = abl.obj;

		Object@ effObj = null;
		if(duration_efficiency.boolean)
			@effObj = abl.obj;
		target.addStatus(uint(type.integer), duration.fromSys(abl.subsystem, efficiencyObj=effObj), originEmpire=origEmp, originObject=origObj);
	}
#section all
};

class ShareCooldown : AbilityHook {
	Document doc("Share this ability's cooldown with abilities of a particular type on the same object.");
	Argument type(AT_Ability, doc="Type of ability to share with.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		double cooldown = abl.cooldown;
		if(cooldown <= 0)
			cooldown = abl.type.cooldown;
		if(cooldown <= 0)
			return;
		if(abl.obj !is null)
			abl.obj.setCooldownForType(type.integer, cooldown);
	}
#section all
};

class ShowSubsystemVariable : AbilityHook {
	Document doc("Show a subsystem variable on the tooltip.");
	Argument variable(AT_SysVar, doc="Variable to show.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");
	Argument multiplier(AT_Decimal, "1", doc="Multiplier to the subsystem variable.");
	Argument efficiency(AT_Boolean, "False", doc="Whether to account for efficiency loss from damage.");
	Argument formatting("Format", AT_Locale, "$1", doc="Formatting for the value.");

	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const {
		Object@ effObj = null;
		if(efficiency.boolean)
			@effObj = abl.obj;
		double v = variable.fromSys(abl.subsystem, effObj) * multiplier.decimal;

		sprt = getSprite(this.icon.str);
		name = this.name.str;
		if(name.length != 0 && name[name.length-1] != ':')
			name += ":";
		value = format(formatting.str, standardize(v, true));
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class IsStatusToggle : AbilityHook {
	Document doc("The ability is a toggle for a status on the object.");
	Argument type(AT_Status, doc="Type of status effect to add.");

#section server
	void create(Ability@ abl, any@ data) const {
		int id = -1;
		data.store(id);
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		int id = -1;
		data.retrieve(id);

		if(id == -1 || !abl.obj.isStatusInstanceActive(id)) {
			id = abl.obj.addStatus(-1.0, type.integer);
			data.store(id);
		}
		else {
			abl.obj.removeStatus(id);
			id = -1;
			data.store(id);
		}
	}

	void destroy(Ability@ abl, any@ data) const {
		disable(abl, data);
	}

	void disable(Ability@ abl, any@ data) const {
		int id = -1;
		data.retrieve(id);

		if(id != -1) {
			abl.obj.removeStatus(id);
			id = -1;
			data.store(id);
		}
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		int id = -1;
		data.retrieve(id);
		file << id;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		int id = -1;
		file >> id;
		data.store(id);
	}
#section all
};

class RequireEnergyMaintenance : AbilityHook {
	Document doc("To activate this ability, you must be able to afford a certain amount of energy per second.");
	Argument amount(AT_Decimal, "0", doc="Base amount of energy per second it costs.");
	Argument per_shipsize(AT_Decimal, "0", doc="When on a ship, increase the energy per second by the ship design size multiplied by this.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(ignoreCost)
			return true;

		double amt = amount.decimal;
		if(per_shipsize.decimal != 0 && abl.obj !is null && abl.obj.isShip)
			amt += cast<Ship>(abl.obj).blueprint.design.size * per_shipsize.decimal;
		return !abl.emp.isEnergyShortage(amt);
	}
};

class ReduceEnergyCostSystemFlag : AbilityHook {
	Document doc("Reduces the energy cost to activate this ability if a particular system flag is active on the system it is in.");
	Argument factor(AT_Decimal, doc="Factor to multiply the energy cost by.");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to check. Can be set to any arbitrary name, and the matching system flag will be created.");

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const override {
		if(abl.obj is null || abl.emp is null)
			return;
		Region@ reg = abl.obj.region;
		if(reg is null)
			return;
		if(reg.getSystemFlag(abl.emp, flag.integer))
			cost *= factor.decimal;
	}
};

class AutoCastNearby : AbilityHook {
	Document doc("Automatically activate this ability on nearby objects that it can target.");
	Argument targ("Target", TT_Object, EMPTY_DEFAULT, doc="If specified, use a stored target to check if the ability is already being cast.");
	Argument prioritize_combat(AT_Boolean, "False", doc="Prioritize fleets that are in combat.");
	Argument prioritize_strongest(AT_Boolean, "False", doc="Prioritize the strongest fleet over the weakest.");
	Argument prioritize_low_supply(AT_Boolean, "False", doc="Prioritize fleets with low supply");
	Argument require_priority(AT_Boolean, "False", doc="Whether to require either low supply or in combat, depending on what prioritizations are set.");

#section server
	void create(Ability@ abl, any@ data) const {
		int triggers = 1;
		data.store(triggers);
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		int triggers = 0;
		data.retrieve(triggers);
		triggers += 1;
		data.store(triggers);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.cooldown > 0 || abl.obj is null)
			return;

		Object@ curTarget;
		if(targ.integer != -1)
			@curTarget = targ.fromTarget(abl.targets).obj;

		int triggers = 0;
		data.retrieve(triggers);
		if(triggers > 1 && curTarget !is null)
			return;

		double curPrior = 1;
		if(curTarget is null) {
			curPrior = 0;
		}
		else {
			bool havePrior = false;
			if(prioritize_combat.boolean && curTarget.inCombat) {
				curPrior *= 3.0;
				havePrior = true;
			}
			if(prioritize_strongest.boolean && curTarget.hasLeaderAI)
				curPrior *= curTarget.getFleetStrength() * 0.001;
			if(prioritize_low_supply.boolean && curTarget.isShip) {
				double maxSupply = cast<Ship>(curTarget).MaxSupply;
				if(maxSupply > 0) {
					double curSupply = cast<Ship>(curTarget).Supply;
					curPrior /= curSupply / maxSupply;
					if(curSupply < maxSupply - 0.01)
						havePrior = true;
				}
			}
			if(require_priority.boolean && !havePrior)
				curPrior = 0;
		}

		Object@ checkTarget = findCastable(abl);
		if(checkTarget !is null) {
			double checkPrior = 1.0;
			bool havePrior = false;
			if(prioritize_combat.boolean && checkTarget.inCombat) {
				checkPrior *= 3.0;
				havePrior = true;
			}
			if(prioritize_strongest.boolean && checkTarget.hasLeaderAI)
				checkPrior *= checkTarget.getFleetStrength() * 0.001;
			if(prioritize_low_supply.boolean && checkTarget.isShip) {
				double maxSupply = cast<Ship>(checkTarget).MaxSupply;
				if(maxSupply > 0) {
					double curSupply = cast<Ship>(checkTarget).Supply;
					curPrior /= curSupply / maxSupply;
					havePrior = curSupply < maxSupply - 0.01;
				}
			}
			if(require_priority.boolean && !havePrior)
				checkPrior = 0;

			if(checkPrior > curPrior && checkPrior > 0) {
				abl.obj.activateAbilityFor(abl.emp, abl.id, checkTarget);
				triggers = 0;
				data.store(triggers);
			}
			else if(curPrior <= 0 && curTarget !is null && triggers <= 1) {
				abl.obj.activateAbilityFor(abl.emp, abl.id, null);
				triggers = 0;
				data.store(triggers);
			}
		}
		else {
			if(curPrior <= 0 && curTarget !is null && triggers <= 1) {
				abl.obj.activateAbilityFor(abl.emp, abl.id, null);
				triggers = 0;
				data.store(triggers);
			}
		}
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		int triggers = 0;
		data.retrieve(triggers);
		file << triggers;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		int triggers = 0;
		file >> triggers;
		data.store(triggers);
	}
#section all
};

class RequireNotInCombat : AbilityHook {
	Document doc("Ability can only be cast while out of combat.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null)
			return true;
		if(abl.obj.hasSurfaceComponent && abl.obj.isContested)
			return false;
		return !abl.obj.inCombat;
	}
};

class RequireNotUnderSiege : AbilityHook {
	Document doc("Ability can only be cast if not by a planet that is under siege.");
	Argument planet_contestion(AT_Boolean, "True", doc="Count planet 'contested' flag set by annex votes.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null)
			return true;
		if(!abl.obj.hasSurfaceComponent)
			return true;
		if(planet_contestion.boolean && abl.obj.hasContestion)
			return false;
		return !abl.obj.isUnderSiege;
	}
};

class RequirePopulation : AbilityHook {
	Document doc("Ability can only be cast by planets that have acertain amount of population.");
	Argument population(AT_Decimal, "1", doc="Minimum population needed.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null)
			return true;
		if(!abl.obj.hasSurfaceComponent)
			return true;
		return abl.obj.population >= population.decimal - 0.0001;
	}
};

class ScanAnomaly : AbilityHook {
	Document doc("The anomaly this is toggled on automatically scans over time.");
	Argument objTarg(TT_Object);
	Argument speed(AT_Decimal, "1.0", doc="Factor of normal scan speed to scan at.");

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		Anomaly@ anom = cast<Anomaly>(target);
		if(anom is null)
			return;

		anom.addProgress(abl.emp, time * speed.decimal);
	}
#section all
};

class MoveFinalSurfaceRowsTo : AbilityHook {
	Document doc("Move the final N rows of the surface to a different planet.");
	Argument targ(TT_Object, doc="Target to move surface rows to.");
	Argument rows(AT_Integer, "1", doc="Amount of surface rows to move.");
	Argument void_biome(AT_PlanetBiome, "Space", doc="Biome of the separating space.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		Object@ other = objTarg.obj;
		if(!other.hasSurfaceComponent || abl.obj is null || !abl.obj.hasSurfaceComponent)
			return;
		other.stealFinalSurfaceRowsFrom(abl.obj, rows.integer, void_biome.integer);
	}
#section all
};

class IsAutoColonize : AbilityHook {
	Document doc("Register this ability as an auto-colonize ability.");

#section server
	void create(Ability@ abl, any@ data) const override {
		abl.obj.owner.registerAutoColonizer(abl.obj, abl.id);
	}

	void destroy(Ability@ abl, any@ data) const override {
		abl.obj.owner.unregisterAutoColonizer(abl.obj, abl.id);
	}

	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		for(uint i = 0, cnt = targs.length; i < cnt; ++i) {
			if(targs[i].obj !is null && targs[i].obj.isPlanet)
				targs[i].obj.setBeingColonized(abl.obj.owner, false);
		}
	}
#section all
};

class AutoOrderOnAutoColonizeTarget : AbilityHook {
	Document doc("Automatically order this ability on planets taken from the auto-colonization list, when the object is otherwise idle.");

#section server
	void create(Ability@ abl, any@ data) const override {
		Object@ cur;
		data.store(@cur);
	}

	void destroy(Ability@ abl, any@ data) const override {
		Object@ cur;
		data.retrieve(@cur);
		if(cur !is null) {
			if(cur.owner !is abl.emp && !cur.owner.valid)
				abl.emp.pushAutoColonizeTarget(cur);
			@cur = null;
			data.store(@cur);
		}
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null || abl.emp is null)
			return;
		if(!abl.obj.hasLeaderAI)
			return;

		Object@ cur;
		data.retrieve(@cur);
		if(cur !is null) {
			if(abl.obj.orderCount == 0 || abl.obj.orderType[0] != OT_Ability) {
				if(cur.owner !is abl.emp && !cur.owner.valid)
					abl.emp.pushAutoColonizeTarget(cur);
				@cur = null;
				data.store(@cur);
			}
		}
		else {
			if(abl.obj.orderCount != 0)
				return;
			Object@ targ = abl.emp.popAutoColonizeTarget();
			if(targ !is null) {
				abl.obj.addAbilityOrder(abl.id, targ, false);
				data.store(@targ);
			}
		}
	}
#section all
};

class AutoCastAsColonizePopTransfer : AbilityHook {
	Document doc("This ability is automatically casted on auto-colonize targets as a population transfer.");

#section server
	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null || abl.emp is null)
			return;
		double maxPop = max(double(abl.obj.maxPopulation), double(getPlanetLevel(abl.obj, abl.obj.primaryResourceLevel).population));
		if(abl.obj.population < maxPop + 1.0 - 0.001)
			return;

		Object@ targ = abl.emp.popAutoColonizeTarget();
		if(targ !is null) {
			Targets targs(abl.type.targets);
			@targs.fill(0).obj = targ;

			if(abl.canActivate(targs)) {
				abl.obj.activateAbility(abl.id, targ);

				double maxPop = double(getPlanetLevel(targ, min(targ.primaryResourceLevel, getMaxPlanetLevel(targ))).population);
				if(targ.population + 1.0 < maxPop - 0.001)
					abl.emp.pushAutoColonizeTarget(targ);
			}
			else {
				abl.emp.pushAutoColonizeTarget(targ);
			}
		}
	}
#section all
};

class AutoCastAsColonize : AbilityHook {
	Document doc("This ability is automatically casted on auto-colonize targets as a population transfer.");

#section server
	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null || abl.emp is null)
			return;
		Object@ targ = abl.emp.popAutoColonizeTarget();
		if(targ !is null) {
			Targets targs(abl.type.targets);
			@targs.fill(0).obj = targ;

			if(abl.canActivate(targs)) {
				abl.obj.activateAbility(abl.id, targ);
			}
			else {
				abl.emp.pushAutoColonizeTarget(targ);
			}
		}
	}
#section all
};

class RequireCargoSpace : AbilityHook {
	Document doc("Ability can only be used if cargo space is not fully filled.");
	
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null || !abl.obj.hasCargo)
			return false;
		return abl.obj.cargoStored < abl.obj.cargoCapacity - 0.0001;
	}
};

class RequireHeldCargo : AbilityHook {
	Document doc("Ability can only be used if cargo space is not fully empty.");
	
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null || !abl.obj.hasCargo)
			return false;
		return abl.obj.cargoStored >= 0.001;
	}
};

class MineCargoFrom : AbilityHook {
	Document doc("Mine cargo from the targeted object over time.");
	Argument objTarg(TT_Object);
	Argument rate(AT_SysVar, "1", doc="Rate to mine cargo at.");

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null || !abl.obj.hasCargo)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null || !target.hasCargo)
			return;
		target.transferPrimaryCargoTo(abl.obj, time * rate.fromSys(abl.subsystem));
	}
#section all
};

class TransferAllCargoTo : AbilityHook {
	Document doc("Transfer all cargo to the target object, as much as possible.");
	Argument targ(TT_Object);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		Object@ other = objTarg.obj;
		if(!other.hasCargo || abl.obj is null || !abl.obj.hasCargo)
			return;
		abl.obj.transferAllCargoTo(other);
	}
#section all
};

class PickupAllCargoFrom : AbilityHook {
	Document doc("Pick up all cargo from the target object, as much as possible.");
	Argument targ(TT_Object);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		Object@ other = objTarg.obj;
		if(!other.hasCargo || abl.obj is null || !abl.obj.hasCargo)
			return;
		other.transferAllCargoTo(abl.obj);
	}
#section all
};

class CastWhenIdle : AbilityHook {
	Document doc("Cast a different ability type when the object is idle ");
	Argument ability(AT_Ability, doc="Other ability to cast.");
	Argument objTarget(TT_Object, doc="Target to cast ability on.");
	Argument require_cargo(AT_Boolean, "False", doc="Only cast when we have cargo.");
	Argument require_no_cargo(AT_Boolean, "False", doc="Only cast when we have no cargo.");
	Argument require_free_cargo(AT_Boolean, "False", doc="Only cast when we have cargo space free.");

#section server
	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null)
			return;
		if(abl.obj.orderCount != 0)
			return;
		if(require_cargo.boolean) {
			if(!abl.obj.hasCargo || abl.obj.cargoStored < 0.001)
				return;
		}
		if(require_no_cargo.boolean) {
			if(!abl.obj.hasCargo || abl.obj.cargoStored >= 0.001)
				return;
		}
		if(require_free_cargo.boolean) {
			if(!abl.obj.hasCargo || abl.obj.cargoStored >= abl.obj.cargoCapacity - 0.001)
				return;
		}

		Target@ storeTarg = objTarget.fromTarget(abl.targets);
		if(storeTarg is null)
			return;
		if(storeTarg.obj is null)
			return;

		int id = abl.obj.findAbilityOfType(ability.integer);
		if(id >= 0)
			abl.obj.addAbilityOrder(id, storeTarg.obj, false);
	}
#section all
};

class CastOnActivate : AbilityHook {
	Document doc("Cast a different ability type when this one gets activated.");
	Argument ability(AT_Ability, doc="Other ability to cast.");
	Argument objTarget(TT_Object, doc="Target to cast ability on.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ targ = objTarget.fromConstTarget(targs);
		if(targ is null || targ.obj is null)
			return;

		int id = abl.obj.findAbilityOfType(ability.integer);
		if(id >= 0)
			abl.obj.addAbilityOrder(id, targ.obj, false);
	}
#section all
};

class ClearOnMoveOrder : AbilityHook {
	Document doc("Clear the stored target when a regular move order is given.");
	Argument objTarget(TT_Object, doc="Target to clear.");
	Argument require_cargo(AT_Boolean, "False", doc="Only clear when we have cargo.");

#section server
	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null)
			return;
		if(abl.obj.orderCount == 0)
			return;
		if(require_cargo.boolean) {
			if(!abl.obj.hasCargo || abl.obj.cargoStored < 0.001)
				return;
		}

		Target@ storeTarg = objTarget.fromTarget(abl.targets);
		if(storeTarg is null)
			return;
		if(storeTarg.obj is null)
			return;

		uint type = abl.obj.orderType[0];
		if(type == OT_Move || type == OT_Goto) {
			Target newTarg = storeTarg;
			@newTarg.obj = null;
			abl.changeTarget(objTarget, newTarg);
		}
	}
#section all
};

class AutoSetToOriginPlanet : AbilityHook {
	Document doc("The stored target is automatically set to whichever planet spawned it.");

#section server
	void create(Ability@ abl, any@ data) const override {
		if(abl.obj is null)
			return;
		double timer = 1.0;
		data.store(timer);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		double timer = 1.0;
		data.retrieve(timer);

		if(timer > 0) {
			timer -= time;
			if(timer <= 0) {
				Object@ origin = abl.obj.getLockedOrbit(false);
				if(origin !is null)
					abl.obj.activateAbility(abl.id, origin);
			}
			data.store(timer);
		}
	}
#section all
};

class AutoCastSystemAsteroid : AbilityHook {
	Document doc("The stored target is automatically set to whichever planet spawned it.");
	Argument objTarget(TT_Object, doc="Target to check.");

#section server
	void create(Ability@ abl, any@ data) const override {
		if(abl.obj is null)
			return;
		double timer = 10.0;
		data.store(timer);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj.orderCount != 0)
			return;

		double timer = 10.0;
		data.retrieve(timer);

		Target@ storeTarg = objTarget.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		if(timer > 0) {
			timer -= time;
			if(timer <= 0) {
				if(abl.obj.region !is null)
					abl.obj.region.castOnRandomAsteroid(abl.obj, abl.id);
			}
			data.store(timer);
		}
		else if(storeTarg.obj is null) {
			timer = 10.0;
			data.store(timer);
		}
	}
#section all
};

tidy final class AfterChannel : AbilityHook {
	Document doc("Runs a triggered hook after a certain channeling period on the same target.");
	Argument channel_targ(TT_Object);
	Argument duration(AT_Decimal);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	Argument clear(AT_Boolean, "True", doc="Clear the channeling after the trigger.");

	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("AfterChannel(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const override {
		if(index != uint(channel_targ.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;

		double timer = 0.0;
		data.store(timer);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null)
			return;
		Target@ storeTarg = channel_targ.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		double timer = 0.0;
		data.retrieve(timer);

		timer += time;
		if(timer >= duration.decimal) {
			//Trigger effect
			if(hook !is null)
				hook.activate(target, abl.emp);
			else if(eff !is null)
				eff.enable(target, null);
			timer = 0.0;

			//Clear out target
			if(clear.boolean) {
				Target newTarg = storeTarg;
				@newTarg.obj = null;
				abl.changeTarget(channel_targ, newTarg);
			}
		}

		data.store(timer);
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		data.retrieve(value);
		file << value;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		if(file >= SV_0161)
			file >> value;
		data.store(value);
	}

#section all
};

tidy final class AfterChannelSelf : AbilityHook {
	Document doc("Runs a triggered hook after a certain channeling period on the same target.");
	Argument channel_targ(TT_Object);
	Argument duration(AT_Decimal);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	Argument clear(AT_Boolean, "True", doc="Clear the channeling after the trigger.");

	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("AfterChannel(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AbilityHook::instantiate();
	}

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const override {
		if(index != uint(channel_targ.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;

		double timer = 0.0;
		data.store(timer);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null)
			return;
		Target@ storeTarg = channel_targ.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		double timer = 0.0;
		data.retrieve(timer);

		timer += time;
		if(timer >= duration.decimal) {
			//Trigger effect
			if(hook !is null)
				hook.activate(abl.obj, abl.emp);
			else if(eff !is null)
				eff.enable(abl.obj, null);
			timer = 0.0;

			//Clear out target
			if(clear.boolean) {
				Target newTarg = storeTarg;
				@newTarg.obj = null;
				abl.changeTarget(channel_targ, newTarg);
			}
		}

		data.store(timer);
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		data.retrieve(value);
		file << value;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		file >> value;
		data.store(value);
	}

#section all
};

tidy final class ChannelWhileHaveQueue : AbilityHook {
	Document doc("Channel this while the target has a build queue.");
	Argument channel_targ(TT_Object);
	Argument delay(AT_Decimal, "0", doc="Minimum delay before checking build queue.");

#section server
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const override {
		if(index != uint(channel_targ.integer))
			return;
		if(oldTarget.obj is newTarget.obj)
			return;

		double timer = 0.0;
		data.store(timer);
	}

	void tick(Ability@ abl, any@ data, double time) const override {
		if(abl.obj is null)
			return;
		Target@ storeTarg = channel_targ.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null)
			return;

		double timer = 0.0;
		data.retrieve(timer);

		timer += time;
		if(timer >= delay.decimal) {
			if(target.constructionCount == 0) {
				//Clear out target
				Target newTarg = storeTarg;
				@newTarg.obj = null;
				abl.changeTarget(channel_targ, newTarg);
			}
		}

		data.store(timer);
	}

	void save(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		data.retrieve(value);
		file << value;
	}

	void load(Ability@ abl, any@ data, SaveFile& file) const override {
		double value = 0.0;
		if(file >= SV_0161)
			file >> value;
		data.store(value);
	}

#section all
};

class TargetFilterLoyaltyMax : TargetFilter {
	Document doc("Only allow planet targets with a particular loyalty or less.");
	Argument objTarget(TT_Object);
	Argument maximum(AT_SysVar, doc="Maximum loyalty");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_LOYALTY_MAX;
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasSurfaceComponent)
			return false;
		int loy = targ.obj.getLoyaltyFacing(abl.emp);
		int maxLoy = maximum.fromSys(abl.subsystem);
		return loy <= maxLoy;
	}
};

class RequireAttitudeNotMaxed : AbilityHook {
	Document doc("Require that a particular attitude on the empire is not currently maxed.");
	Argument attitude(AT_Attitude, doc="Attitude to check.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		Empire@ emp = abl.emp;
		if(emp is null && abl.obj !is null)
			@emp = abl.obj.owner;
		if(emp is null)
			return false;

		auto@ att = getAttitudeType(attitude.integer);
		if(att is null)
			return false;
		uint curLevel = emp.getAttitudeLevel(att.id);
		if(curLevel >= att.levels.length)
			return false;
		return true;
	}
};

class SubsystemOrConsumeStatus : AbilityHook {
	Document doc("If this ability is not given by a subsystem, consume a status whenever it is triggered.");
	Argument consume_status(AT_Status, doc="Status to consume.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;
		if(abl.subsystem !is null)
			return;
		abl.obj.removeStatusInstanceOfType(consume_status.integer);
	}
#section all
};
