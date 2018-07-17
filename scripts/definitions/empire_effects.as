#include "include/resource_constants.as"
import generic_hooks;
import repeat_hooks;
#section server
import bool getCheatsEverOn() from "cheats";
import oddity_navigation;
from influence_global import getLastInfluenceVoteId, getInfluenceVotesSince, disableBuyCardsTargetedAgainst, createInfluenceEffect, dismissEffect;
#section all

class GiveAchievement : EmpireEffect, TriggerableGeneric {
	Document doc("Unlocks an achievement when the effect is enabled.");
	Argument achievement(AT_Custom, doc="ID of the achievement to achieve.");

#section server
	void enable(Empire& owner, any@ data) const override {
		if(!owner.valid || getCheatsEverOn())
			return;
		if(owner is playerEmpire)
			unlockAchievement(achievement.str);
		if(mpServer && owner.player !is null)
			clientAchievement(owner.player, achievement.str);
	}
#section all
};

class GivePoints : EmpireEffect, TriggerableGeneric {
	Document doc("When the effect is first activated, permanently increase the empire's points.");
	Argument points(AT_Integer, doc="Amount of points.");
	
#section server
	void enable(Empire& owner, any@ data) const override {
		owner.points += arguments[0].integer;
	}
#section all
};

class AddDefenseReserve : EmpireEffect {
	Document doc("Add to the maximum defense reserve amount.");
	Argument amount(AT_Decimal, doc="Amount of defense reserve to add.");
	
#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modDefenseStorage(amount.decimal);
	}
	
	void disable(Empire& owner, any@ data) const override {
		owner.modDefenseStorage(-amount.decimal);
	}
#section all
};

class MultBorrowPenalty : EmpireEffect {
	Document doc("Multiply the penalty added to borrow money.");
	Argument multiply(AT_Decimal, doc="Multiply by this amount.");
	
#section server
	void enable(Empire& owner, any@ data) const override {
		owner.multBorrowPenalty(multiply.decimal);
	}
	
	void disable(Empire& owner, any@ data) const override {
		if(multiply.decimal != 0)
			owner.multBorrowPenalty(1.0 / multiply.decimal);
	}
#section all
};

class WorthPoints : EmpireEffect {
	Document doc("While this effect is active, the empire's points are increased.");
	Argument points(AT_Integer, doc="Amount of points.");
	
#section server
	void enable(Empire& owner, any@ data) const override {
		owner.points += arguments[0].integer;
	}
	
	void disable(Empire& owner, any@ data) const override {
		owner.points -= arguments[0].integer;
	}
#section all
};

class GiveGlobalVision : EmpireEffect, TriggerableGeneric {
	Document doc("Grants vision over every object in the universe while active.");

#section server
	void tick(Empire& owner, any@ data, double time) const override {
		owner.visionMask = ~0;
	}

	void disable(Empire& owner, any@ data) const override {
		owner.visionMask = owner.mask;
	}
#section all
};

class GiveGlobalTrade : EmpireEffect, TriggerableGeneric {
	Document doc("Allows planetary resource trade from anywhere to anywhere while active.");

#section server
	void tick(Empire& owner, any@ data, double time) const override {
		owner.GlobalTrade = true;
	}
	
	void disable(Empire& owner, any@ data) {
		owner.GlobalTrade = false;
	}
#section all
};

class ModGlobalLoyalty : EmpireEffect, TriggerableGeneric {
	Document doc("Modifies the loyalty of all planets owned by this effect's owner.");
	Argument amount(AT_Integer, doc="How much to add or subtract from the loyalty value.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.GlobalLoyalty += arguments[0].integer;
	}

	void disable(Empire& owner, any@ data) const override {
		owner.GlobalLoyalty -= arguments[0].integer;
	}
#section all
};

class AddFTLIncome : EmpireEffect, TriggerableGeneric {
	Document doc("Increase FTL income per second.");
	Argument rate(AT_Decimal, doc="Rate per second to add.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modFTLIncome(+arguments[0].decimal);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modFTLIncome(-arguments[0].decimal);
	}
#section all
};

class AddFTLStorage : EmpireEffect, TriggerableGeneric {
	Document doc("Increase FTL storage cap.");
	Argument amount(AT_Integer, doc="Amount of extra storage to add.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modFTLCapacity(+arguments[0].integer);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modFTLCapacity(-arguments[0].integer);
	}
#section all
};

class AddEnergyIncome : EmpireEffect, TriggerableGeneric {
	Document doc("Increase energy income per second.");
	Argument amount(AT_Decimal, doc="Amount of energy per second to add, before storage penalty.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modEnergyIncome(+amount.decimal);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modEnergyIncome(-amount.decimal);
	}
#section all
};

class AddResearchIncome : EmpireEffect, TriggerableGeneric {
	Document doc("Increase research income per second.");
	Argument amount(AT_Decimal, doc="Amount of research generation per second to add, before generation penalties.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modResearchRate(+amount.decimal);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modResearchRate(-amount.decimal);
	}
#section all
};

class AddMoneyIncome : EmpireEffect, TriggerableGeneric {
	Document doc("Increase money income per cycle.");
	Argument amount(AT_Integer, doc="Amount of income per cycle to add.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modTotalBudget(amount.integer, MoT_Misc);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modTotalBudget(-amount.integer, MoT_Misc);
	}
#section all
};

class AddInfluenceStake : EmpireEffect, TriggerableGeneric {
	Document doc("Increase the empire's influence stake, increasing its influence generation.");
	Argument amount(AT_Integer, doc="Amount of pressure-equivalent influence stake to gain while this is active.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modInfluenceIncome(+amount.integer);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modInfluenceIncome(-amount.integer);
	}
#section all
};

