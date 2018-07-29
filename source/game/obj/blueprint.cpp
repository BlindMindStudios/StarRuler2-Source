#include "obj/blueprint.h"
#include "constants.h"
#include "util/random.h"
#include "main/references.h"
#include "main/logging.h"
#include "network/message.h"
#include <algorithm>
#include "empire.h"
#include "util/save_file.h"
#include "scriptany.h"
#include <assert.h>
#include "scene/node.h"

void shader_quadrant_damage(float* values, unsigned short amt, void*) {
	if(auto* node = scene::renderingNode) {
		Object* obj = node->obj;

		if(obj != nullptr) {
			size_t offset = obj->type->blueprintOffset;
			if(offset != 0) {
				Blueprint* bp = (Blueprint*)(((size_t)obj) + offset);
				const Design* dsg = bp->design;
				if(dsg != nullptr) {
					for(unsigned i = 0; i < 4; ++i) {
						float curHP = bp->quadrantHP[i];
						float maxHP = dsg->quadrantTotalHP[i];
						if(maxHP <= 0.f)
							values[i] = 1.f;
						else
							values[i] = 1.f - (curHP / maxHP);
					}
				}
			}
		}
		return;
	}

	for(unsigned i = 0; i < 4; ++i)
		values[i] = 0.f;
}

Blueprint::Blueprint()
	: design(nullptr), statusID(0), designChanged(false), hpDelta(false), repairingHex(-1,-1), holdFire(false),
	  hpFactor(1.f), removedHP(0.f) {
}

void Blueprint::init(Object* obj) {
}

Blueprint::HexStatus* Blueprint::getHexStatus(unsigned x, unsigned y) {
	if(!design->hexStatusIndex.valid(vec2u(x, y)))
		return 0;
	int index = design->hexStatusIndex.get(x, y);
	if(index < 0)
		return 0;
	return &hexes[index];
}

Blueprint::HexStatus* Blueprint::getHexStatus(unsigned index) {
	if(design == nullptr || index >= design->usedHexCount)
		return 0;
	return &hexes[index];
}

Blueprint::SysStatus* Blueprint::getSysStatus(unsigned index) {
	return &subsystems[index];
}

Blueprint::SysStatus* Blueprint::getSysStatus(unsigned x, unsigned y) {
	if(!design->grid.valid(vec2u(x, y)))
		return 0;
	int index = design->grid.get(x, y);
	if(index < 0)
		return 0;
	return &subsystems[index];
}

CScriptAny* Blueprint::getHookData(unsigned index) {
	if(index >= design->dataCount)
		return nullptr;
	return data[index];
}

void Blueprint::create(Object* obj, const Design* design) {
	this->design = design;
	if(!design)
		return;

	designChanged = true;
	hpDelta = true;
	++statusID;
	++design->built;
	++design->active;

	//Create hex status grid
	hexes = new HexStatus[design->usedHexCount];
	for(unsigned i = 0; i < design->usedHexCount; ++i) {
		HexStatus& hex = hexes[i];
		hex.hp = 255;
		hex.flags = HF_Active;
		
		int hexIndex = design->hexIndex[design->hexes[i]];
		int sysIndex = design->grid[design->hexes[i]];

		if(sysIndex != -1) {
			const float* hp = design->subsystems[sysIndex].hexVariable(HV_HP, hexIndex);
			if(hp == nullptr || *hp == 0.f) {
				hex.hp = 0;
				hex.flags |= HF_NoHP;
			}
		}
	}

	//Initialize subsystems
	EffectEvent event;
	event.obj = obj;

	unsigned cnt = (unsigned)design->subsystems.size();
	subsystems = new SysStatus[cnt];
	states = new BasicType[design->stateCount];
	effectorStates = new double[design->effectorStateCount];
	effectorTargets = new EffectorTarget[design->effectorCount];
	destroyedHexes = 0;
	currentHP = design->totalHP;
	for(unsigned i = 0; i < 4; ++i)
		quadrantHP[i] = design->quadrantTotalHP[i];
	shipEffectiveness = 1.0;
	removedHP = 0.f;

	data = new CScriptAny*[design->dataCount];
	for(unsigned i = 0, cnt = design->dataCount; i < cnt; ++i)
		data[i] = new CScriptAny(devices.scripts.server->engine);

	memset(effectorStates, 0, design->effectorStateCount * sizeof(double));
	memset(reinterpret_cast<void *>(effectorTargets), 0, design->effectorCount * sizeof(EffectorTarget));

	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		d.workingHexes = (unsigned short)sys.hexes.size();
		d.status = ES_Active;

		//Initialize states
		for(size_t j = 0, jcnt = sys.type->states.size(); j < jcnt; ++j)
			states[sys.stateOffset + j] = sys.defaults[j];

		//Initialize turret tracking
		for(size_t j = 0, jcnt = sys.type->effectors.size(); j < jcnt; ++j)
			effectorTargets[sys.effectorOffset+j].tracking = sys.effectors[j].turretAngle;
	}
}

void Blueprint::start(Object* obj, bool fromRetrofit) {
	//Initialize subsystems
	EffectEvent event;
	event.obj = obj;

	unsigned cnt = (unsigned)design->subsystems.size();
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		d.status = ES_Active;

		//Start the subsystem
		event.source = i;
		if(fromRetrofit) {
			sys.call(EH_Retrofit_Post, event);
			sys.call(EH_Continue, event);
		}
		else {
			sys.call(EH_Start, event);
		}

		//Enable all the modules
		for(size_t j = 0, jcnt = sys.modules.size(); j < jcnt; ++j)
			sys.modules[j]->onEnable(event, sys.hexes[j]);
	}
}

bool Blueprint::hasTagActive(int index) {
	if(!design)
		return false;

	for(size_t i = 0, cnt = design->subsystems.size(); i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		if(d.status == ES_Active)
			if(sys.type->hasTag(index))
				return true;
	}
	return false;
}

double Blueprint::getTagEfficiency(int index, bool ignoreInactive) {
	unsigned totalHexes = 0;
	unsigned activeHexes = 0;

	for(size_t i = 0, cnt = design->subsystems.size(); i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		totalHexes += (unsigned)sys.hexes.size();

		if(!ignoreInactive || d.status == ES_Active)
			activeHexes += (unsigned)d.workingHexes;
	}

	if(totalHexes == 0)
		return 0.0;
	return (double)activeHexes / (double)totalHexes;
}

