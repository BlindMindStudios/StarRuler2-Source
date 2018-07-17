import orders.Order;
import pickups;

tidy class PickupOrder : Order {
	Object@ target;
	int moveId = -1;

	PickupOrder(Object& targ) {
		@target = targ;
	}

	PickupOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> target;
		msg >> moveId;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << target;
		msg << moveId;
	}

	string get_name() {
		return "Pickup Pickup";
	}

	OrderType get_type() {
		return OT_PickupOrder;
	}

	bool get_hasMovement() override {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) override {
		return target.position;
	}

	OrderStatus tick(Object& obj, double time) {
		Pickup@ pickup = cast<Pickup>(target);
		if(pickup is null || !pickup.valid)
			return OS_COMPLETED;

		const PickupType@ type = getPickupType(pickup.PickupType);
		if(!type.canPickup(pickup, obj))
			return OS_COMPLETED;

		if(obj.position.distanceTo(pickup.position) < 30.0 + obj.radius + pickup.radius) {
			if(moveId != -1) {
				obj.stopMoving();
				moveId = -1;
			}

			if(!pickup.isPickupProtected) {
				pickup.pickupPickup(obj);
				return OS_COMPLETED;
			}
			return OS_BLOCKING;
		}
		else if(!obj.hasMover) {
			return OS_COMPLETED;
		}
		else {
			obj.moveTo(target, moveId);
		}

		return OS_BLOCKING;
	}
};
