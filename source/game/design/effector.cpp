#include "design/effector.h"
#include "design/hull.h"
#include "main/references.h"
#include "main/logging.h"
#include "compat/misc.h"
#include "str_util.h"
#include "design/effector_functions.h"
#include "threads.h"
#include "scene/billboard_node.h"
#include "scene/beam_node.h"
#include "scene/line_trail_node.h"
#include "scene/frame_line.h"
#include "scene/animation/anim_projectile.h"
#include "scene/animation/anim_linear.h"
#include "util/random.h"
#include "util/save_file.h"
#include "network/network_manager.h"
#include "design/projectiles.h"
#include "empire.h"
#include <assert.h>

#include "ISoundDevice.h"
#include "ISound.h"

#include <algorithm>

static std::vector<EffectorDef*> effIds;
static umap<std::string, EffectorDef*> effDefs;
extern int FindQuarticRoots(const double coeff[5], double x[4]);
extern int FindCubicRoots(const double coeff[4], double x[3]);

std::unordered_map<unsigned, const Effector*> effectorMap;
std::vector<const Effector*> loadedEffectors;
static unsigned nextEffId = 1;
static threads::Mutex effMutex;

void registerEffector(const Effector* eff) {
	threads::Lock lock(effMutex);
	if(eff->effectorId == 0) {
		eff->effectorId = nextEffId++;
	}
	else {
		if(nextEffId <= eff->effectorId)
			nextEffId = eff->effectorId+1;
	}
	eff->grab();
	effectorMap[eff->effectorId] = eff;
}

void unregisterEffector(const Effector* eff) {
	threads::Lock lock(effMutex);
	auto it = effectorMap.find(eff->effectorId);
	if(it != effectorMap.end()) {
		effectorMap.erase(it);
		eff->drop();
	}
}

const Effector* getEffector(unsigned id) {
	threads::Lock lock(effMutex);
	auto it = effectorMap.find(id);
	if(it != effectorMap.end()) {
		it->second->grab();
		return it->second;
	}
	return nullptr;
}

void clearEffectors() {
	nextEffId = 1;
	foreach(it, effectorMap)
		it->second->drop();
	effectorMap.clear();
}

void clearEffectorDefinitions() {
	foreach(it, effDefs)
		delete it->second;
	effDefs.clear();
	effIds.clear();
}

void loadEffectorDefinitions(const std::string& filename) {
	EffectorDef* eff = nullptr;
	EffectorSkin* skin = nullptr;
	DataHandler handler;

	handler("Effector", [&](std::string& value) {
		eff = new EffectorDef();
		eff->name = value;
		eff->index = (unsigned)effIds.size();
		skin = &eff->skins[0];

		effDefs[eff->name] = eff;
		effIds.push_back(eff);
	});

	handler("Value", [&](std::string& value) {
		EffectorDef::ValueDesc desc;
		auto pos = value.find('=');
		if(pos != std::string::npos) {
			if(pos < value.size() - 1)
				desc.defaultValue = Formula::fromInfix(value.substr(pos+1).c_str());
			value = trim(value.substr(0, pos));
		}

		eff->valueNames[value] = eff->valueCount++;
		eff->values.push_back(desc);
	});

	handler("Range", [&](std::string& value) {
		eff->range = Formula::fromInfix(value.c_str());
	});

	handler("Lifetime", [&](std::string& value) {
		eff->lifetime = Formula::fromInfix(value.c_str());
	});

	handler("Tracking", [&](std::string& value) {
		eff->tracking = Formula::fromInfix(value.c_str());
	});

	handler("Spread", [&](std::string& value) {
		eff->spread = Formula::fromInfix(value.c_str());
	});

	handler("CapTarget", [&](std::string& value) {
		eff->capTarget = Formula::fromInfix(value.c_str());
	});

	handler("FireArc", [&](std::string& value) {
		eff->fireArc = Formula::fromInfix(value.c_str());
	});

	handler("TargetTolerance", [&](std::string& value) {
		eff->targetTolerance = Formula::fromInfix(value.c_str());
	});

	handler("FireTolerance", [&](std::string& value) {
		eff->fireTolerance = Formula::fromInfix(value.c_str());
	});

	handler("Speed", [&](std::string& value) {
		eff->speed = Formula::fromInfix(value.c_str());
	});

	handler("TargetAlgorithm", [&](std::string& value) {
		eff->def_algorithm = value;
	});

	handler("Activation", [&](std::string& value) {
		eff->def_activation = value;
	});

	handler("OnTrigger", [&](std::string& value) {
		eff->def_onTrigger = value;
	});

	handler("States", [&](std::string& value) {
		eff->stateCount = toNumber<unsigned>(value);
	});

	handler("CanTarget", [&](std::string& value) {
		eff->def_canTarget = value;
	});

	handler("AutoTarget", [&](std::string& value) {
		eff->def_autoTarget = value;
	});

	handler("Physical", [&](std::string& value) {
		eff->physicalImpact = toBool(value, true);
	});

	handler("PassthroughInvalid", [&](std::string& value) {
		eff->passthroughInvalid = toBool(value, true);
	});

	handler("Pierces", [&](std::string& value) {
		eff->pierces = toBool(value, true);
	});

	handler("RecoverTime", [&](std::string& value) {
		eff->recoverTime = toNumber<float>(value);
	});

	handler("Effect", [&](std::string& value) {
		eff->effect = getEffectDefinition(value);
		if(!eff->effect) {
			error(handler.position());
			error("  Unknown effect '%s'.\n", value.c_str());
			return;
		}
		eff->effectValues.resize(eff->effect->valueCount);
	});

	handler("EfficiencyMode", [&](std::string& value) {
		if(value == "Normal") {
			eff->efficiencyMode = EEM_Normal;
		}
		else if(value == "Reload Only") {
			eff->efficiencyMode = EEM_Reload;
		}
		else if(value == "Duration Only") {
			eff->efficiencyMode = EEM_Duration;
		}
		else if(value == "Reload Partial") {
			eff->efficiencyMode = EEM_Reload_Partial;
		}
		else if(value == "Duration Partial") {
			eff->efficiencyMode = EEM_Duration_Partial;
		}
	});

	handler("PhysicalType", [&](std::string& value) {
		if(value == "Instant") {
			eff->physicalType = EPT_Instant;
		}
		else if(value == "Projectile") {
			eff->physicalType = EPT_Projectile;
		}
		else if(value == "Missile") {
			eff->physicalType = EPT_Missile;
		}
		else if(value == "Aimed Missile") {
			eff->physicalType = EPT_AimedMissile;
		}
		else if(value == "Beam") {
			eff->physicalType = EPT_Beam;
		}
	});

	handler("PhysicalSize", [&](std::string& value) {
		eff->physicalSize = toNumber<double>(value);
	});

	handler("Skin", [&](std::string& value) {
		if(eff->skinNames.find(value) != eff->skinNames.end())
			error("Duplicate skin '%s' in effector '%s'", value.c_str(), eff->name.c_str());
		eff->skinNames[value] = eff->skins.size();
		eff->skins.resize(eff->skins.size() + 1);
		skin = &eff->skins.back();
		*skin = eff->skins[0];
	});

	handler("Inherit", [&](std::string& value) {
		auto it = eff->skinNames.find(value);
		if(it == eff->skinNames.end()) {
			error("Cannot find skin '%s' in effector '%s' to inherit from.", value.c_str(), eff->name.c_str());
			return;
		}

		*skin = eff->skins[it->second];
	});

	handler("GfxType", [&](std::string& value) {
		if(value == "Sprite")
			skin->graphicType = EGT_Sprite;
		else if(value == "Line")
			skin->graphicType = EGT_Line;
		else if(value == "Beam")
			skin->graphicType = EGT_Beam;
	});

	handler("GfxSize", [&](std::string& value) {
		skin->graphicSize = toNumber<double>(value);
	});

	handler("GfxLength", [&](std::string& value) {
		skin->length = toNumber<double>(value);
	});

	handler("Trail", [&](std::string& value) {
		skin->trailMatID = value;
	});

	handler("TrailCol", [&](std::string& value) {
		std::vector<std::string> cols;
		split(value, cols, ',', true);

		if(cols.size() == 2) {
			skin->trailStart = toColor(cols[0]);
			skin->trailEnd = toColor(cols[1]);
		}
		else {
			error("Trail requires two colors");
		}
	});

	handler("Color", [&](std::string& value) {
		skin->color = toColor(value);
	});

	handler("ImpactGfx", [&](std::string& value) {
		skin->def_impact = value;
	});

	handler("Material", [&](std::string& value) {
		skin->def_material = value;
	});

	handler("ImpactSfx", [&](std::string& value) {
		skin->def_impact_sound = value;
	});

	handler("FireSfx", [&](std::string& value) {
		skin->fire_sound_names.push_back(value);
	});

	handler("FirePitchVariance", [&](std::string& value) {
		skin->fire_pitch_variance = toNumber<float>(value);
	});

	handler.lineHandler([&](std::string& line) {
		auto pos = line.find("=");
		if(pos == line.npos)
			return;

		std::vector<std::string> args;
		split(line, args, '=', true);

		if(args.size() != 2)
			return;

		if(eff->effect) {
			auto it = eff->effect->valueNames.find(args[0]);
			if(it == eff->effect->valueNames.end()) {
				error(handler.position());
				error("  Unknown effect value '%s'.\n", args[0].c_str());
				return;
			}

			eff->effectValues[it->second] = Formula::fromInfix(args[1].c_str());
		}
	});

	handler.read(filename);
}