double Blueprint::getEfficiencySum(int variable, int tag, bool ignoreInactive) {
	if(!design)
		return 0.0;

	double total = 0.0;

	for(size_t i = 0, cnt = design->subsystems.size(); i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		if(ignoreInactive && d.status != ES_Active)
			continue;

		if(tag != -1 && !sys.type->hasTag(tag))
			continue;

		const float* val = sys.variable(variable);
		if(val) {
			double eff = (double)d.workingHexes / (double)sys.hexes.size();
			total += eff * (double)*val;
		}
	}

	return total;
}

double Blueprint::getEfficiencyFactor(int variable, int tag, bool ignoreInactive) {
	if(!design)
		return 0.0;

	double total = 0.0;
	double active = 0.0;

	for(size_t i = 0, cnt = design->subsystems.size(); i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];

		if(tag != -1 && !sys.type->hasTag(tag))
			continue;

		const float* val = sys.variable(variable);
		if(!val)
			continue;

		total += (double)*val;
		if(!ignoreInactive || d.status == ES_Active) {
			double eff = (double)d.workingHexes / (double)sys.hexes.size();
			active += eff * (double)*val;
		}
	}

	if(total == 0)
		return 0.0;
	return active / total;
}

Object* Blueprint::getCombatTarget() {
	if(!design)
		return nullptr;

	unsigned start = 0;
	unsigned end = design->effectorCount;

	for(; start < end; ++start) {
		auto& targ = effectorTargets[start];
		if(targ.target) {
			targ.target->grab();
			return targ.target;
		}
	}

	return nullptr;
}

//Cached facing angles that are going to be looked at
const vec3d FACING_POSITIONS[20] = {
	vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.1*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.2*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.3*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.4*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.5*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.6*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.7*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.8*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 0.9*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.0*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.1*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.2*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.3*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.4*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.5*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.6*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.7*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.8*pi) * vec3d::front(),
	quaterniond::fromAxisAngle(vec3d::up(), 1.9*pi) * vec3d::front(),
};

vec3d Blueprint::getOptimalFacing(int sysVariable, int tag, bool ignoreInactive) {
	if(!design)
		return vec3d::front();

	double values[20] = {
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };

	size_t sysCount = design->subsystems.size();
	for(size_t i = 0; i < sysCount; ++i) {
		auto& sys = design->subsystems[i];
		auto& status = subsystems[i];

		//Ignore subsystems with no effectors to determine facing
		size_t effCnt = sys.type->effectors.size();
		if(effCnt == 0)
			continue;

		if(ignoreInactive && status.status != ES_Active)
			continue;

		//Do tag filtering
		if(tag != -1 && !sys.type->hasTag(tag))
			continue;

		//Determine value of subsystem by passed variable
		const float* val = sys.variable(sysVariable);
		if(!val)
			continue;

		float curValue = *val;
		curValue *= (float)status.workingHexes / (float)sys.hexes.size();

		//Make sure we have effectors with firing arcs
		bool foundOne = false;
		for(size_t n = 0; n < effCnt; ++n) {
			Effector* eff = &sys.effectors[n];

			if(eff->fireArc >= twopi-0.01 || !eff->enabled)
				continue;

			foundOne = true;
			break;
		}

		if(!foundOne)
			continue;

		//Mark everything that can be fired at by all effectors
		for(unsigned j = 0; j < 20; ++j) {
			const vec3d& facing = FACING_POSITIONS[j];

			bool usable = true;
			double dist = 0;
			for(size_t n = 0; n < effCnt; ++n) {
				Effector* eff = &sys.effectors[n];

				//Ignore omnidirectional stuff
				if(eff->fireArc >= twopi-0.01 || !eff->enabled)
					continue;

				//Check if we can fire in this direction
				double d = facing.angleDistance(eff->turretAngle);
				dist += d;
				if(d > eff->fireArc) {
					usable = false;
					break;
				}
			}

			if(usable)
				values[j] += curValue - (dist * 0.001);
		}
	}

	//Find the best facing
	double best = 0.0;
	vec3d bestFacing = vec3d::front();
	for(unsigned j = 0; j < 20; ++j) {
		if(values[j] > best) {
			best = values[j];
			bestFacing = FACING_POSITIONS[j];
		}
	}

	return bestFacing;
}

void Blueprint::destroy(Object* obj) {
	--design->active;

	//Stop all the subsystem effects
	EffectEvent event;
	event.obj = obj;

	unsigned cnt = (unsigned)design->subsystems.size();
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		auto& d = subsystems[i];
		event.source = i;

		//Disable all the modules
		if(d.status == ES_Active) {
			for(size_t j = 0, jcnt = sys.modules.size(); j < jcnt; ++j)
				sys.modules[j]->onDisable(event, sys.hexes[j]);
			sys.call(EH_End, event);
		}

		sys.call(EH_Destroy, event);
	}
}

void Blueprint::ownerChange(Object* obj, Empire* prevEmpire, Empire* newEmpire) {
	//Stop all the subsystem effects
	EffectEvent event;
	event.obj = obj;

	unsigned cnt = (unsigned)design->subsystems.size();
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		event.source = i;

		sys.ownerChange(event, prevEmpire, newEmpire);
	}
}

void Blueprint::preClear() {
	for(unsigned i = 0; i < design->effectorCount; ++i) {
		if(effectorTargets[i].target) {
			effectorTargets[i].target->drop();
			effectorTargets[i].target = nullptr;
		}
	}
}

Blueprint::~Blueprint() {
	delete[] hexes;
	delete[] subsystems;
	delete[] effectorStates;
	for(unsigned i = 0; i < design->effectorCount; ++i)
		if(effectorTargets[i].target)
			effectorTargets[i].target->drop();
	delete[] effectorTargets;
	for(unsigned i = 0, cnt = design->dataCount; i < cnt; ++i) {
		if(data[i])
			data[i]->Release();
	}
	delete[] data;
}

