import hooks;
import cargo;
import buildings;
from buildings import IBuildingHook;
import constructions;
from constructions import IConstructionHook;
import orbitals;
from orbitals import IOrbitalEffect;
import icons;

#section server
from construction.Constructible import Constructible;
#section all

class ConsumeEffect : Hook, IConstructionHook, IBuildingHook, IOrbitalEffect {
	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		return true;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		return false;
	}

	bool consume(Object& obj, const Targets@ targs) const {
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel = false) const {
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		return false;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		return false;
	}

	//Buildings
	uint hookIndex = 0;
	void initialize(BuildingType@ type, uint index) { hookIndex = index; }
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void complete(Object& obj, SurfaceBuilding@ bld) const {}
	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const {}
	void remove(Object& obj, SurfaceBuilding@ bld) const {}
	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {}
	void save(SurfaceBuilding@ bld, SaveFile& file) const {}
	void load(SurfaceBuilding@ bld, SaveFile& file) const {}
	bool canBuildOn(Object& obj, bool ignoreState = false) const { return canConsume(obj, null, ignoreState); }
	bool canRemove(Object& obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const {
		if(isOption)
			return getVariable(obj, sprt, name, value, color);
		return false;
	}
	bool consume(Object& obj) const { return consume(obj, null); }
	void reverse(Object& obj) const { reverse(obj, null); }
	void modBuildTime(Object& obj, double& time) const {}
	bool canProgress(Object& obj) const { return true; }

	//Orbitals
	void onEnable(Orbital& obj, any@ data) const {}
	void onDisable(Orbital& obj, any@ data) const {}
	void onCreate(Orbital& obj, any@ data) const {}
	void onDestroy(Orbital& obj, any@ data) const {}
	void onTick(Orbital& obj, any@ data, double time) const {}
	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {}
	void onRegionChange(Orbital& obj, any@ data, Region@ prevRegion, Region@ newRegion) const {}
	void onMakeGraphics(Orbital& obj, any@ data, OrbitalNode@ node) const {}
	bool checkRequirements(OrbitalRequirements@ reqs, bool apply) const { return true; }
	void revertRequirements(OrbitalRequirements@ reqs) const {}
	bool canBuildBy(Object@ obj, bool ignoreCost = true) const { return canConsume(obj, null, ignoreCost); }
	bool canBuildAt(Object@ obj, const vec3d& pos) const { return true; }
	bool canBuildOn(Orbital& obj) const { return true; }
	string getBuildError(Object@ obj, const vec3d& pos) const { return ""; }
	bool shouldDisable(Orbital& obj, any@ data) const { return false; }
	bool shouldEnable(Orbital& obj, any@ data) const { return true; }
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}
	void write(any@ data, Message& msg) const {}
	void read(any@ data, Message& msg) const {}
	void onKill(Orbital& obj, any@ data, Empire@ killedBy) const {}
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const { return false; }
	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const { return false; }
	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const { return false; }
	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const { return false; }
	bool getObject(Player& pl, Orbital& obj, any@ data, uint index, Object@& value) const { return false; }
	bool sendObject(Player& pl, Orbital& obj, any@ data, uint index, Object@ value) const { return false; }
	bool getData(Orbital& obj, string& txt, bool enabled) const { return false; }
	void reverse(Object& obj, bool cancel) const { reverse(obj, null, cancel); }

	//Constructions
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {}
#section all

	void save(Construction@ cons, any@ data, SaveFile& file) const {}
	void load(Construction@ cons, any@ data, SaveFile& file) const {}

	bool consume(Construction@ cons, any@ data, const Targets@ targs) const { return consume(cons.obj, targs); }
	void reverse(Construction@ cons, any@ data, const Targets@ targs, bool cancel) const { reverse(cons.obj, targs, cancel); }

	string getFailReason(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return ""; }
	bool isValidTarget(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return true; }

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const { return canConsume(obj, targs, ignoreCost); }

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const {}

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const {
		return getVariable(obj, sprt, name, value, color);
	}
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return formatCost(obj, targs, value); }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return getCost(obj, value, icon); }
};

class ConsumeFTL : ConsumeEffect {
	Document doc("Requires a payment of FTL to build this construction.");
	Argument cost("Amount", AT_Decimal, doc="FTL Cost.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(ignoreCost)
			return true;
		return obj.owner.FTLStored >= cost.decimal;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = format(locale::FTL_COST, toString(cost.decimal, 0));
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(cost.decimal, true);
		icon = icons::FTL;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		if(obj.owner.consumeFTL(cost.decimal, partial=false, record=false) == 0.0)
			return false;
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		if(!cancel)
			obj.owner.modFTLStored(cost.decimal);
	}
#section all
};

