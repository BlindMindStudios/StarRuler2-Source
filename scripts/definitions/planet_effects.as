import buildings;
from buildings import IBuildingHook;
import resources;
import util.formatting;
import systems;
import saving;
from statuses import IStatusHook, Status, StatusInstance;
from resources import integerSum, decimalSum;
import planet_types;
import planet_levels;
import generic_effects;
import hook_globals;

//AddPressureCap(<Amount>)
// Give <amount> extra pressure cap on the planet.
class AddPressureCap : GenericEffect, TriggerableGeneric {
	Document doc("Increase the planet's total pressure capacity.");
	Argument amount(AT_Integer, doc="Amount of pressure capacity to add.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(locale::EFFECT_ADDPRESSURECAP, "+"+integerSum(hooks, 0));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressureCapMod(+arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressureCapMod(-arguments[0].integer);
	}
#section all
};

//ModPressureCapMult(<Percentage>)
// Give <Percentage> extra base pressure cap on the planet.
class ModPressureCapMult : GenericEffect, TriggerableGeneric {
	Document doc("Add to the planet's pressure cap multiplier.");
	Argument amount(AT_Decimal, doc="Percentage increase to pressure cap. eg. 0.3 for +30% pressure cap.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressureCapFactor(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressureCapFactor(-arguments[0].decimal);
	}
#section all
};

//ModCivResourceMult(<Resource>, <Percentage>)
// Add <Percentage> to the civilian <Resource> multiplier.
class ModCivResourceMult : GenericEffect, TriggerableGeneric {
	Document doc("Increase the civilian resource production multiplier for a particular type of income.");
	Argument type(AT_TileResource, doc="Which income to modify the multiplier for.");
	Argument amount(AT_Decimal, doc="Percentage increase to the income multiplier. eg. 0.15 for +15% income.");

	bool get_hasEffect() const override {
		return true;
	}

	bool mergesEffect(const GenericEffect@ eff) const {
		return eff.arguments[0].integer == arguments[0].integer;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(format(locale::EFFECT_MODCIVRESOURCE,
					getTileResourceName(arguments[0].integer)), decimalSum(hooks, 1));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modCivResourceMod(arguments[0].integer, +arguments[1].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modCivResourceMod(arguments[0].integer, -arguments[1].decimal);
	}
#section all
};

//ModTerraformCost(<Percentage>)
// Modify the cost to terraform things *with* this planet by <Percentage>.
class ModTerraformCost : GenericEffect, TriggerableGeneric {
	Document doc("Increase the terraform cost multiplier for terraforming other planets with this object.");
	Argument amount(AT_Decimal, doc="Percentage increase to the terraform cost multiplier. eg. -0.5 for -50% terraform cost.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modTerraformCostMod(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modTerraformCostMod(-arguments[0].decimal);
	}
#section all
};

//ModPopulationGrowth(<Percentage>)
// Modify the population growth rate by an amount.
class ModPopulationGrowth : GenericEffect, TriggerableGeneric {
	Document doc("Increase the population growth multiplier on this planet.");
	Argument amount(AT_Decimal, doc="Percentage increase to the population growth multiplier. eg. 0.1 for +10% population growth.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modGrowthRate(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modGrowthRate(-arguments[0].decimal);
	}
#section all
};

//ModTileDevelopRate(<Percentage>)
// Modify the tile development rate by an amount.
class ModTileDevelopRate : GenericEffect, TriggerableGeneric {
	Document doc("Increase the tile development rate multiplier on this planet.");
	Argument amount(AT_Decimal, doc="Percentage increase to the tile development rate multiplier. eg. 0.25 for +25% tile development speed.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modTileDevelopRate(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modTileDevelopRate(-arguments[0].decimal);
	}
#section all
};

//ModBuildingConstructRate(<Percentage>)
// Modify the building construction rate by an amount.
class ModBuildingConstructRate : GenericEffect, TriggerableGeneric {
	Document doc("Increase the building construction speed multiplier on this planet.");
	Argument amount(AT_Decimal, doc="Percentage increase to the builing construction speed multiplier. eg. 0.25 for +25% building construction speed.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBuildingConstructRate(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBuildingConstructRate(-arguments[0].decimal);
	}
#section all
};

//AddBuildingMaintenanceRefund(<Amount>)
// Reduces the total maintenance of buildings by a flat <Amount>.
class AddBuildingMaintenanceRefund : GenericEffect, TriggerableGeneric {
	Document doc("Decrease the total maintenance cost of buildings on this planet by a static amount.");
	Argument amount(AT_Integer, doc="Amount of money to decrease the total maintenance cost by.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		int totalReduction = integerSum(hooks, 0);
		int remaining = 0;

		if(obj.isPlanet && obj.owner is playerEmpire)
			remaining = obj.buildingMaintenance;

		string eff;
		if(totalReduction > 10000000) {
			if(remaining == 0)
				eff = "-"+formatMoney(0);
			else
				eff = "-"+formatMoney(totalReduction + remaining);
		}
		else {
			if(remaining < 0) {
				int used = totalReduction + remaining;
				if(used != 0) {
					eff = format("-$1 [color=#fe4]($2)[/color]",
							formatMoney(used),
							formatMoney(-remaining));
				}
				else {
					eff = format("[color=#fe4]($1)[/color]",
							formatMoney(-remaining));
				}
			}
			else
				eff = "-"+formatMoney(totalReduction);
		}
		return formatPosEffect(locale::EFFECT_BLDMAINTREFUND, eff);
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBuildingMaintenanceRefund(+arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBuildingMaintenanceRefund(-arguments[0].integer);
	}
#section all
};

//AddResourceVanishBonus(<Percentage>)
// Increases the amount of time temporary resources have on this planet by <Percentage>.
class AddResourceVanishBonus : GenericEffect, TriggerableGeneric {
	Document doc("Increases the amount of time temporary resources consumed by this planet stay active.");
	Argument amount(AT_Decimal, doc="Percentage increase to the temporary resource time. eg. 0.4 for +40% resource time.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(locale::EFFECT_VANISHBONUS, decimalSum(hooks, 0), locale::MOD_TIME);
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modResourceVanishBonus(+arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modResourceVanishBonus(-arguments[0].decimal);
	}
#section all
};

//GiveNativePressure(<Amount>)
// Give the consuming planet <Amount> extra pressure in its native resource's type
class GiveNativePressure : GenericEffect {
	Document doc("Give the consuming planet extra pressure of the primary type of pressure its native resource gives.");
	Argument amount(AT_Integer, doc="Amount of extra pressure to give.");
	Argument allow_money(AT_Boolean, "True", doc="Whether to allow giving extra money pressure.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.nativeResourceCount > 0) {
			const ResourceType@ res = getResource(obj.nativeResourceType[0]);
			if(res !is null) {
				int64 resource = -1;
				int best = 0;
				for(uint i = allow_money.boolean ? 0 : 1; i < TR_COUNT; ++i) {
					if(res.tilePressure[i] > best) {
						best = res.tilePressure[i];
						resource = int(i);
					}
				}

				if(resource != -1)
					obj.modPressure(uint(resource), +arguments[0].integer);
				data.store(resource);
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		int64 reso = -1;
		data.retrieve(reso);
		if(reso != -1)
			obj.modPressure(uint(reso), -arguments[0].integer);
	}

	void save(any@ data, SaveFile& file) const override {
		int64 reso = -1;
		data.retrieve(reso);
		file << reso;
	}

	void load(any@ data, SaveFile& file) const override {
		int64 reso = -1;
		file >> reso;
		data.store(reso);
	}
#section all
};

class GiveNativeProduction : GenericEffect {
	Document doc("Give the consuming planet extra production of the primary type of pressure its native resource gives.");
	Argument amount(AT_Integer, doc="Amount of extra production to give.");
	Argument allow_money(AT_Boolean, "True", doc="Whether to allow giving extra money pressure.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.nativeResourceCount > 0) {
			const ResourceType@ res = getResource(obj.nativeResourceType[0]);
			if(res !is null) {
				int64 resource = -1;
				int best = 0;
				for(uint i = allow_money.boolean ? 0 : 1; i < TR_COUNT; ++i) {
					if(res.tilePressure[i] > best) {
						best = res.tilePressure[i];
						resource = int(i);
					}
				}

				if(resource != -1)
					obj.modResource(uint(resource), +arguments[0].integer);
				data.store(resource);
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		int64 reso = -1;
		data.retrieve(reso);
		if(reso != -1)
			obj.modResource(uint(reso), -arguments[0].integer);
	}

	void save(any@ data, SaveFile& file) const override {
		int64 reso = -1;
		data.retrieve(reso);
		file << reso;
	}

	void load(any@ data, SaveFile& file) const override {
		int64 reso = -1;
		file >> reso;
		data.store(reso);
	}
#section all
};

//GiveResourcePressure(<Tile Resource>, <Factor>, <Level Filter> = -1)
// Give the consuming planet <Factor> extra pressure on all its resources.
class GiveExtraResourcePressure : GenericEffect {
	Document doc("Multiply the pressure each of resources consumed by the planet gives of a particular type.");
	Argument type(AT_TileResource, doc="Type of pressure to multiply.");
	Argument factor(AT_Decimal, doc="Percentage increase to the pressure given. eg. 0.2 for a +20% increase in pressure.");
	Argument level_filter(AT_Integer, "-1", doc="If not -1, only resources of the indicated level receive bonus pressure.");
	Argument allow_uniques(AT_Boolean, "True", doc="If set to false, unique resources will not be boosted by this.");

#section server
	void enable(Object& obj, any@ data) const override {
		int reso = 0;
		data.store(reso);
	}

