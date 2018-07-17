import systems;
import planet_loyalty;
import region_effects;
import saving;
import region_effects.ZealotRegion;
import notifications;
import statuses;
from resources import getLaborCost;
from cargo import hasDesignCosts;
from settings.game_settings import gameSettings;
from region_effects.GrantVision import GrantVision;
import constructions;
import hooks;

#section server
import object_creation;
import resources;
import civilians;
import achievements;
#section all

const uint ZealotMask = 0;
const double CIV_TIMER = 3.0 * 60.0;
const double TRADE_TIMER = 3.0 * 60.0;
const double STATION_TRADES = 6.0;
const double CIVILIAN_LIMIT_POW = 0.85;

tidy class RegionObjects : Component_RegionObjects, Savable {
	SystemDesc@ system;
	Star@[] starList;
	Object@[] objectList;
	Object@[] shipyardList;
	Planet@[] planetList;
	Orbital@[] orbitalList;
	Asteroid@[] asteroidList;
	Anomaly@[] anomalyList;
	Pickup@[] pickupList;
	Artifact@[] artifactList;
	Object@[] resourceHolders;
	RegionEffect@[] effects;
	int nextEffectId = 1;
	SystemPlaneNode@ plane;
	bool planeParented = false;
	TradeLinesNode@ tradeLines;
	array<IconRing@> icons;
	float combatTimer = 60.0;
	double StarTemperature = 0;
	double StarRadius = 0;

	PlanetBucket planetBucket;
	PickupBucket pickupBucket;
	AsteroidBucket asteroidBucket;
	ArtifactBucket artifactBucket;
	AnomalyBucket anomalyBucket;
	StarBucket starBucket;
	
	double PeriodicUpdate = 0.0;
	double PeriodicTime = 0.0;
	
	double regionDPS = 0.0;
	double starDPS = 0.0;

	int[] strengths(getEmpireCount(), 0);
	int[] planetCounts(getEmpireCount(), 0);
	int[] objectCounts(getEmpireCount(), 0);
	int[] visionGrants(getEmpireCount(), 0);
	int[] tradeGrants(getEmpireCount(), 0);
	Empire@[] primaryVision(getEmpireCount(), defaultEmpire);
	Empire@ primaryEmpire;

	double[] empLoyaltyBonus(getEmpireCount(), 0);
	double[] neighbourLoyalty(getEmpireCount(), 0);
	double[] localLoyalty(getEmpireCount(), 0);
	uint HasMilitaryMask = 0;
	uint HasPlanetsMask = 0;
	uint visibleContested = CM_None;

	uint TradeRequestMask = 0;
	array<int> tradeCounter(getEmpireCount(), 0);
	double tradeTimer = 0.0;
	array<Civilian@> tradeStations;
	uint HaveStationsMask = 0;

	array<uint> regionStatusTypes;
	array<double> regionStatusTimers;
	array<Empire@> regionStatusEmps;

	array<locked_Territory> territories(getEmpireCount());

	RegionObjects() {
	}

#section server
	void load(SaveFile& msg) {
		PeriodicUpdate = randomd();
	
		uint cnt = 0;
		msg >> cnt;
		starList.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> starList[i];
			if(starList[i] !is null)
				starBucket.add(starList[i]);
		}

		msg >> cnt;
		objectList.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> objectList[i];

		msg >> cnt;
		planetList.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> planetList[i];
			if(planetList[i] !is null)
				planetBucket.add(planetList[i]);
		}

		msg >> cnt;
		orbitalList.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> orbitalList[i];

		msg >> cnt;
		asteroidList.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> asteroidList[i];
			if(asteroidList[i] !is null)
				asteroidBucket.add(asteroidList[i]);
		}

		if(msg >= SV_0039) {
			msg >> cnt;
			anomalyList.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				msg >> anomalyList[i];
				if(anomalyList[i] !is null)
					anomalyBucket.add(anomalyList[i]);
			}
		}

		if(msg >= SV_0163) {
			msg >> cnt;
			artifactList.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				msg >> artifactList[i];
				if(artifactList[i] !is null)
					artifactBucket.add(artifactList[i]);
			}

			msg >> cnt;
			pickupList.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				msg >> pickupList[i];
				if(pickupList[i] !is null)
					pickupBucket.add(pickupList[i]);
			}
		}

		msg >> cnt;
		shipyardList.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> shipyardList[i];

		msg >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			uint id = msg.readIdentifier(SI_RegionEffect);
			const RegionEffectType@ type = getRegionEffect(id);

			RegionEffect@ eff = type.create();
			msg >> eff.id;
			msg >> eff.forEmpire;
			eff.load(msg);
			effects.insertLast(eff);
		}

		msg >> cnt;
		regionStatusTypes.length = cnt;
		regionStatusTimers.length = cnt;
		regionStatusEmps.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			regionStatusTypes[i] = msg.readIdentifier(SI_Status);
			msg >> regionStatusTimers[i];
			msg >> regionStatusEmps[i];
		}

		msg >> nextEffectId;
		msg >> primaryEmpire;

		uint statCnt = getEmpireCount();
		for(uint i = 0; i < statCnt; ++i) {
			msg >> strengths[i];
			msg >> objectCounts[i];
			msg >> primaryVision[i];
			msg >> planetCounts[i];
			msg >> empLoyaltyBonus[i];
			msg >> neighbourLoyalty[i];
			msg >> localLoyalty[i];
			msg >> visionGrants[i];
			if(msg >= SV_0059)
				msg >> tradeGrants[i];
			territories[i].set(cast<Territory>(msg.readObject()));
			if(msg >= SV_0048)
				msg >> tradeCounter[i];
		}

		msg >> HasMilitaryMask;
		msg >> HasPlanetsMask;
		msg >> visibleContested;
		msg >> combatTimer;

		if(msg >= SV_0048) {
			msg >> TradeRequestMask;
			msg >> HaveStationsMask;
			msg >> tradeTimer;
			uint tCount = 0;
			msg >> tCount;
			tradeStations.length = tCount;
			for(uint i = 0; i < tCount; ++i)
				@tradeStations[i] = cast<Civilian>(msg.readObject());
		}
		
		if(msg >= SV_0103) {
			msg >> regionDPS;
			if(msg >= SV_0123)
				msg >> starDPS;
		}
	}

	void save(SaveFile& msg) {
		uint cnt = starList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << starList[i];

		cnt = objectList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << objectList[i];

		cnt = planetList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << planetList[i];

		cnt = orbitalList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << orbitalList[i];

		cnt = asteroidList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << asteroidList[i];

		cnt = anomalyList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << anomalyList[i];

		cnt = artifactList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << artifactList[i];

		cnt = pickupList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << pickupList[i];

		cnt = shipyardList.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << shipyardList[i];

		cnt = effects.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg.writeIdentifier(SI_RegionEffect, effects[i].type.id);
			msg << effects[i].id;
			msg << effects[i].forEmpire;
			effects[i].save(msg);
		}

		cnt = regionStatusTypes.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg << regionStatusTypes[i];
			msg << regionStatusTimers[i];
			msg << regionStatusEmps[i];
		}

		msg << nextEffectId;
		msg << primaryEmpire;

		uint statCnt = getEmpireCount();
		for(uint i = 0; i < statCnt; ++i) {
			msg << strengths[i];
			msg << objectCounts[i];
			msg << primaryVision[i];
			msg << planetCounts[i];
			msg << empLoyaltyBonus[i];
			msg << neighbourLoyalty[i];
			msg << localLoyalty[i];
			msg << visionGrants[i];
			msg << tradeGrants[i];
			msg << territories[i].get();
			msg << tradeCounter[i];
		}

		msg << HasMilitaryMask;
		msg << HasPlanetsMask;
		msg << visibleContested;
		msg << combatTimer;

		msg << TradeRequestMask;
		msg << HaveStationsMask;
		msg << tradeTimer;
		uint tCount = tradeStations.length;
		msg << tCount;
		for(uint i = 0; i < tCount; ++i)
			msg << tradeStations[i];
		
		msg << regionDPS;
		msg << starDPS;
	}

	void regionPostLoad(Object& obj) {
		Region@ region = cast<Region>(obj);
		@system = getSystem(region);

		@plane = SystemPlaneNode();
		plane.establish(region);
		plane.setPrimaryEmpire(primaryEmpire);
		plane.setContested(visibleContested);
		plane.hintParentObject(obj, false);

		StarTemperature = 0;
		for(uint i = 0, cnt = starList.length; i < cnt; ++i)
			StarTemperature += starList[i].temperature;
		if(starList.length != 0)
			StarRadius = starList[0].radius;
		else
			StarRadius = 0;
	}
