//Locates a system to explore
import systems;
import ftl;
from pings import sendPing;
import design_settings;
#include "include/resource_constants.as"

int64 exploreHash() {
	return int64(ACT_Explore) << ACT_BIT_OFFSET;
}

void moveToFastest(Ship@ ship, const vec3d& pos, FTLType ftl, bool alwaysHyper = false) {
	auto@ emp = ship.owner;
	switch(ftl) {
		case FTL_Hyperdrive: {
			int cost = hyperdriveCost(ship, pos);
			if(emp.FTLStored >= cost && (alwaysHyper || ship.position.distanceToSQ(pos) > 1.0e6)) {
				ship.addHyperdriveOrder(pos);
				ship.addMoveOrder(pos, append=true);
				break;
			}
			ship.addMoveOrder(pos);
			} break;
		case FTL_Jumpdrive: {
			int cost = jumpdriveCost(ship, pos);
			double range = jumpdriveRange(ship);
			double dist = ship.position.distanceToSQ(pos);
			if(emp.FTLStored >= cost && (alwaysHyper || dist > 1.0e6) && dist <= range*1.25) {
				ship.addJumpdriveOrder(pos);
				ship.addMoveOrder(pos, append=true);
				break;
			}
			ship.addMoveOrder(pos);
		} break;
		case FTL_Fling: {
			int cost = flingCost(ship, pos);
			if(emp.hasFlingBeacons && emp.FTLStored >= cost && (alwaysHyper || ship.position.distanceToSQ(pos) > 1.0e6)) {
				Object@ fling = emp.getFlingBeacon(ship.position);
				if(fling !is null) {
					ship.addFlingOrder(fling, pos);
					ship.addMoveOrder(pos, append=true);
					break;
				}
			}
			ship.addMoveOrder(pos);
			} break;
		default:
			ship.addMoveOrder(pos);
			break;
	}
}

class Explore : Action {
	Region@ system;
	Ship@ fleet;
	SysSearch search;
	
	Artifact@ telescope;
	const ArtifactType@ scope = getArtifactType("Telescope");

	Explore() {
	}

	Explore(BasicAI@ ai, SaveFile& file) {
		file >> system;
		file >> fleet;
		if(file < SV_0031) {
			int dummy = 0;
			file >> dummy;
		}
		search.load(file);
	}

	void save(BasicAI@ ai, SaveFile& file) {
		file << system;
		file << fleet;
		search.save(file);
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return exploreHash();
	}

	ActionType get_actionType() const {
		return ACT_Explore;
	}
	
	void reset(BasicAI@ ai, bool automate = true) {
		if(fleet !is null) {
			fleet.addAutoExploreOrder(useFTL=true);
			ai.freeFleet(fleet, FT_Scout);
			@fleet = null;
		}
		
		@system = null;
		search.reset();
	}
	
	string get_state() const {
		if(fleet is null)
			return "Exploring";
		else if(system is null)
			return "Exploring with " + fleet.name + " fleet";
		else
			return "Awaiting " + fleet.name + " scout fleet arrival at " + system.name;
	}
	
	bool perform(BasicAI@ ai) {
		if(ai.skillScout < DIFF_Medium) {
			Ship@ scout = ai.getAvailableFleet(FT_Scout);
			if(scout !is null) {
				if(!scout.hasOrders)
					scout.addAutoExploreOrder(useFTL=true);
				ai.freeFleet(scout, FT_Scout);
			}
			return true;
		}
	
		//Telescope may become inaccessible
		if(telescope !is null && (!telescope.valid || telescope.region.getTerritory(ai.empire) !is null))
			@telescope = null;
		
		if(ai.skillScout >= DIFF_Medium)
			if(telescope is null && ai.empire.EnergyStored > 0.0)
				@telescope = ai.getArtifact(scope);
		
		//At times, we might encouter a situation where the scout is stuck in limbo
		if(fleet !is null && fleet.inFTL && fleet.ftlSpeed < 25.0) {
			fleet.scuttle();
			@fleet = null;
		}
		
		//The fleet may die
		// We should also consider trying to scout a different system
		if(fleet !is null && (!fleet.valid || fleet.owner !is ai.empire)) {
			@system = null;
			@fleet = null;
		}
	
		if(system !is null) {
			if(system.VisionMask & ai.empire.visionMask != 0) {
				PlanRegion@ reg = ai.findSystem(system);
				if(reg is null || !ai.knownSystem(system)) {
					@reg = ai.addExploredSystem(system);
					reg.scout(ai);
				}
				
				//Scout anomalies
				if(fleet !is null) {
					for(uint i = 0, cnt = reg.anomalies.length; i < cnt; ++i) {
						auto@ a = reg.anomalies[i];
						if(!a.valid)
							continue;
						if(a.getEmpireProgress(ai.empire) < 1.f) {
							fleet.addScanOrder(a);
							ai.focus = a.position;
							return false;
						}
						else {
							uint optCount = a.getOptionCount();
							uint off = randomi(0,optCount-1);
							for(uint i = 0; i < optCount; ++i) {
								uint o = (i + off) % optCount;
								if(a.isOptionSafe[o]) {
									a.choose(ai.empire, o);
									return false;
								}
							}
						}
					}
				}
				
				reset(ai);
				return true;
			}
			else if(telescope !is null && ai.empire.EnergyStored > scope.abilities[0].energyCost + 300.0) {
				telescope.activateAbilityFor(ai.empire, 0, system);
			}
			else {
				if(ai.ftl == FTL_Slipstream && ai.skillScout >= DIFF_Medium && (ai.lastSlipstream + 300.0 <= gameTime || clamp(ai.lastSlipstream - gameTime, 0.0, 300.0) < 20.0)) {
					if(gameTime > ai.lastSlipstream + 300.0) {
						auto@ slip = ai.getAvailableFleet(FT_Slipstream);
						if(slip !is null && !slip.hasOrders) {
							vec2d off = random2d(250.0, system.radius);
							vec3d dest = system.position + vec3d(off.x, 0.0, off.y);
							auto cost = slipstreamCost(slip, 1, dest.distanceTo(slip.position));
							if(cost <= ai.empire.FTLStored) {
								slip.addSlipstreamOrder(dest);
								ai.lastSlipstream = gameTime;
								return false;
							}
							else {
								error("Cost: " + cost + " > " + ai.empire.FTLStored);
							}
						}
						
						if(slip !is null)
							ai.freeFleet(slip, FT_Slipstream);
					}
					else {
						//We kinda think maybe the slipstream was for scouting, so we just sit here looking stupid
						return false;
					}
				}
				
				if(fleet !is null) {
					if(fleet.region !is system && !fleet.hasOrders)
						moveToFastest(fleet, system.position + (fleet.position - system.position).normalized(system.radius * 0.85), ai.ftl);
				}
				else if(ai.fleets[FT_Scout].length > 0) {
					double closest = INFINITY;
					array<Ship@>@ scouts = ai.fleets[FT_Scout];
					uint index = 0;
					for(uint i = 0, cnt = scouts.length; i < cnt; ++i) {
						Ship@ ship = scouts[i];
						double d = ship.position.distanceToSQ(system.position);
						if(d < closest) {
							@fleet = ship;
							index = i;
							closest = d;
						}
					}
					
					if(fleet !is null) {
						scouts.removeAt(index);
						fleet.clearOrders();
						ai.focus = fleet.position;
					}
				}
				else {
					ai.requestFleetBuild(FT_Scout);
				}
			}
		}
		else if(ai.ourSystems.length + ai.exploredSystems.length >= systemCount)
		{
			//Only Hard AIs have the focus to keep scouting late-game
			if(ai.skillScout < DIFF_Hard)
				return true;
			//Move a scout to a random nearby system
			if(fleet is null) {
				@fleet = ai.getAvailableFleet(FT_Scout);
				if(fleet !is null)
					fleet.clearOrders();
			}
			else {
				auto@ start = fleet.region;
				if(start !is null) {
					auto@ sys = getSystem(start);
					if(sys.adjacent.length > 0) {
						@system = getSystem(sys.adjacent[randomi(0, sys.adjacent.length-1)]).object;
						if(system.VisionMask & ai.empire.visionMask != 0)
							@system = null;
					}
				}
				
				//If we didn't find a suitable system, pick a random system we don't have vision in
				if(system is null && ai.exploredSystems.length > 0) {
					@system = ai.exploredSystems[randomi(0,ai.exploredSystems.length-1)].region;
					if(system.VisionMask & ai.empire.visionMask != 0)
						@system = null;
				}
			}
		}
		else {
			array<Region@> systems;
			
			//Search for systems bordering our own that we haven't seen yet
			for(uint trySteps = 0; trySteps < 8; ++trySteps) {
				PlanRegion@ target;
				if(ai.skillScout <= DIFF_Easy)
					@target = search.random(ai.ourSystems);
				else
					@target = search.next(ai.ourSystems);
				
				if(target is null)
					@target = search.random(ai.exploredSystems);
				
				if(target !is null) {
					const SystemDesc@ sys = target.system;
					for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
						Region@ other = getSystem(sys.adjacent[i]).object;
						if(!ai.knownSystem(other))
							systems.insertLast(other);
					}
				}
				else {
					search.reset();
					break;
				}
			}
			
			if(systems.length == 0) {
				for(uint i = 0; i < 4; ++i) {
					auto@ sys = getSystem(randomi(0,systemCount-1)).object;
					if(!ai.knownSystem(sys))
						systems.insertLast(sys);
				}
			}
			
			if(systems.length != 0) {
				if(ai.skillScout <= DIFF_Easy) {
					@system = systems[randomi(0,systems.length-1)];
				}
				else {
					//Medium+ AIs will try to select shorter scouting patterns
					Object@ home = ai.homeworld;
					if(home is null)
						@home = ai.empire.HomeObj;
					
					vec3d nearTo = home !is null ? home.position : vec3d();
					auto@ scouts = ai.fleets[FT_Scout];
					if(scouts.length > 0 && randomi(0,4) != 0)
						nearTo = scouts[randomi(0,scouts.length-1)].position;
					
					double nearestDist = INFINITY;
					for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
						double dist = nearTo.distanceToSQ(systems[i].position);
						if(system is null || dist < nearestDist) {
							nearestDist = dist;
							@system = systems[i];
						}
					}
				}
				
				if(system !is null)
					ai.focus = system.position;
			}
		}
		
		return false;
	}
}

