import buildings;
from buildings import IBuildingHook;
import resources;
import util.formatting;
import systems;
import saving;
import influence;
from influence import InfluenceStore;
from statuses import IStatusHook, Status, StatusInstance;
from resources import integerSum, decimalSum;
import orbitals;
from orbitals import IOrbitalEffect;
import attributes;
import hook_globals;
import research;
import empire_effects;
import repeat_hooks;
import planet_types;
#section server
import object_creation;
from components.ObjectManager import getDefenseDesign;
from object_stats import ObjectStatType, getObjectStat;
#section all

//ModSupportBuildSpeed(<Percentage>)
// The consuming planet builds support ships <Percentage> faster.
class ModSupportBuildSpeed : GenericEffect, TriggerableGeneric {
	Document doc("Increase the speed at which support ships are constructed.");
	Argument factor(AT_Decimal, doc="Percentage increase to base build speed. eg. 0.2 for +20%.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(locale::IRON_EFFECT, decimalSum(hooks, 0), locale::MOD_SPEED);
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modSupportBuildSpeed(+int(arguments[0].decimal*100.0));
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modSupportBuildSpeed(-int(arguments[0].decimal*100.0));
	}
#section all
};

//PlayParticles(<Particle Effect Name>, [Scale = 1.0])
// Plays the <Particle Effect> on the specified object, with optional <Scale>
class PlayParticles : GenericEffect, TriggerableGeneric {
	Document doc("Play the specified particle effect around the object when the effect is enabled.");
	Argument particle_effect(AT_Custom, doc="Name of the particle effect to play.");
	Argument scale(AT_Decimal, "1.0", doc="Size of the particle effect relative to the object's size.");

#section server
	void enable(Object& obj, any@ data) const override {
		playParticleSystem(arguments[0].str, vec3d(), quaterniond(), arguments[1].decimal * obj.radius, obj);
	}
#section all
};

class PersistentParticles : GenericEffect {
	Document doc("Add a persistent particle effect to the object while this is active.");
	Argument particle_effect(AT_Custom, doc="Name of the particle effect to play.");
	Argument scale(AT_Decimal, "1.0", doc="Size of the particle effect relative to the object's size.");
	Argument fleet_scale(AT_Boolean, "False", doc="Whether to scale the particle effect to the fleet's scale.");

#section server
	void enable(Object& obj, any@ data) const override {
		int64 effId = 0;
		data.store(effId);
	}

	void tick(Object& obj, any@ data, double time) const override {
		int64 effId = 0;
		data.retrieve(effId);

		if(effId == 0) {
			effId = obj.id << 32 | 0x2 << 24 | randomi(0, 0xffffff);
			data.store(effId);

			double size = scale.decimal;
			if(fleet_scale.boolean && obj.hasLeaderAI)
				size *= obj.getFormationRadius() / obj.radius;
			makePersistentParticles(ALL_PLAYERS, effId, obj, particle_effect.str, size);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int64 effId = 0;
		data.retrieve(effId);

		if(effId != 0) {
			removeGfxEffect(ALL_PLAYERS, effId);

			effId = 0;
			data.store(effId);
		}
	}

	void load(any@ data, SaveFile& file) const override {
		int64 effId = 0;
		data.store(effId);
	}
#section all
};

//GrantAbility(<Ability>)
// Grants the planet access to <Ability>.
class GrantAbility : GenericEffect, TriggerableGeneric {
	Document doc("While this effect is active, the object has access to the specified ability.");
	Argument ability(AT_Ability, doc="The ability type to grant.");

#section server
	void enable(Object& obj, any@ data) const override {
		int id = -1;
		if(data !is null && data.retrieve(id) && id != -1) {
			obj.enableAbility(id);
		}
		else {
			if(!obj.hasAbilities) {
				if(obj.isPlanet)
					cast<Planet>(obj).activateAbilities();
				else if(obj.isShip)
					cast<Ship>(obj).activateAbilities();
				else if(obj.isOrbital)
					cast<Orbital>(obj).activateAbilities();
				else
					return;
			}
			if(data !is null) {
				id = obj.addAbility(ability.integer);
				data.store(id);
			}
			else {
				obj.createAbility(ability.integer);
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		int id = -1;
		if(data.retrieve(id) && id != -1)
			obj.disableAbility(id);
	}

	void save(any@ data, SaveFile& file) const override {
		int id = -1;
		data.retrieve(id);
		file << id;
	}

	void load(any@ data, SaveFile& file) const override {
		int id = -1;
		file >> id;
		data.store(id);
	}
#section all
};

//AddPlanetResource(<Planet Resource>)
// Add a new resource to the planet of type <Planet Resource>.
class AddPlanetResource : GenericEffect, TriggerableGeneric {
	Document doc("The object gains a new planetary resource while the effect is active.");
	Argument resource(AT_PlanetResource, doc="Type of resource to give.");

#section server
	void enable(Object& obj, any@ data) const override {
		int64 id = obj.addResource(arguments[0].integer);
		if(data !is null)
			data.store(id);
	}

	void disable(Object& obj, any@ data) const override {
		int64 id = 0;
		data.retrieve(id);
		obj.removeResource(id);
	}

	void save(any@ data, SaveFile& file) const override {
		int64 id = 0;
		data.retrieve(id);
		file << id;
	}

	void load(any@ data, SaveFile& file) const override {
		int64 id = 0;
		file >> id;
		data.store(id);
	}
#section all
};

//AddStatus(<Status Effect>)
// Add a new status effect.
class AddStatus : GenericEffect {
	Document doc("Give a new status effect to the object.");
	Argument status(AT_Status, doc="Type of status effect to create.");
	Argument duration(AT_Decimal, "-1", doc="How long the status effect should last. If set to -1, the status effect acts as long as this effect hook does.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasStatuses) {
			int64 id = obj.addStatus(arguments[1].decimal, uint(arguments[0].integer));
			if(data !is null)
				data.store(id);
		}
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasStatuses && data !is null) {
			int64 id = 0;
			data.retrieve(id);
			obj.removeStatus(id);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		int64 id = 0;
		data.retrieve(id);
		file << id;
	}

	void load(any@ data, SaveFile& file) const override {
		int64 id = -1;
		if(file >= SV_0013)
			file >> id;
		data.store(id);
	}
#section all
};

class RemoveAllStatus : GenericEffect {
	Document doc("Remove any and all statuses of a praticular type that are on this object at any point.");
	Argument status(AT_Status, doc="Type of status effect to create.");

#section server
	void enable(Object& obj, any@ data) const override {
		check(obj);
	}

	void check(Object& obj) const {
		if(!obj.hasStatuses)
			return;
		obj.removeStatusType(status.integer);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		check(obj);
	}
#section all
};

class AddRegionStatus : GenericEffect, TriggerableGeneric {
	Document doc("Add a status effect to everything in the region this object is in.");
	Argument type(AT_Status, doc="Type of status effect to add.");
	Argument empire_limited(AT_Boolean, "True", doc="Whether the status should be limited to the empire.");

#section server
	void enable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null)
			region.addRegionStatus(empire_limited.boolean ? owner : null, type.integer);
	}

	void disable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null)
			region.removeRegionStatus(empire_limited.boolean ? owner : null, type.integer);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		Region@ region = obj.region;
		if(region !is null && empire_limited.boolean) {
			region.removeRegionStatus(prevOwner, type.integer);
			region.addRegionStatus(newOwner, type.integer);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		Empire@ owner = obj.owner;
		if(fromRegion !is null)
			fromRegion.removeRegionStatus(empire_limited.boolean ? owner : null, type.integer);
		if(toRegion !is null)
			toRegion.addRegionStatus(empire_limited.boolean ? owner : null, type.integer);
	}
#section all
};

class AddRegionStatusEnemies : GenericEffect, TriggerableGeneric {
	Document doc("Add a status effect to all enemy objects in the region this object is in.");
	Argument type(AT_Status, doc="Type of status effect to add.");

#section server
	void enable(Object& obj, any@ data) const {
		int mask = 0;
		data.store(mask);
	}

	void disable(Object& obj, any@ data) const {
		int mask = 0;
		data.retrieve(mask);

		Region@ region = obj.region;
		if(region !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other.major && mask & other.mask != 0)
					region.removeRegionStatus(other, type.integer);
			}
		}

		mask = 0;
		data.store(mask);
	}

	void tick(Object& obj, any@ data) const {
		int curMask = 0;
		data.retrieve(curMask);

		int newMask = obj.owner.hostileMask;

		if(newMask != curMask) {
			Region@ region = obj.region;
			if(region !is null) {
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					Empire@ other = getEmpire(i);
					if(!other.major)
						continue;

					if(curMask & other.mask != 0 && newMask & other.mask == 0)
						region.removeRegionStatus(other, type.integer);
					else if(curMask & other.mask == 0 && newMask & other.mask != 0)
						region.addRegionStatus(other, type.integer);
				}
			}

			curMask = newMask;
			data.store(curMask);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		int curMask = 0;
		data.retrieve(curMask);

		if(fromRegion !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other.major && curMask & other.mask != 0)
					fromRegion.removeRegionStatus(other, type.integer);
			}
		}
		if(toRegion !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other.major && curMask & other.mask != 0)
					toRegion.addRegionStatus(other, type.integer);
			}
		}
	}

	void save(any@ data, SaveFile& file) const override {
		int mask = 0;
		data.retrieve(mask);
		file << mask;
	}

	void load(any@ data, SaveFile& file) const override {
		int mask = 0;
		file >> mask;
		data.store(mask);
	}
#section all
};

//FreeFTLSystem()
// Grants free ftl leaving the system.
class FreeFTLSystem : GenericEffect, TriggerableGeneric {
	Document doc("Objects FTLing out of the system this effect is active in, that are owned by this effect object's owner, can FTL for free.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.FreeFTLMask |= owner.mask;
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ region = obj.region;
		if(region !is null && prevOwner !is null && prevOwner.valid)
			region.FreeFTLMask &= ~prevOwner.mask;
		if(region !is null && newOwner !is null && newOwner.valid)
			region.FreeFTLMask |= newOwner.mask;
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return;
		if(prevRegion !is null)
			prevRegion.FreeFTLMask &= ~owner.mask;
		if(newRegion !is null)
			newRegion.FreeFTLMask |= owner.mask;
	}

	void disable(Object& obj, any@ data) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.FreeFTLMask &= ~owner.mask;
	}
#section all
};

//GiveNeighbourVision()
// Gives the empire vision over neighbouring systems.
class GiveNeighbourVision : GenericEffect, TriggerableGeneric {
	Document doc("Gives full vision over systems neighbouring the one this effect is active in.");

#section server
	void grant(Empire@ emp, Region@ reg) {
		SystemDesc@ system = getSystem(reg);
		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i)
			getSystem(system.adjacent[i]).object.grantVision(emp);
	}

	void revoke(Empire@ emp, Region@ reg) {
		SystemDesc@ system = getSystem(reg);
		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i)
			getSystem(system.adjacent[i]).object.revokeVision(emp);
	}

	void enable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		if(reg !is null)
			grant(obj.owner, reg);
	}

	void disable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		if(reg !is null)
			revoke(obj.owner, reg);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ reg = obj.region;
		if(reg !is null) {
			if(prevOwner !is null)
				revoke(prevOwner, reg);
			if(newOwner !is null)
				grant(newOwner, reg);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		Empire@ owner = obj.owner;
		if(owner !is null) {
			if(prevRegion !is null)
				revoke(owner, prevRegion);
			if(newRegion !is null)
				grant(owner, newRegion);
		}
	}
#section all
};

//ModNeighbourLoyalty(<Amount>)
// Give <Amount> extra loyalty to all neighbouring planets.
class ModNeighbourLoyalty : GenericEffect, TriggerableGeneric {
	Document doc("Modifies the loyalty of all owned planets in this effect's system or adjacent to it.");
	Argument amount(AT_Integer, doc="How much to add or subtract from the loyalty value.");

#section server
	void enable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		Empire@ owner = obj.owner;
		if(reg !is null)
			reg.modNeighbourLoyalty(owner, +arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		Empire@ owner = obj.owner;
		if(reg !is null)
			reg.modNeighbourLoyalty(owner, -arguments[0].integer);
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		Empire@ owner = obj.owner;
		if(prevRegion !is null)
			prevRegion.modNeighbourLoyalty(owner, -arguments[0].integer);
		if(newRegion !is null)
			newRegion.modNeighbourLoyalty(owner, +arguments[0].integer);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ reg = obj.region;
		if(reg !is null) {
			reg.modNeighbourLoyalty(prevOwner, -arguments[0].integer);
			reg.modNeighbourLoyalty(newOwner, +arguments[0].integer);
		}
	}
#section all
};

//ModLocalLoyalty(<Amount>)
// Give <Amount> extra loyalty to all planets in the same region.
class ModLocalLoyalty : GenericEffect, TriggerableGeneric {
	Document doc("Modifies the loyalty of all owned planets in this effect's system.");
	Argument amount(AT_Integer, doc="How much to add or subtract from the loyalty value.");

#section server
	void enable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		Empire@ owner = obj.owner;
		if(reg !is null)
			reg.modLocalLoyalty(owner, +arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		Empire@ owner = obj.owner;
		if(reg !is null)
			reg.modLocalLoyalty(owner, -arguments[0].integer);
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		Empire@ owner = obj.owner;
		if(prevRegion !is null)
			prevRegion.modLocalLoyalty(owner, -arguments[0].integer);
		if(newRegion !is null)
			newRegion.modLocalLoyalty(owner, +arguments[0].integer);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ reg = obj.region;
		if(reg !is null) {
			reg.modLocalLoyalty(prevOwner, -arguments[0].integer);
			reg.modLocalLoyalty(newOwner, +arguments[0].integer);
		}
	}
#section all
};

//RecordBonusDPS(<Amount>)
// Record the object as having <Amount> bonus DPS;
class RecordBonusDPS : GenericEffect, TriggerableGeneric {
	Document doc("Record the object as having bonus DPS. Changes the object's strength calculation.");
	Argument amount(AT_Decimal, doc="Amount of 'bonus' DPS to add to the object.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modBonusDPS(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modBonusDPS(-arguments[0].decimal);
	}
#section all
};

