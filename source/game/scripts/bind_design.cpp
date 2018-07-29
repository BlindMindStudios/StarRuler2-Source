#include "scripts/binds.h"
#include "scripts/manager.h"
#include "design/design.h"
#include "design/effect.h"
#include "obj/blueprint.h"
#include "empire.h"
#include "main/references.h"
#include "network/network_manager.h"
#include "util/lockless_type.h"
#include "util/save_file.h"
#include "scriptarray.h"
#include "scriptany.h"
#include <assert.h>

extern double effVariable(void* effector, const std::string* name);
namespace scripts {

static HullDef* makeHull() {
	return new HullDef();
}

static Shipset* makeShipset() {
	return new Shipset();
}

static HullDef* makeHull_cpy(const HullDef& other) {
	return new HullDef(other);
}

static void readHulls(const std::string& fname, CScriptArray& array) {
	std::vector<HullDef*> hulls;
	readHullDefinitions(fname, hulls);

	foreach(it, hulls) {
		HullDef* def = *it;
		array.InsertLast(&def);
		def->drop();
	}
}

static void writeHulls(const std::string& fname, CScriptArray& array) {
	std::vector<HullDef*> hulls;
	for(unsigned i = 0, cnt = array.GetSize(); i < cnt; ++i)
		hulls.push_back(*(HullDef**)array.At(i));
	writeHullDefinitions(fname, hulls);
}

static void descMake(void* mem) {
	new(mem) Design::Descriptor();
	((Design::Descriptor*)mem)->owner = Empire::getPlayerEmpire();
}

static void descDestroy(Design::Descriptor* desc) {
	desc->~Descriptor();
}

static Design::Descriptor* descCopy(Design::Descriptor* desc, const Design::Descriptor* other) {
	if(other->settings)
		other->settings->AddRef();
	if(other->hull)
		other->hull->grab();
	if(desc->settings)
		desc->settings->Release();
	if(desc->hull)
		desc->hull->drop();
	*desc = *other;
	return desc;
}

static unsigned descAddSys(Design::Descriptor& desc, const SubsystemDef* def) {
	desc.systems.push_back(Design::Descriptor::System());
	desc.systems.back().type = def;

	return (unsigned)desc.systems.size() - 1;
}

static void descApply(Design::Descriptor& desc, const SubsystemDef* def) {
	desc.appliedSystems.push_back(def);
}

static void descSetDirection(Design::Descriptor& desc, const vec3d& dir) {
	if(desc.systems.empty()) {
		scripts::throwException("No subsystem exists.");
		return;
	}

	desc.systems.back().direction = dir;
}

static void descAddHex(Design::Descriptor& desc, unsigned index, vec2u hex) {
	if(index >= desc.systems.size()) {
		scripts::throwException("Subsystem index out of bounds.");
		return;
	}

	desc.systems[index].hexes.push_back(hex);
	desc.systems[index].modules.push_back(0);
}

static void descAddHex_l(Design::Descriptor& desc, vec2u hex) {
	if(desc.systems.empty()) {
		scripts::throwException("No subsystem exists.");
		return;
	}

	desc.systems.back().hexes.push_back(hex);
	desc.systems.back().modules.push_back(0);
}

static void descAddHex_m(Design::Descriptor& desc, unsigned index, vec2u hex, const SubsystemDef::ModuleDesc* mod) {
	if(index >= desc.systems.size()) {
		scripts::throwException("Subsystem index out of bounds.");
		return;
	}

	desc.systems[index].hexes.push_back(hex);
	desc.systems[index].modules.push_back(mod);
}

static void descAddHex_lm(Design::Descriptor& desc, vec2u hex, const SubsystemDef::ModuleDesc* mod) {
	if(desc.systems.empty()) {
		scripts::throwException("No subsystem exists.");
		return;
	}

	desc.systems.back().hexes.push_back(hex);
	desc.systems.back().modules.push_back(mod);
}

static const Design* makeDesign(const Design::Descriptor& desc) {
	try {
		return new Design(desc);
	}
	catch(const char* err) {
		scripts::throwException(err);
		return 0;
	}
}

static bool hasSubsys(const Design* dsg, const SubsystemDef* def) {
	if(!def)
		return false;
	for(unsigned i = 0, cnt = dsg->subsystems.size(); i < cnt; ++i)
		if(dsg->subsystems[i].type == def)
			return true;
	return false;
}

static double quadrantTotalHP(const Design* dsg, unsigned index) {
	if(index >= 4)
		return 0.0;
	return dsg->quadrantTotalHP[index];
}

static unsigned moduleCount(const SubsystemDef* def) {
	return def->modules.size();
}

static const SubsystemDef::ModuleDesc* getModule(const SubsystemDef* def, unsigned i) {
	if(i >= def->modules.size()) {
		scripts::throwException("Subsystem module index out of bounds.");
		return 0;
	}

	return def->modules[i];
}

static unsigned effectorCount(const Subsystem* sys) {
	return sys->type->effectors.size();
}

static const Effector* sysGetEffector(const Subsystem* sys, unsigned i) {
	if(i >= sys->type->effectors.size()) {
		scripts::throwException("Effector index out of bounds.");
		return 0;
	}

	return &sys->effectors[i];
}

static void triggerEffector(const Effector* efft, Object* obj, Object* target, float efficiency = 1.f, double tOffset = 0.0) {
	EffectorTarget targ;
	targ.target = target;
	targ.tracking = (target->position - obj->position).normalized();
	targ.flags = TF_Firing | TF_WithinFireTolerance;
	targ.hits = 0;

	efft->trigger(obj, targ, efficiency, tOffset);
}

static void triggerEffector_t(const Effector* efft, Object* obj, Object* target, const vec3d& tracking, float efficiency = 1.f, double tOffset = 0.0) {
	EffectorTarget targ;
	targ.target = target;
	targ.tracking = tracking;
	targ.flags = TF_Firing | TF_TrackingProgress | TF_WithinFireTolerance;
	targ.hits = 0;

	efft->trigger(obj, targ, efficiency, tOffset);
}

static const SubsystemDef::ModuleDesc* getModule_n(const SubsystemDef* def, std::string& name) {
	auto it = def->moduleIndices.find(name);
	if(it == def->moduleIndices.end())
		return 0;
	return def->modules[it->second];
}

static bool sysDefHasMod(const SubsystemDef* def, std::string& name) {
	auto it = def->modifierIds.find(name);
	return it != def->modifierIds.end();
}

static void sysvar_aGet(asIScriptGeneric* f) {
	unsigned index = (unsigned)(size_t)f->GetFunction()->GetUserData();
	Subsystem* sys = (Subsystem*)f->GetObject();

	if(index >= sys->type->variableIndices.size() || sys->type->variableIndices[index] < 0)
		scripts::throwException("Subsystem variable does not apply to this subsystem.");

	float val = sys->variables[sys->type->variableIndices[index]];
	f->SetReturnFloat(val);
}

static void sysvar_aSet(asIScriptGeneric* f) {
	unsigned index = (unsigned)(size_t)f->GetFunction()->GetUserData();
	Subsystem* sys = (Subsystem*)f->GetObject();
	float val = f->GetArgFloat(0);

	if(index >= sys->type->variableIndices.size() || sys->type->variableIndices[index] < 0)
		scripts::throwException("Subsystem variable does not apply to this subsystem.");

	sys->variables[sys->type->variableIndices[index]] = val;
}

static void subSysVar(const std::string& name, int index) {
	//Enumeration
	EnumBind vars("SubsystemVariable", false);
	vars[std::string("SV_") + name] = index;

	//Accessor
	ClassBind cls("Subsystem");
	cls.addGenericMethod(format("float get_$1() const", name).c_str(), asFUNCTION(sysvar_aGet), (void*)(size_t)index);
	cls.addGenericMethod(format("void set_$1(float)", name).c_str(), asFUNCTION(sysvar_aSet), (void*)(size_t)index);
}

static void hexVar(const std::string& name, int index) {
	EnumBind vars("HexVariable", false);
	vars[std::string("HV_") + name] = index;
}

static void shipVar(const std::string& name, int index) {
	EnumBind vars("ShipVariable", false);
	vars[std::string("ShV_") + name] = index;
}

static float dsgSysTotal(Design* dsg, int index) {
	if(index < 0)
		return 0;

	unsigned cnt = dsg->subsystems.size();
	float value = 0.f;
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = dsg->subsystems[i];
		float* sysVal = sys.variable(index);
		if(sysVal)
			value += *sysVal;
	}
	return value;
}

static float dsgHexTotal(Design* dsg, int index) {
	if(index < 0)
		return 0;

	unsigned cnt = dsg->subsystems.size();
	float value = 0.f;
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = dsg->subsystems[i];
		unsigned hexCnt = sys.hexes.size();
		for(unsigned j = 0; j < hexCnt; ++j) {
			float* hexVal = sys.hexVariable(index, j);
			if(hexVal)
				value += *hexVal;
		}
	}
	return value;
}

