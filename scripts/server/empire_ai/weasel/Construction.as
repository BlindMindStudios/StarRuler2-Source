// Construction
// ------------
// Manages factories and allows build requests for flagships, orbitals, and
// anything else that requires labor.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Orbitals;

import orbitals;
import saving;

import systems;
import regions.regions;

from constructible import ConstructibleType;
from constructions import ConstructionType, getConstructionType;

class AllocateConstruction {
	int id = -1;
	uint moneyType = BT_Development;
	Factory@ tryFactory;
	double maxTime = INFINITY;
	bool completed = false;
	bool started = false;
	double completedAt = 0;
	AllocateBudget@ alloc;
	int cost = 0;
	int maintenance = 0;
	double priority = 1.0;

	AllocateConstruction() {
	}

	void _save(Construction& construction, SaveFile& file) {
		file << moneyType;
		construction.saveFactory(file, tryFactory);
		file << maxTime;
		file << completed;
		file << started;
		file << completedAt;
		construction.budget.saveAlloc(file, alloc);
		file << cost;
		file << maintenance;
		file << priority;
		save(construction, file);
	}

	void save(Construction& construction, SaveFile& file) {
	}

	void _load(Construction& construction, SaveFile& file) {
		file >> moneyType;
		@tryFactory = construction.loadFactory(file);
		file >> maxTime;
		file >> completed;
		file >> started;
		file >> completedAt;
		@alloc = construction.budget.loadAlloc(file);
		file >> cost;
		file >> maintenance;
		file >> priority;
		load(construction, file);
	}

	void load(Construction& construction, SaveFile& file) {
	}

	bool tick(AI& ai, Construction& construction, double time) {
		if(tryFactory !is null && alloc.allocated) {
			construction.start(tryFactory, this);
			return false;
		}
		return true;
	}

	void update(AI& ai, Factory@ f) {
		@alloc = cast<Budget>(ai.budget).allocate(moneyType, cost, maintenance, priority);
	}

	double laborCost(AI& ai, Object@ obj) {
		return 0.0;
	}

	bool canBuild(AI& ai, Factory@ f) {
		return true;
	}

	void construct(AI& ai, Factory@ f) {
		started = true;
	}

	string toString() {
		return "construction";
	}
};

class BuildFlagship : AllocateConstruction {
	double baseLabor = 0.0;
	const Design@ design;
	DesignTarget@ target;

	BuildFlagship() {
	}

	BuildFlagship(const Design@ dsg) {
		set(dsg);
	}

	BuildFlagship(DesignTarget@ target) {
		@this.target = target;
	}

	void save(Construction& construction, SaveFile& file) {
		file << baseLabor;
		if(design !is null) {
			file.write1();
			file << design;
		}
		else {
			file.write0();
		}
		construction.designs.saveDesign(file, target);
	}

	void load(Construction& construction, SaveFile& file) {
		file >> baseLabor;
		if(file.readBit())
			file >> design;
		@target = construction.designs.loadDesign(file);
	}

	void set(const Design& dsg) {
		@design = dsg.mostUpdated();
		baseLabor = design.total(HV_LaborCost);
	}

	double laborCost(AI& ai, Object@ obj) {
		return baseLabor;
	}

	bool tick(AI& ai, Construction& construction, double time) override {
		if(target !is null) {
			if(target.active !is null) {
				set(target.active);
				@target = null;
			}
		}
		return AllocateConstruction::tick(ai, construction, time);
	}

	bool canBuild(AI& ai, Factory@ f) override {
		if(!f.obj.canBuildShips)
			return false;
		return design !is null;
	}

	void update(AI& ai, Factory@ f) {
		double c = design.total(HV_BuildCost);
		c *= double(f.obj.shipBuildCost) / 100.0;
		c *= f.obj.constructionCostMod;

		cost = ceil(c);
		maintenance = ceil(design.total(HV_MaintainCost));

		AllocateConstruction::update(ai, f);
	}

	void construct(AI& ai, Factory@ f) {
		f.obj.buildFlagship(design);
		AllocateConstruction::construct(ai, f);
	}

	string toString() {
		if(design is null)
			return "flagship (design in progress)";
		return "flagship "+design.name;
	}
};

class BuildFlagshipSourced : BuildFlagship {
	Object@ buildAt;
	Object@ buildFrom;

	BuildFlagshipSourced() {
	}

	BuildFlagshipSourced(const Design@ dsg) {
		set(dsg);
	}

	BuildFlagshipSourced(DesignTarget@ target) {
		@this.target = target;
	}

	void save(Construction& construction, SaveFile& file) override {
		BuildFlagship::save(construction, file);
		file << buildAt;
		file << buildFrom;
	}

	void load(Construction& construction, SaveFile& file) override {
		BuildFlagship::load(construction, file);
		file >> buildAt;
		file >> buildFrom;
	}

	bool canBuild(AI& ai, Factory@ f) override {
		if(buildAt !is null && f.obj !is buildAt)
			return false;
		return BuildFlagship::canBuild(ai, f);
	}