void Blueprint::retrofit(Object* obj, const Design* toDesign) {
	if(this->design == nullptr)
		return;
	if(toDesign->base() == this->design->base()
			&& toDesign->usedHexCount == this->design->usedHexCount
			&& toDesign->subsystems.size() == this->design->subsystems.size()
			&& toDesign->dataCount == this->design->dataCount
			&& toDesign->effectorCount == this->design->effectorCount
			&& toDesign->effectorStateCount == this->design->effectorStateCount
			&& toDesign->stateCount == this->design->stateCount
			//These extra checks *should* be implied from sharing a base, but let's just make sure
		) {

		//Stop all subsystems
		EffectEvent event;
		event.obj = obj;

		for(int i = 0, cnt = (int)design->subsystems.size(); i < cnt; ++i) {
			auto& sys = design->subsystems[i];
			auto& d = subsystems[i];

			//Suspend subsystem
			event.source = i;
			sys.call(EH_Retrofit_Pre, event);

			if(d.status == ES_Active) {
				sys.call(EH_Suspend, event);

				//Disable all the modules
				for(size_t j = 0, jcnt = sys.modules.size(); j < jcnt; ++j)
					sys.modules[j]->onDisable(event, sys.hexes[j]);
			}
		}

		this->design = toDesign;
		++statusID;
		hpDelta = true;
		designChanged = true;

		//Resume all subsystems
		double newHP = 0.0;
		for(unsigned i = 0; i < 4; ++i)
			quadrantHP[i] = 0;
		for(unsigned i = 0; i < design->usedHexCount; ++i) {
			vec2u pos = design->hexes[i];
			int sysIndex = design->grid[pos];
			if(sysIndex == -1)
				continue;

			auto& hs = hexes[i];
			auto& sys = design->subsystems[sysIndex];
			int hexIndex = design->hexIndex[pos];

			const float* hp = sys.hexVariable(HV_HP, hexIndex);
			if(hp) {
				double hexHP = *hp * ((double)hs.hp / 255.0);
				newHP += hexHP;
				quadrantHP[design->getQuadrant(pos)] += hexHP;
			}
		}
		currentHP = newHP;
		removedHP = 0.f;

		//Start new subsystems
		start(obj, true);
	}
	else {
		//Stop all subsystems
		EffectEvent event;
		event.obj = obj;

		for(int i = 0, cnt = (int)design->subsystems.size(); i < cnt; ++i) {
			auto& sys = design->subsystems[i];
			auto& d = subsystems[i];

			//Suspend subsystem
			event.source = i;
			sys.call(EH_Retrofit_Pre, event);

			if(d.status == ES_Active) {
				sys.call(EH_Suspend, event);

				//Disable all the modules
				for(size_t j = 0, jcnt = sys.modules.size(); j < jcnt; ++j)
					sys.modules[j]->onDisable(event, sys.hexes[j]);
			}
		}

		//Delete previous data
		delete[] hexes;
		delete[] subsystems;
		delete[] effectorStates;

		for(unsigned i = 0, cnt = design->dataCount; i < cnt; ++i) {
			if(data[i])
				data[i]->Release();
		}
		delete[] data;

		for(unsigned i = 0; i < design->effectorCount; ++i)
			if(effectorTargets[i].target)
				effectorTargets[i].target->drop();
		delete[] effectorTargets;

		//Create new data
		create(obj, toDesign);
		start(obj, true);
	}
}

float Blueprint::think(Object* obj, double time) {
	if(!design)
		return 5.f;

	EffectEvent event;
	event.obj = obj;
	event.time = time;

	unsigned cnt = (unsigned)design->subsystems.size();
	unsigned efftr = 0;
	bool engaged = false, inCombat = obj->getFlag(objCombat);
	for(unsigned i = 0; i < cnt; ++i) {
		auto& sys = design->subsystems[i];
		EffectStatus status = subsystems[i].status;

		event.partiality = (float)subsystems[i].workingHexes / (float)sys.hexes.size();
		if(status != ES_Active)
			event.partiality = 0.f;

		event.efficiency = event.partiality * (float)shipEffectiveness;

		event.source = i;
		event.status = status;

		sys.tick(event);

		//Handle suspend and continue
		if(status == ES_Suspended) {
			if(event.status != ES_Suspended) {
				sys.call(EH_Continue, event);
				++statusID;
			}
		}
		else {
			if(event.status == ES_Suspended) {
				sys.call(EH_Suspend, event);
				++statusID;
			}
		}

		//Handle effectors
		if(event.status == ES_Active) {
			for(unsigned i = 0, cnt = (unsigned)sys.type->effectors.size(); i < cnt; ++i) {
				auto& effector = sys.effectors[i];
				if(!effector.enabled)
					continue;
				EffectorTarget& target = effectorTargets[efftr];
				double* states = effectorStates + effector.stateOffset;
				effector.update(obj, time, states, target, event.efficiency, holdFire);
				++efftr;

				if(target.flags & TF_Firing)
					engaged = true;
			}
		}
	}
	if(engaged)
		obj->setFlag(objEngaged, true);
	return inCombat ? 0.1f : 0.25f;
}

bool Blueprint::canTarget(Object* obj, Object* target) {
	foreach(it, design->subsystems) {
		auto& sys = *it;

		for(unsigned i = 0, cnt = (unsigned)sys.type->effectors.size(); i < cnt; ++i) {
			Effector* eff = &sys.effectors[i];
			if(eff->enabled && eff->canTarget(obj, target))
				return true;
		}
	}
	return false;
}

bool Blueprint::doesAutoTarget(Object* obj, Object* target) {
	foreach(it, design->subsystems) {
		auto& sys = *it;

		for(unsigned i = 0, cnt = (unsigned)sys.type->effectors.size(); i < cnt; ++i) {
			Effector* eff = &sys.effectors[i];
			if(eff->autoTarget(obj, target))
				return true;
		}
	}
	return false;
}

void Blueprint::target(Object* obj, Object* target, TargetFlags flags) {
	unsigned start = 0;
	unsigned end = design->effectorCount;

	for(; start < end; ++start) {
		auto& targ = effectorTargets[start];
		if(targ.target == target)
			continue;
		if(!targ.target || targ.flags & TF_Preference || !(flags & TF_Preference)) {
			if(targ.target)
				targ.target->drop();
			targ.target = target;
			targ.flags = flags;
			if(target)
				target->grab();
		}
	}
}

void Blueprint::clearTracking(Object* obj) {
	unsigned start = 0;
	unsigned end = design->effectorCount;

	for(; start < end; ++start) {
		auto& targ = effectorTargets[start];
		targ.flags |= TF_ClearTracking;
	}
}

void Blueprint::target(Object* obj, unsigned efftrIndex, Object* target, TargetFlags flags) {
	if(efftrIndex >= design->effectorCount)
		return;
	auto& targ = effectorTargets[efftrIndex];
	if(targ.target == target)
		return;
	if(!targ.target || targ.flags & TF_Preference || !(flags & TF_Preference)) {
		if(targ.target)
			targ.target->drop();
		targ.target = target;
		targ.flags = flags;
		if(target)
			target->grab();
	}
}

void Blueprint::target(Object* obj, const Subsystem* sys, Object* target, TargetFlags flags) {
	unsigned start = sys->effectorOffset;
	unsigned end = start + (unsigned)sys->type->effectors.size();

	for(; start < end; ++start) {
		auto& targ = effectorTargets[start];
		if(targ.target == target)
			continue;
		if(!targ.target || targ.flags & TF_Preference || !(flags & TF_Preference)) {
			if(targ.target)
				targ.target->drop();
			targ.target = target;
			targ.flags = flags;
		if(target)
			target->grab();
		}
	}
}

