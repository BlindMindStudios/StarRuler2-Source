import settings.game_settings;
from empire_ai.EmpireAI import AIController;

import AIComponent@ createColonization() from "empire_ai.weasel.Colonization";
import AIComponent@ createResources() from "empire_ai.weasel.Resources";
import AIComponent@ createPlanets() from "empire_ai.weasel.Planets";
import AIComponent@ createSystems() from "empire_ai.weasel.Systems";
import AIComponent@ createFleets() from "empire_ai.weasel.Fleets";
import AIComponent@ createScouting() from "empire_ai.weasel.Scouting";
import AIComponent@ createDevelopment() from "empire_ai.weasel.Development";
import AIComponent@ createDesigns() from "empire_ai.weasel.Designs";
import AIComponent@ createBudget() from "empire_ai.weasel.Budget";
import AIComponent@ createConstruction() from "empire_ai.weasel.Construction";
import AIComponent@ createMilitary() from "empire_ai.weasel.Military";
import AIComponent@ createMovement() from "empire_ai.weasel.Movement";
import AIComponent@ createCreeping() from "empire_ai.weasel.Creeping";
import AIComponent@ createRelations() from "empire_ai.weasel.Relations";
import AIComponent@ createIntelligence() from "empire_ai.weasel.Intelligence";
import AIComponent@ createWar() from "empire_ai.weasel.War";
import AIComponent@ createResearch() from "empire_ai.weasel.Research";
import AIComponent@ createEnergy() from "empire_ai.weasel.Energy";
import IAIComponent@ createDiplomacy() from "empire_ai.weasel.Diplomacy";
import AIComponent@ createConsider() from "empire_ai.weasel.Consider";
import AIComponent@ createOrbitals() from "empire_ai.weasel.Orbitals";

import AIComponent@ createHyperdrive() from "empire_ai.weasel.ftl.Hyperdrive";
import AIComponent@ createGate() from "empire_ai.weasel.ftl.Gate";
import AIComponent@ createFling() from "empire_ai.weasel.ftl.Fling";
import AIComponent@ createSlipstream() from "empire_ai.weasel.ftl.Slipstream";
import AIComponent@ createJumpdrive() from "empire_ai.weasel.ftl.Jumpdrive";

import AIComponent@ createVerdant() from "empire_ai.weasel.race.Verdant";
import AIComponent@ createMechanoid() from "empire_ai.weasel.race.Mechanoid";
import AIComponent@ createStarChildren() from "empire_ai.weasel.race.StarChildren";
import AIComponent@ createExtragalactic() from "empire_ai.weasel.race.Extragalactic";
import AIComponent@ createLinked() from "empire_ai.weasel.race.Linked";
import AIComponent@ createDevout() from "empire_ai.weasel.race.Devout";
import AIComponent@ createAncient() from "empire_ai.weasel.race.Ancient";

import AIComponent@ createInvasion() from "empire_ai.weasel.misc.Invasion";
import bool hasInvasionMap() from "Invasion.InvasionMap";

from buildings import BuildingType;
from orbitals import OrbitalModule;
import util.formatting;

from empire import ai_full_speed;

from traits import getTraitID;

export IAIComponent, AIComponent, AI;
uint GUARD = 0xDEADBEEF;

enum AddedComponent {
	AC_Invasion = 0x1,
};

interface IAIComponent : Savable {
	void set(AI& ai);
	void setLog();
	void setLogCritical();

	double getPrevFocus();
	void setPrevFocus(double value);

	void create();
	void start();

	void tick(double time);
	void focusTick(double time);
	void turn();

	void save(SaveFile& file);
	void load(SaveFile& file);
	void postLoad(AI& ai);
	void postSave(AI& ai);
	void loadFinalize(AI& ai);
};

class AIComponent : IAIComponent, Savable {
	AI@ ai;
	double prevFocus = 0;
	bool log = false;
	bool logCritical = false;
	bool logErrors = true;

	double getPrevFocus() { return prevFocus; }
	void setPrevFocus(double value) { prevFocus = value; }

	void setLog() { log = true; }
	void setLogCritical() { logCritical = true; }

	void set(AI& ai) { @this.ai = ai; }
	void create() {}
	void start() {}

