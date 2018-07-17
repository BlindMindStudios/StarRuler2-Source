import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Military;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Fleets;

import ftl;
from orbitals import getOrbitalModuleID;

const double FLING_MIN_DISTANCE_STAGE = 10000;
const double FLING_MIN_DISTANCE_DEVELOP = 20000;
const double FLING_MIN_TIMER = 3.0 * 60.0;

int flingModule = -1;

void init() {
	flingModule = getOrbitalModuleID("FlingCore");
}

class FlingRegion : Savable {
	Region@ region;
	Object@ obj;
	bool installed = false;
	vec3d destination;

	void save(SaveFile& file) {
		file << region;
		file << obj;
		file << installed;
		file << destination;
	}

	void load(SaveFile& file) {
		file >> region;
		file >> obj;
		file >> installed;
		file >> destination;
	}
};

class Fling : FTL {
	Military@ military;
	Designs@ designs;
	Construction@ construction;
	Development@ development;
	Systems@ systems;
	Budget@ budget;
	Fleets@ fleets;

	array<FlingRegion@> tracked;
	array<Object@> unused;

	BuildOrbital@ buildFling;
	double nextBuildTry = 15.0 * 60.0;
	bool wantToBuild = false;

	void create() override {
		@military = cast<Military>(ai.military);
		@designs = cast<Designs>(ai.designs);
		@construction = cast<Construction>(ai.construction);
		@development = cast<Development>(ai.development);
		@systems = cast<Systems>(ai.systems);
		@budget = cast<Budget>(ai.budget);
		@fleets = cast<Fleets>(ai.fleets);
	}

	void save(SaveFile& file) override {
		construction.saveConstruction(file, buildFling);
		file << nextBuildTry;
		file << wantToBuild;

		uint cnt = tracked.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << tracked[i];

		cnt = unused.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << unused[i];
	}

