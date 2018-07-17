// Creeping
// --------
// Uses fleets that aren't currently doing anything to eliminate creeps.
//

import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Movement;
import empire_ai.weasel.searches;

import saving;
from empire import Creeps;

class CreepingMission : Mission {
	Pickup@ pickup;
	Object@ protector;

	MoveOrder@ move;

	void save(Fleets& fleets, SaveFile& file) {
		file << pickup;
		file << protector;
		fleets.movement.saveMoveOrder(file, move);
	}

	void load(Fleets& fleets, SaveFile& file) {
		file >> pickup;
		file >> protector;
		@move = fleets.movement.loadMoveOrder(file);
	}

	void start(AI& ai, FleetAI& fleet) override {
		vec3d position = pickup.position;
		double dist = fleet.radius;
		if(protector !is null && protector.valid)
			dist = fleet.obj.getEngagementRange();
		position += (fleet.obj.position - pickup.position).normalized(dist);

		@move = cast<Movement>(ai.movement).move(fleet.obj, position);
	}

	void tick(AI& ai, FleetAI& fleet, double time) {
		if(move !is null) {
			if(move.completed) {
				if(protector !is null && protector.valid) {
					if(!protector.isVisibleTo(ai.empire)) { //Yo nebulas are scary yo
						fleet.obj.addMoveOrder(protector.position);
						fleet.obj.addAttackOrder(protector, append=true);
					}
					else {
						fleet.obj.addAttackOrder(protector);
					}
				}
				@move = null;
			}
			else if(move.failed) {
				canceled = true;
				return;
			}
			else
				return;
		}
		if(protector is null || !protector.valid) {
			if(!fleet.obj.hasOrders) {
				if(pickup is null || !pickup.valid) {
					if(cast<Creeping>(ai.creeping).log)
						ai.print("Finished clearing creep camp", fleet.obj);
					completed = true;
				}
				else {
					fleet.obj.addPickupOrder(pickup);
					@protector = null;
				}
			}
		}
		else {
			if((fleet.filled < 0.3 || fleet.supplies < 0.3 || fleet.flagshipHealth < 0.4)
				&& protector.getFleetStrength() * ai.behavior.remnantOverkillFactor > fleet.strength) {
				//Holy shit what's going on? ABORT! ABORT!
				if(cast<Creeping>(ai.creeping).logCritical)
					ai.print("ABORTED CREEPING: About to lose fight", fleet.obj);
				canceled = true;
				cast<Fleets>(ai.fleets).returnToBase(fleet, MP_Critical);
			}
		}
	}
};

class ClearMission : Mission {
	Region@ region;
	Object@ eliminate;

	MoveOrder@ move;

	void save(Fleets& fleets, SaveFile& file) {
		file << region;
		file << eliminate;
		fleets.movement.saveMoveOrder(file, move);
	}

	void load(Fleets& fleets, SaveFile& file) {
		file >> region;
		file >> eliminate;
		@move = fleets.movement.loadMoveOrder(file);
	}

	void start(AI& ai, FleetAI& fleet) override {
		@move = cast<Movement>(ai.movement).move(fleet.obj, region);
	}

	void tick(AI& ai, FleetAI& fleet, double time) {
		if(move !is null) {
			if(move.completed) {
				@move = null;
			}
			else if(move.failed) {
				canceled = true;
				return;
			}
			else
				return;
		}

		if(eliminate is null) {
			@eliminate = cast<Creeping>(ai.creeping).findRemnants(region);
			if(eliminate is null) {
				completed = true;
				return;
			}
		}

		if(eliminate !is null) {
			if(!eliminate.valid) {
				@eliminate = null;
			}
			else {
				if(!fleet.obj.hasOrders)
					fleet.obj.addAttackOrder(eliminate);

				if((fleet.filled < 0.3 || fleet.supplies < 0.3 || fleet.flagshipHealth < 0.4)
					&& eliminate.getFleetStrength() * ai.behavior.remnantOverkillFactor > fleet.strength) {
					//Holy shit what's going on? ABORT! ABORT!
					if(cast<Creeping>(ai.creeping).logCritical)
						ai.print("ABORTED CREEPING: About to lose fight", fleet.obj);
					canceled = true;
					cast<Fleets>(ai.fleets).returnToBase(fleet, MP_Critical);
				}
			}
		}
	}
};

