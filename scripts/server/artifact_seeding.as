import saving;
import object_creation;
import statuses;
from statuses import StatusHook;
from map_generation import generatedGalaxies, GalaxyData;
from empire import Creeps;
import systems;
import system_pathing;
import artifacts;
import Artifact@ createArtifact(const vec3d&, const ArtifactType@, Region@ region = null) from "objects.Artifact";
import bool getCheatsEverOn() from "cheats";

locked_int ArtifactCount = 0;
double storedEnergy = 0.0;

const double SPAWN_OFFSET = 1000.0;
const double MOVE_OFFSET = 500.0;
const double MOVE_VARIANCE = 200.0;
const double ARTIF_OFFSET = 350.0;
const double ARTIF_VARIANCE = 50.0;

void tick(double time) {
	double factor = double(systemCount) * config::TARGET_ARTIFACTS_PER_SYSTEM;
	double count = ArtifactCount.value;
	if(count != 0)
		factor /= count;

	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		Empire@ other = getEmpire(i);
		storedEnergy += other.EnergyIncome * time * factor * other.EnergyEfficiency;
	}

	if(storedEnergy >= config::ENERGY_PER_SEEDSHIP) {
		storedEnergy = 0.0;
		Ship@ ship = createShip(vec3d(1e10, 1e10, 1e10),
			Creeps.getDesign("Seed Ship"), Creeps, free = true);
		ship.addStatus(getStatusID("SeedShip"));
	}
}

void save(SaveFile& file) {
	file << ArtifactCount;
	file << storedEnergy;
}

void load(SaveFile& file) {
	if(file >= SV_0026) {
		file >> ArtifactCount;
		file >> storedEnergy;
	}
}

//SeedShip()
// This behaves as a seed ship.
class SeedData {
	array<uint> targets;
};

class SeedShip : StatusHook {
	void onCreate(Object& obj, Status@ status, any@ data) override {
		SeedData seed;
		data.store(@seed);

		//Find target empire
		Empire@ targEmp;
		double totalGen = 0.0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			totalGen += other.EnergyIncome;
		}

