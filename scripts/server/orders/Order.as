import orders;
import regions.regions;

export OrderStatus;
export Order;
export OrderType;

enum OrderStatus {
	OS_BLOCKING,
	OS_NONBLOCKING,
	OS_COMPLETED
};

tidy class Order {
	Order@ prev, next;
	
	void destroy() {}

	string get_name() {
		return "N/A";
	}

	bool get_hasMovement() {
		return false;
	}

	vec3d getMoveDestination(const Object& obj) {
		return vec3d();
	}

	vec3d getMoveDestination(const Object& obj, Object@ target, double distance = 0.0) {

		vec3d objPos = obj.position;

		Order@ check = prev;
		if(check !is null) {
			while(check.prev !is null)
				@check = check.prev;
			objPos = check.getMoveDestination(obj);
		}

		double targDist;
		if(target.isRegion) {
			if(inRegion(cast<Region>(target), objPos))
				return objPos;
			targDist = target.radius * 0.85;
		}
		else
			targDist = max(distance, obj.radius + target.radius);

		vec3d dir = target.position - objPos;
		return objPos + dir.normalized(dir.length - targDist);
	}

	OrderType get_type() {
		return OT_INVALID;
	}

	OrderStatus tick(Object& obj, double time) {
		return OS_BLOCKING;
	}
	
	uint getIndex() const {
		const Order@ o = this;
		uint ind = 0;
		while(o.prev !is null) {
			++ind;
			@o = o.prev;
		}
		return ind;
	}

	bool cancel(Object& obj) {
		return true;
	}

	void writeDesc(const Object& obj, Message& msg) {
		msg << uint(type);

		bool hasMove = hasMovement;
		if(hasMove) {
			msg.write1();
			msg << getMoveDestination(obj);
		}
		else {
			msg.write0();
		}
	}

	void load(SaveFile& msg) {
	}

	void save(SaveFile& msg) {
		uint8 tp = type;
		msg << tp;
	}
};
