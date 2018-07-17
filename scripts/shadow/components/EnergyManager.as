import abilities;

tidy class EnergyManager : Component_EnergyManager {
	Mutex ablMutex;
	array<Ability> abilities;

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

	void abilityTick(Object& obj, double time) {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(!abilities[i].disabled)
				abilities[i].cooldown = max(0.0, abilities[i].cooldown - time);
		}
	}

	void getAbilities() const {
		Lock lck(ablMutex);
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i)
			yield(abilities[i]);
	}

	uint get_abilityTypes(int id) {
		Lock lck(ablMutex);
		Ability@ abl = getAbility(id);
		if(abl is null)
			return uint(-1);
		return abl.type.id;
	}

	void readAbilities(Message& msg) {
		Lock lck(ablMutex);
		uint cnt = msg.read_uint();
		abilities.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> abilities[i];
	}

	void readAbilityDelta(Message& msg) {
		Lock lck(ablMutex);
		readAbilities(msg);
	}
}