		double roll = randomd(0.0, totalGen);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			@targEmp = other;
			double gen = targEmp.EnergyIncome;
			if(roll <= gen)
				break;
			roll -= gen;
		}

		//Find target system
		DataList@ objs = targEmp.getPlanets();
		array<Planet@> planets;
		Object@ rec;
		while(receive(objs, rec)) {
			Planet@ pl = cast<Planet>(rec);
			if(pl is null)
				continue;
			planets.insertLast(pl);
		}

		if(planets.length == 0) {
			obj.destroy();
			return;
		}

		Planet@ targPl = planets[randomi(0, planets.length - 1)];
		SystemDesc@ targSys = getSystem(targPl.region);

		if(targSys is null) {
			obj.destroy();
			return;
		}

		//Find the target galaxy
		const GalaxyData@ targGlx;
		for(uint i = 0, cnt = generatedGalaxies.length; i < cnt; ++i) {
			auto@ glx = generatedGalaxies[i];
			if(targSys.position.distanceTo(glx.origin) < glx.radius) {
				@targGlx = glx;
				break;
			}
		}

		if(targGlx is null) {
			obj.destroy();
			return;
		}

		//Create line for path
		vec3d offset = (targSys.position - targGlx.origin).normalized(targGlx.radius);
		vec3d startPos = targGlx.origin + offset;
		vec3d endPos = targGlx.origin - offset;

		//Find path start and end
		SystemDesc@ pathStart;
		double startDist = INFINITY;

		SystemDesc@ pathEnd;
		double endDist = INFINITY;

		for(uint i = 0, cnt = targGlx.systems.length; i < cnt; ++i) {
			auto@ other = targGlx.systems[i];
			double d = other.position.distanceToSQ(startPos);
			if(d < startDist) {
				startDist = d;
				@pathStart = other;
			}
			d = other.position.distanceToSQ(endPos);
			if(d < endDist) {
				endDist = d;
				@pathEnd = other;
			}
		}

		//Initial position
		vec3d prevPos = pathStart.position;
		prevPos += (startPos - prevPos).normalized(pathStart.radius + SPAWN_OFFSET);
		obj.teleportTo(prevPos);

		//Path towards target
		SystemPath path;
		path.generate(pathStart, targSys);

		array<SystemDesc@> visited;
		if(path.valid) {
			for(uint i = 0, cnt = path.pathSize; i < cnt; ++i) {
				auto@ other = path.pathNode[i];

				vec3d newPos = other.position;
				newPos += (prevPos - newPos).normalized(other.radius - MOVE_OFFSET) + random3d(0.0, MOVE_VARIANCE);
				obj.addMoveOrder(newPos, append=true);
				prevPos = newPos;

				if(other !is targSys)
					visited.insertLast(other);
			}
		}
		else {
			vec3d newPos = targSys.position;
			newPos += (prevPos - newPos).normalized(targSys.radius - MOVE_OFFSET) + random3d(0.0, MOVE_VARIANCE);
			obj.addMoveOrder(newPos, append=true);
			prevPos = newPos;
		}

		path.generate(targSys, pathEnd);
		if(path.valid) {
			for(uint i = 1, cnt = path.pathSize; i < cnt; ++i) {
				auto@ other = path.pathNode[i];
				vec3d newPos = other.position;
				newPos += (prevPos - newPos).normalized(other.radius - MOVE_OFFSET) + random3d(0.0, MOVE_VARIANCE);
				obj.addMoveOrder(newPos, append=true);
				prevPos = newPos;

				if(other !is targSys)
					visited.insertLast(other);
			}
		}

		vec3d newPos = pathEnd.position;
		newPos += (endPos - prevPos).normalized(pathEnd.radius + SPAWN_OFFSET);
		obj.addMoveOrder(newPos, append=true);

		seed.targets.insertLast(targSys.index);
		if(visited.length > 0) {
			for(uint i = 1, cnt = config::ARTIFACTS_PER_SEEDSHIP; i < cnt; ++i)
				seed.targets.insertLast(visited[randomi(0, visited.length-1)].index);
		}
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(obj.orderCount == 0) {
			playParticleSystem("SeedShipBoom", obj.position, obj.rotation, obj.radius, obj.visibleMask);
			obj.destroy();
			return false;
		}

		Region@ reg = obj.region;
		if(reg is null)
			return true;

		SystemDesc@ sys = getSystem(reg);
		if(sys is null)
			return true;

		SeedData@ seed;
		data.retrieve(@seed);

		for(uint i = 0, cnt = seed.targets.length; i < cnt; ++i) {
			if(seed.targets[i] == sys.index) {
				if(sys.position.distanceTo(obj.position) < sys.radius - ARTIF_OFFSET) {
					const ArtifactType@ type = getSeedArtifactType();
					auto@ artifact = createArtifact(obj.position + random3d(obj.radius + 1.0, ARTIF_VARIANCE), type);
					artifact.orbitAround(reg.position);
					seed.targets.removeAt(i);
				}
				break;
			}
		}

		return true;
	}

	void onObjectDestroy(Object& obj, Status@ status, any@ data) override {
		for(uint i = 0, cnt = config::ARTIFACTS_SEEDSHIP_DEATH; i < cnt; ++i) {
			const ArtifactType@ type = getSeedArtifactType();
			vec3d pos = obj.position + random3d(type.physicalSize * 1.5, type.physicalSize * 3.0);
			auto@ artifact = createArtifact(pos, type);
			if(obj.region !is null)
				artifact.orbitAround(obj.region.position);
		}
		
		if(obj.type == OT_Ship) {
			Empire@ killer = cast<Ship>(obj).getKillCredit();
			if(killer !is null && killer.valid && !getCheatsEverOn()) {
				if(killer is playerEmpire)
					unlockAchievement("ACH_SPILLED_SEED");
				else if(mpServer && killer.player !is null)
					clientAchievement(killer.player, "ACH_SPILLED_SEED");
			}
		}
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		SeedData@ seed;
		data.retrieve(@seed);

		uint cnt = seed.targets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			uint id = seed.targets[i];
			file << id;
		}
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		SeedData seed;
		data.store(@seed);

		uint cnt = 0;
		file >> cnt;
		seed.targets.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			uint id = 0;
			file >> id;
			seed.targets[i] = id;
		}
	}
};

class GravitarShip : StatusHook {
	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		if(obj.orderCount == 0 && randomi(0,10) == 0) {
			playParticleSystem("SeedShipBoom", obj.position, obj.rotation, obj.radius, obj.visibleMask);
			obj.destroy();
			return false;
		}
		return true;
	}
};
