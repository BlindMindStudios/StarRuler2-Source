import hooks;
import systems;
import influence;
from influence import InfluenceCardEffect;
import anomalies;
import orbitals;
import artifacts;
import resources;
from anomalies import IAnomalyHook;
from abilities import IAbilityHook, Ability, AbilityHook;
import planet_levels;
import constructions;
from constructions import IConstructionHook;
import statuses;
import random_events;
import traits;

#section server
from influence_global import getInfluenceEffectOwner, canDismissInfluenceEffect;
from regions.regions import getRegion, isOutsideUniverseExtents;
from construction.Constructible import Constructible;
#section shadow
from influence_global import getInfluenceEffectOwner, canDismissInfluenceEffect;
from regions.regions import getRegion, isOutsideUniverseExtents;
#section all

interface ITargetFilter {
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const;
	string getFailReason(Object@ obj, Empire@ emp, uint index, const Target@ targ) const;

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const;
	string getFailReason(Empire@ emp, uint index, const Target@ targ) const;
};

class TargetFilter : InfluenceCardEffect, ITargetFilter, IAnomalyHook, IAbilityHook, IConstructionHook, IRandomEventHook, IRandomOptionHook {
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const { return isValidTarget(emp, index, targ); }
	string getFailReason(Object@ obj, Empire@ emp, uint index, const Target@ targ) const { return getFailReason(emp, index, targ); }

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const { return true; }
	string getFailReason(Empire@ emp, uint index, const Target@ targ) const { return ""; }

	//Anomaly hooks
	void init(AnomalyType@ type) {}
	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const {}
	bool giveOption(Anomaly@ obj, Empire@ emp) const { return true; }

	//Card hooks
	bool isValidTarget(const InfluenceCard@ card, uint index, const Target@ targets) const { return isValidTarget(card.owner, index, targets); }
	string getFailReason(const InfluenceCard@ card, uint index, const Target@ targets) const { return getFailReason(card.owner, index, targets); }

	//Ability hooks
	void create(Ability@ abl, any@ data) const {}
	void destroy(Ability@ abl, any@ data) const {}
	void enable(Ability@ abl, any@ data) const {}
	void disable(Ability@ abl, any@ data) const {}
	void tick(Ability@ abl, any@ data, double time) const {}
	void save(Ability@ abl, any@ data, SaveFile& file) const {}
	void load(Ability@ abl, any@ data, SaveFile& file) const {}
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {}
	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const {}

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const { return getFailReason(abl.obj, abl.emp, index, targ); }
	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override { return isValidTarget(abl.obj, abl.emp, index, targ); }
	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const { return true; }
	void activate(Ability@ abl, any@ data, const Targets@ targs) const {}

	bool consume(Ability@ abl, any@ data, const Targets@ targs) const { return true; }
	void reverse(Ability@ abl, any@ data, const Targets@ targs) const {}
	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override { return false; }
	bool isChanneling(const Ability@ abl, const any@ data) const { return false; }

	//Construction effects
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {}
#section all

	void save(Construction@ cons, any@ data, SaveFile& file) const {}
	void load(Construction@ cons, any@ data, SaveFile& file) const {}

	bool consume(Construction@ cons, any@ data, const Targets@ targs) const { return true; }
	void reverse(Construction@ cons, any@ data, const Targets@ targs, bool reverse) const {}

	string getFailReason(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return getFailReason(obj, obj.owner, index, targ); }
	bool isValidTarget(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return isValidTarget(obj, obj.owner, index, targ); }

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const { return true; }

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const {}

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return false; }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return false; }

	//Random events
	bool consider(CurrentEvent& evt) const { return true; }
	void create(CurrentEvent& evt) const {}
	bool isValidTarget(CurrentEvent& evt, uint index, const Target@ targ) const {
		return isValidTarget(evt.owner, index, targ);
	}

	bool shouldAdd(CurrentEvent& evt, const EventOption& option) const {
		for(uint i = 0, cnt = evt.targets.length; i < cnt; ++i) {
			if(!isValidTarget(evt.owner, i, evt.targets[i]))
				return false;
		}
		return true;
	}
	void trigger(CurrentEvent& evt, const EventOption& option, const Target@ targ) const {}
};

//TargetFilterOtherEmpire(<Target>)
// Filter <Target> to only allow other, valid, empires.
class TargetFilterOtherEmpire : TargetFilter {
	Document doc("Restricts targets to being owned by another (real) empire.");
	Argument targ(TT_Any);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		if(targ.obj is null || targ.obj.owner is null || !targ.obj.owner.valid)
			return locale::NTRG_NOT_SPACE;
		return locale::NTRG_NOT_SELF;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Empire@ check;
		if(targ.type == TT_Object) {
			Object@ obj = targ.obj;
			if(obj is null)
				return false;
			if(obj.isStar) {
				uint mask = obj.region.TradeMask;
				return mask != 0 && mask != uint(emp.mask);
			}
			else if(obj.isRegion) {
				uint mask = cast<Region>(obj).TradeMask;
				return mask != 0 && mask != uint(emp.mask);
			}
			else {
				@check = obj.owner;
			}
		}
		else if(targ.type == TT_Empire) {
			@check = targ.emp;
		}
		else if(targ.type == TT_Effect) {
			@check = getInfluenceEffectOwner(targ.id);
		}
		if(check is null || !check.valid || check is emp)
			return false;
		return true;
	}
};