final class CreepPenalty : Savable {
	Object@ obj;
	double until;

	void save(SaveFile& file) {
		file << obj;
		file << until;
	}

	void load(SaveFile& file) {
		file >> obj;
		file >> until;
	}
};

final class ClearSystem {
	SystemAI@ sys;
	array<Ship@> remnants;

	void save(Creeping& creeping, SaveFile& file) {
		creeping.systems.saveAI(file, sys);
		uint cnt = remnants.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << remnants[i];
	}

	void load(Creeping& creeping, SaveFile& file) {
		@sys = creeping.systems.loadAI(file);
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Ship@ remn;
			file >> remn;
			if(remn !is null)
				remnants.insertLast(remn);
		}
	}

	void record() {
		auto@ objs = findEnemies(sys.obj, null, Creeps.mask);
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(objs[i]);
			if(ship !is null)
				remnants.insertLast(ship);
		}
	}

	double getStrength() {
		double str = 0.0;
		for(uint i = 0, cnt = remnants.length; i < cnt; ++i) {
			if(remnants[i].valid)
				str += sqrt(remnants[i].getFleetStrength());
		}
		return str * str;
	}
};

class Creeping : AIComponent {
	Systems@ systems;
	Fleets@ fleets;

	array<SystemAI@> requested;
	array<CreepPenalty@> penalties;
	array<CreepingMission@> active;

	array<ClearSystem@> quarantined;

	void create() {
		@systems = cast<Systems>(ai.systems);
		@fleets = cast<Fleets>(ai.fleets);
	}

	void save(SaveFile& file) {
		uint cnt = requested.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			systems.saveAI(file, requested[i]);

		cnt = penalties.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << penalties[i];

		cnt = active.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, active[i]);