atomic_int nextArmadaID(0);

final class Armada {
	int id = ++nextArmadaID;
	array<Ship@> fleets;
	Region@ target;
	
	bool inCombat = false;
	
	Planet@ siegePlanet;
	
	void save(SaveFile& file) {
		file << uint(fleets.length);
		for(uint i = 0; i < fleets.length; ++i)
			file << fleets[i];
		file << target;
		file << inCombat;
		file << siegePlanet;
	}
	
	Armada() {}
	
	Armada(SaveFile& file) {
		uint count = 0;
		file >> count;
		fleets.length = count;
		for(uint i = 0; i < fleets.length; ++i)
			file >> fleets[i];
		file >> target;
		file >> inCombat;
		file >> siegePlanet;
		if(file < SV_0010) {
			Object@ dummy;
			file >> dummy;
		}
	}
	
	bool validate(BasicAI@ ai) {
		for(int i = fleets.length - 1; i >= 0; --i) {
			Ship@ ship = fleets[i];
			if(ship.owner !is ai.empire || !ship.valid) {
				auto@ bp = ship.blueprint;
				if(bp !is null && bp.design !is null)
					ai.willpower -= lostFleetWill * float(bp.design.size);
				fleets.removeAt(i);
			}
		}
		
		return fleets.length != 0;
	}
	
	uint get_fleetCount() const {
		return fleets.length;
	}
	
	vec3d get_position() const {
		if(fleets.length == 0)
			return vec3d();
		else
			return fleets[0].position;
	}
	
	Region@ get_region() const {
		if(fleets.length == 0)
			return null;
		else
			return fleets[0].region;
	}
	
	void addFleet(BasicAI@ ai, Ship@ ship) {
		if(target !is null && ship.region !is target) {
			vec3d pos;
			if(fleets.length == 0)
				pos = target.position + (ship.position - target.position).normalized(target.radius * 0.8);
			else
				pos = position + random3d(50.0);
			
			moveToFastest(ship, pos, ai.ftl);
			if(siegePlanet !is null)
				ship.addCaptureOrder(siegePlanet, append=true);
		}
		else if(siegePlanet !is null) {
			ship.addCaptureOrder(siegePlanet);
		}
		
		fleets.insertLast(ship);
	}
	
	bool isInCombat(Empire@ empire) const {
		if(inCombat)
			return true;
		if(target is null)
			return false;
		
		bool anyEnemyPresence = false;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(emp.valid && emp.major && empire.isHostile(emp)) {
				if(target.getStrength(empire) > 15) {
					anyEnemyPresence = true;
					break;
				}
			}
		}
	
		if(!anyEnemyPresence && target.ContestedMask & empire.mask == 0 && target.TradeMask & empire.hostileMask == 0)
			return false;
	
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			if(fleets[i].region is target)
				return true;
		
		return false;
	}
		
	bool get_isInTransit() const {
		if(target is null)
			return false;
		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Ship@ fleet = fleets[i];
			if(fleet.region !is target && fleet.hasOrders)
				return true;
		}
		
		return false;
	}
	
	double get_lowestSupplyPct() const {
		double lowest = 1.0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			const Ship@ ship = fleets[i];
			double pct = double(ship.Supply) / double(ship.MaxSupply);
			if(pct < lowest)
				lowest = pct;
		}
		return lowest;
	}
	
	double get_totalSupply() const {
		double supply = 0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			supply += double(fleets[i].Supply);
		return supply;
	}
	
	double get_maxSupply() const {
		double supply = 0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			supply += double(fleets[i].MaxSupply);
		return supply;
	}
	
	double get_totalEffectiveness() const {
		double hp = 0, dps = 0;
		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Ship@ leader = fleets[i];
			hp += leader.getFleetHP();
			dps += leader.getFleetDPS();
		}
		
		return hp * dps;
	}
	
	Ship@ freeToStrength(double goalStr) {
		goalStr = sqrt(goalStr);
		
		array<double> strengths(fleets.length);
		double totalStr = 0.0;
		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Ship@ leader = fleets[i];			
			double str = sqrt(leader.getFleetStrength());
			totalStr += str;
			
			strengths[i] = str;
		}
		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			double str = strengths[i];
			if(totalStr - str > goalStr) {
				Ship@ fleet = fleets[i];
				strengths.removeAt(i);
				fleets.removeAt(i);
				return fleet;
			}
		}
		
		return null;
	}
	
	void clear() {
		fleets.length = 0;
		@target = null;
		inCombat = false;
		@siegePlanet = null;
	}
	
	void freeFleets(BasicAI@ ai, FleetType asType) {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			ai.freeFleet(fleets[i], asType);
		fleets.length = 0;
	}
	
	bool get_hasOrderedSupports() const {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			if(fleets[i].hasOrderedSupports)
				return true;
		return false;
	}
	
	uint get_supportCapacityAvailable() const {
		uint avail = 0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			avail += fleets[i].SupplyAvailable;
		return avail;
	}
	
	void moveTo(BasicAI@ ai, Region@ region, bool tryFTL = true, Object@ around = null) {
		if(fleets.length == 0)
			return;
		
		@siegePlanet = null;
		vec3d pos;
		if(around is null)
			pos = region.position + (fleets[0].position - region.position).normalized(region.radius * 0.8);
		else
			pos = around.position + (fleets[0].position - around.position).normalized(around.radius + 100.0);
	
		bool doFTL = false;
		if(tryFTL && (ai.ftl == FTL_Hyperdrive || ai.ftl == FTL_Fling || ai.ftl == FTL_Jumpdrive)) {
			int cost = 0;
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				Ship@ ship = fleets[i];
				if(ship.region is region)
					continue;
				
				if(ai.ftl == FTL_Hyperdrive)
					cost += hyperdriveCost(ship, pos);
				else if(ai.ftl == FTL_Jumpdrive) {
					if(ship.position.distanceTo(pos) > jumpdriveRange(ship) * 1.25) {
						doFTL = false;
						break;
					}
					cost += jumpdriveCost(ship, pos);
				}
				else
					cost += flingCost(ship, pos);

			}
			
			doFTL = ai.empire.FTLStored >= cost;
		}
		
		Object@ fling = null;
		if(doFTL && ai.empire.hasFlingBeacons) {
			@fling = ai.empire.getFlingBeacon(fleets[0].position);
			if(fling is null)
				doFTL = false;
		}
		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Ship@ ship = fleets[i];
			if(ship.region is region)
				continue;
			
			vec3d d = pos + random3d(double(fleets.length) * 25.0);
			
			if(doFTL) {
				if(ai.ftl == FTL_Hyperdrive)
					ship.addHyperdriveOrder(d);
				else if(ai.ftl == FTL_Jumpdrive)
					ship.addJumpdriveOrder(d);
				else
					ship.addFlingOrder(fling, d);
				ship.addMoveOrder(d, append=true);
			}
			else {
				ship.addMoveOrder(d);
			}
		}
		
		@target = region;
	}
	
	void attack(Object@ target) {
		@siegePlanet = null;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].addAttackOrder(target);
	}
	
	void pickup(Pickup@ bonus) {
		@siegePlanet = null;
		if(fleets.length != 0)
			fleets[0].addPickupOrder(bonus);
	}
	
	void rebuildAllGhosts() {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].rebuildAllGhosts();
	}
	
	void refreshSupportsFrom(Object@ obj) {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].refreshSupportsFrom(obj);
	}
	
	void fillFleets(BasicAI@ ai) {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			ai.fillFleet(fleets[i]);
	}
	
	void clearGhosts() {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].clearAllGhosts();
	}
	
	void conquer(Planet@ pl) {
		if(siegePlanet is pl)
			return;
		@siegePlanet = pl;		
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].addCaptureOrder(pl);
	}
};

int64 defendHash() {
	return int64(ACT_Defend) << ACT_BIT_OFFSET;
}

class Defend : Action {
	Region@ region;
	Armada@ armada;
	SysSearch search;

	Defend() {
		@armada = Armada();
	}

	Defend(BasicAI@ ai, SaveFile& file) {
		file >> region;
		@armada = Armada(file);
		search.load(file);
	}

	void save(BasicAI@ ai, SaveFile& file) {
		file << region;
		armada.save(file);
		search.save(file);
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return defendHash();
	}

	ActionType get_actionType() const {
		return ACT_Defend;
	}
	
	string get_state() const {
		if(region is null)
			return "Defending";
		else if(armada.fleetCount == 0)
			return "Defending " + region.name;
		else
			return "Awaiting defense armada arrival at " + region.name;
	}
	
	double getRegionStrength(BasicAI@ ai, Region@ atRegion) {
		if(atRegion is null)
			return 0;
		PlanRegion@ reg = ai.getPlanRegion(atRegion);
		if(reg is null) 
			return 0;
		
		double str = 0.0;
		uint hostileMask = ai.empire.hostileMask;
		for(uint i = 0; i < getEmpireCount(); ++i) {
			Empire@ emp = getEmpire(i);
			if(emp.mask & hostileMask == 0 || !emp.valid)
				continue;
			
			str += reg.strengths[emp.index];
		}
		return str * str;
	}
	
	bool searchBorder = false;
	PlanRegion@ searchForRegion(BasicAI@ ai, uint tries, double maxStr = INFINITY) {
		double weakest = 0;
		PlanRegion@ result;
		for(uint i = 0; i < tries; ++i) {
			PlanRegion@ reg;
			if(ai.skillCombat < DIFF_Medium)
				@reg = search.random(ai.ourSystems);
			else
				@reg = search.next(ai.ourSystems);
			
			if(reg !is null) {
				if(searchBorder || (ai.skillCombat < DIFF_Medium && randomi(0,2) == 0)) {
					@reg = ai.getBorderSystem(reg);
					if(reg is null)
						continue;
				}
				else if(reg.region.VisionMask & ai.empire.visionMask == 0) {
					if(reg.age > 360.0 && !ai.didTickScan)
						reg.scout(ai);
					continue;
				}
				
				
				//See if there are any enemies in the system
				double str = getRegionStrength(ai, reg.region);
				if(str > 0.0 && str < maxStr && (result is null || str < weakest)) {
					@result = reg;
					weakest = str;
				}
			}
			else {
				search.reset();
				searchBorder = !searchBorder;
				break;
			}
		}
		
		if(result !is null) {
			search.reset();
			searchBorder = false;
		}
		
		return result;
	}
	