	void tick(Object& obj, any@ data, double time) const override {
		int current = 0;
		data.retrieve(current);

		double newValue = 0;
		int resType = arguments[0].integer;
		double factor = arguments[1].decimal;
		int level = arguments[2].integer;
		for(uint i = 0, cnt = obj.availableResourceCount; i < cnt; ++i) {
			if(!obj.availableResourceUsable[i])
				continue;
			auto@ type = getResource(obj.availableResourceType[i]);
			if(type is null)
				continue;
			if(level != -1 && level != int(type.level))
				continue;
			if(!allow_uniques.boolean && (type.unique || type.rarity == RR_Unique))
				continue;
			newValue += double(type.tilePressure[resType]) * factor;
		}

		int nextValue = int(newValue);
		if(current != nextValue) {
			obj.modPressure(resType, nextValue - current);
			data.store(nextValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int reso = -1;
		data.retrieve(reso);
		if(reso > 0)
			obj.modPressure(arguments[0].integer, -reso);
	}

	void save(any@ data, SaveFile& file) const override {
		int reso = -1;
		data.retrieve(reso);
		file << reso;
	}

	void load(any@ data, SaveFile& file) const override {
		int reso = -1;
		file >> reso;
		data.store(reso);
	}
#section all
};

class AddPressurePerAffinity : GenericEffect {
	Document doc("For every affinity of a particular type, add an amount of pressure.");
	Argument affinity_type(AT_TileResource, doc="Affinity type to check for.");
	Argument pressure_type(AT_TileResource, doc="Type of pressure to generate.");
	Argument amount(AT_Decimal, "1", doc="Amount of pressure to add per affinity.");

#section server
	void enable(Object& obj, any@ data) const override {
		int amt = 0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent) {
			int amt = 0;
			data.retrieve(amt);
			if(amt != 0)
				obj.modPressure(pressure_type.integer, -amt);
		}
	}

	void tick(Object& obj, any@ data, double tick) const override {
		if(obj.hasSurfaceComponent) {
			int amt = 0;
			data.retrieve(amt);

			int newAmt = double(obj.getAffinitiesMatching(affinity_type.integer)) * amount.decimal;
			if(amt != newAmt) {
				obj.modPressure(pressure_type.integer, newAmt - amt);
				data.store(newAmt);
			}
		}
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

//ModColonyShipAccel(<Percentage>)
// Colony ships leaving the consuming planet accelerate <Percentage> faster.
class ModColonyShipAccel : GenericEffect, TriggerableGeneric {
	Document doc("Multiply the acceleration of outgoing colony ships from this planet by a factor.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplier to the acceleration.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPctEffect(locale::PEKELM_EFFECT, decimalSum(hooks, 0));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modColonyShipAccel(arguments[0].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modColonyShipAccel(1.0/arguments[0].decimal);
	}
#section all
};

//ModLoyalty(<Amount>)
// Add <Amount> extra loyalty to the consuming planet.
class ModLoyalty : GenericEffect, TriggerableGeneric {
	Document doc("Increase the loyalty of this planet.");
	Argument amount(AT_Integer, doc="Amount of extra loyalty to give.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(locale::SPICE_EFFECT, "+"+integerSum(hooks, 0));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBaseLoyalty(+arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modBaseLoyalty(-arguments[0].integer);
	}
#section all
};

//AddPressure(<Resource>, <Amount>)
// Adds <Amount> <Resource> pressure.
class AddPressure : GenericEffect, TriggerableGeneric {
	Document doc("Add extra pressure to this planet.");
	Argument type(AT_TileResource, doc="Type of pressure to give.");
	Argument amount(AT_Integer, doc="Amount of pressure.");

	bool get_hasEffect() const override {
		return true;
	}

	bool mergesEffect(const GenericEffect@ eff) const override {
		return eff.arguments[0].integer == arguments[0].integer;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(format(locale::EFFECT_ADDPRESSURE,
					getTileResourceName(arguments[0].integer)), "+"+integerSum(hooks, 1));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressure(arguments[0].integer, +arguments[1].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modPressure(arguments[0].integer, -arguments[1].integer);
	}
#section all
};

//AddResource(<Resource>, <Amount>)
// Add the equivalent of <Amount> pressure in <Resource> production.
class AddResource : GenericEffect, TriggerableGeneric {
	Document doc("Add free resource production equivalent to an amount of pressure to this planet.");
	Argument type(AT_TileResource, doc="Type of resource income.");
	Argument amount(AT_Decimal, doc="Amount of pressure to give the equivalent resource production for.");

	bool get_hasEffect() const override {
		return true;
	}

	bool mergesEffect(const GenericEffect@ eff) const override {
		return eff.arguments[0].integer == arguments[0].integer;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(format(locale::EFFECT_ADDRESOURCE,
					getTileResourceName(arguments[0].integer)), "+"+integerSum(hooks, 1));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, +arguments[1].decimal);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, -arguments[1].decimal);
	}
#section all
};

class AddIncome : GenericEffect, TriggerableGeneric {
	Document doc("Change the planet's income by an amount.");
	Argument amount(AT_Integer, doc="Amount of income to change the planet's income by.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.modIncome(+amount.integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.modIncome(-amount.integer);
	}
#section all
};

//AddResourceEmpireAttribute(<Resource>, <Attribute>)
// Add resource production from an empire attribute.
class AddResourceEmpireAttribute : GenericEffect {
	Document doc("Add free resource production based on an equivalent amount of pressure stored in an empire attribute.");
	Argument type(AT_TileResource, doc="Type of resource income.");
	Argument attribute(AT_EmpAttribute, doc="Empire attribute to take the amount of income from, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplier to amount of resource to generate.");

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
			newValue = owner.getAttribute(arguments[1].integer) * multiplier.decimal;
		if(newValue != value) {
			obj.modResource(arguments[0].integer, newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, -value);
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

class AddPressureEmpireAttribute : GenericEffect {
	Document doc("Add pressure based on an empire attribute.");
	Argument type(AT_TileResource, doc="Type of resource to add pressure for.");
	Argument attribute(AT_EmpAttribute, doc="Empire attribute to take the amount of income from, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplier to amount of resource to generate.");

#section server
	void enable(Object& obj, any@ data) const override {
		int value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		Empire@ owner = obj.owner;
		int newValue = 0;
		if(owner !is null)
			newValue = int(floor(owner.getAttribute(attribute.integer) * multiplier.decimal));
		if(newValue != value) {
			obj.modPressure(type.integer, newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int value = 0;
		data.retrieve(value);
		if(obj.isPlanet)
			obj.modPressure(type.integer, -value);
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

//AddResourceFromGlobal(<Resource>, <Global>, <Factor> = 1.0)
// Add resource production from an empire attribute.
class AddResourceFromGlobal : GenericEffect {
	Document doc("Add free resource production based on an equivalent amount of pressure stored in a global value.");
	Argument type(AT_TileResource, doc="Type of resource income.");
	Argument global(AT_Global, doc="Global variable to take value from.");
	Argument factor(AT_Decimal, "1.0", doc="Multiplication factor to the global's value to give in pressure-equivalent income.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		double newValue = getGlobal(arguments[1].integer).value * arguments[2].decimal;
		if(newValue != value) {
			obj.modResource(arguments[0].integer, newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, -value);
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

//AddResourceFromLevel(<Resource>, <Base> = 0.0, <Factor> = 1.0)
// Add resource production related to the planet level.
class AddResourceFromLevel : GenericEffect {
	Document doc("Add free resource production based on the planet's level.");
	Argument type(AT_TileResource, doc="Type of resource income.");
	Argument base(AT_Decimal, "0.0", doc="Base amount of pressure-equilavent income to give.");
	Argument factor(AT_Decimal, "1.0", doc="Multiplication factor to the planet's level to give in pressure-equivalent income.");

#section server
	void enable(Object& obj, any@ data) const override {
		double value = 0;
		data.store(value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		double value = 0;
		data.retrieve(value);

		double newValue = arguments[1].decimal + arguments[2].decimal * obj.level;
		if(newValue != value) {
			obj.modResource(arguments[0].integer, newValue - value);
			data.store(newValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double value = 0;
		data.retrieve(value);
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, -value);
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

//AddMaxPopulation(<Amount>)
// Add <Amount> maximum population to the planet.
class AddMaxPopulation : GenericEffect, TriggerableGeneric {
	Document doc("Increase the planet's maximum population.");
	Argument amount(AT_Integer, doc="Amount of extra maximum population.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modMaxPopulation(arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modMaxPopulation(-arguments[0].integer);
	}
#section all
};

//AddOverpopulation(<Amount>)
// Add <Amount> overpopulation to the planet.
class AddOverpopulation : GenericEffect, TriggerableGeneric {
	Document doc("Increase the planet's overpopulation.");
	Argument amount(AT_Integer, doc="Amount of extra overpopulation.");

	bool get_hasEffect() const override {
		return true;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(locale::EFFECT_OVERPOPULATION, toString(integerSum(hooks, 0)));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modOverpopulation(+arguments[0].integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet)
			obj.modOverpopulation(-arguments[0].integer);
	}
#section all
};

//PerResourceAddResource(<Planet Resource>, <Amount>, <Tile Resource>)
// Adds <Tile Resource> generation equivalent to <Amount> pressure for every
// <Planet Resource> available on the planet.
class PerResourceAddResource : GenericEffect {
	Document doc("Add free resource income for every planetary resource of a particular type being consumed on the planet.");
	Argument resource(AT_PlanetResource, doc="Type of planetary resource to count.");
	Argument factor(AT_Decimal, doc="Multiplier to the amount of planetary resources to give in pressure-equivalent income.");
	Argument income(AT_TileResource, doc="Type of income to generate.");

	bool get_hasEffect() const override {
		return true;
	}

	bool mergesEffect(const GenericEffect@ eff) const override {
		return eff.arguments[0].integer == arguments[0].integer
			&& arguments[2].integer == arguments[2].integer;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		return formatPosEffect(format(locale::EFFECT_ADDRESOURCE,
					getTileResourceName(arguments[2].integer)),
				"+"+(decimalSum(hooks, 1) * obj.getAvailableResourceAmount(arguments[0].integer)));
	}

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.isPlanet) {
			int64 prev = 0;
			data.retrieve(prev);

			int64 resCnt = obj.getAvailableResourceAmount(arguments[0].integer);
			if(resCnt != prev) {
				data.store(resCnt);
				obj.modResource(arguments[2].integer, double(resCnt - prev) * arguments[1].decimal);
			}
		}
	}

	void enable(Object& obj, any@ data) const override {
		int64 amt = 0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		int64 amt = 0;
		data.retrieve(amt);
		obj.modResource(arguments[2].integer, -double(amt) * arguments[1].decimal);

		amt = 0;
		data.store(amt);
	}

	void save(any@ data, SaveFile& file) const {
		int64 amt = 0;
		data.retrieve(amt);

		file << int(amt);
	}

	void load(any@ data, SaveFile& file) const {
		int amt = 0;
		file >> amt;

		data.store(int64(amt));
	}
#section all
};

//ModExistingResource(<Tile Resource>, <Amount>)
// Adds <Tile Resource> generation equivalent to <Amount> pressure
// if the resource is being produced at all. Resources cannot drop below 0.
class ModExistingResource : GenericEffect {
	Document doc("Modify a particular type of income on this planet, but only if that income is non-zero to begin with.");
	Argument income(AT_TileResource, doc="Type of income to modify.");
	Argument amount(AT_Decimal, doc="Amount of pressure-equivalent income to add or subtract.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.isPlanet) {
			double cur = 0;
			data.retrieve(cur);

			double production = obj.getResourceProduction(arguments[0].integer);
			double next = 0;
			double mod = arguments[1].decimal;
			double net = production - cur;

			if(mod > 0) {
				if(net > 0)
					next = mod;
				else
					next = 0;
			}
			else {
				if(net >= 0)
					next = max(-net, mod);
				else
					next = 0;
			}

			if(next != cur) {
				obj.modResource(arguments[0].integer, next - cur);
				data.store(next);
			}
		}
	}

	void enable(Object& obj, any@ data) const override {
		double amt = 0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		if(obj.isPlanet)
			obj.modResource(arguments[0].integer, -amt);

		amt = 0;
		data.store(amt);
	}

	void save(any@ data, SaveFile& file) const {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class ModExistingPressure : GenericEffect {
	Document doc("Modify a particular type of pressure on this planet, but only if that pressure is non-zero to begin with.");
	Argument income(AT_TileResource, doc="Type of pressure to modify.");
	Argument amount(AT_Decimal, doc="Amount of pressure to add or subtract.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.isPlanet) {
			double cur = 0;
			data.retrieve(cur);

			double production = obj.getResourcePressure(arguments[0].integer);
			double next = 0;
			double mod = arguments[1].decimal;
			double net = production - cur;

			if(mod > 0) {
				if(net > 0)
					next = mod;
				else
					next = 0;
			}
			else {
				if(net >= 0)
					next = max(-net, mod);
				else
					next = 0;
			}

			if(next != cur) {
				obj.modPressure(arguments[0].integer, next - cur);
				data.store(next);
			}
		}
	}

	void enable(Object& obj, any@ data) const override {
		double amt = 0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		if(obj.isPlanet)
			obj.modPressure(arguments[0].integer, -amt);

		amt = 0;
		data.store(amt);
	}

	void save(any@ data, SaveFile& file) const {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

class ModPressurePct : GenericEffect {
	Document doc("Modify the amount of pressure on the planet of a type by a percentage.");
	Argument income(AT_TileResource, doc="Type of pressure to modify.");
	Argument amount(AT_Decimal, doc="Percentage of pressure to add or subtract.");
	Argument min_amount(AT_Integer, "0", doc="Minimum change to pressure.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.isPlanet) {
			double cur = 0;
			data.retrieve(cur);

			double production = obj.getResourcePressure(income.integer);
			double net = production - cur;
			double next = 0;
			double mod = round((production - cur) * amount.decimal);
			if(min_amount.integer < 0 && net != 0)
				mod = min(double(min_amount.integer), mod);
			else if(min_amount.integer > 0 && net != 0)
				mod = max(double(min_amount.integer), mod);

			if(mod > 0) {
				if(net > 0)
					next = mod;
				else
					next = 0;
			}
			else {
				if(net >= 0)
					next = max(-net, mod);
				else
					next = 0;
			}

			if(next != cur) {
				obj.modPressure(income.integer, next - cur);
				data.store(next);
			}
		}
	}

	void enable(Object& obj, any@ data) const override {
		double amt = 0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		if(obj.isPlanet)
			obj.modPressure(income.integer, -amt);

		amt = 0;
		data.store(amt);
	}

	void save(any@ data, SaveFile& file) const {
		double amt = 0;
		data.retrieve(amt);
		file << amt;
	}

	void load(any@ data, SaveFile& file) const {
		double amt = 0;
		file >> amt;
		data.store(amt);
	}
#section all
};

//PerIncomeAddResource(<Tile Resource>, <Amount>, <Tile Resource>)
// Adds <Tile Resource> generation equivalent to <Amount> pressure for every
// <Tile Resource> being generated on the planet.
class PerIncomeAddResource : GenericEffect {
	Document doc("Add free resource income for every resource income of a particular type being generated on this planet.");
	Argument resource(AT_TileResource, doc="Type of income resource to count.");
	Argument factor(AT_Decimal, doc="Multiplier to the amount of income resource already generated to give in pressure-equivalent income.");
	Argument income(AT_TileResource, doc="Type of income to generate.");

#section server
	void enable(Object& obj, any@ data) const override {
		double amt = 0.0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet) {
			double amt = 0.0;
			data.retrieve(amt);
			if(amt != 0.0)
				obj.modResource(arguments[2].integer, -amt);
		}
	}

	void tick(Object& obj, any@ data, double tick) const override {
		if(obj.isPlanet) {
			double amt = 0.0;
			data.retrieve(amt);

			double newAmt = obj.getResourceProduction(arguments[0].integer) * arguments[1].decimal;
			if(amt != newAmt) {
				obj.modResource(arguments[2].integer, newAmt - amt);
				data.store(newAmt);
			}
		}
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

//PerPopulationAddResource(<Tile Resource>, <Amount>)
// Adds <Tile Resource> generation equivalent to <Amount> pressure for every
// population on the planet.
class PerPopulationAddResource : GenericEffect {
	Document doc("Add free resource income based on the planet's current population.");
	Argument factor(AT_Decimal, doc="Multiplier to the planet's current population to give in pressure-equivalent income.");
	Argument income(AT_TileResource, doc="Type of income to generate.");
	Argument overpop_factor(AT_Boolean, "True", doc="Whether to account for the race's OverpopulationBenefitFactor for overpopulation.");
	Argument ignore_first(AT_Decimal, "0", doc="Ignore this amount of population before adding for the remaining population.");

	bool get_hasEffect() const override {
		return true;
	}

	bool mergesEffect(const GenericEffect@ eff) const override {
		return eff.arguments[1].integer == arguments[1].integer;
	}

	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const override {
		if(arguments[0].integer == TR_Money)
			return formatPosEffect(format(locale::EFFECT_ADDRESOURCE,
						getTileResourceName(arguments[0].integer)),
					"+"+formatMoney(decimalSum(hooks, 1) * obj.population * 100.0));
		else
			return formatMagEffect(format(locale::EFFECT_ADDRESOURCE,
						getTileResourceName(arguments[0].integer)),
					(decimalSum(hooks, 1) * obj.population));
	}

#section server
	void enable(Object& obj, any@ data) const override {
		double amt = 0.0;
		data.store(amt);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.isPlanet) {
			double amt = 0.0;
			data.retrieve(amt);
			if(amt != 0.0)
				obj.modResource(arguments[1].integer, -amt);
		}
	}

	void tick(Object& obj, any@ data, double tick) const override {
		if(obj.isPlanet) {
			double amt = 0.0;
			data.retrieve(amt);

			double pop = max(obj.population - ignore_first.decimal, 0.0);
			double newAmt = pop * arguments[0].decimal;
			if(overpop_factor.boolean) {
				double maxPop = obj.maxPopulation;
				if(pop > maxPop)
					newAmt = (maxPop + (pop - maxPop) * obj.owner.OverpopulationBenefitFactor) * arguments[0].decimal;
			}
			if(amt != newAmt) {
				obj.modResource(arguments[1].integer, newAmt - amt);
				data.store(newAmt);
			}
		}
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

//AddDummyResource(<Planet Resource>, <Amount>)
// Add <Amount> <Planet Resource>s solely for the purpose of requirement resolution.
class AddDummyResource : GenericEffect, TriggerableGeneric {
	Document doc("Add a dummy resource of a particular type. Dummy resources are not listed and have no effects except for being usable for planet levelup.");
	Argument resource(AT_PlanetResource, doc="Type of planetary resource to add a dummy of.");
	Argument amount(AT_Integer, "1", doc="Amount of dummy resources of that type to add.");
	Argument base_chain_only(AT_Boolean, "False", doc="Only add this dummy resource if the planet is using the base levelup chain.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(!base_chain_only.boolean || obj.levelChain == baseLevelChain.id)
			obj.modDummyResource(arguments[0].integer, +arguments[1].integer, true);
	}

	void disable(Object& obj, any@ data) const override {
		if(!base_chain_only.boolean || obj.levelChain == baseLevelChain.id)
			obj.modDummyResource(arguments[0].integer, -arguments[1].integer, true);
	}
#section all
};

//ConvertToFTL(<Tile Resource>, <Rate>)
// Convert all <Tile Resource> income into FTL income at <Rate>.
class ConvertToFTL : GenericEffect {
	Document doc("Convert all income of a particular type to FTL generation.");
	Argument type(AT_TileResource, doc="Type of income to convert.");
	Argument factor(AT_Decimal, doc="Every pressure-equivalent income of the given type is converted to this much FTL per second.");

#section server
	void enable(Object& obj, any@ data) const override {
		double current = 0.0;
		data.store(current);

		obj.modCivResourceMod(arguments[0].integer, -1.f);
	}

	void disable(Object& obj, any@ data) const override {
		double current = 0.0;
		data.retrieve(current);

		if(current > 0) {
			if(obj.owner !is null && obj.owner.valid)
				obj.owner.modFTLIncome(-current);
		}

		obj.modCivResourceMod(arguments[0].integer, +1.f);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		double current = 0.0;
		data.retrieve(current);

		if(current > 0) {
			if(prevOwner !is null && prevOwner.valid)
				prevOwner.modFTLIncome(-current);
			if(newOwner !is null && newOwner.valid)
				newOwner.modFTLIncome(+current);
		}
	}

	void tick(Object& obj, any@ data, double time) const override {
		double newIncome = obj.getCivilianProduction(arguments[0].integer) * arguments[1].decimal;
		double current = 0.0;
		data.retrieve(current);

		if(current != newIncome) {
			obj.owner.modFTLIncome(newIncome - current);
			current = newIncome;
			data.store(current);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		double current = 0.0;
		data.retrieve(current);
		file << current;
	}

	void load(any@ data, SaveFile& file) const override {
		double current = 0.0;
		file >> current;
		data.store(current);
	}
#section all
};

//ConvertResource(<Tile Resource>, <Rate>, <Tile Resource>)
// Convert all civilian <Tile Resource> income into <Tile Resource> income at <Rate>.
tidy final class ConvertData {
	double taken = 0.0;
	double given = 0.0;
};
class ConvertResource : GenericEffect {
	Document doc("Convert all civilian income of a particular type to income of a different type.");
	Argument resource(AT_TileResource, doc="Type of income resource to convert.");
	Argument factor(AT_Decimal, doc="Multiplier to the amount of income taken away.");
	Argument income(AT_TileResource, doc="Type of income to generate, after multiplication.");
	Argument maximum_converted(AT_Decimal, "-1", doc="Maximum amount of resource of the first type that is converted.");
	Argument convert_percent(AT_Decimal, "1", doc="Percentage of the original resource to be converted. The rest is left alone.");

#section server
	void enable(Object& obj, any@ data) const override {
		ConvertData info;
		data.store(@info);
	}

	void disable(Object& obj, any@ data) const override {
		ConvertData@ info;
		data.retrieve(@info);

		if(info.given > 0)
			obj.modResource(income.integer, -info.given);
		if(info.taken > 0)
			obj.modResource(resource.integer, +info.taken);
	}

	void tick(Object& obj, any@ data, double time) const override {
		ConvertData@ info;
		data.retrieve(@info);

		//Check rate
		double curProd = obj.getResourceProduction(resource.integer);
		double total = info.taken + curProd;

		double target = total - (total * (1.0 - convert_percent.decimal));
		target = clamp(target, 0.0, total);

		double newTaken = total - target;
		if(maximum_converted.decimal >= 0)
			newTaken = min(newTaken, maximum_converted.decimal);

		if(newTaken != info.taken) {
			obj.modResource(resource.integer, -(newTaken - info.taken));
			info.taken = newTaken;
		}

		double newGiven = newTaken * factor.decimal;
		if(newGiven != info.given) {
			obj.modResource(income.integer, newGiven - info.given);
			info.given = newGiven;
		}
	}

	void save(any@ data, SaveFile& file) const override {
		ConvertData@ info;
		data.retrieve(@info);
		file << info.given;
		file << info.taken;
	}

	void load(any@ data, SaveFile& file) const override {
		ConvertData info;
		if(file >= SV_0079) {
			file >> info.given;
			file >> info.taken;
		}
		else {
			double current = 0;
			double rate = 0;
			file >> current;
			if(file >= SV_0049)
				file >> rate;
		}
		data.store(@info);
	}
#section all
};

//AddToNativeResource(<Hook>(..))
// Adds the inner effect hook to where the native resource is going.
tidy final class AddToNativeData {
	Object@ current;
	any data;
};

tidy final class AddToNativeResource : GenericEffect {
	GenericEffect@ hook;

	Document doc("The inner hook is executed from the context of the native resource's destination, rather than on the planet this effect is active on.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() {
		@hook = cast<GenericEffect>(parseHook(arguments[0].str, "planet_effects::"));
		if(hook is null) {
			error("AddToNativeResource: could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return GenericEffect::instantiate();
	}

	const IResourceHook@ get_displayHook() const override {
		return null;
	}

	const IResourceHook@ get_carriedHook() const override {
		return hook.displayHook;
	}

#section server
	void enable(Object& obj, any@ data) const override {
		AddToNativeData info;
		data.store(@info);
	}

	void disable(Object& obj, any@ data) const override {
		AddToNativeData@ info;
		data.retrieve(@info);

		if(info !is null && info.current !is null)
			hook.disable(info.current, info.data);

		@info = null;
		data.store(@info);
	}

	void tick(Object& obj, any@ data, double time) const {
		AddToNativeData@ info;
		data.retrieve(@info);

		//Make sure the hook is applied to the right object
		Object@ target;
		if(obj.hasResources)
			@target = obj.nativeResourceDestination[0];
		if(target is null)
			@target = obj;
		if(target !is info.current) {
			if(info.current !is null)
				hook.disable(info.current, info.data);
			if(target !is null)
				hook.enable(target, info.data);
			@info.current = target;
		}

		if(info.current !is null)
			hook.tick(info.current, info.data, time);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		AddToNativeData@ info;
		data.retrieve(@info);

		if(info.current !is null)
			hook.ownerChange(info.current, info.data, prevOwner, newOwner);
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {
		AddToNativeData@ info;
		data.retrieve(@info);

		if(info.current !is null)
			hook.regionChange(info.current, info.data, fromRegion, toRegion);
	}

	void save(any@ data, SaveFile& file) const {
		AddToNativeData@ info;
		data.retrieve(@info);

		if(info is null){ 
			Object@ tmp;
			file << tmp;
		}
		else {
			file << info.current;
			if(info.current !is null)
				hook.save(info.data, file);
		}
	}

	void load(any@ data, SaveFile& file) const {
		AddToNativeData info;
		data.store(@info);

		file >> info.current;
		if(info.current !is null)
			hook.load(info.data, file);
	}
#section all
};

//AddRandomPressure(<Amount>, <Change Timer>, <Buildup Time>)
// Adds <Amount> random pressure that changes every <Change Timer>.
tidy final class PressureData {
	int type;
	int amount;
	double timer;
};

class AddRandomPressure : GenericEffect {
	Document doc("Add randomized pressure to the planet that changes to a different type periodically.");
	Argument amount(AT_Integer, doc="Amount of randomized pressure to give.");
	Argument change_timer(AT_Decimal, doc="Time interval between when the pressure changes types.");
	Argument buildup_time(AT_Decimal, doc="Time period over which the pressure builds up from 0 to its maximum value.");

#section server
	void enable(Object& obj, any@ data) const override {
		PressureData info;
		info.type = randomi(0, TR_COUNT-1);
		info.amount = 0;
		info.timer = 0.0;

		data.store(@info);
	}

	void disable(Object& obj, any@ data) const override {
		PressureData@ info;
		data.retrieve(@info);

		if(info.type != -1)
			obj.modPressure(info.type, -info.amount);

		@info = null;
		data.store(null);
	}

	void tick(Object& obj, any@ data, double time) const {
		PressureData@ info;
		data.retrieve(@info);

		int maxAmount = arguments[0].integer;
		if(info.amount < maxAmount) {
			//Pressure buildup
			int prevAmt = info.amount;
			info.timer += time;
			info.amount = clamp(round(info.timer / arguments[2].decimal * double(maxAmount)), 0, maxAmount);

			if(info.amount != prevAmt)
				obj.modPressure(info.type, info.amount - prevAmt);
			if(info.amount == maxAmount)
				info.timer = 0.0;
		}
		else {
			//Pressure change
			info.timer += time;
			if(info.timer >= arguments[1].decimal) {
				obj.modPressure(info.type, -info.amount);
				info.type = randomi(0, TR_COUNT-1);
				obj.modPressure(info.type, +info.amount);
				info.timer = 0.0;
			}
		}
	}

	void save(any@ data, SaveFile& file) const {
		PressureData@ info;
		data.retrieve(@info);

		if(info !is null) {
			file << info.type;
			file << info.amount;
			file << info.timer;
		}
		else {
			int tmp = -1;
			file << tmp;
			tmp = 0;
			file << tmp;
			double tmpd = 0.0;
			file << tmpd;
		}
	}

	void load(any@ data, SaveFile& file) const {
		PressureData info;
		file >> info.type;
		file >> info.amount;
		file >> info.timer;

		data.store(@info);
	}
#section all
};

class ReplacesCities : GenericEffect, TriggerableGeneric {
	Document doc("The planet this effect is active on needs to construct fewer civilian cities than normal, this effect replaces some.");
	Argument amount(AT_Integer, "1", doc="How many cities this replaces.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.modCityCount(+amount.integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.modCityCount(-amount.integer);
	}

	//This hook, when used on a building, takes effect immediately, to prevent 'temporary' cities from being built
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {
		enable(obj, bld.data[hookIndex]);
	}

	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {
		disable(obj, bld.data[hookIndex]);
	}

	void complete(Object& obj, SurfaceBuilding@ bld) const {
		//Already enabled in startConstruction
	}
#section all
};

class MakeQuarantined : GenericEffect, TriggerableGeneric {
	Document doc("The planet this is active on is marked 'quarantined', which prevents it from importing, exporting or being colonized.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setQuarantined(true);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setQuarantined(false);
	}
#section all
};

class NoNeedPopulationForLevel : GenericEffect {
	Document doc("The planet this is on does not require extra population to level.");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setNeedsPopulationForLevel(false);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.setNeedsPopulationForLevel(true);
	}
#section all
};

class PopulationCannotDie : GenericEffect {
	Document doc("The population on this planet cannot die.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasSurfaceComponent) {
			double curPop = obj.population;
			double intPop = ceil(curPop);
			if(curPop != intPop)
				obj.addPopulation(intPop - curPop);
		}
	}
#section all
};

class AlwaysAtMaxPopulation : GenericEffect {
	Document doc("The population of the planet is always at the maximum value.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasSurfaceComponent) {
			double diff = obj.maxPopulation - obj.population;
			if(diff != 0)
				obj.addPopulation(diff);
		}
	}
#section all
};

class ForceIntegerPopulation : GenericEffect {
	Document doc("The population on this planet dies in integer increments.");

#section server
	void enable(Object& obj, any@ data) const override {
		double popDmg = 0;
		if(obj.hasSurfaceComponent) {
			double curPop = obj.population;
			double targPop = floor(curPop);
			if(curPop != targPop) {
				popDmg = curPop - targPop;
				obj.addPopulation(targPop - curPop);
			}
		}
		data.store(popDmg);
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasSurfaceComponent) {
			double popDmg = 0;
			data.retrieve(popDmg);

			double curPop = obj.population;
			double targPop = max(ceil(curPop - popDmg), 1.0);
			if(curPop != targPop) {
				popDmg += targPop - curPop;
				obj.addPopulation(targPop - curPop);
				data.store(popDmg);
			}
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

class ProduceAllPressure : GenericEffect {
	Document doc("Produce all pressure of a particular type directly as resource production.");
	Argument type(AT_TileResource, doc="Type of pressure to produce.");
	Argument factor(AT_Decimal, "1", doc="Factor of pressure to produce.");

#section server
	void enable(Object& obj, any@ data) const override {
		double prod = 0;
		data.store(prod);
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(!obj.hasSurfaceComponent)
			return;

		double prod = 0;
		data.retrieve(prod);

		double newProd = obj.getResourcePressure(type.integer) * factor.decimal;
		if(newProd != prod && obj.hasSurfaceComponent) {
			obj.modResource(type.integer, newProd - prod);
			data.store(newProd);
		}
	}

	void disable(Object& obj, any@ data) const override {
		double prod = 0;
		data.retrieve(prod);

		if(prod != 0 && obj.hasSurfaceComponent)
			obj.modResource(type.integer, -prod);
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

class SetMaxLevel : GenericEffect {
	Document doc("Set the planet's maximum level, it cannot level up beyond this.");
	Argument level(AT_Integer, doc="Maximum level to set");

#section server
	void enable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.maxLevel = level.integer;
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasSurfaceComponent)
			obj.maxLevel = level.integer;
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.maxLevel = -1;
	}
#section all
};

class SetMaxLevelStatusCount : GenericEffect {
	Document doc("Set the planet's maximum level based on how many statuses it has.");
	Argument base(AT_Integer, doc="Base level.");
	Argument status(AT_Status, doc="Status to count.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if(obj.hasSurfaceComponent)
			obj.maxLevel = base.integer + obj.getStatusStackCountAny(status.integer);
	}

	void disable(Object& obj, any@ data) const override {
		if(obj.hasSurfaceComponent)
			obj.maxLevel = -1;
	}
#section all
};

class ForceUsefulSurface : GenericEffect {
	Document doc("Force the planet to have a percentage of useful region on its surface.");
	Argument percent(AT_Decimal, doc="Percent of the surface that needs to be useful.");
	Argument biome(AT_PlanetBiome, doc="Biome to fill the planet with to ensure surface.");

#section server
	void enable(Object& cur, any@ data) const override {
		if(cur is null || !cur.hasSurfaceComponent)
			return;
		auto@ type = getBiome(biome.str);
		if(type !is null)
			cur.forceUsefulSurface(percent.decimal, type.id);
		else
			print("No such biome: "+biome.str);
	}
#section all
};

class SetOrbitSpin : GenericEffect {
	Document doc("Force the planet to have a particular spin.");
	Argument spin(AT_Range, doc="Time for the planet to complete one spin.");

#section server
	void enable(Object& cur, any@ data) const override {
		if(cur.hasOrbit)
			cur.orbitSpin(spin.fromRange(), true);
	}
#section all
};

class ChangeNativeResourceTo : GenericEffect {
	Document doc("Change the type of native resource for the duration of this effect.");
	Argument resource(AT_PlanetResource, doc="Type of planetary resource to convert to.");

#section server
	void enable(Object& cur, any@ data) const override {
		uint prevType = cur.primaryResourceType;
		data.store(prevType);

		cur.terraformTo(resource.integer);
	}

	void disable(Object& cur, any@ data) const override {
		uint prevType = uint(-1);
		data.retrieve(prevType);

		cur.terraformTo(prevType);
	}

	void save(any@ data, SaveFile& file) const override {
		uint reso = uint(-1);
		data.retrieve(reso);
		file << reso;
	}

	void load(any@ data, SaveFile& file) const override {
		uint reso = uint(-1);
		file >> reso;
		data.store(reso);
	}
#section all
};

class ChangeLevelChain : GenericEffect {
	Document doc("Change the planet's level chain and requirements.");
	Argument chain(AT_Custom, doc="Chain to change to.");
	Argument base_only(AT_Boolean, "True", doc="Only apply this chain if the chain was base before.");

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
	void enable(Object& cur, any@ data) const override {
		if(cur.hasSurfaceComponent) {
			if(base_only.boolean) {
				if(cur.levelChain == 0)
					cur.setLevelChain(chainId);
			}
			else {
				if(cur.levelChain != chainId)
					cur.setLevelChain(chainId);
			}
		}
	}

	void tick(Object& cur, any@ data, double time) const override {
		enable(cur, data);
	}

	void disable(Object& cur, any@ data) const override {
		if(cur.hasSurfaceComponent) {
			if(cur.levelChain == chainId)
				cur.setLevelChain(0);
		}
	}
#section all
};

class PlanetLevelIncomeMod : GenericEffect {
	Document doc("Modify the planet's income based on its level.");
	Argument level0(AT_Integer, doc="Income modification at level 0.");
	Argument level1(AT_Integer, doc="Income modification at level 1.");
	Argument step(AT_Integer, doc="Step that is added at every level afterwards.");

#section server
	void enable(Object& obj, any@ data) const override {
		int mod = 0;
		data.store(mod);
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(!obj.hasSurfaceComponent)
			return;
		int prevMod = 0;
		data.retrieve(prevMod);

		int newMod = 0;
		uint curLevel = obj.level;
		uint chain = obj.levelChain;
		if(curLevel == 0) {
			newMod = level0.integer;
		}
		else {
			double curPop = obj.population;
			auto@ lv0 = getPlanetLevel(chain, 0);
			auto@ lv1 = getPlanetLevel(chain, 1);

			if(lv0 !is null && lv1 !is null) {
				double startPop = lv0.population;
				double endPop = lv1.population;

				newMod = level0.integer + double(level1.integer - level0.integer) * clamp(curPop - startPop, 0.0, (endPop - startPop)) / (endPop - startPop);

				for(uint i = 2; i <= curLevel; ++i) {
					auto@ lv = getPlanetLevel(chain, i);
					if(lv is null)
						break;
					startPop = endPop;
					endPop = lv.population;

					if(startPop != endPop)
						newMod += double(step.integer) * clamp(curPop - startPop, 0.0, (endPop - startPop)) / (endPop - startPop);
				}
			}
		}

		if(newMod != prevMod) {
			obj.modIncome(newMod - prevMod);
			data.store(newMod);
		}
	}

	void disable(Object& obj, any@ data) const override {
		int mod = 0;
		data.retrieve(mod);
		if(mod != 0 && obj.hasSurfaceComponent)
			obj.modIncome(-mod);
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

class ProduceAsteroidPressure : GenericEffect {
	Document doc("Produce the pressure given by asteroids on this plaent.");
	Argument factor(AT_Decimal, "1.0", doc="Multiplication to the pressure in production.");

#section server
	void enable(Object& obj, any@ data) const override {
		array<double> production(TR_COUNT, 0.0);
		data.store(@production);
	}

	void tick(Object& obj, any@ data, double time) const override {
		array<double>@ production;
		data.retrieve(@production);

		for(uint i = 0; i < TR_COUNT; ++i) {
			double prevProd = production[i];
			double newProd = obj.pressureFromAsteroids(i) * factor.decimal;
			if(prevProd != newProd) {
				obj.modResource(i, newProd - prevProd);
				production[i] = newProd;
			}
		}
	}

	void disable(Object& obj, any@ data) const override {
		array<double>@ production;
		data.retrieve(@production);

		for(uint i = 0; i < TR_COUNT; ++i) {
			obj.modResource(i, -production[i]);
			production[i] = 0.0;
		}
	}

	void save(any@ data, SaveFile& file) const override {
		array<double>@ production;
		data.retrieve(@production);
		for(uint i = 0; i < TR_COUNT; ++i)
			file << production[i];
	}

	void load(any@ data, SaveFile& file) const override {
		array<double> production(TR_COUNT, 0.0);
		data.store(@production);
		for(uint i = 0; i < TR_COUNT; ++i)
			file >> production[i];
	}
#section all
};