class TargetFilterDismissableByOwner : TargetFilter {
	Document doc("Only allow effects that the owner can dismiss.");
	Argument targ(TT_Effect);

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		return canDismissInfluenceEffect(targ.id);
	}
};

//TargetFilterRegionOtherEmpire(<Target>)
// Filter <Target> to only allow other, valid, empires.
class TargetFilterRegionOtherEmpire : TargetFilter {
	Document doc("Restricts targets to being in regions owned by another (real) empire.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		if(targ.obj is null || targ.obj.owner is null || !targ.obj.owner.valid)
			return locale::NTRG_NOT_SPACE;
		return locale::NTRG_NOT_SELF;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		if(!obj.isRegion)
			@obj = obj.region;
		if(obj is null)
			return false;
		uint mask = cast<Region>(obj).TradeMask;
		return mask != 0 && mask != uint(emp.mask);
	}
};

//TargetFilterRegion(<Target>)
// Indicates that the target should be the region the system is in.
class TargetFilterRegion : TargetFilter {
	Document doc("Redirects target to be the region of the targeted object.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_REGION;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		return reg !is null;
	}

	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Target@ targ = arguments[0].fromTarget(targets);
		if(targ is null || targ.obj is null)
			return;
		if(targ.obj.isRegion)
			return;
		@targ.obj = targ.obj.region;
	}
};

class TargetFilterInSystem : TargetFilter {
	Document doc("Restricts target to positions located within a system.");
	Argument point(TT_Point);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_IN_SYSTEM;
	}

#section game
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		auto@ reg = getRegion(targ.point);
		if(reg is null)
			return false;
		auto@ sys = getSystem(reg);
		return sys !is null;
	}
#section all
};

class TargetFilterNotInSystem : TargetFilter {
	Document doc("Restricts target to positions outside a system.");
	Argument point(TT_Point);
	Argument radius("Radius", AT_Decimal, "0", doc="Check for systems within a radius of the point.");
	Argument flattened(AT_Boolean, "True", doc="Whether to check for overlap on the flattened plane.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NOT_SYSTEM;
	}

#section game
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(radius.decimal <= 1.0) {
			auto@ reg = getRegion(targ.point);
			return reg is null;
		}
		else if(flattened.boolean) {
			vec2d flatPoint(targ.point.x, targ.point.z);
			for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
				auto@ sys = getSystem(i);
				vec2d flatTarget(sys.position.x, sys.position.z);
				if(flatPoint.distanceToSQ(flatTarget) < sqr(sys.radius + radius.decimal))
					return false;
			}
			return true;
		}
		else {
			for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
				auto@ sys = getSystem(i);
				if(sys.position.distanceToSQ(targ.point) < sqr(sys.radius + radius.decimal))
					return false;
			}
			return true;
		}
	}
#section all
};

class TargetFilterInUniverseBounds : TargetFilter {
	Document doc("Restricts target to positions within the universe bounds.");
	Argument point(TT_Point);
	Argument margin("Margin", AT_Decimal, "500", doc="Margin from the universe's maximum system bounds.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_IN_UNIVERSE;
	}

#section game
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		return !isOutsideUniverseExtents(targ.point, margin.decimal);
	}
#section all
};

class TargetFilterMovableTo : TargetFilter {
	Document doc("The targeted point must be a location the object can actually move to.");
	Argument point(TT_Point);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_IN_SYSTEM;
	}

#section game
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		auto@ reg = getRegion(targ.point);
		if(reg is null) {
			if(emp.ForbidDeepSpace != 0)
				return false;
		}
		auto@ sys = getSystem(reg);
		if(sys is null) {
			if(emp.ForbidDeepSpace != 0)
				return false;
		}
		return true;
	}
#section all
};

//TargetFilterHasTradePresence(<Target>, <Allow Adjacent> = True)
// Filter <Target> to only allow objects we have trade presence near.
class TargetFilterHasTradePresence : TargetFilter {
	Document doc("Restricts target to regions with the empire's trade presence.");
	Argument targ(TT_Object);
	Argument adjacent("Allow Adjacent", AT_Decimal, "True", doc="Whether to allow the target if adjacent regions have trade presence.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_TRADE_PRESENCE;
	}

#section game
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			@reg = obj.region;
		if(reg is null)
			return false;
		if(reg.TradeMask & emp.TradeMask.value == 0) {
			if(!arguments[1].boolean)
				return false;
			const SystemDesc@ sys = getSystem(reg);
			if(sys !is null) {
				bool found = false;
				for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
					const SystemDesc@ other = getSystem(sys.adjacent[i]);
					if(other.object.TradeMask & emp.TradeMask.value != 0) {
						found = true;
						break;
					}
				}
				if(!found)
					return false;
			}
		}
		return true;
	}
#section all
};