//AddEnergyIncome(<Amount>)
// Adds <Amount> Energy income per second.
class AddEnergyIncomeStarTemperature : GenericEffect, TriggerableGeneric {
	Document doc("Increase the energy income per second, based on the temperature of the star.");
	Argument min_amount(AT_Decimal, doc="Minimum amount of energy per second to add, for a low temperature star.");
	Argument max_amount(AT_Decimal, doc="Maximum amount of energy per second to add, for a high temperature star.");
	Argument sqrt_scale(AT_Boolean, "True", doc="Whether to scale with the square root, biasing towards lower temperatures.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void disable(Object& obj, any@ data) const override {
		double amount = 0;
		data.retrieve(amount);

		obj.owner.modEnergyIncome(-amount);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double amount = 0;
		data.retrieve(amount);

		double newAmount = 0;
		Region@ reg = obj.region;
		if(reg !is null) {
			double temp = reg.starTemperature;
			double fact = 1.0;
			if(temp > 0)
				fact = clamp((temp - 2000)/26000, 0.0, 1.0);
			if(sqrt_scale.boolean)
				fact = sqrt(fact);
			newAmount = min_amount.decimal + (max_amount.decimal - min_amount.decimal) * fact;
		}

		if(newAmount != amount) {
			obj.owner.modEnergyIncome(newAmount-amount);
			data.store(newAmount);
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		double amount = 0;
		data.retrieve(amount);

		if(prevOwner !is null && prevOwner.valid)
			prevOwner.modEnergyIncome(-amount);
		if(newOwner !is null && newOwner.valid)
			newOwner.modEnergyIncome(+amount);
	}


	void save(any@ data, SaveFile& file) const override {
		double amount = 0.0;
		data.retrieve(amount);
		file << amount;
	}

	void load(any@ data, SaveFile& file) const override {
		double amount = 0.0;
		file >> amount;
		data.store(amount);
	}
#section all
};

//ProtectSystem()
// Protect the system from losing loyalty.
class ProtectSystem : GenericEffect {
	Document doc("Protect owned planets in the system from losing loyalty in any way.");
	Argument timer(AT_Decimal, "0", doc="Delay timer before the effect starts working after being enabled.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return locale::PSIONIC_REAGENTS_EFFECT;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.region !is null)
			obj.region.ProtectedMask &= ~obj.owner.mask;
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double timer = 0.0;
		data.retrieve(timer);

		if(timer >= arguments[0].decimal) {
			if(obj.region !is null)
				obj.region.ProtectedMask |= obj.owner.mask;
		}
		else {
			timer += tick;
			data.store(timer);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(obj.region !is null) {
			double timer = 0.0;
			data.retrieve(timer);

			if(timer >= arguments[0].decimal) {
				obj.region.ProtectedMask &= ~prevOwner.mask;
				obj.region.ProtectedMask |= newOwner.mask;
			}
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const override {
		double timer = 0.0;
		data.retrieve(timer);

		if(timer >= arguments[0].decimal) {
			if(fromRegion !is null)
				fromRegion.ProtectedMask &= ~obj.owner.mask;
			if(toRegion !is null)
				toRegion.ProtectedMask |= obj.owner.mask;
		}
	}
#section all
};

//BlockSystemFTL(<Block Owner> = False, <Block Friendly> = False, <Timer> = 0)
// Prevent any FTL from being activat
class BlockSystemFTL : GenericEffect {
	Document doc("Block FTL travel from hostile empires in the system this effect is active in.");
	Argument block_owner(AT_Boolean, "False", doc="Whether to also block the owner of the effect from using FTL.");
	Argument block_friendly(AT_Boolean, "False", doc="Whether to also block empires that are not at war with the effect's owner from using FTL.");
	Argument timer(AT_Decimal, "0", doc="Delay timer before the effect starts working after being enabled.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.region !is null)
			obj.region.BlockFTLMask = 0;
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double timer = 0.0;
		data.retrieve(timer);

		if(timer >= arguments[2].decimal) {
			if(obj.region !is null) {
				uint mask = ~0;
				if(!arguments[0].boolean && obj.owner !is null)
					mask &= ~obj.owner.mask;
				if(!arguments[1].boolean && obj.owner !is null)
					mask &= obj.owner.hostileMask;
				obj.region.BlockFTLMask |= mask;
			}
		}
		else {
			timer += tick;
			data.store(timer);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(obj.region !is null)
			obj.region.BlockFTLMask = 0;
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const override {
		if(fromRegion !is null)
			fromRegion.BlockFTLMask = 0;
	}
#section all
};

//ProtectOtherPlanets()
// Protect other planets in the system from losing loyalty.
class ProtectOtherPlanets : GenericEffect {
	Document doc("Planets in the system other than the planet this effect is active on are protected from losing loyalty.");

#section server
	void enable(Object& obj, any@ data) const override {
		obj.setProtectionDisabled(true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.region !is null)
			obj.region.ProtectedMask &= ~obj.owner.mask;
	}

	void tick(Object& obj, any@ data, double tick) const override {
		if(obj.region !is null)
			obj.region.ProtectedMask |= obj.owner.mask;
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(obj.region !is null) {
			obj.region.ProtectedMask &= ~prevOwner.mask;
			obj.region.ProtectedMask |= newOwner.mask;
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const override {
		if(fromRegion !is null)
			fromRegion.ProtectedMask &= ~obj.owner.mask;
		if(toRegion !is null)
			toRegion.ProtectedMask |= obj.owner.mask;
	}
#section all
};

//ModResourceEfficiencyBonus(<Percentage>)
// Improve the resource efficiency bonus of native resources by <Percentage>.
class ModResourceEfficiencyBonus : GenericEffect, TriggerableGeneric {
	Document doc("Modify the resource efficiency bonus for native resources. This bonus changes how much pressure they give wherever they are consumed.");
	Argument amount(AT_Decimal, doc="How much to add to the efficiency bonus. eg. 0.2 adds 20% extra base pressure to the resource.");

	bool get_hasEffect() const override {
		return true;
	}

	const IResourceHook@ get_displayHook() const override {
		return null;
	}

	const IResourceHook@ get_carriedHook() const override {
		return this;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(locale::EFFECT_EFFICIENCY, arguments[0].decimal);
	}

#section server
	void enable(Object& obj, any@ data) const override {
		obj.modResourceEfficiencyBonus(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		obj.modResourceEfficiencyBonus(-arguments[0].decimal);
	}
#section all
};

//AddTurret(<Effector>, <Argument> = <Value>, ...)
// Add a turret to the object.
tidy final class AddTurret : GenericEffect {
	Document doc("Add a turret to the object. Arguments are based on effector values and need to be named and set manually.");

	Effector@ effector;
	EffectorDef@ def;
	dictionary values;
	double range = 0.0;

	bool parse(const string& name, array<string>& args) {
		if(args.length == 0) {
			error("AddTurret expects at least 1 argument.");
			return false;
		}

		@def = getEffectorDef(args[0]);
		if(def is null) {
			error("AddTurret: could not find effector "+args[0]);
			return false;
		}

#section server
		@effector = Effector(def);
#section all

		for(uint i = 1, cnt = args.length; i < cnt; ++i) {
			int pos = args[i].findFirst("=");
			if(pos == -1) {
				error("Invalid effector argument: "+escape(args[i]));
				return false;
			}

			string name = args[i].substr(0, pos).trimmed();
			double value = toDouble(args[i].substr(pos+1));

#section server
			int index = def.getArgumentIndex(name);
			if(index == -1) {
				error("Could not find effector argument: "+escape(args[i]));
				return false;
			}

			effector[index] = value;
#section client
			if(name.equals_nocase("Range"))
				range = value;
#section all
		}

#section server
		effector.turretAngle = random3d();
		effector.relativePosition = random3d(0.5);
		effector.evaluate();
#section all
		return true;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		Turret@ tr = Turret(effector);
		data.store(@tr);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Turret@ tr;
		data.retrieve(@tr);

		if(tr !is null) {
			double eff = 1.0;
			if(obj.isOrbital) {
				Orbital@ orb = cast<Orbital>(obj);
				eff = orb.efficiency;
			}
			tr.update(obj, time, eff);
			if(tr.flags & TF_Firing != 0)
				obj.engaged = true;
		}
	}

	void disable(Object& obj, any@ data) const override {
		Turret@ tr = null;
		data.store(@tr);
	}

	void save(any@ data, SaveFile& file) const override {
		Turret@ tr;
		data.retrieve(@tr);

		if(tr !is null) {
			file << true;
			tr.save(file);
		}
		else {
			file << false;
		}
	}

	void load(any@ data, SaveFile& file) const override {
		Turret@ tr;
		bool has = false;
		file >> has;
		if(has)
			@tr = Turret(file);

		data.store(@tr);
	}
#section all
};

//GlobalTradeNode()
// The system the object is in can be traded to from any other GlobalTradeNode.
class GlobalTradeNode : GenericEffect, TriggerableGeneric {
	Document doc("The system the effect is active in can be traded to from any other GlobalTradeNode by the effect owner.");

	void enable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid)
			region.GateMask |= obj.owner.mask;
	}

	void disable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid)
			region.GateMask &= ~obj.owner.mask;
	}

	void tick(Object& obj, any@ data, double time) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid)
			region.GateMask |= obj.owner.mask;
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		Region@ region = obj.region;
		if(region !is null) {
			if(prevOwner !is null && prevOwner.valid)
				region.GateMask &= ~prevOwner.mask;
			if(newOwner !is null && newOwner.valid)
				region.GateMask |= newOwner.mask;
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			if(fromRegion !is null)
				fromRegion.GateMask &= ~obj.owner.mask;
			if(toRegion !is null)
				toRegion.GateMask |= obj.owner.mask;
		}
	}
};

//GiveTrade()
// The system the object is in can be traded through by its owner.
class GiveTrade : GenericEffect, TriggerableGeneric {
	Document doc("The system this effect is active in can be traded through as if it had planets belonging to the effect's owner.");

#section server
	void enable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid)
			region.grantTrade(owner);
	}

	void disable(Object& obj, any@ data) const {
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid)
			region.revokeTrade(owner);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		Region@ region = obj.region;
		if(region !is null) {
			if(prevOwner !is null && prevOwner.valid)
				region.revokeTrade(prevOwner);
			if(newOwner !is null && newOwner.valid)
				region.grantTrade(newOwner);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			if(fromRegion !is null)
				fromRegion.revokeTrade(owner);
			if(toRegion !is null)
				toRegion.grantTrade(owner);
		}
	}
#section all
};

//PeriodicNearbyLeverage(<Timer>, <Cards>)
// Generate leverage periodically on nearby empires.
class PeriodicNearbyLeverage : GenericEffect {
	Document doc("Grant leverage to the effect's owner every interval. The leverage is against random empires in or adjacent to the system the effect is active in.");
	Argument timer(AT_Decimal, "60", doc="Interval between leverage generation.");
	Argument quality_factor(AT_Decimal, "4.0", doc="Quality factor of leverage to give. An abstract number that determines card quality and uses.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double timer = 0.0;
		data.retrieve(timer);

		timer += tick;
		if(timer >= arguments[0].decimal) {
			//Find a nearby empire that isn't us
			Empire@ us = obj.owner;
			Region@ reg = obj.region;
			if(reg !is null) {
				array<Empire@> choice;
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					auto@ other = getEmpire(i);
					if(!other.major || other is us)
						continue;
					if(reg.TradeMask & other.mask != 0)
						choice.insertLast(other);
				}
				auto@ system = getSystem(reg);
				if(system !is null) {
					for(uint n = 0, ncnt = system.adjacent.length; n < ncnt; ++n) {
						auto@ adj = getSystem(system.adjacent[n]).object;
						for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
							auto@ other = getEmpire(i);
							if(!other.major || other is us)
								continue;
							if(adj.TradeMask & other.mask != 0)
								choice.insertLast(other);
						}
					}
				}

				if(choice.length != 0)
					us.gainRandomLeverage(choice[randomi(0, choice.length-1)], arguments[1].decimal);
			}

			timer -= arguments[0].decimal;
		}

		data.store(timer);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}
#section all
};

//PeriodicNearbyIntelligence(<Timer>, <Cards>)
// Generate leverage periodically on nearby empires.
class PeriodicNearbyIntelligence : GenericEffect {
	Document doc("Grant intelligence cards to the effect's owner every interval. The intelligence is against random empires in or adjacent to the system the effect is active in.");
	Argument timer(AT_Decimal, "60", doc="Interval between intelligence generation.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double timer = 0.0;
		data.retrieve(timer);

		timer += tick;
		if(timer >= arguments[0].decimal) {
			//Find a nearby empire that isn't us
			Empire@ us = obj.owner;
			Region@ reg = obj.region;
			if(reg !is null) {
				array<Empire@> choice;
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					auto@ other = getEmpire(i);
					if(!other.major || other is us || !other.valid)
						continue;
					if(reg.TradeMask & other.mask != 0)
						choice.insertLast(other);
				}
				auto@ system = getSystem(reg);
				if(system !is null) {
					for(uint n = 0, ncnt = system.adjacent.length; n < ncnt; ++n) {
						auto@ adj = getSystem(system.adjacent[n]).object;
						for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
							auto@ other = getEmpire(i);
							if(!other.major || other is us || !other.valid)
								continue;
							if(adj.TradeMask & other.mask != 0)
								choice.insertLast(other);
						}
					}
				}

				if(choice.length != 0) {
					uint index = randomi(0, choice.length - 1);
					for(uint i = 0, cnt = choice.length; i < cnt; ++i) {
						Empire@ emp = choice[index];
						if(us.gainIntelligence(emp))
							break;

						index = (index + 1) % choice.length;
					}
				}
			}

			timer -= arguments[0].decimal;
		}

		data.store(timer);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}
#section all
};

//AddFleetCommand(<Supply>)
// Gain <Supply> in fleet command.
class AddFleetCommand : GenericEffect, TriggerableGeneric {
	Document doc("Add extra support command to the object.");
	Argument amount(AT_Integer, doc="Amount of support command to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isOrbital && !obj.hasLeaderAI) {
			cast<Orbital>(obj).activateLeaderAI();
			obj.leaderInit();
		}
		if(obj.hasLeaderAI)
			obj.modSupplyCapacity(+arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modSupplyCapacity(-arguments[0].integer);
	}
#section all
};

//AddLaborIncome(<Amount>)
// Gain <Amount> labor income per minute.
class AddLaborIncome : GenericEffect, TriggerableGeneric {
	Document doc("Add extra labor income per minute.");
	Argument amount(AT_Decimal, "Amount of labor per minute to add.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatMagEffect(locale::RESOURCE_LABOR, decimalSum(hooks, 0));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborIncome(+arguments[0].decimal/60.0);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborIncome(-arguments[0].decimal/60.0);
	}
#section all
};

//AddLaborIncomePerImport(<Amount>)
// Gain <Amount> labor income per minute per imported resource.
class AddLaborIncomePerImport : GenericEffect {
	Document doc("Add labor income per minute for every imported resource.");
	Argument amount(AT_Decimal, doc="Amount of labor per minute to add for each resource that is being imported.");

#section server
	double getAmount(Object& obj) const {
		return arguments[0].decimal * double(obj.usableResourceCount) / 60.0;
	}

