// Intelligence
// ------------
// Keeps track of the existence and movement of enemy fleets and other assets.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;

import regions.regions;

final class FleetIntel {
	Object@ obj;
	bool known = false;
	bool visible = false;
	double lastSeen = 0;
	double seenStrength = 0;
	double predictStrength = 0;

	vec3d seenPosition;
	Region@ seenRegion;
	vec3d seenDestination;
	Region@ seenTarget;

	void save(SaveFile& file) {
		file << obj;
		file << known;
		file << visible;
		file << lastSeen;
		file << seenStrength;
		file << predictStrength;
		file << seenPosition;
		file << seenRegion;
		file << seenDestination;
		file << seenTarget;
	}

	void load(SaveFile& file) {
		file >> obj;
		file >> known;
		file >> visible;
		file >> lastSeen;
		file >> seenStrength;
		file >> predictStrength;
		file >> seenPosition;
		file >> seenRegion;
		file >> seenDestination;
		file >> seenTarget;
	}

	bool get_isSignificant() {
		return obj.getFleetStrength() > 0.1;
	}

	bool tick(AI& ai, Intelligence& intelligence, Intel& intel) {
		if(visible) {
			if(!obj.valid || obj.owner !is intel.empire)
				return false;
		}
		else {
			if(!obj.valid || obj.owner !is intel.empire) {
				if(!known || lastSeen < gameTime - 300.0)
					return false;
			}
		}
		if(obj.isVisibleTo(ai.empire)) {
			known = true;
			visible = true;
			lastSeen = gameTime;

			seenStrength = obj.getFleetStrength();
			predictStrength = obj.getFleetMaxStrength();
			int supCap = obj.SupplyCapacity;
			double fillPct = 1.0;
			if(supCap != 0) {
				double fillPct = double(obj.SupplyUsed) / double(supCap);
				if(fillPct > 0.5)
					predictStrength /= fillPct;
				else
					predictStrength *= 2.0;
			}

			seenPosition = obj.position;
			@seenRegion = obj.region;

			if(obj.isMoving) {
				seenDestination = obj.computedDestination;
				if(seenRegion !is null && inRegion(seenRegion, seenDestination))
					@seenTarget = seenRegion;
				else if(seenTarget !is null && inRegion(seenTarget, seenDestination))
					@seenTarget = seenTarget;
				else
					@seenTarget = getRegion(seenDestination);
			}
			else {
				seenDestination = seenPosition;
				@seenTarget = seenRegion;
			}
		}
		else {
			visible = false;
		}
		return true;
	}
};

final class Intel {
	Empire@ empire;
	uint borderedTo = 0;

	array<FleetIntel@> fleets;
	array<SystemAI@> shared;
	array<SystemAI@> theirBorder;
	array<SystemAI@> theirOwned;

	void save(Intelligence& intelligence, SaveFile& file) {
		uint cnt = fleets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			fleets[i].save(file);

		cnt = shared.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			intelligence.systems.saveAI(file, shared[i]);

		cnt = theirBorder.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			intelligence.systems.saveAI(file, theirBorder[i]);

		cnt = theirOwned.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			intelligence.systems.saveAI(file, theirOwned[i]);

		file << borderedTo;
	}

	void load(Intelligence& intelligence, SaveFile& file) {
		uint cnt = 0;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			FleetIntel flIntel;
			flIntel.load(file);
			if(flIntel.obj !is null)
				fleets.insertLast(flIntel);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ sys = intelligence.systems.loadAI(file);
			if(sys !is null)
				shared.insertLast(sys);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ sys = intelligence.systems.loadAI(file);
			if(sys !is null)
				theirBorder.insertLast(sys);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ sys = intelligence.systems.loadAI(file);
			if(sys !is null)
				theirOwned.insertLast(sys);
		}

