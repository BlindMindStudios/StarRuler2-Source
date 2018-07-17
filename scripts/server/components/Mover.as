import oddity_navigation;
from regions.regions import getRegion;
import saving;
import ftl;

const double straighDot = 0.99999;

//Rotation rate in radians/s
const double shipRotSpeed = 0.1;
const double SQRT_2 = sqrt(2.0);

double lowerQuadratic(double a, double b, double c) {
	double d = sqrt(b*b - 4.0 * a * c);
	if(d != d)
		return 10000.0;
	//double r1 = (-b + d) / (2.0 * a);
	double r2 = (-b - d) / (2.0 * a);
	if(r2 > 0.0)
		return r2;
	else
		return 10000.0;
}

double timeToTarg(double a, const vec3d& offset, const vec3d& relVel) {
	double dist = offset.length, speed = relVel.length;
	if(speed < 0.05) {
		return sqrt(4.0 * dist / a);
	}
	
	double velDot = 1.0;
	if(dist > 0.001)
		velDot = relVel.dot(offset) / (dist * speed);
	if(velDot > straighDot) {
		//We must accelerate up to the target speed before hitting the point
		
		// d = 1/2 a * t^2 (where t = v/a)
		double accelDist = 0.5 * speed * speed / a;
		
		if(accelDist > dist) {
			//return (speed / a) + sqrt(4.0 * (accelDist - dist) / a);
			//return (speed / a) + (accelDist - dist) / speed;
			
			return lowerQuadratic(-a, 2.0 * speed, dist - accelDist);
		}
		else {
			//We have enough distance
			//Accelerate until we must decelerate
			double totalTime = sqrt(4.0 * (dist - accelDist) / a);
			return totalTime + (speed / a);
		}
	}
	else if(velDot < -straighDot) {
		double deccelTime = speed / a;
		double deccelDist = deccelTime * speed * 0.5;
		
		//We either need to slow down, or accelerate to a maximum velocity
		if(deccelDist < dist) {
			double totalTime = sqrt(4.0 * (deccelDist + dist) / a);
			return totalTime - (speed / a);
		}
		else {
			return deccelTime + sqrt(4.0 * (deccelDist - dist) / a);
		}
	}
	else {
		vec3d linearVel = offset.normalized(speed * velDot);
		vec3d latVel = relVel - linearVel;
		vec3d zero;
		
		double aToward = 0.7;
		
		double rangeLow = 0.0001, rangeHigh = 0.9999;
		double t = 0, leastErr = 99999999.0;
		for(uint i = 0; i < 15; ++i) {
			double aLat = sqrt(1.0 - (aToward * aToward));
		
			double tToward = timeToTarg(aToward * a, offset, linearVel);
			double tLat = timeToTarg(aLat * a, zero, latVel);
				
			double err = abs(tToward - tLat);
			if(err < leastErr) {
				leastErr = err;
				t = (tToward + tLat) * 0.5;
			}
			
			if(err < 0.02)
				break;
			else if(tToward > tLat) {
				rangeLow = aToward;
				aToward = (rangeLow + rangeHigh) * 0.5;
			}
			else {
				rangeHigh = aToward;
				aToward = (rangeLow + rangeHigh) * 0.5;
			}
		}
		
		return t;
	}
}
	
vec3d accToGoal(double a, double& maxTime, const vec3d& offset, const vec3d& relVel) {
	double dist = offset.length, speed = relVel.length;
	
	if(speed < 0.05) {
		//Accelerates for half the time, decelerates for half the time
		maxTime = sqrt(4.0 * dist / a) * 0.5;
		return offset.normalized(a);
	}
	else {
		double velDot = 1.0;
		if(dist > 0.001)
			velDot = relVel.dot(offset) / (dist * speed);
		if(velDot > straighDot) {
			//We must accelerate up to the target speed before hitting the point
			
			// d = 1/2 a * t^2 (where t = v/a)
			double accelDist = 0.5 * speed * speed / a;
			
			if(accelDist > dist) {
				//error(accelDist + " vs " + dist);
				//maxTime = sqrt(4.0 * (accelDist - dist) / a) * 0.5;
				//return offset.normalized(-a);
				//maxTime = (accelDist - dist) / speed;
				//return vec3d();
				maxTime = lowerQuadratic(-a, 2.0 * speed, dist - 0.5 * accelDist);
				return offset.normalized(a);
			}
			else {
				//We have enough distance
				//Accelerate until we must decelerate
				maxTime = speed / a;
				return offset.normalized(a);
			}
		}
		else if(velDot < -straighDot) {
			double deccelTime = speed / a;
			double deccelDist = deccelTime * speed * 0.5;
			if(deccelDist < dist) {
				//Determine our time remaining based on the original null-vel curve
				double totalTime = sqrt(4.0 * (deccelDist + dist) / a);
				maxTime = (totalTime * 0.5) - (speed / a);
				return offset.normalized(a);
			}
			else {
				maxTime = speed / a;
				return relVel.normalized(a);
			}
		}
		else {
			vec3d linearVel = offset.normalized(speed * velDot);
			vec3d latVel = relVel - linearVel;
			vec3d zero;
			
			double rangeLow = 0.0001, rangeHigh = 0.9999;
			double aToward = 0.7;
			double aLat;
			
			double t = 0, leastErr = 999999999.0;
			
			for(uint i = 0; i < 15; ++i) {
				aLat = sqrt(1.0 - (aToward * aToward));
			
				double tToward = timeToTarg(aToward * a, offset, linearVel);
				//double tLat = timeToTarg(aLat * a, zero, latVel);
				
				double tLat = latVel.length / (aLat * a);
				double latDist = latVel.length * tLat * 0.5;
				tLat += sqrt(4.0 * latDist / (aLat * a));
				
				double err = abs(tToward - tLat);
				if(err < leastErr) {
					leastErr = err;
					t = (tToward + tLat) * 0.5;
				}
				
				if(err < 0.02)
					break;
				else if(tToward > tLat) {
					rangeLow = aToward;
					aToward = (rangeLow + rangeHigh) * 0.5;
				}
				else {
					rangeHigh = aToward;
					aToward = (rangeLow + rangeHigh) * 0.5;
				}
			}
			aLat = sqrt(1.0 - (aToward * aToward));
			
			double maxT1 = 0, maxT2 = 0;
			
			vec3d linAcc = accToGoal(aToward * a, maxT1, offset, linearVel);
			//vec3d latAcc = accToGoal(aLat * a, maxT2, zero, latVel);
			vec3d latAcc = latVel.normalize(aLat * a); maxT2 = latVel.length / (aLat * a);
			
			maxTime = min(maxT1, maxT2);
			return latAcc + linAcc;
		}
	}
}

