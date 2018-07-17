import settings.game_settings;
from empire_ai.EmpireAI import AIController;
from saving import SaveVersion;
import biomes;
import orbitals;
import attributes;
import util.convar;
import notifications;
import regions.regions;
import constructible;
import designs;
from util.design_export import getBestHull;
import util.random_designs;
import int getAbilityID(const string& ident) from "abilities";
import int getTraitID(const string&) from "traits";

const double maxAIFrame = 0.001;

const float gotPlanetWill = 1.25f;
const float lostPlanetWill = 1.f;
//Per size of flagship
const float gotFleetWill = 0.05f;
const float lostFleetWill = 0.02f;

//Percent of willpower remaining after 3 minute cycle
const double willDecayPerBudget = 0.55;

ConVar profile_ai("profile_ai", 0.0);

#include "empire_ai/include/bai_act_colonize.as"
#include "empire_ai/include/bai_act_resources.as"
#include "empire_ai/include/bai_act_fleets.as"
#include "empire_ai/include/bai_act_strategy.as"
#include "empire_ai/include/bai_act_influence.as"
#include "empire_ai/include/bai_act_diplomacy.as"
#include "include/resource_constants.as"

from influence_global import sendPeaceOffer, createTreaty;

const uint unownedMask = 1;

enum ActionType {
	ACT_Plan,
	ACT_FindIdle,
	ACT_Colonize,
	ACT_ColonizeRes,
	ACT_Explore,
	ACT_Build,
	ACT_Improve,
	ACT_Trade,
	ACT_Expend,
	ACT_Budget,
	ACT_Vote,
	ACT_Combat,
	ACT_War,
	ACT_Defend,
	ACT_Expand,
	ACT_Building,
	ACT_BuildOrbital,
	ACT_Design,
	ACT_Populate,
	ACT_ManageFactories,
	ACT_ManagePressureResources,
	ACT_Diplomacy, //21
	
	STRAT_Military = 32,
	STRAT_Influence,
	
	ACT_BIT_OFFSET = 58,
};

enum AIDifficulty {
	DIFF_Trivial = 0,
	DIFF_Easy = 1,
	DIFF_Medium = 2,
	DIFF_Hard = 3,
	DIFF_Max = 4,
};

enum AIBehavior {
	AIB_IgnorePlayer = 0x1,
	AIB_IgnoreAI = 0x2,
	AIB_QuickToWar = 0x4,
};

enum AICheats {
	AIC_Vision = 0x1,
	AIC_Resources = 0x2,
};

enum FleetType {
	FT_Scout,
	FT_Combat,
	FT_Carrier,
	FT_Titan,
	
	FT_Mothership,
	FT_Slipstream,

	FT_INVALID
};

enum SpendFlags {
	SF_Borrow = 1
};

interface Action {
	int64 get_hash() const;
	ActionType get_actionType() const;
	string get_state() const;
	//Returns true if the action is finished
	bool perform(BasicAI@);
	void save(BasicAI@, SaveFile& msg);
	void postLoad(BasicAI@);
}

interface ObjectReceiver : Action {
	bool giveObject(BasicAI@ ai, Object@);
}

final class AsteroidCache {
	Asteroid@ asteroid;
	array<int> resources;
	bool cached = false;

	void cache() {
		if(cached)
			return;
		cached = true;
		resources.length = asteroid.getAvailableCount();
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			resources[i] = asteroid.getAvailable(i);
	}
}

final class PlanRegion {
	Region@ region;
	vec3d center;
	double radius = 900.0;
	
	double lastSeen = -1e3;
	uint planetMask = 0;
	
	array<Planet@> planets, plRecord;
	array<int> planetResources;
	array<AsteroidCache@> resourceAsteroids;
	array<Artifact@> artifacts;
	array<Orbital@> orbitals;
	array<Anomaly@> anomalies;
	//Ship strength per-empire (sqrt space)
	array<double> strengths(getEmpireCount());
	
	const SystemDesc@ cachedSystem;
	
	const SystemDesc@ get_system() {
		if(cachedSystem !is null)
			return cachedSystem;
		if(region is null)
			return null;
		@cachedSystem = getSystem(region);
		return cachedSystem;
	}
	
	PlanRegion(Object@ Focus) {
		while(Focus.region !is null)
			@Focus = Focus.region;
		@region = cast<Region>(Focus);
		center = region.position;
		radius = region.radius;
	}

	PlanRegion(SaveFile& file) {
		file >> region;
		file >> center;
		if(file >= SV_0037)
			file >> lastSeen;
		
		file >> planetMask;
		
		uint count = 0;
		
		file >> count;
		planets.length = count;
		planetResources.length = count;
		for(uint i = 0; i < count; ++i) {
			file >> planets[i];
			planetResources[i] = planets[i].primaryResourceType;
		}
		
		plRecord = planets;
		
		file >> count;
		resourceAsteroids.length = count;
		for(uint i = 0; i < count; ++i) {
			AsteroidCache cache;
			file >> cache.asteroid;
			@resourceAsteroids[i] = cache;
		}
		
		if(file >= SV_0030) {
			file >> count;
			artifacts.length = count;
			for(uint i = 0; i < count; ++i)
				file >> artifacts[i];
		}
			
		for(uint i = 0; i < strengths.length; ++i)
			file >> strengths[i];
	}

	void save(SaveFile& file) {
		file << region;
		file << center;
		file << lastSeen;
		
		file << planetMask;
		file << uint(planets.length);
			for(uint i = 0; i < planets.length; ++i)
				file << planets[i];
		
		file << uint(resourceAsteroids.length);
			for(uint i = 0; i < resourceAsteroids.length; ++i)
				file << resourceAsteroids[i].asteroid;
		
		file << uint(artifacts.length);
			for(uint i = 0; i < artifacts.length; ++i)
				file << artifacts[i];
		
		for(uint i = 0; i < strengths.length; ++i)
			file << strengths[i];
	}
	
	double get_age() const {
		return gameTime - lastSeen;
	}
	
	//Checks for various changes to remembered planet states
	//	Returns true if all planets were in memory
	bool useMemory(BasicAI@ ai) {
		bool anyMemory = false, allInMemory = true;
		uint plOwnerMask = 0;
		
		//TODO: Have regions track when their planet list changes
		uint plCount = region.planetCount;
		if(plRecord.length != plCount) {
			plRecord.length = 0;
			for(uint i = 0, cnt = plCount; i < cnt; ++i) {
				Planet@ pl = region.planets[i];
				if(pl !is null && pl.valid)
					plRecord.insertLast(pl);
			}
		}
		
		for(uint i = 0, cnt = plRecord.length; i < cnt; ++i) {
			Planet@ pl = plRecord[i];
			if(pl is null || !pl.valid)
				break;
			
			if(!pl.isKnownTo(ai.empire)) {
				allInMemory = false;
				continue;
			}
			
			Empire@ owner = pl.visibleOwnerToEmp(ai.empire);
			if(owner is null)
				continue;
			
			if(!anyMemory) {
				planets.length = 0;
				planetResources.length = 0;
			}
			
			anyMemory = true;
			plOwnerMask |= owner.mask;
			planets.insertLast(pl);
			planetResources.insertLast(pl.primaryResourceType);
		}
		
		if(anyMemory)
			planetMask = plOwnerMask;
		return allInMemory;
	}
	
	//Search the system for all objects we can track and remember, and update strength ratings
	array<Object@>@ scout(BasicAI@ ai, bool verbose = false) {
		ai.didTickScan = true;
		auto@ empire = ai.empire;
	
		array<Object@>@ objs = search();
		lastSeen = gameTime;
		
		plRecord.length = 0;
		planets.length = 0;
		planetResources.length = 0;
		resourceAsteroids.length = 0;
		artifacts.length = 0;
		orbitals.length = 0;
		anomalies.length = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
			strengths[i] = 0.0;
		
		planetMask = 0;
		
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			Object@ obj = objs[i];
			if(obj.region !is region)
				continue;
			if(!obj.isKnownTo(empire) && !obj.isVisibleTo(empire)) {
				if(obj.isPlanet)
					plRecord.insertLast(cast<Planet>(obj));
				continue;
			}
			
			//if(verbose)
			//	error(obj.name);
			
			switch(obj.type) {
				case OT_Planet:
					{
						Planet@ pl = cast<Planet>(obj);
						plRecord.insertLast(pl);
						planets.insertLast(pl);
						planetResources.insertLast(pl.primaryResourceType);
						Empire@ owner = pl.visibleOwnerToEmp(empire);
						planetMask |= owner.mask;
						if(owner.valid)
							strengths[owner.index] += sqrt(pl.getFleetStrength());
						if(owner is empire && !ai.knownPlanets.contains(pl.id)) {
							ai.addPlanet(pl);
							ai.markAsColony(region);
						}
					}
					break;
				case OT_Asteroid: {
					Empire@ owner = obj.owner;
					if(owner is defaultEmpire && obj.valid && cast<Asteroid>(obj).getAvailableCount() != 0) {
						AsteroidCache cache;
						@cache.asteroid = cast<Asteroid>(obj);
						cache.cache();

						resourceAsteroids.insertLast(cache);
					}
					if(owner is empire && !ai.knownAsteroids.contains(obj.id))
						ai.addAsteroid(cast<Asteroid>(obj));
				  } break;
				case OT_Ship:
					{
						Empire@ owner = obj.owner;
						if(owner.valid && obj.hasLeaderAI)
							strengths[owner.index] += sqrt(obj.getFleetStrength());
					} break;
				case OT_Artifact:
					artifacts.insertLast(cast<Artifact>(obj));
					break;
				case OT_Anomaly:
					anomalies.insertLast(cast<Anomaly>(obj));
					break;
				case OT_Orbital:
					{
						orbitals.insertLast(cast<Orbital>(obj));
						Empire@ owner = obj.owner;
						if(owner.valid) {
							Orbital@ orb = cast<Orbital>(obj);
							double hp = orb.maxHealth + orb.maxArmor;
							double dps = orb.dps * max(orb.efficiency, 0.75);
							if(orb.hasLeaderAI) {
								hp += obj.getFleetHP();
								dps += orb.getFleetDPS();
							}
							strengths[owner.index] += sqrt(hp * dps);
						}
					} break;
			}
		}
		
		return objs;
	}
	
	array<Object@>@ search(uint mask = 0) {
		vec3d bound(radius);
		return findInBox(center - bound, center + bound, mask);
	}
	
	bool hasEnemies(Empire& against) {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.valid)
				continue;
			if(against.isHostile(emp) && strengths[emp.index] > 0)
				return true;
		}
		return false;
	}
};

final class SysSearch {
	int start = -1;
	int index = 0;
	
	void reset() {
		start = -1;
		index = 0;
	}
	
	void save(SaveFile& msg) {
		msg << start;
		if(start != -1)
			msg << index;
	}
	
	void load(SaveFile& msg) {
		msg >> start;
		if(start != -1)
			msg >> index;
	}
	
	PlanRegion@ next(array<PlanRegion@>& sysList) {
		int count = sysList.length;
		if(start == -1)
			start = randomi(0,count-1);
		
		if(index >= count)
			return null;
		
		int ind = (start + index) % count;
		index += 1;
		
		return sysList[ind];
	}
	
	PlanRegion@ random(array<PlanRegion@>& sysList) {
		int count = sysList.length;
		if(count == 0)
			return null;
		else
			return sysList[randomi(0,count-1)];
	}
	
	//Searches the next region, returning null if none are remaining
	array<Object@>@ search(array<PlanRegion@>& sysList, uint mask = 0) {
		PlanRegion@ region = next(sysList);
		if(region !is null)
			return region.search(mask);
		else
			return null;
	}
	
	//Searches a random region
	array<Object@>@ searchRandom(array<PlanRegion@>& sysList, uint mask = 0) {
		PlanRegion@ region = random(sysList);
		if(region !is null)
			return region.search(mask);
		else
			return array<Object@>();
	}
};

final class PlanetList {
	array<Planet@> idle, used;
	array<Object@> purpose;

	uint get_length() {
		return idle.length + used.length;
	}

	Planet@ get_planets(uint index) {
		if(index < idle.length)
			return idle[index];
		index -= idle.length;
		if(index >= used.length)
			return null;
		return used[index];
	}

