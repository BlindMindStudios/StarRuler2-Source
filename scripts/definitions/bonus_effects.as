#include "include/resource_constants.as"
import orbitals;
import hooks;
import pickups;
import resources;
import influence;
import attributes;
import anomalies;
import camps;
import research;
import buildings;
from buildings import getBuildingID;
import artifacts;
import orders;
from traits import ITraitEffect;
from influence import InfluenceStore;
from pickups import IPickupHook;
from anomalies import IAnomalyHook;
from abilities import Ability, IAbilityHook;
from research import ITechnologyHook;
from map_effects import parseResourceSpec;
import constructions;
from constructions import IConstructionHook;
import random_events;
import cargo;
import generic_hooks;
import void gainRandomCard(Empire@ emp) from "card_effects";

#section server
from object_stats import ObjectStatType, getObjectStat;
from objects.Asteroid import createAsteroid;
from objects.Anomaly import createAnomaly;
from empire import Creeps;
from objects.Oddity import createSlipstream;
from objects.Artifact import createArtifact;
from piracy import spawnPirateShip;
from game_start import generateNewSystem, SystemGenerateHook;
import object_creation;
import systems;
import influence_global;
import void makeCreepCamp(const vec3d& pos, const CampType@ type, Region@ region = null) from "map_effects";
import Planet@ spawnPlanetSpec(const vec3d& point, const string& resourceSpec, bool distributeResource = true, double radius = 0.0, bool physics = true) from "map_effects";
import achievements;
from construction.Constructible import Constructible;
from Invasion.InvasionMap import increaseInvasionStrength;
import string getRandomFlagshipName() from "card_effects";
import string getRandomPlanetName() from "card_effects";
from util.design_export import resizeDesign;
#section all

class AddEnergy : EmpireTrigger {
	Document doc("Give the empire extra stored energy.");
	Argument amount(AT_Range, doc="Amount of energy to give.");
	Argument modified(AT_Boolean, "True", doc="Whether to modify the value by the current energy efficiency.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		double amt = amount.fromRange();
		if(modified.boolean)
			amt *= emp.EnergyEfficiency;
		emp.modEnergyStored(amt);
	}
#section all
};

class AddEnergyUpTo : EmpireTrigger {
	Document doc("Give the empire energy until it is at a particular stored amount.");
	Argument amount(AT_Range, doc="Amount of energy to give up to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		double cur = emp.EnergyStored;
		emp.modEnergyStored(max(0.0, amount.fromRange() - cur));
	}
#section all
};

class LoseStoredEnergy : EmpireTrigger {
	Document doc("The empire immediately loses all stored energy.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of stored energy to lose.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modEnergyStored(-emp.EnergyStored * percentage.decimal);
	}
#section all
};

class ModInfluenceFactor : EmpireTrigger {
	Document doc("Change the influence generation rate factor by a certain amount.");
	Argument amount(AT_Decimal, doc="Amount added to percentage influence generation. For example, 0.25 increases influence generation by 25% of base.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modInfluenceFactor(amount.decimal);
	}
#section all
};

class ReserveInfluence : EmpireTrigger {
	Document doc("Reserve a percentage of influence generation for an amount of time.");
	Argument amount(AT_Decimal, doc="Percentage of influence to reserve.");
	Argument duration(AT_Decimal, doc="Time in seconds to reserve the influence for.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.reserveInfluence(amount.decimal, duration.decimal);
	}
#section all
};

class AddEmpireResourceIncome : EmpireTrigger {
	Document doc("Adds income to one of the empire-wide resources.");
	Argument type(AT_EmpireResource, doc="Type of income to add.");
	Argument amount(AT_Range, doc="Amount of income to add.");
	
#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		switch(type.integer) {
			case ER_Money:
				emp.modTotalBudget(amount.fromRange(), MoT_Misc);
				break;
			case ER_Influence:
				emp.modInfluenceIncome(amount.fromRange());
				break;
			case ER_FTL:
				emp.modFTLIncome(amount.fromRange());
				break;
			case ER_Research:
				emp.modResearchRate(amount.fromRange());
				break;
			case ER_Defense:
				emp.modDefenseRate(amount.fromRange() * DEFENSE_LABOR_PM / 60.0);
				break;
			case ER_Energy:
				emp.modEnergyIncome(amount.fromRange());
				break;
		}
	}
#section all
};

class AddEmpireResource : EmpireTrigger {
	Document doc("Adds to one of the empire-wide resources.");
	Argument type(AT_EmpireResource, doc="Type of resource to add. Money will be added as Special Funds.");
	Argument amount(AT_Range, doc="Amount of resource to add.");
	
#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		switch(type.integer) {
			case ER_Money:
				emp.addBonusBudget(amount.fromRange());
				break;
			case ER_Influence:
				emp.addInfluence(amount.fromRange());
				break;
			case ER_FTL:
				emp.modFTLStored(amount.fromRange());
				break;
			case ER_Research:
				emp.generatePoints(amount.fromRange());
				break;
			case ER_Defense:
				emp.generateDefense(amount.fromRange());
				break;
			case ER_Energy:
				emp.modEnergyStored(amount.fromRange() * emp.EnergyEfficiency);
				break;
		}
	}
#section all
};

class AddFTLStorage : EmpireTrigger {
	Document doc("Add permanent FTL storage capacity to the empire.");
	Argument amount(AT_Range, doc="Amount of FTL capacity to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.modFTLCapacity(amount.fromRange());
	}
#section all
};

class GainRandomInfluenceCards : EmpireTrigger {
	Document doc("Give the empire randomized influence cards.");
	Argument amount(AT_Range, doc="Amount of cards to give.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		for(uint i = 0, cnt = amount.fromRange(); i < cnt; ++i)
			gainRandomCard(emp);
	}
#section all
};


class GainInfluenceCard : EmpireTrigger {
	Document doc("Give the empire a particular influence card.");
	Argument card(AT_InfluenceCard, doc="Card type to give.");
	Argument uses(AT_Range, "1", doc="Amount of uses to give the card.");
	Argument quality(AT_Range, "0", doc="Amount of extra quality to give the card.");

	const InfluenceCardType@ type;
	bool instantiate() override {
		@type = getInfluenceCardType(card.str);
		if(type is null) {
			error("Invalid card type: "+card.str);
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		InfluenceCard@ card = type.create(uses=round(uses.fromRange()), quality=1+round(quality.fromRange()));
		cast<InfluenceStore>(emp.InfluenceManager).addCard(emp, card);
	}
#section all
};


class GainRandomLeverage : EmpireTrigger {
	Document doc("Gain leverage on a random empire.");
	Argument quality(AT_Range, doc="Quality factor of the leverage.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Empire@ onEmp;
		uint n = 0;
		do {
			@onEmp = getEmpire(randomi(0, getEmpireCount() - 1));
			++n;
		} while((!onEmp.major || onEmp is emp) && n < 10);

		if(n == 10)
			return;
		emp.gainRandomLeverage(onEmp, quality.fromRange());
	}
#section all
};

class GainDistinctLeverage : EmpireTrigger {
	Document doc("Gain leverage on a number of distinct random empires.");
	Argument empire_count(AT_Range, doc="Amount of different empires to give leverage on.");
	Argument quality(AT_Range, doc="Quality factor of the leverage.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		array<Empire@> emps;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other.major && other !is emp)
				emps.insertLast(other);
		}

		uint n = empire_count.fromRange();
		while(n > 0 && emps.length != 0) {
			uint index = randomi(0, emps.length-1);
			Empire@ other = emps[index];

			emp.gainRandomLeverage(other, quality.fromRange());

			emps.removeAt(index);
			--n;
		}
	}
#section all
};

class GainLeverageInSystem : BonusEffect {
	Document doc("Gain leverage on all other empires in a system.");
	Argument quality(AT_Range, doc="Quality factor of the leverage.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		if(reg is null)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major || other is emp)
				continue;
			if(reg.getPlanetCount(other) > 0)
				emp.gainRandomLeverage(other, quality.fromRange());
		}
	}
#section all
};

class GainIntelligenceInSystem : BonusEffect {
	Document doc("Gain intelligence on all other empires in a system.");
	Argument amount(AT_Range, "1", doc="Amount of intelligence.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		if(reg is null)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major || other is emp)
				continue;
			if(reg.getPlanetCount(other) > 0)
				emp.gainIntelligence(other, amount.fromRange());
		}
	}
#section all
};

class SpawnDryDock : BonusEffect {
	Document doc("Spawn a dry dock of a creep design.");
	Argument design(AT_Custom, doc="Name of the design to use.");
	Argument funding(AT_Range, "0.0", doc="Percentage of the ship already funded.");
	Argument progress(AT_Range, "0.0", doc="Percentage of the ship already constructed.");
	Argument free(AT_Boolean, "true", doc="Whether the ship/drydock is free of maintenance.");
	const Design@ dsg;
	
#section server
	bool instantiate() {
		if(Creeps is null)
			return BonusEffect::instantiate();
		@dsg = Creeps.getDesign(arguments[0].str);
		if(dsg is null) {
			error("Invalid creep design: "+escape(arguments[0].str));
			return false;
		}
		return BonusEffect::instantiate();
	}
	
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		const Design@ dsg = this.dsg;
		if(dsg is null) {
			@dsg = Creeps.getDesign(arguments[0].str);
			if(dsg is null)
				return;
		}
		auto@ module = getOrbitalModule("DryDock");
		if(module is null) {
			error("Error: SpawnDryDock() could not find 'DryDock' orbital module.");
			return;
		}

		ObjectDesc oDesc;
		oDesc.type = OT_Orbital;
		@oDesc.owner = emp;
		oDesc.name = format(locale::DRY_DOCK_NAME, dsg.name);
		oDesc.radius = pow(dsg.size, 1.0/2.5);

		double rad = 0.0;
		if(!obj.isAnomaly)
			rad = max(oDesc.radius, obj.radius);
		oDesc.position = obj.position + random3d(rad*2.0, rad*3.0);

		Orbital@ orb = cast<Orbital>(makeObject(oDesc));
		orb.addSection(module.id);

		if(arguments[3].boolean)
			orb.sendValue(OV_DRY_Free, 1.0);
		orb.sendDesign(OV_DRY_Design, dsg);
		orb.sendValue(OV_DRY_SetFinanced, arguments[1].decimal);
		orb.sendValue(OV_DRY_Progress, arguments[2].decimal);
	}
#section all
};