		file >> borderedTo;
	}

	//TODO: If a fleet is going to drop out of cutoff range soon,
	// queue up a scouting mission to its last known position so we
	// can try to regain intel on it.

	double getSeenStrength(double cutOff = 600.0) {
		double total = 0.0;
		cutOff = gameTime - cutOff;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			auto@ flIntel = fleets[i];
			if(!flIntel.known)
				continue;
			if(flIntel.lastSeen < cutOff)
				continue;
			total += sqrt(fleets[i].seenStrength);
		}
		return total * total;
	}

	double getPredictiveStrength(double cutOff = 600.0) {
		double total = 0.0;
		cutOff = gameTime - cutOff;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			auto@ flIntel = fleets[i];
			if(!flIntel.known)
				continue;
			if(flIntel.lastSeen < cutOff)
				continue;
			total += sqrt(fleets[i].predictStrength);
		}
		return total * total;
	}

	double accuracy(AI& ai, Intelligence& intelligence, double cutOff = 600.0) {
		uint total = 0;
		uint known = 0;

		cutOff = gameTime - cutOff;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			auto@ flIntel = fleets[i];
			if(!flIntel.isSignificant)
				continue;

			total += 1;
			if(flIntel.known && flIntel.lastSeen >= cutOff)
				known += 1;
		}

		if(total == 0)
			return 1.0;
		return double(known) / double(total);
	}

	double defeatability(AI& ai, Intelligence& intelligence, double cutOff = 600.0) {
		double acc = accuracy(ai, intelligence, cutOff);
		double ourStrength = 0, theirStrength = 0;

		if(acc < 0.6) {
			//In low-accuracy situations, base it on the empire overall strength metric
			theirStrength = empire.TotalMilitary;
			ourStrength = ai.empire.TotalMilitary;
		}
		else {
			theirStrength = getPredictiveStrength(cutOff * 10.0);
			ourStrength = intelligence.fleets.totalStrength;
		}

		if(theirStrength == 0)
			return 10.0;
		return ourStrength / theirStrength;
	}

	void tick(AI& ai, Intelligence& intelligence) {
		//Keep known fleets updated
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			if(!fleets[i].tick(ai, intelligence, this)) {
				fleets.removeAt(i);
				--i; --cnt;
			}
		}
	}

	bool isShared(AI& ai, SystemAI@ sys) {
		return sys.seenPresent & ai.empire.mask != 0 && sys.seenPresent & empire.mask != 0;
	}

	bool isBorder(AI& ai, SystemAI@ sys) {
		return sys.outsideBorder && sys.seenPresent & empire.mask != 0;
	}

	void focusTick(AI& ai, Intelligence& intelligence) {
		//Detect newly created fleets
		auto@ data = empire.getFlagships();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj is null)
				continue;

			bool found = false;
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				if(fleets[i].obj is obj) {
					found = true;
					break;
				}
			}

			if(!found) {
				FleetIntel flIntel;
				@flIntel.obj = obj;
				fleets.insertLast(flIntel);
			}
		}

		//Remove no longer shared and border systems
		for(uint i = 0, cnt = shared.length; i < cnt; ++i) {
			if(!isShared(ai, shared[i])) {
				shared.removeAt(i);
				--i; --cnt;
			}
		}
		for(uint i = 0, cnt = theirBorder.length; i < cnt; ++i) {
			if(!isBorder(ai, theirBorder[i])) {
				theirBorder.removeAt(i);
				--i; --cnt;
			}
		}

		borderedTo = 0;
		for(uint i = 0, cnt = theirOwned.length; i < cnt; ++i) {
			auto@ sys = theirOwned[i];
			uint seen = sys.seenPresent;
			if(seen & empire.mask == 0) {
				theirOwned.removeAt(i);
				--i; --cnt;
				continue;
			}

			for(uint n = 0, ncnt = sys.desc.adjacent.length; n < ncnt; ++n) {
				auto@ other = intelligence.systems.getAI(sys.desc.adjacent[n]);
				if(other !is null)
					borderedTo |= other.seenPresent & ~empire.mask;
			}

			for(uint n = 0, ncnt = sys.desc.wormholes.length; n < ncnt; ++n) {
				auto@ other = intelligence.systems.getAI(sys.desc.wormholes[n]);
				if(other !is null)
					borderedTo |= other.seenPresent & ~empire.mask;
			}
		}

		//Detect shared and border systems
		for(uint i = 0, cnt = intelligence.systems.owned.length; i < cnt; ++i) {
			auto@ sys = intelligence.systems.owned[i];
			if(isShared(ai, sys)) {
				if(shared.find(sys) == -1)
					shared.insertLast(sys);
			}
		}
		for(uint i = 0, cnt = intelligence.systems.outsideBorder.length; i < cnt; ++i) {
			auto@ sys = intelligence.systems.outsideBorder[i];
			if(isBorder(ai, sys)) {
				if(theirBorder.find(sys) == -1)
					theirBorder.insertLast(sys);
			}
		}
		for(uint i = 0, cnt = intelligence.systems.all.length; i < cnt; ++i) {
			auto@ sys = intelligence.systems.all[i];
			if(sys.seenPresent & empire.mask != 0) {
				if(theirOwned.find(sys) == -1)
					theirOwned.insertLast(sys);
			}
		}
	
		//Try to update some stuff
		SystemAI@ check;
		double lru = 0;

		for(uint i = 0, cnt = shared.length; i < cnt; ++i) {
			auto@ sys = shared[i];
			double update = sys.lastStrengthCheck;
			if(update < lru && sys.visible) {
				@check = sys;
				lru = update;
			}
		}

		for(uint i = 0, cnt = theirBorder.length; i < cnt; ++i) {
			auto@ sys = theirBorder[i];
			double update = sys.lastStrengthCheck;
			if(update < lru && sys.visible) {
				@check = sys;
				lru = update;
			}
		}

		if(check !is null)
			check.strengthCheck(ai);
	}
};