	Region@ getHome(BasicAI@ ai) {
		Object@ obj = ai.homeworld;
		if(obj !is null && obj.owner is ai.empire && obj.region !is null)
			return obj.region;
		if(ai.factories.length > 0) {
			@obj = ai.factories[0];
			if(obj !is null && obj.owner is ai.empire && obj.region !is null)
				return obj.region;
		}
		if(ai.ourSystems.length > 0)
			return ai.ourSystems[0].region;
		return null;
	}
	
	bool perform(BasicAI@ ai) {
		//Look for a system that needs defending
		if(region is null) {
			PlanRegion@ reg = searchForRegion(ai, 2 + ai.skillCombat * 2);
			if(reg !is null)
				@region = reg.region;
			
			if(armada.fleetCount != 0 && armada.hasOrderedSupports) {
				if(!armada.isInTransit) {
					auto@ home = getHome(ai);
					if(home is null)
						return true;
					if(armada.target is home && armada.region is home) {
						ai.focus = armada.target.position;
						//Use up any support ships available here
						for(uint i = 0, cnt = armada.target.planetCount; i < cnt; ++i) {
							Planet@ pl = armada.target.planets[i];
							if(pl.owner is ai.empire)
								armada.refreshSupportsFrom(pl);
						}
						armada.fillFleets(ai);
					}
					else {
						armada.moveTo(ai, home);
					}
				}
			}
			
			return false;
		}
		else if(region.VisionMask & ai.empire.visionMask == 0 && !ai.isBorderSystem(ai.findSystem(region))) {
			@region = null;
			armada.fillFleets(ai);
			ai.focus = armada.position;
			return false;
		}
		
		armada.validate(ai);
		if(armada.fleetCount == 0) {
			Ship@ fleet = ai.getAvailableFleet(FT_Combat);
			if(fleet !is null) {
				armada.addFleet(ai, fleet);
				ai.focus = fleet.position;
			}
			return false;
		}
		
		if(armada.target !is region) {
			if(!armada.isInTransit) {
				if(armada.hasOrderedSupports) {
					auto@ home = getHome(ai);
					if(armada.region !is home)
						armada.moveTo(ai, home);
				}
				else {
					//Build up defense fleets until we can take them
					double enemy = getRegionStrength(ai, region);
					double us = armada.totalEffectiveness;
					if(us > 0.8 * enemy) {
						if(us > 1.25 * enemy && armada.fleetCount > 1) {
							Ship@ freed = armada.freeToStrength(1.25 * enemy);
							if(freed !is null)
								ai.freeFleet(freed, FT_Combat);
						}
						armada.moveTo(ai, region);
					}
					else {
						//Look for alternate targets weaker than ourselves while trying to build up
						PlanRegion@ weaker = searchForRegion(ai, 1 + ai.skillCombat * 1, us * 1.1);
						if(weaker is null) {
							auto@ ship = armada.fleets[randomi(0, armada.fleetCount-1)];
							ai.fillFleet(ship);
								
							//Add available fleets as necessary
							// If there aren't any available, see if other systems need defending
							Ship@ fleet = ai.getAvailableFleet(FT_Combat);
							if(fleet !is null)
								armada.addFleet(ai, fleet);
							else
								@region = null;
						}
						else {
							@region = weaker.region;
						}
					}
				}
				return false;
			}
		}
		else if(!armada.isInTransit) {
			if(armada.region !is region) {
				armada.moveTo(ai, region);
				return false;
			}
		
			ai.focus = region.position;
			//Check that the enemies died
			PlanRegion@ plan = ai.getPlanRegion(region);
			array<Object@>@ objects = plan.scout(ai);
			if(plan.planetMask & ai.empire.mask == 0 && !ai.isBorderSystem(plan)) {
				@region = null;
				armada.fillFleets(ai);
				return false;
			}
			
			Pickup@ pickup;
			Object@ support;
			
			uint hostileMask = ai.empire.hostileMask;
			for(uint i = 0; i < objects.length; ++i) {
				Object@ obj = objects[i];
				if(obj.isShip || obj.isOrbital) {
					if(obj.owner.mask & hostileMask != 0) {
						if(obj.hasSupportAI)
							@support = obj;
						else {
							ai.focus = obj.position;
							armada.attack(obj);
							return false;
						}
					}
				}
				else if(obj.isPickup) {
					@pickup = cast<Pickup>(obj);
				}
			}
			
			if(pickup !is null) {
				ai.focus = pickup.position;
				armada.pickup(pickup);
				return false;
			}
			
			if(support !is null) {
				ai.focus = support.position;
				armada.attack(support);
				return false;
			}
			
			@region = null;
			armada.fillFleets(ai);
		}
		
		return false;
	}
}

int64 buildFleetHash(FleetType type) {
	return (int64(ACT_Build) << ACT_BIT_OFFSET) | (int64(type));
}

class BuildFleet : Action {
	PlanRegion@ system;
	Object@ builder;
	Ship@ leader;
	FleetType type;
	FlagshipTask flag;
	int64 Hash;
	
	BuildFleet(FleetType Type) {
		Hash = buildFleetHash(Type);
		type = Type;
		switch(type) {
			case FT_Scout:
				flag = FST_Scout; break;
			case FT_Mothership:
				flag = FST_Mothership; break;
			default:
				flag = FST_Combat; break;
		}
	}

	BuildFleet(BasicAI@ ai, SaveFile& msg) {
		Object@ focus;
		msg >> focus;
		if(focus !is null)
			@system = ai.getPlanRegion(focus);
		
		msg >> builder;

		uint tp = 0;
		msg >> tp;
		type = FleetType(tp);

		msg >> Hash;
		
		msg >> leader;
		
		switch(type) {
			case FT_Scout:
				flag = FST_Scout; break;
			case FT_Mothership:
				flag = FST_Mothership; break;
			default:
				flag = FST_Combat; break;
		}
	}

	void postLoad(BasicAI@ ai) {
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		if(system is null) {
			Object@ none;
			msg << none;
		}
		else {
			msg << system.region;
		}
		
		msg << builder;
		msg << uint(type);
		msg << Hash;
		msg << leader;
	}

	int64 get_hash() const {
		return Hash;
	}

	ActionType get_actionType() const {
		return ACT_Build;
	}
	
	string get_state() const {
		if(system is null)
			return "Building fleet (type " + type + ")";
		else if(builder is null)
			return "Building fleet in " + system.region.name + " (type " + type + ")";
		else
			return "Building fleet at " + builder.name + " (type " + type + ")";
	}
	
	Ship@ findShipIn(BasicAI@ ai, Region@ region) {
		auto@ freeFleets = ai.untrackedFleets;
		auto@ expected = ai.getDesign(DT_Flagship, flag, create=false);
		if(expected is null)
			return null;
		@expected = expected.newest();
		
		for(uint i = 0, cnt = freeFleets.length; i < cnt; ++i) {
			Ship@ ship = freeFleets[i];
			if(ship.owner !is ai.empire || !ship.valid) {
				freeFleets.removeAt(i);
				--i; --cnt;
				continue;
			}
			
			if(region !is null && ship.region !is region)
				continue;
			if(ship.region is null)
				continue;
			
			const Design@ design = ship.blueprint.design;
			if(design.newest() !is expected)
				continue;
			
			ai.focus = ship.position;
			
			freeFleets.removeAt(i);
			
			switch(type) {
				case FT_Scout:
					ship.setHoldPosition(true);
				break;
				case FT_Mothership:
				break;
				default: {
					ai.willpower += gotFleetWill * float(design.size);
					//Use up any support ships available here
					for(uint j = 0, jcnt = ship.region.planetCount; j < jcnt; ++j) {
						Planet@ pl = ship.region.planets[j];
						if(pl.owner is ai.empire)
							ship.refreshSupportsFrom(pl);
					}
					
					ship.wait();
					uint supports = ship.SupplyAvailable;
					
					if(supports > 0) {
						//Heavy Gunships
						const Design@ hvy, lit, tnk, fill;
						@hvy = ai.getDesign(DT_Support, ST_AntiFlagship);
						if(hvy is null)
							@hvy = ai.empire.getDesign("Heavy Gunship");
						@lit = ai.getDesign(DT_Support, ST_AntiSupport);
						if(lit is null)
							@lit = ai.empire.getDesign("Beamship");
						@tnk = ai.getDesign(DT_Support, ST_Tank);
						if(tnk is null)
							@tnk = ai.empire.getDesign("Missile Boat");
						@fill = ai.getDesign(DT_Support, ST_Filler);
						if(fill is null)
							@fill = ai.empire.getDesign("Gunship");
						
						uint heavy = (supports / 3) / uint(hvy.size);
						uint light = (supports / 3) / uint(lit.size);
						uint tank = (supports / 5) / uint(tnk.size);
						uint filler = (supports - (heavy * uint(hvy.size) + light * uint(lit.size) + tank * uint(tnk.size))) / uint(fill.size);
						
						if(heavy > 0)
							ship.orderSupports(hvy, heavy);
						if(light > 0)
							ship.orderSupports(lit, light);
						if(tank > 0)
							ship.orderSupports(tnk, tank);
						if(filler > 0)
							ship.orderSupports(fill, filler);
					}
				} break;
			}
			
			return ship;
		}
		
		return null;
	}
	
