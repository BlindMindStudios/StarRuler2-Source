import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Military;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Budget;

from statuses import getStatusID;
from abilities import getAbilityID;

const double GATE_MIN_DISTANCE_STAGE = 10000;
const double GATE_MIN_DISTANCE_DEVELOP = 20000;
const double GATE_MIN_DISTANCE_BORDER = 30000;
const double GATE_MIN_TIMER = 3.0 * 60.0;
const int GATE_BUILD_MOVE_HOPS = 5;

int packAbility = -1;
int unpackAbility = -1;

int packedStatus = -1;
int unpackedStatus = -1;

void init() {
	packAbility = getAbilityID("GatePack");
	unpackAbility = getAbilityID("GateUnpack");

	packedStatus = getAbilityID("GatePacked");
	unpackedStatus = getAbilityID("GateUnpacked");
}

class GateRegion : Savable {
	Region@ region;
	Object@ gate;
	bool installed = false;
	vec3d destination;

	void save(SaveFile& file) {
		file << region;
		file << gate;
		file << installed;
		file << destination;
	}

	void load(SaveFile& file) {
		file >> region;
		file >> gate;
		file >> installed;
		file >> destination;
	}
};

class Gate : FTL {
	Military@ military;
	Designs@ designs;
	Construction@ construction;
	Development@ development;
	Systems@ systems;
	Budget@ budget;

	DesignTarget@ gateDesign;

	array<GateRegion@> tracked;
	array<Object@> unassigned;

	BuildStation@ buildGate;
	double nextBuildTry = 15.0 * 60.0;

	void create() override {
		@military = cast<Military>(ai.military);
		@designs = cast<Designs>(ai.designs);
		@construction = cast<Construction>(ai.construction);
		@development = cast<Development>(ai.development);
		@systems = cast<Systems>(ai.systems);
		@budget = cast<Budget>(ai.budget);
	}