//TargetFilterNotWar(<Target>)
// Filter <Target> to only allow other, valid, empires that you are not at war with.
class TargetFilterNotWar : TargetFilter {
	Document doc("Restricts target to empires not at war with the source empire.");
	Argument targ(TT_Any);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NOT_WAR;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.type == TT_Object) {
			Object@ obj = targ.obj;
			if(obj is null)
				return false;
			Empire@ owner = obj.owner;
			if(owner is null || !owner.valid || owner is emp)
				return false;
			if(emp.isHostile(owner))
				return false;
			return true;
		}
		else if(targ.type == TT_Empire) {
			Empire@ other = targ.emp;
			if(other is null || !other.valid || other is emp)
				return false;
			if(emp.isHostile(other))
				return false;
			return true;
		}
		return false;
	}
};

class TargetFilterWar : TargetFilter {
	Document doc("Restricts target to empires at war with the source empire.");
	Argument targ(TT_Any);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NEED_WAR;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.type == TT_Object) {
			Object@ obj = targ.obj;
			if(obj is null)
				return false;
			Empire@ owner = obj.owner;
			if(owner is null || !owner.valid || owner is emp)
				return false;
			if(!emp.isHostile(owner))
				return false;
			return true;
		}
		else if(targ.type == TT_Empire) {
			Empire@ other = targ.emp;
			if(other is null || !other.valid || other is emp)
				return false;
			if(!emp.isHostile(other))
				return false;
			return true;
		}
		return false;
	}
};

class TargetFilterAttackable : TargetFilter {
	Document doc("Restricts target to empires which could be attacked.");
	Argument targ(TT_Any);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NEED_WAR;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.type == TT_Object) {
			Object@ obj = targ.obj;
			if(obj is null)
				return false;
			Empire@ owner = obj.owner;
			if(owner is null)
				return false;
			if(owner is emp || !owner.valid)
				return true;
			if(!emp.isHostile(owner))
				return false;
			return true;
		}
		else if(targ.type == TT_Empire) {
			Empire@ other = targ.emp;
			if(other is null)
				return false;
			if(other is emp || !other.valid)
				return true;
			if(!emp.isHostile(other))
				return false;
			return true;
		}
		return false;
	}
};

//TargetFilterType(<Target>, <Type>)
// Filter <Target> to only allow objects of <Type>.
class TargetFilterType : TargetFilter {
	Document doc("Restricts target to a specific types of objects.");
	Argument targ(TT_Object);
	Argument adjacent("Type", AT_Custom, "True", doc="What type of object to check for.");
	int typeId = -1;

	bool instantiate() override {
		typeId = getObjectTypeId(arguments[1].str);
		if(typeId == -1) {
			error("Invalid object type: "+arguments[1].str);
			return false;
		}
		return TargetFilter::instantiate();
	}

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_TYPE, localize("#OT_"+getObjectTypeName(typeId)));
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		if(obj is null)
			return false;
		return obj.type == typeId;
	}
};

//TargetFilterOrbitalCore(<Target>, <Types>...)
// Filter <Target> to only allow orbitals with a core among the specified <Types>.
class TargetFilterOrbitalCore : TargetFilter {
	Document doc("Restricts target to orbitals with a core among any of the specified cores.");
	
	TargetFilterOrbitalCore() {
		target("Target", TT_Object);
		varargs(AT_OrbitalModule, true);
	}

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_ORBITAL_CORE, getOrbitalModule(arguments[1].integer).name);
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Orbital@ orb = cast<Orbital>(targ.obj);
		if(orb is null)
			return false;
		for(uint i = 1, cnt = arguments.length; i < cnt; ++i)
			if(orb.coreModule == uint(arguments[i].integer))
				return true;
		return false;
	}
};

//TargetFilterFlagship(<Target>)
// Filter <Target> to only allow flagships.
class TargetFilterFlagship : TargetFilter {
	Document doc("Restricts target to flagships.");
	Argument targ(TT_Object);
	Argument allow_null(AT_Boolean, "False", doc="Whether to allow the ability to be triggered on nulls (for example, for toggle deactivates.)");
	Argument allow_stations(AT_Boolean, "True", doc="Whether to count stations as flagships.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_FLAGSHIP;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		if(obj is null)
			return allow_null.boolean;
		if(!obj.isShip || !obj.hasLeaderAI)
			return false;
		if(!allow_stations.boolean && cast<Ship>(obj).isStation)
			return false;
		return true;
	}
};

class TargetFilterStation : TargetFilter {
	Document doc("Restricts target to designed stations.");
	Argument targ(TT_Object);
	Argument allow_null(AT_Boolean, "False", doc="Whether to allow the ability to be triggered on nulls (for example, for toggle deactivates.)");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_STATION;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		if(obj is null)
			return allow_null.boolean;
		return obj.isShip && obj.hasLeaderAI && cast<Ship>(obj).isStation;
	}
};

//TargetRequireVision(<Target>)
// Only allow this card to be played if the empire has vision of the target.
class TargetRequireVision : TargetFilter {
	Document doc("Restricts target to visible objects.");
	Argument targ(TT_Object);
	Argument region_vision(AT_Boolean, "False", doc="Require vision in this region.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_VISION;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		Object@ obj = targ.obj;
		if(region_vision.boolean && !obj.isRegion)
			@obj = obj.region;
		if(obj is null)
			return false;
		if(obj.isRegion)
			return cast<Region>(obj).VisionMask & emp.visionMask != 0;
		else if(region_vision.boolean)
			return false;
#section server-side
		else
			return obj.isVisibleTo(emp);
#section client-side
		else
			return obj.visible;
#section all
	}
};