void Blueprint::damage(Object* obj, DamageEvent& evt, const vec2d& direction) {
	if(!design || (direction.x == 0.0 && direction.y == 0.0))
		return;

	//Find a position for this direction that ensures something gets damaged
	unsigned count = (unsigned)design->hexes.size();
	unsigned index = randomi(0, count-1);

	unsigned w = design->grid.width;
	unsigned h = design->grid.height;

	vec2d dirline = direction.normalized((double)(w+h) * 2.0);

	vec2u goal(-1, -1);
	for(unsigned i = 0; i < count; ++i, index = (index+1) % count) {
		goal = design->hexes[index];
		HexStatus* status = getHexStatus(goal.x, goal.y);
		if(status && status->hp != 0)
			break;
	}

	if(!design->grid.valid(goal))
		return;

	vec2u hex = goal;

	//We found a hex that can take damage, now run
	//the line through here.

	vec2d effPos = design->grid.getEffectivePosition(hex);
	vec2d startPos = effPos + dirline;
	vec2d endPos = effPos - dirline;

	//Advance toward the edge in the direction of the source
	while(hex.x > 0 && hex.x < w-1 && hex.y > 0 && hex.y < h-1) {
		vec2d diff = design->grid.getEffectivePosition(hex);
		diff.y = -diff.y;
		diff = startPos - diff;
		
		double dir = diff.radians();
		HexGridAdjacency adj = HexGrid<>::AdjacencyFromRadians(dir);

		if(!design->grid.advance(hex, adj))
			break;
	}

	//Run global damage events
	unsigned sysCnt = (unsigned)design->damageOrder.size();
	for(unsigned i = 0; i < sysCnt; ++i) {
		auto& sys = *design->damageOrder[i];
		if(subsystems[sys.index].status != ES_Active)
			continue;
		evt.target = obj;
		evt.destination = sys.index;
		vec2d dir = direction;
		switch(sys.globalDamage(evt, hex, dir)) {
			case DE_Continue:
				break;
			case DE_SkipHex:
			case DE_EndDamage:
				return;
		}
	}

	bool reachedTarget = false;

	//Run forward from the starting position to the end position
	unsigned n = 0;
	for(; n < 500; ++n) {
		damage_internal(obj, evt, hex);

		//Stop if no damage is left
		if(evt.damage <= 0.0)
			break;

		if(!reachedTarget && hex == goal)
			reachedTarget = true;

		//Find next hex
		vec2d diff = design->grid.getEffectivePosition(hex);
		if(reachedTarget)
			diff = endPos - diff;
		else
			diff = effPos - diff;
		diff.y = -diff.y;

		double dir = diff.radians();
		auto adj = HexGrid<>::AdjacencyFromRadians(dir);

		if(!design->grid.advance(hex, adj))
			break;
	}

	if(!evt.spillable && evt.damage > 0) {
		double prev;
		evt.spillable = true;
		do {
			prev = evt.damage;
			damage(obj, evt, direction);
		}
		while (evt.damage < prev - 0.001 && evt.damage > 0.001);
	}

	if(n == 500) {
		error("WARNING: Detected a damage event that passed"
		"a ridiculous amount of hexes (500).\n  Stopping the event. Check if "
		"an endpoint within the blueprint is being passed.");
	}
}

void Blueprint::damage(Object* obj, DamageEvent& evt, double position, const vec2d& direction) {
	if(!design || direction.x == 0.0 || direction.y == 0.0)
		return;

	//Helper to figure out the starting hex from a percentage position
	double rad = direction.radians();
	vec2u hex;
	vec2d endPoint;

	//Top
	if(rad > 0.25*pi && rad < 0.75*pi) {
		if(position == 0.0)
			hex = vec2u(0, 0);
		else
			hex = vec2u((unsigned)ceil(position * design->grid.width) - 1, 0);

		vec2d hpos = design->grid.getEffectivePosition(hex);
		endPoint.y = design->grid.height;
		endPoint.x = hpos.x - direction.x * fabs((double)design->grid.height / direction.y);
	}
	//Bottom
	else if(rad < -0.25*pi && rad > -0.75*pi) {
		if(position == 0.0)
			hex = vec2u(0, design->grid.height - 1);
		else
			hex = vec2u((unsigned)ceil(position * design->grid.width) - 1, design->grid.height - 1);

		vec2d hpos = design->grid.getEffectivePosition(hex);
		endPoint.y = -1.0;
		endPoint.x = hpos.x - direction.x * fabs((double)design->grid.height / direction.y);
	}
	//Right
	else if(rad < 0.25*pi && rad > -0.25*pi) {
		if(position == 0.0)
			hex = vec2u(design->grid.width - 1, 0);
		else
			hex = vec2u(design->grid.width - 1, (unsigned)ceil(position * design->grid.height) - 1);

		vec2d hpos = design->grid.getEffectivePosition(hex);
		endPoint.x = -1.0;
		endPoint.y = hpos.y - direction.y * fabs((0.75 * design->grid.width) / direction.x);
	}
	//Left
	else {
		if(position == 0.0)
			hex = vec2u(0, 0);
		else
			hex = vec2u(0, (unsigned)ceil(position * design->grid.height) - 1);

		vec2d hpos = design->grid.getEffectivePosition(hex);
		endPoint.x = 0.75 * design->grid.width;
		endPoint.y = hpos.y - direction.y * fabs((0.75 * design->grid.width) / direction.x);
	}

	//Run global damage events
	unsigned sysCnt = (unsigned)design->damageOrder.size();
	for(unsigned i = 0; i < sysCnt; ++i) {
		auto& sys = *design->damageOrder[i];
		if(subsystems[sys.index].status != ES_Active)
			continue;
		evt.target = obj;
		evt.destination = sys.index;
		vec2d dir = direction;
		switch(sys.globalDamage(evt, hex, dir)) {
			case DE_Continue:
				break;
			case DE_SkipHex:
			case DE_EndDamage:
				return;
		}
	}

	damage(obj, evt, hex, endPoint);

	if(evt.damage > 0)
		damage(obj, evt, direction);
}

