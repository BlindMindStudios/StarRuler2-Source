import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Systems;

import planets.PlanetSurface;

import void relationRecordLost(AI& ai, Empire& emp, Object@ obj) from "empire_ai.weasel.Relations";

import buildings;
import saving;

final class BuildingRequest {
	int id = -1;
	PlanetAI@ plAI;
	AllocateBudget@ alloc;
	const BuildingType@ type;
	double expires = INFINITY;
	bool built = false;
	bool canceled = false;
	bool scatter = false;
	vec2i builtAt;

	BuildingRequest(Budget& budget, const BuildingType@ type, double priority, uint moneyType) {
		@this.type = type;
		@alloc = budget.allocate(moneyType, type.buildCostEst, type.maintainCostEst, priority=priority);
	}

	BuildingRequest() {
	}

	void save(Planets& planets, SaveFile& file) {
		planets.saveAI(file, plAI);
		planets.budget.saveAlloc(file, alloc);
		file.writeIdentifier(SI_Building, type.id);
		file << expires;
		file << built;
		file << canceled;
		file << builtAt;
		file << scatter;
	}

	void load(Planets& planets, SaveFile& file) {
		@plAI = planets.loadAI(file);
		@alloc = planets.budget.loadAlloc(file);
		@type = getBuildingType(file.readIdentifier(SI_Building));
		file >> expires;
		file >> built;
		file >> canceled;
		file >> builtAt;
		if(file >= SV_0153)
			file >> scatter;
	}

	double cachedProgress = 0.0;
	double nextProgressCache = 0.0;
	double getProgress() {
		if(!built)
			return 0.0;
		if(gameTime < nextProgressCache)
			return cachedProgress;

		cachedProgress = plAI.obj.getBuildingProgressAt(builtAt.x, builtAt.y);
		if(cachedProgress > 0.95)
			nextProgressCache = gameTime + 1.0;
		else if(cachedProgress < 0.5)
			nextProgressCache = gameTime + 30.0;
		else
			nextProgressCache = gameTime + 10.0;

		return cachedProgress;
	}

	bool tick(AI& ai, Planets& planets, double time) {
		if(expires < gameTime) {
			if(planets.log)
				ai.print(type.name+" build request expired", plAI.obj);
			canceled = true;
			return false;
		}

		if(alloc is null || alloc.allocated) {
			builtAt = plAI.buildBuilding(ai, planets, type, scatter=scatter);
			if(builtAt == vec2i(-1,-1)) {
				planets.budget.remove(alloc);
				canceled = true;
			}
			else
				built = true;
			return false;
		}
		return true;
	}
};

final class PlanetAI {
	Planet@ obj;
	int targetLevel = 0;
	int requestedLevel = 0;
	double prevTick = 0;
	array<ExportData@>@ resources;
	ImportData@ claimedChain;

	void init(AI& ai, Planets& planets) {
		@resources = planets.resources.availableResource(obj);
	}

	void save(Planets& planets, SaveFile& file) {
		file << obj;
		file << targetLevel;
		file << requestedLevel;
		file << prevTick;

		uint cnt = 0;
		if(resources !is null)
			cnt = resources.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			planets.resources.saveExport(file, resources[i]);
		planets.resources.saveImport(file, claimedChain);
	}

