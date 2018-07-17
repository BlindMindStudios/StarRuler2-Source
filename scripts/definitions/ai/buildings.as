import hooks;
import buildings;
import resources;

import ai.consider;

interface Buildings : ConsiderComponent {
	Empire@ get_empire();
	Considerer@ get_consider();

	bool requestsFTLStorage();

	bool isBuilding(const BuildingType& type);
	bool isFocus(Object@ obj);

	void registerUse(BuildingUse use, const BuildingType& type);
};

enum BuildingUse {
	BU_Factory,
	BU_LaborStorage,
};

const array<string> BuildingUseName = {
	"Factory",
	"LaborStorage",
};

class BuildingAI : Hook, ConsiderHook {
	double consider(Considerer& cons, Object@ obj) const {
		return 0.0;
	}

	void register(Buildings& buildings, const BuildingType& type) const {
	}

	//Return the planet to build this building on
	Object@ considerBuild(Buildings& buildings, const BuildingType& type) const {
		return null;
	}
};

class RegisterForUse : BuildingAI {
	Document doc("Register this building for a particular use. Only one building can be used for a specific specialized use.");
	Argument use(AT_Custom, doc="Specialized usage for this building.");

	void register(Buildings& buildings, const BuildingType& type) const override {
		for(uint i = 0, cnt = BuildingUseName.length; i < cnt; ++i) {
			if(BuildingUseName[i] == use.str) {
				buildings.registerUse(BuildingUse(i), type);
				return;
			}
		}
	}
};

class AsCreatedResource : BuildingAI {
	Document doc("This building is used to spawn a new resource type on a planet that needs it.");
	Argument resource(AT_PlanetResource, doc="Resource to match import requests to.");
	Argument minimum_idle(AT_Decimal, "180", doc="Minimum amount of time the resource request has to have been idle to consider this.");
	Argument minimum_colonize_idle(AT_Decimal, "180", doc="Minimum amount of time since we've colonized something matching the request before we consider building this.");
	Argument minimum_gametime(AT_Decimal, "1500", doc="Minimum gametime that needs to have passed before we consider building this.");

#section server
	double consider(Considerer& cons, Object@ requestedAt) const override {
		double w = 1.0;
		if(cons.currentSupplier !is null)
			return 0.0;
		if(cons.idleTime < minimum_idle.decimal)
			return 0.0;
		if(cons.timeSinceMatchingColonize() < minimum_colonize_idle.decimal)
			return 0.0;
		if(!cons.building.canBuildOn(requestedAt, ignoreState=true))
			return 0.0;
		return w;
	}

	Object@ considerBuild(Buildings& buildings, const BuildingType& type) const override {
		if(gameTime < minimum_gametime.decimal)
			return null;
		@buildings.consider.building = type;
		return buildings.consider.MatchingImportRequests(this, getResource(resource.integer), false);
	}
#section all
};

class BuildForPressureCap : BuildingAI {
	Document doc("Build this to increase the pressure capacity on a planet.");
	Argument increase(AT_Integer, doc="Pressure this should increase the cap by.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		double w = 1.0;
		int pres = obj.totalPressure;
		int cap = obj.pressureCap;
		if(pres <= cap)
			return 0.0;
		if(obj.level <= 0)
			return 0.0;
		if(double(obj.population) < double(obj.maxPopulation) * 0.9)
			return 0.0;
		double eff = double(pres) / double(cap);
		if(eff < 1.5 && cap + increase.integer > 2 * pres)
			return 0.0;
		if(!cons.building.canBuildOn(obj, ignoreState=true))
			return 0.0;
		return eff;
	}

	Object@ considerBuild(Buildings& buildings, const BuildingType& type) const override {
		@buildings.consider.building = type;
		return buildings.consider.SomePlanets(this);
	}
#section all
};

class AsFTLStorage : BuildingAI {
	Document doc("This building is built whenever more ftl storage is requested.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		if(cast<Buildings>(cons.component).isFocus(obj))
			return 0.0;
		if(obj.emptyDevelopedTiles < 10)
			return 0.0;
		if(!cons.building.canBuildOn(obj, ignoreState=true))
			return 0.0;
		return 1.0;
	}

	Object@ considerBuild(Buildings& buildings, const BuildingType& type) const override {
		if(!buildings.requestsFTLStorage())
			return null;
		if(buildings.isBuilding(type))
			return null;
		@buildings.consider.component = buildings;
		@buildings.consider.building = type;
		return buildings.consider.SomePlanets(this);
	}
#section all
};
