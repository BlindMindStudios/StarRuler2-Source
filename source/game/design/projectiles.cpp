#include "projectiles.h"
#include "line3d.h"
#include "main/references.h"
#include "processing.h"
#include "physics/physics_world.h"
#include "obj/object.h"
#include "empire.h"
#include "design/effector.h"
#include "threads.h"
#include "scene/node.h"
#include "scene/particle_system.h"
#include "memory/AllocOnlyPool.h"
#include "threads.h"
#include "obj/lock.h"
#include "scene/animation/anim_projectile.h"
#include "util/save_file.h"
#include "design/design.h"
#include "obj/blueprint.h"
#include "network/network_manager.h"
#include "ISound.h"
#include "ISoundDevice.h"
#include <climits>
#include <algorithm>

memory::AllocOnlyPool<Projectile,threads::Mutex> projPool(8192);

void initNewThread();
void cleanupThread();

struct ProjEffect : public ObjectMessage {
	Object* source;
	const Effector* effector;
	vec3d relImpact;
	float effectiveness;
	float partiality;
	float delay;

	ProjEffect(const Effector* fctr, Object* target, Object* src, vec3d relImpactPt, float eff, float part, float del) : ObjectMessage(target), source(src), effector(fctr), relImpact(relImpactPt), effectiveness(eff), partiality(part), delay(del) {
		source->grab();
		effector->grab();
	}

	~ProjEffect() {
		object->drop();
		source->drop();
		effector->drop();
	}

	void process() override {
		effector->triggerEffect(source, object, relImpact, effectiveness, partiality, delay);
	}
};

struct ProjImpactEffect : public scene::NodeEvent {
	const scene::ParticleSystemDesc* system;
	vec3d from, vel;
	float scale;
	float delay;

	ProjImpactEffect(scene::Node* parentNode, const scene::ParticleSystemDesc* sys, const vec3d& From, const vec3d& Vel, float Scale, float Delay) : NodeEvent(parentNode), system(sys), from(From), vel(Vel), scale(Scale), delay(Delay) {
	}

	void process() override {
		vec3d pos;
		quaterniond rot;
		if(node) {
			vec3d d = (from - node->abs_position).normalized();
			pos = (from - node->abs_position);
			rot = quaterniond::fromImpliedTransform(vec3d::front(), d);
		}
		else {
			pos = from;
		}
		auto* pSys = scene::playParticleSystem(system, node, pos, rot,  vel, scale, delay);
		if(pSys)
			pSys->drop();
	}

	~ProjImpactEffect() {
	}
};

double clamp(double v, double low, double high) {
	if(v <= low)
		return low;
	else if(v >= high)
		return high;
	else
		return v;
}

static inline double sqr(double x) {
	return x * x;
}

//Look for a new objec hostile to the owner
Object* findTarget(Empire* owner, const vec3d& position, double radius, const void* ofType = nullptr) {
	if(!owner)
		return nullptr;

	Object* obj = nullptr;

	devices.physics->findInBox(AABBoxd::fromCircle(position, radius), [&obj,owner,&position,radius,ofType](const PhysicsItem& item) {
		if(obj)
			return;
		if(item.type == PIT_Object) {
			Object* target = item.object;
			if(!target->isVisibleTo(owner) || !target->isValid())
				return;
			if(ofType && target->type != ofType)
				return;
			if(position.distanceToSQ(target->position) > (radius + target->radius) * (radius + target->radius))
				return;

			obj = target;
			obj->grab();
		}
	}, owner->hostileMask);

	return obj;
}

