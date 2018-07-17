// Scouting
// --------
// Orders the construction of scouts, explores the galaxy with them and makes
// sure we have vision where we need vision, as well as scanning anomalies.
//

import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Creeping;

final class ScoutingMission : Mission {
	Region@ region;
	MoveOrder@ move;

	void save(Fleets& fleets, SaveFile& file) override {
		file << region;
		fleets.movement.saveMoveOrder(file, move);
	}

	void load(Fleets& fleets, SaveFile& file) override {
		file >> region;
		@move = fleets.movement.loadMoveOrder(file);
	}

	double getPerformWeight(AI& ai, FleetAI& fleet) {
		if(fleet.fleetClass != FC_Scout) {
			if(fleet.fleetClass == FC_Mothership)
				return 0.0;
			if(gameTime > ai.behavior.scoutAllTimer)
				return 0.0;
		}
		return 1.0 / region.position.distanceTo(fleet.obj.position);
	}

	void start(AI& ai, FleetAI& fleet) override {
		uint mprior = MP_Background;
		if(gameTime < 6.0 * 60.0)
			mprior = MP_Critical;
		else if(priority > MiP_Normal)
			mprior = MP_Normal;
		@move = cast<Movement>(ai.movement).move(fleet.obj, region, mprior);
	}

	void tick(AI& ai, FleetAI& fleet, double time) {
		if(move.failed)
			canceled = true;
		if(move.completed) {
			//We managed to scout this system
			if(fleet.obj.region !is region) {
				@move = cast<Movement>(ai.movement).move(fleet.obj, region.position + random3d(400.0));
				return;
			}
			completed = true;

			//Detect any anomalies and put them into the scanning queue
			//TODO: Detect newly created anomalies in systems we already have vision over?
			if(region.anomalyCount != 0) {
				auto@ list = region.getAnomalies();
				Object@ obj;
				while(receive(list, obj)) {
					Anomaly@ anom = cast<Anomaly>(obj);
					if(anom !is null)
						cast<Scouting>(ai.scouting).recordAnomaly(anom);
				}
			}
		}
	}
};

final class ScanningMission : Mission {
	Anomaly@ anomaly;
	MoveOrder@ move;

	void save(Fleets& fleets, SaveFile& file) override {
		file << anomaly;
		fleets.movement.saveMoveOrder(file, move);
	}

	void load(Fleets& fleets, SaveFile& file) override {
		file >> anomaly;
		@move = fleets.movement.loadMoveOrder(file);
	}

	double getPerformWeight(AI& ai, FleetAI& fleet) {
		if(fleet.fleetClass != FC_Scout) {
			if(gameTime > ai.behavior.scoutAllTimer)
				return 0.0;
		}
		return 1.0 / anomaly.position.distanceTo(fleet.obj.position);
	}

	void start(AI& ai, FleetAI& fleet) override {
		uint mprior = MP_Background;
		if(priority > MiP_Normal)
			mprior = MP_Normal;
		@move = cast<Movement>(ai.movement).move(fleet.obj, anomaly, mprior);
	}

	void tick(AI& ai, FleetAI& fleet, double time) {
		if(move !is null) {
			if(move.failed) {
				canceled = true;
				return;
			}
			if(move.completed)
				@move = null;
		}
		if(move is null) {
			if(anomaly is null || !anomaly.valid) {
				completed = true;
				return;
			}

			if(anomaly.getEmpireProgress(ai.empire) >= 1.f) {
				uint choose = 0;
				uint possibs = 0;
				uint optCnt = anomaly.getOptionCount();
				for(uint i = 0; i < optCnt; ++i) {
					if(anomaly.isOptionSafe[i]) {
						possibs += 1;
						if(randomd() < 1.0 / double(possibs))
							choose = i;
					}
				}

				if(possibs != 0) {
					anomaly.choose(ai.empire, choose);
				}
				else {
					completed = true;
				}
			}
			else {
				if(!fleet.obj.hasOrders)
					fleet.obj.addScanOrder(anomaly);
			}
		}
	}
};

class Scouting : AIComponent {
	Fleets@ fleets;
	Systems@ systems;
	Designs@ designs;
	Construction@ construction;
	Movement@ movement;
	Creeping@ creeping;

	DesignTarget@ scoutDesign;

	array<ScoutingMission@> queue;
	array<ScoutingMission@> active;

