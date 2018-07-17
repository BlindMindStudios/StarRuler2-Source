import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.searches;

import systems;
import system_pathing;

final class SystemAI {
	const SystemDesc@ desc;
	Region@ obj;
	double prevTick = 0.0;

	array<Planet@> planets;
	array<Pickup@> pickups;
	array<Object@> pickupProtectors;
	array<Artifact@> artifacts;
	array<Asteroid@> asteroids;

	bool explored = false;
	bool owned = false;
	bool visible = false;

	int hopDistance = 0;
	bool visited = false;

	bool border = false;
	bool bordersEmpires = false;
	bool outsideBorder = false;

	double lastVisible = 0;
	uint seenPresent = 0;

	double focusDuration = 0;

	double enemyStrength = 0;
	double lastStrengthCheck = 0;

	double nextDetailed = 0;

	SystemAI() {
	}

	SystemAI(const SystemDesc@ sys) {
		@desc = sys;
		@obj = desc.object;
	}

	void save(SaveFile& file) {
		file << obj;
		file << prevTick;

		uint cnt = planets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << planets[i];

		cnt = pickups.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << pickups[i];

		cnt = pickupProtectors.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << pickupProtectors[i];

		cnt = artifacts.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << artifacts[i];

		cnt = asteroids.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << asteroids[i];

		file << explored;
		file << owned;
		file << visible;
		file << hopDistance;
		file << border;
		file << bordersEmpires;
		file << outsideBorder;
		file << lastVisible;
		file << seenPresent;
		file << enemyStrength;
		file << lastStrengthCheck;
	}
	
	void load(SaveFile& file) {
		file >> obj;
		file >> prevTick;

		uint cnt = 0;
		file >> cnt;
		planets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> planets[i];

		file >> cnt;
		pickups.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> pickups[i];

		file >> cnt;
		pickupProtectors.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> pickupProtectors[i];

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Artifact@ artif;
			file >> artif;
			if(artif !is null)
				artifacts.insertLast(artif);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Asteroid@ roid;
			file >> roid;
			if(roid !is null)
				asteroids.insertLast(roid);
		}

		file >> explored;
		file >> owned;
		file >> visible;
		file >> hopDistance;
		file >> border;
		file >> bordersEmpires;
		file >> outsideBorder;
		file >> lastVisible;
		file >> seenPresent;
		file >> enemyStrength;
		file >> lastStrengthCheck;
	}

	bool visibleNow(AI& ai) {
		return obj.VisionMask & ai.visionMask != 0;
	}

	void strengthCheck(AI& ai, double minInterval = 30.0) {
		if(lastStrengthCheck + minInterval > gameTime)
			return;
		if(!visible && lastVisible < gameTime - 30.0)
			return;
		lastStrengthCheck = gameTime;
		enemyStrength = getTotalFleetStrength(obj, ai.enemyMask);
	}

	void tick(AI& ai, Systems& systems, double time) {
		//Check if we should be visible
		bool shouldVisible = obj.VisionMask & ai.visionMask != 0;
		if(visible != shouldVisible) {
			if(visible)
				lastVisible = gameTime;
			visible = shouldVisible;
		}

		//Check if we should be owned
		bool shouldOwned = obj.PlanetsMask & ai.mask != 0;
		if(owned != shouldOwned) {
			if(shouldOwned) {
				systems.owned.insertLast(this);
				systems.hopsChanged = true;
				hopDistance = 0;
			}
			else {
				hopDistance = 1;
				systems.owned.remove(this);
				systems.hopsChanged = true;
			}
			owned = shouldOwned;
		}

		//Check if we should be border
		bool shouldBorder = false;
		bordersEmpires = false;
		if(owned) {
			for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
				auto@ other = systems.getAI(desc.adjacent[i]);
				if(other !is null && !other.owned) {
					if(other.seenPresent & ~ai.teamMask != 0)
						bordersEmpires = true;
					shouldBorder = true;
					break;
				}
			}
			for(uint i = 0, cnt = desc.wormholes.length; i < cnt; ++i) {
				auto@ other = systems.getAI(desc.wormholes[i]);
				if(other !is null && !other.owned) {
					if(other.seenPresent & ~ai.teamMask != 0)
						bordersEmpires = true;
					shouldBorder = true;
					break;
				}
			}
		}

		if(border != shouldBorder) {
			if(shouldBorder) {
				systems.border.insertLast(this);
			}
			else {
				systems.border.remove(this);
			}
			border = shouldBorder;
		}

		//Check if we should be outsideBorder
		bool shouldOutsideBorder = !owned && hopDistance == 1;
		if(outsideBorder != shouldOutsideBorder) {
			if(shouldOutsideBorder) {
				systems.outsideBorder.insertLast(this);
			}
			else {
				systems.outsideBorder.remove(this);
			}
			outsideBorder = shouldOutsideBorder;
		}

		//Check if we've been explored
		if(visible && !explored) {
			//Find all remnants in this system
			auto@ objs = findType(obj, null, OT_Pickup);
			for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
				Pickup@ p = cast<Pickup>(objs[i]);
				if(p !is null) {
					pickups.insertLast(p);
					pickupProtectors.insertLast(p.getProtector());
				}
			}

			explored = true;
		}

		//Deal with recording new data on this system
		if(explored) {
			uint plCnt = obj.planetCount;
			if(plCnt != planets.length) {
				auto@ objs = findType(obj, null, OT_Planet);
				planets.length = 0;
				planets.reserve(objs.length);
				for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
					Planet@ pl = cast<Planet>(objs[i]);
					if(pl !is null)
						planets.insertLast(pl);
				}
			}
		}

		if(visible) {
			seenPresent = obj.PlanetsMask;

			uint astrCount = obj.asteroidCount;
			if(astrCount != asteroids.length) {
				auto@ objs = findType(obj, null, OT_Asteroid);
				asteroids.length = 0;
				asteroids.reserve(objs.length);
				for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
					Asteroid@ a = cast<Asteroid>(objs[i]);
					if(a !is null)
						asteroids.insertLast(a);
				}
			}

			for(uint i = 0, cnt = pickups.length; i < cnt; ++i) {
				if(!pickups[i].valid) {
					pickups.removeAt(i);
					pickupProtectors.removeAt(i);
					break;
				}
			}

			if(nextDetailed < gameTime) {
				nextDetailed = gameTime + randomd(40.0, 100.0);

				auto@ objs = findType(obj, null, OT_Artifact);
				artifacts.length = 0;
				artifacts.reserve(objs.length);
				for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
					Artifact@ a = cast<Artifact>(objs[i]);
					if(a !is null)
						artifacts.insertLast(a);
				}
			}
		}
	}
};

