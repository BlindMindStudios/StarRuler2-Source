import orders.Order;
from regions.regions import getRegion;
import resources;
import attributes;
import system_flags;
import ftl;

tidy class JumpdriveOrder : Order {
	vec3d destination;
	quaterniond facing;
	double charge = 0.0;
	int cost = 0;
	int moveId = -1;

	JumpdriveOrder(vec3d pos) {
		destination = pos;
	}

	JumpdriveOrder(SaveFile& msg) {
		Order::load(msg);
		msg >> destination;
		msg >> facing;
		msg >> moveId;
		msg >> charge;
		msg >> cost;
	}

	void save(SaveFile& msg) override {
		Order::save(msg);
		msg << destination;
		msg << facing;
		msg << moveId;
		msg << charge;
		msg << cost;
	}

	OrderType get_type() override {
		return OT_Jumpdrive;
	}

	string get_name() override {
		return "Jumping";
	}

	bool cancel(Object& obj) override {
		//Cannot cancel while already ftling
		if(charge >= JUMPDRIVE_CHARGE_TIME || charge < 0.0)
			return false;

		//Refund a part of the ftl cost
		if(cost > 0) {
			double pct = 1.0 - min(charge / JUMPDRIVE_CHARGE_TIME, 1.0);
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
			cost = jumpdriveCost(ship, destination);

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
			
			playParticleSystem("JumpCharge", vec3d(), quaterniond(), obj.radius * 4.0, obj);
		}

		//Wait for the facing to complete
		if(charge > 0.0) {
			bool isFacing = obj.rotateTo(facing, moveId);

			//Charge up the jumpdrive for a while first
			if(charge < JUMPDRIVE_CHARGE_TIME)
				charge += time;

			if(!isFacing) {
				return OS_BLOCKING;
			}
			else {
				if(charge < JUMPDRIVE_CHARGE_TIME)
					return OS_BLOCKING;

				charge = -1.0;
				moveId = -1;

				if(cost > 0)
					obj.owner.modAttribute(EA_FTLEnergySpent, AC_Add, cost);
			}
		}

		//Teleport to destination
		vec3d exitPos = destination;
		double distance = destination.distanceTo(obj.position);

		auto@ destRegion = getRegion(destination);

		double range = 10000;
		if(ship !is null)
			range = ship.blueprint.design.total(SV_JumpRange);

		if(distance > range && (destRegion is null || !destRegion.getSystemFlag(obj.owner, safetyFlag))) {
			//Random offset based on over-distance
			double minOffset = 0.0;
			double maxOffset = (distance - range) * 0.25;
			vec2d offset = random2d(randomd(minOffset, maxOffset));
			exitPos += vec3d(offset.x, 0, offset.y);

			//Random damage based on over-distance
			if(ship !is null) {
				int hits = min(int(floor((distance - range) / range * 25.0)), 100);
				for(int i = 0; i < hits; ++i) {
					DamageEvent dmg;
					dmg.damage = randomd(0.01, 0.03) * ship.blueprint.design.totalHP;
					@dmg.obj = obj;
					@dmg.target = obj;

					obj.damage(dmg, -1.0, random2d(1.0));
				}
			}
		}

		playParticleSystem("FTLEnter", obj.position, obj.rotation, obj.radius * 4.0, obj.visibleMask);
		playParticleSystem("FTLExit", exitPos, obj.rotation, obj.radius * 4.0, obj.visibleMask);

		if(obj.hasOrbit && obj.inOrbit) {
			obj.stopOrbit();
			obj.position = exitPos;
			obj.remakeStandardOrbit();
		}
		else if(obj.hasLeaderAI) {
			obj.teleportTo(exitPos, true);
			int dummy = -1;
			obj.moveTo(exitPos, dummy);
		}

		//Flag ship as no longer in ftl
		if(ship !is null) {
			ship.blueprint.clearTracking(ship);
			ship.isFTLing = false;
		}
		obj.idleAllSupports();

		//Clear tracking on arrival
		uint cnt = obj.supportCount;
		for(uint i = 0; i < cnt; ++i) {
			Ship@ support = cast<Ship>(obj.supportShip[i]);
			support.blueprint.clearTracking(support);
		}

		//Set rotation on arrival
		obj.setRotation(facing);

		return OS_COMPLETED;
	}
};

int safetyFlag = -1;
void init() {
	safetyFlag = getSystemFlag("JumpdriveSafety");
}
