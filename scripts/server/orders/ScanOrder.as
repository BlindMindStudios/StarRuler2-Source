import orders.Order;

tidy class ScanOrder : Order {
	Anomaly@ target;
	int moveId = -1;
	int64 beam = 0;

	ScanOrder(Anomaly& targ) {
		@target = targ;
		moveId = -1;
	}

	ScanOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> target;
		msg >> moveId;
	}
	
	~ScanOrder() {
		removeBeam();
	}

	void save(SaveFile& msg) {
		Order::save(msg);
		msg << target;
		msg << moveId;
	}

	OrderType get_type() {
		return OT_Scan;
	}

	string get_name() {
		return "Scan " + target.name;
	}

	bool get_hasMovement() {
		return true;
	}

	vec3d getMoveDestination(const Object& obj) {
		return target.position;
	}
	
	void removeBeam() {
		if(beam != 0) {
			removeGfxEffect(ALL_PLAYERS, beam);
			beam = 0;
		}
	}

	OrderStatus tick(Object& obj, double time) {
		if(!obj.hasMover || !target.valid || target.getEmpireProgress(obj.owner) >= 1.f) {
			removeBeam();
			return OS_COMPLETED;
		}
		
		if(obj.position.distanceTo(target.position) < 30.0 + target.radius + obj.radius) {
			target.addProgress(obj.owner, time);
			if(beam == 0) {
				beam = (obj.id << 32) | (0x2 << 24);
				makeBeamEffect(ALL_PLAYERS, beam, obj, target, 0xffffffff, obj.radius, "Tractor", -1.0);
			}
		}
		else {
			obj.moveTo(target, moveId, 15.0 + target.radius + obj.radius, enterOrbit=false);
			removeBeam();
		}

		return OS_BLOCKING;
	}
};
