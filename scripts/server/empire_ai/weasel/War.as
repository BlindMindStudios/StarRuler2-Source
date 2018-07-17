// War
// ---
// Attacks and defends from enemy attacks during situations of war.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Intelligence;
import empire_ai.weasel.Relations;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Scouting;
import empire_ai.weasel.Military;
import empire_ai.weasel.searches;

import regions.regions;

class BattleMission : Mission {
	Region@ battleIn;
	FleetAI@ fleet;
	MoveOrder@ move;
	Object@ defending;
	Planet@ capturing;
	Empire@ captureFrom;
	bool arrived = false;

	void save(Fleets& fleets, SaveFile& file) override {
		file << battleIn;
		fleets.saveAI(file, fleet);
		fleets.movement.saveMoveOrder(file, move);
		file << defending;
		file << capturing;
		file << captureFrom;
		file << arrived;
	}

	void load(Fleets& fleets, SaveFile& file) override {
		file >> battleIn;
		@fleet = fleets.loadAI(file);
		@move = fleets.movement.loadMoveOrder(file);
		file >> defending;
		file >> capturing;
		file >> captureFrom;
		file >> arrived;
	}
};

double captureSupply(Empire& emp, Object& check) {
	double loy = check.getLoyaltyFacing(emp);
	double cost = config::SIEGE_LOYALTY_SUPPLY_COST * loy;
	cost *= emp.CaptureSupplyFactor;
	cost *= check.owner.CaptureSupplyDifficulty;
	return cost;
}

class Battle {
	SystemAI@ system;
	Region@ staging;
	array<BattleMission@> fleets;
	uint curPriority = MiP_Critical;
	bool isAttack = false;

	double enemyStrength;
	double ourStrength;
	double lastCombat = 0;
	double bestCapturePct;
	double lastHadFleets = 0;
	bool inCombat = false;
	bool isUnderSiege = false;

	Planet@ defendPlanet;
	Object@ eliminate;

	Battle() {
		lastHadFleets = gameTime;
		lastCombat = gameTime;
	}

	void save(War& war, SaveFile& file) {
		war.systems.saveAI(file, system);

		uint cnt = fleets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			war.fleets.saveMission(file, fleets[i]);

		file << curPriority;
		file << isAttack;
		file << lastCombat;
		file << inCombat;
		file << defendPlanet;
		file << eliminate;
		file << isUnderSiege;
		file << bestCapturePct;
	}

	void load(War& war, SaveFile& file) {
		@system = war.systems.loadAI(file);

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ miss = cast<BattleMission>(war.fleets.loadMission(file));
			if(miss !is null)
				fleets.insertLast(miss);
		}

