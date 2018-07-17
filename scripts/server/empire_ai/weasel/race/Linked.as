import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Movement;
import empire_ai.weasel.Military;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Budget;

from orbitals import getOrbitalModuleID;

const double MAINFRAME_MIN_DISTANCE_STAGE = 15000;
const double MAINFRAME_MIN_DISTANCE_DEVELOP = 20000;
const double MAINFRAME_MIN_TIMER = 3.0 * 60.0;
const int MAINFRAME_BUILD_MOVE_HOPS = 5;

class LinkRegion : Savable {
	Region@ region;
	Object@ obj;
	bool arrived = false;
	vec3d destination;

	void save(SaveFile& file) {
		file << region;
		file << obj;
		file << arrived;
		file << destination;
	}

	void load(SaveFile& file) {
		file >> region;
		file >> obj;
		file >> arrived;
		file >> destination;
	}
};

class Linked : Race {
	Military@ military;
	Designs@ designs;
	Construction@ construction;
	Development@ development;
	Systems@ systems;
	Budget@ budget;

	array<LinkRegion@> tracked;
	array<Object@> unassigned;

	BuildOrbital@ buildMainframe;
	int mainframeId = -1;

	double nextBuildTry = 15.0 * 60.0;

	void create() override {
		@military = cast<Military>(ai.military);
		@designs = cast<Designs>(ai.designs);
		@construction = cast<Construction>(ai.construction);
		@development = cast<Development>(ai.development);
		@systems = cast<Systems>(ai.systems);
		@budget = cast<Budget>(ai.budget);

		mainframeId = getOrbitalModuleID("Mainframe");
	}

	void save(SaveFile& file) override {
		construction.saveConstruction(file, buildMainframe);
		file << nextBuildTry;

		uint cnt = tracked.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << tracked[i];

		cnt = unassigned.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << unassigned[i];
	}