unsigned getEffectorDefinitionCount() {
	return (unsigned)effIds.size();
}

const EffectorDef* getEffectorDefinition(const std::string& name) {
	auto it = effDefs.find(name);
	if(it == effDefs.end())
		return 0;
	return it->second;
}

const EffectorDef* getEffectorDefinition(unsigned index) {
	if(index >= (unsigned)effIds.size())
		return 0;
	return effIds[index];
}

Threaded(std::vector<TargetWeighter>*) weightList = 0;

static int targetFormulaVar(const std::string* wt) {
	if(!weightList)
		return -1;

	weightList->push_back(TargetWeighter());
	TargetWeighter& w = weightList->back();

	//Find type weighter
	for(unsigned i = 0, cnt = getScriptObjectTypeCount(); i < cnt; ++i) {
		ScriptObjectType* tp = getScriptObjectType(i);
		std::string name = "is";
		name += tp->name;

		if(*wt == name) {
			w.isNative = true;
			w.arg = tp;
			w.native = isType;
			return (int)weightList->size() - 1;
		}
	}

	//Find tag weighters
	if(wt->size() > 3 && wt->compare(0, 3, "tag") == 0) {
		std::string tag = wt->substr(3);
		int index = getSysTagIndex(tag, false);
		if(index != -1) {
			w.isNative = true;
			w.arg = (void*)(size_t)index;
			w.native = hasTag;
			return (int)weightList->size() - 1;
		}
		else {
			error("Could not find tag %s in formula", tag.c_str());
		}
	}

	//Find native weighter
	auto f = TargetWeighters.find(*wt);
	if(f != TargetWeighters.end()) {
		w.isNative = true;
		w.native = f->second;
	}

	//Find script weighter
	else {
		w.isNative = false;
		w.script = devices.scripts.server->getFunction(
			*wt, "(const Effector&, const Object&, const Object&)", "double");
	}
	return (int)weightList->size() - 1;
}

static double targetFormulaName(void* user, const std::string* name) {
	return 0.0;
}

struct TargetFormulaData {
	const Effector* eff;
	const std::vector<TargetWeighter>* wl;
	Object* obj;
	Object* target;
};

static double targetFormulaWeight(void* user, int index) {
	TargetFormulaData* dat = (TargetFormulaData*)user;
	if(index < 0 || index >= (int)dat->wl->size())
		return 0.0;

	const TargetWeighter* w = &(*dat->wl)[index];
	if(w->isNative) {
		double weight = w->native(dat->eff, dat->obj, dat->target, w->arg);
		return weight;
	}
	else if(w->script) {
		double weight = 0.0;
		scripts::Call cl = devices.scripts.server->call(w->script);
		cl.push(dat->eff);
		cl.push(dat->obj);
		cl.push(dat->target);
		cl.call(weight);
		return weight;
	}
	return 0.0;
}

