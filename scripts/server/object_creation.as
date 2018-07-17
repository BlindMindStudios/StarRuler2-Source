import orbitals;
import resources;
import regions.regions;
from designs import getDesignMesh;
from civilians import getCivilianName;

//Base acceleration of a colony ship
const double COLONYSHIP_BASE_ACCEL = 5.5;

const double shipVolumePower = 2.5;
const double stationRadiusFactor = 1.3;

ColonyShip@ createColonizer(Object& from, Object& to, double population, double accMod) {
	ObjectDesc colDesc;
	colDesc.type = OT_ColonyShip;
	colDesc.name = locale::COLONY_SHIP;
	colDesc.radius = 4.0 * pow(population / 0.0625, 1.0 / 3.0);
	colDesc.delayedCreation = true;
	if(from.owner.ColonizerName.length != 0)
		colDesc.name = from.owner.ColonizerName;
	
	quaterniond rot = quaterniond_fromVecToVec(vec3d_front(), to.position - from.position, vec3d_up());
	colDesc.position = from.position + rot * vec3d_front(colDesc.radius + from.radius);
	
	@colDesc.owner = from.owner;

	ColonyShip@ colShip = cast<ColonyShip>(makeObject(colDesc));
	colShip.Health = 1000.0 * population;
	@colShip.Target = to;
	@colShip.Origin = from;
	colShip.rotation = rot;
	colShip.CarriedPopulation = population;
	colShip.maxAcceleration = COLONYSHIP_BASE_ACCEL * accMod * from.owner.ModSpeed.value * from.owner.ColonizerSpeed;
	colShip.Health *= from.owner.ModHP.value;
	colShip.finalizeCreation();

	return colShip;
}

ColonyShip@ createColonizer(Empire@ owner, vec3d from, Object& to, double population, double accMod) {
	ObjectDesc colDesc;
	colDesc.type = OT_ColonyShip;
	colDesc.name = locale::COLONY_SHIP;
	colDesc.radius = 4.0 * pow(population / 0.0625, 1.0 / 3.0);
	colDesc.delayedCreation = true;
	if(owner.ColonizerName.length != 0)
		colDesc.name = owner.ColonizerName;
	
	@colDesc.owner = owner;
	colDesc.position = from;

	ColonyShip@ colShip = cast<ColonyShip>(makeObject(colDesc));
	colShip.Health = 1000.0 * population;
	@colShip.Target = to;
	colShip.rotation = quaterniond_fromVecToVec(vec3d_front(), to.position - from, vec3d_up());
	colShip.CarriedPopulation = population;
	colShip.maxAcceleration = COLONYSHIP_BASE_ACCEL * accMod * owner.ModSpeed.value * owner.ColonizerSpeed;
	colShip.Health *= owner.ModHP.value;
	colShip.finalizeCreation();

	return colShip;
}

Pickup@ createPickup(vec3d position, uint type, Empire@ owner) {
	ObjectDesc desc;
	desc.delayedCreation = true;
	desc.type = OT_Pickup;
	@desc.owner = owner;
	desc.position = position;
	desc.flags |= objNoCollide;
	desc.flags |= objNoDamage;

	Pickup@ obj = cast<Pickup>(makeObject(desc));
	obj.PickupType = type;
	return obj;
}

Ship@ createShip(vec3d position, const Design@ design, Empire@ owner, Object@ groupLeader = null, bool free = false, bool memorable = false) {
	ObjectDesc shipDesc;
	shipDesc.delayedCreation = true;
	shipDesc.type = OT_Ship;
	@shipDesc.owner = owner;
	shipDesc.name = design.name;
	if(design.hasTag(ST_Station))
		shipDesc.radius = stationRadiusFactor * pow(design.size,1.0/shipVolumePower) * design.hull.modelScale;
	else
		shipDesc.radius = pow(design.size,1.0/shipVolumePower) * design.hull.modelScale;
	shipDesc.position = position;
	if(memorable)
		shipDesc.flags |= objMemorable;
	
	MeshDesc shipMesh;
	getDesignMesh(owner, design, shipMesh);
	shipMesh.memorable = memorable;
	
	Object@ obj = makeObject(shipDesc);
	bindMesh(obj, shipMesh);
	
	Ship@ ship = cast<Ship>(obj);
	if(free)
		ship.isFree = true;
	ship.blueprint.create(obj, design);

	if(design.hasTag(ST_IsSupport)) {
		ship.activateSupportAI();
		ship.finalizeCreation();

		//Support ships don't provide sight
		ship.sightRange = 0;

		if(groupLeader !is null && groupLeader.valid
				&& groupLeader.owner is ship.owner && groupLeader.hasLeaderAI)
			groupLeader.registerSupport(ship);
	}
	else {
		ship.activateLeaderAI();
		if(design.hasTag(ST_Station)) {
			updateRegion(ship);
			ship.activateOrbit();
		}

		ship.finalizeCreation();
		ship.stopMoving(false, false);

		if(design.hasTag(ST_Station)) {
			ship.remakeStandardOrbit();
			ship.orbitSpin(60.0);
		}
	}

	return ship;
}