	bool perform(BasicAI@ ai) {
		if(leader !is null) {
			if(!leader.valid || leader.owner !is ai.empire) {
				@leader = null;
			}
			else {
				ai.freeFleet(leader, type);
				if(type == FT_Mothership)
					ai.factories.insertLast(leader);
				@leader = null;
				return true;
			}
		}
		else if(system !is null) {
			Region@ region = system.region;
			
			@leader = findShipIn(ai, system.region);
			if(leader !is null) {
				@builder = null;
				@system = null;
				return false;
			}
			
			//Sometimes our constructor fails, oh well
			if(!builder.valid || builder.owner !is ai.empire || ai.isBuildIdle(builder) || builder.laborIncome == 0.0 || !builder.canBuildShips) {
				@builder = null;
				@system = null;
			}
		}
		else {
			@leader = findShipIn(ai, null);
			if(leader !is null) {
				@builder = null;
				@system = null;
				return false;
			}
			
			const Design@ dsg = ai.getDesign(DT_Flagship, flag);
			if(dsg is null)
				return false;
		
			for(uint i = 0, cnt = ai.factories.length; i < cnt; ++i) {
				Object@ buildAt = ai.factories[i];

				if(buildAt.owner is ai.empire && buildAt.hasConstruction && buildAt.canBuildShips &&
					ai.isBuildIdle(buildAt) && buildAt.laborIncome > TILE_LABOR_RATE * 2.95)
				{
					buildAt.buildFlagship(dsg);
					
					if(ai.skillEconomy >= DIFF_Medium) {
						int buildID = buildAt.constructionID[0];
						if(buildID != -1) {
							//Pre-order supports
							uint supports = dsg.total(SV_SupportCapacity);
							if(ai.skillEconomy < DIFF_Hard)
								supports /= 2;
								
							const Design@ hvy, lit, tnk, fill;
							@hvy = ai.getDesign(DT_Support, ST_AntiFlagship);
							if(hvy is null)
								@hvy = ai.empire.getDesign("Heavy Gunship");
							@lit = ai.getDesign(DT_Support, ST_AntiSupport);
							if(lit is null)
								@lit = ai.empire.getDesign("Beamship");
							@tnk = ai.getDesign(DT_Support, ST_Tank);
							if(tnk is null)
								@tnk = ai.empire.getDesign("Missile Boat");
							@fill = ai.getDesign(DT_Support, ST_Filler);
							if(fill is null)
								@fill = ai.empire.getDesign("Gunship");
							
							uint heavy = (supports / 3) / uint(hvy.size);
							uint light = (supports / 3) / uint(lit.size);
							uint tank = (supports / 5) / uint(tnk.size);
							uint filler = (supports - (heavy * uint(hvy.size) + light * uint(lit.size) + tank * uint(tnk.size))) / uint(fill.size);
							
							if(heavy > 0)
								buildAt.addSupportShipConstruction(buildID, hvy, heavy);
							if(light > 0)
								buildAt.addSupportShipConstruction(buildID, lit, light);
							if(tank > 0)
								buildAt.addSupportShipConstruction(buildID, tnk, tank);
							if(filler > 0)
								buildAt.addSupportShipConstruction(buildID, fill, filler);
						}
					}
					
					ai.focus = buildAt.position;
					@builder = buildAt;
					auto@ reg = buildAt.region;
					@system = reg !is null ? ai.findSystem(buildAt.region) : null;
					
					if(ai.skillEconomy >= DIFF_Medium && buildAt.isPlanet && buildAt.laborIncome < TILE_LABOR_RATE * min(gameTime/60.0 * 0.667, 25.0))
						ai.addIdle( ai.requestImport(cast<Planet>(buildAt), ai.getResourceList(RT_LaborZero, onlyExportable=true), execute=false) );
					
					break;
				}
			}
		}
		
		return false;
	}
}

int64 buildCombatHash(int systemID) {
	return (int64(ACT_Combat) << ACT_BIT_OFFSET) | int64(systemID);
}

uint classifyDesign(BasicAI@ ai, const Design@ design) {
	auto@ newest = design.newest();
	int task = -1;
	
	if(newest.hasTag(ST_Mothership))
		return FT_Mothership;
	if(design.hasTag(ST_Gate))
		return FT_INVALID;
	if(design.hasTag(ST_Slipstream))
		return FT_Slipstream;
	
	for(uint i = 0; i < FST_COUNT; ++i) {
		auto@ dsg = ai.getDesign(DT_Flagship, i, create=false);
		if(dsg !is null)
			@dsg = dsg.newest();
		if(newest is dsg) {
			task = int(i);
			break;
		}
	}
	
	
	if(task >= 0) {
		switch(task) {
			case FST_Scout:
				return FT_Scout;
			default:
				return FT_Combat;
		}
	}
	
	string name = newest.name;
	if(name == "Scout")
		return FST_Scout;
	
	return FT_Combat;
}

class Combat : Action {
	Object@ system;
	Ship@ fleet;
	bool checked = false;
	int64 Hash;
	
	Combat(Object@ System) {
		Hash = buildCombatHash(System.id);
		@system = System;
	}

	Combat(BasicAI@ ai, SaveFile& msg) {
		msg >> system;
		msg >> fleet;
		Hash = buildCombatHash(system.id);
		checked = fleet !is null;
	}

	void postLoad(BasicAI@ ai) {
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << system;
		msg << fleet;
	}

	int64 get_hash() const {
		return Hash;
	}

	ActionType get_actionType() const {
		return ACT_Combat;
	}
	
	string get_state() const {
		return "Engaging in combat in " + system.name;
	}
	
	void freeFleet(BasicAI@ ai) {
		if(fleet !is null) {
			fleet.rebuildAllGhosts();
			ai.freeFleet(fleet, FT_Combat);
			@fleet = null;
		}
	}
	
	bool perform(BasicAI@ ai) {
		if(fleet is null) {
			if(!checked) {
				vec3d center = system.position;
				vec3d bound(2000.0);
				array<Object@>@ objs = findInBox(center - bound, center + bound, ai.empire.hostileMask);
				if(objs.length == 0)
					return true;
				checked = true;
			}
			
			@fleet = ai.getAvailableFleet(FT_Combat);
		}
		else if(!fleet.valid) {
			@fleet = null;
		}
		else if(fleet.orderCount == 0) {
			vec3d center = system.position;
			if(fleet.position.distanceTo(center) > 2000.0) {
				vec3d off = fleet.position - center;
				off.y = 0;
				fleet.addMoveOrder(center + off.normalized(1000.0));
			}
			else {
				vec3d bound(2000.0);
				array<Object@>@ objs = findInBox(center - bound, center + bound, ai.empire.hostileMask);
				for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
					Object@ obj = objs[i];
					if(obj.isShip || obj.isOrbital) {
						fleet.addAttackOrder(obj);
						return false;
					}
				}
				
				//No enemies
				freeFleet(ai);
				return true;
			}
		}		
		return false;
	}
}

int64 buildWarHash(Empire& target) {
	return (int64(ACT_War) << ACT_BIT_OFFSET) | int64(target.id);
}

enum TargetGoal {
	TG_Capture,
	TG_Protect,
	TG_Assist
};

final class WarTarget {
	PlanRegion@ region;
	TargetGoal goal = TG_Capture;
	uint enemyPlanets = 0;
	double enemyStrength = 0;
	double value = 0;
	
	double minSiegeSupply = 0;
	double requestedSupply = 0;
	double enrouteStr = 0;
	
	int64 get_id() const {
		return region.region.id;
	}
	
	int opCmp(const WarTarget& other) const {
		double diff = value - other.value;
		if(diff > 0.01)
			return 1;
		else if(diff < -0.01)
			return -1;
		else
			return 0;
	}
	
	Object@ getJumpTarget(Empire& emp) const {
		if(goal == TG_Protect) {
			Planet@ anyOwned;
			for(uint i = 0, cnt = region.planets.length; i < cnt; ++i) {
				Planet@ pl = region.planets[i];
				if(pl.owner is emp) {
					if(pl.captureEmpire !is null)
						return pl;
					else
						@anyOwned = pl;
				}
			}
			return anyOwned;
		}
		else {
			for(uint i = 0, cnt = region.planets.length; i < cnt; ++i) {
				Planet@ pl = region.planets[i];
				if(emp.isHostile(pl.owner))
					return pl;
			}
		}
		
		return null;
	}
};

final class War : Action {
	Empire@ enemy;
	array<Armada@> fleets;
	array<WarTarget@> orders;
	array<WarTarget@> targets;
	map targetMap;
	
	Region@ stage;
	
	Region@ scoutTarget;
	Armada@ scout = Armada();
	int64 Hash;
	
	War(Empire@ Enemy) {
		Hash = buildWarHash(Enemy);
		@enemy = Enemy;
	}

	War(BasicAI@ ai, SaveFile& file) {
		file >> enemy;
		Hash = buildWarHash(enemy);
		
		uint8 fleetCount = 0;
		file >> fleetCount;
		
		fleets.length = fleetCount;
		orders.length = fleetCount;
		for(uint i = 0; i < fleets.length; ++i) {
			@fleets[i] = Armada(file);
			if(file > SV_0030) {
				int id = -1;
				file >> id;
				if(id != -1)
					@orders[i] = getTarget(ai.getPlanRegion(cast<Region>(getObjectByID(id))));
			}
		}
	
		if(file > SV_0030) {
			file >> stage;
			file >> scoutTarget;
		}
		@scout = Armada(file);
	}
	
