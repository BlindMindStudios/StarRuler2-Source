#include "effector_functions.h"
#include "obj/object.h"
#include "util/random.h"
#include "threads.h"
#include "empire.h"
#include "obj/blueprint.h"
#include "assert.h"
#include "main/logging.h"

#ifndef TARGET_SINGLE_TARGET_DEPTH
#define TARGET_SINGLE_TARGET_DEPTH 3
#endif

//* Algorithms
struct SingleTargetFinder {
	const Effector* eff;
	EffectorTarget* efftarg;
	Object* obj;
	Object* best;
	double maxWeight;

	bool result(Object* targ) {
		//Ignore ourselves
		if(targ == obj)
			return false;

		//Ignore objects out of range
		if(!eff->isInRange(obj, targ))
			return false;

		double weight = eff->getTargetWeight(obj, targ);

		//Weights under zero mean to ignore this object
		if(weight <= 0.0)
			return false;

		//Modify weight with targeting preference
		if(efftarg->target) {
			if(efftarg->flags & TF_Group) {
				if(efftarg->target->group != targ->group)
					weight /= 10.0;
			} else if(efftarg->flags & TF_Preference) {
				if(efftarg->target != targ)
					weight /= 10.0;
			}
		}

		//Weights of at least one mean to immediately target this
		if(weight >= 1.0) {
			best = targ;
			return true;
		}

		//Store the object with the highest weight, so
		//we have something to target if nothing is
		//randomed.
		if(weight > maxWeight) {
			best = targ;
			maxWeight = weight;
		}

		return false;
	}
};

static Object* SingleTarget(const Effector* eff, Object* obj, EffectorTarget* efftarg) {
	SingleTargetFinder finder;
	finder.efftarg = efftarg;
	finder.eff = eff;
	finder.obj = obj;
	finder.best = 0;
	finder.maxWeight = 0;

	obj->findTargets(finder, TARGET_SINGLE_TARGET_DEPTH, Object::RANDOMIZE_TARGETS);
	return finder.best;
}

//* Weighters
static double NotOurs(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj->owner == targ->owner)
		return 0.0;
	return 1.0;
}

static double Ours(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj->owner != targ->owner)
		return 0.0;
	return 1.0;
}

static double isEnemy(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(targ->owner && obj->owner != targ->owner && targ->owner->valid()) {
		if(obj->owner && (obj->owner->hostileMask & targ->owner->mask) != 0)
			return 1.0;
		else
			return 0.0;
	}
	else
		return 0.0;
}

static double isDamageable(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(targ->getFlag(objNoDamage))
		return 0.0;
	else
		return 1.0;
}

static double isAttackable(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj->owner == targ->owner || targ->owner == nullptr || !targ->owner->valid())
		return 1.0;
	return isEnemy(eff, obj, targ, arg);
}

static double hasDamagedBlueprint(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj != nullptr && obj->type->blueprintOffset != 0) {
		auto* blueprint = (Blueprint*)(((size_t)obj) + obj->type->blueprintOffset);
		return blueprint->currentHP < blueprint->design->totalHP - 0.0001 ? 1.0 : 0.0;
	}
	return 0.0;
}

double isType(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if((void*)targ->type != arg)
		return 0.0;
	return 1.0;
}

static double Distance(const Effector* eff, Object* obj, Object* targ, void* arg) {
	return obj->position.distanceTo(targ->position);
}

double hasTag(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(targ != nullptr && targ->isValid() && targ->type->blueprintOffset != 0) {
		auto* blueprint = (Blueprint*)(((size_t)targ) + targ->type->blueprintOffset);
		if(!blueprint || !blueprint->design)
			return 0.0;
		return blueprint->design->hasTag((int)(size_t)arg) ? 1.0 : 0.0;
	}
	return 0.0;
}

static double targRadius(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(targ == nullptr)
		return 1.0;
	return targ->radius;
}

static double originRadius(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj == nullptr)
		return 1.0;
	return obj->radius;
}

static double sizeDifference(const Effector* eff, Object* obj, Object* targ, void* arg) {
	if(obj == nullptr || targ == nullptr)
		return 1.0;
	if(obj->radius > targ->radius)
		return obj->radius / targ->radius;
	else
		return targ->radius / obj->radius;
}

//* Activation
static EffectorActivationType Always(const Effector* eff, Object* obj, EffectorTarget& targ, double& time, double* args, double* states) {
	return EAT_Activate;
}

