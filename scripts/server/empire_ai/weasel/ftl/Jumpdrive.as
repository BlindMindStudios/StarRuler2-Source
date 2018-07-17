import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Development;
import empire_ai.weasel.Fleets;

import ftl;
import system_flags;
import regions.regions;
import systems;

from orders import OrderType;

const double REJUMP_MIN_DIST = 8000.0;

class Jumpdrive : FTL {
	Development@ development;
	Fleets@ fleets;

	int safetyFlag = -1;
	array<Region@> safeRegions;

	void create() override {
		@development = cast<Development>(ai.development);
		@fleets = cast<Fleets>(ai.fleets);

		safetyFlag = getSystemFlag("JumpdriveSafety");
	}

	void save(SaveFile& file) {
		uint cnt = safeRegions.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << safeRegions[i];
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		safeRegions.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> safeRegions[i];
	}

	double jdETA(Object& obj, const vec3d& position) {
		double charge = JUMPDRIVE_CHARGE_TIME;
		return charge;
	}

	double subETA(Object& obj, const vec3d& position) {
		return newtonArrivalTime(obj.maxAcceleration, position - obj.position, vec3d());
	}
	
	bool shouldJD(Object& obj, const vec3d& position, uint priority) {
		//This makes me sad
		if(position.distanceTo(obj.position) < 3000)
			return false;
		return true;

		/*double factor = 0.8;*/
		/*if(priority == MP_Critical)*/
		/*	factor = 1.0;*/
		/*return jdETA(obj, position) <= factor * subETA(obj, position);*/
	}

	uint order(MoveOrder& ord) override {
		return order(ord, ord.obj.position, false);
	}

	uint order(MoveOrder& ord, const vec3d& fromPos, bool secondary) {
		if(!canJumpdrive(ord.obj))
			return F_Pass;

		double avail = usableFTL(ai, ord);
		if(avail > 0) {
			vec3d toPosition;
			if(targetPosition(ord, toPosition)) {
				double maxRange = jumpdriveRange(ord.obj);
				double dist = toPosition.distanceTo(fromPos);

				bool isSafe = false;
				Region@ reg = getRegion(toPosition);
				if(reg !is null)
					isSafe = reg.getSystemFlag(ai.empire, safetyFlag);

				if(dist > maxRange && !isSafe) {
					//See if we should jump to a safe region first
					if(!secondary) {
						double bestHop = INFINITY;
						Region@ hopRegion;
						vec3d bestPos;
						for(uint i = 0, cnt = safeRegions.length; i < cnt; ++i) {
							if(!safeRegions[i].getSystemFlag(ai.empire, safetyFlag))
								continue;
							vec3d hopPos = safeRegions[i].position;
							hopPos = hopPos + (fromPos-hopPos).normalized(safeRegions[i].radius * 0.85);
							double d = hopPos.distanceTo(toPosition);
							if(d < bestHop) {
								bestHop = d;
								@hopRegion = safeRegions[i];
								bestPos = hopPos;
							}
						}

						if(bestHop < dist * 0.8) {
							double cost = jumpdriveCost(ord.obj, fromPos, bestPos);
							if(avail >= cost) {
								ord.obj.addJumpdriveOrder(bestPos);
								order(ord, bestPos, true);
								return F_Continue;
							}
						}
					}

					//Shorten our jump
					if(ord.priority < MP_Normal)
						return F_Pass;
					toPosition = fromPos + (toPosition - fromPos).normalized(maxRange);
				}

				if(shouldJD(ord.obj, toPosition, ord.priority)) {
					double cost = jumpdriveCost(ord.obj, toPosition);
					if(avail >= cost) {
						ord.obj.addJumpdriveOrder(toPosition, append=secondary);
						return F_Continue;
					}
				}
			}
		}

		return F_Pass;
	}

	uint tick(MoveOrder& ord, double time) {
		if(ord.priority == MP_Critical && canJumpdrive(ord.obj) && ord.obj.firstOrderType != OT_Jumpdrive) {
			vec3d toPosition;
			if(targetPosition(ord, toPosition)) {
				double dist = ord.obj.position.distanceToSQ(toPosition);
				if(dist > REJUMP_MIN_DIST * REJUMP_MIN_DIST) {
					double maxRange = jumpdriveRange(ord.obj);
					dist = sqrt(dist);

					bool isSafe = false;
					Region@ reg = getRegion(toPosition);
					if(reg !is null)
						isSafe = reg.getSystemFlag(ai.empire, safetyFlag);

					if(dist > maxRange && !isSafe)
						toPosition = ord.obj.position + (toPosition - ord.obj.position).normalized(maxRange);

					if(shouldJD(ord.obj, toPosition, ord.priority)) {
						double avail = usableFTL(ai, ord);
						double cost = jumpdriveCost(ord.obj, toPosition);
						if(avail >= cost) {
							cast<Movement>(ai.movement).order(ord);
							return F_Continue;
						}
					}
				}
			}
		}
		return F_Pass;
	}

	uint sysChk = 0;
	void start() {
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			Region@ reg = getSystem(i).object;
			if(reg.getSystemFlag(ai.empire, safetyFlag))
				safeRegions.insertLast(reg);
		}
	}

	void focusTick(double time) override {
		//Try to get enough ftl storage that we can ftl our largest fleet a fair distance and have some remaining
		double highestCost = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.fleetClass != FC_Combat)
				continue;
			double dist = jumpdriveRange(flAI.obj);
			vec3d toPosition = flAI.obj.position + vec3d(0, 0, dist);
			highestCost = max(highestCost, double(jumpdriveCost(flAI.obj, toPosition)));
		}
		development.aimFTLStorage = highestCost / (1.0 - ai.behavior.ftlReservePctCritical - ai.behavior.ftlReservePctNormal);

		//Disable systems that are no longer safe
		for(uint i = 0, cnt = safeRegions.length; i < cnt; ++i) {
			if(!safeRegions[i].getSystemFlag(ai.empire, safetyFlag)) {
				safeRegions.removeAt(i);
				--i; --cnt;
			}
		}

		//Try to find regions that are safe for us
		{
			sysChk = (sysChk+1) % systemCount;
			auto@ reg = getSystem(sysChk).object;
			if(reg.getSystemFlag(ai.empire, safetyFlag)) {
				if(safeRegions.find(reg) == -1)
					safeRegions.insertLast(reg);
			}
		}
	}
};

AIComponent@ createJumpdrive() {
	return Jumpdrive();
}
