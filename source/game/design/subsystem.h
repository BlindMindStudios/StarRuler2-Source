#pragma once
#include "design/effect.h"
#include "design/effector.h"
#include "vec2.h"
#include "util/formula.h"
#include "util/basic_type.h"
#include "compat/misc.h"
#include "render/spritesheet.h"
#include <string>
#include <vector>
#include <unordered_set>
#include "util/hex_grid.h"

class SaveFile;

#ifndef MODIFY_STAGE_MAXARGS
#define MODIFY_STAGE_MAXARGS 8
#endif

enum SysVariableType {
	SVT_SubsystemVariable,
	SVT_HexVariable,
	SVT_ShipVariable,
};

enum TemplateCondition {
	TC_Tag,
	TC_Modifier,
	TC_Variable,
	TC_HexVariable,
	TC_ShipVariable,
	TC_Subsystem,

	TC_NOT = 1<<20,
};

class Design;
class Subsystem;
class HullDef;
class SubsystemDef {
public:
	struct Variable {
		Formula* formula;
		std::string str_formula;
		std::string name;
		int index;
		int globalId;
		SysVariableType type;
		bool dependent;
	};

	struct Effect {
		const EffectDef* type;
		std::vector<Formula*> values;
		std::vector<std::string> str_values;
	};

	struct Effector {
		const EffectorDef* type;
		bool enabled;
		unsigned skinIndex;
		std::string skinName;
		std::vector<Formula*> values;
		std::vector<std::string> str_values;
	};

	struct StateDesc {
		BasicTypes type;
		Formula* formula;
		std::string str_formula;
	};

	struct HookDesc {
		std::string name;
		std::vector<std::string> str_args;
		std::vector<Formula*> formulas;
		mutable std::vector<double> argValues;

		HookDesc() {}
		HookDesc(const std::string& str);
	};

	struct ModifyStage {
		unsigned index;
		int stage;
		int umodifid;
		std::unordered_map<std::string, int> argumentNames;
		std::vector<std::pair<int, std::string>> str_variables;
		std::vector<std::pair<int, std::string>> str_hexVariables;
		std::vector<std::pair<int, std::string>> str_shipVariables;
		std::unordered_map<int, Formula*> variables;
		std::unordered_map<int, Formula*> hexVariables;
		std::unordered_map<int, Formula*> shipVariables;

		ModifyStage() : stage(0), umodifid(-1), index(0) {}

		void applyVariables(Subsystem* sys) const;
		void applyHexVariables(Subsystem* sys, int hexIndex) const;
		void applyShipVariables(Design* dsg, Subsystem* sys) const;
	};

	struct AppliedStage {
		const ModifyStage* stage;
		float arguments[MODIFY_STAGE_MAXARGS];
		Formula* formulas[MODIFY_STAGE_MAXARGS];

		void clear() {
			for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i) {
				if(formulas[i]) {
					delete formulas[i];
					formulas[i] = 0;
				}
			}
		}

