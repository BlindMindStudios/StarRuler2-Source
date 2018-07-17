import systems;

Territory@ createTerritory(Empire@ emp) {
	ObjectDesc tdesc;
	tdesc.type = OT_Territory;
	@tdesc.owner = emp;
	tdesc.flags |= objNoPhysics;
	tdesc.position = vec3d();

	return cast<Territory>(makeObject(tdesc));
}

final class TerritoryManager {
	int tid = 0;
	uint sysIndex = 0;
	array<int> territories(systemCount, -1);
	array<Territory@> terrObjects(systemCount);
	array<Territory@> tidObjects;

	array<Territory@> activeTerritories;

	void save(SaveFile& file) {
		uint cnt = terrObjects.length;
		for(uint i = 0; i < cnt; ++i)
			file << terrObjects[i];
		for(uint i = cnt; i < systemCount; ++i) {
			int tmp = -1;
			file << tmp;
		}
		cnt = tidObjects.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << tidObjects[i];
	}

	void load(SaveFile& file) {
		uint cnt = systemCount;
		for(uint i = 0; i < cnt; ++i)
			file >> terrObjects[i];
		file >> cnt;
		tidObjects.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> tidObjects[i];
	}

	void finalize(Empire@ emp) {
		//Map tids to actual territory objects
		set_int usedTerritories;
		tidObjects.length = uint(tid);
		for(int i = 0; i < tid; ++i)
			@tidObjects[i] = null;

		//First pass: find existing objects we can reuse
		for(uint i = 0, cnt = territories.length; i < cnt; ++i) {
			int cur = territories[i];
			if(cur != -1) {
				Territory@ terr = terrObjects[i];
				if(terr !is null && tidObjects[cur] is null && !usedTerritories.contains(terr.id)) {
					@tidObjects[cur] = terr;
					usedTerritories.insert(terr.id);
				}
			}
		}

		//Create territories that weren't found
		for(int i = 0; i < tid; ++i) {
			if(tidObjects[i] is null) {
				@tidObjects[i] = createTerritory(emp);
				activeTerritories.insertLast(tidObjects[i]);
			}
		}

		//Second pass: assign to correct territories
		for(uint i = 0, cnt = territories.length; i < cnt; ++i) {
			SystemDesc@ desc = getSystem(i);
			int cur = territories[i];
			if(cur == -1) {
				if(terrObjects[i] !is null) {
					desc.object.setTerritory(emp, null);
					terrObjects[i].remove(desc.object);
					@terrObjects[i] = null;
				}
			}
			else {
				Territory@ prev = terrObjects[i];
				Territory@ next = tidObjects[cur];
				usedTerritories.insert(next.id);
				if(prev !is next) {
					if(prev !is null)
						prev.remove(desc.object);
					if(next !is null)
						next.add(desc.object);
					@terrObjects[i] = next;
					desc.object.setTerritory(emp, next);
				}
			}

			//Clear for next pass
			territories[i] = -1;
		}

		//Check if any territories need to be destroyed
		for(int i = activeTerritories.length - 1; i >= 0; --i) {
			Territory@ terr = activeTerritories[i];
			if(!usedTerritories.contains(terr.id)) {
				terr.destroy();
				activeTerritories.removeAt(i);
			}
		}

		//Update system counts
		if(territories.length != systemCount) {
			uint oldCnt = territories.length;
			territories.length = systemCount;
			terrObjects.length = systemCount;
			for(uint i = oldCnt; i < systemCount; ++i) {
				territories[i] = -1;
				@terrObjects[i] = null;
			}
		}
	}

	void search(Empire@ emp, SystemDesc@ desc, int tid) {
		territories[desc.index] = tid;

		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			uint adj = desc.adjacent[i];
			if(adj >= territories.length || territories[adj] == tid)
				continue;

			SystemDesc@ other = getSystem(adj);
			if(other.object.TradeMask & emp.mask != 0)
				search(emp, other, tid);
		}
	}

	bool update(Empire@ emp, double time) {
		uint sysCnt = territories.length;
		if(sysIndex >= sysCnt) {
			finalize(emp);
			sysIndex = 0;
			tid = 0;
			return true;
		}

		uint amt = max(50.0, time * 500.0);
		uint mask = emp.mask;
		for(uint i = 0; i < amt && sysIndex < sysCnt; ++i) {
			if(territories[sysIndex] != -1) {
				++sysIndex;
				continue;
			}

			SystemDesc@ desc = getSystem(sysIndex);

			//Ignore systems we can't trade through
			if(desc.object.TradeMask & mask == 0) {
				++sysIndex;
				continue;
			}

			//Do a search from this position and mark everything from it
			//as the same territory
			search(emp, desc, tid);
			++tid;
			++sysIndex;
		}

		return false;
	}
};

ScriptThread@ thread;
array<TerritoryManager> managers;
uint index = 0;

double update(double time, ScriptThread& thread) {
	if(managers[index].update(getEmpire(index), time))
		index = (index+1) % managers.length;
	return 0.1;
}

void init() {
	if(isLoadedSave)
		return;
	managers.length = getEmpireCount();
	@thread = ScriptThread("update", null);
}

void save(SaveFile& file) {
	for(uint i = 0, cnt = managers.length; i < cnt; ++i)
		managers[i].save(file);
}

void load(SaveFile& file) {
	managers.length = getEmpireCount();
	for(uint i = 0, cnt = managers.length; i < cnt; ++i)
		managers[i].load(file);
	@thread = ScriptThread("update", null);
}
