import orders.Order;
import resources;
import attributes;
import ftl;

tidy class HyperdriveOrder : Order {
	vec3d destination;
	quaterniond facing;
	double charge = 0.0;
	int cost = 0;
	int moveId = -1;

	HyperdriveOrder(vec3d pos) {
		destination = pos;
	}

	HyperdriveOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> facing;
		msg >> moveId;
		msg >> charge;
		msg >> cost;
	}

	void save(SaveFile& msg) override {
		Order::save(msg);
		msg << destination;
		msg << facing;
		msg << moveId;
		msg << charge;
		msg << cost;
	}

	OrderType get_type() override {
		return OT_Hyperdrive;
	}

	string get_name() override {
		return "Hyperdrifting";
	}

	bool cancel(Object& obj) override {
		//Cannot cancel while already ftling
		if(charge >= HYPERDRIVE_CHARGE_TIME || charge < 0.0)
			return false;

		//Refund a part of the ftl cost
		if(cost > 0) {
			double pct = 1.0 - min(charge / HYPERDRIVE_CHARGE_TIME, 1.0);
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
		if(!obj.hasMover)
			return OS_COMPLETED;

		//Pay for the FTL
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null && ship.delayFTL && charge >= 0) {
			if(charge > 0)
				charge = 0.001;
			return OS_BLOCKING;
		}
		if(charge == 0) {
			int scale = 1;
			if(ship !is null) {
				scale = ship.blueprint.design.size;
				if(ship.group !is null)
					scale *= ship.group.objectCount;
			}

			double dist = obj.position.distanceTo(destination);
			cost = hyperdriveCost(ship, destination);

			if(cost > 0) {
				double consumed = obj.owner.consumeFTL(cost, false, record=false);
				if(consumed < cost)
					return OS_COMPLETED;
			}
			charge = 0.001;

			//Mark ship as FTLing
			if(ship !is null)
				ship.isFTLing = true;

			//Calculate needed facing
			facing = quaterniond_fromVecToVec(vec3d_front(), destination - obj.position);
			obj.stopMoving();
			
			if(obj.owner.HyperdriveNeedCharge != 0)
				playParticleSystem("FTLCharge", vec3d(), quaterniond(), obj.radius * 4.0, obj);
		}

		//Wait for the facing to complete
		if(charge > 0.0) {
			bool isFacing = obj.rotateTo(facing, moveId);

			double chargeTime = HYPERDRIVE_CHARGE_TIME;
			if(obj.owner.HyperdriveNeedCharge == 0)
				chargeTime = 0.0;

			//Charge up the hyperdrive for a while first
			if(charge < chargeTime)
				charge += time;

			if(!isFacing) {
				return OS_BLOCKING;
			}
			else {
				if(charge < chargeTime)
					return OS_BLOCKING;

				charge = -1.0;
				moveId = -1;

				if(cost > 0)
					obj.owner.modAttribute(EA_FTLEnergySpent, AC_Add, cost);
			}
		}

		//Do actual hyperdriving
		double speed = hyperdriveSpeed(obj);
		bool wasMoving = moveId != -1;
		bool arrived = obj.FTLTo(destination, speed, moveId);
		if(!wasMoving) {
			obj.idleAllSupports();
			//Order supports to ftl
			uint cnt = obj.supportCount;
			for(uint i = 0; i < cnt; ++i) {
				Object@ support = obj.supportShip[i];
				support.FTLTo(destination + (support.position - obj.position), speed);
			}
			
			playParticleSystem("FTLEnter", obj.position, obj.rotation, obj.radius * 4.0, obj.visibleMask);
		}
		else {
			if(speed != obj.ftlSpeed) {
				obj.ftlSpeed = speed;
				uint cnt = obj.supportCount;
				for(uint i = 0; i < cnt; ++i) {
					Object@ support = obj.supportShip[i];
					support.ftlSpeed = speed;
				}
			}
		}

		if(arrived) {
			//Flag ship as no longer in ftl
			if(ship !is null) {
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
			//Check for dropping out of hyperdrive
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