class MapVision : BonusEffect {
	Document doc("Grants memory of planets for nearby systems.");
	Argument hops(AT_Integer, "1", doc="Amount of system links away to give memory on.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ region = obj.region;
		if(region is null)
			return;
		
		set_int visited;
		array<const SystemDesc@> listA, listB;
		array<const SystemDesc@>@ border = @listA, nextBorder = @listB;
		
		border.insertLast(getSystem(region));
		visited.insert(region.id);
		
		for(uint hop = 0, hopCnt = arguments[0].integer; hop < hopCnt; ++hop) {
			for(uint j = 0, jcnt = border.length; j < jcnt; ++j) {
				const SystemDesc@ sys = border[j];
				for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
					const SystemDesc@ borderSys = getSystem(sys.adjacent[i]);
					if(visited.contains(borderSys.object.id))
						continue;
					visited.insert(borderSys.object.id);
					borderSys.object.grantMemory(emp);
					nextBorder.insertLast(borderSys);
				}
			}
			
			array<const SystemDesc@>@ swap = @border;
			@border = nextBorder;
			@nextBorder = swap;
			nextBorder.length = 0;
		}
	}
#section all
};


class RandomMapVision : EmpireTrigger {
	Document doc("Grants memory of planets in random systems.");
	Argument count(AT_Integer, doc="Amount of systems to randomly choose.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		uint count = min(arguments[0].integer, systemCount);
		set_int picked;
		
		for(uint i = 0; i < count; ++i) {
			for(uint try = 0; try < 5; ++try) {
				auto@ sys = getSystem(randomi(0, systemCount-1));
				if(picked.contains(sys.object.id))
					continue;
				sys.object.grantMemory(emp);
				picked.insert(sys.object.id);
				break;
			}
		}
	}
#section all
};


class GiveLoyalty : BonusEffect {
	Document doc("Restores loyalty to the target planet.");
	Argument amount(AT_Decimal, doc="Amount of loyalty to restore.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		obj.restoreLoyalty(amount.decimal);
	}
#section all
};


class GenerateDefenseShips : BonusEffect {
	Document doc("Spawn defense ships around the target planet.");
	Argument amount(AT_Range, doc="Labor value's worth of supports.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null) {
			if(obj.hasSurfaceComponent)
				obj.spawnDefenseShips(amount.fromRange());
			else
				obj.owner.spawnDefenseAt(obj, amount.fromRange());
		}
	}
#section all
};

class ModDefenseReserve : EmpireTrigger {
	Document doc("Add to the maximum defense reserve amount.");
	Argument amount(AT_Range, doc="Amount of defense reserve to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modDefenseStorage(amount.fromRange());
	}
#section all
};

class AddPermanentEffectiveness : BonusEffect {
	Document doc("Add permanent effectiveness to the target fleet.");
	Argument amount(AT_Range, doc="Percentage amount of effectiveness to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.isShip)
			return;
		Ship@ flagship = cast<Ship>(obj);
		if(flagship.hasSupportAI)
			@flagship = cast<Ship>(flagship.Leader);
		if(flagship !is null)
			flagship.modFleetEffectiveness(+amount.fromRange());
	}
#section all
};

class ModAttribute : EmpireTrigger {
	Document doc("Modify an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to modify.");
	Argument mode(AT_AttributeMode, doc="How to modify the attribute.");
	Argument value(AT_Decimal, doc="How much to modify the attribute.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.modAttribute(uint(attribute.integer), mode.integer, value.decimal);
	}
#section all
};


class ModAttributeTimed : EmpireTrigger {
	Document doc("Modify an empire attribute for a limited duration.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to modify.");
	Argument mode(AT_AttributeMode, doc="How to modify the attribute.");
	Argument value(AT_Decimal, doc="How much to modify the attribute.");
	Argument duration(AT_Decimal, doc="Duration to modify the attribute for.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.createAttributeMod(uint(attribute.integer), mode.integer, value.decimal, duration.decimal);
	}
#section all
};


class AddStatus : BonusEffect {
	Document doc("Add a status effect to the target object.");
	Argument type(AT_Status, doc="Type of status effect to add.");
	Argument duration(AT_Decimal, "-1", doc="Duration to add the status for, -1 for permanent.");
	Argument set_origin_empire(AT_Boolean, "False", doc="Whether to record the empire triggering this hook into the origin empire field of the resulting status. If not set, any hooks that refer to Origin Empire cannot not apply. Status effects with different origin empires set do not collapse into stacks.");
	Argument set_origin_object(AT_Boolean, "False", doc="Whether to record the object triggering this hook into the origin object field of the resulting status. If not set, any hooks that refer to Origin Object cannot not apply. Status effects with different origin objects set do not collapse into stacks.");
	Argument max_stacks(AT_Integer, "0", doc="If set to more than 0, never add stacks beyond a certain amount.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Empire@ origEmp = null;
		if(set_origin_empire.boolean)
			@origEmp = emp;
		Object@ origObj = null;
		if(set_origin_object.boolean)
			@origObj = obj;

		if(max_stacks.integer > 0) {
			if(obj.getStatusStackCount(type.integer, originEmpire=origEmp, originObject=origObj) >= uint(max_stacks.integer))
				return;
		}
		obj.addStatus(uint(type.integer), duration.decimal, originEmpire=origEmp, originObject=origObj);
	}
#section all
};


class RemoveStatus : BonusEffect {
	Document doc("Remove all instances of a status effect from the target object.");
	Argument type(AT_Status, doc="Type of status effect to remove.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		obj.removeStatusType(uint(type.integer));
	}
#section all
};

class RemoveStatusInstance : BonusEffect {
	Document doc("Remove a single instance of a particular status effect.");
	Argument type(AT_Status, doc="Type of status effect to remove.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		obj.removeStatusInstanceOfType(uint(type.integer));
	}
#section all
};


class AddRegionStatus : BonusEffect {
	Document doc("Add a status effect to everything in the target region.");
	Argument type(AT_Status, doc="Type of status effect to add.");
	Argument duration(AT_Decimal, "-1", doc="Duration to add the status for, -1 for permanent.");
	Argument empire_limited(AT_Boolean, "True", doc="Whether the status should be limited to the target empire.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ region = cast<Region>(obj);
		if(region is null)
			@region = obj.region;
		if(region is null)
			return;
		if(!empire_limited.boolean)
			@emp = null;
		region.addRegionStatus(emp, uint(type.integer), duration.decimal);
	}
#section all
};


class TakeControl : BonusEffect {
	Document doc("The target empire takes control of the target object.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || emp is null)
			return;
		if(obj.isPlanet)
			obj.takeoverPlanet(emp, 0.5);
		else if(obj.isShip && obj.hasLeaderAI)
			obj.takeoverFleet(emp, 1.0, false);
		else
			@obj.owner = emp;
	}
#section all
};


class MoveToOwnedSystem : BonusEffect {
	Document doc("Move the target object to a system owned by the target empire.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || emp is null)
			return;

		//Find target system
		DataList@ objs = emp.getPlanets();
		array<Planet@> planets;
		Object@ rec;
		while(receive(objs, rec)) {
			Planet@ pl = cast<Planet>(rec);
			if(pl is null)
				continue;
			planets.insertLast(pl);
		}

		if(planets.length == 0) {
			obj.destroy();
			return;
		}

		Planet@ targPl = planets[randomi(0, planets.length - 1)];
		SystemDesc@ targSys = getSystem(targPl.region);

		if(targSys is null) {
			obj.destroy();
			return;
		}

		vec3d pos = targSys.position;
		vec2d offset = random2d(150.0, targSys.radius - 150.0);
		pos.x += offset.x;
		pos.z += offset.y;

		obj.position = pos;
		if(obj.hasOrbit && obj.inOrbit)
			obj.orbitAround(pos, targSys.position);
		else if(obj.hasLeaderAI)
			obj.teleportTo(pos);
	}
#section all
};

class MoveToSystemCenter : BonusEffect {
	Document doc("Move the object's origin to the center of the system it is in.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ reg = obj.region;
		if(reg !is	null) {
			if(obj.hasOrbit)
				obj.stopOrbit();
			obj.position = reg.position;
		}
	}
#section all
};


class SpawnCreepCamp : BonusEffect {
	Document doc("Spawn a creep capm at the target object's poistion.");
	Argument type("Camp Type", AT_CreepCamp, "distributed", doc="Type of creep camp to spawn. Defaults to randomized.");

	const CampType@ campType;

	bool instantiate() {
		if(!type.str.equals_nocase("distributed")) {
			@campType = getCreepCamp(type.str);
			if(campType is null) {
				error(" Error: Could not find creep camp type: '"+escape(type.str)+"'");
				return false;
			}
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		const CampType@ type = campType;
		if(type is null)
			@type = getDistributedCreepCamp();

		makeCreepCamp(obj.position, type);
	}
#section all
};

class SpawnAnomaly : BonusEffect {
	Document doc("Spawn an anomaly at the location of the object this effect triggers on.");
	Argument type(AT_Anomaly, "distributed", doc="Type of anomaly to spawn. Defaults to randomized.");
	Argument start_scanned(AT_Boolean, "False", doc="Whether the anomaly starts out scanned by the empire that triggered this.");
	Argument random_system(AT_Boolean, "False", doc="Whether to spawn the anomaly in a random system instead of where the effect was triggered.");
	Argument give_vision(AT_Boolean, "False", doc="Whether to give immediate vision/memory over the anomaly to the empire that triggered its creation.");

	const AnomalyType@ anomType;