	void load(SaveFile& file) override {
		@buildMainframe = cast<BuildOrbital>(construction.loadConstruction(file));
		file >> nextBuildTry;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			LinkRegion gt;
			file >> gt;
			tracked.insertLast(gt);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Object@ obj;
			file >> obj;
			if(obj !is null)
				unassigned.insertLast(obj);
		}
	}

	LinkRegion@ get(Region@ reg) {
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].region is reg)
				return tracked[i];
		}
		return null;
	}

	void remove(LinkRegion@ gt) {
		if(gt.obj !is null && gt.obj.valid && gt.obj.owner is ai.empire)
			unassigned.insertLast(gt.obj);
		tracked.remove(gt);
	}

	Object@ getClosestMainframe(const vec3d& position) {
		Object@ closest;
		double minDist = INFINITY;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			Object@ obj = tracked[i].obj;
			if(obj is null)
				continue;
			if(!tracked[i].arrived)
				continue;
			double d = obj.position.distanceTo(position);
			if(d < minDist) {
				minDist = d;
				@closest = obj;
			}
		}
		return closest;
	}

	LinkRegion@ getClosestLinkRegion(const vec3d& position) {
		LinkRegion@ closest;
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

	void assignTo(LinkRegion@ gt, Object@ closest) {
		unassigned.remove(closest);
		@gt.obj = closest;
		gt.arrived = false;

		if(closest.region is gt.region)
			gt.arrived = true;
		if(!gt.arrived) {
			gt.destination = military.getStationPosition(gt.region);
			closest.addMoveOrder(gt.destination);
		}
	}

	bool trackingMainframe(Object@ obj) {
		for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
			if(unassigned[i] is obj)
				return true;
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].obj is obj)
				return true;
		}
		return false;
	}

	bool shouldHaveMainframe(Region@ reg, bool always = false) {
		if(military.getBase(reg) !is null)
			return true;
		if(development.isDevelopingIn(reg))
			return true;
		return false;
	}

	void focusTick(double time) override {
		//Manage unassigned mainframes list
		for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
			Object@ obj = unassigned[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				unassigned.removeAt(i);
				--i; --cnt;
			}
		}

		//Detect new gates
		auto@ data = ai.empire.getOrbitals();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj is null)
				continue;
			Orbital@ orb = cast<Orbital>(obj);
			if(orb is null || orb.coreModule != uint(mainframeId))
				continue;
			if(!trackingMainframe(obj))
				unassigned.insertLast(obj);
		}

		//Update existing gates for staging bases
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			bool checkAlways = false;
			if(gt.obj !is null) {
				if(!gt.obj.valid || gt.obj.owner !is ai.empire || (gt.arrived && gt.obj.region !is gt.region)) {
					@gt.obj = null;
					gt.arrived = false;
					checkAlways = true;
				}
				else if(!gt.arrived && !gt.obj.hasOrders) {
					if(gt.destination.distanceTo(gt.obj.position) < 10.0)
						gt.arrived = true;
					else
						gt.obj.addMoveOrder(gt.destination);
				}
			}
			if(!shouldHaveMainframe(gt.region, checkAlways)) {
				remove(tracked[i]);
				--i; --cnt;
			}
		}

		//Detect new staging bases to build mainframes at
		for(uint i = 0, cnt = military.stagingBases.length; i < cnt; ++i) {
			auto@ base = military.stagingBases[i];
			if(base.occupiedTime < MAINFRAME_MIN_TIMER)
				continue;

			if(get(base.region) is null) {
				LinkRegion@ closest = getClosestLinkRegion(base.region.position);
				if(closest !is null && closest.region.position.distanceTo(base.region.position) < MAINFRAME_MIN_DISTANCE_STAGE)
					continue;

				LinkRegion gt;
				@gt.region = base.region;
				tracked.insertLast(gt);
				break;
			}
		}

		//Detect new important planets to build mainframes at
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			auto@ focus = development.focuses[i];
			Region@ reg = focus.obj.region;
			if(reg is null)
				continue;

			if(get(reg) is null) {
				LinkRegion@ closest = getClosestLinkRegion(reg.position);
				if(closest !is null && closest.region.position.distanceTo(reg.position) < MAINFRAME_MIN_DISTANCE_DEVELOP)
					continue;

				LinkRegion gt;
				@gt.region = reg;
				tracked.insertLast(gt);
				break;
			}
		}

		//See if we should build a new mainframe
		if(buildMainframe !is null) {
			if(buildMainframe.completed) {
				@buildMainframe = null;
				nextBuildTry = gameTime + 60.0;
			}
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			if(gt.obj is null) {
				Object@ closest;
				double closestDist = INFINITY;
				for(uint n = 0, ncnt = unassigned.length; n < ncnt; ++n) {
					Object@ obj = unassigned[n];
					if(obj.region is gt.region) {
						@closest = obj;
						break;
					}
					if(!obj.hasMover)
						continue;
					if(buildMainframe is null && gameTime > nextBuildTry) {
						double d = obj.position.distanceTo(gt.region.position);
						if(d < closestDist) {
							closestDist = d;
							@closest = obj;
						}
					}
				}

				if(closest !is null) {
					if(log)
						ai.print("Assign mainframe to => "+gt.region.name, closest.region);
					assignTo(gt, closest);
				} else if(buildMainframe is null && gameTime > nextBuildTry) {
					if(log)
						ai.print("Build mainframe for this system", gt.region);

					bool buildLocal = true;
					auto@ factory = construction.primaryFactory;
					if(factory !is null) {
						Region@ factRegion = factory.obj.region;
						if(factRegion !is null && systems.hopDistance(gt.region, factRegion) < MAINFRAME_BUILD_MOVE_HOPS)
							buildLocal = false;
					}

					if(buildLocal)
						@buildMainframe = construction.buildLocalOrbital(getOrbitalModule(mainframeId));
					else
						@buildMainframe = construction.buildOrbital(getOrbitalModule(mainframeId), military.getStationPosition(gt.region));
				}
			}
		}
	}
};

AIComponent@ createLinked() {
	return Linked();
}
