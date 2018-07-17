import resources;
import saving;
import ftl;
import planet_levels;
import object_creation;
import cargo;

tidy class ColonizationEvent : Savable, Serializable {
	Object@ from;
	Object@ to;

	void save(SaveFile& file) {
		file << from;
		file << to;
	}

	void load(SaveFile& file) {
		file >> from;
		file >> to;
	}

	void write(Message& msg) {
		msg << from;
		msg << to;
	}

	void read(Message& msg) {
		msg >> from;
		msg >> to;
	}
};

const Design@ getDefenseDesign(Empire& owner, double defenseRate, double tolerance = 1.0, bool satellite = false, int maxSize = -1) {
	const Design@ defenseDesign;

	double laborV = defenseRate * 60.0;
	double optMin = laborV / (10.0 * tolerance), optMax = laborV / (2.0 / tolerance);

	double totalWeight = 0.0;

	ReadLock lock(owner.designMutex);
	uint designCount = owner.designCount;
	for(uint i = 0; i < designCount; ++i) {
		const Design@ dsg = owner.designs[i];
		if(dsg.obsolete)
			continue;
		if(dsg.newest() !is dsg)
			continue;
		if(satellite) {
			if(!dsg.hasTag(ST_Satellite))
				continue;
		}
		else {
			if(!dsg.hasTag(ST_Support))
				continue;
		}
		if(maxSize > 0 && dsg.size > maxSize)
			continue;
		if(dsg.hasTag(ST_HasMaintenanceCost))
			continue;
		if(hasDesignCosts(dsg))
			continue;

		double cost = getLaborCost(dsg, 1);

		double weight = 100.0;
		weight += dsg.built * dsg.size;

		if(cost < optMin)
			weight *= pow(0.5, optMin / cost);
		else if(cost > optMax)
			weight *= pow(0.5, cost / optMax);

		if(weight <= 0.0)
			continue;
		totalWeight += weight;
		if(randomd() < weight / totalWeight)
			@defenseDesign = dsg;
	}
	return defenseDesign;
}

tidy class AutoImport : Savable, AutoImportDesc {
	void save(SaveFile& file) {
		file << to;
		file << handled;
		if(cls !is null) {
			file.write1();
			file << cls.ident;
		}
		else {
			file.write0();
		}
		file << level;
		if(type !is null) {
			file.write1();
			file.writeIdentifier(SI_Resource, type.id);
		}
		else {
			file.write0();
		}
	}

	void load(SaveFile& file) {
		file >> to;
		if(file >= SV_0058)
			file >> handled;
		if(file >= SV_0052) {
			string clsname;
			if(file.readBit()) {
				file >> clsname;
				@cls = getResourceClass(clsname);
			}
			else {
				@cls = null;
			}
			file >> level;
			if(file.readBit())
				@type = getResource(file.readIdentifier(SI_Resource));
			else
				@type = null;
		}
		else {
			string clsname;
			file >> clsname;
			@cls = getResourceClass(clsname);
		}
	}

	void addTo(Empire& emp, Object& obj) {
		const ResourceType@ type = getResource(0);
		int id = 0;
		if(cls !is null) {
			@type = cls.types[0];
			id = cls.id;
		}
		if(level != -1) {
			id |= level << 16;
		}

		if(this.type !is null) {
			id = -int(this.type.id);
			@type = this.type;
		}
		else {
			for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
				auto@ res = getResource(i);
				if(res.displayWeight < 0)
					continue;
				if(res.artificial)
					continue;
				if(cls !is null && res.cls !is cls)
					continue;
				if(level != -1 && res.level != uint(level))
					continue;
				@type = res;
				break;
			}
		}

		obj.addQueuedImport(emp, null, id, type.id);
	}

	void removeFrom(Empire& emp, Object& obj) {
		int id = 0;
		if(cls !is null)
			id = int(cls.id);
		if(this.type !is null)
			id = -int(this.type.id);
		if(level != -1)
			id |= level << 16;
		obj.removeQueuedImport(emp, null, id);
	}
};