static float dsgSysAvg(Design* dsg, int index) {
	if(index < 0)
		return 0;

	unsigned cnt = dsg->subsystems.size();
	float value = 0.f;
	unsigned systems = 0;
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = dsg->subsystems[i];
		float* sysVal = sys.variable(index);
		if(sysVal) {
			value += *sysVal;
			systems += 1;
		}
	}
	return value / float(systems);
}

static float dsgHexAvg(Design* dsg, int index) {
	if(index < 0)
		return 0;

	unsigned cnt = dsg->subsystems.size();
	float value = 0.f;
	unsigned systems = 0;
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = dsg->subsystems[i];
		unsigned hexCnt = sys.hexes.size();
		for(unsigned j = 0; j < hexCnt; ++j) {
			float* hexVal = sys.hexVariable(index, j);
			if(hexVal) {
				value += *hexVal;
				systems += 1;
			}
		}
	}
	return value / float(systems);
}

static float sysHexTotal(Subsystem* sys, int index) {
	if(index < 0)
		return 0;

	float value = 0.f;
	unsigned hexCnt = sys->hexes.size();
	for(unsigned j = 0; j < hexCnt; ++j) {
		float* hexVal = sys->hexVariable(index, j);
		if(hexVal)
			value += *hexVal;
	}
	return value;
}

static float* getSysVar(Subsystem* sys, int index) {
	if(index < 0) {
		scripts::throwException("Invalid subsystem variable.");
		return 0;
	}

	if(index >= (int)sys->type->variableIndices.size() || sys->type->variableIndices[index] < 0) {
		scripts::throwException("Subsystem variable does not apply to this subsystem.");
		return 0;
	}

	return &sys->variables[sys->type->variableIndices[index]];
}

static float getSysHexVar(Subsystem* sys, int index, unsigned hexIndex) {
	if(index < 0) {
		scripts::throwException("Invalid hex variable.");
		return 0;
	}

	if(index >= (int)sys->type->hexVariableIndices.size() || sys->type->hexVariableIndices[index] < 0) {
		scripts::throwException("Hex variable does not apply to this subsystem.");
		return 0;
	}

	if(hexIndex >= sys->hexes.size()) {
		scripts::throwException("Hexagon index out of bounds.");
		return 0;
	}

	return *sys->hexVariable(index, hexIndex);
}

static float* getSysHexVarRef(Subsystem* sys, int index, unsigned hexIndex) {
	if(index < 0) {
		scripts::throwException("Invalid hex variable.");
		return 0;
	}

	if(index >= (int)sys->type->hexVariableIndices.size() || sys->type->hexVariableIndices[index] < 0) {
		scripts::throwException("Hex variable does not apply to this subsystem.");
		return 0;
	}

	if(hexIndex >= sys->hexes.size()) {
		scripts::throwException("Hexagon index out of bounds.");
		return 0;
	}

	return sys->hexVariable(index, hexIndex);
}

static float dsgGetVar(Design* dsg, Subsystem* sys, int index) {
	float* ptr = getSysVar(sys, index);
	if(ptr)
		return *ptr;
	else
		return 0.0;
}

static float* dsgVarPtr(Design* dsg, Subsystem* sys, int index) {
	return getSysVar(sys, index);
}

static float dsgGetShipVar(Design* dsg, unsigned index) {
	if(index >= getShipVariableCount()) {
		scripts::throwException("Invalid ship variable index.");
		return 0;
	}

	return dsg->shipVariables[index];
}

static float* dsgShipVarPtr(Design* dsg, unsigned index) {
	if(index >= getShipVariableCount()) {
		scripts::throwException("Invalid ship variable index.");
		return 0;
	}

	return &dsg->shipVariables[index];
}

static float* dsgHexVarPtr(Design* dsg, const vec2u& v, int index) {
	//Get subsystem
	if(v.x >= dsg->grid.width || v.y >= dsg->grid.height) {
		scripts::throwException("Hex position out of bounds.");
		return 0;
	}

	int sysIndex = dsg->grid[v];
	if(sysIndex < 0) {
		scripts::throwException("No subsystem on hex position.");
		return 0;
	}
	auto& sys = dsg->subsystems[sysIndex];

	//Get hex variable
	int hexIndex = dsg->hexIndex[v];
	float* ptr = sys.hexVariable(index, hexIndex);

	if(!ptr) {
		scripts::throwException("Hexagon variable does not apply to this subsystem.");
		return 0;
	}

	return ptr;
}

static float dsgGetHexVar(Design* dsg, const vec2u& v, int index) {
	//Get subsystem
	if(v.x >= dsg->grid.width || v.y >= dsg->grid.height)
		return 0;

	int sysIndex = dsg->grid[v];
	if(sysIndex < 0)
		return 0;
	auto& sys = dsg->subsystems[sysIndex];

	//Get hex variable
	int hexIndex = dsg->hexIndex[v];
	float* ptr = sys.hexVariable(index, hexIndex);

	if(!ptr)
		return 0;
	return *ptr;
}

static bool dsgHasHexVar(Design* dsg, const vec2u& v, int index) {
	//Get subsystem
	if(v.x >= dsg->grid.width || v.y >= dsg->grid.height)
		return false;

	int sysIndex = dsg->grid[v];
	if(sysIndex < 0)
		return false;
	auto& sys = dsg->subsystems[sysIndex];

	//Get hex variable
	int hexIndex = dsg->hexIndex[v];
	float* ptr = sys.hexVariable(index, hexIndex);

	if(!ptr)
		return false;
	return true;
}

static bool hasSysVar(Subsystem* sys, int index) {
	if(index < 0)
		return false;
	if(index >= (int)sys->type->variableIndices.size() || sys->type->variableIndices[index] < 0)
		return false;
	return true;
}

static bool hasSysHexVar(Subsystem* sys, int index) {
	if(index < 0)
		return false;
	if(index >= (int)sys->type->hexVariableIndices.size() || sys->type->hexVariableIndices[index] < 0)
		return false;
	return true;
}

static void dsgRename(Design* dsg, const std::string& name) {
	if(!dsg->used)
		dsg->name = name;
}

static int dsgGetBuilt(Design* dsg) {
	return dsg->built.get();
}

static void dsgDecBuilt(Design* dsg) {
	--dsg->built;
}

static void dsgIncBuilt(Design* dsg) {
	++dsg->built;
}

static int dsgGetActive(Design* dsg) {
	return dsg->active.get();
}

static Effect* getSysEff(Subsystem* sys, unsigned index) {
	if(index >= sys->type->effects.size()) {
		scripts::throwException("Subsystem effect index out of bounds.");
		return 0;
	}

	return &sys->effects[index];
}

static void makeEvt(void* mem) {
	new(mem) EffectEvent();
}

static void delEvt(EffectEvent* evt) {
	evt->~EffectEvent();
}

static Blueprint* dmgBlueprint(DamageEvent& evt) {
	if(evt.target == nullptr)
		return nullptr;
	if(evt.target->type->blueprintOffset == 0)
		return nullptr;
	return (Blueprint*)(((size_t)evt.target.ptr) + evt.target->type->blueprintOffset);
}

static Blueprint* evtBlueprint(EffectEvent& evt) {
	if(evt.obj == nullptr)
		return nullptr;
	if(evt.obj->type->blueprintOffset == 0)
		return nullptr;
	return (Blueprint*)(((size_t)evt.obj.ptr) + evt.obj->type->blueprintOffset);
}

template<class T>
static Subsystem* evtSource(T& evt) {
	if(evt.source < 0 || !evt.obj)
		return 0;
	if(evt.obj->type->blueprintOffset == 0)
		return 0;

	Blueprint* bp = (Blueprint*)(((size_t)evt.obj.ptr) + evt.obj->type->blueprintOffset);
	if(!bp || evt.source >= (int)bp->design->subsystems.size())
		return 0;

	return (Subsystem*)&bp->design->subsystems[evt.source];
}

template<class T>
static Subsystem* evtDest(T& evt) {
	if(evt.destination < 0 || !evt.target)
		return 0;
	if(evt.target->type->blueprintOffset == 0)
		return 0;

	Blueprint* bp = (Blueprint*)(((size_t)evt.target.ptr) + evt.target->type->blueprintOffset);
	if(!bp || evt.destination >= (int)bp->design->subsystems.size())
		return 0;

	return (Subsystem*)&bp->design->subsystems[evt.destination];
}

template<class T>
static Blueprint::SysStatus* evtSourceStatus(T& evt) {
	if(evt.source < 0 || !evt.obj)
		return 0;
	if(evt.obj->type->blueprintOffset == 0)
		return 0;

	Blueprint* bp = (Blueprint*)(((size_t)evt.obj.ptr) + evt.obj->type->blueprintOffset);
	if(!bp || evt.source >= (int)bp->design->subsystems.size())
		return 0;

	return &bp->subsystems[evt.source];
}