bool Projectile::tick(double time) {
	//Rotate to track the target
	if(type == PT_Missile) {
		if(target && target->isValid()) {
			if(recover <= 0.f) {
				vec3d dir = (target->position - position).normalized();
				vec3d projImpact = target->position + dir;
				if(target->type->blueprintOffset != 0) {
					auto* blueprint = (Blueprint*)(((size_t)target) + target->type->blueprintOffset);
					const Design* dsg = blueprint->design;

					if(dsg != nullptr) {
						vec3d impactOffset = target->rotation.inverted() * dir;
						projImpact = target->rotation * dsg->hull->getImpact(impactOffset, target->radius, true) + target->position;
					}
				}

				dir = (projImpact - position).normalized();
				double speed = velocity.getLength();
				vec3d vdir = velocity / speed;

				double angle = acos(clamp(vdir.dot(dir),-1,1)), rot = tracking * time;
				if(angle < rot) {
					velocity = dir * speed;
				}
				else if(angle >= pi * 0.9) {
					quaterniond dirq = quaterniond::fromImpliedTransform(vec3d::front(), dir);
					quaterniond vdirq = quaterniond::fromImpliedTransform(vec3d::front(), vdir);
					quaterniond result = vdirq.slerp(dirq, rot / angle);
					velocity = (result * vec3d::front()).normalized(speed);
				}
				else {//if(angle < 0.05) {
					//Lerp is a good enough approximation
					//   -- It really is not :( stupid missiles can't even turn 180 degrees
					velocity = vdir.interpolate(dir, rot / angle).normalized(speed);
				}

				if(graphics) {
					auto* anim = (scene::ProjectileAnim*)graphics->animator.ptr;
					anim->velocity = velocity;
				}
			}
		}
		else if(source && source->isValid()) {
			if(target) {
				auto* prevTarget = target;
				target = findTarget(source->owner, target->position, 50.0, target->type);
				prevTarget->drop();
			}
			else {
				target = findTarget(source->owner, position, 50.0);
			}

			//If we didn't quickly find a target, we die twice as fast
			if(target == 0 && !effector->type.pierces)
				lifetime *= 0.5f;
		}
		else {
			//Become a dummy when the target is already dead
			//Also live only half the remaining time
			lifetime *= 0.5f;
			if(target) {
				target->drop();
				target = 0;
			}
		}
	}
	else if(type == PT_Beam) {
		//Beams can't fire when the source is dead
		if(!source->isValid())
			return true;

		if(target) {
			if(target->isValid()) {
				if(tracking > 0) {
					vec3d targDir = (target->position - (source->position + position)).normalize();
					double range = velocity.getLength();

					vec3d curDir = velocity / range;

					double dot = std::max(std::min(targDir.dot(curDir), 1.0), -1.0);
					double angDiff = acos(dot);
					double track = tracking * time;

					if(angDiff <= track)
						velocity = targDir * range;
					else
						velocity = curDir.slerp(targDir,track/angDiff) * range;
				}
			}
			else {
				//Our current target is dead, find a new one
				auto* prevTarget = target;
				if(source)
					target = findTarget(source->owner, target->position, 50.0, target->type);
				else
					target = 0;
				prevTarget->drop();
			}
		}
	}

	line3dd line(position, vec3d());

	if(type != PT_Beam) {
		line.end = position + velocity * time;
	}
	else {
		line.start += source->position;
		line.end = line.start + velocity;
	}

	Object* other = 0;
	vec3d impactPt;

	double prevDistSQ = 0;
	double projScale = scale;

	//If our line still collides with our last impacted object, we can check for only intervening objects
	if(lastImpact && lastImpact->isValid()) {
		vec3d closePt = line.getClosestPoint(lastImpact->position,false);
		double distSQ = closePt.distanceToSQ(lastImpact->position);
		double width = lastImpact->radius + scale;
		if(distSQ <= width * width) {
			other = lastImpact;
			other->grab();
			impactPt = closePt - line.getDirection() * sqrt(width*width - distSQ);
			if(!effector || !effector->type.pierces)
				line.end = impactPt;
			prevDistSQ = closePt.distanceToSQ(line.start);
		}
	}

	if(mode != PM_OnlyHitsTarget) {
		if(mode == PM_PassthroughInvalid) {
			const Effector* eff = effector;
			Object* src = source;
			devices.physics->findInBox(AABBoxd(line, scale), [&other,&line,&prevDistSQ,&impactPt,projScale,eff,src](const PhysicsItem& item) {
				//if(item.type != PIT_Object)
				//	return;
				Object* obj = item.object;
				vec3d closePt = line.getClosestPoint(obj->position,false);
				double distSQ = closePt.distanceToSQ(obj->position);
				double width = obj->radius + projScale;
				if(distSQ <= width * width && (!eff || eff->canTarget(src, obj))) {
					double objDistSQ = closePt.distanceToSQ(line.start);
					if(!other || objDistSQ < prevDistSQ) {
						if(other)
							other->drop();
						other = obj;
						other->grab();
						prevDistSQ = objDistSQ;
						impactPt = closePt - line.getDirection() * sqrt(width*width - distSQ);
					}
				}
			}, source->owner ? (source->owner->hostileMask | 0x1) : ~0x0);
		}
		else {
			devices.physics->findInBox(AABBoxd(line, scale), [&other,&line,&prevDistSQ,&impactPt,projScale](const PhysicsItem& item) {
				//if(item.type != PIT_Object)
				//	return;
				Object* obj = item.object;
				vec3d closePt = line.getClosestPoint(obj->position,false);
				double distSQ = closePt.distanceToSQ(obj->position);
				double width = obj->radius + projScale;
				if(distSQ <= width * width) {
					double objDistSQ = closePt.distanceToSQ(line.start);
					if(!other || objDistSQ < prevDistSQ) {
						if(other)
							other->drop();
						other = obj;
						other->grab();
						prevDistSQ = objDistSQ;
						impactPt = closePt - line.getDirection() * sqrt(width*width - distSQ);
					}
				}
			}, source->owner ? (source->owner->hostileMask | 0x1) : ~0x0);
		}
	}
	else if(target && target->isValid()){
		vec3d closePt = line.getClosestPoint(target->position,false);
		double distSQ = closePt.distanceToSQ(target->position);
		double width = target->radius + projScale;
		if(distSQ <= width * width) {
			if(other)
				other->drop();
			other = target;
			other->grab();
			impactPt = closePt - line.getDirection() * sqrt(width*width - distSQ);
		}
	}

	if(other != nullptr && other->type->blueprintOffset != 0) {
		auto* blueprint = (Blueprint*)(((size_t)other) + other->type->blueprintOffset);
		const Design* dsg = blueprint->design;

		if(dsg != nullptr) {
			vec3d impactOffset = impactPt - other->position;
			impactOffset = other->rotation.inverted() * impactOffset;
			impactPt = other->rotation * dsg->hull->getImpact(impactOffset, other->radius, type == PT_Beam) + other->position;
		}
	}

	if(recover > 0.f) {
		if(other && other == lastImpact) {
			other->drop();
			other = nullptr;
		}
		recover -= time;
		if(recover <= 0.f)
			recover = 0.f;
	}

	if(other) {
		if(impact)
			*impact = impactPt;
		if(type == PT_Beam || effector->type.pierces) {
			other->grab();
			if(lastImpact)
				lastImpact->drop();
			lastImpact = other;
		}

		auto* player = Empire::getPlayerEmpire();

		if(effector) {
			if(player && other->isVisibleTo(player)) {
				if(auto* sfx = effector->type.skins[effector->skinIndex].impact_sound) {
					if(sfx->loaded && !audio::disableSFX) {
						auto* sound = devices.sound->play3D(sfx->source, snd_vec(other->position), false, true);
						if(sound) {
							if(source)
								sound->setVolume((float)((scale + 1.0) / (scale + 7.0)));
							sound->setPitch((float)randomd(0.95,1.05));
							float dist = other->position.distanceTo(devices.render->cam_pos);
							float lo = dist / (dist + scale * 500.0);
							if(lo > 0.05)
								sound->setLowPass(lo);
							sound->resume();
						}
					}
				}
			}
		}

		LockGroup* lockGroup = other->lockGroup;
		float delay = 0.f;
		if(effector && lockGroup) {
			if(type == PT_Missile && missileData) {
				double speed = velocity.getLength();
				delay = impactPt.distanceTo(position) / speed * 1.5f;
			}

			if(effector->type.skins[effector->skinIndex].impact && (!player || other->isVisibleTo(player)))
				scene::queueNodeEvent(new ProjImpactEffect(other->node, effector->type.skins[effector->skinIndex].impact, impactPt, other->velocity, (float)sqrt(effector->relativeSize * (source ? source->radius : 1.0)), delay));
			if(!devices.network->isClient)
				lockGroup->addMessage(new ProjEffect(effector, other, source, impactPt - other->position, efficiency, type == PT_Beam ? (float)time : 1.f, delay));
			else
				other->drop();
		}
		else {
			other->drop();
		}

		if(type != PT_Beam) {
			if(effector && effector->type.pierces) {
				recover = effector->type.recoverTime;
				if(target && other == target) {
					target->drop();
					target = nullptr;
				}
			}
			else {
				if(type == PT_Missile && missileData) {
					auto& data = **missileData;
					double gameTime = devices.driver->getGameTime();
					double speed = velocity.getLength();

					data.lastUpdate = gameTime;
					data.aliveUntil = gameTime + delay;
					data.pos = impactPt;
					data.vel = vec3f((impactPt - position).normalized(speed));
				}
				return true;
			}
		}
	}
	else if(impact) {
		*impact = line.end;
	}

	if(type != PT_Beam) {
		position = line.end;
		if(type == PT_Missile && missileData) {
			auto& data = **missileData;
			data.lastUpdate = devices.driver->getGameTime();
			data.pos = position;
			data.vel = vec3f(velocity);
		}
	}
	lifetime -= (float)time;
	return lifetime <= 0;
}