	void freeFleets(BasicAI@ ai) {
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i)
			fleets[i].freeFleets(ai, FT_Combat);
		scout.freeFleets(ai, FT_Scout);
	}

	void postLoad(BasicAI@ ai) {
	}

	void save(BasicAI@ ai, SaveFile& file) {
		file << enemy;
		
		uint8 fleetCount = uint8(fleets.length);
		file << fleetCount;
		
		for(uint i = 0; i < fleetCount; ++i) {
			fleets[i].save(file);
			int id = -1;
			if(orders[i] !is null)
				id = orders[i].region.region.id;
			file << id;
		}
		
		file << stage;
		
		file << scoutTarget;
		scout.save(file);
	}

	int64 get_hash() const {
		return Hash;
	}

	ActionType get_actionType() const {
		return ACT_War;
	}
	
	string get_state() const {
		return "Waging war against the " + enemy.name;
	}
	
	Region@ findNearestSafe(BasicAI@ ai, const vec3d& pos) {
		if(stage !is null && stage.ContestedMask & ai.empire.mask == 0 && pos.distanceTo(stage.position) > stage.radius)
			return stage;
	
		Region@ nearest;
		double dist = 0;
			
		array<PlanRegion@>@ systems = ai.ourSystems;
		for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
			Region@ region = systems[i].region;
			if(region.ContestedMask & ai.empire.mask != 0)
				continue;
			double d = region.position.distanceToSQ(pos);
			if(nearest is null || d < dist) {
				dist = d;
				@nearest = region;
			}
		}
		
		return nearest;
	}
	
	bool scoutRegion(BasicAI@ ai, Region@ region) {
		if(region.VisionMask & ai.empire.visionMask != 0) {
			auto@ pr = ai.findSystem(region);
			if(pr is null || !ai.knownSystem(region))
				@pr = ai.addExploredSystem(region);
			pr.scout(ai);
			return true;
		}
	
		scout.validate(ai);
		if(scout.fleetCount == 0) {
			Ship@ scoutFleet = ai.getAvailableFleet(FT_Scout);
			if(scoutFleet !is null) {
				scoutFleet.clearOrders();
				scout.addFleet(ai, scoutFleet);
			}
		}
		else if(!scout.isInTransit) {
			scout.moveTo(ai, region);
		}
		return false;
	}
	
	void processCombat(BasicAI@ ai, Armada@ fleet) {
		uint empMask = ai.empire.mask;
		uint visionMask = ai.empire.visionMask;
		uint hostileMask = ai.empire.hostileMask;
		Region@ region = fleet.target;
		
		//We must wait until we get vision to make any more decisions
		if(region.VisionMask & visionMask == 0)
			return;
		
		PlanRegion@ plan = ai.getPlanRegion(region);
		
		array<Planet@> planets;
		array<Ship@> enemyFleets;
		array<Orbital@> enemyOrbitals;
		
		array<Object@>@ objects = plan.scout(ai);
		for(uint i = 0, cnt = objects.length; i < cnt; ++i) {
			Object@ obj = objects[i];
			if(obj.visibleMask & visionMask == 0 || obj.region !is region || obj.owner.mask & hostileMask == 0)
				continue;
			if(obj.isShip) {
				if(obj.hasLeaderAI) {
					enemyFleets.insertLast(cast<Ship>(obj));
				}
			}
			else if(obj.isOrbital) {
				enemyOrbitals.insertLast(cast<Orbital>(obj));
			}
			else if(obj.isPlanet) {
				if(obj.owner.valid)
					planets.insertLast(cast<Planet>(obj));
			}
		}
		
		Planet@ targetPlanet;
		int targetLoyalty = 0;
		if(planets.length > 0) {
			for(uint i = 0, cnt = planets.length; i < cnt; ++i) {
				Planet@ pl = planets[i];
				if(pl.owner is ai.empire) {
					if(!ai.isKnownPlanet(pl)) {
						ai.addPlanet(pl);
						ai.markAsColony(pl.region);
					}
				}
				else {				
					if(pl.owner.mask & ai.empire.hostileMask == 0 || pl.owner.mask & region.ProtectedMask.value != 0)
						continue;
					
					int loy = pl.getLoyaltyFacing(ai.empire);
					if(targetPlanet is null || loy < targetLoyalty || (loy == targetLoyalty && pl.id < targetPlanet.id)) {
						//Take planets in order of lowest loyalty first, and guarantee we always pick them in the same order (lowest id)
						@targetPlanet = pl;
						targetLoyalty = loy;
					}
				}
			}
		}
		
		//Attack orbitals first
		if(enemyOrbitals.length > 0) {
			Orbital@ target = enemyOrbitals[0];
			vec3d from = fleet.position;
			double nearest = from.distanceToSQ(enemyOrbitals[0].position);
			for(uint i = 1, cnt = enemyOrbitals.length; i < cnt; ++i) {
				double dist = from.distanceToSQ(enemyOrbitals[i].position);
				if(dist < nearest) {
					@target = enemyOrbitals[i];
					nearest = dist;
				}
			}
			
			fleet.attack(target);
			return;
		}
		
		//Calculate enemy strength
		double strength = 0, weak = 0;
		Ship@ weakest;
		
		double ourStrength = fleet.totalEffectiveness;
		
		for(uint i = 0, cnt = enemyFleets.length; i < cnt; ++i) {
			double hp = 0, dps = 0;
			
			Ship@ leader = enemyFleets[i];
			double str = leader.getFleetStrength();
			if(str > 1000.0 && str > ourStrength * 1.0e-2 && str < ourStrength * 2.5) {
				if(weakest is null || str < weak) {
					@weakest = enemyFleets[i];
					weak = str;
				}
			}
			strength += sqrt(str);
		}
		strength *= strength;
		
		bool underSiege = empMask & region.SiegedMask.value & region.ContestedMask != 0;
		//Attack the criminal scum
		if(underSiege) {
			if(weakest !is null) {
				fleet.attack(weakest);
				return;
			}
		}
		
		//If there's a planet to siege, take it
		if(targetPlanet !is null) {
			//However, if we've run out of supply, we need to leave to a different region
			double supply = fleet.totalSupply;
			if(supply == 0.0 || supply < ((double(targetLoyalty) - 0.5) * 3000.0)) {
				Region@ nearest = findNearestSafe(ai, fleet.position);
				if(nearest !is null)
					fleet.moveTo(ai, nearest);
				return;
			}
			
			fleet.conquer(targetPlanet);
			return;
		}
		
		//Attack the criminal scum
		if(weakest !is null && strength > ourStrength * 0.02) {
			fleet.attack(weakest);
			return;
		}
		
		@fleet.target = null;
	}
	
	WarTarget@ getTarget(PlanRegion@ region) {
		WarTarget@ targ;
		targetMap.get(region.region.id, @targ);
		if(targ is null) {
			@targ = WarTarget();
			@targ.region = region;
			targetMap.set(region.region.id, @targ);
			targets.insertLast(@targ);
		}
		return targ;
	}
	
	
	bool contestedFriendly = false;
	
	void evaluateTargets(BasicAI@ ai) {
		contestedFriendly = false;
		double rescoutDelay = 12.0 * 60.0;
		if(ai.skillScout < DIFF_Medium)
			rescoutDelay *= 2.0;
	
		for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
			auto@ target = targets[i];
			target.value = -1.0;
			target.enrouteStr = 0.0;
		}
		
		for(uint i = 0, cnt = orders.length; i < cnt; ++i) {
			auto@ order = orders[i];
			if(order is null)
				continue;
			order.enrouteStr = sqr(sqrt(order.enrouteStr) + sqrt(fleets[i].totalEffectiveness));
		}
		
		Region@ oldestUnknown, anyBorder, enemyBorder;
		double oldest = 0, dist = 1e9;
		
		vec3d averageUnknown;
		uint unknownCount = 0;
		array<Region@> borders;
		vec3d averageEnemy;
		uint enemyCount = 0;
		array<Region@> enemyBorders;
	
		//Go after systems that we know have enemy planets, and that border our systems
		array<PlanRegion@>@ systems = ai.exploredSystems;
		for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
			PlanRegion@ region = systems[i];
			
			if(region.planetMask & enemy.mask != 0) {
				averageUnknown += region.region.position;
				enemyCount += 1;
			}
			else {
				averageUnknown += region.region.position;
				unknownCount += 1;
			}
			
			Region@ adjacent;
			bool bordered = false;
			const SystemDesc@ sys = region.system;
			for(uint j = 0, jcnt = sys.adjacent.length; j < jcnt; ++j) {
				@adjacent = getSystem(sys.adjacent[j]).object;
				if(adjacent.TradeMask & ai.empire.mask != 0) {
					bordered = true;
					break;
				}
			}
			
			if(region.age > 12.0 * 60.0) {
				if(region.region.VisionMask & ai.empire.visionMask == 0) {
					if(oldestUnknown is null || region.age > oldest) {
						oldest = region.age;
						@oldestUnknown = region.region;
					}
				}
			}
			
			if(bordered)
				borders.insertLast(adjacent);
			
			auto@ target = getTarget(region);
			
			target.minSiegeSupply = 0;
			target.requestedSupply = 0;
			target.goal = TG_Capture;
			
			if(ai.allyMask & region.region.ContestedMask != 0)
				target.goal = TG_Assist;
			else if(region.planetMask & enemy.mask == 0 || enemy.mask & region.region.ProtectedMask.value != 0)
				continue;
			
			if(bordered)
				enemyBorders.insertLast(adjacent);
			
			bool sysIsVisible = region.region.VisionMask & ai.empire.visionMask != 0;
			
			target.enemyStrength = sqr(region.strengths[enemy.index]);
			target.enemyPlanets = region.planetMask & enemy.mask != 0 ? 1 : 0;
			if(sysIsVisible) {
				target.minSiegeSupply = 1.0e10;
				target.requestedSupply = 0;
				for(uint j = 0, jcnt = region.planets.length; j < jcnt; ++j) {
					Planet@ pl = region.planets[j];
					Empire@ owner = pl.visibleOwnerToEmp(ai.empire);
					if(ai.empire.isHostile(owner)) {
						double siegeCost = 3000.0 * double(pl.currentLoyalty);
						target.minSiegeSupply = min(target.minSiegeSupply, siegeCost);
						target.requestedSupply += siegeCost;
					}
				}
			}
			else {
				target.minSiegeSupply = max(9000.0, target.minSiegeSupply);
				target.requestedSupply = 9000.0;
			}
			
			if(ai.allyMask & region.region.ContestedMask != 0)
				target.value = 3.0;
			else if(target.enemyStrength > 1000.0 || target.enemyPlanets > 0)
				target.value = 0.5 + double(target.enemyPlanets);
			if(!bordered)
				target.value *= 0.125;
		}
		
		if(unknownCount > 0)
			averageUnknown /= double(unknownCount);
		if(enemyCount > 0)
			averageEnemy /= double(enemyCount);
		
		if(enemyBorders.length > 0) {
			Region@ closest;
			double dist = 1.0e35;
			
			for(uint i = 0, cnt = enemyBorders.length; i < cnt; ++i) {
				auto@ reg = enemyBorders[i];
				double d = reg.position.distanceToSQ(averageEnemy);
				if(d < dist) {
					dist = d;
					@closest = reg;
				}
			}
			
			if(closest !is null)
				@stage = closest;
		}
		else if(borders.length > 0) {
			Region@ closest;
			double dist = 1.0e35;
			
			for(uint i = 0, cnt = borders.length; i < cnt; ++i) {
				auto@ reg = borders[i];
				double d = reg.position.distanceToSQ(averageUnknown);
				if(d < dist) {
					dist = d;
					@closest = reg;
				}
			}
			
			if(closest !is null)
				@stage = closest;
		}
		
		if(oldestUnknown !is null && scoutTarget is null)
			@scoutTarget = oldestUnknown;
	
		//Look for systems we own that are under attack
		@systems = ai.ourSystems;
		for(uint i = 0, cnt = systems.length, offset = randomi(0,cnt-1); i < cnt; ++i) {
			auto@ reg = systems[(i + offset) % cnt];
			auto@ target = getTarget(reg);
			bool sysIsVisible = reg.region.VisionMask & ai.empire.visionMask != 0;
			
			if(!ai.didTickScan && reg.age > 3.0 * 60.0)
				if(sysIsVisible && reg.strengths[enemy.index] <= 0.0 && reg.planetMask & enemy.mask == 0)
					reg.scout(ai);
			
			target.goal = TG_Protect;
			target.enemyStrength = sqr(reg.strengths[enemy.index]);
			target.enemyPlanets = reg.planetMask & enemy.mask != 0 ? 1 : 0;
			target.requestedSupply = 0.0;
			
			if(sysIsVisible) {
				target.minSiegeSupply = 1.0e10;
				for(uint j = 0, jcnt = reg.planets.length; j < jcnt; ++j) {
					Planet@ pl = reg.planets[j];
					if(pl.owner is enemy) {
						double siegeCost = 3000.0 * double(pl.currentLoyalty);
						target.minSiegeSupply = min(target.minSiegeSupply, siegeCost);
						target.requestedSupply += siegeCost;
					}
				}
			}
			else {
				target.minSiegeSupply = max(9000.0, target.minSiegeSupply);
				target.requestedSupply = 9000.0;
			}
			
			if(!contestedFriendly)
				if(reg.region.ContestedMask & ~reg.region.ProtectedMask.value & ai.empire.mask != 0 || reg.planetMask & ~reg.region.ProtectedMask.value & enemy.mask != 0)
					contestedFriendly = true;
			
			//Planets being sieged, in a contested system, which isn't protected
			if(ai.empire.mask & reg.region.SiegedMask.value & reg.region.ContestedMask & ~reg.region.ProtectedMask.value != 0)
				target.value = 10.0;
			else if(target.enemyStrength > 1000.0)
				target.value = 2.0 + double(target.enemyPlanets);
			else if(target.enemyPlanets > 0) {
				target.goal = TG_Capture;
				target.value = 2.0 + double(target.enemyPlanets);
			}
		}
		
		//Increase importance of requested systems
		for(uint i = 0, cnt = ai.requests.length; i < cnt && i < 5; ++i) {
			Region@ reg = ai.requests[i].region;
			if(reg is null)
				continue;
			auto@ pr = ai.findSystem(reg);
			if(pr is null)
				continue;
			auto@ target = getTarget(pr);
			if(target is null)
				continue;
			
			target.value = (target.value * 1.2) + 0.3;
		}
		
		//Increase importance of systems that have revenant parts owned by enemies
		for(uint i = 0, cnt = ai.revenantParts.length; i < cnt && i < 5; ++i) {
			auto@ part = ai.revenantParts[i];
			Region@ reg = part.region;
			if(reg is null || !ai.empire.isHostile(part.owner))
				continue;
			auto@ pr = ai.findSystem(reg);
			if(pr is null)
				continue;
			auto@ target = getTarget(pr);
			if(target is null)
				continue;
			
			target.value = (target.value * 1.5 + 1.0);
		}
	}
	
	Ship@ pullFleet(BasicAI@ ai, bool onlyFull = true, bool purchase = false) {
		Ship@ ship;
		if(ai.fleets[FT_Titan].length > 0)
			@ship = ai.getAvailableFleet(FT_Titan);
		else if(ai.fleets[FT_Carrier].length > 0)
			@ship = ai.getAvailableFleet(FT_Carrier);
		else if(ai.fleets[FT_Combat].length > 1)
			@ship = ai.getAvailableFleet(FT_Combat);
		else if(purchase)
			@ship = ai.getAvailableFleet(FT_Titan);
		if(onlyFull && ship !is null) {
			if(ship.hasOrderedSupports) {
				ai.freeFleet(ship, FT_Combat);
				@ship = null;
			}
			else if(ship.SupplyAvailable > 0) {
				//Wait till the fleet is full
				if(!ai.fillFleet(ship)) {
					ai.freeFleet(ship, FT_Combat);
					@ship = null;
				}
			}
		}
		return ship;
	}
	
	string get_warID() const {
		return enemy.name + " War: ";
	}
	
	bool perform(BasicAI@ ai) {
		if(!ai.empire.isHostile(enemy) || !enemy.hasPlanets) {
			if(ai.logWar) ai.log.writeLine("War against " + ai.empire.name + " is over.");
			freeFleets(ai);
			return true;
		}
		
		//Idle the war, otherwise we won't free our fleets when the war ends
		ai.addIdle(this);
		
		//Check all current siege targets to see if they've been captured
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Planet@ sieging = fleets[i].siegePlanet;
			if(sieging !is null) {
				if(sieging.owner is ai.empire) {
					ai.addPlanet(sieging);
					ai.markAsColony(sieging.region);
				}
			}
		}
		
		//Clear out invalid/dead fleets
		for(int i = int(fleets.length) - 1; i >= 0; --i) {
			if(!fleets[i].validate(ai)) {
				if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleets[i].id + " destroyed.");
				fleets.removeAt(i);
				orders.removeAt(i);
			}
		}
		
		if(scoutTarget !is null)
			if(scoutRegion(ai, scoutTarget))
				@scoutTarget = null;
		
		//Update target evaluations, then decide the most valuable deployments
		// We are limited to a set number of deployments, based on difficulty (Easy=1, Medium=3, Hard=8)
		evaluateTargets(ai);
		
		bool newFleet = false;
		
		if(fleets.length == 0) {
			Ship@ fleet = pullFleet(ai, onlyFull = !contestedFriendly, purchase=true);
			if(fleet !is null) {
				fleets.insertLast(Armada());
				orders.insertLast(null);
				fleets[0].addFleet(ai, fleet);
				if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleets[0].id + " created.");
			}
		}
		else {
			uint fleetCap = 1;
			if(ai.skillCombat >= DIFF_Hard)
				fleetCap = 8;
			else if(ai.skillCombat >= DIFF_Medium)
				fleetCap = 3;
			
			//Create a spare fleet if we have a lot of unused fleets
			if(fleets.length < fleetCap && (ai.fleets[FT_Combat].length > 0 || fleets[0].fleetCount >= 3)) {
				bool allBusy = true;
				for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
					auto@ order = orders[i];
					if(order is null || order.region.region is stage) {
						allBusy = false;
						break;
					}
				}
				
				if(allBusy) {
					Ship@ fleet = pullFleet(ai, purchase=true);
					if(fleet !is null) {
						fleets.insertLast(Armada());
						orders.insertLast(null);
						fleets[fleets.length-1].addFleet(ai, fleet);
						newFleet = true;
						if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleets[fleets.length-1].id + " created (active fleets busy).");
					}
				}
			}
			
			//Free excess idle fleets
			if(fleets.length > 1) {
				bool allIdle = true;
				for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
					auto@ order = orders[i];
					if(order !is null && (order.region.region !is stage || stage.ContestedMask & ai.empire.mask != 0)) {
						allIdle = false;
						break;
					}
				}
				
				if(allIdle) {
					uint n = fleets.length-1;
					if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleets[n].id + " released (fleets idle).");
					fleets[n].freeFleets(ai, FT_Combat);
					fleets.length = n;
					orders.length = n;
				}
			}
			
			uint index = newFleet ? fleets.length-1 : randomi(0, fleets.length-1);
			Armada@ fleet = fleets[index];
			if(fleet.isInTransit)
				return false;
			
			WarTarget@ target = orders[index];
			if(target !is null)
				ai.focus = target.region.region.position;
			else
				ai.focus = fleet.position;
			
			double strength = fleet.totalEffectiveness;
			double supply = fleet.totalSupply;
			double siegeSupply = supply - 3000.0;
			vec3d pos = fleet.position;
			
			Region@ underAttack;
			double scariest = 0;
			
			double strThresh = 1.5;
			if(ai.skillCombat < DIFF_Medium)
				strThresh = 0.75;
			
			//Find the best (other) target we have
			WarTarget@ best;
			double bestScore = 0;
			for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
				auto@ other = targets[i];
				if(other is target || other.value == 0.0)
					continue;
				double score = other.value * (8000.0 / (8000.0 + other.region.region.position.distanceTo(pos)));
				
				if(other.enrouteStr > 0.0 && other.enrouteStr > other.enemyStrength * strThresh)
					score *= 0.25 * other.enemyStrength / other.enrouteStr;
					
				bool weak = false;
				
				double totStr = sqr(sqrt(strength) + sqrt(other.enrouteStr));
				if(totStr < other.enemyStrength * strThresh) {
					score *= totStr / (other.enemyStrength * strThresh);
					weak = true;
				}
				
				if(totStr < other.enemyStrength * 0.25)
					score *= 0.1;
				
				if(other.goal == TG_Protect && weak && (underAttack is null || scariest < other.value)) {
					@underAttack = other.region.region;
					scariest = other.value;
				}
				
				if(other.goal == TG_Capture) {
					if(siegeSupply < other.minSiegeSupply)
						score *= 0.0;
					else if(siegeSupply < other.requestedSupply)
						score *= 0.9;
				}
				
				if(best is null || score > bestScore) {
					@best = other;
					bestScore = score;
				}
			}
			
			if(underAttack !is null && gameTime > ai.lastPing + 60.0) {
				@ai.protect = ai.getPlanRegion(underAttack);
				ai.lastPing = gameTime;
				if(ai.allyMask != 0) {
					vec2d p = random2d(250.0, underAttack.radius * 0.9);
					sendPing(ai.empire, underAttack.position + vec3d(p.x, 0.0, p.y));
					if(ai.logWar) ai.log.writeLine(warID + "Requesting help at " + underAttack.name + ".");
				}
				else {
					if(ai.logWar) ai.log.writeLine(warID + "Protecting " + underAttack.name + ".");
				}
			}
			
			double currentScore = 0;
			if(target !is null) {
				double score = target.value;
				
				double totStr = sqr(sqrt(strength) + sqrt(target.enrouteStr));
				if(totStr < target.enemyStrength * strThresh)
					score *= totStr / (target.enemyStrength * strThresh);
				if(totStr < target.enemyStrength * 0.25)
					score *= 0.1;
				
				if(target.goal == TG_Capture) {
					if(siegeSupply < target.minSiegeSupply)
						score *= 0.25;
					else if(siegeSupply < target.requestedSupply)
						score *= 0.9;
				}
				
				if(target.region.region.SiegingMask.value & (ai.empire.mask | ai.allyMask) != 0)
					score *= 2.0;
				
				currentScore = score;
			}
			
			if(fleet.isInCombat(ai.empire)) {
				processCombat(ai, fleet);
		
				if(target !is null) {
					//Update target data
					target.enemyStrength = sqr(target.region.strengths[enemy.index]);
					target.enemyPlanets = (target.region.planetMask & enemy.mask != 0) ? 1 : 0;
					double regionStr = target.enrouteStr;
					
					//Decide if we should end the combat
					bool endCombat = false;
					if(target.goal == TG_Protect) {
						if(regionStr < target.enemyStrength * (strThresh * 0.3333)) {
							endCombat = true;
							if(ai.logWar) ai.log.writeLine(warID + "Fleeing fleet " + fleet.id + " from " + target.region.region.name + " due to strong opposition.");
						}
					}
					else if(ai.skillCombat >= DIFF_Medium) {
						if(regionStr < target.enemyStrength * (strThresh * 0.5)) {
							endCombat = true;
							if(ai.logWar) ai.log.writeLine(warID + "Fleeing fleet " + fleet.id + " from " + target.region.region.name + " due to strong opposition.");
						}
						else if(target.enemyPlanets > 0 && siegeSupply < target.minSiegeSupply) {
							endCombat = true;
							if(ai.logWar) ai.log.writeLine(warID + "Fleeing fleet " + fleet.id + " from " + target.region.region.name + " due to insufficient supply.");
						}
					}
					
					if(endCombat) {
						Region@ safe = findNearestSafe(ai, pos);
						if(safe !is null) {
							if(ai.logWar) ai.log.writeLine("\tFleeing to " + safe.name);
							fleet.moveTo(ai, safe);
							return false;
						}
						else {
							if(ai.logWar) ai.log.writeLine("\tNowhere to flee");
						}
					}
					
					//Consider changing targets					
					if(bestScore > currentScore && best !is null) {
						@orders[index] = best;
						@target = best;
						Object@ jumpTo = null;
						if(ai.skillCombat >= DIFF_Medium)
							@jumpTo = best.getJumpTarget(ai.empire);
						fleet.moveTo(ai, best.region.region, around=jumpTo);
						if(ai.logWar) ai.log.writeLine(warID + "Changing fleet " + fleet.id + " target to " + best.region.region.name + " due to better score.");
					}
					else if(regionStr < target.enemyStrength * 2.0) {
						Ship@ ship = pullFleet(ai, onlyFull = (target.goal != TG_Protect));
						if(ship !is null) {
							fleet.addFleet(ai, ship);
							if(ai.logWar) ai.log.writeLine(warID + "Assigning fleet to fleet " + fleet.id + " to improve strength.");
						}
					}
				}
				
				return false;
			}
			
			if(target !is null) {
				if(fleet.region is target.region.region) {
					@target = best;
					@orders[index] = target;
				
					fleet.rebuildAllGhosts();
					
					if(stage !is null && fleet.target !is stage) {
						if(fleet.supportCapacityAvailable > 15 || fleet.hasOrderedSupports) {
							fleet.moveTo(ai, stage);
							if(ai.logWar) ai.log.writeLine(warID + "Staging fleet " + fleet.id + " to recover supports.");
						}
					}
				}
				else {
					//Consider changing targets	
					if(bestScore > target.value) {
						@target = best;
						@orders[index] = target;
					}
					
					//Attack only if we have enough strength, and gather fleets till we do
					// When protecting systems, we accept more risk
					// Easy AIs purposefully attack in worse situations
					bool doAssault = true;
					double reqStr = target.enemyStrength;
					if(target.goal == TG_Protect)
						reqStr *= 0.67;
					else if(ai.skillCombat >= DIFF_Medium)
						reqStr *= 1.5;
					else
						reqStr *= 0.75;
					
					if(strength < reqStr) {
						Ship@ ship = ai.getAvailableFleet(FT_Carrier);
						if(ship !is null)
							fleet.addFleet(ai, ship);
						doAssault = false;
						if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleet.id + " requires more strength to attack " + target.region.region.name + ".");
					}
					else if(target.goal == TG_Capture && fleet.fleetCount > 1) {
						bool freedAny = false;
						double needSupply = target.requestedSupply;
						while(strength > reqStr * 2.5) {
							Ship@ ship = fleet.freeToStrength(reqStr * 2.5);
							if(ship is null)
								break;
							if(fleet.totalSupply > needSupply) {
								ai.freeFleet(ship, FT_Combat);
								freedAny = true;
							}
							else {
								fleet.addFleet(ai, ship);
								break;
							}
						}
						
						if(freedAny && ai.logWar) ai.log.writeLine(warID + "Freed fleets from fleet " + fleet.id + " to meet needs.");
					}
					
					if(doAssault && target.goal == TG_Capture && (fleet.totalSupply <= target.minSiegeSupply || fleet.totalSupply < fleet.maxSupply * 0.9)) {
						doAssault = false;
						if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleet.id + " requires more supply to siege " + target.region.region.name + ".");
					}
					
					if(doAssault) {
						Object@ jumpTo = null;
						if(ai.skillCombat >= DIFF_Medium)
							@jumpTo = target.getJumpTarget(ai.empire);
						fleet.moveTo(ai, target.region.region, around=jumpTo);
						if(ai.logWar) ai.log.writeLine(warID + "Fleet " + fleet.id + " sent to assault " + target.region.region.name + ".");
					}
					else {
						Ship@ ship = ai.getAvailableFleet(FT_Carrier);
						if(ship !is null)
							fleet.addFleet(ai, ship);
					}
				}
			}
			else {
				if(target is null && stage !is null && fleet.target !is stage)
					fleet.moveTo(ai, stage);
			}
			
			if(stage !is null && fleet.target is stage) {
				fleet.fillFleets(ai);
			
				@orders[index] = best;
				@target = best;
				Ship@ ship = pullFleet(ai);
				if(ship !is null)
					fleet.addFleet(ai, ship);
				
				if(ai.logWar) ai.log.writeLine(warID + "Changing fleet " + fleet.id + " target to " + best.region.region.name + " because it is staging.");

				if(ai.needsMainframes && ai.mainframeMod !is null) {
					Orbital@ orb = ai.empire.getClosestOrbital(ai.mainframeMod.id, stage.position);
					if(orb is null || orb.position.distanceTo(stage.position) > stage.radius)
						ai.requestOrbital(stage, OT_Mainframe);
				}

				if(ai.ftl == FTL_Fling) {
					if(ai.empire.getFlingBeacon(stage.position) is null)
						ai.requestOrbital(stage, OT_FlingBeacon);
				}
				else if(ai.ftl == FTL_Gate) {
					auto@ gate = ai.empire.getStargate(stage.position);
					if(gate is null || gate.position.distanceTo(stage.position) > 10000.0)
						ai.requestOrbital(stage, OT_Gate);
				}
				else if(ai.ftl == FTL_Slipstream) {
					if(gameTime > ai.lastSlipstream + 300.0) {
						auto@ slip = ai.getAvailableFleet(FT_Slipstream);
						if(slip !is null && !slip.hasOrders) {
							vec2d off = random2d(250.0, stage.radius);
							vec3d dest = stage.position + vec3d(off.x, 0.0, off.y);
							if(slipstreamCost(slip, 1, dest.distanceTo(slip.position)) <= ai.empire.FTLStored) {
								slip.addSlipstreamOrder(dest);
								ai.lastSlipstream = gameTime;
							}
						}
						
						if(slip !is null)
							ai.freeFleet(slip, FT_Slipstream);
					}
				}
				
				if(fleet.hasOrderedSupports) {
					if(!ai.factoriesInRegion(stage) && !ai.isMachineRace) {
						ai.requestOrbital(stage, OT_Shipyard);
					}
				}
			}
		}
		
		return false;
	}
}


