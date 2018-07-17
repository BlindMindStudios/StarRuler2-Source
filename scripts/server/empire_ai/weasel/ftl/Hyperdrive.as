import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Development;
import empire_ai.weasel.Fleets;

import ftl;

from orders import OrderType;

const double REJUMP_MIN_DIST = 8000.0;
const double STORAGE_AIM_DISTANCE = 40000;

class Hyperdrive : FTL {
	Development@ development;
	Fleets@ fleets;

	void create() override {
		@development = cast<Development>(ai.development);
		@fleets = cast<Fleets>(ai.fleets);
	}

	double hdETA(Object& obj, const vec3d& position) {
		double charge = HYPERDRIVE_CHARGE_TIME;
		if(obj.owner.HyperdriveNeedCharge == 0)
			charge = 0.0;
		double dist = position.distanceTo(obj.position);
		double speed = hyperdriveMaxSpeed(obj);
		return charge + dist / speed;
	}

	double subETA(Object& obj, const vec3d& position) {
		return newtonArrivalTime(obj.maxAcceleration, position - obj.position, vec3d());
	}
	
	bool shouldHD(Object& obj, const vec3d& position, uint priority) {
		//This makes me sad
		if(position.distanceTo(obj.position) < 3000)
			return false;
		double pathDist = cast<Movement>(ai.movement).getPathDistance(obj.position, position, obj.maxAcceleration);
		double straightDist = position.distanceTo(obj.position);
		return pathDist >= straightDist * 0.6;
	}

	uint order(MoveOrder& ord) override {
		if(!canHyperdrive(ord.obj))
			return F_Pass;

		double avail = usableFTL(ai, ord);
		if(avail > 0) {
			vec3d toPosition;
			if(targetPosition(ord, toPosition)) {
				if(shouldHD(ord.obj, toPosition, ord.priority)) {
					double cost = hyperdriveCost(ord.obj, toPosition);
					if(avail >= cost) {
						ord.obj.addHyperdriveOrder(toPosition);
						return F_Continue;
					}
				}
			}
		}

		return F_Pass;
	}

	uint tick(MoveOrder& ord, double time) {
		if(ord.priority == MP_Critical && canHyperdrive(ord.obj) && ord.obj.firstOrderType != OT_Hyperdrive) {
			vec3d toPosition;
			if(targetPosition(ord, toPosition)) {
				double dist = ord.obj.position.distanceToSQ(toPosition);
				if(dist > REJUMP_MIN_DIST * REJUMP_MIN_DIST) {
					double avail = usableFTL(ai, ord);
					double cost = hyperdriveCost(ord.obj, toPosition);
					if(avail >= cost && shouldHD(ord.obj, toPosition, ord.priority)) {
						cast<Movement>(ai.movement).order(ord);
						return F_Continue;
					}
				}
			}
		}
		return F_Pass;
	}

	void focusTick(double time) override {
		//Try to get enough ftl storage that we can ftl our largest fleet a fair distance and have some remaining
		double highestCost = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			vec3d toPosition = flAI.obj.position + vec3d(0, 0, STORAGE_AIM_DISTANCE);
			highestCost = max(highestCost, double(hyperdriveCost(flAI.obj, toPosition)));
		}
		development.aimFTLStorage = highestCost / (1.0 - ai.behavior.ftlReservePctCritical - ai.behavior.ftlReservePctNormal);
	}
};

AIComponent@ createHyperdrive() {
	return Hyperdrive();
}