class ConsumeInfluence : ConsumeEffect {
	Document doc("Requires a payment of influence to build this construction.");
	Argument cost("Amount", AT_Integer, doc="Influence Cost.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(ignoreCost)
			return true;
		return obj.owner.Influence >= cost.integer;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = format(locale::RESOURCE_INFLUENCE, toString(cost.integer, 0));
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(cost.integer, true);
		icon = icons::Influence;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		value = standardize(cost.integer, true);
		sprt = icons::Influence;
		name = locale::RESOURCE_INFLUENCE + " "+locale::COST;
		color = colors::Influence;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		if(!obj.owner.consumeInfluence(cost.integer))
			return false;
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		if(!cancel)
			obj.owner.modInfluence(cost.integer);
	}
#section all
};

class ConsumeResearch : ConsumeEffect {
	Document doc("Requires a payment of Research to build this construction.");
	Argument cost("Amount", AT_Integer, doc="Research Cost.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(ignoreCost)
			return true;
		return obj.owner.ResearchPoints >= cost.integer;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = toString(cost.integer, 0)+" "+locale::RESOURCE_RESEARCH;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(cost.integer, true);
		icon = icons::Research;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		value = standardize(cost.integer, true);
		sprt = icons::Research;
		name = locale::RESOURCE_RESEARCH + " "+locale::COST;
		color = colors::Research;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		if(!obj.owner.consumeResearchPoints(cost.integer))
			return false;
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		obj.owner.freeResearchPoints(cost.integer);
	}
#section all
};

class ConsumeEnergy : ConsumeEffect {
	Document doc("Requires a payment of Energy to build this construction.");
	Argument cost("Amount", AT_Decimal, doc="Energy Cost.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(ignoreCost)
			return true;
		return obj.owner.EnergyStored >= cost.decimal;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = toString(cost.decimal, 0)+" "+locale::RESOURCE_ENERGY;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(cost.decimal, true);
		icon = icons::Energy;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		value = standardize(cost.decimal, true);
		sprt = icons::Energy;
		name = locale::RESOURCE_ENERGY + " "+locale::COST;
		color = colors::Energy;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		if(obj.owner.consumeEnergy(cost.decimal, false) == 0.0)
			return false;
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		if(!cancel)
			obj.owner.modEnergyStored(cost.decimal);
	}
#section all
};

class ConsumePopulation : ConsumeEffect {
	Document doc("Requires a payment of Population to build this construction.");
	Argument cost("Amount", AT_Decimal, doc="Population Cost.");
	Argument allow_abandon(AT_Boolean, "False", doc="Whether to allow the planet to build this so it would go below 1 population and abandon.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(!obj.hasSurfaceComponent)
			return false;
		if(ignoreCost)
			return true;
		if(!allow_abandon.boolean)
			return obj.population - 1.0 > cost.decimal;
		return obj.population > cost.decimal;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = toString(cost.decimal, 0)+" "+locale::POPULATION;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(cost.decimal, true);
		icon = icons::Population;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		value = standardize(cost.decimal, true);
		sprt = icons::Population;
		name = locale::POPULATION + " "+locale::COST;
		color = colors::White;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		if(!obj.hasSurfaceComponent)
			return false;
		double avail = obj.population;
		if(!allow_abandon.boolean)
			avail -= 1.0;
		if(avail < cost.decimal)
			return false;
		obj.addPopulation(-cost.decimal);
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		if(!cancel)
			obj.addPopulation(cost.decimal);
	}

	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {
		if(allow_abandon.boolean && cons.obj.population <= 0.1)
			cons.obj.forceAbandon();
	}
#section all
};

class ConsumeCargo : ConsumeEffect {
	Document doc("Requires a payment of cargo to build this construction.");
	Argument type(AT_Cargo, doc="Type of cargo to take.");
	Argument amount(AT_Decimal, doc="Amount of cargo taken to build.");
	Argument hide(AT_Boolean, "False", doc="If the planet has _no_ cargo of this type, hide the project.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(!obj.hasCargo)
			return false;

		double val = obj.getCargoStored(type.integer);
		if(hide.boolean && val < 0.001)
			return false;
		if(ignoreCost)
			return true;
		return val >= amount.decimal;
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = standardize(amount.decimal, true)+" "+getCargoType(type.integer).name;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(amount.decimal, true);
		icon = getCargoType(type.integer).icon;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		auto@ cargo = getCargoType(type.integer);
		value = standardize(amount.decimal, true);
		sprt = cargo.icon;
		name = cargo.name + " "+locale::COST;
		color = cargo.color;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		double consAmt = obj.consumeCargo(type.integer, amount.decimal, partial=false);
		return consAmt >= amount.decimal - 0.001;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		obj.addCargo(type.integer, amount.decimal);
	}
#section all
};

