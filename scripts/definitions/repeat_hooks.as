import generic_hooks;

tidy class GenericRepeatHook : EmpireEffect {
	EmpireEffect@ empHook;
	GenericEffect@ hook;

	uint getRepeats(Empire& emp, any@ data) const {
		return 0;
	}

	uint getRepeats(Object& obj, any@ data) const {
		return getRepeats(obj.owner, data);
	}

	bool withHook(const string& str) {
		@hook = cast<GenericEffect>(parseHook(str, "planet_effects::", required = false));
		@empHook = cast<EmpireEffect>(parseHook(str, "empire_effects::", required = false));
		if(hook is null && empHook is null) {
			error("Repeat<>(): could not find inner hook: "+escape(str));
			return false;
		}
		return true;
	}

	void enable(Empire& emp, any@ data) const override {
		array<any> datlist;
		data.store(@datlist);
	}

	void tick(Empire& emp, any@ data, double time) const override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;

		uint oldCnt = datlist.length;
		uint newCnt = getRepeats(emp, data);
		for(uint i = newCnt; i < oldCnt; ++i)
			empHook.disable(emp, datlist[i]);
		datlist.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			empHook.enable(emp, datlist[i]);
		for(uint i = 0; i < newCnt; ++i)
			empHook.tick(emp, datlist[i], time);
	}

	void disable(Empire& emp, any@ data) const override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			empHook.disable(emp, datlist[i]);
		datlist.length = 0;
		@datlist = null;
		data.store(@datlist);
	}

	void enable(Object& obj, any@ data) const override {
		if(hook is null) {
			enable(obj.owner, data);
			return;
		}
		array<any> datlist;
		data.store(@datlist);
	}

	void tick(Object& obj, any@ data, double time) const override {
		if(hook is null) {
			tick(obj.owner, data, time);
			return;
		}
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;

		uint oldCnt = datlist.length;
		uint newCnt = getRepeats(obj, data);
		for(uint i = newCnt; i < oldCnt; ++i)
			hook.disable(obj, datlist[i]);
		datlist.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			hook.enable(obj, datlist[i]);
		for(uint i = 0; i < newCnt; ++i)
			hook.tick(obj, datlist[i], time);
	}

	void disable(Object& obj, any@ data) const override {
		if(hook is null) {
			disable(obj.owner, data);
			return;
		}
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.disable(obj, datlist[i]);
		datlist.length = 0;
		@datlist = null;
		data.store(@datlist);
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const override {
		if(hook is null) {
			disable(prevOwner, data);
			enable(newOwner, data);
			return;
		}
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.ownerChange(obj, datlist[i], prevOwner, newOwner);
	}

	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		if(datlist is null)
			return;
		for(uint i = 0, cnt = datlist.length; i < cnt; ++i)
			hook.regionChange(obj, datlist[i], fromRegion, toRegion);
	}

	void save(any@ data, SaveFile& file) const override {
		array<any>@ datlist;
		data.retrieve(@datlist);
		uint cnt = 0;
		if(datlist is null) {
			file << cnt;
			return;
		}

		cnt = datlist.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(hook !is null)
				hook.save(datlist[i], file);
			else if(empHook !is null)
				empHook.save(datlist[i], file);
		}
	}

	void load(any@ data, SaveFile& file) const override {
		array<any> datlist;
		uint cnt = 0;
		file >> cnt;
		datlist.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(hook !is null)
				hook.load(datlist[i], file);
			else if(empHook !is null)
				empHook.load(datlist[i], file);
		}
		data.store(@datlist);
	}
};

tidy final class Repeat : GenericRepeatHook {
	Document doc("Repeat an inner hook multiple times.");
	Argument amount(AT_Integer, doc="Amount of times to repeat.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument per_import(AT_Integer, "0", doc="Additional repeats to add for every imported resource.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Object& obj, any@ data) const override {
		uint newCnt = arguments[0].integer;
		uint perImport = arguments[2].integer;
		if(perImport != 0)
			newCnt += obj.usableResourceCount * perImport;
		return newCnt;
	}

	uint getRepeats(Empire& emp, any@ data) const override {
		uint newCnt = arguments[0].integer;
		return newCnt;
	}
#section all
};

tidy final class RepeatEmpireAttribute : GenericRepeatHook {
	Document doc("Repeat a hook an amount of times as stored in an empire attribute of the owner.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to take repeats from. Naming a new attribute will create it with a default value of 0.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Empire& emp, any@ data) const override {
		return uint(emp.getAttribute(attribute.integer));
	}
#section all
};