//TargetFilterCardUses(<Target>, <Uses>, <Allow Unlimited> = False)
// Filter cards that have <Uses> available.
class TargetFilterCardUses : TargetFilter {
	Document doc("Restricts target to cards with uses available.");
	Argument targ(TT_Card);
	Argument useCount("Uses", AT_Integer, "1", doc="Minimum available uses to require.");
	Argument unlimited("Allow Unlimited", AT_Boolean, "False", doc="Allow cards with unlimited uses.");

	bool isValidTarget(const InfluenceCard@ card, uint index, const Target@ targ) const {
		if(index != uint(arguments[0].integer))
			return true;
		int uses = card.owner.getInfluenceCardUses(targ.id);
		if(uses < 0)
			return unlimited.boolean;
		if(card.id == targ.id)
			uses -= 1;
		return uses >= useCount.integer;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		int uses = emp.getInfluenceCardUses(targ.id);
		if(uses < 0)
			return unlimited.boolean;
		return uses >= useCount.integer;
	}
};

//TargetFilterHasQuality(<Card>)
// Filter cards that support quality.
class TargetFilterHasQuality : TargetFilter {
	Document doc("Restricts target to cards that can have quality.");
	Argument targ(TT_Card);

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		auto@ type = getInfluenceCardType(emp.getInfluenceCardType(targ.id));
		if(type is null)
			return false;
		return type.maxQuality > type.minQuality;
	}
};

//TargetFilterUpgradableQuality(<Card>, <Add Quality> = 0)
// Only allow cards that can still be upgraded in quality.
class TargetFilterUpgradableQuality : TargetFilter {
	Document doc("Restricts target to cards that can have their quality improved.");
	Argument targ(TT_Card);
	Argument quality("Add Quality", AT_Integer, "1", doc="Amount of quality levels to add.");

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		auto@ type = getInfluenceCardType(emp.getInfluenceCardType(targ.id));
		if(type is null)
			return false;
		int qual = emp.getInfluenceCardQuality(targ.id);
		if(qual >= type.maxQuality) {
			if(!type.canOverquality || qual >= type.maxQuality + quality.integer)
				return false;
		}
		return true;
	}
};

//TargetFilterOwned(<Target>)
// Only allow objects you own into <Target>.
class TargetFilterOwned : TargetFilter {
	Document doc("Restricts target to objects owned by the source empire.");
	Argument targ(TT_Object);
	Argument allow_null(AT_Boolean, "False", doc="Whether to allow the ability to be triggered on nulls (for example, for toggle deactivates.)");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_OWNED;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return allow_null.boolean;
		if(targ.obj.isStar) {
			Region@ region = targ.obj.region;
			if(region is null)
				return false;
			return region.TradeMask & emp.mask != 0;
		}
		else if(targ.obj.isRegion) {
			return cast<Region>(targ.obj).TradeMask & emp.mask != 0;
		}
		else {
#section client-side
			if(targ.obj.hasSurfaceComponent) {
				if(targ.obj.visibleOwner is emp)
					return true;
			}
			else {
				if(targ.obj.owner is emp)
					return true;
			}
#section server-side
			if(targ.obj.owner is emp)
				return true;
#section all
			return false;
		}
	}
};

class TargetFilterAllied : TargetFilter {
	Document doc("Restricts target to objects owned by the source empire or its allies.");
	Argument targ(TT_Object);
	Argument allow_null(AT_Boolean, "False", doc="Whether to allow the ability to be triggered on nulls (for example, for toggle deactivates.)");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_ALLIED;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return allow_null.boolean;
		if(targ.obj.isStar) {
			Region@ region = targ.obj.region;
			if(region is null)
				return false;
			return region.TradeMask & (emp.mask | emp.ForcedPeaceMask.value) != 0;
		}
		else if(targ.obj.isRegion) {
			return cast<Region>(targ.obj).TradeMask & (emp.mask | emp.ForcedPeaceMask.value) != 0;
		}
		else {
			return targ.obj.owner is emp || (targ.obj.owner.mask & emp.ForcedPeaceMask.value) != 0;
		}
	}
};

class TargetFilterNotAllied : TargetFilter {
	Document doc("Restricts target to objects not owned by the source empire or its allies.");
	Argument targ(TT_Object);
	Argument allow_null(AT_Boolean, "False", doc="Whether to allow the ability to be triggered on nulls (for example, for toggle deactivates.)");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NOT_ALLIED;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return allow_null.boolean;
		if(targ.obj.isStar) {
			Region@ region = targ.obj.region;
			if(region is null)
				return false;
			return region.TradeMask & (emp.mask | emp.ForcedPeaceMask.value) == 0;
		}
		else if(targ.obj.isRegion) {
			return cast<Region>(targ.obj).TradeMask & (emp.mask | emp.ForcedPeaceMask.value) == 0;
		}
		else {
			return targ.obj.owner !is emp && (targ.obj.owner.mask & emp.ForcedPeaceMask.value) == 0;
		}
	}
};

class TargetFilterNotQuarantined : TargetFilter {
	Document doc("Restricts target to planets that are not quarantined.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NO_COLONIZE;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(targ.obj.isPlanet)
			return !targ.obj.quarantined;
		return false;
	}
};