	void tick(double time) {}
	void focusTick(double time) {}
	void turn() {}

	void save(SaveFile& file) {}
	void load(SaveFile& file) {}
	void postLoad(AI& ai) {}
	void postSave(AI& ai) {}
	void loadFinalize(AI& ai) {}
};

class ProfileData {
	double tickPeak = 0.0;
	double tickAvg = 0.0;
	double tickCount = 0.0;

	double focusPeak = 0.0;
	double focusAvg = 0.0;
	double focusCount = 0.0;
};

final class AIBehavior {
	//How many focuses we can manage in a tick
	uint focusPerTick = 2;

	//The maximum colonizations this AI can do in one turn
	uint maxColonizations = UINT_MAX;
	//How many colonizations we're guaranteed to be able to do in one turn regardless of finances
	uint guaranteeColonizations = 2;
	//How many colonizations at most we can be doing at once
	uint maxConcurrentColonizations = UINT_MAX;
	//Whether this AI will colonize planets in systems owned by someone else
	// TODO: This should be partially ignored for border systems, so it can try to aggressively expand into the border
	bool colonizeEnemySystems = false;
	bool colonizeNeutralOwnedSystems = false;
	bool colonizeAllySystems = false;
	//How much this AI values claiming new systems instead of colonizing stuff in its existing ones
	double weightOutwardExpand = 2.0;
	//How much money this AI considers a colonization event to cost out of the budget
	int colonizeBudgetCost = 80;
	//Whether to do any generic expansion beyond any requests
	bool colonizeGenericExpand = true;
	//Latest percentage into a budget cycle that we still allow colonization
	double colonizeMaxBudgetProgress = 0.66;
	//Time after initial ownership change that an incomplete colonization is canceled
	double colonizeFailGraceTime = 100.0;
	//Time a planet that we failed to colonize is disregarded for colonization
	double colonizePenalizeTime = 9.0 * 60.0;

	//Maximum amount of scouting missions that can be performed simultaneously
	uint maxScoutingMissions = UINT_MAX;
	//Minimum time after losing vision over a system that we can scout it again
	double minScoutingInterval = 3.0 * 60.0;
	//Weight that it gives to exploring things near our empire instead of greedily exploring nearby things
	double exploreBorderWeight = 2.0;
	//How long we consider all fleets viable for scouting with
	double scoutAllTimer = 3.0 * 60.0;
	//How many scouts we want to have active
	uint scoutsActive = 2;
	//How many scanning missions we can do at once
	uint maxScanningMissions = 1;
	//Whether to prioritize scouting over scanning if we only have one scout
	bool prioritizeScoutOverScan = true;

	//Weights for what to do in generic planet development
	//  Leveling up an existing development focus
	double focusDevelopWeight = 1.0;
	//  Colonizing a new scalable or high tier to focus on
	double focusColonizeNewWeight = 4.0;
	//  Colonizing a new high tier resource to import to one of our focuses
	double focusColonizeHighTierWeight = 1.0;

	//How many potential designs are evaluated before choosing the best one
	uint designEvaluateCount = 10;
	//How long a fleet has to be fully idle before it returns to its stationed system
	double fleetIdleReturnStationedTime = 60.0;
	//How long we try to have a fleet be capable of firing before running out of supplies
	double fleetAimSupplyDuration = 2.0 * 60.0;

	//How long a potential construction can take at most before we consider it unreasonable
	double constructionMaxTime = 10.0 * 60.0;
	//How long a factory has to have been idle for us to consider constructing labor storage
	double laborStoreIdleTimer = 60.0;
	//Maximum amount of time worth of labor we want to store in our warehouses
	double laborStoreMaxFillTime = 60.0 * 10.0;
	//Whether to use labor to build asteroids in the background
	bool backgroundBuildAsteroids = true;
	//Whether to choose the best resource on an asteroid, instead of doing it randomly
	bool chooseAsteroidResource = true;
	//Whether to distribute labor to shipyards when planets are idle
	bool distributeLaborExports = true;
	//Whether to build a shipyard to consolidate multiple planets of labor where possible
	bool consolidateLaborExports = true;
	//Estimate amount of labor spent per point of support ship size
	double estSizeSupportLabor = 0.25;

