import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Military;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Fleets;

from statuses import getStatusID;
from abilities import getAbilityID;

from oddity_navigation import hasOddityLink;

const double SS_MIN_DISTANCE_STAGE = 0;
const double SS_MIN_DISTANCE_DEVELOP = 10000;
const double SS_MIN_TIMER = 3.0 * 60.0;
const double SS_MAX_DISTANCE = 3000.0;

class SSRegion : Savable {
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

class Slipstream : FTL {
	Military@ military;
	Designs@ designs;
	Construction@ construction;
	Development@ development;
	Systems@ systems;
	Budget@ budget;
	Fleets@ fleets;

	DesignTarget@ ssDesign;

	array<SSRegion@> tracked;
	array<Object@> unassigned;

	BuildFlagship@ buildSS;
	double nextBuildTry = 15.0 * 60.0;

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
		designs.saveDesign(file, ssDesign);
		construction.saveConstruction(file, buildSS);
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
		@ssDesign = designs.loadDesign(file);
		@buildSS = cast<BuildFlagship>(construction.loadConstruction(file));
		file >> nextBuildTry;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			SSRegion gt;
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

	uint order(MoveOrder& ord) override {
		//Find the position to fling to
		vec3d toPosition;
		if(!targetPosition(ord, toPosition))
			return F_Pass;

		//Check if we have a slipstream generator in this region
		auto@ gt = get(ord.obj.region);
		if(gt is null || gt.obj is null || !gt.arrived)
			return F_Pass;

		//Make sure our generator is usable
		Object@ ssGen = gt.obj;
		if(!canSlipstream(ssGen))
			return F_Pass;

		//Check if we already have a link
		if(hasOddityLink(gt.region, toPosition, SS_MAX_DISTANCE, minDuration=60.0))
			return F_Pass;

		//See if we have the FTL to make a link
		double avail = usableFTL(ai, ord);
		if(!canSlipstreamTo(ssGen, toPosition))
			return F_Pass;
		if(slipstreamCost(ssGen, 0, toPosition.distanceTo(ssGen.position)) >= avail)
			return F_Pass;

		ssGen.addSlipstreamOrder(toPosition, append=true);
		if(ssGen !is ord.obj) {
			ord.obj.addWaitOrder(ssGen, moveTo=true);
			ssGen.addSecondaryToSlipstream(ord.obj);
		}
		else {
			ord.obj.addMoveOrder(toPosition, append=true);
		}

		return F_Continue;
	}

	SSRegion@ get(Region@ reg) {
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].region is reg)
				return tracked[i];
		}
		return null;
	}

	void remove(SSRegion@ gt) {
		if(gt.obj !is null && gt.obj.valid && gt.obj.owner is ai.empire)
			unassigned.insertLast(gt.obj);
		tracked.remove(gt);
	}

	Object@ getClosest(const vec3d& position) {
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

	SSRegion@ getClosestRegion(const vec3d& position) {
		SSRegion@ closest;
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

	void assignTo(SSRegion@ gt, Object@ closest) {
		unassigned.remove(closest);
		@gt.obj = closest;
		gt.arrived = false;
		military.stationFleet(fleets.getAI(closest), gt.region);

		if(closest.region is gt.region)
			gt.arrived = true;

		if(!gt.arrived) {
			gt.destination = military.getStationPosition(gt.region);
			closest.addMoveOrder(gt.destination);
		}
	}

	bool trackingGen(Object@ obj) {
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

	bool shouldHaveGen(Region@ reg, bool always = false) {
		if(military.getBase(reg) !is null)
			return true;
		if(development.isDevelopingIn(reg))
			return true;
		return false;
	}

	void turn() override {
		if(ssDesign !is null && ssDesign.active !is null) {
			int newSize = round(double(budget.spendable(BT_Military)) * 0.2 * ai.behavior.shipSizePerMoney / 64.0) * 64;
			if(newSize < 128)
				newSize = 128;
			if(newSize != ssDesign.targetSize) {
				@ssDesign = designs.design(DP_Slipstream, newSize);
				ssDesign.customName = "Slipstream";
			}
		}
	}

	void focusTick(double time) override {
		//Design a generator
		if(ssDesign is null) {
			@ssDesign = designs.design(DP_Slipstream, 128);
			ssDesign.customName = "Slipstream";
		}

		//Manage unassigned gens list
		for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
			Object@ obj = unassigned[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				unassigned.removeAt(i);
				--i; --cnt;
			}
		}

		//Detect new gens
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Slipstream)
				continue;
			if(!trackingGen(flAI.obj))
				unassigned.insertLast(flAI.obj);
		}

		//Update existing gens for staging bases
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
						assignTo(gt, gt.obj);
				}
			}
			if(!shouldHaveGen(gt.region, checkAlways)) {
				remove(tracked[i]);
				--i; --cnt;
			}
		}

		//Detect new staging bases to build gens at
		for(uint i = 0, cnt = military.stagingBases.length; i < cnt; ++i) {
			auto@ base = military.stagingBases[i];
			if(base.occupiedTime < SS_MIN_TIMER)
				continue;

			if(get(base.region) is null) {
				SSRegion@ closest = getClosestRegion(base.region.position);
				if(closest !is null && closest.region.position.distanceTo(base.region.position) < SS_MIN_DISTANCE_STAGE)
					continue;

				SSRegion gt;
				@gt.region = base.region;
				tracked.insertLast(gt);
				break;
			}
		}

		//Detect new important planets to build generator at
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			auto@ focus = development.focuses[i];
			Region@ reg = focus.obj.region;
			if(reg is null)
				continue;

			if(get(reg) is null) {
				SSRegion@ closest = getClosestRegion(reg.position);
				if(closest !is null && closest.region.position.distanceTo(reg.position) < SS_MIN_DISTANCE_DEVELOP)
					continue;

				SSRegion gt;
				@gt.region = reg;
				tracked.insertLast(gt);
				break;
			}
		}

		//See if we should build a new generator
		if(buildSS !is null) {
			if(buildSS.completed) {
				@buildSS = null;
				nextBuildTry = gameTime + 60.0;
			}
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			if(gt.obj is null && gt.region.ContestedMask & ai.mask == 0 && gt.region.BlockFTLMask & ai.mask == 0) {
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
					if(buildSS is null && gameTime > nextBuildTry) {
						double d = obj.position.distanceTo(gt.region.position);
						if(d < closestDist) {
							closestDist = d;
							@closest = obj;
						}
					}
				}

				if(closest !is null) {
					if(log)
						ai.print("Assign slipstream gen to => "+gt.region.name, closest.region);
					assignTo(gt, closest);
				} else if(buildSS is null && gameTime > nextBuildTry) {
					if(log)
						ai.print("Build slipstream gen for this system", gt.region);

					@buildSS = construction.buildFlagship(ssDesign);
				}
			}
		}

		//Try to get enough ftl storage that we can permanently open a slipstream with each of generators
		double mostCost = 0.0;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			Ship@ obj = cast<Ship>(tracked[i].obj);
			if(obj is null)
				continue;

			double baseCost = obj.blueprint.design.average(SV_SlipstreamCost);
			double duration = obj.blueprint.design.average(SV_SlipstreamDuration);
			mostCost += baseCost / duration;
		}
		development.aimFTLStorage = mostCost;
	}
};

AIComponent@ createSlipstream() {
	return Slipstream();
}
