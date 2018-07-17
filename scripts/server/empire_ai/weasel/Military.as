// Military
// --------
// Military construction logic. Builds and restores fleets and defensive stations,
// but does not deal with actually using those fleets to fight - that is the purview of
// the War component.
//

import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Designs;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Development;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Orbitals;

import resources;

class SupportOrder {
	DesignTarget@ design;
	Object@ onObject;
	AllocateBudget@ alloc;
	bool isGhostOrder = false;
	double expires = INFINITY;
	uint count = 0;

	void save(Military& military, SaveFile& file) {
		military.designs.saveDesign(file, design);
		file << onObject;
		military.budget.saveAlloc(file, alloc);
		file << isGhostOrder;
		file << expires;
		file << count;
	}

	void load(Military& military, SaveFile& file) {
		@design = military.designs.loadDesign(file);
		file >> onObject;
		@alloc = military.budget.loadAlloc(file);
		file >> isGhostOrder;
		file >> expires;
		file >> count;
	}

	bool tick(AI& ai, Military& military, double time) {
		if(alloc !is null) {
			if(alloc.allocated) {
				if(isGhostOrder)
					onObject.rebuildAllGhosts();
				else
					onObject.orderSupports(design.active.mostUpdated(), count);
				if(military.log && design !is null)
					ai.print("Support order completed for "+count+"x "+design.active.name+" ("+design.active.size+")", onObject);
				return false;
			}
		}
		else if(design !is null) {
			if(design.active !is null)
				@alloc = military.budget.allocate(BT_Military, getBuildCost(design.active.mostUpdated()) * count);
		}
		if(expires < gameTime) {
			if(alloc !is null && !alloc.allocated)
				military.budget.remove(alloc);
			if(isGhostOrder)
				onObject.clearAllGhosts();
			if(military.log)
				ai.print("Support order expired", onObject);
			return false;
		}
		return true;
	}
};

class StagingBase {
	Region@ region;
	array<FleetAI@> fleets;

	double idleTime = 0.0;
	double occupiedTime = 0.0;

	OrbitalAI@ shipyard;
	BuildOrbital@ shipyardBuild;
	Factory@ factory;

	bool isUnderAttack = false;

	void save(Military& military, SaveFile& file) {
		file << region;
		file << idleTime;
		file << occupiedTime;
		file << isUnderAttack;

		military.orbitals.saveAI(file, shipyard);
		military.construction.saveConstruction(file, shipyardBuild);

		uint cnt = fleets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			military.fleets.saveAI(file, fleets[i]);
	}

