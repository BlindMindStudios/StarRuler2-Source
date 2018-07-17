import hooks;
import orbitals;
import generic_effects;
import traits;
from orbitals import OrbitalEffect;
import requirement_effects;
import consume_effects;

#section server-side
from regions.regions import getRegion;
#section all

#section server
import object_creation;
#section all

class AddParticleSystem : OrbitalEffect {
	Document doc("Adds a permanent particle system to the orbital.");
	Argument particle("Particle System", AT_Custom, doc="ID of the particle system to create.");
	Argument size("Size", AT_Decimal, "1.0", doc="Scale factor for the effect.");

#section server-side
	void onMakeGraphics(Orbital& obj, any@ data, OrbitalNode@ node) const override {
		auto@ gfx = PersistentGfx();
		gfx.establish(obj, arguments[0].str, arguments[1].decimal);
		gfx.rotate(obj.rotation);
	}
#section all
};

//AddArmor(<Amount> = 0, <Per Import> = 0)
// Add maximum armor to the orbital.
class AddArmor : OrbitalEffect {
	Document doc("Add maximum armor to the orbital.");
	Argument amt("Amount", AT_Decimal, "0.0", doc="Base armor to add.");
	Argument perImport("Per Import", AT_Decimal, "0.0", doc="Armor added per import.");

#section server
	double amount(Orbital& obj) {
		double amt = arguments[0].decimal;
		double per = arguments[1].decimal;
		if(per != 0)
			amt += per * double(obj.usableResourceCount);
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modMaxArmor(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modMaxArmor(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modMaxArmor(-amt);
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

//AddHealth(<Amount> = 0, <Per Import> = 0)
// Add maximum health to the orbital.
class AddHealth : OrbitalEffect {
	Document doc("Add maximum health to the orbital.");
	Argument amt("Amount", AT_Decimal, "0.0", doc="Base health to add.");
	Argument perImport("Per Import", AT_Decimal, "0.0", doc="Health added per import.");

#section server
	double amount(Orbital& obj) {
		double amt = arguments[0].decimal;
		double per = arguments[1].decimal;
		if(per != 0)
			amt += per * double(obj.usableResourceCount);
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modMaxHealth(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modMaxHealth(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modMaxHealth(-amt);
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

class AddHealthEmpireAttribute : OrbitalEffect {
	Document doc("Add base maximum health to the orbital based on an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to take the extra health from.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplication factor to the attribute value.");

#section server
	double amount(Orbital& obj) {
		double amt = obj.owner.getAttribute(attribute.integer);
		amt *= multiplier.decimal;
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modMaxHealth(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modMaxHealth(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modMaxHealth(-amt);
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

class AddArmorEmpireAttribute : OrbitalEffect {
	Document doc("Add base maximum armor to the orbital based on an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to take the extra armor from.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplication factor to the attribute value.");

#section server
	double amount(Orbital& obj) {
		double amt = obj.owner.getAttribute(attribute.integer);
		amt *= multiplier.decimal;
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modMaxArmor(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modMaxArmor(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modMaxArmor(-amt);
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

//AddResistance(<Amount> = 0, <Per Import> = 0)
// Add damage resistance to the orbital.
class AddResistance : OrbitalEffect {
	Document doc("Add armor resistance to the orbital.");
	Argument amt("Amount", AT_Decimal, "0.0", doc="Base resistance to add.");
	Argument perImport("Per Import", AT_Decimal, "0.0", doc="Resistance added per import.");

#section server
	double amount(Orbital& obj) {
		double amt = arguments[0].decimal;
		double per = arguments[1].decimal;
		if(per != 0)
			amt += per * double(obj.usableResourceCount);
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modDR(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modDR(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modDR(-amt);
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

class AddResistanceEmpireAttribute : OrbitalEffect {
	Document doc("Add base resistance to the orbital based on an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to take the extra resistance from.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplication factor to the attribute value.");

#section server
	double amount(Orbital& obj) {
		double amt = obj.owner.getAttribute(attribute.integer);
		amt *= multiplier.decimal;
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modDR(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modDR(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modDR(-amt);
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

//FTLMaintenance(<Amount>)
// Add an FTL maintenance cost to the module.
class FTLMaintenance : OrbitalEffect {
	Document doc("Makes the orbital cost FTL to maintain.");
	Argument amt("Amount", AT_Decimal, doc="FTL maintenance cost.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modFTLUse(arguments[0].decimal);
	}

	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.modFTLUse(-arguments[0].decimal);
		if(newOwner !is null && newOwner.valid)
			newOwner.modFTLUse(arguments[0].decimal);
	}

	void onDisable(Orbital& obj, any@ data) const override {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modFTLUse(-arguments[0].decimal);
	}

	bool shouldDisable(Orbital& obj, any@ data) const override {
		if(obj.owner is null || !obj.owner.valid)
			return true;
		return obj.owner.FTLShortage;
	}

	bool shouldEnable(Orbital& obj, any@ data) const override {
		if(obj.owner is null || !obj.owner.valid)
			return false;
		return !obj.owner.isFTLShortage(arguments[0].decimal);
	}
#section all
};

//DisableOnFTLBlock()
// Disables the module if ftl is blocked in the region.
class DisableOnFTLBlock : OrbitalEffect {
	Document doc("Disables this orbital if FTL jamming is affecting its region.");
	
#section server
	bool shouldDisable(Orbital& obj, any@ data) const override {
		if(obj.owner is null || !obj.owner.valid)
			return false;
		Region@ reg = obj.region;
		if(reg is null)
			return false;
		if(reg.BlockFTLMask & obj.owner.mask != 0)
			return true;
		return false;
	}

	bool shouldEnable(Orbital& obj, any@ data) const override {
		if(obj.owner is null || !obj.owner.valid)
			return true;
		Region@ reg = obj.region;
		if(reg is null)
			return true;
		if(reg.BlockFTLMask & obj.owner.mask != 0)
			return false;
		return true;
	}
#section all
};

//CannotBuildManually()
// Module cannot be built manually.
class CannotBuildManually : OrbitalEffect {
	Document doc("Prevents this orbital from being manually contructed.");
	
	bool canBuildBy(Object@ obj, bool ignoreCost) const override {
		return false;
	}

	bool canBuildOn(Orbital& obj) const override {
		return false;
	}
};

class RequireBlackHoleSystem : OrbitalEffect {
	Document doc("This orbital can only be constructed in systems that have a black hole.");

	string getBuildError(Object@ obj, const vec3d& pos) const {
		return locale::OERR_BLACKHOLE;
	}

	bool canBuildAt(Object@ obj, const vec3d& pos) const {
		Region@ target = getRegion(pos);
		if(target is null)
			return false;
		return target.starCount > 0 && target.starTemperature == 0;
	}
};

class RequireCloseToStar : OrbitalEffect {
	Document doc("This orbital must be placed close to the star.");
	Argument max_distance(AT_Decimal, "110", doc="Maximum radius away from star.");
	Argument min_distance(AT_Decimal, "10", doc="Minimum radius away from star.");

	string getBuildError(Object@ obj, const vec3d& pos) const {
		return locale::OERR_CLOSE_TO_STAR;
	}

	bool canBuildAt(Object@ obj, const vec3d& pos) const {
		Region@ target = getRegion(pos);
		if(target is null)
			return false;
		double dist = pos.distanceTo(target.position);
		double starRad = target.starRadius;
		return dist > starRad && dist <= starRad + max_distance.decimal;
	}
};

class LimitInOrbitStatus : OrbitalEffect {
	Document doc("This orbital must be constructed in orbit of a planet, and can only be constructed if there is a limited amount of a status present.");
	Argument status(AT_Status, doc="Status type to check for.");
	Argument max_stacks(AT_Integer, "1", doc="Maximum stacks for the orbital.");
	Argument min_distance(AT_Decimal, "5", doc="Minimum distance this needs to be from the planet.");

	string getBuildError(Object@ obj, const vec3d& pos) const {
		Region@ target = getRegion(pos);
		if(target is null)
			return locale::OERR_PLANET_ORBIT;
		Object@ orbit = target.getOrbitObject(pos);
		if(orbit is null || obj is null || orbit.owner !is obj.owner)
			return locale::OERR_PLANET_ORBIT;
		if(orbit.position.distanceTo(pos) < orbit.radius + min_distance.decimal)
			return locale::OERR_PLANET_ORBIT;
		return locale::OERR_PLANET_LIMIT;
	}

	bool canBuildAt(Object@ obj, const vec3d& pos) const {
		Region@ target = getRegion(pos);
		if(target is null)
			return false;

		Object@ orbit = target.getOrbitObject(pos);
		if(orbit is null || obj is null || obj.owner !is orbit.owner)
			return false;

		if(orbit.position.distanceTo(pos) < orbit.radius + min_distance.decimal)
			return false;

		int count = orbit.getStatusStackCountAny(status.integer);
		if(count >= max_stacks.integer)
			return false;

		return true;
	}

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		Region@ target = getRegion(obj.position);
		if(target is null) {
			obj.destroy();
			return;
		}

		Object@ orbit = target.getOrbitObject(obj.position);
		if(orbit is null) {
			obj.destroy();
			return;
		}

		int count = orbit.getStatusStackCountAny(status.integer);
		if(count >= max_stacks.integer) {
			obj.destroy();
			return;
		}
	}
#section all
};

//OnKillSpreadLeverageToFriendlies(<Quality Factor>)
// When this orbital is killed, all friendly empires get <Quality Factor> leverage on the killer.
class OnKillSpreadLeverageToFriendlies : OrbitalEffect {
	Document doc("Gives leverage to the orbital's owner and allies when destroyed.");
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic number to decide the overall value of leverage granted.");

#section server
	void onKill(Orbital& obj, any@ data, Empire@ killedBy) const override {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major || other is killedBy)
				continue;
			if(other !is owner && other.isHostile(owner))
				continue;

			other.gainRandomLeverage(killedBy, arguments[0].decimal);
		}
	}
#section all
};

//DryDockConstruction()
// Allow this orbital to do dry dock construction.
tidy final class DryDockStatus {
	const Design@ design;
	int maintainCost = 0;
	int buildCost = 0;
	double percentPaid = 0;
	double laborGen = 0;
	double curLabor = 0;
	double totalLabor = 1;
	bool isFree = false;
};

class DryDockConstruction : OrbitalEffect {
	Document doc("Allows this orbital to act as a drydock.");
	
#section server-side
	void write(any@ data, Message& msg) const {
		DryDockStatus@ status;
		data.retrieve(@status);

		if(status is null) {
			msg.write0();
			return;
		}

		msg.write1();
		msg << status.design;
		msg.writeFixed(status.percentPaid, bits=8);
		msg << float(status.curLabor);
		msg << float(status.totalLabor);
		msg << float(status.laborGen);
		msg.writeBit(status.isFree);
	}

	void read(any@ data, Message& msg) const {
		if(!msg.readBit())
			return;

		DryDockStatus@ status;
		data.retrieve(@status);
		if(status is null) {
			@status = DryDockStatus();
			data.store(@status);
		}

		msg >> status.design;
		status.percentPaid = msg.readFixed(bits=8);
		status.curLabor = msg.read_float();
		status.totalLabor = msg.read_float();
		status.laborGen = msg.read_float();
		status.isFree = msg.readBit();
	}
#section server
	void save(any@ data, SaveFile& file) const {
		DryDockStatus@ status;
		data.retrieve(@status);

		file << status.design;
		file << status.maintainCost;
		file << status.buildCost;
		file << status.percentPaid;
		file << status.laborGen;
		file << status.curLabor;
		file << status.totalLabor;
		file << status.isFree;
	}

	void load(any@ data, SaveFile& file) const {
		DryDockStatus status;
		data.store(@status);

		file >> status.design;
		file >> status.maintainCost;
		file >> status.buildCost;
		file >> status.percentPaid;
		file >> status.laborGen;
		file >> status.curLabor;
		file >> status.totalLabor;
		file >> status.isFree;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		DryDockStatus status;
		data.store(@status);
	}

	void onDisable(Orbital& obj, any@ data) const override {
		DryDockStatus@ status;
		data.retrieve(@status);

		if(!status.isFree) {
			int prevMaint = ceil(double(status.maintainCost) * status.percentPaid);
			obj.owner.modMaintenance(-prevMaint, MoT_Construction);
		}

		@status = null;
		data.store(@status);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		DryDockStatus@ status;
		data.retrieve(@status);
		if(status is null || status.design is null)
			return;
		int pct = int(status.curLabor / status.totalLabor * 1000);
		if(status.laborGen != 0) {
			double prevLabor = status.curLabor;
			status.curLabor = clamp(status.curLabor + status.laborGen * time,
					0, max(status.totalLabor * status.percentPaid, status.curLabor));
			obj.usingLabor = abs(prevLabor - status.curLabor) > 0.001;
			if(pct != int(status.curLabor / status.totalLabor * 1000))
				obj.triggerDelta();
		}
		else {
			obj.usingLabor = false;
		}
		if(status.curLabor >= status.totalLabor && status.percentPaid >= 1.f) {
			createShip(obj, status.design, move=false, free=status.isFree);
			obj.usingLabor = false;
			obj.destroy();
		}
	}

	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const {
		if(pl != SERVER_PLAYER)
			return false;
		if(index == OV_DRY_Design) {
			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			@status.design = value;
			getBuildCost(value, status.buildCost, status.maintainCost, status.totalLabor);
			status.buildCost = double(status.buildCost) * config::DRYDOCK_BUILDCOST_FACTOR * obj.owner.DrydockCostFactor;
			status.curLabor = 0;
			return true;
		}
		return false;
	}

	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const {
		if(index == OV_DRY_SetFinanced) {
			if(pl != SERVER_PLAYER)
				return false;

			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			if(!status.isFree) {
				int prevMaint = ceil(double(status.maintainCost) * status.percentPaid);
				int newMaint = ceil(double(status.maintainCost) * value);
				obj.owner.modMaintenance(newMaint - prevMaint, MoT_Construction);
			}
			status.percentPaid = value;
			obj.triggerDelta();
			return true;
		}
		if(index == OV_DRY_Progress) {
			if(pl != SERVER_PLAYER)
				return false;

			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			status.curLabor = value * status.totalLabor;
			obj.triggerDelta();
			return true;
		}
		if(index == OV_DRY_Free) {
			if(pl != SERVER_PLAYER)
				return false;

			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			bool free = value != 0.0;
			if(free != status.isFree) {
				if(status.maintainCost != 0) {
					if(status.isFree) {
						int prevMaint = ceil(double(status.maintainCost) * status.percentPaid);
						obj.owner.modMaintenance(+prevMaint, MoT_Construction);
					}
					else {
						int prevMaint = ceil(double(status.maintainCost) * status.percentPaid);
						obj.owner.modMaintenance(-prevMaint, MoT_Construction);
					}
				}
				status.isFree = free;
			}
			obj.triggerDelta();
			return true;
		}
		if(index == OV_DRY_ModLabor) {
			if(pl != SERVER_PLAYER)
				return false;

			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			status.laborGen += value;
			obj.triggerDelta();
			return true;
		}
		if(index == OV_DRY_Financed) {
			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			double pct = value;
			double prevPct = status.percentPaid;
			double newPct = clamp(pct, 0.0, 1.0);
			pct = newPct - prevPct;

			int cost = ceil(double(status.buildCost) * pct);
			if(obj.owner.consumeBudget(cost) == -1)
				return true;

			if(!status.isFree) {
				int prevMaint = ceil(double(status.maintainCost) * prevPct);
				int newMaint = ceil(double(status.maintainCost) * newPct);
				obj.owner.modMaintenance(newMaint - prevMaint, MoT_Construction);
			}
			status.percentPaid = newPct;
			obj.triggerDelta();
			return true;
		}
		return false;
	}
#section server-side
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const {
		DryDockStatus@ status;
		data.retrieve(@status);
		if(status is null)
			return false;

		switch(index) {
			case OV_DRY_Free: value = status.isFree ? 1.0 : 0.0; return true;
			case OV_DRY_Progress: value = status.curLabor / status.totalLabor; return true;
			case OV_DRY_Financed: value = status.percentPaid; return true;
			case OV_DRY_ETA:
				value = (status.laborGen == 0) ? INFINITY :
						 (status.totalLabor - status.curLabor) / status.laborGen;
				return true;
		}
		return false;
	}

	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const {
		if(index == OV_DRY_Design) {
			DryDockStatus@ status;
			data.retrieve(@status);
			if(status is null)
				return false;

			@value = status.design;
			return true;
		}
		return false;
	}
#section all
};

//PacksIntoShip(<Design> = "", <Maintenance> = True)
// This orbital can be packed into a ship of <Design>.
class PacksIntoShip : OrbitalEffect {
	Document doc("Allows the orbital to be packed into a specific ship design.");
	Argument design("Design", AT_Custom, "", doc="Design name to packup into.");
	Argument maint("Maintenance", AT_Boolean, "True", doc="Whether the created ship should cost maintenance.");

#section server-side
	void write(any@ data, Message& msg) const {
		const Design@ dsg;
		data.retrieve(@dsg);
		msg << dsg;
	}

	void read(any@ data, Message& msg) const {
		const Design@ dsg;
		msg >> dsg;
		data.store(@dsg);
	}
#section server
	void save(any@ data, SaveFile& file) const {
		const Design@ dsg;
		data.retrieve(@dsg);
		file << dsg;
	}

	void load(any@ data, SaveFile& file) const {
		const Design@ dsg;
		file >> dsg;
		data.store(@dsg);
	}

	void onEnable(Orbital& obj, any@ data) const override {
		const Design@ dsg;
		data.retrieve(@dsg);
		if(dsg is null) {
			for(uint i = 0, cnt = obj.owner.designCount; i < cnt; ++i) {
				auto@ check = obj.owner.designs[i];
				if(check.name == arguments[0].str) {
					@dsg = check.mostUpdated();
					break;
				}
			}
			data.store(@dsg);
		}
		if(arguments[1].boolean && obj.owner !is null && obj.owner.valid)
			obj.owner.modMaintenance(+getMaintenance(obj, data), MoT_Orbitals);
	}

	int getMaintenance(Orbital& obj, any@ data) const {
		const Design@ dsg;
		data.retrieve(@dsg);
		if(dsg is null)
			return 0;
		const OrbitalModule@ mod = getOrbitalModule(obj.coreModule);
		if(mod is null)
			return getMaintenanceCost(dsg);
		return getMaintenanceCost(dsg) - mod.maintenance;
	}

	void onDisable(Orbital& obj, any@ data) const override {
		if(arguments[1].boolean && obj.owner !is null && obj.owner.valid)
			obj.owner.modMaintenance(-getMaintenance(obj, data), MoT_Orbitals);
		const Design@ dsg = null;
		data.store(@dsg);
	}

	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(arguments[1].boolean) {
			int maint = getMaintenance(obj, data);
			if(prevOwner !is null && prevOwner.valid)
				prevOwner.modMaintenance(-maint, MoT_Orbitals);
			if(newOwner !is null && newOwner.valid)
				newOwner.modMaintenance(+maint, MoT_Orbitals);
		}
	}

	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const {
		if(pl != SERVER_PLAYER)
			return false;
		if(index == OV_PackUp) {
			int prevMaintenance = 0, newMaintenance = 0;
			if(arguments[1].boolean)
				prevMaintenance = getMaintenance(obj, data);
			data.store(@value);
			if(arguments[1].boolean) {
				newMaintenance = getMaintenance(obj, data);
				if(prevMaintenance != newMaintenance && obj.owner !is null && obj.owner.valid)
					obj.owner.modMaintenance(newMaintenance - prevMaintenance, MoT_Orbitals);
			}
			obj.triggerDelta();
			return true;
		}
		return false;
	}

	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const {
		if(index == OV_PackUp) {
			if(pl != SERVER_PLAYER && pl.emp !is obj.owner)
				return false;

			const Design@ dsg;
			data.retrieve(@dsg);
			if(dsg is null)
				return false;
			createShip(obj.position, dsg, obj.owner);
			obj.destroy();
			return true;
		}
		return false;
	}
#section server-side
	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const {
		if(index == OV_PackUp) {
			const Design@ dsg;
			data.retrieve(@dsg);
			@value = dsg;
			return true;
		}
		return false;
	}
#section all
};

//RecordOrbitalDPS(<Amount> = 0, <Per Import> = 0)
// Add recorded dps to the orbital.
class RecordOrbitalDPS : OrbitalEffect {
	Document doc("Adds to the listed damage per second on an orbital.");
	Argument amt("Amount", AT_Decimal, "0.0", doc="Base DPS to add.");
	Argument perImport("Per Import", AT_Decimal, "0.0", doc="DPS to add per import");

#section server
	double amount(Orbital& obj) {
		double amt = arguments[0].decimal;
		double per = arguments[1].decimal;
		if(per != 0)
			amt += per * double(obj.usableResourceCount);
		return amt;
	}

	void onEnable(Orbital& obj, any@ data) const override {
		double amt = amount(obj);
		data.store(amt);
		obj.modDPS(amt);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double amt = amount(obj);
		double prev = 0;
		data.retrieve(prev);
		if(amt != prev) {
			data.store(amt);
			obj.modDPS(amt - prev);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		double amt = 0;
		data.retrieve(amt);
		obj.modDPS(-amt);
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

class LimitOncePerSystem : OrbitalEffect {
	Document doc("This orbital can only be constructed once per system.");
	Argument flag(AT_SystemFlag, doc="System flag to base the once per system limit on. Can be set to any arbitrary unique name.");
	Argument any_empire(AT_Boolean, "False", doc="If set to true, only one empire may build this in a system.");

	bool canBuildAt(Object@ obj, const vec3d& pos) const {
		auto@ system = getRegion(pos);
		if(system is null)
			return false;
		if(obj is null)
			return false;
		return !check(obj, system);
	}
	
	bool check(Object& obj, Region@ system) {
		if(any_empire.boolean)
			return system.getSystemFlagAny(flag.integer);
		else
			return system.getSystemFlag(obj.owner, flag.integer);
	}

	string getBuildError(Object@ obj, const vec3d& pos) const {
		return locale::OERR_LIMIT;
	}

#section server
	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		Region@ region = obj.region;
		if(region !is null) {
			if(prevOwner !is null && prevOwner.valid)
				region.setSystemFlag(prevOwner, flag.integer, false);
			if(newOwner !is null && newOwner.valid) {
				if(region.getSystemFlag(newOwner, flag.integer))
					obj.destroy();
				else
					region.setSystemFlag(newOwner, flag.integer, true);
			}
		}
	}

	void onRegionChange(Orbital& obj, any@ data, Region@ fromRegion, Region@ toRegion) const override {
		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid) {
			if(fromRegion !is null)
				fromRegion.setSystemFlag(owner, flag.integer, false);
			if(toRegion !is null) {
				if(check(obj, toRegion)) {
					if(!obj.inFTL)
						obj.destroy();
				}
				else
					toRegion.setSystemFlag(owner, flag.integer, true);
			}
		}
	}

	void onEnable(Orbital& obj, any@ data) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid) {
			if(check(obj, region))
				obj.destroy();
			else
				region.setSystemFlag(owner, flag.integer, true);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		Region@ region = obj.region;
		Empire@ owner = obj.owner;
		if(region !is null && owner !is null && owner.valid)
			region.setSystemFlag(owner, flag.integer, false);
	}

	bool shouldDisable(Orbital& obj, any@ data) const override {
		return obj.inFTL || obj.region is null;
	}

	bool shouldEnable(Orbital& obj, any@ data) const override {
		return !obj.inFTL && obj.region !is null;
	}
#section all
};

class SetAsDefense : OrbitalEffect {
	Document doc("This orbital is set to make use of defense production by default.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid)
			owner.setDefending(obj, true);
	}

	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.setDefending(obj, false);
		if(newOwner !is null && newOwner.valid)
			newOwner.setDefending(obj, true);
	}
#section all
};

class FrameConstruction : OrbitalEffect {
	Document doc("This orbital is a construction frame for other orbitals.");
	Argument cost_factor(AT_Decimal, "1.0", doc="Factor to build cost of orbitals built on this frame.");
	Argument labor_factor(AT_Decimal, "1.0", doc="Factor to labor cost of orbitals built on this frame.");
	Argument labor_penalty_factor(AT_Decimal, "1.0", doc="Factor to labor cost penalty of orbitals built on this frame.");
	
#section server
	bool sendObject(Player& pl, Orbital& obj, any@ data, uint index, Object@ value) const {
		if(index == OV_FRAME_Target) {
			obj.destroy();
			return true;
		}
		return false;
	}
#section server-side
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const {
		if(index == OV_FRAME_Usable) {
			value = 1.0;
			return true;
		}
		else if(index == OV_FRAME_CostFactor) {
			value = cost_factor.decimal;
			return true;
		}
		else if(index == OV_FRAME_LaborFactor) {
			value = labor_factor.decimal;
			return true;
		}
		else if(index == OV_FRAME_LaborPenaltyFactor) {
			value = labor_penalty_factor.decimal;
			return true;
		}
		return false;
	}
#section all
};

class BreakOrbitOnFTL : OrbitalEffect {
	Document doc("When the planet this orbital is orbiting FTLs, the orbital breaks its orbit.");

#section server
	void onTick(Orbital& obj, any@ data, double time) const override {
		Object@ around = obj.getOrbitingAround();
		if(around !is null && around.inFTL)
			obj.stopOrbit();
	}
#section all
};

class AllowResourceImport : OrbitalEffect {
	Document doc("This orbital can import resources.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		obj.setImportEnabled(true);
	}
#section all
};

class AutoMasterSlave : OrbitalEffect {
	Document doc("Automatically slave this to the first orbital of this type.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		uint core = obj.coreModule;
		uint id = uint(obj.id);

		auto@ datalist = obj.owner.getOrbitals();
		Object@ check;
		Orbital@ newMaster;
		while(receive(datalist, check)) {
			Orbital@ orb = cast<Orbital>(check);
			if(orb is null || !orb.valid)
				continue;
			if(uint(orb.id) >= id)
				continue;
			if(orb.coreModule != core)
				continue;

			@newMaster = orb;
			id = uint(orb.id);
		}

		obj.setMaster(newMaster);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		Orbital@ master = obj.getMaster();
		if(master !is null) {
			if(!master.valid || master.owner !is obj.owner)
				onEnable(obj, data);
		}
	}

	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		onEnable(obj, data);
	}
#section all
};

class CopyLaborFromMaster : OrbitalEffect {
	Document doc("Copy the labor income that this orbital's master is giving.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		double amount = 0;
		data.store(amount);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		double prevAmount = 0;
		data.retrieve(prevAmount);

		double newAmount = 0;
		Orbital@ master = obj.getMaster();
		if(master !is null)
			newAmount = master.laborIncome;

		if(prevAmount != newAmount) {
			obj.modLaborIncome(newAmount - prevAmount);
			data.store(newAmount);
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
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

tidy final class PressureCopier {
	Orbital@ copyTo;
	array<double> amount(TR_COUNT, 0.0);
};

class CopyPressureToMaster : OrbitalEffect {
	Document doc("Copy over all the pressure this orbital is importing to the orbital's master if it has one.");

#section server
	void onEnable(Orbital& obj, any@ data) const override {
		PressureCopier pc;
		data.store(@pc);
	}

	void onTick(Orbital& obj, any@ data, double time) const override {
		PressureCopier@ pc;
		data.retrieve(@pc);

		//Deal with master changes
		Orbital@ newMaster = obj.getMaster();
		if(newMaster !is pc.copyTo) {
			for(uint i = 0, cnt = pc.amount.length; i < cnt; ++i) {
				if(pc.amount[i] != 0) {
					pc.copyTo.modPressure(i, -pc.amount[i]);
					newMaster.modPressure(i, +pc.amount[i]);
				}
			}
			@pc.copyTo = newMaster;
		}

		//Deal with pressure changes
		if(pc.copyTo !is null) {
			for(uint i = 0, cnt = pc.amount.length; i < cnt; ++i) {
				double newValue = obj.resourcePressure[i];
				if(pc.amount[i] != newValue) {
					pc.copyTo.modPressure(i, newValue - pc.amount[i]);
					pc.amount[i] = newValue;
				}
			}
		}
	}

	void onDisable(Orbital& obj, any@ data) const override {
		PressureCopier@ pc;
		data.retrieve(@pc);

		if(pc.copyTo !is null) {
			for(uint i = 0, cnt = pc.amount.length; i < cnt; ++i) {
				if(pc.amount[i] != 0)
					pc.copyTo.modPressure(i, -pc.amount[i]);
			}
		}
	}

	void save(any@ data, SaveFile& file) const override {
		PressureCopier@ pc;
		data.retrieve(@pc);
		if(pc is null)
			@pc = PressureCopier();

		file << pc.copyTo;

		uint cnt = pc.amount.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << pc.amount[i];
	}

	void load(any@ data, SaveFile& file) const override {
		PressureCopier pc;
		data.store(@pc);

		file >> pc.copyTo;

		uint cnt = 0;
		file >> cnt;
		pc.amount.length = cnt;

		for(uint i = 0; i < cnt; ++i)
			file >> pc.amount[i];
	}
#section all
};

class MoveCargoToMaster : OrbitalEffect {
	Document doc("Move all the cargo on this orbital to the orbital's master if it has one.");

#section server
	void onTick(Orbital& obj, any@ data, double time) const override {
		if(obj.hasCargo && obj.cargoStored > 0 && obj.hasMaster())
			obj.transferAllCargoTo(obj.getMaster());
	}
#section all
};

class MoveImportsToMaster : OrbitalEffect {
	Document doc("Redirect all imports to this orbital to its master.");

#section server
	void onTick(Orbital& obj, any@ data, double time) const override {
		if(obj.hasMaster()) {
			Object@ master = obj.getMaster();
			obj.redirectAllImports(master);
		}
	}
#section all
};