tidy final class RepeatPlanetLevel : GenericRepeatHook {
	Document doc("Repeat a hook for every planet level.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument base(AT_Decimal, "0", doc="Base amount of repeats to add regardless of level.");
	Argument per_level_bonus(AT_Decimal, "1", doc="Amount of repeats to add per planet level.");

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::"));
		if(hook is null) {
			error("Repeat(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Object& obj, any@ data) const override {
		double cnt = base.decimal;
		if(per_level_bonus.decimal != 0 && obj.isPlanet)
			cnt += per_level_bonus.decimal * obj.level;
		return cnt;
	}
#section all
};

tidy final class RepeatExtended : GenericRepeatHook {
	Document doc("Repeat a hook an amount of times as stored in an empire attribute of the owner.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument base_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to add to new repeats.");
	Argument multiply_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to multiply the whole repeat amount by.");
	Argument base(AT_Decimal, "0", doc="Base amount of repeats to add.");
	Argument multiplier(AT_Decimal, "1", doc="Multiplication to empire attribute before taking the repeats.");
	Argument per_level_bonus(AT_Decimal, "0", doc="If this is applied to a planet, add this many repeats per planet level.");
	Argument per_gametime_bonus(AT_Decimal, "0", doc="Adds more repeats for every minute of gametime that has passed since the beginning of the game.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Object& obj, any@ data) const override {
		double cnt = base.decimal;
		if(base_attribute.integer != -1)
			cnt += obj.owner.getAttribute(base_attribute.integer);
		if(per_level_bonus.decimal != 0 && obj.isPlanet)
			cnt += per_level_bonus.decimal * obj.level;
		cnt += per_gametime_bonus.decimal * (gameTime / 60.0);
		cnt *= multiplier.decimal;
		if(multiply_attribute.integer != -1)
			cnt *= obj.owner.getAttribute(multiply_attribute.integer);
		return cnt;
	}

	uint getRepeats(Empire& emp, any@ data) const override {
		double cnt = base.decimal;
		if(base_attribute.integer != -1)
			cnt += emp.getAttribute(base_attribute.integer);
		cnt += per_gametime_bonus.decimal * (gameTime / 60.0);
		cnt *= multiplier.decimal;
		if(multiply_attribute.integer != -1)
			cnt *= emp.getAttribute(multiply_attribute.integer);
		return cnt;
	}
#section all
};

tidy final class RepeatEmpirePopulation : GenericRepeatHook {
	Document doc("Repeat a hook based on the difference between an attribute value and the total empire population.");
	Argument interval(AT_Decimal, doc="Repeat the hook once for every <interval> population the empire has.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Empire& emp, any@ data) const override {
		return floor(double(emp.TotalPopulation) / interval.decimal);
	}
#section all
};

tidy final class RepeatPopulationCoverage : GenericRepeatHook {
	Document doc("Repeat a hook based on the difference between an attribute value and the total empire population.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to require covering of population.");
	Argument interval(AT_Decimal, doc="Repeat the hook once for every <interval> population that is not covered by the attribute.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Empire& emp, any@ data) const override {
		double diff = emp.TotalPopulation - emp.getAttribute(attribute.integer);
		if(diff <= 0)
			return 0;
		return ceil(diff / interval.decimal);
	}
#section all
};

tidy final class RepeatPressure : GenericRepeatHook {
	Document doc("Repeat a hook based on how much of a particular pressure is available locally.");
	Argument type(AT_TileResource, doc="Resource of pressure to check.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument multiplier(AT_Decimal, "1", doc="How many repeats per pressure.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Object& obj, any@ data) const override {
		return round(double(obj.resourcePressure[type.integer]) * multiplier.decimal);
	}
#section all
};

tidy final class RepeatFoodCount : GenericRepeatHook {
	Document doc("Repeat a hook for every food resource present.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Object& obj, any@ data) const override {
		return obj.getFoodCount();
	}
#section all
};

tidy final class RepeatEnergyStored : GenericRepeatHook {
	Document doc("Repeat a hook depending on how much energy is stored.");
	Argument step(AT_Decimal, doc="How much energy should be stored per repeat.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Empire& emp, any@ data) const {
		return floor(emp.EnergyStored / step.decimal);
	}
#section all
};

tidy final class RepeatEmpireContacts : GenericRepeatHook {
	Document doc("Repeat a hook with the amount of empires that have been contacted.");
	Argument hookID("Hook", AT_Hook, "planet_effects::GenericEffect");
	Argument maximum(AT_Integer, "-1", doc="Maximum contact count.");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	uint getRepeats(Empire& emp, any@ data) const {
		uint contacts = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(emp is other || !other.major)
				continue;
			if(emp.ContactMask & other.mask != 0)
				contacts += 1;
		}

		if(contacts > uint(maximum.integer))
			contacts = uint(maximum.integer);
		return contacts;
	}
#section all
};