	void construct(AI& ai, Factory@ f) override {
		f.obj.buildFlagship(design, constructFrom=buildFrom);
		AllocateConstruction::construct(ai, f);
	}
};

class BuildStation : AllocateConstruction {
	double baseLabor = 0.0;
	const Design@ design;
	DesignTarget@ target;
	vec3d position;
	bool local = false;

	BuildStation() {
	}

	BuildStation(const Design@ dsg, const vec3d& position) {
		this.position = position;
		set(dsg);
	}

	BuildStation(DesignTarget@ target, const vec3d& position) {
		this.position = position;
		@this.target = target;
	}

	BuildStation(const Design@ dsg, bool local) {
		this.local = true;
		set(dsg);
	}

	BuildStation(DesignTarget@ target, bool local) {
		@this.target = target;
		this.local = true;
	}

	void save(Construction& construction, SaveFile& file) {
		file << baseLabor;
		file << position;
		file << local;
		if(design !is null) {
			file.write1();
			file << design;
		}
		else {
			file.write0();
		}
		construction.designs.saveDesign(file, target);
	}

	void load(Construction& construction, SaveFile& file) {
		file >> baseLabor;
		file >> position;
		file >> local;
		if(file.readBit())
			file >> design;
		@target = construction.designs.loadDesign(file);
	}

	void set(const Design& dsg) {
		@design = dsg.mostUpdated();
		baseLabor = design.total(HV_LaborCost);
	}

	double laborCost(AI& ai, Object@ obj) {
		double labor = baseLabor;

		labor *= obj.owner.OrbitalLaborCostFactor;

		if(!local) {
			Region@ reg = getRegion(position);
			Region@ targReg = obj.region;
			if(reg !is null && targReg !is null) {
				int hops = cast<Systems>(ai.systems).tradeDistance(targReg, reg);
				if(hops > 0) {
					double penalty = 1.0 + config::ORBITAL_LABOR_COST_STEP * double(hops);
					baseLabor *= penalty;
				}
			}
		}
		return labor;
	}

	bool tick(AI& ai, Construction& construction, double time) override {
		if(target !is null) {
			if(target.active !is null) {
				set(target.active);
				@target = null;
			}
		}
		return AllocateConstruction::tick(ai, construction, time);
	}

	bool canBuild(AI& ai, Factory@ f) override {
		if(design is null)
			return false;
		if(!f.obj.canBuildOrbitals)
			return false;
		Region@ targReg = f.obj.region;
		if(targReg is null)
			return false;
		if(!local) {
			Region@ reg = getRegion(position);
			if(reg is null)
				return false;
			if(!cast<Systems>(ai.systems).canTrade(targReg, reg))
				return false;
		}
		return true;
	}

	void update(AI& ai, Factory@ f) {
		double c = design.total(HV_BuildCost);
		c *= f.obj.owner.OrbitalBuildCostFactor;
		c *= f.obj.constructionCostMod;

		cost = ceil(c);
		maintenance = ceil(design.total(HV_MaintainCost));

		AllocateConstruction::update(ai, f);
	}

	void construct(AI& ai, Factory@ f) {
		if(local) {
			position = f.obj.position;
			vec2d offset = random2d(f.obj.radius + 10.0, f.obj.radius + 100.0);
			position.x += offset.x;
			position.z += offset.y;
		}
		f.obj.buildStation(design, position);
		AllocateConstruction::construct(ai, f);
	}

	string toString() {
		if(design is null)
			return "station (design in progress)";
		return "station "+design.name;
	}
};

class BuildOrbital : AllocateConstruction {
	double baseLabor = 0.0;
	const OrbitalModule@ module;
	bool local = false;
	vec3d position;

	BuildOrbital() {
	}

	BuildOrbital(const OrbitalModule@ module, const vec3d& position) {
		this.position = position;
		@this.module = module;
		baseLabor = module.laborCost;
	}

	BuildOrbital(const OrbitalModule@ module, bool local) {
		this.local = true;
		@this.module = module;
		baseLabor = module.laborCost;
	}

	void save(Construction& construction, SaveFile& file) {
		file << baseLabor;
		file << position;
		file << local;
		file.writeIdentifier(SI_Orbital, module.id);
	}

	void load(Construction& construction, SaveFile& file) {
		file >> baseLabor;
		file >> position;
		file >> local;
		@module = getOrbitalModule(file.readIdentifier(SI_Orbital));
	}

	double laborCost(AI& ai, Object@ obj) {
		double labor = baseLabor;

		labor *= obj.owner.OrbitalLaborCostFactor;

		if(!local) {
			Region@ reg = getRegion(position);
			Region@ targReg = obj.region;
			if(reg !is null && targReg !is null) {
				int hops = cast<Systems>(ai.systems).tradeDistance(targReg, reg);
				if(hops > 0) {
					double penalty = 1.0 + config::ORBITAL_LABOR_COST_STEP * double(hops);
					baseLabor *= penalty;
				}
			}
		}
		return labor;
	}

	bool tick(AI& ai, Construction& construction, double time) override {
		return AllocateConstruction::tick(ai, construction, time);
	}

