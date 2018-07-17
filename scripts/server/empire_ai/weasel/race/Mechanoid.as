import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Resources;
import empire_ai.weasel.Colonization;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Budget;

import resources;
import abilities;
import planet_levels;
from constructions import getConstructionType, ConstructionType;
from abilities import getAbilityID;
import oddity_navigation;

const double MAX_POP_BUILDTIME = 3.0 * 60.0;

class Mechanoid : Race, RaceResources, RaceColonization {
	Colonization@ colonization;
	Construction@ construction;
	Movement@ movement;
	Budget@ budget;
	Planets@ planets;

	const ResourceType@ unobtanium;
	const ResourceType@ crystals;
	int unobtaniumAbl = -1;

	const ResourceClass@ foodClass;
	const ResourceClass@ waterClass;
	const ResourceClass@ scalableClass;
	const ConstructionType@ buildPop;

	int colonizeAbl = -1;

	array<Planet@> popRequests;
	array<Planet@> popSources;
	array<Planet@> popFactories;

	void create() {
		@colonization = cast<Colonization>(ai.colonization);
		@construction = cast<Construction>(ai.construction);
		@movement = cast<Movement>(ai.movement);
		@planets = cast<Planets>(ai.planets);
		@budget = cast<Budget>(ai.budget);

		@ai.defs.Shipyard = null;

		@crystals = getResource("FTL");
		@unobtanium = getResource("Unobtanium");
		unobtaniumAbl = getAbilityID("UnobtaniumMorph");

		@foodClass = getResourceClass("Food");
		@waterClass = getResourceClass("WaterType");
		@scalableClass = getResourceClass("Scalable");

		colonizeAbl = getAbilityID("MechanoidColonize");
		colonization.performColonization = false;

		@buildPop = getConstructionType("MechanoidPopulation");
	}

	void start() {
		//Oh yes please can we have some ftl crystals sir
		if(crystals !is null) {
			ResourceSpec spec;
			spec.type = RST_Specific;
			@spec.resource = crystals;
			spec.isLevelRequirement = false;
			spec.isForImport = false;

			colonization.queueColonize(spec);
		}
	}

	void levelRequirements(Object& obj, int targetLevel, array<ResourceSpec@>& specs) override {
		//Remove all food and water resources
		if(obj.levelChain != baseLevelChain.id)
			return;
		for(int i = specs.length-1; i >= 0; --i) {
			auto@ spec = specs[i];
			if(spec.type == RST_Class && (spec.cls is foodClass || spec.cls is waterClass))
				specs.removeAt(i);
		}
	}

	double transferCost(double dist) {
		return 20 + dist * 0.002;
	}

	bool orderColonization(ColonizeData& data, Planet@ sourcePlanet) {
		return false;
	}

	double getGenericUsefulness(const ResourceType@ type) override {
		if(type.cls is foodClass || type.cls is waterClass)
			return 0.00001;
		if(type.level == 1)
			return 100.0;
		return 1.0;
	}

	bool canBuildPopulation(Planet& pl, double factor=1.0) {
		if(buildPop is null)
			return false;
		if(!buildPop.canBuild(pl, ignoreCost=true))
			return false;
		auto@ primFact = construction.primaryFactory;
		if(primFact !is null && pl is primFact.obj)
			return true;

		double laborCost = buildPop.getLaborCost(pl);
		double laborIncome = pl.laborIncome;
		return laborCost < laborIncome * MAX_POP_BUILDTIME * factor;
	}

	bool requiresPopulation(Planet& pl, double mod = 0.0) {
		double curPop = pl.population + mod;
		double maxPop = pl.maxPopulation;
		return curPop < maxPop;
	}

	bool canSendPopulation(Planet& pl, double mod = 0.0) {
		double curPop = pl.population + mod;
		double maxPop = pl.maxPopulation;
		if(curPop >= maxPop + 1)
			return true;
		//auto@ primFact = construction.primaryFactory;
		//if(primFact !is null && pl is primFact.obj) {
		//	uint minFacts = 2;
		//	if(popFactories.find(pl) == -1)
		//		minFacts -= 1;
		//	if(popFactories.length >= minFacts)
		//		return false;
		//}
		//if(canBuildPopulation(pl)) {
		//	if(curPop >= maxPop)
		//		return true;
		//}
		return false;
	}

