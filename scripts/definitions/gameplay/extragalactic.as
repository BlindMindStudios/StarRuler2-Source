#priority init 1500
import generic_hooks;
from bonus_effects import BonusEffect;

import resources;

#section server
import systems;
import regions.regions;
import object_creation;
import attributes;
import oddity_navigation;

const ResourceClass@ foodClass;
const ResourceClass@ waterClass;
const ResourceClass@ scalableClass;

void init() {
	@foodClass = getResourceClass("Food");
	@waterClass = getResourceClass("WaterType");
	@scalableClass = getResourceClass("Scalable");

	coordination.length = getEmpireCount();
}

void EGCoordinationTick(Empire& emp, double time) {
	auto@ coord = getCoordinate(emp);
	if(coord !is null)
		coord.tick(emp, time);
}

bool checkSlot(uint index, const ResourceType@ resource) {
	switch(index) {
		case 0:
			return resource.cls is foodClass;
		case 1:
			return resource.cls is waterClass;
		case 2:
			return resource.level == 1;
		case 3:
			return resource.level == 2;
	}
	return false;
}

final class Coordinate : Savable {
	Mutex mtx;
	array<Planet@> slots(4);

	double sendTimer = 0.0;

	set_int targetIds;
	array<Planet@> curTargets;
	array<ColonyShip@> curShips;

	set_int penaltyIds;
	array<Planet@> curPenalties;
	array<double> penaltiesUntil;

	array<RefugeeData@> spreading;

	void tick(Empire& emp, double time) {
		if(spreading.length == 0)
			return;

		Lock lck(mtx);

		//Update colony targets
		for(int i = curTargets.length-1; i >= 0; --i) {
			Planet@ pl = curTargets[i];
			ColonyShip@ colShip = curShips[i];

			if(colShip is null || !colShip.valid || pl is null || !pl.valid) {
				curTargets.removeAt(i);
				curShips.removeAt(i);

				if(pl !is null) {
					targetIds.erase(pl.id);

					Empire@ owner = pl.owner;
					if(owner !is emp && owner !is null && owner.valid) {
						if(!penaltyIds.contains(pl.id)) {
							curPenalties.insertLast(pl);
							penaltiesUntil.insertLast(gameTime + 90.0);
							penaltyIds.insert(pl.id);
						}
					}
				}
			}
		}

		//Update colony penalties
		double curTime = gameTime;
		for(int i = curPenalties.length-1; i >= 0; --i) {
			if(curTime >= penaltiesUntil[i]) {
				if(curPenalties[i] !is null)
					penaltyIds.erase(curPenalties[i].id);
				penaltiesUntil.removeAt(i);
				curPenalties.removeAt(i);
			}
		}

		//Manage resource type slots
		for(uint i = 0, cnt = slots.length; i < cnt; ++i) {
			Planet@ pl = slots[i];
			if(pl is null)
				continue;
			if(!pl.valid) {
				@slots[i] = null;
				continue;
			}

			Empire@ owner = pl.owner;
			if(owner !is emp && owner !is null) {
				if(owner.valid) {
					@slots[i] = null;
					continue;
				}
				else if(!targetIds.contains(pl.id)) {
					@slots[i] = null;
					continue;
				}
			}

			if(owner is emp && pl.primaryResourceUsable) {
				uint resLevel = pl.primaryResourceLevel;
				uint plLevel = pl.level;
				if(resLevel >= 2 || plLevel > resLevel || pl.primaryResourceExported) {
					@slots[i] = null;
					continue;
				}
			}
		}

		//Send colonizations
		double speed = 1.0;
		speed *= max(pow(emp.TotalPopulation / 10.0, 0.6), 1.0);

		//Slow down expansion speed for lower difficulty AIs
		if(emp.isAI) {
			int diff = emp.difficulty;
			if(diff == 0)
				speed *= 0.3;
			else if(diff == 1)
				speed *= 0.65;
		}

		sendTimer -= time * speed;

		if(sendTimer <= 0.0) {
			Planet@ bestPlanet;
			RefugeeData@ bestBeacon;
			double bestWeight = 0.0;

			uint cnt = spreading.length;
			uint offset = randomi(0, cnt-1);
			for(uint i = 0; i < cnt; ++i) {
				uint index = (i+offset) % cnt;
				auto@ rd = spreading[index];
				if(rd.obj is null || !rd.obj.valid) {
					spreading.removeAt(index);
					--i; --cnt;
					continue;
				}

				Planet@ pl = rd.nextTarget;
				if(pl !is null) {
					double w = getWeight(emp, rd, pl);
					if(rd.lastBeacon)
						w *= 0.9;
					if(w > bestWeight) {
						@bestPlanet = pl;
						@bestBeacon = rd;
						bestWeight = w;
					}
				}

				rd.lastBeacon = false;
			}

			if(bestPlanet !is null) {
				send(bestBeacon.obj, bestPlanet);
				@bestBeacon.nextTarget = null;
				bestBeacon.lastBeacon = true;
				sendTimer += 60.0;
			}
		}
	}