int64 designHash(uint type, uint task) {
	return int64(ACT_Design) << ACT_BIT_OFFSET | int64(type) << 32 | int64(task);
}

class MakeDesign : Action {
	uint type, task;
	Designer@ designer;
	bool prepared = false;
	array<const Design@> tries;
	
	double goalSpeed = 0;

	MakeDesign(uint Type, uint Task) {
		type = Type;
		task = Task;
	}

	MakeDesign(BasicAI@ ai, SaveFile& file) {
		file >> type >> task;
	}

	void save(BasicAI@ ai, SaveFile& file) {
		file << type << task;
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return designHash(type, task);
	}

	ActionType get_actionType() const {
		return ACT_Design;
	}
	
	string get_state() const {
		return "Designing " + type + ":" + task;
	}
	
	const Design@ getCurrentDesign(BasicAI@ ai) {
		switch(type) {
			case DT_Support:
				if(task < ST_COUNT)
					return ai.dsgSupports[task];
				break;
			case DT_Flagship:
				if(task < FST_COUNT)
					return ai.dsgFlagships[task];
				break;
			case DT_Station:
				if(task < STT_COUNT)
					return ai.dsgStations[task];
				break;
		}
		return null;
	}
	
	void replaceDesign(BasicAI@ ai, const Design@ dsg) {
		if(dsg is null)
			return;
		
		bool added = false;
		const Design@ prev = getCurrentDesign(ai);
		
		switch(type) {
			case DT_Support:
				if(task < ST_COUNT) {
					@ai.dsgSupports[task] = dsg;
					added = true;
				}
				if(dsg.total(SV_SupportSupplyCapacity) > 0.001) {
					DesignSettings settings;
					settings.behavior = SG_Brawler;

					dsg.setSettings(settings);
				}
				else if(task == ST_Tank) {
					DesignSettings settings;
					settings.behavior = SG_Shield;

					dsg.setSettings(settings);
				}
				break;
			case DT_Flagship:
				if(task < FST_COUNT) {
					@ai.dsgFlagships[task] = dsg;
					added = true;
				}
				break;
			case DT_Station:if(task < STT_COUNT) {
					@ai.dsgStations[task] = dsg;
					added = true;
				}
				break;
		}
		
		if(added) {
			string name = dsg.name;
			uint try = 0;
			while(ai.empire.getDesign(name) !is null) {
				name = dsg.name + " ";
				appendRoman(++try, name);
			}
			if(name != dsg.name)
				dsg.rename(name);
			if(prev is null)
				ai.empire.addDesign(ai.empire.getDesignClass("Combat", true), dsg);
			else
				ai.empire.changeDesign(prev, dsg, ai.empire.getDesignClass("Combat", true));
		}
	}
	