#section all
	void addShipDebris(vec3d position, uint count = 1) {
		if(plane !is null)
			plane.addMetalDebris(position, count);
	}

#section shadow
	void save(SaveFile&){}
	void load(SaveFile&){}
#section all

	void registerShipyard(Object& region, Object& obj) {
		shipyardList.insertLast(obj);
		calculateShipyards(region);
	}

	void unregisterShipyard(Object& region, Object& obj) {
		shipyardList.remove(obj);
		calculateShipyards(region);
	}

	void regionBuildSupport(Object& obj, uint id, Object& forLeader, const Design@ design) {
		if(shipyardList.length == 0)
			return;
		bool hasCosts = hasDesignCosts(design);
		double laborCost = getLaborCost(design);
		Object@ secondary;
		bool havePrimary = false;
		for(uint i = 0, cnt = shipyardList.length; i < cnt; ++i) {
			Object@ yard = shipyardList[i];
			if(yard.owner !is forLeader.owner)
				continue;
			if(!yard.canBuildSupports)
				continue;
			if(hasCosts && (!yard.hasCargo || yard.cargoTypes == 0))
				continue;
			double laborIncome = yard.laborIncome;
			bool efficient = laborIncome > 0 && (laborCost / laborIncome) < 3.0 * 60.0;
			if(yard.constructingSupport) {
				if(efficient)
					havePrimary = true;
				continue;
			}
			if(!efficient) {
				if(secondary is null)
					@secondary = yard;
				continue;
			}
			yard.buildSupport(id, design, forLeader);
			return;
		}
		if(secondary !is null && !havePrimary) {
			secondary.buildSupport(id, design, forLeader);
			return;
		}
	}

	void requestConstructionOn(Object& onObj, uint constrId) {
		auto@ constr = getConstructionType(constrId);
		if(constr is null)
			return;
		if(shipyardList.length == 0)
			return;

		Targets targs(constr.targets);
		if(targs.length != 0) {
			targs[0].filled = true;
			@targs[0].obj = onObj;
		}

		bool havePrimary = false;
		Object@ primary;
		Object@ secondary;
		for(uint i = 0, cnt = shipyardList.length; i < cnt; ++i) {
			auto@ yard = shipyardList[i];
			if(yard is null || !constr.canBuild(yard, targs))
				continue;
			if(yard.owner !is onObj.owner)
				continue;

			double laborCost = constr.getLaborCost(yard, targs);
			double laborIncome = yard.laborIncome;
			bool efficient = laborIncome > 0 && (laborCost / laborIncome) < 3.0 * 60.0;

			if(efficient) {
				if(yard.constructionCount > 0) {
					havePrimary = true;
					continue;
				}
				@primary = yard;
			}
			else
				@secondary = yard;
		}

		if(primary !is null)
			primary.buildConstruction(constrId, objTarg=onObj);
		else if(secondary !is null && !havePrimary)
			secondary.buildConstruction(constrId, objTarg=onObj);
	}

	void initRegion(Object& obj) {
		//Randomize vision check moment
		PeriodicTime = PeriodicUpdate = double(uint8(obj.id)) / 255.0;

		Region@ region = cast<Region>(obj);
		region.AngleOffset = randomd(0, twopi);

		//Create the plane
		@plane = SystemPlaneNode();
		plane.establish(region);
		plane.hintParentObject(obj, false);

		//Find system
		@system = getSystem(cast<Region>(region));
	}

	double longTimer = 0.0;
	void tickRegion(Object& region, double time) {
		if(system is null) {
			@system = getSystem(cast<Region>(region));
			return;
		}
	
		if(plane !is null && !planeParented) {
			planeParented = true;
			plane.hintParentObject(region, false);
		}

		//Update contested flags
		updateContested(region);

		//Check vision periodically
		if(PeriodicUpdate <= 0.0) {
			//Update total interior vision
			calculateVision(region);
#section server
			//Update neighbouring loyalty
			updateEmpLoyalty(region);
			//Update effects of zealotry
			updateZealotry(region);
			//Update status effects
			updateStatuses(region, PeriodicTime + (-PeriodicUpdate));
			//Update civilian trade
			updateCivilianTrade(region);
			//Area damage
			if(regionDPS > 0.0)
				processDamage(region, PeriodicTime + (-PeriodicUpdate));
			if(starDPS > 0.0) {
				double time = PeriodicTime + (-PeriodicUpdate);
				for(uint i = 0, cnt = starList.length; i < cnt; ++i)
					starList[i].dealStarDamage(time * starDPS);
				starDPS *= pow(0.75, time);
				starDPS -= time;
			}
#section all
			
			PeriodicTime = PeriodicUpdate = randomd(0.9,1.1);
		}
		else {
			PeriodicUpdate -= time;
		}

		longTimer -= time;
		if(longTimer <= 0.0) {
			Region@ reg = cast<Region>(region);
			reg.SiegedMask = 0;
			reg.SiegingMask = 0;
			longTimer = 15.0;
		}

#section server
		//Update region effects
		Region@ reg = cast<Region>(region);
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			if(!effects[i].tick(reg, time)) {
				effects[i].end(reg);
				effects.removeAt(i);
				--i;
				--cnt;
			}
		}

		//Update the combat state
		updateCombatState(reg, time);

#section shadow
		if(prevMask != playerEmpire.visionMask) {
			updatePlane(cast<Region>(region));
			prevMask = playerEmpire.visionMask;
		}
#section all
	}

	double getNeighbourLoyalty(Empire@ emp) {
		if(emp is null || !emp.valid)
			return 0;
		return neighbourLoyalty[emp.index];
	}

	void modNeighbourLoyalty(Object& region, Empire@ emp, double mod) {
		if(emp is null || !emp.valid)
			return;
		neighbourLoyalty[emp.index] += mod;
	}

	double getLocalLoyalty(Empire@ emp) {
		if(emp is null || !emp.valid)
			return 0;
		return localLoyalty[emp.index];
	}

	void modLocalLoyalty(Object& region, Empire@ emp, double mod) {
		if(emp is null || !emp.valid)
			return;
		localLoyalty[emp.index] += mod;
	}

	void updateStatuses(Object& obj, double time) {
		for(int i = regionStatusTypes.length - 1; i >= 0; --i) {
			if(regionStatusTimers[i] >= 0) {
				regionStatusTimers[i] -= time;
				if(regionStatusTimers[i] <= 0) {
					regionStatusTypes.removeAt(i);
					regionStatusTimers.removeAt(i);
					regionStatusEmps.removeAt(i);
				}
			}
		}
	}

	void applyStatuses(Region& reg, Object& obj, bool isOwnerChange = false) {
		for(uint i = 0, cnt = regionStatusTypes.length; i < cnt; ++i) {
			auto@ status = getStatusType(regionStatusTypes[i]);
			Empire@ emp = regionStatusEmps[i];
			if((emp is null && !isOwnerChange) || obj.owner is emp) {
				if(status.shouldApply(emp, reg, obj))
					obj.addStatus(status.id, regionStatusTimers[i], boundEmpire=emp, boundRegion=reg);
			}
		}
	}

	void addRegionStatus(Object& obj, Empire@ emp, uint statusId, double timer = -1.0) {
		auto@ status = getStatusType(statusId);
		if(status is null)
			return;

		Region@ reg = cast<Region>(obj);
		regionStatusTypes.insertLast(statusId);
		regionStatusTimers.insertLast(timer);
		regionStatusEmps.insertLast(emp);

		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			auto@ obj = objectList[i];
			if(emp is null || obj.owner is emp) {
				if(status.shouldApply(emp, reg, obj))
					obj.addStatus(statusId, timer, boundEmpire=emp, boundRegion=reg);
			}
		}
	}

	void removeRegionStatus(Object& obj, Empire@ emp, uint statusId) {
		auto@ status = getStatusType(statusId);
		if(status is null)
			return;

		Region@ reg = cast<Region>(obj);
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			auto@ obj = objectList[i];
			if(emp is null || obj.owner is emp) {
				if(status.shouldApply(emp, reg, obj))
					obj.removeRegionBoundStatus(reg, statusId);
			}
		}

		for(int i = regionStatusTypes.length - 1; i >= 0; --i) {
			if(regionStatusTypes[i] == statusId && regionStatusEmps[i] is emp
					&& regionStatusTimers[i] == -1.0) {
				regionStatusTypes.removeAt(i);
				regionStatusTimers.removeAt(i);
				regionStatusEmps.removeAt(i);
				break;
			}
		}
	}

	void mirrorRegionStatusTo(Region& otherRegion) {
		for(uint i = 0, cnt = regionStatusTypes.length; i < cnt; ++i)
			otherRegion.addRegionStatus(regionStatusEmps[i], regionStatusTypes[i], regionStatusTimers[i]);
	}

	void addSystemDPS(double amount) {
		regionDPS += amount;
	}

	void addStarDPS(double amount) {
		starDPS += amount;
	}

	void dealStarDamage(double amount) {
		for(uint i = 0, cnt = starList.length; i < cnt; ++i)
			starList[i].dealStarDamage(amount);
	}
	
	void processDamage(Object& reg, double time) {
		DamageEvent dmg;
		
		if(regionDPS <= 0.0)
			return;
	
		double baseDamage = regionDPS * time / 100.0;
		
		for(uint i = 0, cnt = time * 15.0; i < cnt; ++i) {
			auto@ obj = trace(line3dd(reg.position, reg.position + random3d(reg.radius * 1.5)));
			if(obj is null)
				continue;
			
			double deal = randomd(0.5,1.5) * baseDamage;
			
			if(obj.isStar) {
				cast<Star>(obj).dealStarDamage(deal);
			}
			else if(obj.isPlanet) {
				cast<Planet>(obj).dealPlanetDamage(deal);
			}
			else {
				@dmg.obj = obj;
				@dmg.target = obj;
				dmg.spillable = false;
				dmg.damage = deal;
				
				vec3d off = obj.position - reg.position;
				vec2d dir = vec2d(off.x, off.z).normalized();
				obj.damage(dmg, -1.0, dir);
			}
		}
		
		uint objCount = objectList.length;
		if(objCount > 0) {
			uint traces = max(min(uint(time * 85.0), objCount * 10), 1);
		
			for(uint i = 0; i < traces; ++i) {
				auto@ obj = objectList[randomi(0,objCount-1)];
				if(obj is null)
					continue;
					
				line3dd line = line3dd(reg.position, obj.position + random3d(5.0));
				line.end = line.start + line.direction * (reg.radius * 1.5);
					
				@obj = trace(line);
				if(obj is null)
					continue;
				
				double deal = randomd(0.5,1.5) * baseDamage;
				
				if(obj.isStar) {
					cast<Star>(obj).dealStarDamage(deal);
				}
				else if(obj.isPlanet) {
					cast<Planet>(obj).dealPlanetDamage(deal);
				}
				else {
					@dmg.obj = obj;
					@dmg.target = obj;
					dmg.spillable = false;
					dmg.damage = deal;
					
					vec3d off = obj.position - reg.position;
					vec2d dir = vec2d(off.x, off.z).normalized();
					obj.damage(dmg, -1.0, dir);
				}
			}
		}
		
		regionDPS *= pow(0.95, time);
		regionDPS -= time;
	}