void* Projectile::operator new(size_t size) {
	return projPool.alloc();
}

void Projectile::operator delete(void* p) {
	return projPool.dealloc((Projectile*)p);
}

Projectile::Projectile(ProjType Type) : lastTick(devices.driver->getGameTime()), source(0), target(0), lastImpact(0), graphics(0), type(Type), impact(0), efficiency(1.f), endNotice(0), mode(PM_Normal), recover(0.f) {
}

Projectile::~Projectile() {
	if(graphics) {
		graphics->markForDeletion();
		graphics->drop();
	}

	if(type != PT_Missile) {
		if(endNotice) {
			**endNotice = true;
			endNotice->drop();
		}
	}
	else {
		if(missileData) {
			if((*missileData)->aliveUntil < 0)
				(*missileData)->aliveUntil = 0;
			missileData->drop();
		}
	}
	
	if(source)
		source->drop();
	if(target)
		target->drop();
	if(lastImpact)
		lastImpact->drop();
	if(effector)
		effector->drop();
}

extern double frameTime_s;
Projectile* Projectile::load(SaveFile& file) {
	const Effector* efftr = nullptr;

	unsigned char empID;
	int dsgId;
	unsigned subsysIndex, effectorIndex, effId;
	if((bool)file) {
		empID = file;
		if(empID == INVALID_EMPIRE)
			return 0;

		dsgId = file;
		subsysIndex = file;
		effectorIndex = file;

		Empire* dsgOwner = Empire::getEmpireByID(empID);
		const Design* dsg = dsgOwner->getDesign(dsgId);
		if(dsg == nullptr || subsysIndex >= dsg->subsystems.size() || effectorIndex >= dsg->subsystems[subsysIndex].type->effectors.size()) {
			//throw "Invalid projectile effector.";
			// Just cancel the projectile later so we can continue the load.
		}
		else {
			efftr = &dsg->subsystems[subsysIndex].effectors[effectorIndex]; //No refcounting on design effectors
		}
	}
	else {
		effId = file;
		efftr = getEffector(effId); //Reference is transfered to projectile
	}

	//Find effector
	Projectile* proj = new Projectile((ProjType)file.read<unsigned char>());
	proj->effector = efftr;

	//Load data
	file >> proj->lastTick;
	file >> proj->lifetime;
	proj->source = file.readExistingObject();
	proj->target = file.readExistingObject();
	file >> proj->position;
	file >> proj->velocity;
	file >> proj->scale;
	file >> proj->tracking;
	file >> proj->efficiency;

	//Actually screw this, these things cause nothing but problems
	delete proj;
	return 0;

	if(!proj->source || !proj->effector) {
		//This can happen if the object that fired the projectile
		//was already destroyed when the save occured. We have no way
		//of instantiating these or their effects at the moment, because
		//we know absolutely nothing about the source.

		//TODO: Preserve these in some way, they can still impact and matter
		//quite a bit.
		delete proj;
		return 0;
	}

	//TODO: The effects are non-trivial, figure out how to restore them
	//Create graphics
	/*proj->graphics = proj->effector->type.createGraphics(proj->effector, proj->scale);
	if(!proj->graphics) {
		delete proj;
		throw "Invalid projectile effector graphics.";
	}

	proj->graphics->position = proj->position;
	proj->graphics->rebuildTransformation();
	proj->graphics->animator = new scene::ProjectileAnim(proj->velocity, 1.f);

	registerProjectile(proj);
	proj->graphics->queueReparent(devices.scene);
	return proj;*/
	registerProjectile(proj);
	return proj;
}