class ConsumeCargoAttribute : ConsumeEffect {
	Document doc("Requires a payment of cargo to build this construction based on an attribute.");
	Argument type(AT_Cargo, doc="Type of cargo to take.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to get value from.");
	Argument base_amount(AT_Decimal, "0", doc="Base amount of cargo taken to build.");
	Argument multiply(AT_Decimal, "1", doc="Multiply value of attribute.");
	Argument hide(AT_Boolean, "False", doc="If the planet has _no_ cargo of this type, hide the project.");

	double getCost(Empire& emp) {
		return base_amount.decimal + emp.getAttribute(attribute.integer) * multiply.decimal;
	}

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(!obj.hasCargo)
			return false;

		double val = obj.getCargoStored(type.integer);
		if(hide.boolean && val < 0.001)
			return false;
		if(ignoreCost)
			return true;
		return val >= getCost(obj.owner);
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = standardize(getCost(obj.owner), true)+" "+getCargoType(type.integer).name;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(getCost(obj.owner), true);
		icon = getCargoType(type.integer).icon;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		auto@ cargo = getCargoType(type.integer);
		value = standardize(getCost(obj.owner), true);
		sprt = cargo.icon;
		name = cargo.name + " "+locale::COST;
		color = cargo.color;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		double cost = getCost(obj.owner);
		double consAmt = obj.consumeCargo(type.integer, cost, partial=false);
		return consAmt >= cost - 0.001;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		obj.addCargo(type.integer, getCost(obj.owner));
	}
#section all
};

class ConsumeCargoStatusCount : ConsumeEffect {
	Document doc("Requires a payment of cargo to build this construction, based on the amount of stacks of a status present.");
	Argument type(AT_Cargo, doc="Type of cargo to take.");
	Argument status(AT_Status, doc="Status to count.");
	Argument amount(AT_Decimal, doc="Amount of cargo taken to build per status.");
	Argument hide(AT_Boolean, "False", doc="If the planet has _no_ cargo of this type, hide the project.");
	Argument allow_cancel(AT_Boolean, "False", doc="Refund the cost when canceling. Only use in specific circumstances when you know the status doesn't get added any other way.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(!obj.hasCargo)
			return false;

		double val = obj.getCargoStored(type.integer);
		if(hide.boolean && val < 0.001)
			return false;
		if(ignoreCost)
			return true;
		return val >= get(obj);
	}

	double get(Object& obj) const {
		return amount.decimal * obj.getStatusStackCountAny(status.integer);
	}

	bool formatCost(Object& obj, const Targets@ targs, string& value) const {
		value = standardize(get(obj), true)+" "+getCargoType(type.integer).name;
		return true;
	}

	bool getCost(Object& obj, string& value, Sprite& icon) const {
		value = standardize(get(obj), true);
		icon = getCargoType(type.integer).icon;
		return true;
	}

	bool getVariable(Object& obj, Sprite& sprt, string& name, string& value, Color& color) const {
		auto@ cargo = getCargoType(type.integer);
		value = standardize(get(obj), true);
		sprt = cargo.icon;
		name = cargo.name + " "+locale::COST;
		color = cargo.color;
		return true;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		double consAmt = obj.consumeCargo(type.integer, get(obj), partial=false);
		return consAmt >= amount.decimal - 0.001;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		double consAmt = get(obj);
		if(!cancel || allow_cancel.boolean)
			obj.addCargo(type.integer, consAmt);
	}
#section all
};

class ConsumeStatus : ConsumeEffect {
	Document doc("Consumes an instance of a status on the object.");
	Argument type(AT_Status, doc="Type of status to take.");
	Argument amount(AT_Integer, "1", doc="Amount of cargo taken to build per status.");
	Argument hide(AT_Boolean, "False", doc="If the object has _no_ statuses of this type, hide the option.");

	bool canConsume(Object& obj, const Targets@ targs, bool ignoreCost) const {
		if(!obj.hasStatuses)
			return false;

		int val = obj.getStatusStackCountAny(type.integer);
		if(hide.boolean && val < amount.integer)
			return false;
		if(ignoreCost)
			return true;
		return val >= amount.integer;
	}

#section server
	bool consume(Object& obj, const Targets@ targs) const override {
		int count = obj.getStatusStackCount(type.integer);
		if(count < amount.integer)
			return false;

		for(int i = 0; i < amount.integer; ++i)
			obj.removeStatusInstanceOfType(type.integer);
		return true;
	}

	void reverse(Object& obj, const Targets@ targs, bool cancel) const override {
		obj.addStatus(type.integer);
	}
#section all
};