void bindEffectorHooks(bool shadow) {
	foreach(it, effDefs) {
		EffectorDef& def = *it->second;

		if(!shadow && !def.def_algorithm.empty()) {
			auto f = TargetAlgorithms.find(def.def_algorithm);
			if(f != TargetAlgorithms.end()) {
				def.algorithm.isNative = true;
				def.algorithm.native = f->second;
			}
			else {
				def.algorithm.isNative = false;
				def.algorithm.script = devices.scripts.server->getFunction(
					def.def_algorithm, "(const Effector&, const Object&)", "Object@");
			}
		}

		if(!def.def_activation.empty()) {
			std::string func;
			std::vector<std::string> arguments;

			funcSplit(def.def_activation, func, arguments);

			auto f = EffectorActivation.find(func);
			if(f != EffectorActivation.end()) {
				def.activation.isNative = true;
				def.activation.native = f->second.func;
				def.stateCount = f->second.stateCount;

				if(arguments.size() != f->second.argCount) {
					def.activation.native = 0;
					error("Incorrect argument count for '%s' (got %i, expected %u)", func.c_str(), arguments.size(), f->second.argCount);
				}
			}
			else if(!shadow) {
				std::string decl;
				decl += "(const Effector&, const Object&, const Object&, double";
				for(unsigned i = 0; i < arguments.size(); ++i)
					decl += ", double";
				for(unsigned i = 0; i < def.stateCount; ++i)
					decl += ", double&";
				decl += ")";

				def.activation.isNative = false;
				def.activation.script = devices.scripts.server->getFunction(
					func, decl.c_str(), "bool");
			}

			def.arguments.clear();
			foreach(a, arguments)
				def.arguments.push_back(Formula::fromInfix(a->c_str()));
		}

		if(!def.def_onTrigger.empty()) {
			std::string func;
			std::vector<std::string> arguments;

			funcSplit(def.def_onTrigger, func, arguments);

			if(!shadow) {
				std::string decl;
				decl += "(const Effector&, Object&, Object&, float&";
				for(unsigned i = 0; i < arguments.size(); ++i)
					decl += ", double";
				decl += ")";

				def.onTrigger = devices.scripts.server->getFunction(
					func, decl.c_str(), "bool");
			}

			def.triggerArguments.clear();
			foreach(a, arguments)
				def.triggerArguments.push_back(Formula::fromInfix(a->c_str()));
		}

		weightList = &def.canTargetWeighters;
		if(!def.def_canTarget.empty())
			def.canTarget = Formula::fromInfix(def.def_canTarget.c_str(), &targetFormulaVar);

		weightList = &def.autoTargetWeighters;
		if(!def.def_autoTarget.empty())
			def.autoTarget = Formula::fromInfix(def.def_autoTarget.c_str(), &targetFormulaVar);
	}
}

void bindEffectorResources() {
	foreach(it, effDefs) {
		EffectorDef& def = *it->second;
		for(unsigned i = 0, cnt = def.skins.size(); i < cnt; ++i) {
			auto& skin = def.skins[i];
			if(!skin.def_material.empty())
				skin.material = &devices.library.getMaterial(skin.def_material);
			if(!skin.trailMatID.empty())
				skin.trailMat = &devices.library.getMaterial(skin.trailMatID);
			if(!skin.def_impact.empty())
				skin.impact = devices.library.getParticleSystem(skin.def_impact);
			foreach(snd, skin.fire_sound_names)
				skin.fire_sounds.push_back(devices.library.getSound(*snd));
			if(!skin.def_impact_sound.empty())
				skin.impact_sound = devices.library.getSound(skin.def_impact_sound);
		}
	}
}

EffectorSkin::EffectorSkin()
	: graphicType(EGT_Line), graphicSize(1.0), length(1.0), material(0), impact(0), impact_sound(0), fire_pitch_variance(0.f),
	trailMat(0), trailStart((unsigned)0xffff0000), trailEnd((unsigned)0)
{
}

EffectorDef::EffectorDef()
	: range(0), lifetime(0), tracking(0), speed(0), spread(0), capTarget(0), fireArc(0), targetTolerance(0), fireTolerance(0),
		valueCount(0), stateCount(0), physicalType(EPT_Instant), physicalSize(1.0), efficiencyMode(EEM_Normal),
		onTrigger(0), canTarget(0), autoTarget(0), physicalImpact(true), passthroughInvalid(false), skins(1), pierces(false), recoverTime(1.f), effect(0)
{
	skinNames["Default"] = 0;
}

Effector::Effector(const EffectorDef& def) : inDesign(0), subsysIndex(0), effectorIndex(0), effectorId(0), skinIndex(0),
		type(def), effect(def.effect), range(1000.0), lifetime(6.0), tracking(0.5), speed(50.0), spread(0.0),
		capTarget(1), fireArc(twopi), fireTolerance(twopi), targetTolerance(0.0), relativeSize(1.0), enabled(true), refs(1) {
	values = new double[def.valueCount + def.arguments.size() + def.triggerArguments.size()];
}

double effVariable(void* effector, const std::string* name) {
	Effector* eff = (Effector*)effector;
	auto it = eff->type.valueNames.find(*name);
	if(it == eff->type.valueNames.end()) {
		error("Could not find variable %s in effector.\n", name->c_str());
		return 0.0;
	}
	return eff->values[it->second];
}

void Effector::initValues() {
	//Physical value calculations
	if(type.range)
		range = type.range->evaluate(effVariable, this);
	if(type.lifetime)
		lifetime = type.lifetime->evaluate(effVariable, this);
	if(type.tracking)
		tracking = type.tracking->evaluate(effVariable, this);
	if(type.capTarget)
		capTarget = (unsigned)type.capTarget->evaluate(effVariable, this);
	if(type.fireArc)
		fireArc = type.fireArc->evaluate(effVariable, this);
	if(type.fireTolerance)
		fireTolerance = type.fireTolerance->evaluate(effVariable, this);
	if(type.targetTolerance)
		targetTolerance = type.targetTolerance->evaluate(effVariable, this);
	if(type.speed)
		speed = type.speed->evaluate(effVariable, this);
	if(type.spread)
		spread = type.spread->evaluate(effVariable, this);

	//Arguments
	for(unsigned i = 0; i < type.arguments.size(); ++i)
		values[type.valueCount + i] = type.arguments[i]->evaluate(effVariable, this);
	for(unsigned i = 0; i < type.triggerArguments.size(); ++i)
		values[type.valueCount + type.arguments.size() + i] = type.triggerArguments[i]->evaluate(effVariable, this);

	//Effect values
	for(unsigned i = 0; i < type.effectValues.size(); ++i) {
		if(type.effectValues[i])
			effect.values[i] = type.effectValues[i]->evaluate(effVariable, this);
		else
			effect.values[i] = type.effect->values[i].defaultValue->evaluate(effVariable, this);
	}
}