	Object@ get_planetPurpose(uint index) {
		if(index < idle.length)
			return null;
		index -= idle.length;
		if(index >= used.length)
			return null;
		return purpose[index];
	}
	
	bool markIdle(Planet@ pl, bool onlyIfMissing = false) {
		bool wasNew = true;
		if(idle.find(pl) < 0) {
			int ind = used.find(pl);
			if(ind >= 0) {
				if(onlyIfMissing)
					return false;
				
				wasNew = false;
				used.removeAt(ind);
				purpose.removeAt(ind);
			}
			idle.insertLast(pl);
		}
		
		return wasNew;
	}
	
	void markUsed(Planet@ pl, Object@ goal) {
		int ind = used.find(pl);
		if(ind < 0) {
			idle.remove(pl);
			used.insertLast(pl);
			purpose.insertLast(goal);
		}
		else {
			@purpose[ind] = goal;
		}
	}
	
	Object@ getPurpose(Planet@ pl) {
		int ind = used.find(pl);
		if(ind >= 0)
			return purpose[ind];
		else
			return null;
	}
	
	void remove(Planet@ pl) {
		int index = idle.find(pl);
		if(index >= 0) {
			idle.removeAt(index);
			return;
		}
		
		index = used.find(pl);
		if(index >= 0) {
			used.removeAt(index);
			purpose.removeAt(index);
			return;
		}
	}
	
	void validate(BasicAI@ ai, Empire@ owner, const ResourceType@ type) {
		uint resType = uint(-1);
		uint usedLevel = 0;
		if(type !is null) {
			usedLevel = type.level;
			resType = type.id;
		}
	
		for(int i = idle.length - 1; i >= 0; --i) {
			Planet@ pl = idle[i];
			if(pl.owner !is owner || !pl.valid) {
				ai.willpower -= lostPlanetWill;
				idle.removeAt(i);
				ai.knownPlanets.erase(pl.id);
				if(pl.valid && pl.owner.valid) {
					auto@ relation = ai.getRelation(pl.owner);
					relation.offense = RA_Planet;
					relation.standing -= 15;
				}
			}
			else if(pl.Population < 1.0) {
				ai.addIdle(ai.requestColony(pl, execute=false));
			}
			else if(pl.primaryResourceType != resType) {
				idle.removeAt(i);
				ai.addPlanet(pl);
			}
		}
		
		for(int i = used.length - 1; i >= 0; --i) {
			Planet@ pl = used[i];
			if(pl.owner !is owner || !pl.valid) {
				ai.willpower -= lostPlanetWill;
				used.removeAt(i);
				purpose.removeAt(i);
				ai.knownPlanets.erase(pl.id);
			}
			else if(pl.resourceLevel < usedLevel) {
				if(purpose[i] !is pl) {
					pl.exportResource(owner, 0, null);
					used.removeAt(i);
					purpose.removeAt(i);
					idle.insertLast(pl);
					ai.freePlanetImports(pl);
				}
			}
			else if(pl.primaryResourceType != resType) {
				used.removeAt(i);
				auto@ use = purpose[i];
				purpose.removeAt(i);
				ai.addPlanet(pl, use);
			}
			else {
				Object@ goal = purpose[i];
				if(!goal.valid || goal.owner !is owner || goal.region.getTerritory(owner) !is pl.region.getTerritory(owner)) {
					pl.exportResource(owner, 0, null);
					used.removeAt(i);
					purpose.removeAt(i);
					idle.insertLast(pl);
					ai.freePlanetImports(pl);
				}
			}
		}
		
		if(used.length > 0) {
			uint index = randomi(0,used.length - 1);
			Planet@ pl = used[index];
			Object@ dest = purpose[index];
			
			if(pl !is dest && pl.level >= usedLevel && !pl.isPrimaryDestination(dest)) {
				pl.exportResource(owner, 0, null);
				used.removeAt(index);
				purpose.removeAt(index);
				idle.insertLast(pl);
				ai.freePlanetImports(pl);
			}
		}
	}
	
	void save(SaveFile& msg) {
		uint count = idle.length;
		msg << count;
		for(uint i = 0; i < count; ++i)
			msg << idle[i];
		
		count = used.length;
		msg << count;
		for(uint i = 0; i < count; ++i) {
			msg << used[i];
			msg << purpose[i];
		}
	}
	
	void load(BasicAI@ ai, SaveFile& msg) {
		Planet@ pl;
		uint count = 0;
		msg >> count;
		idle.reserve(count);
		for(uint i = 0; i < count; ++i) {
			msg >> pl;
			if(pl is null)
				continue;
			idle.insertLast(pl);
			ai.knownPlanets.insert(pl.id);
		}
		
		Object@ other;
		count = 0;
		msg >> count;
		used.reserve(count);
		purpose.reserve(count);
		for(uint i = 0; i < count; ++i) {
			msg >> pl; msg >> other;
			if(pl is null)
				continue;
			used.insertLast(pl);
			ai.knownPlanets.insert(pl.id);
			purpose.insertLast(other);
		}
	}
};

enum AIResourceType {
	RT_Water,
	RT_Food,
	RT_LevelZero,
	RT_LevelOne,
	RT_LevelTwo,
	RT_LevelThree,
	RT_LaborZero,
	RT_PressureResource,
	
	RT_COUNT
};

final class Request {
	Region@ region;
	double time;
};

enum RecentAction {
	RA_None,
	RA_War,
	RA_Influence,
	RA_Planet,
	RA_Donation,
};

final class Relationship {
	Empire@ emp;
	int standing = 0;
	bool bordered = false, allied = false, war = false, brokeAlliance = false;
	int relStrength = 0;
	RecentAction lastOffense = RA_None;
	double offenseTime = 0;
	
	void set_offense(RecentAction act) {
		lastOffense = act;
		offenseTime = gameTime;
	}
};

enum SupportTask {
	ST_Filler,
	ST_AntiSupport,
	ST_AntiFlagship,
	ST_Tank,
	ST_Supplies,
	
	ST_COUNT
};

enum FlagshipTask {
	FST_Scout,
	FST_Combat,
	FST_SuperHeavy,
	FST_Mothership,
	FST_Slipstream,
	
	FST_COUNT,
	
	FST_COUNT_OLD1 = FST_Mothership,
	FST_COUNT_OLD2 = FST_Slipstream
};

enum StationTask {
	STT_LightDefense,
	STT_HeavyDefense,
	
	STT_COUNT
};

enum TreatyClauses {
	TC_Alliance = 0x1,
	TC_Trade = 0x2,
	TC_MutualDefense = 0x4,
	TC_Vision = 0x8,
};

enum FTLType {
	FTL_Hyperdrive,
	FTL_Jumpdrive,
	FTL_Fling,
	FTL_Gate,
	FTL_Slipstream
};

final class BasicAI : AIController {
	Empire@ empire;
	Planet@ homeworld;
	
	bool isMachineRace = false, usesMotherships = false, needsStalks = false, needsAltars = false;
	bool isFrugal = false;
	bool cannotDesign = false, needsMainframes = false;
	FTLType ftl = FTL_Hyperdrive;
	const OrbitalModule@ mainframeMod;
	
	PlanRegion@ protect;
	
	bool debug = false, profile = false, logWar = false;
	uint printDepth = 0;
	string dbgMsg;
	vec3d focus;
	WriteFile@ log;

	array<Empire@> enemies;
	array<Relationship> relations(32);
	Relationship pirateRelation;
	uint allyMask = 0;
	
	//Start at a reasonable willpower
	float willpower = gotPlanetWill * 3.f;
	
	array<double> treatyWaits(getEmpireCount(), gameTime + randomd(20.0,60.0));
	
	double lastPing = gameTime - randomd(65.0,90.0);
	Mutex reqLock;
	array<Request> requests, queuedRequests;
	
	array<PlanRegion@> ourSystems, exploredSystems, otherSystems;
	array<PlanetList> planetsByResource(getResourceCount());
	set_int knownPlanets;
	array<Asteroid@> idleAsteroids;
	array<Asteroid@> usedAsteroids;
	set_int knownAsteroids;
	
	array<Artifact@> artifacts(getArtifactTypeCount());
	array<Ship@> scoutFleets, combatFleets, motherships, slipstreamers, untrackedFleets;
	set_int knownLeaders;
	map systems;
	set_int knownSystems;
	
	double lastSlipstream = -300.0;
	
	array<Orbital@> orbitals;
	array<Object@> factories;
	set_int knownFactories;
	
	array<const Design@> dsgSupports(ST_COUNT), dsgFlagships(FST_COUNT), dsgStations(STT_COUNT);
	
	array<Object@> revenantParts;
	
	//AI Skill at various mechanics
	int skillEconomy = DIFF_Medium;
	int skillCombat = DIFF_Medium;
	int skillDiplo = DIFF_Medium;
	int skillTech = DIFF_Medium;
	int skillScout = DIFF_Medium;
	
	uint behaviorFlags = 0;
	uint cheatFlags = 0;
	int cheatLevel = 0;
	
	int getDifficultyLevel() {
		if(skillEconomy <= DIFF_Easy)
			return behaviorFlags & AIB_IgnorePlayer != 0 ? 0 : 1;
		else if(skillEconomy == DIFF_Medium)
			return 2;
		else if(cheatLevel > 0) {
			if(cheatLevel >= 12)
				return 7;
			else if(cheatLevel >= 11)
				return 6;
			return 5;
		}
		else if(behaviorFlags & AIB_IgnoreAI != 0)
			return 4;
		return 3;
	}
	
	map actions;
	Action@ head;
	array<Action@> idle;
	set_int idles;
	int thoughtCycle = 0;
	
	//Track when the AI has performed a scout of a system, to avoid too much per-tick load
	bool didTickScan = false;
	
	double timeSinceLastExpand = 0.0;
	
	uint nextNotification = 0;
	
	array<array<int>> resLists(RT_COUNT), resListsExportable(RT_COUNT);
	const ResourceClass@ foods = getResourceClass("Food");
	const ResourceClass@ waters = getResourceClass("WaterType");
	