class Systems : AIComponent {
	//All owned systems
	array<SystemAI@> owned;

	//All owned systems that are considered our empire's border
	array<SystemAI@> border;

	//All systems just outside our border
	array<SystemAI@> outsideBorder;

	//All systems
	array<SystemAI@> all;

	//Systems that need to be processed soon
	array<SystemAI@> bumped;
	array<SystemAI@> focused;

	uint sysIdx = 0;
	bool hopsChanged = false;

	void save(SaveFile& file) {
		uint cnt = all.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			all[i].save(file);

		cnt = owned.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			saveAI(file, owned[i]);

		cnt = border.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			saveAI(file, border[i]);

		cnt = outsideBorder.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			saveAI(file, outsideBorder[i]);
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		all.length = max(all.length, cnt);
		for(uint i = 0; i < cnt; ++i) {
			if(all[i] is null)
				@all[i] = SystemAI();
			all[i].load(file);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadAI(file);
			if(data !is null)
				owned.insertLast(data);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadAI(file);
			if(data !is null)
				border.insertLast(data);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadAI(file);
			if(data !is null)
				outsideBorder.insertLast(data);
		}
	}

	void loadFinalize(AI& ai) override {
		for(uint i = 0, cnt = all.length; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			@all[i].desc = sys;
			@all[i].obj = sys.object;
		}
	}

	void saveAI(SaveFile& file, SystemAI@ ai) {
		Region@ reg;
		if(ai !is null)
			@reg = ai.obj;
		file << reg;
	}

	SystemAI@ loadAI(SaveFile& file) {
		Region@ reg;
		file >> reg;

		if(reg is null)
			return null;

		uint id = reg.SystemId;
		if(id >= all.length) {
			all.length = id+1;
			@all[id] = SystemAI();
			@all[id].obj = reg;
		}

		return all[id];
	}

	void focusTick(double time) {
		if(all.length != systemCount) {
			uint prevCount = all.length;
			all.length = systemCount;
			for(uint i = prevCount, cnt = all.length; i < cnt; ++i)
				@all[i] = SystemAI(getSystem(i));
		}
		if(hopsChanged)
			calculateHops();
	}

