import orders.Order;

tidy class MoveOrder : Order {
	vec3d destination;
	quaterniond facing;
	int moveId = -1;
	int rotateId = -1;

	MoveOrder(vec3d Destination, quaterniond Facing) {
		destination = Destination;
		facing = Facing;
		facing.normalize();
	}

	MoveOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> facing;
		msg >> moveId;
		msg >> rotateId;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << destination;
		msg << facing;
		msg << moveId;
		msg << rotateId;
	}

	OrderType get_type() {
		return OT_Move;
	}

	string get_name() {
		return "Moving";
	}

	bool get_hasMovement() {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) override {
		return destination;
	}

	OrderStatus tick(Object& obj, double time) {
		if(!obj.hasMover)
			return OS_COMPLETED;

		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.formationDest = facing;
		if(obj.moveTo(destination, moveId)) {
			obj.setRotation(facing);
			return OS_COMPLETED;
		}

		return OS_BLOCKING;
	}
};