class TargetFilterHasConstruction : TargetFilter {
	Document doc("Only allow objects that support construction with labor.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_CONSTRUCTION;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		return targ.obj.hasConstruction;
	}
};

//TargetFilterRegionOwned(<Target>)
// Only allow systems you control into <Target>.
class TargetFilterRegionOwned : TargetFilter {
	Document doc("Restricts target to regions owned by the source empire.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_OWNED;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		Object@ obj = targ.obj;
		if(!obj.isRegion)
			@obj = obj.region;
		if(obj is null)
			return false;
		return cast<Region>(obj).TradeMask & emp.mask != 0;
	}
};

//TargetFilterOwnsAllPlanets(<Target>)
// Only allow systems you fully control into <Target>.
class TargetFilterOwnsAllPlanets : TargetFilter {
	Document doc("Restricts target to region where all planets are owned by the source empire.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_OWN_SYSTEM;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		Object@ obj = targ.obj;
		if(!obj.isRegion)
			@obj = obj.region;
		Region@ region = cast<Region>(obj);
		if(region is null)
			return false;
		return region.getPlanetCount(emp) == region.planetCount;
	}
};

//TargetFilterOccupied(<Target>)
// Only allow objects owned by an empire into <Target>.
class TargetFilterOccupied : TargetFilter {
	Document doc("Restricts target to objects owned by an empire.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NOT_SPACE;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null || !targ.obj.owner.valid)
			return false;
		return true;
	}
};

class TargetFilterCreeps : TargetFilter {
	Document doc("Restricts target to objects owned by the creeps.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_SPACE;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
#section client-side
		if(targ.obj.hasSurfaceComponent) {
			Empire@ owner = targ.obj.visibleOwner;
			if(owner is null)
				return true;
			return !owner.major && owner.valid;
		}
		else {
			if(!targ.obj.owner.major && targ.obj.owner.valid)
				return true;
		}
#section server-side
		if(!targ.obj.owner.major && targ.obj.owner.valid)
			return true;
#section all
		return false;
	}
};

class TargetFilterSpace : TargetFilter {
	Document doc("Restricts target to objects owned by space.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_SPACE;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
#section client-side
		if(targ.obj.hasSurfaceComponent) {
			Empire@ owner = targ.obj.visibleOwner;
			if(owner is null || !owner.valid)
				return true;
		}
		else {
			if(!targ.obj.owner.valid)
				return true;
		}
#section server-side
		if(!targ.obj.owner.valid)
			return true;
#section all
		return false;
	}
};

//TargetFilterUnnamed(<Target>)
// Only allow objects that have not been named.
class TargetFilterUnnamed : TargetFilter {
	Document doc("Restricts target to objects without a special name.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_UNNAMED;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null || targ.obj.named)
			return false;
		return true;
	}
};

//TargetFilterNotStatus(<Target>, <Status>)
// Only allow objects that do not have a particular status.
class TargetFilterNotStatus : TargetFilter {
	Document doc("Restricts target to objects with a particular status.");
	Argument targ(TT_Object);
	Argument status("Status", AT_Status, doc="Status to require.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_STATUS;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasStatuses)
			return false;
		if(targ.obj.hasStatusEffect(status.integer))
			return false;
		return true;
	}
};

//TargetFilterNotFTL(<Target>)
// Only allow objects not in FTL
class TargetFilterNotFTL : TargetFilter {
	Document doc("Restricts target to objects not currently in FTL.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_FTL;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasMover)
			return true;
		return !targ.obj.inFTL;
	}
};

//TargetFilterPlanetLevelBelow(<Target>, <Level>)
// Only allow targeted planets below level <Level>.
class TargetFilterPlanetLevelBelow : TargetFilter {
	Document doc("Restricts target to planets below a certain level.");
	Argument targ(TT_Object);
	Argument level("Level", AT_Integer, doc="Level the planet must be below.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_PLLEV, toString(arguments[1].integer-1));
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		return targ.obj.level < uint(level.integer);
	}
};

class TargetFilterPlanetLevel : TargetFilter {
	Document doc("Restricts target to planets at leasto f a certain level.");
	Argument targ(TT_Object);
	Argument level("Level", AT_Integer, doc="Level the planet must be at or higher.");
	Argument exact(AT_Boolean, "False", doc="Only allow the exact specified level.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		if(exact.boolean)
			return format(locale::NTRG_PLLEVE, toString(level.integer));
		else
			return format(locale::NTRG_PLLEVA, toString(level.integer));
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(exact.boolean)
			return targ.obj.level == uint(level.integer);
		else
			return targ.obj.level >= uint(level.integer);
	}
};

class TargetFilterResourceLevel : TargetFilter {
	Document doc("Restricts target to planets with resources of at least a certain level.");
	Argument targ(TT_Object);
	Argument level("Level", AT_Integer, doc="Level the planet must be at or higher.");
	Argument exact(AT_Boolean, "False", doc="Only allow the exact specified level.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		if(exact.boolean)
			return format(locale::NTRG_RSLEVE, toString(level.integer));
		else
			return format(locale::NTRG_RSLEVA, toString(level.integer));
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasSurfaceComponent)
			return false;
		if(exact.boolean)
			return targ.obj.primaryResourceLevel == uint(level.integer);
		else
			return targ.obj.primaryResourceLevel >= uint(level.integer);
	}
};