#section server
	void grantExperience(Empire@ toEmpire, double amount, bool combatOnly = false) {
		array<Object@> objects;
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[i];
			if(!obj.hasLeaderAI || !obj.isShip)
				continue;
			if(obj.owner !is toEmpire)
				continue;
			if(combatOnly && !obj.inCombat)
				continue;
			if(cast<Ship>(obj).getFleetStrength() < 1000.0)
				continue;
			objects.insertLast(obj);
		}
		if(objects.length != 0) {
			amount /= double(objects.length);
			for(uint i = 0, cnt = objects.length; i < cnt; ++i)
				objects[i].addExperience(amount);
		}
	}

	void renameSystem(Object& obj, string name) {
		string oldname = obj.name;
		obj.name = name;
		obj.named = true;
		objectRenamed(ALL_PLAYERS, obj, name);

		for(uint i = 0, cnt = starList.length; i < cnt; ++i) {
			Star@ star = starList[i];
			if(!star.named) {
				star.name = star.name.replaced(oldname, name);
				star.named = true;
				objectRenamed(ALL_PLAYERS, star, star.name);
			}
		}
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			if(!pl.named) {
				pl.name = pl.name.replaced(oldname, name);
				objectRenamed(ALL_PLAYERS, pl, pl.name, setNamed=false);
			}
		}
	}
#section all

	void updateEmpLoyalty(Object& region) {
		uint empCnt = empLoyaltyBonus.length;

		//Calculate new loyalty bonuses
		for(uint i = 0, cnt = empCnt; i < cnt; ++i)
			empLoyaltyBonus[i] = neighbourLoyalty[i] + localLoyalty[i];

		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
			SystemDesc@ desc = getSystem(system.adjacent[i]);
			Region@ other = desc.object;

			for(uint n = 0; n < empCnt; ++n)
				empLoyaltyBonus[n] += other.getNeighbourLoyalty(getEmpire(n));
		}

		//Update planet loyalty bonuses
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			Empire@ owner = pl.owner;
			if(owner !is null && owner.valid)
				pl.setLoyaltyBonus(empLoyaltyBonus[owner.index]);
		}
	}

	uint getContestedState(const Object& region, Empire@ forEmpire) {
		if(forEmpire is null || !forEmpire.valid)
			return CM_None;

		const Region@ reg = cast<const Region>(region);
		if(reg.ContestedMask & forEmpire.mask == 0)
			return CM_None;

		bool usProtected = reg.ProtectedMask & forEmpire.mask != 0;
		bool usZealot = ZealotMask & forEmpire.mask != 0;

		if(reg.SiegedMask & forEmpire.mask != 0) {
			if(usZealot)
				return CM_Zealot;
			return CM_LosingLoyalty;
		}

		bool enemyProtected = false, enemyZealot = false;
		for(uint i = 0, empCnt = getEmpireCount(); i < empCnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(!other.isHostile(forEmpire))
				continue;
			if(planetCounts[i] == 0)
				continue;

			if(reg.SiegingMask & forEmpire.mask != 0) {
				bool zeal = ZealotMask & other.mask != 0;
				if(zeal)
					enemyZealot = true;
			}

			bool prot = reg.ProtectedMask & other.mask != 0;
			if(prot)
				enemyProtected = true;
		}

		if(usProtected || enemyProtected)
			return CM_Protected;
		if(enemyZealot)
			return CM_Zealot;
		if(reg.SiegingMask & forEmpire.mask != 0)
			return CM_GainingLoyalty;
		return CM_Contested;
	}

	void updateCombatState(Region& region, double time) {
		region.CombatMask |= region.EngagedMask;

		combatTimer -= time;
		if(combatTimer <= 0) {
			region.CombatMask = region.EngagedMask;
			region.EngagedMask = 0;
			combatTimer += 20.f;
		}
	}

	void modMilitaryStrength(Empire@ emp, int amt) {
		if(emp is null || !emp.valid)
			return;
		strengths[emp.index] += amt;
	}

	void updateContested(Object& region) {
		int newMilitaryMask = 0;
		int newPlanetsMask = 0;
		for(uint i = 0, cnt = strengths.length; i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(strengths[i] > 0)
				newMilitaryMask |= other.mask;
			if(planetCounts[i] > 0)
				newPlanetsMask |= other.mask;
		}
		HasMilitaryMask = newMilitaryMask;
		HasPlanetsMask = newPlanetsMask;

		uint CMask = 0, OMask = 0;
		uint empCnt = getEmpireCount();
		Region@ reg = cast<Region>(region);
		reg.PlanetsMask = HasPlanetsMask;
		for(uint i = 0; i < empCnt; ++i) {
			// Contested if this empire has planets or military,
			// and an empire hostile to it has military.
			Empire@ other = getEmpire(i);
			int hostile = other.hostileMask;

			bool contested = (planetCounts[i] > 0 || strengths[i] > 0)
				&& (hostile & HasMilitaryMask != 0 || reg.SiegedMask & other.mask != 0);
			if(contested && reg.CombatMask & other.mask != 0 && reg.CombatMask & hostile != 0) {
				int totEnemy = 0;
				for(uint n = 0; n < empCnt; ++n) {
					uint mask = getEmpire(n).mask;
					if(hostile & mask != 0 && reg.CombatMask & mask != 0)
						totEnemy += strengths[n];
				}

				if(totEnemy > 20 || reg.SiegedMask & other.mask != 0) {
					CMask |= other.mask;
					if(isServer && reg.ContestedMask & other.mask == 0 && planetCounts[i] > 0)
						other.notifyWarEvent(region, WET_ContestedSystem);
				}
			}

			//Check if this is a core system
			if(reg.TradeMask & other.mask != 0) {
				bool isCore = true;
				for(uint j = 0, jcnt = system.adjacent.length; j < jcnt; ++j) {
					SystemDesc@ desc = getSystem(system.adjacent[j]);
					if(desc.object.TradeMask & other.mask == 0) {
						isCore = false;
						break;
					}
				}

				if(isCore)
					OMask |= other.mask;
			}
		}

		reg.ContestedMask = CMask;
		reg.CoreSystemMask = OMask;

		//Update whether the node is set as contested
		if(plane !is null) {
			uint newContested = getContestedState(region, playerEmpire);
			if(visibleContested != newContested) {
				plane.setContested(newContested);
				visibleContested = newContested;
			}
		}
	}

	void updateZealotry(Object& obj) {
		//Update zealotry for all empires
		Region@ region = cast<Region>(obj);
		uint isZealotMask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(ZealotMask & emp.mask == 0)
				continue;

			if(planetCounts[i] > 0 && region.SiegedMask & emp.mask != 0) {
				isZealotMask |= emp.mask;

				//Check which zealot effects we need to add
				uint haveEffectMask = 0, needEffectMask = 0;
				for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
					ZealotRegionEffect@ eff = cast<ZealotRegionEffect>(effects[i]);
					if(eff !is null) {
						if(eff.forEmpire is emp)
							haveEffectMask |= eff.other.mask;
					}
				}

				//Check which effects we need
				for(uint j = 0; j < cnt; ++j) {
					Empire@ other = getEmpire(j);
					if(HasMilitaryMask & other.mask == 0)
						continue;
					if(!other.isHostile(emp))
						continue;

					//TODO: This is not 100% accurate. Fix zealot stuff to be fully working.
					if(region.SiegingMask & other.mask != 0) {
						needEffectMask |= other.mask;
						if(haveEffectMask & other.mask == 0)
							addRegionEffect(region, createZealotRegionEffect(emp, other));
					}
				}

				//Check which effects to remove
				for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
					ZealotRegionEffect@ eff = cast<ZealotRegionEffect>(effects[i]);
					if(eff !is null && eff.forEmpire is emp) {
						if(needEffectMask & eff.other.mask == 0) {
							removeRegionEffectByIndex(region, i);
							--i;
							--cnt;
						}
					}
				}
			}
		}

		//Remove all zealotry-related effects
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			ZealotRegionEffect@ eff = cast<ZealotRegionEffect>(effects[i]);
			if(eff !is null) {
				if(isZealotMask & eff.forEmpire.mask == 0) {
					removeRegionEffectByIndex(region, i);
					--i;
					--cnt;
				}
			}
		}
	}

	uint get_planetCount() const {
		return planetBucket.length;
	}

	Planet@ get_planets(uint index) const {
		if(index >= planetBucket.length)
			return null;
		return planetBucket[index];
	}

	uint get_anomalyCount() const {
		return anomalyBucket.length;
	}

	Anomaly@ get_anomalies(uint index) const {
		if(index >= anomalyBucket.length)
			return null;
		return anomalyBucket[index];
	}

	uint get_asteroidCount() const {
		return asteroidBucket.length;
	}

	Asteroid@ get_asteroids(uint index) const {
		if(index >= asteroidBucket.length)
			return null;
		return asteroidBucket[index];
	}

	void castOnRandomAsteroid(Object@ obj, int ablId) {
		if(obj is null)
			return;
		if(asteroidList.length == 0)
			return;
		obj.activateAbility(ablId, asteroidList[randomi(0, asteroidList.length-1)]);
	}

	uint getPlanetCount(Empire@ emp) const {
		if(emp is null || !emp.valid)
			return 0;
		return planetCounts[emp.index];
	}