	bool instantiate() {
		if(!type.str.equals_nocase("distributed")) {
			@anomType = getAnomalyType(type.str);
			if(anomType is null) {
				error(" Error: Could not find anomaly type: '"+escape(type.str)+"'");
				return false;
			}
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		const AnomalyType@ type = anomType;
		if(type is null) {
			do {
				@type = getDistributedAnomalyType();
			}
			while(type.unique);
		}

		double rad = obj.radius + 20.0;
		vec3d pos = obj.position + random3d(rad*1.2, rad*2.0);

		if(random_system.boolean) {
			auto@ sys = getSystem(randomi(0, systemCount-1));
			if(sys !is null) {
				pos = sys.position;
				vec2d off = random2d(200.0, sys.radius);
				pos.x += off.x;
				pos.y += randomd(-20.0, 20.0);
				pos.z += off.y;
			}
		}

		Anomaly@ anomaly = createAnomaly(pos, type.id);
		if(start_scanned.boolean && emp !is null)
			anomaly.addProgress(emp, 10000000000.f);
		if(give_vision.boolean && emp !is null)
			anomaly.donatedVision |= emp.mask;
	}
#section all
};

class SpawnSupports : BonusEffect {
	Document doc("Spawn a number of supports around the target object owned by the target empire.");
	Argument design("Design", AT_Custom, doc="Design of the supports to spawn.");
	Argument amount("Amount", AT_Range, doc="Amount of supports to spawn.");
	Argument creep_design("Creep Design", AT_Boolean, "False", doc="Whether to use a design from the creeps or the empire.");
	Argument radius("Distance", AT_Decimal, "100", doc="Radius to spread the ships out over.");
	Argument prevent_expire("No Expiration", AT_Boolean, "True", doc="Whether to prevent the supports from ever expiring.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		const Design@ dsg;
		if(arguments[2].boolean)
			@dsg = Creeps.getDesign(arguments[0].str);
		else
			@dsg = emp.getDesign(arguments[0].str);
		if(dsg is null) {
			error("Could not find design "+arguments[0].str+" ("+arguments[2].boolean+")");
			return;
		}
		bool preventExpire = arguments[4].boolean;
		for(uint i = 0, cnt = arguments[1].fromRange(); i < cnt; ++i) {
			vec3d pos = obj.position;
			pos += random3d(0.0, arguments[3].decimal);

			Ship@ ship = createShip(pos, dsg, emp);
			if(preventExpire)
				ship.preventExpire();
		}
	}
#section all
};


class SpawnRandomSlipstream : BonusEffect {
	Document doc("Spawn a slipstream tear to a random location.");
	Argument duration("Duration", AT_Decimal, "-1", doc="Duration in seconds for the slipstream to last. -1 for permanent.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		vec3d from = obj.position;

		auto@ sys = getSystem(randomi(0, systemCount-1));
		vec3d to = sys.position;
		vec2d offset = random2d(125.0, sys.radius - 10.0);
		to.x += offset.x;
		to.z += offset.y;

		createSlipstream(from, to, duration.decimal);
	}
#section all
};


class SpawnOrbital : EmpireTrigger {
	Document doc("Spawn an orbital.");
	Argument type("Core", AT_OrbitalModule, doc="Type of orbital core to use.");
	Argument creep_owned("Creep Owned", AT_Boolean, "False", doc="Whether the orbital should be owned by the creeps.");
	Argument free("Free", AT_Boolean, "False", doc="Whether to make the orbital free of maintenance.");
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="Status effect to add to the orbital after it is created.");
	Argument in_orbit(AT_Boolean, "False", doc="Whether to spawn somewhere in orbit around the target object.");
	Argument set_home(AT_Boolean, "False", doc="Whether to set the orbital as a home object.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		auto@ def = getOrbitalModule(arguments[0].integer);
		vec3d pos;
		if(obj !is null) {
			pos = obj.position;
			if(in_orbit.boolean) {
				double minRad = 0.0, maxRad = 0.0;
				if(obj.isStar)
					@obj = obj.region;
				if(obj is null)
					return;
				if(obj.isPlanet) {
					minRad = obj.radius * 1.1;
					maxRad = cast<Planet>(obj).OrbitSize;
				}
				else if(obj.isRegion) {
					minRad = 400.0;
					maxRad = cast<Region>(obj).radius - 250.0;
				}
				vec2d off = random2d(minRad + def.size, maxRad - def.size);
				pos.x += off.x;
				pos.z += off.y;
			}
		}
		else {
			Region@ region;
			if(emp.Homeworld !is null) {
				@region = emp.Homeworld.region;
			}
			else if(emp.HomeObj !is null) {
				@region = emp.HomeObj.region;
				if(region is null)
					@region = getRegion(emp.HomeObj.position);
			}
			if(region is null)
				return;
			pos = region.position;
			vec2d off = random2d(400.0, region.radius - 200.0);
			pos.x += off.x;
			pos.z += off.y;
		}
		
		auto@ orb = createOrbital(pos, def, arguments[1].boolean ? Creeps : emp);
		if(arguments[2].boolean && !arguments[1].boolean)
			orb.makeFree();
		if(add_status.integer != -1)
			orb.addStatus(add_status.integer);
		if(set_home.boolean)
			@emp.HomeObj = orb;
	}

	void init(Empire& emp, any@ data) const override {}
	void postInit(Empire& emp, any@ data) const override { activate(null, emp); }
#section all
};


class ReduceInfluenceIncome : EmpireTrigger {
	Document doc("Reduce the empire's influence income by a factor for a duration.");
	Argument duration("Duration", AT_Decimal, doc="Duration of the reduction.");
	Argument multiplier("Factor", AT_Decimal, doc="Multiplier to the influence income.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.reserveInfluence(factor=arguments[1].decimal, timer=arguments[0].decimal);
	}
#section all
};

class SetInCombat : BonusEffect {
	Document doc("Flag the object as currently being in combat.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null) {
			obj.engaged = true;
			obj.inCombat = true;
		}
	}
#section all
};

class Destroy : BonusEffect {
	Document doc("Destroy the target object.");
	Argument quiet(AT_Boolean, "False", doc="Apply quiet destruction, where appropriate.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.valid) {
			if(obj.isPlanet && quiet.boolean)
				cast<Planet>(obj).destroyQuiet();
			else
				obj.destroy();
		}
	}
#section all
};


class StealInfluencePointsFromAll : EmpireTrigger {
	Document doc("Steal influence points from all other empires.");
	Argument amount("Amount", AT_Integer, doc="Amount of influence points to steal from each.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;

		int total = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(other is emp || !other.major)
				continue;

			int steal = min(other.Influence, arguments[0].integer);
			other.modInfluence(-steal);
			total += steal;
		}

		emp.modInfluence(+total);
	}
#section all
};


class NotifyOwner : EmpireTrigger {
	Document doc("Notify the triggering empire of an event.");
	Argument title("Title", AT_Custom, doc="Title of the notification.");
	Argument desc("Description", AT_Custom, EMPTY_DEFAULT, doc="Description of the notification.");
	Argument icon("Icon", AT_Sprite, EMPTY_DEFAULT, doc="Sprite specifier for the notification icon.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null && obj !is null)
			@emp = obj.owner;
		if(emp !is null)
			emp.notifyGeneric(title.str, desc.str, icon.str, emp, obj);
	}
#section all
};


class NotifyAll : EmpireTrigger {
	Document doc("Notify all other empires of an event.");
	Argument title("Title", AT_Custom, doc="Title of the notification.");
	Argument desc("Description", AT_Custom, EMPTY_DEFAULT, doc="Description of the notification.");
	Argument icon("Icon", AT_Sprite, EMPTY_DEFAULT, doc="Sprite specifier for the notification icon.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(other is emp || !other.major)
				continue;

			other.notifyGeneric(arguments[0].str, arguments[1].str, arguments[2].str, emp, obj);
		}
	}
#section all
};


class GrantAbility : EmpireTrigger {
	Document doc("Grant an ability to the target object or empire.");
	Argument type("Ability", AT_Ability, doc="Type of ability to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null)
			obj.addAbility(arguments[0].integer);
		else if(emp !is null)
			emp.addAbility(arguments[0].integer);
	}
#section all
};


class GrantRegionVision : BonusEffect {
	Document doc("Grant vision over the target region.");
	Argument timer("Duration", AT_Decimal, "-1", doc="Duration in seconds for vision to last. -1 for permanent.");
	Argument hops("Hops", AT_Integer, "0", doc="Amount of additional hops to give vision in.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ reg = cast<Region>(obj);
		if(reg is null && obj !is null)
			@reg = obj.region;
		if(reg is null || emp is null)
			return;

		if(arguments[0].decimal < 0)
			reg.grantVision(emp);
		else
			reg.addTemporaryVision(emp, arguments[0].decimal);

		uint hops = arguments[1].integer;
		if(hops != 0)
			grant(emp, getSystem(reg), hops);
	}

	void grant(Empire@ emp, SystemDesc@ sys, uint hops) {
		if(sys is null)
			return;
		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			auto@ other = getSystem(sys.adjacent[i]);
			if(arguments[0].decimal < 0)
				other.object.grantVision(emp);
			else
				other.object.addTemporaryVision(emp, arguments[0].decimal);
			if(hops > 1)
				grant(emp, other, hops-1);
		}
	}
#section all
};

class PricedAsteroid : BonusEffect {
	Document doc("Adds an asteroid with the specified resources.");
	Argument cost(AT_Decimal, doc="Cost of all the resources.");
	Argument resources(AT_VarArgs, AT_PlanetResource, required=true, doc="Resources on the asteroid.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Asteroid@ roid = createAsteroid(obj.position);
		Region@ reg = obj.region;
		if(reg !is null) {
			roid.orbitAround(reg.position);
			roid.orbitSpin(randomd(20.0, 60.0));
		}
		for(uint i = 1, cnt = arguments.length; i < cnt; ++i)
			roid.addAvailable(arguments[i].integer, arguments[0].decimal);
	}
#section all
};


class OwnedAsteroid : BonusEffect {
	Document doc("Add an asteroid owned by the empire with the specified resources.");
	Argument resources(AT_VarArgs, AT_PlanetResource, required=true, doc="Resources on the asteroid.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		vec3d pos = obj.position;
		vec2d off = random2d(5.0);
		pos.x += off.x;
		pos.z += off.y;

		Asteroid@ roid = createAsteroid(pos);
		Region@ reg = obj.region;
		if(reg !is null) {
			roid.orbitAround(reg.position);
			roid.orbitSpin(randomd(20.0, 60.0));
		}
		roid.addAvailable(arguments[0].integer, 0.0);
		roid.setup(null, emp, arguments[0].integer);
		for(uint i = 1, cnt = arguments.length; i < cnt; ++i)
			roid.createResource(arguments[i].integer);
	}
#section all
};


class SpawnAsteroids : BonusEffect {
	Document doc("Spawn an amount of asteroids around the object.");
	Argument amount("Amount", AT_Integer, doc="Amount of asteroids to spawn.");
	Argument offset("Distance", AT_Decimal, "80", doc="Radius to spread the asteroids out over.");
	Argument cargo(AT_Cargo, EMPTY_DEFAULT, doc="Type of cargo to create on the asteroid.");
	Argument cargo_amount(AT_Range, "500:10000", doc="Amount of cargo for the asteroid to have.");
	Argument distribution_chance(AT_Decimal, "0.4", doc="For distributed resources, chance to add additional resource. Repeats until failure.");
	Argument resource_only(AT_Boolean, "False", doc="Whether to only spawn resource asteroids.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		for(uint i = 0, cnt = arguments[0].integer; i < cnt; ++i) {
			vec3d pos = obj.position;
			if(obj.isRegion)
				pos += random3d(200.0, obj.radius * 0.75);
			else
				pos += random3d(arguments[1].decimal + obj.radius);

			double totChance = config::ASTEROID_OCCURANCE + config::RESOURCE_ASTEROID_OCCURANCE;
			double resChance = config::RESOURCE_ASTEROID_OCCURANCE;
			double roll = randomd(0, totChance);

			int cargoType = cargo.integer;
			if(cargoType == -1) {
				auto@ ore = getCargoType("Ore");
				if(ore !is null)
					cargoType = ore.id;
			}

			Asteroid@ roid = createAsteroid(pos, delay=true);
			Region@ reg = obj.region;
			if(reg !is null) {
				roid.orbitAround(reg.position);
				roid.orbitSpin(randomd(20.0, 60.0));
			}

			if(!resource_only.boolean && (cargo.integer != -1 || (cargoType != -1 && roll >= resChance))) {
				roid.addCargo(cargoType, cargo_amount.fromRange());
			}
			else {
				do {
					const ResourceType@ type = getDistributedAsteroidResource();
					if(roid.getAvailableCostFor(type.id) < 0.0)
						roid.addAvailable(type.id, type.asteroidCost);
				}
				while(randomd() < distribution_chance.decimal);
			}

			roid.initMesh();
		}
	}
