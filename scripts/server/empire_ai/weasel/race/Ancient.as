import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Colonization;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Development;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Orbitals;

from orbitals import getOrbitalModule, OrbitalModule;
from buildings import getBuildingType, BuildingType;
from resources import ResourceType, getResource, getResourceID;
from statuses import getStatusID;
from biomes import getBiomeID;

enum PlanetClass {
	PC_Empty,
	PC_Core,
	PC_Mine,
	PC_Transmute,
}

class TrackReplicator {
	Object@ obj;
	Planet@ target;
	bool arrived = false;
	MoveOrder@ move;
	BuildingRequest@ build;
	uint intention = PC_Empty;

	bool get_busy() {
		if(target is null)
			return false;
		if(!arrived || move !is null || build !is null)
			return true;
		return false;
	}

	void save(Ancient& ancient, SaveFile& file) {
		file << obj;
		file << target;
		file << arrived;
		ancient.movement.saveMoveOrder(file, move);
		ancient.planets.saveBuildingRequest(file, build);
		file << intention;
	}

	void load(Ancient& ancient, SaveFile& file) {
		file >> obj;
		file >> target;
		file >> arrived;
		@move = ancient.movement.loadMoveOrder(file);
		@build = ancient.planets.loadBuildingRequest(file);
		file >> intention;
	}
};

class Ancient : Race, RaceResources, RaceColonization {
	Colonization@ colonization;
	Construction@ construction;
	Resources@ resources;
	Planets@ planets;
	Development@ development;
	Movement@ movement;
	Orbitals@ orbitals;

	array<TrackReplicator@> replicators;

	const OrbitalModule@ replicatorMod;

	const BuildingType@ core;
	const BuildingType@ miner;
	const BuildingType@ transmuter;

	const BuildingType@ foundry;

	const BuildingType@ depot;
	const BuildingType@ refinery;
	const BuildingType@ reinforcer;
	const BuildingType@ developer;
	const BuildingType@ compressor;

	int claimStatus = -1;
	int replicatorStatus = -1;

	int mountainsBiome = -1;

	int oreResource = -1;
	int baseMatResource = -1;

	bool foundFirstT2 = false;

	void create() {
		@colonization = cast<Colonization>(ai.colonization);
		colonization.performColonization = false;

		@resources = cast<Resources>(ai.resources);
		@construction = cast<Construction>(ai.construction);
		@movement = cast<Movement>(ai.movement);
		@planets = cast<Planets>(ai.planets);
		@orbitals = cast<Orbitals>(ai.orbitals);
		@planets = cast<Planets>(ai.planets);

		@development = cast<Development>(ai.development);
		development.managePlanetPressure = false;
		development.buildBuildings = false;
		development.colonizeResources = false;

		@replicatorMod = getOrbitalModule("AncientReplicator");

		@transmuter = getBuildingType("AncientTransmuter");
		@miner = getBuildingType("AncientMiner");
		@core = getBuildingType("AncientCore");

		@foundry = getBuildingType("AncientFoundry");

		@depot = getBuildingType("AncientDepot");
		@refinery = getBuildingType("AncientRefinery");
		@reinforcer = getBuildingType("AncientReinforcer");
		@developer = getBuildingType("AncientDeveloper");
		@compressor = getBuildingType("Compressor");

		claimStatus = getStatusID("AncientClaim");
		replicatorStatus = getStatusID("AncientReplicator");

		mountainsBiome = getBiomeID("Mountains");

		oreResource = getResourceID("OreRate");
		baseMatResource = getResourceID("BaseMaterial");

		@ai.defs.Factory = null;
		@ai.defs.LaborStorage = null;
	}

	void save(SaveFile& file) override {
		file << foundFirstT2;
		uint cnt = replicators.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			replicators[i].save(this, file);
	}