double Effector::getTargetWeight(Object* obj, Object* target) const {
	TargetFormulaData dat;
	dat.eff = this;
	dat.wl = &type.canTargetWeighters;
	dat.obj = obj;
	dat.target = target;

	if(obj->owner != nullptr) {
		if(!target->isVisibleTo(obj->owner))
			return 0.0;
	}
	if(type.canTarget) {
		double c = type.canTarget->evaluate(&targetFormulaName, &dat, &targetFormulaWeight);
		if(c <= 0.0)
			return 0.0;
	}
	if(!type.autoTarget)
		return 0.0;
	dat.wl = &type.autoTargetWeighters;
	return type.autoTarget->evaluate(&targetFormulaName, &dat, &targetFormulaWeight);
}

bool Effector::isInRange(Object* obj, Object* target, bool considerArc) const {
	vec3d pos = obj->position, targPos = target->position;
	double distSQ = pos.distanceToSQ(targPos);

	if(distSQ > range * range)
		return false;

	if(considerArc) {
		double tolerance = fireArc + targetTolerance;
		if(tolerance < twopi) {
			vec3d dir = (targPos - pos) / sqrt(distSQ);
			dir = obj->rotation.inverted() * dir;

			double angDiff = dir.angleDistance(turretAngle);
			if(angDiff > tolerance)
				return false;
		}
	}
	return true;
}

bool Effector::canTarget(Object* obj, Object* target) const {
	if(!type.canTarget)
		return true;
	TargetFormulaData dat;
	dat.eff = this;
	dat.wl = &type.canTargetWeighters;
	dat.obj = obj;
	dat.target = target;
	if(obj->owner != nullptr) {
		if(!target->isVisibleTo(obj->owner))
			return false;
	}
	double w = type.canTarget->evaluate(&targetFormulaName, &dat, &targetFormulaWeight);
	return w > 0.0;
}

bool Effector::autoTarget(Object* obj, Object* target) const {
	if(!type.autoTarget)
		return true;
	TargetFormulaData dat;
	dat.eff = this;
	dat.wl = &type.autoTargetWeighters;
	dat.obj = obj;
	dat.target = target;

	double w = type.autoTarget->evaluate(&targetFormulaName, &dat, &targetFormulaWeight);
	return w > 0.0;
}

scene::ProjectileBatch* batch[4] = {0,0,0,0};
scene::MissileBatch* mBatch[4] = {0,0,0,0};
unsigned nextBatch = 0, nextMissileBatch = 0;

void clearProjectileBatches() {
	for(unsigned i = 0; i < 4; ++i) {
		if(batch[i]) {
			batch[i]->drop();
			batch[i] = 0;
		}
		if(mBatch[i]) {
			mBatch[i]->drop();
			mBatch[i] = 0;
		}
	}
}

struct BatchedProjectile : public scene::NodeEvent {
	const render::RenderState& mat;
	scene::ProjectileBatch::ProjEffect proj;

	BatchedProjectile(const render::RenderState& Mat) : NodeEvent(0), mat(Mat) {}

	void process() override {
		if(!batch[0]) {
			for(unsigned i = 0; i < 4; ++i) {
				batch[i] = new scene::ProjectileBatch();
				batch[i]->queueReparent(devices.scene);
				mBatch[i] = new scene::MissileBatch();
				mBatch[i]->queueReparent(devices.scene);
			}
		}

		batch[++nextBatch % 4]->registerProj(mat, proj);
	}
};

struct BatchedMissile : public scene::NodeEvent {
	const render::RenderState& mat, &trail;
	scene::MissileBatch::MissileTrail missile;

	BatchedMissile(const render::RenderState& Mat, const render::RenderState& Trail) : NodeEvent(0), mat(Mat), trail(Trail) {}

	void process() override {
		if(!batch[0]) {
			for(unsigned i = 0; i < 4; ++i) {
				batch[i] = new scene::ProjectileBatch();
				batch[i]->queueReparent(devices.scene);
				mBatch[i] = new scene::MissileBatch();
				mBatch[i]->queueReparent(devices.scene);
			}
		}

		mBatch[++nextBatch % 4]->registerProj(mat, trail, missile);
	}
};

//Pick a random vector in a cone <angle> wide centered around <from>
vec3d coneSpread(const vec3d& from, double angle) {
	vec3d perpRight = from.cross(vec3d::up());
	vec3d perpUp = from.cross(perpRight);

	double perpAngle = randomd() * twopi;
	vec3d perp = (perpRight * cos(perpAngle) + perpUp * sin(perpAngle)).normalized();

	//Slerp to the perpendicular vector based on the actual chosen spread angle
	angle = randomd() * angle;
	if(angle < pi * 0.5)
		return from.slerp(perp, angle / (pi * 0.5));
	else
		return perp.slerp(-from, (angle - pi*0.5) / (pi * 0.5));
}

