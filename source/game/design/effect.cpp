#include "design/effect.h"
#include "compat/misc.h"
#include "main/references.h"
#include "main/logging.h"
#include "network/message.h"
#include "str_util.h"
#include <unordered_map>

static std::vector<EffectDef*> effectDefinitions;
static umap<std::string, int> effectIndices;

static const char* callback_retval[EH_COUNT] = {
	"void",
	"void",
	"void",
	"void",
	"void",
	"void",
	"void",
	"DamageEventStatus",
	"DamageEventStatus",
	"void",
	"void",
	"void",
	"void",
	"void",
};

static const char* callback_basedecl[EH_COUNT] = {
	"Event&",
	"Event&",
	"Event&",
	"Event&",
	"Event&",
	"Event&",
	"Event&",
	"DamageEvent&, const vec2u&",
	"DamageEvent&, vec2u&, vec2d&",
	"Event&",
	"Event&",
	"Event&, Empire@, Empire@",
	"Event&",
	"Event&",
};

void clearEffectDefinitions() {
	effectIndices.clear();
	foreach(it, effectDefinitions)
		delete *it;
	effectDefinitions.clear();
}

void loadEffectDefinitions(const std::string& filename) {
	EffectDef* def = 0;

	DataHandler datahandler;

	datahandler("Effect", [&](std::string& value) {
		auto it = effectIndices.find(value);
		if(it != effectIndices.end()) {
			def = 0;
			error("Error: Duplicate effect %s.", value.c_str());
			return;
		}

		def = new EffectDef();
		def->name = value;
		def->id = (unsigned)effectDefinitions.size();
		def->valueCount = 0;

		effectDefinitions.push_back(def);
		effectIndices[def->name] = def->id;
	});

	datahandler("Value", [&](std::string& value) {
		if(!def)
			return;

		if(def->valueCount >= EFFECT_MAX_VALUES) {
			error("(Effect %s): Error: Maximum of 6 values allowed per effect.", def->name.c_str());
			return;
		}

		EffectDef::ValueDesc desc;
		auto pos = value.find('=');
		if(pos != std::string::npos) {
			if(pos < value.size() - 1)
				desc.defaultValue = Formula::fromInfix(value.substr(pos+1).c_str());
			value = trim(value.substr(0, pos));
		}

		auto it = def->valueNames.find(value);
		if(it != def->valueNames.end()) {
			error("(Effect %s): Error: Duplicate effect value %s.", def->name.c_str(), value.c_str());
			return;
		}

		def->valueNames[value] = def->valueCount;
		def->values.push_back(desc);
		++def->valueCount;
	});

	datahandler("Start", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Start] = value;
	});

	datahandler("Destroy", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Destroy] = value;
	});

	datahandler("End", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_End] = value;
	});

	datahandler("Suspend", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Suspend] = value;
	});

	datahandler("Continue", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Continue] = value;
	});

	datahandler("Change", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Change] = value;
	});

	datahandler("Damage", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Damage] = value;
	});

	datahandler("Tick", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Tick] = value;
	});

	datahandler("GlobalDamage", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_GlobalDamage] = value;
	});

	datahandler("RetrofitPre", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Retrofit_Pre] = value;
	});

	datahandler("RetrofitPost", [&](std::string& value) {
		if(def)
			def->hookDefinitions[EH_Retrofit_Post] = value;
	});

	datahandler.read(filename);
}

EffectDef::EffectDef() : id(-1), valueCount(0), hooks() {
}

void EffectDef::setHook(EffectHook hook, const std::string& ref) {
	std::vector<std::string> args;
	split(ref, args, "::");
	
	if(args.size() != 2) {
		error("(Effect %s): Error: Invalid script function reference.", name.c_str());
		hooks[hook] = 0;
		return;
	}

	//Find the module the function is in
	scripts::Module* modu = devices.scripts.server->getModule(args[0].c_str());
	if(!modu) {
		error("(Effect %s): Error: Invalid script module '%s'.", name.c_str(), args[0].c_str());
		hooks[hook] = 0;
		return;
	}

	//Build declaration for function
	std::string def;
	def = callback_retval[hook];
	def += " "+args[1]+"(";
	def += callback_basedecl[hook];
	for(unsigned i = 0; i < valueCount; ++i) {
		def += ",double";
	}
	def += ")";

	//Find the function
	asIScriptFunction* func = modu->getFunction(def.c_str());
	if(!func) {
		error("(Effect %s): Error: Could not find script function '%s'.", name.c_str(), def.c_str());
		hooks[hook] = 0;
		return;
	}

	hooks[hook] = func;
}

Effect::Effect() : type(0) {
}

Effect::Effect(const EffectDef* Type) : type(Type) {
}

void Effect::call(EffectHook hook, EffectEvent& event) const {
	if(!type)
		return;
	auto* func = type->hooks[hook];
	if(!func)
		return;
	scripts::Call cl = devices.scripts.server->call(func);
	if(cl.ctx) {
		cl.push((void*)&event);
		for(unsigned i = 0; i < type->valueCount; ++i)
			cl.push(values[i]);
		cl.call();
	}
}

