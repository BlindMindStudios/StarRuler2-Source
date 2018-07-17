import hooks;
import orbitals;
from orbitals import IOrbitalEffect;
import buildings;
from buildings import IBuildingHook;
import constructions;
from constructions import IConstructionHook;
import resources;

#section server
from construction.Constructible import Constructible;
#section server-side
from influence_global import getSenateLeader;
#section all

class Requirement : Hook, IOrbitalEffect, IBuildingHook, IConstructionHook {
	bool meets(Object& obj, bool ignoreState = false) const {
		return true;
	}

	string getFailError(Object& obj, bool ignoreState = false) const {
		return "";
	}

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
	bool canBuildBy(Object@ obj, bool ignoreCost) const { if(obj is null) return false; return meets(obj); }
	bool canBuildAt(Object@ obj, const vec3d& pos) const { if(obj is null) return false; return meets(obj); }
	bool canBuildOn(Orbital& obj) const { if(obj is null) return false; return meets(obj); }
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
	void reverse(Object& obj, bool cancel) const {}

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
	bool canBuildOn(Object& obj, bool ignoreState = false) const { return meets(obj, ignoreState); }
	bool canRemove(Object& obj) const { return true; }
	void modBuildTime(Object& obj, double& time) const {}
	bool canProgress(Object& obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const {
		if(obj !is null && !meets(obj) && isOption) {
			sprt = icons::Remove;
			name = getFailError(obj);
			value = "";
			color = colors::Red;
			return true;
		}
		return false;
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

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const { return meets(obj, ignoreCost); }

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const {}

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return false; }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return false; }
	bool getCost(Object& obj, string& value, Sprite& icon) const { return false; }
	bool consume(Object& obj) const { return true; }
	void reverse(Object& obj) const {}
};

class RequireTrait : Requirement {
	Document doc("This requires the empire to have a specific trait.");
	Argument trait("Trait", AT_Trait, doc="Trait to require.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(!owner.hasTrait(arguments[0].integer))
			return false;
		return true;
	}
};

class RequireNotTrait : Requirement {
	Document doc("This requires the empire to not have a specific trait.");
	Argument trait("Trait", AT_Trait, doc="Trait to require.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(!owner.hasTrait(arguments[0].integer))
			return true;
		return false;
	}
};

class RequireUnlockTag : Requirement {
	Document doc("This requires the empire to have a specific unlock tag.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to check. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in the UnlockTag() or similar hook that should unlock it.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(!owner.isTagUnlocked(tag.integer))
			return false;
		return true;
	}
};

class RequireSubsystemUnlocked : Requirement {
	Document doc("This requires a particular subsystem to be unlocked.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to check.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(!owner.isUnlocked(getSubsystemDef(subsystem.integer)))
			return false;
		return true;
	}
};

class InDLC : Requirement {
	Document doc("This is a subsystem that is only available if a particular dlc is installed.");
	Argument dlc(AT_UnlockTag, doc="Name of the DLC.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(!owner.isTagUnlocked(dlc.integer))
			return false;
		return true;
	}
};

class RequireAttributeLT : Requirement {
	Document doc("This requires the empire's attribute to be less than a certain value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) >= value.decimal)
			return false;
		return true;
	}
};

class RequireAttributeGTE : Requirement {
	Document doc("This requires the empire's attribute to be greater or equal to a certain value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

	bool meets(Object& obj, bool ignoreState = false) const {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) < value.decimal)
			return false;
		return true;
	}
};

class RequireEither : Requirement {
	Document doc("This requires either of two conditions to apply");
	Argument condition_one(AT_Hook, "requirement_effects::Requirement");
	Argument condition_two(AT_Hook, "requirement_effects::Requirement");

	Requirement@ hook1;
	Requirement@ hook2;

	bool instantiate() override {
		@hook1 = cast<Requirement>(parseHook(condition_one.str, "requirement_effects::"));
		if(hook1 is null)
			error("RequireEither(): could not find first condition: "+escape(condition_one.str));
		@hook2 = cast<Requirement>(parseHook(condition_two.str, "requirement_effects::"));
		if(hook2 is null)
			error("RequireEither(): could not find second condition: "+escape(condition_two.str));
		return Requirement::instantiate();
	}

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(hook1 !is null && hook1.meets(obj))
			return true;
		if(hook2 !is null && hook2.meets(obj))
			return true;
		return false;
	}
};

class RequireNever : Requirement {
	Document doc("This requirement can never be met.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		return false;
	}
};

class ConflictBuilding : Requirement {
	Document doc("The object cannot have a building of a particular type to meet this requirement.");
	Argument building(AT_Building, doc="Building type to conflict with.");
	Argument hide(AT_Boolean, "True", doc="Hide when unavailable.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(ignoreState && !hide.boolean)
			return true;
		return obj.getBuildingCount(building.integer) == 0;
	}