void EffectorDef::triggerGraphics(Object* obj, EffectorTarget& targ, const Effector* effector, double* pTime, vec2d* pDirection, float efficiency, double tOffset) const {
	double time = 0.0;
	auto* player = Empire::getPlayerEmpire();
	auto& skin = skins[effector->skinIndex];
	Object*& target = targ.target;

	bool eventVisible = player && (obj->isVisibleTo(player) || target->isVisibleTo(player));
	double size = 1.0;

	switch(physicalType) {
		case EPT_Instant:
		break;
		case EPT_AimedMissile:
		case EPT_Missile: {
			vec3d turretOffset = obj->rotation * (effector->relativePosition * obj->radius);
			if(turretOffset.zero())
				turretOffset = obj->rotation * vec3d::front(obj->radius);

			size = physicalSize * sqrt(effector->relativeSize * obj->radius);

			scene::Node* node = 0;
			BatchedMissile* batched = 0;
			if(eventVisible) {
				if(skin.trailMat)
					batched = new BatchedMissile(*skin.material, *skin.trailMat);
				else
					node = new scene::BillboardNode(skin.material, skin.graphicSize * size);
			}

			Projectile* proj = new Projectile(PT_Missile);
			proj->position = obj->position + turretOffset;
			vec3d trackPos = turretOffset;
			if(targ.flags & TF_TrackingProgress)
				trackPos = targ.tracking;
			if(physicalType == EPT_AimedMissile)
				proj->velocity = (target->position - proj->position).normalized(effector->speed);
			else if(effector->spread > 0)
				proj->velocity = coneSpread(trackPos.normalized(), effector->spread) * effector->speed;
			else
				proj->velocity = trackPos.normalized(effector->speed);
			proj->lastTick += tOffset;
			proj->source = obj; obj->grab();
			proj->target = target; target->grab();
			proj->effector = effector; effector->grab();
			proj->graphics = node;
			proj->lifetime = (float)effector->lifetime;
			proj->tracking = (float)effector->tracking;
			proj->scale = (float)size;
			proj->efficiency = efficiency;
			if(!physicalImpact)
				proj->mode = PM_OnlyHitsTarget;
			else if(passthroughInvalid)
				proj->mode = PM_PassthroughInvalid;
			if(batched) {
				proj->missileData = new threads::SharedData<MissileData>(2);
				auto& sharedData = **proj->missileData;
				sharedData.aliveUntil = -1.0;
				sharedData.lastUpdate = devices.driver->getGameTime();
				sharedData.pos = proj->position;
				sharedData.vel = vec3f(proj->velocity);
			}

			if(node) {
				if(skin.trailMat) {
					auto* trail = new scene::LineTrailNode(*skin.trailMat);
					trail->setParent(node);
					trail->startCol = skin.trailStart;
					trail->endCol = skin.trailEnd;
					double lineSize = obj->radius * effector->relativeSize;
					trail->lineLen_s *= (4.0 + lineSize) / (12.0 + lineSize);
				}

				node->position = obj->position;
				node->animator = new scene::ProjectileAnim(proj->velocity);

				node->setFlag(scene::NF_CustomColor, true);
				node->color = Colorf(skin.color);
			
				node->queueReparent(devices.scene);
			}
			else if(batched) {
				auto& data = batched->missile;
				data.start = skin.trailStart;
				data.end = skin.trailEnd;
				data.color = skin.color;
				data.pos = proj->position;
				data.size = (float)(skin.graphicSize * size);
				data.length = (float)(data.size * 40.0 / effector->speed) * skin.length;
				data.lastUpdate = devices.driver->getGameTime();
				data.track = proj->missileData;
				
				scene::queueNodeEvent(batched);
			}
			
			registerProjectile(proj);

			} break;
		case EPT_Projectile: {
			vec3d start = obj->position;
			start += obj->rotation * (effector->relativePosition * obj->radius);

			//Fire toward the predicted position of the target for maximum accuracy
			vec3d p = target->position - start;
			vec3d v = target->velocity - obj->velocity;
			const vec3d& a = target->acceleration;

			//s * t = sqrt(E((p + v*t + 1/2a*t^2)^2))
			//s^2 * t^2 = (p + vt + 1/2at2)(p + vt + 1/2at2)
			//s2t2 = p2 + 2pvt + pat2 + v2t2 + 1/4a2t4 + vat3

			double coeffs[5] = {
				p.dot(p),
				2.0 * p.dot(v),
				(v.dot(v) + p.dot(a) - effector->speed*effector->speed),
				v.dot(a),
				0.25*a.dot(a)
			};
			double roots[4];
			//TODO: If we solve for t > effector->lifetime, we know that we can't really hit the target
			//		Should we do something about that?
			double t = effector->lifetime;
			int rootCount = 0;
			
			//Very small coefficients on the upper values yield incorrect results, and are unnecessary to evaluate
			if(fabs(coeffs[4]) > 0.00001) {
				rootCount = FindQuarticRoots(coeffs, roots);
			}
			else if(fabs(coeffs[3]) > 0.00001) {
				rootCount = FindCubicRoots(coeffs, roots);
			}
			else {
				const double& a = coeffs[2], &b = coeffs[1], &c = coeffs[0];
				double det = b*b - 4.0*a*c;
				if(det > 0) {
					double sqrtDet = sqrt(det);
					roots[0] = (-b + sqrtDet) / (2.0 * a);
					roots[1] = (-b - sqrtDet) / (2.0 * a);
					rootCount = 2;
				}
				else if(det == 0) {
					roots[0] = -b / (2.0 * a);
					rootCount = 1;
				}
				else {
					rootCount = 0;
				}
			}

			for(int i = 0; i < rootCount; ++i)
				if(roots[i] < t && roots[i] > 0)
					t = roots[i];

			vec3d offset = p + (v*t) + (a * (0.5 * t * t));

			//Create final velocity with a cone spread
			vec3d velocity = coneSpread(offset.normalize(), effector->spread) * effector->speed;

			//Add the prediction to the tracking. This is a hack so we don't have to do
			//prediction in our tracking step, the error should be small.
			quaterniond rotate = quaterniond::fromImpliedTransform(p, velocity);
			velocity = rotate * (obj->rotation * targ.tracking.normalized(effector->speed));
			velocity += obj->velocity;

			scene::Node* node = 0;
			BatchedProjectile* batched = 0;

			size = physicalSize * sqrt(effector->relativeSize * obj->radius);

			if(eventVisible) {
				if(skin.graphicType != EGT_Sprite) {
					bool isLine = (skin.graphicType == EGT_Line);
					batched = new BatchedProjectile(isLine ? *skin.trailMat : *skin.material);
					auto& proj = batched->proj;
					proj.start = skin.trailStart;
					proj.end = skin.trailEnd;
					proj.pos = start + velocity * -tOffset;
					proj.dir = vec3f(velocity.normalized());
					proj.speed = (float)effector->speed;
					proj.length = (float)(effector->speed / 60.0) * skin.graphicSize * size * skin.length;
					proj.life = (float)effector->lifetime;
					proj.fadeStart = (float)(effector->lifetime - std::min(effector->lifetime * 0.8, t));
					proj.kill = new threads::SharedData<bool>(2);
					proj.line = isLine;
				}
				else {
					node = new scene::BillboardNode(skin.material, skin.graphicSize * size);
					node->position = start + velocity * -tOffset;
					node->color = skin.color;
				}
			}

			Projectile* proj = new Projectile(PT_Bullet);

			proj->position = start;
			proj->lastTick += tOffset;
			proj->velocity = velocity;
			proj->source = obj; obj->grab();
			proj->effector = effector; effector->grab();
			proj->graphics = node;
			if(batched)
				proj->endNotice = batched->proj.kill;
			proj->lifetime = (float)effector->lifetime;
			proj->scale = (float)size;
			proj->efficiency = efficiency;
			if(!physicalImpact)
				proj->mode = PM_OnlyHitsTarget;
			else if(passthroughInvalid)
				proj->mode = PM_PassthroughInvalid;
			if(!physicalImpact) {
				proj->target = target;
				target->grab();
			}

			if(pDirection) {
				vec3d localOffset = (obj->rotation * offset);
				*pDirection = vec2d(-localOffset.x, localOffset.z);
			}

			if(node) {
				node->animator = new scene::ProjectileAnim(proj->velocity);
				node->queueReparent(devices.scene);
			}
			else if(batched) {
				scene::queueNodeEvent(batched);
			}

			registerProjectile(proj);
		} break;
		case EPT_Beam: {
			vec3d start = obj->rotation * (effector->relativePosition * obj->radius);
			vec3d pos = start + obj->position;
			vec3d end = (target->position - pos).normalize(effector->range) + pos;

			size = effector->relativeSize * obj->radius;
			size = physicalSize * std::min(sqrt(size), size);
			
			scene::Node* node = 0;
			if(eventVisible) {
				node = new scene::BeamNode(skin.material, (float)(skin.graphicSize * size), start, vec3d());
				node->color = Colorf(skin.trailStart);
				if(size < 3.0)
					node->color.a *= std::max(size / 3.0, 0.1);
			}
			
			Projectile* proj = new Projectile(PT_Beam);
			proj->position = start;
			proj->lastTick += tOffset;
			proj->velocity = end - pos;
			if(effector->spread > 0)
				proj->velocity = coneSpread(proj->velocity.normalized(), effector->spread) * proj->velocity.getLength();
			proj->source = obj; obj->grab();
			if(effector->tracking > 0 || !physicalImpact) {
				proj->target = target; target->grab();
				proj->tracking = (float)effector->tracking;
			}
			proj->effector = effector; effector->grab();
			proj->graphics = node;
			proj->scale = (float)size;
			if(!physicalImpact)
				proj->mode = PM_OnlyHitsTarget;
			else if(passthroughInvalid)
				proj->mode = PM_PassthroughInvalid;

			if(effector->type.efficiencyMode == EEM_Duration) {
				proj->lifetime = (float)effector->lifetime * efficiency;
				proj->efficiency = 1.f;
			}
			else if(effector->type.efficiencyMode == EEM_Duration_Partial) {
				efficiency = sqrt(efficiency);
				proj->lifetime = (float)effector->lifetime * efficiency;
				proj->efficiency = efficiency;
			}
			else {
				proj->lifetime = (float)effector->lifetime;
				proj->efficiency = efficiency;
			}

			if(node) {
				proj->impact = &((scene::BeamNode*)node)->endPosition;

				node->visible = false;
				node->position = vec3d();
				node->animator = new scene::BeamAnim(obj->node, start, (float)effector->range);
				node->queueReparent(devices.scene);
			}
			
			registerProjectile(proj);
		} break;
	}

	if(pTime)
		*pTime = time;

	if(devices.network->isServer)
		devices.network->sendEffectorTrigger(this, effector, obj, targ, devices.driver->getGameTime() + tOffset);

	size *= skin.graphicSize;

	if(eventVisible && !skin.fire_sounds.empty()) {
		auto* fire_sound = skin.fire_sounds[randomi(0,(int)skin.fire_sounds.size()-1)];
		if(fire_sound && fire_sound->loaded && !audio::disableSFX) {
			auto* sound = devices.sound->play3D(fire_sound->source, snd_vec(obj->position), false, true);
			if(sound) {
				sound->setVolume((float)size);
				if(skin.fire_pitch_variance > 0)
					sound->setPitch((float)randomd(1.0 - skin.fire_pitch_variance,1.0 + skin.fire_pitch_variance));
				float dist = obj->position.distanceTo(devices.render->cam_pos);
				float lo = dist / (dist + size * 500.0);
				if(lo > 0.05)
					sound->setLowPass(lo);
				sound->resume();
			}
		}
	}
}