tidy class ObjectManager : Component_ObjectManager, Savable {
	ReadWriteMutex plMutex;
	Planet@[] planets;
	Asteroid@[] asteroids;

	ReadWriteMutex orbMutex;
	Orbital@[] Orbitals;

	Mutex flingMutex;
	Object@[] flingBeacons;

	Mutex gateMutex;
	Object@[] gates;

	Mutex artifMutex;
	Artifact@[] artifacts;

	ColonizationEvent@[] colonizations;
	set_int colonizationSet;

	ColonizationEvent@[] queuedAutoColonizations;
	set_int queuedSet;

	array<Object@> autoColonizers;
	array<int> autoColonizeAbls;

	ReadWriteMutex defenseMtx;
	array<Object@> defenseObjects;
	set_int defenseSet;

	const Design@ defenseDesign;
	double defenseRate = 0;
	double defenseStorage = 0;
	double defenseStored = 0;
	double localDefenseRate = 0;
	double defenseLabor = -1;

	bool objDelta = false;
	bool defDelta = false;
	bool colonizeDelta = false;
	bool autoImportDelta = false;

	Mutex tradeMtx;
	array<Region@> tradeRequests;

	AutoImport@[] autoImports;

	void requestTradeCivilian(Region@ toRegion) {
		Lock lck(tradeMtx);
		if(tradeRequests.find(toRegion) == -1)
			tradeRequests.insertLast(toRegion);
	}

	void stopRequestTradeCivilian(Region@ toRegion) {
		Lock lck(tradeMtx);
		tradeRequests.remove(toRegion);
	}

	Region@ getTradeCivilianRequest(vec3d position) {
		Lock lck(tradeMtx);
		Region@ closest;
		double dist = INFINITY;
		for(uint i = 0, cnt = tradeRequests.length; i < cnt; ++i) {
			double d = position.distanceToSQ(tradeRequests[i].position);
			if(d < dist) {
				dist = d;
				@closest = tradeRequests[i];
			}
		}
		return closest;
	}
	
	bool get_hasPlanets() {
		return planets.length != 0;
	}

	void getPlanets() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = planets.length; i < cnt; ++i)
			yield(planets[i]);
	}

	uint get_planetCount() {
		return planets.length;
	}

	Planet@ get_planetList(uint index) {
		ReadLock lock(plMutex);
		if(index >= planets.length)
			return null;
		return planets[index];
	}

	void bumpPlanetUpdate() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = planets.length; i < cnt; ++i)
			planets[i].bumpResourceModId();
	}

	uint get_autoColonizeCount() {
		return queuedAutoColonizations.length;
	}

	uint get_orbitalCount() {
		return Orbitals.length;
	}

	Orbital@ get_orbitals(uint index) {
		ReadLock lock(orbMutex);
		if(index >= Orbitals.length)
			return null;
		return Orbitals[index];
	}

	Orbital@ getClosestOrbital(uint type, const vec3d& position) {
		ReadLock lock(orbMutex);
		Orbital@ closest;
		double closestDist = INFINITY;
		for(uint i = 0, cnt = Orbitals.length; i < cnt; ++i) {
			Orbital@ orb = Orbitals[i];
			if(orb.coreModule == type) {
				double d = orb.position.distanceToSQ(position);
				if(d < closestDist) {
					closestDist = d;
					@closest = orb;
				}
			}
		}
		return closest;
	}

	void getAsteroids() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = asteroids.length; i < cnt; ++i)
			yield(asteroids[i]);
	}

	void getFlingBeacons() {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i)
			yield(flingBeacons[i]);
	}

	void getStargates() {
		Lock lock(gateMutex);
		for(uint i = 0, cnt = gates.length; i < cnt; ++i)
			yield(gates[i]);
	}

	void getArtifacts() {
		Lock lock(artifMutex);
		for(uint i = 0, cnt = artifacts.length; i < cnt; ++i)
			yield(artifacts[i]);
	}

	void getOrbitals() {
		ReadLock lock(orbMutex);
		for(uint i = 0, cnt = Orbitals.length; i < cnt; ++i)
			yield(Orbitals[i]);
	}

	Orbital@ getOrbitalAfter(int id) {
		ReadLock lock(orbMutex);
		for(uint i = 0, cnt = Orbitals.length; i < cnt; ++i) {
			if(Orbitals[i].id > id)
				return Orbitals[i];
		}
		return null;
	}

	bool isFlingBeacon(Object@ obj) {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i)
			if(flingBeacons[i] is obj)
				return true;
		return false;
	}

	bool isStargate(Object@ obj) {
		Lock lock(gateMutex);
		for(uint i = 0, cnt = gates.length; i < cnt; ++i)
			if(gates[i] is obj)
				return true;
		return false;
	}

	void getQueuedColonizations(Empire& emp) {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = colonizations.length; i < cnt; ++i) {
			if(colonizations[i].to.owner !is emp)
				yield(colonizations[i].to);
		}
		for(uint i = 0, cnt = queuedAutoColonizations.length; i < cnt; ++i) {
			auto@ q = queuedAutoColonizations[i];
			if(q.to.owner !is emp && q.from is null)
				yield(q.to);
		}
	}
	
	bool get_hasFlingBeacons() {
		return flingBeacons.length != 0;
	}

	Object@ getFlingBeacon(vec3d position) {
		Lock lock(flingMutex);
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			Object@ beacon = flingBeacons[i];
			if(beacon.position.distanceToSQ(position) < FLING_BEACON_RANGE_SQ)
				return beacon;
		}
		return null;
	}

	Object@ getClosestFlingBeacon(vec3d position) {
		Lock lock(flingMutex);
		Object@ nearest;
		double dist = 0;
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			Object@ beacon = flingBeacons[i];
			double d = beacon.position.distanceToSQ(position);
			if(nearest is null || d < dist) {
				@nearest = beacon;
				dist = d;
			}
		}
		return nearest;
	}

	Object@ getClosestFlingBeacon(Object& obj) {
		Lock lock(flingMutex);
		Object@ nearest;
		double dist = 0;
		for(uint i = 0, cnt = flingBeacons.length; i < cnt; ++i) {
			Object@ beacon = flingBeacons[i];
			if(beacon is obj)
				continue;
			double d = beacon.position.distanceToSQ(obj.position);
			if(nearest is null || d < dist) {
				@nearest = beacon;
				dist = d;
			}
		}
		return nearest;
	}

	Object@ getStargate(vec3d position) {
		Lock lock(gateMutex);
		Object@ best;
		double bestDist = INFINITY;
		for(uint i = 0, cnt = gates.length; i < cnt; ++i) {
			Object@ gate = gates[i];
			double d = gate.position.distanceToSQ(position);
			if(d < bestDist) {
				bestDist = d;
				@best = gate;
			}
		}
		return best;
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		planets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@planets[i] = cast<Planet>(file.readObject());

		file >> cnt;
		asteroids.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@asteroids[i] = cast<Asteroid>(file.readObject());

		file >> cnt;
		Orbitals.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@Orbitals[i] = cast<Orbital>(file.readObject());

		file >> cnt;
		flingBeacons.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@flingBeacons[i] = file.readObject();

		file >> cnt;
		gates.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@gates[i] = file.readObject();

		if(file >= SV_0029) {
			file >> cnt;
			artifacts.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				@artifacts[i] = cast<Artifact>(file.readObject());
		}

		file >> cnt;
		colonizations.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@colonizations[i] = ColonizationEvent();
			file >> colonizations[i];
			colonizationSet.insert(colonizations[i].to.id);
		}

		file >> cnt;
		queuedAutoColonizations.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@queuedAutoColonizations[i] = ColonizationEvent();
			file >> queuedAutoColonizations[i];
			queuedSet.insert(queuedAutoColonizations[i].to.id);
		}

		file >> cnt;
		autoImports.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@autoImports[i] = AutoImport();
			file >> autoImports[i];
		}

		if(file >= SV_0048) {
			file >> cnt;
			tradeRequests.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				@tradeRequests[i] = cast<Region>(file.readObject());
		}

		if(file >= SV_0088) {
			file >> cnt;
			defenseObjects.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				file >> defenseObjects[i];
				if(defenseObjects[i] !is null)
					defenseSet.insert(defenseObjects[i].id);
			}
			file >> defenseDesign;
			file >> defenseRate;
			file >> defenseLabor;
			if(file >= SV_0125)
				file >> localDefenseRate;
			if(file >= SV_0141) {
				file >> defenseStorage;
				file >> defenseStored;
			}

			if(file >= SV_0139) {
				file >> cnt;
				autoColonizers.length = cnt;
				autoColonizeAbls.length = cnt;
				for(uint i = 0; i < cnt; ++i) {
					file >> autoColonizers[i];
					file >> autoColonizeAbls[i];
				}
			}
		}
	}

	void save(SaveFile& file) {
		uint cnt = planets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << planets[i];

		cnt = asteroids.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << asteroids[i];

		cnt = Orbitals.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << Orbitals[i];

		cnt = flingBeacons.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << flingBeacons[i];

		cnt = gates.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << gates[i];

		cnt = artifacts.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << artifacts[i];

		cnt = colonizations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << colonizations[i];

		cnt = queuedAutoColonizations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << queuedAutoColonizations[i];

		cnt = autoImports.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << autoImports[i];

		cnt = tradeRequests.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << tradeRequests[i];

		cnt = defenseObjects.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << defenseObjects[i];
		file << defenseDesign;
		file << defenseRate;
		file << defenseLabor;
		file << localDefenseRate;
		file << defenseStorage;
		file << defenseStored;

		cnt = autoColonizers.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << autoColonizers[i];
			file << autoColonizeAbls[i];
		}
	}

	void registerPlanet(Empire& emp, Planet@ pl) {
		checkAutoImport(emp, pl);

		WriteLock lock(plMutex);
		planets.insertLast(pl);
		objDelta = true;
	}

	void unregisterPlanet(Planet@ pl) {
		WriteLock lock(plMutex);
		planets.remove(pl);
		objDelta = true;
	}

	void registerAsteroid(Empire& emp, Asteroid@ obj) {
		checkAutoImport(emp, obj);

		WriteLock lock(plMutex);
		asteroids.insertLast(obj);
		objDelta = true;
	}

	void unregisterAsteroid(Asteroid@ obj) {
		WriteLock lock(plMutex);
		asteroids.remove(obj);
		objDelta = true;
	}

	void registerOrbital(Empire& emp, Orbital@ obj) {
		WriteLock lock(orbMutex);
		Orbitals.insertLast(obj);
		objDelta = true;
	}

	void unregisterOrbital(Orbital@ obj) {
		WriteLock lock(orbMutex);
		Orbitals.remove(obj);
		objDelta = true;
	}

	void registerFlingBeacon(Object@ obj) {
		Lock lock(flingMutex);
		flingBeacons.insertLast(obj);
		objDelta = true;
	}

	void unregisterFlingBeacon(Object@ obj) {
		Lock lock(flingMutex);
		flingBeacons.remove(obj);
		objDelta = true;
	}

	void registerStargate(Empire& emp, Object@ obj) {
		emp.PathId += 1;
		Lock lock(gateMutex);
		gates.insertLast(obj);
		objDelta = true;
	}

	void unregisterStargate(Object@ obj) {
		Lock lock(gateMutex);
		gates.remove(obj);
		objDelta = true;
	}

	void registerArtifact(Artifact@ obj) {
		Lock lock(artifMutex);
		artifacts.insertLast(obj);
		objDelta = true;
	}

	void unregisterArtifact(Artifact@ obj) {
		Lock lock(artifMutex);
		artifacts.remove(obj);
		objDelta = true;
	}

	bool hasStargates() {
		return gates.length != 0;
	}

	double get_globalDefenseRate() {
		return defenseRate + localDefenseRate;
	}

	double get_globalDefenseStorage() {
		return defenseStorage;
	}

	double get_globalDefenseStored() {
		return defenseStored;
	}

	bool isDefending(Object@ obj) {
		if(obj is null)
			return false;
		ReadLock lck(defenseMtx);
		return defenseSet.contains(obj.id);
	}

	bool get_hasDefending() {
		return defenseObjects.length > 0 || defenseStored < defenseStorage;
	}

	void modDefenseRate(double value) {
		WriteLock lck(defenseMtx);
		defenseRate += value;
		defDelta = true;
	}

	void modLocalDefense(double value) {
		WriteLock lck(defenseMtx);
		localDefenseRate += value;
		defDelta = true;
	}

	void modDefenseStorage(double value) {
		WriteLock lck(defenseMtx);
		defenseStorage += value;
		defenseStored = min(defenseStored, defenseStorage);
		defDelta = true;
	}

	void getDefending() {
		ReadLock lck(defenseMtx);
		for(uint i = 0, cnt = defenseObjects.length; i < cnt; ++i)
			yield(defenseObjects[i]);
	}

	void spawnDefenseAt(Empire& owner, Object& spawnAt, double defense) {
		const Design@ dsg;
		double labor = 0;

		while(defense > 0) {
			if(dsg is null) {
				@dsg = getDefenseDesign(owner, defense / 60.0);
				if(dsg is null)
					return;
				labor = getLaborCost(dsg, 1);
			}

			double take = min(defense, labor);
			labor -= take;
			defense -= take;

			if(labor <= 0) {
				if(spawnAt.isRegion) {
					spawnAt.spawnSupportAtRandomPlanet(owner, dsg);
				}
				else if(spawnAt.hasLeaderAI) {
					dsg.decBuilt(); //automatic built doesn't increment
					createShip(spawnAt, dsg, owner, spawnAt, false, true);
				}

				@dsg = null;
			}
		}
	}

	void setDefending(Object@ obj, bool value) {
		if(obj is null)
			return;
		objDelta = true;
		WriteLock lck(defenseMtx);
		if(value) {
			if(defenseSet.contains(obj.id))
				return;

			defenseSet.insert(obj.id);
			defenseObjects.insertLast(obj);
		}
		else {
			if(!defenseSet.contains(obj.id))
				return;

			defenseSet.erase(obj.id);
			defenseObjects.remove(obj);
		}
	}

	void deployDefense(Empire& emp, Object& at) {
		double spawn = 0;
		{
			WriteLock lck(defenseMtx);
			if(!at.hasSurfaceComponent)
				return;
			if(defenseStorage <= 0)
				return;
			if(defenseStored < defenseStorage*0.9999)
				return;

			spawn = defenseStored;
			defenseStored = 0;
		}
		if(at.hasSurfaceComponent)
			at.spawnDefenseShips(spawn);
		else
			spawnDefenseAt(emp, at, spawn);
	}

	void generateDefense(Empire& owner, double defense) {
		if(defenseStored < defenseStorage) {
			double take = min(defenseStorage - defenseStored, defense);
			if(take != 0) {
				defenseStored = min(defenseStored+take, defenseStorage);
				defense -= take;
				defDelta = true;
			}
			if(defense <= 0.001)
				return;
		}

		Planet@ fallback = null;
		if(owner.Homeworld !is null) {
			@fallback = owner.Homeworld;
			if(fallback !is null) {
				if(!fallback.valid || fallback.owner !is owner || !fallback.canGainSupports)
					@fallback = null;
			}
		}
		if(fallback is null) {
			if(planets.length > 0) {
				ReadLock lock(plMutex);
				if(planets.length > 0)
					@fallback = planets[0];
			}
			if(fallback !is null) {
				if(!fallback.valid || fallback.owner !is owner || !fallback.canGainSupports)
					@fallback = null;
			}
		}

		WriteLock lck(defenseMtx);
		while(defense > 0) {
			if(defenseDesign is null) {
				@defenseDesign = getDefenseDesign(owner, max(defenseRate, defense / 60.0));
				if(defenseDesign is null)
					return;
				defenseLabor = getLaborCost(defenseDesign, 1);
			}

			double take = min(defense, defenseLabor);
			defenseLabor -= take;
			defense -= take;

			if(defenseLabor <= 0) {
				uint cnt = defenseObjects.length;
				uint index = randomi(0, cnt-1);
				Object@ spawnAt;

				uint i = 0;
				while(spawnAt is null && i < cnt) {
					@spawnAt = defenseObjects[index];

					if(spawnAt.isRegion) {
						Region@ reg = cast<Region>(spawnAt);
						if(reg.PlanetsMask & owner.mask == 0)
							@spawnAt = null;
					}
					else if(spawnAt.isPlanet) {
						if(spawnAt.owner !is owner || !spawnAt.canGainSupports)
							@spawnAt = null;
					}
					else if(spawnAt.hasLeaderAI) {
						Region@ reg = spawnAt.region;
						if(!spawnAt.valid || spawnAt.owner !is owner)
							@spawnAt = null;
						else if(reg is null || reg.TradeMask & owner.TradeMask.value == 0)
							@spawnAt = null;
						else if(spawnAt.SupplyUsed + uint(defenseDesign.size) > spawnAt.SupplyCapacity)
							@spawnAt = null;
					}
					else {
						@spawnAt = null;
					}

					++i;
					index = (index+1)%cnt;
				}

				if(spawnAt is null)
					@spawnAt = fallback;
				if(spawnAt !is null) {
					//Build defense at planets in the projected system
					if(spawnAt.isRegion) {
						spawnAt.spawnSupportAtRandomPlanet(owner, defenseDesign, fallback = fallback);
					}
					else if(spawnAt.hasLeaderAI) {
						defenseDesign.decBuilt(); //automatic built doesn't increment
						createShip(spawnAt, defenseDesign, owner, spawnAt, false, true);
					}

					defenseLabor = -1.0;
					@defenseDesign = null;
				}
				else {
					return;
				}
			}
		}
	}
	
	Object@ findFreeResource(Empire& emp, AutoImport@ imp, vec3d closeTo) {
		double dist = INFINITY;
		Object@ found;

		ReadLock lock(plMutex);

		//Find in currently colonized planets
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			Planet@ pl = planets[i];
			const ResourceType@ type = getResource(pl.primaryResourceType);
			if(type is null || !type.exportable)
				continue;
			if(!imp.satisfies(type))
				continue;
			if(type.isMaterial(pl.level))
				continue;
			if(!pl.nativeResourceUsable[0])
				continue;
			Object@ dest = pl.getNativeResourceDestination(emp, 0);
			if(dest is null) {
				double d = closeTo.distanceToSQ(pl.position);
				if(pl.population < 1.0)
					d *= 10000.0;
				if(d < dist) {
					dist = d;
					@found = pl;
				}
			}
		}

		//Find in asteroids
		for(uint i = 0, cnt = asteroids.length; i < cnt; ++i) {
			Asteroid@ roid = asteroids[i];
			const ResourceType@ type = getResource(roid.primaryResourceType);
			if(type is null || !type.exportable)
				continue;
			if(!imp.satisfies(type))
				continue;
			if(!roid.nativeResourceUsable[0])
				continue;
			Object@ dest = roid.getNativeResourceDestination(emp, 0);
			if(dest is null) {
				double d = closeTo.distanceToSQ(roid.position);
				if(d < dist) {
					dist = d;
					@found = roid;
				}
			}
		}

		return found;
	}

	void autoImportResourceOfClass(Empire& emp, Object& into, uint resClsId) {
		const ResourceClass@ cls = getResourceClass(resClsId);
		if(cls is null)
			return;

		AutoImport imp;
		@imp.to = into;
		@imp.cls = cls;

		Object@ current = findFreeResource(emp, imp, into.position);
		if(current !is null) {
			current.exportResource(emp, 0, into);
		}
		else {
			imp.addTo(emp, into);

			WriteLock lock(plMutex);
			autoImports.insertLast(imp);
			autoImportDelta = true;
		}
	}

	void autoImportResourceOfLevel(Empire& emp, Object& into, uint level) {
		AutoImport imp;
		@imp.to = into;
		imp.level = int(level);

		Object@ current = findFreeResource(emp, imp, into.position);
		if(current !is null) {
			current.exportResource(emp, 0, into);
		}
		else {
			imp.addTo(emp, into);

			WriteLock lock(plMutex);
			autoImports.insertLast(imp);
			autoImportDelta = true;
		}
	}

	void autoImportResourceOfType(Empire& emp, Object& into, uint typeId) {
		AutoImport imp;
		@imp.to = into;
		@imp.type = getResource(typeId);
		if(imp.type is null)
			return;

		Object@ current = findFreeResource(emp, imp, into.position);
		if(current !is null) {
			current.exportResource(emp, 0, into);
		}
		else {
			imp.addTo(emp, into);

			WriteLock lock(plMutex);
			autoImports.insertLast(imp);
			autoImportDelta = true;
		}
	}

	void autoImportToLevel(Empire& emp, Object& into, uint level) {
		cancelAutoImportTo(emp, into);

		auto@ lvl = getPlanetLevel(into, level);
		if(lvl is null)
			return;
		auto@ reqs = lvl.reqs;

		array<int> remaining;

		Resources available;
		receive(into.getResourceAmounts(), available);

		array<Resource> resources;
		resources.syncFrom(into.getQueuedImportsFor(emp));
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			available.modAmount(r.type, +1);
		}

		if(reqs.satisfiedBy(available, null, true, remaining))
			return;

		for(uint i = 0, cnt = reqs.reqs.length; i < cnt; ++i) {
			auto@ req = reqs.reqs[i];
			for(uint n = 0, ncnt = remaining[i]; n < ncnt; ++n) {
				switch(req.type) {
					case RRT_Resource:
						autoImportResourceOfType(emp, into, req.resource.id);
					break;
					case RRT_Class:
					case RRT_Class_Types:
						autoImportResourceOfClass(emp, into, req.cls.id);
					break;
					case RRT_Level:
					case RRT_Level_Types:
						autoImportResourceOfLevel(emp, into, req.level);
					break;
				}
			}
		}
	}

	void getAutoImports() {
		ReadLock lock(plMutex);
		for(uint i = 0, cnt = autoImports.length; i < cnt; ++i) {
			if(!autoImports[i].handled)
				yield(autoImports[i]);
		}
	}

	void checkAutoImport(Empire& emp, Object@ from) {
		if(autoImports.length == 0)
			return;
		
		if(!from.nativeResourceUsable[0])
			return;
		const ResourceType@ res = getResource(from.primaryResourceType);
		if(res is null)
			return;

		Object@ dest = from.getNativeResourceDestination(emp, 0);
		if(dest !is null)
			return;

		WriteLock lock(plMutex);
		Object@ best;
		Empire@ bestOwner;
		double bestWeight = INFINITY;
		uint bestIndex = 0;
		for(uint i = 0, cnt = autoImports.length; i < cnt; ++i) {
			AutoImport@ imp = autoImports[i];
			if(imp.handled)
				continue;
			if(!imp.satisfies(res))
				continue;

			Empire@ owner = imp.to.owner;
			double weight = from.position.distanceToSQ(imp.to.position);
			if((bestOwner !is emp && owner is emp) || weight < bestWeight) {
				bestWeight = weight;
				@bestOwner = owner;
				@best = imp.to;
				bestIndex = i;
			}
		}

		if(best !is null) {
			auto@ imp = autoImports[bestIndex];
			imp.handled = true;

			from.exportResource(emp, 0, best);
		}
	}

	void gotImportFor(Empire& emp, Object@ forObj, uint resId) {
		if(forObj is null)
			return;

		const ResourceType@ res = getResource(resId);
		if(res is null)
			return;

		WriteLock lock(plMutex);
		for(uint i = 0, cnt = autoImports.length; i < cnt; ++i) {
			AutoImport@ imp = autoImports[i];
			if(!imp.handled)
				continue;
			if(imp.to !is forObj)
				continue;
			if(!imp.satisfies(res, alreadyPresent=true))
				continue;

			imp.removeFrom(emp, forObj);
			autoImports.removeAt(i);
			autoImportDelta = true;
			return;
		}
		for(uint i = 0, cnt = autoImports.length; i < cnt; ++i) {
			AutoImport@ imp = autoImports[i];
			if(imp.handled)
				continue;
			if(imp.to !is forObj)
				continue;
			if(!imp.satisfies(res, alreadyPresent=true))
				continue;

			imp.removeFrom(emp, forObj);
			autoImports.removeAt(i);
			autoImportDelta = true;
			return;
		}
	}
	
	void cancelAutoImportTo(Empire& emp, Object& into) {
		WriteLock lock(plMutex);
		
		for(int i = int(autoImports.length) - 1; i >= 0; --i) {
			AutoImport@ imp = autoImports[i];
			if(!imp.handled && imp.to is into) {
				autoImports.removeAt(i);
				autoImportDelta = true;
				imp.removeFrom(emp, into);
			}
		}
	}

	void cancelAutoImportLevelTo(Empire& emp, Object& into, uint level) {
		WriteLock lock(plMutex);
		for(int i = int(autoImports.length) - 1; i >= 0; --i) {
			AutoImport@ imp = autoImports[i];
			if(!imp.handled && imp.to is into && imp.level == int(level)) {
				autoImports.removeAt(i);
				autoImportDelta = true;
				imp.removeFrom(emp, into);
				return;
			}
		}
	}

	void cancelAutoImportClassTo(Empire& emp, Object& into, uint clsId) {
		WriteLock lock(plMutex);
		for(int i = int(autoImports.length) - 1; i >= 0; --i) {
			AutoImport@ imp = autoImports[i];
			if(!imp.handled && imp.to is into && imp.cls !is null && imp.cls.id == clsId) {
				autoImports.removeAt(i);
				autoImportDelta = true;
				imp.removeFrom(emp, into);
				return;
			}
		}
	}

	void cancelAutoImportTo(Empire& emp, Object& into, uint resId) {
		auto@ res = getResource(resId);

		WriteLock lock(plMutex);
		for(int i = int(autoImports.length) - 1; i >= 0; --i) {
			AutoImport@ imp = autoImports[i];
			if(!imp.handled && imp.to is into && imp.satisfies(res)) {
				autoImports.removeAt(i);
				autoImportDelta = true;
				imp.removeFrom(emp, into);
				return;
			}
		}
	}

	void registerColonization(Empire& emp, Object@ from, Object@ to) {
		ColonizationEvent evt;
		@evt.to = to;
		@evt.from = from;

		//Inform the planet
		to.setBeingColonized(emp, true);

		WriteLock lock(plMutex);
		colonizationSet.insert(to.id);
		colonizations.insertLast(evt);
		colonizeDelta = true;
	}

	void unregisterColonization(Empire& emp, Object@ from, Object@ to, bool cancel) {
		colonizeDelta = true;
		bool remaining = false;
		{
			WriteLock lock(plMutex);

			//Remove colonization event record
			for(uint i = 0, cnt = colonizations.length; i < cnt; ++i) {
				ColonizationEvent@ evt = colonizations[i];
				if(evt.from is from && evt.to is to) {
					colonizationSet.erase(to.id);
					colonizations.removeAt(i);
					--i; --cnt;
				}
				else if(evt.to is to) {
					remaining = true;
					break;
				}
			}

			//Check to remove autocolonization order
			if(queuedSet.contains(to.id)) {
				uint qcnt = queuedAutoColonizations.length;
				for(uint n = 0; n < qcnt; ++n) {
					ColonizationEvent@ evt = queuedAutoColonizations[n];
					if(evt.to is to) {
						if(cancel) {
							queuedSet.erase(to.id);
							queuedAutoColonizations.removeAt(n);
						}
						else {
							@evt.from = null;
							remaining = true;
						}
						break;
					}
				}
			}
			else {
				if(!cancel) {
					//Add it back as an auto-colonization
					autoColonize(emp, to);
					remaining = true;
				}
			}
		}

		//Inform the planet
		if(!remaining)
			to.setBeingColonized(emp, false);
	}

	void cancelColonization(Empire& emp, Object@ to) {
		colonizeDelta = true;
		bool remaining = false;
		{
			WriteLock lock(plMutex);

			//Find the planet sourcing this
			if(colonizationSet.contains(to.id)) {
				for(uint i = 0, cnt = colonizations.length; i < cnt; ++i) {
					ColonizationEvent@ evt = colonizations[i];
					if(evt.to is to) {
						evt.from.stopColonizing(to);
						remaining = true;
					}
				}
			}

			//Remove from queued
			if(queuedSet.contains(to.id)) {
				uint qcnt = queuedAutoColonizations.length;
				for(uint n = 0; n < qcnt; ++n) {
					ColonizationEvent@ evt = queuedAutoColonizations[n];
					if(evt.to is to) {
						queuedAutoColonizations.removeAt(n);
						break;
					}
				}
				queuedSet.erase(to.id);
			}
		}

		//Inform the planet
		if(!remaining)
			to.setBeingColonized(emp, false);
	}

	void planetTick(Empire& emp, double time) {
		if(queuedAutoColonizations.length != 0 && (emp.ForbidColonization == 0.0 || autoColonizers.length != 0)) {
			WriteLock lock(plMutex);
			for(uint i = 0, qcnt = queuedAutoColonizations.length; i < qcnt; ++i) {
				ColonizationEvent@ evt = queuedAutoColonizations[i];
				if(!evt.to.valid || (evt.to.owner is emp && evt.to.population >= 1.0)
						|| (evt.to.owner.valid && evt.to.owner !is emp && evt.to.isVisibleTo(emp)))
				{
					queuedAutoColonizations.remove(evt);
					queuedSet.erase(evt.to.id);
					evt.to.setBeingColonized(emp, false);
					colonizeDelta = true;
					return;
				}

				if(evt.from !is null)
					continue;
				if(evt.to.quarantined)
					continue;

				//Find planet to auto-colonize from
				if(emp.ForbidColonization == 0) {
					Planet@ best;
					double bestWeight = INFINITY;

					for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
						Planet@ cur = planets[i];
						if(cur.maxPopulation <= 1)
							continue;
						if(cur.isSendingColonyShips)
							continue;
						if(!cur.canSafelyColonize)
							continue;

						double w = cur.position.distanceTo(evt.to.position);
						w /= sqr(cur.population / double(cur.maxPopulation));

						if(w < bestWeight) {
							bestWeight = w;
							@best = cur;
						}
					}

					//Order colonization
					if(best !is null) {
						@evt.from = best;
						best.flagColonizing();
						best.colonize(evt.to);
					}
				}
				else {
					Object@ best;
					int abl = -1;
					double bestWeight = INFINITY;

					for(uint i = 0, cnt = autoColonizers.length; i < cnt; ++i) {
						Object@ cur = autoColonizers[i];
						if(cur is null)
							continue;
						if(cur.hasOrders)
							continue;
						if(cur.isMoving)
							continue;

						double w = cur.position.distanceTo(evt.to.position);
						if(w < bestWeight) {
							bestWeight = w;
							abl = autoColonizeAbls[i];
							@best = cur;
						}
					}

					if(best !is null) {
						best.addAbilityOrder(abl, evt.to, false);

						queuedAutoColonizations.remove(evt);
						queuedSet.erase(evt.to.id);
						--i; --qcnt;
					}
				}
			}
		}

		{
			WriteLock lock(defenseMtx);

			//Remove invalidated defense objects
			for(uint i = 0, cnt = defenseObjects.length; i < cnt; ++i) {
				auto@ obj = defenseObjects[i];
				bool valid = true;
				if(obj is null) {
					valid = false;
				}
				else if(obj.isRegion) {
					Region@ reg = cast<Region>(obj);
					if(reg.PlanetsMask & emp.mask == 0)
						valid = false;
				}
				else if(obj.isPlanet || obj.hasLeaderAI) {
					if(obj.owner !is emp)
						valid = false;
				}
				else {
					valid = false;
				}

				if(!valid) {
					defenseObjects.removeAt(i);
					if(obj !is null)
						defenseSet.erase(obj.id);
					objDelta = true;
					--i; --cnt;
				}
			}

			//Tick defense rate
			if(defenseRate > 0) {
				generateDefense(emp, defenseRate * time);
			}
		}
	}

	void autoColonize(Empire& emp, Object@ other) {
		ColonizationEvent evt;
		@evt.to = other;
		colonizeDelta = true;

		{
			WriteLock lock(plMutex);
			if(queuedSet.contains(other.id))
				return;
			queuedAutoColonizations.insertLast(evt);
			queuedSet.insert(other.id);
		}

		//Inform the planet
		other.setBeingColonized(emp, true);
	}

	Object@ popAutoColonizeTarget() {
		if(queuedAutoColonizations.length == 0)
			return null;

		WriteLock lock(plMutex);
		if(queuedAutoColonizations.length == 0)
			return null;
		uint index = 0;
		auto@ q = queuedAutoColonizations[index];
		if(q.to is null || q.from !is null)
			return null;
		queuedSet.erase(q.to.id);
		queuedAutoColonizations.removeAt(index);
		return q.to;
	}

	void pushAutoColonizeTarget(Object& obj) {
		WriteLock lock(plMutex);
		ColonizationEvent evt;
		@evt.to = obj;
		queuedAutoColonizations.insertAt(0, evt);
		queuedSet.insert(obj.id);
	}

	void registerAutoColonizer(Object& obj, int ablId) {
		WriteLock lock(plMutex);
		autoColonizers.insertLast(obj);
		autoColonizeAbls.insertLast(ablId);
	}

	void unregisterAutoColonizer(Object& obj, int ablId) {
		WriteLock lock(plMutex);
		for(uint i = 0, cnt = autoColonizers.length; i < cnt; ++i) {
			if(autoColonizers[i] is obj && autoColonizeAbls[i] == ablId) {
				autoColonizers.removeAt(i);
				autoColonizeAbls.removeAt(i);
				break;
			}
		}
	}

	void writeObjects(Message& msg, bool initial = false) {
		ReadLock rlock(plMutex);

		if(initial || defDelta) {
			msg.write1();

			msg << defenseRate;
			msg << localDefenseRate;
			msg << defenseStorage;
			msg << defenseStored;

			if(!initial)
				defDelta = false;
		}
		else {
			msg.write0();
		}

		if(initial || objDelta) {
			msg.write1();

			uint cnt = planets.length;
			msg << cnt;
			for(uint i = 0; i < cnt; ++i)
				msg << planets[i];

			cnt = asteroids.length;
			msg << cnt;
			for(uint i = 0; i < cnt; ++i)
				msg << asteroids[i];

			{
				ReadLock lock(orbMutex);
				cnt = Orbitals.length;
				msg << cnt;
				for(uint i = 0; i < cnt; ++i)
					msg << Orbitals[i];
			}

			{
				Lock lock(flingMutex);
				cnt = flingBeacons.length;
				msg << cnt;
				for(uint i = 0; i < cnt; ++i)
					msg << flingBeacons[i];
			}

			{
				Lock lock(gateMutex);
				cnt = gates.length;
				msg << cnt;
				for(uint i = 0; i < cnt; ++i)
					msg << gates[i];
			}

			{
				Lock lock(artifMutex);
				cnt = artifacts.length;
				msg << cnt;
				for(uint i = 0; i < cnt; ++i)
					msg << artifacts[i];
			}

			{
				ReadLock lock(defenseMtx);
				cnt = defenseObjects.length;
				msg << cnt;
				for(uint i = 0; i < cnt; ++i)
					msg << defenseObjects[i];
			}

			if(!initial)
				objDelta = false;
		}
		else {
			msg.write0();
		}

		if(initial || colonizeDelta) {
			msg.write1();

			uint cnt = colonizations.length;
			msg << cnt;
			for(uint i = 0; i < cnt; ++i)
				msg << colonizations[i];

			cnt = queuedAutoColonizations.length;
			msg << cnt;
			for(uint i = 0; i < cnt; ++i)
				msg << queuedAutoColonizations[i];

			if(!initial)
				colonizeDelta = false;
		}
		else {
			msg.write0();
		}

		if(initial || autoImportDelta) {
			msg.write1();

			uint cnt = autoImports.length;
			msg << cnt;

			for(uint i = 0; i < cnt; ++i)
				msg << autoImports[i];

			if(!initial)
				autoImportDelta = false;
		}
		else {
			msg.write0();
		}
	}
};