	void load(SaveFile& file) override {
		@buildFling = cast<BuildOrbital>(construction.loadConstruction(file));
		file >> nextBuildTry;
		file >> wantToBuild;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			FlingRegion fr;
			file >> fr;
			tracked.insertLast(fr);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Object@ obj;
			file >> obj;
			if(obj !is null)
				unused.insertLast(obj);
		}
	}

	uint order(MoveOrder& ord) override {
		if(!canFling(ord.obj))
			return F_Pass;

		//Find the position to fling to
		vec3d toPosition;
		if(!targetPosition(ord, toPosition))
			return F_Pass;

		//Don't fling if we're saving our FTL for a new beacon
		double avail = usableFTL(ai, ord);
		if((buildFling !is null && !buildFling.started) || wantToBuild)
			avail = min(avail, ai.empire.FTLStored - 250.0);

		//Make sure we have the ftl to fling
		if(flingCost(ord.obj, toPosition) > avail)
			return F_Pass;

		//Make sure we're in range of a beacon
		Object@ beacon = getClosest(ord.obj.position);
		if(beacon is null || beacon.position.distanceTo(ord.obj.position) > FLING_BEACON_RANGE)
			return F_Pass;

		ord.obj.addFlingOrder(beacon, toPosition);
		return F_Continue;
	}

	FlingRegion@ get(Region@ reg) {
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].region is reg)
				return tracked[i];
		}
		return null;
	}

	void remove(FlingRegion@ gt) {
		if(gt.obj !is null && gt.obj.valid && gt.obj.owner is ai.empire)
			unused.insertLast(gt.obj);
		tracked.remove(gt);
	}

	Object@ getClosest(const vec3d& position) {
		Object@ closest;
		double minDist = INFINITY;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			Object@ obj = tracked[i].obj;
			if(obj is null)
				continue;
			double d = obj.position.distanceTo(position);
			if(d < minDist) {
				minDist = d;
				@closest = obj;
			}
		}
		for(uint i = 0, cnt = unused.length; i < cnt; ++i) {
			Object@ obj = unused[i];
			if(obj is null)
				continue;
			double d = obj.position.distanceTo(position);
			if(d < minDist) {
				minDist = d;
				@closest = obj;
			}
		}
		return closest;
	}

	FlingRegion@ getClosestRegion(const vec3d& position) {
		FlingRegion@ closest;
		double minDist = INFINITY;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			double d = tracked[i].region.position.distanceTo(position);
			if(d < minDist) {
				minDist = d;
				@closest = tracked[i];
			}
		}
		return closest;
	}

	void assignTo(FlingRegion@ track, Object@ closest) {
		unused.remove(closest);
		@track.obj = closest;
	}

	bool trackingBeacon(Object@ obj) {
		for(uint i = 0, cnt = unused.length; i < cnt; ++i) {
			if(unused[i] is obj)
				return true;
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].obj is obj)
				return true;
		}
		return false;
	}

	bool shouldHaveBeacon(Region@ reg, bool always = false) {
		if(military.getBase(reg) !is null)
			return true;
		if(development.isDevelopingIn(reg))
			return true;
		return false;
	}

	void focusTick(double time) override {
		//Manage unused beacons list
		for(uint i = 0, cnt = unused.length; i < cnt; ++i) {
			Object@ obj = unused[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				unused.removeAt(i);
				--i; --cnt;
			}
		}

		//Detect new beacons
		auto@ data = ai.empire.getFlingBeacons();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj is null)
				continue;
			if(!trackingBeacon(obj))
				unused.insertLast(obj);
		}

		//Update existing beacons for staging bases
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ reg = tracked[i];
			bool checkAlways = false;
			if(reg.obj !is null) {
				if(!reg.obj.valid || reg.obj.owner !is ai.empire || reg.obj.region !is reg.region) {
					@reg.obj = null;
					checkAlways = true;
				}
			}
			if(!shouldHaveBeacon(reg.region, checkAlways)) {
				remove(tracked[i]);
				--i; --cnt;
			}
		}

		//Detect new staging bases to build beacons at
		for(uint i = 0, cnt = military.stagingBases.length; i < cnt; ++i) {
			auto@ base = military.stagingBases[i];
			if(base.occupiedTime < FLING_MIN_TIMER)
				continue;

			if(get(base.region) is null) {
				FlingRegion@ closest = getClosestRegion(base.region.position);
				if(closest !is null && closest.region.position.distanceTo(base.region.position) < FLING_MIN_DISTANCE_STAGE)
					continue;

				FlingRegion gt;
				@gt.region = base.region;
				tracked.insertLast(gt);
				break;
			}
		}

		//Detect new important planets to build beacons at
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			auto@ focus = development.focuses[i];
			Region@ reg = focus.obj.region;
			if(reg is null)
				continue;

			if(get(reg) is null) {
				FlingRegion@ closest = getClosestRegion(reg.position);
				if(closest !is null && closest.region.position.distanceTo(reg.position) < FLING_MIN_DISTANCE_DEVELOP)
					continue;

				FlingRegion gt;
				@gt.region = reg;
				tracked.insertLast(gt);
				break;
			}
		}

		//Destroy beacons if we're having ftl trouble
		if(ai.empire.FTLShortage) {
			Orbital@ leastImportant;
			double leastWeight = INFINITY;

			for(uint i = 0, cnt = unused.length; i < cnt; ++i) {
				Orbital@ obj = cast<Orbital>(unused[i]);
				if(obj is null || !obj.valid)
					continue;

				@leastImportant = obj;
				leastWeight = 0.0;
				break;
			}

			if(leastImportant !is null) {
				if(log)
					ai.print("Scuttle unused beacon for ftl", leastImportant.region);
				leastImportant.scuttle();
			}
			else {
				for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
					Orbital@ obj = cast<Orbital>(tracked[i].obj);
					if(obj is null || !obj.valid)
						continue;

					double weight = 1.0;
					auto@ base = military.getBase(tracked[i].region);
					if(base is null) {
						weight *= 5.0;
					}
					else if(base.idleTime >= 1) {
						weight *= 1.0 + (base.idleTime / 60.0);
					}
					else {
						weight /= 2.0;
					}

					if(weight < leastWeight) {
						@leastImportant = obj;
						leastWeight = weight;
					}
				}

				if(leastImportant !is null) {
					if(log)
						ai.print("Scuttle unimportant beacon for ftl", leastImportant.region);
					leastImportant.scuttle();
				}
			}
		}

		//See if we should build a new gate
		if(buildFling !is null) {
			if(buildFling.completed) {
				@buildFling = null;
				nextBuildTry = gameTime + 60.0;
			}
		}
		wantToBuild = false;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			if(gt.obj is null && gt.region.ContestedMask & ai.mask == 0 && gt.region.BlockFTLMask & ai.mask == 0) {
				Object@ found;
				for(uint n = 0, ncnt = unused.length; n < ncnt; ++n) {
					Object@ obj = unused[n];
					if(obj.region is gt.region) {
						@found = obj;
						break;
					}
				}

				if(found !is null) {
					if(log)
						ai.print("Assign beacon to => "+gt.region.name, found.region);
					assignTo(gt, found);
				} else if(buildFling is null && gameTime > nextBuildTry && !ai.empire.isFTLShortage(0.15)) {
					if(ai.empire.FTLStored >= 250) {
						if(log)
							ai.print("Build beacon for this system", gt.region);

						@buildFling = construction.buildOrbital(getOrbitalModule(flingModule), military.getStationPosition(gt.region));
					}
					else {
						wantToBuild = true;
					}
				}
			}
		}

		//Scuttle anything unused if we don't need beacons in those regions
		for(uint i = 0, cnt = unused.length; i < cnt; ++i) {
			if(get(unused[i].region) is null && unused[i].isOrbital) {
				cast<Orbital>(unused[i]).scuttle();
				unused.removeAt(i);
				--i; --cnt;
			}
		}

		//Try to get enough ftl storage that we can fling our largest fleet and have some remaining
		double highestCost = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			highestCost = max(highestCost, double(flingCost(flAI.obj, vec3d())));
		}
		development.aimFTLStorage = highestCost / (1.0 - ai.behavior.ftlReservePctCritical - ai.behavior.ftlReservePctNormal);
	}
};

AIComponent@ createFling() {
	return Fling();
}