void Effector::trigger(Object* obj, EffectorTarget& target, float efficiency, double tOffset) const {
	if(type.onTrigger && !devices.network->isClient) {
		scripts::Call cl = devices.scripts.server->call(type.onTrigger);
		cl.push(this);
		cl.push(obj);
		cl.push(target.target);
		cl.push((void*)&efficiency);

		for(unsigned i = 0, cnt = (unsigned)type.triggerArguments.size(); i < cnt; ++i)
			cl.push(values[type.valueCount + type.arguments.size() + i]);

		bool continueTrigger = false;
		cl.call(continueTrigger);

		if(!continueTrigger)
			return;
	}

	double time = 0.0;
	vec2d direction;

	type.triggerGraphics(obj, target, this, &time, &direction, efficiency, tOffset);
}

void Effector::triggerEffect(Object* obj, Object* target, const vec3d& impactOffset, float efficiency, float partiality, double delay) const {
	if(target->isValid()) {
		TimedEffect eff(effect, delay);
		eff.event.obj = obj;
		eff.event.target = target;
		eff.event.impact = impactOffset;

		//vec3d localOffset = (target->rotation.inverted() * (target->position - obj->position));
		vec3d localOffset = target->rotation.inverted() * impactOffset;
		eff.event.direction = vec2d(localOffset.x, -localOffset.z);
		eff.event.efficiency = efficiency;
		eff.event.partiality = partiality;

		target->addTimedEffect(eff);
	}
}

bool trackTo(Object* obj, const Effector& eff, double time, EffectorTarget& targ, vec3d& absTargDir, bool isAbs) {
	vec3d targDir = absTargDir;
	vec3d curDir = targ.tracking.normalized();

	//Put the target direction into object rotated space so we can do proper relative tracking
	if(isAbs)
		targDir = obj->rotation.inverted() * targDir;

	//Check whether we should fire at this angle difference
	double track = eff.tracking * time;
	double angDiff = targDir.angleDistance(curDir);

	if(angDiff - track <= eff.fireTolerance)
		targ.flags |= TF_WithinFireTolerance;
	else
		targ.flags &= ~TF_WithinFireTolerance;

	//Only track up to our firing arc
	angDiff = targDir.angleDistance(eff.turretAngle);
	if(angDiff > eff.fireArc) {
		//Clamp target angle to fire arc
		targDir = eff.turretAngle.slerp(targDir, eff.fireArc/angDiff);
	}

	//Check whether we should do instant tracking
	if(targ.flags & TF_ClearTracking || eff.tracking < 0) {
		targ.tracking = targDir;
		targ.flags &= ~(TF_ClearTracking | TF_TrackingProgress);
		return true;
	}

	//Do tracking to calculated target
	angDiff = targDir.angleDistance(curDir);

	//Do actual tracking
	if(angDiff <= track) {
		targ.tracking = targDir;
		targ.flags &= ~TF_TrackingProgress;
		return true;
	}
	else {
		targ.tracking = curDir.slerp(targDir,track/angDiff);
		targ.flags |= TF_TrackingProgress;
		return false;
	}
}