	//Maximum combat fleets we can have in service at once (counts starting fleet(s))
	uint maxActiveFleets = UINT_MAX;
	//How much flagship size we try to make per available money
	double shipSizePerMoney = 1.0 / 3.5;
	//How much flagship size we try to make per available labor
	double shipSizePerLabor = 1.0 / 0.33;
	//How much maintenance we expect per ship size
	double maintenancePerShipSize = 2.0;
	//Minimum percentage increase in size before we decide to retrofit a flagship to be bigger
	double shipRetrofitThreshold = 0.5;
	//Whether to retrofit our free starting fleet if appropriate
	bool retrofitFreeFleets = false;
	//Minimum percentage of average current flagship size new fleets should be
	double flagshipBuildMinAvgSize = 1.00;
	//Minimum game time before we consider constructing new flagships
	double flagshipBuildMinGameTime = 4.0 * 60.0;
	//Whether to build factories when we need labor
	bool buildFactoryForLabor = true;
	//Whether to build warehouses when we're not using labor
	bool buildLaborStorage = true;
	//Whether factories can queue labor resource imports when needed
	bool allowRequestLaborImports = true;
	//Whether fleets with ghosted supports attempt to rebuild the ghosts or just clear them
	bool fleetsRebuildGhosts = true;
	//When trying to order supports on a fleet, wait for the planet to construct its supports so we can claim them
	bool supportOrderWaitOnFactory = true;

	//How much stronger we need to be than a remnant fleet to clear it
	double remnantOverkillFactor = 1.5;
	//Whether to allow idle fleets to be sent to clear remnants
	// Modified by Relations
	bool remnantAllowArbitraryClear = true;

	//Whether we should aggressively try to take out enemies
	bool aggressive = false;
	//Whether to become aggressive after we get boxed in and can no longer expand anywhere
	bool aggressiveWhenBoxedIn = false;
	//Whether we should never declare war ourselves
	bool passive = false;
	//Whether to hate human players the most
	bool biased = false;
	//How much stronger we need to be than someone to declare war out of hatred
	double hatredWarOverkill = 0.5;
	//How much stronger we need to be than someone to try to take them out in an aggressive war
	double aggressiveWarOverkill = 1.5;
	//How much stronger we want to be before we attack a system
	double attackStrengthOverkill = 1.5;
	//How many battles we can be performing at once
	uint maxBattles = UINT_MAX;
	//How much we try to overkill while fighting
	double battleStrengthOverkill = 1.5;
	//How many fleets we don't commit to attacks when we're already currently fighting
	uint battleReserveFleets = 1;
	//How much extra supply we try to have before starting a capture, to make sure we can actually do it
	double captureSupplyEstimate = 1.5;
	//Maximum hop distance we use as staging areas for our attacks
	int stagingMaxHops = 5;
	//If our fleet fill is less than this, immediately move back to factory from staging
	double stagingToFactoryFill = 0.6;

	//How much ftl is reserved for critical applications
	double ftlReservePctCritical = 0.25;
	//How much ftl is reserved to not be used for background applications
	double ftlReservePctNormal = 0.25;

	//How many artifacts we consider where to use per focus turn
	uint artifactFocusConsiderCount = 2;

	//How long after trying to build a generically requested building we give up
	double genericBuildExpire = 3.0 * 60.0;

	//How much the hate in a relationship decays to every minute
	double hateDecayRate = 0.9;
	//How much weaker we need to be to even consider surrender
	double surrenderMinStrength = 0.5;
	//How many of our total war points have to be taken by an empire for us to surrender
	double acceptSurrenderRatio = 0.75;
	double offerSurrenderRatio = 0.5;

