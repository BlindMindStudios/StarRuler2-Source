import constructions;
from constructions import ConstructionHook;
import generic_hooks;
import requirement_effects;
import bonus_effects;
import target_filters;
import listed_values;
import consume_effects;
import util.formatting;

#section server
from constructions import Constructible;
#section all

class AddBuildCostAttribute : ConstructionHook {
	Document doc("Add build cost based on an empire attribute value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to use.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.owner.getAttribute(attribute.integer);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddMaintainCostAttribute : ConstructionHook {
	Document doc("Add maintenance cost based on an empire attribute value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to use.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.owner.getAttribute(attribute.integer);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddLaborCostAttribute : ConstructionHook {
	Document doc("Add labor cost based on an empire attribute value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to use.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const override {
		double value = obj.owner.getAttribute(attribute.integer);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddBuildCostTotalPopulation : ConstructionHook {
	Document doc("Add build cost based on an empire attribute value.");
	Argument add(AT_Decimal, "0", doc="Modify the value by this amount first.");
	Argument add_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to add to the amount first.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.owner.TotalPopulation + add.decimal;
		if(add_attribute.integer != 0)
			value += obj.owner.getAttribute(add_attribute.integer);
		value = max(value, 0.0);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddMaintainCostTotalPopulation : ConstructionHook {
	Document doc("Add maintenance cost based on an empire attribute value.");
	Argument add(AT_Decimal, "0", doc="Modify the value by this amount first.");
	Argument add_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to add to the amount first.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.owner.TotalPopulation + add.decimal;
		if(add_attribute.integer != 0)
			value += obj.owner.getAttribute(add_attribute.integer);
		value = max(value, 0.0);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddLaborCostTotalPopulation : ConstructionHook {
	Document doc("Add labor cost based on an empire attribute value.");
	Argument add(AT_Decimal, "0", doc="Modify the value by this amount first.");
	Argument add_attribute(AT_EmpAttribute, EMPTY_DEFAULT, doc="Attribute to add to the amount first.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");
	Argument power(AT_Decimal, "1", doc="Raise the attribute to this power before multiplying.");

	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const override {
		double value = obj.owner.TotalPopulation + add.decimal;
		if(add_attribute.integer != 0)
			value += obj.owner.getAttribute(add_attribute.integer);
		value = max(value, 0.0);
		if(power.decimal != 1.0)
			value = pow(value, power.decimal);

		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

tidy final class OnStart : ConstructionHook {
	Document doc("Trigger a hook whenever the construction is started.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnStart(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return ConstructionHook::instantiate();
	}

#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const override {
		if(hook !is null)
			hook.activate(cons.obj, cons.obj.owner);
	}
#section all
};

tidy final class OnCancel : ConstructionHook {
	Document doc("Trigger a hook whenever the construction is canceled.");
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnStart(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return ConstructionHook::instantiate();
	}

#section server
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const override {
		if(hook !is null)
			hook.activate(cons.obj, cons.obj.owner);
	}
#section all
};

tidy final class Trigger : ConstructionHook {
	Document doc("Runs a triggered hook on the target when the construction completes.");
	Argument targ(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;
	GenericEffect@ eff;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::", required=false));
		if(hook is null)
			@eff = cast<GenericEffect>(parseHook(hookID.str, "planet_effects::", required=false));
		if(hook is null && eff is null) {
			error("Trigger(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return ConstructionHook::instantiate();
	}

#section server
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const {
		auto@ objTarg = targ.fromConstTarget(cons.targets);
		if(objTarg is null || objTarg.obj is null)
			return;
		if(hook !is null)
			hook.activate(objTarg.obj, cons.obj.owner);
		else if(eff !is null)
			eff.enable(objTarg.obj, null);
	}
#section all
};

class SlowDownDebtGrowthFactor : ConstructionHook {
	Document doc("This constructible gets slowed down depending on the current debt factor.");

#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const override {
		double lab = qitem.totalLabor;
		data.store(lab);
	}

	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {
		double lab = 0;
		data.retrieve(lab);

		float growthFactor = 1.f;
		float debtFactor = cons.obj.owner.DebtFactor;
		for(; debtFactor > 0; debtFactor -= 1.f)
			growthFactor *= 0.33f + 0.67f * (1.f - min(debtFactor, 1.f));

		qitem.totalLabor = (lab - qitem.curLabor) / max(growthFactor, 0.01f) + qitem.curLabor;
	}

	void save(Construction@ cons, any@ data, SaveFile& file) const {
		double lab = 0;
		data.retrieve(lab);
		file << lab;
	}

	void load(Construction@ cons, any@ data, SaveFile& file) const {
		double lab = 0;
		file >> lab;
		data.store(lab);
	}
#section all
};

class AddBuildCostStatusCount : ConstructionHook {
	Document doc("Add build cost based on the amount of stacks of a status present.");
	Argument status(AT_Status, doc="Status to count.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.getStatusStackCountAny(status.integer);
		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddMaintainCostStatusCount : ConstructionHook {
	Document doc("Add maintenance cost based on the amount of stacks of a status present.");
	Argument status(AT_Status, doc="Status to count.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");

	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		double value = obj.getStatusStackCountAny(status.integer);
		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddLaborCostStatusCount : ConstructionHook {
	Document doc("Add labor cost based on the amount of stacks of a status present.");
	Argument status(AT_Status, doc="Status to count.");
	Argument multiply(AT_Decimal, "1", doc="Multiply attribute value by this much.");
	Argument multiply_sqrt(AT_Decimal, "0", doc="Add cost based on the square root of the attribute multiplied by this.");

	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const override {
		double value = obj.getStatusStackCountAny(status.integer);
		cost += value * multiply.decimal;
		if(multiply_sqrt.decimal != 0)
			cost += sqrt(value) * multiply_sqrt.decimal;
	}
};

class AddBuildCostTargetVar : ConstructionHook {
	Document doc("Add build cost based on a ship variable of the target.");
	Argument targ(TT_Object);
	Argument variable(AT_SysVar, doc="Variable to add as build cost.");
	Argument multiply(AT_Decimal, "1", doc="Multiply value by this much.");

	int get(Object@ obj) const {
		if(obj is null || !obj.isShip)
			return 0;

		auto@ design = cast<Ship>(obj).blueprint.design;
		if(design is null)
			return 0;

		return design.total(SubsystemVariable(variable.integer)) * multiply.decimal;
	}

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const override {
		if(targs is null)
			return;
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;

		cost += get(objTarg.obj);
	}
};

class AddLaborCostTargetVar : ConstructionHook {
	Document doc("Add labor cost based on a ship variable of the target.");
	Argument targ(TT_Object);
	Argument variable(AT_SysVar, doc="Variable to add as labor cost.");
	Argument multiply(AT_Decimal, "1", doc="Multiply value by this much.");

	double get(Object@ obj) const {
		if(obj is null || !obj.isShip)
			return 0;

		auto@ design = cast<Ship>(obj).blueprint.design;
		if(design is null)
			return 0;

		return design.total(SubsystemVariable(variable.integer)) * multiply.decimal;
	}

	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const override {
		if(targs is null)
			return;
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;

		cost += get(objTarg.obj);
	}
};