static EffectorActivationType Timed(const Effector* eff, Object* obj, EffectorTarget& targ, double& time, double* args, double* states) {
	if(!(targ.flags & TF_WithinFireTolerance)) {
		if(states[0] > 0.0)
			states[0] = std::max(states[0] - time, 0.0);
		return EAT_Inactive;
	}
	else if(states[0] <= time) {
		time = states[0];
		states[0] = args[0];
		if(args[0] <= 0.000001)
			return EAT_Inactive;
		return EAT_Repeat;
	}

	states[0] -= time;
	return EAT_Inactive;
}

static EffectorActivationType VariableTimed(const Effector* eff, Object* obj, EffectorTarget& targ, double& time, double* args, double* states) {
	if(!(targ.flags & TF_WithinFireTolerance)) {
		if(states[0] > 0.0)
			states[0] = std::max(states[0] - time, 0.0);
		return EAT_Inactive;
	}
	else if(states[0] <= time) {
		time = states[0];
		if(targ.target)
			states[0] = args[0] * randomd(1.0 - args[1], 1.0 + args[1]);
		else
			states[0] = args[0];
		if(args[0] <= 0.000001)
			return EAT_Inactive;
		return EAT_Repeat;
	}

	states[0] -= time;
	return EAT_Inactive;
}

static EffectorActivationType StaggeredTimed(const Effector* eff, Object* obj, EffectorTarget& targ, double& time, double* args, double* states) {
	if(!(targ.flags & TF_WithinFireTolerance)) {
		double stagger = args[1] * args[0] * (-eff->relativePosition.x + 1.0) * 0.5;
		states[0] = std::max(states[0] - time, stagger);
		return EAT_Inactive;
	}
	else if(states[0] <= time) {
		time = states[0];
		states[0] = args[0];
		if(args[0] <= 0.000001)
			return EAT_Inactive;
		return EAT_Repeat;
	}

	states[0] -= time;
	return EAT_Inactive;
}

//Fires arg[1] shots at arg[0] second intervals, then reloads over arg[2] seconds
static EffectorActivationType Magazine(const Effector* eff, Object* obj, EffectorTarget& targ, double& time, double* args, double* states) {
	if(!(targ.flags & TF_WithinFireTolerance) || states[1] <= 0.0) {
		if(states[0] > 0.0) {
			states[0] = states[0] - time;
			if(states[0] <= 0.0) {
				states[1] = args[1];
				states[0] = 0.0;
			}
		}
		else {
			states[1] = args[1];
		}
		return EAT_Inactive;
	}
	else if(states[0] <= time) {
		time = states[0];
		states[1] -= 1.0;
		if(states[1] <= 0.000001)
			states[0] = args[2];
		else
			states[0] = args[0];
		if(args[0] <= 0.000001)
			return EAT_Inactive;
		return EAT_Repeat;
	}

	states[0] -= time;
	return EAT_Inactive;
}

//Build maps
decltype(TargetAlgorithms) makeAlgoList() {
	decltype(TargetAlgorithms) list;

	list["SingleTarget"] = SingleTarget;

	return list;
}

decltype(TargetWeighters) makeWeighterList() {
	decltype(TargetWeighters) list;
	
	list["NotOurs"] = NotOurs;
	list["Ours"] = Ours;
	list["isEnemy"] = isEnemy;
	list["isAttackable"] = isAttackable;
	list["hasDamagedBlueprint"] = hasDamagedBlueprint;
	list["isDamageable"] = isDamageable;
	list["targRadius"] = targRadius;
	list["originRadius"] = originRadius;
	list["sizeDifference"] = sizeDifference;
	list["Distance"] = Distance;

	return list;
}

decltype(EffectorActivation) makeActivationList() {
	decltype(EffectorActivation) list;

	auto addFunc = [&](std::string name, nativeEffectorActivation f, unsigned stateCount, unsigned argCount)
	{
		auto& cb = list[name];
		cb.func = f;
		cb.stateCount = stateCount;
		cb.argCount = argCount;
	};

	addFunc("Always", Always, 0, 0);
	addFunc("Timed", Timed, 1, 1);
	addFunc("VariableTimed", VariableTimed, 1, 2);
	addFunc("StaggeredTimed", StaggeredTimed, 1, 2);
	addFunc("Magazine", Magazine, 2, 3);

	return list;
}

umap<std::string, nativeTargetAlgorithm> TargetAlgorithms = makeAlgoList();
umap<std::string, nativeTargetWeighter> TargetWeighters = makeWeighterList();
umap<std::string, ActivationCB> EffectorActivation = makeActivationList();
