import hooks;
import buildings;
from buildings import IBuildingHook;
import abilities;
from abilities import IAbilityHook;
import statuses;
from statuses import IStatusHook;
import util.formatting;
import icons;
import constructions;
from constructions import IConstructionHook;

#section server
from construction.Constructible import Constructible;
#section all

class ListedValue : Hook, IBuildingHook, IAbilityHook, IStatusHook, IConstructionHook {
	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		return false;
	}

	//For use as an ability hook
	void create(Ability@ abl, any@ data) const {}
	void destroy(Ability@ abl, any@ data) const {}
	void enable(Ability@ abl, any@ data) const {}
	void disable(Ability@ abl, any@ data) const {}
	void tick(Ability@ abl, any@ data, double time) const {}
	void save(Ability@ abl, any@ data, SaveFile& file) const {}
	void load(Ability@ abl, any@ data, SaveFile& file) const {}
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {}
	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const {}

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const { return ""; }
	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const { return true; }
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const { return true; }
	void activate(Ability@ abl, any@ data, const Targets@ targs) const {}

	bool consume(Ability@ abl, any@ data, const Targets@ targs) const { return true; }
	void reverse(Ability@ abl, any@ data, const Targets@ targs) const {}
	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const {
		return getVariable(abl.obj, abl.emp, sprt, name, value, color);
	}
	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override { return false; }
	bool isChanneling(const Ability@ abl, const any@ data) const { return false; }

	//Lets this be used as a building hook
	void initialize(BuildingType@ type, uint index) {}
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void complete(Object& obj, SurfaceBuilding@ bld) const {}
	void remove(Object& obj, SurfaceBuilding@ bld) const {}
	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const {}
	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {}
	bool canBuildOn(Object& obj, bool ignoreState = false) const { return true; }
	bool canRemove(Object& obj) const { return true; }
	void save(SurfaceBuilding@ bld, SaveFile& file) const {}
	void load(SurfaceBuilding@ bld, SaveFile& file) const {}
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const {
		return getVariable(obj, obj !is null ? obj.owner : playerEmpire, sprt, name, value, color);
	}
	void modBuildTime(Object& obj, double& time) const {}
	bool canProgress(Object& obj) const { return true; }

	//Status hooks
	void onCreate(Object& obj, Status@ status, any@ data) {}
	void onDestroy(Object& obj, Status@ status, any@ data) {}
	void onObjectDestroy(Object& obj, Status@ status, any@ data) {}
	bool onTick(Object& obj, Status@ status, any@ data, double time) { return true; }
	void onAddStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	void onRemoveStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) { return true; }
	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion) { return true; }
	void save(Status@ status, any@ data, SaveFile& file) {}
	void load(Status@ status, any@ data, SaveFile& file) {}
	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color) const {
		return getVariable(obj, obj !is null ? obj.owner : playerEmpire, sprt, name, value, color);
	}

	//Constructions
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {}
#section all

	void save(Construction@ cons, any@ data, SaveFile& file) const {}
	void load(Construction@ cons, any@ data, SaveFile& file) const {}

	bool consume(Construction@ cons, any@ data, const Targets@ targs) const { return true; }
	void reverse(Construction@ cons, any@ data, const Targets@ targs, bool cancel) const {}

	string getFailReason(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return ""; }
	bool isValidTarget(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return true; }

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const { return true; }

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const {}

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const { return getVariable(obj, obj.owner, sprt, name, value, color); }
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return false; }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return false; }
	bool getCost(Object& obj, string& value, Sprite& icon) const { return false; }
	bool consume(Object& obj) const { return true; }
	void reverse(Object& obj) const {}
};