	void save(SaveFile& file) override {
		designs.saveDesign(file, gateDesign);
		construction.saveConstruction(file, buildGate);
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
		@gateDesign = designs.loadDesign(file);
		@buildGate = cast<BuildStation>(construction.loadConstruction(file));
		file >> nextBuildTry;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			GateRegion gt;
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

	GateRegion@ get(Region@ reg) {
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].region is reg)
				return tracked[i];
		}
		return null;
	}

	void remove(GateRegion@ gt) {
		if(gt.gate !is null && gt.gate.valid && gt.gate.owner is ai.empire)
			unassigned.insertLast(gt.gate);
		tracked.remove(gt);
	}

	Object@ getClosestGate(const vec3d& position) {
		Object@ closest;
		double minDist = INFINITY;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			Object@ gate = tracked[i].gate;
			if(gate is null)
				continue;
			if(!tracked[i].installed)
				continue;
			double d = gate.position.distanceTo(position);
			if(d < minDist) {
				minDist = d;
				@closest = gate;
			}
		}
		return closest;
	}

	GateRegion@ getClosestGateRegion(const vec3d& position) {
		GateRegion@ closest;
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

	void assignTo(GateRegion@ gt, Object@ closest) {
		unassigned.remove(closest);
		@gt.gate = closest;
		gt.installed = false;

		if(closest.region is gt.region) {
			if(closest.hasStatusEffect(unpackedStatus)) {
				gt.installed = true;
			}
		}

		if(!gt.installed) {
			gt.destination = military.getStationPosition(gt.region);
			closest.activateAbilityTypeFor(ai.empire, packAbility);
			closest.addMoveOrder(gt.destination);
		}
	}

	bool trackingGate(Object@ obj) {
		for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
			if(unassigned[i] is obj)
				return true;
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i].gate is obj)
				return true;
		}
		return false;
	}

	bool shouldHaveGate(Region@ reg, bool always = false) {
		if(military.getBase(reg) !is null)
			return true;
		if(development.isDevelopingIn(reg))
			return true;
		if(!always) {
			auto@ sys = systems.getAI(reg);
			if(sys !is null) {
				if(sys.border && sys.bordersEmpires)
					return true;
			}
		}
		return false;
	}

	void turn() override {
		if(gateDesign !is null && gateDesign.active !is null) {
			int newSize = round(double(budget.spendable(BT_Military)) * 0.5 * ai.behavior.shipSizePerMoney / 64.0) * 64;
			if(newSize < 128)
				newSize = 128;
			if(newSize != gateDesign.targetSize) {
				@gateDesign = designs.design(DP_Gate, newSize);
				gateDesign.customName = "Gate";
			}
		}
	}

	void focusTick(double time) override {
		//Design a gate
		if(gateDesign is null) {
			@gateDesign = designs.design(DP_Gate, 128);
			gateDesign.customName = "Gate";
		}

		//Manage unassigned gates list
		for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
			Object@ obj = unassigned[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				unassigned.removeAt(i);
				--i; --cnt;
			}
		}

		//Detect new gates
		auto@ data = ai.empire.getStargates();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj is null)
				continue;
			if(!trackingGate(obj))
				unassigned.insertLast(obj);
		}

		//Update existing gates for staging bases
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			bool checkAlways = false;
			if(gt.gate !is null) {
				if(!gt.gate.valid || gt.gate.owner !is ai.empire || (gt.installed && gt.gate.region !is gt.region)) {
					@gt.gate = null;
					gt.installed = false;
					checkAlways = true;
				}
				else if(!gt.installed && !gt.gate.hasOrders) {
					if(gt.destination.distanceTo(gt.gate.position) < 10.0) {
						gt.gate.activateAbilityTypeFor(ai.empire, unpackAbility, gt.destination);
						gt.installed = true;
					}
					else {
						gt.gate.activateAbilityTypeFor(ai.empire, packAbility);
						gt.gate.addMoveOrder(gt.destination);
					}
				}
			}
			if(!shouldHaveGate(gt.region, checkAlways)) {
				remove(tracked[i]);
				--i; --cnt;
			}
		}

		//Detect new staging bases to build gates at
		for(uint i = 0, cnt = military.stagingBases.length; i < cnt; ++i) {
			auto@ base = military.stagingBases[i];
			if(base.occupiedTime < GATE_MIN_TIMER)
				continue;

			if(get(base.region) is null) {
				GateRegion@ closest = getClosestGateRegion(base.region.position);
				if(closest !is null && closest.region.position.distanceTo(base.region.position) < GATE_MIN_DISTANCE_STAGE)
					continue;

				GateRegion gt;
				@gt.region = base.region;
				tracked.insertLast(gt);
				break;
			}
		}

		//Detect new important planets to build gates at
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			auto@ focus = development.focuses[i];
			Region@ reg = focus.obj.region;
			if(reg is null)
				continue;

			if(get(reg) is null) {
				GateRegion@ closest = getClosestGateRegion(reg.position);
				if(closest !is null && closest.region.position.distanceTo(reg.position) < GATE_MIN_DISTANCE_DEVELOP)
					continue;

				GateRegion gt;
				@gt.region = reg;
				tracked.insertLast(gt);
				break;
			}
		}

		//Detect new border systems to build gates at
		uint offset = randomi(0, systems.border.length-1);
		for(uint i = 0, cnt = systems.border.length; i < cnt; ++i) {
			auto@ sys = systems.border[(i+offset)%cnt];
			Region@ reg = sys.obj;
			if(reg is null)
				continue;
			if(!sys.bordersEmpires)
				continue;

			if(get(reg) is null) {
				GateRegion@ closest = getClosestGateRegion(reg.position);
				if(closest !is null && closest.region.position.distanceTo(reg.position) < GATE_MIN_DISTANCE_DEVELOP)
					continue;

				GateRegion gt;
				@gt.region = reg;
				tracked.insertLast(gt);
				break;
			}
		}

		//Destroy gates if we're having ftl trouble
		if(ai.empire.FTLShortage) {
			Ship@ leastImportant;
			double leastWeight = INFINITY;

			for(uint i = 0, cnt = unassigned.length; i < cnt; ++i) {
				Ship@ ship = cast<Ship>(unassigned[i]);
				if(ship is null || !ship.valid)
					continue;

				double weight = ship.blueprint.design.size;
				weight *= 10.0;

				if(weight < leastWeight) {
					@leastImportant = ship;
					leastWeight = weight;
				}
			}

			if(leastImportant !is null) {
				if(log)
					ai.print("Scuttle unassigned gate for ftl", leastImportant.region);
				leastImportant.scuttle();
			}
			else {
				for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
					Ship@ ship = cast<Ship>(tracked[i].gate);
					if(ship is null || !ship.valid)
						continue;

					double weight = ship.blueprint.design.size;
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
						@leastImportant = ship;
						leastWeight = weight;
					}
				}

				if(leastImportant !is null) {
					if(log)
						ai.print("Scuttle unimportant gate for ftl", leastImportant.region);
					leastImportant.scuttle();
				}
			}
		}

		//See if we should build a new gate
		if(buildGate !is null) {
			if(buildGate.completed) {
				@buildGate = null;
				nextBuildTry = gameTime + 60.0;
			}
		}
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			auto@ gt = tracked[i];
			if(gt.gate is null && gt.region.ContestedMask & ai.mask == 0 && gt.region.BlockFTLMask & ai.mask == 0) {
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
					if(buildGate is null && gameTime > nextBuildTry) {
						double d = obj.position.distanceTo(gt.region.position);
						if(d < closestDist) {
							closestDist = d;
							@closest = obj;
						}
					}
				}

				if(closest !is null) {
					if(log)
						ai.print("Assign gate to => "+gt.region.name, closest.region);
					assignTo(gt, closest);
				} else if(buildGate is null && gameTime > nextBuildTry && !ai.empire.isFTLShortage(0.15)) {
					if(log)
						ai.print("Build gate for this system", gt.region);

					bool buildLocal = true;
					auto@ factory = construction.primaryFactory;
					if(factory !is null) {
						Region@ factRegion = factory.obj.region;
						if(factRegion !is null && systems.hopDistance(gt.region, factRegion) < GATE_BUILD_MOVE_HOPS)
							buildLocal = false;
					}

					if(buildLocal)
						@buildGate = construction.buildLocalStation(gateDesign);
					else
						@buildGate = construction.buildStation(gateDesign, military.getStationPosition(gt.region));
				}
			}
		}
	}
};

AIComponent@ createGate() {
	return Gate();
}