class ModInfluenceFactor : EmpireEffect, TriggerableGeneric {
	Document doc("Change the influence generation rate factor by a certain amount.");
	Argument amount(AT_Decimal, doc="Amount added to percentage influence generation. For example, 0.25 increases influence generation by 25% of base.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modInfluenceFactor(+amount.decimal);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modInfluenceFactor(-amount.decimal);
	}
#section all
};

class PeriodicInfluenceCard : EmpireEffect {
	Document doc("Grant one of the specified influence cards every specified interval.");
	Argument cardIDs("Cards", AT_Custom, doc="A list of possible influence cards to grant, separated by :.");
	Argument timer(AT_Decimal, "60", doc="Amount of seconds between influence card generation.");
	Argument quality(AT_Integer, "0", doc="Extra quality to add to the generated cards.");

#section server
	array<const InfluenceCardType@> cards;

	bool instantiate() override {
		array<string>@ args = arguments[0].str.split(":");
		for(uint i = 0, cnt = args.length; i < cnt; ++i) {
			auto@ card = getInfluenceCardType(args[i]);
			if(card is null) {
				error("PeriodicInfluenceCrad() Error: could not find influence card "+args[i]);
			}
			else {
				cards.insertLast(card);
			}
		}
		return EmpireEffect::instantiate();
	}

	void enable(Empire& owner, any@ data) const override {
		double timer = 0.0;
		data.store(timer);
	}

	void tick(Empire& owner, any@ data, double tick) const override {
		double timer = 0.0;
		data.retrieve(timer);

		timer += tick;
		if(timer >= arguments[1].decimal) {
			auto@ type = cards[randomi(0, cards.length-1)];
			auto@ newCard = type.generate();
			newCard.quality = clamp(arguments[2].integer, type.minQuality, type.maxQuality);
			cast<InfluenceStore>(owner.InfluenceManager).addCard(owner, newCard);

			timer -= arguments[1].decimal;
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

class ModEmpireAttribute : EmpireEffect, TriggerableGeneric {
	Document doc("Modify the value of an empire attribute while this effect is active.");
	Argument attribute(AT_EmpAttribute, doc="Which attribute to alter.");
	Argument mode(AT_AttributeMode, doc="How to modify the attribute.");
	Argument value(AT_Decimal, doc="Value to modify the attribute by.");

#section server
	void enable(Empire& emp, any@ data) const override {
		if(emp !is null && emp.valid)
			emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, arguments[2].decimal);
	}

	void disable(Empire& emp, any@ data) const override {
		if(emp !is null && emp.valid) {
			if(arguments[1].integer == AC_Multiply)
				emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, 1.0/arguments[2].decimal);
			else
				emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, -1.0*arguments[2].decimal);
		}
	}
#section all
};

class UnlockTagWhileActive : EmpireEffect {
	Document doc("While this effect is active, the specified unlock tag is marked as unlocked on the empire. When the effect stops, the unlocking is revoked.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to unlock. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.setTagUnlocked(tag.integer, true);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.setTagUnlocked(tag.integer, false);
	}
#section all
};

class AddGlobalDefense : EmpireEffect, TriggerableGeneric {
	Document doc("Add an amount of pressure-equivalent defense generation to the empire's global defense pool.");
	Argument amount(AT_Decimal, doc="Amount of defense generation to add to the global pool.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.modDefenseRate(+amount.decimal * DEFENSE_LABOR_PM / 60.0);
	}

	void disable(Empire& owner, any@ data) const override {
		owner.modDefenseRate(-amount.decimal * DEFENSE_LABOR_PM / 60.0);
	}
#section all
};

class ReduceEmpireInfluencePerFlagshipSize : EmpireEffect {
	Document doc("While this is active, the empire's influence stake is reduced by 1 for every specified amount of size worth of flagships.");
	Argument per_size(AT_Decimal, "100", doc="Reduces influence generation by 1 stake for every flagship size multiple of this.");
	Argument count_orbitals(AT_Boolean, "False", doc="Whether to count orbital size.");

#section server
	void enable(Empire& owner, any@ data) const override {
		int amount = 0;
		data.store(amount);
	}

	void disable(Empire& owner, any@ data) const override {
		int amount = 0;
		data.retrieve(amount);

		owner.modInfluenceIncome(+amount);
	}

	void tick(Empire& owner, any@ data, double time) const override {
		int amount = 0;
		data.retrieve(amount);

		double totalSize = 0;
		for(uint i = 0, cnt = owner.fleetCount; i < cnt; ++i) {
			Ship@ obj = cast<Ship>(owner.fleets[i]);
			if(obj is null)
				continue;
			auto@ bp = obj.blueprint;
			if(bp is null)
				continue;
			auto@ dsg = bp.design;
			if(dsg is null)
				continue;
			if(!count_orbitals.boolean && dsg.hasTag(ST_Station))
				continue;
			totalSize += dsg.size;
		}

		int newAmount = floor(totalSize / per_size.decimal);
		if(amount != newAmount) {
			owner.modInfluenceIncome(amount - newAmount);
			data.store(newAmount);
		}
	}

	void save(any@ data, SaveFile& file) const override {
		int amount = 0;
		data.retrieve(amount);
		file << amount;
	}

	void load(any@ data, SaveFile& file) const override {
		int amount = 0;
		file >> amount;
		data.store(amount);
	}
#section all
};

