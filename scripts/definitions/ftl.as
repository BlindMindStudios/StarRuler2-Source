#section server-side
from regions.regions import getRegion;
#section all
import orbitals;

const double HYPERDRIVE_COST = 0.08;
const double HYPERDRIVE_START_COST = 25.0;
const double HYPERDRIVE_CHARGE_TIME = 15.0;

bool canHyperdrive(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null || !ship.hasLeaderAI)
		return false;
	if(isFTLBlocked(ship))
		return false;
	return ship.blueprint.hasTagActive(ST_Hyperdrive);
}

double hyperdriveSpeed(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	return ship.blueprint.getEfficiencySum(SV_HyperdriveSpeed);
}

double hyperdriveMaxSpeed(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	return ship.blueprint.design.total(SV_HyperdriveSpeed);
}

int hyperdriveCost(Object& obj, const vec3d& position) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return 0;
	auto@ dsg = ship.blueprint.design;
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return 0;
	return ceil(log(dsg.size) * (dsg.total(HV_Mass)*0.5/dsg.size) * sqrt(position.distanceTo(obj.position)) * HYPERDRIVE_COST + HYPERDRIVE_START_COST + owner.HyperdriveStartCostMod) * owner.FTLCostFactor;
}

int hyperdriveCost(array<Object@>& objects, const vec3d& destination) {
	int cost = 0;
	for(uint i = 0, cnt = objects.length; i < cnt; ++i) {
		if(!canHyperdrive(objects[i]))
			continue;
		cost += hyperdriveCost(objects[i], destination);
	}
	return cost;
}

double hyperdriveRange(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return 0.0;
	int scale = ship.blueprint.design.size;
	return hyperdriveRange(obj, scale, playerEmpire.FTLStored);
}

double hyperdriveRange(Object& obj, int scale, int stored) {
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return INFINITY;
	return sqr(max(double(stored) - (HYPERDRIVE_START_COST - owner.HyperdriveStartCostMod) * owner.FTLCostFactor, 0.0) / (log(double(scale)) * HYPERDRIVE_COST * owner.FTLCostFactor));
}

bool canHyperdriveTo(Object& obj, const vec3d& pos) {
	return !isFTLBlocked(obj, pos);
}

const double FLING_BEACON_RANGE = 12500.0;
const double FLING_BEACON_RANGE_SQ = sqr(FLING_BEACON_RANGE);
const double FLING_COST = 8.0;
const double FLING_CHARGE_TIME = 15.0;
const double FLING_TIME = 15.0;

bool canFling(Object& obj) {
	if(isFTLBlocked(obj))
		return false;
	if(!obj.hasLeaderAI)
		return false;
	if(obj.isShip) {
		return true;
	}
	else {
		if(obj.isOrbital) {
			if(obj.owner.isFlingBeacon(obj))
				return false;
			Orbital@ orb = cast<Orbital>(obj);
			auto@ core = getOrbitalModule(orb.coreModule);
			return core is null || core.canFling;
		}
		if(obj.isPlanet)
			return true;
		return false;
	}
}

bool canFlingTo(Object& obj, const vec3d& pos) {
	return !isFTLBlocked(obj, pos);
}

double flingSpeed(Object& obj, const vec3d& pos) {
	return obj.position.distanceTo(pos) / FLING_TIME;
}

int flingCost(Object& obj, vec3d position) {
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return 0;
	if(obj.isShip) {
		Ship@ ship = cast<Ship>(obj);
		auto@ dsg = ship.blueprint.design;
		int scale = dsg.size;
		double massFactor = dsg.total(HV_Mass) * 0.3/dsg.size;

		double scaleFactor;
		if(dsg.hasTag(ST_Station))
			scaleFactor = pow(double(scale), 0.75);
		else
			scaleFactor = sqrt(double(scale));

		return ceil(FLING_COST * scaleFactor * massFactor * owner.FTLCostFactor);
	}
	else {
		if(obj.isOrbital)
			return ceil(FLING_COST * obj.radius * 3.0 * owner.FTLCostFactor);
		else if(obj.isPlanet)
			return ceil(FLING_COST * obj.radius * 30.0 * owner.FTLCostFactor);
		return INFINITY;
	}
}