void Blueprint::damage(Object* obj, DamageEvent& evt, const vec2u& _position, const vec2d& _endPoint) {
	if(!design)
		return;

	vec2u position = _position;
	vec2d endPoint = _endPoint;

	//Make sure we start at a valid hex
	if(!design->grid.valid(position))
		return;

	//endPoint y coordinate should be flipped due to euclidian space
	//and hex grid space being oriented differently in that dimension
	endPoint.y = -endPoint.y;

	//Keep hitting hexes until we run out of damage or hexes
	// (Limit the amount of hexes that can be damaged for if
	// some retard passes an endPoint that is within the blueprint)
	unsigned i = 0;
	for(; i < 500; ++i) {
		damage_internal(obj, evt, position);

		//Stop if no damage is left
		if(evt.damage <= 0.0)
			break;

		//Find next hex
		vec2d diff = design->grid.getEffectivePosition(position);
		diff.y = -diff.y;
		diff = endPoint - diff;

		double dir = diff.radians() + pi;
		HexGridAdjacency adj = HexGridAdjacency(dir >= 2*pi ? 5 : (int)floor(dir / (pi / 3.0)));

		if(!design->grid.advance(position, adj))
			break;
	}

	if(i == 500) {
		error("WARNING: Detected a damage event that passed"
		"a ridiculous amount of hexes (500).\n  Stopping the event. Check if "
		"an endpoint within the blueprint is being passed.");
	}
}

void Blueprint::damage(Object* obj, DamageEvent& evt, const vec2u& hex, HexGridAdjacency dir, bool runGlobal) {
	if(!design)
		return;

	vec2u pos = hex;
	vec2d direction;
	if(!design->grid.valid(pos))
		return;

	//Run global damage events
	if(runGlobal) {
		unsigned sysCnt = (unsigned)design->damageOrder.size();
		for(unsigned i = 0; i < sysCnt; ++i) {
			auto& sys = *design->damageOrder[i];
			if(subsystems[sys.index].status != ES_Active)
				continue;
			evt.target = obj;
			evt.destination = sys.index;
			switch(sys.globalDamage(evt, pos, direction)) {
				case DE_Continue:
					break;
				case DE_SkipHex:
				case DE_EndDamage:
					return;
			}
		}
	}

	//Run forward from the starting position to the end position
	while(design->grid.valid(pos)) {
		damage_internal(obj, evt, pos);

		//Stop if no damage is left
		if(evt.damage <= 0.0)
			break;

		//Find next hex
		if(!design->grid.advance(pos, dir))
			break;
	}
}

void Blueprint::damage(Object* obj, DamageEvent& evt, const vec2u& hex, bool runGlobal) {
	if(!design)
		return;

	vec2u pos = hex;
	vec2d direction;
	if(!design->grid.valid(pos))
		return;

	//Run global damage events
	if(runGlobal) {
		unsigned sysCnt = (unsigned)design->damageOrder.size();
		for(unsigned i = 0; i < sysCnt; ++i) {
			auto& sys = *design->damageOrder[i];
			if(subsystems[sys.index].status != ES_Active)
				continue;
			evt.target = obj;
			evt.destination = sys.index;
			switch(sys.globalDamage(evt, pos, direction)) {
				case DE_Continue:
					break;
				case DE_SkipHex:
				case DE_EndDamage:
					return;
			}
		}
	}

	//Damage the specified hex
	damage_internal(obj, evt, pos);
}

bool Blueprint::globalDamage(Object* obj, DamageEvent& evt) {
	if(!design)
		return false;

	vec2u dummyHex(0, 0);
	vec2d dummyDir(1.0, 0.0);

	//Run global damage events
	unsigned sysCnt = (unsigned)design->damageOrder.size();
	for(unsigned i = 0; i < sysCnt; ++i) {
		auto& sys = *design->damageOrder[i];
		if(subsystems[sys.index].status != ES_Active)
			continue;
		evt.target = obj;
		evt.destination = sys.index;
		switch(sys.globalDamage(evt, dummyHex, dummyDir)) {
			case DE_Continue:
			case DE_SkipHex:
				return false;
			case DE_EndDamage:
				return true;
		}
	}
	return false;
}

void Blueprint::damage_internal(Object* obj, DamageEvent& evt, const vec2u& position) {
	int index = design->grid[position];
	if(index >= 0) {
		auto& sys = design->subsystems[index];
		auto& status = *getHexStatus(position.x, position.y);
		if(status.hp == 0 && !sys.type->alwaysTakeDamage)
			return;

		float prevPartial = evt.partiality;

		//Resistance reduces pierce through
		double dealDamage = evt.damage;
		int hexIndex = design->hexIndex[position];
		if(const float* res = sys.hexVariable(HV_Resistance, hexIndex))
			evt.pierce = std::max(evt.pierce - *res, 0.f);

		if(evt.pierce > 0) {
			if(evt.pierce > 1.f)
				return;
			dealDamage *= (1.0 - evt.pierce);
			float part = (float)(dealDamage / evt.damage);
			evt.partiality *= part;
			prevPartial *= 1.f - part;
		}

		double remainingDamage = evt.damage - dealDamage;

		//Do damage to hex
		evt.target = obj;
		evt.destination = index;
		evt.damage = dealDamage;

		if(status.flags & HF_Active) {
			switch(sys.damage(evt, position)) {
				case DE_Continue:
					damage(obj, evt, position);
					break;
				case DE_SkipHex:
					break;
				case DE_EndDamage:
					evt.damage = 0;
					return;
			}
		}
		else {
			damage(obj, evt, position);
		}

		evt.partiality = prevPartial;
		evt.damage += remainingDamage;
	}
}

void Blueprint::damage(Object* obj, DamageEvent& evt, const vec2u& position) {
	if(!design)
		return;

	int index = design->grid[position];
	if(index < 0)
		return;

	HexStatus* hexPtr = getHexStatus(position.x, position.y);
	if(!hexPtr)
		return;
	HexStatus& hex = *hexPtr;

	auto& sys = design->subsystems[index];
	SysStatus& status = subsystems[index];
	int hexIndex = design->hexIndex[position];

	//If it has HP, we can damage it
	if(const float* hp = sys.hexVariable(HV_HP, hexIndex)) {
		//Figure out how much damage to deal
		double hexHP = *hp * (double)hex.hp / 255.0 * hpFactor;
		double deal = std::min(evt.damage, hexHP);
		if(deal <= 0.0)
			return;

		double dmgPts, fracPt = modf(deal * (255.0 / (double)*hp) / hpFactor, &dmgPts);

		//Directly deal any full damage
		unsigned char relative = (unsigned char)dmgPts;

		//If there is a significant fractional damage
		//component, use randomness
		if(fracPt > 0.001 && relative < 255)
			if(randomd() <= fracPt)
				relative += 1;

		//We absorbed the hit (likely only a fractional hit)
		if(relative == 0) {
			evt.damage -= deal;
			return;
		}

		//Deal the damage
		short prevHP = hex.hp;
		hex.hp = (unsigned char)std::max(0, (short)hex.hp - (short)relative);
		relative = (prevHP - hex.hp);
		hpDelta = true;

		//Check if the hex should be marked as destroyed
		if(!(hex.flags & HF_Destroyed) && hex.hp == 0) {
			hex.flags |= HF_Destroyed;
			status.workingHexes -= 1;

			//Notify the effects that a hex was destroyed
			EffectEvent ef;
			ef.obj = obj;
			ef.source = index;

			ef.partiality = (float)status.workingHexes / (float)sys.hexes.size();
			ef.efficiency = ef.partiality * (float)shipEffectiveness;

			sys.call(EH_Change, ef);
			++statusID;

			//Notify the module
			auto* mod = sys.modules[hexIndex];

			if(mod->scr_onDisable) {
				EffectEvent evt;
				evt.obj = obj;
				evt.source = index;

				mod->onDisable(evt, position);
			}

			//Deactivate the entire subsystem if we have to
			if(mod->vital || status.workingHexes == 0) {
				status.status = ES_Ended;
				sys.call(EH_End, ef);
			}

			//Check if the entire ship should blow up
			++destroyedHexes;
			//if(destroyedHexes >= design->usedHexCount / 3) {
			//	evt.damage = 0.0;
			//	evt.flags |= 0x40000000;
			//	obj->flagDestroy();
			//	return;
			//}
		}

		//Remove dealt damage
		evt.damage -= deal;

		double change = relative * (double)*hp / 255.0;
		currentHP -= change;
		quadrantHP[design->getQuadrant(position)] -= change;
	}
}