class ModEmpireInfluenceGenMilitaryRank : EmpireEffect {
	Document doc("Modify influence generation percent of the empire based on their military rank.");
	Argument min_pct(AT_Decimal, "The empire with the lowest military gets this modification on their influence generation. Empires in between are interpolated.");
	Argument max_pct(AT_Decimal, "The empire with the highest military gets this modification on their influence generation. Empires in between are interpolated.");

#section server
	void enable(Empire& owner, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void disable(Empire& owner, any@ data) const override {
		double amount = 0;
		data.retrieve(amount);

		owner.modInfluenceFactor(-amount);
	}

	void tick(Empire& owner, any@ data, double time) const override {
		double amount = 0;
		data.retrieve(amount);

		uint total = 0;
		uint rank = 0;
		double myMil = owner.TotalMilitary;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(other is owner)
				continue;

			++total;
			if(other.TotalMilitary > myMil)
				++rank;
		}
		if(total == 0)
			total = 1;

		double newAmount = (1.0 - (double(rank) / double(total))) * (max_pct.decimal - min_pct.decimal) + min_pct.decimal;
		if(newAmount != amount) {
			owner.modInfluenceFactor(newAmount - amount);
			data.store(newAmount);
		}
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

class GiveVisionOverPeaceful : EmpireEffect {
	Document doc("Give the empire vision over all empires that it is not currently at war with, even if they are not allies.");
	Argument limit_contact(AT_Boolean, "True", doc="Whether to only give vision over empires we have contact with.");

#section server
	void disable(Empire& owner, any@ data) const override {
		owner.visionMask = owner.mask;
	}

	void tick(Empire& owner, any@ data, double time) const override {
		uint mask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.valid || !other.major)
				continue;
			if(other.isHostile(owner))
				continue;
			if(limit_contact.boolean && owner.ContactMask.value & other.mask == 0)
				continue;
			mask |= other.mask;
		}
		owner.visionMask |= mask;
	}
#section all
};

class ObjectStatusList {
	double timer;
	set_int set;
	array<Object@> list;
	uint prevCount = 0;
};