		file >> curPriority;
		file >> isAttack;
		file >> lastCombat;
		file >> inCombat;
		file >> defendPlanet;
		file >> eliminate;
		file >> isUnderSiege;
		file >> bestCapturePct;
	}

	BattleMission@ join(AI& ai, War& war, FleetAI@ flAI) {
		BattleMission mission;
		@mission.fleet = flAI;
		@mission.battleIn = system.obj;
		mission.priority = curPriority;

		Object@ moveTo = system.obj;
		if(defendPlanet !is null)
			@moveTo = defendPlanet;
		else if(eliminate !is null && eliminate.isShip)
			@moveTo = eliminate;
		@mission.move = war.movement.move(flAI.obj, moveTo, MP_Critical, spread=true, nearOnly=true);

		//Station this fleet nearby after the battle is over
		if(staging !is null)
			war.military.stationFleet(flAI, staging);

		if(war.log)
			ai.print("Assign to battle at "+system.obj.name
					+" for strength "+standardize(ourStrength * 0.001, true)
					+ " vs their "+standardize(enemyStrength * 0.001, true), flAI.obj);

		fleets.insertLast(mission);
		war.fleets.performMission(flAI, mission);
		return mission;
	}

	bool stayingHere(Object@ other) {
		if(other is null || !other.hasMover)
			return true;
		if(!inRegion(system.obj, other.position))
			return false;
		double acc = other.maxAcceleration;
		if(acc <= 0.0001)
			return true;
		vec3d compDest = other.computedDestination;
		if(inRegion(system.obj, compDest))
			return true;
		if(inRegion(system.obj, other.position + other.velocity * 10.0))
			return true;
		return false;
	}

	bool tick(AI& ai, War& war, double time) {
		//Compute strength values
		enemyStrength = getTotalFleetStrength(system.obj, ai.enemyMask, planets=true);
		ourStrength = 0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			ourStrength += sqrt(fleets[i].fleet.strength);
		ourStrength *= ourStrength;
		inCombat = false;
		bool ourPlanetsPresent = system.obj.PlanetsMask & (ai.allyMask | ai.mask) != 0;

		if((enemyStrength < 0.01 || !ourPlanetsPresent) && defendPlanet is null)
			isUnderSiege = false;

		//Remove lost fleets
		bool anyArrived = false;
		bestCapturePct = 0.0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			auto@ miss = fleets[i];
			miss.priority = curPriority;
			if(!miss.fleet.obj.valid || miss.canceled) {
				if(!miss.fleet.obj.valid) {
					for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
						Empire@ other = getEmpire(i);
						if(!other.major || !ai.empire.isHostile(other))
							continue;
						if(system.obj.ContestedMask & other.mask != 0)
							war.relations.recordLostTo(other, miss.fleet.obj);
					}
				}
				miss.canceled = true;
				if(war.log)
					ai.print("BATTLE: lost fleet "+miss.fleet.obj.name, system.obj);
				fleets.removeAt(i);
				--i; --cnt;
				if(fleets.length == 0)
					lastHadFleets = gameTime;
				continue;
			}
			if(miss.move !is null) {
				if(miss.move.failed) {
					miss.canceled = true;
					if(war.log)
						ai.print("BATTLE: move failed on lost fleet "+miss.fleet.obj.name, system.obj);
					fleets.removeAt(i);
					--i; --cnt;
					if(fleets.length == 0)
						lastHadFleets = gameTime;
					continue;
				}
				if(miss.move.completed) {
					miss.arrived = true;
					@miss.move = null;
				}
			}
			if(miss.arrived) {
				anyArrived = true;

				bool shouldRetreat = false;
				if(miss.fleet.supplies < 0.05) {
					if(isCapturingAny && eliminate is null)
						shouldRetreat = true;
					else if(ourStrength < enemyStrength * 0.75)
						shouldRetreat = true;
				}
				if(miss.fleet.fleetHealth < 0.25) {
					if(ourStrength < enemyStrength * 0.5)
						shouldRetreat = true;
				}
				if(shouldRetreat) {
					war.fleets.returnToBase(miss.fleet);
					fleets.removeAt(i);
					miss.canceled = true;
					--i; --cnt;
					if(fleets.length == 0)
						lastHadFleets = gameTime;
					continue;
				}
			}
			if(miss.capturing !is null)
				bestCapturePct = max(bestCapturePct, miss.capturing.capturePct);
		}

		//Defend our planets
		if(defendPlanet is null) {
			Planet@ defPl;
			double bestWeight = 0.0;
			for(uint i = 0, cnt = system.planets.length; i < cnt; ++i) {
				Planet@ pl = system.planets[i];
				double w = 1.0;
				if(pl.owner is ai.empire)
					w *= 2.0;
				else if(pl.owner.mask & ai.allyMask != 0)
					w *= 0.5;
				else
					continue;
				double capt = pl.capturePct;
				if(capt <= 0.01)
					continue;
				w *= capt;

				if(!pl.enemiesInOrbit)
					continue;
				if(w > bestWeight) {
					bestWeight = w;
					@defPl = pl;
				}
			}

			if(defPl !is null) {
				if(war.log)
					ai.print("BATTLE: protect planet "+defPl.name, system.obj);

				@defendPlanet = defPl;
				for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
					moveTo(fleets[i], defendPlanet, force=true);
			}
		}
		else {
			//Check if there are still enemies in orbit
			if(!defendPlanet.enemiesInOrbit || !defendPlanet.valid || defendPlanet.owner.isHostile(ai.empire))
				@defendPlanet = null;
		}
		if(defendPlanet !is null) {
			//Make sure one fleet is in orbit
			inCombat = true;
			isUnderSiege = true;
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
				moveTo(fleets[i], defendPlanet);
		}

		//Eliminate any remaining threats
		if(!inCombat) {
			//Eliminate any hostile targets in the system
			if(eliminate !is null) {
				//Make sure this is still a valid target to eliminate
				bool valid = true;
				if(!eliminate.valid) {
					valid = false;
					war.relations.recordTakenFrom(eliminate.owner, eliminate);
				}
				else if(!stayingHere(eliminate))
					valid = false;
				else if(!eliminate.isVisibleTo(ai.empire))
					valid = false;
				else if(!ai.empire.isHostile(eliminate.owner))
					valid = false;

				if(!valid) {
					@eliminate = null;
					clearOrders();
				}
				else {
					for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
						attack(fleets[i], eliminate);
					inCombat = true;
				}
			}
			else {
				//Find a new target to eliminate
				Object@ check = findEnemy(system.obj, ai.empire, ai.enemyMask);
				if(check !is null) {
					if(stayingHere(check)) {
						@eliminate = check;
						for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
							auto@ obj = fleets[i].fleet.obj;
							if(!fleets[i].arrived)
								continue;
							obj.addAttackOrder(eliminate);
						}

						if(war.log)
							ai.print("BATTLE: Eliminate "+eliminate.name, system.obj);

						inCombat = true;
						for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
							attack(fleets[i], eliminate, force=true);
					}
				}
			}
		}
		else {
			@eliminate = null;
		}

		//Capture enemy planets if possible
		//TODO: Respond to defense by abandoning all but 1 capture and swarming around the best one
		if(!inCombat) {
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				auto@ miss = fleets[i];
				if(miss.capturing !is null) {
					if(canCapture(ai, miss, miss.capturing) && miss.fleet.remainingSupplies > captureSupply(ai.empire, miss.capturing) && miss.fleet.obj.hasOrders) {
						inCombat = true;
						continue;
					}
					else {
						if(miss.capturing.owner is ai.empire && miss.captureFrom !is null)
							war.relations.recordTakenFrom(miss.captureFrom, miss.capturing);
						@miss.capturing = null;
						@miss.captureFrom = null;
					}
				}
				if(!miss.arrived)
					continue;

				Planet@ bestCapture;
				double totalWeight = 0;

				for(uint i = 0, cnt = system.planets.length; i < cnt; ++i) {
					Planet@ check = system.planets[i];
					if(!canCapture(ai, miss, check))
						continue;

					//Don't send two fleets to the same thing
					if(isCapturing(check))
						continue;

					//Make sure we have the supplies remaining to capture
					if(miss.fleet.remainingSupplies < captureSupply(ai.empire, check) * ai.behavior.captureSupplyEstimate)
						continue;

					double str = check.getFleetStrength();
					double w = 1.0;
					w *= check.getLoyaltyFacing(ai.empire);
					if(str != 0)
						w /= str;

					totalWeight += w;
					if(randomd() < w / totalWeight)
						@bestCapture = check;
				}

				if(bestCapture !is null) {
					if(war.log)
						ai.print("BATTLE: Capture "+bestCapture.name+" with "+miss.fleet.obj.name, system.obj);

					@miss.capturing = bestCapture;
					@miss.captureFrom = bestCapture.owner;
					miss.fleet.obj.addCaptureOrder(bestCapture);
					inCombat = true;
				}
			}
		}
		else {
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				auto@ miss = fleets[i];
				@miss.capturing = null;
				@miss.captureFrom = null;
			}
		}

		//Keep fleets here in non-critical mode for a few minutes
		if(!inCombat && (anyArrived || !isAttack)) {
			//TODO: Don't start this countdown until we've actually arrived
			if(gameTime > lastCombat + 90.0) {
				for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
					fleets[i].completed = true;
				if(war.log)
					ai.print("BATTLE: ended", system.obj);
				return false;
			}
			else if(gameTime > lastCombat + 30.0) {
				curPriority = MiP_Normal;
			}
			else {
				curPriority = MiP_High;
			}
		}
		else {
			if(ourPlanetsPresent && isUnderSiege) {
				curPriority = MiP_Critical;
				if(war.winnability(this) < 0.5)
					curPriority = MiP_High;
			}
			else if(bestCapturePct > 0.75)
				curPriority = MiP_Critical;
			else
				curPriority = MiP_High;
			lastCombat = gameTime;
		}

		//If needed, claim fleets
		if(ourStrength < enemyStrength * ai.behavior.battleStrengthOverkill) {
			FleetAI@ claim;
			double bestWeight = 0;

			for(uint i = 0, cnt = war.fleets.fleets.length; i < cnt; ++i) {
				auto@ fleet = war.fleets.fleets[i];
				double w = war.assignable(this, fleet);

				if(w > bestWeight) {
					bestWeight = w;
					@claim = fleet;
				}
			}

			if(claim !is null)
				join(ai, war, claim);
		}

		//Give up the battle when we should
		if(fleets.length == 0) {
			if(!ourPlanetsPresent && !isAttack) {
				//We lost all our planets before we could respond with anything.
				// We might be able to use an attack to claim it back later, but for now we just give up on it.
				if(war.log)
					ai.print("BATTLE: aborted defense, no fleets and no planets left", system.obj);
				for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
					fleets[i].canceled = true;
				return false;
			}
			if(isAttack) {
				//We haven't been able to find any fleets to assign here for a while,
				//so just abort the attack
				if(gameTime - lastHadFleets > 60.0) {
					if(war.log)
						ai.print("BATTLE: aborted attack, no fleets available", system.obj);
					for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
						fleets[i].canceled = true;
					return false;
				}
			}
		}

		return true;
	}

	void clearOrders() {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			auto@ obj = fleets[i].fleet.obj;
			if(!fleets[i].arrived)
				continue;
			if(obj.hasOrders)
				obj.clearOrders();
		}
	}

	bool canCapture(AI& ai, BattleMission@ miss, Planet@ check) {
		if(!ai.empire.isHostile(check.owner))
			return false;
		//TODO: Wait around a while maybe?
		if(check.isProtected(ai.empire))
			return false;
		return true;
	}

	void moveTo(BattleMission@ miss, Planet@ defPl, bool force = false) {
		if(!miss.arrived)
			return;
		if(!force) {
			if(miss.fleet.obj.hasOrders)
				return;
			double dist = miss.fleet.obj.position.distanceTo(defPl.position);
			if(dist < defPl.OrbitSize)
				return;
		}
		vec3d pos = defPl.position;
		vec2d offset = random2d(defPl.OrbitSize * 0.85);
		pos.x += offset.x;
		pos.z += offset.y;
		miss.fleet.obj.addMoveOrder(pos);
	}

	void attack(BattleMission@ miss, Object@ target, bool force = false) {
		//TODO: make this not chase stuff out of the system like a madman?
		// (in attack logic as well)
		if(!miss.arrived)
			return;
		if(!force) {
			if(miss.fleet.obj.hasOrders)
				return;
		}
		miss.fleet.obj.addAttackOrder(target);
	}

	bool isCapturing(Planet@ pl) {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			if(fleets[i].capturing is pl)
				return true;
		}
		return false;
	}

	bool get_isCapturingAny() {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			if(fleets[i].capturing !is null)
				return true;
		}
		return false;
	}
};