double Blueprint::repair(Object* obj, double amount) {
	if(!design || currentHP >= design->totalHP) {
		repairingHex = vec2i(-1, -1);
		return amount;
	}

	auto findRepairHex = [](Blueprint* bp) -> vec2i {
		//Repair core hexes first
		unsigned sysCnt = (unsigned)bp->design->subsystems.size();
		for(unsigned i = 0; i < sysCnt; ++i) {
			auto& sys = bp->design->subsystems[i];
			auto& status = *bp->getSysStatus(i);

			if(sys.type->hasCore && status.status == ES_Ended) {
				HexStatus* stat = bp->getHexStatus(sys.core.x, sys.core.y);
				if(stat && stat->hp < 255 && !(stat->flags & (HF_NoHP | HF_NoRepair)))
					return vec2i(sys.core);
			}
		}

		//Search randomly
		unsigned hexCnt = bp->design->usedHexCount;
		unsigned index = randomi(0, hexCnt-1);
		for(unsigned i = 0; i < hexCnt; ++i, index = (index+1) % hexCnt) {
			vec2u hex = bp->design->hexes[i];
			HexStatus* stat = bp->getHexStatus(hex.x, hex.y);
			if(stat && stat->hp < 255 && !(stat->flags & (HF_NoHP | HF_NoRepair)))
				return vec2i(hex);
		}

		return vec2i(-1, -1);
	};

	vec2u gridSize = design->hull->gridSize;
	if((unsigned)repairingHex.x >= gridSize.x || (unsigned)repairingHex.y >= gridSize.y) {
		//Find a new hex to be repairing
		repairingHex = findRepairHex(this);
	}

	while(true) {
		if((unsigned)repairingHex.x >= gridSize.x || (unsigned)repairingHex.y >= gridSize.y)
			return amount;

		HexStatus* stat = getHexStatus(repairingHex.x, repairingHex.y);
		if(!stat) {
			repairingHex = vec2i(-1, -1);
			return amount;
		}

		if(stat->hp < 255 && !(stat->flags & (HF_NoHP | HF_NoRepair)))
			amount = repair(obj, vec2u(repairingHex), amount);

		if(currentHP >= design->totalHP) {
			repairingHex = vec2i(-1, -1);
			currentHP = design->totalHP;
			for(unsigned i = 0; i < 4; ++i)
				quadrantHP[i] = design->quadrantTotalHP[i];
			return amount;
		}

		if(amount > 0.0) {
			repairingHex = findRepairHex(this);
			continue;
		}
		else {
			return 0.0;
		}
	}
}

double Blueprint::repair(Object* obj, const vec2u& position, double amount) {
	if(!design)
		return amount;

	int index = design->grid[position];
	if(index < 0)
		return amount;

	HexStatus* hexPtr = getHexStatus(position.x, position.y);
	if(!hexPtr)
		return amount;
	HexStatus& hex = *hexPtr;

	auto& sys = design->subsystems[index];
	SysStatus& status = subsystems[index];
	int hexIndex = design->hexIndex[position];
	const float* hp = sys.hexVariable(HV_HP, hexIndex);

	if(!hp)
		return amount;
	if(*hp <= 0.f)
		return 0.0;

	//Check if it needs any repair at all
	if(hex.hp == 255)
		return amount;

	//Figure out how much damage to deal
	double hexDam = *hp * (1.0 - ((double)hex.hp / 255.0)) * hpFactor;
	double repair = std::min(amount, hexDam);
	if(repair <= 0.0)
		return amount;

	double repPts, fracPt = modf(repair * (255.0 / (double)*hp) / hpFactor, &repPts);

	//Directly deal any full damage
	unsigned char relative = (unsigned char)repPts;

	//If there is a significant fractional
	//component, use randomness
	if(fracPt > 0.001 && relative < 255)
		if(randomd() <= fracPt)
			relative += 1;

	//All the repair was randomed out
	if(relative == 0)
		return 0.0;

	//Modify the hex's hp
	short prevHP = hex.hp;
	hex.hp = (unsigned char)std::min(255, (short)hex.hp + (short)relative);
	relative = (hex.hp - prevHP);
	hpDelta = true;

	amount -= repair;
	double change = relative * (double)*hp / 255.0;
	currentHP = std::min(currentHP + change, design->totalHP);

	unsigned quadrant = design->getQuadrant(position);
	quadrantHP[quadrant] = std::min(currentHP + change, design->quadrantTotalHP[quadrant]);

	//Inform the subsystem
	if(hex.flags & HF_Destroyed && hex.hp > 0) {
		hex.flags &= ~HF_Destroyed;
		status.workingHexes += 1;
		--destroyedHexes;

		//Notify the effects that a hex was destroyed
		EffectEvent ef;
		ef.obj = obj;
		ef.source = index;

		ef.partiality = (float)status.workingHexes / (float)sys.hexes.size();
		ef.efficiency = ef.partiality * (float)shipEffectiveness;

		sys.call(EH_Change, ef);
		++statusID;

		//Notify the module
		auto* mod = sys.modules[hexIndex];

		if(mod->scr_onEnable) {
			EffectEvent evt;
			evt.obj = obj;
			evt.source = index;

			mod->onEnable(evt, position);
		}

		//Reactivate subsystem if needed
		if(mod->vital || status.workingHexes == 1) {
			bool hasAllVital = true;
			size_t hexCnt = sys.hexes.size();

			for(size_t i = 0; i < hexCnt; ++i) {
				if(sys.modules[i]->vital) {
					HexStatus* otherStatus = getHexStatus(sys.hexes[i].x, sys.hexes[i].y);
					if(otherStatus && otherStatus->flags & HF_Destroyed) {
						hasAllVital = false;
						break;
					}
				}
			}

			if(hasAllVital) {
				status.status = ES_Active;
				sys.call(EH_Start, ef);
			}
		}
	}

	if(amount < 0.0001)
		return 0.0;
	return amount;
}