	double getWeight(Empire& emp, RefugeeData& rd, Planet& pl) {
		Empire@ owner = pl.visibleOwnerToEmp(emp);
		double w = 1.0;

		//Deal with sending population to planets that aren't full
		if(owner is emp) {
			double curPop = pl.population;
			double maxPop = pl.maxPopulation;
			if(curPop >= maxPop - 0.0001)
				return 0.0;

			//Track how much population we're currently sending
			for(uint j = 0, jcnt = curTargets.length; j < jcnt; ++j) {
				if(curTargets[j] is pl)
					curPop += 1.0;
			}

			if(curPop < double(maxPop) - 0.0001)
				w *= 200.0;
			else
				return 0.0;
		}
		else if(owner is null || owner.valid) {
			return 0.0;
		}
		else {
			//Don't target quarantined planets
			if(pl.quarantined)
				return 0.0;
			//Don't colonize twice
			if(targetIds.contains(pl.id))
				return 0.0;
			if(penaltyIds.contains(pl.id))
				return 0.0;
		}

		//Deal with slots for particular types of resources
		auto@ resource = getResource(pl.primaryResourceType);
		if(resource is null)
			return 0.0;

		for(uint i = 0, cnt = slots.length; i < cnt; ++i) {
			if(slots[i] !is null)
				continue;
			if(checkSlot(i, resource)) {
				w *= 100.0;
				break;
			}
		}

		//Deal with generic resource value
		if(resource.cls is foodClass)
			w *= 1.5;
		else if(resource.cls is waterClass)
			w *= 1.5;

		w /= ceil(pl.position.distanceTo(rd.obj.position) / 5000.0);
		return w;
	}

	void save(SaveFile& file) {
		file << sendTimer;
		for(uint i = 0, cnt = slots.length; i < cnt; ++i)
			file << slots[i];

		uint cnt = curTargets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << curTargets[i];
			file << curShips[i];
		}

		cnt = curPenalties.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << curPenalties[i];
			file << penaltiesUntil[i];
		}
	}

	void load(SaveFile& file) {
		file >> sendTimer;
		for(uint i = 0, cnt = slots.length; i < cnt; ++i)
			file >> slots[i];

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Planet@ targ;
			ColonyShip@ ship;
			file >> targ;
			file >> ship;

			if(targ !is null && ship !is null) {
				curTargets.insertLast(targ);
				curShips.insertLast(ship);
				targetIds.insert(targ.id);
			}
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Planet@ targ;
			double until = 0.0;
			file >> targ;
			file >> until;

			if(targ !is null) {
				curPenalties.insertLast(targ);
				penaltiesUntil.insertLast(until);
				penaltyIds.insert(targ.id);
			}
		}
	}

	void send(Empire& emp, Planet@ toPlanet) {
		Object@ best;
		double bestDist = INFINITY;
		for(uint i = 0, cnt = spreading.length; i < cnt; ++i) {
			Object@ obj = spreading[i].obj;
			if(obj is null || !obj.valid)
				continue;

			double d = getPathDistance(emp, obj.position, toPlanet.position);
			if(d < bestDist) {
				@best = obj;
				bestDist = d;
			}
		}

		if(best !is null)
			send(best, toPlanet);
	}

	void send(Object@ obj, Planet@ bestPlanet) {
		auto@ resource = getResource(bestPlanet.primaryResourceType);
		if(resource !is null) {
			for(uint i = 0, cnt = slots.length; i < cnt; ++i) {
				if(slots[i] !is null)
					continue;
				if(checkSlot(i, resource)) {
					@slots[i] = bestPlanet;
					break;
				}
			}
		}

		auto@ colShip = createColonizer(obj, bestPlanet, 1.0, 1.0);
		if(colShip !is null) {
			curTargets.insertLast(bestPlanet);
			curShips.insertLast(colShip);
			targetIds.insert(bestPlanet.id);
		}
	}
};