	void buildCommonLists() {
		pirateRelation.standing = -100;
	
		isMachineRace = empire.hasTrait(getTraitID("Mechanoid"));
		usesMotherships = empire.hasTrait(getTraitID("StarChildren"));
		needsStalks = empire.hasTrait(getTraitID("Verdant"));
		needsMainframes = empire.hasTrait(getTraitID("Linked"));
		cannotDesign = empire.hasTrait(getTraitID("Verdant"));
		needsAltars = empire.hasTrait(getTraitID("Devout"));
		isFrugal = empire.hasTrait(getTraitID("Frugal"));
		@mainframeMod = getOrbitalModule("Mainframe");
		
		if(empire.hasTrait(getTraitID("Hyperdrive")))
			ftl = FTL_Hyperdrive;
		else if(empire.hasTrait(getTraitID("Slipstream")))
			ftl = FTL_Slipstream;
		else if(empire.hasTrait(getTraitID("Gate")))
			ftl = FTL_Gate;
		else if(empire.hasTrait(getTraitID("Fling")))
			ftl = FTL_Fling;
		else if(empire.hasTrait(getTraitID("Jumpdrive")))
			ftl = FTL_Jumpdrive;
		
		auto@ r = resLists, e = resListsExportable;
		
		for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
			auto@ res = getResource(i);
			uint type = classifyResource(res);
			if(type == RT_COUNT)
				continue;
			r[type].insertLast(res.id);
			if(res.exportable && !(res.artificial && type == RT_Water))
				e[type].insertLast(res.id);
		}
	}

	uint classifyResource(const ResourceType@ res) {
		if(res.mode == RM_NonRequirement)
			return RT_COUNT;
		
		switch(res.level) {
			case 0:
				if(res.cls is waters) {
					return RT_Water;
				}
				else if(res.cls is foods) {
					return RT_Food;
				}
				else {
					bool isLabor = res.tilePressure[TR_Labor] > 0;
					if(isLabor)
						return RT_LaborZero;
					else if(res.totalPressure > 0)
						return RT_PressureResource;
					else
						return RT_LevelZero;
				}
			case 1:
				return RT_LevelOne;
			case 2:
				return RT_LevelTwo;
			case 3:
				return RT_LevelThree;
		}

		return RT_COUNT;
	}
	
	string getOpinionOf(Empire& emp, Empire@ other) {
		auto@ relation = getRelation(other);
		string response;
		
		if(relation.standing > 10) {
			if(relation.standing > 50)
				response = locale::AI_STANDING_VERY_POSITIVE;
			else
				response = locale::AI_STANDING_POSITIVE;
		}
		else if(relation.standing < -10) {
			if(relation.standing < -50)
				response = locale::AI_STANDING_VERY_NEGATIVE;
			else
				response = locale::AI_STANDING_NEGATIVE;
		}
		else {
			if(randomi(0,100) == 0)
				response = locale::AI_STANDING_TRUE_NEUTRAL;
			else
				response = locale::AI_STANDING_NEUTRAL;
		}
		
		if(relation.offenseTime > gameTime - 180.0) {
			switch(relation.lastOffense) {
				case RA_War: response += " " + locale::AI_STANDING_OFFENSE_WAR; break;
				case RA_Influence: response += " " + locale::AI_STANDING_OFFENSE_INFLUENCE; break;
				case RA_Planet: response += " " + locale::AI_STANDING_OFFENSE_PLANET; break;
				case RA_Donation: response += " " + locale::AI_STANDING_GLAD_DONATION; break;
			}
		}
		
		if(relation.war) {
			if(relation.relStrength > 0)
				response += " " + locale::AI_STANDING_WAR_FEAR;
			else
				response += " " + locale::AI_STANDING_WAR;
		}
		else if(relation.allied) {
			response += " " + locale::AI_STANDING_ALLIES;
		}
		
		if(relation.bordered && !relation.allied) {
			if(!relation.war) {
				if(timeSinceLastExpand > 7.5 * 60.0)
					response += " " + locale::AI_STANDING_EXPANDING;
				else
					response += " " + locale::AI_STANDING_BORDER;
			}
			else {
				response += " " + locale::AI_STANDING_BORDER_WAR;
			}
		}
		
		if(ignoreEmpire(other) && !relation.war) {
			if(relation.war || relation.allied)
				response += " " + locale::AI_STANDING_IGNORE;
		}
		else if(behaviorFlags & locale::AIB_QuickToWar != 0) {
			response += " " + locale::AI_STANDING_WAAGH;
		}
		else if(treatyWaits[other.index] > gameTime) {
			response += " " + locale::AI_STANDING_WAIT;
		}
		else if((emp.points.value + 150) * 5 < other.points.value + 150) {
			response += " " + locale::AI_STANDING_GIVE_UP;
		}
		
		if(cheatFlags != 0) {
			response += " " + locale::AI_STANDING_CHEATS;
		}
		
		if(skillDiplo < DIFF_Medium) {
			response += " " + locale::AI_STANDING_EASY;
		}
		
		return response;
	}
	
	int getStandingTo(Empire& emp, Empire@ other) {
		return getRelation(other).standing / 10;
	}

	void proposeTreaty(Empire@ toEmpire, uint clauseMask) {
		Treaty treaty;

		if(clauseMask & TC_Trade != 0)
			treaty.addClause(getInfluenceClauseType("TradeClause"));
		if(clauseMask & TC_Alliance != 0)
			treaty.addClause(getInfluenceClauseType("AllianceClause"));
		if(clauseMask & TC_MutualDefense != 0)
			treaty.addClause(getInfluenceClauseType("MutualDefenseClause"));
		if(clauseMask & TC_Vision != 0)
			treaty.addClause(getInfluenceClauseType("VisionClause"));

		//Make sure we can invite to this treaty
		if(!treaty.canInvite(empire, toEmpire))
			return;
		treaty.inviteMask = toEmpire.mask;

		//Generate treaty name
		string genName;
		uint genCount = 0;
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ reg = getSystem(i).object;
			if(reg.TradeMask & (playerEmpire.mask | toEmpire.mask) != 0) {
				genCount += 1;
				if(randomd() < 1.0 / double(genCount))
					genName = reg.name;
			}
		}
		treaty.name = format(locale::TREATY_NAME_GEN, genName);

		//Create the treaty globally
		createTreaty(empire, treaty);
	}
	
	array<int>@ getResourceList(AIResourceType type, bool onlyExportable = false) {
		if(uint(type) >= resLists.length)
			return null;
		
		if(onlyExportable)
			return resListsExportable[type];
		else
			return resLists[type];
	}
	
	array<PlanRegion@>@ getBorder() {
		array<PlanRegion@> border;
		set_int found;
		uint mask = empire.mask;
		
		auto@ ours = ourSystems;
		for(uint i = 0, cnt = ours.length; i < cnt; ++i) {
			auto@ sys = ours[i].system;
			for(uint j = 0, jcnt = sys.adjacent.length; j < jcnt; ++j) {
				auto@ r = findSystem(getSystem(sys.adjacent[j]).object);
				if(r !is null && r.planetMask & mask == 0 && !found.contains(r.region.id)) {
					found.insert(r.region.id);
					border.insertLast(r);
				}
			}
		}
		
		return border;
	}
	
	PlanRegion@ getBorderSystem(PlanRegion& region) {
		auto@ sys = region.system;
		uint mask = empire.mask;
		uint off = randomi();
		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			auto@ r = findSystem(getSystem(sys.adjacent[(off+i) % cnt]).object);
			if(r !is null && r.planetMask & mask == 0)
				return r;
		}
		
		return null;
	}
	
	bool isBorderSystem(PlanRegion& region) {
		auto@ sys = region.system;
		uint mask = empire.mask;
		for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
			auto@ r = findSystem(getSystem(sys.adjacent[i]).object);
			if(r !is null && r.planetMask & mask != 0)
				return true;
		}
		
		return false;
	}
	
	vec3d get_aiFocus() {
		return focus;
	}
	
	Relationship@ getRelation(Empire@ emp) {
		if(emp is null || !emp.valid || !emp.major)
			return pirateRelation;
		return relations[emp.index];
	}
	
	bool ignoreEmpire(Empire@ emp) const {
		if(emp is null)
			return true;
		auto aiType = emp.getAIType();
		if(behaviorFlags & AIB_IgnorePlayer != 0 && aiType == ET_Player)
			return true;
		else if(behaviorFlags & AIB_IgnoreAI != 0 && aiType != ET_Player)
			return true;
		return false;
	}
	
	PlanetList@ get_planets(uint resourceType) {
		return planetsByResource[resourceType];
	}

	void addAsteroid(Asteroid@ roid) {
		knownAsteroids.insert(roid.id);
		idleAsteroids.insertLast(roid);
	}

	void markAsteroidUsed(Asteroid@ roid) {
		idleAsteroids.remove(roid);
		usedAsteroids.insertLast(roid);
	}

	void markAsteroidIdle(Asteroid@ roid) {
		usedAsteroids.remove(roid);
		idleAsteroids.insertLast(roid);
	}

	void markUsedGeneric(Object@ obj, Object@ purpose) {
		if(obj.isPlanet)
			markPlanetUsed(cast<Planet>(obj), purpose);
		else if(obj.isAsteroid)
			markAsteroidUsed(cast<Asteroid>(obj));
	}

	void markIdleGeneric(Object@ obj) {
		if(obj.isPlanet)
			markPlanetIdle(cast<Planet>(obj));
		else if(obj.isAsteroid)
			markAsteroidIdle(cast<Asteroid>(obj));
	}

	void removeAsteroid(Asteroid@ roid) {
		usedAsteroids.remove(roid);
		idleAsteroids.remove(roid);
		knownAsteroids.erase(roid.id);
	}
	
	void markPlanetIdle(Planet@ pl, bool onlyIfMissing = false) {
		knownPlanets.insert(pl.id);
		int resType = pl.primaryResourceType;
		if(resType < 0)
			return;
		bool wasNew = planetsByResource[resType].markIdle(pl, onlyIfMissing);
		if(wasNew)
			willpower += gotPlanetWill;
	}
	
	void markPlanetUsed(Planet@ pl, Object@ purpose) {
		knownPlanets.insert(pl.id);
		int typeID = pl.primaryResourceType;
		if(typeID < 0)
			return;
		planetsByResource[typeID].markUsed(pl, purpose);
		optimizePlanetImports(pl, getResource(typeID).level);
	}
	
	bool isKnownPlanet(Planet@ pl) {
		return knownPlanets.contains(pl.id);
	}
	
	void optimizePlanetImports(Planet@ pl, uint forLevel) {
		if(pl is null)
			return;
		array<Resource> avail;
		avail.syncFrom(pl.getAllResources());
		
		bool needWater = forLevel > 0;
		uint needFood = forLevel;
		if(isMachineRace) {
			needFood = 0;
			needWater = false;
		}
		uint needLevel1 = 0;
		uint needLevel2 = 0;
		switch(forLevel) {
			case 2:
				needLevel1 = 1;
				break;
			case 3:
				needLevel1 = isFrugal ? 1 : 2;
				needLevel2 = 1;
				break;
			case 4:
				needLevel1 = isFrugal ? 2 : 4;
				needLevel2 = 2;
				break;
			case 5:
				needLevel1 = isFrugal ? 4 : 6;
				needLevel2 = 4;
				break;
		}
		
		auto@ resFood = getResourceList(RT_Food);
		auto@ resWater = getResourceList(RT_Water);
		auto@ resLevelOne = getResourceList(RT_LevelOne);
		auto@ resLevelTwo = getResourceList(RT_LevelTwo);
		
		for(uint i = 0, cnt = avail.length; i < cnt; ++i) {
			auto@ res = avail[i];
			uint rid = res.type.id, rlevel = res.type.level;
			Object@ source = res.origin;
			if(!res.usable || (source !is null && source.owner !is empire))
				continue;

			bool needed = true;
			
			if(rlevel == 0 && resFood.find(rid) >= 0) {
				if(needFood == 0)
					needed = false;
				else
					needFood -= 1;
			}
			else if(rlevel == 0 && resWater.find(rid) >= 0) {
				if(!needWater)
					needed = false;
				else
					needWater = false;
			}
			else if(rlevel == 1 && resLevelOne.find(rid) >= 0) {
				if(needLevel1 == 0)
					needed = false;
				else
					needLevel1 -= 1;
			}
			else if(rlevel == 2 && resLevelTwo.find(rid) >= 0) {
				if(needLevel2 == 0)
					needed = false;
				else
					needLevel2 -= 1;
			}
			
			if(source !is null && source !is pl) {
				if(source.isPlanet) {
					auto@ src = cast<Planet>(source);
					if(needed)
						markPlanetUsed(src, pl);
					else {
						markPlanetIdle(src);
						src.exportResource(empire, 0, null);
					}
				}
				else if(source.isAsteroid) {
					auto@ src = cast<Asteroid>(source);
					if(needed)
						markAsteroidUsed(src);
					else {
						markAsteroidIdle(src);
						src.exportResource(empire, 0, null);
					}
				}
			}
		}
	}
	
	void usePlanetImports(Planet@ pl, int targetLevel = -1) {
		if(pl is null)
			return;
		array<Resource> avail;
		avail.syncFrom(pl.getAllResources());
		
		uint plLevel = targetLevel == -1 ? pl.level : uint(targetLevel);
		
		bool needWater = plLevel > 0;
		uint needFood = plLevel;
		if(isMachineRace) {
			needWater = false;
			needFood = 0;
		}
		uint needLevel1 = 0;
		uint needLevel2 = 0;
		switch(plLevel) {
			case 2:
				needLevel1 = 1;
				break;
			case 3:
				needLevel1 = 2;
				needLevel2 = 1;
				break;
			case 4:
				needLevel1 = 4;
				needLevel2 = 2;
				break;
			case 5:
				needLevel1 = 6;
				needLevel2 = 4;
				break;
		}
		
		auto@ resFood = getResourceList(RT_Food);
		auto@ resWater = getResourceList(RT_Water);
		auto@ resLevelOne = getResourceList(RT_LevelOne);
		auto@ resLevelTwo = getResourceList(RT_LevelTwo);
		
		for(uint i = 0, cnt = avail.length; i < cnt; ++i) {
			auto@ res = avail[i];
			uint rid = res.type.id, rlevel = res.type.level;
			Object@ source = res.origin;
			if(!res.usable || (source !is null && source.owner !is empire))
				continue;
			
			if(rlevel == 0 && resFood.find(rid) >= 0) {
				if(needFood == 0)
					continue;
				needFood -= 1;
			}
			else if(rlevel == 0 && resWater.find(rid) >= 0) {
				if(!needWater)
					continue;
				needWater = false;
			}
			else if(rlevel == 1 && resLevelOne.find(rid) >= 0) {
				if(needLevel1 == 0)
					continue;
				needLevel1 -= 1;
			}
			else if(rlevel == 2 && resLevelTwo.find(rid) >= 0) {
				if(needLevel2 == 0)
					continue;
				needLevel2 -= 1;
			}
			
			if(source !is null && source !is pl) {
				if(source.isPlanet) {
					auto@ src = cast<Planet>(source);
					markPlanetUsed(src, pl);
				}
				else if(source.isAsteroid) {
					auto@ src = cast<Asteroid>(source);
					markAsteroidUsed(src);
				}
			}
		}
	}
	
	void freePlanetImports(Planet@ pl) {
		array<Resource> avail;
		avail.syncFrom(pl.getAllResources());
		
		for(uint i = 0, cnt = avail.length; i < cnt; ++i) {
			Planet@ source = cast<Planet>(avail[i].origin);
			if(source !is null && source !is pl)
				markPlanetIdle(source);
		}
	}
	
	void addPlanet(Planet@ pl, Object@ purpose = null) {
		if(purpose is null)
			markPlanetIdle(pl, true);
		else
			markPlanetUsed(pl, purpose);
	}
	
	void removePlanet(Planet@ pl) {
		knownPlanets.erase(pl.id);
		int resType = pl.primaryResourceType;
		if(resType < 0)
			return;
		planetsByResource[resType].remove(pl);
	}
	
	uint nextFactoryRes = 0;
	void updateFactories() {
		auto@ list = planetsByResource[nextFactoryRes++ % planetsByResource.length];
		for(uint j = 0; j < 2; ++j) {
			auto@ planets = j == 0 ? list.idle : list.used;
			for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
				Planet@ pl = planets[i];
				if(pl.valid && pl.owner is empire && pl.laborIncome > 0 && !knownFactories.contains(pl.id)) {
					if(!isMachineRace || (pl.laborIncome * 60.0 > double(pl.population) + 0.05)) {
						knownFactories.insert(pl.id);
						factories.insertLast(pl);
					}
				}
			}
		}
		
		for(uint i = 0, cnt = orbitals.length; i < cnt; ++i) {
			Orbital@ orb = orbitals[i];
			if(orb.valid && orb.owner is empire && orb.hasConstruction && orb.laborIncome > 0 && !knownFactories.contains(orb.id)) {
				knownFactories.insert(orb.id);
				factories.insertLast(orb);
			}
		}
	}

	double getMaxFactoryLabor() {
		double labor = 0;
		for(uint i = 0, cnt = factories.length; i < cnt; ++i)
			labor = max(factories[i].laborIncome, labor);
		return labor;
	}
	
	void validateFactories() {
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			Object@ factory = factories[i];
			if(!factory.valid || !factory.hasConstruction || factory.laborIncome <= 0.000001 || factory.owner !is empire) {
				knownFactories.erase(factory.id);
				if(i + 1 < cnt)
					@factories[i] = factories[cnt-1];
				--cnt;
				factories.length = cnt;
			}
			else {
				++i;
			}
		}
	}

	//Check if the factory should be considered idle and we can give it build orders
	// - Handles asteroid construction being automatically shuffled to the end to prevent blocking things.
	bool isBuildIdle(Object@ factory) {
		uint count = factory.constructionCount;
		if(count == 0)
			return true;
		if(count == 1 && factory.constructionType == CT_Asteroid)
			return true;
		return false;
	}
	
	bool factoriesInRegion(Region@ reg) const {
		for(uint i = 0, cnt = factories.length; i < cnt; ++i)
			if(factories[i].region is reg)
				return true;
		return false;
	}
	
	void validateOrbitals() {
		for(uint i = 0, cnt = orbitals.length; i < cnt;) {
			Orbital@ factory = orbitals[i];
			if(!factory.valid || factory.owner !is empire) {
				if(i + 1 < cnt)
					@orbitals[i] = orbitals[cnt-1];
				--cnt;
				orbitals.length = cnt;
			}
			else {
				++i;
			}
		}
	}
	
	PlanRegion@ pickRandomSys(array<PlanRegion@>& systemList) {
		uint sysCount = systemList.length;
		if(sysCount == 0)
			return null;
		else
			return systemList[randomi(0,sysCount-1)];
	}

	void aiPing(Empire@ fromEmpire, vec3d position, uint type) {
		if(empire is fromEmpire || (fromEmpire.team != empire.team && empire.team != -1))
			return;
		if(fromEmpire.SubjugatedBy !is empire || empire.SubjugatedBy !is fromEmpire)
			return;
		
		Request req;
		@req.region = findNearestRegion(position);
		req.time = gameTime;
		
		Lock lock(reqLock);
		queuedRequests.insertLast(req);
	}
	
	void commandAI(string cmd) {
		if(cmd.substr(0,7) == "planet ") {
			string name = cmd.substr(7);
			for(uint i = 0, cnt = planetsByResource.length(); i < cnt; ++i) {
				auto@ list = planetsByResource[i].idle;
				for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
					if(list[j].name == name) {
						auto@ export = list[j].nativeResourceDestination[0];
						if(export is null)
							error(name + " is idle");
						else
							error(name + " is idle, but exporting to " + export.name);
						return;
					}
				}
				
				@list = planetsByResource[i].used;
				auto@ purpose = planetsByResource[i].purpose;
				for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
					if(list[j].name == name) {
						auto@ export = list[j].nativeResourceDestination[0];
						if(export is purpose[j])
							error(name + " is used for " + purpose[j].name);
						else
							error(name + " is used for " + purpose[j].name + " but is exporting to " + (export is null ? "nowhere" : export.name));
						return;
					}
				}
			}
			
			error("Could not locate planet");
		}
		else if(cmd == "planets") {
			for(uint i = 0, cnt = planetsByResource.length(); i < cnt; ++i) {
				auto@ list = planetsByResource[i].idle;
				for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
					auto@ pl = list[j];
					auto@ export = pl.nativeResourceDestination[0];
					if(export is null)
						error(pl.name + " is idle");
					else
						error(pl.name + " is idle, but exporting to " + export.name);
				}
				
				@list = planetsByResource[i].used;
				auto@ purpose = planetsByResource[i].purpose;
				for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
					auto@ pl = list[j];
					auto@ export = pl.nativeResourceDestination[0];
					if(export is purpose[j])
						error(pl.name + " is used for " + purpose[j].name);
					else
						error(pl.name + " is used for " + purpose[j].name + " but is exporting to " + (export is null ? "nowhere" : export.name));
				}
			}
		}
		else if(cmd == "idle") {
			error("Current idle actions:");
			for(uint i = 0; i < idle.length; ++i) {
				auto@ act = idle[i];
				error(act.hash + ": " + act.state);
			}
		}
		else if(cmd == "artifacts") {
			error("Known artifacts:");
			for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
				auto@ type = getArtifactType(i);
				if(artifacts[i] !is null)
					error(" " + type.name);
			}
		}
		else if(cmd == "fleets") {
			for(uint j = 0; j < 4; ++j) {
				FleetType type = FleetType(j);
				if(j == 2)
					type = FT_Mothership;
				else if(j == 3)
					type = FT_Slipstream;
				auto@ f = fleets[type];
				error("Fleets of type " + j + ":");
				for(uint i = 0, cnt = f.length; i < cnt; ++i) {
					auto@ ship = f[i];
					error("\t" + ship.name + " in " + (ship.region is null ? "empty space" : ship.region.name));
				}
			}
		}
		else if(cmd == "fix war") {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
				requestWar(getEmpire(i));
		}
		else if(cmd.substr(0,6) == "scout ") {
			auto@ sys = getSystem(cmd.substr(6));
			if(sys !is null) {
				for(uint i = 0, cnt = ourSystems.length; i < cnt; ++i) {
					if(ourSystems[i].region is sys.object) {
						ourSystems[i].scout(this, verbose=true);
						error("Scouted system");
						break;
					}
				}
			}
			else {
				error("Couldn't find system");
			}
		}
		else if(cmd.substr(0,9) == "artifact ") {
			string id = cmd.substr(9);
			auto@ art = getArtifact(getArtifactType(id));
			if(art !is null)
				error("Found artifact");
			else
				error("Found no artifact");
		}
		else if(cmd.substr(0,9) == "resource ") {
			string id = cmd.substr(9);
			auto@ res = getResource(id);
			if(res is null) {
				error("Invalid resource");
				return;
			}
			
			auto@ list = planetsByResource[res.id].idle;
			for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
				auto@ pl = list[j];
				auto@ export = pl.nativeResourceDestination[0];
				if(export is null)
					error(pl.name + " is idle");
				else
					error(pl.name + " is idle, but exporting to " + export.name);
			}
			
			@list = planetsByResource[res.id].used;
			auto@ purpose = planetsByResource[res.id].purpose;
			for(uint j = 0, jcnt = list.length; j < jcnt; ++j) {
				auto@ pl = list[j];
				auto@ export = pl.nativeResourceDestination[0];
				if(export is purpose[j])
					error(pl.name + " is used for " + purpose[j].name);
				else
					error(pl.name + " is used for " + purpose[j].name + " but is exporting to " + (export is null ? "nowhere" : export.name));
			}
		}
		else if(cmd.substr(0,5) == "diff ") {
			string newDiff = cmd.substr(5);
			toLowercase(newDiff);
			uint diff = 3;
			if(newDiff == "passive")
				diff = 0;
			else if(newDiff == "easy")
				diff = 1;
			else if(newDiff == "medium")
				diff = 2;
			else if(newDiff == "hard")
				diff = 3;
			else if(newDiff == "murderous")
				diff = 4;
			else if(newDiff == "cheating")
				diff = 5;
			else if(newDiff == "savage")
				diff = 6;
			else if(newDiff == "barbaric")
				diff = 7;
			else
				diff = toUInt(newDiff);
			
			changeDifficulty(diff);
		}
		else if(cmd == "log war") {
			if(!logWar) {
				makeDirectory(profileRoot + "/war_logs/");
				@log = WriteFile(profileRoot + "/war_logs/" + empire.name + ".txt");
				logWar = true;
			}
		}
		else if(cmd == "relations") {
			for(uint i = 0; i < relations.length; ++i) {
				auto@ rel = relations[i];
				auto@ emp = getEmpire(i);
				if(emp is null || emp is empire || !emp.valid)
					continue;
				error(emp.name + " = " + rel.standing);
			}
		}
		else {
			error("Unknown command");
		}
	}
	
	void debugAI() {
		debug = !debug;
	}
	
	PlanRegion@ markAsColony(Region@ region) {
		for(uint i = 0, cnt = exploredSystems.length; i < cnt; ++i) {
			Region@ reg = exploredSystems[i].region;
			if(reg is region) {
				auto@ pr = exploredSystems[i];
				ourSystems.insertLast(pr);
				exploredSystems.removeAt(i);
				for(uint i = 0, cnt = pr.artifacts.length; i < cnt; ++i)
					logArtifact(pr.artifacts[i]);
				timeSinceLastExpand = 0.0;
				return ourSystems.last;
			}
		}
		
		//Check for duplicates
		for(uint i = 0, cnt = ourSystems.length; i < cnt; ++i) {
			Region@ reg = ourSystems[i].region;
			if(reg is region)
				return ourSystems[i];
		}
		
		PlanRegion@ newRegion = findSystem(region);
		if(newRegion is null) {
			@newRegion = PlanRegion(region);
			systems.set(region.id, @newRegion);
		}
		
		for(uint i = 0, cnt = newRegion.artifacts.length; i < cnt; ++i)
			logArtifact(newRegion.artifacts[i]);
		
		knownSystems.insert(region.id);
		ourSystems.insertLast(newRegion);
		timeSinceLastExpand = 0.0;
		return newRegion;
	}

	PlanRegion@ getPlanRegion(Object@ focus) {
		Region@ area = focus.region;
		if(area is null) {
			@area = cast<Region>(focus);
			if(area is null)
				return null;
		}
		
		PlanRegion@ pr;
		systems.get(area.id, @pr);
		return pr;
	}
	
	bool knownSystem(Region@ region) const {
		return knownSystems.contains(region.id);
	}
	
	PlanRegion@ findSystem(Region@ region) const {
		PlanRegion@ pr;
		systems.get(region.id, @pr);
		return pr;
	}
	
	PlanRegion@ addExploredSystem(Region@ focus) {
		PlanRegion@ region = PlanRegion(focus);
		exploredSystems.insertLast(region);
		systems.set(focus.id, @region);
		knownSystems.insert(focus.id);
		return region;
	}
	
	void addExploredSystem(PlanRegion@ region) {
		exploredSystems.insertLast(region);
		systems.set(region.region.id, @region);
		knownSystems.insert(region.region.id);
	}
	
	uint nextVision = randomi(0,10000);
	void updateRandomVision() {
		for(uint i = 0; i < 5; ++i) {
			Region@ region = getSystem(nextVision++ % systemCount).object;
			if(region.VisionMask & empire.visionMask != 0) {
				auto@ plan = findSystem(region);
				if(plan is null)
					@plan = addExploredSystem(region);
				plan.scout(this);
				break;
			}
			else if(region.SeenMask & empire.mask != 0) {
				//We may have gained memory of the planets through various means
				auto@ plan = findSystem(region);
				if(plan is null) {
					@plan = PlanRegion(region);
					systems.set(region.id, @plan);
				}
				
				if(plan.useMemory(this) && !knownSystem(region))
					addExploredSystem(plan);
				break;
			}
		}
	}
	
	array<Ship@>@ get_fleets(FleetType type) {
		if(type == FT_Scout)
			return scoutFleets;
		else if(type == FT_Mothership)
			return motherships;
		else if(type == FT_Slipstream)
			return slipstreamers;
		else
			return combatFleets;
	}
	
	uint get_fleetTypeCount() const {
		return 4;
	}
	
	void freeFleet(Ship@ leader, FleetType type) {
		if(leader !is null && leader.valid && leader.owner is empire)
			fleets[type].insertLast(leader);
	}
	
	void removeInvalidFleets() {
		for(uint f = 0, fCnt = fleetTypeCount; f < fCnt; ++f) {
			FleetType type;
			switch(f) {
				case 0: type = FT_Scout; break;
				case 1: type = FT_Combat; break;
				case 2: type = FT_Mothership; break;
				case 3: type = FT_Slipstream; break;
			}
		
			array<Ship@>@ Fleets = fleets[type];
			for(int i = int(Fleets.length) - 1; i >= 0; --i) {
				Ship@ leader = Fleets[i];
				if(!leader.valid || leader.owner !is empire) {
					Fleets.removeAt(i);
					knownLeaders.erase(leader.id);
				}
			}
		}
	}
	
	Ship@ getAvailableFleet(FleetType type, bool build = true) {
		array<Ship@>@ Fleets = fleets[type];
		
		if(Fleets.length != 0) {
			Ship@ leader = Fleets.last;
			Fleets.removeLast();
			
			if(leader.valid && leader.owner is empire)			
				return leader;
			else
				return getAvailableFleet(type);
		}
		else {
			if(build)
				requestFleetBuild(type);
			return null;
		}
	}
	
	void logArtifact(Artifact@ artifact) {
		int type = artifact.ArtifactType;
		if(type >= 0 && artifacts[type] is null)
			@artifacts[type] = artifact;
	}
	
	Artifact@ getArtifact(const ArtifactType@ Type, Region@ availableTo = null) {
		if(Type is null)
			return null;

		Artifact@ artifact = artifacts[Type.id];
		if(artifact !is null && (!artifact.valid || artifact.region is null)) {
			@artifacts[Type.id] = null;
			@artifact = null;
		}
		
		if(artifact is null && ourSystems.length != 0) {
			SysSearch search;
			for(uint i = 0; i < 8; ++i) {
				auto@ region = ourSystems[randomi(0,ourSystems.length-1)];
				for(uint j = 0, cnt = region.artifacts.length; j < cnt; ++j) {
					if(region.artifacts[j].ArtifactType == int(Type.id)) {
						@artifact = region.artifacts[j];
						break;
					}
				}
			}
			
			@artifacts[Type.id] = artifact;
		}
		
		if(artifact !is null) {
			Region@ from = artifact.region;
			Territory@ fromTerr = from !is null ? from.getTerritory(empire) : null;
			if(fromTerr is null) {
				@artifacts[Type.id] = null;
				return null;
			}
			
			if(availableTo !is null && availableTo.getTerritory(empire) !is fromTerr)
				return null;
		}
		
		return artifact;
	}
	
	bool performAction(Action@ act) {
		if(act is null) {
			error("BasicAI Error: Unexpected null action.");
			::debug();
			return true;
		}
	
		//TODO: This leaks a reference? (if exist is not null)
		Action@ exist;
		if(actions.get(act.hash, @exist))
			@act = exist;
		if(act !is null) {
			if(debug) {
				dbgMsg += "\n ";
				for(int i = printDepth; i > 0; --i)
					dbgMsg += " ";
				dbgMsg += act.state;
			}
			++printDepth;
			
			if(printDepth >= 25) {
				error("AI Recursed too deep.");
				::debug();
				actions.delete(act.hash);
				removeIdle(act);
				return true;
			}
			
			double t = 0.0;
			if(profile)
				t = getExactTime();
		
			if(act.perform(this)) {
				--printDepth;
				if(profile && debug) {
					double e = getExactTime();
					dbgMsg += "\n ";
					for(int i = printDepth; i > 0; --i)
						dbgMsg += " ";
					dbgMsg += "Took " + int((e-t) * 1.0e6) + " us";
				}
				
				actions.delete(act.hash);
				removeIdle(act);
				return true;
			}
			else {
				--printDepth;
				if(profile && debug) {
					double e = getExactTime();
					dbgMsg += "\n ";
					for(int i = printDepth; i > 0; --i)
						dbgMsg += " ";
					dbgMsg += "Took " + int((e-t) * 1.0e6) + " us";
				}
				
				actions.set(act.hash, @act);
				return false;
			}
		}
		else {
			return true;
		}
	}
	
	Action@ locateAction(int64 hash) {
		Action@ act;
		actions.get(hash, @act);
		if(act is null) {
			int64 replace = 0;
			if(newHashes.get(hash, replace))
				return locateAction(replace);
		}
		return act;
	}
	
	void insertAction(Action@ act) {
		actions.set(act.hash, @act);
	}
	
	Action@ performKnownAction(Action@ act) {
		if(act is null)
			return null;
		
		if(debug) {
			dbgMsg += "\n ";
			for(int i = printDepth; i > 0; --i)
				dbgMsg += " ";
			dbgMsg += act.state;
		}
		++printDepth;
		
		if(printDepth >= 25) {
			error("AI Recursed too deep.");
			::debug();
			actions.delete(act.hash);
			removeIdle(act);
			return null;
		}
			
		double t = 0.0;
		if(profile)
			t = getExactTime();
		
		if(act.perform(this)) {
			--printDepth;
			if(profile && debug) {
				double e = getExactTime();
				dbgMsg += "\n ";
				for(int i = printDepth; i > 0; --i)
					dbgMsg += " ";
				dbgMsg += "Took " + int((e-t) * 1.0e6) + " us";
			}
			
			actions.delete(act.hash);
			removeIdle(act);
			return null;
		}
		else {
			--printDepth;
			if(profile && debug) {
				double e = getExactTime();
				dbgMsg += "\n ";
				for(int i = printDepth; i > 0; --i)
					dbgMsg += " ";
				dbgMsg += "Took " + int((e-t) * 1.0e6) + " us";
			}
			actions.set(act.hash, @act);
			return act;
		}
	}
	
	const Design@ getDesign(DesignType type, uint task, bool create = true) {
		if(type == DT_Flagship) {
			if(task == FST_Mothership)
				return empire.getDesign("Mothership");
			else if(task == FST_Slipstream)
				return empire.getDesign("Slipstream Generator");
		}
	
		if(create) {
			Action@ act = locateAction( designHash(type, task) );
			if(act is null)
				@act = MakeDesign(type, task);
			performKnownAction( act );
		}
		
		switch(type) {
			case DT_Support:
				if(task < ST_COUNT)
					return dsgSupports[task];
				break;
			case DT_Flagship:
				if(task < FST_COUNT)
					return dsgFlagships[task];
				break;
			case DT_Station:
				if(task < STT_COUNT)
					return dsgStations[task];
				break;
		}
		return null;
	}
	
	bool fillFleet(Object@ fleet, int maxSpend = -1) {
		if(!fleet.hasLeaderAI)
			return true;
		uint supports = fleet.SupplyAvailable;
		if(supports == 0)
			return true;
		fleet.clearAllGhosts();
		
		//Can't afford anything, probably not any time soon either
		if(empire.RemainingBudget < -250 && empire.TotalBudget < -150)
			return true;
			
		const Design@ hvy, lit, tnk, fill;
		@hvy = getDesign(DT_Support, ST_AntiFlagship);
		if(hvy is null)
			@hvy = empire.getDesign("Heavy Gunship");
		@lit = getDesign(DT_Support, ST_AntiSupport);
		if(lit is null)
			@lit = empire.getDesign("Beamship");
		@tnk = getDesign(DT_Support, ST_Tank);
		if(tnk is null)
			@tnk = empire.getDesign("Missile Boat");
		@fill = getDesign(DT_Support, ST_Filler);
		if(fill is null)
			@fill = empire.getDesign("Gunship");
		
		uint heavy = (supports / 3) / uint(hvy.size);
		uint light = (supports / 2) / uint(lit.size);
		uint tank = (supports / 8) / uint(tnk.size);
		uint filler = (supports - (heavy * uint(hvy.size) + light * uint(lit.size) + tank * uint(tnk.size))) / uint(fill.size);
		
		if(heavy + light + tank + filler == 0)
			return true;
		
		if(maxSpend >= 0) {
			int cost = hvy.total(HV_BuildCost);
			if(cost < maxSpend) {
				heavy = min(heavy, uint(maxSpend/cost));
				maxSpend -= int(heavy * cost);
			}
			
			cost = lit.total(HV_BuildCost);
			if(cost < maxSpend) {
				light = min(light, uint(maxSpend/cost));
				maxSpend -= int(light * cost);
			}
			
			cost = tnk.total(HV_BuildCost);
			if(cost < maxSpend) {
				tank = min(tank, uint(maxSpend/cost));
				maxSpend -= int(tank * cost);
			}
			
			cost = fill.total(HV_BuildCost);
			if(cost < maxSpend) {
				filler = min(filler, uint(maxSpend/cost));
				maxSpend -= int(filler * cost);
			}
		}
		
		if(heavy > 0)
			fleet.orderSupports(hvy, heavy);
		if(light > 0)
			fleet.orderSupports(lit, light);
		if(tank > 0)
			fleet.orderSupports(tnk, tank);
		if(filler > 0)
			fleet.orderSupports(fill, filler);
		return false;
	}
	
	Action@ requestFleetBuild(FleetType type) {
		Action@ act = locateAction( buildFleetHash(type) );
		if(act is null)
			@act = BuildFleet(type);
		return performKnownAction( act );
	}
	
	Action@ requestOrbital(Region& where, OrbitalType type) {
		Action@ act = locateAction( buildOrbitalHash(where, type) );
		if(act is null)
			@act = BuildOrbital(where, type);
		return performKnownAction( act );
	}
	
	Action@ requestCombatAt(Object@ system) {
		Action@ act = locateAction( buildCombatHash(system.id) );
		if(act is null)
			@act = Combat(system);
		return performKnownAction( act );
	}
	
	Action@ requestWar(Empire@ target) {
		Action@ act = locateAction( buildWarHash(target) );
		if(act is null)
			@act = War(target);
		return performKnownAction( act );
	}
	
	Action@ requestImport(Planet@ pl, array<int>@ resources, bool execute = true) {
		Action@ act = locateAction( importResHash(pl, resources) );
		if(act is null)
			@act = ImportResource( pl, resources);
		if(execute)
			return performKnownAction( act );
		else {
			insertAction( act );
			return act;
		}
	}
	
	Action@ requestPlanetImprovement(Planet@ pl, uint toLevel) {
		Action@ act = locateAction( improvePlanetHash(pl, toLevel) );
		if(act is null)
			@act = ImprovePlanet( pl, toLevel);
		return performKnownAction( act );
	}
	
	Action@ requestBuilding(Planet& pl, const BuildingType& type, bool force = false) {
		Action@ act = locateAction( buildBuildingHash(pl, type) );
		if(act is null)
			@act = BuildBuilding( pl, type, force );
		return performKnownAction( act );
	}
	
	Action@ colonizeByResource(array<int>@ resources, ObjectReceiver@ inform = null, bool execute = true) {
		Action@ act = locateAction( colonyByResHash(resources) );
		if(act is null)
			@act = ColonizeByResource( resources, inform );
		if(execute)
			return performKnownAction( act );
		else {
			insertAction( act );
			return act;
		}
	}
	
	Action@ requestColony(Planet@ pl, bool execute = true) {
		Action@ act = locateAction( colonyHash(pl) );
		if(act is null)
			@act = Colonize(this, pl);
		if(execute)
			return performKnownAction( act );
		else {
			insertAction( act );
			return act;
		}
	}
	
	Action@ requestPopulate(Planet@ pl, bool execute = true) {
		Action@ act = locateAction( populateHash(pl) );
		if(act is null)
			@act = Populate(this, pl);
		if(execute)
			return performKnownAction( act );
		else {
			insertAction( act );
			return act;
		}
	}
	
	Action@ requestExpansion() {
		Action@ act = locateAction( expandHash() );
		if(act is null)
			@act = Expand();
		return performKnownAction( act );
	}
	
	Action@ requestExploration() {
		Action@ act = locateAction( exploreHash() );
		if(act is null)
			@act = Explore();
		return performKnownAction( act );
	}
	
	Action@ requestDefense() {
		Action@ act = locateAction( defendHash() );
		if(act is null)
			@act = Defend();
		return performKnownAction( act );
	}
	
	Action@ requestBudget() {
		Action@ act = locateAction( budgetHash() );
		if(act is null)
			@act = GatherBudget();
		return performKnownAction( act );
	}
	
	void removeIdle(Action& act) {
		if(idles.contains(act.hash)) {
			idles.erase(act.hash);
			//if(idle.find(@act) < 0)
			//	::debug();
			idle.remove(@act);
		}
	}
	
	void addIdle(Action@ act) {
		if(act is null)
			return;
		
		if(!idles.contains(act.hash)) {
			idle.insertLast(@act);
			idles.insert(act.hash);
			if(debug)
				error("Adding idle action: " + act.state);
		}
		//else if(idle.find(@act) < 0) {
		//	::debug();
		//}
	}
	
	void addNewIdle(Action& act) {
		insertAction(act);
		addIdle(act);
	}
	
	void changeDifficulty(uint level) {
		int prevCheatedResources = cheatLevel;
		cheatLevel = 0;
		
		cheatFlags = 0;
		behaviorFlags = 0;
		
		//$ -> Influence
		empire.WelfareMode = 0;
		
		if(level > 7)
			level = 7;
	
		switch(level) {
			case 0: //Passive
				skillEconomy = DIFF_Easy;
				skillCombat = DIFF_Trivial;
				skillDiplo = DIFF_Easy;
				skillTech = DIFF_Easy;
				skillScout = DIFF_Easy;
				behaviorFlags = AIB_IgnorePlayer | AIB_IgnoreAI;
				break;
			case 1: //Easy
				skillEconomy = DIFF_Easy;
				skillCombat = DIFF_Easy;
				skillDiplo = DIFF_Easy;
				skillTech = DIFF_Easy;
				skillScout = DIFF_Easy;
				break;
			case 2: //Medium
				skillEconomy = DIFF_Medium;
				skillCombat = DIFF_Medium;
				skillDiplo = DIFF_Medium;
				skillTech = DIFF_Medium;
				skillScout = DIFF_Medium;
				break;
			case 3: //Hard
				skillEconomy = DIFF_Hard;
				skillCombat = DIFF_Hard;
				skillDiplo = DIFF_Hard;
				skillTech = DIFF_Hard;
				skillScout = DIFF_Hard;
				break;
			case 4: //Murderous
				skillEconomy = DIFF_Hard;
				skillCombat = DIFF_Hard;
				skillDiplo = DIFF_Hard;
				skillTech = DIFF_Hard;
				skillScout = DIFF_Hard;
				behaviorFlags = AIB_IgnoreAI | AIB_QuickToWar;
				break;
			case 5: //Cheating
				skillEconomy = DIFF_Max;
				skillCombat = DIFF_Max;
				skillDiplo = DIFF_Max;
				skillTech = DIFF_Max;
				skillScout = DIFF_Max;
				cheatFlags = AIC_Vision | AIC_Resources;
				cheatLevel = 10;
		
				//$ -> Labor
				empire.WelfareMode = 3;
				break;
			case 6: //Savage
				skillEconomy = DIFF_Max;
				skillCombat = DIFF_Max;
				skillDiplo = DIFF_Max;
				skillTech = DIFF_Max;
				skillScout = DIFF_Max;
				behaviorFlags = AIB_IgnoreAI | AIB_QuickToWar;
				cheatFlags = AIC_Vision | AIC_Resources;
				cheatLevel = 11;
		
				//$ -> Labor
				empire.WelfareMode = 3;
				break;
			case 7: //Barbaric
				skillEconomy = DIFF_Max;
				skillCombat = DIFF_Max;
				skillDiplo = DIFF_Max;
				skillTech = DIFF_Max;
				skillScout = DIFF_Max;
				cheatFlags = AIC_Vision | AIC_Resources;
				cheatLevel = 12;
		
				//$ -> Labor
				empire.WelfareMode = 3;
				break;
		}
		
		if(cheatFlags & AIC_Vision != 0)
			empire.visionMask = ~0;
		else
			empire.visionMask = empire.mask;
		
		if(cheatLevel != prevCheatedResources) {
			double factor = double(cheatLevel - prevCheatedResources);
			double tiles = double(cheatLevel - prevCheatedResources) * 3.0;
			
			empire.modFTLCapacity(125.0 * factor);
			empire.modFTLIncome(0.5 * factor);
			empire.modEnergyIncome(TILE_ENERGY_RATE * double(tiles) / 2.0);
			empire.modTotalBudget(int(TILE_MONEY_RATE * tiles));
			empire.modResearchRate(TILE_RESEARCH_RATE * double(tiles));
		}
	}

	void init(Empire& emp, EmpireSettings& settings) {
		@empire = emp;
		buildCommonLists();
		
		changeDifficulty(settings.difficulty);
	}
	
	void init(Empire& emp) {
		@empire = emp;
		buildCommonLists();
		addNewIdle(ExpendResources());
		addNewIdle(ManageFactories());
		addNewIdle(ManagePressureResources());
		addNewIdle(createDiplomacyAI(this));
		
		Planet@ hw = emp.Homeworld;
		if(hw !is null && hw.valid && hw.owner is emp) {
			@homeworld = hw;
			addPlanet(hw, hw);
		}
		
		if(hw !is null)
			focus = hw.position;
		
		if(head is null) {
			@head = MilitaryVictory();
			insertAction(head);
		}
	
		uint objects = emp.objectCount;
		for(uint i = 0; i < objects; ++i) {
			Object@ obj = emp.objects[i];
			
			switch(obj.type) {
				case OT_Planet: {
					Planet@ pl = cast<Planet>(obj);
					markAsColony(pl.region).scout(this);
					
					if(homeworld is null) {
						@homeworld = pl;
						addPlanet(pl, pl);
					}
				} break;
				case OT_Ship: {
					Ship@ ship = cast<Ship>(obj);
					if(ship.hasLeaderAI) {
						uint type = classifyDesign(this, ship.blueprint.design);
						if(type != FT_INVALID) {
							freeFleet(ship, FleetType(type));
							if(type == FT_Mothership)
								factories.insertLast(ship);
						}
					}
				} break;
			}
		}
	}

	void save(SaveFile& msg) {
		msg << empire;
		msg << homeworld;
		
		msg << willpower;
		
		msg << skillEconomy;
		msg << skillCombat;
		msg << skillDiplo;
		msg << skillTech;
		msg << skillScout;
		
		msg << behaviorFlags;
		msg << cheatFlags;
		msg << cheatLevel;
		
		msg << timeSinceLastExpand;
		
		msg << nextNotification;
		
		for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
			auto@ rel = relations[i];
			msg << rel.standing;
			msg << rel.bordered;
			msg << rel.allied;
			msg << rel.war;
			msg << rel.brokeAlliance;
			msg << rel.relStrength;
			msg << int(rel.lastOffense);
			msg << rel.offenseTime;
		}

		//System registry
		uint cnt = ourSystems.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			ourSystems[i].save(msg);

		cnt = exploredSystems.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			exploredSystems[i].save(msg);
		
		//Planet registry
		for(uint i = 0; i < planetsByResource.length; ++i)
			planetsByResource[i].save(msg);

		//Asteroid registry
		cnt = idleAsteroids.length;
		msg << cnt;
		for(uint i = 0, cnt = idleAsteroids.length; i < cnt; ++i)
			msg << idleAsteroids[i];

		cnt = usedAsteroids.length;
		msg << cnt;
		for(uint i = 0, cnt = usedAsteroids.length; i < cnt; ++i)
			msg << usedAsteroids[i];
		
		//Orbital registry
		cnt = orbitals.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << orbitals[i];
		
		//Artifact registry
		{
			Artifact@ artifact = null;
			for(uint i = 0; i < artifacts.length; ++i) {
				@artifact = artifacts[i];
				if(artifact !is null)
					msg << artifact;
			}
			
			@artifact = null;
			msg << artifact;
		}

		//Fleet registry
		cnt = scoutFleets.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << scoutFleets[i];

		cnt = combatFleets.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << combatFleets[i];

		cnt = motherships.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << motherships[i];
		
		cnt = slipstreamers.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << slipstreamers[i];
		msg << lastSlipstream;

		cnt = untrackedFleets.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << untrackedFleets[i];
			
		//Design types
		for(uint i = 0; i < ST_COUNT; ++i)
			msg << dsgSupports[i];
		for(uint i = 0; i < FST_COUNT; ++i)
			msg << dsgFlagships[i];
		for(uint i = 0; i < STT_COUNT; ++i)
			msg << dsgStations[i];
		
		//Revenant parts (owned by others)
		cnt = revenantParts.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << revenantParts[i];
		
		//Treaty responses
		cnt = queuedTreatyJoin.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << queuedTreatyJoin[i];
			
		cnt = queuedTreatyDecline.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << queuedTreatyDecline[i];

		//Actions
		map_iterator it = actions.iterator();

		int64 hash = 0;
		Action@ act;

		msg << actions.getSize();
		while(it.iterate(hash, @act)) {
			msg << hash;
			msg << uint(act.actionType);
			act.save(this, msg);
		}

		msg << head.hash;
		
		cnt = idle.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << idle[i].hash;

		msg << thoughtCycle;
		msg << diplomacyTick;
	}

	map newHashes;
	void load(SaveFile& msg) {
		msg >> empire;
		msg >> homeworld;
		
		buildCommonLists();
		
		if(msg >= SV_0063)
			msg >> willpower;
		
		msg >> skillEconomy;
		msg >> skillCombat;
		msg >> skillDiplo;
		msg >> skillTech;
		msg >> skillScout;
		
		if(msg >= SV_0046) {
			msg >> behaviorFlags;
			msg >> cheatFlags;
			msg >> cheatLevel;
		}
		
		if(msg >= SV_0079)
			msg >> timeSinceLastExpand;
		
		if(msg >= SV_0016)
			msg >> nextNotification;
		
		if(msg >= SV_0131) {
			for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
				auto@ rel = relations[i];
				msg >> rel.standing;
				msg >> rel.bordered;
				msg >> rel.allied;
				msg >> rel.war;
				msg >> rel.brokeAlliance;
				msg >> rel.relStrength;
				int offense = 0;
				msg >> offense;
				rel.lastOffense = RecentAction(offense);
				msg >> rel.offenseTime;
			}
		}

		//System registry
		uint cnt = 0;
		msg >> cnt;
		ourSystems.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			PlanRegion@ reg = PlanRegion(msg); 
			@ourSystems[i] = reg;
			systems.set(reg.region.id, @reg);
			knownSystems.insert(reg.region.id);
		}

		msg >> cnt;
		exploredSystems.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			PlanRegion@ reg = PlanRegion(msg); 
			@exploredSystems[i] = reg;
			systems.set(reg.region.id, @reg);
			knownSystems.insert(reg.region.id);
		}
		
		//Planet registry
		for(uint i = 0, cnt = msg.getPrevIdentifierCount(SI_Resource); i < cnt; ++i) {
			uint newIndex = msg.getIdentifier(SI_Resource, i);
			if(newIndex < planetsByResource.length) {
				planetsByResource[newIndex].load(this, msg);
			}
			else {
				PlanetList list;
				list.load(this, msg);
			}
		}

		//Asteroid registry
		if(msg >= SV_0128) {
			msg >> cnt;
			for(uint i = 0; i < cnt; ++i) {
				Asteroid@ rock;
				msg >> rock;
				if(rock !is null) {
					idleAsteroids.insertLast(rock);
					knownAsteroids.insert(rock.id);
				}
			}

			msg >> cnt;
			for(uint i = 0; i < cnt; ++i) {
				Asteroid@ rock;
				msg >> rock;
				if(rock !is null) {
					usedAsteroids.insertLast(rock);
					knownAsteroids.insert(rock.id);
				}
			}
		}
		
		//Orbital registry
		if(msg >= SV_0051) {
			msg >> cnt;
			orbitals.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> orbitals[i];
		}
		
		//Artifact registry
		if(msg >= SV_0036) {
			Artifact@ artifact;
			msg >> artifact;
			while(artifact !is null) {
				logArtifact(artifact);
				msg >> artifact;
			}
		}

		//Fleet registry
		msg >> cnt;
		scoutFleets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> scoutFleets[i];

		msg >> cnt;
		combatFleets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> combatFleets[i];
		
		if(msg >= SV_0114) {
			msg >> cnt;
			motherships.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> motherships[i];
		}
		
		if(msg >= SV_0130) {
			msg >> cnt;
			slipstreamers.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> slipstreamers[i];
			msg >> lastSlipstream;
		}
		
		if(msg >= SV_0016) {
			msg >> cnt;
			untrackedFleets.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> untrackedFleets[i];
		}
		
		//Design types
		if(msg >= SV_0081) {
			for(uint i = 0; i < ST_COUNT; ++i)
				msg >> dsgSupports[i];
			uint count = FST_COUNT;
			if(msg < SV_0119)
				count = FST_COUNT_OLD1;
			else if(msg < SV_0130)
				count = FST_COUNT_OLD2;
			for(uint i = 0; i < count; ++i)
				msg >> dsgFlagships[i];
			for(uint i = 0; i < STT_COUNT; ++i)
				msg >> dsgStations[i];
		}
		
		//Revenant parts (owned by others)
		if(msg >= SV_0087) {
			msg >> cnt;
			revenantParts.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> revenantParts[i];
		}
		
		//Treaty responses
		if(msg >= SV_0100) {
			msg >> cnt;
			queuedTreatyJoin.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> queuedTreatyJoin[i];
				
			msg >> cnt;
			queuedTreatyDecline.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> queuedTreatyDecline[i];
		}

		//Actions
		int64 hash = 0;
		Action@ act;

		msg >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> hash;
			uint type = 0;
			msg >> type;

			switch(type) {
				case ACT_Colonize:
					@act = Colonize(this, msg);
				break;
				case ACT_ColonizeRes:
					@act = ColonizeByResource(this, msg);
				break;
				case ACT_Explore:
					@act = Explore(this, msg);
				break;
				case ACT_Build:
					@act = BuildFleet(this, msg);
				break;
				case ACT_Trade:
					@act = ImportResource(this, msg);
				break;
				case ACT_Improve:
					@act = ImprovePlanet(this, msg);
				break;
				case ACT_Budget:
					@act = GatherBudget(this, msg);
				break;
				case ACT_Expend:
					@act = ExpendResources(this, msg);
				break;
				case ACT_Combat:
					@act = Combat(this, msg);
				break;
				case ACT_War:
					@act = War(this, msg);
				break;
				case ACT_Defend:
					@act = Defend(this, msg);
				break;
				case ACT_Expand:
					@act = Expand(this, msg);
				break;
				case ACT_Building:
					@act = BuildBuilding(this, msg);
				break;
				case ACT_BuildOrbital:
					@act = BuildOrbital(this, msg);
				break;
				case ACT_Design:
					@act = MakeDesign(this, msg);
				break;
				case ACT_Populate:
					@act = Populate(this, msg);
				break;
				case ACT_Diplomacy:
					@act = loadDiplomacyAI(this, msg);
				break;
				case ACT_ManageFactories:
					@act = ManageFactories(this, msg);
				break;
				case ACT_ManagePressureResources:
					@act = ManagePressureResources(this, msg);
				break;
				case STRAT_Military:
					@act = MilitaryVictory(this, msg);
				break;
				case STRAT_Influence:
					@act = InfluenceVictory(this, msg);
				break;
			}

			if(act !is null) {
				//Hashes may need to change.
				//When they do, the AI may forget some things it was doing,
				// but that is preferable to other issues that may arise (e.g. freezes)
				if(act.hash == hash)
					actions.set(hash, @act);
				else {
					newHashes.set(hash, act.hash);
					actions.set(act.hash, @act);
				}
			}
			else {
				error("Could not find action: " + uint64(hash) + " (" + (hash >> ACT_BIT_OFFSET) + ")");
			}
		}

		map_iterator it = actions.iterator();
		while(it.iterate(hash, @act))
			act.postLoad(this);

		int64 headHash = 0;
		msg >> headHash;
		@head = locateAction(headHash);
		if(head is null) {
			error("Couldn't find head: " + uint64(headHash));
			@head = MilitaryVictory();
			insertAction(head);
		}
		
		if(msg < SV_0021) {
			addNewIdle(ExpendResources());
			addNewIdle(ManageFactories());
			addNewIdle(ManagePressureResources());
		}
		else {
			msg >> cnt;
			int64 h = 0;
			
			for(uint i = 0; i < cnt; ++i) {
				msg >> h;
				Action@ act = locateAction(h);
				if(act !is null) {
					idle.insertLast(act);
					idles.insert(h);
				}
				else {
					error("Couldn't locate idle action: " + uint64(h));
					error("Action Type: " + uint64(h >> ACT_BIT_OFFSET));
				}
			}
		}
		
		newHashes.deleteAll();

		msg >> thoughtCycle;
		msg >> diplomacyTick;
	}
	
	double diplomacyTick = 0.0;
	
	void validatePlanets() {
		WaitForSafeCalls wait(false);
		int resourceID = randomi(0, planetsByResource.length - 1);
		PlanetList@ list = planetsByResource[resourceID];
		
		for(uint i = 0; i < 3 && list.used.length + list.idle.length == 0; ++i) {
			resourceID = randomi(0, planetsByResource.length - 1);
			@list = planetsByResource[resourceID];
		}
		
		list.validate(this, empire, getResource(resourceID));

		if(usedAsteroids.length > 0) {
			uint index = randomi(0, usedAsteroids.length-1);
			Asteroid@ roid = usedAsteroids[index];
			if(!roid.valid || roid.owner !is empire) {
				removeAsteroid(roid);
			}
			else if(randomi(0,10) == 0 && roid.primaryResourceExported) {
				Object@ dest = roid.nativeResourceDestination[0];
				if(dest is null || !dest.valid || dest.owner !is empire)
					markAsteroidIdle(roid);
			}
		}

		if(idleAsteroids.length > 0) {
			uint index = randomi(0, idleAsteroids.length-1);
			Asteroid@ roid = idleAsteroids[index];
			if(!roid.valid || roid.owner !is empire)
				removeAsteroid(roid);
		}
	}
	
	//Make sure we still own systems marked as ours
	void validateSystems() {
		if(ourSystems.length == 0)
			return;
		
		uint index = randomi(0, ourSystems.length-1);
		PlanRegion@ region = ourSystems[index];
		for(uint i = 0, cnt = region.planets.length; i < cnt; ++i)
			if(region.planets[i].owner is empire)
				return;
		
		ourSystems.removeAt(index);
		exploredSystems.insertLast(region);
	}
	
	array<int> queuedTreatyJoin, queuedTreatyDecline;
	double nextConsideration = gameTime + randomd(8.0, 22.0);
	bool checkJoin = true;
	
	void processTreatyQueue() {
		if(queuedTreatyJoin.length + queuedTreatyDecline.length == 0) {
			nextConsideration = gameTime + randomd(6.0, 16.0);
		}
		else if(gameTime > nextConsideration) {
			nextConsideration = gameTime + randomd(2.0, 8.0);
			checkJoin = !checkJoin;
			
			if(queuedTreatyJoin.length > 0 && checkJoin) {
				uint index = randomi(0, queuedTreatyJoin.length-1);
				joinTreaty(empire, queuedTreatyJoin[index]);
				queuedTreatyJoin.removeAt(index);
			}
			else if(queuedTreatyDecline.length > 0) {
				uint index = randomi(0, queuedTreatyDecline.length-1);
				declineTreaty(empire, queuedTreatyDecline[index]);
				queuedTreatyDecline.removeAt(index);
			}
		}
	}
	
	set_int callOuts;
	array<Notification@> notices;
	void getNotifications() {
		uint latest = empire.notificationCount;
		if(latest == nextNotification)
			return;
		receiveNotifications(notices, empire.getNotifications(20, nextNotification, false));
		nextNotification = latest;
		
		for(uint i = 0, cnt = notices.length; i < cnt; ++i) {
			auto@ notice = notices[i];
			switch(notice.type) {
				case NT_FlagshipBuilt:
					{
						Ship@ ship = cast<Ship>(notice.relatedObject);
						if(ship !is null && ship.owner is empire && !knownLeaders.contains(ship.id)) {
							knownLeaders.insert(ship.id);
							untrackedFleets.insertLast(ship);
						}
					} break;
				case NT_StructureBuilt:
					{
						Planet@ pl = cast<Planet>(notice.relatedObject);
						if(pl !is null && pl.owner is empire)
							optimizePlanetImports(pl, pl.nativeResourceDestination[0] is null ? min(pl.level+1, 4) : max(pl.resourceLevel, getResource(pl.primaryResourceType).level));
					} break;
				case NT_TreatyEvent:
					{
						TreatyEventNotification@ evt = cast<TreatyEventNotification>(notice);
						if(evt.eventType == TET_Invite) {
							double t = treatyWaits[evt.empOne.index];
							if(gameTime + randomd(5.0,120.0) < t) {
								queuedTreatyDecline.insertLast(evt.treaty.id);
								getRelation(evt.empOne).standing -= 1;
								break;
							}
							
							treatyWaits[evt.empOne.index] = gameTime + randomd(120.0,240.0);
						}
							
						if(evt.treaty.leader !is null) {
							//Ignore constant requests
							
							if(evt.eventType == TET_Invite && evt.treaty.hasClause("SubjugateClause")) {
								//Get the approximate point ratio. We add a small value to both points to reduce the noise of very small point values
								float pointRatio = float(evt.empOne.points.value + 200) / float(empire.points.value + 200);
								float reqRatio = (empire.isHostile(evt.empOne) && evt.empOne.MilitaryStrength > empire.MilitaryStrength) ? 3.f : 4.f;
								reqRatio *= pow(0.5f, -willpower / float(empire.TotalPlanets.value + 1));
								
								if(pointRatio > reqRatio)
									queuedTreatyJoin.insertLast(evt.treaty.id);
								else
									queuedTreatyDecline.insertLast(evt.treaty.id);
								break;
							}
						}
						else {
							if(evt.eventType == TET_Invite && evt.treaty.hasClause("SubjugateClause")) {
								//Someone wants to surrender, accept
								queuedTreatyJoin.insertLast(evt.treaty.id);
								break;
							}
						}
						
						if(evt.eventType == TET_Invite) {
							bool defense = evt.treaty.hasClause("MutualDefenseClause");
							//bool trade = evt.treaty.hasClause("TradeClause");
							bool vision = evt.treaty.hasClause("VisionClause");
							bool alliance = evt.treaty.hasClause("AllianceClause");
							
							double basis = -1.0;
							if(alliance && enemies.length > 0)
								basis += double(enemies.length);
							if(defense)
								basis += double(evt.empOne.MilitaryStrength - empire.MilitaryStrength);
							if(evt.empOne.isHostile(empire))
								basis -= 1.0;
						
							basis += double(getRelation(evt.empOne).standing) / 100.0;
							
							double chance = 0.5; pow(0.5, -basis);
							if(basis > 0)
								chance = 1.0 - pow(chance, 1.0 + basis);
							else if(basis < 0)
								chance = pow(chance, 1.0 - basis);
							
							if((defense || alliance) && behaviorFlags & AIB_QuickToWar != 0)
								chance = 0.0;
							
							if(randomd() < chance) {
								getRelation(evt.empOne).standing += 5;
								queuedTreatyJoin.insertLast(evt.treaty.id);
							}
							else {
								getRelation(evt.empOne).standing -= 1;
								queuedTreatyDecline.insertLast(evt.treaty.id);
							}
						}
					} break;
				case NT_Vote:
					{
						VoteNotification@ evt = cast<VoteNotification>(notice);
						if(evt.type == IVET_Start) {
							if(evt.vote.startedBy !is empire && isTargetOf(this, evt.vote, empire)) {
								auto@ rel = getRelation(evt.vote.startedBy);
								rel.standing -= 5;
								rel.offense = RA_Influence;
							}
						}
						else if(evt.type == IVET_Card) {
							auto@ c = evt.event.cardEvent;
							auto@ card = c.card;
							if(card.owner !is empire) {
								int stance = 0;
								auto@ starter = evt.vote.startedBy;
								if(starter is empire)
									stance = 2;
								else if(starter.ForcedPeaceMask & empire.mask != 0 || getRelation(starter).standing > 30)
									stance = 1;
								else if(empire.isHostile(starter))
									stance = -2;
								else if(getRelation(starter).standing < -30)
									stance = -1;
								
								//Nature of the card (+ good, - bad)
								int nature = 0;
								auto@ targs = card.targets;
								
								if(card.type.ident == "Rider") {
									nature = -1;
								}
								else if(card.type.ident == "Hedge") {
									nature = 1;
								}
								else if(card.type.ident == "Rush") {
									nature = 1;
								}
								else if(card.type.ident == "CallOut") {
									auto@ t = targs.get("Empire");
									if(t !is null && t.emp is empire) {
										//We need to track when we've been called out (yo)
										callOuts.insert(evt.vote.id);
										
										int rel = (getRelation(card.owner).standing - 15) / 10;
										if(rel > 0)
											nature = 1;
										else if(rel < 0)
											nature = -1;
									}
								}
								else if(card.type.cls == ICC_Support) {
									//Base whether the card is good/bad off the side it was targeted against
									auto@ t = targs.get("VoteSide");
									if(t !is null)
										nature = t.side ? 2 : -2;
								}
								
								int response = 0;
								if((stance > 0 && nature > 0) || (stance < 0 && nature < 0))
									response = abs(nature);
								else
									response = -abs(nature);
								
								if(response != 0) {
									auto@ rel = getRelation(card.owner);
									rel.standing += response * 2;
								}
							}
						}
					} break;
				case NT_Card:
					{
						CardNotification@ evt = cast<CardNotification>(notice);
					} break;
				case NT_Donation:
					{
						DonationNotification@ evt = cast<DonationNotification>(notice);
						int value = 0;
						switch(evt.offer.type) {
							case DOT_Money:
								value = clamp(evt.offer.value / double(empire.TotalBudget), 0.0, 1.0) * 15.0;
								break;
							case DOT_Energy:
								value = clamp(evt.offer.value / 1500.0, 0.0, 1.0) * 15.0;
								break;
							case DOT_Card:
								value = 2;
								break;
							case DOT_Fleet:
								value = 2;
								break;
							case DOT_Planet:
								value = 5;
								break;
							case DOT_Artifact:
								value = 1;
								break;
						}
						
						if(skillDiplo < DIFF_Medium)
							value += 1;
						
						if(value != 0) {
							auto@ rel = getRelation(evt.fromEmpire);
							rel.standing += value;
							if(value >= 5)
								rel.offense = RA_Donation;
						}
					} break;
				case NT_Generic:
					{
						GenericNotification@ evt = cast<GenericNotification>(notice);
						if(evt.obj !is null && evt.obj.isOrbital) {
							//Check to see if this is a revenant part
							Orbital@ part = cast<Orbital>(evt.obj);
							int core = part.coreModule;
							if(	core == getOrbitalModuleID("RevenantCore") ||
								core == getOrbitalModuleID("RevenantCannon") ||
								core == getOrbitalModuleID("RevenantChassis") ||
								core == getOrbitalModuleID("RevenantEngine") )
							{
								revenantParts.insertLast(part);
							}
						}
					} break;
			}
		}
		
		notices.length = 0;
	}

	double relationTick = randomd(0.0,60.0);
	void tick(Empire& emp, double time) {
		//Copy queued requests over, so we can access them quickly, and remove old requests
		for(int i = requests.length - 1; i >= 0; --i)
			if(requests[i].time < gameTime - 600.0)
				requests.removeAt(i);
		if(queuedRequests.length > 0) {
			Lock lock(reqLock);
			for(uint i = 0, cnt = queuedRequests.length; i < cnt; ++i)
				requests.insertLast(queuedRequests[i]);
			if(requests.length > 0 && protect is null)
				@protect = getPlanRegion(requests[0].region);
		}
		while(requests.length > 5)
			requests.removeAt(0);
	
		timeSinceLastExpand += time;
		didTickScan = false;
	
		profile = profile_ai.value > 0.0;
		double start = getExactTime();
	
		diplomacyTick += time;
		relationTick += time;
		
		if(diplomacyTick >= 2.0) {
			//Ticks happen at real time, so we compensate to make it behave similarly at all game speeds
			willpower *= pow(willDecayPerBudget,diplomacyTick * gameSpeed/180.0);
			diplomacyTick = 0.0;
		}
		
		if(relationTick >= 60.0) {
			uint borderMask = 0;
			auto@ border = getBorder();
			for(uint i = 0, cnt = border.length; i < cnt; ++i)
				borderMask |= border[i].planetMask;
			auto@ inner = ourSystems;
			for(uint i = 0, cnt = inner.length; i < cnt; ++i)
				borderMask |= inner[i].planetMask;
			
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				auto@ other = getEmpire(i);
				auto@ relation = getRelation(other);
				relation.standing -= relation.standing / 50;
				
				if(relation.lastOffense != RA_None && relation.offenseTime > gameTime - 180.0)
					if(relation.allied && relation.standing < -25)
						leaveTreatiesWith(emp, other.mask);
				
				relation.war = other.hostileMask & emp.mask != 0;
				relation.allied = other.ForcedPeaceMask.value & emp.mask != 0;
				relation.bordered = borderMask & other.mask != 0;
				relation.relStrength = other.MilitaryStrength - emp.MilitaryStrength;
				
				int goalStanding = 0;
				if(relation.war) {
					if(emp.MilitaryStrength >= other.MilitaryStrength)
						goalStanding = -50;
				}
				else {
					if(relation.allied)
						goalStanding = relation.brokeAlliance ? 15 : 60;
					
					if(relation.bordered)
						goalStanding -= 15;
					
					if(emp.MilitaryStrength < other.MilitaryStrength)
						goalStanding += 15;
					if(emp.points.value + 400 < other.points.value)
						goalStanding -= 5;
				}
				
				if(relation.standing > goalStanding)
					relation.standing -= 1;
				else if(relation.standing < goalStanding)
					relation.standing += skillDiplo < DIFF_Medium ? 3 : 2;
			}
			relationTick -= 60.0 + randomd(-5.0,5.0);
			
			auto@ emp = getEmpire(randomi(0, getEmpireCount()-1));
			if(emp.valid && emp !is empire && emp.major && !emp.isHostile(empire) && empire.ContactMask & emp.mask != 0 &&
				treatyWaits[emp.index] < gameTime && !isInTreatiesWith(empire, emp.mask))
			{
				//Consider sending a treaty
				auto@ rel = getRelation(emp);
				if(rel.standing >= 0) {
					uint clauses = 0;
					if(randomi(5,25) == 0)
						clauses |= TC_Trade;
					if(rel.standing > randomi(0,25))
						clauses |= TC_Vision;
					if(rel.standing > randomi(15,35))
						clauses |= TC_MutualDefense;
					if(rel.standing > randomi(15,60))
						clauses |= TC_Alliance;
					if(clauses != 0) {
						proposeTreaty(emp, clauses);
						treatyWaits[emp.index] = gameTime + randomd(120.0,180.0);
					}
				}
			}
		}
		
		getNotifications();
		removeInvalidFleets();
		validatePlanets();
		validateSystems();
		validateOrbitals();
		validateFactories();
		updateFactories();
		processTreatyQueue();
		for(int i = revenantParts.length-1; i >= 0; --i)
			if(revenantParts[i] is null || !revenantParts[i].valid)
				revenantParts.removeAt(i);
		
		//Check for new fleets that may have been given to us
		uint empFleets = empire.fleetCount;
		{
			if(empFleets > 0) {
				auto@ fleet = cast<Ship>(empire.fleets[randomi(0, empFleets-1)]);
				if(fleet !is null && fleet.valid && fleet.owner is empire && !knownLeaders.contains(fleet.id)) {
					knownLeaders.insert(fleet.id);
					auto@ design = fleet.blueprint.design;
					if((design is null || design.owner is empire) && gameTime > 5.0) {
						untrackedFleets.insertLast(fleet);
					}
					else {
						uint type = classifyDesign(this, design);
						if(type != FT_INVALID)
							freeFleet(fleet, FleetType(type));
					}
				}
			}
		}
		
		if(ourSystems.length == 0 && !(usesMotherships && empFleets > 0))
			return;
		
		double validateEnd = getExactTime();
		
		
		//Print depth is used both for debugging and tracking infinite recursion
		printDepth = 0;
		if(debug || profile)
			dbgMsg = empire.name + " {";
		
		if(validateEnd - start < maxAIFrame) {
			switch(thoughtCycle) {
				case 0:
					if(idle.length > 0) {
						performAction(idle[randomi(0, idle.length-1)]);
						break;
					}
				case 1:
					//Improve homeworld to level 4, then begin importing level 3 resources
					if(performAction(head)) {
						int[] l3res;
						for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
							const ResourceType@ type = getResource(i);
							if(type.level >= 3 && type.exportable)
								l3res.insertLast(type.id);
						}
						@head = ImportResource(homeworld, l3res);
					}
					break;
			}
		
			thoughtCycle = (thoughtCycle + 1) % 2;
		}
		
		double actionEnd = getExactTime();
		
		if(!didTickScan && actionEnd - start < maxAIFrame)
			updateRandomVision();
		
		if(profile) {
			double end = getExactTime();
			dbgMsg += format("\n\tTook $1us to validate, $2us to process, $3us for vision", toString((validateEnd-start) * 1.0e6, 1), toString((actionEnd-validateEnd) * 1.0e6 , 1), toString((end-actionEnd) * 1.0e6 , 1));
		}
		
		if(debug || profile) {
			dbgMsg += "\n}";
			print(dbgMsg);
		}
	}

	void pause(Empire& emp) {
	}

	void resume(Empire& emp) {
	}
};

AIController@ createBasicAI() {
	return BasicAI();
}