#section all
};


class TerraformToLevel : BonusEffect {
	Document doc("Instantly terraform the target planet to a random resource of a level.");
	Argument level("Level", AT_Integer, doc="Level of resource to terraform to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Planet@ pl = cast<Planet>(obj);
		if(pl is null)
			return;

		auto@ resource = getDistributedResource(level=arguments[0].integer);
		pl.startTerraform();
		pl.terraformTo(resource.id);
	}
#section all
};

class TerraformTo : BonusEffect {
	Document doc("Instantly terraform the target planet to a particular resource.");
	Argument resource(AT_PlanetResource, doc="Resource to terraform to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Planet@ pl = cast<Planet>(obj);
		if(pl is null)
			return;

		pl.startTerraform();
		pl.terraformTo(resource.integer);
	}
#section all
};


class DevelopTiles : BonusEffect {
	Document doc("Develop an amount of tiles on the target planet.");
	Argument amount("Amount", AT_Integer, doc="Amount of tiles to develop.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj.hasSurfaceComponent)
			obj.developTiles(arguments[0].integer);
	}
#section all
};


class DestroyAnomalies : BonusEffect {
	Document doc("Destroy all anomalies of a particular type in the target region.");
	Argument type("Type", AT_Anomaly, doc="Type of anomalies to destroy.");

	const AnomalyType@ anomType;

	bool instantiate() {
		@anomType = getAnomalyType(arguments[0].str);
		if(anomType is null) {
			error(" Error: Could not find anomaly type: "+arguments[0].str);
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ reg = obj.region;
		if(reg is null)
			return;

		uint cnt = reg.anomalyCount;
		for(uint i = 0; i < cnt; ++i) {
			Anomaly@ other = reg.anomalies[i];
			if(other is null)
				continue;
			if(other is obj)
				continue;
			if(other.anomalyType != anomType.id)
				continue;
			other.destroy();
		}
	}
#section all
}


class MorphSystemPlanetResource : BonusEffect {
	Document doc("Morph the resource of the <Index>th planet in the target region.");
	Argument index(AT_Integer, doc="Index of the planet to morph.");
	Argument resource(AT_PlanetResource, doc="Resource to morph to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ reg = obj.region;
		if(reg is null)
			return;
		Planet@ other = reg.planets[arguments[0].integer];
		if(other is null)
			return;
		other.terraformTo(arguments[1].integer);
	}
#section all
}

class DestroySystemPlanet : BonusEffect {
	Document doc("Destroy the <Index>th planet in the target region.");
	Argument index(AT_Integer, doc="Index of the planet to morph.");
	Argument quiet(AT_Boolean, "False", doc="Whether to silently destroy the planet and play no effect and generate no asteroids.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ reg = obj.region;
		if(reg is null)
			return;
		Planet@ other = reg.planets[arguments[0].integer];
		if(other is null)
			return;
		if(other is emp.Homeworld)
			@emp.Homeworld = null;
		if(quiet.boolean)
			other.destroyQuiet();
		else
			other.destroy();
	}
#section all
}

class SpawnBuilding : BonusEffect {
	Document doc("Attempt to spawn a building at a particular position.");
	Argument type(AT_Building, doc="Type of building to spawn.");
	Argument position(AT_Position2D, doc="Surface position to spawn at.");
	Argument develop(AT_Boolean, "False", doc="Whether to mark all tiles its on as developed.");

	const BuildingType@ bldType;

	bool instantiate() {
		@bldType = getBuildingType(type.str);
		if(bldType is null) {
			error(" Error: Could not find building type: '"+escape(type.str)+"'");
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.spawnBuilding(bldType.id, vec2i(position.fromPosition2D()), develop.boolean);
	}
#section all
};

class QueueBuilding : BonusEffect {
	Document doc("Attempt to normally queue the construction of a building on a planet.");
	Argument type(AT_Building, doc="Type of building to build.");
	Argument position(AT_Position2D, doc="Surface position to spawn at.");

	int bldType = -1;

	bool instantiate() {
		bldType = getBuildingID(type.str);
		if(bldType == -1) {
			error(" Error: Could not find building type: '"+escape(type.str)+"'");
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.buildBuilding(bldType, vec2i(position.fromPosition2D()));
	}
#section all
};

class DestroyBuildingAt : BonusEffect {
	Document doc("Destroy the building at a specified position.");
	Argument position(AT_Position2D, doc="Surface position to destroy at.");
	Argument undevelop(AT_Boolean, "False", doc="Whether to remove developed status on the tiles the building was on.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.forceDestroyBuilding(vec2i(position.fromPosition2D()), undevelop.boolean);
	}
#section all
};

class GiveAchievement : EmpireTrigger {
	Document doc("Grants an achievement upon activation.");
	Argument achieve(AT_Custom, doc="Achievement ID to grant.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		giveAchievement(emp, achieve.str);
	}
#section all
};

class SpawnArtifact : BonusEffect {
	Document doc("Spawn an artifact at the target object's poistion.");
	Argument type(AT_Artifact, EMPTY_DEFAULT, doc="Type of artifact to spawn. Defaults to randomized.");
	Argument in_system(AT_Boolean, "False", doc="Whether to spawn the artifact somewhere in the system, instead of on top of the object.");
	Argument allow_natural(AT_Boolean, "False", doc="If no artifact type is distributed, whether to allow natural artifacts to be randomly spawned.");
	Argument owned(AT_Boolean, "False", doc="Whether the artifact should be owned by the empire that caused it to spawn.");
	Argument expire(AT_Decimal, "-1", doc="If set to a positive number, the artifact will expire after the specified amount of seconds.");

	const ArtifactType@ artifType;

	bool instantiate() {
		if(!BonusEffect::instantiate())
			return false;
		@artifType = getArtifactType(type.integer);
		return true;
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		const ArtifactType@ type = artifType;
		if(type is null) {
			do {
				@type = getDistributedArtifactType();
			} while((!allow_natural.boolean && type.natural) || type.unique);
		}

		vec3d pos = obj.position;
		if(in_system.boolean) {
			Region@ reg = obj.region;
			if(reg is null)
				@reg = getRegion(obj.position);
			if(reg !is null) {
				pos = reg.position;
				vec2d off = random2d(200.0, reg.radius);
				pos.x += off.x;
				pos.y += randomd(-20.0, 20.0);
				pos.z += off.y;
			}
		}

		Artifact@ artif = createArtifact(pos, type);
		Region@ region = obj.region;
		if(region !is null)
			artif.orbitAround(region.position);
		if(owned.boolean && emp !is null)
			@artif.owner = emp;
		if(expire.decimal > 0)
			artif.setExpire(expire.decimal);
	}
#section all
};

class SpawnPlanet : BonusEffect {
	Document doc("Spawn a new planet at the current position.");
	Argument resource(AT_Custom, "distributed");
	Argument owned(AT_Boolean, "False", doc="Whether the planet starts colonized.");
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="A status to add to the planet after it is spawned.");
	Argument in_system(AT_Boolean, "False", doc="Whether to spawn the planet somewhere in the system, instead of on top of the object.");
	Argument radius(AT_Range, "0", doc="Radius of the resulting planet.");
	Argument physics(AT_Boolean, "True", doc="Whether the planet should be a physical object.");
	Argument set_homeworld(AT_Boolean, "False", doc="Whether to set this planet as the homeworld.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		vec3d point = obj.position;
		if(in_system.boolean) {
			Region@ reg = obj.region;
			if(reg !is null) {
				point = reg.position;
				vec2d off = random2d(200.0, reg.radius);
				point.x += off.x;
				point.y += randomd(-20.0, 20.0);
				point.z += off.y;
			}
		}
		auto@ planet = spawnPlanetSpec(point, resource.str, true, radius.fromRange(), physics.boolean);
		if(owned.boolean && emp !is null)
			planet.colonyShipArrival(emp, 1.0);
		if(add_status.integer != -1)
			planet.addStatus(add_status.integer);
		if(set_homeworld.boolean) {
			@emp.Homeworld = planet;
			@emp.HomeObj = planet;
		}
	}
#section all
};

class SpawnShip : EmpireTrigger {
	Document doc("Spawn a ship at the location of the object.");
	Argument design(AT_Custom);
	Argument design_from(AT_Custom, "Player");
	Argument supports(AT_VarArgs, AT_Custom);
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="A status to add to the ship after it is spawned.");
	Argument override_disable_starting(AT_Boolean, "False", doc="If called in a trait, do not disable this spwan even if starting fleets are disabled.");
	Argument set_home(AT_Boolean, "False", doc="If called in a trait, set this as the home object.");
	Argument offset(AT_Decimal, "0", doc="Offset from the object position to spawn.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Empire@ designEmp = emp;
		if(design_from.str.length != 0) {
			if(design_from.str.equals_nocase("Creeps")
					|| design_from.str.equals_nocase("Remnants")) {
				@designEmp = Creeps;
			}
		}

		vec3d pos;
		if(obj !is null) {
			pos = obj.position;
			if(obj.isRegion) {
				vec2d off = random2d(obj.radius * 0.4, obj.radius * 0.9);
				pos.x += off.x;
				pos.z += off.y;
			}
			else if(offset.decimal != 0) {
				vec2d off = random2d(offset.decimal);
				pos.x += off.x;
				pos.z += off.y;
			}
		}
		else if(emp !is null && (emp.Homeworld !is null || emp.HomeObj !is null)) {
			if(config::DISABLE_STARTING_FLEETS != 0 && designEmp is emp && !override_disable_starting.boolean)
				return;
			Region@ region;
			if(emp.Homeworld !is null) {
				@region = emp.Homeworld.region;
			}
			else {
				@region = emp.HomeObj.region;
				if(region is null)
					@region = getRegion(emp.HomeObj.position);
			}
			vec2d offset = random2d(200.0, region.radius * 0.5);
			pos = region.position + vec3d(offset.x, 0, offset.y);
		}
		else {
			return;
		}

		auto@ dsg = designEmp.getDesign(design.str);
		if(dsg !is null) {
			Ship@ leader = createShip(pos, dsg, emp, free=true);

			for(uint i = 2, cnt = arguments.length; i < cnt; ++i) {
				string arg = arguments[i].str;
				int pos = arg.findFirst("x ");
				if(pos != -1) {
					uint count = toUInt(arg.substr(0, pos));
					string dsgName = arg.substr(pos+2).trimmed();
					@dsg = designEmp.getDesign(dsgName);
					if(dsg !is null) {
						for(uint n = 0; n < count; ++n)
							createShip(leader.position, dsg, emp, leader, free=true);
					}
				}
			}

			if(add_status.integer != -1)
				leader.addStatus(add_status.integer);
			if(set_home.boolean)
				@emp.HomeObj = leader;
		}
	}

