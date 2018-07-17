import hooks;
import artifacts;
import resources;

import ai.consider;

#section server
from empire import Creeps;
#section all

interface Artifacts {
	Empire@ get_empire();
	Considerer@ get_consider();
}

class ArtifactAI : Hook, ConsiderHook {
	double consider(Considerer& cons, Object@ obj) const {
		return 0.0;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const {
		return false;
	}
};

class Value : ArtifactAI {
	Document doc("Sets the value for the artifact to a basic amount.");
	Argument value(AT_Decimal, doc="Value to set for the artifact.");

#section server
	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		value *= this.value.decimal;
		return true;
	}
#section all
};

class ActivateOnBestFleet : ArtifactAI {
	Document doc("This artifact should be activated on our strongest fleet that it can be.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating on the best fleet.");
	Argument min_strength(AT_Decimal, "1000", doc="Minimum strength for a fleet to be considered for this.");

#section server
	double consider(Considerer& cons, Object@ fleet) const override {
		double str = fleet.getFleetStrength() * 0.001;
		if(str < min_strength.decimal)
			return 0.0;
		if(!cons.artifact.canTarget(fleet))
			return 0.0;
		return str;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Object@ best = ai.consider.Fleets(this);
		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class ActivateOnBestPlanet : ArtifactAI {
	Document doc("This artifact should be activated on our best planet that it can be.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating on the best planet.");
	Argument min_population(AT_Decimal, "10", doc="Minimum population for a planet to be considered for this.");

#section server
	double consider(Considerer& cons, Object@ planet) const override {
		double pop = planet.population;
		if(pop < min_population.decimal)
			return 0.0;
		if(!cons.artifact.canTarget(planet))
			return 0.0;
		return pop;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Object@ best = ai.consider.ImportantPlanets(this);
		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class AsCreatedResource : ArtifactAI {
	Document doc("This artifact is used to spawn a new resource type on a planet that needs it.");
	Argument resource(AT_PlanetResource, doc="Resource to match import requests to.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating this.");
	Argument replaces_existing(AT_Boolean, "True", doc="Whether this can be used to replace an existing import of that type or not.");

#section server
	double consider(Considerer& cons, Object@ requestedAt) const override {
		if(!cons.artifact.canTarget(requestedAt))
			return 0.0;
		if(cons.currentSupplier !is null)
			return 0.5;
		return 1.0;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Object@ best = ai.consider.MatchingImportRequests(this, getResource(resource.integer), replaces_existing.boolean);
		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class ActivateInOwnedSystem : ArtifactAI {
	Document doc("Activate this artifact on a position in an arbitrary owned system.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating this.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		Region@ sys = cast<Region>(obj);
		if(sys.PlanetsMask & ~cons.empire.mask != 0)
			return randomd(0.4, 0.6);
		return randomd(0.9, 1.1);
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		Region@ best = cast<Region>(ai.consider.OwnedSystems(this));
		if(best !is null) {
			vec3d position = best.position;
			vec2d offset = random2d(best.radius * 0.4, best.radius * 0.85);
			position.x += offset.x;
			position.z += offset.y;

			if(!c.canTargetPosition(position))
				return false;

			c.setTargetPosition(position);
			if(best.PlanetsMask & ~ai.empire.mask != 0)
				value *= 0.5;
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class ActivateNearOwnedSystem : ArtifactAI {
	Document doc("Activate this artifact on a position placed outside an arbitrary owned system.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating this.");
	Argument min_distance(AT_Decimal, "2000", doc="Minimum distance from the system boundary to place it.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		Region@ sys = cast<Region>(obj);
		if(sys.PlanetsMask & ~cons.empire.mask != 0)
			return randomd(0.4, 0.6);
		return randomd(0.9, 1.1);
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		Region@ best = cast<Region>(ai.consider.OwnedSystems(this));
		if(best !is null) {
			vec3d position = best.position;
			vec2d offset = random2d(best.radius + min_distance.decimal, best.radius + min_distance.decimal * 2.0);
			position.x += offset.x;
			position.z += offset.y;
			position.y += min_distance.decimal * randomd(0.0, 0.25);

			if(!c.canTargetPosition(position))
				return false;

			c.setTargetPosition(position);
			if(best.PlanetsMask & ~ai.empire.mask != 0)
				value *= 0.5;
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class AsVisionGain : ArtifactAI {
	Document doc("Activate this to gain vision over systems with other people in them we want to see.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating this.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		Region@ sys = cast<Region>(obj);
		if(sys.VisionMask & cons.empire.visionMask != 0)
			return 0.0;
		if(!cons.artifact.canTarget(sys))
			return 0.0;
		double w = 1.0;
		if(sys.PlanetsMask & cons.empire.hostileMask != 0)
			w *= 2.0;
		return w * randomd(0.9, 1.1);
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Region@ best = cast<Region>(ai.consider.OtherSystems(this));
		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			if(best.PlanetsMask & ai.empire.hostileMask != 0)
				value *= 2.0;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class RevenantPart : ArtifactAI {
	Document doc("Special AI to deal with using parts of the revenant.");

#section server
	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		//If we are subjugated don't use these
		if(ai.empire.SubjugatedBy !is null)
			return false;

		value *= 10.0;
		//If we have parts ourselves, weight more
		value *= pow(2.0, ai.empire.RevenantParts);

		//If an enemy has multilple parts, weight more
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major || other !is ai.empire)
				value *= pow(3.0, other.RevenantParts);
		}

		return true;
	}
#section all
};

class ActivateAsPressureBoost : ArtifactAI {
	Document doc("Activate this artifact on a planet to boost its pressure.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating on the best planet.");
	Argument pressure_amount(AT_Decimal, "1.0", doc="Amount of pressure that is added.");

#section server
	double consider(Considerer& cons, Object@ planet) const override {
		auto@ res = getResource(planet.primaryResourceType);
		if(res is null)
			return 0.0;
		if(res.totalPressure < 1)
			return 0.0;
		double pres = planet.totalPressure;
		double cap = planet.pressureCap;
		if(pres + pressure_amount.decimal > cap * 1.5)
			return 0.0;
		if(!cons.artifact.canTarget(planet))
			return 0.0;
		return 1.0;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Object@ best = ai.consider.SomePlanets(this);
		Object@ existing = c.getTarget();
		if(existing !is null && consider(ai.consider, existing) > ai.consider.selectedWeight)
			@best = existing;
		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};

class ActivateOnRemnantStation : ArtifactAI {
	Document doc("Find remnant stations to trigger this on.");
	Argument value(AT_Decimal, "1.0", doc="Value for activating on the best station.");

#section server
	double consider(Considerer& cons, Object@ obj) const override {
		Region@ reg = cast<Region>(obj);
		if(reg.getStrength(Creeps) > 0)
			return 1.0;
		return 0.0;
	}

	bool consider(Artifacts& ai, ArtifactConsider& c, double& value) const override {
		@ai.consider.artifact = c;
		Object@ best;

		Object@ reg = cast<Region>(ai.consider.OwnedSystems(this));
		if(reg !is null) {
			Object@ en = reg.findEnemy(ai.empire, Creeps.mask, fleets=false, stations=true);
			if(en !is null) {
				if(c.canTarget(en))
					@best = en;
			}
		}
		Object@ existing = c.getTarget();
		if(best is null && existing !is null && existing.valid && c.canTarget(existing))
			@best = existing;

		if(best !is null) {
			c.setTarget(best);
			value *= this.value.decimal;
			return true;
		}
		else {
			return false;
		}
	}
#section all
};