void Projectile::save(SaveFile& file) {
	if(effector && effector->effectorId != 0) {
		file << false;
		file << effector->effectorId;
	}
	else {
		file << true;
		if(!effector || !effector->inDesign || !effector->inDesign->owner) {
			file << INVALID_EMPIRE;
			return;
		}

		file << effector->inDesign->owner->id;
		file << effector->inDesign->id;
		file << effector->subsysIndex;
		file << effector->effectorIndex;
	}

	file << (unsigned char)type;
	file << lastTick;
	file << lifetime;
	file << source;
	file << target;
	file << position;
	file << velocity;
	file << scale;
	file << tracking;
	file << efficiency;
}

threads::Mutex projAddLock, projfillLock;
threads::Signal activeProjThreads;
threads::atomic_int pull_index, push_index, processed_count;
std::vector<double> projThreadTimes;

std::vector<Projectile*>* source = new std::vector<Projectile*>, *dest = new std::vector<Projectile*>;
std::vector<Projectile*> queuedProjs;

static void fillProjectiles() {
	dest->resize(push_index);

	if(!queuedProjs.empty()) {
		projAddLock.lock();
		dest->insert(dest->end(), queuedProjs.begin(), queuedProjs.end());
		queuedProjs.clear();
		projAddLock.release();
	}

	std::swap(source, dest);
	dest->resize(source->size());

	processed_count = 0;
	push_index = 0;
	pull_index = 0;
}

