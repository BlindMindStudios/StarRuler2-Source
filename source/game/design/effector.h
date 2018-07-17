#pragma once
#include "util/formula.h"
#include "scripts/manager.h"
#include "design/effect.h"
#include "render/render_state.h"
#include "threads.h"
#include <vector>
#include <unordered_map>

class Object;
class Effector;
class Design;
struct EffectorTarget;
class HullDef;

namespace net {
	struct Message;
};

namespace resource {
	class Sound;
};

namespace scene {
	class Node;
	struct ParticleSystemDesc;
};

typedef Object*(*nativeTargetAlgorithm)(const Effector*, Object*, EffectorTarget* targ);
struct TargetAlgorithm {
	union {
		nativeTargetAlgorithm native;
		asIScriptFunction* script;
	};
	bool isNative;
};

typedef double(*nativeTargetWeighter)(const Effector*, Object*, Object*, void*);
struct TargetWeighter {
	union {
		nativeTargetWeighter native;
		asIScriptFunction* script;
	};
	bool isNative;
	void* arg;

	TargetWeighter() {
		script = 0;
		isNative = false;
		arg = 0;
	}
};

struct EffectorTarget;

enum EffectorActivationType {
	EAT_Inactive,
	EAT_Activate,
	EAT_Repeat
};

typedef EffectorActivationType(*nativeEffectorActivation)(const Effector*, Object*, EffectorTarget& targ, double&, double*, double*);
struct EffectorActivation {
	union {
		nativeEffectorActivation native;
		asIScriptFunction* script;
	};
	bool isNative;
};

enum EffectorPhysicalType {
	EPT_Instant,
	EPT_Projectile,
	EPT_Missile,
	EPT_AimedMissile,
	EPT_Beam,
};

enum EffectorGraphicType {
	EGT_Sprite,
	EGT_Beam,
	EGT_Line
};

enum EffectorEfficiencyMode {
	EEM_Normal,
	EEM_Reload_Partial,
	EEM_Duration_Partial,
	EEM_Reload,
	EEM_Duration,
};

struct EffectorSkin {
	EffectorGraphicType graphicType;
	double graphicSize;
	double length;
	std::string trailMatID;
	const render::RenderState* trailMat;
	Color trailStart, trailEnd, color;

	std::string def_material;
	const render::RenderState* material;

	std::string def_impact;
	const scene::ParticleSystemDesc* impact;

	float fire_pitch_variance;
	std::vector<std::string> fire_sound_names;
	std::vector<const resource::Sound*> fire_sounds;

	std::string def_impact_sound;
	const resource::Sound* impact_sound;

	EffectorSkin();
};

class EffectorDef {
public:
	unsigned index;
	std::string name;
	std::unordered_map<std::string, unsigned> valueNames;

	Formula* range, *lifetime, *tracking, *speed, *spread, *capTarget;
	Formula* fireArc, *targetTolerance, *fireTolerance;

	std::string def_algorithm;
	std::string def_activation;
	std::string def_canTarget;
	std::string def_autoTarget;
	std::string def_onTrigger;

	TargetAlgorithm algorithm;
	EffectorActivation activation;
	asIScriptFunction* onTrigger;

	std::vector<TargetWeighter> canTargetWeighters;
	Formula* canTarget;
	std::vector<TargetWeighter> autoTargetWeighters;
	Formula* autoTarget;

	//Whether the projectile should hit a target according to physical behaviors, or only the chosen target
	bool physicalImpact;
	bool passthroughInvalid;

	bool pierces;
	float recoverTime;
	
	EffectorEfficiencyMode efficiencyMode;
	EffectorPhysicalType physicalType;
	double physicalSize;

	std::unordered_map<std::string, unsigned> skinNames;
	
	unsigned valueCount;
	struct ValueDesc {
		Formula* defaultValue;

		ValueDesc() : defaultValue(nullptr) {}
	};
	std::vector<ValueDesc> values;

	unsigned stateCount;
	std::vector<Formula*> arguments;
	std::vector<Formula*> triggerArguments;

	const EffectDef* effect;
	std::vector<Formula*> effectValues;

	std::vector<EffectorSkin> skins;

	void triggerGraphics(Object* obj, EffectorTarget& targ, const Effector* effector, double* time = 0, vec2d* direction = 0, float efficiency = 1.f, double tOffset = 0) const;
	EffectorDef();
};

enum TargetFlags {
	TF_Target = 0,
	TF_Preference = 0x1,
	TF_Group = 0x2,
	TF_Firing = 0x4,
	TF_Retarget = 0x8,
	TF_TrackingProgress = 0x10,
	TF_ClearTracking = 0x20,
	TF_WithinFireTolerance = 0x40,
};

struct EffectorTarget {
	Object* target;
	unsigned flags;
	unsigned char hits;
	vec3d tracking;
};

class Effector {
	mutable threads::atomic_int refs;
public:
	const Design* inDesign;
	unsigned subsysIndex;
	unsigned effectorIndex;
	mutable unsigned effectorId;

	unsigned skinIndex;

	vec3d relativePosition;
	vec3d turretAngle;
	double relativeSize;
	bool enabled;

	const EffectorDef& type;
	double* values;
	double range, lifetime, tracking, speed, spread;
	double fireArc, targetTolerance, fireTolerance;
	unsigned capTarget;
	unsigned stateOffset;
	Effect effect;

	Effector(const EffectorDef& def);
	~Effector();
	void initValues();

	void load(SaveFile& file);
	void save(SaveFile& file) const;

	static const Effector* receiveUpdate(net::Message& msg);
	void sendUpdate(net::Message& msg) const;
	void sendDestruction(net::Message& msg) const;

	void grab() const;
	void drop() const;

	bool isInRange(Object* obj, Object* target, bool considerArc = true) const;
	bool canTarget(Object* obj, Object* target) const;
	bool autoTarget(Object* obj, Object* target) const;
	double getTargetWeight(Object* obj, Object* target) const;
	
	void trigger(Object* obj, EffectorTarget& targ, float efficiency, double tOffset = 0) const;
	void triggerEffect(Object* obj, Object* target, const vec3d& impactOffset, float efficiency, float partiality, double delay = 0.0) const;
	void update(Object* obj, double time, double* states, EffectorTarget& target, float efficiency, bool holdFire = false) const;

	void setRelativePosition(vec2u hex, const HullDef* hull, vec3d direction);

	void writeData(net::Message& msg) const;
	Effector(net::Message& msg);
};

void clearEffectorDefinitions();
void loadEffectorDefinitions(const std::string& filename);
unsigned getEffectorDefinitionCount();
const EffectorDef* getEffectorDefinition(const std::string& name);
const EffectorDef* getEffectorDefinition(unsigned index);
void bindEffectorHooks(bool shadow = false);
void bindEffectorResources();

extern std::unordered_map<unsigned, const Effector*> effectorMap;
void registerEffector(const Effector* eff);
void unregisterEffector(const Effector* eff);
const Effector* getEffector(unsigned id);
void clearEffectors();

void saveEffectors(SaveFile& file);
void loadEffectors(SaveFile& file);
void postLoadEffectors();
