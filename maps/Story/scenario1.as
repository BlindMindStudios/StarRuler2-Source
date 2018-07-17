#priority init 1501
import maps;

#section game
import dialogue;
#section all

#section server
import object_creation;
import influence;
import tile_resources;
import scenario;
import systems;
import map_loader;
import campaign;
#include "include/resource_constants.as"
#section all

Scenario _map;
class Scenario : Map {
	Scenario() {
		super();

		isListed = false;
		isScenario = true;
	}
	
#section server
	PersistentGfx@ wormhole;
	vec3d wormholePos = vec3d(1400.0, 15.0, -750.0);
	double whLife = -1.0;
	double nextOpen = 180.0;
	bool periodicOpen = true;

	void prepareSystem(SystemData@ data, SystemDesc@ desc) {
		@data.homeworlds = null;
		Map::prepareSystem(data, desc);
	}

	bool canHaveHomeworld(SystemData@ data, Empire@ emp) {
		return false;
	}

	void placeSystems() {
		loadMap("maps/Story/scenario1.txt").generate(this);
	}

	void preGenerate() {
		Map::preGenerate();
		radius = 40000;
	}

	void modSettings(GameSettings& settings) {
		settings.empires.length = 2;
		settings.empires[0].name = locale::SCEN1_PLAYER_EMP;
		settings.empires[0].shipset = "Gevron";
		settings.empires[1].name = locale::SCEN1_ENEMY_EMP;
		settings.empires[1].shipset = "Volkur";
		settings.empires[1].type = ET_NoAI;
	}
	
	Planet@ planet(uint sys, uint ind) {
		return systemData[sys].planets[ind];
	}
	
	void populate(Planet@ pl, Empire@ owner, double pop = 1.0, Object@ exportTo = null, double defense = 0.0) {
		@pl.owner = owner;
		pl.addPopulation(pop);
		if(exportTo !is null)
			pl.exportResource(owner, 0, exportTo);
		if(defense > 0)
			pl.spawnDefenseShips(defense);
	}
	
	void init() {
		Empire@ enemy = getEmpire(1);
	
		playerEmpire.setHostile(enemy, true);
		enemy.setHostile(playerEmpire, true);
		playerEmpire.Victory = -2;
		
		wormholePos.normalize(planet(0,0).region.radius - 100.0);
		
		populate(planet(1,1), enemy, 7.0, defense=70.0);
		populate(planet(1,0), enemy, exportTo=planet(1,1), defense = 5.0);
		populate(planet(2,0), enemy, 3.0, planet(1,1), defense = 44.0);
		populate(planet(2,1), enemy, exportTo=planet(2,0), defense = 12.0);
		populate(planet(2,3), enemy, exportTo=planet(2,0), defense = 5.0);
		populate(planet(0,1), enemy, 3.0, planet(1,1), defense = 27.0);
		populate(planet(0,0), enemy, exportTo=planet(0,1), defense = 7.0);
		populate(planet(0,2), enemy, exportTo=planet(0,1), defense = 8.0);
		populate(planet(0,3), enemy, exportTo=planet(1,1), defense = 15.0);
		planet(0,1).colonize(planet(1,2));
		planet(1,2).exportResource(enemy, 0, planet(1,1));
		
		spawnFleet(enemy, planet(1,1).position + vec3d(50.0,0.0,0.0), "Defense Platform", 10);
		spawnFleet(enemy, planet(1,1).position + vec3d(40.0,0.0,0.0), "Defense Platform", 10);
		spawnFleet(enemy, planet(2,0).position + vec3d(40.0,0.0,0.0), "Defense Platform", 10);
		spawnFleet(enemy, planet(0,1).position + vec3d(50.0,0.0,0.0), "Defense Platform", 10);
		
		Dialogue("SCEN1_INTRO");
		Dialogue("SCEN1_INTRO2")
			.newObjective.checker(1, IntroCinematic(this));
		Dialogue("SCEN1_CONQUER")
			.checker(1, Conquer(this));
		Dialogue("SCEN1_COMPLETE")
			.onStart(EndCinematic(this));
	}
	
