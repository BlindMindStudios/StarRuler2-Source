#include "design/effector.h"
#include "compat/misc.h"

extern umap<std::string, nativeTargetAlgorithm> TargetAlgorithms;
extern umap<std::string, nativeTargetWeighter> TargetWeighters;

struct ActivationCB {
	nativeEffectorActivation func;
	unsigned stateCount, argCount;
};

extern umap<std::string, ActivationCB> EffectorActivation;

double isType(const Effector* eff, Object* obj, Object* targ, void* arg);
double hasTag(const Effector* eff, Object* obj, Object* targ, void* arg);
