import statuses;

tidy class Statuses : Component_Statuses {
	array<Status@> statuses;

	void getStatusEffects(Player& pl, Object& obj) {
		Empire@ plEmp = pl.emp;
		for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
			if(!statuses[i].isVisibleTo(obj, plEmp))
				continue;
			yield(statuses[i]);
		}
	}

	uint get_statusEffectCount() {
		return statuses.length;
	}

	uint get_statusEffectType(uint index) {
		if(index >= statuses.length)
			return uint(-1);
		return statuses[index].type.id;
	}

	uint get_statusEffectStacks(uint index) {
		if(index >= statuses.length)
			return 0;
		return statuses[index].stacks;
	}

	Object@ get_statusEffectOriginObject(uint index) {
		if(index >= statuses.length)
			return null;
		return statuses[index].originObject;
	}

	Empire@ get_statusEffectOriginEmpire(uint index) {
		if(index >= statuses.length)
			return null;
		return statuses[index].originEmpire;
	}

	uint getStatusStackCountAny(uint typeId) {
		uint count = 0;
		for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
			if(statuses[i].type.id == typeId)
				count += statuses[i].stacks;
		}
		return count;
	}

	uint getStatusStackCount(uint typeId, Object@ originObject = null, Empire@ originEmpire = null) {
		uint count = 0;
		for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
			if(statuses[i].type.id == typeId && statuses[i].originObject is originObject && statuses[i].originEmpire is originEmpire)
				count += statuses[i].stacks;
		}
		return count;
	}

	bool hasStatusEffect(uint typeId) {
		for(uint i = 0, cnt = statuses.length; i < cnt; ++i) {
			if(statuses[i].type.id == typeId)
				return true;
		}
		return false;
	}

	void readStatuses(Message& msg) {
		uint cnt = msg.readSmall();
		statuses.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(statuses[i] is null)
				@statuses[i] = Status();
			msg >> statuses[i];
		}
	}

	void readStatusDelta(Message& msg) {
		readStatuses(msg);
	}
};