	void enable(Object& obj, any@ data) const override {
		double amt = getAmount(obj);
		data.store(amt);
		obj.modLaborIncome(amt);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double amt = getAmount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modLaborIncome(amt - prev);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modLaborIncome(-amt);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

//AddLaborFactor(<Amount>)
// Gain <Amount> labor income per minute.
class AddLaborFactor : GenericEffect, TriggerableGeneric {
	Document doc("Increase the base labor generation rate by a percentage.");
	Argument amount(AT_Decimal, doc="Percentage of base labor generation to add. eg. 0.2 means 20% extra labor generation.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(locale::RESOURCE_LABOR, decimalSum(hooks, 0));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborFactor(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborFactor(-arguments[0].decimal);
	}
#section all
};

//AddLaborFactorPerImport(<Amount>)
// Gain <Amount> labor income per minute per imported resource.
class AddLaborFactorPerImport : GenericEffect {
	Document doc("Increase the base labor generation rate by a percentage for every imported resource.");
	Argument amount(AT_Decimal, doc="Percentage of base labor generation to add per imported resource.");

#section server
	double getAmount(Object& obj) const {
		return arguments[0].decimal * double(obj.usableResourceCount);
	}

	void enable(Object& obj, any@ data) const override {
		double amt = getAmount(obj);
		data.store(amt);
		obj.modLaborFactor(amt);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double amt = getAmount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modLaborFactor(amt - prev);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modLaborFactor(-amt);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

//ModRegionTargetCostMod(<Amount>)
// The region the object is in gets a target cost mod of <Amount>.
class ModRegionTargetCostMod : GenericEffect, TriggerableGeneric {
	Document doc("Change the region target cost modifier for the system this effect is active in. Changes the cost of playing influence cards on targets in the system.");
	Argument amount(AT_Integer, doc="Amount of influence points to change the costs by.");

#section server
	void enable(Object& obj, any@ data) const override {
		Region@ region = obj.region;
		if(region !is null)
			region.modTargetCostMod(arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		Region@ region = obj.region;
		if(region !is null)
			region.modTargetCostMod(-arguments[0].integer);
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		if(prevRegion !is null)
			prevRegion.modTargetCostMod(-arguments[0].integer);
		if(newRegion !is null)
			newRegion.modTargetCostMod(arguments[0].integer);
	}
#section all
};

//ModLocalLoyaltyPerImport(<Amount>)
// Give <Amount> extra loyalty to all planets in the same region per imported resource.
class ModLocalLoyaltyPerImport : GenericEffect {
	Document doc("Add extra loyalty to each owned planet in the system this effect is active in for every resource imported to this effect's object.");
	Argument amount(AT_Integer, doc="Amount of loyalty to add to owned nearby planets for each imported resource.");

#section server
	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		int amt = 0;
		data.retrieve(amt);

		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			if(prevRegion !is null)
				prevRegion.modLocalLoyalty(owner, -amt);
			if(newRegion !is null)
				newRegion.modLocalLoyalty(owner, +amt);
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		int amt = 0;
		data.retrieve(amt);

		Region@ region = obj.region;
		if(region !is null) {
			if(prevOwner !is null && prevOwner.valid)
				region.modLocalLoyalty(prevOwner, -amt);
			if(newOwner !is null && newOwner.valid)
				region.modLocalLoyalty(newOwner, +amt);
		}
	}

	int getAmount(Object& obj) const {
		return arguments[0].integer * int(obj.usableResourceCount);
	}

	void enable(Object& obj, any@ data) const override {
		int amt = getAmount(obj);
		data.store(amt);

		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.modLocalLoyalty(owner, amt);
	}

	void tick(Object& obj, any@ data, double time) const override {
		int amt = getAmount(obj);
		int prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			Region@ region = obj.region;
			Empire@ owner = obj.owner;
			if(region !is null && owner !is null && owner.valid)
				region.modLocalLoyalty(owner, amt - prev);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int amt = 0;
		data.retrieve(amt);
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.modLocalLoyalty(owner, -amt);
	}

	void save(any@ data, SaveFile& file) const override {
		int amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		int amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

//AllowLaborImport()
// Allow this object to import labor from other labor-generating objects.
class AllowLaborImport : GenericEffect, TriggerableGeneric {
	Document doc("Allow the object this effect is active in to import labor from other objects with labor.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.canImportLabor = true;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.canImportLabor = false;
	}
#section all
};

//ForbidLaborExport()
// Do not allow this object to export labor to other objects.
class ForbidLaborExport : GenericEffect, TriggerableGeneric {
	Document doc("Forbid the object this effect is active in from exporting labor to other objects.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.canExportLabor = false;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.canExportLabor = true;
	}
#section all
};

class DisableResourceImport : GenericEffect, TriggerableGeneric {
	Document doc("Forbid the object from importing resources.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasResources)
			obj.setImportEnabled(false);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasResources)
			obj.setImportEnabled(true);
	}
#section all
};

class DisableResourceExport : GenericEffect, TriggerableGeneric {
	Document doc("Forbid the object from exporting resources.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasResources)
			obj.setExportEnabled(false);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasResources)
			obj.setExportEnabled(true);
	}
#section all
};

//FriendlyPlanetMoney(<To Self> = 0, <To Other> = 0, <Count Self> = False)
// For each friendly planet in the system, give <To Self> money to the owner of the effect
// and <To Other> money to the owner of the planet.
class FriendlyPlanetMoney : GenericEffect {
	Document doc("Generate extra money income for each planet owned by a friendly empire in the system.");
	Argument to_self(AT_Integer, "0", doc="Amount of money to give to this effect's owner per friendly planet.");
	Argument to_other(AT_Integer, "0", doc="Amount of money to give to the owners of the friendly planets.");
	Argument count_self(AT_Boolean, "False", doc="Whether to count planets owned by the effect's owner as well as friendly empires.");

	bool getData(Orbital& obj, string& txt, bool enabled) const override {
		if(!enabled)
			return true;
		int money = 0;
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(!other.major)
					continue;
				if(!arguments[2].boolean && other is owner)
					continue;
				int planets = 0;
				if(!other.isHostile(owner))
					planets = region.getPlanetCount(other);
				money += planets * arguments[0].integer;
			}
		}
		txt = format("$1: [color=#d1cb6a]$2[/color]", locale::TRADE, formatMoney(money));
		return true;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		array<int> amounts(getEmpireCount(), 0);
		data.store(@amounts);
	}

	void tick(Object& obj, any@ data, double time) const override {
		array<int>@ amounts;
		data.retrieve(@amounts);

		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(region !is null && owner !is null && owner.valid) {
			int selfAmount = 0;
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(!other.major)
					continue;
				if(!arguments[2].boolean && other is owner)
					continue;

				int planets = 0;
				if(!other.isHostile(owner))
					planets = region.getPlanetCount(other);

				int prevAmount = amounts[other.index];
				int newAmount = planets * arguments[1].integer;
				if(newAmount != prevAmount) {
					other.modTotalBudget(newAmount - prevAmount, MoT_Trade);
					amounts[other.index] = newAmount;
				}

				selfAmount += planets * arguments[0].integer;
			}

			int prevAmount = amounts[owner.index];
			if(selfAmount != prevAmount) {
				owner.modTotalBudget(selfAmount - prevAmount, MoT_Trade);
				amounts[owner.index] = selfAmount;
			}
		}
	}

	void clear(Object& obj, any@ data) const {
		array<int>@ amounts;
		data.retrieve(@amounts);

		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(!other.major)
					continue;

				int amt = amounts[other.index];
				if(amt != 0) {
					other.modTotalBudget(-amt, MoT_Trade);
					amounts[other.index] = 0;
				}
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		clear(obj, data);

		array<int>@ amounts = null;
		data.store(@amounts);
	}

	void regionChange(Object& obj, any@ data, Region@ prevRegion, Region@ newRegion) const override {
		clear(obj, data);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		clear(obj, data);
	}

	void save(any@ data, SaveFile& file) const override {
		array<int>@ amounts;
		data.retrieve(@amounts);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
			file << amounts[i];
	}

	void load(any@ data, SaveFile& file) const override {
		array<int> amounts(getEmpireCount(), 0);
		data.store(@amounts);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
			file >> amounts[i];
	}
#section all
};

//AddFleetEffectiveness(<Percentage>)
// Adds <Percentage> effectiveness to the fleet.
class AddFleetEffectiveness : GenericEffect, TriggerableGeneric {
	Document doc("The fleet this effect is active on gains an increased effectiveness percentage.");
	Argument amount(AT_Decimal, doc="Percentage of effectiveness to add. eg. 0.15 for +15% effectiveness.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modFleetEffectiveness(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modFleetEffectiveness(-arguments[0].decimal);
	}
#section all
};

class AddShipEffectiveness : GenericEffect {
	Document doc("Add a percentage dps effectiveness just to this individual ship, not its fleet.");
	Argument amount(AT_Decimal, doc="Percentage of effectiveness to add. eg. 0.15 for +15% effectiveness.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).addBonusEffectiveness(amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).addBonusEffectiveness(-amount.decimal);
	}
#section all
};

//AddLaborEmpireAttribute(<Resource>, <Attribute>)
// Add labor production from an empire attribute.
class AddLaborEmpireAttribute : GenericEffect {
	Document doc("Add labor based on the value of an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to add as labor, can be set to any arbitrary name to be created as a new attribute with starting value 0.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		Empire@ owner = obj.owner;
		double newValue = 0;
		if(owner !is null)
			newValue = owner.getAttribute(arguments[0].integer);
		if(newValue != value && obj.hasConstruction) {
			obj.modLaborIncome((newValue - value)/60.0);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);
		if(obj.hasConstruction)
			obj.modLaborIncome(-value/60.0);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class AddFleetCommandEmpireAttribute : GenericEffect {
	Document doc("Add fleet command to the object based on an empire attribute value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to add as fleet command, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplication factor to the attribute value.");

#section server
	void enable(Object& obj, any@ data) const override {
		int value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		int value = 0;
		data.retrieve(value);

		Empire@ owner = obj.owner;
		int newValue = 0;
		if(owner !is null)
			newValue = owner.getAttribute(attribute.integer) * multiplier.decimal;
		if(newValue != value && obj.hasLeaderAI) {
			obj.modSupplyCapacity(newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int value = 0;
		data.retrieve(value);
		if(obj.hasLeaderAI)
			obj.modSupplyCapacity(-value);
	}

	void save(any@ data, SaveFile& file) const override {
		int amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		int amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

//AddResourceToAllOrbitals(<Planet Resource>)
// Add a particular resource natively to all orbitals.
class AddResourceToAllOrbitals : GenericEffect {
	Document doc("Add a resource to every owned orbital.");
	Argument resource(AT_PlanetResource, doc="Which resource to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		int id = 0;
		if(data !is null)
			data.store(id);
	}

	void tick(Object& obj, any@ data, double time) const override {
		int id = 0;
		data.retrieve(id);

		Orbital@ orb = obj.owner.getOrbitalAfter(id);
		if(orb !is null) {
			if(!orb.isStandalone)
				orb.createResource(arguments[0].integer);
			id = orb.id;
			data.store(id);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		int id = 0;
		data.retrieve(id);
		file << id;
	}

	void load(any@ data, SaveFile& file) const override {
		int id = 0;
		file >> id;
		data.store(id);
	}
#section all
};

//MorphAllResourcesInto(<Planet Resource>)
// Morphs all resources into a particular type.
class MorphAllResourcesInto : GenericEffect, TriggerableGeneric {
	Document doc("Morph all native resources present on the planet to a different type.");
	Argument resource(AT_PlanetResource, doc="What type of resource to morph them into.");

#section server
	void enable(Object& obj, any@ data) const override {
		uint cnt = obj.nativeResourceCount;
		for(uint i = 0; i < cnt; ++i) {
			int type = obj.nativeResourceType[i];
			if(type == -1)
				continue;
			if(type == arguments[0].integer)
				continue;

			Object@ dest = obj.nativeResourceDestination[i];
			int id = obj.nativeResourceId[i];

			obj.removeResource(id);
			int newId = obj.addResource(arguments[0].integer);
			if(dest !is null)
				obj.exportResourceByID(newId, dest);
		}
	}
#section all
};

//HealFleetPerSecond(<Amount>, <Spread> = True)
// Heal the ships in the fleet an amount per second.
//  If Spread is true, the healed amount will be spread
//  out across all the ships, otherwise, each ship individually
//  gets the full heal amount.
class HealFleetPerSecond : GenericEffect {
	Document doc("The fleet this effect is active on is healed by a certain amount of HP per second.");
	Argument amount(AT_Decimal, doc="Amount of HP per second to heal.");
	Argument spread(AT_Boolean, "True", doc="If set to false, each individual ship in the fleet will be healed by the full amount. If set to true, the healed amount is spread out evenly amongst ships.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasLeaderAI)
			obj.repairFleet(arguments[0].decimal, spread=arguments[1].boolean);
	}
#section all
};

class RepairPerSecond : GenericEffect {
	Document doc("Repair the flagship or orbital this is applied to a set amount per second.");
	Argument base_amount(AT_Decimal, "0", doc="Base amount of HP per second to repair.");
	Argument percent(AT_Decimal, "0", doc="Percentage of maximum health to repair per second.");
	Argument multiply_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to multiply base healing amount by.");
	Argument multiply_percent(AT_Boolean, "False", doc="Whether to also multiply the percentage by the attribute.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		double hp = 0;
		if(obj.isShip)
			hp = cast<Ship>(obj).blueprint.design.totalHP;
		else if(obj.isOrbital)
			hp = cast<Orbital>(obj).maxHealth + cast<Orbital>(obj).maxArmor;

		double amt = base_amount.decimal;
		if(multiply_attribute.integer != -1 && !multiply_percent.boolean)
			amt *= obj.owner.getAttribute(multiply_attribute.integer);
		amt += hp * percent.decimal;
		if(multiply_attribute.integer != -1 && multiply_percent.boolean)
			amt *= obj.owner.getAttribute(multiply_attribute.integer);

		amt *= time;

		if(obj.isShip)
			cast<Ship>(obj).repairShip(amt);
		else if(obj.isOrbital)
			cast<Orbital>(obj).repairOrbital(amt);
	}
#section all
};

//InterdictMovement()
// Remove all velocity from an object and prevent it from accelerating.
class InterdictMovement : GenericEffect {
	Document doc("The object this effect is active on cannot accelerate in any way.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasMover) {
			double acc = obj.maxAcceleration;
			data.store(acc);

			obj.velocity = vec3d();
			obj.acceleration = vec3d();
			obj.maxAcceleration = 0.0;
		}
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasMover)
			obj.maxAcceleration = 0.0;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasMover) {
			if(obj.maxAcceleration == 0.0) {
				double acc = 0.0;
				data.retrieve(acc);
				obj.maxAcceleration = acc;
			}
		}
	}
#section all
};

//DelayFTL()
// Delay any FTL used by the object.
class DelayFTL : GenericEffect, TriggerableGeneric {
	Document doc("The object this effect is active on cannot activate its FTL capabilities.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.delayFTL = true;
	}

	void disable(Object& obj, any@ data) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.delayFTL = false;
	}
#section all
};

//DuplicateResourceEffects()
// Duplicate any resource effects present.
tidy final class DupInfo {
	int id;
	Object@ source;
	const ResourceType@ type;
	array<any> dat;
};

class DuplicateResourceEffects : GenericEffect {
	Document doc("All resource effect hooks of resources present on the object are duplicated and run twice.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return locale::HYDROCONDUCTORS_EFFECT;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		array<DupInfo> list;
		data.store(@list);
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(obj.owner is null || !obj.owner.valid)
			return;

		array<DupInfo>@ list;
		data.retrieve(@list);

		array<Resource> resources;
		resources.syncFrom(obj.getAvailableResources());

		//Disable old ones
		for(int i = list.length - 1; i >= 0; --i) {
			auto@ f = list[i];
			bool found = false;
			for(uint j = 0, jcnt = resources.length; j < jcnt; ++j) {
				auto@ r = resources[j];
				if(r.id == f.id && r.origin is f.source && r.type is f.type) {
					found = true;
					resources.removeAt(j);
					break;
				}
			}

			if(!found) {
				for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
					GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
					if(eff !is null && getClass(eff) !is getClass(this))
						eff.disable(obj, f.dat[n]);
				}
				list.removeAt(i);
			}
		}

		//Enable new ones
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			auto@ r = resources[i];
			DupInfo f;
			f.id = r.id;
			@f.source = r.origin;
			@f.type = r.type;
			f.dat.length = r.type.hooks.length;

			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.enable(obj, f.dat[n]);
			}

			list.insertLast(f);
		}

		//Tick existing
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ f = list[i];
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.tick(obj, f.dat[n], time);
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		array<DupInfo>@ list;
		data.retrieve(@list);

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ f = list[i];
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.disable(obj, f.dat[n]);
			}
		}

		@list = null;
		data.store(@list);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		array<DupInfo>@ list;
		data.retrieve(@list);

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ f = list[i];
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.ownerChange(obj, f.dat[n], prevOwner, newOwner);
			}
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		array<DupInfo>@ list;
		data.retrieve(@list);

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ f = list[i];
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.regionChange(obj, f.dat[n], fromRegion, toRegion);
			}
		}
	}

	void save(any@ data, SaveFile& file) const {
		array<DupInfo>@ list;
		data.retrieve(@list);

		uint cnt = list.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ f = list[i];
			file << f.id;
			file << f.source;
			file.writeIdentifier(SI_Resource, f.type.id);
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.save(f.dat[n], file);
			}
		}
	}

	void load(any@ data, SaveFile& file) const {
		array<DupInfo> list;
		data.store(@list);

		uint cnt = 0;
		file >> cnt;
		list.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ f = list[i];
			file >> f.id;
			file >> f.source;
			@f.type = getResource(file.readIdentifier(SI_Resource));
			f.dat.length = f.type.hooks.length;
			for(uint n = 0, ncnt = f.type.hooks.length; n < ncnt; ++n) {
				GenericEffect@ eff = cast<GenericEffect>(f.type.hooks[n]);
				if(eff !is null && getClass(eff) !is getClass(this))
					eff.load(f.dat[n], file);
			}
		}
	}