class War : AIComponent {
	Fleets@ fleets;
	Intelligence@ intelligence;
	Relations@ relations;
	Movement@ movement;
	Scouting@ scouting;
	Systems@ systems;
	Military@ military;

	array<Battle@> battles;

	ScoutingMission@ currentScout;

	void create() {
		@fleets = cast<Fleets>(ai.fleets);
		@intelligence = cast<Intelligence>(ai.intelligence);
		@relations = cast<Relations>(ai.relations);
		@movement = cast<Movement>(ai.movement);
		@scouting = cast<Scouting>(ai.scouting);
		@systems = cast<Systems>(ai.systems);
		@military = cast<Military>(ai.military);
	}

	void save(SaveFile& file) {
		uint cnt = battles.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			battles[i].save(this, file);

		fleets.saveMission(file, currentScout);
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		battles.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@battles[i] = Battle();
			battles[i].load(this, file);
		}

		@currentScout = cast<ScoutingMission>(fleets.loadMission(file));
		ai.behavior.remnantAllowArbitraryClear = false;
	}

	double getCombatReadyStrength() {
		double str = 0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			if(!flAI.readyForAction)
				continue;
			str += flAI.strength;
		}
		return str * str;
	}

	Battle@ attack(SystemAI@ sys) {
		Battle atk;
		@atk.system = sys;
		atk.isAttack = true;
		atk.curPriority = MiP_High;
		@atk.staging = military.getStagingFor(sys.obj);

		if(log)
			ai.print("Organizing an attack against "+sys.obj.name);

		claimFleetsFor(atk);
		battles.insertLast(atk);
		return atk;
	}

	Battle@ defend(SystemAI@ sys) {
		Battle def;
		@def.system = sys;
		@def.staging = military.getClosestStaging(sys.obj);

		if(log)
			ai.print("Organizing defense for "+sys.obj.name);

		battles.insertLast(def);
		return def;
	}

	void claimFleetsFor(Battle@ atk) {
		//TODO: This currently claims everything not in use, should it
		//leave some reserves for defense? Is that good?
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			if(!flAI.readyForAction)
				continue;
			atk.join(ai, this, flAI);
		}
	}

	void sendFleetToJoin(Battle@ atk) {
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			if(!flAI.readyForAction)
				continue;
			atk.join(ai, this, flAI);
			break;
		}
	}

	bool isFightingIn(Region@ reg) {
		for(uint i = 0, cnt = battles.length; i < cnt; ++i) {
			if(battles[i].system.obj is reg)
				return true;
		}
		return false;
	}

	void tick(double time) override {
		for(uint i = 0, cnt = battles.length; i < cnt; ++i) {
			if(!battles[i].tick(ai, this, time)) {
				battles.removeAt(i);
				--i; --cnt;
			}
		}
	}

	double ourStrength;
	double curTime;
	SystemAI@ best;
	double totalWeight;
	SystemAI@ scout;
	uint scoutCount;
	void check(SystemAI@ sys, double baseWeight) {
		if(isFightingIn(sys.obj))
			return;

		if(!sys.visible) {
			sys.strengthCheck(ai, minInterval=5*60.0);
			if(sys.lastStrengthCheck < curTime - 5 * 60.0) {
				scoutCount += 1;
				if(randomd() < 1.0 / double(scoutCount))
					@scout = sys;
				return;
			}
		}
		else {
			sys.strengthCheck(ai, minInterval=60.0);
		}

		double theirStrength = sys.enemyStrength;
		if(ourStrength < theirStrength * ai.behavior.attackStrengthOverkill)
			return;

		double w = baseWeight;

		//Try to capture less important systems at first
		//TODO: This should flip when we go from border skirmishes to subjugation war
		uint capturable = 0;
		for(uint i = 0, cnt = sys.planets.length; i < cnt; ++i) {
			Planet@ pl = sys.planets[i];
			if(!ai.empire.isHostile(pl.owner))
				continue;
			if(pl.isProtected(ai.empire))
				continue;
			w /= 1.0 + double(pl.level);
			capturable += 1;
		}

		//Ignore protected systems
		if(capturable == 0)
			return;

		//See where their defenses are low
		if(theirStrength != 0) {
			double defRatio = ourStrength / theirStrength;
			if(defRatio > 4.0) {
				//We prefer destroying some minor assets over fighting an entirely undefended system,
				//because it hurts more to lose stuff.
				w *= 6.0;
			}
		}
		else {
			w *= 2.0;
		}

		totalWeight += w;
		if(randomd() < w / totalWeight)
			@best = sys;
	}

	int totalEnemySize(SystemAI@ sys) {
		int size = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other.major && ai.empire.isHostile(other))
				size += sys.obj.getStrength(other);
		}
		return size;
	}

	bool isUnderAttack(SystemAI@ sys) {
		if(sys.obj.ContestedMask & ai.mask == 0)
			return false;
		if(totalEnemySize(sys) < 100) {
			if(sys.obj.SiegedMask & ai.mask == 0)
				return false;
		}
		return true;
	}

	double assignable(Battle& battle, FleetAI& fleet) {
		if(fleet.fleetClass != FC_Combat)
			return 0.0;
		double w = 1.0;
		if(fleet.mission !is null) {
			w *= 0.1;
			if(fleet.mission.priority >= MiP_High)
				w *= 0.1;
			if(fleet.mission.priority >= battle.curPriority)
				return 0.0;

			auto@ miss = cast<BattleMission>(fleet.mission);
			if(miss !is null && miss.battleIn is battle.system.obj)
				return 0.0;
		}
		else if(fleet.isHome && fleet.stationed is battle.system.obj) {
			//This should be allowed to fight always
		}
		else if(battle.curPriority >= MiP_Critical) {
			if(fleet.supplies < 0.25)
				return 0.0;
			if(fleet.fleetHealth < 0.25)
				return 0.0;
			if(fleet.filled < 0.2)
				return 0.0;

			if(fleet.obj.isMoving) {
				if(fleet.obj.velocity.length / fleet.obj.maxAcceleration > 16.0)
					w *= 0.1;
			}
		}
		else {
			if(!fleet.readyForAction)
				return 0.0;
		}
		double fleetStrength = fleet.strength;
		if(battle.ourStrength + fleetStrength < battle.enemyStrength * ai.behavior.battleStrengthOverkill)
			w *= 0.25;
		return w;
	}

	double winnability(Battle& battle) {
		double ours = sqrt(battle.ourStrength);
		double theirs = battle.enemyStrength;
		if(theirs <= 0.0)
			return 10.0;

		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ fleet = fleets.fleets[i];
			double w = assignable(battle, fleet);
			if(w != 0.0)
				ours += sqrt(fleet.strength);
		}
		ours *= ours;

		return ours / theirs;
	}

	void focusTick(double time) override {
		if(currentScout !is null) {
			if(currentScout.canceled || currentScout.completed)
				@currentScout = null;
		}

		//Change our behavior a little depending on the state
		ai.behavior.remnantAllowArbitraryClear = !relations.isFightingWar(aggressive=true) && battles.length == 0;

		//Find any systems that need defending
		//TODO: Defend allies at lowered priority
		for(uint i = 0, cnt = systems.owned.length; i < cnt; ++i) {
			SystemAI@ sys = systems.owned[i];
			if(!isUnderAttack(sys))
				continue;
			if(isFightingIn(sys.obj))
				continue;
			defend(sys);
			return;
		}

		//Do attacks
		uint ready = fleets.countCombatReadyFleets();
		if(ready != 0) {
			//See if we can start a new attack
			if(battles.length < ai.behavior.maxBattles && relations.isFightingWar(aggressive=true)
					&& (battles.length == 0 || ready > ai.behavior.battleReserveFleets)) {
				//Determine our own strength
				ourStrength = getCombatReadyStrength();

				//Evaluate systems to attack in our aggressive war
				@best = null;
				totalWeight = 0;
				curTime = gameTime;
				@scout = null;
				scoutCount = 0;
				//TODO: Consider aggressive wars against an empire to also be against that empire's vassals
				for(uint i = 0, cnt = intelligence.intel.length; i < cnt; ++i) {
					auto@ intel = intelligence.intel[i];
					if(intel is null)
						continue;

					auto@ relation = relations.get(intel.empire);
					if(!relation.atWar || !relation.aggressive)
						continue;

					for(uint n = 0, ncnt = intel.shared.length; n < ncnt; ++n) {
						auto@ sys = intel.shared[n];
						check(sys, 20.0);
					}

					for(uint n = 0, ncnt = intel.theirBorder.length; n < ncnt; ++n) {
						auto@ sys = intel.theirBorder[n];
						check(sys, 1.0);
					}
				}

				//Make the attack with our fleets
				if(best !is null)
					attack(best);
				else if(scout !is null && currentScout is null) {
					if(log)
						ai.print("War requests scout to flyby "+scout.obj.name);
					@currentScout = scouting.scout(scout.obj);
				}
			}
		}
	}
};

AIComponent@ createWar() {
	return War();
}