//TargetFilterCanTerraform(<Target>, <Level>)
// Only allow targeting things that can be terraformed.
class TargetFilterCanTerraform : TargetFilter {
	Document doc("Restricts target to planets that can be terraformed.");
	Argument targ(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_TERRAFORM;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasResources)
			return false;
		return targ.obj.nativeResourceType[0] != uint(-1);
	}
};

//TargetFilterArtifactNatural(<Target>, <Natural>)
// Only allow artifacts that are <Natural>.
class TargetFilterArtifactNatural : TargetFilter {
	Document doc("Restricts target to artifacs which are either natural or artificial.");
	Argument targ(TT_Object);
	Argument isNatural("Natural", AT_Boolean, doc="Whether artifacts must be natural or artificial.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		if(arguments[1].boolean)
			return locale::NTRG_NATURAL;
		else
			return locale::NTRG_NOT_NATURAL;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(arguments[0].integer))
			return true;
		if(targ.obj is null)
			return false;
		Artifact@ artif = cast<Artifact>(targ.obj);
		if(artif is null)
			return false;
		return getArtifactType(artif.ArtifactType).natural == isNatural.boolean;
	}
};

//RequireContact()
// Only allow playing this if we're in contact with at least one other empire.
class RequireContact : TargetFilter {
	Document doc("Restricts activation if the empire doesn't have contact with at least one empire not on its team.");
	Argument allow_team(AT_Boolean, "False", doc="Whether to count empires in the same team as contact.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_CONTACT;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		uint aloneCount = 0;
		int prevTeam = -1;
		bool multipleTeams = false;
		
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(emp.team < 0)
				++aloneCount;
			else if(emp.team != prevTeam) {
				if(prevTeam != -1)
					multipleTeams = emp.team != prevTeam;
				prevTeam = emp.team;
			}
			
			if(!allow_team.boolean && emp.team >= 0 && other.team == emp.team)
				continue;
			if(emp !is other && emp.ContactMask & other.mask != 0)
				return true;
		}
		
		if(multipleTeams)
			aloneCount += 1;
		if(prevTeam != -1)
			aloneCount += 1;
		return aloneCount == 1;
	}
};

class TargetFilterResourceNonUnique : TargetFilter {
	Document doc("Only allow targeting planets whose primary resource is not a unique resource.");
	Argument objTarget(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_UNIQUE;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasResources)
			return false;

		auto@ type = getResource(targ.obj.primaryResourceType);
		if(type is null)
			return false;
		return type.rarity < RR_Unique && !type.unique;
	}
};

class TargetFilterResourceNonArtificial : TargetFilter {
	Document doc("Only allow targeting planets whose primary resource is not an artificial resource.");
	Argument objTarget(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_ARTIFICIAL;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasResources)
			return false;

		auto@ type = getResource(targ.obj.primaryResourceType);
		if(type is null)
			return false;
		return !type.artificial;
	}
};

class TargetFilterResourceNot : TargetFilter {
	Document doc("Only allow targeting planets whose primary resource is not the specified resource.");
	Argument objTarget(TT_Object);
	Argument resource(AT_PlanetResource, doc="Resource to disallow targeting.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		auto@ res = getResource(resource.integer);
		if(res !is null)
			return format(locale::NTRG_CANNOT, res.name);
		return "-";
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasResources)
			return false;

		auto@ type = getResource(targ.obj.primaryResourceType);
		if(int(type.id) == resource.integer)
			return false;
		return true;
	}
};

class TargetFilterSelf : AbilityHook {
	Document doc("Only allow this ability to target the object that is casting it.");
	Argument objTarget(TT_Object);

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const override {
		return locale::NTRG_OWNED;
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj !is abl.obj)
			return false;
		return true;
	}
};

class TargetFilterNotSelf : AbilityHook {
	Document doc("do not allow this ability to target the object that is casting it.");
	Argument objTarget(TT_Object);

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const override {
		return locale::NTRG_NOT_SELF;
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override {
		if(index != uint(objTarget.integer))
			return true;
		if(targ.obj is abl.obj)
			return false;
		return true;
	}
};

class ForClient : TargetFilter {
	Document doc("These target filters only apply on the UI.");
	Argument condition(AT_Hook, "target_filters::TargetFilter");

	TargetFilter@ hook1;

	bool instantiate() override {
		@hook1 = cast<TargetFilter>(parseHook(condition.str, "target_filters::"));
		if(hook1 is null)
			error("ForClient could not find first condition: "+escape(condition.str));
		return TargetFilter::instantiate();
	}

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const override {
#section client-side
		if(hook1 !is null && !hook1.isValidTarget(abl, index, targ))
			return hook1.getFailReason(abl, index, targ);
#section all
		return "";
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override {
#section client-side
		if(hook1 !is null && !hook1.isValidTarget(abl, index, targ))
			return false;
#section all
		return true;
	}
};

class Either : TargetFilter {
	Document doc("Allow targets that pass either of the inner target filters.");
	Argument condition_one(AT_Hook, "target_filters::TargetFilter");
	Argument condition_two(AT_Hook, "target_filters::TargetFilter");

	TargetFilter@ hook1;
	TargetFilter@ hook2;