	Ship@ spawnFleet(Empire@ emp, const vec3d& pos, const string& base = "Titan", uint supBase = 25) {
		auto@ leaderDsg = emp.getDesign(base);
		auto@ sup3Dsg = emp.getDesign("Missile Boat");
		auto@ sup1Dsg = emp.getDesign("Beamship");
		auto@ sup2Dsg = emp.getDesign("Heavy Gunship");

		Ship@ leader = createShip(pos, leaderDsg, emp, free=true);
		for(uint i = 0; i < supBase / 2; ++i)
			createShip(pos, sup1Dsg, emp, leader);
		for(uint i = 0; i < supBase / 4; ++i)
			createShip(pos, sup2Dsg, emp, leader);
		for(uint i = 0; i < supBase / 8; ++i)
			createShip(pos, sup3Dsg, emp, leader);
		leader.setHoldPosition(true);
		return leader;
	}
	
	void openWormhole(double timeout = -1.0) {
		if(wormhole is null) {
			@wormhole = PersistentGfx();
			if(wormhole !is null)
				wormhole.establish(wormholePos, "Wormhole", 50.0, systemData[0].planets[0].region);
		}
		whLife = timeout;
		
		nextOpen = 180.0;
	}
	
	void closeWormhole() {
		if(wormhole !is null) {
			wormhole.stop();
			@wormhole = null;
		}
	}
	
	void lockWormhole() {
		periodicOpen = false;
	}

	void tick(double time) {
		if(wormhole !is null) {
			if(whLife > 0) {
				whLife -= time;
				if(whLife <= 0)
					closeWormhole();
			}
		}
		else if(periodicOpen) {
			nextOpen -= time;
			if(nextOpen < 0) {
				openWormhole(15.0);
				if(playerEmpire.TotalMilitary * playerEmpire.TotalMilitary / 1000 < 5000.0)
					spawnFleet(playerEmpire, wormholePos, "Dreadnaught", randomi(20,40))
						.addMoveOrder(wormholePos + random3d(80.0,150.0));
			}
		}
	}
#section all
};

#section server
class IntroCinematic : GuiObjectiveCheck {
	uint sent = 0;
	double nextSend;
	PersistentGfx@ wh;
	Scenario@ scen;

	IntroCinematic(Scenario@ _scen) {
		@scen = _scen;
	}
	
	bool start() {
		scen.openWormhole();
		nextSend = gameTime + 8.0;
		return true;
	}
	
	bool check() {
		if(sent == 2) {
			if(gameTime > nextSend) {
				scen.closeWormhole();
				return true;
			}
		}
		else if(gameTime > nextSend) {
			nextSend = gameTime + 16.0;
			if(sent == 0)
				scen.spawnFleet(playerEmpire, scen.wormholePos, "Scout", 0)
					.addMoveOrder(scen.wormholePos + vec3d(-50.0, 0.0, -100.0));
			else
				scen.spawnFleet(playerEmpire, scen.wormholePos, "Dreadnaught", 35)
					.addMoveOrder(scen.wormholePos + vec3d(100.0, 0.0, 50.0));
			++sent;
		}
		return false;
	}
};

class Conquer : GuiObjectiveCheck {
	Scenario@ scen;
	Conquer(Scenario@ _scen) {
		@scen = _scen;
	}
	
	bool check() {
		if(getEmpire(1).fleetCount > 0)
			return false;
		
		auto@ systemData = scen.systemData;
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			auto@ sys = systemData[i];
			for(uint j = 0, jcnt = sys.planets.length; j < jcnt; ++j) {
				auto@ pl = sys.planets[j];
				if(pl.owner.valid && pl.owner !is playerEmpire)
					return false;
			}
		}
		return true;
	}
};


class EndCinematic : DialogueAction {
	Scenario@ scen;
	EndCinematic(Scenario@ _scen) { @scen = _scen; }
	bool start() {
		scen.openWormhole();
		completeCampaignScenario("InevitableConquest");
		return true;
	}
};
#section all