	bool perform(BasicAI@ ai) {
		if(!prepared) {
			prepared = true;

			double budget = ai.empire.TotalBudget;
			auto@ cur = getCurrentDesign(ai);

			double supportScaleFactor = max(1.0, log(budget / 500.0) / log(2.0));
			double flagScaleFactor = supportScaleFactor;
			if(ai.skillCombat >= DIFF_Medium) {
				flagScaleFactor = max(flagScaleFactor, double(ai.empire.EstNextBudget) / 4.0 / 64.0);
				flagScaleFactor = clamp(flagScaleFactor, 1.0, ((ai.getMaxFactoryLabor() * 60.0 * 10.0) * 2.5) / 64.0);
			}

			double goalScale = 1;
			
			switch(type) {
				case DT_Support:
					goalSpeed = 3.0;
					switch(task) {
						case ST_Filler:
							goalScale = supportScaleFactor; break;
						case ST_AntiSupport:
							goalScale = supportScaleFactor * 4.0; break;
						case ST_AntiFlagship:
							goalScale = supportScaleFactor * 9.0; break;
						case ST_Tank:
							goalScale = supportScaleFactor * 5.0; break;
						case ST_Supplies:
							goalScale = supportScaleFactor * 4.0; break;
						default:
							return true;
					}
					break;
				case DT_Flagship:
					goalSpeed = 1.45;
					switch(task) {
						case FST_Scout:
							goalScale = 16.0;
							if(ai.ftl != FTL_Hyperdrive && ai.ftl != FTL_Jumpdrive)
								goalSpeed *= 2.0;
							goalSpeed *= 2.5;
							break;
						case FST_Combat:
							goalScale = flagScaleFactor * 64.0; break;
						case FST_SuperHeavy:
							goalScale = flagScaleFactor * 128.0; break;
						default:
							return true;
					}
					break;
				default:
					return true;
			}

			goalScale = max(floor(goalScale), 1.0);
			if(cur !is null && floor(cur.size * 1.1) >= goalScale)
				return true;

			if(ai.cannotDesign) {
				const Design@ baseDesign;
				string name, tag;
				switch(type) {
					case DT_Support:
						switch(randomi(0,3)) {
							case 0: @baseDesign = ai.empire.getDesign("Gunship"); break;
							case 1: @baseDesign = ai.empire.getDesign("Missile Boat"); break;
							case 2: @baseDesign = ai.empire.getDesign("Beamship"); break;
							case 3: @baseDesign = ai.empire.getDesign("Heavy Gunship"); break;
						}
						name = autoSupportNames[randomi(0,autoSupportNames.length-1)];
						tag = "Support";
					break;
					case DT_Flagship:
						if(task == FST_Scout) {
							@baseDesign = ai.empire.getDesign("Scout");
						}
						else {
							switch(randomi(0,2)) {
								case 0: @baseDesign = ai.empire.getDesign("Heavy Carrier"); break;
								case 1: @baseDesign = ai.empire.getDesign("Dreadnaught"); break;
								case 2: @baseDesign = ai.empire.getDesign("Battleship"); break;
							}
						}
						name = autoFlagNames[randomi(0,autoFlagNames.length-1)];
						tag = "Flagship";
					break;
				}

				if(baseDesign is null)
					return true;

				DesignDescriptor desc;
				desc.name = name;
				desc.className = "Combat";
				desc.gridSize = getDesignGridSize(tag, goalScale);
				desc.size = goalScale;
				@desc.hull = getBestHull(desc, tag, ai.empire);
				@desc.owner = ai.empire;

				uint sysCnt = baseDesign.subsystemCount;
				for(uint i = 0; i < sysCnt; ++i) {
					const Subsystem@ sys = baseDesign.subsystems[i];
					if(sys.type.isHull)
						continue;
					if(sys.type.isApplied) {
						desc.applySubsystem(sys.type);
						continue;
					}

					desc.addSystem(sys.type);
					desc.setDirection(sys.direction);
					uint hexCnt = sys.hexCount;
					for(uint j = 0; j < hexCnt; ++j) {
						vec2u hex = sys.hexagon(j);
						desc.addHex(hex, sys.module(j));
					}
				}
				
				auto@ dsg = makeDesign(desc);
				if(dsg !is null && !dsg.hasFatalErrors())
					replaceDesign(ai, dsg);
				return true;
			}

			@designer = Designer(type, goalScale, ai.empire);
			designer.randomHull = true;
			if(task == FST_Scout)
				designer.composeScout();
		}
		
		auto@ dsg = designer.design(1);
		if(dsg !is null)
			tries.insertLast(dsg);
		
		if(tries.length < uint(2 + ai.skillTech)) {
			ai.addIdle(this);
			return false;
		}
		
		//Evaluate the available designs and pick one to use
		array<double> values(tries.length);
		for(uint i = 0, cnt = tries.length; i < cnt; ++i) {
			//error("Design " + i);
			@dsg = tries[i];
			
			double value = 1.0;
			
			double hyperSpeed = dsg.total(SV_HyperdriveSpeed);
			if(hyperSpeed > 0.0) {
				//Hyperdrive races are guaranteed to receive a hyperdrive in their flagships
				if(hyperSpeed < 125.0)
					value /= 10.0;
				else if(hyperSpeed < 175.0)
					value /= 2.0;
				else if(hyperSpeed < 375.0) {
					if(task == FST_Scout)
						value /= 1.8;
				}
				else if(task != FST_Scout) {
					value /= 1.5;
				}
			}

			double jumpRange = dsg.total(SV_JumpRange);
			if(jumpRange > 0.0) {
				if(jumpRange < 5000.0)
					value /= 10.0;
				else if(jumpRange < 15000.0)
					value /= 2.0;
				else if(jumpRange < 25000.0) {
					if(task == FST_Scout)
						value /= 1.8;
				}
				else if(task != FST_Scout) {
					value /= 1.5;
				}
			}
			
			double thrust = dsg.total(SV_Thrust);
			double mass = max(dsg.total(HV_Mass), 0.01);
			{
				double speed = thrust / mass;
				//error("Speed: " + speed + "/" + goalSpeed);
				if(speed < goalSpeed)
					value *= pow(speed / goalSpeed, 2.0);
				else if(speed > goalSpeed * 1.5)
					value *= goalSpeed / speed;
			}
			
			double str = 0.0;
			if(task != FST_Scout) {
				double dps = dsg.total(SV_DPS);
				double hp = dsg.totalHP + dsg.total(SV_ShieldCapacity);
				str = sqrt(dps * hp);
				value *= str;
			}
			
			if(type == DT_Flagship) {
				auto@ support = ai.dsgSupports[ST_AntiFlagship];
				double supportStr = support is null ? 30.0 : sqrt(support.total(SV_DPS) * (dsg.totalHP + dsg.total(SV_ShieldCapacity)));
				double supportSize = support is null ? 1.0 : double(support.size);
				
				if(dsg.hasTag(ST_SupportCap))
					str += dsg.total(SV_SupportCapacity) / supportSize * supportStr;
				
				//Avoid wasting resources
				double commandUsed = dsg.variable(ShV_REQUIRES_Command);
				double commandNeed = dsg.total(SV_Command);
				if(commandNeed < commandUsed * 0.8)
					value *= 0.5 + commandNeed / commandUsed * 0.5;
				
				double powerUsed = dsg.variable(ShV_REQUIRES_Power);
				double powerNeed = dsg.total(SV_Power);
				if(powerNeed < powerUsed * 0.8)
					value *= 0.5 + powerNeed / powerUsed * 0.5;
				
				double maint = dsg.total(HV_MaintainCost);
				value /= maint;
			}
			
			value /= sqrt(dsg.total(HV_BuildCost));
			
			if(str != 0.0)
				value *= str;
			
			values[i] = value;
		}
		
		double best = -INFINITY;
		//uint bestInd = 0;
		for(uint i = 0, cnt = tries.length; i < cnt; ++i) {
			double value = values[i];
			if(value > best) {
				best = value;
				@dsg = tries[i];
				//bestInd = i;
			}
		}
		//error("Chose " + dsg.name + " id " + bestInd);
		
		replaceDesign(ai, dsg);
		return true;
	}
}


