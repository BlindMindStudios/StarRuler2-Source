import abilities;
from saving import SaveVersion;

tidy class EnergyManager : Component_EnergyManager, Savable {
	Mutex ablMutex;
	int nextAbilityId = 0;
	array<Ability@> abilities;
	bool delta = false;

	uint get_abilityTypes(int id) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return uint(-1);
		return abl.type.id;
	}

	int addAbility(Empire& emp, uint id) {
		Lock lck(ablMutex);
		const AbilityType@ type = getAbilityType(id);
		if(type !is null) {
			delta = true;
			return addAbility(emp, type).id;
		}
		return -1;
	}

	void removeAbility(Empire& emp, int id) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(!abl.disabled)
			abl.disable();
		abl.destroy();
		abilities.remove(abl);
		delta = true;
	}

	void disableAbility(Empire& emp, int id) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(!abl.disabled) {
			abl.disable();
			abl.disabled = true;
			delta = true;
		}
	}

	void enableAbility(Empire& emp, int id) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(abl.disabled) {
			abl.enable();
			abl.disabled = false;
			delta = true;
		}
	}

	Ability@ addAbility(Empire& emp, const AbilityType@ type, const Subsystem@ sys = null) {
		Lock lck(ablMutex);
		Ability abl(type);
		abl.id = nextAbilityId++;
		@abl.subsystem = sys;
		@abl.obj = null;
		@abl.emp = emp;

		abilities.insertLast(abl);
		abl.create();
		abl.enable();
		return abl;
	}

	void save(SaveFile& file) {
		Lock lck(ablMutex);
		uint cnt = abilities.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << abilities[i];
		file << nextAbilityId;
	}

	void load(SaveFile& file) {
		Lock lck(ablMutex);
		uint cnt = 0;
		file >> cnt;
		abilities.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			Ability abl;
			file >> abl;
			@abilities[i] = abl;
		}

		file >> nextAbilityId;
	}

	void powerTick(Empire& emp, double time) {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(!abilities[i].disabled) {
				abilities[i].cooldown = max(0.0, abilities[i].cooldown - time);
				abilities[i].tick(time);
			}
		}
	}

	Ability@ getAbility(int id) {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(abilities[i].id == id)
				return abilities[i];
		}
		return null;
	}

	void getAbility(int id) const {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(abilities[i].id == id) {
				yield(abilities[i]);
				return;
			}
		}
	}

	void getAbilityOfType(uint id) const {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(abilities[i].type.id == id) {
				yield(abilities[i]);
				return;
			}
		}
	}

	uint get_abilityCount() const {
		return abilities.length;
	}

	void getAbilities() const {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i)
			yield(abilities[i]);
	}

	void triggerAbility(Empire& emp, int id, Targets@ targs) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(abl.disabled || abl.cooldown > 0)
			return;
		abl.activate(targs);
		delta = true;
	}

	void activateAbility(Empire& emp, int id) {
		triggerAbility(emp, id, null);
	}

	void activateAbility(Empire& emp, int id, vec3d point) {
		Targets targs;
		targs.add(TT_Point, fill=true).point = point;
		triggerAbility(emp, id, targs);
	}

	void activateAbility(Empire& emp, int id, Object@ target) {
		Targets targs;
		@targs.add(TT_Object, fill=true).obj = target;
		triggerAbility(emp, id, targs);
	}

	void writeAbilities(Message& msg) const {
		Lock lck(ablMutex);
		uint cnt = abilities.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << abilities[i];
	}

	bool writeAbilityDelta(Message& msg) {
		if(!delta)
			return false;
		msg.write1();
		writeAbilities(msg);
		delta = false;
		return true;
	}
};