	void load(Planets& planets, SaveFile& file) {
		file >> obj;
		file >> targetLevel;
		file >> requestedLevel;
		file >> prevTick;
		uint cnt = 0;
		file >> cnt;
		@resources = array<ExportData@>();
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = planets.resources.loadExport(file);
			if(data !is null)
				resources.insertLast(data);
		}
		@claimedChain = planets.resources.loadImport(file);
	}

	void remove(AI& ai, Planets& planets) {
		if(claimedChain !is null) {
			claimedChain.claimedFor = false;
			@claimedChain = null;
		}
		@resources = null;
	}

	void tick(AI& ai, Planets& planets, double time) {
		//Deal with losing planet ownership
		if(obj is null || !obj.valid || obj.owner !is ai.empire) {
			if(obj.owner !is ai.empire)
				relationRecordLost(ai, obj.owner, obj);
			planets.remove(this);
			return;
		}

		//Handle when the planet's native resources change
		if(obj.nativeResourceCount != resources.length || (resources.length != 0 && obj.primaryResourceId != resources[0].resourceId))
			planets.updateResourceList(obj, resources);

		//Level up resources if we need them
		if(resources.length != 0 && claimedChain is null) {
			int resLevel = resources[0].resource.level;
			if(resLevel > 0 && !resources[0].resource.exportable)
				resLevel += 1;
			if(targetLevel < resLevel) {
				//See if we need it for anything first
				@claimedChain = planets.resources.findUnclaimed(resources[0]);
				if(claimedChain !is null)
					claimedChain.claimedFor = true;

				//Chain the levelup before what needs it
				planets.requestLevel(this, resLevel, before=claimedChain);
			}
		}

		//Request imports if the planet needs to level up
		if(targetLevel > requestedLevel) {
			int nextLevel = min(targetLevel, min(obj.resourceLevel, requestedLevel)+1);
			if(nextLevel != requestedLevel) {
				planets.resources.organizeImports(obj, nextLevel);
				requestedLevel = nextLevel;
			}
		}
		else if(targetLevel < requestedLevel) {
			planets.resources.organizeImports(obj, targetLevel);
			requestedLevel = targetLevel;
		}
	}

	double get_colonizeWeight() {
		if(obj.isColonizing)
			return 0.0;
		if(obj.level == 0)
			return 0.0;
		if(!obj.canSafelyColonize)
			return 0.0;
		double w = 1.0;
		double pop = obj.population;
		double maxPop = obj.maxPopulation;
		if(pop < maxPop-0.1) {
			if(obj.resourceLevel > 1 && pop/maxPop < 0.9)
				return 0.0;
			w *= 0.01 * (pop / maxPop);
		}
		return w;
	}

	vec2i buildBuilding(AI& ai, Planets& planets, const BuildingType@ type, bool scatter = true) {
		if(type is null || !type.canBuildOn(obj))
			return vec2i(-1,-1);

		if(planets.log)
			ai.print("Attempt to construct "+type.name, obj);

		PlanetSurface@ surface = planets.surface;
		receive(obj.getPlanetSurface(), surface);

		//Find the best place to build this building
		int bestPenalty = INT_MAX;
		int possibs = 0;
		vec2i best;
		vec2i center = vec2i(type.getCenter());

		for(int x = 0, w = surface.size.x; x < w; ++x) {
			for(int y = 0, h = surface.size.y; y < h; ++y) {
				vec2i pos(x, y);

				bool valid = true;
				int penalty = 0;

				for(int xoff = 0; xoff < int(type.size.x); ++xoff) {
					for(int yoff = 0; yoff < int(type.size.y); ++yoff) {
						vec2i rpos = pos - center + vec2i(xoff, yoff);

						if(rpos.x < 0 || rpos.y < 0 || rpos.x >= w || rpos.y >= h) {
							valid = false;
							break;
						}

						auto@ biome = surface.getBiome(rpos.x, rpos.y);
						if(biome is null || !biome.buildable) {
							valid = false;
							break;
						}

						uint flags = surface.getFlags(rpos.x, rpos.y);
						if(flags & SuF_Usable == 0) {
							bool affinity = false;
							if(type.buildAffinities.length != 0) {
								for(uint i = 0, cnt = type.buildAffinities.length; i < cnt; ++i) {
									if(biome is type.buildAffinities[i].biome) {
										affinity = true;
										break;
									}
								}
							}
							if(!affinity && type.tileBuildCost > 0) {
								penalty += 1;

								if(biome.buildCost > 1.0)
									penalty += ceil((biome.buildCost - 1.0) / 0.1);
							}
							affinity = false;
							if(type.maintainAffinities.length != 0) {
								for(uint i = 0, cnt = type.maintainAffinities.length; i < cnt; ++i) {
									if(biome is type.maintainAffinities[i].biome) {
										affinity = true;
										break;
									}
								}
							}
							if(!affinity && type.tileMaintainCost > 0)
								penalty += 2;
						}

						auto@ bld = surface.getBuilding(rpos.x, rpos.y);
						if(bld !is null) {
							if(bld.type.civilian) {
								penalty += 2;
							}
							else {
								valid = false;
								break;
							}
						}
					}
					if(!valid)
						break;
				}

				if(valid) {
					if(penalty < bestPenalty) {
						possibs = 1;
						bestPenalty = penalty;
						best = pos;
					}
					else if(penalty == bestPenalty && scatter) {
						possibs += 1;
						if(randomd() < 1.0 / double(possibs))
							best = pos;
					}
				}
			}
		}

		if(bestPenalty != INT_MAX) {
			if(planets.log)
				ai.print("Construct "+type.name+" at "+best+" with penalty "+bestPenalty, obj);
			obj.buildBuilding(type.id, best);
			return best;
		}

		if(planets.log)
			ai.print("Could not find place to construct "+type.name, obj);
		return vec2i(-1,-1);
	}
}