	void setDifficulty(int diff, uint flags) {
		//This changes the behavior values based on difficulty and flags
		if(flags & AIF_Aggressive != 0)
			aggressive = true;
		if(flags & AIF_Passive != 0)
			passive = true;
		if(flags & AIF_Biased != 0)
			biased = true;

		//Low difficulties can't colonize as many things at once
		if(diff <= 0) {
			maxConcurrentColonizations = 1;
			guaranteeColonizations = 1;
			weightOutwardExpand = 0.5;
		}
		else if(diff <= 1) {
			maxConcurrentColonizations = 2;
			weightOutwardExpand = 1.0;
		}

		//Hard AI becomes aggressive when it gets boxed in
		aggressiveWhenBoxedIn = diff >= 2;

		//Easy difficulty can't attack and defend at the same time
		if(diff <= 0)
			maxBattles = 1;

		//Low difficulties aren't as good at managing labor
		if(diff <= 0) {
			distributeLaborExports = false;
			consolidateLaborExports = false;
			buildLaborStorage = false;
		}
		else if(diff <= 1) {
			consolidateLaborExports = false;
		}

		//Low difficulties aren't as good at managing fleets
		if(diff <= 0) {
			maxActiveFleets = 2;
			retrofitFreeFleets = true;
		}

		//Low difficulties aren't as good at scouting
		if(diff <= 1)
			scoutAllTimer = 0.0;

		//Low difficulties are worse at designing
		if(diff <= 0)
			designEvaluateCount = 3;
		else if(diff <= 1)
			designEvaluateCount = 8;
		else
			designEvaluateCount = 12;

		//Easy is a bit slow
		if(diff <= 0)
			focusPerTick = 1;
		else if(diff >= 2)
			focusPerTick = 3;
	}
};

final class AIDefs {
	const BuildingType@ Factory;
	const BuildingType@ LaborStorage;
	const OrbitalModule@ Shipyard;
};

final class AI : AIController, Savable {
	Empire@ empire;
	AIBehavior behavior;
	AIDefs defs;

	int cycleId = -1;
	uint componentCycle = 0;
	uint addedComponents = 0;

	uint majorMask = 0;
	uint difficulty = 0;
	uint flags = 0;
	bool isLoading = false;

	array<IAIComponent@> components;
	array<ProfileData> profileData;
	IAIComponent@ fleets;
	IAIComponent@ budget;
	IAIComponent@ colonization;
	IAIComponent@ resources;
	IAIComponent@ planets;
	IAIComponent@ systems;
	IAIComponent@ scouting;
	IAIComponent@ development;
	IAIComponent@ designs;
	IAIComponent@ construction;
	IAIComponent@ military;
	IAIComponent@ movement;
	IAIComponent@ creeping;
	IAIComponent@ relations;
	IAIComponent@ intelligence;
	IAIComponent@ war;
	IAIComponent@ research;
	IAIComponent@ energy;
	IAIComponent@ diplomacy;
	IAIComponent@ consider;
	IAIComponent@ orbitals;

	IAIComponent@ ftl;
	IAIComponent@ race;

	IAIComponent@ invasion;

	void createComponents() {
		//NOTE: This is also save/load order, so
		//make sure to add loading logic when changing this list
		@budget = add(createBudget());
		@planets = add(createPlanets());
		@resources = add(createResources());
		@colonization = add(createColonization());
		@systems = add(createSystems());
		@fleets = add(createFleets());
		@scouting = add(createScouting());
		@development = add(createDevelopment());
		@designs = add(createDesigns());
		@construction = add(createConstruction());
		@military = add(createMilitary());
		@movement = add(createMovement());
		@creeping = add(createCreeping());
		@relations = add(createRelations());
		@intelligence = add(createIntelligence());
		@war = add(createWar());
		@research = add(createResearch());
		@energy = add(createEnergy());
		@diplomacy = add(createDiplomacy());
		@consider = add(createConsider());
		@orbitals = add(createOrbitals());

		//Make FTL component
		if(empire.hasTrait(getTraitID("Hyperdrive")))
			@ftl = add(createHyperdrive());
		else if(empire.hasTrait(getTraitID("Gate")))
			@ftl = add(createGate());
		else if(empire.hasTrait(getTraitID("Fling")))
			@ftl = add(createFling());
		else if(empire.hasTrait(getTraitID("Slipstream")))
			@ftl = add(createSlipstream());
		else if(empire.hasTrait(getTraitID("Jumpdrive")))
			@ftl = add(createJumpdrive());

		//Make racial component
		if(empire.hasTrait(getTraitID("Verdant")))
			@race = add(createVerdant());
		else if(empire.hasTrait(getTraitID("Mechanoid")))
			@race = add(createMechanoid());
		else if(empire.hasTrait(getTraitID("StarChildren")))
			@race = add(createStarChildren());
		else if(empire.hasTrait(getTraitID("Extragalactic")))
			@race = add(createExtragalactic());
		else if(empire.hasTrait(getTraitID("Linked")))
			@race = add(createLinked());
		else if(empire.hasTrait(getTraitID("Devout")))
			@race = add(createDevout());
		else if(empire.hasTrait(getTraitID("Ancient")))
			@race = add(createAncient());

		//Misc components
		if(hasInvasionMap() || addedComponents & AC_Invasion != 0) {
			@invasion = add(createInvasion());
			addedComponents |= AC_Invasion;
		}

		//if(empire is playerEmpire) {
			//log(race);
		//	log(colonization);
		//	log(resources);
		//	log(construction);
		//}
		//log(intelligence);
		//logAll();
		logCritical();

		profileData.length = components.length;
		for(uint i = 0, cnt = components.length; i < cnt; ++i)
			components[i].create();
	}