	void load(SaveFile& file) override {
		file >> foundFirstT2;
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			TrackReplicator t;
			t.load(this, file);
			if(t.obj !is null)
				replicators.insertLast(t);
		}
	}

	void levelRequirements(Object& obj, int targetLevel, array<ResourceSpec@>& specs) {
		//YOLO
		specs.length = 0;
	}

	bool orderColonization(ColonizeData& data, Planet@ sourcePlanet) {
		return true;
	}

	double getGenericUsefulness(const ResourceType@ type) {
		return 1.0;
	}

	bool hasReplicator(Planet& pl) {
		for(uint i = 0, cnt = replicators.length; i < cnt; ++i) {
			if(replicators[i].target is pl)
				return true;
		}
		return false;
	}

	bool isTracking(Object& obj) {
		for(uint i = 0, cnt = replicators.length; i < cnt; ++i) {
			if(replicators[i].obj is obj)
				return true;
		}
		return false;
	}

	void trackReplicator(Object& obj) {
		TrackReplicator t;
		@t.obj = obj;

		replicators.insertLast(t);
	}

	void updateRequests(Planet& pl) {
		//Handle requests for base materials
		uint baseMatReqs = 0;
		baseMatReqs += pl.getBuildingCount(depot.id);
		baseMatReqs += pl.getBuildingCount(refinery.id);
		baseMatReqs += pl.getBuildingCount(reinforcer.id);
		baseMatReqs += pl.getBuildingCount(developer.id);
		baseMatReqs += pl.getBuildingCount(compressor.id);

		array<ImportData@> curBaseMat;
		resources.getImportsOf(curBaseMat, baseMatResource, pl);

		if(curBaseMat.length < baseMatReqs) {
			for(uint i = curBaseMat.length, cnt = baseMatReqs; i < cnt; ++i) {
				ResourceSpec spec;
				spec.type = RST_Specific;
				@spec.resource = getResource(baseMatResource);

				resources.requestResource(pl, spec);
			}
		}
		else if(curBaseMat.length > baseMatReqs) {
			for(uint i = baseMatReqs, cnt = curBaseMat.length; i < cnt; ++i)
				resources.cancelRequest(curBaseMat[i]);
		}

		//Handle requests for ore
		uint oreReqs = 0;
		oreReqs += pl.getBuildingCount(foundry.id);

		array<ImportData@> curOre;
		resources.getImportsOf(curOre, oreResource, pl);

		if(curOre.length < oreReqs) {
			for(uint i = curOre.length, cnt = oreReqs; i < cnt; ++i) {
				ResourceSpec spec;
				spec.type = RST_Specific;
				@spec.resource = getResource(oreResource);

				resources.requestResource(pl, spec);
			}
		}
		else if(curOre.length > oreReqs) {
			for(uint i = oreReqs, cnt = curOre.length; i < cnt; ++i)
				resources.cancelRequest(curOre[i]);
		}
	}

	uint plInd = 0;
	void focusTick(double time) {
		//Find new replicators
		for(uint i = 0, cnt = orbitals.orbitals.length; i < cnt; ++i) {
			auto@ orb = cast<Orbital>(orbitals.orbitals[i].obj);
			if(orb.coreModule == replicatorMod.id) {
				if(!isTracking(orb))
					trackReplicator(orb);
			}
		}

		//Update requests for planets
		if(planets.planets.length != 0) {
			for(uint n = 0, ncnt = min(planets.planets.length, 10); n < ncnt; ++n) {
				plInd = (plInd+1) % planets.planets.length;
				Planet@ pl = planets.planets[plInd].obj;

				if(classify(pl) == PC_Core)
					updateRequests(pl);
			}
		}

		//Manage existing replicators
		for(uint i = 0, cnt = replicators.length; i < cnt; ++i) {
			auto@ t = replicators[i];
			if(t.obj is null || !t.obj.valid || t.obj.owner !is ai.empire) {
				replicators.removeAt(i);
				--i; --cnt;
				continue;
			}

			if(t.target !is null) {
				if(!t.target.valid) {
					@t.target = null;
					if(!t.arrived)
						t.obj.stopMoving();
					t.arrived = false;
				}
				else if(t.target.owner !is ai.empire && t.target.owner.valid) {
					@t.target = null;
					if(!t.arrived)
						t.obj.stopMoving();
					t.arrived = false;
				}
			}

			if(t.move !is null) {
				if(t.move.failed) {
					@t.move = null;
					t.arrived = false;
				}
				else if(t.move.completed) {
					if(t.obj.isOrbitingAround(t.target)) {
						@t.move = null;
						t.arrived = true;
					}
					else if(t.obj.inOrbit) {
						@t.move = null;
						t.arrived = false;
						@t.target = null;
					}
				}
			}
			else if(t.target !is null && !t.arrived) {
				@t.move = movement.move(t.obj, t.target);
			}

			if(t.build !is null) {
				if(t.build.canceled) {
					//A build failed, give up on this planet
					if(log)
						ai.print("Failed building build", t.target);
					@t.target = null;
					@t.build = null;
					t.arrived = false;
				}
				else if(t.build.built) {
					float progress = t.build.getProgress();
					if(progress >= 1.f) {
						if(log)
							ai.print("Completed building build", t.target);
						@t.build = null;
					}
					else if(progress < -0.5f) {
						if(log)
							ai.print("Failed building build location "+t.build.builtAt, t.target);
						@t.build = null;
						@t.target = null;
						t.arrived = false;
					}
				}
			}

			if(t.arrived || t.target is null) {
				if(!t.busy)
					useReplicator(t);
			}
		}
	}
	
	uint classify(Planet& pl) {
		int resType = pl.primaryResourceType;
		if(resType == oreResource)
			return PC_Mine;
		if(resType == baseMatResource)
			return PC_Transmute;
		uint claims = pl.getStatusStackCountAny(claimStatus);
		if(claims <= 1)
			return PC_Empty;
		if(pl.getBuildingCount(core.id) >= 1)
			return PC_Core;
		if(pl.getBuildingCount(transmuter.id) >= 1)
			return PC_Transmute;
		if(pl.getBuildingCount(miner.id) >= 1)
			return PC_Mine;
		return PC_Empty;
	}

	bool shouldBeCore(const ResourceType@ type) {
		if(type.level >= 1)
			return true;
		if(type.totalPressure >= 8)
			return true;
		return false;
	}

	int openOreRequests(TrackReplicator@ discount = null) {
		int reqs = 0;
		for(uint i = 0, cnt = resources.requested.length; i < cnt; ++i) {
			auto@ req = resources.requested[i];
			if(req.beingMet)
				continue;
			if(req.spec.type != RST_Specific)
				continue;
			if(req.spec.resource.id != uint(oreResource))
				continue;
			reqs += 1;
		}
		for(uint i = 0, cnt = replicators.length; i < cnt; ++i) {
			auto@ t = replicators[i];
			if(t is discount)
				continue;
			if(t.target is null)
				continue;
			if(t.intention == PC_Mine && (t.build is null || t.build.type is miner))
				reqs -= 1;
		}
		return reqs;
	}

	int openBaseMatRequests(TrackReplicator@ discount = null) {
		int reqs = 0;
		for(uint i = 0, cnt = resources.requested.length; i < cnt; ++i) {
			auto@ req = resources.requested[i];
			if(req.beingMet)
				continue;
			if(req.spec.type != RST_Specific)
				continue;
			if(req.spec.resource.id != uint(baseMatResource))
				continue;
			reqs += 1;
		}
		for(uint i = 0, cnt = replicators.length; i < cnt; ++i) {
			auto@ t = replicators[i];
			if(t is discount)
				continue;
			if(t.target is null)
				continue;
			if(t.intention == PC_Transmute && (t.build is null || t.build.type is transmuter))
				reqs -= 1;
		}
		return reqs;
	}

	void build(TrackReplicator& t, const BuildingType@ building) {
		auto@ plAI = planets.getAI(t.target);
		if(plAI is null)
			return;
		if(!t.target.hasStatusEffect(replicatorStatus))
			return;

		//bool scatter = building is miner || building is transmuter;
		bool scatter = false;
		@t.build = planets.requestBuilding(plAI, building, scatter=scatter, moneyType=BT_Colonization);

		if(log)
			ai.print("Build "+building.name, t.target);
	}

	void useReplicator(TrackReplicator& t) {
		if(t.target !is null) {
			uint type = classify(t.target);
			switch(type) {
				case PC_Empty: {
					const ResourceType@ res = getResource(t.target.primaryResourceType);
					if(res is null) {
						@t.target = null;
						t.arrived = false;
						return;
					}

					if(shouldBeCore(res)) {
						build(t, core);
					}
					else if(openBaseMatRequests(t) >= openOreRequests(t) || gameTime < 6.0 * 60.0 || !t.target.hasBiome(mountainsBiome)) {
						build(t, transmuter);
					}
					else {
						build(t, miner);
					}
					return;
				}
				case PC_Transmute:
					@t.target = null;
					t.arrived = false;
				break;
				case PC_Mine:
					@t.target = null;
					t.arrived = false;
				break;
				case PC_Core:
					build(t, refinery);
					return;
			}
		}

		//Find a new planet to colonize
		PotentialColonize@ best;
		double bestWeight = 0.0;

		uint getType = PC_Core;
		if(openBaseMatRequests() >= 1)
			getType = PC_Transmute;
		else if(openOreRequests() >= 1 && gameTime > 6.0 * 60.0)
			getType = PC_Mine;

		auto@ potentials = colonization.getPotentialColonize();
		for(uint i = 0, cnt = potentials.length; i < cnt; ++i) {
			PotentialColonize@ p = potentials[i];
			if(hasReplicator(p.pl))
				continue;

			double w = p.weight;
			if(!foundFirstT2 && p.resource.level >= 2)
				w *= 100.0;
			else if((getType == PC_Core) != shouldBeCore(p.resource))
				w *= 0.6;
			if(getType == PC_Core && p.resource.level >= 2)
				w *= 4.0;
			if(getType == PC_Core && p.resource.level >= 3)
				w *= 6.0;
			if(getType == PC_Mine && !p.pl.hasBiome(mountainsBiome))
				w *= 0.1;
			if(getType == PC_Core)
				w *= double(p.pl.totalSurfaceTiles) / 100.0;
			w /= p.pl.position.distanceTo(t.obj.position)/1000.0;

			if(w > bestWeight) {
				bestWeight = w;
				@best = p;
			}
		}

		if(best !is null) {
			@t.target = best.pl;
			t.intention = shouldBeCore(best.resource) ? uint(PC_Core) : getType;
			t.arrived = false;
			if(!foundFirstT2) {
				if(best.resource.level == 2)
					foundFirstT2 = true; 
			}
		}
	}
};

AIComponent@ createAncient() {
	return Ancient();
}
