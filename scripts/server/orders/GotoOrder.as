import orders.Order;

tidy class GotoOrder : Order {
	Object@ destination;
	float dist;
	int moveId;

	GotoOrder(Object& dest, float Distance = 0) {
		@destination = dest;
		dist = Distance;
		moveId = -1;
	}

	GotoOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> dist;
		msg >> moveId;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << destination;
		msg << dist;
		msg << moveId;
	}

	OrderType get_type() {
		return OT_Goto;
	}

	string get_name() {
		return "Go to " + destination.name;
	}

	bool get_hasMovement() {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) {
		return getMoveDestination(obj, destination, dist);
	}

	OrderStatus tick(Object& obj, double time) {
		if(!obj.hasMover)
			return OS_COMPLETED;

		if(obj.moveTo(destination, moveId, dist))
			return OS_COMPLETED;

		return OS_BLOCKING;
	}
};