#section server
	void addStatusRandomPlanet(int statusType, double duration, uint mask) {
		Planet@ pl;
		double tot = 0;

		for(uint i = 0, plCnt = planetList.length; i < plCnt; ++i) {
			Planet@ check = planetList[i];
			Empire@ owner = check.owner;
			if(owner is null || !owner.valid)
				continue;
			if(owner.mask & mask == 0)
				continue;

			tot += 1.0;
			if(randomd() <= 1.0 / tot)
				@pl = check;
		}

		if(pl !is null)
			pl.addStatus(statusType, duration);
	}

	void spawnSupportAtRandomPlanet(Empire@ owner, const Design@ design, bool free = true, Planet@ fallback = null) {
		if(owner is null || design is null || !owner.valid)
			return;

		uint plCnt = planetCounts[owner.index];
		if(plCnt == 0)
			return;
		uint index = randomi(0, plCnt-1);
		Object@ pl;
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ obj = planetList[i];
			if(obj.owner is owner && obj.canGainSupports) {
				if(index == 0) {
					@pl = obj;
					break;
				}
				--index;
			}
		}

		if(pl is null)
			@pl = fallback;
		if(pl !is null) {
			design.decBuilt(); //automatic built doesn't increment
			createShip(pl, design, owner, pl, false, free);
		}
	}
	
	void refreshSupportsFor(Object& dest, bool keepGhosts) {
		auto@ owner = dest.owner;
		if(!owner.valid)
			return;
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			auto@ pl = planetList[i];
			if(pl.owner is owner && pl.SupplyUsed > 0 && pl.allowFillFrom)
				dest.refreshSupportsFrom(pl, keepGhosts);
		}
		for(uint i = 0, cnt = orbitalList.length; i < cnt; ++i) {
			auto@ obj = orbitalList[i];
			if(obj.owner is owner && obj.SupplyUsed > 0 && obj.allowFillFrom)
				dest.refreshSupportsFrom(obj, keepGhosts);
		}
	}

	void convertRandomSupport(Object@ toLeader, Empire@ toEmpire, uint mask, int maxSize) {
		Object@ found;
		double foundCount = 0;

		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[i];
			if(obj is null || !obj.hasLeaderAI)
				continue;
			if(obj.owner.mask & mask == 0)
				continue;

			uint supCnt = obj.supportCount;
			if(supCnt == 0)
				continue;

			foundCount += supCnt;
			if(randomd() < double(supCnt) / foundCount)
				@found = obj;
		}

		if(found !is null)
			found.convertRandomSupport(toLeader, toEmpire, maxSize);
	}

	bool hasTradeStation(Empire@ owner) {
		return HaveStationsMask & owner.mask != 0;
	}

	bool hasTradeStations() {
		return HaveStationsMask != 0;
	}

	void getTradeStation(Civilian@ request, Empire@ owner, vec3d position) {
		if(HaveStationsMask & owner.mask == 0) {
			request.gotoTradeStation(null);
			return;
		}
		Civilian@ best;
		double bestDist = INFINITY;
		for(uint i = 0, cnt = tradeStations.length;  i < cnt; ++i) {
			auto@ station = tradeStations[i];
			if(station.owner !is owner)
				continue;
			double d = position.distanceToSQ(station.position);
			if(d < bestDist) {
				bestDist = d;
				@best = station;
			}
		}
		
		request.gotoTradeStation(best);
	}

	void getTradePlanet(Civilian@ request, Empire@ owner) {
		uint index = randomi(0, planetCounts[owner.index]-1);
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			if(planetList[i].owner is owner) {
				if(index == 0) {
					request.gotoTradePlanet(planetList[i]);
					return;
				}
				--index;
			}
		}
		request.gotoTradePlanet(null);
	}

	void bumpTradeCounter(Empire@ emp) {
		tradeCounter[emp.index] += 1;
	}

	void updateCivilianTrade(Object& region) {
		//Make sure each planet has a civilian ship assigned
		if(config::ENABLE_CIVILIAN_TRADE == 0.0 || config::CIVILIAN_TRADE_MULT == 0.0)
			return;
		uint needRequests = 0;
		int stationLevels = 0;
		for(uint i = 0; i < planetList.length; ++i) {
			Planet@ pl = planetList[i];
			Empire@ owner = pl.owner;
			if(owner is null || !owner.valid)
				continue;
			Civilian@ civ = pl.getAssignedCivilian();
			if(civ !is null)
				continue;
			double timer = pl.getCivilianTimer();
			if(timer < CIV_TIMER / config::CIVILIAN_TRADE_MULT)
				continue;

			//Calculate maximum amount of civilians
			int plCount = owner.TotalPlanets.value;
			int civLimit = 0;
			int plLimit = 100 * config::CIVILIAN_TRADE_MULT;
			if(plCount > plLimit)
				civLimit = plLimit + pow(double(plCount - plLimit), CIVILIAN_LIMIT_POW);
			else
				civLimit = plCount;
			civLimit = double(civLimit) * config::CIVILIAN_TRADE_MULT;

			if(owner.CivilianTradeShips.value < civLimit) {
				Object@ destination = pl.getNativeResourceDestination(owner, 0);
				if(destination is null)
					continue;
				
				@civ = createCivilian(pl.position, owner, type=CiT_Freighter,
						radius = randomCivilianFreighterSize());
				if(civ.radius >= CIV_SIZE_CARAVAN)
					civ.modIncome(+CIV_CARAVAN_INCOME);
				civ.pathTo(destination);
				civ.setOrigin(pl);
				civ.setCargoResource(pl.primaryResourceType);
				pl.setAssignedCivilian(civ);
				pl.setCivilianTimer(0.0);
			}
			else {
				needRequests |= owner.mask;
			}
		}

		if(needRequests != TradeRequestMask) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				if(needRequests & emp.mask != 0) {
					if(TradeRequestMask & emp.mask == 0)
						emp.requestTradeCivilian(cast<Region>(region));
				}
				else {
					if(TradeRequestMask & emp.mask != 0)
						emp.stopRequestTradeCivilian(cast<Region>(region));
				}
			}
			TradeRequestMask = needRequests;
		}

		if(gameTime >= tradeTimer) {
			tradeTimer = gameTime + TRADE_TIMER;

			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				if(!emp.major)
					continue;
				uint buildStations = min(planetCounts[i], uint(double(tradeCounter[i]) / STATION_TRADES));
				uint maxStations = max(buildStations, uint(double(tradeCounter[i] * 2) / STATION_TRADES));

				uint stationCount = 0;
				for(uint i = 0, cnt = tradeStations.length; i < cnt; ++i) {
					Empire@ owner = tradeStations[i].owner;
					if(!tradeStations[i].valid) {
						tradeStations.removeAt(i);
						--i; --cnt;
					}
					else if(owner is emp) {
						stationCount += 1;
					}
				}
				if(stationCount > maxStations) {
					for(uint i = 0, cnt = tradeStations.length; i < cnt && stationCount > maxStations; ++i) {
						if(tradeStations[i].owner is emp) {
							tradeStations[i].destroy();
							stationCount -= 1;
						}
					}
				}
				else if(stationCount < buildStations) {
					for(; stationCount < buildStations; ++stationCount) {
						vec3d pos = system.position;
						vec2d offset = random2d(system.radius * 0.5, system.radius * 0.8);
						pos.x += offset.x;
						pos.z += offset.y;

						Civilian@ civ = createCivilian(pos, emp, CiT_Station,
								radius=randomd(STATION_MIN_RAD, STATION_MAX_RAD));
						civ.modIncome(+CIV_STATION_INCOME);
						civ.setCargoType(CT_Goods);
						tradeStations.insertLast(civ);
					}
				}
				if(stationCount == 0)
					HaveStationsMask &= ~emp.mask;
				else
					HaveStationsMask |= emp.mask;
				tradeCounter[i] = 0;
			}
		}
	}

	void freeUpCivilian(Object& region, Civilian@ civ) {
		//Check which planet here needs a trader the most
		Planet@ bestPlanet;
		Object@ bestDest;
		Empire@ civOwner = civ.owner;
		double bestTimer = 0.0;
		for(uint i = 0; i < planetList.length; ++i) {
			Planet@ pl = planetList[i];
			Empire@ owner = pl.owner;
			if(owner !is civOwner)
				continue;
			Civilian@ civ = pl.getAssignedCivilian();
			if(civ !is null)
				continue;
			Object@ destination = pl.getNativeResourceDestination(owner, 0);
			if(destination is null)
				continue;
			double timer = pl.getCivilianTimer();
			if(timer > bestTimer) {
				@bestPlanet = pl;
				@bestDest = destination;
				bestTimer = timer;
			}
		}

		if(bestPlanet !is null && bestTimer > randomd(0.0, CIV_TIMER / config::CIVILIAN_TRADE_MULT)) {
			//Reroute the trader
			civ.pathTo(bestPlanet, bestDest);
			civ.setCargoResource(bestPlanet.primaryResourceType);
			civ.resetStepCount();
			bestPlanet.setAssignedCivilian(civ);
			bestPlanet.setCivilianTimer(0.0);
		}
		else {
			//Send the trader to a random adjacent system
			SystemDesc@ nextSys;
			int stepCount = civ.getStepCount();
			if(randomd() > pow(0.9, stepCount)) {
				Region@ reqRegion = civOwner.getTradeCivilianRequest(civ.position);
				if(reqRegion !is null)
					@nextSys = getSystem(reqRegion);
				civ.resetStepCount();
				if(nextSys is null && bestPlanet !is null) {
					civ.pathTo(bestPlanet, bestDest);
					civ.setCargoResource(bestPlanet.primaryResourceType);
					bestPlanet.setAssignedCivilian(civ);
					bestPlanet.setCivilianTimer(0.0);
					return;
				}
			}
			if(nextSys is null) {
				uint sysCount = 0;
				for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
					SystemDesc@ other = getSystem(system.adjacent[i]);
					if(other.object.getPlanetCount(civOwner) != 0)
						sysCount += 1;
				}
				for(uint i = 0, cnt = system.wormholes.length; i < cnt; ++i) {
					SystemDesc@ other = getSystem(system.wormholes[i]);
					if(other.object.getPlanetCount(civOwner) != 0)
						sysCount += 1;
				}
				if(sysCount != 0) {
					uint index = randomi(0, sysCount-1);
					for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
						SystemDesc@ other = getSystem(system.adjacent[i]);
						if(other.object.getPlanetCount(civOwner) != 0) {
							if(index == 0) {
								@nextSys = other;
								break;
							}
							else {
								--index;
							}
						}
					}
					if(nextSys is null) {
						for(uint i = 0, cnt = system.wormholes.length; i < cnt; ++i) {
							SystemDesc@ other = getSystem(system.wormholes[i]);
							if(other.object.getPlanetCount(civOwner) != 0) {
								if(index == 0) {
									@nextSys = other;
									break;
								}
								else {
									--index;
								}
							}
						}
					}
				}
			}
			if(nextSys !is null) {
				civ.setCargoType(CT_Goods);
				civ.pathTo(nextSys.object);
				civ.modStepCount(+1);
			}
			else {
				if(bestPlanet is null) {
					civ.destroy();
				}
				else {
					//TODO: Remember the civilian for later
					civ.destroy();
				}
			}
		}
	}
