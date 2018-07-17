#pragma once
#include "vec3.h"
#include "threads.h"
#include <stddef.h>

namespace scene {
	class Node;
};

struct MissileData {
	vec3d pos;
	double lastUpdate;
	vec3f vel;
	double aliveUntil;
};

class Effector;
class Object;
class SaveFile;

enum ProjType {
	PT_Bullet,
	PT_Beam,
	PT_Missile
};

enum ProjMode {
	PM_Normal,
	PM_OnlyHitsTarget,
	PM_PassthroughInvalid
};

struct Projectile {
	//NOTE: Velocity is reused to specify a beam's target
	vec3d position, velocity;

	double lastTick;

	vec3d* impact;
	const Effector* effector;
	Object* source, *target, *lastImpact;
	scene::Node* graphics;
	union {
		threads::SharedData<bool>* endNotice;
		threads::SharedData<MissileData>* missileData;
	};

	float lifetime;
	float scale;

	//radians per second of turning
	float tracking;

	//efficiency of the subsystem
	float efficiency;

	//recovery time in which nothing can be hit
	float recover;

	ProjType type;
	ProjMode mode;

	//Advances projectile and performs collision
	//Returns true if the projectile is dead
	bool tick(double time);

	Projectile(ProjType Type);
	~Projectile();

	static Projectile* load(SaveFile& file);
	void save(SaveFile& file);

	void* operator new(size_t size);
	void operator delete(void*);
};

void registerProjectile(Projectile* proj);
void initProjectiles();
void stopProjectiles();

void saveProjectiles(SaveFile& file);
void loadProjectiles(SaveFile& file);

void pauseProjectiles();
void resumeProjectiles();