final class PotentialSource {
	Planet@ pl;
	double weight = 0;
};

final class AsteroidData {
	Asteroid@ asteroid;
	array<ExportData@>@ resources;

	void save(Planets& planets, SaveFile& file) {
		file << asteroid;

		uint cnt = 0;
		if(resources !is null)
			cnt = resources.length;

		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			planets.resources.saveExport(file, resources[i]);
	}

	void load(Planets& planets, SaveFile& file) {
		file >> asteroid;

		uint cnt = 0;
		file >> cnt;
		if(cnt != 0)
			@resources = array<ExportData@>();
		for(uint i = 0; i < cnt; ++i) {
			auto@ res = planets.resources.loadExport(file);
			if(res !is null)
				resources.insertLast(res);
		}
	}

	bool tick(AI& ai, Planets& planets) {
		if(asteroid is null || !asteroid.valid || asteroid.owner !is ai.empire) {
			planets.resources.killImportsTo(asteroid);
			planets.resources.killResourcesFrom(asteroid);
			return false;
		}
		if(resources is null) {
			@resources = planets.resources.availableResource(asteroid);
		}
		else {
			if(asteroid.nativeResourceCount != resources.length || (resources.length != 0 && asteroid.primaryResourceId != resources[0].resourceId))
				planets.updateResourceList(asteroid, resources);
		}
		return true;
	}
};

class Planets : AIComponent {
	Resources@ resources;
	Budget@ budget;
	Systems@ systems;

	PlanetSurface surface;

	array<AsteroidData@> ownedAsteroids;
	array<PlanetAI@> planets;
	array<PlanetAI@> bumped;
	uint planetIdx = 0;

	array<BuildingRequest@> building;
	int nextBuildingRequestId = 0;

	void create() {
		@resources = cast<Resources>(ai.resources);
		@budget = cast<Budget>(ai.budget);
		@systems = cast<Systems>(ai.systems);
	}

	void save(SaveFile& file) {
		file << nextBuildingRequestId;

		uint cnt = planets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ plAI = planets[i];
			saveAI(file, plAI);
			plAI.save(this, file);
		}