	void init(Empire& emp, any@ data) const override {}
	void postInit(Empire& emp, any@ data) const override { activate(null, emp); }
#section all
};

class SpawnCreepShip : BonusEffect {
	Document doc("Spawn a creep ship at the location.");
	Argument design(AT_Custom);
	Argument status(AT_Status, doc="Type of status effect to add to the creep ship.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Empire@ designEmp = Creeps;

		vec3d pos;
		if(obj !is null) {
			pos = obj.position;
		}
		else if(emp !is null && (emp.Homeworld !is null || emp.HomeObj !is null)) {
			Region@ region;
			if(emp.Homeworld !is null) {
				@region = emp.Homeworld.region;
			}
			else {
				@region = emp.HomeObj.region;
				if(region is null)
					@region = getRegion(emp.HomeObj.position);
			}
			vec2d offset = random2d(200.0, region.radius * 0.5);
			pos = region.position + vec3d(offset.x, 0, offset.y);
		}

		auto@ dsg = designEmp.getDesign(design.str);
		Ship@ leader = createShip(pos, dsg, Creeps, free=true);
		leader.addStatus(status.integer, -1.0, originEmpire=emp, originObject=obj);
	}
#section all
};

class UnlockSubsystem : EmpireTrigger {
	Document doc("Set a particular subsystem as unlocked in the affected empire.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to unlock.");

#section server
	void preInit(Empire& emp, any@ data) const override { activate(null, emp); }
	void init(Empire& emp, any@ data) const override {}

	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.setUnlocked(getSubsystemDef(subsystem.integer), true);
	}
#section all
};

class ForbidSubsystem : EmpireTrigger {
	Document doc("Set a particular subsystem as not unlocked in the affected empire.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to forbid.");

#section server
	void preInit(Empire& emp, any@ data) const override { activate(null, emp); }
	void init(Empire& emp, any@ data) const override {}

	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.setUnlocked(getSubsystemDef(subsystem.integer), false);
	}
#section all
};

class UnlockModule : EmpireTrigger {
	Document doc("Set a particular modifier module as unlocked in all subsystems that support it.");
	Argument module(AT_Custom, doc="Identifier of the module to unlock.");

#section server
	void preInit(Empire& emp, any@ data) const override { activate(null, emp); }
	void init(Empire& emp, any@ data) const override {}

	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			auto@ sys = getSubsystemDef(i);
			auto@ mod = sys.module(module.str);
			if(mod !is null)
				emp.setUnlocked(sys, mod, true);
		}
	}
#section all
};

class AddStoredLabor : BonusEffect {
	Document doc("Generates an amount of labor into the object's labor storage. Only works on objects with construction capabilities.");
	Argument amount(AT_Decimal, doc="Amount of stored labor to generate.");
	Argument obey_capacity(AT_Boolean, "False", doc="If set, the object's stored labor will not go over its labor storage capacity. Otherwise, the object can store more labor than its capacity.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		if(!obj.hasConstruction)
			return;
		obj.modStoredLabor(amount.decimal, obeyCap=obey_capacity.boolean);
	}
#section all
};

class UnlockTag : EmpireTrigger {
	Document doc("Marks a particular unlock tag as unlocked on the empire when triggered, permanently.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to unlock. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.setTagUnlocked(tag.integer, true);
	}
#section all
};

class RemoveUnlockTag : EmpireTrigger {
	Document doc("Marks a particular unlock tag as no longer unlocked on the empire when triggered, permanently.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to remove. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.setTagUnlocked(tag.integer, false);
	}
#section all
};

class RemoveTechnologyNodes : EmpireTrigger {
	Document doc("Remove all currently un-researched research nodes of a particular type of technology from the grid, making them unable to be researched.");
	Argument type(AT_Technology, doc="Type of technology to remove nodes of.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.removeResearchOfType(type.integer);
	}
#section all
};

class ReplaceTechnologyNodes : EmpireTrigger {
	Document doc("Replace all un-researched technology nodes of a particular type with another type.");
	Argument type(AT_Technology, doc="Type of technology to replace nodes of.");
	Argument replace_with(AT_Technology, doc="Type of technology to replace nodes with.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.replaceResearchOfType(type.integer, replace_with.integer);
	}
#section all
};

class ReplaceTechnologyNodeAt : EmpireTrigger {
	Document doc("Replace all un-researched technology nodes of a particular type with another type.");
	Argument pos(AT_Position2D, doc="Position of the node to replace.");
	Argument replace_with(AT_Technology, doc="Type of technology to replace nodes with.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.replaceResearchAt(vec2i(pos.fromPosition2D()), replace_with.integer);
	}
#section all
};

class ReplaceTechnologyGrid : EmpireTrigger {
	Document doc("Replace the entire technology grid by a new named grid from the files. Any already unlocked bonuses will be kept.");
	Argument type(AT_Custom, doc="Name of the grid to replace with.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.replaceResearchGrid(type.str);
	}
#section all
};

class PlayParticles : BonusEffect {
	Document doc("Play particles at the object's position when activated.");
	Argument type(AT_Custom, doc="Which particle effect to play.");
	Argument scale(AT_Decimal, "1.0", doc="Scale of the particle effect.");
	Argument object_scale(AT_Boolean, "True", doc="Whether to scale the particle effect to the object's scale as well.");
	Argument object_tied(AT_Boolean, "True", doc="Whether the particle effect is tied to the object.");
	Argument fleet_scale(AT_Boolean, "False", doc="Whether to scale the particle effect to the fleet's scale instead of the object's.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		double size = scale.decimal;
		if(fleet_scale.boolean && obj.hasLeaderAI)
			size *= obj.getFormationRadius();
		else if(object_scale.boolean)
			size *= obj.radius;
		if(object_tied.boolean)
			playParticleSystem(type.str, vec3d(), quaterniond(), size, obj);
		else
			playParticleSystem(type.str, obj.position, quaterniond(), size);
	}
#section all
};

class DismissTaggedEffects : EmpireTrigger {
	Document doc("Dismiss all active influence effects that have a particular tag, owned by any empire.");
	Argument tag(AT_Custom, doc="Tag to select influence effects by.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		auto@ effs = getActiveInfluenceEffects();
		for(uint i = 0, cnt = effs.length; i < cnt; ++i) {
			if(effs[i].type.tags.find(tag.str) != -1)
				dismissEffect(emp, effs[i].id);
		}
	}
#section all
};

class SpawnPirateAgainst : EmpireTrigger {
	Document doc("Spawns a new pirate ship that will only raid the empire this is activated against.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		spawnPirateShip(limitEmpire=emp);
	}
#section all
};

tidy final class TriggerAllEmpires : EmpireTrigger {
	Document doc("Trigger the specified hook once on all empires in the game.");
	Argument hookID(AT_Hook, "bonus_effects::EmpireTrigger");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerAllEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(!other.valid || !other.major)
				continue;
			if(hook !is null)
				hook.activate(obj, other);
		}
	}
#section all
};

tidy final class TriggerAllPlanets : EmpireTrigger {
	Document doc("Trigger the specified hook once on every planet the empire owns. This is a single-time trigger, so will only apply on all current objects, not future ones.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerAllEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		for(uint i = 0, cnt = emp.planetCount; i < cnt; ++i) {
			auto@ pl = emp.planetList[i];
			if(pl !is null && hook !is null)
				hook.activate(pl, emp);
		}
	}
#section all
};

tidy final class TriggerAllFleets : EmpireTrigger {
	Document doc("Trigger the specified hook once on every fleet the empire owns. This is a single-time trigger, so will only apply on all current objects, not future ones.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerAllEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		for(uint i = 0, cnt = emp.fleetCount; i < cnt; ++i) {
			auto@ fl = emp.fleets[i];
			if(fl !is null && hook !is null && fl.isShip)
				hook.activate(fl, emp);
		}
	}
#section all
};

class StartVote : EmpireTrigger {
	Document doc("Start a new influence vote. If the vote takes an object target, fill it with the triggered object. Other targets will not be filled.");
	Argument type(AT_InfluenceVote, doc="Type of vote to start.");
	Argument start_ownerless(AT_Boolean, "False", doc="Whether to start the vote without an owner, like zeitgeists, or whether to have the triggering empire as its owner.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null || start_ownerless.boolean)
			@emp = defaultEmpire;

		auto@ type = getInfluenceVoteType(type.integer);
		Targets targs(type.targets);
		if(targs.length != 0 && targs[0].type == TT_Object) {
			@targs[0].obj = obj;
			targs[0].filled = true;
		}

		if(type !is null)
			startInfluenceVote(emp, type, targs);
	}
#section all
};

class CreateEffect : EmpireTrigger {
	Document doc("Start a new influence effect. If the effect takes an object target, fill it with the triggered object. Other targets will not be filled.");
	Argument type(AT_InfluenceEffect, doc="Type of effect to start.");
	Argument start_ownerless(AT_Boolean, "False", doc="Whether to start the effect without an owner, like zeitgeists, or whether to have the triggering empire as its owner.");
	Argument duration(AT_Decimal, "-1", doc="Duration of the effect. Set to 0 to use the default duration that the effect type specifies. Set to -1 to force an infinite duration effect.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null || start_ownerless.boolean)
			@emp = defaultEmpire;

		auto@ type = getInfluenceEffectType(type.integer);
		Targets targs(type.targets);
		if(targs.length != 0 && targs[0].type == TT_Object) {
			@targs[0].obj = obj;
			targs[0].filled = true;
		}

		if(type !is null)
			createInfluenceEffect(emp, type, targs, duration.decimal);
	}
#section all
};

class DealDamage : BonusEffect {
	Document doc("Deal some generic amount of damage to the object this is triggered on.");
	Argument amount(AT_Decimal, doc="Amount of damage to deal.");
	Argument spillable(AT_Boolean, "True", doc="Whether the damage can be spilled after passing through the ship or should be dealt in full in multiple instances if necessary.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		DamageEvent dmg;
		dmg.damage = amount.decimal;

		@dmg.obj = obj;
		@dmg.target = obj;
		dmg.spillable = spillable.boolean;

		obj.damage(dmg, -1.0, vec2d(1.0, 0.0));
	}
#section all
};

class DealStellarDamage : BonusEffect {
	Document doc("Deal damage to a stellar object such as a planet or star.");
	Argument amount(AT_Decimal, doc="Amount of damage to deal.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		if(obj.isPlanet)
			cast<Planet>(obj).dealPlanetDamage(amount.decimal);
		else if(obj.isStar)
			cast<Star>(obj).dealStarDamage(amount.decimal);
	}
#section all
};

class AddModifier : EmpireTrigger {
	TechAddModifier@ mod;
	string spec;
	Argument modifier(AT_Custom);

	bool parse(const string& name, array<string>& args) override {
		for(uint i = 0, cnt = args.length; i < cnt; ++i) {
			if(i != 0)
				spec += ",";
			spec += args[i];
		}
		return true;
	}