template<class T>
static Blueprint::SysStatus* evtDestStatus(T& evt) {
	if(evt.destination < 0 || !evt.target)
		return 0;
	if(evt.target->type->blueprintOffset == 0)
		return 0;

	Blueprint* bp = (Blueprint*)(((size_t)evt.target.ptr) + evt.target->type->blueprintOffset);
	if(!bp || evt.destination >= (int)bp->design->subsystems.size())
		return 0;

	return &bp->subsystems[evt.destination];
}

static void makeDamageEvt(void* mem) {
	new(mem) DamageEvent();
}

static void delDamageEvt(DamageEvent* evt) {
	evt->~DamageEvent();
}

static void emptyEff(void* mem) {
	new(mem) Effect();
}

static void makeEff(void* mem, unsigned effType) {
	new(mem) Effect(getEffectDefinition(effType));
}

static void emptyTimed(void* mem) {
	new(mem) TimedEffect();
}

static void makeTimed(void* mem, unsigned effType, double time) {
	new(mem) TimedEffect(getEffectDefinition(effType), time);
}

static void delTimed(TimedEffect* evt) {
	evt->~TimedEffect();
}

static void effectType(const std::string& name, int index) {
	EnumBind effType("EffectType", false);
	effType[std::string("ET_")+name] = index;
}

static double* effValue(Effect* eff, unsigned index) {
	if(index >= EFFECT_MAX_VALUES) {
		scripts::throwException("Effect value index out of bounds.");
		return 0;
	}
	return &eff->values[index];
}

static unsigned effectCount(const SubsystemDef* def) {
	return def->effects.size();
}

static unsigned sysCount(const Design* design) {
	return design->subsystems.size();
}

static const Subsystem* getSys(const Design* design, unsigned i) {
	if(i >= design->subsystems.size())
		return 0;

	return &design->subsystems[i];
}

static const Subsystem* getHexSys(const Design* design, unsigned x, unsigned y) {
	if(x >= design->grid.width || y >= design->grid.height)
		return 0;

	int index = design->grid.get(x, y);
	if(index < 0)
		return 0;
	return &design->subsystems[index];
}

static const Subsystem* getHexSys_v(const Design* design, const vec2u& v) {
	if(v.x >= design->grid.width || v.y >= design->grid.height)
		return 0;

	int index = design->grid[v];
	if(index < 0)
		return 0;
	return &design->subsystems[index];
}

static const SubsystemDef::ModuleDesc* getHexModule(const Design* design, unsigned x, unsigned y) {
	if(x >= design->grid.width || y >= design->grid.height)
		return 0;

	int index = design->grid.get(x, y);
	if(index < 0)
		return 0;

	int hexIndex = design->hexIndex.get(x, y);
	auto& sys = design->subsystems[index];
	if((unsigned)hexIndex >= sys.modules.size())
		assert(false);
	return sys.modules[hexIndex];
}

static const SubsystemDef::ModuleDesc* getHexModule_v(const Design* design, const vec2u& v) {
	if(v.x >= design->grid.width || v.y >= design->grid.height)
		return 0;

	int index = design->grid[v];
	if(index < 0)
		return 0;

	int hexIndex = design->hexIndex[v];
	auto& sys = design->subsystems[index];
	return sys.modules[hexIndex];
}

static int getHexIndex(const Design* design, const vec2u& v) {
	if(v.x >= design->grid.width || v.y >= design->grid.height)
		return -1;

	int index = design->grid.get(v.x, v.y);
	if(index < 0)
		return -1;

	int hexIndex = design->hexIndex.get(v.x, v.y);
	return hexIndex;
}

static int getHexStatusIndex(const Design* design, const vec2u& v) {
	if(v.x >= design->grid.width || v.y >= design->grid.height)
		return -1;

	int index = design->grid.get(v.x, v.y);
	if(index < 0)
		return -1;

	int hexIndex = design->hexStatusIndex.get(v.x, v.y);
	return hexIndex;
}

static bool isValidhex(const Design* design, const vec2u& v) {
	if(v.x >= design->grid.width || v.y >= design->grid.height)
		return false;
	return true;
}

static void setDesignObsolete(const Design* design, bool value) {
	design->obsolete = value;
}

static void setDesignData(Design* design, asIScriptObject* obj) {
	auto* man = getActiveManager();
	if(design->data != nullptr) {
		scripts::throwException("Setting design data on design that already has data.");
		return;
	}

	design->data = new net::Message();

	auto* writeFunc = (asIScriptFunction*)man->engine->GetUserData(scripts::EDID_SerializableWrite);
	if(writeFunc) {
		scripts::Call cl = man->call(writeFunc);
		cl.setObject(obj);
		cl.push(design->data);
		cl.call();
	}

	design->bindData();
}

static unsigned hexCount(const Subsystem* sys) {
	return sys->hexes.size();
}

static vec2u getHex(const Subsystem* sys, unsigned i) {
	if(i >= sys->hexes.size()) {
		scripts::throwException("Subsystem hex index out of bounds.");
		return vec2u();
	}

	return sys->hexes[i];
}

static const SubsystemDef::ModuleDesc* getSysModule(const Subsystem* sys, unsigned i) {
	if(i >= sys->modules.size()) {
		scripts::throwException("Subsystem hex index out of bounds.");
		return 0;
	}

	return sys->modules[i];
}

static unsigned designCount(const DesignClass* cls) {
	return cls->designs.size();
}

static const Design* getDesign(const DesignClass* cls, unsigned i) {
	if(i >= cls->designs.size()) {
		scripts::throwException("Design index out of bounds.");
		return 0;
	}

	const Design* dsg = cls->designs[i];
	if(dsg)
		dsg->grab();
	return dsg;
}

static unsigned dsgErrorCount(const Design* dsg) {
	return dsg->errors.size();
}

static const DesignError* dsgError(const Design* dsg, unsigned index) {
	if(index >= dsg->errors.size()) {
		scripts::throwException("Design error index out of bounds.");
		return 0;
	}

	return &dsg->errors[index];
}

static void dsgAddError(Design* dsg, bool fatal, const std::string& text,
		const Subsystem* sys, const SubsystemDef::ModuleDesc* module,
		vec2u hex) {
	dsg->errors.push_back(DesignError(fatal, text, sys, module, hex));
}

static void dsgAddErrorHex(Design* dsg, const vec2u& hex) {
	dsg->errorHexes.insert((uint64_t)hex.x << 32 | (uint64_t)hex.y);
}

static bool dsgIsErrorHex(Design* dsg, const vec2u& hex) {
	if(dsg->errorHexes.size() == 0)
		return false;
	auto it = dsg->errorHexes.find((uint64_t)hex.x << 32 | (uint64_t)hex.y);
	return it != dsg->errorHexes.end();
}

static Color effTrailStart(const EffectorDef& def) {
	return def.skins[0].trailStart;
}

static Color effTrailEnd(const EffectorDef& def) {
	return def.skins[0].trailEnd;
}

static int effArg(const EffectorDef& def, const std::string& name) {
	auto it = def.valueNames.find(name);
	if(it == def.valueNames.end())
		return -1;
	return (int)it->second;
}

static double ERR_DOUBLE = 1e30;

class ScriptEffector : public Effector {
public:
	ScriptEffector(const EffectorDef& def) : Effector(def) {
		turretAngle = vec3d::front();
		relativePosition = vec3d();

		for(unsigned i = 0; i < type.valueCount; ++i) {
			if(type.values[i].defaultValue)
				values[i] = type.values[i].defaultValue->evaluate(effVariable, this);
			else
				values[i] = 0.0;
		}

		registerEffector(this);
	}

	double& getValue(const std::string& name) {
		auto it = type.valueNames.find(name);
		if(it == type.valueNames.end()) {
			scripts::throwException("Value not found.");
			return ERR_DOUBLE;
		}
		return values[it->second];
	}

	double& getValueByIndex(unsigned index) {
		if(index >= type.valueCount) {
			scripts::throwException("Value out of bounds.");
			return ERR_DOUBLE;
		}
		return values[index];
	}

	void evaluate() {
		initValues();
		if(devices.network->isServer)
			devices.network->sendEffectorUpdate(this);
	}
};

static ScriptEffector* makeScriptEff(const EffectorDef& def) {
	return new ScriptEffector(def);
}

static const EffectorDef* getEffDefType(const Effector& eff) {
	return &eff.type;
}

class ScriptTurret  {
	mutable threads::atomic_int refs;
public:
	const Effector& type;
	double* states;
	EffectorTarget target;

	ScriptTurret(const Effector& efftr) : type(efftr), refs(1) {
		type.grab();
		states = new double[type.type.stateCount]();

		memset(reinterpret_cast<void *>(&target), 0, sizeof(EffectorTarget));
		target.tracking = vec3d::front();
	}

	~ScriptTurret() {
		type.drop();
	}

	void grab() const {
		++refs;
	}

	void drop() const {
		if(!--refs)
			delete this;
	}

	void update(Object* obj, double time, float efficiency) {
		type.update(obj, time, states, target, efficiency);
	}

	void trigger(Object* obj, Object* targObj, float efficiency, double tOffset = 0) {
		EffectorTarget ctarg = target;
		ctarg.target = targObj;
		type.trigger(obj, ctarg, efficiency, tOffset);
	}

