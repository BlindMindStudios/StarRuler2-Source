import abilities;
import saving;
import hooks;
import systems;
import attributes;
import achievements;

tidy class Abilities : Component_Abilities, Savable {
	int nextAbilityId = 0;
	Ability@[] abilities;
	bool delta = false;
	bool neutralAbilities = false;
	bool abilityDestroy = false;

	void setNeutralAbilities(bool value) {
		neutralAbilities = value;
	}

	void setAbilityDestroy(bool value) {
		abilityDestroy = value;
	}

	void initAbilities(Object& obj, const Design@ fromDesign) {
		array<Ability@> subsysAbilities;
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(abilities[i].subsystem !is null) {
				subsysAbilities.insertLast(abilities[i]);
				abilities.removeAt(i);
				--i; --cnt;
			}
		}
		uint sysCnt = fromDesign.subsystemCount;
		for(uint i = 0; i < sysCnt; ++i) {
			const Subsystem@ sys = fromDesign.subsystems[i];
			uint cnt = sys.type.getTagValueCount(ST_Ability);
			for(uint i = 0; i < cnt; ++i) {
				const AbilityType@ type = getAbilityType(sys.type.getTagValue(ST_Ability, i));
				if(type !is null) {
					bool found = false;
					for(uint i = 0, cnt = subsysAbilities.length; i < cnt; ++i) {
						auto@ abl = subsysAbilities[i];
						if(abl.type is type) {
							@abl.subsystem = sys;
							found = true;
							abilities.insertLast(abl);
							subsysAbilities.removeAt(i);
							break;
						}
					}

					if(!found)
						addAbility(obj, type, sys);
				}
			}
		}
		for(uint i = 0, cnt = subsysAbilities.length; i < cnt; ++i) {
			auto@ abl = subsysAbilities[i];
			if(!abl.disabled)
				abl.disable();
			abl.destroy();
		}
		delta = true;
	}

	void destroyAbilities() {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i)
			abilities[i].destroy();
	}

	uint get_abilityTypes(int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return uint(-1);
		return abl.type.id;
	}

	Ability@ getAbilityOfType(int type) {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			auto@ abl = abilities[i];
			if(abl.disabled || abl.cooldown > 0)
				continue;
			if(abl.type.id == uint(type))
				return abl;
		}
		return null;
	}

	void createAbility(Object& obj, uint id) {
		addAbility(obj, id);
	}

	int addAbility(Object& obj, uint id) {
		const AbilityType@ type = getAbilityType(id);
		if(type !is null) {
			delta = true;
			return addAbility(obj, type).id;
		}
		return -1;
	}

	void removeAbility(Object& obj, int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(!abl.disabled)
			abl.disable();
		abl.destroy();
		abilities.remove(abl);
		delta = true;
	}

	void disableAbility(Object& obj, int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(!abl.disabled) {
			abl.disable();
			abl.disabled = true;
			delta = true;
		}
	}

	void enableAbility(Object& obj, int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(abl.disabled) {
			abl.enable();
			abl.disabled = false;
			delta = true;
		}
	}

	Ability@ addAbility(Object& obj, const AbilityType@ type, const Subsystem@ sys = null) {
		Ability abl(type);
		abl.id = nextAbilityId++;
		@abl.subsystem = sys;
		@abl.obj = obj;
		@abl.emp = obj.owner;

		abilities.insertLast(abl);
		abl.create();
		abl.enable();
		return abl;
	}

	void setCooldownForType(int typeId, double cooldown) {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(int(abilities[i].type.id) == typeId) {
				abilities[i].cooldown = cooldown;
				delta = true;
			}
		}
	}

	void abilityOwnerChange(Object& obj, Empire@ prevOwner, Empire@ newOwner) {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i)
			@abilities[i].emp = newOwner;
	}

	void save(SaveFile& file) {
		uint cnt = abilities.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << abilities[i];
		file << nextAbilityId;
		file << neutralAbilities;
		file << abilityDestroy;
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		abilities.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			Ability abl;
			file >> abl;
			@abilities[i] = abl;
		}

		file >> nextAbilityId;
		file >> neutralAbilities;
		file >> abilityDestroy;
	}

	void abilityTick(Object& obj, double time) {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			auto@ abl = abilities[i];
			if(!abl.disabled) {
				if(abl.cooldown > 0) {
					abl.cooldown = max(0.0, abl.cooldown - time);
					delta = true;
				}
				abl.tick(time);
			}
		}
	}

	Ability@ getAbility(int id) {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if(abilities[i].id == id)
				return abilities[i];
		}
		return null;
	}

	uint get_abilityCount() const {
		return abilities.length;
	}

	void getAbilities() const {
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i)
			yield(abilities[i]);
	}
	
	int findAbilityOfType(int type) const {
		auto@ abl = getAbilityOfType(type);
		if(abl is null)
			return -1;
		else
			return abl.id;
	}

	void triggerAbility(Empire@ emp, Object& obj, int id, Targets@ targs) {
		if(!obj.valid || obj.destroying)
			return;
		Ability@ abl = getAbility(id);
		if(abl is null)
			return;
		if(abl.disabled || abl.cooldown > 0)
			return;
		if(emp !is null) {
			if(neutralAbilities) {
				//Check for trade access for cast
				Region@ reg = obj.region;
				if(reg is null)
					return;
				if(reg.PlanetsMask != 0) {
					if(reg.PlanetsMask & emp.mask == 0)
						return;
				}
				else {
					const SystemDesc@ sys = getSystem(reg);
					bool found = false;
					for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
						const SystemDesc@ other = getSystem(sys.adjacent[i]);
						if(other.object.TradeMask & emp.mask != 0) {
							found = true;
							break;
						}
					}
					if(!found)
						return;
				}
			}
			else {
				//Only the owner can cast
				if(emp !is obj.owner)
					return;
			}
			if(obj.isArtifact) {
				emp.modAttribute(EA_ArtifactsActivated, AC_Add, 1.0);
				giveAchievement(emp, "ACH_USE_ARTIFACT");
			}
			@abl.emp = emp;
		}
		if(abl.activate(targs)) {
			if(abilityDestroy)
				obj.destroy();
		}
		delta = true;
	}

	void triggerAbility(Player& pl, Object& obj, int id, Targets@ targs) {
		triggerAbility(pl != SERVER_PLAYER ? pl.emp : null, obj, id, targs);
	}

	bool isAbilityOnCooldown(int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return false;
		return abl.cooldown > 0;
	}

	void activateAbility(Player& pl, Object& obj, int id) {
		triggerAbility(pl, obj, id, null);
	}

	void activateAbility(Player& pl, Object& obj, int id, vec3d point) {
		Targets targs;
		targs.add(TT_Point, fill=true).point = point;
		triggerAbility(pl, obj, id, targs);
	}

	void activateAbility(Player& pl, Object& obj, int id, Object@ target) {
		Targets targs;
		@targs.add(TT_Object, fill=true).obj = target;
		triggerAbility(pl, obj, id, targs);
	}

	void activateAbilityFor(Object& obj, Empire& emp, int id) {
		triggerAbility(emp, obj, id, null);
	}

	void activateAbilityFor(Object& obj, Empire& emp, int id, vec3d point) {
		Targets targs;
		targs.add(TT_Point, fill=true).point = point;
		triggerAbility(emp, obj, id, targs);
	}

	void activateAbilityFor(Object& obj, Empire& emp, int id, Object@ target) {
		Targets targs;
		@targs.add(TT_Object, fill=true).obj = target;
		triggerAbility(emp, obj, id, targs);
	}
	
	void activateAbilityTypeFor(Object& obj, Empire& emp, int type) {
		auto@ abl = getAbilityOfType(type);
		if(abl !is null)
			activateAbilityFor(obj, emp, abl.id);
	}
	
	void activateAbilityTypeFor(Object& obj, Empire& emp, int type, Object@ target) {
		auto@ abl = getAbilityOfType(type);
		if(abl !is null)
			activateAbilityFor(obj, emp, abl.id, target);
	}
	
	void activateAbilityTypeFor(Object& obj, Empire& emp, int type, vec3d point) {
		auto@ abl = getAbilityOfType(type);
		if(abl !is null)
			activateAbilityFor(obj, emp, abl.id, point);
	}

	bool isChanneling(int id) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return false;
		return abl.isChanneling();
	}

	double getAbilityRange(int id, Object@ target) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return 0;
		return abl.getRange();
	}

	double getAbilityRange(int id, vec3d target) {
		Ability@ abl = getAbility(id);
		if(abl is null)
			return 0;
		return abl.getRange();
	}

	void writeAbilities(Message& msg) const {
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

