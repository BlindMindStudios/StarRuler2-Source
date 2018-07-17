import hooks;
import resources;

import ai.consider;

interface AIResources : ConsiderComponent {
	Empire@ get_empire();
	Considerer@ get_consider();
};

class ResourceAI : Hook, ConsiderHook {
	double consider(Considerer& cons, Object@ obj) const {
		return 1.0;
	}

	//If the AI is not currently using this resource for anything
	//that explicitly requested it, this hook determines where it will
	//be distributed to in the meantime. Returning null means it will not be
	//placed anywhere.
	Object@ distribute(AIResources& ai, const ResourceType& type, Object@ current) const {
		return null;
	}
};

class DistributeToImportantPlanet : ResourceAI {
	Document doc("This resource goes to important planets to make them better.");

#section server
	double consider(Considerer& cons, Object@ obj) const {
		return 1.0 + obj.level;
	}

	Object@ distribute(AIResources& ai, const ResourceType& type, Object@ current) const {
		if(current !is null)
			return current;
		return ai.consider.ImportantPlanets(this);
	}
#section all
};

class DistributeToLaborUsing : ResourceAI {
	Document doc("This resource gets distributed to planets building things with labor.");
	Argument remove_idle(AT_Boolean, "True", doc="Remove the resource again when the target goes idle.");

#section server
	double consider(Considerer& cons, Object@ obj) const {
		if(obj.constructionCount == 0)
			return 0.0;
		return 1.0;
	}

	Object@ distribute(AIResources& ai, const ResourceType& type, Object@ current) const {
		if(current !is null) {
			if(!remove_idle.boolean || current.constructionCount != 0)
				return current;
		}
		return ai.consider.FactoryPlanets(this);
	}
#section all
};

class DistributeAsLocalPressureBoost : ResourceAI {
	Document doc("This resource gets distributed to boost the native pressure of a resource.");
	Argument amount(AT_Integer, doc="Amount of pressure this boosts by.");

#section server
	double consider(Considerer& cons, Object@ obj) const {
		auto@ resource = getResource(obj.primaryResourceType);
		if(resource is null)
			return 0.0;
		if(resource.totalPressure <= 0)
			return 0.0;
		bool havePressure = obj.owner.HasPressure != 0.0;
		if(havePressure) {
			int presCap = obj.pressureCap;
			int presUse = obj.totalPressure;
			if(presUse + amount.integer <= presCap)
				return 1.0;
			return 0.0;
		}
		else {
			return 1.0;
		}
	}

	Object@ distribute(AIResources& ai, const ResourceType& type, Object@ current) const {
		if(current !is null) {
			int presCap = current.pressureCap;
			int presUse = current.totalPressure;
			if(presUse <= presCap)
				return current;
		}
		Object@ check = ai.consider.SomePlanets(this);
		if(check !is null)
			return check;
		else
			return current;
	}
#section all
};
