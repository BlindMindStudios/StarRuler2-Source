import traits;
import attitudes;

tidy class Traits : Component_Traits {
	array<const Trait@> traits;
	array<bool> hasTraits(getTraitCount(), false);

	array<Attitude> attitudes;
	ReadWriteMutex attMtx;

	bool hasTrait(uint id) {
		if(id >= hasTraits.length)
			return false;
		return hasTraits[id];
	}

	uint get_traitCount() const {
		return traits.length;
	}

	uint getTraitType(uint index) const {
		if(index >= traits.length)
			return uint(-1);
		return traits[index].id;
	}

	uint getAttitudeLevel(uint id) const {
		ReadLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id)
				return attitudes[i].level;
		}
		return 0;
	}

	void readTraits(Message& msg) {
		uint cnt = msg.readSmall();
		traits.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			int id = msg.readSmall();
			@traits[i] = getTrait(id);
			hasTraits[id] = true;
		}
	}

	uint get_attitudeCount() {
		return attitudes.length;
	}

	void getAttitudes() {
		ReadLock lck(attMtx);
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i)
			yield(attitudes[i]);
	}

	bool hasAttitude(uint id) {
		ReadLock lck(attMtx);
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i)
			if(attitudes[i].type.id == id)
				return true;
		return false;
	}

	int getNextAttitudeCost(Empire& emp) {
		if(emp.FreeAttitudes > 0)
			return 0;
		return config::ATTITUDE_BASE_COST + config::ATTITUDE_INC_COST * max(int(attitudes.length)-1, 0);
	}

	void readAttitudes(Message& msg, bool initial) {
		uint cnt = msg.readSmall();
		attitudes.length = cnt;

		for(uint i = 0; i < cnt; ++i) {
			if(msg.readBit())
				msg >> attitudes[i];
		}
	}
};

