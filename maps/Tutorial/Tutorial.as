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
from influence import InfluenceStore;
from influence_global import influenceLock, cardStack, deck, nextStackId, StackInfluenceCard;
import systems;
import map_loader;
#section all

Tutorial _map;
class Tutorial : Map {
	Tutorial() {
		super();

		isListed = false;
		isScenario = true;
	}

#section server
	void prepareSystem(SystemData@ data, SystemDesc@ desc) {
		@data.homeworlds = null;
		Map::prepareSystem(data, desc);
	}

	bool canHaveHomeworld(SystemData@ data, Empire@ emp) {
		return false;
	}

	void preGenerate() {
		Map::preGenerate();
		radius = 40000;
	}

	void placeSystems() {
		loadMap("maps/Tutorial/map.txt").generate(this);
	}

	void modSettings(GameSettings& settings) {
		settings.empires.length = 2;
		settings.empires[0].name = locale::TUT_PLAYER_EMP;
		settings.empires[1].name = locale::TUT_ENEMY_EMP;
		settings.empires[1].shipset = "Gevron";
		settings.empires[1].type = ET_NoAI;
		config::ENABLE_UNIQUE_SPREADS = 0.0;
		config::DISABLE_STARTING_FLEETS = 1.0;
		config::ENABLE_DREAD_PIRATE = 0.0;
		config::ENABLE_INFLUENCE_EVENTS = 0.0;
		config::START_EXPLORED_MAP = 1.0;
	}

	void enemyPlanet(uint systemId, uint planetId) {
		auto@ sys = systemData[systemId];
		auto@ planet = sys.planets[planetId];

		planet.addPopulation(1.0);
		@planet.owner = enemyEmp;
	}

	Empire@ enemyEmp;
	const SystemDesc@ lihls;
	const SystemDesc@ yingmow;
	Planet@ spacewood;
	bool ownsSpacewood = false;

	void spawnPlayerFleet() {
		auto@ leaderDsg = playerEmpire.getDesign("Battleship");
		auto@ sup1Dsg = playerEmpire.getDesign("Beamship");
		auto@ sup2Dsg = playerEmpire.getDesign("Heavy Gunship");
		auto@ sup3Dsg = playerEmpire.getDesign("Missile Boat");

		vec3d pos = systemData[0].position + vec3d(200, 0, 900);

		Ship@ leader = createShip(pos, leaderDsg, playerEmpire, free=true);
		leader.name = locale::TUT_FLAGSHIP_NAME;
		leader.setHoldPosition(true);
		playerEmpire.registerFleet(leader);
		for(uint i = 0; i < 25; ++i)
			createShip(pos, sup1Dsg, playerEmpire, leader);
		for(uint i = 0; i < 25; ++i)
			createShip(pos, sup2Dsg, playerEmpire, leader);
		for(uint i = 0; i < 25; ++i)
			createShip(pos, sup3Dsg, playerEmpire, leader);
	}

	void spawnEnemyFleet(const vec3d& pos, const string& base = "Battleship", uint supBase = 25, bool aggro = false) {
		auto@ leaderDsg = enemyEmp.getDesign(base);
		auto@ sup1Dsg = enemyEmp.getDesign("Beamship");
		auto@ sup2Dsg = enemyEmp.getDesign("Heavy Gunship");
		auto@ sup3Dsg = enemyEmp.getDesign("Missile Boat");

		Ship@ leader = createShip(pos, leaderDsg, enemyEmp, free=true);
		if(!aggro)
			leader.setHoldPosition(true);
		for(uint i = 0; i < supBase; ++i)
			createShip(pos, sup1Dsg, enemyEmp, leader);
		for(uint i = 0; i < supBase; ++i)
			createShip(pos, sup2Dsg, enemyEmp, leader);
		for(uint i = 0; i < supBase; ++i)
			createShip(pos, sup3Dsg, enemyEmp, leader);
	}

	void init() {
		@enemyEmp = getEmpire(1);
		@lihls = systems[1];
		@yingmow = systems[3];
		@spacewood = systemData[1].planets[0];
		playerEmpire.setHostile(enemyEmp, true);
		playerEmpire.Victory = -3;
		enemyEmp.Victory = -3;
		enemyEmp.setHostile(playerEmpire, true);

		playerEmpire.ContactMask.value = int(~0);

		initDialogue();
	}