#section all

	uint get_objectCount() const {
		return objectList.length;
	}

	Object@ get_objects(uint index) const {
		if(index >= objectList.length)
			return null;
		return objectList[index];
	}

	Object@ getOrbitObject(vec3d point) const {
		uint cnt = planetList.length;
		for(uint i = 0; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			double d = point.distanceToSQ(pl.position);
			if(d < pl.OrbitSize * pl.OrbitSize)
				return pl;
		}
		return null;
	}

	uint get_starCount() const {
		return starBucket.length;
	}

	Star@ get_stars(uint index) const {
		if(index >= starBucket.length)
			return null;
		return starBucket[index];
	}

	double get_starTemperature() const {
		return StarTemperature;
	}

	double get_starRadius() const {
		return StarRadius;
	}

	void getPlanets() {
		for(uint i = 0, cnt = planetBucket.length; i < cnt; ++i)
			yield(planetBucket[i]);
	}

	void getPickups() {
		for(uint i = 0, cnt = pickupBucket.length; i < cnt; ++i)
			yield(pickupBucket[i]);
	}

	void getAsteroids() {
		for(uint i = 0, cnt = asteroidBucket.length; i < cnt; ++i)
			yield(asteroidBucket[i]);
	}

	void getAnomalies() {
		for(uint i = 0, cnt = anomalyBucket.length; i < cnt; ++i)
			yield(anomalyBucket[i]);
	}

	void getArtifacts() {
		for(uint i = 0, cnt = artifactBucket.length; i < cnt; ++i)
			yield(artifactBucket[i]);
	}

	int getStrength(Empire@ emp) const {
		if(emp is null || !emp.valid)
			return 0;
		return strengths[emp.index];
	}

	Territory@ getTerritory(Empire@ emp) const {
		if(emp is null || !emp.valid)
			return null;
		return territories[emp.index].get();
	}

	bool sharesTerritory(Empire& emp, Region& other) const {
		Territory@ my = getTerritory(emp);
		Territory@ their = other.getTerritory(emp);
		return my !is null && my is their;
	}

	bool isTradableRegion(const Object& obj, Empire& emp) const {
		const Region@ reg = cast<const Region>(obj);
		if(reg.TradeMask & emp.TradeMask.value != 0)
			return true;

		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
			SystemDesc@ desc = getSystem(system.adjacent[i]);
			if(desc.object.TradeMask & emp.TradeMask.value != 0)
				return true;
		}
		return false;
	}

	double getTotalFleetStrength(uint empireMask, bool fleets = true, bool stations = true, bool planets = true) const {
		double str = 0.0;
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[i];
			Empire@ owner = obj.owner;
			if(owner is null || owner.mask & empireMask == 0)
				continue;
			if(!obj.hasLeaderAI)
				continue;

			if(!fleets && obj.isShip && !cast<Ship>(obj).isStation)
				continue;
			if(!stations && obj.isShip && cast<Ship>(obj).isStation)
				continue;
			if(!stations && obj.isOrbital)
				continue;
			if(!planets && obj.isPlanet)
				continue;

			str += sqrt(obj.getFleetStrength());
		}
		return str * str;
	}

	Object@ findEnemy(Empire@ emp, uint empireMask, bool fleets = true, bool stations = true, bool planets = false) const {
		uint offset = randomi(0, objectList.length-1);
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[(i+offset)%cnt];
			Empire@ owner = obj.owner;
			if(owner is null || owner.mask & empireMask == 0)
				continue;

			uint type = obj.type;
			if(emp !is null && !obj.isVisibleTo(emp))
				continue;
			switch(type) {
				case OT_Ship:
					if(!obj.hasLeaderAI)
						continue;
					if(cast<Ship>(obj).isStation) {
						if(!stations)
							continue;
					}
					else {
						if(!fleets)
							continue;
					}
					if(obj.getFleetStrength() < 100.0)
						continue;
				break;
				case OT_Orbital:
					if(!stations)
						continue;
				break;
				case OT_Planet:
					if(!planets)
						continue;
				break;
				default:
					continue;
			}

			return obj;
		}
		return null;
	}

	void getEnemies(Empire@ emp, uint empireMask, bool fleets = true, bool stations = true, bool planets = false) const {
		uint offset = randomi(0, objectList.length-1);
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[(i+offset)%cnt];
			Empire@ owner = obj.owner;
			if(owner is null || owner.mask & empireMask == 0)
				continue;

			uint type = obj.type;
			if(emp !is null && !obj.isVisibleTo(emp))
				continue;
			switch(type) {
				case OT_Ship:
					if(!obj.hasLeaderAI)
						continue;
					if(cast<Ship>(obj).isStation) {
						if(!stations)
							continue;
					}
					else {
						if(!fleets)
							continue;
					}
					if(obj.getFleetStrength() < 100.0)
						continue;
				break;
				case OT_Orbital:
					if(!stations)
						continue;
				break;
				case OT_Planet:
					if(!planets)
						continue;
				break;
				default:
					continue;
			}

			yield(obj);
		}
	}

	void destroyOwnedBy(uint mask, bool ships, bool planets) {
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			Object@ obj = objectList[i];
			Empire@ owner = obj.owner;
			if(owner is null || owner.mask & mask == 0)
				continue;

			if(obj.isShip && ships)
				obj.destroy();
			else if(obj.isPlanet && planets)
				obj.destroy();
		}
	}

	void setTerritory(Empire@ emp, Territory@ terr) {
		if(emp is null || !emp.valid)
			return;
		Territory@ prev = territories[emp.index].get();
		territories[emp.index].set(terr);

		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			pl.changeResourceTerritory(prev, terr);
			pl.changeSurfaceTerritory(prev, terr);
		}

		for(uint i = 0, cnt = resourceHolders.length; i < cnt; ++i) {
			Object@ obj = resourceHolders[i];

			//Planets were already handled before
			if(obj.isPlanet)
				continue;

			obj.changeResourceTerritory(prev, terr);
		}
	}

	void clearTerritory(Empire@ emp, Territory@ old) {
		if(emp is null || !emp.valid)
			return;
		Territory@ prev = territories[emp.index].get();
		if(prev is old)
			territories[emp.index].set(null);
	}

	void regionObjectOwnerChange(Object& thisObj, Object& obj, Empire@ prevOwner, Empire@ newOwner) {
		Region@ region = cast<Region>(thisObj);
		//Change effect owner
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			RegionEffect@ eff = effects[i];
			eff.ownerChange(region, obj, prevOwner, newOwner);
			if(eff.forEmpire is null)
				continue;

			if(prevOwner is eff.forEmpire)
				eff.disable(region, obj);
			else if(newOwner is eff.forEmpire)
				eff.enable(region, obj);
		}

		//Check planet trade
		switch(obj.type) {
			case OT_Planet:
				if(prevOwner !is null && prevOwner.valid) {
					planetCounts[prevOwner.index] -= 1;
				}
				
				if(newOwner !is null && newOwner.valid) {
					planetCounts[newOwner.index] += 1;
					cast<Planet>(obj).setLoyaltyBonus(empLoyaltyBonus[obj.owner.index]);
				}
				else {
					cast<Planet>(obj).setLoyaltyBonus(0);
				}
				calculatePlanets(region);
				break;
			case OT_Ship:
				{
				//Update ship strength
				Ship@ ship = cast<Ship>(obj);
				if(ship.hasLeaderAI) {
					int value = round(ship.blueprint.design.size);
					if(prevOwner !is null && prevOwner.valid)
						strengths[prevOwner.index] -= value;
					if(newOwner !is null && newOwner.valid)
						strengths[newOwner.index] += value;
				}
				calculateShips(region);
				} break;
			case OT_Orbital:
				{
				Orbital@ orbital = cast<Orbital>(obj);
				calculateTradeAccess(region);
				} break;
		}
		
		//Apply statuses
		applyStatuses(region, obj, isOwnerChange=true);

		//Update object counts
		if(prevOwner !is null && prevOwner.valid)
			objectCounts[prevOwner.index] -= 1;
		if(newOwner !is null && newOwner.valid)
			objectCounts[newOwner.index] += 1;

		//Update shipyards
		if(obj.hasConstruction)
			calculateShipyards(region);
	}

	void leaveRegion(Object& thisObj, Object& obj) {
		Region@ region = cast<Region>(thisObj);

		//Remove effects
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			RegionEffect@ eff = effects[i];
			if(eff.forEmpire is null || obj.owner is eff.forEmpire)
				eff.disable(region, obj);
		}

		switch(obj.type)
		{
			case OT_Ship:
			{
				Ship@ ship = cast<Ship>(obj);
				auto@ dsg = ship.blueprint.design;
				if(obj.owner !is null && obj.owner.valid && ship.hasLeaderAI) {
					int value = round(dsg.size);
					strengths[obj.owner.index] -= value;
				}
				calculateShips(region);
			}
			break;
			case OT_Planet:
			{
				Planet@ pl = cast<Planet>(obj);
				planetList.remove(pl);
				planetBucket.remove(pl);
				if(obj.owner !is null && obj.owner.valid)
					planetCounts[obj.owner.index] -= 1;
				calculatePlanets(region);
			}
			break;
			case OT_Star:
			{
				Star@ star = cast<Star>(obj);
				starList.remove(star);
				starBucket.remove(star);
				StarTemperature -= star.temperature;
				if(starList.length != 0)
					StarRadius = starList[0].radius;
				else
					StarRadius = 0;
			}
			break;
			case OT_Orbital:
			{
				Orbital@ orbital = cast<Orbital>(obj);
				orbitalList.remove(orbital);
				calculateTradeAccess(region);
			}
			break;
			case OT_Asteroid:
			{
				Asteroid@ roid = cast<Asteroid>(obj);
				asteroidList.remove(roid);
				asteroidBucket.remove(roid);
			}
			break;
			case OT_Anomaly:
			{
				Anomaly@ anomaly = cast<Anomaly>(obj);
				anomalyList.remove(anomaly);
				anomalyBucket.remove(anomaly);
			}
			break;
			case OT_Pickup:
			{
				Pickup@ pickup = cast<Pickup>(obj);
				pickupList.remove(pickup);
				pickupBucket.remove(pickup);
			}
			break;
			case OT_Artifact:
			{
				Artifact@ artifact = cast<Artifact>(obj);
				artifactList.remove(artifact);
				artifactBucket.remove(artifact);
			}
			break;
		}

		//Handle shipyards
		if(obj.hasConstruction)
			unregisterShipyard(region, obj);

		//Remove from all objects
		if(obj.owner !is null && obj.owner.valid)
			objectCounts[obj.owner.index] -= 1;
		objectList.remove(obj);

		//Remove from component-based lists
		if(obj.hasResources)
			resourceHolders.remove(obj);
	}

	void enterRegion(Object& thisObj, Object& obj) {
		Region@ region = cast<Region>(thisObj);
		switch(obj.type)
		{
			case OT_Ship:
			{
				Ship@ ship = cast<Ship>(obj);
				if(obj.owner !is null && obj.owner.valid && ship.hasLeaderAI) {
					auto@ dsg = ship.blueprint.design;
					if(dsg !is null) {
						int value = round(dsg.size);
						strengths[obj.owner.index] += value;
					}
				}
				calculateShips(region);
			}
			break;
			case OT_Planet:
			{
				Planet@ pl = cast<Planet>(obj);
				planetList.insertLast(pl);
				planetBucket.add(pl);
				if(obj.owner !is null && obj.owner.valid)
					planetCounts[obj.owner.index] += 1;
				calculatePlanets(region);
			}
			break;
			case OT_Star:
			{
				Star@ star = cast<Star>(obj);
				starList.insertLast(star);
				starBucket.add(star);
				StarTemperature += star.temperature;
				if(starList.length != 0)
					StarRadius = starList[0].radius;
				else
					StarRadius = 0;
			}
			break;
			case OT_Orbital:
			{
				Orbital@ orbital = cast<Orbital>(obj);
				orbitalList.insertLast(orbital);
				/*int value = orbital.MilitaryValue;*/
				/*if(obj.owner !is null && obj.owner.valid)*/
				/*	strengths[obj.owner.index] += value;*/
				calculateTradeAccess(region);
			}
			break;
			case OT_Asteroid:
			{
				Asteroid@ roid = cast<Asteroid>(obj);
				asteroidList.insertLast(roid);
				asteroidBucket.add(roid);
			}
			break;
			case OT_Anomaly:
			{
				Anomaly@ anomaly = cast<Anomaly>(obj);
				anomalyList.insertLast(anomaly);
				anomalyBucket.add(anomaly);
			}
			break;
			case OT_Pickup:
			{
				Pickup@ pickup = cast<Pickup>(obj);
				pickupList.insertLast(pickup);
				pickupBucket.add(pickup);
			}
			break;
			case OT_Artifact:
			{
				Artifact@ artifact = cast<Artifact>(obj);
				artifactList.insertLast(artifact);
				artifactBucket.add(artifact);
			}
			break;
		}

		//Add to all objects
		if(obj.owner !is null && obj.owner.valid)
			objectCounts[obj.owner.index] += 1;
		objectList.insertLast(obj);

		//Add to component-based lists
		if(obj.hasResources)
			resourceHolders.insertLast(obj);

		//Apply statuses
		applyStatuses(region, obj);

		//Handle shipyards
		if(obj.hasConstruction)
			registerShipyard(region, obj);

		//Add effects
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			RegionEffect@ eff = effects[i];
			if(eff.forEmpire is null || obj.owner is eff.forEmpire)
				eff.enable(region, obj);
		}
	}

	int addRegionEffect(Object& obj, RegionEffect@ eff) {
		Region@ region = cast<Region>(obj);
		eff.id = nextEffectId++;
		effects.insertLast(eff);

		eff.start(region);
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			if(eff.forEmpire is null || objectList[i].owner is eff.forEmpire)
				eff.enable(region, objectList[i]);
		}

		return eff.id;
	}

	int addRegionEffect(Object& obj, Empire@ forEmpire, uint id) {
		Region@ region = cast<Region>(obj);
		const RegionEffectType@ type = getRegionEffect(id);

		RegionEffect@ eff = type.create();
		@eff.forEmpire = forEmpire;

		return addRegionEffect(obj, eff);
	}

	void addTemporaryVision(Object& obj, Empire@ forEmpire, double timer) {
		addRegionEffect(obj, GrantVision(forEmpire, timer));
	}

	void removeRegionEffect(Object& obj, int id) {
		Region@ region = cast<Region>(obj);
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			RegionEffect@ eff = effects[i];
			if(eff.id != id)
				continue;

			removeRegionEffectByIndex(obj, i);
			break;
		}
	}

	void removeRegionEffectByIndex(Object& obj, uint withIndex) {
		Region@ region = cast<Region>(obj);
		RegionEffect@ eff = effects[withIndex];
		eff.end(region);
		for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
			if(eff.forEmpire is null || objectList[i].owner is eff.forEmpire)
				eff.disable(region, objectList[i]);
		}
		effects.removeAt(withIndex);
	}

	void changeRegionEffectOwner(Object& obj, int id, Empire@ newOwner) {
		Region@ region = cast<Region>(obj);
		for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
			RegionEffect@ eff = effects[i];
			if(eff.id != id)
				continue;

			//Disable for anything that is no longer affected, and enable
			//for everything that is now newly affected
			for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
				if(newOwner !is null && (eff.forEmpire is null || objectList[i].owner is eff.forEmpire))
					eff.disable(region, objectList[i]);
			}

			Empire@ prevOwner = eff.forEmpire;
			@eff.forEmpire = newOwner;
			eff.changeEffectOwner(region, prevOwner, newOwner);

			for(uint i = 0, cnt = objectList.length; i < cnt; ++i) {
				if((newOwner is null && objectList[i].owner !is eff.forEmpire) || objectList[i].owner is newOwner)
					eff.enable(region, objectList[i]);
			}
			break;
		}
	}

	void calculateShips(Object& obj) {
		//Update the vision
		calculateVision(obj);
	}

	void addTradePathing(int toSystem, Object@ from, Object@ to, int resId, uint resource) {
		//Create line node if needed
		if(tradeLines is null) {
			if(system is null)
				return;
			@tradeLines = TradeLinesNode();
			tradeLines.establish(system.index);
		}

		//Find other system index
		int other = -1;
		uint sys = toSystem;
		if(sys != system.index && toSystem != -1) {
			for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
				if(system.adjacent[i] == sys) {
					other = i;
					break;
				}
			}
			if(other == -1)
				return;
		}

		//Add to the node
		tradeLines.addPathing(other, from, to, resId, resource);
	}

	void removeTradePathing(int toSystem, Object@ from, int resId) {
		if(tradeLines is null)
			return;

		//Find other system index
		int other = -1;
		uint sys = toSystem;
		if(sys != system.index && toSystem != -1) {
			for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
				if(system.adjacent[i] == sys) {
					other = i;
					break;
				}
			}
			if(other == -1)
				return;
		}

		//Remove from the node
		tradeLines.removePathing(other, from, resId);
	}

	void calculatePlanets(Object& obj) {
		Region@ region = cast<Region>(obj);

		//Calculate primary empire (most planets)
		Empire@ primary = null;
		int amount = 0;

		uint cnt = planetCounts.length;
		for(uint i = 0; i < cnt; ++i) {
			int value = planetCounts[i];
			if(value > amount) {
				amount = value;
				@primary = getEmpire(i);
			}
		}

		if(primary !is primaryEmpire) {
			@primaryEmpire = primary;

			if(primary is null)
				region.PrimaryEmpire = -1;
			else
				region.PrimaryEmpire = primary.id;

			updatePlane(region);
		}

		calculateVision(obj);
		calculateTradeAccess(obj);
	}

	Empire@ get_visiblePrimaryEmpire(Player& pl, const Object& obj) const {
		const Region@ region = cast<const Region>(obj);
		Empire@ emp = pl.emp;
		if(emp is null)
			return null;

		if(region.VisionMask & emp.visionMask != 0)
			return primaryEmpire;

		if(!emp.valid)
			return null;
		return primaryVision[emp.index];
	}

	void updatePlane(const Region& obj) {
		for(uint i = 0, cnt = primaryVision.length; i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(obj.VisionMask & other.visionMask != 0)
				@primaryVision[i] = primaryEmpire;
		}

		//Inform the nodes
		if(playerEmpire is null || !playerEmpire.valid)
			plane.setPrimaryEmpire(primaryEmpire);
		else
			plane.setPrimaryEmpire(primaryVision[playerEmpire.index]);
	}
	
	void calculateTradeAccess(Object& obj) {
#section server
		Region@ region = cast<Region>(obj);
		
		uint mask = 0;
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			if(pl.owner is null || !pl.owner.valid)
				continue;
			mask |= pl.owner.mask;
		}
		for(uint i = 0, cnt = tradeGrants.length; i < cnt; ++i) {
			if(tradeGrants[i] > 0)
				mask |= getEmpire(i).mask;
		}

		region.TradeMask = mask;