	bool instantiate() override {
		@hook1 = cast<TargetFilter>(parseHook(condition_one.str, "target_filters::"));
		if(hook1 is null)
			error("Either(): could not find first condition: "+escape(condition_one.str));
		@hook2 = cast<TargetFilter>(parseHook(condition_two.str, "target_filters::"));
		if(hook2 is null)
			error("Either(): could not find second condition: "+escape(condition_two.str));
		return TargetFilter::instantiate();
	}

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const override {
		if(hook1 !is null && !hook1.isValidTarget(abl, index, targ))
			return hook1.getFailReason(abl, index, targ);
		if(hook2 !is null && hook2.isValidTarget(abl, index, targ))
			return hook2.getFailReason(abl, index, targ);
		return "";
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override {
		if(hook1 !is null && hook1.isValidTarget(abl, index, targ))
			return true;
		if(hook2 !is null && hook2.isValidTarget(abl, index, targ))
			return true;
		return false;
	}
};

class Both : TargetFilter {
	Document doc("Allow targets that pass both of the inner target filters.");
	Argument condition_one(AT_Hook, "target_filters::TargetFilter");
	Argument condition_two(AT_Hook, "target_filters::TargetFilter");

	TargetFilter@ hook1;
	TargetFilter@ hook2;

	bool instantiate() override {
		@hook1 = cast<TargetFilter>(parseHook(condition_one.str, "target_filters::"));
		if(hook1 is null)
			error("Either(): could not find first condition: "+escape(condition_one.str));
		@hook2 = cast<TargetFilter>(parseHook(condition_two.str, "target_filters::"));
		if(hook2 is null)
			error("Either(): could not find second condition: "+escape(condition_two.str));
		return TargetFilter::instantiate();
	}

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const override {
		if(hook1 !is null && !hook1.isValidTarget(abl, index, targ))
			return hook1.getFailReason(abl, index, targ);
		if(hook2 !is null && hook2.isValidTarget(abl, index, targ))
			return hook2.getFailReason(abl, index, targ);
		return "";
	}

	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const override {
		if(hook1 !is null && !hook1.isValidTarget(abl, index, targ))
			return false;
		if(hook2 !is null && !hook2.isValidTarget(abl, index, targ))
			return false;
		return true;
	}
};

class TargetFilterSameTerritory : TargetFilter {
	Document doc("Only allow targets in the same territory as the casting object.");
	Argument object(TT_Object);
	Argument allow_same_region(AT_Boolean, "False", doc="Whether to allow activation outside territory in the same system.");
	Argument allow_within_trade(AT_Boolean, "True", doc="Whether to count trade borders as part of a territory.");

	string getFailReason(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_TERRITORY;
	}

#section game
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(object.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(emp is null || obj is null)
			return false;

		auto@ myRegion = obj.region;
		if(myRegion is null)
			@myRegion = getRegion(obj.position);
		auto@ targRegion = targ.obj.region;
		if(targRegion is null)
			@targRegion = getRegion(targ.obj.position);
		if(myRegion is null || targRegion is null)
			return false;
		if(allow_same_region.boolean && myRegion is targRegion)
			return true;

		auto@ myTerritory = myRegion.getTerritory(emp);
		auto@ targTerritory = targRegion.getTerritory(emp);
		if(myTerritory is null) {
			if(!allow_within_trade.boolean)
				return false;
			if(targTerritory !is null) {
				auto@ sys = getSystem(myRegion);
				for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
					auto@ other = getSystem(sys.adjacent[i]);
					if(other.object.getTerritory(emp) is targTerritory)
						return true;
				}
			}
			else {
				auto@ sys = getSystem(myRegion);
				auto@ targSys = getSystem(targRegion);
				for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
					auto@ other = getSystem(sys.adjacent[i]);
					auto@ otherTerritory = other.object.getTerritory(emp);
					if(otherTerritory !is null) {
						for(uint i = 0, cnt = targSys.adjacent.length; i < cnt; ++i) {
							auto@ other = getSystem(targSys.adjacent[i]);
							if(other.object.getTerritory(emp) is otherTerritory)
								return true;
						}
					}
				}
			}
		}
		else {
			if(targTerritory is myTerritory)
				return true;
			if(!allow_within_trade.boolean)
				return false;
			auto@ sys = getSystem(targRegion);
			for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
				auto@ other = getSystem(sys.adjacent[i]);
				if(other.object.getTerritory(emp) is myTerritory)
					return true;
			}
		}
		return false;
	}
#section all
};

class TargetFilterSameRegion : TargetFilter {
	Document doc("Only allow targets in the same region/system as the casting object.");
	Argument object(TT_Object);

	string getFailReason(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_SAME_REGION;
	}

#section game
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(object.integer))
			return true;
		if(targ.obj is null)
			return false;
		Region@ myRegion = obj.region;
		Region@ targRegion = targ.obj.region;
		return myRegion !is null && myRegion is targRegion;
	}
#section all
};

class TargetFilterMinimumMaxPopulation : TargetFilter {
	Document doc("Only allow planets with at least a specific amount of max population.");
	Argument object(TT_Object);
	Argument amount(AT_Integer, doc="Amount to require.");

	string getFailReason(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_MIN_MAXPOP, toString(amount.integer, 0));
	}