	void createGeneral() {
	}

	void init(Empire& emp, EmpireSettings& settings) {
		@this.empire = emp;
		flags = settings.aiFlags;
		difficulty = settings.difficulty;
		behavior.setDifficulty(difficulty, flags);

		createComponents();
	}

	int getDifficultyLevel() {
		return difficulty;
	}

	void load(SaveFile& file) {
		file >> empire;
		file >> cycleId;
		file >> majorMask;
		file >> difficulty;
		file >> flags;
		if(file >= SV_0153)
			file >> addedComponents;
		behavior.setDifficulty(difficulty, flags);
		createComponents();
		createGeneral();

		uint loadCnt = 0;
		file >> loadCnt;
		loadCnt = loadCnt;
		for(uint i = 0; i < loadCnt; ++i) {
			double prevFocus = 0;
			file >> prevFocus;
			components[i].setPrevFocus(prevFocus);
			file >> components[i];

			uint check = 0;
			file >> check;
			if(check != GUARD)
				error("ERROR: AI Load error detected in component "+addrstr(components[i])+" of "+empire.name);
		}
		for(uint i = 0, cnt = components.length; i < cnt; ++i)
			components[i].postLoad(this);
		isLoading = true;
	}

	void save(SaveFile& file) {
		file << empire;
		file << cycleId;
		file << majorMask;
		file << difficulty;
		file << flags;
		file << addedComponents;
		uint saveCnt = components.length;
		file << saveCnt;
		for(uint i = 0; i < saveCnt; ++i) {
			file << components[i].getPrevFocus();
			file << components[i];
			file << GUARD;
		}
		for(uint i = 0, cnt = components.length; i < cnt; ++i)
			components[i].postSave(this);
	}

	void log(IAIComponent@ comp) {
		if(comp is null)
			return;
		comp.setLog();
		comp.setLogCritical();
	}

	void logCritical() {
		for(uint i = 0, cnt = components.length; i < cnt; ++i)
			components[i].setLogCritical();
	}

	void logAll() {
		for(uint i = 0, cnt = components.length; i < cnt; ++i) {
			components[i].setLog();
			components[i].setLogCritical();
		}
	}

	IAIComponent@ add(IAIComponent& component) {
		component.set(this);
		components.insertLast(component);
		return component;
	}

