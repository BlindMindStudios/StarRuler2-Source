import orders.Order;
import resources;
import attributes;
import ftl;
from objects.Oddity import createSlipstream;
import movement;

tidy class SlipstreamOrder : Order {
	vec3d destination;
	quaterniond facing;
	double charge = 0.0;
	int cost = 0;
	int moveId = -1;
	array<Object@> secondary;

	SlipstreamOrder(vec3d pos) {
		destination = pos;
	}

	SlipstreamOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> facing;
		msg >> moveId;
		msg >> charge;
		msg >> cost;

		if(msg >= SV_0067) {
			uint cnt = 0;
			msg >> cnt;
			secondary.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> secondary[i];
		}
	}

	void save(SaveFile& msg) override {
		Order::save(msg);
		msg << destination;
		msg << facing;
		msg << moveId;
		msg << charge;
		msg << cost;

		uint cnt = secondary.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg << secondary[i];
		}
	}

	OrderType get_type() override {
		return OT_Slipstream;
	}

	string get_name() override {
		return "Generating Slipstream";
	}

	bool cancel(Object& obj) override {
		//Cannot cancel while already ftling
		if(charge >= SLIPSTREAM_CHARGE_TIME || charge < 0.0)
			return false;

		//Refund a part of the ftl cost
		if(cost > 0) {
			double pct = 1.0 - min(charge / SLIPSTREAM_CHARGE_TIME, 1.0);
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
		if(!canSlipstream(obj))
			return OS_COMPLETED;
		if(!canSlipstreamTo(obj, destination))
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
			cost = slipstreamCost(obj, scale, dist);

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

			playParticleSystem("FTLCharge", vec3d(), quaterniond(), obj.radius * 4.0, obj);
			playParticleSystem("FTLCharge", destination, quaterniond(), slipstreamInaccuracy(obj, destination) * 0.25);
		}

		if(charge > 0.0) {
			bool isFacing = obj.rotateTo(facing, moveId);

			//Charge up the slipstream drive for a while first
			if(charge < SLIPSTREAM_CHARGE_TIME)
				charge += time;

			if(!isFacing) {
				return OS_BLOCKING;
			}
			else {
				if(charge < SLIPSTREAM_CHARGE_TIME)
					return OS_BLOCKING;

				charge = -1.0;
				moveId = -1;

				if(cost > 0)
					obj.owner.modAttribute(EA_FTLEnergySpent, AC_Add, cost);
			}
		}

		//Generate the slipstream
		vec3d startPos = obj.position;
		startPos += (obj.rotation * vec3d_front()).normalized(obj.radius * 2.5 + 15.0);

		vec3d endPos = destination;
		slipstreamModifyPosition(obj, endPos);
		createSlipstream(startPos, endPos, slipstreamLifetime(obj), obj.owner);

		//Flag ship as no longer in ftl
		if(ship !is null) {
			ship.blueprint.clearTracking(ship);
			ship.isFTLing = false;
		}

		//Set movement
		if(secondary.length != 0) {
			vec3d movePos = destination;
			movePos += facing * vec3d_front() * obj.radius * 15.0;

			auto@ positions = getFleetTargetPositions(secondary, movePos, quaterniond_fromAxisAngle(vec3d_up(), pi) * facing);
			for(uint i = 0, cnt = secondary.length; i < cnt; ++i)
				secondary[i].moveAfterWait(positions[i], obj);
		}

		return OS_COMPLETED;
	}
};