	void postInit() {
		@enemyEmp = getEmpire(1);
		@lihls = systems[1];
		@yingmow = systems[3];
		@spacewood = systemData[1].planets[0];

		//Player influence
		{
			playerEmpire.modInfluence(+50);

			auto@ type = getInfluenceCardType("AnnexSystem");
			InfluenceCard@ card = type.create();
			cast<InfluenceStore>(playerEmpire.InfluenceManager).addCard(playerEmpire, card);
		}

		//Player FTL
		playerEmpire.modFTLStored(+250);

		//Set up planets
		enemyPlanet(2, 3);
		enemyPlanet(3, 1);
		enemyPlanet(3, 2);
		enemyPlanet(3, 3);
		systemData[3].planets[1].exportResource(0, systemData[3].planets[3]);
		systemData[3].planets[2].exportResource(0, systemData[3].planets[3]);

		//Set up initial fleets
		spawnPlayerFleet();
		Orbital@ orb = createOrbital(systemData[0].position + vec3d(600, 0, 200), getOrbitalModule("GateCore"), enemyEmp);
		orb.modMaxHealth(-5500);
		orb.modMaxArmor(-2500);
		spawnEnemyFleet(systemData[0].position + vec3d(700, 0, 250), "Dreadnaught", 5);
		spawnEnemyFleet(systemData[0].position + vec3d(500, 0, 150), "Dreadnaught", 5);

		//Defenses for phasite
		{
			auto@ enemySup = enemyEmp.getDesign("Beamship");
			vec3d pos = systemData[2].planets[3].position;
			for(uint i = 0; i < 20; ++i)
				createShip(pos, enemySup, enemyEmp, systemData[2].planets[3]);
		}

		guiDialogueAction(CURRENT_PLAYER, "Tutorial.Tutorial::ZoomFleet");
	}

	void initDialogue() {
		//Prepare dialogue
		Dialogue("TUT_INTRO")
			.onPass(GUIAction("Tutorial.Tutorial::HideGUI"));
		Dialogue("TUT_INTRO2");
		Dialogue("TUT_INTRO3");
		Dialogue("TUT_CAM")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckPan"))
			.checker(2, GUIChecker("Tutorial.Tutorial::CheckZoom"))
			.checker(3, GUIChecker("Tutorial.Tutorial::CheckRotate"));
		Dialogue("TUT_TIME")
			.onPass(GUIAction("Tutorial.Tutorial::ShowTime"));
		Dialogue("TUT_SCAN")
			.checker(1, CheckFleetSelect())
			.checker(2, CheckFleetAttack())
			.checker(3, CheckDestroyGate());
		Dialogue("TUT_FTL");
		Dialogue("TUT_FTL2")
			.objectiveKeybind(1, KB_FTL)
			.checker(1, CheckSystemArrive())
			.onPass(GUIAction("Tutorial.Tutorial::ShowFTL"))
			.onComplete(GainSpacewood(this));
		Dialogue("TUT_ARRIVE");
		Dialogue("TUT_RES");
		Dialogue("TUT_LEVEL");
		Dialogue("TUT_LEVEL2");
		Dialogue("TUT_EXPAND")
			.checker(1, CheckColonizeFood())
			.checker(2, CheckExportFood())
			.checker(3, CheckColonizeTier1())
			.checker(4, CheckExportTier1());
		Dialogue("TUT_LEVELREQS");
		Dialogue("TUT_IMPORT1")
			.checker(1, CheckLevel1());
		Dialogue("TUT_IMPORT2")
			.checker(1, CheckLevel2());
		Dialogue("TUT_EXPAND_SUCC")
			.onPass(GUIAction("Tutorial.Tutorial::ShowPlanets"));
		Dialogue("TUT_BUDGET")
			.onPass(GUIAction("Tutorial.Tutorial::ShowMoney"));
		Dialogue("TUT_BUDGET2");
		Dialogue("TUT_BUILD")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckPlanetOverlay", spacewood))
			.checker(2, CheckBuildScout()) ;
		Dialogue("TUT_BUILD2")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckNoOverlay"))
			.checker(2, GUIChecker("Tutorial.Tutorial::CheckFleetOverlay"))
			.checker(3, CheckReinforceFleet())
			.checker(4, CheckScoutFinished());
		Dialogue("TUT_SCOUT")
			.checker(1, CheckScouted());
		Dialogue("TUT_CONQ")
			.checker(1, CheckFleetMoved())
			.checker(2, CheckDefenseKilled())
			.checker(3, CheckCaptured());
		Dialogue("TUT_CAPT")
			.checker(1, CheckPhasiteImport())
			.onPass(GUIAction("Tutorial.Tutorial::ShowQuickbars"));
		Dialogue("TUT_PRES");
		Dialogue("TUT_BLD")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckPlanetOverlay", spacewood))
			.checker(2, GUIChecker("Tutorial.Tutorial::CheckBuildingsList"))
			.checker(3, CheckResearchComplex())
			.onComplete(GainResearchRate());
		Dialogue("TUT_RSC")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckResearchTab"))
			.checker(2, CheckResearchArmoring())
			.checker(3, CheckResearchBulkhead())
			.onPass(GUIAction("Tutorial.Tutorial::ShowResearch"));
		Dialogue("TUT_DSG")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckDesignEdit"))
			.onPass(GUIAction("Tutorial.Tutorial::ShowDesigns"));
		Dialogue("TUT_DSG2");
		Dialogue("TUT_DSG3")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckDesignArmor"));
		Dialogue("TUT_DSG4")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckDesignBulkhead"))
			.checker(2, GUIChecker("Tutorial.Tutorial::CheckDesignSaved"));
		Dialogue("TUT_FLT")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckPlanetOverlay", spacewood))
			.checker(2, CheckBuildCarrier())
			.checker(3, CheckAddBeamships())
			.checker(4, CheckAddSupports())
			.checker(5, CheckFinishCarrier())
			.onComplete(GainEnergy());
		Dialogue("TUT_ENG")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckArtifactTarget"))
			.checker(2, CheckArtifactEquip())
			.onPass(GUIAction("Tutorial.Tutorial::ShowEnergy"));
		Dialogue("TUT_INF")
			.onPass(GUIAction("Tutorial.Tutorial::ShowInfluence"));
		Dialogue("TUT_INF2")
			.onPass(GUIAction("Tutorial.Tutorial::ShowInfluenceTab"));
		Dialogue("TUT_INF3")
			.checker(1, CheckBuySpy())
			.checker(2, CheckActivateSpy())
			.onComplete(ShowSpySystem());
		Dialogue("TUT_INF4");
		Dialogue("TUT_SPY")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckViewSpy"));
		Dialogue("TUT_ANNEX")
			.checker(1, CheckStartVote());
		Dialogue("TUT_VOTE");
		Dialogue("TUT_VOTE2")
			.onComplete(EnemyPlayRhetoric());
		Dialogue("TUT_VOTE3")
			.checker(1, CheckPlayNegotiate())
			.checker(2, CheckWinVote());
		Dialogue("TUT_ANNEX2");
		Dialogue("TUT_DEFCORE")
			.checker(1, GUIChecker("Tutorial.Tutorial::CheckPlanetOverlay", spacewood))
			.checker(2, GUIChecker("Tutorial.Tutorial::CheckOrbitalsList"))
			.checker(3, GUIChecker("Tutorial.Tutorial::CheckTargetDefPlat"))
			.checker(4, CheckOrbitalPlaced())
			.onComplete(GainDefenseGen(this));
		Dialogue("TUT_DEFPROJ")
			.onPass(GUIAction("Tutorial.Tutorial::ShowDefense"))
			.checker(1, CheckDefenseProject())
			.checker(2, CheckMoveFleet());
		Dialogue("TUT_DEF")
			.onPass(GUIAction("Tutorial.Tutorial::ShowTabStuff"))
			.proceedWith(locale::ENTER_COMBAT)
			.onComplete(SpawnAttackFleets(this));
		Dialogue("TUT_DEF2")
			.checker(1, CheckDefeatEnemies());
		Dialogue("TUT_FINAL")
			.proceedWith(locale::CLOSE)
			.onPass(GUIAction("Tutorial.Tutorial::ShowWiki"));
	}