		cnt = quarantined.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			quarantined[i].save(this, file);
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ sys = systems.loadAI(file);
			if(sys !is null)
				requested.insertLast(sys);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			CreepPenalty pen;
			file >> pen;
			if(pen.obj !is null)
				penalties.insertLast(pen);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<CreepingMission>(fleets.loadMission(file));
			if(miss !is null)
				active.insertLast(miss);
		}

		if(file >= SV_0151) {
			file >> cnt;
			for(uint i = 0; i < cnt; ++i) {
				ClearSystem qsys;
				qsys.load(this, file);
				quarantined.insertLast(qsys);
			}
		}
	}

	void requestClear(SystemAI@ system) {
		if(system is null)
			return;
		if(log)
			ai.print("Requested creep camp clear", system.obj);
		if(requested.find(system) == -1)
			requested.insertLast(system);
	}

	CreepingMission@ creepWithFleet(FleetAI@ fleet, Pickup@ pickup, Object@ protector = null) {
		if(protector is null)
			@protector = pickup.getProtector();

		if(log)
			ai.print("Clearing creep camp in "+pickup.region.name, fleet.obj);

		CreepingMission mission;
		@mission.pickup = pickup;
		@mission.protector = protector;

		fleets.performMission(fleet, mission);
		active.insertLast(mission);
		return mission;
	}

	Pickup@ best;
	Object@ bestProtector;
	vec3d ourPosition;
	double bestWeight;
	double ourStrength;

	void check(SystemAI@ sys, double weight = 1.0) {
		for(uint n = 0, ncnt = sys.pickups.length; n < ncnt; ++n) {
			Pickup@ pickup = sys.pickups[n];
			Object@ protector = sys.pickupProtectors[n];
			
			if(!pickup.valid)
				continue;

			double protStrength;
			if(protector !is null && protector.valid) {
				protStrength = protector.getFleetStrength();

				if(protStrength * ai.behavior.remnantOverkillFactor > ourStrength)
					continue;
			}
			else
				protStrength = 1.0;

			if(isCreeping(pickup))
				continue;

			double w = weight;
			w /= protStrength / 1000.0;
			w /= pickup.position.distanceTo(ourPosition);

			if(w > bestWeight) {
				bestWeight = w;
				@best = pickup;
				@bestProtector = protector;
			}
		}
	}

	void penalize(Object@ obj, double time) {
		for(uint i = 0, cnt = penalties.length; i < cnt; ++i) {
			if(penalties[i].obj is obj) {
				penalties[i].until = max(penalties[i].until, gameTime + time);
				return;
			}
		}

		CreepPenalty p;
		@p.obj = obj;
		p.until = gameTime + time;
		penalties.insertLast(p);
	}

	bool isPenalized(Object@ obj) {
		for(uint i = 0, cnt = penalties.length; i < cnt; ++i) {
			if(penalties[i].obj is obj)
				return true;
		}
		return false;
	}

	bool isCreeping(Pickup@ pickup) {
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].pickup is pickup)
				return true;
		}
		return false;
	}

	CreepingMission@ creepWithFleet(FleetAI@ fleet) {
		@best = null;
		@bestProtector = null;
		bestWeight = 0.0;
		ourStrength = fleet.strength;
		ourPosition = fleet.obj.position;

		//Check requested systems first
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ sys = requested[i];

			if(sys.pickups.length == 0) {
				requested.removeAt(i);
				--i; --cnt;
				continue;
			}

			if(haveQuarantinedSystem(sys))
				continue;

			check(sys);
		}

		if(best !is null)
			return creepWithFleet(fleet, best, bestProtector);

		if(!ai.behavior.remnantAllowArbitraryClear)
			return null;

		if(log)
			ai.print("Attempted to find creep camp to clear", fleet.obj);

		//Check systems in our territory
		for(uint i = 0, cnt = systems.owned.length; i < cnt; ++i) {
			SystemAI@ sys = systems.owned[i];
			if(sys.pickups.length != 0)
				check(sys);
		}

		if(best !is null)
			return creepWithFleet(fleet, best, bestProtector);

		//Check systems just outside our border
		for(uint i = 0, cnt = systems.outsideBorder.length; i < cnt; ++i) {
			SystemAI@ sys = systems.outsideBorder[i];
			if(sys.seenPresent & ai.otherMask != 0)
				continue;
			if(haveQuarantinedSystem(sys))
				continue;
			if(sys.pickups.length != 0)
				check(sys, 1.0 / double(1.0 + sys.hopDistance));
		}

		if(best !is null)
			return creepWithFleet(fleet, best, bestProtector);

		penalize(fleet.obj, 90.0);
		return null;
	}

	Object@ findRemnants(Region@ reg) {
		for(uint i = 0, cnt = quarantined.length; i < cnt; ++i) {
			auto@ qsys = quarantined[i];
			if(qsys.sys.obj !is reg)
				continue;

			for(uint n = 0, ncnt = qsys.remnants.length; n < ncnt; ++n) {
				auto@ remn = qsys.remnants[n];
				if(remn is null || !remn.valid)
					continue;
				return remn;
			}
		}
		return null;
	}

	ClearMission@ sendToClear(FleetAI@ fleet, ClearSystem@ system) {
		ClearMission miss;
		@miss.region = system.sys.obj;

		fleets.performMission(fleet, miss);
		if(log)
			ai.print("Clear remnant defenders in "+miss.region.name, fleet.obj);
		return miss;
	}

	bool isQuarantined(SystemAI@ sys) {
		if(sys.planets.length == 0)
			return false;
		for(uint i = 0, cnt = sys.planets.length; i < cnt; ++i) {
			if(!sys.planets[i].quarantined)
				return false;
		}
		return true;
	}

	bool isQuarantined(Region@ region) {
		for(uint i = 0, cnt = quarantined.length; i < cnt; ++i) {
			if(quarantined[i].sys.obj is region)
				return true;
		}
		return false;
	}

	bool haveQuarantinedSystem(SystemAI@ sys) {
		for(uint i = 0, cnt = quarantined.length; i < cnt; ++i) {
			if(quarantined[i].sys is sys)
				return true;
		}
		return false;
	}

	void recordQuarantinedSystem(SystemAI@ sys) {
		ClearSystem qsys;
		@qsys.sys = sys;
		quarantined.insertLast(qsys);

		qsys.record();
	}

	uint ownedCheck = 0;
	uint outsideCheck = 0;
	void focusTick(double time) {
		//Manage creeping check penalties
		for(uint i = 0, cnt = penalties.length; i < cnt; ++i) {
			if(penalties[i].until < gameTime) {
				penalties.removeAt(i);
				--i; --cnt;
			}
		}

		//Manage current creeping missions
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].completed || active[i].canceled) {
				active.removeAt(i);
				--i; --cnt;
			}
		}

		//Find new systems that are quarantined
		if(systems.owned.length != 0) {
			ownedCheck = (ownedCheck+1) % systems.owned.length;
			auto@ sys = systems.owned[ownedCheck];
			if(sys.explored && isQuarantined(sys)) {
				if(!haveQuarantinedSystem(sys))
					recordQuarantinedSystem(sys);
			}
		}
		if(systems.outsideBorder.length != 0) {
			outsideCheck = (outsideCheck+1) % systems.outsideBorder.length;
			auto@ sys = systems.outsideBorder[outsideCheck];
			if(sys.explored && isQuarantined(sys)) {
				if(!haveQuarantinedSystem(sys))
					recordQuarantinedSystem(sys);
			}
		}

		//Update existing quarantined systems list
		for(uint i = 0, cnt = quarantined.length; i < cnt; ++i) {
			auto@ qsys = quarantined[i];
			if(!isQuarantined(qsys.sys)) {
				quarantined.removeAt(i);
				--i; --cnt;
				continue;
			}
			for(uint n = 0, ncnt = qsys.remnants.length; n < ncnt; ++n) {
				auto@ remn = qsys.remnants[n];
				if(remn is null || !remn.valid || remn.region !is qsys.sys.obj) {
					qsys.remnants.removeAt(n);
					--n; --ncnt;
				}
			}
		}

		//See if we should try to clear a quarantined system
		bool waitingForGather = false;
		if(ai.behavior.remnantAllowArbitraryClear) {
			ClearSystem@ best;
			double bestStr = INFINITY;

			for(uint i = 0, cnt = quarantined.length; i < cnt; ++i) {
				double str = quarantined[i].getStrength();
				if(quarantined[i].remnants.length == 0)
					continue;
				if(str < bestStr) {
					bestStr = str;
					@best = quarantined[i];
				}
			}

			if(best !is null) {
				double needStr = bestStr * ai.behavior.remnantOverkillFactor;
				if(fleets.getTotalStrength(FC_Combat) > needStr) {
					waitingForGather = true;
					if(fleets.getTotalStrength(FC_Combat, readyOnly=true) > needStr) {
						//Order sufficient fleets to go clear this system
						double takeStr = sqrt(needStr);
						double haveStr = 0.0;

						uint offset = randomi(0, fleets.fleets.length-1);
						for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
							FleetAI@ fleet = fleets.fleets[(i+offset)%cnt];
							if(fleet.fleetClass != FC_Combat)
								continue;
							if(!fleet.readyForAction)
								continue;

							haveStr += sqrt(fleet.strength);
							sendToClear(fleet, best);

							if(haveStr > takeStr)
								break;
						}
					}
				}
			}
		}

		//Find new fleets to creep with
		if(!waitingForGather) {
			uint offset = randomi(0, fleets.fleets.length-1);
			for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
				FleetAI@ fleet = fleets.fleets[(i+offset)%cnt];
				if(fleet.fleetClass != FC_Combat)
					continue;
				if(!fleet.readyForAction)
					continue;
				if(isPenalized(fleet.obj))
					continue;

				creepWithFleet(fleet);
				break;
			}
		}
	}
};

AIComponent@ createCreeping() {
	return Creeping();
}
