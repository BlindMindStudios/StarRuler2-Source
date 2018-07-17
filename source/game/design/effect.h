#pragma once
#include "util/formula.h"
#include "compat/misc.h"
#include "obj/object.h"
#include "util/refcount.h"
#include <string>
#include <vector>
#include <map>
#include <unordered_map>

#ifndef EFFECT_MAX_VALUES
	#define EFFECT_MAX_VALUES 6
#endif

class asIScriptFunction;
namespace net {
	struct Message;
};

enum EffectHook {
	EH_Start,
	EH_Tick,
	EH_Suspend,
	EH_Continue,
	EH_Destroy,
	EH_End,
	EH_Change,
	EH_Damage,
	EH_GlobalDamage,
	EH_Retrofit_Pre,
	EH_Retrofit_Post,
	EH_Owner_Change,
	EH_Save,
	EH_Load,
	EH_COUNT
};

class EffectDef {
public:
	std::string name;
	int id;

	umap<std::string, unsigned> valueNames;
	unsigned valueCount;
	struct ValueDesc {
		Formula* defaultValue;

		ValueDesc() : defaultValue(nullptr) {}
	};
	std::vector<ValueDesc> values;

	std::map<EffectHook, std::string> hookDefinitions;
	asIScriptFunction* hooks[EH_COUNT];
	void setHook(EffectHook hook, const std::string& ref);

	EffectDef();
};

enum EffectStatus {
	ES_Active,
	ES_Suspended,
	ES_Ended,
};

class Subsystem;
class EffectEvent {
public:
	vec3d impact;
	vec2d direction;
	heldPointer<Object> obj;
	heldPointer<Object> target;
	double time;
	float efficiency;
	float partiality;
	int source;
	int destination;
	float custom1;
	float custom2;
	EffectStatus status;

	EffectEvent();
	~EffectEvent();
};

enum DamageEventStatus {
	DE_Continue,
	DE_SkipHex,
	DE_EndDamage,
};

class DamageEvent {
public:
	vec3d impact;
	double damage;
	float pierce;
	float partiality;
	float custom1;
	float custom2;
	unsigned flags;
	bool spillable;

	int source;
	int destination;
	heldPointer<Object> obj;
	heldPointer<Object> target;

	DamageEvent();
	~DamageEvent();
};

class Effect {
public:
	const EffectDef* type;
	double values[EFFECT_MAX_VALUES];

	Effect();
	Effect(const EffectDef* Type);

	void call(EffectHook hook, EffectEvent& event) const;
	DamageEventStatus damage(DamageEvent& event, const vec2u& position) const;
	DamageEventStatus globalDamage(DamageEvent& event, vec2u& position, vec2d& endPoint) const;
	void ownerChange(EffectEvent& event, Empire* prevEmpire, Empire* newEmpire) const;

	void writeData(net::Message& msg) const;
	void readData(net::Message& msg);
};

class TimedEffect {
public:
	EffectEvent event;
	Effect effect;
	double remaining;

	TimedEffect();
	TimedEffect(const TimedEffect& other);
	TimedEffect(const EffectDef* Type, double Time);
	TimedEffect(const Effect& Effect, double Time);
	~TimedEffect();
	void call(EffectHook hook);
	void tick(double time);
};

void loadEffectDefinitions(const std::string& filename);
const EffectDef* getEffectDefinition(const std::string& name);
const EffectDef* getEffectDefinition(int index);
unsigned getEffectDefinitionCount();
void enumerateEffectDefinitions(void (*cb)(const std::string&,int));
void bindEffectHooks();
void clearEffectDefinitions();