volatile bool ProjectilesActive = false;
volatile bool EndProjectiles = false;
volatile bool PauseProjectiles = false;
volatile bool ProjectilesPaused = false;
class ProcessProjectiles : public processing::Action {
	bool host, active;
public:
	ProcessProjectiles(bool Host) : host(Host), active(true) {
	}

	~ProcessProjectiles() {
		//This happens when the game is ending. We may not complete an entire cycle at the right time.
		if(host)
			ProjectilesActive = false;
		else if(active)
			activeProjThreads.signalDown();
	}

	bool run() {
		if(host && activeProjThreads.check(0)) {
			if(EndProjectiles)
				return true;
			ProjectilesActive = true;

			if(PauseProjectiles) {
				ProjectilesActive = false;
				ProjectilesPaused = true;
				return false;
			}
			else if(ProjectilesPaused) {
				ProjectilesPaused = false;
			}
			else {
				fillProjectiles();
			}

			if(!source->empty()) {
				activeProjThreads.signal(4);
				for(unsigned i = 0; i < 4; ++i)
					processing::queueAction(new ProcessProjectiles(false));
			}
			else {
				ProjectilesActive = false;
				return false;
			}
		}

		double curTime = devices.driver->getGameTime();
		unsigned tickMax = 1000;
		while(tickMax--) {
			int index = pull_index++;
			if(index >= (int)source->size()) {
				if(host) {
					ProjectilesActive = false;
					return false;
				}
				else {
					active = false;
					activeProjThreads.signalDown();
					return true;
				}
			}

			//Take the next projectile, tick it, and put it on the output stack (unless it needs deleted)
			Projectile* proj = source->at(index);
			double t = curTime - proj->lastTick;

			if(t < 0.125) {
				int outIndex = push_index++;
				dest->at(outIndex) = proj;
			}
			else {
				if(!proj->tick(t)) {
					proj->lastTick = curTime;
					int outIndex = push_index++;
					dest->at(outIndex) = proj;
				}
				else {
					delete proj;
				}
			}
		}

		return false;
	}
};

void registerProjectile(Projectile* proj) {
	projAddLock.lock();
	queuedProjs.push_back(proj);
	projAddLock.release();
}

void initProjectiles() {
	EndProjectiles = false;
	PauseProjectiles = false;
	processing::queueAction(new ProcessProjectiles(true));
}

void stopProjectiles() {
	EndProjectiles = true;
	while(ProjectilesActive)
		threads::sleep(1);
	activeProjThreads.wait(0);
	source->clear(); source->shrink_to_fit();
	dest->clear(); dest->shrink_to_fit();
	for(auto i = queuedProjs.begin(), end = queuedProjs.end(); i != end; ++i)
		delete *i;
	queuedProjs.clear();
	pull_index = 0;
	push_index = 0;
	processed_count = 0;
}

void saveProjectiles(SaveFile& file) {
	unsigned cnt = (unsigned)(queuedProjs.size() + push_index);
	file << cnt;

	cnt = (unsigned)queuedProjs.size();
	for(unsigned i = 0; i < cnt; ++i)
		queuedProjs[i]->save(file);

	cnt = (unsigned)push_index;
	for(unsigned i = 0; i < cnt; ++i)
		(*dest)[i]->save(file);
}

void loadProjectiles(SaveFile& file) {
	unsigned cnt = file;
	for(unsigned i = 0; i < cnt; ++i)
		Projectile::load(file);
}

void pauseProjectiles() {
	PauseProjectiles = true;
	if(!ProjectilesActive)
		return;
	activeProjThreads.wait(0);
	while(!ProjectilesPaused && ProjectilesActive)
		threads::sleep(1);
}

void resumeProjectiles() {
	PauseProjectiles = false;
}