class Intelligence : AIComponent {
	Fleets@ fleets;
	Systems@ systems;

	array<Intel@> intel;

	void create() {
		@fleets = cast<Fleets>(ai.fleets);
		@systems = cast<Systems>(ai.systems);
	}

	void start() {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp is ai.empire)
				continue;
			if(!emp.major)
				continue;

			Intel empIntel;
			@empIntel.empire = emp;

			if(intel.length <= uint(emp.index))
				intel.length = uint(emp.index)+1;
			@intel[emp.index] = empIntel;
		}
	}

	void save(SaveFile& file) {
		uint cnt = intel.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(intel[i] is null) {
				file.write0();
				continue;
			}

			file.write1();
			intel[i].save(this, file);
		}
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		intel.length = cnt;

		for(uint i = 0; i < cnt; ++i) {
			if(!file.readBit())
				continue;

			@intel[i] = Intel();
			@intel[i].empire = getEmpire(i);
			intel[i].load(this, file);
		}
	}

	Intel@ get(Empire@ emp) {
		if(emp is null)
			return null;
		if(!emp.major)
			return null;
		if(uint(emp.index) >= intel.length)
			return null;
		return intel[emp.index];
	}

	uint ind = 0;
	void tick(double time) override {
		if(intel.length == 0)
			return;
		ind = (ind+1)%intel.length;
		if(intel[ind] !is null)
			intel[ind].tick(ai, this);
	}

	uint fInd = 0;
	void focusTick(double time) override {
		if(intel.length == 0)
			return;
		fInd = (fInd+1)%intel.length;
		if(intel[fInd] !is null)
			intel[fInd].focusTick(ai, this);
	}

	string strdisplay(double str) {
		return standardize(str * 0.001, true);
	}

	double defeatability(Empire@ emp) {
		auto@ empIntel = get(emp);
		if(empIntel is null)
			return 0.0;
		return empIntel.defeatability(ai, this);
	}

	double defeatability(uint theirMask, uint myMask = 0, double cutOff = 600.0) {
		if(myMask == 0)
			myMask = ai.empire.mask;

		double minAcc = 1.0;
		for(uint i = 0, cnt = intel.length; i < cnt; ++i) {
			auto@ itl = intel[i];
			if(itl is null || itl.empire is null)
				continue;
			if((theirMask | myMask) & itl.empire.mask == 0)
				continue;
			minAcc = min(itl.accuracy(ai, this, cutOff), minAcc);
		}

		double ourStrength = 0, theirStrength = 0;
		for(uint i = 0, cnt = intel.length; i < cnt; ++i) {
			auto@ itl = intel[i];
			if(itl is null || itl.empire is null)
				continue;
			if((theirMask | myMask) & itl.empire.mask == 0)
				continue;

			double str = 0.0;
			if(minAcc < 0.6)
				str = itl.empire.TotalMilitary;
			else
				str = itl.getPredictiveStrength(cutOff * 10.0);

			if(itl.empire.mask & theirMask != 0)
				theirStrength += str;
			if(itl.empire.mask & myMask != 0)
				ourStrength += str;
		}

		if(myMask & ai.empire.mask != 0) {
			if(minAcc < 0.6)
				ourStrength += ai.empire.TotalMilitary;
			else
				ourStrength += fleets.totalStrength;
		}
		if(theirMask & ai.empire.mask != 0) {
			if(minAcc < 0.6)
				theirStrength += ai.empire.TotalMilitary;
			else
				theirStrength += fleets.totalStrength;
		}

		if(theirStrength == 0)
			return 10.0;
		return ourStrength / theirStrength;
	}

	void turn() override {
		if(log) {
			ai.print("Intelligence Report on Empires:");
			ai.print(ai.pad(" Our strength: ", 18)+strdisplay(fleets.totalStrength)+" / "+strdisplay(fleets.totalMaxStrength));
			for(uint i = 0, cnt = intel.length; i < cnt; ++i) {
				auto@ empIntel = intel[i];
				if(empIntel is null)
					continue;
				ai.print(" "+ai.pad(empIntel.empire.name, 16)
						+ai.pad(" "+strdisplay(empIntel.getSeenStrength())
						+" / "+strdisplay(empIntel.getPredictiveStrength()), 20)
						+" defeatability "+toString(empIntel.defeatability(ai, this), 2)
						+"   accuracy "+toString(empIntel.accuracy(ai, this), 2));
			}
		}
	}
};

AIComponent@ createIntelligence() {
	return Intelligence();
}