	void save(SaveMessage& file) {
		if(type.effectorId != 0) {
			file.write0();
			file << type.effectorId;
		}
		else {
			file.write1();
			file << type.inDesign->owner->id;
			file << type.inDesign->id;
			file << type.subsysIndex;
			file << type.effectorIndex;
		}
		file.write(states, sizeof(double) * type.type.stateCount);
		scripts::saveObject(file, target.target);
		file << target.flags;
		file << target.tracking;
		file << target.hits;
	}
};

static ScriptTurret* makeScriptTurret(const Effector& efftr) {
	return new ScriptTurret(efftr);
}

static ScriptTurret* loadScriptTurret(SaveMessage& file) {
	const Effector* efftr = nullptr;
	if(!file.readBit()) {
		unsigned id = 0;
		file >> id;
		efftr = getEffector(id);
	}
	else {
		unsigned char empID;
		file >> empID;
		if(empID == INVALID_EMPIRE)
			return nullptr;

		int dsgId;
		unsigned subsysIndex;
		unsigned effectorIndex;
		file >> dsgId >> subsysIndex >> effectorIndex;

		Empire* dsgOwner = Empire::getEmpireByID(empID);
		const Design* dsg = dsgOwner->getDesign(dsgId);
		if(subsysIndex >= dsg->subsystems.size() || effectorIndex >= dsg->subsystems[subsysIndex].type->effectors.size())
			throw "Invalid turret effector.";

		efftr = &dsg->subsystems[subsysIndex].effectors[effectorIndex];
	}

	ScriptTurret* turr = new ScriptTurret(*efftr);
	file.read(turr->states, sizeof(double) * efftr->type.stateCount);
	scripts::loadObject(file, &turr->target.target);
	file >> turr->target.flags;
	file >> turr->target.tracking;
	file >> turr->target.hits;

	efftr->drop();
	return turr;
}

static unsigned strvec_length(std::vector<std::string>& vec) {
	return vec.size();
}

const std::string ERRSTR = "ERR";
static const std::string& strvec_get(std::vector<std::string>& vec, unsigned index) {
	if(index >= vec.size())
		return ERRSTR;
	return vec[index];
}

static unsigned dblvec_length(std::vector<double>& vec) {
	return vec.size();
}

static double dblvec_get(std::vector<double>& vec, unsigned index) {
	if(index >= vec.size())
		return 0.0;
	return vec[index];
}

static void ssevtMake(void* mem) {
	new(mem) SubsystemEvent();
	memset(mem, 0, sizeof(SubsystemEvent));
}

static void ssevtDestroy(SubsystemEvent* mem) {
	if(mem->data)
		((CScriptAny*)mem->data)->Release();
	if(mem->design)
		mem->design->drop();
	if(mem->obj)
		mem->obj->drop();
	mem->~SubsystemEvent();
}

static unsigned sysHookCount(const Subsystem* sys) {
	return sys->hookClasses.size();
}

static asIScriptObject* sysHookGet(const Subsystem* sys, unsigned index) {
	if(index >= sys->hookClasses.size())
		return nullptr;
	auto* obj = sys->hookClasses[index];
	if(obj)
		obj->AddRef();
	return obj;
}

static unsigned getSSTag(const std::string& tag) {
	return getSysTagIndex(tag);
}

