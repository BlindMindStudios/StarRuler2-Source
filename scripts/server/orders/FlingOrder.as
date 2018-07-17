import orders.Order;
import resources;
import attributes;
import ftl;

tidy class FlingOrder : Order {
	Object@ beacon;
	vec3d destination;
	quaterniond facing;
	double charge = 0.0;
	int cost = 0;
	double speed = 0.0;
	int moveId = -1;

	FlingOrder(Object& beacon, vec3d pos) {
		@this.beacon = beacon;
		destination = pos;
	}

	FlingOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> facing;
		msg >> moveId;
		msg >> charge;
		msg >> cost;
		msg >> beacon;
		msg >> speed;
	}

	void save(SaveFile& msg) override {
		Order::save(msg);
		msg << destination;
		msg << facing;
		msg << moveId;
		msg << charge;
		msg << cost;
		msg << beacon;
		msg << speed;
	}

	OrderType get_type() override {
		return OT_Fling;
	}

	string get_name() override {
		return "Flinging";
	}

	bool cancel(Object& obj) override {
		//Cannot cancel while already ftling
		if(charge >= FLING_CHARGE_TIME || charge < 0.0)
			return false;

		//Refund a part of the ftl cost
		if(cost > 0) {
			double pct = 1.0 - min(charge / FLING_CHARGE_TIME, 1.0);
			double refund = cost * pct;
			obj.owner.modFTLStored(refund);
			cost = 0;
		}

		//Mark ship as no longer FTLing
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.isFTLing = false;
		return true;
	}

	bool get_hasMovement() override {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) override {
		return destination;
	}

	OrderStatus tick(Object& obj, double time) override {
		if(!obj.hasMover || !canFling(obj))
			return OS_COMPLETED;

		//Pay for the FTL
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null && ship.delayFTL && charge >= 0) {
			if(charge > 0)
				charge = 0.001;
			return OS_BLOCKING;
		}
		if(charge == 0) {
			cost = flingCost(obj, destination);
			speed = flingSpeed(obj, destination);

			if(cost > 0) {
				double consumed = obj.owner.consumeFTL(cost, false, record=false);
				if(consumed < cost)
					return OS_COMPLETED;
			}
			charge = 0.001;

			//Make sure we have a beacon in range
			if(beacon is null || beacon.position.distanceToSQ(obj.position) > FLING_BEACON_RANGE_SQ) {
				@beacon = obj.owner.getClosestFlingBeacon(obj.position);
				if(beacon is null || beacon.position.distanceToSQ(obj.position) > FLING_BEACON_RANGE_SQ)
					return OS_COMPLETED;
			}

			//Mark ship as FTLing
			if(ship !is null)
				ship.isFTLing = true;

			//Calculate needed facing
			facing = quaterniond_fromVecToVec(vec3d_front(), destination - obj.position);
			obj.stopMoving();
			
			playParticleSystem("FTLCharge", vec3d(), quaterniond(), obj.radius * 4.0, obj);
		}

		//Wait for the facing to complete
		if(charge > 0.0) {
			bool isFacing = obj.rotateTo(facing, moveId);

			//Charge up the ftl drive for a while first
			if(charge < FLING_CHARGE_TIME)
				charge += time;

			if(!isFacing) {
				return OS_BLOCKING;
			}
			else {
				if(charge < FLING_CHARGE_TIME)
					return OS_BLOCKING;

				charge = -1.0;
				moveId = -1;

				if(cost > 0)
					obj.owner.modAttribute(EA_FTLEnergySpent, AC_Add, cost);
			}
		}

		//Do actual flinging
		bool wasMoving = moveId != -1;
		bool arrived = obj.FTLTo(destination, speed, moveId);
		if(!wasMoving) {
			if(obj.hasOrbit)
				obj.stopOrbit();

			obj.idleAllSupports();
			//Order supports to ftl
			uint cnt = obj.supportCount;
			for(uint i = 0; i < cnt; ++i) {
				Object@ support = obj.supportShip[i];
				support.FTLTo(destination + (support.position - obj.position), speed);
			}
			
			playParticleSystem("FTLEnter", obj.position, obj.rotation, obj.radius * 4.0, obj.visibleMask);
		}

		if(arrived) {
			if(ship !is null) {
				//Flag ship as no longer in ftl
				ship.blueprint.clearTracking(ship);
				ship.isFTLing = false;
			}

			//Clear tracking on arrival
			uint cnt = obj.supportCount;
			for(uint i = 0; i < cnt; ++i) {
				Ship@ support = cast<Ship>(obj.supportShip[i]);
				support.FTLTo(destination + (support.position - obj.position), speed);
				support.blueprint.clearTracking(support);
			}
			//Set rotation on arrival
			obj.setRotation(facing);
			return OS_COMPLETED;
		}
		else {
			//Check for dropping out of ftl
			Region@ reg = getRegion(obj.position);
			if(reg !is null && obj.owner !is null) {
				if(reg.BlockFTLMask & obj.owner.mask != 0) {
					obj.FTLDrop();
					uint cnt = obj.supportCount;
					for(uint i = 0; i < cnt; ++i) {
						Object@ support = obj.supportShip[i];
						if(support !is null)
							support.FTLDrop();
					}

					if(obj.orderCount == 1)
						obj.addMoveOrder(destination, true);
					return OS_COMPLETED;
				}
			}
			return OS_BLOCKING;
		}
	}
};