		AppliedStage() {
			memset(this, 0, sizeof(AppliedStage));
		}
	};

	struct ShipModifier {
		AppliedStage stage;
		std::string modifyName;
		std::vector<std::string> str_arguments;
		std::vector<std::pair<int,std::string>> conditions;
	};

	struct Assert {
		std::string str_formula;
		Formula* formula;
		std::string message;
		bool fatal;
		bool unique;
	};

	struct ModuleDesc {
		int index;
		std::string id;
		std::string name;
		std::string description;
		Color color;

		std::string umodident;
		int umodid;

		std::string def_onEnable;
		std::string def_onDisable;

		asIScriptFunction* scr_onEnable;
		asIScriptFunction* scr_onDisable;

		std::vector<ModifyStage> modifiers;
		std::vector<ModifyStage> uniqueModifiers;

		std::vector<AppliedStage> appliedStages;
		std::vector<std::string> str_appliedStages;

		std::vector<AppliedStage> uniqueAppliedStages;
		std::vector<std::string> str_uniqueAppliedStages;

		std::vector<AppliedStage> hexAppliedStages;
		std::vector<std::string> str_hexAppliedStages;

		std::vector<SubsystemDef::ShipModifier> adjacentModifiers;
		std::vector<SubsystemDef::Effect> effects;

		std::unordered_set<std::string> tags;
		std::unordered_set<int> numTags;
		std::unordered_map<int, std::vector<std::string>> tagValues;

		bool hasTag(const std::string& tag) const;
		bool hasTag(int index) const;
		const std::string& getTagValue(int index, unsigned num = 0) const;
		unsigned getTagValueCount(int index) const;
		bool hasTagValue(int index, const std::string& value) const;

		std::string def_onCheckErrors;
		asIScriptFunction* scr_onCheckErrors;

		bool onCheckErrors(Design* design, Subsystem* sys, const vec2u& hex) const;

		std::vector<HookDesc> hooks;
		std::vector<Assert> asserts;

		std::string spriteMat;
		render::Sprite sprite;
		int drawMode;

		bool required;
		bool unique;
		bool vital;
		bool defaultUnlock;

		void onEnable(EffectEvent& evt, const vec2u& position) const;
		void onDisable(EffectEvent& evt, const vec2u& position) const;

		ModuleDesc()
			: index(-1), scr_onEnable(0), scr_onDisable(0),
				drawMode(0), required(false), unique(false), vital(false),
				defaultUnlock(false), scr_onCheckErrors(nullptr) {
		}
	};

	std::string name;
	std::string description;
	std::string id;
	int index;
	int ordering;
	int damageOrder;

	int elevation;
	Color baseColor;
	Color typeColor;

	std::string hexMat;
	std::string picMat;
	render::Sprite picture;

	std::vector<int> variableIndices;
	std::vector<SubsystemDef::Variable> variables;
	std::vector<int> hexVariableIndices;
	std::vector<SubsystemDef::Variable> hexVariables;
	std::vector<int> shipVariableIndices;
	std::vector<SubsystemDef::Variable> shipVariables;

	std::vector<SubsystemDef::Effect> effects;
	std::vector<SubsystemDef::Effector> effectors;
	std::vector<SubsystemDef::StateDesc> states;
	std::vector<SubsystemDef::ModuleDesc*> modules;
	std::vector<SubsystemDef::ShipModifier> shipModifiers;
	std::vector<SubsystemDef::ShipModifier> postModifiers;
	std::vector<SubsystemDef::ShipModifier> adjacentModifiers;
	std::unordered_map<std::string, int> moduleIndices;
	const SubsystemDef::ModuleDesc* defaultModule;
	const SubsystemDef::ModuleDesc* coreModule;

	std::vector<ModifyStage*> modifiers;
	std::unordered_map<std::string, ModifyStage*> modifierIds;
	std::vector<Assert> asserts;

	uset<std::string> tags;
	std::vector<std::string> hullTags;

	uset<int> numTags;
	std::unordered_map<int, std::vector<std::string>> tagValues;

	void finalize();
	bool hasTag(const std::string& tag) const;
	bool hasTag(int index) const;
	const std::string& getTagValue(int index, unsigned num = 0) const;
	unsigned getTagValueCount(int index) const;
	bool hasTagValue(int index, const std::string& value) const;

	std::string def_onCheckErrors;
	asIScriptFunction* scr_onCheckErrors;

	std::vector<HookDesc> hooks;

	bool onCheckErrors(Design* design, Subsystem* sys) const;
	bool canUseOn(const HullDef* hull) const;
	bool hasHullTag(const std::string& tag) const;

	bool hasCore;
	bool isContiguous;
	bool exteriorCore;
	bool defaultUnlock;
	bool isHull;
	bool isApplied;
	bool hexLimitArc;
	bool passExterior;
	bool fauxExterior;
	bool alwaysTakeDamage;

	SubsystemDef();
	~SubsystemDef();
};

extern int SV_Size, HV_Resistance, HV_HP, ShV_HexSize;
extern umap<std::string, int> subsystemIndices;
extern umap<std::string, int> variableIndices;
extern umap<std::string, int> hexVariableIndices;
extern umap<std::string, int> shipVariableIndices;