tidy class Mover : Component_Mover, Savable {
	Object@ target;
	vec3d destination;
	quaterniond prevFormationDest;
	quaterniond targRot;
	quaterniond targFacing;
	quaterniond combatFacing;
	vec3d compDestination;
	bool inCombat = false;
	double targDist = 0;
	int prevPathId = 0;
	array<PathNode@>@ path;

	Object@ lockTo;
	bool isLocked = false;
	vec3d lockOffset;
	float rotSpeed = shipRotSpeed;
	bool vectorMovement = false;
	bool fleetRelative = true;
	
	const Object@ colliding;

	double accel = 1.0;
	double accelBonus = 0;
	bool moving = false;
	bool rotating = false;
	bool moverDelta = false;
	bool posDelta = false;
	bool facingDelta = false;
	int moveID = 0;
	int syncedID = 0;

	bool FTL = false;
	double FTLSpeed = 1.0;

	Mover() {
	}

	void load(SaveFile& data) {
		data >> target;
		data >> destination;
		data >> accel;
		if(data >= SV_0100)
			data >> accelBonus;
		data >> moving;
		data >> rotating;
		data >> lockTo;
		data >> isLocked;
		data >> lockOffset;
		data >> moveID;
		data >> FTL;
		data >> FTLSpeed;
		data >> targDist;
		data >> combatFacing;
		data >> targFacing;
		data >> inCombat;
		if(data >= SV_0126)
			data >> vectorMovement;
		if(data >= SV_0048)
			data >> rotSpeed;
		if(data >= SV_0054)
			data >> fleetRelative;

		if(data >= SV_0009) {
			uint cnt = 0;
			data >> cnt;
			if(cnt > 0) {
				@path = array<PathNode@>(cnt);
				for(uint i = 0; i < cnt; ++i) {
					@path[i] = PathNode();
					data >> path[i];
				}
			}
		}

		if(data >= SV_0067)
			data >> prevPathId;
	}
	
	void save(SaveFile& data) {
		data << target;
		data << destination;
		data << accel;
		data << accelBonus;
		data << moving;
		data << rotating;
		data << lockTo;
		data << isLocked;
		data << lockOffset;
		data << moveID;
		data << FTL;
		data << FTLSpeed;
		data << targDist;
		data << combatFacing;
		data << targFacing;
		data << inCombat;
		data << vectorMovement;
		data << rotSpeed;
		data << fleetRelative;

		uint cnt = path is null ? 0 : path.length;
		data << cnt;
		for(uint i = 0; i < cnt; ++i)
			data << path[i];
		data << prevPathId;
	}

	void destroy() {
		@target = null;
	}

	Object@ getLockedOrbit(bool requireLock = true) {
		if(requireLock && !isLocked)
			return null;
		return lockTo;
	}

	bool hasLockedOrbit(bool requireLock = true) {
		if(requireLock && !isLocked)
			return false;
		return lockTo !is null;
	}

	bool isLockedOrbit(Object@ at, bool requireLock = true) {
		if(requireLock && !isLocked)
			return false;
		if(lockTo is at)
			return true;
		return false;
	}

	Object@ getAroundLockedOrbit(Object& obj) {
		if(lockTo is null)
			return null;
		if(lockTo.isPlanet) {
			double maxDist = cast<Planet>(lockTo).OrbitSize;
			if(obj.position.distanceToSQ(lockTo.position) > maxDist * maxDist)
				return null;
		}
		return lockTo;
	}
	
	double get_ftlSpeed() {
		return FTLSpeed;
	}

	void set_ftlSpeed(double value) {
		if(FTLSpeed == value)
			return;
		FTLSpeed = value;
		moverDelta = true;
	}

	bool FTLTo(Object& obj, vec3d target, double speed, int& id) {
		if(id > 0 && id == moveID)
			return !FTL;
		if(FTL)
			return false;
		moveTo(obj, target, id, false);
		FTL = true;
		FTLSpeed = max(speed, 1.0);
		return false;
	}

	void FTLTo(Object& obj, vec3d target, double speed) {
		if(FTL)
			return;
		int id = -1;
		moveTo(obj, target, id, false);
		FTL = true;
		FTLSpeed = max(speed, 1.0);
	}

	void FTLDrop(Object& obj) {
		if(!FTL)
			return;
		obj.velocity = vec3d();
		obj.acceleration = vec3d();
		FTL = false;
		FTLSpeed = 0;
		stopMoving(obj);
		moverDelta = true;
		posDelta = true;
	}
	
	bool get_isColliding() const {
		return colliding !is null;
	}

	bool get_inFTL() const {
		return FTL;
	}

	bool get_isMoving(const Object& obj) const {
		return moving || rotating || FTL;
	}
	
	vec3d get_internalDestination() const {
		return destination;
	}

	vec3d get_computedDestination() const {
		return compDestination;
	}

	vec3d get_moveDestination(const Object& obj) const {
		if(target !is null) {
			vec3d dir = (target.position - obj.position);
			return obj.position + dir.normalized(dir.length - targDist);
		}
		if(lockTo !is null)
			return lockTo.position + lockOffset;
		if(obj.hasSupportAI) {
			const Ship@ ship = cast<const Ship>(obj);
			Object@ leader = ship.Leader;

			if(leader !is null) {
					Ship@ leaderShip = cast<Ship>(leader);
					quaterniond formationFacing;
					if(leaderShip !is null)
						formationFacing = leaderShip.formationDest;

					if(fleetRelative)
						return leader.position + (formationFacing * ship.formationDest.xyz);
					else
						return leader.position + destination;
			}
		}
		return destination;
	}

	bool get_hasMovePath() const {
		return path !is null && path.length > 0;
	}

	bool get_hasMovePortal() {
		return path !is null && path.length > 0 && path[0].pathEntry !is null;
	}

	vec3d getMovePortal() {
		if(path is null || path.length == 0)
			return vec3d();
		return path[0].pathOut();
	}

	void getMovePath(const Object& obj) const {
		if(path is null)
			return;
	
		Object@ prev;
		for(uint i = 0, cnt = path.length; i < cnt; ++i) {
			auto@ node = path[i];
			if(node.pathEntry !is prev)
				yield(node.pathEntry);
			if(node.pathExit !is null)
				yield(node.pathExit);
		}
	}

	double get_maxAcceleration() const {
		return accel;
	}

	void set_rotationSpeed(float amt) {
		if(rotSpeed != amt) {
			rotSpeed = amt;
			moverDelta = true;
		}
	}

	void set_hasVectorMovement(bool value) {
		if(vectorMovement != value) {
			vectorMovement = value;
			moverDelta = true;
		}
	}

	void set_maxAcceleration(Object& obj, double Accel) {
		if(accel != Accel) {
			moverDelta = true;
			accel = Accel + accelBonus;
		}
	}

	void modAccelerationBonus(double mod) {
		accel += mod;
		accelBonus += mod;
		moverDelta = true;
	}
	
	bool get_leaderLock() {
		return fleetRelative;
	}
	
	void set_leaderLock(bool doLock) {
		if(fleetRelative != doLock) {
			fleetRelative = doLock;
			//If we're changing to a locked state, we need a delta (other steps are responsible for this when a lock is released)
			if(doLock)
				moverDelta = true;
		}
	}
	
	void impulse(Object& obj, vec3d ForceSeconds) {
		obj.velocity += ForceSeconds;
		moving = true;
		moverDelta = true;
		posDelta = true;

		if(obj.hasOrbit && obj.inOrbit)
			obj.stopOrbit();
	}
	
	void rotate(Object& obj, quaterniond rot) {
		obj.rotation *= rot;
		rotating = true;
		moverDelta = true;
	}
	
	double timeToTarget(Object& obj, double a, const vec3d& point, const vec3d& velocity) {
		//NOTE: The engine implements an identical implementation of timeToTarg for performance reasons
		//return timeToTarg(a, point - obj.position, velocity - obj.velocity);
		return newtonArrivalTime(a, point - obj.position, velocity - obj.velocity);
	}

	void speedBoost(Object& obj, double amount) {
		//Note to self: try to keep any cleaver-like objects away from
		//Reaper for a while after this code gets committed. Maybe go into
		//hiding a few years.

		if(accel == 0)
			return;
		vec3d acc = obj.acceleration.normalized();
		vec3d dist = get_moveDestination(obj) - obj.position;;
		double distLen = dist.length;
		double velLen = obj.velocity.length;
		if(amount > 0 && distLen < velLen * 2.0)
			return;
		moverDelta = true;
		dist /= distLen;

		if(amount < 0) {
			if(acc.angleDistance(dist) < pi) {
				//Remove some of our velocity-to-target.
				// The move algorithm will compensate, since we're
				// still accelerating towards it.
				obj.velocity.length = velLen + amount;
			}
			else {
				//We're slowing down. Don't slow down below what would be
				//a sane-ish speed for this ship *ducks*.
				double sane = min(velLen, distLen / accel);
				obj.velocity.length = max(sane, velLen + amount);
			}
		}
		else {
			if(acc.angleDistance(dist) < pi) {
				//Fucking full speed ahead. Who gives a shit.
				obj.velocity += dist * amount;
			}
		}
	}
	
	vec3d accelToGoal(Object& obj, double a, double& maxTime, const vec3d& point, const vec3d& velocity) {
		vec3d offset = point - obj.position;
		vec3d relVel = velocity - obj.velocity;
		return accToGoal(a, maxTime, offset, relVel);
	}

	double moverTick(Object& obj, double time) {
		if(time <= 0)
			return 0.1;

		if(!moving && !inFTL && obj.hasOrbit && obj.inOrbit) {
			obj.orbitTick(time);
			return 0.25;
		}

		//Push away from nearby objects
		if(!obj.isPlanet && !obj.noCollide && (!obj.hasSupportAI || !obj.isDetached)) {
			if(colliding is null) {
				const Object@ nearest;
				double dist = 0;
				double myRadius = obj.radius;
				for(int i = 0; i < TARGET_COUNT; ++i) {
					const Object@ other = obj.targets[i];
					if(other is obj || !other.isPhysical || other.noCollide)
						continue;
					//Only push from things larger than me
					if(other.radius < myRadius && !other.isPlanet && !other.isStar)
						continue;
					vec3d off = obj.position - other.position;
					double d = off.lengthSQ;
					if(d <= (obj.radius + other.radius) * (obj.radius + other.radius)) {
						off += random3d(0.1); off.normalize();
						obj.position += off * min(time * other.radius * 0.5, d - other.radius + obj.radius);
						@colliding = other;
						break;
					}
					else if(nearest is null || d < dist) {
						@nearest = other;
						dist = d;
					}
				}
				
				if(nearest !is null && colliding is null) {
					for(int i = 0; i < TARGET_COUNT; ++i) {
						const Object@ other = nearest.targets[i];
						if(other is obj || !other.isPhysical || other.noCollide)
							continue;
						//Only push from things larger than me
						if(other.radius < myRadius && !other.isPlanet && !other.isStar)
							continue;
						vec3d off = obj.position - other.position;
						double d = off.lengthSQ;
						if(d <= (obj.radius + other.radius) * (obj.radius + other.radius)) {
							off += random3d(0.1); off.normalize();
							obj.position += off * min(time * other.radius * 0.5, d - other.radius + obj.radius);
							@colliding = other;
							break;
						}
					}
				}
			}
			else {
				if(!colliding.valid)
					@colliding = null;
				else {
					vec3d off = obj.position - colliding.position;
					double d = off.lengthSQ;
					if(d <= (obj.radius + colliding.radius) * (obj.radius + colliding.radius)) {
						off += random3d(0.1); off.normalize();
						obj.position += off * min(time * colliding.radius * 0.5, d - colliding.radius + obj.radius);
					}
					else {
						@colliding = null;
					}
				}
			}
		}

		vec3d dest, destVel, destAccel;
		PathNode@ pathNode;
		
		{
			double dot = targRot.dot(obj.rotation);
			if(dot < 0.999) {
				if(dot < -1.0)
					dot = -1.0;
				double angle = acos(dot);
				double tickRot = rotSpeed * time;
				if(angle > tickRot) {
					obj.rotation = obj.rotation.slerp(targRot, tickRot / angle);
				}
				else {
					obj.rotation = targRot;
					rotating = false;
				}
			}
			else {
				if(dot != 1.0)
					obj.rotation = targRot;
				rotating = false;
			}
		}

		Object@ leader = obj;
		if(obj.hasSupportAI)
			@leader = cast<Ship>(obj).Leader;
		
		double doneRange = obj.radius;

		if(FTL) {
			vec3d prevPos = obj.position;
			vec3d prevVel = obj.velocity;

			vec3d movement = (destination - obj.position);
			double speed = FTLSpeed * time;
			double dist = movement.length;
			if(dist <= speed) {
				obj.position = destination;
				obj.velocity = vec3d();
				obj.acceleration = vec3d();
				targRot = (!rotating && inCombat) ? combatFacing : targFacing;
				FTL = false;
			
				if(obj.hasLeaderAI)
					playParticleSystem("FTLExit", obj.position, obj.rotation, obj.radius * 4.0, obj.visibleMask);
			}
			else {
				movement.normalize(speed);

				targRot = quaterniond_fromVecToVec(vec3d_front(), movement, vec3d_up());
				obj.position += movement;
				obj.velocity = movement / time;
				obj.acceleration = vec3d();
			}

			return 0.1;
		}
		else if(leader is obj) {
			if(!moving) {
				if(lockTo is null) {
					if(!rotating && inCombat)
						targRot = combatFacing;
					else
						targRot = targFacing;
					return 0.5;
				}
			}

			//Check for path invalidation
			if(prevPathId != 0 && prevPathId != obj.owner.PathId.value)
				updatePath(obj);

			//Get correct destination
			uint pathLen = path is null ? 0 : path.length;
			if(pathLen > 0) {
				for(uint i = 0; i < pathLen; ++i) {
					if(!path[i].valid(obj)) {
						path.length = 0;
						pathLen = 0;

						vec3d destPos = destination;
						if(target !is null)
							destPos = (obj.position - target.position).normalize(targDist) + target.position;
						obj.createPathTowards(destPos, target);
					}
				}

				if(pathLen > 0) {
					@pathNode = path[0];
					if(pathNode.pathEntry !is null)
						dest = pathNode.pathEntry.position;
					else {
						dest = pathNode.pathTo;
						doneRange = max(pathNode.dist, doneRange);
					}
					//double space = pathNode.pathEntry.radius + obj.radius;
					//dest += (obj.position - dest).normalize(space);
				}
			}
			if(pathNode is null) {
				if(lockTo !is null) {
					dest = lockTo.position + lockOffset;
					destVel = lockTo.velocity;
					destAccel = lockTo.acceleration;
					
					//Compensate for varying tick times
					double tDiff = (obj.lastTick + time) - lockTo.lastTick;
					if(tDiff != 0.0) {
						dest += (destVel + (destAccel * (tDiff * 0.5))) * tDiff;
						destVel += destAccel * tDiff;
					}
				}
				else if(target !is null) {
					if(target.valid) {
						dest = target.position;
						destVel = target.velocity;
						destAccel = target.acceleration;
						
						//Compensate for varying tick times
						double tDiff = (obj.lastTick + time) - target.lastTick;
						if(tDiff != 0.0) {
							dest += (destVel + (destAccel * (tDiff * 0.5))) * tDiff;
							destVel += destAccel * tDiff;
						}
						
						//Try to reach the target at a particular distance
						//NOTE: This is inaccurate (the angle of the target will change during target prediction)
						//		However, because we iterate over small time steps, the error should be relatively small
						dest += (obj.position - dest).normalize(targDist);
					}
					else {
						destination = target.position;
						@target = null;
					}
				}
				else {
					dest = destination;
				}
			}
		}
		else {
			quaterniond formationFacing;
			Ship@ leaderShip = cast<Ship>(leader);
			if(leaderShip !is null)
				formationFacing = leaderShip.formationDest;

			if(leader !is null) {
				destVel = leader.velocity;
				destAccel = leader.acceleration;
				if(fleetRelative)
					dest = leader.position + (formationFacing * cast<Ship>(obj).formationDest.xyz);
				else
					dest = leader.position + destination;

				//Compensate for varying tick times
				double tDiff = (obj.lastTick + time) - leader.lastTick;
				if(tDiff != 0) {
					dest += (destVel + (destAccel * (tDiff * 0.5))) * tDiff;
					destVel += destAccel * tDiff;
				}
			}
			else {
				dest = obj.position;
				destVel = vec3d();
				destAccel = vec3d();
			}
		}
		
		doneRange *= doneRange;
		compDestination = dest;

		double a = accel;
		
		obj.position += obj.velocity * time;

		if(obj.owner.ForbidDeepSpace != 0) {
			Region@ reg = obj.region;
			if(reg !is null && !obj.hasSupportAI) {
				double dist = obj.position.distanceTo(reg.position+obj.velocity);
				if(dist > reg.radius && dist <= reg.radius*1.05+obj.velocity.length) {
					vec3d dir = obj.position - reg.position;
					vec3d toPos = reg.position + dir.normalized(reg.radius * 0.999);
					if(obj.hasLeaderAI) {
						obj.teleportTo(toPos, movementPart=true);
					}
					else {
						obj.position = toPos;
						obj.velocity = vec3d();
						obj.acceleration = vec3d();
					}
					stopMoving(obj, enterOrbit=false);
				}
			}
		}
		
		if(!isLocked && (a <= 0.0000001 || a != a)) {
			double speed = obj.velocity.length;
			double tickAccel = 0.1 * time;
			if(speed < tickAccel) {
				obj.velocity = vec3d();
				if(moving) {
					moverDelta = true;
					moving = false;
					if(obj.hasOrbit)
						obj.remakeStandardOrbit();
					prevPathId = 0;
				}
				return 0.25;
			}
			else {
				if(moving && obj.hasOrbit) {
					moverDelta = true;
					moving = false;
					if(obj.hasOrbit)
						obj.remakeStandardOrbit();
					prevPathId = 0;
				}
				obj.velocity *= (speed - tickAccel)/speed;
				return 0.125;
			}
		}
		
		//Check if we can decellerate to our target this tick
		double tGoal = newtonArrivalTime(a, dest - obj.position, destVel - obj.velocity);
		if(tGoal > 1.0e4 || tGoal != tGoal) {
			//We might not be able to reach the target (infinite time), so make sure we're working with a vaguely sensible timeline
			tGoal = 1.0e4;
		}
		
		if(pathNode !is null && (tGoal <= time || tGoal <= 1.0 || (obj.position + obj.velocity).distanceToSQ(dest) < doneRange)) {
			if(pathNode.pathEntry !is null) {
				playParticleSystem("GateFlash", obj.position, obj.rotation, obj.radius, obj.visibleMask, false);
				if(obj.hasLeaderAI)
					obj.teleportTo(pathNode.pathOut(), movementPart=true);
				else {
					obj.position = pathNode.pathOut();
					obj.velocity = vec3d();
					obj.acceleration = vec3d();
				}
				playParticleSystem("GateFlash", obj.position, obj.rotation, obj.radius, obj.visibleMask | pathNode.visionMask, false);
			}
			path.remove(pathNode);
			posDelta = true;
			moverDelta = true;
			return 0.125;
		}
		else if(tGoal <= time || (lockTo !is null && isLocked)) {
			obj.position = dest;
			obj.velocity = destVel;
			obj.acceleration = destAccel;

			if(moving) {
				moverDelta = true;
				moving = false;
				if(obj.hasOrbit)
					obj.remakeStandardOrbit();
				prevPathId = 0;
			}

			if(lockTo !is null)
				isLocked = true;
			if(rotating)
				targRot = targFacing;
			else if(inCombat)
				targRot = combatFacing;
			else if(leader !is obj && cast<Ship>(leader) !is null)
				targRot = leader.rotation;
			else
				targRot = targFacing;
			return 0.5;
		}
		else {
			//Deal with flux
			if(obj.owner.HasFlux != 0 && !obj.hasSupportAI) {
				Region@ reg = obj.region;
				if(reg !is null) {
					if(dest.distanceToSQ(reg.position) > reg.radius*reg.radius) {
						if(canFluxTo(obj, dest)) {
							commitFlux(obj, dest);
							return 0.25;
						}
						else if(obj.owner.ForbidDeepSpace != 0) {
							double speed = obj.velocity.length;
							if(speed < a)
								obj.velocity = vec3d();
							else
								obj.velocity *= (speed - a)/speed;
							obj.acceleration = vec3d();
							return 0.25;
						}
					}
				}
			}

			//Do movement
			for(uint i = 0; i < 15; ++i) {
				double tOff = tGoal - time;
				vec3d predDest = dest + (destVel + (destAccel * (tOff * 0.5))) * tOff;
				vec3d predVel = destVel + destAccel * tOff;
			
				double requires = newtonArrivalTime(a, predDest - obj.position, predVel - obj.velocity);
				//We may be near a case where we can't reach the target
				if(requires > 1.0e4 || requires != requires)
					break;
				
				if(abs(requires - tGoal) < 0.02 || requires <= time) {
					tGoal = requires;
					break;
				}
				else {
					double diff = abs(requires - tGoal) * 0.1;
					vec3d primeDest = predDest + (predVel + (destAccel * (diff * 0.5))) * diff;
					vec3d primeVel = predVel + destAccel * diff;
					
					double then = timeToTarget(obj, a, primeDest, primeVel);
					
					//Move to a guess for the next 0
					double slope = ((then - requires) / diff) - 1.0;
					double y = then - (requires + diff);
					tGoal = (requires + diff) - y / slope;
				}
			}
			
			vec3d prevPos = obj.position;
			vec3d prevVel = obj.velocity;
			
			if(tGoal > 1.0) {
				if(leader !is obj && cast<Ship>(leader) !is null) {
					if(obj.isDetached)
						targRot = quaterniond_fromVecToVec(vec3d_front(), dest - obj.position, vec3d_up());
					else
						targRot = leader.rotation;
				}
				else if(inCombat)
					targRot = combatFacing;
				else
					targRot = targFacing;
			}

			//Perform necessary acceleration at arbitrary accuracy
			if(tGoal > time) {
				//Flagships can only accelerate after they finish rotating
				if((leader !is null && leader !is obj) || !rotating || vectorMovement) {
					double timeLeft = time;
					do {
						double take = 0;
						obj.acceleration = accToGoal(a, take, dest - obj.position, destVel - obj.velocity);
						take = min(timeLeft, max(take, 0.01));
						obj.position += obj.acceleration * (take * take * 0.5);
						obj.velocity += obj.acceleration * take;
						timeLeft -= take;
					} while(timeLeft > 0.0001);

					if(!vectorMovement) {
						if((leader is obj || cast<Ship>(leader) is null) && obj.acceleration.lengthSQ > 0.01 && tGoal > 1.0)
							targRot = quaterniond_fromVecToVec(vec3d_front(), dest - obj.position, vec3d_up());
					}
				}
				else if(!vectorMovement) {
					targRot = quaterniond_fromVecToVec(vec3d_front(), dest - obj.position, vec3d_up());
				}
			}
			else {
				obj.position = dest;
				obj.velocity = destVel;
				obj.acceleration = destAccel;
			}
			
			//double trueAcc = prevVel.distanceTo(obj.velocity) / time;
			//if(trueAcc - a > 0.001)
			//	error(trueAcc + " > " + a);
			
			isLocked = false;
			return tGoal * 0.5;
		}
	}

	quaterniond get_targetRotation() {
		return targRot;
	}

	void forceLockTo(Object@ obj) {
		@lockTo = obj;
		isLocked = true;
	}

	void checkOrbitObject(Object& obj, vec3d destPoint) {
		Region@ reg = getRegion(destPoint);
		if(reg is null)
			return;

		Object@ orbit = reg.getOrbitObject(destPoint);
		if(orbit is null)
			return;

		@lockTo = orbit;
		isLocked = false;
		lockOffset = destPoint - orbit.position;

		if(syncedID == moveID)
			syncedID = -1;
	}
	
	PathNode@ dodge(Object& obj, const line3dd& line, Object@ ignore, Object@& prev) {
		auto@ obstacle = trace(line, 0x1);
		if(obstacle is null || obstacle is ignore || obstacle is prev || !(obstacle.isStar || obstacle.isPlanet))
			return null;
		
		double baseDist = line.start.distanceTo(obstacle.position);
		
		@prev = obstacle;
		
		double dist = (obj.radius + obstacle.radius) * 2.0;
		dist = max(dist, sqrt(baseDist));
		
		vec3d pt = line.getClosestPoint(obstacle.position, false);
		if(pt != obstacle.position)
			pt = obstacle.position + (pt - obstacle.position).normalized(dist);
		else
			pt = obstacle.position + quaterniond_fromAxisAngle(line.direction, randomd(-pi,pi)) * line.direction.cross(vec3d_up()).normalized(dist);
		
		PathNode node;
		node.pathTo = pt;
		node.dist = (dist + (pt - line.start).normalize().dot(pt - obstacle.position)); //The less perpendicular the course, the further away we can start changing course
		node.dist = min(node.dist, line.start.distanceTo(pt) * 0.5);
		return node;
	}

	void createPathTowards(Object& obj, vec3d point, Object@ targ = null) {
		auto@ temp = path;
		if(temp is null)
			@temp = array<PathNode@>();
		@path = null;
		pathOddityGates(obj.owner, temp, obj.position, point, maxAcceleration);
		
		if(maxAcceleration > 0) {
			Object@ prev;
			vec3d from = obj.position + obj.velocity * (obj.velocity.length / (maxAcceleration * 2.0));
			for(uint i = 0; i < temp.length && temp.length < 50; ++i) {
				if(i > 0) {
					auto@ f = temp[i-1];
					if(f.pathExit !is null)
						from = f.pathExit.position;
					else
						from = f.pathTo;
				}
				vec3d to;
				auto@ node = temp[i];
				if(node.pathEntry !is null)
					to = node.pathEntry.position;
				else
					to = node.pathTo;
				line3dd line(from, to);
				@node = dodge(obj, line, targ, prev);
				if(node !is null)
					temp.insertAt(i, @node);
			}
			
			if(temp.length > 0) {
				auto@ f = temp.last;
				if(f.pathExit !is null)
					from = f.pathExit.position;
				else
					from = f.pathTo;
			}
			
			while(temp.length < 50) {
				line3dd line(from, point);
				auto@ node = dodge(obj, line, targ, prev);
				if(node is null)
					break;
				temp.insertLast(@node);
				from = node.pathTo;
			}
		}
		
		if(temp.length > 0)
			@path = temp;
		prevPathId = obj.owner.PathId.value;
		moverDelta = true;
	}

	void updatePath(Object& obj) {
		prevPathId = obj.owner.PathId.value;
		vec3d dest = destination;
		if(target !is null)
			dest = (obj.position - target.position).normalize(targDist) + target.position;

		array<PathNode@> newPath;
		pathOddityGates(obj.owner, newPath, obj.position, dest, maxAcceleration);

		double prevETA = getPathETA(obj.position, dest, maxAcceleration, path);
		double newETA = getPathETA(obj.position, dest, maxAcceleration, newPath);

		double vel = obj.velocity.length;
		double t = (vel / maxAcceleration);
		newETA += t + sqrt(t * vel * 0.5 / maxAcceleration);

		if(newETA < prevETA) {
			@path = newPath;
			moverDelta = true;
		}
	}
	
	bool isOnMoveOrder(int id) {
		return !FTL && id == moveID && moving;
	}

	bool moveTo(Object& obj, vec3d point, int& id, bool doPathing = true, bool enterOrbit = true, bool allowStop = false) {
		if(FTL)
			return false;
		if(id > 0 && id == moveID)
			return !moving;

		moving = true;
		destination = point;
		@target = null;
		@lockTo = null;

		if(obj.hasOrbit && obj.inOrbit)
			obj.stopOrbit();

		if(!vectorMovement || !inCombat) {
			if(allowStop) {
				double d = point.distanceToSQ(obj.position);
				if(d > sqr(obj.radius + obj.velocity.length))
					allowStop = false;
			}
			if(!allowStop) {
				rotating = true;
				targRot = quaterniond_fromVecToVec(vec3d_front(), point - obj.position, vec3d_up());
			}
		}

		id = ++moveID;

		if(doPathing) {
			if(path !is null)
				path.length = 0;
			obj.createPathTowards(point);
			if(enterOrbit && !obj.isPlanet)
				obj.checkOrbitObject(destination);
		}
		else {
			@path = null;
			prevPathId = 0;
		}

		return false;
	}

	bool moveTo(Object& obj, Object& targ, int& id, double distance = 0.0, bool doPathing = true, bool enterOrbit = true) {
		if(FTL)
			return false;
		if(id > 0 && id == moveID)
			return !moving;

		moving = true;
		@target = targ;
		@lockTo = null;

		if(obj.hasOrbit && obj.inOrbit)
			obj.stopOrbit();

		if(targ.isRegion)
			targDist = targ.radius * 0.85;
		else
			targDist = max(distance, obj.radius + targ.radius);

		if(!vectorMovement || !inCombat) {
			rotating = true;
			targRot = quaterniond_fromVecToVec(vec3d_front(), targ.position - obj.position, vec3d_up());
		}

		id = ++moveID;

		if(doPathing) {
			if(path !is null)
				path.length = 0;
			vec3d destPos = (obj.position - targ.position).normalize(targDist) + targ.position;
			obj.createPathTowards(destPos, targ);
			if(enterOrbit && !obj.isPlanet)
				obj.checkOrbitObject(destPos);
		}
		else {
			@path = null;
			prevPathId = 0;
		}

		return false;
	}

	void stopMoving(Object& obj, bool doPathing = false, bool enterOrbit = true) {
		int dummy = -1;
		if(accel > 1.0e-4)
			moveTo(obj, obj.position + obj.velocity * min(abs(obj.velocity.length) * 0.5 / accel, 30.0), dummy, doPathing, enterOrbit, allowStop=true);
		else
			moveTo(obj, obj.position, dummy, doPathing, enterOrbit, allowStop=true);
	}

	void clearMovement(Object& obj) {
		if(!moving)
			return;
		moving = false;
		moverDelta = true;
		rotating = false;
		if(obj.hasOrbit)
			obj.remakeStandardOrbit();
	}

	bool rotateTo(Object& obj, quaterniond rotation, int& id) {
		if(obj.hasOrbit && obj.inOrbit)
			return true;
		id = moveID;
		rotation.normalize();
		if(targFacing != rotation) {
			facingDelta = true;
			targFacing = rotation;
		}
		
		if(obj.rotation.dot(targFacing) > 0.999) {
			return true;
		}
		else {
			targRot = rotation;
			rotating = true;
			return false;
		}
	}

	void setRotation(Object& obj, quaterniond rotation) {
		rotation.normalize();
		if(targFacing != rotation) {
			targFacing = rotation;
			facingDelta = true;
		}
	}

	void setCombatFacing(Object& obj, quaterniond& rotation) {
		quaterniond prev = combatFacing;
		bool prevCombat = inCombat;

		combatFacing = rotation;
		combatFacing.normalize();
		inCombat = true;

		if(prev != combatFacing || !prevCombat)
			facingDelta = true;
	}

	void clearCombatFacing(Object& obj) {
		if(inCombat) {
			inCombat = false;
			facingDelta = true;
		}
	}

	void flagPositionUpdate(Object& obj) {
		moverDelta = true;
		posDelta = true;
		obj.wake();
	}
	
	bool writeMoverDelta(const Object& obj, Message& msg) {
		const Ship@ ship = cast<const Ship@>(obj);
		if(syncedID != moveID || moverDelta) {
			msg.write1();
			msg.write1();
			writeMover(obj, msg);

			if(obj.velocity.lengthSQ < 0.001 || posDelta) {
				msg.write1();
				msg.writeMedVec3(obj.position);
				posDelta = false;
			}
			else {
				msg.write0();
			}

			syncedID = moveID;
			moverDelta = false;
			facingDelta = false;
			return true;
		}
		else if(facingDelta) {
			msg.write1();
			msg.write0();
			msg.write1();
			msg.writeBit(inCombat);
			if(inCombat)
				msg.writeRotation(combatFacing);
			else {
				msg.writeBit(rotating);
				if(rotating)
					msg.writeRotation(targFacing);
			}
			facingDelta = false;
			return true;
		}
		else if(ship !is null && prevFormationDest != ship.formationDest) {
			msg.write1();
			msg.write0();
			msg.write0();
			if(ship.hasLeaderAI)
				msg.writeRotation(ship.formationDest);
			else
				msg.writeSmallVec3(ship.formationDest.xyz);
			prevFormationDest = ship.formationDest;
			return true;
		}
		return false;
	}

	void readMoverDelta(Object& obj, Message& msg) {
		if(msg.readBit()) {
			readMover(obj, msg);

			if(msg.readBit()) {
				obj.position = msg.readMedVec3();
				obj.velocity = vec3d();
				obj.acceleration = vec3d();
			}
		}
		else {
			if(msg.readBit()) {
				inCombat = msg.readBit();
				if(inCombat)
					combatFacing = msg.readRotation();
				else if(msg.readBit()) {
					rotating = true;
					targFacing = msg.readRotation();
				}
			}
			else {
				Ship@ ship = cast<Ship>(obj);
				if(ship.hasLeaderAI)
					ship.formationDest = msg.readRotation();
				else
					ship.formationDest.xyz = msg.readSmallVec3();
			}
		}
	}

	void writeMover(const Object& obj, Message& msg) {
		msg << float(accel);
		if(rotSpeed == shipRotSpeed) {
			msg.write0();
		}
		else {
			msg.write1();
			msg << float(rotSpeed);
		}
		msg.writeBit(vectorMovement);
		
		if(targRot == targFacing) {
			msg.write1();
			msg.writeRotation(targRot);
		}
		else {
			msg.write0();
			msg.writeRotation(targRot);
			msg.writeRotation(targFacing);
		}
		
		msg << moving;
		msg << rotating;
		msg << FTL;
		if(FTL)
			msg << float(FTLSpeed);
		msg << inCombat;
		if(inCombat)
			msg.writeRotation(combatFacing);
		if(obj.hasSupportAI)
			msg << fleetRelative;

		uint pathCnt = path is null ? 0 : path.length;
		msg.writeBit(pathCnt != 0);
		if(pathCnt != 0) {
			msg.writeSmall(pathCnt);
			for(uint i = 0; i < pathCnt; ++i)
				msg << path[i];
		}

		if(lockTo !is null) {
			msg.write1();
			msg << lockTo;
			msg << isLocked;
			msg.writeSmallVec3(lockOffset);
		}
		else {
			msg.write0();
		}

		const Ship@ ship = cast<const Ship@>(obj);
		if(ship !is null) {
			msg.write1();
			if(ship.hasLeaderAI)
				msg.writeRotation(ship.formationDest);
			else if(fleetRelative)
				msg.writeSmallVec3(ship.formationDest.xyz);
		}
		else {
			msg.write0();
		}

		if(target !is null) {
			msg.write1();
			msg << target;
			msg << float(targDist);
		}
		else {
			msg.write0();
			if(!FTL && obj.hasSupportAI) {
				if(!fleetRelative)
					msg.writeSmallVec3(destination);
			}
			else {
				msg.writeMedVec3(destination);
			}
		}
	}

	void readMover(Object& obj, Message& msg) {
		accel = msg.read_float();
		if(msg.readBit())
			rotSpeed = msg.read_float();
		else
			rotSpeed = shipRotSpeed;
		vectorMovement = msg.readBit();
		
		if(msg.readBit()) {
			targFacing = msg.readRotation();
			targRot = targFacing;
		}
		else {
			targRot = msg.readRotation();
			targFacing = msg.readRotation();
		}

		msg >> moving;
		msg >> rotating;
		++moveID;
		bool prevFTL = FTL;
		msg >> FTL;
		if(FTL)
			FTLSpeed = msg.read_float();
		
		msg >> inCombat;
		if(inCombat)
			combatFacing = msg.readRotation();
		if(obj.hasSupportAI)
			msg >> fleetRelative;

		uint pathCnt = 0;
		if(msg.readBit())
			pathCnt = msg.readSmall();
		if(pathCnt == 0)
			@path = null;
		else {
			if(path is null)
				@path = array<PathNode@>();
			path.length = pathCnt;
			for(uint i = 0; i < pathCnt; ++i) {
				if(path[i] is null)
					@path[i] = PathNode();
				msg >> path[i];
			}
		}
		
		if(prevFTL && !FTL)
			obj.velocity = vec3d();

		if(msg.readBit()) {
			msg >> lockTo;
			msg >> isLocked;
			lockOffset = msg.readSmallVec3();
		}
		else {
			@lockTo = null;
		}

		if(msg.readBit()) {
			Ship@ ship = cast<Ship>(obj);
			if(ship.hasLeaderAI)
				ship.formationDest = msg.readRotation();
			else if(fleetRelative)
				ship.formationDest.xyz = msg.readSmallVec3();
		}

		if(msg.readBit()) {
			msg >> target;
			float td = 0;
			msg >> td;
			targDist = td;
		}
		else {
			if(!FTL && obj.hasSupportAI) {
				if(!fleetRelative)
					destination = msg.readSmallVec3();
			}
			else {
				destination = msg.readMedVec3();
			}
			@target = null;
		}
	}
};
