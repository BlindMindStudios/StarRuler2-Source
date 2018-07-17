// Movement
// --------
// Manages FTL travel modes, expenditure of FTL energy, and general movement patterns.
//

import empire_ai.weasel.WeaselAI;

import oddity_navigation;
import ftl;

enum FTLReturn {
	F_Pass,
	F_Continue,
	F_Done,
	F_Kill,
};

class FTL : AIComponent {
	uint order(MoveOrder& order) { return F_Pass; }
	uint tick(MoveOrder& order, double time) { return F_Pass; }
};

bool getNearPosition(Object& obj, Object& target, vec3d& pos, bool spread = false) {
	if(target !is null) {
		if(target.isPlanet) {
			Planet@ toPl = cast<Planet>(target);
			vec3d dir = obj.position - toPl.position;
			dir = dir.normalized(toPl.OrbitSize * 0.9);
			if(spread)
				dir = quaterniond_fromAxisAngle(vec3d_up(), randomd(-0.15,0.15) * pi) * dir;
			pos = toPl.position + dir;
			return true;
		}
		else if(obj.hasLeaderAI && (target.isShip || target.isOrbital)) {
			vec3d dir = obj.position - target.position;
			dir = dir.normalized(obj.getEngagementRange());
			pos = target.position + dir;
			return true;
		}
		else {
			Region@ reg = cast<Region>(target);
			if(reg is null)
				@reg = target.region;
			if(reg !is null) {
				vec3d dir = obj.position - reg.position;
				dir = dir.normalized(reg.radius * 0.85);
				if(spread)
					dir = quaterniond_fromAxisAngle(vec3d_up(), randomd(-0.15,0.15) * pi) * dir;
				pos = reg.position + dir;
				return true;
			}
		}
	}
	return false;
}

bool targetPosition(MoveOrder& ord, vec3d& toPosition) {
	if(ord.target !is null) {
		return getNearPosition(ord.obj, ord.target, toPosition);
	}
	else {
		toPosition = ord.position;
		return true;
	}
}

double usableFTL(AI& ai, MoveOrder& ord) {
	double storage = ai.empire.FTLCapacity;
	double avail = ai.empire.FTLStored;

	double reserved = 0.0;
	if(ord.priority < MP_Critical)
		reserved += ai.behavior.ftlReservePctCritical;
	if(ord.priority < MP_Normal)
		reserved += ai.behavior.ftlReservePctNormal;
	avail -= reserved * storage;

	return avail;
}

enum MovePriority {
	MP_Background,
	MP_Normal,
	MP_Critical
};

class MoveOrder {
	int id = -1;
	uint priority = MP_Normal;
	Object@ obj;
	Object@ target;
	vec3d position;
	bool completed = false;
	bool failed = false;

	void save(Movement& movement, SaveFile& file) {
		file << priority;
		file << obj;
		file << target;
		file << position;
		file << completed;
		file << failed;
	}

	void load(Movement& movement, SaveFile& file) {
		file >> priority;
		file >> obj;
		file >> target;
		file >> position;
		file >> completed;
		file >> failed;
	}

	void cancel() {
		failed = true;
		obj.clearOrders();
	}

	bool tick(AI& ai, Movement& movement, double time) {
		//Check if we still exist
		if(obj is null || !obj.valid || obj.owner !is ai.empire) {
			failed = true;
			return false;
		}

		uint ftlMode = F_Pass;
		if(movement.ftl !is null) {
			ftlMode = movement.ftl.tick(this, time);
			if(ftlMode == F_Kill)
				return false;
			if(ftlMode == F_Done)
				return true;
		}

		//Check if we've arrived
		if(target !is null) {
			if(!target.valid) {
				failed = true;
				return false;
			}
			double targDist = target.radius + 45.0 + obj.radius;
			if(target.isRegion)
				targDist = target.radius * 0.86 + obj.radius;
			if(target.position.distanceTo(obj.position) < targDist) {
				completed = true;
				return false;
			}
		}
		else {
			double targDist = obj.radius * 2.0;
			if(obj.position.distanceTo(position) < targDist) {
				completed = true;
				return false;
			}
		}

		//Fail out if our order failed
		if(ftlMode == F_Pass) {
			if(!obj.hasOrders) {
				failed = true;
				return false;
			}
		}

		return true;
	}
};

class Movement : AIComponent {
	int nextMoveOrderId = 0;
	array<MoveOrder@> moveOrders;

	array<Oddity@> oddities;

	FTL@ ftl;