#section all
};

//MultConstructionCostFromGlobal(<Global>, <Base> = 1.0, <Factor> = 0.0)
// Change the construction cost modifier from a global.
class MultConstructionCostFromGlobal : GenericEffect {
	Document doc("Multiply the construction cost of building things on this object based on a global value.");
	Argument global(AT_Global, doc="Name of the global variable to use.");
	Argument base(AT_Decimal, "1.0", doc="Base factor to multiply construction costs by.");
	Argument factor(AT_Decimal, "0.0", doc="Is multiplied by the value of the global, then added to Base in order to get the new construction cost multiplier.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 1.0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 1.0;
		data.retrieve(value);

		double newValue = arguments[1].decimal + getGlobal(arguments[0].integer).value * arguments[2].decimal;
		newValue = max(newValue, 0.001);
		if(newValue != value) {
			obj.multConstructionCostMod(newValue / value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 1.0;
		data.retrieve(value);
		obj.multConstructionCostMod(1.0 / value);
	}
#section all
};

class MultConstructionCost : GenericEffect, TriggerableGeneric {
	Document doc("Multiply the construction cost of building things on this object.");
	Argument factor(AT_Decimal, "1.0", doc="Factor to multiply construction costs by.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.multConstructionCostMod(max(factor.decimal, 0.001));
	}

	void disable(Object& obj, any@ data) const override {
		obj.multConstructionCostMod(1.0 / max(factor.decimal, 0.001));
	}
#section all
};

class ResupplyFlagship : GenericEffect {
	Document doc("Resupply the flagship over time.");
	Argument base_amount(AT_Decimal, "0", doc="Base rate to resupply at per second.");
	Argument percent(AT_Decimal, "0", doc="Percentage of maximum supply to resupply per second.");
	Argument in_combat(AT_Boolean, "False", doc="Whether the resupply rate should apply in combat.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(!obj.isShip || !obj.hasLeaderAI)
			return;
		if(!in_combat.boolean && obj.inCombat)
			return;

		Ship@ ship = cast<Ship>(obj);
		if(ship.Supply >= ship.MaxSupply)
			return;

		double rate = time * base_amount.decimal;
		if(percent.decimal != 0)
			rate += time * percent.decimal * ship.MaxSupply;
		ship.refundSupply(rate);
	}
#section all
};

tidy final class OnEnable : GenericEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when the effect enables.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");
	Argument repeats(AT_Integer, "1", doc="How many times to execute the effect.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnEnable(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(hook !is null) {
			for(int i = 0; i < repeats.integer; ++i)
				hook.activate(obj, obj.owner);
		}
	}
#section all
};

tidy final class OnPlanetEnable : GenericEffect {
	GenericEffect@ hook;

	Document doc("Trigger a generic planet effect when the effect enables.");
	Argument function(AT_Hook, "planet_effects::TriggerableGeneric");
	Argument repeats(AT_Integer, "1", doc="How many times to execute the effect.");

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(arguments[0].str, "planet_effects::", required=false));
		if(hook is null) {
			error("OnPlanetEnable(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(hook !is null) {
			for(int i = 0; i < repeats.integer; ++i)
				hook.enable(obj, data);
		}
	}
#section all
};

tidy final class OnDisable : GenericEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when the effect disables.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");
	Argument repeats(AT_Integer, "1", doc="How many times to execute the effect.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnDisable(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void disable(Object& obj, any@ data) const override {
		if(hook !is null) {
			for(int i = 0; i < repeats.integer; ++i)
				hook.activate(obj, obj.owner);
		}
	}
#section all
};

class GloballyVisible : GenericEffect {
	Document doc("The object this effect is on can be seen by everyone at all times.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		obj.donatedVision |= ~0;
	}
#section all
};

class AddLaborStorage : GenericEffect, TriggerableGeneric {
	Document doc("Add labor storage capacity to the object. Only works on objects with construction capabilities.");
	Argument amount(AT_Decimal, doc="Amount of labor storage capacity to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborStorage(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modLaborStorage(-amount.decimal);
	}
#section all
};

class IsGate : GenericEffect {
	Document doc("This object behaves as if it is a gate that connects to the gate network.");
	
#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.registerStargate(obj);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.unregisterStargate(obj);
		if(newOwner !is null && newOwner.valid)
			newOwner.registerStargate(obj);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.unregisterStargate(obj);
	}
#section all
};

class IsFlingBeacon : GenericEffect {
	Document doc("This object behaves like it is a fling beacon that ships can fling off of.");
	
#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.registerFlingBeacon(obj);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.unregisterFlingBeacon(obj);
		if(newOwner !is null && newOwner.valid)
			newOwner.registerFlingBeacon(obj);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.unregisterFlingBeacon(obj);
	}
#section all
};

class SetSystemFlag : GenericEffect, TriggerableGeneric {
	Document doc("While this object is in a particular system, a specified system flag is set.");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to set. Can be set to any arbitrary name, and the matching system flag will be created.");

#section server
	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ region = obj.region;
		if(region !is null) {
			if(prevOwner !is null && prevOwner.valid)
				region.setSystemFlag(prevOwner, flag.integer, false);
			if(newOwner !is null && newOwner.valid)
				region.setSystemFlag(newOwner, flag.integer, true);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			if(fromRegion !is null)
				fromRegion.setSystemFlag(owner, flag.integer, false);
			if(toRegion !is null)
				toRegion.setSystemFlag(owner, flag.integer, true);
		}
	}

	void enable(Object& obj, any@ data) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.setSystemFlag(owner, flag.integer, true);
	}

	void disable(Object& obj, any@ data) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.setSystemFlag(owner, flag.integer, false);
	}
#section all
};

//Generic implementation for generic hook conditions
tidy final class IfData {
	bool enabled;
	any data;
};

tidy class IfHook : GenericEffect {
	GenericEffect@ hook;

	bool withHook(const string& str) {
		@hook = cast<GenericEffect>(parseHook(str, "planet_effects::"));
		if(hook is null) {
			error("If<>(): could not find inner hook: "+escape(str));
			return false;
		}
		return true;
	}

	bool condition(Object& obj) const {
		return false;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		IfData info;
		info.enabled = condition(obj);
		data.store(@info);

		if(info.enabled)
			hook.enable(obj, info.data);
	}

	void disable(Object& obj, any@ data) const override {
		IfData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.disable(obj, info.data);
	}

	void tick(Object& obj, any@ data, double time) const {
		IfData@ info;
		data.retrieve(@info);

		bool cond = condition(obj);
		if(cond != info.enabled) {
			if(info.enabled)
				hook.disable(obj, info.data);
			else
				hook.enable(obj, info.data);
			info.enabled = cond;
		}
		if(info.enabled)
			hook.tick(obj, info.data, time);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		IfData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.ownerChange(obj, info.data, prevOwner, newOwner);
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		IfData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.regionChange(obj, info.data, fromRegion, toRegion);
	}

	void save(any@ data, SaveFile& file) const {
		IfData@ info;
		data.retrieve(@info);

		if(info is null) {
			bool enabled = false;
			file << enabled;
		}
		else {
			file << info.enabled;
			if(info.enabled)
				hook.save(info.data, file);
		}
	}

	void load(any@ data, SaveFile& file) const {
		IfData info;
		data.store(@info);

		file >> info.enabled;
		if(info.enabled)
			hook.load(info.data, file);
	}
#section all
};

//IfNative(<Planet Resource>, <Hook>(..))
// Executes the hook if the planet has native <Planet Resource>.
tidy final class IfNative : IfHook {
	Document doc("Only apply the inner hook if the planet this is being executed on has a particular native resource.");
	Argument resource(AT_PlanetResource, doc="Planetary resource to check for.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[1].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		for(uint i = 0, cnt = obj.nativeResourceCount; i < cnt; ++i) {
			if(obj.nativeResourceType[i] == uint(arguments[0].integer))
				return true;
		}
		return false;
	}
};

tidy final class IfNotNative : IfHook {
	Document doc("Only apply the inner hook if the planet this is being executed on does not have a particular native resource.");
	Argument resource(AT_PlanetResource, doc="Planetary resource to check for.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[1].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		for(uint i = 0, cnt = obj.nativeResourceCount; i < cnt; ++i) {
			if(obj.nativeResourceType[i] == uint(arguments[0].integer))
				return false;
		}
		return true;
	}
};

tidy final class IfAvailableOfTier : IfHook {
	Document doc("Only apply the hook if the object has a certain amount of available usable tiered resources.");
	Argument tier(AT_Integer, doc="Tier to check for.");
	Argument amount(AT_Integer, doc="Minimum amount that should be available.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument enabled_mod(AT_Integer, "0", doc="Change to available when the hook is enabled.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	void tick(Object& obj, any@ data, double time) const {
		IfData@ info;
		data.retrieve(@info);

		int avail = obj.getAvailableOfTier(tier.integer);
		if(info.enabled)
			avail += enabled_mod.integer;
		bool cond = avail >= amount.integer;

		if(cond != info.enabled) {
			if(info.enabled)
				hook.disable(obj, info.data);
			else
				hook.enable(obj, info.data);
			info.enabled = cond;
		}
		if(info.enabled)
			hook.tick(obj, info.data, time);
	}
#section all
};

tidy final class IfHaveTrait : IfHook {
	Document doc("Only apply the inner hook if the owner of the object has a particular trait.");
	Argument trait(AT_Trait, doc="Trait to check for.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[1].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		return owner.hasTrait(trait.integer);
	}
};

tidy final class IfNotHaveTrait : IfHook {
	Document doc("Only apply the inner hook if the owner of the object does not have a particular trait.");
	Argument trait(AT_Trait, doc="Trait to check for.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[1].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		return !owner.hasTrait(trait.integer);
	}
};

tidy final class ConsumeData {
	bool enabled = false;
	double timer = 0.0;
	any data;
};
class WhileConsumingCargo : GenericEffect {
	Document doc("This hook applies while a particular amount of cargo can be consumed every interval.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to consume.");
	Argument amount(AT_Decimal, doc="Amount of cargo to consume per interval.");
	Argument interval(AT_Decimal, doc="Interval to consume cargo at.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	GenericEffect@ hook;

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool withHook(const string& str) {
		@hook = cast<GenericEffect>(parseHook(str, "planet_effects::"));
		if(hook is null) {
			error("If<>(): could not find inner hook: "+escape(str));
			return false;
		}
		return true;
	}

	bool condition(Object& obj) const {
		return false;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		ConsumeData info;
		info.enabled = false;
		data.store(@info);

		if(info.enabled)
			hook.enable(obj, info.data);
	}

	void disable(Object& obj, any@ data) const override {
		ConsumeData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.disable(obj, info.data);
	}

	void tick(Object& obj, any@ data, double time) const {
		ConsumeData@ info;
		data.retrieve(@info);

		bool cond = info.enabled;
		info.timer -= time;
		if(info.timer <= 0) {
			if(!obj.hasCargo) {
				cond = false;
				info.timer = randomd(1.0, 2.0);
			}
			else {
				double consAmt = obj.consumeCargo(cargo_type.integer, amount.decimal, partial=false);
				if(consAmt < amount.decimal - 0.001) {
					cond = false;
					info.timer = randomd(1.0, 2.0);
				}
				else {
					cond = true;
					info.timer += interval.decimal;
				}
			}
		}

		if(cond != info.enabled) {
			if(info.enabled)
				hook.disable(obj, info.data);
			else
				hook.enable(obj, info.data);
			info.enabled = cond;
		}
		if(info.enabled)
			hook.tick(obj, info.data, time);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		ConsumeData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.ownerChange(obj, info.data, prevOwner, newOwner);
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		ConsumeData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.regionChange(obj, info.data, fromRegion, toRegion);
	}

	void save(any@ data, SaveFile& file) const {
		ConsumeData@ info;
		data.retrieve(@info);

		if(info is null) {
			bool enabled = false;
			file << enabled;
			double timer = 0.0;
			file << timer;
		}
		else {
			file << info.enabled;
			file << info.timer;
			if(info.enabled)
				hook.save(info.data, file);
		}
	}

	void load(any@ data, SaveFile& file) const {
		ConsumeData info;
		data.store(@info);

		file >> info.enabled;
		file >> info.timer;
		if(info.enabled)
			hook.load(info.data, file);
	}
#section all
};

tidy final class IfMaster : IfHook {
	Document doc("Only apply the hook if this is not an orbital, or if the orbital it is on is not slaved to anything.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Orbital@ orb = cast<Orbital>(obj);
		return orb is null || !orb.hasMaster();
	}
};

tidy final class IfNotMaster : IfHook {
	Document doc("Only apply the hook if this is not an orbital, or if the orbital it is on is slaved to something else.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Orbital@ orb = cast<Orbital>(obj);
		return orb is null || orb.hasMaster();
	}
};

//IfType(<Object Type>, <Hook>(..))
// Executes the hook if the object is of a particular type.
tidy final class IfType : IfHook {
	int typeId = -1;

	Document doc("Only apply the inner hook if the object this effect is being executed on is of a particular type.");
	Argument type(AT_ObjectType, doc="Type of objects to apply the hook on.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		typeId = getObjectTypeId(arguments[0].str);
		if(typeId == -1) {
			error("Invalid object type: "+arguments[0].str);
			return false;
		}
		if(!withHook(arguments[1].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		return obj.type == typeId;
	}

	void load(Resource@ r, SaveFile& file) const {
		if(file >= SV_0045) {
			load(r.data[hookIndex], file);
		}
		else {
			Object@ onObj;
			if(r.exportedTo !is null)
				@onObj = r.exportedTo;
			else
				@onObj = r.origin;

			IfData info;
			r.data[hookIndex].store(@info);

			file >> info.enabled;
			if(info.enabled && !condition(onObj))
				info.enabled = false;
			if(info.enabled)
				hook.load(info.data, file);
		}
	}
};

tidy final class IfTagUnlocked : IfHook {
	Document doc("Only apply the inner hook if the object's owner has a particular tag marked as unlocked.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in the UnlockTag() or similar hook that should unlock it.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Empire@ owner = obj.owner;
		if(owner is null)
			return false;
		return owner.isTagUnlocked(tag.integer);
	}
};

//IfNearFriendlyPlanets(<Hook>(..))
// Executes the hook only if there are friendly planets nearby.
tidy final class IfNearFriendlyPlanets : IfHook {
	Document doc("Only apply the inner hook if the object this effect is being executed on is in the same system as planets owned by friendly empires.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[0].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		Empire@ owner = obj.owner;
		if(owner is null)
			return false;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major || other is owner)
				continue;
			if(owner.isHostile(other))
				continue;
			if(reg.getPlanetCount(other) > 0)
				return true;
		}
		return false;
	}
};

tidy final class IfFriendlyStationed : IfHook {
	Document doc("Apply the inner hook if this fleet is stationed in a friendly system.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[0].str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		if(obj.inCombat)
			return false;
		if(reg.PlanetsMask & obj.owner.mask == 0)
			return false;
		if(reg.ContestedMask & obj.owner.mask != 0)
			return false;
		if(obj.velocity.lengthSQ >= 0.01)
			return false;
		return true;
	}
};

tidy final class IfBorderSystem : IfHook {
	Document doc("Apply the inner hook if the object is in a system that is bordering a different empire.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[0].str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;

		Empire@ emp = obj.owner;
		SystemDesc@ sys = getSystem(reg);
		if(sys.object.PlanetsMask & emp.mask == 0)
			return false;

		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			SystemDesc@ adj = getSystem(sys.adjacent[i]);
			uint planets = adj.object.PlanetsMask;
			if(planets & ~emp.mask != 0)
				return true;
		}
		return false;
	}
#section all
};

tidy final class IfSystemFlag : IfHook {
	Document doc("Only apply the inner hook if a particular system flag is set on the system this is in.");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to check. Can be set to any arbitrary name, and the matching system flag will be created.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		return reg.getSystemFlag(obj.owner, flag.integer);
	}
};