	bool canBuild(AI& ai, Factory@ f) override {
		if(module is null)
			return false;
		if(!f.obj.canBuildOrbitals)
			return false;
		Region@ targReg = f.obj.region;
		if(targReg is null)
			return false;
		if(!local) {
			Region@ reg = getRegion(position);
			if(reg is null)
				return false;
			if(!cast<Systems>(ai.systems).canTrade(targReg, reg))
				return false;
		}
		return true;
	}

	void update(AI& ai, Factory@ f) {
		double c = module.buildCost;
		c *= f.obj.owner.OrbitalBuildCostFactor;
		c *= f.obj.constructionCostMod;

		cost = ceil(c);
		maintenance = module.maintenance;

		AllocateConstruction::update(ai, f);
	}

	void construct(AI& ai, Factory@ f) {
		if(local) {
			position = f.obj.position;
			vec2d offset = random2d(f.obj.radius + 10.0, f.obj.radius + 100.0);
			position.x += offset.x;
			position.z += offset.y;
		}
		f.obj.buildOrbital(module.id, position);
		AllocateConstruction::construct(ai, f);
	}

	string toString() {
		return "orbital "+module.name;
	}
};

class RetrofitShip : AllocateConstruction {
	Ship@ ship;
	double labor;

	RetrofitShip() {
	}

	RetrofitShip(Ship@ ship) {
		@this.ship = ship;
		labor = ship.getRetrofitLabor();
		cost = ship.getRetrofitCost();
	}

	void save(Construction& construction, SaveFile& file) {
		file << ship;
		file << labor;
	}

	void load(Construction& construction, SaveFile& file) {
		file >> ship;
		file >> labor;
	}

	double laborCost(AI& ai, Object@ obj) {
		return labor;
	}

	bool canBuild(AI& ai, Factory@ f) override {
		if(!f.obj.canBuildShips)
			return false;
		Region@ reg = ship.region;
		return reg !is null && reg is f.obj.region;
	}

	void construct(AI& ai, Factory@ f) {
		ship.retrofitFleetAt(f.obj);
		AllocateConstruction::construct(ai, f);
	}

	string toString() {
		return "retrofit "+ship.name;
	}
};

class BuildConstruction : AllocateConstruction {
	const ConstructionType@ consType;

	BuildConstruction() {
	}

	BuildConstruction(const ConstructionType@ consType) {
		@this.consType = consType;
	}

	void save(Construction& construction, SaveFile& file) {
		file.writeIdentifier(SI_ConstructionType, consType.id);
	}

	void load(Construction& construction, SaveFile& file) {
		@consType = getConstructionType(file.readIdentifier(SI_ConstructionType));
	}

	double laborCost(AI& ai, Object@ obj) {
		if(obj is null)
			return consType.laborCost;
		return consType.getLaborCost(obj);
	}

	bool canBuild(AI& ai, Factory@ f) override {
		return consType.canBuild(f.obj, ignoreCost=true);
	}

	void update(AI& ai, Factory@ f) {
		cost = consType.getBuildCost(f.obj);
		maintenance = consType.getMaintainCost(f.obj);

		AllocateConstruction::update(ai, f);
	}

	void construct(AI& ai, Factory@ f) {
		f.obj.buildConstruction(consType.id);
		AllocateConstruction::construct(ai, f);
	}

	string toString() {
		return "construction "+consType.name;
	}
};

class Factory {
	Object@ obj;
	PlanetAI@ plAI;

	Factory@ exportingTo;

	AllocateConstruction@ active;
	double laborAim = 0.0;
	double laborIncome = 0.0;

	double idleSince = 0.0;
	double storedLabor = 0.0;
	double laborMaxStorage = 0.0;
	double buildingPenalty = 0.0;

	bool needsSupportLabor = false;
	double waitingSupportLabor = 0.0;
	uint curConstructionType = 0;
	bool valid = true;
	bool significantLabor = true;

	uint backgrounded = 0;
	Asteroid@ bgAsteroid;

	BuildingRequest@ curBuilding;
	ImportData@ curImport;

	void save(Construction& construction, SaveFile& file) {
		construction.planets.saveAI(file, plAI);
		construction.saveConstruction(file, active);
		file << laborAim;
		file << laborIncome;
		file << idleSince;
		file << storedLabor;
		file << laborMaxStorage;
		file << buildingPenalty;
		construction.planets.saveBuildingRequest(file, curBuilding);
		construction.resources.saveImport(file, curImport);
		file << backgrounded;
		file << bgAsteroid;
		file << curConstructionType;
		file << valid;
		file << needsSupportLabor;
		file << waitingSupportLabor;
		construction.saveFactory(file, exportingTo);
	}

	void load(Construction& construction, SaveFile& file) {
		@plAI = construction.planets.loadAI(file);
		@active = construction.loadConstruction(file);
		file >> laborAim;
		file >> laborIncome;
		file >> idleSince;
		file >> storedLabor;
		file >> laborMaxStorage;
		file >> buildingPenalty;
		@curBuilding = construction.planets.loadBuildingRequest(file);
		@curImport = construction.resources.loadImport(file);
		file >> backgrounded;
		file >> bgAsteroid;
		file >> curConstructionType;
		file >> valid;
		file >> needsSupportLabor;
		file >> waitingSupportLabor;
		@exportingTo = construction.loadFactory(file);
	}