#section all
	}
	
	void grantMemory(Empire@ emp) {
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i)
			planetList[i].giveHistoricMemory(emp);
	}

	void grantVision(Object& obj, Empire@ emp) {
		if(emp !is null && emp.valid) {
			visionGrants[emp.index] += 1;
			calculateVision(obj);
		}
	}

	void revokeVision(Object& obj, Empire@ emp) {
		if(emp !is null && emp.valid) {
			visionGrants[emp.index] -= 1;
			calculateVision(obj);
		}
	}

	void grantTrade(Object& obj, Empire@ emp) {
		if(emp !is null && emp.valid) {
			tradeGrants[emp.index] += 1;
			calculateTradeAccess(obj);
		}
	}

	void revokeTrade(Object& obj, Empire@ emp) {
		if(emp !is null && emp.valid) {
			tradeGrants[emp.index] -= 1;
			calculateTradeAccess(obj);
		}
	}

	void forceSiegeAllPlanets(Empire@ emp, uint mask, uint doMask = ~0) {
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			Empire@ owner = pl.owner;
			if(owner is emp)
				continue;
			if(!pl.valid || owner is null)
				continue;
			if(owner.mask & mask != 0)
				continue;
			if(owner.mask & doMask == 0)
				continue;

			pl.forceSiege(mask);
			if(pl.getLoyaltyFacing(emp) <= 0)
				pl.annex(emp);
		}
	}

	void clearForceSiegeAllPlanets(uint mask) {
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			Planet@ pl = planetList[i];
			pl.clearForceSiege(mask);
		}
	}

	uint prevMask = 0;
	void calculateVision(Object& obj) {
		Region@ region = cast<Region>(obj);

		int prevSeen = region.SeenMask;
		uint avSupMask = 0;
		for(uint i = 0, cnt = planetList.length; i < cnt; ++i) {
			auto@ pl = planetList[i];
			Empire@ owner = pl.owner;
			if(owner is null || !owner.valid)
				continue;
			if(pl.supportCount > 0 && pl.SupplyUsed > pl.SupplySatellite && pl.allowFillFrom)
				avSupMask |= owner.mask;
		}
		for(uint i = 0, cnt = orbitalList.length; i < cnt; ++i) {
			auto@ obj = orbitalList[i];
			Empire@ owner = obj.owner;
			if(owner is null || !owner.valid)
				continue;
			if(obj.supportCount > 0 && obj.allowFillFrom)
				avSupMask |= owner.mask;
		}
		region.AvailSupportMask = avSupMask;

#section server
		uint mask = 0, basicMask = 0;
		for(uint i = 0, cnt = objectCounts.length; i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(objectCounts[i] > 0) {
				basicMask |= emp.mask;
				mask |= emp.mask;
			}
			if(visionGrants[i] > 0) {
				mask |= emp.mask;
			}
		}
		
		for(uint i = 0, cnt = objectCounts.length; i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp.visionMask & mask != 0)
				mask |= emp.mask;
		}

		if(region.VisionMask != mask || prevMask != playerEmpire.visionMask || basicMask != region.BasicVisionMask) {
			region.VisionMask = mask;
			region.MemoryMask |= mask;
			region.SeenMask |= mask;
			updatePlane(region);

			if(system.donateVision)
				region.DonateVisionMask = mask;
			else
				region.DonateVisionMask = 0;

			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				if(!emp.major)
					continue;
				if(basicMask & emp.mask == 0)
					continue;
				uint contact = uint(emp.ContactMask.value);
				if((~contact) & basicMask == 0)
					continue;

				for(uint j = 0; j < cnt; ++j) {
					Empire@ other = getEmpire(j);
					if(!other.major)
						continue;
					if(basicMask & other.mask == 0)
						continue;
					uint prevContact = (emp.ContactMask |= other.mask);
					if(prevContact & other.mask != 0)
						continue;

					bool gainsBonus = config::INFLUENCE_CONTACT_BONUS > 0
						&& (other.ContactMask & ~(emp.mask | other.mask) == 0);
					if(gainsBonus) {
						emp.addInfluence(config::INFLUENCE_CONTACT_BONUS);
						giveAchievement(emp, "ACH_FIRST_SIGHT");
					}
					emp.notifyEmpireMet(obj, other, gainsBonus);
				}
			}

			prevMask = playerEmpire.visionMask;
		}

		region.BasicVisionMask = basicMask;