#section game
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(object.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasSurfaceComponent)
			return false;
		return int(targ.obj.maxPopulation) >= amount.integer;
	}
#section all
};

class TargetFilterBelowLimitMaxPop : TargetFilter {
	Document doc("Only allow planets with population below their native maximum population.");
	Argument object(TT_Object);

#section game
	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(object.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasSurfaceComponent)
			return false;

		double curPop = targ.obj.population;
		double maxPop = max(double(targ.obj.maxPopulation), double(getPlanetLevel(targ.obj, targ.obj.primaryResourceLevel).population));
		return curPop < maxPop;
	}
#section all
};

class TargetFilterNotInCombat : TargetFilter {
	Document doc("Target cannot be currently in combat.");
	Argument object(TT_Object);

	bool isValidTarget(Object@ obj, Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(object.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(targ.obj.inCombat)
			return false;
		return true;
	}
};

class TargetFilterCargoStorage : TargetFilter {
	Document doc("Only allow targets that have cargo storage.");
	Argument objTarg(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_CARGO;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarg.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasCargo)
			return false;
		if(targ.obj.cargoCapacity < 0.001)
			return false;
		return true;
	}
};

class TargetFilterHasCargoStored : TargetFilter {
	Document doc("Only allow targets that have some cargo stored.");
	Argument objTarg(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_CARGO;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarg.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasCargo)
			return false;
		if(targ.obj.cargoStored < 0.001)
			return false;
		return targ.obj.cargoTypes != 0;
	}
};

class TargetFilterNotHomeSystem : TargetFilter {
	Document doc("Only target objects that are not in a home system.");
	Argument objTarg(TT_Object);
	Argument only_mine(AT_Boolean, "False", doc="Only disallow targets in _my_ home system.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_NO_HOME;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarg.integer))
			return true;
		if(targ.obj is null)
			return false;
		Region@ reg = cast<Region>(targ.obj);
		if(reg is null)
			@reg = targ.obj.region;
		if(reg is null)
			return true;
		if(only_mine.boolean) {
			if(emp is null)
				return true;
			Object@ home = emp.Homeworld;
			if(home !is null) {
				if(home.region is reg)
					return false;
			}
		}
		else {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Object@ home = getEmpire(i).Homeworld;
				if(home !is null) {
					if(home.region is reg)
						return false;
				}
			}
		}
		return true;
	}
};

class TargetFilterHasTrait : TargetFilter {
	Document doc("Only allow targets that are ane empire or have an owner that has a trait.");
	Argument targID(TT_Any);
	Argument trait(AT_Trait, doc="Trait to select for.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_REQUIRE, getTrait(trait.integer).name);
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(targID.integer))
			return true;
		Empire@ check;
		if(targ.type == TT_Empire) {
			@check = targ.emp;
		}
		else if(targ.type == TT_Object) {
			if(targ.obj is null)
				return false;
			@check = targ.obj.owner;
		}
		if(check is null)
			return false;
		return check.hasTrait(trait.integer);
	}
};

class TargetFilterRace : TargetFilter {
	Document doc("Only allow targets that have an empire that is of a particular race.");
	Argument targID(TT_Any);
	Argument trait(AT_Trait, doc="Trait to select for on human empires.");
	Argument name(AT_Locale, doc="Race name to require for AI empires.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_REQUIRE, getTrait(trait.integer).name);
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(targID.integer))
			return true;
		Empire@ check;
		if(targ.type == TT_Empire) {
			@check = targ.emp;
		}
		else if(targ.type == TT_Object) {
			if(targ.obj is null)
				return false;
			@check = targ.obj.owner;
		}
		if(check is null)
			return false;
		if(check.isAI)
			return check.RaceName == name.str;
		else
			return check.hasTrait(trait.integer);
	}
};

class TargetFilterDesignTag : TargetFilter {
	Document doc("Only allow targets with a specific tag on their design.");
	Argument targID(TT_Object);
	Argument tag(AT_Custom, doc="Tag for the design.");
	int tagId = -1;

	bool instantiate() override {
		tagId = getSubsystemTag(tag.str);
		return TargetFilter::instantiate();
	}

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return format(locale::NTRG_REQUIRE, tag.str);
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(targID.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.isShip)
			return false;
		auto@ dsg = cast<Ship>(targ.obj).blueprint.design;
		if(dsg is null)
			return false;
		return dsg.hasTag(SubsystemTag(tagId));
	}
};

class TargetFilterFewerStatusesThanVar : TargetFilter {
	Document doc("Only allow targets with fewer of a status than a variable on their design.");
	Argument targID(TT_Object);
	Argument status(AT_Status, doc="Status to check.");
	Argument variable(AT_SysVar, doc="Variable to add as labor cost.");

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		auto@ type = getStatusType(status.integer);
		if(type is null)
			return "-";
		return format(locale::NTRG_STORAGE_FULL, type.name);
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(targID.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.isShip)
			return false;
		auto@ dsg = cast<Ship>(targ.obj).blueprint.design;
		if(dsg is null)
			return false;
		if(!targ.obj.hasStatuses)
			return false;

		int max = dsg.total(SubsystemVariable(variable.integer));
		int cur = targ.obj.getStatusStackCount(status.integer);
		return cur < max;
	}
};