	bool initialized = false;
	void tick(double time) {
		if(!initialized && !isLoadedSave) {
			initialized = true;
			postInit();
		}

		//Make sure there's always a spy in the stack
		{
			Lock lck(influenceLock);
			auto@ spyType = getInfluenceCardType("Spy");
			bool found = false;
			for(uint i = 1, cnt = cardStack.length; i < cnt; ++i) {
				if(cardStack[i].type is spyType) {
					found = true;
					break;
				}
			}

			if(!found && (deck.length == 0 || deck.last.type !is spyType)) {
				StackInfluenceCard card;
				card.id = nextStackId++;
				spyType.generate(card);
				@card.targets.fill("target").emp = enemyEmp;

				deck.insertLast(card);
			}
		}
	}

	void save(SaveFile& file) {
		file << enemyEmp;
		file << spacewood;
		file << ownsSpacewood;
		saveDialoguePosition(file);
	}

	void load(SaveFile& file) {
		file >> enemyEmp;
		file >> spacewood;
		file >> ownsSpacewood;
		@enemyEmp = getEmpire(1);
		@lihls = getSystem(1);
		@yingmow = getSystem(3);

		initDialogue();
		loadDialoguePosition(file);
	}
#section all
};

#section server
from orders import OrderType;
import planets.PlanetSurface;
import research;
import constructible;
import statuses;
import influence;
import influence_global;