tidy final class IfNotSystemFlag : IfHook {
	Document doc("Only apply the inner hook if a particular system flag is not set on the system this is in.");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to check. Can be set to any arbitrary name, and the matching system flag will be created.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		return !reg.getSystemFlag(obj.owner, flag.integer);
	}
};

//IfNotSiege(<Hook>(..))
// Executes the hook only if the planet is not under siege.
tidy final class IfNotSiege : IfHook {
	Document doc("Only apply the inner hook if the planet is not currently under siege.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[0].str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.hasSurfaceComponent)
			return true;
		return !obj.isUnderSiege || obj.supportCount > 0 || obj.isGettingRelief;
	}
#section all
};

tidy final class IfDefending : IfHook {
	Document doc("Only applies the inner hook if the object is currently listed as being used for defense.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(arguments[0].str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		Empire@ owner = obj.owner;
		if(owner is null)
			return false;
		return owner.isDefending(obj);
	}
#section all
};

tidy final class IfStation : IfHook {
	Document doc("Only apply the inner hook if this is a station.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument allow_orbital(AT_Boolean, "True", doc="Whether to count orbitals as stations.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		if(allow_orbital.boolean && obj.isOrbital)
			return true;
		if(obj.isShip)
			return cast<Ship>(obj).isStation;
		return false;
	}
};

tidy final class IfLevel : IfHook {
	Document doc("Only applies the inner hook if a planet is of a specified level.");
	Argument level(AT_Integer, doc="Required planet level for the effect to apply.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument exact(AT_Boolean, "False", doc="If set, only activate the hook if the planet is _exactly_ this level. If not set, all planets of the specified level _or higher_ will be affected.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.isPlanet)
			return false;
		int lv = obj.level;
		if(exact.boolean)
			return lv == level.integer;
		return lv >= level.integer;
	}
#section all
};

tidy final class IfHaveStatus : IfHook {
	Document doc("Only applies the inner hook if the object has a particular status.");
	Argument status(AT_Status, doc="Required status for the effect to apply.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.hasStatuses)
			return false;
		return obj.getStatusStackCountAny(status.integer) > 0;
	}
#section all
};

tidy final class IfNotHaveStatus : IfHook {
	Document doc("Only applies the inner hook if the object does not have a particular status.");
	Argument status(AT_Status, doc="Forbidden status for the effect toapply.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.hasStatuses)
			return false;
		return obj.getStatusStackCountAny(status.integer) == 0;
	}
#section all
};

tidy final class IfAttributeGTE : IfHook {
	Document doc("Only applies the inner hook if the empire has an attribute at at least a value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Value to check.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return obj.owner.getAttribute(attribute.integer) >= value.decimal;
	}
#section all
};

tidy final class IfAttributeLT : IfHook {
	Document doc("Only applies the inner hook if the empire has an attribute at lower than a value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Value to check.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return obj.owner.getAttribute(attribute.integer) < value.decimal;
	}
#section all
};

tidy final class IfAttributeZero : IfHook {
	Document doc("Only applies the inner hook if the empire has an attribute at zero.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return obj.owner.getAttribute(attribute.integer) <= 0.0001;
	}
#section all
};

tidy final class IfNativeLevel : IfHook {
	Document doc("Only applies the inner hook if a planet's native resource is of a specified level.");
	Argument level(AT_Integer, doc="Required resource level for the effect to apply.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument exact(AT_Boolean, "False", doc="If set, only activate the hook if the planet is _exactly_ this level. If not set, all planets of the specified level _or higher_ will be affected.");
	Argument limit(AT_Boolean, "True", doc="Whether to take limit level instead of requirement level.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.isPlanet)
			return false;
		int lv = 0;
		if(limit.boolean)
			lv = obj.primaryResourceLimitLevel;
		else
			lv = obj.primaryResourceLevel;
		if(exact.boolean)
			return lv == level.integer;
		return lv >= level.integer;
	}
#section all
};

tidy final class IfNotNativeClass : IfHook {
	Document doc("Only applies the inner hook if a planet's native resource is of a specified class.");
	Argument cls(AT_Custom, doc="Required resource class.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	int clsId = -1;

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;

		auto@ clsType = getResourceClass(cls.str);
		if(clsType !is null)
			clsId = clsType.id;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.isPlanet)
			return true;
		auto@ res = getResource(obj.primaryResourceType);
		if(res is null || res.cls is null)
			return true;
		return int(res.cls.id) != clsId;
	}
#section all
};

tidy final class IfNativeClass : IfHook {
	Document doc("Only applies the inner hook if a planet's native resource is of a specified class.");
	Argument cls(AT_Custom, doc="Required resource class.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	int clsId = -1;

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;

		auto@ clsType = getResourceClass(cls.str);
		if(clsType !is null)
			clsId = clsType.id;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.isPlanet)
			return false;
		auto@ res = getResource(obj.primaryResourceType);
		if(res is null || res.cls is null)
			return false;
		return int(res.cls.id) == clsId;
	}
#section all
};

tidy final class IfTargetLevel : IfHook {
	Document doc("Only applies the inner hook if a planet's current target level based on its imports is of a specified level.");
	Argument level(AT_Integer, doc="Required resource level for the effect to apply.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument exact(AT_Boolean, "False", doc="If set, only activate the hook if the planet is _exactly_ this level. If not set, all planets of the specified level _or higher_ will be affected.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.isPlanet)
			return false;
		int lv = obj.resourceLevel;
		if(exact.boolean)
			return lv == level.integer;
		return lv >= level.integer;
	}
#section all
};

tidy final class IfPopulationBelow : IfHook {
	Document doc("Only applies the inner hook if the population is below a certain amount.");
	Argument amount(AT_Decimal, doc="Population below which to apply the inner effect.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.hasSurfaceComponent)
			return false;
		return obj.population < amount.decimal;
	}
#section all
};