void save(SaveFile& file) {
	uint cnt = coordination.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << coordination[i];
}

void load(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;
	coordination.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		file >> coordination[i];
}

array<Coordinate> coordination;
Coordinate@ getCoordinate(Empire@ emp) {
	if(emp is null)
		return null;
	if(uint(emp.index) >= coordination.length)
		return null;
	return coordination[emp.index];
}

final class SysData {
	Region@ region;
	array<Planet@> planets;
};

final class RefugeeData : Savable {
	Object@ obj;

	double updateTimer = 0.0;
	bool lastBeacon = false;
	bool registered = false;

	Planet@ nextTarget;

	array<SysData@>@ systems;
	array<SysData@>@ updateData;
	bool foundGate = false;
	uint sysUpdate = 0;

	void save(SaveFile& file) {
		file << obj;
		file << updateTimer;
		file << lastBeacon;
	}

	void load(SaveFile& file) {
		file >> obj;
		file >> updateTimer;
		file >> lastBeacon;
	}
};

#section all

class RefugeeColonization : GenericEffect {
	Document doc("Automatically sends population to nearby planets with colony/refugee ships.");

#section server
	void enable(Object& obj, any@ data) const override {
		RefugeeData rd;
		@rd.obj = obj;

		data.store(@rd);

		{
			auto@ coord = getCoordinate(obj.owner);
			Lock lck(coord.mtx);
			coord.spreading.insertLast(rd);
			rd.registered = true;
		}
	}

	void disable(Object& obj, any@ data) const override {
		RefugeeData@ rd;
		data.retrieve(@rd);

		if(rd !is null) {
			auto@ coord = getCoordinate(obj.owner);
			Lock lck(coord.mtx);
			coord.spreading.remove(rd);
			rd.registered = false;
		}
	}

	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		RefugeeData@ rd;
		data.retrieve(@rd);