class GainSpacewood : DialogueAction {
	Tutorial@ tut;
	GainSpacewood(Tutorial@ tut) { @this.tut = tut; }
	void call() {
		@tut.spacewood.owner = playerEmpire;
		tut.spacewood.addPopulation(3.0);
		tut.ownsSpacewood = true;
		@playerEmpire.Homeworld = tut.spacewood;
	}
}

class GainDefenseGen : DialogueAction {
	Tutorial@ tut;
	GainDefenseGen(Tutorial@ tut) { @this.tut = tut; }
	void call() {
		tut.spacewood.modResource(TR_Defense, +10);
	}
}

class SpawnAttackFleets : DialogueAction {
	Tutorial@ tut;
	SpawnAttackFleets(Tutorial@ tut) { @this.tut = tut; }
	void call() {
		for(uint i = 0; i < 3; ++i) {
			vec3d pos = tut.yingmow.position;
			vec2d offset = random2d(tut.yingmow.radius - 150.0);
			pos.x += offset.x;
			pos.z += offset.y;

			tut.spawnEnemyFleet(pos, "Dreadnaught", 5, aggro=true);
		}
	}
};

class GainResearchRate : DialogueAction {
	void call() {
		playerEmpire.generatePoints(900);
		playerEmpire.modResearchRate(+2.0);
	}
};

class GainEnergy : DialogueAction {
	void call() {
		playerEmpire.modEnergyStored(+500);
	}
};

class ShowSpySystem : DialogueAction {
	void call() {
		getSystem(3).object.grantVision(playerEmpire);
	}
};

class EnemyPlayRhetoric : DialogueAction {
	void call() {
		Empire@ enemy = getEmpire(1);
		auto@ votes = getActiveInfluenceVotes();
		InfluenceVoteStub@ stub;
		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {
			if(votes[i].type.ident == "AnnexSystem")
				@stub = votes[i];
		}
		if(stub is null)
			return;
		Lock lock(influenceLock);
		auto@ type = getInfluenceCardType("Rhetoric");
		InfluenceCard@ card = type.create();
		int id = cast<InfluenceStore>(enemy.InfluenceManager).addCard(enemy, card);
		Targets targets = card.targets;
		targets.fill("VoteSide").side = false;
		enemy.modInfluence(+100);
		playInfluenceCard_server(enemy, id, targets, stub.id);
	}
};

class CheckFleetSelect : ObjectiveCheck {
	bool check() {
		return playerEmpire.fleets[0].selected;
	}
};

class CheckFleetAttack : ObjectiveCheck {
	bool check() {
		//Either the player issued the attack order, or has already destroyed everything in the system
		return playerEmpire.fleets[0].hasOrder(OT_Attack) || (getSystem(0).object.BasicVisionMask & getEmpire(1).mask == 0);
	}
};

class CheckDestroyGate : ObjectiveCheck {
	bool check() {
		return !getEmpire(1).hasStargates() || getSystem(0).object.BasicVisionMask & getEmpire(1).mask == 0;
	}
};

class CheckSystemArrive : ObjectiveCheck {
	bool check() {
		return getSystem(1).object.BasicVisionMask & playerEmpire.mask != 0;
	}
};

class CheckColonizeNeeds : ObjectiveCheck {
	bool check() {
		bool hasLevel1 = false, hasFood = false;
	
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.BasicVisionMask & playerEmpire.mask == 0)
				continue;
			for(uint j = 0, jcnt = reg.planetCount; j < jcnt; ++j) {
				auto@ pl = reg.planets[j];
				if(pl.owner is playerEmpire && pl.population >= 1.0) {
					auto@ r = getResource(pl.primaryResourceType);
					if(r.level == 1)
						hasLevel1 = true;
					else if(r.cls !is null && r.cls is getResourceClass("Food"))
						hasFood = true;
				}
			}
			
			if(hasLevel1 && hasFood)
				return true;
		}
	
		return false;
	}
};

class CheckColonizeFood : ObjectiveCheck {
	bool check() {
		bool hasFood = false;
	
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.BasicVisionMask & playerEmpire.mask == 0)
				continue;
			for(uint j = 0, jcnt = reg.planetCount; j < jcnt; ++j) {
				auto@ pl = reg.planets[j];
				if(pl is playerEmpire.Homeworld)
					continue;
				if(pl.owner is playerEmpire && pl.population >= 1.0) {
					auto@ r = getResource(pl.primaryResourceType);
					if(r.cls !is null && r.cls is getResourceClass("Food"))
						return true;
				}
			}
		}
		return false;
	}
};