#section shadow
		if(system !is null)
			region.SeenMask |= region.VisionMask;
#section all

		int newSeen = region.SeenMask;
		if(prevSeen != newSeen && system !is null) {
			region.ExploredMask |= newSeen;
			for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
				auto@ other = getSystem(system.adjacent[i]);
				if(other !is null)
					other.object.ExploredMask |= newSeen;
			}
		}

		for(uint i = 0, cnt = icons.length; i < cnt; ++i)
			icons[i].update(region);
	}

	void updateRegionPlane(const Object& obj) {
		updatePlane(cast<const Region>(obj));
	}

	void calculateShipyards(Object& obj) {
		Region@ region = cast<Region>(obj);

		uint mask = 0;
		for(uint i = 0, cnt = shipyardList.length; i < cnt; ++i)
			mask |= shipyardList[i].owner.mask;
		region.ShipyardMask = mask;
	}

	IconRing@ getIconRing(int level, bool create) {
		IconRing@ ring;
		for(uint i = 0, cnt = icons.length; i < cnt; ++i) {
			if(icons[i].level == level)
				return icons[i];
		}

		if(create) {
			IconRing ring;
			ring.level = level;
			icons.insertLast(ring);
			return ring;
		}

		return null;
	}

	void addStrategicIcon(Object& region, int level, Object& obj, Node& node) {
		IconRing@ ring = getIconRing(level, true);
		ring.add(cast<Region>(region), obj, node);
	}

	void removeStrategicIcon(Object& region, int level, Node& node) {
		IconRing@ ring = getIconRing(level, false);
		if(ring !is null)
			ring.remove(cast<Region>(region), node);
	}
};