	array<Anomaly@> anomalies;
	array<ScanningMission@> scanQueue;
	array<ScanningMission@> scanActive;

	array<BuildFlagship@> constructing;

	int exploreHops = 0;
	bool buildScouts = true;

	void create() {
		@fleets = cast<Fleets>(ai.fleets);
		@systems = cast<Systems>(ai.systems);
		@designs = cast<Designs>(ai.designs);
		@construction = cast<Construction>(ai.construction);
		@movement = cast<Movement>(ai.movement);
		@creeping = cast<Creeping>(ai.creeping);
	}

	void save(SaveFile& file) {
		designs.saveDesign(file, scoutDesign);
		file << exploreHops;

		uint cnt = queue.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, queue[i]);

		cnt = active.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, active[i]);

		cnt = anomalies.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << anomalies[i];

		cnt = scanQueue.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, scanQueue[i]);

		cnt = scanActive.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, scanActive[i]);

		cnt = constructing.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			construction.saveConstruction(file, constructing[i]);
	}

	void load(SaveFile& file) {
		@scoutDesign = designs.loadDesign(file);
		file >> exploreHops;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<ScoutingMission>(fleets.loadMission(file));
			if(miss !is null)
				queue.insertLast(miss);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<ScoutingMission>(fleets.loadMission(file));
			if(miss !is null)
				active.insertLast(miss);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Anomaly@ anom;
			file >> anom;
			if(anom !is null)
				anomalies.insertLast(anom);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<ScanningMission>(fleets.loadMission(file));
			if(miss !is null)
				scanQueue.insertLast(miss);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<ScanningMission>(fleets.loadMission(file));
			if(miss !is null)
				scanActive.insertLast(miss);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ cons = cast<BuildFlagship>(construction.loadConstruction(file));
			if(cons !is null)
				constructing.insertLast(cons);
		}
	}

	void start() {
		@scoutDesign = DesignTarget(DP_Scout, 16);
		scoutDesign.targetMaintenance = 40;
		designs.design(scoutDesign);
	}

	bool isScouting(Region@ region) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			if(queue[i].region is region)
				return true;
		}
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].region is region)
				return true;
		}
		return false;
	}

	ScoutingMission@ scout(Region@ region, uint priority = MiP_High) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			if(queue[i].region is region)
				return queue[i];
		}

		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].region is region)
				return active[i];
		}

		if(log)
			ai.print("Queue scouting mission", region);

		ScoutingMission mission;
		@mission.region = region;
		mission.priority = priority;
		fleets.register(mission);

		queue.insertLast(mission);
		return mission;
	}

	void recordAnomaly(Anomaly@ anom) {
		for(uint i = 0, cnt = scanActive.length; i < cnt; ++i) {
			if(scanActive[i].anomaly is anom)
				return;
		}

		if(anomalies.find(anom) == -1)
			anomalies.insertLast(anom);
	}

	ScanningMission@ scan(Anomaly& anomaly, uint priority = MiP_Normal) {
		for(uint i = 0, cnt = scanActive.length; i < cnt; ++i) {
			if(scanActive[i].anomaly is anomaly)
				return scanActive[i];
		}

		if(log)
			ai.print("Queue scanning mission on "+anomaly.name, anomaly.region);

		ScanningMission mission;
		@mission.anomaly = anomaly;
		mission.priority = priority;
		fleets.register(mission);
		anomalies.remove(anomaly);

		scanQueue.insertLast(mission);
		return mission;
	}

	void focusTick(double time) {
		//Remove completed scouting missions
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].completed || active[i].canceled) {
				active.removeAt(i);
				--i; --cnt;
			}
		}

		//Remove completed scanning missions
		for(uint i = 0, cnt = scanActive.length; i < cnt; ++i) {
			if(scanActive[i].completed || scanActive[i].canceled) {
				scanActive.removeAt(i);
				--i; --cnt;
			}
		}

		//Make sure we have enough scouts active and scouting
		if(fleets.count(FC_Scout) + constructing.length < ai.behavior.scoutsActive && buildScouts)
			constructing.insertLast(construction.buildFlagship(scoutDesign));
		for(uint i = 0, cnt = constructing.length; i < cnt; ++i) {
			if(constructing[i].completed && constructing[i].completedAt + 30.0 < gameTime) {
				constructing.removeAt(i);
				--i; --cnt;
			}
		}

		//See if we can fill the scouting queue with something nice
		uint scoutClass = FC_Scout;
		if(gameTime < ai.behavior.scoutAllTimer)
			scoutClass = FC_ALL;
		bool haveIdle = fleets.haveIdle(scoutClass);

		//See if we should queue up a new anomaly scan
		if(scanQueue.length == 0 && anomalies.length != 0 && scanActive.length < ai.behavior.maxScanningMissions && haveIdle && (!ai.behavior.prioritizeScoutOverScan || active.length > 0)) {
			Anomaly@ best;
			double bestDist = INFINITY;
			for(uint i = 0, cnt = anomalies.length; i < cnt; ++i) {
				auto@ anom = anomalies[i];
				if(anom is null || !anom.valid) {
					anomalies.removeAt(i);
					--i; --cnt;
					continue;
				}
				if(creeping.isQuarantined(anom.region))
					continue;

				double d = fleets.closestIdleTo(scoutClass, anom.position);
				if(d < bestDist) {
					@best = anom;
					bestDist = d;
				}
			}

			if(best !is null)
				scan(best);
		}

		//Scan anomalies in our scan queue
		if(scanQueue.length != 0) {
			auto@ mission = scanQueue[0];
			if(mission.anomaly is null || !mission.anomaly.valid) {
				scanQueue.removeAt(0);
			}
			else {
				auto@ flAI = fleets.performMission(mission);
				if(flAI !is null) {
					if(log)
						ai.print("Perform scanning mission with "+flAI.obj.name, mission.anomaly.region);

					scanQueue.remove(mission);
					scanActive.insertLast(mission);
				}
			}
		}

		//TODO: In large maps we should probably devote scouts to scouting enemies even before the map is fully explored
		if(queue.length == 0 && active.length < ai.behavior.maxScoutingMissions && haveIdle) {
			//Explore systems from the inside out
			if(exploreHops != -1) {
				double bestDist = INFINITY;
				bool remainingHops = false;
				bool emptyHops = true;
				Region@ best;

				for(uint i = 0, cnt = systems.all.length; i < cnt; ++i) {
					auto@ sys = systems.all[i];

					if(sys.hopDistance == exploreHops)
						emptyHops = false;

					if(sys.explored || isScouting(sys.obj))
						continue;

					if(sys.hopDistance == exploreHops)
						remainingHops = true;

					double d = fleets.closestIdleTo(scoutClass, sys.obj.position);
					if(sys.hopDistance != exploreHops)
						d *= pow(ai.behavior.exploreBorderWeight, double(sys.hopDistance - exploreHops));

					if(d < bestDist) {
						bestDist = d;
						@best = sys.obj;
					}
				}

				if(best !is null)
					scout(best, priority=MiP_Normal);

				if(emptyHops)
					exploreHops = -1;
				else if(!remainingHops)
					exploreHops += 1;
			}
			else {
				//Gain vision over systems we haven't recently seen
				Region@ best;
				double bestWeight = 0;
				double curTime = gameTime;

				for(uint i = 0, cnt = systems.all.length; i < cnt; ++i) {
					auto@ sys = systems.all[i];
					if(sys.visible || sys.visibleNow(ai))
						continue;
					if(isScouting(sys.obj))
						continue;

					double timer = curTime - sys.lastVisible;
					if(timer < ai.behavior.minScoutingInterval)
						continue;

					double w = 1.0;
					w *= timer / ai.behavior.minScoutingInterval;
					w /= fleets.closestIdleTo(scoutClass, sys.obj.position);

					if(!sys.explored)
						w *= 10.0;
					if(sys.seenPresent & ~ai.visionMask != 0)
						w *= 2.0;
					if(sys.seenPresent & ai.enemyMask != 0) {
						if(sys.hopDistance < 2)
							w *= 4.0;
						w *= 4.0;
					}

					if(w > bestWeight) {
						bestWeight = w;
						@best = sys.obj;
					}
				}

				if(best !is null)
					scout(best, priority=MiP_Normal);
			}
		}

		//Try to find a scout to perform our top scouting mission from the queue
		if(queue.length != 0) {
			auto@ mission = queue[0];
			auto@ flAI = fleets.performMission(mission);
			if(flAI !is null) {
				if(log)
					ai.print("Perform scouting mission with "+flAI.obj.name, mission.region);

				active.insertLast(mission);
				queue.removeAt(0);
			}
		}
	}
};

AIComponent@ createScouting() {
	return Scouting();
}