class CheckColonizeTier1 : ObjectiveCheck {
	bool check() {
		bool hasFood = false;
	
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.BasicVisionMask & playerEmpire.mask == 0)
				continue;
			for(uint j = 0, jcnt = reg.planetCount; j < jcnt; ++j) {
				auto@ pl = reg.planets[j];
				if(pl.owner is playerEmpire && pl.population >= 1.0) {
					auto@ r = getResource(pl.primaryResourceType);
					if(r.level == 1)
						return true;
				}
			}
		}
		return false;
	}
};

class CheckExportFood : ObjectiveCheck {
	bool check() {
		bool hasFood = false;
	
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.BasicVisionMask & playerEmpire.mask == 0)
				continue;
			for(uint j = 0, jcnt = reg.planetCount; j < jcnt; ++j) {
				auto@ pl = reg.planets[j];
				if(pl is playerEmpire.Homeworld)
					continue;
				if(pl.owner is playerEmpire && pl.population >= 1.0) {
					auto@ r = getResource(pl.primaryResourceType);
					if(r.cls !is null && r.cls is getResourceClass("Food")) {
						if(pl.nativeResourceDestination[0] is playerEmpire.Homeworld)
							return true;
					}
				}
			}
		}
		return false;
	}
};

class CheckExportTier1 : ObjectiveCheck {
	bool check() {
		bool hasFood = false;
	
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.BasicVisionMask & playerEmpire.mask == 0)
				continue;
			for(uint j = 0, jcnt = reg.planetCount; j < jcnt; ++j) {
				auto@ pl = reg.planets[j];
				if(pl.owner is playerEmpire && pl.population >= 1.0) {
					auto@ r = getResource(pl.primaryResourceType);
					if(r.level == 1) {
						if(pl.nativeResourceDestination[0] is playerEmpire.Homeworld)
							return true;
					}
				}
			}
		}
		return false;
	}
};

class CheckLevel1 : ObjectiveCheck {
	bool check() {
		Region@ reg = getSystem(1).object;
		Planet@ pl = reg.planets[1];
		if(pl.owner is playerEmpire && pl.resourceLevel == 1)
			return true;
		@reg = getSystem(3).object;
		@pl = reg.planets[3];
		if(pl.owner is playerEmpire && pl.resourceLevel == 1)
			return true;
		return false;
	}
};

class CheckLevel2 : ObjectiveCheck {
	bool check() {
		Region@ reg = getSystem(1).object;
		Planet@ pl = reg.planets[0];
		if(pl.owner is playerEmpire && pl.resourceLevel == 2)
			return true;
		return false;
	}
};

class CheckBuildScout : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;
		if(hw.constructionCount != 0 && hw.constructionName[0] == "Scout")
			return true;
		return false;
	}
};

class CheckReinforceFleet : ObjectiveCheck {
	bool check() {
		return playerEmpire.fleets[0].hasOrderedSupports;
	}
};

class CheckScoutFinished : ObjectiveCheck {
	bool check() {
		for(uint i = 0, cnt = playerEmpire.fleetCount; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(playerEmpire.fleets[i]);
			if(ship !is null && ship.blueprint.design.name == "Scout")
				return true;
		}
		return false;
	}
};

class CheckScouted : ObjectiveCheck {
	bool check() {
		return getSystem(2).object.BasicVisionMask & playerEmpire.mask != 0;
	}
};

class CheckFleetMoved : ObjectiveCheck {
	bool check() {
		return playerEmpire.fleets[0].region is getSystem(2).object;
	}
};

class CheckDefenseKilled : ObjectiveCheck {
	bool check() {
		auto@ pl = getSystem(2).object.planets[3];
		return pl.supportCount == 0 || pl.owner is playerEmpire;
	}
};

class CheckCaptured : ObjectiveCheck {
	bool check() {
		return getSystem(2).object.planets[3].owner is playerEmpire;
	}
};

class CheckPhasiteImport : ObjectiveCheck {
	bool check() {
		return getSystem(2).object.planets[3].nativeResourceDestination[0] is playerEmpire.Homeworld;
	}
};

class CheckResearchComplex : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;

		PlanetSurface surface;
		receive(hw.getPlanetSurface(), surface);
		for(uint i = 0, cnt = surface.buildings.length; i < cnt; ++i) {
			if(surface.buildings[i].type.ident == "ResearchComplex")
				return true;
		}
		return false;
	}
};

class CheckResearchArmoring : ObjectiveCheck {
	TechnologyNode node;
	bool check() {
		receive(playerEmpire.getTechnologyNode(vec2i(-1,1)), node);
		return node.unlocked;
	}
};

class CheckResearchBulkhead : ObjectiveCheck {
	TechnologyNode node;
	bool check() {
		receive(playerEmpire.getTechnologyNode(vec2i(0,2)), node);
		return node.unlocked;
	}
};

class CheckBuildCarrier : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;
		if(hw.constructionCount != 0 && hw.constructionName[0] == "Heavy Carrier")
			return true;
		return false;
	}
};

