import buildings;
from buildings import IBuildingHook;
import resources;
import anomalies;
import camps;
import research;
import buildings;
import artifacts;
import random_events;
import util.formatting;
import systems;
import saving;
import influence;
from attitudes import Attitude, IAttitudeHook;
from influence import InfluenceStore, IInfluenceEffectEffect;
from statuses import IStatusHook, Status, StatusInstance;
from resources import integerSum, decimalSum;
from traits import ITraitEffect;
from influence import InfluenceStore;
from pickups import IPickupHook;
from anomalies import IAnomalyHook;
from abilities import Ability, IAbilityHook;
from research import ITechnologyHook;
import constructions;
from constructions import IConstructionHook;
import orbitals;
from orbitals import IOrbitalEffect;
import attributes;
import hook_globals;
import research;

#section server
from construction.Constructible import Constructible;
#section all

tidy class GenericEffect : Hook, IResourceHook, IBuildingHook, IStatusHook, IOrbitalEffect, SubsystemHook, RegionChangeable, LeaderChangeable {
	uint hookIndex = 0;

	//Generic reusable hooks
	void enable(Object& obj, any@ data) const {}
	void disable(Object& obj, any@ data) const {}
	void tick(Object& obj, any@ data, double time) const {}
	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {}
	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {}
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}

	//Lets this be used as a resource hook
	void initialize(ResourceType@ type, uint index) { hookIndex = index; }
	bool canTerraform(Object@ from, Object@ to) const { return true; }
	void applyGraphics(Object& obj, Node& node) const {}
	void onTerritoryAdd(Object& obj, Resource@ r, Territory@ terr) const {}
	void onTerritoryRemove(Object& obj, Resource@ r, Territory@ terr) const {}
	bool get_hasEffect() const { return false; }
	bool mergesEffect(Object& obj, const IResourceHook@ other) const {
		if(getClass(other) !is getClass(this))
			return false;
		return mergesEffect(cast<const GenericEffect>(other));
	}
	bool mergesEffect(const GenericEffect@ eff) const { return true; }
	string formatEffect(Object& obj, array<const IResourceHook@>& hooks) const { return "---"; }
	const IResourceHook@ get_carriedHook() const { return null; }
	const IResourceHook@ get_displayHook() const { return this; }
	void onGenerate(Object& obj, Resource@ native) const {}
	void nativeTick(Object&, Resource@ native, double time) const {}
	void onDestroy(Object&, Resource@ native) const {}
	void nativeSave(Resource@ native, SaveFile& file) const {}
	void nativeLoad(Resource@ native, SaveFile& file) const {}
	bool shouldVanish(Object& obj, Resource@ native) const { return false; }
	void onAdd(Object& obj, Resource@ r) const { enable(obj, r.data[hookIndex]); }
	void onRemove(Object& obj, Resource@ r) const { disable(obj, r.data[hookIndex]); }
	void onTick(Object& obj, Resource@ r, double time) const { tick(obj, r.data[hookIndex], time); }
	void onTradeDeliver(Civilian& civ, Object@ origin, Object@ target) const {}
	void onTradeDestroy(Civilian& civ, Object@ origin, Object@ target, Object@ destroyer) const {}
	void onOwnerChange(Object& obj, Resource@ r, Empire@ prevOwner, Empire@ newOwner) const {
		ownerChange(obj, r.data[hookIndex], prevOwner, newOwner);
	}
	void onRegionChange(Object& obj, Resource@ r, Region@ fromRegion, Region@ toRegion) const {
		regionChange(obj, r.data[hookIndex], fromRegion, toRegion);
	}
	void save(Resource@ r, SaveFile& file) const {
		save(r.data[hookIndex], file);
	}
	void load(Resource@ r, SaveFile& file) const {
		load(r.data[hookIndex], file);
	}

	//Lets this be used as a building hook
	void initialize(BuildingType@ type, uint index) { hookIndex = index; }
	void startConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void cancelConstruction(Object& obj, SurfaceBuilding@ bld) const {}
	void complete(Object& obj, SurfaceBuilding@ bld) const { enable(obj, bld.data[hookIndex]); }
	void remove(Object& obj, SurfaceBuilding@ bld) const { disable(obj, bld.data[hookIndex]); }
	void ownerChange(Object& obj, SurfaceBuilding@ bld, Empire@ prevOwner, Empire@ newOwner) const {
		ownerChange(obj, bld.data[hookIndex], prevOwner, newOwner);
	}
	void tick(Object& obj, SurfaceBuilding@ bld, double time) const {
		tick(obj, bld.data[hookIndex], time);
	}
	bool canBuildOn(Object& obj, bool ignoreState = false) const { return true; }
	bool canRemove(Object& obj) const { return true; }
	void save(SurfaceBuilding@ bld, SaveFile& file) const { save(bld.data[hookIndex], file); }
	void load(SurfaceBuilding@ bld, SaveFile& file) const { load(bld.data[hookIndex], file); }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color, bool isOption) const {
		return false;
	}
	bool getCost(Object& obj, string& value, Sprite& icon) const { return false; }
	void modBuildTime(Object& obj, double& time) const {}
	bool canProgress(Object& obj) const { return true; }

	//Lets this be used as a status hook
	// Planet effects do not deal with status stacks, so they will only
	// trigger once per status, regardless of collapsing.
	void onCreate(Object& obj, Status@ status, any@ data) { enable(obj, data); }
	void onDestroy(Object& obj, Status@ status, any@ data) { disable(obj, data); }
	void onObjectDestroy(Object& obj, Status@ status, any@ data) {}
	bool onTick(Object& obj, Status@ status, any@ data, double time) { tick(obj, data, time); return true; }
	void onAddStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	void onRemoveStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) {
		ownerChange(obj, data, prevOwner, newOwner); return true; }
	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion) {
		regionChange(obj, data, prevRegion, newRegion); return true; }
	void save(Status@ status, any@ data, SaveFile& file) { save(data, file); }
	void load(Status@ status, any@ data, SaveFile& file) { load(data, file); }
	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool consume(Object& obj) const { return true; }
	void reverse(Object& obj) const {}

	//Lets this be used as an orbital hook
	void onEnable(Orbital& obj, any@ data) const { enable(obj, data); }
	void onDisable(Orbital& obj, any@ data) const { disable(obj, data); }
	void onCreate(Orbital& obj, any@ data) const {}
	void onDestroy(Orbital& obj, any@ data) const {}
	void onTick(Orbital& obj, any@ data, double time) const { tick(obj, data, time); }
	void onOwnerChange(Orbital& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		ownerChange(obj, data, prevOwner, newOwner);
	}
	void onRegionChange(Orbital& obj, any@ data, Region@ prevRegion, Region@ newRegion) const {
		regionChange(obj, data, prevRegion, newRegion);
	}
	void onMakeGraphics(Orbital& obj, any@ data, OrbitalNode@ node) const {}
	bool checkRequirements(OrbitalRequirements@ reqs, bool apply) const { return true; }
	void revertRequirements(OrbitalRequirements@ reqs) const {}
	bool canBuildBy(Object@ obj, bool ignoreCost) const { return true; }
	bool canBuildOn(Orbital& obj) const { return true; }
	bool shouldDisable(Orbital& obj, any@ data) const { return false; }
	bool shouldEnable(Orbital& obj, any@ data) const { return true; }
	void onKill(Orbital& obj, any@ data, Empire@ killedBy) const {}
	void write(any@ data, Message& msg) const {}
	void read(any@ data, Message& msg) const {}
	bool getValue(Player& pl, Orbital& obj, any@ data, uint index, double& value) const { return false; }
	bool sendValue(Player& pl, Orbital& obj, any@ data, uint index, double value) const { return false; }
	bool getDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@& value) const { return false; }
	bool sendDesign(Player& pl, Orbital& obj, any@ data, uint index, const Design@ value) const { return false; }
	bool getObject(Player& pl, Orbital& obj, any@ data, uint index, Object@& value) const { return false; }
	bool sendObject(Player& pl, Orbital& obj, any@ data, uint index, Object@ value) const { return false; }
	bool getData(Orbital& obj, string& txt, bool enabled) const { return false; }
	bool canBuildAt(Object@ obj, const vec3d& pos) const { return true; }
	string getBuildError(Object@ obj, const vec3d& pos) const { return ""; }
	void reverse(Object& obj, bool cancel) const {}

	//Subsystem hooks
	void start(SubsystemEvent& event) const { enable(event.obj, event.data); }
	void tick(SubsystemEvent& event, double time) const { tick(event.obj, event.data, time); }
	void suspend(SubsystemEvent& event) const { disable(event.obj, event.data); }
	void resume(SubsystemEvent& event) const { enable(event.obj, event.data); }
	void destroy(SubsystemEvent& event) const {}
	void end(SubsystemEvent& event) const { disable(event.obj, event.data); }
	void change(SubsystemEvent& event) const {}
	void ownerChange(SubsystemEvent& event, Empire@ prevOwner, Empire@ newOwner) const {
		ownerChange(event.obj, event.data, prevOwner, newOwner);
	}
	void regionChange(SubsystemEvent& event, Region@ prevRegion, Region@ newRegion) const {
		regionChange(event.obj, event.data, prevRegion, newRegion);
	}
	void leaderChange(SubsystemEvent& event, Object@ prevLeader, Object@ newLeader) const {}

	DamageEventStatus damage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position) const {
		return DE_Continue;
	}

	DamageEventStatus globalDamage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position, vec2d& endPoint) const {
		return DE_Continue;
	}

	void preRetrofit(SubsystemEvent& event) const {}
	void postRetrofit(SubsystemEvent& event) const {}
	void save(SubsystemEvent& event, SaveFile& file) const { save(event.data, file); }
	void load(SubsystemEvent& event, SaveFile& file) const { load(event.data, file); }
};