	bool instantiate() override {
		string funcName;
		array<string> argNames;
		if(!funcSplit(spec, funcName, argNames)) {
			error("Invalid modifier: "+spec);
			return false;
		}

		@mod = parseModifier(funcName);
		if(mod is null) {
			error("Invalid modifier: "+spec);
			return false;
		}

		mod.arguments = argNames;
		return BonusEffect::instantiate();
	}

#section server
	void preInit(Empire& emp, any@ data) const override { activate(null, emp); }
	void init(Empire& emp, any@ data) const override {}

	void activate(Object@ obj, Empire@ emp) const {
		if(emp !is null)
			mod.apply(emp);
	}
#section all
};

void addModifierToEmpire(Empire@ emp, const string& spec) {
	string funcName;
	array<string> argNames;
	if(!funcSplit(spec, funcName, argNames)) {
		error("Invalid modifier: "+spec);
		return;
	}

	TechAddModifier@ mod = parseModifier(funcName);
	if(mod is null) {
		error("Invalid modifier: "+spec);
		return;
	}

	mod.arguments = argNames;
	if(mod !is null && emp !is null)
		mod.apply(emp);
}

class ClearAttackOrder : EmpireTrigger {
	Document doc("Clear the object's current attack order if it has one.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasLeaderAI)
			return;
		if(obj.orderType[0] == OT_Attack)
			obj.clearTopOrder();
	}
#section all
};

class Repair : BonusEffect {
	Document doc("Repair the flagship or orbital this is applied to a set amount.");
	Argument base_amount(AT_Decimal, "0", doc="Base amount of HP to repair.");
	Argument percent(AT_Decimal, "0", doc="Percentage of maximum health to repair.");
	Argument multiply_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to multiply base healing amount by.");
	Argument multiply_percent(AT_Boolean, "False", doc="Whether to also multiply the percentage by the attribute.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		double hp = 0;
		if(obj.isShip)
			hp = cast<Ship>(obj).blueprint.design.totalHP;
		else if(obj.isOrbital)
			hp = cast<Orbital>(obj).maxHealth + cast<Orbital>(obj).maxArmor;

		double amt = base_amount.decimal;
		if(emp !is null && multiply_attribute.integer != -1 && !multiply_percent.boolean)
			amt *= emp.getAttribute(multiply_attribute.integer);
		amt += hp * percent.decimal;
		if(emp !is null && multiply_attribute.integer != -1 && multiply_percent.boolean)
			amt *= emp.getAttribute(multiply_attribute.integer);

		if(obj.isShip)
			cast<Ship>(obj).repairShip(amt);
		else if(obj.isOrbital)
			cast<Orbital>(obj).repairOrbital(amt);
	}
#section all
};

class GivePopulation : BonusEffect {
	Document doc("The planet this is triggered on instantly gains an amount of population.");
	Argument amount(AT_Decimal, doc="Amount of population to gain.");
	Argument allow_over(AT_Boolean, "True", doc="Whether to allow temporarily going over population capacity.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.addPopulation(amount.decimal, allow_over.boolean);
	}
#section all
};

class LosePopulation : BonusEffect {
	Document doc("The planet this is triggered on instantly loses an amount of population. Planet gets un-colonized if it drops to 0.");
	Argument amount(AT_Decimal, doc="Amount of population to lose.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.addPopulation(-amount.decimal, true);
		if(obj.population < 0.999)
			obj.forceAbandon();
	}
#section all
};

class AbandonPlanet : BonusEffect {
	Document doc("The planet this is triggered on is abandoned.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.forceAbandon();
	}
#section all
};

tidy final class RepeatTrigger : BonusEffect {
	Document doc("Repeat a particular trigger hook multiple times.");
	Argument repeats(AT_Range, doc="Amount of times to repeat the trigger.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("RepeatTrigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(hook is null)
			return;
		uint amt = uint(repeats.decimal);
		if(repeats.isRange)
			amt = randomi(int(repeats.decimal), int(repeats.decimal2));
		for(uint i = 0; i < amt; ++i)
			hook.activate(obj, emp);
	}
#section all
};

tidy final class RandomTrigger : BonusEffect {
	Document doc("Trigger a particular hook only at a particular chance.");
	Argument chance(AT_Range, doc="Chance between 0.0 and 1.0 to trigger the effect.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("RandomTrigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(hook is null)
			return;
		if(randomd() < chance.fromRange())
			hook.activate(obj, emp);
	}
#section all
};

class AddSurfaceArea : BonusEffect {
	Document doc("On the planet, add an extra section of usable space on the surface.");
	Argument biome(AT_PlanetBiome, doc="Biome of the added space.");
	Argument size(AT_Position2D, doc="Size of the added space.");
	Argument void_biome(AT_PlanetBiome, "Space", doc="Biome of the separating space.");
	Argument separate(AT_Boolean, "True", doc="Whether to separate the added space from the rest of the planet by using the void biome.");
	Argument developed(AT_Boolean, "True", doc="Whether the added tiles should be developed.");
	Argument vertical(AT_Boolean, "False", doc="Whether to add it below the existing surface, vertically.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasSurfaceComponent)
			return;
		obj.addSurfaceArea(vec2i(size.fromPosition2D()), biome.integer, void_biome.integer, separate.boolean, developed.boolean, vertical.boolean);
	}
#section all
};

class GiveMemory : BonusEffect {
	Document doc("Give the empire memory over the object.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || emp is null)
			return;
		if(obj.isPlanet)
			cast<Planet>(obj).giveHistoricMemory(emp);
		obj.donatedVision |= emp.mask;
	}
#section all
};

class SetNeedPopulationForLevel : BonusEffect {
	Document doc("Set whether the planet needs minimum population to level up.");
	Argument value(AT_Boolean, doc="Whether the planet needs population to level up.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.hasSurfaceComponent)
			obj.setNeedsPopulationForLevel(value.boolean);
	}
#section all
};


class AddResearchPoints : EmpireTrigger {
	Document doc("Add research points to the empire.", hidden=true);
	Argument points(AT_Range, doc="Amount of research points to add when triggered.");
	Argument modified(AT_Boolean, "True", doc="Whether the amount of points gained should be reduced by the research efficiency rate. That is, the more research an empire has done, the fewer points it will get in the future.");
	Argument penalized(AT_Boolean, "True", doc="Whether the points generated in this way are recorded as total research done for the purposes of research efficiency penalty.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.generatePoints(points.fromRange(), modified.boolean, penalized.boolean);
	}
#section all
};

class ReduceResearchPenalty : EmpireTrigger {
	Document doc("Reduce the recorded total research done for purposes of research efficiency penalty.");
	Argument amount(AT_Range, doc="Amount of points to remove from the total research done.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.reduceResearchPenalty(amount.fromRange());
	}
#section all
};

class AddInfluencePoints : EmpireTrigger {
	Document doc("Add influence points to the empire's stores.", hidden=true);
	Argument amount(AT_Range, doc="Influence points to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.addInfluence(amount.fromRange());
	}
#section all
};

class AddInfluenceStake : EmpireTrigger {
	Document doc("Add permanent influence generation stake.", hidden=true);
	Argument amount(AT_Range, doc="Influence stake to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modInfluenceIncome(amount.fromRange());
	}
#section all
};

class LoseInfluencePoints : EmpireTrigger {
	Document doc("The empire immediately loses all stored influence.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of stored influence to lose.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modInfluence(-floor(double(emp.Influence) * percentage.decimal));
	}
#section all
};

class AddMoney : EmpireTrigger {
	Document doc("Add special funds to the empire.");
	Argument amount(AT_Range, doc="Amount of special funds to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.addBonusBudget(amount.fromRange());
	}
#section all
};

class AddMoneyEstNextBudget : EmpireTrigger {
	Document doc("Add special funds to the empire depending on the estimated next budget.");
	Argument amount(AT_Range, doc="Amount of special funds to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		int estimate = double(emp.EstNextBudget) * amount.fromRange();
		if(estimate > 0)
			emp.addBonusBudget(+estimate);
	}
#section all
};

class AddEnergyIncome : EmpireTrigger {
	Document doc("Increase energy income per second.", hidden=true);
	Argument amount(AT_Decimal, doc="Amount of energy per second to add, before storage penalty.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modEnergyIncome(+amount.decimal);
	}
#section all
};

class AddResearchIncome : EmpireTrigger {
	Document doc("Increase research income per second.", hidden=true);
	Argument amount(AT_Decimal, doc="Amount of research generation per second to add, before generation penalties.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modResearchRate(+amount.decimal);
	}
#section all
};

class GenerateGlobalDefense : EmpireTrigger {
	Document doc("Generate an amount of global defense into the empire, spread across anything it has marked as being defended.", hidden=true);
	Argument amount(AT_Range, doc="Amount of labor's worth of defense to instantly generate.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.generateDefense(amount.fromRange());
	}
#section all
};

class AddGlobalDefenseIncome : EmpireTrigger {
	Document doc("Permanently increase an empire's global defense generation by a rate.", hidden=true);
	Argument amount(AT_Range, doc="Amount of defense per minute to add to the empire's global rate.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.modDefenseRate(amount.fromRange() * DEFENSE_LABOR_PM / 60.0);
	}
#section all
};

class AddStoredFTL : EmpireTrigger {
	Document doc("Add FTL Energy to the empire's storage.");
	Argument amount(AT_Range, doc="Amount of FTL to add.");
	Argument obey_capacity(AT_Boolean, "False", doc="Whether to allow temporarily going above your ftl storage capacity.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.modFTLStored(amount.fromRange(), obey_capacity.boolean);
	}
#section all
};


class AddFTLIncome : EmpireTrigger {
	Document doc("Add permanent FTL income to the empire.");
	Argument amount(AT_Range, doc="Amount of FTL income to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.modFTLIncome(amount.fromRange());
	}
#section all
};

class AddPermanentIncome : EmpireTrigger {
	Document doc("Add permanent money to the empire's income.");
	Argument amount(AT_Range, doc="Amount of extra income to give.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		emp.modTotalBudget(amount.fromRange(), MoT_Misc);
	}
#section all
};

class AddCargoStorage : BonusEffect {
	Document doc("Add an amount of cargo storage to the object. Not all objects support cargo storage.");
	Argument amount(AT_Decimal, doc="Amount of cargo storage to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		if(obj.isShip && !obj.hasCargo)
			cast<Ship>(obj).activateCargo();
		if(obj.hasCargo)
			obj.modCargoStorage(+amount.decimal);
	}
#section all
};

class AddCargo : BonusEffect {
	Document doc("Add an amount of a particular type of cargo to the object.");
	Argument type(AT_Cargo, doc="Type of cargo to add.");
	Argument amount(AT_Decimal, doc="Amount of cargo to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasCargo)
			return;
		obj.addCargo(type.integer, amount.decimal);
	}
#section all
};

class AddStarDPS : BonusEffect {
	Document doc("Add some diminishing dammage over time to the star in the system this is triggered in.");
	Argument amount(AT_Decimal, doc="Initial damage over time to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ region = obj.region;
		if(region is null)
			return;
		region.addStarDPS(amount.decimal);
	}
#section all
};