void Effector::update(Object* obj, double time, double* states, EffectorTarget& targ, float efficiency, bool holdFire) const {
	if(type.efficiencyMode == EEM_Reload) {
		time *= efficiency;
		efficiency = 1.f;
	}
	else if(type.efficiencyMode == EEM_Reload_Partial) {
		efficiency = sqrt(efficiency);
		time *= efficiency;
	}

	Object*& target = targ.target;
	if(target && (!target->isValid() || !target->owner || !target->owner->valid())) {
		//TODO: Force orders for neutral targeting? Not relevant now.
		target->drop();
		target = 0;
	}

	//Check if the previous target is still available
	if(target) {
		if(!isInRange(obj, target) || !canTarget(obj, target)) {
			target->drop();
			target = 0;
		}
	}

	//Search for new targets if we have no target or were forced to retarget
	if(!target || (targ.flags & TF_Retarget)) {
		//Search for targets
		Object* newTarget = 0;
		if(type.algorithm.isNative) {
			newTarget = type.algorithm.native(this, obj, &targ);
		}
		else {
			scripts::Call cl = devices.scripts.server->call(type.algorithm.script);
			cl.push(this);
			cl.push(obj);
			cl.call(newTarget);
		}

		if(newTarget && newTarget != target) {
			//Retarget to the new target
			Object* prevTarget = target;
			newTarget->grab();
			target = newTarget;
			if(prevTarget)
				prevTarget->drop();

			//Remove retargeting flag if it was there
			targ.flags &= ~TF_Retarget;

			//Reset hit counter
			targ.hits = 0;

			if(!type.algorithm.isNative)
				newTarget->drop();
		}
	}

	//Do tracking
	if(target) {
		if(type.physicalType == EPT_Projectile) {
			vec3d start = obj->position;
			start += obj->rotation * (relativePosition * obj->radius);

			vec3d targDir = (target->position - start).normalized();
			trackTo(obj, *this, time ,targ, targDir, true);
		}
		else {
			targ.flags |= TF_WithinFireTolerance;
		}
	}
	else if(tracking > 0) {
		if(type.physicalType == EPT_Projectile) {
			if(!(targ.flags & TF_ClearTracking)) {
				//Retract turret into neutral position for quick targeting,
				//so finding new stuff after no combat doesn't shoot
				//in odd directions.
				vec3d targDir = turretAngle;
				if(trackTo(obj, *this, time, targ, targDir, false))
					targ.flags |= TF_ClearTracking;
			}
		}
	}

	//Run activation procedure
	EffectorActivationType activate;
	do {
		activate = EAT_Inactive;
		double took = time;
		if(type.activation.isNative) {
			if(type.activation.native)
				activate = type.activation.native(this, obj, targ, took, values + type.valueCount, states);
		}
		else {
			scripts::Call cl = devices.scripts.server->call(type.activation.script);
			cl.push(this);
			cl.push(obj);
			cl.push(target);
			cl.push(took);
			for(unsigned i = 0, cnt = (unsigned)type.arguments.size(); i < cnt; ++i)
				cl.push(values[type.valueCount + i]);
			for(unsigned i = 0, cnt = type.stateCount; i < cnt; ++i)
				cl.push(&states[i]);
			bool doActivate;
			cl.call(doActivate);
			activate = doActivate ? EAT_Activate : EAT_Inactive;
		}

		//Do activation
		if(target && !holdFire) {
			if(activate) {
				trigger(obj, targ, efficiency, took - time);

				//Only count hits firing when we're done tracking
				if(!(targ.flags & TF_TrackingProgress)) {
					targ.hits += 1;
					if(targ.hits >= capTarget && capTarget > 0)
						targ.flags |= TF_Retarget;
				}
			}
			targ.flags |= TF_Firing;
		}
		else {
			targ.flags &= ~TF_Firing;
		}

		time -= took;
	} while(activate == EAT_Repeat);
}

void Effector::setRelativePosition(vec2u hex, const HullDef* hull, vec3d direction) {
	//Set the relative source position from a hex position
	vec2d center = vec2d((double)hull->gridSize.x * 0.75, (double)hull->gridSize.y) / 2.0;
	vec2d effPos = hull->active.getEffectivePosition(hex);

	vec2d diff = effPos - center;
	relativePosition.x = diff.x / (double(hull->gridSize.x) * 0.75 * 0.5);
	relativePosition.y = 0;
	relativePosition.z = diff.y / (double(hull->gridSize.y) * 0.5);

	relativePosition = hull->getClosestImpact(relativePosition);

	turretAngle = direction.normalized();
}

Effector::~Effector() {
	if(effectorId != 0 && devices.network->isServer)
		devices.network->sendEffectorDestruction(this);
	delete[] values;
}

void Effector::grab() const {
	if(effectorId != 0)
		++refs;
}

void Effector::drop() const {
	if(effectorId != 0)
		if(--refs == 0)
			delete this;
}

void Effector::load(SaveFile& file) {
	file >> range >> stateOffset;
	file >> lifetime >> tracking;
	file >> speed >> capTarget;
	file >> relativePosition >> turretAngle;
	file >> fireArc >> fireTolerance;
	file >> targetTolerance >> spread;
	file >> relativeSize >> enabled;
	file.read(values, sizeof(double) * (type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size()));
	if(effect.type)
		file.read(effect.values, sizeof(double) * effect.type->valueCount);

	unsigned skin = 0;
	if(file >= SFV_0006)
		file >> skin;
	if(skin < type.skins.size())
		skinIndex = skin;
}

void Effector::save(SaveFile& file) const {
	file << range << stateOffset;
	file << lifetime << tracking;
	file << speed << capTarget;
	file << relativePosition << turretAngle;
	file << fireArc << fireTolerance;
	file << targetTolerance << spread;
	file << relativeSize << enabled;
	file.write(values, sizeof(double) * (type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size()));
	if(effect.type)
		file.write(effect.values, sizeof(double) * effect.type->valueCount);

	file << skinIndex;
}