int flingCost(array<Object@>& objects, const vec3d& destination) {
	int cost = 0;
	for(uint i = 0, cnt = objects.length; i < cnt; ++i)
		cost += flingCost(objects[i], destination);
	return cost;
}

double flingRange(Object& obj) {
	if(flingCost(obj, obj.position) > obj.owner.FTLStored)
		return 0.0;
	return INFINITY;
}

const double SLIPSTREAM_CHARGE_TIME = 15.0;
const double SLIPSTREAM_LIFETIME = 10.0 * 60.0;

bool canSlipstream(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null || !ship.hasLeaderAI)
		return false;
	if(isFTLBlocked(ship))
		return false;
	return ship.blueprint.hasTagActive(ST_Slipstream);
}

int slipstreamCost(Object& obj, int scale, double distance) {
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return 0;
	Ship@ ship = cast<Ship>(obj);
	double baseCost = ship.blueprint.design.total(SV_SlipstreamCost);
	double optDist = ship.blueprint.design.total(SV_SlipstreamOptimalDistance);
	if(distance < optDist)
		return baseCost * obj.owner.FTLCostFactor;
	return baseCost * ceil(distance / optDist) * obj.owner.FTLCostFactor;
}

double slipstreamRange(Object& obj, int scale, int stored) {
	Ship@ ship = cast<Ship>(obj);

	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return INFINITY;

	double baseCost = ship.blueprint.design.total(SV_SlipstreamCost);
	double optDist = ship.blueprint.design.total(SV_SlipstreamOptimalDistance);

	if(stored < baseCost)
		return 0.0;
	return floor(double(stored) / baseCost / obj.owner.FTLCostFactor) * optDist;
}

double slipstreamLifetime(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	return ship.blueprint.getEfficiencyFactor(SV_SlipstreamDuration) * ship.blueprint.design.total(SV_SlipstreamDuration);
}

void slipstreamModifyPosition(Object& obj, vec3d& position) {
	double radius = slipstreamInaccuracy(obj, position);

	vec2d offset = random2d(radius);
	position += vec3d(offset.x, randomd(-radius * 0.2, radius * 0.2), offset.y);
}

double slipstreamInaccuracy(Object& obj, const vec3d& position) {
	double dist = obj.position.distanceTo(position);
	return dist * 0.01;
}

bool canSlipstreamTo(Object& obj, const vec3d& point) {
	auto@ reg = obj.region;
	if(reg !is null) {
		if(reg.BlockFTLMask & obj.owner.mask != 0)
			return false;
	}
	@reg = getRegion(point);
	if(reg !is null) {
		if(reg.BlockFTLMask & obj.owner.mask != 0)
			return false;
	}
	return true;
}

bool isFTLBlocked(Object& obj, const vec3d& point) {
	auto@ reg = getRegion(point);
	if(reg is null)
		return false;
	if(reg.BlockFTLMask & obj.owner.mask != 0)
		return true;
	return false;
}

bool isFTLBlocked(Object& obj) {
	auto@ reg = obj.region;
	if(reg is null)
		return false;
	if(reg.BlockFTLMask & obj.owner.mask != 0)
		return true;
	return false;
}

const double JUMPDRIVE_COST = 0.06;
const double JUMPDRIVE_START_COST = 50.0;
const double JUMPDRIVE_CHARGE_TIME = 25.0;

bool canJumpdrive(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null || !ship.hasLeaderAI)
		return false;
	if(isFTLBlocked(ship))
		return false;
	return ship.blueprint.hasTagActive(ST_Jumpdrive);
}