class DealDamageToStar : BonusEffect {
	Document doc("Deal a set amount of damage to all stars in the system the object is in.");
	Argument amount(AT_Decimal, doc="Damage to deal to all stars.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ region = obj.region;
		if(region is null)
			return;
		region.dealStarDamage(amount.decimal);
	}
#section all
};

class SendMessage : EmpireTrigger {
	Document doc("Sends a message to the empire which activates the anomaly.");
	Argument msg("Message", AT_Locale, doc="Message to send.");
	Argument title(AT_Locale, EMPTY_DEFAULT, doc="Title of the message.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		Player@ pl = emp.player;
		if(pl is null)
			return;
		string head = title.str;
		if(head.length == 0 && obj !is null)
			head = obj.name;
		sendClientMessage(pl, head, msg.str);
	}
#section all
};


class TriggerRandomEvent : EmpireTrigger {
	Document doc("Immediately trigger a random event on the empire. Note that it is still possible for the event not to occur if its conditions cannot be satisfied.");
	Argument type(AT_RandomEvent, doc="Type of random event to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.spawnRandomEvent(type.integer);
	}
#section all
};

class SetPermanentSystemFlag : BonusEffect {
	Document doc("Permanently set a system flag in the system the object this is triggered on is currently in.");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to set. Can be set to any arbitrary name, and the matching system flag will be created.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ reg = obj.region;
		if(reg is null)
			return;
		reg.setSystemFlag(emp, flag.integer, true);
	}
#section all
}

class RestoreShields : BonusEffect {
	Document doc("Restore an amount of shields on the ship.");
	Argument amount(AT_Decimal, "0", doc="Amount of shields to restore.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of shields to restore.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.isShip)
			return;
		Ship@ ship = cast<Ship>(obj);
		ship.restoreShield(amount.decimal + percentage.decimal * ship.MaxShield);
	}
#section all
};

class RevealSecretProject : EmpireTrigger {
	Document doc("Reveal a secret project on this empire's research grid.");
	Argument picked_only(AT_Boolean, "False", doc="Only reveal secret projects that would already be available instead of potentially enabling new ones.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.revealSecretProject(picked_only.boolean);
	}
#section all
};

class AddPlanetIncome : BonusEffect {
	Document doc("Change the planet's income by an amount.");
	Argument amount(AT_Integer, doc="Amount of income to change the planet's income by.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.hasSurfaceComponent)
			obj.modIncome(+amount.integer);
	}
#section all
};

class NameObject : BonusEffect {
	Document doc("Change the object's name.");
	Argument name(AT_Custom, doc="Name to change to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null) {
			obj.name = name.str;
			obj.named = true;
			objectRenamed(ALL_PLAYERS, obj, name.str);
		}
	}
#section all
};

tidy final class TriggerRandomSystem : EmpireTrigger {
	Document doc("Trigger a hook on a random system.");
	Argument hookID(AT_Hook, "bonus_effects::EmpireTrigger");
	Argument min_contestation(AT_Decimal, "0", doc="Minimum contestation to consider the system.");
	Argument fallback_random(AT_Boolean, "False", doc="Whether to fall back to a completely random system if no match was found.");
	Argument has_planets(AT_Boolean, "False", doc="Whether to require the system has any planets from the triggering player.");
	Argument fully_owned(AT_Boolean, "False", doc="Whether to require the system to only contain planets from the triggering player.");
	Argument match_homeworld_assign(AT_Boolean, "False", doc="Whether to only ever pick systems in the same map assign group as the triggering empire's homeworld.");
	Argument reassign(AT_Integer, "-1", doc="If set to not -1, change the map assign group of the system to this.");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerRandomSystem(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		uint cnt = systemCount;
		double total = 0.0;
		SystemDesc@ current;
		uint hwAssign = uint(-1);
		if(match_homeworld_assign.boolean) {
			Object@ hw = emp.Homeworld;
			if(hw is null)
				@hw = emp.HomeObj;
			if(hw !is null) {
				Region@ reg = hw.region;
				if(reg !is null)
					hwAssign = getSystem(reg).assignGroup;
			}
		}
		for(uint i = 0; i < cnt; ++i) {
			auto@ check = getSystem(i);
			if(has_planets.boolean && emp !is null) {
				if(check.object.PlanetsMask & emp.mask == 0)
					continue;
			}
			if(fully_owned.boolean && emp !is null) {
				if(check.object.PlanetsMask & ~emp.mask != 0)
					continue;
			}
			if(match_homeworld_assign.boolean && hwAssign != uint(-1)) {
				uint assign = check.assignGroup;
				if(assign != uint(-1) && assign != hwAssign)
					continue;
				if(assign == uint(-1)) {
					if(check.contestation < min_contestation.decimal)
						continue;
				}
			}
			else {
				if(check.contestation < min_contestation.decimal)
					continue;
			}
			total += 1.0;
			if(randomd() < 1.0 / total)
				@current = check;
		}

		if(current is null && fallback_random.boolean)
			@current = getSystem(randomi(0, cnt-1));

		if(current !is null) {
			hook.activate(current.object, emp);
			if(reassign.integer != -1)
				current.assignGroup = reassign.integer;
		}
	}
#section all
};

tidy final class OnSystem : BonusEffect {
	Document doc("Trigger the effect on the system the object is in, not the object itself.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnSystem(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		Region@ region = cast<Region>(obj);
		if(region is null)
			@region = obj.region;
		if(region is null)
			return;
		hook.activate(region, emp);
	}
#section all
};

tidy final class TriggerEmpHomeworld : BonusEffect {
	Document doc("Trigger the effect on the empire's homeworld.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerHomeworld(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		Object@ hw = emp.Homeworld;
		if(hw is null || !hw.valid)
			@hw = emp.HomeObj;
		if(hw !is null)
			hook.activate(hw, emp);
	}
#section all
};

tidy final class OnEmpHomeworld : BonusEffect {
	Document doc("Trigger the planetary effect on the empire's homeworld.");
	Argument hookID(AT_Hook, "planet_effects::TriggerableGeneric");

	GenericEffect@ hook;

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null) {
			error("OnHomeworld(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		Object@ hw = emp.Homeworld;
		if(hw is null || !hw.valid)
			@hw = emp.HomeObj;
		if(hw !is null)
			hook.enable(hw, null);
	}
#section all
};

class AddInvasionStrength : BonusEffect {
	Document doc("When called in an invasion map, increase the strength of invasions.");
	Argument amount(AT_Decimal, doc="Amount to increase invasion strength by.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		increaseInvasionStrength(amount.decimal);
	}
#section all
};

tidy final class TriggerRandomPlanet : BonusEffect {
	Document doc("Trigger the effect on a random planet.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerRandomPlanet(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		uint cnt = emp.planetCount;
		Planet@ pl = emp.planetList[randomi(0, cnt-1)];
		if(pl is null)
			return;
		hook.activate(pl, emp);
	}
#section all
};

tidy final class OnRandomPlanet : BonusEffect {
	Document doc("Trigger the planetary effect on a random planet.");
	Argument hookID(AT_Hook, "planet_effects::TriggerableGeneric");

	GenericEffect@ hook;

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null) {
			error("OnRandomPlanet(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		uint cnt = emp.planetCount;
		Planet@ pl = emp.planetList[randomi(0, cnt-1)];
		if(pl is null)
			return;
		hook.enable(pl, null);
	}
#section all
};

tidy final class TriggerGeneric : BonusEffect {
	Document doc("Trigger a generic or planet effect once.");
	Argument hookID(AT_Hook, "planet_effects::TriggerableGeneric");

	GenericEffect@ hook;

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null) {
			error("TriggerGeneric(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		hook.enable(obj, null);
	}
#section all
};

class AddRandomResource : BonusEffect {
	Document doc("Add a randomized resource according to a spec.");
	Argument resource(AT_Custom, "distributed", doc="The  resource to add. 'distributed' to randomize.");
	Argument distribute_resource(AT_Boolean, "True", doc="Whether or not the selected resources should be frequency distributed.");

	array<const ResourceType@> resPossib;
	bool distribute = false;

	bool instantiate() override {
		if(resource.str.equals_nocase("distributed"))
			distribute = true;
		else if(!parseResourceSpec(resPossib, resource.str))
			return false;
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.hasResources)
			return;

		const ResourceType@ resource;
		if(resPossib.length > 0) {
			if(resPossib.length == 1)
				@resource = resPossib[0];
			else if(distribute_resource.boolean) {
				double roll = randomd();
				double freq = 0.0;
				for(uint i = 0, cnt = resPossib.length; i < cnt; ++i) {
					freq += resPossib[i].frequency;
					double chance = resPossib[i].frequency / freq;
					if(roll < chance) {
						@resource = resPossib[i];
						roll /= chance;
					}
					else {
						roll = (roll - chance) / (1.0 - chance);
					}
				}
			}
			else
				@resource = resPossib[randomi(0, resPossib.length-1)];
		}
		else if(distribute)
			@resource = getDistributedResource();

		if(resource !is null)
			obj.createResource(resource.id);
	}
#section all
};

class MakeSenateLeader : EmpireTrigger {
	Document doc("Make the empire this is triggered on the senate leader.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			electSenateLeader(emp);
	}
#section all
};

#section server
class GiveVision : SystemGenerateHook {
	Empire@ emp;
	GiveVision(Empire@ emp) {
		@this.emp = emp;
	}

	void call(SystemDesc@ desc) {
		desc.object.grantVision(emp);
	}
};
#section all

class GenerateSystem : EmpireTrigger {
	Document doc("Generate a new system at a random position according to a particular map generation spec.");
	Argument system_type(AT_Custom, doc="Map system type to generate.");
	Argument adjacent_to_empire(AT_Boolean, "False", doc="Spawn the system near a system that the triggering empire is in.");
	Argument vision_to_empire(AT_Boolean, "False", doc="If true, give the empire triggering this effect permanent vision over the system.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		vec3d position;
		bool found = false;
		for(uint tries = 0; tries < 1000; ++tries) {
			const SystemDesc@ offSystem;
			if(!adjacent_to_empire.boolean || emp is null || !emp.valid) {
				@offSystem = getSystem(randomi(0, systemCount-1));
			}
			else {
				double count = 0;
				for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
					auto@ sys = getSystem(i);
					if(sys.object.TradeMask & emp.mask == 0)
						continue;

					count += 1.0;
					if(randomd() < 1.0 / count)
						@offSystem = sys;
				}
			}

			vec2d offset = random2d(3000.0 + offSystem.radius * randomd(1.5, 5.0));
			vec3d offPosition = offSystem.position;
			offPosition.x += offset.x;
			offPosition.y += randomd(-100, 100);
			offPosition.z += offset.y;

			bool overlaps = false;
			for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
				auto@ sys = getSystem(i);
				if(sys.position.distanceToSQ(offPosition) < sqr(sys.radius + 3000.0)) {
					overlaps = true;
					break;
				}
			}