tidy final class IfCoversPopulation : IfHook {
	Document doc("Only apply the inner hook if an attribute is greater or equal to the total empire population.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check for coverage.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

	bool condition(Object& obj) const override {
		return obj.owner.TotalPopulation <= obj.owner.getAttribute(attribute.integer);
	}
};

tidy final class IfInOwnedSpace : IfHook {
	Document doc("Only applies the inner hook if the current object is in owned space. ie a system where you own planets.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument allow_allies(AT_Boolean, "False", doc="Whether to count space with allied planets as owned.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		Region@ region = obj.region;
		if(region is null)
			return false;
		if(allow_allies.boolean)
			return region.PlanetsMask & obj.owner.ForcedPeaceMask.value != 0;
		else
			return region.PlanetsMask & obj.owner.mask != 0;
	}
#section all
};

tidy final class IfNotFTLBlocked : IfHook {
	Document doc("Only applies the inner hook if the current object is not being FTL jammed.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		Region@ region = obj.region;
		if(region is null)
			return true;
		if(region.BlockFTLMask & obj.owner.mask != 0)
			return false;
		return true;
	}
#section all
};

tidy final class IfNotFTLShortage : IfHook {
	Document doc("Only applies the inner hook if the empire does not have an FTL shortage.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return !obj.owner.FTLShortage;
	}
#section all
};

tidy final class IfInSystem : IfHook {
	Document doc("Only applies the inner hook if the object is in a system.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return obj.region !is null;
	}
#section all
};

tidy final class IfSystemHasStar : IfHook {
	Document doc("Only applies the inner hook if the object is in a system that has a star.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		return reg.starCount > 0;
	}
#section all
};

tidy final class IfUsingLabor : IfHook {
	Document doc("Only applies the inner hook if the object is currently using labor.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return obj.hasConstruction && obj.isUsingLabor;
	}
#section all
};

tidy final class TimerData {
	double timer = 0;
	bool enabled = false;
	any data;
};

class EnableAfter : GenericEffect {
	GenericEffect@ hook;
	Document doc("Only enable the specified effect after a certain amount of time has passed.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument start_timer(AT_Decimal, "0", doc="Amount of time in seconds before enabling the effect.");
	Argument stop_timer(AT_Decimal, "-1", doc="Amount of time in seconds before disabling the effect again, measured from the same 0 point as the start timer. -1 to never disable it again.");

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::"));
		if(hook is null) {
			error("EnableAfter(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Object& obj, any@ data) const override {
		TimerData info;
		info.enabled = false;
		info.timer = 0;
		data.store(@info);
	}

	void disable(Object& obj, any@ data) const override {
		TimerData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.disable(obj, info.data);
	}

	void tick(Object& obj, any@ data, double time) const {
		TimerData@ info;
		data.retrieve(@info);

		info.timer += time;
		bool cond = info.timer >= start_timer.decimal && (stop_timer.decimal < 0 || info.timer < stop_timer.decimal);
		if(cond != info.enabled) {
			if(info.enabled)
				hook.disable(obj, info.data);
			else
				hook.enable(obj, info.data);
			info.enabled = cond;
		}
		if(info.enabled)
			hook.tick(obj, info.data, time);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		TimerData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.ownerChange(obj, info.data, prevOwner, newOwner);
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		TimerData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.regionChange(obj, info.data, fromRegion, toRegion);
	}

	void save(any@ data, SaveFile& file) const {
		TimerData@ info;
		data.retrieve(@info);

		if(info is null) {
			bool enabled = false;
			file << enabled;
			double timer = 0.0;
			file << timer;
		}
		else {
			file << info.enabled;
			file << info.timer;
			if(info.enabled)
				hook.save(info.data, file);
		}
	}

	void load(any@ data, SaveFile& file) const {
		TimerData info;
		data.store(@info);

		file >> info.enabled;
		file >> info.timer;
		if(info.enabled)
			hook.load(info.data, file);
	}
#section all
};

class AddGlobalDefenseAdjacentFlags : GenericEffect {
	Document doc("Add an amount of pressure-equivalent defense generation to the empire's global defense pool, based on how many systems surrounding the system this is in have a particular system flag active..");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to check. Can be set to any arbitrary name, and the matching system flag will be created.");
	Argument min_amount(AT_Decimal, doc="Minimum amount of defense generation to add, when no surrounding systems have the flag.");
	Argument max_amount(AT_Decimal, doc="Maximum amount of defense generation to add, when all surrounding systems have the flag.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		Empire@ owner = obj.owner;
		auto@ region = obj.region;
		double newValue = 0;
		if(owner !is null && region !is null) {
			newValue = min_amount.decimal;

			auto@ sys = getSystem(region);
			double perSys = (max_amount.decimal - min_amount.decimal) / double(sys.adjacent.length);
			for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
				auto@ other = getSystem(sys.adjacent[i]);
				if(other !is null) {
					if(other.object.getSystemFlag(owner, flag.integer))
						newValue += perSys;
				}
			}
			newValue *= DEFENSE_LABOR_PM / 60.0;
		}
		if(newValue != value && obj.hasLeaderAI) {
			if(owner !is null)
				owner.modDefenseRate(newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);

		if(obj.owner !is null)
			obj.owner.modDefenseRate(-value);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		double value = 0;
		data.retrieve(value);

		if(prevOwner !is null && prevOwner.valid)
			prevOwner.modDefenseRate(-value);
		if(newOwner !is null && newOwner.valid)
			newOwner.modDefenseRate(+value);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};


tidy final class LocalData {
	const Design@ design;
	double labor = 0;
	double global = 0;
	double timeout = 0;
};

class AddLocalDefense : GenericEffect {
	Document doc("Add an amount of pressure-equivalent defense generation that is only used to build defense on this local object.");
	Argument amount(AT_Decimal, doc="Amount of defense generation.");
	Argument overflow_global(AT_Boolean, "False", doc="If set, the local defense will be added to the empire's global pool, but only after the current object has filled up all its support command.");
	Argument disable_in_combat(AT_Boolean, "True", doc="If set, the defense generation is disabled when the object is in combat.");
	Argument global_factor(AT_Decimal, "1.0", doc="Multiplication factor to the defense before it gets added to the global pool.");
	Argument build_satellites(AT_Boolean, "False", doc="Whether to only build satellite designs locally.");
	Argument stop_filled(AT_Boolean, "True", doc="Don't build past what fills up this object.");

#section server
	void enable(Object& obj, any@ data) const override {
		LocalData dat;
		data.store(@dat);
	}

	void tick(Object& obj, any@ data, double time) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		double secondDefense = amount.decimal * DEFENSE_LABOR_PM / 60.0;
		double tickDefense = secondDefense * time;
		if(disable_in_combat.boolean && obj.inCombat)
			tickDefense = 0;

		if(dat.design is null) {
			int maxSize = -1;
			if(stop_filled.boolean && obj.hasLeaderAI) {
				maxSize = obj.SupplyCapacity - obj.SupplyUsed;
				if(maxSize <= 0)
					return;
			}
			if(obj.hasLeaderAI && !obj.canGainSupports)
				return;
			if(dat.timeout > 0) {
				dat.timeout -= time;
				return;
			}

			@dat.design = getDefenseDesign(obj.owner, secondDefense, satellite=build_satellites.boolean, maxSize=maxSize);
			if(dat.design !is null)
				dat.labor = getLaborCost(dat.design, 1);
			else
				dat.timeout = 30.0;
		}
		else {
			if(overflow_global.boolean) {
				if(!obj.hasLeaderAI || obj.SupplyUsed + uint(dat.design.size) > obj.SupplyCapacity) {
					if(dat.global != secondDefense) {
						obj.owner.modDefenseRate((secondDefense-dat.global) * global_factor.decimal);
						dat.global = secondDefense;
					}
					return;
				}
				else if(dat.global != 0) {
					obj.owner.modDefenseRate(-dat.global * global_factor.decimal);
					dat.global = 0;
				}
			}

			dat.labor -= tickDefense;
			if(dat.labor <= 0) {
				Object@ leader;
				if(obj.hasLeaderAI && obj.canGainSupports)
					@leader = obj;
				createShip(obj, dat.design, obj.owner, leader, false, true);
				@dat.design = null;
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		LocalData@ dat;
		data.retrieve(@dat);
		
		Empire@ owner = obj.owner;
		if(owner !is null && dat.global != 0) {
			owner.modDefenseRate(-dat.global * global_factor.decimal);
			dat.global = 0;
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		if(dat !is null && dat.global != 0) {
			if(prevOwner !is null && prevOwner.valid)
				prevOwner.modDefenseRate(-dat.global * global_factor.decimal);
			if(newOwner !is null && newOwner.valid)
				newOwner.modDefenseRate(+dat.global * global_factor.decimal);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		file << dat.design;
		file << dat.labor;
		file << dat.global;
	}

	void load(any@ data, SaveFile& file) const override {
		LocalData dat;
		data.store(@dat);

		file >> dat.design;
		file >> dat.labor;
		file >> dat.global;
	}
#section all
};

class AddLocalDefenseAdjacentFlags : GenericEffect {
	Document doc("Add an amount of pressure-equivalent defense generation that is only used to build defense on this local object, based on how many systems surrounding the system this is in have a particular system flag active..");
	Argument flag(AT_SystemFlag, doc="Identifier for the system flag to check. Can be set to any arbitrary name, and the matching system flag will be created.");
	Argument min_amount(AT_Decimal, doc="Minimum amount of defense generation to add, when no surrounding systems have the flag.");
	Argument max_amount(AT_Decimal, doc="Maximum amount of defense generation to add, when all surrounding systems have the flag.");
	Argument overflow_global(AT_Boolean, "False", doc="If set, the local defense will be added to the empire's global pool, but only after the current object has filled up all its support command.");
	Argument disable_in_combat(AT_Boolean, "True", doc="If set, the defense generation is disabled when the object is in combat.");
	Argument global_factor(AT_Decimal, "1.0", doc="Multiplication factor to the defense before it gets added to the global pool.");
	Argument local_boost(AT_EmpAttribute, "", doc="Empire attribute to add as a percentage of defense value by when used locally.");

#section server
	void enable(Object& obj, any@ data) const override {
		LocalData dat;
		data.store(@dat);
	}

	void tick(Object& obj, any@ data, double time) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		double secondDefense = 0;
		Empire@ owner = obj.owner;
		Region@ region = obj.region;
		if(owner !is null && region !is null) {
			secondDefense = min_amount.decimal;

			auto@ sys = getSystem(region);
			double perSys = (max_amount.decimal - min_amount.decimal) / double(sys.adjacent.length);
			for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
				auto@ other = getSystem(sys.adjacent[i]);
				if(other !is null) {
					if(other.object.getSystemFlag(owner, flag.integer))
						secondDefense += perSys;
				}
			}
			secondDefense *= DEFENSE_LABOR_PM / 60.0;
		}

		double tickDefense = secondDefense * time;
		if(disable_in_combat.boolean && obj.inCombat)
			tickDefense = 0;

		if(dat.design is null) {
			@dat.design = getDefenseDesign(obj.owner, secondDefense);
			if(dat.design !is null)
				dat.labor = getLaborCost(dat.design, 1);
		}
		else {
			if(overflow_global.boolean) {
				if(!obj.hasLeaderAI || obj.SupplyUsed + uint(dat.design.size) > obj.SupplyCapacity) {
					if(dat.global != secondDefense) {
						obj.owner.modDefenseRate((secondDefense-dat.global) * global_factor.decimal);
						dat.global = secondDefense;
					}
					return;
				}
				else if(dat.global != 0) {
					obj.owner.modDefenseRate(-dat.global * global_factor.decimal);
					dat.global = 0;
				}
			}

			if(local_boost.integer != -1)
				tickDefense *= 1.0 + obj.owner.getAttribute(local_boost.integer);

			dat.labor -= tickDefense;
			if(dat.labor <= 0) {
				Object@ leader;
				if(obj.hasLeaderAI && obj.canGainSupports)
					@leader = obj;
				createShip(obj, dat.design, obj.owner, leader, false, true);
				@dat.design = null;
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		LocalData@ dat;
		data.retrieve(@dat);
		
		Empire@ owner = obj.owner;
		if(owner !is null && dat.global != 0) {
			owner.modDefenseRate(-dat.global * global_factor.decimal);
			dat.global = 0;
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		if(dat.global != 0) {
			if(prevOwner !is null && prevOwner.valid)
				prevOwner.modDefenseRate(-dat.global * global_factor.decimal);
			if(newOwner !is null && newOwner.valid)
				newOwner.modDefenseRate(+dat.global * global_factor.decimal);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		LocalData@ dat;
		data.retrieve(@dat);

		file << dat.design;
		file << dat.labor;
		file << dat.global;
	}

	void load(any@ data, SaveFile& file) const override {
		LocalData dat;
		data.store(@dat);

		file >> dat.design;
		file >> dat.labor;
		file >> dat.global;
	}
#section all
};

class LimitSightRange : GenericEffect {
	Document doc("Limit the sight range of all objects given this status to no more than the specified value. Do not apply multiple times to a single object.");
	Argument max_sight(AT_Decimal, doc="Maximum sight range to set objects to.");
	Argument min_sight(AT_Decimal, "0", doc="Minimum sight range to set objects to.");

#section server
	void enable(Object& obj, any@ data) const override {
		double prevRange = obj.sightRange;
		data.store(prevRange);

		double newRange = clamp(prevRange, min_sight.decimal, max_sight.decimal);
		obj.sightRange = newRange;
	}

	void disable(Object& obj, any@ data) const override {
		double prevRange = 0;
		data.retrieve(prevRange);

		obj.sightRange = prevRange;
	}

	void save(any@ data, SaveFile& file) const override {
		double prevRange = 0;
		data.retrieve(prevRange);

		file << prevRange;
	}

	void load(any@ data, SaveFile& file) const override {
		double prevRange = 0;
		file >> prevRange;

		data.store(prevRange);
	}
#section all
};

class LimitSeeableRange : GenericEffect {
	Document doc("Limit the seeable range of all objects given this status to no more than the specified value. Do not apply multiple times to a single object.");
	Argument max_seeable(AT_Decimal, doc="Maximum seeable range to set objects to.");
	Argument min_seeable(AT_Decimal, "0", doc="Minimum seeable range to set objects to.");

#section server
	void enable(Object& obj, any@ data) const override {
		double prevRange = obj.seeableRange;
		data.store(prevRange);

		double newRange = clamp(prevRange, min_seeable.decimal, max_seeable.decimal);
		obj.seeableRange = newRange;
	}

	void disable(Object& obj, any@ data) const override {
		double prevRange = 0;
		data.retrieve(prevRange);

		obj.seeableRange = prevRange;
	}

	void save(any@ data, SaveFile& file) const override {
		double prevRange = 0;
		data.retrieve(prevRange);

		file << prevRange;
	}

	void load(any@ data, SaveFile& file) const override {
		double prevRange = 0;
		file >> prevRange;

		data.store(prevRange);
	}
#section all
};

class AddAccelerationBonus : GenericEffect, TriggerableGeneric {
	Document doc("Add a bonus amount of acceleration to the object. In case it is a planet, also allow the planet to move.");
	Argument amount(AT_Decimal, doc="Acceleration amount to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet) {
			Planet@ pl = cast<Planet>(obj);
			if(!pl.hasMover) {
				pl.activateMover();
				pl.maxAcceleration = 0;
			}
		}
		if(obj.hasMover)
			obj.modAccelerationBonus(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasMover)
			obj.modAccelerationBonus(-amount.decimal);
	}
#section all
};

class AttributeAccelerationBonus : GenericEffect, TriggerableGeneric {
	Document doc("Add bonus acceleration equal to an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to add as fleet command, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument stations(AT_Boolean, "True", doc="Whether to also give the acceleration bonus to stations.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double curAmount = 0;
		data.retrieve(curAmount);

		double newAmount = 0;
		if(obj.owner !is null && (stations.boolean || (!obj.isOrbital && !(obj.isShip && cast<Ship>(obj).isStation))))
			newAmount = obj.owner.getAttribute(attribute.integer);

		if(newAmount != curAmount) {
			obj.modAccelerationBonus(newAmount - curAmount);
			data.store(newAmount);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double curAmount = 0;
		data.retrieve(curAmount);
		
		if(curAmount != 0) {
			obj.modAccelerationBonus(-curAmount);
			curAmount = 0;
			data.store(curAmount);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double curAmount = 0;
		data.retrieve(curAmount);
		file << curAmount;
	}

	void load(any@ data, SaveFile& file) const override {
		double curAmount = 0;
		file >> curAmount;
		data.store(curAmount);
	}
#section all
};

class AttributeFleetEffectiveness : GenericEffect, TriggerableGeneric {
	Document doc("Change the fleet effectiveness based on an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to add as fleet command, can be set to any arbitrary name to be created as a new attribute with starting value 0.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double curAmount = 0;
		data.retrieve(curAmount);

		double newAmount = 0;
		if(obj.owner !is null)
			newAmount = obj.owner.getAttribute(attribute.integer);

		if(newAmount != curAmount) {
			obj.modFleetEffectiveness(newAmount - curAmount);
			data.store(newAmount);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double curAmount = 0;
		data.retrieve(curAmount);
		
		if(curAmount != 0) {
			obj.modFleetEffectiveness(-curAmount);
			curAmount = 0;
			data.store(curAmount);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double curAmount = 0;
		data.retrieve(curAmount);
		file << curAmount;
	}

	void load(any@ data, SaveFile& file) const override {
		double curAmount = 0;
		file >> curAmount;
		data.store(curAmount);
	}
#section all
};

class NoRegionVision : GenericEffect {
	Document doc("When applied to a ship, neither it nor its supports can be seen through region vision, but must be scouted.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).setDisableRegionVision(true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).setDisableRegionVision(false);
	}
#section all
};

class ForceHoldFire : GenericEffect {
	Document doc("When applied to a ship, neither it nor its supports can fire their weapons.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).setHoldFire(true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isShip)
			cast<Ship>(obj).setHoldFire(false);
	}
#section all
};

class CountAsPlanet : GenericEffect {
	Document doc("This object counts as a planet for preventing game loss conditions.");

	void enable(Object& obj, any@ data) const override {
		if(obj.owner !is null)
			obj.owner.TotalPlanets += 1;
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		if(prevOwner !is null)
			prevOwner.TotalPlanets -= 1;
		if(newOwner !is null)
			newOwner.TotalPlanets += 1;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.owner !is null)
			obj.owner.TotalPlanets -= 1;
	}
};

class CannotFireOutsideOwnedSpace : GenericEffect {
	Document doc("When applied to a ship, neither it nor its supports can fire outside owned space.");

#section server
	void enable(Object& obj, any@ data) const override {
		bool disabled = false;
		data.store(disabled);
	}

	void tick(Object& obj, any@ data, double time) const override {
		bool disabled = false;
		data.retrieve(disabled);

		bool shouldDisable = false;
		Region@ reg = obj.region;
		if(reg is null)
			shouldDisable = true;
		else if(reg.PlanetsMask & obj.owner.mask == 0)
			shouldDisable = true;

		if(shouldDisable != disabled) {
			if(obj.isShip)
				cast<Ship>(obj).setHoldFire(shouldDisable);
			data.store(shouldDisable);
		}
	}

	void disable(Object& obj, any@ data) const override {
		bool disabled = false;
		data.retrieve(disabled);

		if(disabled && obj.isShip)
			cast<Ship>(obj).setHoldFire(false);
	}

	void save(any@ data, SaveFile& file) const override {
		bool disabled = false;
		data.retrieve(disabled);
		file << disabled;
	}

	void load(any@ data, SaveFile& file) const override {
		bool disabled = false;
		file >> disabled;
		data.store(disabled);
	}
#section all
};

class AddStatusToOrbitingPlanet : GenericEffect {
	Document doc("Add an instance of a status effect to the planet this is orbiting.");
	Argument status(AT_Status, doc="Type of status effect to create.");
	Argument set_origin_empire(AT_Boolean, "False", doc="Whether to record the empire triggering this hook into the origin empire field of the resulting status. If not set, any hooks that refer to Origin Empire cannot not apply. Status effects with different origin empires set do not collapse into stacks.");
	Argument set_origin_object(AT_Boolean, "False", doc="Whether to record the object triggering this hook into the origin object field of the resulting status. If not set, any hooks that refer to Origin Object cannot not apply. Status effects with different origin objects set do not collapse into stacks.");
	Argument only_owned(AT_Boolean, "False", doc="Only apply the status if the planet is owned by this owner.");
	Argument allow_space(AT_Boolean, "False", doc="Also allow planets owned by space to receive this status.");

#section server
	void enable(Object& obj, any@ data) const override {
		Object@ prevObj;
		data.store(@prevObj);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Object@ prevObj;
		data.retrieve(@prevObj);

		Object@ newObj;
		if(obj.hasOrbit && obj.inOrbit)
			@newObj = obj.getOrbitingAround();
		if(newObj is null && obj.hasMover)
			@newObj = obj.getAroundLockedOrbit();
		if(newObj !is null && only_owned.boolean) {
			Empire@ owner = obj.owner;
			Empire@ otherOwner = newObj.owner;

			if(owner !is otherOwner) {
				if(!allow_space.boolean || otherOwner.valid) {
					@newObj = null;
				}
			}
		}
		if(newObj !is prevObj) {
			Empire@ origEmp = null;
			if(set_origin_empire.boolean)
				@origEmp = obj.owner;
			Object@ origObj = null;
			if(set_origin_object.boolean)
				@origObj = obj;

			if(prevObj !is null)
				prevObj.removeStatusInstanceOfType(status.integer);
			if(newObj !is null)
				newObj.addStatus(status.integer, originEmpire=origEmp, originObject=origObj);
			data.store(@newObj);
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		disable(obj, data);
	}

	void disable(Object& obj, any@ data) const override {
		Object@ prevObj;
		data.retrieve(@prevObj);

		if(prevObj !is null) {
			prevObj.removeStatusInstanceOfType(status.integer);

			@prevObj = null;
			data.store(@prevObj);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		Object@ obj;
		data.retrieve(@obj);
		file << obj;
	}

	void load(any@ data, SaveFile& file) const override {
		Object@ obj;
		file >> obj;
		data.store(@obj);
	}
#section all
};

class MatchOrbitingOwner : GenericEffect {
	Document doc("Match the object's owner to the owner of what it is orbiting.");
	Argument destroy_none(AT_Boolean, doc="Destroy the object if it is not orbiting anything.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Planet@ orbit = cast<Planet>(obj.getOrbitingAround());
		if(orbit is null || !orbit.valid) {
			obj.destroy();
			return;
		}

		if(orbit.owner !is obj.owner)
			@obj.owner = orbit.owner;
	}
#section all
};

class DestroyIfNotAroundOwnedPlanet : GenericEffect {
	Document doc("Destroy the object if the planet it is orbiting around is owned by a different player.");
	Argument do_colonize(AT_Boolean, "False", doc="If moved around a space owned planet, colonize it?");
	Argument destroy_no_orbit(AT_Boolean, "False", doc="Whether to destroy the object if it is not in orbit around a planet.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Planet@ orbit = cast<Planet>(obj.getOrbitingAround());
		if(orbit is null || !orbit.valid) {
			if(destroy_no_orbit.boolean)
				obj.destroy();
			return;
		}

		if(orbit.owner !is obj.owner) {
			if(do_colonize.boolean && !orbit.owner.valid)
				@orbit.owner = obj.owner;
			else
				obj.destroy();
		}
	}
#section all
};

class ProtectsOrbitSiege : GenericEffect {
	Document doc("While in orbit of a planet, the planet is protected from siege.");

#section server
	void enable(Object& obj, any@ data) const override {
		Object@ prevObj;
		data.store(@prevObj);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Object@ prevObj;
		data.retrieve(@prevObj);

		Object@ newObj;
		if(obj.hasOrbit && obj.inOrbit)
			@newObj = obj.getOrbitingAround();
		if(newObj is null && obj.hasMover)
			@newObj = obj.getAroundLockedOrbit();
		if(newObj !is prevObj) {
			if(prevObj !is null)
				prevObj.leaveFromOrbit(obj);
			if(newObj !is null)
				newObj.enterIntoOrbit(obj);
			data.store(@newObj);
		}
	}

	void disable(Object& obj, any@ data) const override {
		Object@ prevObj;
		data.retrieve(@prevObj);

		if(prevObj !is null) {
			prevObj.leaveFromOrbit(obj);

			@prevObj = null;
			data.store(@prevObj);
		}
	}

	void load(any@ data, SaveFile& file) const override {
		Object@ obj;
		if(file < SV_0113) {
			file >> obj;
			@obj = null;
		}
		data.store(@obj);
	}
#section all
};

class CannotUseLabor : GenericEffect {
	Document doc("The object this effect is on cannot use its labor for anything.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(!obj.hasConstruction)
			return;
		obj.canBuildShips = false;
		obj.canBuildAsteroids = false;
		obj.canBuildOrbitals = false;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setDistributedLabor(0);
	}
#section all
};

class AllowConstruction : GenericEffect {
	Document doc("Permits the orbital or ship to construct various things.");
	Argument ships("Ships", AT_Boolean, "False", doc="Allow support and flagship construction.");
	Argument orbs("Orbitals", AT_Boolean, "False", doc="Allow orbital and station construction.");
	Argument asteroids(AT_Boolean, "False", doc="Allow asteroid mining base construction.");
	Argument terraform("Terraforming", AT_Boolean, "False", doc="Allow planet terraforming.");
	Argument supports_only("Supports Only", AT_Boolean, "False", doc="Only allow automatic construction of support ships.");
	Argument enable_fill_from(AT_Boolean, "False", doc="Automatically enable fill from the first time this is added.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(!obj.hasConstruction) {
			if(obj.isOrbital) {
				cast<Orbital>(obj).activateConstruction();
				if(obj.hasLeaderAI && enable_fill_from.boolean)
					obj.allowFillFrom = true;
			}
			else if(obj.isShip)
				cast<Ship>(obj).activateConstruction();
			else
				return;
		}
		obj.canBuildShips = arguments[0].boolean;
		obj.canBuildOrbitals = arguments[1].boolean;
		obj.canBuildAsteroids = arguments[2].boolean;
		obj.canTerraform = arguments[3].boolean;
		obj.canBuildSupports = ships.boolean || supports_only.boolean;

		Region@ reg = obj.region;
		if(reg !is null && (ships.boolean || supports_only.boolean))
			reg.registerShipyard(obj);
	}

	void disable(Object& obj, any@ data) const override {
		if(!obj.hasConstruction)
			return;
		obj.canBuildShips = false;
		obj.canBuildOrbitals = false;
		obj.canBuildAsteroids = false;
		obj.canTerraform = false;
	}
#section all
};

class CopyLaborFromOrbitPlanet : GenericEffect {
	Document doc("While in orbit of a planet, gain the amount of labor from it.");
	Argument factor(AT_Decimal, "1.0", doc="Factor to labor gained.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double prevAmount = 0;
		data.retrieve(prevAmount);

		double newAmount = 0;
		Object@ orbit;
		if(obj.hasOrbit && obj.inOrbit)
			@orbit = obj.getOrbitingAround();
		if(orbit is null && obj.hasMover)
			@orbit = obj.getAroundLockedOrbit();
		if(orbit !is null && orbit.hasConstruction && orbit.owner is obj.owner) {
			if(orbit.flagUsingLabor(obj))
				newAmount = orbit.laborIncome;
			else
				newAmount = 0;
		}

		if(prevAmount != newAmount) {
			obj.modLaborIncome(newAmount - prevAmount);
			data.store(newAmount);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double amount = 0;
		data.retrieve(amount);

		obj.modLaborIncome(-amount);
	}

	void save(any@ data, SaveFile& file) const override {
		double amount = 0;
		data.retrieve(amount);
		file << amount;
	}

	void load(any@ data, SaveFile& file) const override {
		double amount = 0;
		file >> amount;
		data.store(amount);
	}
#section all
};

class ShowRange : GenericEffect, ShowsRange {
	Document doc("If used in certain places, shows a range circle around the object when selected. Supported Places: Orbitals, Resources.");
	Argument range(AT_Decimal, doc="Range to show.");
	Argument color(AT_Color, doc="Color of the range circle.");
	Argument selected_only(AT_Boolean, "False", doc="Only show the range if selected, or when hovered too.");

	Color bColor;

	bool instantiate() override {
		bColor = toColor(color.str);
		return GenericEffect::instantiate();
	}

	bool getShowRange(Object& obj, double& range, Color& color) const override {
		range = this.range.decimal;
		color = bColor;
		return !selected_only.boolean || obj.selected;
	}
};

tidy final class UpdatedValue {
	double value = 0;
	double timer = 0;
}

class ModEfficiencyDistanceToOrbital : GenericEffect {
	Document doc("Modify the efficiency of the fleet based on the distance to the nearest owned orbital of a particular type.");
	Argument orbital(AT_OrbitalModule, doc="Type of orbital module to check for.");
	Argument minrange_efficiency(AT_Decimal, doc="Efficiency at minimum range.");
	Argument maxrange_efficiency(AT_Decimal, doc="Efficiency at maximum range.");
	Argument minrange(AT_Decimal, doc="Minimum range for min efficiency.");
	Argument maxrange(AT_Decimal, doc="Maximum range for max efficiency.");

#section server
	void enable(Object& obj, any@ data) const override {
		UpdatedValue value;
		data.store(@value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		UpdatedValue@ value;
		data.retrieve(@value);

		value.timer -= time;
		if(value.timer <= 0) {
			value.timer = randomd(0.5, 5.0);

			double prevValue = value.value;
			double dist = maxrange.decimal;
			Orbital@ closest = obj.owner.getClosestOrbital(orbital.integer, obj.position);
			if(closest !is null)
				dist = closest.position.distanceTo(obj.position);

			if(dist <= minrange.decimal) {
				value.value = minrange_efficiency.decimal;
			}
			else if(dist >= maxrange.decimal) {
				value.value = maxrange_efficiency.decimal;
			}
			else {
				double pct = (dist - minrange.decimal) / (maxrange.decimal - minrange.decimal);
				value.value = minrange_efficiency.decimal + pct * (maxrange_efficiency.decimal - minrange_efficiency.decimal);
			}

			if(prevValue != value.value)
				obj.modFleetEffectiveness(value.value - prevValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		UpdatedValue@ value;
		data.retrieve(@value);

		if(value.value > 0) {
			obj.modFleetEffectiveness(-value.value);
			value.value = 0;
		}
	}

	void save(any@ data, SaveFile& file) const override {
		UpdatedValue@ value;
		data.retrieve(@value);
		file << value.value;
		file << value.timer;
	}

	void load(any@ data, SaveFile& file) const override {
		UpdatedValue value;
		file >> value.value;
		file >> value.timer;
		data.store(value);
	}
#section all
};

class SpawnFreighters : GenericEffect {
	Document doc("Makes the orbital spawn civilian freighters periodically.");
	Argument rate("Rate", AT_Decimal, "0.0", doc="Base rate per three minutes to spawn freighters.");
	Argument perImport("Per Import", AT_Decimal, "0.0", doc="Additional freighters to spawn per three minutes per import.");
	Argument status(AT_Status, "Happy", doc="Status effect to add when the freighter arrives.");
	Argument duration(AT_Decimal, "180", doc="Duration that the status effect lasts.");
	Argument name(AT_Locale, "#FREIGHTER", doc="Name to give the ship.");
	Argument set_origin_empire(AT_Boolean, "False", doc="Whether to set the origin empire of the status.");
	Argument min_level(AT_Integer, "0", doc="Minimum level for the freighter to go to a planet.");
	Argument visit_hostile(AT_Boolean, "False", doc="Whether to also visit planets of empires you are at war with.");
	Argument skin(AT_Custom, "Freighter", doc="Skin from the shipset to use.");

#section server
	double amount(Object& obj) {
		double amt = arguments[0].decimal;
		double per = arguments[1].decimal;
		if(per != 0)
			amt += per * double(obj.usableResourceCount);
		return amt;
	}

	void enable(Object& obj, any@ data) const override {
		double progress = 0;
		data.store(progress);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double progress = 0;
		data.retrieve(progress);
		progress += amount(obj) * time / 180.0;
		
		while(progress >= 1.0) {
			progress -= 1.0;
			
			ObjectDesc freightDesc;
			freightDesc.type = OT_Freighter;
			freightDesc.name = name.str;
			freightDesc.radius = 4.0;
			freightDesc.delayedCreation = true;
			
			@freightDesc.owner = obj.owner;
			freightDesc.position = obj.position + random3d(obj.radius + 4.5);

			Freighter@ colShip = cast<Freighter>(makeObject(freightDesc));
			colShip.skin = skin.str;
			colShip.StatusId = status.integer;
			colShip.StatusDuration = duration.decimal;
			colShip.SetOrigin = set_origin_empire.boolean;
			colShip.MinLevel = min_level.integer;
			colShip.VisitHostile = visit_hostile.boolean;
			@colShip.Origin = obj;
			colShip.rotation = quaterniond_fromVecToVec(vec3d_front(), colShip.position - obj.position, vec3d_up());
			colShip.maxAcceleration = 2.5 * obj.owner.ModSpeed.value * obj.owner.ColonizerSpeed;
			colShip.Health *= obj.owner.ModHP.value;
			colShip.finalizeCreation();
		}
		
		data.store(progress);
	}

	void save(any@ data, SaveFile& file) const override {
		double progress = 0;
		data.retrieve(progress);
		file << progress;
	}

	void load(any@ data, SaveFile& file) const override {
		double progress = 0;
		file >> progress;
		data.store(progress);
	}
#section all
};


class IsHomeObject : GenericEffect {
	Document doc("This object is considered a home for the race. Only one object is the home object at any time. Is used for things like public works.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.owner.HomeObj is null && obj.valid)
			@obj.owner.HomeObj = obj;
	}
#section all
};

class FTLMaintenance : GenericEffect {
	Document doc("Adds an FTL maintenance cost while this effect is active.");
	Argument amt("Amount", AT_Decimal, doc="FTL maintenance cost.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modFTLUse(arguments[0].decimal);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.modFTLUse(-arguments[0].decimal);
		if(newOwner !is null && newOwner.valid)
			newOwner.modFTLUse(arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modFTLUse(-arguments[0].decimal);
	}
#section all
};

class AddCargoStorage : GenericEffect {
	Document doc("Add an amount of cargo storage to the ship.");
	Argument amount(AT_Decimal, doc="Amount of cargo storage to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isShip && !obj.hasCargo)
			cast<Ship>(obj).activateCargo();
		else if(obj.isOrbital && !obj.hasCargo)
			cast<Orbital>(obj).activateCargo();
		if(obj.hasCargo)
			obj.modCargoStorage(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasCargo)
			obj.modCargoStorage(-amount.decimal);
	}
#section all
}

class AddPlanetGfxFlag : GenericEffect {
	Document doc("Add a particular planet graphics flag while this is active.");
	Argument flag(AT_Custom, doc="Graphics flag to add.");

	uint setFlags = 0;

	bool instantiate() override {
		for(uint i = 0, cnt = PlanetGfxNames.length; i < cnt; ++i) {
			if(PlanetGfxNames[i].equals_nocase(flag.str)) {
				setFlags = 1<<i;
				break;
			}
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setGraphicsFlag(setFlags, true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setGraphicsFlag(setFlags, false);
	}
#section all
}

class ProcessCargo : GenericEffect {
	Document doc("Process cargo at a particular rate, triggering a bonus hook whenever a certain amount of ore has been processed.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to process.");
	Argument rate(AT_Decimal, doc="Rate at which to process the cargo per second.");
	Argument threshold(AT_Decimal, doc="Trigger the hook whenever this much cargo has been processed.");
	Argument hookID(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("ProcessCargo(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Object& obj, any@ data) const override {
		double amt = 0;
		data.store(amt);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double processed = 0;
		data.retrieve(processed);

		if(obj.hasCargo) {
			double consAmt = time * rate.decimal;
			consAmt = obj.consumeCargo(cargo_type.integer, consAmt, partial=true);
			processed += consAmt;
		}

		while(processed >= threshold.decimal) {
			processed -= threshold.decimal;
			if(hook !is null)
				hook.activate(obj, obj.owner);
		}
		data.store(processed);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class AddStatusInitialCombat : GenericEffect {
	Document doc("Add a status whenever first entering combat with a specific duration.");
	Argument status(AT_Status, doc="Type of status to add.");
	Argument duration(AT_SysVar, doc="Duration of the status to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0;
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double timer = 0;
		data.retrieve(timer);

		if(timer <= 0) {
			if(obj.inCombat) {
				timer = 10.0;
				data.store(timer);

				double dur = duration.fromShipEfficiencySum(obj);
				obj.addStatus(status.integer, dur);
			}
		}
		else if(!obj.inCombat) {
			timer -= time;
			data.store(timer);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class ModFleetEffectivenessSubsystem : GenericEffect, TriggerableGeneric {
	Document doc("The fleet this effect is active on gains an increased effectiveness percentage from a subsystem total..");
	Argument amount(AT_SysVar, doc="Percentage of effectiveness to add. eg. 0.15 for +15% effectiveness.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amt = amount.fromShipEfficiencySum(obj);
		if(obj.hasLeaderAI)
			obj.modFleetEffectiveness(amt);
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);

		if(obj.hasLeaderAI)
			obj.modFleetEffectiveness(-amt);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class RestoreShieldsOverTime : GenericEffect {
	Document doc("Restore an amount of shields on the ship per second.");
	Argument amount(AT_Decimal, "0", doc="Amount of shields to restore per second.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of shields to restore per second.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj is null || !obj.isShip)
			return;
		Ship@ ship = cast<Ship>(obj);
		ship.restoreShield((amount.decimal + percentage.decimal * ship.MaxShield) * time);
	}
#section all
};

class LimitStatusStacks : GenericEffect {
	Document doc("Make sure the object never has more than a certain amount of stacks of a type.");
	Argument status(AT_Status, doc="Type of status effect to limit.");
	Argument amount(AT_Integer, doc="Maximum amount of stacks to maintain.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(!obj.hasStatuses)
			return;
		int count = obj.getStatusStackCount(status.integer);
		while(count > amount.integer) {
			obj.removeStatusInstanceOfType(status.integer);
			--count;
		}
	}
#section all
};

class RefillStatusConstruction : GenericEffect {
	Document doc("Make sure the object never has more than a certain amount of stacks of a type.");
	Argument status(AT_Status, doc="Type of status effect to limit.");
	Argument fill_to(AT_Integer, doc="Maximum amount of stacks to maintain.");
	Argument construction(AT_Construction, doc="Type of construction to queue.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Region@ reg = obj.region;
		if(reg is null || reg.ShipyardMask & obj.owner.mask == 0)
			return;

		double timer = 0.0;
		data.retrieve(timer);

		timer -= time;
		if(timer > 0.0) {
			data.store(timer);
			return;
		}

		timer = randomd(15.0, 30.0);
		data.store(timer);

		int count = obj.getStatusStackCount(status.integer);
		if(count >= fill_to.integer)
			return;

		reg.requestConstructionOn(obj, construction.integer);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0;
		file >> timer;
		data.store(timer);
	}
#section all
};

class AddBonusHP : GenericEffect {
	Document doc("Add a percentage bonus health to a ship while this effect is active.");
	Argument amount(AT_Decimal, doc="Percentage of hp to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj is null || !obj.isShip)
			return;

		Ship@ ship = cast<Ship>(obj);
		ship.modHPFactor(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj is null || !obj.isShip)
			return;

		Ship@ ship = cast<Ship>(obj);
		ship.modHPFactor(-amount.decimal);
	}
#section all
};

class AddBonusShield : GenericEffect {
	Document doc("Add a percentage bonus shield to a ship while this effect is active.");
	Argument amount(AT_Decimal, "0", doc="Base amount of shields to add.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of maximum shields to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		const Design@ dsg = null;
		data.store(@dsg);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		const Design@ newDesign = ship.blueprint.design;
		const Design@ oldDesign;
		data.retrieve(@oldDesign);

		if(oldDesign !is newDesign) {
			double given = 0.0;
			if(oldDesign !is null)
				given = amount.decimal + oldDesign.total(SV_ShieldCapacity) * percentage.decimal;
			double newGiven = 0.0;
			if(newDesign !is null)
				newGiven = amount.decimal + newDesign.total(SV_ShieldCapacity) * percentage.decimal;

			if(given != newGiven)
				ship.modBonusShield(newGiven - given);
			data.store(@newDesign);
		}
	}

	void disable(Object& obj, any@ data) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		const Design@ oldDesign;
		data.retrieve(@oldDesign);

		double given = 0.0;
		if(oldDesign !is null)
			given = amount.decimal + oldDesign.total(SV_ShieldCapacity) * percentage.decimal;
		if(given != 0.0) {
			ship.modBonusShield(-given);

			@oldDesign = null;
			data.store(@oldDesign);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		const Design@ dsg;
		data.retrieve(@dsg);
		file << dsg;
	}

	void load(any@ data, SaveFile& file) const override {
		const Design@ dsg;
		if(file >= SV_0157)
			file >> dsg;
		data.store(@dsg);
	}
#section all
};

class AddBonusSupportCapPct : GenericEffect {
	Document doc("Add a percentage bonus support capacity to this fleet.");
	Argument percentage(AT_Decimal, "0", doc="Percentage of maximum support cap to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		const Design@ dsg = null;
		data.store(@dsg);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		const Design@ newDesign = ship.blueprint.design;
		const Design@ oldDesign;
		data.retrieve(@oldDesign);

		if(oldDesign !is newDesign) {
			int given = 0;
			if(oldDesign !is null)
				given = oldDesign.total(SV_SupportCapacity) * percentage.decimal;
			int newGiven = 0;
			if(newDesign !is null)
				newGiven = newDesign.total(SV_SupportCapacity) * percentage.decimal;

			if(given != newGiven)
				ship.modSupplyCapacity(newGiven - given);
			data.store(@newDesign);
		}
	}

	void disable(Object& obj, any@ data) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		const Design@ oldDesign;
		data.retrieve(@oldDesign);

		int given = 0;
		if(oldDesign !is null)
			given = oldDesign.total(SV_SupportCapacity) * percentage.decimal;
		if(given != 0.0) {
			ship.modSupplyCapacity(-given);

			@oldDesign = null;
			data.store(@oldDesign);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		const Design@ dsg;
		data.retrieve(@dsg);
		file << dsg;
	}

	void load(any@ data, SaveFile& file) const override {
		const Design@ dsg;
		file >> dsg;
		data.store(@dsg);
	}
#section all
};

class ExperienceOverTime : GenericEffect {
	Document doc("Grant experience over time to this fleet.");
	Argument amount(AT_Decimal, "0", doc="Amount of experience per second to add.");
	Argument require_friendly_stationed(AT_Boolean, "False", doc="Only grant the experience when stationed in a friendly system.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	bool checkStationed(Object& obj) const {
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		if(obj.inCombat)
			return false;
		if(reg.PlanetsMask & obj.owner.mask == 0)
			return false;
		if(reg.ContestedMask & obj.owner.mask != 0)
			return false;
		if(obj.velocity.lengthSQ >= 0.01)
			return false;
		return true;
	}

	void tick(Object& obj, any@ data, double time) const override {
		double timer = 0.0;
		data.retrieve(timer);

		if(!require_friendly_stationed.boolean || checkStationed(obj))
			timer += time;

		if(timer < 10.0) {
			data.store(timer);
			return;
		}

		timer = 0.0;
		data.store(timer);
		obj.addExperience(10.0 * amount.decimal);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0;
		file >> timer;
		data.store(timer);
	}
#section all
};

class GrantAllVision : GenericEffect {
	Document doc("Grant vision over the system this effect is in to all empires.");

#section server
	void enable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		if(reg !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
				reg.grantVision(getEmpire(i));
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		if(fromRegion !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
				fromRegion.revokeVision(getEmpire(i));
		}
		if(toRegion !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
				toRegion.grantVision(getEmpire(i));
		}
	}

	void disable(Object& obj, any@ data) const override {
		Region@ reg = obj.region;
		if(reg !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
				reg.revokeVision(getEmpire(i));
		}
	}
#section all
};

class AllowFreeRaiding : GenericEffect {
	Document doc("Allow all support ships on this to freely raid even without having ammo stores.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.setFreeRaiding(true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.setFreeRaiding(false);
	}
#section all
};

class AddRaidRange : GenericEffect {
	Document doc("Allow support ships to raid away from the flagship further.");
	Argument amount(AT_Decimal, doc="Amount of extra distance to add. Raiding starts with 1000 range by default.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modRaidRange(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasLeaderAI)
			obj.modRaidRange(-amount.decimal);
	}
#section all
};

class ImproveNativeResourcePressure : GenericEffect {
	Document doc("Improve the amount of pressure the native resource gives.");
	Argument amount(AT_Integer, doc="Amount of extra pressure it should give.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amt = 0.0;

		if(obj.hasResources) {
			auto@ resource = getResource(obj.primaryResourceType);
			if(resource.totalPressure > 0)
				amt = double(amount.integer) / double(resource.totalPressure);
		}

		obj.modResourceEfficiencyBonus(+amt);
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0.0;
		data.retrieve(amt);

		obj.modResourceEfficiencyBonus(-amt);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0.0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0.0;
		file >> amt;
		data.store(amt);
	}
#section all
};

tidy final class SupportList {
	set_int set;
	array<Ship@> list;
};

class AddSupportBonusHP : GenericEffect {
	Document doc("Add a percentage bonus health to all support ships assigned to this.");
	Argument amount(AT_Decimal, doc="Percentage of hp to add.");

#section server
	void enable(Object& obj, any@ data) const override {
		SupportList list;
		data.store(@list);
	}

	void tick(Object& obj, any@ data, double time) const override {
		SupportList@ list;
		data.retrieve(@list);
		if(list is null || !obj.hasLeaderAI)
			return;

		uint supCnt = obj.supportCount;
		if(supCnt != 0) {
			uint offset = randomi(0, supCnt-1);
			for(uint checks = 0; checks < 10; ++checks) {
				Ship@ support = cast<Ship>(obj.supportShip[(offset+checks)%supCnt]);
				if(support is null || list.set.contains(support.id))
					continue;
				support.modHPFactor(+amount.decimal);
				list.list.insertLast(support);
				list.set.insert(support.id);
			}
		}

		uint prevCnt = list.list.length;
		if(prevCnt != 0) {
			uint offset = randomi(0, prevCnt-1);
			for(uint checks = 0; checks < 5 && prevCnt != 0; ++checks) {
				Ship@ support = list.list[(offset+checks)%prevCnt];
				if(support.LeaderID != obj.id) {
					support.modHPFactor(-amount.decimal);

					list.list.removeAt((offset+checks)%prevCnt);
					list.set.erase(support.id);
					--prevCnt;
				}
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		SupportList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		for(int i = list.list.length - 1; i >= 0; --i) {
			Ship@ ship = list.list[i];
			ship.modHPFactor(-amount.decimal);
		}

		list.list.length = 0;
		@list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		SupportList@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		file << list.list.length;
		for(uint i = 0, cnt = list.list.length; i < cnt; ++i)
			file << list.list[i];
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			SupportList list;
			data.store(@list);
			uint cnt = 0;
			file >> cnt;
			list.list.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				file >> list.list[i];
				list.set.insert(list.list[i].id);
			}
		}
	}
#section all
};

class FacesOrbitCenter : GenericEffect {
	Document doc("When applied to objects that have an orbit, they always rotate to face the center of their orbit.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasOrbit)
			obj.orbitSpin(-1.0);
	}

	void onCreate(Orbital& obj, any@ data) const override {
		obj.orbitSpin(-1.0);
	}
#section all
};

class GainSupplyVelocity : GenericEffect {
	Document doc("The ship regains supply based on its current velocity.");
	Argument rate(AT_Decimal, doc="Rate at which supply is regained.");
	Argument velocity_target(AT_Decimal, doc="Target velocity at which the full rate is regained.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;

		double vel = ship.velocity.length;
		if(vel <= 0.01)
			return;

		double regain = rate.decimal * clamp(vel / velocity_target.decimal, 0.0, 1.0) * time;
		ship.refundSupply(regain);
	}
#section all
};

class ApplyStatusRandomPlanets : GenericEffect {
	Document doc("Periodically apply a status to random planets in the system.");
	Argument status(AT_Status, doc="Status type to apply.");
	Argument interval(AT_Decimal, doc="Interval between adding the status.");
	Argument duration(AT_Decimal, doc="Duration of a status instance.");
	Argument allow_self(AT_Boolean, "True", doc="Whether to apply to owned planets.");
	Argument allow_allied(AT_Boolean, "True", doc="Whether to apply to allied planets.");
	Argument allow_war(AT_Boolean, "True", doc="Whether to apply to hostile planets.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return;

		double timer = 0.0;
		data.retrieve(timer);

		timer += time;
		if(timer >= interval.decimal) {
			timer -= interval.decimal;

			uint mask = ~0;
			if(!allow_self.boolean)
				mask &= ~obj.owner.mask;
			if(!allow_allied.boolean)
				mask &= ~obj.owner.ForcedPeaceMask.value;
			if(!allow_war.boolean)
				mask &= ~obj.owner.hostileMask;

			reg.addStatusRandomPlanet(status.integer, duration.decimal, mask);
		}

		data.store(timer);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}
#section all
};

class RandomlyConvertSupports : GenericEffect {
	Document doc("While this has support capacity, convert supports from other empires in this system to join this fleets.");
	Argument interval(AT_Decimal, doc="Interval between adding the status.");
	Argument allow_allied(AT_Boolean, "True", doc="Whether to apply to allied planets.");
	Argument allow_war(AT_Boolean, "True", doc="Whether to apply to hostile planets.");
	Argument interval_margin(AT_Decimal, "0", doc="Randomized margin to add to each interval.");

#section server
	void enable(Object& obj, any@ data) const override {
		double timer = interval.decimal * randomd(1.0-interval_margin.decimal, 1.0+interval_margin.decimal);
		data.store(timer);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Region@ reg = obj.region;
		if(reg is null)
			return;

		int maxSize = -1;
		if(obj.hasLeaderAI) {
			maxSize = obj.SupplyAvailable;
			if(maxSize <= 0)
				return;
		}

		double timer = 0.0;
		data.retrieve(timer);

		timer -= time;
		if(timer <= 0) {
			timer += interval.decimal * randomd(1.0-interval_margin.decimal, 1.0+interval_margin.decimal);

			uint mask = ~0;
			mask &= ~obj.owner.mask;
			if(!allow_allied.boolean)
				mask &= ~obj.owner.ForcedPeaceMask.value;
			if(!allow_war.boolean)
				mask &= ~obj.owner.hostileMask;

			reg.convertRandomSupport(obj, obj.owner, mask, maxSize);
		}

		data.store(timer);
	}

	void save(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		data.retrieve(timer);
		file << timer;
	}

	void load(any@ data, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		data.store(timer);
	}
#section all
};

class ModSupplyConsumeFactor : GenericEffect {
	Document doc("Change the amount of supply consumed by the ship.");
	Argument amount(AT_Decimal, doc="Change to the supply consumption.");

#section server
	void enable(Object& obj, any@ data) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.modSupplyConsumeFactor(amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.modSupplyConsumeFactor(-amount.decimal);
	}
#section all
};

class ModConstructionHPBonus : GenericEffect {
	Document doc("Ships constructed here gain a percentage bonus hp.");
	Argument amount(AT_Decimal, doc="Amount of hp change in percentage.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modConstructionHPBonus(+amount.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasConstruction)
			obj.modConstructionHPBonus(-amount.decimal);
	}
#section all
};

class ModConstructionHPBonusAttribute : GenericEffect {
	Document doc("Ships constructed here gain a percentage bonus hp.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to add as labor, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplier to the attribute.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		Empire@ owner = obj.owner;
		double newValue = 0;
		if(owner !is null)
			newValue = owner.getAttribute(attribute.integer) * multiplier.decimal;
		if(newValue != value && obj.hasConstruction) {
			obj.modConstructionHPBonus(newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);
		if(obj.hasConstruction)
			obj.modConstructionHPBonus(-value);
	}

	void save(any@ data, SaveFile& file) const override {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const override {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class ModObjectStat : GenericEffect {
	Document doc("Modify a stat of the object this is called on while the effect is active.");
	Argument stat(AT_ObjectStat, doc="Stat to modify. Type anything and a new stat with that name will be created. Adding # in the name indicates the stat is integral, adding & in the name indicates the stat is server-only.");
	Argument mode(AT_ObjectStatMode, doc="The way to modify the stat.");
	Argument value(AT_Decimal, doc="The value to modify the stat by.");
	Argument for_empire(AT_Boolean, "False", doc="If set, the stat is modified only inside the triggering empire's context, instead of for the object globally.");

#section server
	const ObjectStatType@ objStat;

	bool instantiate() override {
		if(!GenericEffect::instantiate())
			return false;
		@objStat = getObjectStat(stat.str);
		return true;
	}

	void enable(Object& obj, any@ data) const override {
		if(objStat is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.mod(obj, emp, mode.integer, value.decimal);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(objStat is null)
			return;

		if(for_empire.boolean) {
			objStat.reverse(obj, prevOwner, mode.integer, value.decimal);
			objStat.mod(obj, newOwner, mode.integer, value.decimal);
		}
	}

	void disable(Object& obj, any@ data) const override {
		if(objStat is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.reverse(obj, emp, mode.integer, value.decimal);
	}
#section all
};

class ModRegionStat : GenericEffect {
	Document doc("Modify a stat of the region this is in.");
	Argument stat(AT_ObjectStat, doc="Stat to modify. Type anything and a new stat with that name will be created. Adding # in the name indicates the stat is integral, adding & in the name indicates the stat is server-only.");
	Argument mode(AT_ObjectStatMode, doc="The way to modify the stat.");
	Argument value(AT_Decimal, doc="The value to modify the stat by.");
	Argument for_empire(AT_Boolean, "False", doc="If set, the stat is modified only inside the triggering empire's context, instead of for the object globally.");

#section server
	const ObjectStatType@ objStat;

	bool instantiate() override {
		if(!GenericEffect::instantiate())
			return false;
		@objStat = getObjectStat(stat.str);
		return true;
	}

	void enable(Object& obj, any@ data) const override {
		if(objStat is null)
			return;

		Region@ reg = obj.region;
		if(reg is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.mod(reg, emp, mode.integer, value.decimal);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(objStat is null)
			return;

		if(for_empire.boolean) {
			Region@ reg = obj.region;
			if(reg is null)
				return;

			objStat.reverse(reg, prevOwner, mode.integer, value.decimal);
			objStat.mod(reg, newOwner, mode.integer, value.decimal);
		}
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		if(objStat is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		if(fromRegion !is null)
			objStat.reverse(fromRegion, emp, mode.integer, value.decimal);
		if(toRegion !is null)
			objStat.mod(toRegion, emp, mode.integer, value.decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(objStat is null)
			return;

		Region@ reg = obj.region;
		if(reg is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.reverse(reg, emp, mode.integer, value.decimal);
	}
#section all
};

class GenerateObjectStat : GenericEffect {
	Document doc("Generate an amount of an object stat per second while this effect is active.");
	Argument stat(AT_ObjectStat, doc="Stat to modify. Type anything and a new stat with that name will be created. Adding & in the name indicates the stat is server-only.");
	Argument per_second(AT_Decimal, doc="The value to add to the stat per second.");
	Argument for_empire(AT_Boolean, "False", doc="If set, the stat is modified only inside the triggering empire's context, instead of for the object globally.");

#section server
	const ObjectStatType@ objStat;

	bool instantiate() override {
		if(!GenericEffect::instantiate())
			return false;
		@objStat = getObjectStat(stat.str);
		return true;
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(objStat is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.mod(obj, emp, OSM_Add, per_second.decimal * time);
	}
#section all
};

class GenerateRegionStat : GenericEffect {
	Document doc("Generate an amount of a stat per second on the region this object is in while this effect is active.");
	Argument stat(AT_ObjectStat, doc="Stat to modify. Type anything and a new stat with that name will be created. Adding & in the name indicates the stat is server-only.");
	Argument per_second(AT_Decimal, doc="The value to add to the stat per second.");
	Argument for_empire(AT_Boolean, "False", doc="If set, the stat is modified only inside the triggering empire's context, instead of for the object globally.");

#section server
	const ObjectStatType@ objStat;

	bool instantiate() override {
		if(!GenericEffect::instantiate())
			return false;
		@objStat = getObjectStat(stat.str);
		return true;
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(objStat is null)
			return;

		Region@ reg = obj.region;
		if(reg is null)
			return;

		Empire@ emp = obj.owner;
		if(!for_empire.boolean)
			@emp = null;

		objStat.mod(reg, emp, OSM_Add, per_second.decimal * time);
	}
#section all
};