void clearSubsystemDefinitions();
void loadSubsystemDefinitions(const std::string& filename);
const SubsystemDef* getSubsystemDef(const std::string& name);
const SubsystemDef* getSubsystemDef(int id);
int getSubsystemDefCount();
void enumerateVariables(std::function<void(const std::string&,int)>);
int getVariableIndex(const std::string& name);
const std::string& getVariableId(int index);
void enumerateHexVariables(std::function<void(const std::string&,int)>);
int getHexVariableIndex(const std::string& name);
const std::string& getHexVariableId(int index);
void enumerateShipVariables(std::function<void(const std::string&,int)>);
unsigned getShipVariableCount();
int getShipVariableIndex(const std::string& name);
const std::string& getShipVariableId(int index);
void enumerateSysTags(std::function<void(const std::string&,int)>);
int getSysTagIndex(const std::string& name, bool create = false);

Formula* parseFormula(const std::string& str, const SubsystemDef* def = 0, const SubsystemDef::ModifyStage* modifier = 0);

void bindSubsystemMaterials();
void bindSubsystemHooks();
void finalizeSubsystems();
void executeSubsystemTemplates();

class Blueprint;
struct SubsystemEvent {
	const Subsystem* subsystem;
	const Design* design;
	Object* obj;
	Blueprint* blueprint;
	void* data;
	float efficiency;
	float partiality;
};

class asIScriptFunction;
class asIScriptObject;
class SaveMessage;
class Subsystem {
public:
	const SubsystemDef* type;
	std::vector<vec2u> hexes;
	std::vector<const SubsystemDef::ModuleDesc*> modules;
	std::vector<SubsystemDef::ShipModifier> adjacentModifiers;
	std::vector<std::vector<SubsystemDef::ShipModifier>> hexAdjacentModifiers;
	std::vector<int> moduleCounts;
	vec2u core;
	vec3d direction;
	int exteriorHexes;
	bool hasErrors;

	static asIScriptFunction* ScriptInitFunction;
	static asIScriptFunction* ScriptHookFunctions[EH_COUNT];

	Effector* effectors;
	float* variables;
	float* baseVariables;
	float* hexVariables;
	float* hexBaseVariables;
	BasicType* defaults;
	unsigned stateOffset;
	unsigned effectorOffset;
	unsigned dataOffset;

	std::vector<Effect> effects;
	std::vector<std::vector<unsigned>> hexEffects;

	std::vector<asIScriptObject*> hookClasses;
	void addHook(Design* design, const SubsystemDef::HookDesc& desc);

	const Design* inDesign;
	unsigned index;

	int getModuleCount(int index);
	
	float* variable(int index);
	const float* variable(int index) const;
	float* hexVariable(int index, int hexIndex);
	const float* hexVariable(int index, int hexIndex) const;

	Subsystem();
	Subsystem(const SubsystemDef& def);
	Subsystem(SaveFile& file);
	~Subsystem();
	void save(SaveFile& file) const;
	void postLoad(Design* design);

	void init(const SubsystemDef& def);
	void init(SaveFile& file);

	void initVariables(Design* design);
	void initEffects(Design* design);
	void initLinks(Design* design);
	void evaluatePost(Design* design);
	void evaluateAsserts(Design* design);
	void skinEffectors(Empire& emp);
	void applyAdjacencies(Design* design);

	DamageEventStatus damage(DamageEvent& event, const vec2u& position) const;
	DamageEventStatus globalDamage(DamageEvent& event, vec2u& position, vec2d& endPoint) const;
	bool hasGlobalDamage() const;

	void ownerChange(EffectEvent& event, Empire* prevEmpire, Empire* newEmpire) const;
	void call(EffectHook hook, EffectEvent& event) const;
	void tick(EffectEvent& event) const;

	void save(EffectEvent& event, SaveMessage& msg) const;
	void load(EffectEvent& event, SaveMessage& msg) const;

	void markConnected(HexGrid<bool>& grid, vec2u hex);

	void writeData(net::Message& msg) const;
	Subsystem(net::Message& msg);
};