class CheckAddBeamships : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;
		if(hw.constructionCount == 0 || hw.constructionName[0] != "Heavy Carrier")
			return true;
		Constructible cons;
		receive(hw.getConstructionQueue(1), cons);
		for(uint i = 0, cnt = cons.groups.length; i < cnt; ++i) {
			if(cons.groups[i].dsg.name == "Beamship")
				return true;
		}
		return false;
	}
};

class CheckAddSupports : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;
		if(hw.constructionCount == 0 || hw.constructionName[0] != "Heavy Carrier")
			return true;
		Constructible cons;
		receive(hw.getConstructionQueue(1), cons);
		for(uint i = 0, cnt = cons.groups.length; i < cnt; ++i) {
			if(cons.groups[i].dsg.name != "Beamship")
				return true;
		}
		return false;
	}
};

class CheckFinishCarrier : ObjectiveCheck {
	bool check() {
		for(uint i = 1, cnt = playerEmpire.fleetCount; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(playerEmpire.fleets[i]);
			if(ship !is null && ship.blueprint.design.name == "Heavy Carrier")
				return true;
		}
		return false;
	}
};

class CheckArtifactEquip : ObjectiveCheck {
	bool check() {
		auto@ status = getStatusType("PowerCell");
		for(uint i = 0, cnt = playerEmpire.fleetCount; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(playerEmpire.fleets[i]);
			if(ship is null)
				continue;
			if(ship.hasStatuses && ship.hasStatusEffect(status.id))
				return true;
		}
		return false;
	}
};

class CheckBuySpy : ObjectiveCheck {
	bool check() {
		array<InfluenceCard> cards;
		cards.syncFrom(playerEmpire.getInfluenceCards());
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].type.ident == "Spy")
				return true;
		}
		return false;
	}
};

class CheckActivateSpy : ObjectiveCheck {
	bool check() {
		auto@ effects = getActiveInfluenceEffects();
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			if(effects[i].type.ident == "Spy")
				return true;
		}
		return false;
	}
};

class CheckStartVote : ObjectiveCheck {
	bool check() {
		if(getEmpire(1).TotalPlanets.value == 0)
			return true;
		
		auto@ votes = getActiveInfluenceVotes();
		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {
			if(votes[i].type.ident == "AnnexSystem")
				return true;
		}
		return false;
	}
};

class CheckPlayNegotiate : ObjectiveCheck {
	bool check() {
		auto@ votes = getActiveInfluenceVotes();
		InfluenceVoteStub@ stub;
		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {
			if(votes[i].type.ident == "AnnexSystem")
				@stub = votes[i];
		}
		if(stub is null)
			return true;
		Lock lock(influenceLock);
		auto@ vote = getInfluenceVoteByID(stub.id);
		if(vote.currentTime < -120.0)
			vote.currentTime = -120.0;
		for(uint i = 0, cnt = vote.events.length; i < cnt; ++i) {
			auto@ evt = vote.events[i];
			if(evt.cardEvent !is null && evt.cardEvent.card.type.ident == "Negotiate")
				return true;
		}
		return false;
	}
};

class CheckWinVote : ObjectiveCheck {
	double startTime = 0.0;

	bool start() {
		startTime = gameTime;
		return true;
	}

	bool check() {
		auto@ votes = getActiveInfluenceVotes();
		InfluenceVoteStub@ stub;
		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {
			if(votes[i].type.ident == "AnnexSystem")
				@stub = votes[i];
		}
		if(stub is null)
			return true;
		Lock lock(influenceLock);
		auto@ vote = getInfluenceVoteByID(stub.id);
		if(vote.currentTime < -120.0)
			vote.currentTime = -120.0;
		if(gameTime > startTime + 30.0) {
			startTime = INFINITY;
			Empire@ enemy = getEmpire(1);
			auto@ type = getInfluenceCardType("Negotiate");
			InfluenceCard@ card = type.create();
			int id = cast<InfluenceStore>(enemy.InfluenceManager).addCard(enemy, card);
			Targets targets = card.targets;
			targets.fill("VoteSide").side = false;
			playInfluenceCard_server(enemy, id, targets, stub.id);
		}
		return false;
	}
};

class CheckOrbitalPlaced : ObjectiveCheck {
	bool check() {
		Planet@ hw = playerEmpire.Homeworld;
		if(hw.constructionCount != 0 && hw.constructionName[0] == "Defense Platform")
			return true;
		return false;
	}
};

class CheckDefenseProject : ObjectiveCheck {
	bool check() {
		return playerEmpire.isDefending(getSystem(3).object);
	}
};