DamageEventStatus Effect::damage(DamageEvent& event, const vec2u& position) const {
	if(!type || type->hooks[EH_Damage] == nullptr)
		return DE_Continue;
	scripts::Call cl = devices.scripts.server->call(type->hooks[EH_Damage]);
	unsigned status = DE_Continue;
	if(cl.ctx) {
		cl.push((void*)&event);
		cl.push((void*)&position);
		for(unsigned i = 0; i < type->valueCount; ++i)
			cl.push(values[i]);
		cl.call(status);
	}
	return (DamageEventStatus)status;
}

void Effect::ownerChange(EffectEvent& event, Empire* prevEmpire, Empire* newEmpire) const {
	if(!type || type->hooks[EH_Owner_Change] == nullptr)
		return;
	scripts::Call cl = devices.scripts.server->call(type->hooks[EH_Owner_Change]);
	if(cl.ctx) {
		cl.push((void*)&event);
		cl.push((void*)prevEmpire);
		cl.push((void*)newEmpire);
		for(unsigned i = 0; i < type->valueCount; ++i)
			cl.push(values[i]);
		cl.call();
	}
}

DamageEventStatus Effect::globalDamage(DamageEvent& event, vec2u& position, vec2d& endPoint) const {
	if(!type || type->hooks[EH_GlobalDamage] == nullptr)
		return DE_Continue;
	scripts::Call cl = devices.scripts.server->call(type->hooks[EH_GlobalDamage]);
	unsigned status = DE_Continue;
	if(cl.ctx) {
		cl.push((void*)&event);
		cl.push((void*)&position);
		cl.push((void*)&endPoint);
		for(unsigned i = 0; i < type->valueCount; ++i)
			cl.push(values[i]);
		cl.call(status);
	}
	return (DamageEventStatus)status;
}

void Effect::writeData(net::Message& msg) const {
	if(type) {
		msg.write1();
		msg.writeLimited(type->id, (unsigned)effectDefinitions.size()-1);
	}
	else {
		msg.write0();
	}
	for(size_t i = 0; i < EFFECT_MAX_VALUES; ++i)
		msg << (float)values[i];
}

void Effect::readData(net::Message& msg) {
	if(msg.readBit()) {
		unsigned typeId = msg.readLimited((unsigned)effectDefinitions.size()-1);
		type = getEffectDefinition(typeId);
	}
	else {
		type = nullptr;
	}
	for(size_t i = 0; i < EFFECT_MAX_VALUES; ++i) {
		float v;
		msg >> v;
		values[i] = v;
	}
}

TimedEffect::TimedEffect()
	: remaining(0.0) {
}

TimedEffect::TimedEffect(const TimedEffect& other)
	: remaining(other.remaining) {
	event = other.event;
	effect = other.effect;
}

TimedEffect::~TimedEffect() {
}

TimedEffect::TimedEffect(const EffectDef* Type, double Time)
	: effect(Type), remaining(Time) {
}

TimedEffect::TimedEffect(const Effect& Effect, double Time)
	: remaining(Time) {
	effect = Effect;
}

void TimedEffect::call(EffectHook hook) {
	effect.call(hook, event);
}

void TimedEffect::tick(double time) {
	event.time = time;
	effect.call(EH_Tick, event);

	if(event.status != ES_Suspended) {
		remaining -= time;

		if(remaining <= 0.0)
			event.status = ES_Ended;
	}
}

EffectEvent::EffectEvent()
	: time(0.0), efficiency(1.f), partiality(1.f), source(-1), destination(-1), obj(0),
		target(0), status(ES_Active), custom1(0.f), custom2(0.f) {
}

EffectEvent::~EffectEvent() {
}

DamageEvent::DamageEvent()
	: damage(0.0), pierce(0.f), partiality(1.f), flags(0), source(-1), destination(-1), obj(0),
		target(0), custom1(0), custom2(0), spillable(true) {
}

DamageEvent::~DamageEvent() {
}

const EffectDef* getEffectDefinition(const std::string& name) {
	auto it = effectIndices.find(name);
	if(it == effectIndices.end())
		return 0;
	return effectDefinitions[it->second];
}

const EffectDef* getEffectDefinition(int index) {
	if(index < 0 || index >= (int)effectDefinitions.size())
		return 0;
	return effectDefinitions[index];
}

unsigned getEffectDefinitionCount() {
	return effectDefinitions.size();
}

void enumerateEffectDefinitions(void (*cb)(const std::string&,int)) {
	foreach(it, effectDefinitions)
		cb((*it)->name, (*it)->id);
}

void bindEffectHooks() {
	foreach(it, effectDefinitions) {
		foreach(h, (*it)->hookDefinitions) {
			(*it)->setHook(h->first, h->second);
		}
	}
}