class AddStatusOwnedPlanets : EmpireEffect {
	Document doc("Add a status effect to all owned planets.");
	Argument status(AT_Status, doc="Type of status to add to planets.");
	Argument level_requirement(AT_Integer, "0", doc="Minimum level of planets that get the status.");

#section server
	void enable(Empire& emp, any@ data) const override {
		ObjectStatusList list;
		data.store(@list);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		list.timer -= time;
		if(list.timer >= 0 && emp.planetCount == list.prevCount)
			return;
		uint minLevel = level_requirement.integer;
		list.timer = 5.0;
		list.prevCount = emp.planetCount;

		int maxMods = 25;

		//Check old
		for(int i = list.list.length - 1; i >= 0 && maxMods > 0; --i) {
			Object@ pl = list.list[i];
			if(pl.level < minLevel || pl.owner !is emp || !pl.valid) {
				pl.removeStatusInstanceOfType(status.integer);
				list.list.removeAt(uint(i));
				list.set.erase(pl.id);
				--maxMods;
			}
		}

		//Check new
		if(maxMods > 0) {
			DataList@ objs = emp.getPlanets();
			Object@ obj;
			while(receive(objs, obj)) {
				if(maxMods <= 0)
					continue;
				Planet@ pl = cast<Planet>(obj);
				if(!list.set.contains(pl.id) && pl.level >= minLevel) {
					pl.addStatus(status.integer);
					list.list.insertLast(pl);
					list.set.insert(pl.id);
					--maxMods;
				}
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		for(int i = list.list.length - 1; i >= 0; --i) {
			Object@ pl = list.list[i];
			pl.removeStatusInstanceOfType(status.integer);
		}

		list.list.length = 0;
		@list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		file << list.timer;
		file << list.list.length;
		for(uint i = 0, cnt = list.list.length; i < cnt; ++i)
			file << list.list[i];
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			ObjectStatusList list;
			data.store(@list);
			file >> list.timer;
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

class AddStatusOwnedFleets : EmpireEffect {
	Document doc("Add a status effect to all owned fleets.");
	Argument status(AT_Status, doc="Type of status to add to fleets.");
	Argument give_to_stations(AT_Boolean, "True", doc="Whether to also give the status to designed stations.");
	Argument give_to_ships(AT_Boolean, "True", doc="Whether to give the status to movable flagships.");

#section server
	void enable(Empire& emp, any@ data) const override {
		ObjectStatusList list;
		data.store(@list);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		list.timer -= time;
		if(list.timer >= 0 && emp.fleetCount == list.prevCount)
			return;
		list.timer = 5.0;
		list.prevCount = emp.fleetCount;

		int maxMods = 25;

		//Check old
		for(int i = list.list.length - 1; i >= 0 && maxMods > 0; --i) {
			Object@ flt = list.list[i];
			if(flt.owner !is emp || !flt.valid) {
				flt.removeStatusInstanceOfType(status.integer);
				list.list.removeAt(uint(i));
				list.set.erase(flt.id);
				--maxMods;
			}
		}

		//Check new
		if(maxMods > 0) {
			if(give_to_ships.boolean) {
				DataList@ objs = emp.getFlagships();
				Object@ obj;
				while(receive(objs, obj)) {
					if(maxMods <= 0)
						continue;
					if(!list.set.contains(obj.id)) {
						obj.addStatus(status.integer);
						list.list.insertLast(obj);
						list.set.insert(obj.id);
						--maxMods;
					}
				}
			}

			if(give_to_stations.boolean) {
				DataList@ objs = emp.getStations();
				Object@ obj;
				while(receive(objs, obj)) {
					if(maxMods <= 0)
						continue;
					if(!list.set.contains(obj.id)) {
						obj.addStatus(status.integer);
						list.list.insertLast(obj);
						list.set.insert(obj.id);
						--maxMods;
					}
				}
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		for(int i = list.list.length - 1; i >= 0; --i) {
			Object@ obj = list.list[i];
			obj.removeStatusInstanceOfType(status.integer);
		}

		list.list.length = 0;
		@list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		file << list.timer;
		file << list.list.length;
		for(uint i = 0, cnt = list.list.length; i < cnt; ++i)
			file << list.list[i];
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			ObjectStatusList list;
			data.store(@list);
			file >> list.timer;
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

tidy final class TriggerNewFleets : EmpireEffect {
	BonusEffect@ hook;

	Document doc("Trigger a hook on any newly constructed fleet.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");
	Argument give_to_stations(AT_Boolean, "True", doc="Whether to also give the status to designed stations.");
	Argument give_to_ships(AT_Boolean, "True", doc="Whether to give the status to movable flagships.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerNewFleets(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return EmpireEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		ObjectStatusList list;
		data.store(@list);

		if(give_to_ships.boolean) {
			DataList@ objs = emp.getFlagships();
			Object@ obj;
			while(receive(objs, obj)) {
				list.list.insertLast(obj);
				list.set.insert(obj.id);
			}
		}

		if(give_to_stations.boolean) {
			DataList@ objs = emp.getStations();
			Object@ obj;
			while(receive(objs, obj)) {
				list.list.insertLast(obj);
				list.set.insert(obj.id);
			}
		}
	}

	void tick(Empire& emp, any@ data, double time) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		list.timer -= time;
		if(list.timer >= 0 && emp.fleetCount == list.prevCount)
			return;
		list.timer = 5.0;
		list.prevCount = emp.fleetCount;
		int maxMods = 25;

		//Check old
		for(int i = list.list.length - 1; i >= 0 && maxMods > 0; --i) {
			Object@ flt = list.list[i];
			if(flt.owner !is emp || !flt.valid) {
				list.list.removeAt(uint(i));
				list.set.erase(flt.id);
				--maxMods;
			}
		}

		//Check new
		if(maxMods > 0) {
			if(give_to_ships.boolean) {
				DataList@ objs = emp.getFlagships();
				Object@ obj;
				while(receive(objs, obj)) {
					if(maxMods <= 0)
						continue;
					if(!list.set.contains(obj.id)) {
						hook.activate(obj, obj.owner);
						list.list.insertLast(obj);
						list.set.insert(obj.id);
						--maxMods;
					}
				}
			}

			if(give_to_stations.boolean) {
				DataList@ objs = emp.getStations();
				Object@ obj;
				while(receive(objs, obj)) {
					if(maxMods <= 0)
						continue;
					if(!list.set.contains(obj.id)) {
						hook.activate(obj, obj.owner);
						list.list.insertLast(obj);
						list.set.insert(obj.id);
						--maxMods;
					}
				}
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		ObjectStatusList@ list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		ObjectStatusList@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		file << list.timer;
		file << list.list.length;
		for(uint i = 0, cnt = list.list.length; i < cnt; ++i)
			file << list.list[i];
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			ObjectStatusList list;
			data.store(@list);
			file >> list.timer;
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

class SystemData {
	uint index = 0;
	set_int set;
};

class AddRegionStatusOwnedSystems : EmpireEffect {
	Document doc("Add a region status to all owned systems.");
	Argument status(AT_Status, doc="Type of status to add to regions.");
	Argument allow_neutral(AT_Boolean, "True", doc="Whether to count systems that also have planets from neutral empires as owned.");
	Argument allow_enemy(AT_Boolean, "False", doc="Whether to count systems that also have planets from enemy empires as owned.");
	Argument bind_empire(AT_Boolean, "True", doc="Whether to only add to objects of this empire, or of all empires.");

#section server
	void enable(Empire& emp, any@ data) const override {
		SystemData list;
		data.store(@list);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		list.index = (list.index+1) % systemCount;
		auto@ sys = getSystem(list.index);

		Empire@ bindEmp;
		if(bind_empire.boolean)
			@bindEmp = emp;

		bool applicable = false;
		uint plMask = sys.object.PlanetsMask;
		if(plMask & emp.mask != 0) {
			applicable = true;
			if(plMask != emp.mask && !allow_neutral.boolean)
				applicable = false;
			else if(plMask & emp.hostileMask != 0 && !allow_enemy.boolean)
				applicable = false;
		}

		if(list.set.contains(sys.object.id)) {
			if(!applicable) {
				sys.object.removeRegionStatus(bindEmp, status.integer);
				list.set.erase(sys.object.id);
			}
		}
		else {
			if(applicable) {
				sys.object.addRegionStatus(bindEmp, status.integer);
				list.set.insert(sys.object.id);
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		Empire@ bindEmp;
		if(bind_empire.boolean)
			@bindEmp = emp;

		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			if(list.set.contains(sys.object.id))
				sys.object.removeRegionStatus(bindEmp, status.integer);
		}

		@list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		uint cnt = list.set.size();
		file << cnt;
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			if(list.set.contains(sys.object.id))
				file << sys.object.id;
		}
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			SystemData list;
			data.store(@list);

			if(file >= SV_0111) {
				uint cnt = 0;
				file >> cnt;
				for(uint i = 0; i < cnt; ++i) {
					int id = 0;
					file >> id;
					list.set.insert(id);
				}
			}
			else {
				for(uint i = 0, cnt = 100; i < cnt; ++i)
					file.readBit();
			}
		}
	}
#section all
};

class GrantAllFleetVision : EmpireEffect {
	Document doc("Grant vision of all fleets anywhere.");
	Argument system_space(AT_Boolean, "True", doc="Grant vision over fleets currently in system space.");
	Argument deep_space(AT_Boolean, "True", doc="Grant vision over fleets currently in deep space.");
	Argument in_ftl(AT_Boolean, "True", doc="Grant vision over fleets currently in FTL.");
	Argument flagships(AT_Boolean, "True", doc="Grant vision over flagships.");
	Argument stations(AT_Boolean, "False", doc="Grant vision over stations.");
	Argument require_status(AT_Status, EMPTY_DEFAULT, doc="Status effect to require.");
	Argument require_heading_here(AT_Boolean, "False", doc="Only grant vision if the fleet is currently heading towards the system this effect is active in.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		Region@ toSystem;
		if(require_heading_here.boolean) {
			@toSystem = obj.region;
			if(toSystem is null)
				return;
		}
		grant(obj.owner, toSystem);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		grant(emp, null);
	}

	void grant(Empire& emp, Region@ toSystem) {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(emp.visionMask & other.mask != 0)
				continue;
			other.giveFleetVisionTo(emp, system_space.boolean, deep_space.boolean, in_ftl.boolean, flagships.boolean, stations.boolean, require_status.integer, toSystem);
		}
	}
#section all
};

class GrantAllOddityGateVision : EmpireEffect {
	Document doc("Grant vision over everything classified as an oddity gate: slipstreams, wormholes.");

#section server
	void tick(Empire& emp, any@ data, double time) const override {
		grantOddityGateVision(emp);
	}
#section all
};

class TiedSubsystemUnlock : EmpireEffect {
	Document doc("Unlock a particular subsystem, but only while this effect is active.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to unlock.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to track the unlock.");

#section server
	void enable(Empire& emp, any@ data) const override {
		emp.modAttribute(attribute.integer, AC_Add, 1.0);
		if(emp.getAttribute(attribute.integer) > 0.9999)
			emp.setUnlocked(getSubsystemDef(subsystem.integer), true);
	}

	void disable(Empire& emp, any@ data) const override {
		emp.modAttribute(attribute.integer, AC_Add, -1.0);
		if(emp.getAttribute(attribute.integer) <= 0.00001)
			emp.setUnlocked(getSubsystemDef(subsystem.integer), false);
	}

#section all
};

tidy final class OnFriendlyEmpires : EmpireEffect {
	EmpireEffect@ eff;

	Document doc("Apply an effect to all empires the owner is not at war with.");
	Argument hookID("Hook", AT_Hook, "empire_effects::EmpireEffect");
	Argument apply_on_owner(AT_Boolean, "True", doc="Whether to also apply the effect on the owner, or just others.");

	bool instantiate() override {
		@eff = cast<EmpireEffect>(parseHook(hookID.str, "empire_effects::", required=false));
		if(eff is null) {
			error("OnFriendlyEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return EmpireEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		array<any@> arr(getEmpireCount());
		data.store(@arr);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		if(arr is null)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			bool should = true;
			if(other is emp && !apply_on_owner.boolean)
				should = false;
			else if(emp.isHostile(other))
				should = false;

			if(should && arr[i] is null) {
				@arr[i] = any();
				eff.enable(other, arr[i]);
			}
			else if(!should && arr[i] !is null) {
				eff.disable(other, arr[i]);
				@arr[i] = null;
			}

			if(should)
				eff.tick(other, arr[i], time);
		}
	}

	void disable(Empire& emp, any@ data) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		for(uint i = 0, cnt = arr.length; i < cnt; ++i) {
			if(arr[i] is null)
				continue;

			Empire@ other = getEmpire(i);
			eff.disable(other, arr[i]);
		}

		@arr = null;
		data.store(@arr);
	}

	void save(any@ data, SaveFile& file) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			if(arr[i] !is null) {
				file.write1();
				eff.save(arr[i], file);
			}
			else {
				file.write0();
			}
		}
	}

	void load(any@ data, SaveFile& file) const override {
		array<any@> arr(getEmpireCount());
		data.store(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			if(file.readBit()) {
				@arr[i] = any();
				eff.load(arr[i], file);
			}
			else {
				@arr[i] = null;
			}
		}
	}
#section all
};

class EnableModifier : EmpireEffect {
	Document doc("Enable a particular design modifier while this effect is active.");
	Argument modifier(AT_Custom, doc="Modifier spec.");

	TechAddModifier@ mod;

	bool instantiate() override {
		string funcName;
		array<string> argNames;
		if(!funcSplit(arguments[0].str, funcName, argNames)) {
			error("Invalid modifier: "+arguments[0].str);
			return false;
		}

		@mod = parseModifier(funcName);
		if(mod is null) {
			error("Invalid modifier: "+arguments[0].str);
			return false;
		}

		mod.arguments = argNames;
		return GenericEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		array<uint> ids;
		data.store(@ids);

		if(emp.valid)
			mod.apply(emp, ids);
	}

	void disable(Empire& emp, any@ data) const override {
		array<uint>@ ids;
		data.retrieve(@ids);

		if(ids !is null && emp.valid)
			mod.remove(emp, ids);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		array<uint>@ ids;
		data.retrieve(@ids);

		if(prevOwner !is null && prevOwner.valid)
			mod.remove(prevOwner, ids);
		if(newOwner !is null && newOwner.valid)
			mod.apply(newOwner, ids);
	}

	void save(any@ data, SaveFile& file) const override {
		array<uint>@ ids;
		data.retrieve(@ids);

		uint cnt = ids.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << ids[i];
	}

	void load(any@ data, SaveFile& file) const override {
		array<uint> ids;
		data.store(@ids);

		uint cnt = 0;
		file >> cnt;
		ids.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> ids[i];
	}
#section all
};

class GiveVisionCombatSystems : EmpireEffect {
	Document doc("Give the empire vision over all systems where combat is taking place.");

#section server
	void enable(Empire& emp, any@ data) const override {
		SystemData list;
		data.store(@list);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		for(uint steps = 0; steps < 15; ++steps) {
			list.index = (list.index+1) % systemCount;
			auto@ sys = getSystem(list.index);

			bool applicable = sys.object.ContestedMask != 0;
			if(list.set.contains(sys.object.id)) {
				if(!applicable) {
					sys.object.revokeVision(emp);
					list.set.erase(sys.object.id);
				}
			}
			else {
				if(applicable) {
					sys.object.grantVision(emp);
					list.set.insert(sys.object.id);
				}
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null)
			return;

		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			if(list.set.contains(sys.object.id))
				sys.object.revokeVision(emp);
		}

		@list = null;
		data.store(@list);
	}

	void save(any@ data, SaveFile& file) const override {
		SystemData@ list;
		data.retrieve(@list);
		if(list is null) {
			file.write0();
			return;
		}
		file.write1();
		uint cnt = list.set.size();
		file << cnt;
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			if(list.set.contains(sys.object.id))
				file << sys.object.id;
		}
	}

	void load(any@ data, SaveFile& file) const override {
		if(file.readBit()) {
			SystemData list;
			data.store(@list);

			uint cnt = 0;
			file >> cnt;
			for(uint i = 0; i < cnt; ++i) {
				int id = 0;
				file >> id;
				list.set.insert(id);
			}
		}
	}
#section all
};

tidy final class OnEmpireAttributeGTE : EmpireEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when an empire attribute is at least the specified value.");
	Argument attribute(AT_EmpAttribute);
	Argument value(AT_Decimal);
	Argument function(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnEnable(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void tick(Empire& owner, any@ data, double time) const override {
		if(!owner.valid)
			return;
		if(owner.getAttribute(attribute.integer) >= value.decimal)
			hook.activate(null, owner);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return;
		if(owner.getAttribute(attribute.integer) >= value.decimal)
			hook.activate(obj, owner);
	}
#section all
};

tidy final class OnEmpireAttributeLT : EmpireEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when an empire attribute is lower than the specified value.");
	Argument attribute(AT_EmpAttribute);
	Argument value(AT_Decimal);
	Argument function(AT_Hook, "bonus_effects::BonusEffect");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnEnable(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void tick(Empire& owner, any@ data, double time) const override {
		if(!owner.valid)
			return;
		if(owner.getAttribute(attribute.integer) < value.decimal)
			hook.activate(null, owner);
	}

	void tick(Object& obj, any@ data, double time) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return;
		if(owner.getAttribute(attribute.integer) < value.decimal)
			hook.activate(obj, owner);
	}
#section all
};

tidy final class PeriodicData {
	double timer = 0;
	uint count = 0;
};
tidy final class TriggerPeriodic : EmpireEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect every set interval.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");
	Argument interval(AT_Decimal, "60", doc="Interval in seconds between triggers.");
	Argument max_triggers(AT_Integer, "-1", doc="Maximum amount of times to trigger the hook before stopping. -1 indicates no maximum triggers.");
	Argument trigger_immediate(AT_Boolean, "False", doc="Whether to first trigger the effect right away before starting the timer.");
	Argument random_margin(AT_Decimal, "0", doc="Random margin for the interval.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerPeriodic(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	double getTimer() const {
		double timer = interval.decimal;
		double margin = random_margin.decimal;
		if(margin != 0)
			timer *= randomd(1.0 - margin, 1.0 + margin);
		return timer;
	}

	void enable(Object& obj, any@ data) const override {
		PeriodicData@ dat;
		if(!data.retrieve(@dat)) {
			@dat = PeriodicData();
			dat.timer = getTimer();
			data.store(@dat);
		}

		if(trigger_immediate.boolean) {
			if(hook !is null)
				hook.activate(obj, obj.owner);
			dat.count += 1;
		}
	}

	void tick(Object& obj, any@ data, double tick) const override {
		PeriodicData@ dat;
		data.retrieve(@dat);

		dat.timer -= tick;
		if(dat.timer <= 0.0) {
			if(max_triggers.integer < 0 || dat.count < uint(max_triggers.integer)) {
				if(hook !is null)
					hook.activate(obj, obj.owner);
				dat.count += 1;
			}
			dat.timer += getTimer();
		}
	}

	void enable(Empire& emp, any@ data) const override {
		PeriodicData@ dat;
		if(!data.retrieve(@dat)) {
			@dat = PeriodicData();
			dat.timer = getTimer();
			data.store(@dat);
		}

		if(trigger_immediate.boolean) {
			if(hook !is null)
				hook.activate(null, emp);
			dat.count += 1;
		}
	}

	void tick(Empire& emp, any@ data, double tick) const override {
		PeriodicData@ dat;
		data.retrieve(@dat);

		dat.timer -= tick;
		if(dat.timer <= 0.0) {
			if(max_triggers.integer < 0 || dat.count < uint(max_triggers.integer)) {
				if(hook !is null)
					hook.activate(null, emp);
				dat.count += 1;
			}
			dat.timer += getTimer();
		}
	}

	void save(any@ data, SaveFile& file) const override {
		PeriodicData@ dat;
		data.retrieve(@dat);

		file << dat.timer;
		file << dat.count;
	}

	void load(any@ data, SaveFile& file) const override {
		PeriodicData dat;
		data.store(@dat);

		file >> dat.timer;
		if(file >= SV_0096)
			file >> dat.count;
	}
#section all
};

tidy final class TriggerOnAttributeIncrease : EmpireEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect whenever an empire attribute increases by a certain threshold.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect");
	Argument threshold(AT_Decimal, "1.0", doc="Trigger the effect every time the empire attribute has increased by this amount.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerOnAttributeIncrease(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return EmpireEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		double amount = emp.getAttribute(attribute.integer);
		data.store(amount);
	}

	void tick(Object& obj, any@ data, double tick) const override {
		double curAmount = 0;
		data.retrieve(curAmount);

		double newAmount = 0;
		if(obj.owner !is null)
			newAmount = obj.owner.getAttribute(attribute.integer);

		while(newAmount > curAmount + threshold.decimal) {
			if(hook !is null)
				hook.activate(obj, obj.owner);
			curAmount += threshold.decimal;
		}

		data.store(curAmount);
	}

	void tick(Empire& emp, any@ data, double tick) const override {
		double curAmount = 0;
		data.retrieve(curAmount);

		double newAmount = emp.getAttribute(attribute.integer);

		while(newAmount > curAmount + threshold.decimal) {
			if(hook !is null)
				hook.activate(null, emp);
			curAmount += threshold.decimal;
		}

		data.store(curAmount);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		double amount = 0;
		if(newOwner !is null)
			amount = newOwner.getAttribute(attribute.integer);
		data.store(amount);
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


tidy final class TriggerOnVoteStart : EmpireEffect {
	Document doc("Triggers the inner effect whenever someone starts a vote.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect");
	Argument on_self(AT_Boolean, "False", doc="Whether to count votes started by the empire itself.");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerOnVoteStart(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		int last = getLastInfluenceVoteId();
		data.store(last);
	}

	void tick(Object& obj, any@ data, double time) const override {
		tick(obj, obj.owner, data, time);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		tick(null, emp, data, time);
	}

	void tick(Object@ obj, Empire& emp, any@ data, double time) const {
		int last = -1;
		data.retrieve(last);

		auto@ list = getInfluenceVotesSince(last);
		if(list is null)
			return;

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ vote = list[i];

			if(!vote.startedBy.valid)
				continue;
			if(!on_self.boolean && vote.startedBy is emp)
				continue;
			if(emp.ContactMask & vote.startedBy.mask == 0)
				continue;

			if(hook !is null)
				hook.activate(obj, emp);
			last = max(last, int(vote.id));
		}

		data.store(last);
	}

	void save(any@ data, SaveFile& file) const override {
		int last = -1;
		data.retrieve(last);
		file << last;
	}

	void load(any@ data, SaveFile& file) const override {
		int last = -1;
		file >> last;
		data.store(last);
	}
#section all
};

class AddStatusHomeworld : EmpireEffect {
	Document doc("Add a status to the empire's homeworld.");
	Argument status(AT_Status, doc="Type of status to add.");

#section server
	void enable(Empire& emp, any@ data) const override {
		Object@ hw;
		data.store(@hw);

		tick(emp, data, 0.0);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		Object@ current;
		data.retrieve(@current);

		Object@ next;
		if(emp.Homeworld !is null) {
			@next = emp.Homeworld;
			if(next is null || !next.valid)
				@next = null;
		}
		if(next is null && emp.HomeObj !is null) {
			@next = emp.HomeObj;
			if(next is null || !next.valid)
				@next = null;
		}

		if(next !is current) {
			if(current !is null)
				current.removeStatusInstanceOfType(status.integer);
			if(next !is null)
				next.addStatus(status.integer);
			data.store(@next);
		}
	}

	void disable(Empire& emp, any@ data) const override {
		Object@ hw;
		data.retrieve(@hw);

		if(hw !is null)
			hw.removeStatusInstanceOfType(status.integer);
	}

	void save(any@ data, SaveFile& file) const override {
		Object@ hw;
		data.retrieve(@hw);
		file << hw;
	}

	void load(any@ data, SaveFile& file) const override {
		Object@ hw;
		file >> hw;
		data.store(@hw);
	}
#section all
};

class GainResearchWhenAttributeUps : EmpireEffect {
	Document doc("Gain research points whenever a particular attribute is increased.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check for.");
	Argument multiply(AT_Decimal, "1", doc="Multiplier to the attribute's value.");
	Argument modified(AT_Boolean, "True", doc="Whether the amount of points gained should be reduced by the research efficiency rate. That is, the more research an empire has done, the fewer points it will get in the future.");
	Argument penalized(AT_Boolean, "True", doc="Whether the points generated in this way are recorded as total research done for the purposes of research efficiency penalty.");

#section server
	void enable(Empire& emp, any@ data) const override {
		double amount = emp.getAttribute(attribute.integer);
		data.store(amount);
	}

	void tick(Empire& emp, any@ data, double tick) const override {
		double curAmount = 0;
		data.retrieve(curAmount);

		double newAmount = emp.getAttribute(attribute.integer);
		if(newAmount > curAmount) {
			emp.generatePoints(multiply.decimal * (newAmount - curAmount), modified.boolean, penalized.boolean);
			data.store(newAmount);
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		double amount = 0;
		if(newOwner !is null)
			amount = newOwner.getAttribute(attribute.integer);
		data.store(amount);
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

tidy final class OnEmpires : EmpireEffect {
	EmpireEffect@ eff;

	Document doc("Apply the effect to a subset of all empires.");
	Argument hookID("Hook", AT_Hook, "empire_effects::EmpireEffect");
	Argument on_allied(AT_Boolean, "True", doc="Apply the effect on any empires that are allied to the owner.");
	Argument on_enemy(AT_Boolean, "True", doc="Apply the effect on any empires that are at war with the owner.");
	Argument on_owner(AT_Boolean, "True", doc="Whether to also apply the effect on the owner, or just others.");

	bool instantiate() override {
		@eff = cast<EmpireEffect>(parseHook(hookID.str, "empire_effects::", required=false));
		if(eff is null) {
			error("OnEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return EmpireEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		array<any@> arr(getEmpireCount());
		data.store(@arr);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		if(arr is null)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			bool should = true;
			if(other is emp && !on_owner.boolean)
				should = false;
			else if(emp.isHostile(other) && !on_enemy.boolean)
				should = false;
			else if(emp.ForcedPeaceMask & other.mask != 0 && !on_allied.boolean)
				should = false;

			if(should && arr[i] is null) {
				@arr[i] = any();
				eff.enable(other, arr[i]);
			}
			else if(!should && arr[i] !is null) {
				eff.disable(other, arr[i]);
				@arr[i] = null;
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		for(uint i = 0, cnt = arr.length; i < cnt; ++i) {
			if(arr[i] is null)
				continue;

			Empire@ other = getEmpire(i);
			eff.disable(other, arr[i]);
		}

		@arr = null;
		data.store(@arr);
	}

	void save(any@ data, SaveFile& file) const override {
		array<any@>@ arr;
		data.retrieve(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			if(arr[i] !is null) {
				file.write1();
				eff.save(arr[i], file);
			}
			else {
				file.write0();
			}
		}
	}

	void load(any@ data, SaveFile& file) const override {
		array<any@> arr(getEmpireCount());
		data.store(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);

			if(file.readBit()) {
				@arr[i] = any();
				eff.load(arr[i], file);
			}
			else {
				@arr[i] = null;
			}
		}
	}
#section all
};

class RemoveInfluenceCardStackTargeted : EmpireEffect {
	Document doc("Automatically disables people from buying any cards on the influence stack targeted against this empire.");

#section server
	void tick(Empire& emp, any@ data, double time) const override {
		disableBuyCardsTargetedAgainst(emp);
	}
#section all
};

class MaintainInfluenceEffect : EmpireEffect {
	Document doc("While this effect is active, an influence effect is maintained on the empire.");
	Argument type(AT_InfluenceEffect, doc="Type of effect to start.");

#section server
	void enable(Empire& emp, any@ data) const override {
		int id = -1;

		auto@ type = getInfluenceEffectType(type.integer);
		if(type !is null) {
			Targets targs(type.targets);
			auto@ eff = createInfluenceEffect(emp, type, targs);
			id = eff.id;
		}

		data.store(id);
	}

	void disable(Empire& emp, any@ data) const override {
		int id = -1;
		data.retrieve(id);

		if(id != -1)
			dismissEffect(emp, id);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null)
			disable(prevOwner, data);
		if(newOwner !is null)
			enable(newOwner, data);
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

tidy final class TriggerWhenWarEmpires : EmpireEffect {
	Document doc("Trigger an effect on any empire that becomes at war with the owner of this effect. Applies both to them or the owner declaring war.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect");

	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(function.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("TriggerWhenWarEmpires(): could not find inner hook: "+escape(function.str));
			return false;
		}
		return EmpireEffect::instantiate();
	}

#section server
	void enable(Empire& emp, any@ data) const override {
		int mask = emp.hostileMask;
		data.store(mask);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		int mask = 0;
		data.retrieve(mask);

		int newMask = emp.hostileMask;
		if(mask != newMask) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(mask & other.mask == 0 && newMask & other.mask != 0)
					hook.activate(null, other);
			}
			data.store(newMask);
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		int mask = 0;
		if(newOwner !is null)
			mask = newOwner.hostileMask;
		data.store(mask);
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

class ModAttributeWarPercentage : EmpireEffect {
	Document doc("Increase an attribute by an amount depending on how many empires the owner is currently at war with.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to increase.");
	Argument amount(AT_Decimal, doc="Amount to increase by when at war with _everybody_.");

#section server
	void enable(Empire& emp, any@ data) const override {
		double mod = 0.0;
		data.store(mod);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		double mod = 0.0;
		data.retrieve(mod);

		uint warEmpires = 0;
		uint otherEmpires = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other is emp || !other.major)
				continue;
			if(other.team == emp.team && other.team != -1)
				continue;

			++otherEmpires;
			if(emp.isHostile(other))
				++warEmpires;
		}

		double newMod = 0.0;
		if(otherEmpires != 0)
			newMod = amount.decimal * double(warEmpires) / double(otherEmpires);
		if(mod != newMod) {
			emp.modAttribute(attribute.integer, AC_Add, newMod-mod);
			data.store(newMod);
		}
	}

	void disable(Empire& emp, any@ data) const override {
		double mod = 0.0;
		data.retrieve(mod);

		emp.modAttribute(attribute.integer, AC_Add, -mod);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null)
			disable(prevOwner, data);
		if(newOwner !is null)
			enable(newOwner, data);
	}

	void save(any@ data, SaveFile& file) const override {
		double mod = 0;
		data.retrieve(mod);
		file << mod;
	}

	void load(any@ data, SaveFile& file) const override {
		double mod = 0;
		file >> mod;
		data.store(mod);
	}
#section all
};

class BorderSystemData {
	array<Region@> active;
	uint chkInd = 0;
};

class TakeoverBorderedSystems : EmpireEffect {
	Document doc("Automatically take over enemy planets in systems bordering your empire.");
	Argument attribute_check(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to check before doing this.");
	Argument check_value(AT_Decimal, "1", doc="Value to check for before doing this.");

#section server
	void enable(Empire& emp, any@ data) const override {
		BorderSystemData info;
		data.store(@info);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		BorderSystemData@ info;
		data.retrieve(@info);

		if(attribute_check.integer != 0 && emp.getAttribute(attribute_check.integer) < check_value.decimal) {
			if(info.active.length != 0)
				disable(emp, data);
		}
		else {
			//Handle existing systems
			for(uint i = 0, cnt = info.active.length; i < cnt; ++i) {
				auto@ sys = info.active[i];
				if(!hasPlanetsAdjacent(emp, sys) || sys.PlanetsMask == 0) {
					sys.clearForceSiegeAllPlanets(emp.mask);
					info.active.removeAt(i);
					--i; --cnt;
					continue;
				}
				sys.forceSiegeAllPlanets(emp, emp.mask, ~(emp.mask | emp.ForcedPeaceMask.value));
			}

			//Find new systems
			uint check = max(1.0, double(systemCount / 60.0 * time));
			for(uint n = 0; n < check; ++n) {
				info.chkInd = (info.chkInd+1) % systemCount;
				auto@ sys = getSystem(info.chkInd);
				if(hasPlanetsAdjacent(emp, sys.object) && sys.object.PlanetsMask != 0) {
					if(info.active.find(sys.object) == -1)
						info.active.insertLast(sys.object);
				}
			}
		}
	}

	void disable(Empire& emp, any@ data) const override {
		BorderSystemData@ info;
		data.retrieve(@info);

		for(uint i = 0, cnt = info.active.length; i < cnt; ++i) {
			auto@ sys = info.active[i];
			sys.clearForceSiegeAllPlanets(emp.mask);
		}
		info.active.length = 0;
	}

	void save(any@ data, SaveFile& file) const override {
		BorderSystemData@ info;
		data.retrieve(@info);

		uint cnt = info.active.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << info.active[i];
	}

	void load(any@ data, SaveFile& file) const override {
		BorderSystemData info;
		data.store(@info);

		uint cnt = 0;
		file >> cnt;
		info.active.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> info.active[i];
	}
#section all
};