class ShowValue : ListedValue {
	Document doc("Show a value in the tooltip.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument amount(AT_Decimal, doc="Amount of the value.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		sprt = getSprite(this.icon.str);
		name = this.name.str;
		value = standardize(this.amount.decimal, true);
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class ShowAttributeValue : ListedValue {
	Document doc("Show a value in the tooltip.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute of the value to show.");
	Argument base_amount(AT_Decimal, "0", doc="Base amount to add independent of the attribute value.");
	Argument multiplier(AT_Decimal, "1.0", doc="Multiplier to the attribute value to add to the base amount and show.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");
	Argument hide_zero(AT_Boolean, "False", doc="Don't show the attribute if it is zero.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		Empire@ owner = emp;
		if(obj !is null && owner is null)
			@owner = obj.owner;

		double v = base_amount.decimal;
		if(owner !is null)
			v += multiplier.decimal * owner.getAttribute(attribute.integer);
		if(v == 0 && hide_zero.boolean)
			return false;

		sprt = getSprite(this.icon.str);
		name = this.name.str;
		value = standardize(v, true);
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class ShowEnergyValue : ListedValue {
	Document doc("Show an energy value in the tooltip.");
	Argument amount(AT_Decimal, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_ENERGY", doc="Name of the value.");
	Argument apply_penalty(AT_Boolean, "True", doc="Whether the value should be multiplied by the current energy storage penalty.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		double v = amount.decimal;
		Empire@ owner = emp;
		if(obj !is null && owner is null)
			@owner = obj.owner;
		if(owner !is null && apply_penalty.boolean)
			v *= owner.EnergyEfficiency;

		sprt = icons::Energy;
		color = colors::Energy;
		name = this.name.str;
		value = toString(v, 0);
		return true;
	}
};

class ShowMoneyValue : ListedValue {
	Document doc("Show a money value in the tooltip.");
	Argument amount(AT_Integer, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_MONEY", doc="Name of the value.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		sprt = icons::Money;
		color = colors::Money;
		name = this.name.str;
		value = formatMoney(amount.integer);
		return true;
	}
};

class ShowInfluenceValue : ListedValue {
	Document doc("Show an influence value in the tooltip.");
	Argument amount(AT_Integer, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_INFLUENCE", doc="Name of the value.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		sprt = icons::Influence;
		color = colors::Influence;
		name = this.name.str;
		value = toString(amount.integer, 0);
		return true;
	}
};

class ShowResearchValue : ListedValue {
	Document doc("Show a research value in the tooltip.");
	Argument amount(AT_Decimal, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_RESEARCH", doc="Name of the value.");
	Argument apply_efficiency(AT_Boolean, "True", doc="Whether the value should be multiplied by the current research efficiency.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		double v = amount.decimal;
		Empire@ owner = emp;
		if(obj !is null && owner is null)
			@owner = obj.owner;
		if(owner !is null && apply_efficiency.boolean)
			v *= owner.ResearchEfficiency;

		sprt = icons::Research;
		color = colors::Research;
		name = this.name.str;
		value = toString(v, 0);
		return true;
	}
};

class ShowLaborValue : ListedValue {
	Document doc("Show a labor value in the tooltip.");
	Argument amount(AT_Decimal, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_LABOR", doc="Name of the value.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		sprt = icons::Labor;
		color = colors::Labor;
		name = this.name.str;
		value = toString(amount.decimal, 0);
		return true;
	}
};

class ShowShipSizeValue : ListedValue {
	Document doc("Show a value in the tooltip based on ship size.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument amount(AT_Decimal, "0", doc="Base amount of the value.");
	Argument per_shipsize(AT_Decimal, "0", doc="When on a ship, increase the value by the ship design size multiplied by this.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		sprt = getSprite(this.icon.str);
		name = this.name.str;

		double v = this.amount.decimal;
		if(per_shipsize.decimal != 0 && obj !is null && obj.isShip)
			v += cast<Ship>(obj).blueprint.design.size * per_shipsize.decimal;

		value = standardize(v, true);
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class ShowTotalPopulation : ListedValue {
	Document doc("Show the empire's total population.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		Empire@ owner = emp;
		if(obj !is null && owner is null)
			@owner = obj.owner;

		double v = 0;
		if(owner !is null)
			v = owner.TotalPopulation;

		sprt = getSprite(this.icon.str);
		name = this.name.str;
		value = standardize(v, true);
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class ShowLevelValue : ListedValue {
	Document doc("Show a value dependent on the planet level of the object.");
	Argument name(AT_Locale, doc="Name of the value.");
	Argument values(AT_Locale, doc="Values for each level.");
	Argument icon(AT_Sprite, EMPTY_DEFAULT, doc="Icon to show for the value");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");
	Argument color(AT_Color, EMPTY_DEFAULT, doc="Color of the value's name.");
	Argument value_color(AT_Color, "#00c0ff", doc="Color of the highlighted value.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		uint lv = 0;
		if(obj !is null && obj.hasSurfaceComponent)
			lv = obj.level;

		sprt = getSprite(this.icon.str);
		name = this.name.str;
		value = format("[levels=$1;$22]", lv, value_color.str);
		value += values.str;
		value += "[/levels]";
		if(this.color.str.length != 0)
			color = toColor(this.color.str);
		return true;
	}
};

class ShowFTLValue : ListedValue {
	Document doc("Show an FTL value in the tooltip.");
	Argument amount(AT_Decimal, doc="Amount of the value.");
	Argument name(AT_Locale, "#RESOURCE_FTL", doc="Name of the value.");
	Argument suffix(AT_Locale, EMPTY_DEFAULT, doc="Suffix behind the value.");

	bool getVariable(Object@ obj, Empire@ emp, Sprite& sprt, string& name, string& value, Color& color) const {
		double v = amount.decimal;
		Empire@ owner = emp;
		if(obj !is null && owner is null)
			@owner = obj.owner;

		sprt = icons::FTL;
		color = colors::FTL;
		name = this.name.str;
		value = standardize(v, true);
		if(suffix.str.length != 0)
			value += " "+suffix.str;
		return true;
	}
};