class CheckMoveFleet : ObjectiveCheck {
	bool check() {
		bool moved = false, created = false;
		for(uint i = 1, cnt = playerEmpire.fleetCount; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(playerEmpire.fleets[i]);
			if(ship is null)
				continue;
			if(ship.blueprint.design.name == "Defense Platform") {
				created = true;
			}
			else if(ship.region is getSystem(3).object)
				moved = true;
		}
		return moved && created;
	}
};

class CheckDefeatEnemies : ObjectiveCheck {
	double startTime = 0.0;

	bool start() {
		startTime = gameTime;
		return true;
	}

	bool check() {
		if(gameTime < startTime + 5.0)
			return false;
		return getEmpire(1).fleetCount == 0;
	}
};

#section gui
from tabs.tabbar import tabBar, globalBar, closeTab, tabs, newTab, ActiveTab;
from tabs.GlobalBar import GlobalBar;
from tabs.GalaxyTab import GalaxyTab;
from tabs.PlanetsTab import createPlanetsTab;
from tabs.ResearchTab import createResearchTab, ResearchTab;
from tabs.DiplomacyTab import createDiplomacyTab;
from community.Home import createCommunityHome;
from tabs.DesignOverviewTab import createDesignOverviewTab;
from tabs.DesignEditorTab import DesignEditor;
from navigation.SmartCamera  import CAM_PANNED, CAM_ZOOMED, CAM_ROTATED;
from overlays.PlanetInfoBar import PlanetInfoBar;
from overlays.Supports import SupportOverlay;
from overlays.Construction import OrbitalTarget;
from targeting.targeting import mode;
from targeting.ObjectTarget import AbilityTargetObject, ObjectMode;
from targeting.PointTarget import PointTargetMode;
from overlays.TimeDisplay import ShowTimeDisplay;

class HideGUI : DialogueAction {
	void call() {
		//Global bar
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.budget.visible = false;
		gbar.energy.visible = false;
		gbar.defense.visible = false;
		gbar.ftl.visible = false;
		gbar.influence.visible = false;
		gbar.research.visible = false;

		//Tab bar
		tabBar.goButton.visible = false;
		tabBar.newButton.visible = false;
		tabBar.homeButton.visible = false;

		for(uint i = 1, cnt = tabs.length; i < cnt; ++i)
			closeTab(tabs[1]);
		tabs[0].locked = true;

		//Quickbar
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.quickbar.visible = false;

		//Hide the timer
		ShowTimeDisplay = false;
	}
};

class ZoomFleet : DialogueAction {
	void call() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.zoomTo(playerEmpire.fleets[0]);
	}
};

class ShowTime : DialogueAction {
	void call() {
		ShowTimeDisplay = true;
	}
};

class ShowFTL : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.ftl.visible = true;
	}
};

class ShowPlanets : DialogueAction {
	void call() {
		//Show planets tab
		newTab(createPlanetsTab());
		tabs[1].locked = true;
	}
};

class ShowMoney : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.budget.visible = true;
	}
};

class ShowQuickbars : DialogueAction {
	void call() {
		//Show planets quickbars
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.quickbar.visible = true;
		gtab.quickbar.modes[0].closed = true;
		gtab.quickbar.modes[11].closed = true;
		gtab.quickbar.quickButton.visible = false;
	}
};

class ShowResearch : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.research.visible = true;

		newTab(createResearchTab());
		tabs[2].locked = true;
	}
};

class ShowDesigns : DialogueAction {
	void call() {
		newTab(createDesignOverviewTab());
		tabs[3].locked = true;
	}
};

class ShowEnergy : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.energy.visible = true;

		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.quickbar.modes[11].closed = false;
	}
};

class ShowDefense : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.defense.visible = true;
	}
};

class ShowInfluence : DialogueAction {
	void call() {
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.influence.visible = true;
	}
};

class ShowInfluenceTab : DialogueAction {
	void call() {
		newTab(createDiplomacyTab());
		tabs[4].locked = true;
	}
};

class ShowTabStuff : DialogueAction {
	void call() {
		tabBar.goButton.visible = true;
		tabBar.newButton.visible = true;
		tabBar.homeButton.visible = true;
		for(uint i = 0; i < 5; ++i)
			tabs[i].locked = false;

		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.quickbar.modes[0].closed = false;
		gtab.quickbar.quickButton.visible = true;
	}
};

class ShowWiki : DialogueAction {
	void call() {
		newTab(createCommunityHome());
	}
};

class CheckPan : GuiObjectiveCheck {
	bool start() {
		CAM_PANNED = false;
		return true;
	}

	bool check() {
		return CAM_PANNED;
	}
};

class CheckZoom : GuiObjectiveCheck {
	bool start() {
		CAM_ZOOMED = false;
		return true;
	}