	uint chkInd = 0;
	array<Planet@> availSources;
	void focusTick(double time) override {
		//Check existing lists
		for(uint i = 0, cnt = popFactories.length; i < cnt; ++i) {
			auto@ obj = popFactories[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popFactories.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!canBuildPopulation(popFactories[i])) {
				popFactories.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		for(uint i = 0, cnt = popSources.length; i < cnt; ++i) {
			auto@ obj = popSources[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popSources.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!canSendPopulation(popSources[i])) {
				popSources.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		for(uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			auto@ obj = popRequests[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!requiresPopulation(popRequests[i])) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		//Find new planets to add to our lists
		bool checkMorph = false;
		Planet@ hw = ai.empire.Homeworld;
		if(hw !is null && hw.valid && hw.owner is ai.empire && unobtanium !is null) {
			if(hw.primaryResourceType == unobtanium.id)
				checkMorph = true;
		}

		uint plCnt = planets.planets.length;
		for(uint n = 0, cnt = min(15, plCnt); n < cnt; ++n) {
			chkInd = (chkInd+1) % plCnt;
			auto@ plAI = planets.planets[chkInd];

			//Find planets that can build population reliably
			if(canBuildPopulation(plAI.obj)) {
				if(popFactories.find(plAI.obj) == -1)
					popFactories.insertLast(plAI.obj);
			}

			//Find planets that need population
			if(requiresPopulation(plAI.obj)) {
				if(popRequests.find(plAI.obj) == -1)
					popRequests.insertLast(plAI.obj);
			}

			//Find planets that have extra population
			if(canSendPopulation(plAI.obj)) {
				if(popSources.find(plAI.obj) == -1)
					popSources.insertLast(plAI.obj);
			}

			if(plAI.resources !is null && plAI.resources.length != 0) {
				auto@ res = plAI.resources[0];

				//Get rid of food and water we don't need
				if(res.resource.cls is foodClass || res.resource.cls is waterClass) {
					if(res.request is null) {
						Region@ reg = res.obj.region;
						if(reg !is null && reg.getPlanetCount(ai.empire) >= 2) {
							plAI.obj.abandon();
						}
					}
				}

				//See if we have anything useful to morph our homeworld too
				if(checkMorph) {
					bool morph = false;
					if(res.resource is crystals)
						morph = true;
					else if(res.resource.level >= 2 && res.resource.tilePressure[TR_Labor] >= 5)
						morph = true;
					else if(res.resource.level >= 3 && res.resource.totalPressure > 10)
						morph = true;
					else if(res.resource.cls is scalableClass && gameTime > 30.0 * 60.0)
						morph = true;
					else if(res.resource.level >= 2 && res.resource.totalPressure >= 5 && gameTime > 60.0 * 60.0)
						morph = true;

					if(morph) {
						if(log)
							ai.print("Morph homeworld to "+res.resource.name+" from "+res.obj.name, hw);
						hw.activateAbilityTypeFor(ai.empire, unobtaniumAbl, plAI.obj);
					}
				}
			}
		}

		//See if we can find something to send population to
		availSources = popSources;

		for(uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			Planet@ dest = popRequests[i];
			if(canBuildPopulation(dest, factor=(availSources.length == 0 ? 2.5 : 1.5))) {
				Factory@ f = construction.get(dest);
				if(f !is null) {
					if(f.active is null) {
						auto@ build = construction.buildConstruction(buildPop);
						construction.buildNow(build, f);
						if(log)
							ai.print("Build population", f.obj);
						continue;
					}
					else {
						auto@ cons = cast<BuildConstruction>(f.active);
						if(cons !is null && cons.consType is buildPop) {
							if(double(dest.maxPopulation) <= dest.population + 0.0)
								continue;
						}
					}
				}
			}
			transferBest(dest, availSources);
		}

		if(availSources.length != 0) {
			//If we have any population left, do stuff from our colonization queue
			for(uint i = 0, cnt = colonization.awaitingSource.length; i < cnt && availSources.length != 0; ++i) {
				Planet@ dest = colonization.awaitingSource[i].target;
				Planet@ source = transferBest(dest, availSources);
				if(source !is null) {
					@colonization.awaitingSource[i].colonizeFrom = source;
					colonization.awaitingSource.removeAt(i);
					--i; --cnt;
				}
			}
		}

		//Build population on idle planets
		if(budget.canSpend(BT_Development, 100)) {
			for(int i = popFactories.length-1; i >= 0; --i) {
				Planet@ dest = popFactories[i];
				Factory@ f = construction.get(dest);
				if(f is null || f.active !is null)
					continue;
				if(dest.population >= double(dest.maxPopulation) + 1.0)
					continue;

				auto@ build = construction.buildConstruction(buildPop);
				construction.buildNow(build, f);
				if(log)
					ai.print("Build population for idle", f.obj);
				break;
			}
		}
	}

	Planet@ transferBest(Planet& dest, array<Planet@>& availSources) {
		//Find closest source
		Planet@ bestSource;
		double bestDist = INFINITY;
		for(uint j = 0, jcnt = availSources.length; j < jcnt; ++j) {
			double d = movement.getPathDistance(availSources[j].position, dest.position);
			if(d < bestDist) {
				bestDist = d;
				@bestSource = availSources[j];
			}
		}

		if(bestSource !is null) {
			double cost = transferCost(bestDist);
			if(cost <= ai.empire.FTLStored) {
				if(log)
					ai.print("Transfering population to "+dest.name, bestSource);
				availSources.remove(bestSource);
				bestSource.activateAbilityTypeFor(ai.empire, colonizeAbl, dest);
				return bestSource;
			}
		}
		return null;
	}

	void tick(double time) override {
	}
};

AIComponent@ createMechanoid() {
	return Mechanoid();
}