void Blueprint::sendDetails(Object* obj, net::Message& msg) {
	if(!design || !design->owner) {
		msg.write0();
		return;
	}
	msg.write1();
	msg << design->owner->id;
	msg.writeSmall(design->id);

	//Sync subsystem status
	for(unsigned i = 0; i < design->subsystems.size(); ++i) {
		auto& ss = subsystems[i];
		if(ss.status == ES_Active) {
			msg.write1();
			continue;
		}

		msg.write0();
		msg << ss.status;
	}

	//Sync hex status
	for(unsigned i = 0; i < design->usedHexCount; ++i) {
		auto& hs = hexes[i];
		if(hs.hp == 255 && hs.flags == HF_Active) {
			msg.write1();
			continue;
		}
		if(hs.hp == 0 && hs.flags == HF_Destroyed) {
			msg.write0();
			msg.write1();
			continue;
		}

		msg.write0();
		msg.write0();
		if(hs.flags == HF_Active) {
			msg.write1();
		}
		else {
			msg.write0();
			msg << hs.flags;
		}

		msg << hs.hp;
	}

	//Sync subsystem states
	for(unsigned i = 0; i < design->stateCount; ++i) {
		switch(states[i].type) {
			case BT_Int:
				msg << states[i].integer;
			break;
			case BT_Double: {
				float val = (float)states[i].decimal;
				msg << val;
			} break;
			case BT_Bool:
				msg.writeBit(states[i].boolean);
			break;
		}
	}

	//Sync effector states
	for(unsigned i = 0; i < design->effectorStateCount; ++i) {
		float val = (float)effectorStates[i];
		msg << val;
	}
}

void Blueprint::recvDetails(Object* obj, net::Message& msg) {
	unsigned char ownerID;

	if(!msg.readBit())
		return;

	++statusID;

	msg >> ownerID;
	unsigned designID = msg.readSmall();

	if(!design || designID != design->id) {
		Empire* owner = Empire::getEmpireByID(ownerID);
		if(!owner)
			return;
		design = owner->getDesign(designID);
		if(!design)
			return;

		create(obj, design);
	}

	destroyedHexes = 0;

	//Sync subsystem status
	for(size_t i = 0; i < design->subsystems.size(); ++i) {
		auto& ss = subsystems[i];
		ss.workingHexes = (unsigned short)design->subsystems[i].hexes.size();

		if(msg.readBit()) {
			ss.status = ES_Active;
			continue;
		}

		msg >> ss.status;
	}

	//Sync hex status
	for(unsigned i = 0; i < design->usedHexCount; ++i) {
		auto& hs = hexes[i];
		if(msg.readBit()) {
			hs.hp = 255;
			hs.flags = HF_Active;
			continue;
		}
		if(msg.readBit()) {
			hs.hp = 0;
			hs.flags = HF_Destroyed;
		}
		else {
			if(msg.readBit())
				hs.flags = HF_Active;
			else
				msg >> hs.flags;
			msg >> hs.hp;
		}

		if(hs.flags & HF_Destroyed) {
			vec2u pos = design->hexes[i];
			destroyedHexes += 1;
			auto* ss = getSysStatus(pos.x, pos.y);
			if(ss)
				ss->workingHexes -= 1;
		}
	}

	//Sync subsystem states
	for(unsigned i = 0; i < design->stateCount; ++i) {
		switch(states[i].type) {
			case BT_Int:
				msg >> states[i].integer;
			break;
			case BT_Double: {
				float val = 0.f;
				msg >> val;
				states[i].decimal = val;
			} break;
			case BT_Bool:
				states[i].boolean = msg.readBit();
			break;
		}
	}

	//Sync effector states
	for(unsigned i = 0; i < design->effectorStateCount; ++i) {
		float val = 0.f;
		msg >> val;
		effectorStates[i] = val;
	}
}

bool Blueprint::sendDelta(Object* obj, net::Message& msg) {
	if(!design)
		return false;
	if(!designChanged && !hpDelta)
		return false;

	hpDelta = false;
	msg.write1();

	msg.writeBit(designChanged);
	if(designChanged) {
		designChanged = false;
		msg.write(design->owner->id);
		msg.writeSmall(design->id);
	}

	//Sync subsystem status
	for(size_t i = 0; i < design->subsystems.size(); ++i) {
		auto& ss = subsystems[i];
		if(ss.status == ES_Active) {
			msg.write1();
			continue;
		}

		msg.write0();
		msg << ss.status;
	}

	//Sync hex status
	for(unsigned i = 0; i < design->usedHexCount; ++i) {
		auto& hs = hexes[i];
		if(hs.hp == 255 && hs.flags == HF_Active) {
			msg.write1();
			continue;
		}
		if(hs.hp == 0 && hs.flags == HF_Destroyed) {
			msg.write0();
			msg.write1();
			continue;
		}

		msg.write0();
		msg.write0();
		msg << hs.hp;
	}

	//Sync effectiveness
	if(shipEffectiveness != 1.f) {
		msg.write1();
		msg.writeFixed(shipEffectiveness, 0.0, 50.0, 16);
	}
	else {
		msg.write0();
	}

	//Sync hpFactor
	if(hpFactor != 1.f) {
		msg.write1();
		msg.writeFixed(hpFactor, 0.0, 50.0, 16);
	}
	else {
		msg.write0();
	}

	//Sync removedHP
	if(removedHP != 0.f) {
		msg.write1();
		msg.writeFixed(removedHP, 0.0, design->totalHP, 16);
	}
	else {
		msg.write0();
	}

	//Sync current HP value
	//msg.writeFixed(currentHP, 0, design->totalHP, 16);

	//Repairing hex
	if(repairingHex.x >= 0 && repairingHex.y >= 0) {
		msg.write1();
		msg.writeSmall(repairingHex.x);
		msg.writeSmall(repairingHex.y);
	}
	else {
		msg.write0();
	}

	return true;
}

