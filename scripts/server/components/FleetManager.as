import saving;

int points(Object& fleet, double strength) {
	if(!fleet.isShip)
		return 0;
	double pts = ceil(sqrt(strength) * 5.0);
	if(cast<Ship>(fleet).isStation)
		pts *= 0.25;
	return pts;
}

tidy class FleetManager : Component_FleetManager, Savable {
	ReadWriteMutex fleetMutex;
	Object@[] fleetList;
	double[] strengths;
	int militaryPoints = 0;

	FleetManager() {
	}

	uint get_fleetCount() {
		return fleetList.length;
	}

	Object@ get_fleets(uint index) {
		ReadLock lock(fleetMutex);
		if(index >= fleetList.length)
			return null;
		return fleetList[index];
	}

	Ship@ getStrongestFleet() {
		ReadLock lock(fleetMutex);
		double str = 0;
		Ship@ strongest;
		for(uint i = 0, cnt = fleetList.length; i < cnt; ++i) {
			if(strengths[i] < str)
				continue;
			if(!fleetList[i].isShip)
				continue;
			str = strengths[i];
			@strongest = cast<Ship>(fleetList[i]);
		}
		return strongest;
	}

	double getTotalFleetStrength(Empire& emp) {
		WriteLock lock(fleetMutex);
		uint fltCnt = fleetList.length;
		if(fltCnt == 0)
			return 0.0;
		
		for(uint n = 0; n < fltCnt; ++n) {
			uint updateInd = n;
			Object@ flt = fleetList[updateInd];
			if(flt is null || !flt.valid)
				continue;

			int prevPoints = points(flt, strengths[updateInd]);
			strengths[updateInd] = sqrt(flt.getFleetMaxStrength());

			int newPoints = points(flt, strengths[updateInd]);
			if(newPoints != prevPoints) {
				militaryPoints += (newPoints - prevPoints);
				emp.points += (newPoints - prevPoints);
			}
		}
		
		double total = 0;
		for(uint i = 0; i < fltCnt; ++i)
			total += strengths[i];
		return total;
	}

	void load(SaveFile& msg) {
		uint cnt = 0;
		msg >> cnt;
		fleetList.length = cnt;
		strengths.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> fleetList[i];
			if(msg >= SV_0065)
				msg >> strengths[i];
			else
				strengths[i] = 0.0;
		}
		if(msg >= SV_0124)
			msg >> militaryPoints;
	}

	void save(SaveFile& msg) {
		uint cnt = fleetList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg << fleetList[i];
			msg << strengths[i];
		}
		msg << militaryPoints;
	}

	Object@ getFleetFromPosition(vec3d pos) {
		ReadLock lock(fleetMutex);
		for(uint i = 0, cnt = fleetList.length; i < cnt; ++i) {
			Object@ leader = fleetList[i];
			double rad = leader.getFormationRadius();

			if(leader.position.distanceToSQ(pos) < rad * rad)
				return leader;
		}
		return null;
	}

	void registerFleet(Empire& emp, Object@ obj) {
		WriteLock lock(fleetMutex);
		fleetList.insertLast(obj);
		strengths.insertLast(0);
	}

	void unregisterFleet(Empire& emp, Object@ obj) {
		WriteLock lock(fleetMutex);
		int ind = fleetList.find(obj);
		if(ind != -1) {
			int pts = points(obj, strengths[ind]);
			if(pts != 0) {
				militaryPoints -= pts;
				emp.points -= pts;
			}
			fleetList.removeAt(ind);
			strengths.removeAt(ind);
		}
	}

	void getFlagships() {
		ReadLock lock(fleetMutex);
		for(uint i = 0, cnt = fleetList.length; i < cnt; ++i) {
			Object@ leader = fleetList[i];
			if(leader.isShip && !cast<Ship>(leader).isStation)
				yield(leader);
		}
	}

	void getStations() {
		ReadLock lock(fleetMutex);
		for(uint i = 0, cnt = fleetList.length; i < cnt; ++i) {
			Object@ leader = fleetList[i];
			if(leader.isShip && cast<Ship>(leader).isStation)
				yield(leader);
		}
	}

	void giveFleetVisionTo(Empire@ toEmpire, bool systemSpace = true, bool deepSpace = true, bool inFTL = true, bool flagships = true, bool stations = false, int statusReq = -1, Region@ toSystem = null) {
		if(toEmpire is null)
			return;
		array<Ship@>@ pending = null;
		if(statusReq != -1)
			@pending = array<Ship@>();

		{
			ReadLock lock(fleetMutex);
			for(uint i = 0, cnt = fleetList.length; i < cnt; ++i) {
				Ship@ ship = cast<Ship>(fleetList[i]);
				if(ship is null)
					continue;
				if(!stations || !flagships) {
					if(ship.isStation) {
						if(!stations)
							continue;
					}
					else {
						if(!flagships)
							continue;
					}
				}
				if(!inFTL || !ship.inFTL) {
					if(ship.region is null) {
						if(!deepSpace)
							continue;
					}
					else {
						if(!systemSpace)
							continue;
					}
				}
				if(toSystem !is null) {
					if(!ship.isMoving)
						continue;
					if(ship.computedDestination.distanceToSQ(toSystem.position) > (toSystem.radius * toSystem.radius * 2.0))
						continue;
				}
				if(pending !is null)
					pending.insertLast(ship);
				else
					ship.donatedVision |= toEmpire.mask;
			}
		}

		if(pending !is null) {
			for(uint i = 0, cnt = pending.length; i < cnt; ++i) {
				Ship@ ship = pending[i];
				if(statusReq != -1) {
					if(!ship.hasStatusEffect(statusReq))
						continue;
				}
				ship.donatedVision |= toEmpire.mask;
			}
		}
	}
};