Ship@ createShip(Object& at, const Design@ design, Empire@ owner = null, Object@ groupLeader = null, bool detectLeader = true, bool free = false, bool move = true, bool forceLeader = false) {
	if(owner is null)
		@owner = at.owner;

	ObjectDesc shipDesc;
	shipDesc.delayedCreation = true;
	shipDesc.type = OT_Ship;
	@shipDesc.owner = owner;
	shipDesc.name = design.name;
	if(design.hasTag(ST_Station))
		shipDesc.radius = stationRadiusFactor * pow(design.size,1.0/shipVolumePower) * design.hull.modelScale;
	else
		shipDesc.radius = pow(design.size,1.0/shipVolumePower) * design.hull.modelScale;

	if(design.hasTag(ST_Satellite)) {
		Object@ spawnAt = at;
		if(groupLeader !is null && groupLeader.isPlanet && groupLeader.region is at.region)
			@spawnAt = groupLeader;
		if(spawnAt !is null && spawnAt.hasLeaderAI) {
			vec3d pos = at.position;
			double rad = at.getFormationRadius();
			vec2d offset = random2d(at.radius * 1.1 + shipDesc.radius + 1.0, 0.95 * rad);
			shipDesc.position = pos + vec3d(offset.x, randomd(rad*-0.2, rad*0.2), offset.y);
		}
		else {
			shipDesc.position = at.position + random3d(at.radius + shipDesc.radius + 0.75);
		}
	}
	else
		shipDesc.position = at.position + random3d(at.radius + shipDesc.radius + 0.75);
	
	MeshDesc shipMesh;
	getDesignMesh(owner, design, shipMesh);
	
	Object@ obj = makeObject(shipDesc);
	bindMesh(obj, shipMesh);
	
	Planet@ planet = cast<Planet>(at);
	Ship@ ship = cast<Ship>(obj);
	if(free)
		ship.isFree = true;
	ship.blueprint.create(obj, design);

	if(design.hasTag(ST_IsSupport)) {
		ship.activateSupportAI();
		if(design.hasTag(ST_Satellite))
			ship.forceLockTo(at);

		//Support ships don't provide sight
		ship.sightRange = 0;

		if(groupLeader !is null && groupLeader.valid
				&& groupLeader.owner is ship.owner && groupLeader.hasLeaderAI) {
			groupLeader.registerSupport(ship, force=forceLeader);
		}
		else if(detectLeader) {
			if(planet !is null)
				planet.registerSupport(ship, force=forceLeader);
			else if(at.hasLeaderAI)
				at.registerSupport(ship, force=forceLeader);
		}
	}
	else {
		ship.activateLeaderAI();

		if(move) {
			if(planet !is null) {
				vec2d pos = random2d(0.8 * planet.OrbitSize);
				ship.addMoveOrder(planet.position + vec3d(pos.x, 0, pos.y), false);
			}
			else {
				vec2d pos = random2d(at.radius + shipDesc.radius + 3.75);
				ship.addMoveOrder(at.position + vec3d(pos.x, 0, pos.y), false);
			}
		}
	}

	ship.finalizeCreation();
	return ship;
}

Orbital@ createOrbital(const vec3d& at, const OrbitalModule@ core, Empire@ owner = null, bool disabled = false, const string& nameOverride = "") {
	ObjectDesc oDesc;
	oDesc.type = OT_Orbital;
	@oDesc.owner = owner;
	if(nameOverride.length != 0)
		oDesc.name = nameOverride;
	else
		oDesc.name = core.name;
	oDesc.radius = core.size;
	oDesc.position = at;
	
	Object@ obj = makeObject(oDesc);
	Orbital@ orb = cast<Orbital>(obj);

	if(owner !is null && owner.valid)
		owner.registerOrbital(orb);

	obj.rotation = quaterniond_fromAxisAngle(vec3d_up(), randomd(0.0,twopi));

	orb.checkOrbit();
	if(disabled)
		orb.setDisabled(true);
	orb.addSection(core.id);
	return orb;
}

Civilian@ createCivilian(const vec3d& at, Empire@ owner, uint type = CiT_Freighter, double radius = 2.0) {
	ObjectDesc desc;
	desc.type = OT_Civilian;
	@desc.owner = owner;
	desc.name = getCivilianName(type, radius);
	desc.radius = radius;
	desc.position = at;
	desc.delayedCreation = true;
	
	Civilian@ obj = cast<Civilian>(makeObject(desc));
	obj.sightRange = 0;
	obj.setCivilianType(type);
	obj.finalizeCreation();
	return obj;
}
