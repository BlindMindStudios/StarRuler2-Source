import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Movement;
import empire_ai.weasel.searches;

import systems;
from empire import Pirates;

class InvasionDefendMission : Mission {
	FleetAI@ fleet;
	Region@ targRegion;
	MoveOrder@ move;
	bool pending = false;

	Object@ eliminate;

	void save(Fleets& fleets, SaveFile& file) override {
		fleets.saveAI(file, fleet);
		file << targRegion;
		fleets.movement.saveMoveOrder(file, move);
		file << pending;
	}

	void load(Fleets& fleets, SaveFile& file) override {
		@fleet = fleets.loadAI(file);
		file >> targRegion;
		@move = fleets.movement.loadMoveOrder(file);
		file >> pending;
	}

	bool get_isActive() override {
		return targRegion !is null;
	}

	void tick(AI& ai, FleetAI& fleet, double time) override {
		if(targRegion is null)
			return;
		if(move !is null)
			return;

		//Find stuff to fight
		if(eliminate is null)
			@eliminate = findEnemy(targRegion, null, ai.empire.hostileMask);

		if(eliminate !is null) {
			if(!eliminate.valid) {
				@eliminate = null;
			}
			else {
				if(!fleet.obj.hasOrders)
					fleet.obj.addAttackOrder(eliminate);
				if((fleet.filled < 0.3 || fleet.supplies < 0.3 || fleet.flagshipHealth < 0.5)
					&& eliminate.getFleetStrength() * 2.0 > fleet.strength
					&& !pending) {
					@targRegion = null;
					@eliminate = null;
					@move = cast<Fleets>(ai.fleets).returnToBase(fleet, MP_Critical);
				}
			}
		}
	}

	void update(AI& ai, Invasion& invasion) {
		//Manage movement
		if(move !is null) {
			if(move.failed || move.completed)
				@move = null;
		}

		//Find new regions to go to
		if(targRegion is null || (!pending && move is null && !invasion.isFighting(targRegion))) {
			bool ready = fleet.actionableState && move is null;

			DefendSystem@ bestDef;
			double bestWeight = 0.0;

			for(uint i = 0, cnt = invasion.defending.length; i < cnt; ++i) {
				auto@ def = invasion.defending[i];
				double w = randomd(0.9, 1.1);
				if(!def.fighting) {
					if(!ready)
						continue;
					else
						w *= 0.1;
				}

				if(!def.winning) {
					w *= 10.0;
				}
				else {
					if(!ready)
						continue;
				}

				if(def.obj is targRegion)
					w *= 1.5;

				if(w > bestWeight) {
					bestWeight = w;
					@bestDef = def;
				}
			}

			if(bestDef !is null && fleet.supplies >= 0.25 && fleet.filled >= 0.2 && fleet.fleetHealth >= 0.2) {
				@targRegion = bestDef.obj;
				invasion.pend(targRegion, fleet);
				pending = true;
			}
		}

		//Move to the region we want to go to
		if(targRegion !is null) {
			if(move is null) {
				if(fleet.obj.region !is targRegion) {
					@eliminate = findEnemy(targRegion, null, ai.empire.hostileMask);
					if(eliminate is null) {
						vec3d targPos = targRegion.position;
						targPos += (targRegion.position - ai.empire.HomeSystem.position).normalized(targRegion.radius * 0.85);

						@move = invasion.movement.move(fleet.obj, targPos, MP_Critical);
					}
					else {
						@move = invasion.movement.move(fleet.obj, eliminate, MP_Critical, nearOnly=true);
					}
				}
				else {
					//Remove from pending list
					if(pending) {
						invasion.unpend(targRegion, fleet);
						pending = false;
					}

					//See if we should return to base
					if(!invasion.isFighting(targRegion) && (fleet.supplies < 0.25 || fleet.filled < 0.5)) {
						@targRegion = null;
						@move = invasion.fleets.returnToBase(fleet, MP_Critical);
					}
				}
			}
		}
	}
};

class DefendSystem {
	Region@ obj;
	array<FleetAI@> pending;

	double enemyStrength = 0.0;
	double ourStrength = 0.0;
	double remnantStrength = 0.0;
	double pendingStrength = 0.0;

	void save(Invasion& invasion, SaveFile& file) {
		file << obj;

		uint cnt = pending.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			invasion.fleets.saveAI(file, pending[i]);

		file << enemyStrength;
		file << ourStrength;
		file << remnantStrength;
		file << pendingStrength;
	}

