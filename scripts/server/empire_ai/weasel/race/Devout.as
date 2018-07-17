import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Development;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Budget;

import resources;
import buildings;
import attributes;

class Devout : Race, RaceDevelopment {
	Development@ development;
	Planets@ planets;
	Budget@ budget;

	const ResourceType@ altarResource;
	const BuildingType@ altar;

	int coverAttrib = -1;

	BuildingRequest@ altarBuild;
	Planet@ focusAltar;

	double considerTimer = 0.0;

	void save(SaveFile& file) {
		planets.saveBuildingRequest(file, altarBuild);
		file << focusAltar;
		file << considerTimer;
	}

	void load(SaveFile& file) {
		@altarBuild = planets.loadBuildingRequest(file);
		file >> focusAltar;
		file >> considerTimer;
	}

	void create() {
		@planets = cast<Planets>(ai.planets);
		@development = cast<Development>(ai.development);
		@budget = cast<Budget>(ai.budget);

		@altarResource = getResource("Altar");

		@altar = getBuildingType("Altar");

		coverAttrib = getEmpAttribute("AltarSupportedPopulation");
	}

	void start() {
		auto@ data = ai.empire.getPlanets();
		Object@ obj;
		while(receive(data, obj)) {
			Planet@ pl = cast<Planet>(obj);
			if(pl !is null){
				if(pl.primaryResourceType == altarResource.id) {
					@focusAltar = pl;
					break;
				}
			}
		}
	}

	bool shouldBeFocus(Planet& pl, const ResourceType@ resource) override {
		if(resource is altarResource)
			return true;
		return false;
	}

	void focusTick(double time) override {
		//Handle our current altar build
		if(altarBuild !is null) {
			if(altarBuild.built) {
				@focusAltar = altarBuild.plAI.obj;
				@altarBuild = null;
			}
			else if(altarBuild.canceled) {
				@altarBuild = null;
			}
		}

		//Handle our focused altar
		if(focusAltar !is null) {
			if(!focusAltar.valid || focusAltar.owner !is ai.empire || focusAltar.primaryResourceType != altarResource.id) {
				@focusAltar = null;
			}
		}

		//If we aren't covering our entire population, find new planets to make into altars
		double coverage = ai.empire.getAttribute(coverAttrib);
		double population = ai.empire.TotalPopulation;

		if(coverage >= population || altarBuild !is null)
			return;

		bool makeNewAltar = true;
		if(focusAltar !is null) {
			auto@ foc = development.getFocus(focusAltar);
			if(foc !is null && int(foc.obj.level) >= foc.targetLevel) {
				foc.targetLevel += 1;
				considerTimer = gameTime + 180.0;
				makeNewAltar = false;
			}
			else {
				makeNewAltar = gameTime > considerTimer;
			}
		}

		if(makeNewAltar) {
			if(budget.canSpend(BT_Development, 300)) {
				//Turn our most suitable planet into an altar
				PlanetAI@ bestBuild;
				double bestWeight = 0.0;

				for(uint i = 0, cnt = planets.planets.length; i < cnt; ++i) {
					auto@ plAI = planets.planets[i];
					double w = randomd(0.9, 1.1);

					if(plAI.resources !is null && plAI.resources.length != 0) {
						auto@ res = plAI.resources[0].resource;
						if(res.level == 0 && !res.limitlessLevel)
							w *= 5.0;
						if(res.cls !is null)
							w *= 0.5;
						if(res.level > 0)
							w /= pow(2.0, res.level);
					}
					else {
						w *= 100.0;
					}

					if(w > bestWeight) {
						bestWeight = w;
						@bestBuild = plAI;
					}
				}

				if(bestBuild !is null) {
					@altarBuild = planets.requestBuilding(bestBuild, altar, expire=60.0);
					considerTimer = gameTime + 120.0;
				}
			}
		}
	}
};

AIComponent@ createDevout() {
	return Devout();
}