			if(!overlaps) {
				position = offPosition;
				found = true;
				break;
			}
		}

		if(!found)
			return;

		NameGenerator sysNames;
		sysNames.read("data/system_names.txt");
		string name = sysNames.generate();

		SystemGenerateHook@ hook;
		if(vision_to_empire.boolean && emp !is null && emp.valid)
			@hook = GiveVision(emp);

		generateNewSystem(position, hook=hook, radius=250.0, type=system_type.str, name=name);
	}
#section all
};

class PermanentBonusHP : BonusEffect {
	Document doc("Add a permanent percentage bonus health to a ship.");
	Argument amount(AT_Decimal, doc="Percentage of hp to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.isShip)
			return;

		Ship@ ship = cast<Ship>(obj);
		ship.modHPFactor(amount.decimal);
	}
#section all
};

class GrantExperience : BonusEffect {
	Document doc("Grant the flagship extra experience for veterancy levels.");
	Argument amount(AT_Range, "0", doc="Experience to grant.");
	Argument size_factor(AT_Range, "0", doc="Factor of the design size in experience to grant.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || !obj.isShip || !obj.hasLeaderAI)
			return;

		Ship@ ship = cast<Ship>(obj);

		double xp = amount.fromRange();
		xp += ship.blueprint.design.size * size_factor.fromRange();

		if(xp != 0)
			ship.addExperience(xp);
	}
#section all
};

class SubjugateVictory : EmpireTrigger {
	Document doc("The triggered empire wins the game by subjugating everyone else.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		if(emp.Victory == 1)
			return;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other.SubjugatedBy is null && other.major && other.valid && other !is emp)
				forceSubjugate(emp, other);
		}
	}
#section all
};

class GainAttitude : EmpireTrigger {
	Document doc("Gain an attitude on the empire.");
	Argument attitude(AT_Attitude, doc="Attitude to gain.");
	Argument level_up(AT_Integer, "0", doc="Immediately provide level ups for this attitude as well.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.forceAttitude(attitude.integer);
		int levelups = level_up.integer - int(emp.AttitudeStartLevel);
		if(levelups > 0)
			emp.levelAttitude(attitude.integer, levelups);
	}
#section all
};

class DiscardAttitude : EmpireTrigger {
	Document doc("Force an attitude to be discarded from the empire.");
	Argument attitude(AT_Attitude, doc="Attitude to gain.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.forceDiscardAttitude(attitude.integer);
	}
#section all
};

class GainAttitudeProgress : EmpireTrigger {
	Document doc("Gain progress on one of the attitudes the empire has.");
	Argument attitude(AT_Attitude, doc="Attitude to gain progress on.");
	Argument progress(AT_Decimal, "0", doc="Amount of absolute progress to gain.");
	Argument progress_percentage(AT_Decimal, "0", doc="Amount of progress to gain as a percentage of the next level.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.progressAttitude(attitude.integer, progress.decimal, progress_percentage.decimal);
	}
#section all
};

class ResetAttitudeProgress : EmpireTrigger {
	Document doc("Completely reset all attitude progress for a particular attitude.");
	Argument attitude(AT_Attitude, doc="Attitude to reset progress on.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		emp.resetAttitude(attitude.integer);
	}
#section all
};

tidy final class OnDLC : EmpireTrigger {
	Document doc("Only trigger this if a certain DLC is present.");
	Argument dlc(AT_Custom, doc="DLC to check for.");
	Argument hookID(AT_Hook, "bonus_effects::EmpireTrigger");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnDLC(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(hasDLC(dlc.str))
			hook.activate(obj, emp);
	}
#section all
};

class TriggerPlanetUpdate : EmpireTrigger {
	Document doc("Bump planet population-based variables such as pressure cap after global changes.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.bumpPlanetUpdate();
	}
#section all
};

class GrantRandomName : BonusEffect {
	Document doc("Give the object a randomized name.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		string name;
		if(obj.isShip) {
			name = getRandomFlagshipName();
		}
		else if(obj.isPlanet) {
			name = getRandomPlanetName();
		}
		else {
			return;
		}

		obj.name = name;
		obj.named = true;
		objectRenamed(ALL_PLAYERS, obj, name);
	}
#section all
};

class AddGlobalLoyalty : EmpireTrigger {
	Document doc("Permanently add global loyalty to all planets.");
	Argument amount(AT_Integer, doc="How much to add or subtract from the loyalty value.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp !is null)
			emp.GlobalLoyalty += amount.integer;
	}
#section all
};

class GainPlanetResource : BonusEffect {
	Document doc("The object gains a new planetary resource.");
	Argument resource(AT_PlanetResource, doc="Type of resource to give.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.hasResources)
			obj.createResource(resource.integer);
	}
#section all
};

class AddOrbitalHealth : BonusEffect {
	Document doc("Add maximum health to this orbital.");
	Argument amount(AT_Decimal, "0.0", doc="Maximum health to add.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.isOrbital)
			cast<Orbital>(obj).modMaxHealth(amount.decimal);
	}
#section all
};

class RetrofitUpscale : BonusEffect {
	Document doc("Upscales the design of the targeted ship, saves it as a separate design, and retrofits to it.");
	Argument add(AT_Decimal, "0", doc="Extra size to add.");
	Argument multiply(AT_Decimal, "1", doc="Multiplier to size.");
	Argument name(AT_Boolean, "True", doc="Whether to name the station so it keeps the same name.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		const Design@ orig = ship.blueprint.design;
		if(orig is null)
			return;

		int newSize = orig.size;
		newSize *= multiply.decimal;
		newSize += add.decimal;

		DesignDescriptor desc;
		resizeDesign(orig, newSize, desc);

		string name = desc.name;
		uint try = 0;
		while(desc.owner.getDesign(name) !is null) {
			name = desc.name + " ";
			appendRoman(++try, name);
		}
		if(name != desc.name)
			desc.name = name;

		auto@ newDesign = makeDesign(desc);
		desc.owner.addDesign(orig.cls, newDesign);

		ship.retrofit(newDesign);

		if(this.name.boolean && !obj.named) {
			obj.name = orig.name;
			obj.named = true;
			objectRenamed(ALL_PLAYERS, obj, orig.name);
		}
	}
#section all
};

class DestroyAllEnemies : BonusEffect {
	Document doc("Destroy all enemies of the caster in the targeted region.");
	Argument ships(AT_Boolean, "True", doc="Destroy all enemy ships.");
	Argument planets(AT_Boolean, "False", doc="Destroy all enemy planets too.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		if(reg is null)
			return;

		reg.destroyOwnedBy(emp.hostileMask, ships=this.ships.boolean, planets=this.planets.boolean);
	}
#section all
};

class DestroyAllNonMajorEnemies : BonusEffect {
	Document doc("Destroy all non-major units (creep camps) that are enemies of the caster in the targeted region.");
	Argument ships(AT_Boolean, "True", doc="Destroy all enemy ships.");
	Argument planets(AT_Boolean, "False", doc="Destroy all enemy planets too.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(emp is null)
			return;
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		if(reg is null)
			return;

		uint mask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other.major)
				continue;
			if(!emp.isHostile(other))
				continue;
			mask |= other.mask;
		}

		if(mask != 0)
			reg.destroyOwnedBy(mask, ships=this.ships.boolean, planets=this.planets.boolean);
	}
#section all
};

class ReplaceAllBiomesWith : BonusEffect {
	Document doc("Replaces all biomes on a planet with a particular type.");
	Argument biome_type(AT_PlanetBiome, doc="Biome to change everything to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj !is null && obj.hasSurfaceComponent)
			obj.replaceAllBiomesWith(biome_type.integer);
	}
#section all
};

class AddMoonGraphic : BonusEffect {
	Document doc("Add a graphic for a moon to the planet.");
	Argument size(AT_Decimal, doc="Size of the moon graphic.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null)
			pl.addMoon(size.decimal);
	}
#section all
};

tidy final class OnNearbySystems : BonusEffect {
	BonusEffect@ hook;

	Document doc("Apply the hook on systems close to the triggered system.");
	Argument hops(AT_Integer, doc="The maximum amount of hops of distance to consider nearby.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect");
	Argument on_home(AT_Boolean, "False", "Whether to also apply to the given system itself.");
	Argument empty_only(AT_Boolean, "False", doc="Only spawn in systems that don't contain any other empires.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::"));
		if(hook is null)
			return false;
		return BonusEffect::instantiate();
	}

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ region = cast<Region>(obj);
		if(region is null)
			return;
		set_int visited;
		SystemDesc@ sys = getSystem(region);
		check(emp, sys, hops.integer, visited);
	}

	void check(Empire@ emp, SystemDesc@ sys, int hops, set_int& visited) {
		if(visited.contains(sys.index))
			return;

		visited.insert(sys.index);

		if(empty_only.boolean) {
			uint mask = ~0;
			if(emp !is null)
				mask = ~emp.mask;
			if(sys.object.PlanetsMask & mask != 0)
				return;
		}
		hook.activate(sys.object, emp);

		if(hops >= 1) {
			hops -= 1;
			for(uint i= 0, cnt = sys.adjacent.length; i < cnt; ++i) {
				auto@ otherSys = getSystem(sys.adjacent[i]);
				check(emp, otherSys, hops, visited);
			}
			for(uint i= 0, cnt = sys.wormholes.length; i < cnt; ++i) {
				auto@ otherSys = getSystem(sys.wormholes[i]);
				check(emp, otherSys, hops, visited);
			}
		}
	}
#section all
};


class SetSystemAssignGroup : BonusEffect {
	Document doc("Set the assign group of the system this is in.");
	Argument assign(AT_Integer, doc="Assign group to set to.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		Region@ reg = cast<Region>(obj);
		if(reg is null && obj !is null)
			@reg = obj.region;
		if(reg !is null)
			getSystem(reg).assignGroup = assign.integer;
	}
#section all
};

class ModStat : BonusEffect {
	Document doc("Permanently modify a stat of the object this is called on.");
	Argument stat(AT_ObjectStat, doc="Stat to modify. Type anything and a new stat with that name will be created. Adding # in the name indicates the stat is integral, adding & in the name indicates the stat is server-only.");
	Argument mode(AT_ObjectStatMode, doc="The way to modify the stat.");
	Argument value(AT_Decimal, doc="The value to modify the stat by.");
	Argument for_empire(AT_Boolean, "False", doc="If set, the stat is modified only inside the triggering empire's context, instead of for the object globally.");
	Argument on_system(AT_Boolean, "False", doc="If set, instead modify the stat on the system the triggering object is in instead.");

#section server
	const ObjectStatType@ objStat;

	bool instantiate() override {
		if(!BonusEffect::instantiate())
			return false;
		@objStat = getObjectStat(stat.str);
		return true;
	}

	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null || objStat is null)
			return;
		if(on_system.boolean) {
			@obj = obj.region;
			if(obj is null)
				return;
		}

		if(!for_empire.boolean)
			@emp = null;

		objStat.mod(obj, emp, mode.integer, mode.decimal);
	}
#section all
};