	void load(Military& military, SaveFile& file) {
		file >> region;
		file >> idleTime;
		file >> occupiedTime;
		file >> isUnderAttack;

		@shipyard = military.orbitals.loadAI(file);
		@shipyardBuild = cast<BuildOrbital>(military.construction.loadConstruction(file));

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(i > 200 && file < SV_0158) {
				//Something went preeeetty wrong in an old save
				if(file.readBit()) {
					Object@ obj;
					file >> obj;
				}
			}
			else {
				auto@ fleet = military.fleets.loadAI(file);
				if(fleet !is null)
					fleets.insertLast(fleet);
			}
		}
	}

	bool tick(AI& ai, Military& military, double time) {
		if(fleets.length == 0) {
			occupiedTime = 0.0;
			idleTime += time;
		}
		else {
			occupiedTime += time;
			idleTime = 0.0;
		}

		isUnderAttack = region.ContestedMask & ai.mask != 0;

		//Manage building our shipyard
		if(shipyardBuild !is null) {
			if(shipyardBuild.completed) {
				@shipyard = military.orbitals.getInSystem(ai.defs.Shipyard, region);
				if(shipyard !is null)
					@shipyardBuild = null;
			}
		}
		if(shipyard !is null) {
			if(!shipyard.obj.valid) {
				@shipyard = null;
				@shipyardBuild = null;
			}
		}

		if(factory !is null && (!factory.valid || factory.obj.region !is region))
			@factory = null;
		if(factory is null)
			@factory = military.construction.getFactory(region);

		if(factory !is null) {
			factory.needsSupportLabor = false;
			factory.waitingSupportLabor = 0.0;
			if(factory.obj.hasOrderedSupports) {
				factory.needsSupportLabor = true;
				factory.waitingSupportLabor += double(factory.obj.SupplyOrdered) * ai.behavior.estSizeSupportLabor;
			}
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				if(fleets[i].isHome && fleets[i].obj.hasOrderedSupports) {
					factory.needsSupportLabor = true;
					factory.waitingSupportLabor += double(fleets[i].obj.SupplyOrdered) * ai.behavior.estSizeSupportLabor;
					break;
				}
			}
			if(factory.waitingSupportLabor > 0)
				factory.aimForLabor(factory.waitingSupportLabor / ai.behavior.constructionMaxTime);
		}

		bool isFactorySufficient = false;
		if(factory !is null) {
			if(factory.waitingSupportLabor <= factory.laborIncome * ai.behavior.constructionMaxTime
					|| factory.obj.canImportLabor || factory !is military.construction.primaryFactory)
				isFactorySufficient = true;
		}

		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			Object@ obj = fleets[i].obj;
			if(obj is null || !obj.valid) {
				fleets.removeAt(i);
				--i; --cnt;
				continue;
			}
			fleets[i].stationedFactory = isFactorySufficient;
		}

		if(occupiedTime >= 3.0 * 60.0 && ai.defs.Shipyard !is null && shipyard is null && shipyardBuild is null
				&& !isUnderAttack && (!isFactorySufficient && factory !is military.construction.primaryFactory)) {
			//If any fleets need construction try to queue up a shipyard
			bool needYard = false;
			for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
				auto@ flt = fleets[i];
				if(flt.obj.hasOrderedSupports || flt.filled < 0.8) {
					needYard = true;
					break;
				}
			}

			if(needYard) {
				@shipyard = military.orbitals.getInSystem(ai.defs.Shipyard, region);
				if(shipyard is null) {
					vec3d pos = region.position;
					vec2d offset = random2d(region.radius * 0.4, region.radius * 0.8);
					pos.x += offset.x;
					pos.z += offset.y;

					@shipyardBuild = military.construction.buildOrbital(ai.defs.Shipyard, pos);
				}
			}
		}

		if((idleTime >= 10.0 * 60.0 || region.PlanetsMask & ai.mask == 0) && (shipyardBuild is null || shipyard !is null) && (factory is null || (shipyard !is null && factory.obj is shipyard.obj)) && military.stagingBases.length >= 2) {
			if(shipyard !is null) {
				cast<Orbital>(shipyard.obj).scuttle();
			}
			else {
				if(factory !is null) {
					factory.needsSupportLabor = false;
					@factory = null;
				}
				return false;
			}
		}
		return true;
	}
};

class Military : AIComponent {
	Fleets@ fleets;
	Development@ development;
	Designs@ designs;
	Construction@ construction;
	Budget@ budget;
	Systems@ systems;
	Orbitals@ orbitals;

	array<SupportOrder@> supportOrders;
	array<StagingBase@> stagingBases;

	AllocateConstruction@ mainWait;
	bool spentMoney = true;

	void create() {
		@fleets = cast<Fleets>(ai.fleets);
		@development = cast<Development>(ai.development);
		@designs = cast<Designs>(ai.designs);
		@construction = cast<Construction>(ai.construction);
		@budget = cast<Budget>(ai.budget);
		@systems = cast<Systems>(ai.systems);
		@orbitals = cast<Orbitals>(ai.orbitals);
	}