interface TriggerableGeneric {
};

interface RegionChangeable {
	void regionChange(SubsystemEvent& event, Region@ prevRegion, Region@ newRegion) const;
};

interface LeaderChangeable {
	void leaderChange(SubsystemEvent& event, Object@ prevLeader, Object@ newLeader) const;
};

interface ShowsRange {
	bool getShowRange(Object& obj, double& range, Color& color) const;
};

tidy class EmpireEffect : GenericEffect, IInfluenceEffectEffect, ITraitEffect, IAttitudeHook {
	void enable(Empire& emp, any@ data) const {}
	void disable(Empire& emp, any@ data) const {}
	void tick(Empire& emp, any@ data, double time) const {}
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}
	
	//Generic effects on objects
	void enable(Object& obj, any@ data) const { if(obj.owner !is null) enable(obj.owner, data); }
	void disable(Object& obj, any@ data) const { if(obj.owner !is null) disable(obj.owner, data); }
	void tick(Object& obj, any@ data, double time) const { if(obj.owner !is null) tick(obj.owner, data, time); }
	void ownerChange(Object& obj, any@ data, Empire@ prevOwner, Empire@ newOwner) const {
		if(prevOwner !is null)
			disable(prevOwner, data);
		if(newOwner !is null)
			enable(newOwner, data);
	}
	void regionChange(Object& obj, any@ data, Region@ fromRegion, Region@ toRegion) const {}

	//Influence effects
	void set_dataIndex(uint ind) { hookIndex = ind; }

	void init(InfluenceEffectType@ type) {}
	void onStart(InfluenceEffect@ effect) const { enable(effect.owner, effect.data[hookIndex]); }
	bool onTick(InfluenceEffect@ effect, double time) const { tick(effect.owner, effect.data[hookIndex], time); return false; }
	void onDismiss(InfluenceEffect@ effect, Empire@ byEmpire) const {}
	void onEnd(InfluenceEffect@ effect) const { disable(effect.owner, effect.data[hookIndex]); }
	bool canDismiss(const InfluenceEffect@ effect, Empire@ byEmpire) const { return true; }
	void save(InfluenceEffect@ effect, SaveFile& file) const { save(effect.data[hookIndex], file); }
	void load(InfluenceEffect@ effect, SaveFile& file) const { load(effect.data[hookIndex], file); }

	//Trait effects
	void preInit(Empire& emp, any@ data) const {}
	void init(Empire& emp, any@ data) const { enable(emp, data); }
	void postInit(Empire& emp, any@ data) const {}

	//Attitude effects
	Ability@ showAbility(Attitude& att, Empire& emp, Ability@ abl) const { return null; }
	bool canTake(Empire& emp) const { return true; }

	void enable(Attitude& att, Empire& emp, any@ data) const { enable(emp, data); }
	void disable(Attitude& att, Empire& emp, any@ data) const { disable(emp, data); }
	void tick(Attitude& att, Empire& emp, any@ data, double time) const { tick(emp, data, time); }
};

