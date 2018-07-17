import orders.Order;
import pickups;

tidy class RefreshOrder : Order {
	Object@ target;
	int moveId = -1;

	RefreshOrder(Object& targ) {
		@target = targ;
	}

	RefreshOrder(SaveFile& msg) {
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
		return "Refresh Supports";
	}

	OrderType get_type() {
		return OT_Refresh;
	}

	bool get_hasMovement() override {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) override {
		Object@ moveTo = cast<Region>(target);
		if(moveTo is null)
			@moveTo = target.region;
		if(moveTo is null)
			@moveTo = target;
		return getMoveDestination(obj, moveTo);
	}

	OrderStatus tick(Object& obj, double time) {
		Object@ moveTo = cast<Region>(target);
		if(moveTo is null)
			@moveTo = target.region;
		if(moveTo is null)
			@moveTo = target;
		if(moveTo is obj.region || obj.moveTo(moveTo, moveId)) {
			obj.refreshSupportsFrom(target);
			return OS_COMPLETED;
		}
		return OS_BLOCKING;
	}
};