	void init(Empire& emp) {
		majorMask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp.major)
				majorMask |= emp.mask;
		}

		createGeneral();
	}

	bool hasStarted = false;
	void tick(Empire& emp, double time) {
		if(isLoading) {
			for(uint i = 0, cnt = components.length; i < cnt; ++i)
				components[i].loadFinalize(this);
			isLoading = false;
			hasStarted = true;
		}
		else if(!hasStarted) {
			for(uint i = 0, cnt = components.length; i < cnt; ++i)
				components[i].start();
			hasStarted = true;
		}
		else if(emp.Victory == -1) {
			//Don't do anything when actually defeated
			return;
		}

		//Manage gametime-specific behaviors
		behavior.colonizeGenericExpand = gameTime >= 6.0 * 60.0;

		//Find cycled turns
		int curCycle = emp.BudgetCycleId;
		if(curCycle != cycleId) {
			for(uint i = 0, cnt = components.length; i < cnt; ++i)
				components[i].turn();
			cycleId = curCycle;
		}

		//Generic ticks
		double startTime = getExactTime();
		for(uint i = 0, cnt = components.length; i < cnt; ++i) {
			auto@ comp = components[i];
			comp.tick(time);

			double endTime = getExactTime();
			//double ms = 1000.0 * (endTime - startTime);
			startTime = endTime;

			//auto@ dat = profileData[i];
			//dat.tickPeak = max(dat.tickPeak, ms);
			//dat.tickAvg += ms;
			//dat.tickCount += 1.0;
		}

		//Do focuseds tick on components
		uint focusCount = behavior.focusPerTick;
		if(ai_full_speed.value == 1.0)
			focusCount = max(uint(round((time / 0.25) * behavior.focusPerTick)), behavior.focusPerTick);
		double allocStart = startTime;

		for(uint n = 0; n < focusCount; ++n) {
			componentCycle = (componentCycle+1) % components.length;
			auto@ focusComp = components[componentCycle];
			focusComp.focusTick(gameTime - focusComp.getPrevFocus());
			focusComp.setPrevFocus(gameTime);

			double endTime = getExactTime();
			//double ms = 1000.0 * (endTime - startTime);
			startTime = endTime;
			if(endTime - allocStart > 4000.0)
				break;

			//auto@ dat = profileData[componentCycle];
			//dat.focusPeak = max(dat.focusPeak, ms);
			//dat.focusAvg += ms;
			//dat.focusCount += 1.0;
		}
	}

	void dumpProfile() {
		for(uint i = 0, cnt = components.length; i < cnt; ++i) {
			auto@ c = profileData[i];
			print(pad(addrstr(components[i]), 40)+" tick peak "+toString(c.tickPeak,2)+"    tick avg "+toString(c.tickAvg/c.tickCount, 2)
				+"    focus peak "+toString(c.focusPeak,2)+"    focus avg "+toString(c.focusAvg/c.focusCount, 2));
		}
	}

	void resetProfile() {
		for(uint i = 0, cnt = profileData.length; i < cnt; ++i) {
			auto@ c = profileData[i];
			c.tickPeak = 0.0;
			c.tickAvg = 0.0;
			c.tickCount = 0.0;
			c.focusPeak = 0.0;
			c.focusAvg = 0.0;
			c.focusCount = 0.0;
		}
	}

	uint get_mask() {
		return empire.mask;
	}

	uint get_teamMask() {
		//TODO
		return empire.mask;
	}

	uint get_visionMask() {
		return majorMask & empire.visionMask;
	}

	uint get_allyMask() {
		return empire.mutualDefenseMask | empire.ForcedPeaceMask.value;
	}

	uint get_enemyMask() {
		return empire.hostileMask & majorMask;
	}

	uint get_neutralMask() {
		return majorMask & ~allyMask & ~mask & ~enemyMask;
	}

	uint get_otherMask() {
		return majorMask & ~mask;
	}

	string pad(const string& input, uint width) {
		string str = input;
		while(str.length < width)
			str += " ";
		return str;
	}

	void print(const string& info, Object@ related = null, double value = INFINITY, bool flag = false, Empire@ emp = null) {
		string str = info;
		if(related !is null)
			str = pad(related.name, 16)+" | "+str;
		str = pad("["+empire.index+": "+empire.name+" AI] ", 20)+str;
		str = formatGameTime(gameTime) + " " + str;
		if(value != INFINITY)
			str += " | Value = "+standardize(value, true);
		if(flag)
			str += " | FLAGGED On";
		if(emp !is null)
			str += " | Target = "+emp.name;
		::print(str);
	}

	void debugAI() {}
	void commandAI(string cmd) {}
	void aiPing(Empire@ fromEmpire, vec3d position, uint type) {}
	void pause(Empire& emp) {}
	void resume(Empire& emp) {}
	vec3d get_aiFocus() { return vec3d(); }
	string getOpinionOf(Empire& emp, Empire@ other) { return ""; }
	int getStandingTo(Empire& emp, Empire@ other) { return 0; }
};

AIController@ createWeaselAI() {
	return AI();
}