void Blueprint::recvDelta(Object* obj, net::Message& msg) {
	if(!design)
		return;
	statusID += 1;

	if(msg.readBit()) {
		unsigned char empID;
		msg >> empID;
		unsigned dsgID = msg.readSmall();

		Empire* emp = Empire::getEmpireByID(empID);
		create(obj, emp->getDesign(dsgID));
		assert(design != nullptr);
	}

	destroyedHexes = 0;

	//Sync subsystem status
	for(size_t i = 0; i < design->subsystems.size(); ++i) {
		auto& ss = subsystems[i];
		ss.workingHexes = (unsigned)design->subsystems[i].hexes.size();

		if(msg.readBit()) {
			ss.status = ES_Active;
			continue;
		}

		msg >> ss.status;
	}

	//Sync hex status
	double newHP = 0;
	double newQuadHP[4] = {0.0, 0.0, 0.0, 0.0};
	for(unsigned i = 0; i < design->usedHexCount; ++i) {
		vec2u pos = design->hexes[i];
		auto& hs = hexes[i];

		if(msg.readBit()) {
			hs.hp = 255;
			hs.flags = HF_Active;
		}
		else {
			if(msg.readBit()) {
				hs.hp = 0;
				hs.flags = HF_Destroyed;
			}
			else {
				msg >> hs.hp;
			}

			if(hs.flags & HF_Destroyed) {
				destroyedHexes += 1;
				auto* ss = getSysStatus(pos.x, pos.y);
				if(ss)
					ss->workingHexes -= 1;
			}
		}

		int sysIndex = design->grid[pos];
		if(sysIndex >= 0) {
			int hexIndex = design->hexIndex[pos];
			const float* ptr = design->subsystems[sysIndex].hexVariable(HV_HP, hexIndex);
			if(ptr != nullptr) {
				double curHP = double(hs.hp) / 255.0 * (*ptr);
				newHP += curHP;
				newQuadHP[design->getQuadrant(pos)] += curHP;
			}
		}
	}
	currentHP = newHP;
	for(unsigned i = 0; i < 4; ++i)
		quadrantHP[i] = newQuadHP[i];

	//Sync effectiveness
	if(msg.readBit())
		shipEffectiveness = msg.readFixed(0.0, 50.0, 16);
	else
		shipEffectiveness = 1.f;

	//Sync hpFactor
	if(msg.readBit())
		hpFactor = msg.readFixed(0.0, 50.0, 16);
	else
		hpFactor = 1.f;

	//Sync removedHP
	if(msg.readBit())
		removedHP = msg.readFixed(0.0, design->totalHP, 16);
	else
		removedHP = 0.f;

	//Read current hp value
	//currentHP = msg.readFixed(0, design->totalHP, 16);

	//Repairing hex
	if(msg.readBit()) {
		repairingHex.x = msg.readSmall();
		repairingHex.y = msg.readSmall();
	}
	else {
		repairingHex = vec2i(-1, -1);
	}
}

namespace scripts {
	extern SaveMessage& loadObject(SaveMessage& msg, Object** obj);
	extern SaveMessage& saveObject(SaveMessage& msg, Object* obj);
};

void Blueprint::save(Object* obj, SaveMessage& file) {
	file << design->owner->id << design->id;
	file << currentHP << shipEffectiveness;
	file << repairingHex << holdFire;
	file << hpFactor << removedHP;

	file.write(hexes,sizeof(HexStatus) * design->usedHexCount);
	file.write(subsystems,sizeof(SysStatus) * (unsigned)design->subsystems.size());
	file.write(states,sizeof(BasicType) * design->stateCount);
	file.write(effectorStates,sizeof(double) * design->effectorStateCount);

	for(unsigned i = 0; i < design->effectorCount; ++i) {
		scripts::saveObject(file, effectorTargets[i].target);
		file << effectorTargets[i].flags;
		file << effectorTargets[i].tracking;
		file << effectorTargets[i].hits;
	}

	EffectEvent event;
	event.obj = obj;
	for(unsigned i = 0; i < design->subsystems.size(); ++i)
		design->subsystems[i].save(event, file);
}

void Blueprint::load(Object* obj, SaveMessage& file) {
	try {
		unsigned char dsgnOwner;
		file >> dsgnOwner;
		if(Empire* emp = Empire::getEmpireByID(dsgnOwner)) {
			int dsgnID;
			file >> dsgnID;
			design = emp->getDesign(dsgnID);
			if(!design)
				throw SaveFileError("Invalid design");
		}
		else {
			throw SaveFileError("Invalid design owner");
		}
		file >> currentHP >> shipEffectiveness;
		file >> repairingHex;

		if(file >= SFV_0017)
			file >> holdFire;
		if(file >= SFV_0021)
			file >> hpFactor;
		if(file >= SFV_0022)
			file >> removedHP;

		hexes = new HexStatus[design->usedHexCount];
		file.read(hexes,sizeof(HexStatus) * design->usedHexCount);

		subsystems = new SysStatus[design->subsystems.size()];
		file.read(subsystems,sizeof(SysStatus) * (unsigned)design->subsystems.size());

		states = new BasicType[design->stateCount];
		file.read(states,sizeof(BasicType) * design->stateCount);

		effectorStates = new double[design->effectorStateCount];
		file.read(effectorStates,sizeof(double) * design->effectorStateCount);

		effectorTargets = new EffectorTarget[design->effectorCount];
		for(unsigned i = 0; i < design->effectorCount; ++i) {
			effectorTargets[i].target = nullptr;
			scripts::loadObject(file, &effectorTargets[i].target);
			file >> effectorTargets[i].flags;
			file >> effectorTargets[i].tracking;
			file >> effectorTargets[i].hits;
		}

		data = new CScriptAny*[design->dataCount];
		for(unsigned i = 0, cnt = design->dataCount; i < cnt; ++i)
			data[i] = new CScriptAny(devices.scripts.server->engine);

		EffectEvent event;
		event.obj = obj;
		for(unsigned i = 0; i < design->subsystems.size(); ++i)
			design->subsystems[i].load(event, file);

		for(unsigned i = 0; i < 4; ++i)
			quadrantHP[i] = 0.0;
		for(unsigned i = 0; i < design->usedHexCount; ++i) {
			vec2u pos = design->hexes[i];
			auto* hs = getHexStatus(pos.x, pos.y);
			if(hs == nullptr)
				continue;
			int sysIndex = design->grid[pos];
			if(sysIndex >= 0) {
				int hexIndex = design->hexIndex[pos];
				const float* ptr = design->subsystems[sysIndex].hexVariable(HV_HP, hexIndex);
				if(ptr != nullptr) {
					double curHP = double(hs->hp) / 255.0 * (*ptr);
					quadrantHP[design->getQuadrant(pos)] += curHP;
				}
			}
		}
	}
	catch(net::MessageReadError) {
		throw SaveFileError("Unexpected eof");
	}
}