	bool get_busy() {
		return active !is null;
	}

	bool get_needsLabor() {
		if(!valid)
			return false;
		if(obj.hasOrderedSupports)
			return true;
		if(active !is null)
			return true;
		if(needsSupportLabor)
			return true;
		if(obj.constructionCount > 0 && curConstructionType != CT_Export)
			return true;
		return false;
	}

	double laborToBear(AI& ai) {
		return laborIncome * ai.behavior.constructionMaxTime + storedLabor;
	}

	bool viable(AI& ai, AllocateConstruction@ alloc) {
		double labor = obj.laborIncome;
		double estTime = (alloc.laborCost(ai, obj) - storedLabor) / labor;
		if(estTime > alloc.maxTime)
			return false;
		return true;
	}

	bool tick(AI& ai, Construction& construction, double time) {
		if(obj is null || !obj.valid || obj.owner !is ai.empire) {
			valid = false;
			return false;
		}

		uint curCount = obj.constructionCount;
		curConstructionType = 0;
		bool isBackground = false;
		if(curCount != 0) {
			curConstructionType = obj.constructionType;
			isBackground = curConstructionType == CT_Asteroid || curConstructionType == CT_Export;
		}
		if(active !is null) {
			if(curCount <= backgrounded || (curCount == 1 && isBackground)) {
				if(construction.log)
					ai.print("Completed construction of "+active.toString()+" "+backgrounded+" / "+curCount, obj);
				active.completed = true;
				active.completedAt = gameTime;
				@active = null;
				idleSince = gameTime;
				backgrounded = 0;
			}
		}
		else {
			if(curCount < backgrounded) {
				backgrounded = curCount;
			}
		}

		//Background constructibles we don't need to do right now
		if(curCount > 1 && curConstructionType == CT_Asteroid && bgAsteroid !is null) {
			obj.moveConstruction(obj.constructionID[0], -1);
			backgrounded += 1;
		}
		if(curCount > 1 && curConstructionType == CT_Export && exportingTo !is null) {
			obj.cancelConstruction(obj.constructionID[0]);
			@exportingTo = null;
		}
		if(bgAsteroid !is null && (bgAsteroid.owner.valid || curCount == 0)) {
			if(bgAsteroid.owner is ai.empire)
				construction.planets.register(bgAsteroid);
			@bgAsteroid = null;
		}

		//Build warehouse(s) if we've been idle
		laborIncome = obj.laborIncome;
		storedLabor = obj.currentLaborStored;
		laborMaxStorage = obj.laborStorageCapacity;
		significantLabor = laborIncome >= 0.4 * construction.bestLabor && obj.baseLaborIncome > 4.0/60.0;
		if(storedLabor < laborMaxStorage)
			idleSince = gameTime;
		if(active is null && curBuilding is null && plAI !is null && gameTime - idleSince > ai.behavior.laborStoreIdleTimer && ai.behavior.buildLaborStorage && (laborMaxStorage+50) < ai.behavior.laborStoreMaxFillTime * max(obj.baseLaborIncome, laborAim) && significantLabor) {
			auto@ bld = ai.defs.LaborStorage;
			if(bld !is null && buildingPenalty < gameTime) {
				if(construction.log)
					ai.print("Build building "+bld.name+" for labor storage", obj);

				@curBuilding = construction.planets.requestBuilding(plAI, bld);
			}
		}

		//Remove waits on completed labor gains
		if(curBuilding !is null) {
			if(curBuilding.canceled || (curBuilding.built && curBuilding.getProgress() >= 1.0)) {
				if(construction.log)
					ai.print("Building construction for labor finished", obj);
				if(curBuilding.canceled)
					buildingPenalty = gameTime + 60.0;
				@curBuilding = null;
			}
		}
		if(curImport !is null) {
			if(curImport.beingMet) {
				if(construction.log)
					ai.print("Resource import for labor finished", obj);
				@curImport = null;
			}
		}

		//See if we need a new labor gain
		if(laborIncome < laborAim) {
			if(curImport is null && plAI !is null && obj.isPressureSaturated(TR_Labor) && obj.pressureCap < uint(obj.totalPressure) && gameTime > 6.0 * 60.0 && ai.behavior.buildFactoryForLabor) {
				ResourceSpec spec;
				spec.type = RST_Pressure_Level0;
				spec.pressureType = TR_Labor;

				if(construction.log)
					ai.print("Queue resource import for labor", obj);

				@curImport = construction.resources.requestResource(obj, spec, prioritize=true);
			}
			if(curBuilding is null && plAI !is null && ai.behavior.buildLaborStorage) {
				auto@ bld = ai.defs.Factory;
				if(bld !is null && buildingPenalty < gameTime) {
					if(construction.log)
						ai.print("Build building "+bld.name+" for labor", obj);

					@curBuilding = construction.planets.requestBuilding(plAI, bld);
				}
			}
		}

		//See if we should spend our labor on a labor export somewhere else
		if(exportingTo !is null && curConstructionType == CT_Export) {
			if(!exportingTo.valid || (!exportingTo.needsLabor && exportingTo !is construction.primaryFactory)) {
				obj.cancelConstruction(obj.constructionID[0]);
				@exportingTo = null;
			}
		}
		if(ai.behavior.distributeLaborExports) {
			if(curCount == 0 && obj.canExportLabor) {
				uint offset = randomi(0, construction.factories.length-1);
				for(uint i = 0, cnt = construction.factories.length; i < cnt; ++i) {
					auto@ other = construction.factories[(i+offset) % cnt];
					if(other is this)
						continue;
					if(!other.obj.canImportLabor)
						continue;

					//Check if this is currently busy
					if(other !is construction.primaryFactory) {
						if(!other.needsLabor)
							continue;
					}

					obj.exportLaborTo(other.obj);
					@exportingTo = other;
				}
			}
		}

		//See if we should spend our labor trying to build an asteroid
		if(ai.behavior.backgroundBuildAsteroids) {
			if((curCount == 0 || (curConstructionType == CT_Export && curCount == 1)) && storedLabor >= laborMaxStorage * 0.5 && obj.canBuildAsteroids) {
				Asteroid@ roid = construction.getBackgroundAsteroid(this);
				if(roid !is null) {
					uint resCount = roid.getAvailableCount();
					if(resCount != 0) {
						uint bestIndex = 0;
						int bestId = -1;
						double bestWeight = 0.0;

						if(ai.behavior.chooseAsteroidResource) {
							for(uint i = 0; i < resCount; ++i) {
								int resourceId = roid.getAvailable(i);
								double w = asteroidResourceValue(getResource(resourceId));
								if(w > bestWeight) {
									bestWeight = w;
									bestId = resourceId;
									bestIndex = i;
								}
							}
						}
						else {
							bestIndex = randomi(0, resCount-1);
							bestId = roid.getAvailable(bestIndex);
						}

						double laborCost = roid.getAvailableCost(bestIndex);

						Region@ fromReg = obj.region;
						Region@ toReg = roid.region;
						if(fromReg !is null && toReg !is null)
							laborCost *= 1.0 + config::ASTEROID_COST_STEP * double(construction.systems.hopDistance(fromReg, toReg));

						double timeTaken = laborIncome / laborCost;
						if(timeTaken < ai.behavior.constructionMaxTime || storedLabor >= laborMaxStorage * 0.95) {
							@bgAsteroid = roid;
							obj.buildAsteroid(roid, bestId);

							if(construction.log)
								ai.print("Use background labor to mine "+roid.name+" in "+roid.region.name, obj);
						}
					}
				}
			}
		}

		return true;
	}