	void tick(double time) override {
		double curTime = gameTime;

		if(all.length != 0) {
			uint tcount = max(ceil(time / 0.2), double(all.length)/20.0);
			for(uint n = 0; n < tcount; ++n) {
				sysIdx = (sysIdx+1) % all.length;

				auto@ sys = all[sysIdx];
				sys.tick(ai, this, curTime - sys.prevTick);
				sys.prevTick = curTime;
			}
		}

		for(uint i = 0, cnt = bumped.length; i < cnt; ++i) {
			auto@ sys = bumped[i];
			double tickTime = curTime - sys.prevTick;
			if(tickTime != 0) {
				sys.tick(ai, this, tickTime);
				sys.prevTick = curTime;
			}
		}
		bumped.length = 0;

		for(uint i = 0, cnt = focused.length; i < cnt; ++i) {
			auto@ sys = focused[i];
			sys.focusDuration -= time;

			double tickTime = curTime - sys.prevTick;
			if(tickTime != 0) {
				sys.tick(ai, this, tickTime);
				sys.prevTick = curTime;
			}

			if(sys.focusDuration <= 0) {
				focused.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void calculateHops() {
		if(!hopsChanged)
			return;
		hopsChanged = false;
		priority_queue q;
		for(uint i = 0, cnt = all.length; i < cnt; ++i) {
			auto@ sys = all[i];
			sys.visited = false;
			if(sys.owned) {
				sys.hopDistance = 0;
				q.push(int(i), 0);
			}
			else
				sys.hopDistance = INT_MAX;
		}

		while(!q.empty()) {
			uint index = uint(q.top());
			q.pop();

			auto@ sys = all[index];
			if(sys.visited)
				continue;

			int dist = sys.hopDistance;
			sys.visited = true;

			for(uint i = 0, cnt = sys.desc.adjacent.length; i < cnt; ++i) {
				uint otherInd = sys.desc.adjacent[i];
				if(otherInd < all.length) {
					auto@ other = all[otherInd];
					if(other.hopDistance > dist+1) {
						other.hopDistance = dist+1;
						q.push(otherInd, -other.hopDistance);
					}
				}
			}
			for(uint i = 0, cnt = sys.desc.wormholes.length; i < cnt; ++i) {
				uint otherInd = sys.desc.wormholes[i];
				if(otherInd < all.length) {
					auto@ other = all[otherInd];
					if(other.hopDistance > dist+1) {
						other.hopDistance = dist+1;
						q.push(otherInd, -other.hopDistance);
					}
				}
			}
		}
	}

	void focus(Region@ reg, double duration = 30.0) {
		bool found = false;
		for(uint i = 0, cnt = focused.length; i < cnt; ++i) {
			if(focused[i].obj is reg) {
				focused[i].focusDuration = max(focused[i].focusDuration, duration);
				found = true;
				break;
			}
		}

		if(!found) {
			auto@ sys = getAI(reg);
			if(sys !is null) {
				sys.focusDuration = duration;
				focused.insertLast(sys);
			}
		}
	}

	void bump(Region@ sys) {
		if(sys !is null)
			bump(getAI(sys));
	}

	void bump(SystemAI@ sys) {
		if(sys !is null)
			bumped.insertLast(sys);
	}

	SystemAI@ getAI(uint idx) {
		if(idx < all.length)
			return all[idx];
		return null;
	}

	SystemAI@ getAI(Region@ region) {
		if(region is null)
			return null;
		uint idx = region.SystemId;
		if(idx < all.length)
			return all[idx];
		return null;
	}

	SystemPath pather;
	int hopDistance(Region& fromRegion, Region& toRegion){ 
		pather.generate(getSystem(fromRegion), getSystem(toRegion), keepCache=true);
		if(!pather.valid)
			return INT_MAX;
		return pather.pathSize - 1;
	}

	TradePath tradePather;
	int tradeDistance(Region& fromRegion, Region& toRegion) {
		@tradePather.forEmpire = ai.empire;
		tradePather.generate(getSystem(fromRegion), getSystem(toRegion), keepCache=true);
		if(!tradePather.valid)
			return -1;
		return tradePather.pathSize - 1;
	}

	bool canTrade(Region& fromRegion, Region& toRegion) {
		if(fromRegion.sharesTerritory(ai.empire, toRegion))
			return true;
		int dist = tradeDistance(fromRegion, toRegion);
		if(dist < 0)
			return false;
		return true;
	}

	SystemAI@ getAI(const string& name) {
		for(uint i = 0, cnt = all.length; i < cnt; ++i) {
			if(all[i].obj.name.equals_nocase(name))
				return all[i];
		}
		return null;
	}

	uint index(const string& name) {
		for(uint i = 0, cnt = all.length; i < cnt; ++i) {
			if(all[i].obj.name.equals_nocase(name))
				return i;
		}
		return uint(-1);
	}
};

AIComponent@ createSystems() {
	return Systems();
}