tidy class BonusEffect : Hook, IPickupHook, IAnomalyHook, IAbilityHook, IConstructionHook, IRandomOptionHook {
	void activate(Object@ obj, Empire@ emp) const {};

	//For use as pickup hook
	bool canPickup(Pickup& pickup, Object& obj) const { return true; }
	void onPickup(Pickup& pickup, Object& obj) const { activate(obj, obj.owner); }
	void onClear(Pickup& pickup, Object& obj) const {}

	//For use as an anomaly hook
	void init(AnomalyType@ type) {}
	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const override { activate(obj, emp); }
	bool giveOption(Anomaly@ obj, Empire@ emp) const override { return true; }
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const { return true; }

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
	void activate(Ability@ abl, any@ data, const Targets@ targs) const { activate(abl.obj, abl.emp); }

	bool consume(Ability@ abl, any@ data, const Targets@ targs) const { return true; }
	void reverse(Ability@ abl, any@ data, const Targets@ targs) const {}
	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const override { return false; }
	bool isChanneling(const Ability@ abl, const any@ data) const { return false; }

	//Construction effects
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const { activate(cons.obj, cons.obj.owner); }
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

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return false; }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return false; }

	//Random events
	bool shouldAdd(CurrentEvent& evt, const EventOption& option) const { return true; }
	void trigger(CurrentEvent& evt, const EventOption& option, const Target@ targ) const {
		if(targ is null)
			activate(null, evt.owner);
		else if(targ.type == TT_Object && targ.obj !is null)
			activate(targ.obj, evt.owner);
		else if(targ.type == TT_Empire && targ.emp !is null)
			activate(null, targ.emp);
		else
			activate(null, evt.owner);
	}
};