	void aimForLabor(double labor) {
		if(labor > laborAim)
			laborAim = labor;
	}
};

class Construction : AIComponent {
	array<Factory@> factories;
	Factory@ primaryFactory;
	double noFactoryTimer = 0.0;

	int nextAllocId = 0;
	array<AllocateConstruction@> allocations;

	double totalLabor = 0.0;
	double bestLabor = 0.0;

	BuildOrbital@ buildConsolidate;

	Budget@ budget;
	Planets@ planets;
	Orbitals@ orbitals;
	Resources@ resources;
	Designs@ designs;
	Systems@ systems;

	void create() {
		@budget = cast<Budget>(ai.budget);
		@planets = cast<Planets>(ai.planets);
		@resources = cast<Resources>(ai.resources);
		@designs = cast<Designs>(ai.designs);
		@systems = cast<Systems>(ai.systems);
		@orbitals = cast<Orbitals>(ai.orbitals);
	}

	void save(SaveFile& file) {
		file << nextAllocId;

		uint cnt = allocations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			saveConstruction(file, allocations[i]);

		cnt = factories.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveFactory(file, factories[i]);
			factories[i].save(this, file);
		}

		saveFactory(file, primaryFactory);
		file << noFactoryTimer;

		saveConstruction(file, buildConsolidate);
	}

	void load(SaveFile& file) {
		file >> nextAllocId;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ alloc = loadConstruction(file);
			if(alloc !is null)
				allocations.insertLast(alloc);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Factory@ f = loadFactory(file);
			if(f !is null)
				f.load(this, file);
			else
				Factory().load(this, file);
		}

		@primaryFactory = loadFactory(file);
		file >> noFactoryTimer;

		@buildConsolidate = cast<BuildOrbital>(loadConstruction(file));
	}

	void saveFactory(SaveFile& file, Factory@ f) {
		if(f !is null) {
			file.write1();
			file << f.obj;
		}
		else {
			file.write0();
		}
	}

	Factory@ loadFactory(SaveFile& file) {
		if(!file.readBit())
			return null;

		Object@ obj;
		file >> obj;

		if(obj is null)
			return null;

		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].obj is obj)
				return factories[i];
		}

		Factory f;
		@f.obj = obj;
		factories.insertLast(f);
		return f;
	}

	array<AllocateConstruction@> savedConstructions;
	array<AllocateConstruction@> loadedConstructions;
	void postSave(AI& ai) {
		savedConstructions.length = 0;
	}
	void postLoad(AI& ai) {
		loadedConstructions.length = 0;
	}

	void saveConstruction(SaveFile& file, AllocateConstruction@ alloc) {
		if(alloc is null) {
			file.write0();
			return;
		}

		file.write1();
		file << alloc.id;
		if(alloc.id == -1) {
			storeConstruction(file, alloc);
		}
		else {
			bool found = false;
			for(uint i = 0, cnt = savedConstructions.length; i < cnt; ++i) {
				if(savedConstructions[i] is alloc) {
					found = true;
					break;
				}
			}

			if(!found) {
				storeConstruction(file, alloc);
				savedConstructions.insertLast(alloc);
			}
		}
	}

	AllocateConstruction@ loadConstruction(SaveFile& file) {
		if(!file.readBit())
			return null;

		int id = 0;
		file >> id;
		if(id == -1) {
			AllocateConstruction@ alloc = createConstruction(file);
			alloc.id = id;
			return alloc;
		}
		else {
			for(uint i = 0, cnt = loadedConstructions.length; i < cnt; ++i) {
				if(loadedConstructions[i].id == id)
					return loadedConstructions[i];
			}

			AllocateConstruction@ alloc = createConstruction(file);
			alloc.id = id;
			loadedConstructions.insertLast(alloc);
			return alloc;
		}
	}

	void storeConstruction(SaveFile& file, AllocateConstruction@ alloc) {
		auto@ cls = getClass(alloc);
		auto@ mod = cls.module;

		file << mod.name;
		file << cls.name;
		alloc._save(this, file);
	}

	AllocateConstruction@ createConstruction(SaveFile& file) {
		string modName;
		string clsName;

		file >> modName;
		file >> clsName;

		auto@ mod = getScriptModule(modName);
		if(mod is null) {
			error("ERROR: AI Load could not find module for alloc "+modName+"::"+clsName);
			return null;
		}

		auto@ cls = mod.getClass(clsName);
		if(cls is null) {
			error("ERROR: AI Load could not find class for alloc "+modName+"::"+clsName);
			return null;
		}

		auto@ alloc = cast<AllocateConstruction>(cls.create());
		if(alloc is null) {
			error("ERROR: AI Load could not create class instance for alloc "+modName+"::"+clsName);
			return null;
		}

		alloc._load(this, file);
		return alloc;
	}

	void start() {
		Object@ hw = ai.empire.Homeworld;
		if(hw !is null) {
			Factory f;
			@f.obj = hw;
			@f.plAI = planets.getAI(cast<Planet>(hw));

			factories.insertLast(f);
		}
	}

	Factory@ get(Object@ obj) {
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].obj is obj)
				return factories[i];
		}
		return null;
	}

	Factory@ registerFactory(Object@ obj) {
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].obj is obj)
				return factories[i];
		}
		Factory f;
		@f.obj = obj;
		factories.insertLast(f);
		return f;
	}

	Factory@ getFactory(Region@ region) {
		Factory@ best;
		double bestLabor = 0;
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].obj.region !is region)
				continue;
			double l = factories[i].obj.laborIncome;
			if(l > bestLabor) {
				bestLabor = l;
				@best = factories[i];
			}
		}
		return best;
	}

	BuildConstruction@ buildConstruction(const ConstructionType@ type, double priority = 1.0, bool force = false, uint moneyType = BT_Development) {
		//Potentially build a flagship
		BuildConstruction f(type);
		f.moneyType = moneyType;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildFlagship@ buildFlagship(const Design@ dsg, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildFlagship f(dsg);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildFlagship@ buildFlagship(DesignTarget@ target, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildFlagship f(target);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildStation@ buildStation(const Design@ dsg, const vec3d& position, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildStation f(dsg, position);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildStation@ buildStation(DesignTarget@ target, const vec3d& position, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildStation f(target, position);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildOrbital@ buildOrbital(const OrbitalModule@ module, const vec3d& position, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildOrbital f(module, position);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildStation@ buildLocalStation(const Design@ dsg, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildStation f(dsg, local=true);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildStation@ buildLocalStation(DesignTarget@ target, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildStation f(target, local=true);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	BuildOrbital@ buildLocalOrbital(const OrbitalModule@ module, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		BuildOrbital f(module, local=true);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	RetrofitShip@ retrofit(Ship@ ship, double priority = 1.0, bool force = false) {
		//Potentially build a flagship
		RetrofitShip f(ship);
		f.moneyType = BT_Military;
		f.priority = priority;
		build(f, force=force);
		return f;
	}

	AllocateConstruction@ build(AllocateConstruction@ alloc, bool force = false) {
		//Add a construction into the potential constructions queue
		if(!force)
			alloc.maxTime = ai.behavior.constructionMaxTime;
		alloc.id = nextAllocId++;
		allocations.insertLast(alloc);

		if(log)
			ai.print("Queue construction: "+alloc.toString());

		return alloc;
	}

	AllocateConstruction@ buildNow(AllocateConstruction@ alloc, Factory@ f) {
		if(f.busy)
			return null;
		if(alloc.alloc !is null)
			budget.applyNow(alloc.alloc);
		start(f, alloc);
		allocations.remove(alloc);
		return alloc;
	}

	void cancel(AllocateConstruction@ alloc) {
		if(alloc.started || (alloc.alloc !is null && alloc.alloc.allocated))
			return; //TODO

		allocations.remove(alloc);
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].active is alloc)
				@factories[i].active = null;
		}

		if(alloc.alloc !is null)
			budget.remove(alloc.alloc);
	}

	uint factInd = 0;
	void tick(double time) {
		//Manage factories
		if(factories.length != 0) {
			factInd = (factInd+1) % factories.length;
			auto@ f = factories[factInd];
			if(!f.tick(ai, this, time))
				factories.removeAt(factInd);
		}
	}

	void start(Factory@ f, AllocateConstruction@ c) {
		//Actually construct something we've allocated budget for
		@f.active = c;
		@c.tryFactory = null;

		c.construct(ai, f);

		if(log)
			ai.print("Construct: "+c.toString(), f.obj);

		for(uint i = 0, cnt = allocations.length; i < cnt; ++i) {
			if(allocations[i].tryFactory is f)
				@allocations[i].tryFactory = null;
		}
	}

	uint plCheck = 0;
	uint orbCheck = 0;
	double consTimer = 0.0;
	void focusTick(double time) {
		//Progress the allocations
		for(uint n = 0, ncnt = allocations.length; n < ncnt; ++n) {
			if(!allocations[n].tick(ai, this, time)) {
				allocations.removeAt(n);
				--n; --ncnt;
			}
		}

		//See if anything we can potentially construct is constructible
		totalLabor = 0.0;
		bestLabor = 0.0;
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			auto@ f = factories[i];
			totalLabor += f.laborIncome;
			if(f.laborIncome > bestLabor)
				bestLabor = f.laborIncome;
		}

		for(uint n = 0, ncnt = allocations.length; n < ncnt; ++n) {
			auto@ alloc = allocations[n];
			if(alloc.tryFactory !is null)
				continue;

			Factory@ bestFact;
			double bestCur = 0.0;

			for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
				auto@ f = factories[i];
				if(f.busy)
					continue;
				if(!alloc.canBuild(ai, f))
					continue;
				if(!f.viable(ai, alloc))
					continue;

				double w = f.laborIncome;
				if(f is primaryFactory)
					w *= 1.5;
				if(f.exportingTo !is null)
					w /= 0.75;

				if(w > bestCur) {
					bestCur = w;
					@bestFact = f;
				}
			}

			if(bestFact !is null) {
				@alloc.tryFactory = bestFact;
				alloc.update(ai, bestFact);
			}
		}

		//Classify our primary factory
		if(primaryFactory is null) {
			//Find our best factory
			Factory@ best;
			double bestWeight = 0.0;
			for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
				auto@ f = factories[i];

				double w = f.laborIncome;
				w += 0.1 * f.laborAim;
				if(f.obj.isPlanet)
					w *= 100.0;
				if(f.obj.isShip)
					w *= 0.1;

				if(w > bestWeight) {
					bestWeight = w;
					@best = f;
				}
			}

			if(best !is null) {
				@primaryFactory = best;
			}
			else {
				noFactoryTimer += time;
				if(noFactoryTimer > 3.0 * 60.0 && ai.defs.Factory !is null) {
					//Just pick our highest level planet and hope for the best
					PlanetAI@ best;
					double bestWeight = 0.0;

					for(uint i = 0, cnt = planets.planets.length; i < cnt; ++i) {
						auto@ plAI = planets.planets[i];
						double w = plAI.obj.level;
						w += 0.5 * plAI.obj.resourceLevel;

						if(w > bestWeight) {
							bestWeight = w;
							@best = plAI;
						}
					}

					if(best !is null) {
						Factory f;
						@f.obj = best.obj;
						@f.plAI = best;

						factories.insertLast(f);
						@primaryFactory = f;
					}

					noFactoryTimer = 0.0;
				}
			}
		}
		else {
			noFactoryTimer = 0.0;
		}

		//Find new factories
		if(planets.planets.length != 0) {
			plCheck = (plCheck+1) % planets.planets.length;
			PlanetAI@ plAI = planets.planets[plCheck];
			if(plAI.obj.laborIncome > 0 && plAI.obj.canBuildShips) {
				if(get(plAI.obj) is null) {
					Factory f;
					@f.obj = plAI.obj;
					@f.plAI = plAI;

					factories.insertLast(f);
				}
			}
		}
		if(orbitals.orbitals.length != 0) {
			orbCheck = (orbCheck+1) % orbitals.orbitals.length;
			OrbitalAI@ orbAI = orbitals.orbitals[orbCheck];
			if(orbAI.obj.hasConstruction && orbAI.obj.laborIncome > 0
					&& !cast<Orbital>(orbAI.obj).hasMaster()) {
				if(get(orbAI.obj) is null) {
					Factory f;
					@f.obj = orbAI.obj;

					factories.insertLast(f);
				}
			}
		}

		//See if we should switch our primary factory
		if(primaryFactory !is null) {
			if(!primaryFactory.valid) {
				@primaryFactory = null;
			}
			else {
				Factory@ best;
				double bestLabor = 0.0;
				double primaryLabor = primaryFactory.laborIncome;
				bool canImport = primaryFactory.obj.canImportLabor;
				for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
					auto@ f = factories[i];
					double checkLabor = f.laborIncome;
					if(f.obj.isShip)
						checkLabor *= 0.1;
					if(f.exportingTo !is primaryFactory && canImport)
						primaryLabor += checkLabor * 0.75;
					if(checkLabor > bestLabor) {
						bestLabor = checkLabor;
						@best = f;
					}
				}

				if(best !is null && bestLabor > 1.5 * primaryLabor)
					@primaryFactory = best;
			}
		}

		//See if we should consolidate at a shipyard
		if(buildConsolidate !is null && buildConsolidate.completed) {
			@buildConsolidate = null;
			consTimer = gameTime + 60.0;
		}
		else if(ai.behavior.consolidateLaborExports && primaryFactory !is null && ai.defs.Shipyard !is null && buildConsolidate is null && !primaryFactory.obj.canImportLabor && consTimer < gameTime) {
			double totalLabor = 0.0, bestLabor = 0.0;
			for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
				double inc = factories[i].obj.baseLaborIncome;
				if(factories[i].obj.canExportLabor)
					totalLabor += inc;
				if(factories[i].laborIncome > bestLabor)
					bestLabor = factories[i].laborIncome;
			}

			if(bestLabor < totalLabor * 0.6) {
				Factory@ bestConsolidate;
				double bestWeight = 0.0;
				for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
					auto@ f = factories[i];
					if(!f.obj.canImportLabor)
						continue;

					double w = f.obj.baseLaborIncome;
					w /= f.obj.position.distanceTo(primaryFactory.obj.position);

					if(w > bestWeight) {
						bestWeight = w;
						@bestConsolidate = f;
					}
				}

				if(bestConsolidate !is null) {
					if(log)
						ai.print("Set shipyard for consolidate.", bestConsolidate.obj.region);
					@primaryFactory = bestConsolidate;
				}
				else {
					Region@ reg = primaryFactory.obj.region;
					if(reg !is null) {
						vec3d pos = reg.position;
						vec2d offset = random2d(reg.radius * 0.4, reg.radius * 0.8);
						pos.x += offset.x;
						pos.z += offset.y;

						if(log)
							ai.print("Build shipyard for consolidate.", reg);

						@buildConsolidate = buildOrbital(ai.defs.Shipyard, pos);
					}
				}
			}
		}
	}

	bool isGettingAsteroid(Asteroid@ asteroid) {
		for(uint i = 0, cnt = factories.length; i < cnt; ++i) {
			if(factories[i].bgAsteroid is asteroid)
				return true;
		}
		return false;
	}

	Asteroid@ getBackgroundAsteroid(Factory& f) {
		double closest = INFINITY;
		Asteroid@ best;
		Region@ reg = f.obj.region;
		if(reg is null)
			return null;
		
		uint cnt = systems.owned.length;
		uint offset = randomi(0, cnt-1);
		for(uint i = 0, check = min(3, cnt); i < check; ++i) {
			auto@ sys = systems.owned[(i+offset)%cnt];
			double dist = sys.obj.position.distanceToSQ(f.obj.position);
			if(dist > closest)
				continue;
			if(!sys.obj.sharesTerritory(ai.empire, reg))
				continue;

			for(uint n = 0, ncnt = sys.asteroids.length; n < ncnt; ++n) {
				Asteroid@ roid = sys.asteroids[n];
				if(roid.owner.valid)
					continue;
				if(roid.getAvailableCount() == 0)
					continue;
				if(isGettingAsteroid(roid))
					continue;

				closest = dist;
				@best = roid;
				break;
			}
		}

		cnt = systems.outsideBorder.length;
		offset = randomi(0, cnt-1);
		for(uint i = 0, check = min(3, cnt); i < check; ++i) {
			auto@ sys = systems.outsideBorder[(i+offset)%cnt];
			double dist = sys.obj.position.distanceToSQ(f.obj.position);
			if(dist > closest)
				continue;
			if(!sys.obj.sharesTerritory(ai.empire, reg))
				continue;

			for(uint n = 0, ncnt = sys.asteroids.length; n < ncnt; ++n) {
				Asteroid@ roid = sys.asteroids[n];
				if(roid.owner.valid)
					continue;
				if(roid.getAvailableCount() == 0)
					continue;
				if(isGettingAsteroid(roid))
					continue;

				closest = dist;
				@best = roid;
				break;
			}
		}

		return best;
	}
};

double asteroidResourceValue(const ResourceType@ type) {
	if(type is null)
		return 0.0;
	double w = 1.0;
	w += type.level * 10.0;
	w += type.totalPressure;
	if(type.cls !is null)
		w += 5.0;
	return w;
}

AIComponent@ createConstruction() {
	return Construction();
}