	void create() {
		@ftl = cast<FTL>(ai.ftl);
	}

	void save(SaveFile& file) {
		file << nextMoveOrderId;

		uint cnt = moveOrders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveMoveOrder(file, moveOrders[i]);
			moveOrders[i].save(this, file);
		}
	}

	void load(SaveFile& file) {
		file >> nextMoveOrderId;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ ord = loadMoveOrder(file);
			if(ord !is null) {
				ord.load(this, file);
				if(ord.obj !is null)
					moveOrders.insertLast(ord);
			}
			else {
				MoveOrder().load(this, file);
			}
		}
	}

	array<MoveOrder@> loadIds;
	MoveOrder@ loadMoveOrder(SaveFile& file) {
		int id = -1;
		file >> id;
		bool failed = false, completed = false;
		file >> failed;
		file >> completed;
		if(id == -1) {
			return null;
		}
		else {
			for(uint i = 0, cnt = loadIds.length; i < cnt; ++i) {
				if(loadIds[i].id == id)
					return loadIds[i];
			}
			MoveOrder data;
			data.id = id;
			data.failed = failed;
			data.completed = completed;
			loadIds.insertLast(data);
			return data;
		}
	}

	void saveMoveOrder(SaveFile& file, MoveOrder@ data) {
		int id = -1;
		bool failed = false, completed = false;
		if(data !is null) {
			id = data.id;
			failed = data.failed;
			completed = data.completed;
		}
		file << id;
		file << failed;
		file << completed;
	}

	void postLoad(AI& ai) {
		loadIds.length = 0;
		getOddityGates(oddities);
	}

	array<PathNode@> path;
	double getPathDistance(const vec3d& fromPosition, const vec3d& toPosition, double accel = 1.0) {
		pathOddityGates(oddities, ai.empire, path, fromPosition, toPosition, accel);
		return ::getPathDistance(fromPosition, toPosition, path);
	}

	double eta(Object& obj, Object& toObject, uint priority = MP_Normal) {
		return eta(obj, toObject.position, priority);
	}

	double eta(Object& obj, const vec3d& position, uint priority = MP_Normal) {
		//TODO: Use FTL
		//TODO: Path through gates/wormholes
		return newtonArrivalTime(obj.maxAcceleration, position - obj.position, obj.velocity);
	}

	void order(MoveOrder& ord) {
		if(ord.target !is null && ord.target is ord.obj.region)
			return;

		bool madeOrder = false;

		if(ftl !is null) {
			uint mode = ftl.order(ord);
			if(mode == F_Kill || mode == F_Done)
				return;
			madeOrder = (mode == F_Continue);
		}

		if(ord.target !is null) {
			ord.obj.addGotoOrder(ord.target, append=madeOrder);
			ord.position = ord.target.position;
		}
		else
			ord.obj.addMoveOrder(ord.position, append=madeOrder);
	}

	void add(MoveOrder& ord) {
		for(uint i = 0, cnt = moveOrders.length; i < cnt; ++i) {
			if(moveOrders[i].obj is ord.obj) {
				moveOrders[i].failed = true;
				moveOrders.removeAt(i);
				--i; --cnt;
			}
		}

		moveOrders.insertLast(ord);
		order(ord);
	}

	MoveOrder@ move(Object& obj, Object& toObject, uint priority = MP_Normal, bool spread = false, bool nearOnly = false) {
		if(toObject.isRegion) {
			if(obj.region is toObject)
				nearOnly = false;
			else
				nearOnly = true;
		}
		if(nearOnly) {
			vec3d pos;
			bool canNear = getNearPosition(obj, toObject, pos, spread);
			if(canNear)
				return move(obj, pos, priority);
		}

		MoveOrder ord;
		ord.id = nextMoveOrderId++;
		@ord.obj = obj;
		@ord.target = toObject;
		ord.priority = priority;

		add(ord);
		return ord;
	}

	MoveOrder@ move(Object& obj, const vec3d& position, uint priority = MP_Normal, bool spread = false) {
		MoveOrder ord;
		ord.id = nextMoveOrderId++;
		@ord.obj = obj;
		ord.position = position;
		ord.priority = priority;

		add(ord);
		return ord;
	}

	void tick(double time) override {
		for(uint i = 0, cnt = moveOrders.length; i < cnt; ++i) {
			if(!moveOrders[i].tick(ai, this, time)) {
				moveOrders.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void focusTick(double time) override {
		//Update our gate navigation list
		getOddityGates(oddities);
	}
};

AIComponent@ createMovement() {
	return Movement();
}