int jumpdriveCost(Object& obj, const vec3d& fromPos, const vec3d& position) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return 0;
	auto@ dsg = ship.blueprint.design;
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return 0;
	double dist = position.distanceTo(fromPos);
	dist = min(dist, jumpdriveRange(obj));

	return ceil(log(dsg.size) * (dsg.total(HV_Mass)*0.5/dsg.size) * sqrt(dist) * JUMPDRIVE_COST + JUMPDRIVE_START_COST) * owner.FTLCostFactor;
}

int jumpdriveCost(Object& obj, const vec3d& position) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return 0;
	auto@ dsg = ship.blueprint.design;
	Region@ reg = obj.region;
	Empire@ owner = obj.owner;
	if(reg !is null && owner !is null && reg.FreeFTLMask & owner.mask != 0)
		return 0;
	double dist = position.distanceTo(obj.position);
	dist = min(dist, jumpdriveRange(obj));

	return ceil(log(dsg.size) * (dsg.total(HV_Mass)*0.5/dsg.size) * sqrt(dist) * JUMPDRIVE_COST + JUMPDRIVE_START_COST) * owner.FTLCostFactor;
}

int jumpdriveCost(array<Object@>& objects, const vec3d& destination) {
	int cost = 0;
	for(uint i = 0, cnt = objects.length; i < cnt; ++i) {
		if(!canHyperdrive(objects[i]))
			continue;
		cost += jumpdriveCost(objects[i], destination);
	}
	return cost;
}

double jumpdriveRange(Object& obj) {
	Ship@ ship = cast<Ship>(obj);
	return ship.blueprint.design.total(SV_JumpRange);
}

double jumpdriveRange(Object& obj, int scale, int stored) {
	Ship@ ship = cast<Ship>(obj);
	return ship.blueprint.design.total(SV_JumpRange);
}

bool canJumpdriveTo(Object& obj, const vec3d& pos) {
	return !isFTLBlocked(obj, pos);
}

const double FLUX_CD_RANGE = 300.0;

bool canFluxTo(Object& obj, const vec3d& pos) {
	if(obj.owner.HasFlux == 0)
		return false;

	auto@ reg = getRegion(pos);
	auto@ curReg = obj.region;

	if(curReg is null)
		return false;
	if(reg is null)
		return false;
	if(reg is curReg)
		return false;

	if(reg.VisionMask & obj.owner.mask == 0)
		return false;
	if(isFTLBlocked(obj) || isFTLBlocked(obj, pos))
		return false;
	if(obj.hasStatuses) {
		if(obj.hasStatusEffect(fluxStatus))
			return false;
	}
	return true;
}

vec3d getFluxDest(Object& obj, const vec3d& pos) {
	auto@ reg = getRegion(pos);
	auto@ curReg = obj.region;

	vec3d dir;
	if(curReg !is null)
		dir = (obj.position - curReg.position) / curReg.radius;
	else
		dir = random3d(0.6);

	if(reg !is null)
		return reg.position + (dir * reg.radius);
	else
		return pos;
}

from statuses import getStatusID;
int fluxStatus = -1;
void init() {
	fluxStatus = getStatusID("FluxCooldown");
}

#section server-side
void commitFlux(Object& obj, const vec3d& pos) {
	vec3d fluxPos = getFluxDest(obj, pos);

#section server
	playParticleSystem("FluxJump", obj.position, obj.rotation, obj.radius * 4.0, obj.visibleMask);
	playParticleSystem("FluxJump", fluxPos, obj.rotation, obj.radius * 4.0, obj.visibleMask);
#section server-side

	if(obj.hasStatuses) {
		double dist = fluxPos.distanceTo(obj.position);
		double cd = dist / FLUX_CD_RANGE;
		obj.addStatus(fluxStatus, timer=cd);
	}

	if(obj.hasLeaderAI) {
		obj.teleportTo(fluxPos, movementPart=true);
	}
	else {
		obj.position = fluxPos;
		obj.velocity = vec3d();
		obj.acceleration = vec3d();
	}
}
#section all