void RegisterDesignBinds(bool server, bool declarations) {
	if(declarations) {
		ClassBind hull("Hull", asOBJ_REF);
		ClassBind shipset("Shipset", asOBJ_REF);
		ClassBind ds("Design", asOBJ_REF);
		ClassBind dc("DesignClass", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind evt("Event", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CD, sizeof(EffectEvent));
		ClassBind dev("DamageEvent", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CD, sizeof(DamageEvent));
		ClassBind def("EffectDef", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind deftr("EffectorDef", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind eff("Effect", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_C, sizeof(Effect));
		ClassBind efftr("Effector", asOBJ_REF);
		ClassBind turr("Turret", asOBJ_REF);
		ClassBind timed("TimedEffect", asOBJ_VALUE | asOBJ_POD | asOBJ_APP_CLASS_CD, sizeof(TimedEffect));
		ClassBind sysdef("SubsystemDef", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind moddef("ModuleDef", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind sys("Subsystem", asOBJ_REF | asOBJ_NOCOUNT);
		ClassBind desc("DesignDescriptor", asOBJ_VALUE | asOBJ_APP_CLASS_CDA, sizeof(Design::Descriptor));
		return;
	}

	//Tags
	EnumBind tags("SubsystemTag");
	tags["ST_NULL"] = -1;
	enumerateSysTags([&tags](const std::string& name, int index) {
		tags[std::string("ST_")+name] = index;
	});
	bind("SubsystemTag getSubsystemTag(const string& tag)", asFUNCTION(getSSTag));

	//Shipsets
	ClassBind shipset("Shipset");
	shipset.addFactory("Shipset@ Hull()", asFUNCTION(makeShipset));
	shipset.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(Shipset, grab));
	shipset.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(Shipset, drop));
	shipset.addMember("uint id", offsetof(Shipset, id));
	shipset.addMember("string ident", offsetof(Shipset, ident));
	shipset.addMember("string name", offsetof(Shipset, name));
	shipset.addMember("string dlc", offsetof(Shipset, dlc));
	shipset.addMember("bool available", offsetof(Shipset, available));
	shipset.addMethod("uint get_hullCount() const", asMETHOD(Shipset, getHullCount));
	shipset.addMethod("bool hasHull(const Hull& hull) const", asMETHOD(Shipset, hasHull));
	shipset.addMethod("const Hull@+ get_hulls(uint index) const", asMETHODPR(Shipset, getHull, (unsigned) const, const HullDef*));
	shipset.addMethod("const Hull@+ getHull(const string& ident) const", asMETHODPR(Shipset, getHull, (const std::string&) const, const HullDef*));

	bind("uint getShipsetCount()", asFUNCTION(getShipsetCount));
	bind("const Shipset& getShipset(uint id)", asFUNCTIONPR(getShipset, (unsigned), const Shipset*));
	bind("const Shipset& getShipset(const string& ident)", asFUNCTIONPR(getShipset, (const std::string&), const Shipset*));

	//Ship skins
	ClassBind shipskin("ShipSkin", asOBJ_REF | asOBJ_NOCOUNT);
	shipskin.addMember("string ident", offsetof(ShipSkin, ident));
	shipskin.addMember("const Material@ material", offsetof(ShipSkin, material));
	shipskin.addMember("const Model@ model", offsetof(ShipSkin, mesh));
	shipskin.addMember("Sprite icon", offsetof(ShipSkin, icon));

	shipset.addMethod("const ShipSkin& getSkin(const string& name) const", asMETHOD(Shipset, getSkin));

	//Hull shape
	ClassBind hull("Hull");
	hull.addFactory("Hull@ Hull()", asFUNCTION(makeHull));
	hull.addFactory("Hull@ Hull(const Hull& other)", asFUNCTION(makeHull_cpy));
	hull.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(HullDef, grab));
	hull.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(HullDef, drop));
	hull.addMember("uint id", offsetof(HullDef, id));
	hull.addMember("string ident", offsetof(HullDef, ident));
	hull.addMember("string name", offsetof(HullDef, name));
	hull.addMember("string backgroundName", offsetof(HullDef, backgroundName));
	hull.addMember("string modelName", offsetof(HullDef, meshName));
	hull.addMember("string materialName", offsetof(HullDef, materialName));
	hull.addMember("string iconName", offsetof(HullDef, iconName));
	hull.addMember("const Material@ background", offsetof(HullDef, background));
	hull.addMember("const Material@ material", offsetof(HullDef, material));
	hull.addMember("const Model@ model", offsetof(HullDef, mesh));
	hull.addMember("const SpriteSheet@ iconSheet", offsetof(HullDef, iconSheet));
	hull.addMember("Sprite guiIcon", offsetof(HullDef, guiIcon));
	hull.addMember("Sprite fleetIcon", offsetof(HullDef, fleetIcon));
	hull.addMember("uint iconIndex", offsetof(HullDef, iconIndex));
	hull.addMember("vec2i gridSize", offsetof(HullDef, gridSize));
	hull.addMember("recti gridOffset", offsetof(HullDef, gridOffset));
	hull.addMember("double minSize", offsetof(HullDef, minSize));
	hull.addMember("double maxSize", offsetof(HullDef, maxSize));
	hull.addMember("HexGridi exterior", offsetof(HullDef, exterior));
	hull.addMember("HexGridb active", offsetof(HullDef, active));
	hull.addMember("double backgroundScale", offsetof(HullDef, backgroundScale));
	hull.addMember("double modelScale", offsetof(HullDef, modelScale));
	hull.addMember("uint activeCount", offsetof(HullDef, activeCount));
	hull.addMember("uint exteriorCount", offsetof(HullDef, exteriorCount));
	hull.addMember("Hull@ baseHull", offsetof(HullDef, baseHull));
	hull.addMember("bool special", offsetof(HullDef, special));
	hull.addMethod("Hull& opAssign(const Hull&in other)", asMETHOD(HullDef, operator=));
	hull.addMethod("bool hasTag(const string&in tag) const", asMETHOD(HullDef, hasTag));
	hull.addMethod("bool isExterior(const vec2u& hex) const", asMETHOD(HullDef, isExterior));
	hull.addMethod("bool isExteriorInDirection(const vec2u& hex, HexGridAdjacency adj) const", asMETHOD(HullDef, isExteriorInDirection));
	hull.addMethod("double getMatchDistance(const vec2d& pos) const",
			asMETHODPR(HullDef, getMatchDistance, (const vec2d&) const, double));
	hull.addMethod("double getMatchDistance(const DesignDescriptor& desc) const",
			asMETHODPR(HullDef, getMatchDistance, (void*) const, double));

	bind("uint getHullCount()", asFUNCTION(getHullCount));
	bind("const Hull@+ getHullDefinition(uint id)",
		asFUNCTIONPR(getHullDefinition, (unsigned), const HullDef*));
	bind("const Hull@+ getHullDefinition(const string &in ident)",
		asFUNCTIONPR(getHullDefinition, (const std::string&), const HullDef*));

	bind("void readHullDefinitions(const string&in filename, array<Hull@>& hulls)", asFUNCTION(readHulls));
	bind("void writeHullDefinitions(const string&in filename, array<Hull@>& hulls)", asFUNCTION(writeHulls));

	//Effect definitions
	EnumBind status("EffectStatus");
	status["ES_Active"] = ES_Active;
	status["ES_Suspended"] = ES_Suspended;
	status["ES_Ended"] = ES_Ended;

	EnumBind effType("EffectType");
	enumerateEffectDefinitions(effectType);

	ClassBind def("EffectDef");
	def.addMember("string name", offsetof(EffectDef, name));
	def.addMember("EffectType type", offsetof(EffectDef, id));
	def.addMember("uint valueCount", offsetof(EffectDef, valueCount));

	bind("const EffectDef@ getEffectDefinition(EffectType type)", asFUNCTIONPR(getEffectDefinition, (int), const EffectDef*));
	bind("const EffectDef@ getEffectDefinition(const string &in name)", asFUNCTIONPR(getEffectDefinition, (const std::string&), const EffectDef*));

	//Event data
	ClassBind evt("Event");
	evt.addConstructor("void f()", asFUNCTION(makeEvt));
	evt.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(delEvt));
	evt.addMember("double time", offsetof(EffectEvent, time));
	evt.addMember("vec3d impact", offsetof(EffectEvent, impact))
		doc("Impact location relative to the object.");
	evt.addMember("float efficiency", offsetof(EffectEvent, efficiency));
	evt.addMember("float partiality", offsetof(EffectEvent, partiality));
	evt.addMember("float workingPercent", offsetof(EffectEvent, partiality));
	evt.addMember("float custom1", offsetof(EffectEvent, custom1));
	evt.addMember("float custom2", offsetof(EffectEvent, custom2));
	evt.addMember("Object@ obj", offsetof(EffectEvent, obj));
	evt.addMember("Object@ target", offsetof(EffectEvent, target));
	evt.addMember("EffectStatus status", offsetof(EffectEvent, status));
	evt.addMember("int source_index", offsetof(EffectEvent, source));
	evt.addMember("int destination_index", offsetof(EffectEvent, destination));
	evt.addMember("vec2d direction", offsetof(EffectEvent, direction));
	evt.addExternMethod("Blueprint@ get_blueprint()", asFUNCTION(evtBlueprint));
	evt.addExternMethod("const Subsystem@ get_source()", asFUNCTION(evtSource<EffectEvent>));
	evt.addExternMethod("const Subsystem@ get_destination()", asFUNCTION(evtDest<EffectEvent>));
	evt.addExternMethod("SysStatus@ get_source_status()", asFUNCTION(evtSourceStatus<EffectEvent>));
	evt.addExternMethod("SysStatus@ get_destination_status()", asFUNCTION(evtDestStatus<EffectEvent>));

	EnumBind des("DamageEventStatus");
	des["DE_Continue"] = DE_Continue;
	des["DE_SkipHex"] = DE_SkipHex;
	des["DE_EndDamage"] = DE_EndDamage;

	EnumBind dmgflag("DamageFlags");
	dmgflag["DF_Flag1"] = 1;
	dmgflag["DF_Flag2"] = 2;
	dmgflag["DF_Flag3"] = 4;
	dmgflag["DF_Flag4"] = 8;
	dmgflag["DF_Flag5"] = 0x10;
	dmgflag["DF_Flag6"] = 0x20;
	dmgflag["DF_Flag7"] = 0x40;
	dmgflag["DF_Flag8"] = 0x80;
	dmgflag["DF_DestroyedObject"] = DF_DestroyedObject;

	//Damage event data
	ClassBind dev("DamageEvent");
	dev.addConstructor("void f()", asFUNCTION(makeDamageEvt));
	dev.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(delDamageEvt));
	dev.addMember("vec3d impact", offsetof(DamageEvent, impact))
		doc("Impact location relative to the object.");
	dev.addMember("double damage", offsetof(DamageEvent, damage));
	dev.addMember("float pierce", offsetof(DamageEvent, pierce));
	dev.addMember("float partiality", offsetof(DamageEvent, partiality));
	dev.addMember("float custom1", offsetof(DamageEvent, custom1));
	dev.addMember("float custom2", offsetof(DamageEvent, custom2));
	dev.addMember("uint flags", offsetof(DamageEvent, flags));
	dev.addMember("Object@ obj", offsetof(DamageEvent, obj));
	dev.addMember("Object@ target", offsetof(DamageEvent, target));
	dev.addMember("int source_index", offsetof(DamageEvent, source));
	dev.addMember("int destination_index", offsetof(DamageEvent, destination));
	dev.addMember("bool spillable", offsetof(DamageEvent, spillable));
	dev.addExternMethod("Blueprint@ get_blueprint()", asFUNCTION(dmgBlueprint));
	dev.addExternMethod("const Subsystem@ get_source()", asFUNCTION(evtSource<DamageEvent>));
	dev.addExternMethod("const Subsystem@ get_destination()", asFUNCTION(evtDest<DamageEvent>));
	dev.addExternMethod("SysStatus@ get_source_status()", asFUNCTION(evtSourceStatus<DamageEvent>));
	dev.addExternMethod("SysStatus@ get_destination_status()", asFUNCTION(evtDestStatus<DamageEvent>));

	//Instantiated effects
	ClassBind eff("Effect");
	eff.addConstructor("void f()", asFUNCTION(emptyEff));
	eff.addConstructor("void f(EffectType type)", asFUNCTION(makeEff));
	eff.addExternMethod("double& opIndex(uint num)", asFUNCTION(effValue));
	eff.addMember("const EffectDef@ type", offsetof(Effect, type));
	eff.addMember("double value0", offsetof(Effect, values[0]));
	eff.addMember("double value1", offsetof(Effect, values[1]));
	eff.addMember("double value2", offsetof(Effect, values[2]));
	eff.addMember("double value3", offsetof(Effect, values[3]));
	eff.addMember("double value4", offsetof(Effect, values[4]));
	eff.addMember("double value5", offsetof(Effect, values[5]));

	//Timed effect
	ClassBind timed("TimedEffect");
	timed.addConstructor("void f()", asFUNCTION(emptyTimed));
	timed.addConstructor("void f(EffectType type, double time)", asFUNCTION(makeTimed));
	timed.addExternBehaviour(asBEHAVE_DESTRUCT, "void f()", asFUNCTION(delTimed));
	timed.addMember("double remaining", offsetof(TimedEffect, remaining));
	timed.addMember("Effect effect", offsetof(TimedEffect, effect));
	timed.addMember("Event event", offsetof(TimedEffect, event));

	//Effector definitions
	ClassBind effd("EffectorDef");
	effd.addMember("uint id", offsetof(EffectorDef, index));
	effd.addMember("string name", offsetof(EffectorDef, name));
	effd.addMember("uint valueCount", offsetof(EffectorDef, valueCount));
	effd.addExternMethod("Color get_trailStart() const", asFUNCTION(effTrailStart));
	effd.addExternMethod("Color get_trailEnd() const", asFUNCTION(effTrailEnd));
	effd.addExternMethod("int getArgumentIndex(const string& name)", asFUNCTION(effArg));

	{
		Namespace ns("effector");
		for(int i = 0, cnt = getEffectorDefinitionCount(); i < cnt; ++i) {
			const EffectorDef* def = getEffectorDefinition(i);
			bindGlobal(format("const ::EffectorDef $1", def->name).c_str(), (void*)def);
		}
	}

	bind("EffectorDef@ getEffectorDef(uint id)", asFUNCTIONPR(getEffectorDefinition, (unsigned), const EffectorDef*));
	bind("EffectorDef@ getEffectorDef(const string& ident)", asFUNCTIONPR(getEffectorDefinition, (const std::string&), const EffectorDef*));

	//Script effectors
	ClassBind efft("Effector");
	efft.setReferenceFuncs(asMETHOD(ScriptEffector, grab), asMETHOD(ScriptEffector, drop));
	efft.addMember("vec3d turretAngle", offsetof(Effector, turretAngle));
	efft.addMember("vec3d relativePosition", offsetof(Effector, relativePosition));
	efft.addMember("const double fireArc", offsetof(Effector, fireArc));
	efft.addMember("const double targetTolerance", offsetof(Effector, targetTolerance));
	efft.addMember("const double fireTolerance", offsetof(Effector, fireTolerance));
	efft.addMember("const double range", offsetof(Effector, range));
	efft.addMember("const double lifetime", offsetof(Effector, lifetime));
	efft.addMember("const double tracking", offsetof(Effector, tracking));
	efft.addMember("const double speed", offsetof(Effector, speed));
	efft.addMember("const double spread", offsetof(Effector, spread));
	efft.addMember("const uint capTarget", offsetof(Effector, capTarget));

	if(server) {
		efft.addFactory("Effector@ f(const EffectorDef& def)", asFUNCTION(makeScriptEff));
		efft.addExternMethod("const EffectorDef@ get_type() const", asFUNCTION(getEffDefType));
		efft.addMember("uint id", offsetof(Effector, effectorId));
		efft.addMember("uint sysIndex", offsetof(Effector, subsysIndex));
		efft.addMember("uint index", offsetof(Effector, effectorIndex));
		efft.addMember("double relativeSize", offsetof(Effector, relativeSize));
		efft.addMethod("double& opIndex(uint index)", asMETHOD(ScriptEffector, getValueByIndex));
		efft.addMethod("double& opIndex(const string& name)", asMETHOD(ScriptEffector, getValue));
		efft.addMethod("void evaluate()", asMETHOD(ScriptEffector, evaluate));

		efft.addExternMethod("void trigger(Object& obj, Object& target, float efficiency = 1.f, double tOffset = 0.0) const", asFUNCTION(triggerEffector));
		efft.addExternMethod("void trigger(Object& obj, Object& target, const vec3d& tracking, float efficiency = 1.f, double tOffset = 0.0) const", asFUNCTION(triggerEffector_t));
	}

	bind("Effector@ getEffectorByID(uint id)", asFUNCTION(getEffector));

	//Script turrets
	ClassBind turr("Turret");
	turr.setReferenceFuncs(asMETHOD(ScriptTurret, grab), asMETHOD(ScriptTurret, drop));
	if(server) {
		turr.addFactory("Turret@ f(const Effector& efftr)", asFUNCTION(makeScriptTurret));
		turr.addFactory("Turret@ f(SaveFile& file)", asFUNCTION(loadScriptTurret));
		turr.addMember("Object@ target", offsetof(ScriptTurret, target)+offsetof(EffectorTarget, target));
		turr.addMember("vec3d tracking", offsetof(ScriptTurret, target)+offsetof(EffectorTarget, tracking));
		turr.addMember("uint8 hits", offsetof(ScriptTurret, target)+offsetof(EffectorTarget, hits));
		turr.addMember("uint flags", offsetof(ScriptTurret, target)+offsetof(EffectorTarget, flags));

		turr.addMethod("void update(Object& obj, double time, float efficiency = 1.f)", asMETHOD(ScriptTurret, update));
		turr.addMethod("void trigger(Object& obj, Object& target, float efficiency = 1.f, double tOffset = 0.0)", asMETHOD(ScriptTurret, trigger));

		turr.addMethod("void save(SaveFile& file)", asMETHOD(ScriptTurret, save));
	}

	EnumBind tfl("TurretFlags");
	tfl["TF_Target"] = TF_Target;
	tfl["TF_Group"] = TF_Group;
	tfl["TF_Preference"] = TF_Preference;
	tfl["TF_Firing"] = TF_Firing;
	tfl["TF_Retarget"] = TF_Retarget;
	tfl["TF_TrackingProgress"] = TF_TrackingProgress;
	tfl["TF_ClearTracking"] = TF_ClearTracking;
	tfl["TF_WithinFireTolerance"] = TF_WithinFireTolerance;

	//Subsystem definitions
	ClassBind sysdef("SubsystemDef");
	sysdef.addMember("string id", offsetof(SubsystemDef, id));
	sysdef.addMember("string name", offsetof(SubsystemDef, name));
	sysdef.addMember("string description", offsetof(SubsystemDef, description));
	sysdef.addMember("int elevation", offsetof(SubsystemDef, elevation));
	sysdef.addMember("Color color", offsetof(SubsystemDef, baseColor));
	sysdef.addMember("Color typeColor", offsetof(SubsystemDef, typeColor));
	sysdef.addMember("bool hasCore", offsetof(SubsystemDef, hasCore));
	sysdef.addMember("bool passExterior", offsetof(SubsystemDef, passExterior));
	sysdef.addMember("bool fauxExterior", offsetof(SubsystemDef, fauxExterior));
	sysdef.addMember("bool isHull", offsetof(SubsystemDef, isHull));
	sysdef.addMember("bool isApplied", offsetof(SubsystemDef, isApplied));
	sysdef.addMember("bool isContiguous", offsetof(SubsystemDef, isContiguous));
	sysdef.addMember("bool exteriorCore", offsetof(SubsystemDef, exteriorCore));
	sysdef.addMember("bool defaultUnlock", offsetof(SubsystemDef, defaultUnlock));
	sysdef.addMember("const Sprite picture", offsetof(SubsystemDef, picture));
	sysdef.addMember("int index", offsetof(SubsystemDef, index));
	sysdef.addMember("const ModuleDef@ coreModule", offsetof(SubsystemDef, coreModule));
	sysdef.addMember("const ModuleDef@ defaultModule", offsetof(SubsystemDef, defaultModule));
	sysdef.addExternMethod("uint get_effectCount() const", asFUNCTION(effectCount));
	sysdef.addMethod("bool hasTag(const string &in tag) const", asMETHODPR(SubsystemDef, hasTag, (const std::string&) const, bool));
	sysdef.addMethod("bool hasTag(SubsystemTag tag) const", asMETHODPR(SubsystemDef, hasTag, (int) const, bool));
	sysdef.addMethod("const string& getTagValue(SubsystemTag tag, uint index = 0) const", asMETHOD(SubsystemDef, getTagValue));
	sysdef.addMethod("uint getTagValueCount(SubsystemTag tag) const", asMETHOD(SubsystemDef, getTagValueCount));
	sysdef.addMethod("bool hasTagValue(SubsystemTag tag, const string& value) const", asMETHOD(SubsystemDef, hasTagValue));
	sysdef.addMethod("bool hasHullTag(const string &in tag) const", asMETHOD(SubsystemDef, hasHullTag));
	sysdef.addMethod("bool canUseOn(const Hull@ hull) const", asMETHOD(SubsystemDef, canUseOn));
	sysdef.addExternMethod("bool hasModifier(const string&in mod) const", asFUNCTION(sysDefHasMod));

	sysdef.addExternMethod("uint get_moduleCount() const", asFUNCTION(moduleCount));
	sysdef.addExternMethod("const ModuleDef@ get_modules(uint index) const", asFUNCTION(getModule));
	sysdef.addExternMethod("const ModuleDef@ module(const string&in) const", asFUNCTION(getModule_n));

	bind("int getSubsystemDefCount()", asFUNCTION(getSubsystemDefCount));
	bind("const SubsystemDef@ getSubsystemDef(int index)", asFUNCTIONPR(getSubsystemDef, (int), const SubsystemDef*));
	bind("const SubsystemDef@ getSubsystemDef(const string& id)", asFUNCTIONPR(getSubsystemDef, (const std::string&), const SubsystemDef*));

	{
		Namespace ns("subsystem");
		for(int i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			const SubsystemDef* def = getSubsystemDef(i);
			bindGlobal(format("const ::SubsystemDef $1", def->id).c_str(), (void*)def);
		}
	}

	//Module description
	ClassBind mod("ModuleDef");
	mod.addMember("int index", offsetof(SubsystemDef::ModuleDesc, index));
	mod.addMember("string id", offsetof(SubsystemDef::ModuleDesc, id));
	mod.addMember("string name", offsetof(SubsystemDef::ModuleDesc, name));
	mod.addMember("string description", offsetof(SubsystemDef::ModuleDesc, description));
	mod.addMember("Color color", offsetof(SubsystemDef::ModuleDesc, color));
	mod.addMember("bool required", offsetof(SubsystemDef::ModuleDesc, required));
	mod.addMember("bool unique", offsetof(SubsystemDef::ModuleDesc, unique));
	mod.addMember("bool vital", offsetof(SubsystemDef::ModuleDesc, vital));
	mod.addMember("bool defaultUnlock", offsetof(SubsystemDef::ModuleDesc, defaultUnlock));
	mod.addMember("const Sprite sprite", offsetof(SubsystemDef::ModuleDesc, sprite));
	mod.addMember("int drawMode", offsetof(SubsystemDef::ModuleDesc, drawMode));

	mod.addMethod("bool hasTag(const string &in tag) const", asMETHODPR(SubsystemDef::ModuleDesc, hasTag, (const std::string&) const, bool));
	mod.addMethod("bool hasTag(SubsystemTag tag) const", asMETHODPR(SubsystemDef::ModuleDesc, hasTag, (int) const, bool));
	mod.addMethod("const string& getTagValue(SubsystemTag tag, uint index = 0) const", asMETHOD(SubsystemDef::ModuleDesc, getTagValue));
	mod.addMethod("uint getTagValueCount(SubsystemTag tag) const", asMETHOD(SubsystemDef::ModuleDesc, getTagValueCount));
	mod.addMethod("bool hasTagValue(SubsystemTag tag, const string& value) const", asMETHOD(SubsystemDef::ModuleDesc, hasTagValue));

	EnumBind vars("SubsystemVariable");
	EnumBind hexvars("HexVariable");
	EnumBind shipvars("ShipVariable");

	bind("SubsystemVariable getSubsystemVariable(const string&in name)", asFUNCTION(getVariableIndex));
	bind("HexVariable getHexVariable(const string&in name)", asFUNCTION(getHexVariableIndex));
	bind("ShipVariable getShipVariable(const string&in name)", asFUNCTION(getShipVariableIndex));

	//Subsystem instances
	ClassBind sys("Subsystem");
	sys.addMember("const SubsystemDef@ type", offsetof(Subsystem, type));
	sys.addMember("vec2u core", offsetof(Subsystem, core));
	sys.addMember("bool hasErrors", offsetof(Subsystem, hasErrors));
	sys.addMember("int exteriorHexes", offsetof(Subsystem, exteriorHexes));
	sys.addMember("vec3d direction", offsetof(Subsystem, direction));
	sys.addMember("const Design@ inDesign", offsetof(Subsystem, inDesign));
	sys.addMember("uint index", offsetof(Subsystem, index));
	sys.addMember("uint dataOffset", offsetof(Subsystem, dataOffset));
	sys.addExternMethod("const float& opIndex(SubsystemVariable var) const", asFUNCTION(getSysVar));
	sys.addExternMethod("float& opIndex(SubsystemVariable var)", asFUNCTION(getSysVar));
	sys.addExternMethod("bool has(SubsystemVariable var) const", asFUNCTION(hasSysVar));
	sys.addExternMethod("bool has(HexVariable var) const", asFUNCTION(hasSysHexVar));
	sys.addExternMethod("const Effect& opIndex(uint ind) const", asFUNCTION(getSysEff));
	sys.addExternMethod("Effect& opIndex(uint ind)", asFUNCTION(getSysEff));
	sys.addExternMethod("uint get_effectorCount() const", asFUNCTION(effectorCount));
	sys.addExternMethod("const Effector@ get_effectors(uint index) const", asFUNCTION(sysGetEffector));

	sys.addExternMethod("float total(HexVariable var) const", asFUNCTION(sysHexTotal));

	sys.addExternMethod("uint get_hexCount() const", asFUNCTION(hexCount));
	sys.addExternMethod("vec2u hexagon(uint i) const", asFUNCTION(getHex));
	sys.addExternMethod("const ModuleDef@ module(uint i) const", asFUNCTION(getSysModule));

	sys.addExternMethod("const float hexVariable(HexVariable, uint) const", asFUNCTION(getSysHexVar));
	sys.addExternMethod("float& hexVariable(HexVariable, uint)", asFUNCTION(getSysHexVarRef));

	sys.addExternMethod("const float& variable(SubsystemVariable) const", asFUNCTION(getSysVar));
	sys.addExternMethod("float& variable(SubsystemVariable)", asFUNCTION(getSysVar));

	//Bind subsystem variables
	enumerateVariables(subSysVar);
	enumerateHexVariables(hexVar);
	enumerateShipVariables(shipVar);

	//Designs based on hull shapes
	ClassBind desc("DesignDescriptor");
	ClassBind ds("Design");

	ds.addBehaviour(asBEHAVE_ADDREF,  "void f()", asMETHOD(Design, grab));
	ds.addBehaviour(asBEHAVE_RELEASE, "void f()", asMETHOD(Design, drop));
	ds.addMember("int id", offsetof(Design, id));
	ds.addMember("string name", offsetof(Design, name));
	ds.addMember("const Hull@ hull", offsetof(Design, hull));
	ds.addMember("double size", offsetof(Design, size));
	ds.addMember("double hexSize", offsetof(Design, hexSize));
	ds.addMember("bool obsolete", offsetof(Design, obsolete));
	ds.addMember("uint interiorHexes", offsetof(Design, interiorHexes));
	ds.addMember("uint exteriorHexes", offsetof(Design, exteriorHexes));
	ds.addMember("uint usedHexCount", offsetof(Design, usedHexCount));
	ds.addMember("uint dataCount", offsetof(Design, dataCount));
	ds.addMember("uint effectorCount", offsetof(Design, effectorCount));
	ds.addMember("int revision", offsetof(Design, revision));
	ds.addMember("Empire@ owner", offsetof(Design, owner));
	ds.addMember("double totalHP", offsetof(Design, totalHP));
	ds.addMember("bool outdated", offsetof(Design, outdated));
	ds.addMember("bool used", offsetof(Design, used));
	ds.addMember("Color color", offsetof(Design, color));
	ds.addMember("Color dullColor", offsetof(Design, dullColor));
	ds.addMember("Sprite icon", offsetof(Design, icon));
	ds.addMember("Sprite distantIcon", offsetof(Design, distantIcon));
	ds.addMember("Sprite fleetIcon", offsetof(Design, fleetIcon));
	ds.addMember("bool forceHull", offsetof(Design, forceHull));

	if(server)
		ds.addMember("const Serializable@ settings", offsetof(Design, serverData));
	else
		ds.addMember("const Serializable@ settings", offsetof(Design, clientData));

	ds.addMember("const Design@ newer", offsetof(Design, newer));
	ds.addMember("const Design@ original", offsetof(Design, original));
	ds.addMember("const Design@ updated", offsetof(Design, updated));

	ds.addMember("double topHP", offsetof(Design, quadrantTotalHP[0]));
	ds.addMember("double rightHP", offsetof(Design, quadrantTotalHP[1]));
	ds.addMember("double bottomHP", offsetof(Design, quadrantTotalHP[2]));
	ds.addMember("double leftHP", offsetof(Design, quadrantTotalHP[3]));
	ds.addExternMethod("double get_quadrantTotalHP(uint index) const", asFUNCTION(quadrantTotalHP));
	ds.addMethod("uint getQuadrant(const vec2u& pos) const", asMETHOD(Design, getQuadrant));

	ds.addMethod("const Design& newest() const", asMETHOD(Design, newest));
	ds.addMethod("const Design& next() const", asMETHOD(Design, next));
	ds.addMethod("const Design& mostUpdated() const", asMETHOD(Design, mostUpdated));
	ds.addMethod("const Design& base() const", asMETHOD(Design, base));
	ds.addMethod("bool hasTag(const string &in tag) const", asMETHODPR(Design, hasTag, (const std::string&) const, bool));
	ds.addMethod("bool hasTag(SubsystemTag tag) const", asMETHODPR(Design, hasTag, (int) const, bool));
	ds.addExternMethod("bool hasSubsystem(const SubsystemDef&) const", asFUNCTION(hasSubsys));
	ds.addMethod("void toDescriptor(DesignDescriptor& desc) const", asMETHOD(Design, toDescriptor));

	ds.addExternMethod("void rename(const string &in name) const", asFUNCTION(dsgRename))
		doc("Renames a design, but only if it is not in use.", "");

	ds.addExternMethod("int get_built() const", asFUNCTION(dsgGetBuilt));
	ds.addExternMethod("void incBuilt() const", asFUNCTION(dsgIncBuilt));
	ds.addExternMethod("void decBuilt() const", asFUNCTION(dsgDecBuilt));
	ds.addExternMethod("int get_active() const", asFUNCTION(dsgGetActive));

	ds.addExternMethod("float variable(ShipVariable var) const", asFUNCTION(dsgGetShipVar));
	ds.addExternMethod("float& variable(ShipVariable var)", asFUNCTION(dsgShipVarPtr));

	ds.addExternMethod("float variable(const Subsystem& sys, SubsystemVariable var) const", asFUNCTION(dsgGetVar));
	ds.addExternMethod("float& variable(Subsystem& sys, SubsystemVariable var)", asFUNCTION(dsgVarPtr));

	ds.addExternMethod("bool has(const vec2u& hex, HexVariable var) const", asFUNCTION(dsgHasHexVar));
	ds.addExternMethod("float variable(const vec2u& hex, HexVariable var) const", asFUNCTION(dsgGetHexVar));
	ds.addExternMethod("float& variable(const vec2u& hex, HexVariable var)", asFUNCTION(dsgHexVarPtr));

	ds.addExternMethod("float total(SubsystemVariable var) const", asFUNCTION(dsgSysTotal));
	ds.addExternMethod("float total(HexVariable var) const", asFUNCTION(dsgHexTotal));

	ds.addExternMethod("float average(SubsystemVariable var) const", asFUNCTION(dsgSysAvg));
	ds.addExternMethod("float average(HexVariable var) const", asFUNCTION(dsgHexAvg));

	ds.addExternMethod("uint get_subsystemCount() const", asFUNCTION(sysCount));
	ds.addExternMethod("const Subsystem@ get_subsystems(uint i) const", asFUNCTION(getSys));
	ds.addExternMethod("const Subsystem@ subsystem(uint i) const", asFUNCTION(getSys));
	ds.addExternMethod("const Subsystem@ subsystem(uint x, uint y) const", asFUNCTION(getHexSys));
	ds.addExternMethod("const Subsystem@ subsystem(const vec2u& hex) const", asFUNCTION(getHexSys_v));
	ds.addExternMethod("const ModuleDef@ module(uint x, uint y) const", asFUNCTION(getHexModule));
	ds.addExternMethod("const ModuleDef@ module(const vec2u& hex) const", asFUNCTION(getHexModule_v));
	ds.addExternMethod("const int hexIndex(const vec2u& hex) const", asFUNCTION(getHexIndex));
	ds.addExternMethod("const int hexStatusIndex(const vec2u& hex) const", asFUNCTION(getHexStatusIndex));
	ds.addExternMethod("bool validHex(const vec2u& hex) const", asFUNCTION(isValidhex));
	ds.addExternMethod("void setObsolete(bool obsolete) const", asFUNCTION(setDesignObsolete));
	ds.addExternMethod("void setSettings(const Serializable& ser) const", asFUNCTION(setDesignData));

	//Design errors
	ClassBind de("DesignError", asOBJ_REF | asOBJ_NOCOUNT);
	de.addMember("bool fatal", offsetof(DesignError, fatal));
	de.addMember("string text", offsetof(DesignError, text));
	de.addMember("const Subsystem@ subsys", offsetof(DesignError, subsys));
	de.addMember("const ModuleDef@ module", offsetof(DesignError, module));
	de.addMember("vec2i hex", offsetof(DesignError, hex));

	ds.addMethod("bool hasFatalErrors() const", asMETHOD(Design, hasFatalErrors));
	ds.addExternMethod("uint get_errorCount() const", asFUNCTION(dsgErrorCount));
	ds.addExternMethod("DesignError@ get_errors(uint) const", asFUNCTION(dsgError));
	ds.addExternMethod("void addError(bool fatal, const string&in text, const Subsystem@ subsys, const ModuleDef@ module, vec2u hex)", asFUNCTION(dsgAddError));
	ds.addExternMethod("void addErrorHex(const vec2u& hex)", asFUNCTION(dsgAddErrorHex));
	ds.addExternMethod("bool isErrorHex(const vec2u& hex) const", asFUNCTION(dsgIsErrorHex));

	//Design classes
	ClassBind dc("DesignClass");
	dc.addMember("uint id", offsetof(DesignClass, id));
	dc.addMember("string name", offsetof(DesignClass, name));
	dc.addExternMethod("uint get_designCount() const", asFUNCTION(designCount));
	dc.addExternMethod("const Design@ get_designs(uint i) const", asFUNCTION(getDesign));
	ds.addMember("const DesignClass@ cls", offsetof(Design, cls));

	//Design descriptor for instantiation
	desc.addConstructor("void f()", asFUNCTION(descMake));
	desc.addDestructor("void f()", asFUNCTION(descDestroy));
	desc.addExternMethod("DesignDescriptor& opAssign(const DesignDescriptor&in other)", asFUNCTION(descCopy));
	desc.addMember("string name", offsetof(Design::Descriptor, name));
	desc.addMember("string className", offsetof(Design::Descriptor, className));
	desc.addMember("string hullName", offsetof(Design::Descriptor, hullName));
	desc.addMember("bool staticHull", offsetof(Design::Descriptor, staticHull));
	desc.addMember("bool forceHull", offsetof(Design::Descriptor, forceHull));
	desc.addMember("Serializable@ settings", offsetof(Design::Descriptor, settings));
	desc.addMember("const Hull@ hull", offsetof(Design::Descriptor, hull));
	desc.addMember("double size", offsetof(Design::Descriptor, size));
	desc.addMember("vec2u gridSize", offsetof(Design::Descriptor, gridSize));
	desc.addMember("Empire@ owner", offsetof(Design::Descriptor, owner));

	desc.addExternMethod("uint addSystem(const SubsystemDef& type)", asFUNCTION(descAddSys));
	desc.addExternMethod("void setDirection(const vec3d& dir)", asFUNCTION(descSetDirection));
	desc.addExternMethod("void addHex(uint num, vec2u pos)", asFUNCTION(descAddHex));
	desc.addExternMethod("void addHex(vec2u pos)", asFUNCTION(descAddHex_l));
	desc.addExternMethod("void addHex(uint num, vec2u pos, const ModuleDef& mod)", asFUNCTION(descAddHex_m));
	desc.addExternMethod("void addHex(vec2u pos, const ModuleDef& mod)", asFUNCTION(descAddHex_lm));
	desc.addExternMethod("void applySubsystem(const SubsystemDef& type)", asFUNCTION(descApply));

	bind("const Design@ makeDesign(const DesignDescriptor &in desc)", asFUNCTION(makeDesign));

	//Hooks
	InterfaceBind sh("SubsystemHook");
	ClassBind se("SubsystemEvent", asOBJ_VALUE, sizeof(SubsystemEvent));
	se.addConstructor("void f()", asFUNCTION(ssevtMake));
	se.addDestructor("void f()", asFUNCTION(ssevtDestroy));
	se.addMember("Object@ obj", offsetof(SubsystemEvent, obj));
	se.addMember("const Design@ design", offsetof(SubsystemEvent, design));
	se.addMember("const Subsystem@ subsystem", offsetof(SubsystemEvent, subsystem));
	se.addMember("Blueprint@ blueprint", offsetof(SubsystemEvent, blueprint));
	se.addMember("any@ data", offsetof(SubsystemEvent, data));
	se.addMember("float efficiency", offsetof(SubsystemEvent, efficiency));
	se.addMember("float workingPercent", offsetof(SubsystemEvent, partiality));
	se.addMember("float partiality", offsetof(SubsystemEvent, partiality));

	if(server) {
		ClassBind strlist("StringList", asOBJ_REF | asOBJ_NOCOUNT);
		strlist.addExternMethod("uint get_length()", asFUNCTION(strvec_length));
		strlist.addExternMethod("const string& opIndex(uint num)", asFUNCTION(strvec_get));

		ClassBind dblList("DoubleList", asOBJ_REF | asOBJ_NOCOUNT);
		dblList.addExternMethod("uint get_length()", asFUNCTION(dblvec_length));
		dblList.addExternMethod("double opIndex(uint num)", asFUNCTION(dblvec_get));

		sh.addMethod("bool init(Design& design, Subsystem& subsystem, StringList& arguments, DoubleList& values) const", &Subsystem::ScriptInitFunction);
		sh.addMethod("void start(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Start]);
		sh.addMethod("void tick(SubsystemEvent& event, double time) const", &Subsystem::ScriptHookFunctions[EH_Tick]);
		sh.addMethod("void suspend(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Suspend]);
		sh.addMethod("void resume(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Continue]);
		sh.addMethod("void destroy(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Destroy]);
		sh.addMethod("void end(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_End]);
		sh.addMethod("void change(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Change]);
		sh.addMethod("void save(SubsystemEvent& event, SaveFile& file) const", &Subsystem::ScriptHookFunctions[EH_Save]);
		sh.addMethod("void load(SubsystemEvent& event, SaveFile& file) const", &Subsystem::ScriptHookFunctions[EH_Load]);
		sh.addMethod("void ownerChange(SubsystemEvent& event, Empire@ prevEmpire, Empire@ newEmpire) const", &Subsystem::ScriptHookFunctions[EH_Owner_Change]);
		sh.addMethod("DamageEventStatus damage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position) const", &Subsystem::ScriptHookFunctions[EH_Damage]);
		sh.addMethod("DamageEventStatus globalDamage(SubsystemEvent& event, DamageEvent& damage, const vec2u& position, vec2d& endPoint) const", &Subsystem::ScriptHookFunctions[EH_GlobalDamage]);
		sh.addMethod("void preRetrofit(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Retrofit_Pre]);
		sh.addMethod("void postRetrofit(SubsystemEvent& event) const", &Subsystem::ScriptHookFunctions[EH_Retrofit_Post]);

		sys.addExternMethod("uint get_hookCount() const", asFUNCTION(sysHookCount));
		sys.addExternMethod("SubsystemHook@ get_hooks(uint index) const", asFUNCTION(sysHookGet));
	}
}

};