tidy class IconRing {
	int level = 0;
	array<Object@> objects;
	array<Node@> nodes;
	array<uint> sortList;

	void update(Region& region) {
		uint cnt = nodes.length;
		if(cnt == 0)
			return;

		double angleStep = (twopi / double(cnt));
		vec3d sysPos = region.position;
		double radius = region.OuterRadius + (800 * level);
		vec3d basePos = objects[0].position;
		double baseAngle = vec2d(basePos.x - sysPos.x, basePos.z - sysPos.z).radians();

		sortList.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			Node@ node = nodes[i];
			vec3d pos = objects[i].position;
			double myAngle = vec2d(pos.x - sysPos.x, pos.z - sysPos.z).radians();
			double diff = angleDiff(myAngle, baseAngle);
			if(diff < 0)
				diff += twopi;

			sortList[i] = uint(diff * 10000.0) << 8 | i;
		}
		sortList.sortAsc();

		uint mask = 0;
		for(uint i = 0; i < cnt; ++i) {
			uint index = sortList[i] & 0x000000ff;
			Node@ node = nodes[index];

			double myAngle = baseAngle + double(i) * angleStep;
			vec3d pos = sysPos + vec3d(cos(myAngle) * radius, 0, sin(myAngle) * radius);
			node.hintParentObject(region, false);

			{
				PlanetIconNode@ icon = cast<PlanetIconNode@>(node);
				if(icon !is null) {
					icon.setStrategic(pos, sysPos);
					continue;
				}
			}

			{
				StrategicIconNode@ icon = cast<StrategicIconNode@>(node);
				if(icon !is null) {
					icon.setStrategic(pos, sysPos);
					continue;
				}
			}
		}
	}

	void add(Region& region, Object@ obj, Node@ node) {
		objects.insertLast(obj);
		nodes.insertLast(node);
		update(region);
	}

	void remove(Region& region, Node@ node) {
		int index = nodes.find(node);
		if(index != -1) {
			nodes.removeAt(index);
			objects.removeAt(index);
		}

		{
			PlanetIconNode@ icon = cast<PlanetIconNode@>(node);
			if(icon !is null)
				icon.clearStrategic();
		}

		{
			StrategicIconNode@ icon = cast<StrategicIconNode@>(node);
			if(icon !is null)
				icon.clearStrategic();
		}

		node.hintParentObject(null, false);
		update(region);
	}
};