tidy class EmpireTrigger : BonusEffect, ITraitEffect, ITechnologyHook, IAttitudeHook {
	//For use as a trait effect
	void preInit(Empire& emp, any@ data) const {}
	void init(Empire& emp, any@ data) const override { activate(null, emp); }
	void postInit(Empire& emp, any@ data) const {}
	void tick(Empire& emp, any@ data, double time) const {}
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}

	//For use as a technology hook
	void unlock(TechnologyNode@ node, Empire& emp) const { activate(null, emp); }
	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const { return false; }
	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const { return true; }
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const { return true; }
	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {}
	bool canUnlock(TechnologyNode@ node, Empire& emp) const { return true; }
	bool canBeSecret(TechnologyNode@ node, Empire& emp) const { return true; }
	void onStateChange(TechnologyNode@ node, Empire@ emp) const {}
	void tick(TechnologyNode@ node, Empire& emp, double time) const {}
	void addToDescription(TechnologyNode@ node, Empire@ emp, string& description) const {}
	void modPointCost(const TechnologyNode@ node, Empire& emp, double& pointCost) const {}
	void modTimeCost(const TechnologyNode@ node, Empire& emp, double& timeCost) const {}

	//Attitude hooks
	Ability@ showAbility(Attitude& att, Empire& emp, Ability@ abl) const { return null; }
	bool canTake(Empire& emp) const { return true; }

	void enable(Attitude& att, Empire& emp, any@ data) const { activate(null, emp); }
	void disable(Attitude& att, Empire& emp, any@ data) const {}
	void tick(Attitude& att, Empire& emp, any@ data, double time) const {}
};