	void save(SaveFile& file) {
		uint cnt = supportOrders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			supportOrders[i].save(this, file);

		construction.saveConstruction(file, mainWait);
		file << spentMoney;

		cnt = stagingBases.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveStaging(file, stagingBases[i]);
			stagingBases[i].save(this, file);
		}
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			SupportOrder ord;
			ord.load(this, file);
			if(ord.onObject !is null)
				supportOrders.insertLast(ord);
		}

		@mainWait = construction.loadConstruction(file);
		file >> spentMoney;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			StagingBase@ base = loadStaging(file);
			if(base !is null) {
				base.load(this, file);
				if(stagingBases.find(base) == -1)
					stagingBases.insertLast(base);
			}
			else {
				StagingBase().load(this, file);
			}
		}
	}

	void loadFinalize(AI& ai) override {
		for(uint i = 0, cnt = stagingBases.length; i < cnt; ++i) {
			auto@ base = stagingBases[i];
			for(uint n = 0, ncnt = base.fleets.length; n < ncnt; ++n) {
				Object@ obj = base.fleets[n].obj;
				if(obj is null || !obj.valid || !obj.initialized) {
					base.fleets.removeAt(n);
					--n; --ncnt;
				}
			}
		}
	}

	StagingBase@ loadStaging(SaveFile& file) {
		Region@ reg;
		file >> reg;

		if(reg is null)
			return null;

		StagingBase@ base = getBase(reg);
		if(base is null) {
			@base = StagingBase();
			@base.region = reg;
			stagingBases.insertLast(base);
		}
		return base;
	}

	void saveStaging(SaveFile& file, StagingBase@ base) {
		Region@ reg;
		if(base !is null)
			@reg = base.region;
		file << reg;
	}

	Region@ getClosestStaging(Region& targetRegion) {
		//Check if we have anything close enough
		StagingBase@ best;
		int minHops = INT_MAX;
		for(uint i = 0, cnt = stagingBases.length; i < cnt; ++i) {
			int d = systems.hopDistance(stagingBases[i].region, targetRegion);
			if(d < minHops) {
				minHops = d;
				@best = stagingBases[i];
			}
		}
		if(best !is null)
			return best.region;
		return null;
	}

	Region@ getStagingFor(Region& targetRegion) {
		//Check if we have anything close enough
		StagingBase@ best;
		int minHops = INT_MAX;
		for(uint i = 0, cnt = stagingBases.length; i < cnt; ++i) {
			int d = systems.hopDistance(stagingBases[i].region, targetRegion);
			if(d < minHops) {
				minHops = d;
				@best = stagingBases[i];
			}
		}
		if(minHops < ai.behavior.stagingMaxHops)
			return best.region;

		//Create a new staging base for this
		Region@ bestNew;
		minHops = INT_MAX;
		for(uint i = 0, cnt = systems.border.length; i < cnt; ++i) {
			auto@ sys = systems.border[i].obj;
			int d = systems.hopDistance(sys, targetRegion);
			if(d < minHops) {
				minHops = d;
				@bestNew = sys;
			}
		}

		if(minHops > ai.behavior.stagingMaxHops && best !is null)
			return best.region;

		auto@ base = getBase(bestNew);
		if(base !is null)
			return base.region;
		else
			return createStaging(bestNew).region;
	}

	StagingBase@ createStaging(Region@ region) {
		if(region is null)
			return null;

		if(log)
			ai.print("Create new staging base.", region);

		StagingBase newBase;
		@newBase.region = region;

		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			if(fleets.fleets[i].stationed is region)
				newBase.fleets.insertLast(fleets.fleets[i]);
		}

		stagingBases.insertLast(newBase);
		return newBase;
	}

	StagingBase@ getBase(Region@ inRegion) {
		if(inRegion is null)
			return null;
		for(uint i = 0, cnt = stagingBases.length; i < cnt; ++i) {
			if(stagingBases[i].region is inRegion)
				return stagingBases[i];
		}
		return null;
	}

	vec3d getStationPosition(Region& inRegion, double distance = 100.0) {
		auto@ base = getBase(inRegion);
		if(base !is null) {
			if(base.shipyard !is null) {
				vec3d pos = base.shipyard.obj.position;
				vec2d offset = random2d(distance * 0.5, distance * 1.5);
				pos.x += offset.x;
				pos.z += offset.y;

				return pos;
			}
		}

		vec3d pos = inRegion.position;
		vec2d offset = random2d(inRegion.radius * 0.4, inRegion.radius * 0.8);
		pos.x += offset.x;
		pos.z += offset.y;
		return pos;
	}

	void stationFleet(FleetAI@ fleet, Region@ inRegion) {
		if(inRegion is null || fleet.stationed is inRegion)
			return;

		auto@ prevBase = getBase(fleet.stationed);
		if(prevBase !is null)
			prevBase.fleets.remove(fleet);

		auto@ base = getBase(inRegion);
		if(base !is null)
			base.fleets.insertLast(fleet);

		@fleet.stationed = inRegion;
		fleet.stationedFactory = construction.getFactory(inRegion) !is null;
		if(fleet.mission is null)
			fleets.returnToBase(fleet);
	}

	void orderSupportsOn(Object& obj, double expire = 60.0) {
		if(obj.SupplyGhost > 0) {
			if(ai.behavior.fleetsRebuildGhosts) {
				//Try to rebuild the fleet's ghosts
				SupportOrder ord;
				@ord.onObject = obj;
				@ord.alloc = budget.allocate(BT_Military, obj.rebuildGhostsCost());
				ord.expires = gameTime + expire;
				ord.isGhostOrder = true;

				supportOrders.insertLast(ord);

				if(log)
					ai.print("Attempting to rebuild ghosts", obj);
				return;
			}
			else {
				obj.clearAllGhosts();
			}
		}

		int supCap = obj.SupplyCapacity;
		int supHave = obj.SupplyUsed - obj.SupplyGhost;

		//Build some supports
		int supSize = pow(2, round(::log(double(supCap) * randomd(0.005, 0.03))/::log(2.0)));
		supSize = max(min(supSize, supCap - supHave), 1);

		SupportOrder ord;
		@ord.onObject = obj;
		@ord.design = designs.design(DP_Support, supSize);
		ord.expires = gameTime + expire;
		ord.count = clamp((supCap - supHave)/supSize, 1, int(ceil((randomd(0.01, 0.1)*supCap)/double(supSize))));

		if(log)
			ai.print("Attempting to build supports: "+ord.count+"x size "+supSize, obj);

		supportOrders.insertLast(ord);
	}

	void findSomethingToDo() {
		//See if we should retrofit anything
		if(mainWait is null && !spentMoney && gameTime > ai.behavior.flagshipBuildMinGameTime) {
			int availMoney = budget.spendable(BT_Military);
			int moneyTargetSize = floor(double(availMoney) * ai.behavior.shipSizePerMoney);

			//See if one of our fleets is old enough that we can retrofit it
			for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
				FleetAI@ fleet = fleets.fleets[i];
				if(fleet.mission !is null && fleet.mission.isActive)
					continue;
				if(fleet.fleetClass != FC_Combat)
					continue;
				if(fleet.obj.hasOrders)
					continue;

				Ship@ ship = cast<Ship>(fleet.obj);
				if(ship is null)
					continue;

				//Don't retrofit free fleets
				if(ship.isFree && !ai.behavior.retrofitFreeFleets)
					continue;

				//Find the factory assigned to this
				Factory@ factory;
				if(fleet.isHome) {
					Region@ reg = fleet.obj.region;
					@factory = construction.getFactory(reg);
				}
				if(factory is null)
					continue;
				if(factory.busy)
					continue;

				//Find how large we can make this flagship
				const Design@ dsg = ship.blueprint.design;
				int targetSize = min(int(moneyTargetSize * 1.2), int(factory.laborToBear(ai) * 1.3 * ai.behavior.shipSizePerLabor));
				targetSize = 5 * floor(double(targetSize) / 5.0);

				//See if we should retrofit this
				int size = ship.blueprint.design.size;
				if(size > targetSize)
					continue;

				double pctDiff = (double(targetSize) / double(size)) - 1.0;
				if(pctDiff < ai.behavior.shipRetrofitThreshold)
					continue;

				DesignTarget@ newDesign = designs.scale(dsg, targetSize);
				spentMoney = true;

				auto@ retrofit = construction.retrofit(ship);
				@mainWait = construction.buildNow(retrofit, factory);

				if(log)
					ai.print("Retrofitting to size "+targetSize, fleet.obj);

				//TODO: This should mark the fleet as occupied for missions while we retrofit

				return;
			}

			//See if we should build a new fleet
			Factory@ factory = construction.primaryFactory;
			if(factory !is null && !factory.busy) {
				//Figure out how large our flagship would be if we built one
				factory.aimForLabor((double(moneyTargetSize) / ai.behavior.shipSizePerLabor) / ai.behavior.constructionMaxTime);
				int targetSize = min(moneyTargetSize, int(factory.laborToBear(ai) * ai.behavior.shipSizePerLabor));
				targetSize = 5 * floor(double(targetSize) / 5.0);

				int expMaint = double(targetSize) * ai.behavior.maintenancePerShipSize;
				int expCost = double(targetSize) / ai.behavior.shipSizePerMoney;
				if(budget.canSpend(BT_Military, expCost, expMaint)) {
					//Make sure we're building an adequately sized flagship
					uint count = 0;
					double avgSize = 0.0;
					for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
						FleetAI@ fleet = fleets.fleets[i];
						Ship@ ship = cast<Ship>(fleet.obj);
						if(ship !is null && fleet.fleetClass == FC_Combat) {
							avgSize += ship.blueprint.design.size;
							count += 1;
						}
					}
					if(count != 0)
						avgSize /= double(count);

					if(count < ai.behavior.maxActiveFleets && targetSize >= avgSize * ai.behavior.flagshipBuildMinAvgSize) {
						//Build the flagship
						DesignTarget@ design = designs.design(DP_Combat, targetSize,
								availMoney, budget.maintainable(BT_Military),
								factory.laborToBear(ai),
								findSize=true);
						@mainWait = construction.buildFlagship(design);
						mainWait.maxTime *= 1.5;
						spentMoney = true;

						if(log)
							ai.print("Ordering a new fleet at size "+targetSize);

						return;
					}
				}
			}
		}

		//See if any of our fleets need refilling
		//TODO: Aim for labor on the factory so that the supports are built in reasonable time
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			FleetAI@ fleet = fleets.fleets[i];
			if(fleet.mission !is null && fleet.mission.isActive)
				continue;
			if(fleet.fleetClass != FC_Combat)
				continue;
			if(fleet.obj.hasOrders)
				continue;
			if(fleet.filled >= 1.0)
				continue;
			if(hasSupportOrderFor(fleet.obj))
				continue;
			if(!fleet.isHome)
				continue;

			//Re-station to our factory if we're idle and need refill without being near a factory
			Factory@ f = construction.getFactory(fleet.obj.region);
			if(f is null) {
				if(fleet.filled < ai.behavior.stagingToFactoryFill && construction.primaryFactory !is null)
					stationFleet(fleet, construction.primaryFactory.obj.region);
				continue;
			}

			//Don't order if the factory has support orders, it'll just make everything take longer
			if(f !is null && ai.behavior.supportOrderWaitOnFactory && fleet.filled < 0.9 && fleet.obj.SupplyGhost == 0) {
				if(f.obj.hasOrderedSupports && f.obj.SupplyUsed < f.obj.SupplyCapacity)
					continue;
			}

			int supCap = fleet.obj.SupplyCapacity;
			int supHave = fleet.obj.SupplyUsed - fleet.obj.SupplyGhost;
			if(supHave < supCap) {
				orderSupportsOn(fleet.obj);
				spentMoney = true;
				return;
			}
		}

		budget.checkedMilitarySpending = spentMoney;

		//TODO: Build defense stations
	}

	bool hasSupportOrderFor(Object& obj) {
		for(uint i = 0, cnt = supportOrders.length; i < cnt; ++i) {
			if(supportOrders[i].onObject is obj)
				return true;
		}
		return false;
	}

	void tick(double time) override {
		//Manage our orders for support ships
		for(uint i = 0, cnt = supportOrders.length; i < cnt; ++i) {
			if(!supportOrders[i].tick(ai, this, time)) {
				supportOrders.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void focusTick(double time) override {
		//Find something for us to do
		findSomethingToDo();

		//If we're far into the budget, spend our money on building supports at our factories
		if(budget.Progress > 0.9 && budget.canSpend(BT_Military, 10)) {
			for(uint i = 0, cnt = construction.factories.length; i < cnt; ++i) {
				//TODO: Build on planets in the system if this is full
				auto@ f = construction.factories[i];
				if(f.obj.SupplyUsed < f.obj.SupplyCapacity && !hasSupportOrderFor(f.obj)) {
					orderSupportsOn(f.obj, expire=budget.RemainingTime);
					break;
				}
			}
		}

		//Check if we should re-station any of our fleets
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if(flAI.stationed is null) {
				Region@ reg = flAI.obj.region;
				if(reg !is null && reg.PlanetsMask & ai.mask != 0)
					stationFleet(flAI, reg);
			}
		}

		//Make sure all our major factories are considered staging bases
		for(uint i = 0, cnt = construction.factories.length; i < cnt; ++i) {
			auto@ f = construction.factories[i];
			if(f.obj.isShip)
				continue;
			Region@ reg = f.obj.region;
			if(reg is null)
				continue;
			auto@ base = getBase(reg);
			if(base is null)
				createStaging(reg);
		}

		//If we don't have any staging bases, make one at a focus
		if(stagingBases.length == 0 && development.focuses.length != 0) {
			Region@ reg = development.focuses[0].obj.region;
			if(reg !is null)
				createStaging(reg);
		}

		//Update our staging bases
		for(uint i = 0, cnt = stagingBases.length; i < cnt; ++i) {
			auto@ base = stagingBases[i];
			if(!base.tick(ai, this, time)) {
				stagingBases.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void turn() override {
		//Fleet construction happens in the beginning of the turn, because we want
		//to use our entire military budget on it.
		if(mainWait !is null) {
			if(mainWait.completed) {
				@mainWait = null;
			}
			else if(!mainWait.started) {
				if(log)
					ai.print("Failed current main construction wait.");
				construction.cancel(mainWait);
				@mainWait = null;
			}
		}
		spentMoney = false;
	}
};

AIComponent@ createMilitary() {
	return Military();
}
