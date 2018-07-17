import orders.Order;

tidy class OddityGateOrder : Order {
	Oddity@ target;
	int moveId = -1;

	OddityGateOrder(Oddity& targ) {
		@target = targ;
		moveId = -1;
	}

	OddityGateOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> target;
		msg >> moveId;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << target;
		msg << moveId;
	}

	OrderType get_type() {
		return OT_OddityGate;
	}

	string get_name() {
		return "Warp with " + target.name;
	}

	bool get_hasMovement() {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) {
		return target.position;
	}

	OrderStatus tick(Object& obj, double time) {
		if(!obj.hasMover)
			return OS_COMPLETED;
		if(!target.isGate())
			return OS_COMPLETED;

		if(obj.moveTo(target, moveId, target.radius + obj.radius, enterOrbit=false)) {
			vec3d toPos = target.getGateDest();
			if(toPos == vec3d())
				return OS_COMPLETED;

			if(obj.hasLeaderAI) {
				obj.teleportTo(toPos);
			}
			else {
				obj.position = toPos;
				obj.wake();
			}
			return OS_COMPLETED;
		}

		return OS_BLOCKING;
	}
};
