import orders.Order;

tidy class WaitOrder : Order {
	Object@ waitTarget;
	bool moveTo = false;
	int moveId = -1;

	WaitOrder(Object@ waitFor, bool moveTo) {
		@waitTarget = waitFor;
		this.moveTo = moveTo;
	}

	WaitOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> waitTarget;
		msg >> moveTo;
		msg >> moveId;
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << waitTarget;
		msg << moveTo;
		msg << moveId;
	}

	OrderType get_type() {
		return OT_Wait;
	}

	string get_name() {
		return "Waiting";
	}

	bool get_hasMovement() {
		return waitTarget !is null && waitTarget.valid;
	}

	vec3d getMoveDestination(const Object& obj) override {
		if(waitTarget is null || !waitTarget.valid)
			return vec3d();
		return waitTarget.position;
	}

	OrderStatus tick(Object& obj, double time) {
		if(moveTo && waitTarget !is null && waitTarget.valid)
			obj.moveTo(waitTarget, moveId, 0.0);
		return OS_BLOCKING;
	}
};