	void load(Invasion& invasion, SaveFile& file) {
		file >> obj;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ fleet = invasion.fleets.loadAI(file);
			if(fleet !is null && fleet.obj !is null)
				pending.insertLast(fleet);
		}

		file >> enemyStrength;
		file >> ourStrength;
		file >> remnantStrength;
		file >> pendingStrength;
	}

	void update(AI& ai, Invasion& invasion) {
		enemyStrength = getTotalFleetStrength(obj, ai.empire.hostileMask);

		ourStrength = getTotalFleetStrength(obj, ai.mask);
		remnantStrength = getTotalFleetStrength(obj, Pirates.mask);
		if(gameTime < 10.0 * 60.0)
			ourStrength += remnantStrength;
		else if(gameTime < 30.0 * 60.0)
			ourStrength += remnantStrength * 0.5;

		pendingStrength = 0.0;
		for(uint i = 0, cnt = pending.length; i < cnt; ++i)
			pendingStrength += sqrt(pending[i].strength);
		pendingStrength *= pendingStrength;

		if(obj.PlanetsMask & ai.empire.mask != 0)
			ai.empire.setDefending(obj, true);
	}

	bool get_fighting() {
		return enemyStrength > 0;
	}

	bool get_winning() {
		return ourStrength + pendingStrength > enemyStrength;
	}
};

class Invasion : AIComponent {
	Fleets@ fleets;
	Movement@ movement;

	array<DefendSystem@> defending;
	array<InvasionDefendMission@> tracked;

	void create() {
		@fleets = cast<Fleets>(ai.fleets);
		@movement = cast<Movement>(ai.movement);

		ai.behavior.maintenancePerShipSize = 0.0;
	}

	void save(SaveFile& file) {
		uint cnt = defending.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			defending[i].save(this, file);

		cnt = tracked.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets.saveMission(file, tracked[i]);
	}

	void load(SaveFile& file) {
		uint cnt = 0;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			DefendSystem def;
			def.load(this, file);
			defending.insertLast(def);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			InvasionDefendMission@ miss = cast<InvasionDefendMission>(fleets.loadMission(file));
			if(miss !is null)
				tracked.insertLast(miss);
		}
	}

	void start() {
		//Find systems to defend
		Region@ home = ai.empire.HomeSystem;
		const SystemDesc@ sys = getSystem(home);
		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			auto@ otherSys = getSystem(sys.adjacent[i]);
			if(findEnemy(otherSys.object, null, Pirates.mask, fleets=false, stations=true) !is null) {
				DefendSystem def;
				@def.obj = otherSys.object;
				defending.insertLast(def);
			}
		}
	}

	bool isManaging(FleetAI& fleet) {
		if(fleet.mission is null)
			return false;
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i) {
			if(tracked[i] is fleet.mission)
				return true;
		}
		return false;
	}

	void manage(FleetAI& fleet) {
		InvasionDefendMission miss;
		@miss.fleet = fleet;

		fleets.performMission(fleet, miss);
		tracked.insertLast(miss);
	}

	void pend(Region@ region, FleetAI& fleet) {
		for(uint i = 0, cnt = defending.length; i < cnt; ++i ){
			if(defending[i].obj is region) {
				defending[i].pending.insertLast(fleet);
				break;
			}
		}
	}

	void unpend(Region@ region, FleetAI& fleet) {
		for(uint i = 0, cnt = defending.length; i < cnt; ++i ){
			if(defending[i].obj is region) {
				defending[i].pending.remove(fleet);
				break;
			}
		}
	}

	DefendSystem@ getDefending(Region@ region) {
		for(uint i = 0, cnt = defending.length; i < cnt; ++i ){
			if(defending[i].obj is region)
				return defending[i];
		}
		return null;
	}

	bool isFighting(Region@ region) {
		for(uint i = 0, cnt = defending.length; i < cnt; ++i ){
			if(defending[i].obj is region)
				return defending[i].fighting;
		}
		return false;
	}

	uint sysUpd = 0;
	void focusTick(double time) {
		//All your fleets are belong to us
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			if(!isManaging(flAI))
				manage(flAI);
		}

		//Update systems we're defending
		if(defending.length != 0) {
			sysUpd = (sysUpd+1) % defending.length;
			defending[sysUpd].update(ai, this);
		}

		//Make sure our fleets are in the right places
		for(uint i = 0, cnt = tracked.length; i < cnt; ++i)
			tracked[i].update(ai, this);
	}
};

AIComponent@ createInvasion() {
	return Invasion();
}
