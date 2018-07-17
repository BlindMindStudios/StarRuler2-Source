import orders.Order;
import saving;

tidy class AttackOrder : Order {
	Object@ target;
	int moveId = -1;
	uint flags = TF_Preference;
	bool movement = true;
	double minRange = 0;
	quaterniond facing;

	bool isBound = false;
	vec3d boundPos;
	double boundDistance = 0;
	vec3d fleePos;
	bool closeIn = false;
	bool dodgeObstacle = false;

	AttackOrder(Object& targ, double engagementRange) {
		minRange = engagementRange;
		@target = targ;
	}

	AttackOrder(Object& targ, double engagementRange, const vec3d bindPosition, double bindDistance, bool closeIn) {
		minRange = engagementRange;
		@target = targ;
		boundPos = bindPosition;
		boundDistance = bindDistance;
		isBound = true;
		this.closeIn = closeIn;
	}

	bool get_hasMovement() {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) {
		return target.position;
	}

	AttackOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> target;
		msg >> moveId;
		msg >> flags;
		msg >> movement;
		msg >> minRange;
		if(msg >= SV_0062) {
			msg >> isBound;
			msg >> boundPos;
			msg >> boundDistance;
			msg >> fleePos;
		}
		if(msg >= SV_0066)
			msg >> closeIn;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << target;
		msg << moveId;
		msg << flags;
		msg << movement;
		msg << minRange;
		msg << isBound;
		msg << boundPos;
		msg << boundDistance;
		msg << fleePos;
		msg << closeIn;
	}

	string get_name() {
		return "Attack " + target.name;
	}

	OrderType get_type() {
		return OT_Attack;
	}

	OrderStatus tick(Object& obj, double time) {
		if(!obj.hasMover)
			return OS_COMPLETED;

		//Switch targets if targeting a group
		if(target is null || !target.valid) {
			//Only complete the order if we're out
			//of combat, so we don't mess up the
			//combat positioning
			if(obj.inCombat && flags & TF_Group != 0) {
				if(moveId != -1) {
					obj.stopMoving();
					moveId = -1;
				}
				return OS_BLOCKING;
			}
			return OS_COMPLETED;
		}

		if(!target.memorable && !target.isVisibleTo(obj.owner)) {
			if(moveId != -1) {
				obj.stopMoving();
				moveId = -1;
			}
			return OS_COMPLETED;
		}
		
		if(!target.isVisibleTo(obj.owner) && (!target.memorable || !target.isKnownTo(obj.owner))) {
			if(moveId != -1) {
				obj.stopMoving();
				moveId = -1;
			}
			return OS_COMPLETED;
		}

		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return OS_COMPLETED;

		Empire@ myOwner = obj.owner;
		Empire@ targOwner = target.owner;
		if(myOwner is null || targOwner is null || !myOwner.isHostile(targOwner)) {
			if(moveId != -1) {
				obj.stopMoving();
				moveId = -1;
			}
			return OS_COMPLETED;
		}

		//Set effector targets
		ship.blueprint.target(obj, target, flags);

		double distSQ = obj.position.distanceToSQ(target.position);
		if(distSQ > minRange * minRange) {
			if(!movement)
				return OS_COMPLETED;
			if(moveId == -1)
				facing = quaterniond_fromVecToVec(vec3d_front(), target.position - obj.position);
			if(obj.moveTo(target, moveId, minRange * 0.9, enterOrbit=false))
				obj.setRotation(facing);
			fleePos = vec3d();
		}
		else if(closeIn && distSQ < (minRange * 0.75) * (minRange * 0.75)) {
			if(!movement)
				return OS_COMPLETED;
			if(moveId == -1)
				facing = quaterniond_fromVecToVec(vec3d_front(), target.position - obj.position);

			//Calculate the position we would be going to
			if(!fleePos.zero) {
				if(obj.moveTo(fleePos, moveId, doPathing=false, enterOrbit=false))
					fleePos = vec3d();
			}
			else {
				if(!isBound) {
					Region@ reg = obj.region;
					if(reg !is null) {
						boundPos = reg.position;
						boundDistance = reg.radius;
						isBound = true;
					}
				}
				if(isBound) {
					vec3d offset = (obj.position - target.position).normalized(minRange);
					vec3d destPos = target.position + offset;
					if(destPos.distanceToSQ(boundPos) > boundDistance * boundDistance * 0.95 * 0.95) {
						double angle = randomd(pi*0.4,pi*0.6) * (randomi(0,1) == 0 ? -1.0 : 1.0);
						auto rot = quaterniond_fromAxisAngle(vec3d_up(), angle);
						fleePos = target.position + rot * offset;
						moveId = -1;
						return OS_BLOCKING;
					}
				}

				if(obj.moveTo(target, moveId, minRange, enterOrbit=false))
					obj.setRotation(facing);
			}
		}
		else if(dodgeObstacle) {
			if(moveId == -1 || !obj.isOnMoveOrder(moveId))
				dodgeObstacle = false;
		}
		else {
			fleePos = vec3d();
			if(moveId != -1) {
				obj.stopMoving(enterOrbit=false);
				moveId = -1;
			}
			else {
				line3dd line(obj.position, target.position);
				auto@ blocker = trace(line, obj.owner.hostileMask | 0x1);
				if(blocker !is null && blocker !is target && (blocker.isPlanet || blocker.isStar)) {
					//Move to a position that gets us around the obstacle
					double dist = (blocker.radius + obj.radius * 2.0) * 1.2;
					vec3d to = line.getClosestPoint(blocker.position, false);
					if(to != blocker.position)
						to = blocker.position + (to - blocker.position).normalized(dist);
					else
						to = blocker.position + quaterniond_fromAxisAngle(line.direction, randomd(-pi,pi)) * line.direction.cross(vec3d_up()).normalized(dist);
					obj.moveTo(to, moveId, false, false);
					dodgeObstacle = true;
				}
			}
		}

		return OS_BLOCKING;
	}
};