	string getFailError(Object& obj, bool ignoreState = false) const {
		return format(locale::CANNOT_BUILD_CONFLICT, getBuildingType(building.integer).name);
	}
};

class RequireBuilding : Requirement {
	Document doc("This can only work if a particular building is present.");
	Argument building(AT_Building, doc="Building type to require.");
	Argument hide(AT_Boolean, "True", doc="Hide when unavailable.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(ignoreState && !hide.boolean)
			return true;
		return obj.getBuildingCount(building.integer) != 0;
	}

	string getFailError(Object& obj, bool ignoreState = false) const {
		return format(locale::CANNOT_BUILD_REQUIRE, getBuildingType(building.integer).name);
	}
};

class RequireNativeLevel : Requirement {
	Document doc("This can only work if the planet's resource is of a particular level.");
	Argument level(AT_Integer, doc="Resource level to require.");
	Argument hide(AT_Boolean, "True", doc="Hide when unavailable.");
	Argument exact(AT_Boolean, "False", doc="Filter for exactly this level, instead of at least this level.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(ignoreState && !hide.boolean)
			return true;
		if(exact.boolean)
			return obj.nativeResourceTotalLevel == uint(level.integer);
		else
			return obj.nativeResourceTotalLevel >= uint(level.integer);
	}

	string getFailError(Object& obj, bool ignoreState = false) const {
		return format(locale::CANNOT_BUILD_LEVEL, toString(level.integer));
	}
};

class RequireNativeClass : Requirement {
	Document doc("This can only work if the planet's resource has a particular class.");
	Argument cls(AT_Custom, doc="Resource class to require.");
	Argument hide(AT_Boolean, "True", doc="Hide when unavailable.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(ignoreState && !hide.boolean)
			return true;
		auto@ res = getResource(obj.primaryResourceType);
		if(res is null)
			return false;
		if(res.cls is null)
			return false;
		return res.cls.ident.equals_nocase(cls.str);
	}
};

class RequireNativePressure : Requirement {
	Document doc("This requirement can only be met if the planet has at least a specified amount of native pressure.");
	Argument required_amount(AT_Integer, "1", doc="How much native pressure is required.");
	Argument allow_money(AT_Boolean, "True", doc="Whether to count money pressure as native pressure.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(!obj.hasResources)
			return false;
		const ResourceType@ res = getResource(obj.primaryResourceType);
		if(res is null)
			return false;
		int total = 0;
		for(uint i = allow_money.boolean ? 0 : 1; i < TR_COUNT; ++i)
			total += res.tilePressure[i];
		return total >= required_amount.integer;
	}
};

class RequireMoreMoonsThanStatus : Requirement {
	Document doc("Satisfied if there are more moons than an amount of a particular status on this planet.");
	Argument status(AT_Status, doc="Status type to check for.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(!obj.isPlanet)
			return false;
		Planet@ pl = cast<Planet>(obj);
		return pl.moonCount > pl.getStatusStackCountAny(status.integer);
	}
};

class RequireStatus : Requirement {
	Document doc("Require that a particular status is present to build this.");
	Argument status(AT_Status, doc="Status type to check for.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(!obj.hasStatuses)
			return false;
		return obj.getStatusStackCountAny(status.integer) > 0;
	}
};

class RequireNotStatus : Requirement {
	Document doc("Require that a particular status is not present to build this.");
	Argument status(AT_Status, doc="Status type to check for.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if(!obj.hasStatuses)
			return false;
		return obj.getStatusStackCountAny(status.integer) == 0;
	}
};

class RequirePlanet : Requirement {
	Document doc("Can only be built on planets.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		return obj.isPlanet;
	}
};

class RequireOnOrbital : Requirement {
	Document doc("Can only be used on orbitals of a particular type.");
	Argument type(AT_OrbitalModule, doc="Orbital module to check for.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		Orbital@ orb = cast<Orbital>(obj);
		if(orb is null)
			return false;
		return orb.coreModule == uint(type.integer);
	}
};

class RequireInSystem : Requirement {
	Document doc("Can only be used inside a system.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		return obj.region !is null;
	}
};

class RequireNotManual : Requirement {
	Document doc("This cannot be manually triggered by the player.");

#section client
	bool meets(Object& obj, bool ignoreState = false) const override {
		return false;
	}
#section all
};

class RequireSenateLeader : Requirement {
	Document doc("This can only be done if you are the senate leader.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		Empire@ owner = obj.owner;
		return owner is getSenateLeader();
	}
};

class RequireConfigOption : Requirement {
	Document doc("This can only be done if a config option is a particular value.");
	Argument option(AT_Custom, doc="Config option to check.");
	Argument value(AT_Decimal, "1.0", doc="Value for the option to check for.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		return config::get(option.str) == value.decimal;
	}
};