		if(prevOwner !is null) {
			auto@ coord = getCoordinate(prevOwner);
			Lock lck(coord.mtx);
			coord.spreading.remove(rd);
		}
		if(newOwner !is null) {
			auto@ coord = getCoordinate(newOwner);
			Lock lck(coord.mtx);
			coord.spreading.insertLast(rd);
			rd.registered = true;
		}
	}

	void tick(Object& obj, any@ data, double time) const override {
		RefugeeData@ rd;
		data.retrieve(@rd);

		if(rd.nextTarget is null)
			rd.updateTimer -= time * 10.0;
		else
			rd.updateTimer -= time;
		if(!rd.registered) {
			auto@ coord = getCoordinate(obj.owner);
			if(coord !is null) {
				Lock lck(coord.mtx);
				rd.registered = true;
				coord.spreading.insertLast(rd);
			}
		}
		if(rd.updateTimer <= 0.0 && rd.systems !is null) {
			rd.updateTimer += randomd(10.0, 20.0);
			Empire@ emp = obj.owner;

			auto@ coord = getCoordinate(emp);
			Lock lck(coord.mtx);

			//Send colonizations
			Region@ reg = obj.region;
			if(reg is null)
				@reg = findNearestRegion(obj.position);

			Planet@ bestPlanet;
			double bestWeight = 0.0;

			for(uint i = 0, cnt = rd.systems.length; i < cnt; ++i) {
				auto@ sys = rd.systems[i];
				for(uint n = 0, ncnt = sys.planets.length; n < ncnt; ++n) {
					Planet@ pl = sys.planets[n];

					double w = coord.getWeight(emp, rd, pl);
					if(w > bestWeight) {
						bestWeight = w;
						@bestPlanet = pl;
					}
				}
			}

			@rd.nextTarget = bestPlanet;
		}

		//Update our internal representation of the surrounding area
		if(rd.updateData is null || rd.sysUpdate >= rd.updateData.length) {
			if(rd.updateData !is null)
				@rd.systems = rd.updateData;
			@rd.updateData = array<SysData@>();
			rd.sysUpdate = 0;
			rd.foundGate = false;

			Region@ reg = obj.region;
			if(reg is null)
				@reg = findNearestRegion(obj.position);

			set_int visited;
			visitSystem(obj.owner, rd, reg, visited);
		}
		else {
			updateSystem(obj.owner, rd, rd.updateData[rd.sysUpdate]);
			rd.sysUpdate += 1;
		}
	}

	void updateSystem(Empire& emp, RefugeeData& rd, SysData& sys) const {
		if(sys.region.planetCount == sys.planets.length)
			return;

		sys.planets.length = 0;

		auto@ datalist = sys.region.getPlanets();
		Object@ obj;
		while(receive(datalist, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(pl !is null)
				sys.planets.insertLast(pl);
		}
	}

	void visitSystem(Empire& emp, RefugeeData& rd, Region& reg, set_int& visited) const {
		visited.insert(reg.id);

		bool found = false;
		if(rd.systems !is null) {
			for(uint i = 0, cnt = rd.systems.length; i < cnt; ++i) {
				if(rd.systems[i].region is reg) {
					rd.updateData.insertLast(rd.systems[i]);
					found = true;
					break;
				}
			}
		}
		if(!found) {
			SysData sd;
			@sd.region = reg;
			rd.updateData.insertLast(sd);
		}

		uint curPresent = reg.PlanetsMask;
		bool isBorder = curPresent & ~(emp.mask | emp.ForcedPeaceMask.value) != 0;
		bool isEmpty = curPresent & emp.mask == 0;

		auto@ system = getSystem(reg);
		for(uint i = 0, cnt = system.spatialAdjacentCount; i < cnt; ++i) {
			auto@ other = getSystem(system.spatialAdjacent[i]);
			if(other is null)
				continue;
			if(other.object.SeenMask & emp.mask == 0)
				continue;
			if(visited.contains(other.object.id))
				continue;

			uint present = other.object.PlanetsMask;
			if(present & emp.mask == 0) {
				if(present & ~emp.ForcedPeaceMask.value != 0 && isBorder)
					continue;
				if(isEmpty)
					continue;
			}

			visitSystem(emp, rd, other.object, visited);
		}

		//Can't do this: beacons themselves are gatemask for trade even though they can't port
		//if(!rd.foundGate && reg.GateMask & emp.mask != 0 && !isEmpty) {
		//	rd.foundGate = true;
		//	for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
		//		auto@ sys = getSystem(i);
		//		if(sys.object.GateMask & emp.mask == 0)
		//			continue;
		//		if(sys.object is reg)
		//			continue;
		//		if(visited.contains(sys.object.id))
		//			continue;

		//		visitSystem(emp, rd, sys.object, visited);
		//	}
		//}
	}

	void save(any@ data, SaveFile& file) const override {
		RefugeeData@ rd;
		data.retrieve(@rd);
		if(data !is null)
			file << rd;
		else
			file << RefugeeData();
	}

	void load(any@ data, SaveFile& file) const override {
		RefugeeData rd;
		file >> rd;
		data.store(@rd);
	}
#section all
};

class TriggerRefugees : BonusEffect {
	Document doc("Immediately trigger the next refugee ship to leave to the targeted planet.");

#section server
	void activate(Object@ target, Empire@ emp) const override {
		if(emp is null)
			return;
		if(target is null || !target.isPlanet)
			return;

		auto@ coord = getCoordinate(emp);
		{
			Lock lck(coord.mtx);
			coord.send(emp, cast<Planet>(target));
		}
	}
#section all
};
