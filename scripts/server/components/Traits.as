import traits;
import attitudes;
import attributes;
import saving;

tidy class TraitData {
	const Trait@ trait;
	array<any> data;
};

tidy class Traits : Component_Traits, Savable {
	array<TraitData@> traits;
	array<bool> hasTraits(getTraitCount(), false);

	array<Attitude@> attitudes;
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
		return traits[index].trait.id;
	}

	void addTrait(Empire& emp, uint id, bool doPreInit = false) {
		auto@ trait = getTrait(id);
		if(trait is null)
			throw("Invalid trait.");

		TraitData dat;
		@dat.trait = trait;
		traits.insertLast(dat);
		hasTraits[trait.id] = true;
		if(doPreInit)
			dat.trait.preInit(emp, dat.data);
	}

	void replaceTrait(Empire& emp, uint fromId, uint toId, bool doPreInit = true) {
		auto@ fromType = getTrait(fromId);
		auto@ toType = getTrait(toId);
		if(fromType is null || toType is null)
			return;

		for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
			if(traits[i].trait is fromType) {
				@traits[i].trait = toType;
				if(doPreInit)
					toType.preInit(emp, traits[i].data);
				hasTraits[fromType.id] = false;
				hasTraits[toType.id] = true;
				break;
			}
		}
	}

	void preInitTraits(Empire& emp) {
		for(uint i = 0, cnt = traits.length; i < cnt; ++i)
			traits[i].trait.preInit(emp, traits[i].data);
	}

	void initTraits(Empire& emp) {
		for(uint i = 0, cnt = traits.length; i < cnt; ++i)
			traits[i].trait.init(emp, traits[i].data);
	}

	void postInitTraits(Empire& emp) {
		for(uint i = 0, cnt = traits.length; i < cnt; ++i)
			traits[i].trait.postInit(emp, traits[i].data);
	}

	void traitsTick(Empire& emp, double time) {
		for(uint i = 0, cnt = traits.length; i < cnt; ++i)
			traits[i].trait.tick(emp, traits[i].data, time);

		{
			WriteLock lck(attMtx);
			for(uint i = 0, cnt = attitudes.length; i < cnt; ++i)
				attitudes[i].tick(emp, time);
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

	void takeAttitude(Empire& emp, uint id) {
		WriteLock lck(attMtx);
		if(hasAttitude(id))
			return;

		auto@ type = getAttitudeType(id);
		if(type is null)
			return;

		if(!type.canTake(emp))
			return;

		if(emp.FreeAttitudes > 0) {
			emp.modAttribute(EA_FreeAttitudes, AC_Add, -1.0);
		}
		else {
			int cost = getNextAttitudeCost(emp);
			if(emp.Influence < cost)
				return;
			if(!emp.consumeInfluence(cost))
				return;
		}

		forceAttitude(emp, id);

		if(emp.AttitudeStartLevel > 0)
			levelAttitude(emp, id, int(emp.AttitudeStartLevel));
	}

	void forceAttitude(Empire& emp, uint id) {
		WriteLock lck(attMtx);
		if(hasAttitude(id))
			return;

		auto@ type = getAttitudeType(id);
		if(type is null)
			return;

		Attitude att;
		@att.type = type;

		attitudes.insertLast(att);
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i)
			attitudes[i].delta = true;

		att.start(emp);
	}

	void discardAttitude(Empire& emp, uint id) {
		WriteLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id) {
				@att = attitudes[i];
				break;
			}
		}

		if(att is null)
			return;

		int cost = att.getDiscardCost(emp);
		if(emp.Influence < cost)
			return;
		if(!emp.consumeInfluence(cost))
			return;

		forceDiscardAttitude(emp, id);
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

	void forceDiscardAttitude(Empire& emp, uint id) {
		WriteLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id) {
				@att = attitudes[i];
				break;
			}
		}

		if(att is null)
			return;

		att.end(emp);
		attitudes.remove(att);
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i)
			attitudes[i].delta = true;
	}

	void levelAttitude(Empire& emp, uint id, int levels) {
		WriteLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id) {
				@att = attitudes[i];
				break;
			}
		}

		if(att is null)
			return;

		uint newLevel = clamp(int(att.level) + levels, 0, att.type.levels.length);
		if(newLevel == att.level)
			return;

		if(newLevel == 0)
			att.progress = 0;
		else
			att.progress = att.levels[newLevel].threshold;
		att.delta = true;
		att.checkProgress(emp);
	}

	void progressAttitude(Empire& emp, uint id, double progress, double pct) {
		WriteLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id) {
				@att = attitudes[i];
				break;
			}
		}

		if(att is null)
			return;

		uint curLevel = att.level;
		uint nextLevel = att.nextLevel;
		if(curLevel == nextLevel)
			return;

		double prevThres = 0;
		if(curLevel != 0)
			prevThres = att.levels[curLevel].threshold;
		double nextThres = att.levels[nextLevel].threshold;

		att.progress += progress + (nextThres - prevThres) * pct;
		att.delta = true;
		att.checkProgress(emp);
	}

	void resetAttitude(Empire& emp, uint id) {
		WriteLock lck(attMtx);
		Attitude@ att;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].type.id == id) {
				@att = attitudes[i];
				break;
			}
		}

		if(att is null)
			return;

		att.progress = 0.0;
		att.delta = true;
		att.checkProgress(emp);
	}

	uint getLevelAttitudeCount(uint level) {
		ReadLock lck(attMtx);

		uint count = 0;
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			if(attitudes[i].level >= level)
				count += 1;
		}
		return count;
	}

	void save(SaveFile& file) {
		uint cnt = traits.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file.writeIdentifier(SI_Trait, traits[i].trait.id);
			traits[i].trait.save(traits[i].data, file);
		}

		cnt = attitudes.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << attitudes[i];
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ trait = getTrait(file.readIdentifier(SI_Trait));
			if(trait !is null) {
				TraitData dat;
				@dat.trait = trait;
				trait.load(dat.data, file);
				hasTraits[trait.id] = true;

				traits.insertLast(dat);
			}
		}

		if(file >= SV_0147) {
			file >> cnt;
			attitudes.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				Attitude att;
				file >> att;

				@attitudes[i] = att;
			}
		}
	}

	void writeTraits(Message& msg) {
		uint cnt = traits.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg.writeSmall(traits[i].trait.id);
	}

	void writeAttitudes(Message& msg, bool initial) {
		uint cnt = attitudes.length;
		msg.writeSmall(cnt);

		for(uint i = 0; i < cnt; ++i) {
			if(initial || attitudes[i].delta) {
				msg.write1();
				msg << attitudes[i];
				if(!initial)
					attitudes[i].delta = false;
			}
			else {
				msg.write0();
			}
		}
	}
};
