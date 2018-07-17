import buildings;
from buildings import BuildingHook;
from bonus_effects import BonusEffect;
import planet_effects;
import listed_values;
import requirement_effects;
import consume_effects;

tidy final class TriggerStartConstruction : BuildingHook {
	Document doc("Triggers another hook when construction of a building starts.");
	Argument hook("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ eff;

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::", required=false));
		if(eff is null) {
			error("TriggerStartConstruction(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return BuildingHook::instantiate();
	}

#section server
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {
		if(eff !is null)
			eff.activate(obj, obj.owner);
	}
#section all
};

tidy final class TriggerCancelConstruction : BuildingHook {
	Document doc("Triggers another hook when construction of a building is cancelled.");
	Argument hook("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ eff;

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::", required=false));
		if(eff is null) {
			error("TriggerCancelConstruction(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return BuildingHook::instantiate();
	}

#section server
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {
		if(eff !is null)
			eff.activate(obj, obj.owner);
	}
#section all
};

tidy final class TriggerConstructed : BuildingHook {
	Document doc("Triggers another hook when construction of a building is finished.");
	Argument hook("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ eff;

	bool instantiate() override {
		@eff = cast<BonusEffect>(parseHook(hook.str, "bonus_effects::", required=false));
		if(eff is null) {
			error("TriggerConstructed(): could not find inner hook: "+escape(hook.str));
			return false;
		}
		return BuildingHook::instantiate();
	}

#section server
	void complete(Object& obj, SurfaceBuilding@ bld) const {
		if(eff !is null)
			eff.activate(obj, obj.owner);
	}
#section all
};

class ConstructibleIfAttributeGTE : BuildingHook {
	Document doc("Only constructible if an empire attribute is greater than or equal to the specified value.");
	Argument attribute("Attribute", AT_EmpAttribute, doc="Attribute to test, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument value("Value", AT_Decimal, doc="Value to test against.");

	bool canBuildOn(Object& obj, bool ignoreState = false) const override {
		Empire@ emp = obj.owner;
		if(emp is null)
			return false;
		if(emp.getAttribute(attribute.integer) < value.decimal)
			return false;
		return true;
	}
};

class ConstructibleIfAttribute : BuildingHook {
	Document doc("Only constructible if an empire attribute is equal to the specified value.");
	Argument attribute("Attribute", AT_EmpAttribute, doc="Attribute to test, can be set to any arbitrary name to be created as a new attribute with starting value 0.");
	Argument value("Value", AT_Decimal, doc="Value to test against.");

	bool canBuildOn(Object& obj, bool ignoreState = false) const override {
		Empire@ emp = obj.owner;
		if(emp is null)
			return false;
		if(abs(emp.getAttribute(attribute.integer) - value.decimal) >= 0.001)
			return false;
		return true;
	}
};

class CannotBuildManually : BuildingHook {
	Document doc("Indicates that the building cannot be manually constructed.");

	bool canBuildOn(Object& obj, bool ignoreState = false) const override {
		return false;
	}
};

class CannotRemove : BuildingHook {
	Document doc("Indicates that the building cannot be removed by the player.");

	bool canRemove(Object& obj) const override {
		return false;
	}
};

class ModBuildSpeedAttribute : BuildingHook {
	Document doc("Multiply the build speed of this building by an attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to modify build speed by.");

	void modBuildTime(Object& obj, double& time) const {
		time /= obj.owner.getAttribute(attribute.integer);
	}
};

tidy final class ActiveWhenCargoConsumed : GenericEffect {
	Document doc("This hook applies while a particular amount of cargo can be consumed every interval.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to consume.");
	Argument amount(AT_Decimal, doc="Amount of cargo to consume per interval.");
	Argument interval(AT_Decimal, doc="Interval to consume cargo at.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");
	Argument labor_use_linked(AT_Boolean, "False", doc="Don't require the cargo consumption when no labor is currently being used.");
	Argument inactive_status(AT_Status, EMPTY_DEFAULT, doc="Status to add when this building is inactive.");
	Argument inactive_status_count(AT_Integer, "1", doc="How many statuses to add when this building is inactive.");
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
	void complete(Object& obj, SurfaceBuilding@ bld) const {
		auto@ data = bld.data[hookIndex];
		ConsumeData info;
		info.enabled = false;
		data.store(@info);

		bld.disabled = !info.enabled;
		bld.delta = true;

		if(info.enabled) {
			hook.enable(obj, info.data);
		}
		else if(inactive_status.integer != -1) {
			for(int n = 0; n < inactive_status_count.integer; ++n)
				obj.addStatus(inactive_status.integer);
		}
	}

	void disable(Object& obj, any@ data) const override {
		ConsumeData@ info;
		data.retrieve(@info);

		if(info.enabled)
			hook.disable(obj, info.data);
	}

	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {
		auto@ data = bld.data[hookIndex];
		ConsumeData@ info;
		data.retrieve(@info);

		bool cond = info.enabled;
		info.timer -= time;
		if(info.timer <= 0) {
			if(!obj.hasCargo) {
				cond = false;
				info.timer += interval.decimal;
			}
			else if(labor_use_linked.boolean && !obj.isUsingLabor) {
				cond = obj.getCargoStored(cargo_type.integer) >= amount.decimal;
			}
			else {
				double consAmt = obj.consumeCargo(cargo_type.integer, amount.decimal, partial=false);
				if(consAmt < amount.decimal - 0.001) {
					cond = false;
					info.timer += interval.decimal;
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

			bld.disabled = !cond;
			bld.delta = true;

			if(inactive_status.integer != -1) {
				for(int n = 0; n < inactive_status_count.integer; ++n) {
					if(bld.disabled)
						obj.addStatus(inactive_status.integer);
					else
						obj.removeStatusInstanceOfType(inactive_status.integer);
				}
			}
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

class RequireStatusToProgress : Requirement {
	Document doc("Require that a particular status is present for this building to progress construction.");
	Argument status(AT_Status, doc="Status type to check for.");

	bool canProgress(Object& obj) const override {
		if(!obj.hasStatuses)
			return false;
		return obj.getStatusStackCountAny(status.integer) > 0;
	}
};