		cnt = building.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveBuildingRequest(file, building[i]);
			building[i].save(this, file);
		}

		cnt = ownedAsteroids.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			ownedAsteroids[i].save(this, file);
	}

	void load(SaveFile& file) {
		file >> nextBuildingRequestId;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ plAI = loadAI(file);
			if(plAI !is null)
				plAI.load(this, file);
			else
				PlanetAI().load(this, file);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ req = loadBuildingRequest(file);
			if(req !is null) {
				req.load(this, file);
				building.insertLast(req);
			}
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			AsteroidData data;
			data.load(this, file);
			if(data.asteroid !is null)
				ownedAsteroids.insertLast(data);
		}
	}

	PlanetAI@ loadAI(SaveFile& file) {
		Planet@ obj;
		file >> obj;

		if(obj is null)
			return null;

		PlanetAI@ plAI = getAI(obj);
		if(plAI is null) {
			@plAI = PlanetAI();
			@plAI.obj = obj;
			plAI.prevTick = gameTime;
			planets.insertLast(plAI);
		}
		return plAI;
	}

	void saveAI(SaveFile& file, PlanetAI@ ai) {
		Planet@ pl;
		if(ai !is null)
			@pl = ai.obj;
		file << pl;
	}

	array<BuildingRequest@> loadIds;
	BuildingRequest@ loadBuildingRequest(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = loadIds.length; i < cnt; ++i) {
			if(loadIds[i].id == id)
				return loadIds[i];
		}
		BuildingRequest data;
		data.id = id;
		loadIds.insertLast(data);
		return data;
	}
	BuildingRequest@ loadBuildingRequest(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadBuildingRequest(id);
	}
	void saveBuildingRequest(SaveFile& file, BuildingRequest@ data) {
		int id = -1;
		if(data !is null)
			id = data.id;
		file << id;
	}
	void postLoad(AI& ai) {
		loadIds.length = 0;
	}

	void start() {
		checkForPlanets();
	}

	void checkForPlanets() {
		auto@ data = ai.empire.getPlanets();
		Object@ obj;
		while(receive(data, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(pl !is null)
				register(cast<Planet>(obj));
		}
	}

	uint roidIdx = 0;
	void tick(double time) {
		double curTime = gameTime;

		if(planets.length != 0) {
			planetIdx = (planetIdx+1) % planets.length;

			auto@ plAI = planets[planetIdx];
			plAI.tick(ai, this, curTime - plAI.prevTick);
			plAI.prevTick = curTime;
		}

		for(int i = bumped.length-1; i >= 0; --i) {
			auto@ plAI = bumped[i];
			double tickTime = curTime - plAI.prevTick;
			if(tickTime != 0) {
				plAI.tick(ai, this, tickTime);
				plAI.prevTick = curTime;
			}
		}
		bumped.length = 0;

		if(ownedAsteroids.length != 0) {
			roidIdx = (roidIdx+1) % ownedAsteroids.length;
			if(!ownedAsteroids[roidIdx].tick(ai, this))
				ownedAsteroids.removeAt(roidIdx);
		}

		//Construct any buildings we are waiting on
		for(uint i = 0, cnt = building.length; i < cnt; ++i) {
			if(!building[i].tick(ai, this, time)) {
				building.removeAt(i);
				--i; --cnt;
				break;
			}
		}
	}

	uint prevCount = 0;
	double checkTimer = 0;
	uint sysIdx = 0, ownedIdx = 0;
	void focusTick(double time) override {
		//Check for any newly obtained planets
		uint curCount = ai.empire.planetCount;
		checkTimer += time;
		if(curCount != prevCount || checkTimer > 60.0) {
			checkForPlanets();
			prevCount = curCount;
			checkTimer = 0;
		}

		//Find any asteroids we've gained
		if(systems.all.length != 0) {
			sysIdx = (sysIdx+1) % systems.all.length;
			auto@ sys = systems.all[sysIdx];
			for(uint i = 0, cnt = sys.asteroids.length; i < cnt; ++i)
				register(sys.asteroids[i]);
		}
		if(systems.owned.length != 0) {
			ownedIdx = (ownedIdx+1) % systems.owned.length;
			auto@ sys = systems.owned[ownedIdx];
			for(uint i = 0, cnt = sys.asteroids.length; i < cnt; ++i)
				register(sys.asteroids[i]);
		}
	}

	void bump(Planet@ pl) {
		if(pl !is null)
			bump(getAI(pl));
	}

	void bump(PlanetAI@ plAI) {
		if(plAI !is null)
			bumped.insertLast(plAI);
	}

	PlanetAI@ getAI(Planet& obj) {
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			if(planets[i].obj is obj)
				return planets[i];
		}
		return null;
	}

	PlanetAI@ register(Planet& obj) {
		PlanetAI@ plAI = getAI(obj);
		if(plAI is null) {
			@plAI = PlanetAI();
			@plAI.obj = obj;
			plAI.prevTick = gameTime;
			planets.insertLast(plAI);
			plAI.init(ai, this);
		}
		return plAI;
	}

	AsteroidData@ register(Asteroid@ obj) {
		if(obj is null || !obj.valid || obj.owner !is ai.empire)
			return null;
		for(uint i = 0, cnt = ownedAsteroids.length; i < cnt; ++i) {
			if(ownedAsteroids[i].asteroid is obj)
				return ownedAsteroids[i];
		}

		AsteroidData data;
		@data.asteroid = obj;
		ownedAsteroids.insertLast(data);

		if(log)
			ai.print("Detected asteroid: "+obj.name, obj.region);

		return data;
	}

	void remove(PlanetAI@ plAI) {
		resources.killImportsTo(plAI.obj);
		resources.killResourcesFrom(plAI.obj);
		plAI.remove(ai, this);
		planets.remove(plAI);
		bumped.remove(plAI);
	}

	void requestLevel(PlanetAI@ plAI, int toLevel, ImportData@ before = null) {
		if(plAI is null)
			return;
		plAI.targetLevel = toLevel;
		if(before !is null) {
			for(int lv = max(plAI.requestedLevel, 1); lv <= toLevel; ++lv)
				resources.organizeImports(plAI.obj, lv, before);
			plAI.requestedLevel = toLevel;
		}
		else {
			bump(plAI);
		}
	}

	BuildingRequest@ requestBuilding(PlanetAI@ plAI, const BuildingType@ type, double priority = 1.0, double expire = INFINITY, bool scatter = true, uint moneyType = BT_Development) {
		if(plAI is null)
			return null;

		if(log)
			ai.print("Requested building of type "+type.name, plAI.obj);

		BuildingRequest req(budget, type, priority, moneyType);
		req.scatter = scatter;
		req.id = nextBuildingRequestId++;
		req.expires = gameTime + expire;
		@req.plAI = plAI;

		building.insertLast(req);
		return req;
	}

	bool isBuilding(Planet@ planet, const BuildingType@ type) {
		for(uint i = 0, cnt = building.length; i < cnt; ++i) {
			if(building[i].type is type && building[i].plAI.obj is planet)
				return true;
		}
		return false;
	}

	void getColonizeSources(array<PotentialSource@>& sources) {
		sources.length = 0;
		for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
			auto@ plAI = planets[i];
			if(!plAI.obj.valid)
				continue;

			double w = plAI.colonizeWeight;
			if(w == 0)
				continue;
			if(plAI.obj.owner !is ai.empire)
				continue;

			PotentialSource src;
			@src.pl = planets[i].obj;
			src.weight = w;
			sources.insertLast(src);
		}
	}

	array<ExportData@> newResources;
	array<ExportData@> removedResources;
	array<Resource> checkResources;
	void updateResourceList(Object@ obj, array<ExportData@>& resList) {
		newResources.length = 0;
		removedResources = resList;

		checkResources.syncFrom(obj.getNativeResources());

		uint nativeCnt = checkResources.length;
		for(uint i = 0; i < nativeCnt; ++i) {
			int id = checkResources[i].id;

			bool found = false;
			for(uint n = 0, ncnt = removedResources.length; n < ncnt; ++n) {
				if(removedResources[n].resourceId == id) {
					removedResources.removeAt(n);
					found = true;
					break;
				}
			}

			if(!found) {
				auto@ type = checkResources[i].type;
				auto@ res = resources.availableResource(obj, type, id);

				if(i == 0)
					resList.insertAt(0, res);
				else
					resList.insertLast(res);
				newResources.insertLast(res);
			}
			else if(i == 0 && resList.length > 1 && resList[0].resourceId != id) {
				for(uint n = 0, ncnt = resList.length; n < ncnt; ++n) {
					if(resList[n].resourceId == id) {
						auto@ res = resList[n];
						resList.removeAt(n);
						resList.insertAt(0, res);
						break;
					}
				}
			}
		}

		//Get rid of resources we no longer have
		for(uint i = 0, cnt = removedResources.length; i < cnt; ++i) {
			resources.removeResource(removedResources[i]);
			resList.remove(removedResources[i]);
		}

		//Tell the resources component to try to immediately use the new resources
		for(uint i = 0, cnt = newResources.length; i < cnt; ++i)
			resources.checkReplaceCurrent(newResources[i]);
	}
};

AIComponent@ createPlanets() {
	return Planets();
}