	bool check() {
		return CAM_ZOOMED;
	}
};

class CheckRotate : GuiObjectiveCheck {
	bool start() {
		CAM_ROTATED = false;
		return true;
	}

	bool check() {
		return CAM_ROTATED;
	}
};

class CheckPlanetOverlay : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		if(gtab !is ActiveTab)
			return false;
		auto@ ibar = cast<PlanetInfoBar>(gtab.infoBar);
		if(ibar is null)
			return false;
		if(ibar.overlay is null || !ibar.overlay.visible)
			return false;
		return ibar.overlay.obj is obj;
	}
};

class CheckBuildingsList : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		if(gtab !is ActiveTab)
			return false;
		auto@ ibar = cast<PlanetInfoBar>(gtab.infoBar);
		if(ibar is null)
			return false;
		if(ibar.overlay is null || !ibar.overlay.visible)
			return false;
		return ibar.overlay.construction.buildingsList.visible;
	}
};

class CheckOrbitalsList : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		if(gtab !is ActiveTab)
			return false;
		auto@ ibar = cast<PlanetInfoBar>(gtab.infoBar);
		if(ibar is null)
			return false;
		if(ibar.overlay is null || !ibar.overlay.visible)
			return false;
		return ibar.overlay.construction.orbitalsList.visible;
	}
};

class CheckNoOverlay : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		if(gtab !is ActiveTab)
			return false;
		return gtab.infoBar is null || !gtab.infoBar.showingManage;
	}
};

class CheckFleetOverlay : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		if(gtab !is ActiveTab)
			return false;
		auto@ overlay = cast<SupportOverlay>(gtab.overlay);
		if(overlay is null || !overlay.visible)
			return false;
		return true;
	}
};

class CheckResearchTab : GuiObjectiveCheck {
	bool check() {
		return cast<ResearchTab>(ActiveTab) !is null;
	}
};

class CheckDesignEdit : GuiObjectiveCheck {
	bool check() {
		auto@ tab = cast<DesignEditor>(ActiveTab);
		if(tab is null)
			return false;
		if(tab.originalDesign is null)
			return false;
		return tab.originalDesign.name == "Heavy Carrier";
	}
};

class CheckDesignArmor : GuiObjectiveCheck {
	uint armor = 0;

	bool start() {
		armor = 0;
		auto@ dsg = playerEmpire.getDesign("Heavy Carrier");
		for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
			auto@ sys = dsg.subsystems[i];
			if(sys.type is subsystem::PlateArmor)
				armor += sys.hexCount;
		}
		return true;
	}

	bool check() {
		auto@ tab = cast<DesignEditor>(ActiveTab);
		if(tab is null)
			return false;
		if(tab.originalDesign is null)
			return false;
		if(tab.originalDesign.name != "Heavy Carrier")
			return false;

		uint curArmor = 0;
		auto@ dsg = tab.design;
		for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
			auto@ sys = dsg.subsystems[i];
			if(sys.type is subsystem::PlateArmor)
				curArmor += sys.hexCount;
		}

		return curArmor >= armor+3;
	}
};

class CheckDesignBulkhead : GuiObjectiveCheck {
	bool check() {
		auto@ tab = cast<DesignEditor>(ActiveTab);
		if(tab is null)
			return false;
		if(tab.originalDesign is null)
			return false;
		if(tab.originalDesign.name != "Heavy Carrier")
			return false;

		auto@ dsg = tab.design;
		for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
			auto@ sys = dsg.subsystems[i];
			for(uint n = 0, ncnt = sys.hexCount; n < ncnt; ++n) {
				if(sys.module(n).id == "Bulkhead")
					return true;
			}
		}
		return false;
	}
};

class CheckDesignSaved : GuiObjectiveCheck {
	bool check() {
		return playerEmpire.getDesign("Heavy Carrier").revision > 1;
	}
};

class CheckArtifactTarget : GuiObjectiveCheck {
	bool check() {
		auto@ tg = cast<ObjectMode>(mode);
		if(tg is null)
			return false;
		auto@ to = cast<AbilityTargetObject>(tg.targ);
		if(to is null)
			return false;
		if(!to.abl.obj.isArtifact)
			return false;
		return true;
	}
};

class CheckTargetDefPlat : GuiObjectiveCheck {
	bool check() {
		auto@ tg = cast<PointTargetMode>(mode);
		if(tg is null)
			return false;
		auto@ to = cast<OrbitalTarget>(tg.targ);
		if(to is null)
			return false;
		if(to.dsg is null)
			return false;
		return to.dsg.name == "Defense Platform";
	}
};

class CheckViewSpy : GuiObjectiveCheck {
	bool check() {
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		return gtab.title == "Yingmow";
	}
};

#section all