const Effector* Effector::receiveUpdate(net::Message& msg) {
	if(msg.readBit()) {
		unsigned typeIndex = msg.readSmall();
		unsigned id = msg.readSmall();

		Effector* eff = const_cast<Effector*>(getEffector(id));

		if(!eff) {
			auto* def = getEffectorDefinition(typeIndex);
			if(!def)
				return nullptr;
			eff = new Effector(*def);
			eff->effectorId = id;

			registerEffector(eff);
			eff->grab();
		}

		eff->stateOffset = msg.readSmall();
		eff->capTarget = msg.readSmall();
	
		eff->range = msg.readIn<float>();
		eff->lifetime = msg.readIn<float>();
		eff->tracking = msg.readIn<float>();
		eff->speed = msg.readIn<float>();

		msg.readSmallVec3(eff->relativePosition.x, eff->relativePosition.y, eff->relativePosition.z);
		msg.readDirection(eff->turretAngle.x, eff->turretAngle.y, eff->turretAngle.z);
	
		eff->fireArc = msg.readIn<float>();
		eff->fireTolerance = msg.readIn<float>();
		eff->targetTolerance = msg.readIn<float>();
		eff->spread = msg.readIn<float>();
		eff->relativeSize = msg.readIn<float>();

		{
			unsigned valueCount = eff->type.valueCount + (unsigned)eff->type.arguments.size() + (unsigned)eff->type.triggerArguments.size();
			unsigned effValueCount = eff->effect.type->valueCount;
			float* floatValues = (float*)alloca(sizeof(float) * (valueCount + effValueCount));
			msg.read(floatValues, sizeof(float) * (valueCount + effValueCount));
			
			for(unsigned i = 0; i < valueCount; ++i)
				eff->values[i] = floatValues[i];
			for(unsigned i = 0; i < effValueCount; ++i)
				eff->effect.values[i] = floatValues[i + valueCount];
		}

		return eff;
	}
	else {
		unsigned id;
		msg >> id;
		Effector* eff = const_cast<Effector*>(getEffector(id));
		if(eff) {
			eff->drop();
			eff->drop();
		}
		return nullptr;
	}
}

void Effector::sendUpdate(net::Message& msg) const {
	msg.write1();

	msg.writeSmall(type.index);
	msg.writeSmall(effectorId);
	msg.writeSmall(stateOffset);
	msg.writeSmall(capTarget);
	msg << (float)range << (float)lifetime;
	msg << (float)tracking << (float)speed;
	msg.writeSmallVec3(relativePosition.x, relativePosition.y, relativePosition.z);
	msg.writeDirection(turretAngle.x, turretAngle.y, turretAngle.z);
	msg << (float)fireArc << (float)fireTolerance;
	msg << (float)targetTolerance << (float)spread;
	msg << (float)relativeSize;
	{
		unsigned valueCount = type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size();
		unsigned effValueCount = effect.type->valueCount;
		float* floatValues = (float*)alloca(sizeof(float) * (valueCount + effValueCount));
		for(unsigned i = 0; i < valueCount; ++i)
			floatValues[i] = (float)values[i];
		for(unsigned i = 0; i < effValueCount; ++i)
			floatValues[i + valueCount] = (float)effect.values[i];

		msg.write(floatValues, sizeof(float) * (valueCount + effValueCount));
	}
}

void Effector::sendDestruction(net::Message& msg) const {
	msg.write0();
	msg << effectorId;
}

void Effector::writeData(net::Message& msg) const {
	msg.writeSmall(type.index);
	msg.writeSmall(effectorId);
	msg.writeSmall(stateOffset);
	msg.writeSmall(capTarget);
	msg.writeSmall(skinIndex);
	msg << (float)range << (float)lifetime;
	msg << (float)tracking << (float)speed;
	msg.writeSmallVec3(relativePosition.x, relativePosition.y, relativePosition.z);
	msg.writeDirection(turretAngle.x, turretAngle.y, turretAngle.z);
	msg << (float)fireArc << (float)fireTolerance;
	msg << (float)targetTolerance << (float)spread;
	msg << (float)relativeSize << enabled;
	{
		unsigned valueCount = type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size();
		float* floatValues = (float*)alloca(sizeof(float) * valueCount);
		for(unsigned i = 0; i < valueCount; ++i)
			floatValues[i] = (float)values[i];

		msg.write(floatValues, sizeof(float) * valueCount);
	}
	effect.writeData(msg);
}

Effector::Effector(net::Message& msg) : inDesign(0), subsysIndex(0), effectorIndex(0), effectorId(0),
		type(*getEffectorDefinition(msg.readSmall())), effect(), range(1000.0), lifetime(6.0), tracking(0.5), speed(50.0), spread(0.03),
		capTarget(1), fireArc(twopi), fireTolerance(twopi), targetTolerance(0.0), relativeSize(1.0), enabled(true), refs(1)
{
	values = new double[type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size()];
	effectorId = msg.readSmall();
	stateOffset = msg.readSmall();
	capTarget = msg.readSmall();
	skinIndex = msg.readSmall();
	if(skinIndex >= type.skins.size())
		skinIndex = 0;
	
	range = msg.readIn<float>();
	lifetime = msg.readIn<float>();
	tracking = msg.readIn<float>();
	speed = msg.readIn<float>();

	msg.readSmallVec3(relativePosition.x, relativePosition.y, relativePosition.z);
	msg.readDirection(turretAngle.x, turretAngle.y, turretAngle.z);
	
	fireArc = msg.readIn<float>();
	fireTolerance = msg.readIn<float>();
	targetTolerance = msg.readIn<float>();
	spread = msg.readIn<float>();
	relativeSize = msg.readIn<float>();

	msg >>  enabled;

	{
		unsigned valueCount = type.valueCount + (unsigned)type.arguments.size() + (unsigned)type.triggerArguments.size();
		float* floatValues = (float*)alloca(sizeof(float) * valueCount);
		msg.read(floatValues, sizeof(float) * valueCount);

		for(unsigned i = 0; i < valueCount; ++i)
			values[i] = floatValues[i];
	}

	effect = Effect(type.effect);
	effect.readData(msg);
}

void saveEffectors(SaveFile& file) {
	file << (unsigned)effectorMap.size();
	foreach(it, effectorMap) {
		auto& eff = *it->second;
		file.writeIdentifier(SI_Effector, eff.type.index);
		file << eff.effectorId;
		eff.save(file);
	}
}

void loadEffectors(SaveFile& file) {
	unsigned cnt = file;
	for(unsigned i = 0; i < cnt; ++i) {
		unsigned typeIndex = file.readIdentifier(SI_Effector);
		auto* type = getEffectorDefinition(typeIndex);
		Effector* eff = new Effector(*type);
		eff->effectorId = file;
		eff->load(file);

		eff->grab();
		effectorMap[eff->effectorId] = eff;
		loadedEffectors.push_back(eff);
		if(nextEffId <= eff->effectorId)
			nextEffId = eff->effectorId+1;
	}
}

void postLoadEffectors() {
	foreach(it, loadedEffectors)
		(*it)->drop();
	loadedEffectors.clear();
}
