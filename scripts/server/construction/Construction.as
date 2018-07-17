import construction.Constructible;
import construction.ShipConstructible;
from construction.OrbitalConstructible import OrbitalConstructible;
from construction.AsteroidConstructible import AsteroidConstructible;
from construction.TerraformConstructible import TerraformConstructible;
from construction.RetrofitConstructible import RetrofitConstructible;
from construction.DryDockConstructible import DryDockConstructible;
from construction.ExportConstructible import ExportConstructible;
from construction.StationConstructible import StationConstructible;
from construction.BuildingConstructible import BuildingConstructible;
from construction.ConstructionConstructible import ConstructionConstructible;
from constructions import ConstructionType, getConstructionType;
import object_creation;
import resources;
import systems;
import buildings;
import bool getCheatsEverOn() from "cheats";
from regions.regions import getRegion;
#include "include/resource_constants.as"

enum ConstructionCapability {
	CC_Ship = 0x1,
	CC_Orbital = 0x2,
	CC_Asteroid = 0x4,
	CC_Terraform = 0x8,
	CC_Supports = 0x10,
};

bool allowConstructFrom(Object& obj, Object& constructFrom) {
	if(obj is constructFrom)
		return true;
	if(obj.isOrbital && constructFrom.isOrbital) {
		if(cast<Orbital>(constructFrom).isMaster(obj))
			return true;
	}
	return false;
}

tidy class Construction : Component_Construction, Savable {
	Constructible@[] queue;

	uint capabilities = 0;
	bool deltaConstruction = false;
	bool buildingSupport = false;
	bool deltaStored = false;
	bool curUsingLabor = false;
	int nextID = 0;

	bool canExport = true;
	bool canImport = false;

	double LaborIncome = 0;
	double DistributedLabor = 0;
	double LaborFactor = 1.0;
	double hpBonus = 0.0;

	int supportSpeed = 100;
	int shipCost = 100;
	int orbitalCost = 100;
	double orbitalMaint = 1.0;
	double terraformCost = 1.0;
	double constructionCost = 1.0;

	double laborStorage = 0;
	double storedLabor = 0;

	uint supportId = 0;
	const Design@ supportDesign;
	Object@ supportFor;
	double supportLabor = -1;
	int consType = -1;
	
	bool repeating = false;
	bool rally = false;
	Object@ rallyObj;
	vec3d rallyPoint;

	Construction() {
	}

	void load(SaveFile& msg) {
		msg >> capabilities;
		msg >> LaborIncome;
		msg >> LaborFactor;
		msg >> DistributedLabor;
		msg >> supportSpeed;
		msg >> shipCost;
		msg >> orbitalCost;
		msg >> orbitalMaint;
		msg >> nextID;
		msg >> terraformCost;
		msg >> canExport;
		msg >> canImport;
		if(msg >= SV_0035)
			msg >> constructionCost;
		if(msg >= SV_0090) {
			msg >> laborStorage;
			msg >> storedLabor;
		}
		
		if(msg > SV_0021) {
			msg >> rally;
			msg >> rallyObj;
			msg >> rallyPoint;
		}
		if(msg >= SV_0117)
			msg >> repeating;

		uint cnt = 0;
		msg >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Constructible@ cons;

			uint8 type = 0;
			msg >> type;
			switch(type) {
				case CT_Orbital:
					@cons = OrbitalConstructible(msg);
				break;
				case CT_Flagship:
					@cons = ShipConstructible(msg);
				break;
				case CT_Station:
					@cons = StationConstructible(msg);
				break;
				case CT_Asteroid:
					@cons = AsteroidConstructible(msg);
				break;
				case CT_Terraform:
					@cons = TerraformConstructible(msg);
				break;
				case CT_Retrofit:
					@cons = RetrofitConstructible(msg);
				break;
				case CT_DryDock:
					@cons = DryDockConstructible(msg);
				break;
				case CT_Export:
					@cons = ExportConstructible(msg);
				break;
				case CT_Building:
					@cons = BuildingConstructible(msg);
				break;
				case CT_Construction:
					@cons = ConstructionConstructible(msg);
				break;
			}

			if(cons !is null)
				queue.insertLast(cons);
		}

		msg >> supportId;
		msg >> supportDesign;
		msg >> supportFor;
		msg >> supportLabor;
		if(msg >= SV_0147)
			msg >> hpBonus;
	}

	void save(SaveFile& msg) {
		msg << capabilities;
		msg << LaborIncome;
		msg << LaborFactor;
		msg << DistributedLabor;
		msg << supportSpeed;
		msg << shipCost;
		msg << orbitalCost;
		msg << orbitalMaint;
		msg << nextID;
		msg << terraformCost;
		msg << canExport;
		msg << canImport;
		msg << constructionCost;
		msg << laborStorage;
		msg << storedLabor;
		
		msg << rally;
		msg << rallyObj;
		msg << rallyPoint;
		msg << repeating;

		uint cnt = queue.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			queue[i].save(msg);

		msg << supportId;
		msg << supportDesign;
		msg << supportFor;
		msg << supportLabor;
		msg << hpBonus;
	}

	double get_constructionCostMod() const {
		return constructionCost;
	}

	double get_laborIncome() const {
		return LaborIncome * LaborFactor;
	}

	double get_baseLaborIncome() const {
		return LaborIncome;
	}

	double get_laborFactor() const {
		return LaborFactor;
	}

	double get_laborStorageCapacity() const {
		return laborStorage;
	}

	double get_currentLaborStored() const {
		return storedLabor;
	}

	bool get_isRepeating() const {
		return repeating;
	}

	void modLaborIncome(Object& obj, double mod) {
		LaborIncome += mod;
		deltaConstruction = true;
		
		if(laborIncome >= LABOR_ACHIEVE_THRESH && obj.owner is playerEmpire && !getCheatsEverOn())
			unlockAchievement("ACH_LABOR200");
	}

	void modLaborFactor(Object& obj, double mod) {
		LaborFactor += mod;
		deltaConstruction = true;
		
		if(laborIncome >= LABOR_ACHIEVE_THRESH && obj.owner is playerEmpire && !getCheatsEverOn())
			unlockAchievement("ACH_LABOR200");
	}

	void setDistributedLabor(Object& obj, double val) {
		if(val != DistributedLabor) {
			LaborIncome += val - DistributedLabor;
			DistributedLabor = val;
			deltaConstruction = true;
		
			if(laborIncome >= LABOR_ACHIEVE_THRESH && obj.owner is playerEmpire && !getCheatsEverOn())
				unlockAchievement("ACH_LABOR200");
		}
	}

	void setRepeating(bool value) {
		repeating = value;
		deltaConstruction = true;
	}

	double get_distributedLabor() {
		return DistributedLabor;
	}

	float get_constructionProgress() const {
		if(queue.length == 0)
			return -1.f;
		if(queue[0].totalLabor <= 0)
			return 1.f;
		return queue[0].curLabor / queue[0].totalLabor;
	}
	
	const Design@ get_constructionDesign() const {
		if(queue.length == 0)
			return null;
		Constructible@ top = queue[0];
		
		ShipConstructible@ flagship = cast<ShipConstructible@>(top);
		if(flagship !is null)
			return flagship.design;
			
		return null;
	}

	bool hasConstructionUnder(double eta) {
		if(queue.length == 0)
			return false;
		if(LaborIncome == 0)
			return false;
		return (queue[0].totalLabor - queue[0].curLabor) / (LaborIncome * LaborFactor) < eta;
	}

	bool get_canBuildSupports() {
		return capabilities & CC_Supports != 0;
	}

	void set_canBuildSupports(bool value) {
		if(value == get_canBuildSupports())
			return;
		if(value)
			capabilities |= CC_Supports;
		else
			capabilities &= ~CC_Supports;
		deltaConstruction = true;
	}

	bool get_canBuildShips() {
		return capabilities & CC_Ship != 0;
	}

	void set_canBuildShips(bool value) {
		if(value == get_canBuildShips())
			return;
		if(value)
			capabilities |= CC_Ship | CC_Supports;
		else
			capabilities &= ~(CC_Ship | CC_Supports);
		deltaConstruction = true;
	}

	bool get_canBuildOrbitals() {
		return capabilities & CC_Orbital != 0;
	}

	void set_canBuildOrbitals(bool value) {
		if(value == get_canBuildOrbitals())
			return;
		if(value)
			capabilities |= CC_Orbital;
		else
			capabilities &= ~CC_Orbital;
		deltaConstruction = true;
	}

	bool get_canBuildAsteroids() {
		return capabilities & CC_Asteroid != 0;
	}

	void set_canBuildAsteroids(bool value) {
		if(value == get_canBuildAsteroids())
			return;
		if(value)
			capabilities |= CC_Asteroid;
		else
			capabilities &= ~CC_Asteroid;
		deltaConstruction = true;
	}

	bool get_canTerraform() {
		return capabilities & CC_Terraform != 0;
	}

	void set_canTerraform(bool value) {
		if(value == get_canTerraform())
			return;
		if(value)
			capabilities |= CC_Terraform;
		else
			capabilities &= ~CC_Terraform;
		deltaConstruction = true;
	}

	bool get_canExportLabor() {
		return canExport;
	}

	void set_canExportLabor(bool value) {
		if(value == canExport)
			return;
		canExport = value;
		deltaConstruction = true;
	}

	bool get_canImportLabor() {
		return canImport;
	}

	void set_canImportLabor(bool value) {
		if(value == canImport)
			return;
		canImport = value;
		deltaConstruction = true;
	}

	uint get_constructionCount() const {
		return queue.length;
	}

	uint get_constructionType() const {
		return consType;
	}

	string get_constructionName(uint num) const {
		if(num >= queue.length)
			return "(null)";
		return queue[num].name;
	}
	
	int get_constructionID(uint num) const {
		if(num >= queue.length)
			return -1;
		return queue[num].id;
	}

	void getConstructionQueue() {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			yield(queue[i]);
	}

	void getConstructionQueue(uint limit) {
		for(uint i = 0, cnt = min(queue.length, limit); i < cnt; ++i)
			yield(queue[i]);
	}

	bool queueConstructible(Object& obj, Constructible@ cons) {
		if(!cons.pay(obj))
			return false;
		cons.id = nextID++;
		queue.insertLast(cons);
		deltaConstruction = true;
		if(queue.length == 1)
			startConstruction(obj);
		return true;
	}

	int constructibleIndex(int id) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			if(queue[i].id == id)
				return i;
		return -1;
	}

	int shipConsIndex(int id) {
		if(id == -1) {
			for(int i = queue.length - 1; i >= 0; --i)
				if(queue[i].type == CT_Flagship || queue[i].type == CT_Station)
					return i;
		}
		else {
			for(uint i = 0, cnt = queue.length; i < cnt; ++i)
				if(queue[i].id == id)
					return i;
		}
		return -1;
	}

	void startConstruction(Object& obj) {
		if(queue.length == 0)
			return;
		Constructible@ active = queue[0];
		active.start(obj);
	}

	int get_supportBuildSpeed(const Object& obj) const {
		int cost = 100;
		cost = max(10, cost + (supportSpeed - 100));
		return cost;
	}

	int get_shipBuildCost(const Object& obj) const {
		int cost = 100;
		cost = max(10, cost + (shipCost - 100));
		return cost;
	}

	int get_orbitalBuildCost(const Object& obj) const {
		int cost = 100;
		cost = max(10, cost + (orbitalCost - 100));
		return cost;
	}

	void modSupportBuildSpeed(int amt) {
		supportSpeed += amt;
		deltaConstruction = true;
	}

	void modShipBuildCost(int amt) {
		shipCost += amt;
		deltaConstruction = true;
	}

	void multConstructionCostMod(double multFactor) {
		constructionCost *= multFactor;
		deltaConstruction = true;
	}

	void modOrbitalBuildCost(int amt) {
		orbitalCost += amt;
		deltaConstruction = true;
	}

	double get_orbitalMaintenanceMod(const Object& obj) const {
		double cost = 1.0;
		cost *= clamp(orbitalMaint, 0.01f, 1.f);
		return cost;
	}

	void modOrbitalMaintenanceMod(double amt) {
		orbitalMaint *= amt;
		deltaConstruction = true;
	}

	double get_terraformCostMod() const {
		return terraformCost;
	}

	void modTerraformCostMod(double amt) {
		terraformCost += amt;
		deltaConstruction = true;
	}

	bool get_constructingSupport() const {
		return supportDesign !is null;
	}

	bool get_isUsingLabor() const {
		return curUsingLabor;
	}
	
	void clearRally() {
		rally = false;
		@rallyObj = null;
		deltaConstruction = true;
	}
	
	void rallyTo(Object& obj, Object@ dest) {
		if(dest is null || !dest.valid || !dest.isVisibleTo(obj.owner))
			clearRally();
		rally = true;
		@rallyObj = dest;
		rallyPoint = dest.position;
		deltaConstruction = true;
	}
	
	void rallyTo(vec3d position) {
		rally = true;
		rallyPoint = position;
		deltaConstruction = true;
	}
	
	bool get_isRallying() {
		return rally;
	}
	
	vec3d get_rallyPosition() {
		return rallyPoint;
	}
	
	Object@ get_rallyObject() {
		return rallyObj;
	}
	
	void doRally(Object& obj, Object@ orderObj) {
		if(!rally || obj.owner !is orderObj.owner || !orderObj.hasLeaderAI)
			return;
		if(rallyObj !is null && rallyObj.isVisibleTo(obj.owner)) {
			switch(rallyObj.type) {
				case OT_Planet:
				{
					Planet@ pl = cast<Planet>(rallyObj);
					vec2d off = random2d(pl.radius + 0.5 + orderObj.radius, pl.OrbitSize - 0.1);
					orderObj.addMoveOrder(pl.position + vec3d(off.x, 0.0, off.y));
					break;
				}
				case OT_Star:
				{
					Region@ reg = rallyObj.region;
					orderObj.addMoveOrder(reg.position + (orderObj.position - reg.position).normalize(reg.radius * 0.9));
					break;
				}
				case OT_Region:
				{
					Region@ reg = cast<Region>(rallyObj);
					orderObj.addMoveOrder(reg.position + (orderObj.position - reg.position).normalize(reg.radius * 0.9));
					break;
				}
				default:
					orderObj.addGotoOrder(rallyObj); break;
			}
		}
		else {
			orderObj.addMoveOrder(rallyPoint);
		}
	}

	bool laborFlag = false;
	int labObj = 0;
	bool flagUsingLabor(Object@ obj) {
		if(obj !is null) {
			int id = obj.id;
			if(labObj == id)
				return true;
			if(labObj != 0)
				return false;
			labObj = id;
		}
		else {
			if(labObj != 0)
				return false;
		}
		laborFlag = true;
		return true;
	}

	void constructionTick(Object& obj, double time) {
		bool usingLabor = laborFlag;
		if(rally && rallyObj !is null && rallyObj.isVisibleTo(obj.owner))
			rallyPoint = rallyObj.position;
	
		//Handle support construction
		double subLabor = time * LaborIncome * LaborFactor * double(get_supportBuildSpeed(obj)) / 100.0;
		double resvLabor = 0.0;
		if(supportDesign !is null) {
			subLabor *= 0.5;
			resvLabor = subLabor;
			usingLabor = true;
		}
		for(uint i = 0, cnt = queue.length; i < cnt && subLabor > 0; ++i) {
			ShipConstructible@ cons = cast<ShipConstructible>(queue[i]);
			if(cons !is null && cons.hasSupportsBuilding) {
				subLabor = cons.addSupportLabor(subLabor);
				usingLabor = true;
			}
		}
		if(supportDesign !is null) {
			subLabor += resvLabor;
			if(subLabor > 0) {
				if(supportLabor < 0) {
					supportLabor = getLaborCost(supportDesign, 1);
				}
				else {
					supportLabor -= subLabor;
					if(supportLabor <= 0) {
						Object@ at = obj;
						if(supportDesign.hasTag(ST_Satellite) && supportFor.isPlanet)
							@at = supportFor;
						Ship@ ship = createShip(at, supportDesign, obj.owner, null, false);
						supportFor.supportBuildFinished(supportId, supportDesign, obj, ship);
						if(hpBonus != 0)
							ship.modHPFactor(+hpBonus);

						@supportDesign = null;
						@supportFor = null;
						deltaConstruction = true;
					}
				}
			}
		}

		//Handle the queue
		double tick = time * LaborIncome * LaborFactor;
		double prevMaximumStored = max(storedLabor, laborStorage);
		if(queue.length != 0 && storedLabor > 0) {
			double takeLabor = min(storedLabor, max(prevMaximumStored, 1.0) * time / config::LABOR_STORAGE_DUMP_TIME);
			tick += takeLabor;
			storedLabor -= takeLabor;
		}

		uint index = 0;
		while(index < queue.length) {
			Constructible@ active = queue[index];
			if(!active.paid) {
				if(!active.pay(obj))
					break;
			}
			if(!active.start(obj))
				break;

			double remain = active.totalLabor - active.curLabor;
			if(remain <= tick && active.canComplete) {
				deltaConstruction = true;
				tick -= remain;
				active.complete(obj);
				active.remove(obj);
				queue.removeAt(index);
				if(repeating) {
					if(active.repeat(obj)) {
						active.id = nextID++;
						queue.insertLast(active);
					}
				}
				usingLabor = true;
				deltaConstruction = true;
			}
			else {
				active.curLabor += tick;
				uint result = active.tick(obj, time);
				switch(result) {
					case TR_Remove:
						active.remove(obj);
						queue.removeAt(index);
						deltaConstruction = true;
					break;
					case TR_UsedLabor:
						usingLabor = true;
						tick = 0;
					break;
					case TR_VanishLabor:
						tick = 0;
					break;
					case TR_UnusedLabor:
						//Fall through the tick labor
					break;
				}
				if(tick <= 0)
					break;
				else
					index += 1;
			}
		}
		if(tick > 0 && storedLabor < prevMaximumStored) {
			storedLabor = min(prevMaximumStored, storedLabor + tick);
			deltaStored = true;
			usingLabor = true;
		}
		laborFlag = false;
		labObj = 0;
		curUsingLabor = usingLabor;

		if(queue.length == 0)
			consType = -1;
		else
			consType = queue[0].type;
	}

	uint queuePosition(int id) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			if(queue[i].id == id)
				return i;
		}
		return uint(-1);
	}

	void modLaborStorage(double mod) {
		laborStorage += mod;
		deltaStored = true;
	}

	void modStoredLabor(double mod, bool obeyCap = false) {
		if(obeyCap) {
			if(storedLabor < laborStorage)
				storedLabor = min(laborStorage, storedLabor + mod);
		}
		else {
			storedLabor += mod;
		}
		deltaStored = true;
	}

	void cancelConstruction(Object& obj, int id) {
		int index = constructibleIndex(id);
		if(index == -1)
			return;
		queue[index].cancel(obj);
		queue[index].remove(obj);
		queue.removeAt(index);
		deltaConstruction = true;
	}

	void moveConstruction(Object& obj, int id, int beforeId = -1) {
		int myIndex = constructibleIndex(id);
		if(myIndex == -1)
			return;
		int dropIndex = constructibleIndex(beforeId);
		if(dropIndex == -1) {
			queue.insertLast(queue[myIndex]);
			queue.removeAt(myIndex);
		}
		else {
			Constructible@ copy = queue[myIndex];
			queue.removeAt(myIndex);
			if(myIndex < dropIndex)
				--dropIndex;
			queue.insertAt(dropIndex, copy);
		}
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			queue[i].move(obj, i);
		deltaConstruction = true;
	}

	void buildOrbital(Object& obj, int type, vec3d position, Object@ frame = null, Object@ constructFrom = null) {
		if(capabilities & CC_Orbital == 0)
			return;

		Object@ pathFrom = obj;
		if(constructFrom !is null) {
			if(!allowConstructFrom(obj, constructFrom))
				return;
			@pathFrom = constructFrom;
		}

		auto@ def = getOrbitalModule(type);
		if(def is null)
			return;
		if(!def.canBuildBy(obj))
			return;
		if(!def.canBuildAt(obj, position))
			return;
		if(!canBuildOrbital(pathFrom, position, true))
			return;

		Orbital@ orbFrame = cast<Orbital>(frame);
		if(orbFrame !is null && orbFrame.getValue(OV_FRAME_Usable) == 0.0)
			@orbFrame = null;
		if(orbFrame !is null && orbFrame.owner !is obj.owner)
			@orbFrame = null;

		OrbitalConstructible cons(obj, def, position);
		cons.buildCost = ceil(double(cons.buildCost) * double(get_orbitalBuildCost(obj)) / 100.0);
		cons.buildCost *= constructionCost;

		double penFact = 1.0;
		if(orbFrame !is null) {
			cons.buildCost *= orbFrame.getValue(OV_FRAME_CostFactor);
			cons.totalLabor *= orbFrame.getValue(OV_FRAME_LaborFactor);
			penFact = orbFrame.getValue(OV_FRAME_LaborPenaltyFactor);
		}

		TradePath path(obj.owner);
		Region@ target = getRegion(position);
		path.generate(getSystem(pathFrom.region), getSystem(target));
		if(!path.isUsablePath)
			return;

		cons.totalLabor *= 1.0 + config::ORBITAL_LABOR_COST_STEP * penFact * double(path.pathSize - 1);

		if(queueConstructible(obj, cons)) {
			if(orbFrame !is null)
				orbFrame.sendObject(OV_FRAME_Target, cons.target);
		}
	}

	void buildStation(Object& obj, const Design@ design, vec3d position, Object@ frame = null, Object@ constructFrom = null) {
		if(capabilities & CC_Orbital == 0)
			return;
		if(design is null || design.hull is null || !design.hasTag(ST_Station)) {
			error("Invalid design for station construction at " + obj.name);
			return;
		}

		Object@ pathFrom = obj;
		if(constructFrom !is null) {
			if(!allowConstructFrom(obj, constructFrom))
				return;
			@pathFrom = constructFrom;
		}

		if(!canBuildOrbital(pathFrom, position))
			return;

		Orbital@ orbFrame = cast<Orbital>(frame);
		if(orbFrame !is null && orbFrame.getValue(OV_FRAME_Usable) == 0.0)
			@orbFrame = null;
		if(orbFrame !is null && orbFrame.owner !is obj.owner)
			@orbFrame = null;

		TradePath path(obj.owner);
		Region@ target = getRegion(position);

		Region@ reg = pathFrom.region;
		if(reg is null)
			return;
		auto@ fromSys = getSystem(reg);
		auto@ toSys = getSystem(target);
		if(fromSys is null || toSys is null)
			return;

		path.generate(fromSys, toSys);
		if(!path.isUsablePath)
			return;

		double penFact = 1.0;
		if(orbFrame !is null)
			penFact = orbFrame.getValue(OV_FRAME_LaborPenaltyFactor);
		double penalty = 1.0 + config::ORBITAL_LABOR_COST_STEP * penFact * double(path.pathSize - 1);
		StationConstructible cons(design, position, penalty);
		cons.totalLabor *= obj.owner.OrbitalLaborCostFactor;
		cons.buildCost *= obj.owner.OrbitalBuildCostFactor;
		cons.buildCost *= constructionCost;

		if(orbFrame !is null) {
			cons.buildCost *= orbFrame.getValue(OV_FRAME_CostFactor);
			cons.totalLabor *= orbFrame.getValue(OV_FRAME_LaborFactor);
		}

		if(queueConstructible(obj, cons)) {
			if(orbFrame !is null)
				orbFrame.sendObject(OV_FRAME_Target, cons.target);
		}
	}

	void buildFlagship(Object& obj, const Design@ design, Object@ constructFrom) {
		if(capabilities & CC_Ship == 0)
			return;
		if(constructFrom !is null) {
			if(!allowConstructFrom(obj, constructFrom))
				return;
		}
		if(design is null || design.hull is null || !design.hasTag(ST_Flagship)) {
			error("Invalid design for ship construction at " + obj.name);
			return;
		}

		ShipConstructible cons(design);
		@cons.constructFrom = constructFrom;
		cons.buildCost = ceil(double(cons.buildCost) * double(get_shipBuildCost(obj)) / 100.0);
		cons.buildCost *= constructionCost;
		queueConstructible(obj, cons);
	}

	void buildDryDock(Object& obj, const Design@ forDesign, float pct) {
		if(capabilities & CC_Ship == 0 || capabilities & CC_Orbital == 0)
			return;
		if(pct < 0.01f)
			return;
		auto@ module = getOrbitalModule("DryDock");
		if(module is null) {
			error("Could not find 'DryDock' orbital module for drydock construction.");
			return;
		}
		if(!module.canBuildBy(obj))
			return;
		if(!payDesignCosts(obj, forDesign))
			return;

		//Pay for all this*/
		int cost = getBuildCost(forDesign);
		cost = 100 + ceil(float(cost) * pct);
		cost *= constructionCost;
		cost = double(cost) * config::DRYDOCK_BUILDCOST_FACTOR * obj.owner.DrydockCostFactor;
		if(obj.owner.consumeBudget(cost) == -1)
			return;

		ObjectDesc oDesc;
		oDesc.type = OT_Orbital;
		@oDesc.owner = obj.owner;
		oDesc.name = format(locale::DRY_DOCK_NAME, forDesign.name);
		oDesc.radius = pow(forDesign.size, 1.0/2.5);

		//Figure out a good position to put this dry dock
		double minRad = obj.radius * 2.5, maxRad = minRad * 2.0;
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null)
			maxRad = pl.OrbitSize;

		vec2d pos = random2d(minRad, maxRad);
		vec3d offset(pos.x, 0, pos.y);
		oDesc.position = obj.position + offset;

		Orbital@ orb = cast<Orbital>(makeObject(oDesc));
		orb.addSection(module.id);

		orb.sendDesign(OV_DRY_Design, forDesign);
		orb.sendValue(OV_DRY_SetFinanced, pct);

		//Start building on it
		DryDockConstructible cons(obj, orb);
		queueConstructible(obj, cons);
	}

	void workDryDock(Object& obj, Orbital@ dryDock) {
		if(capabilities & CC_Ship == 0)
			return;
		if(dryDock is null || dryDock.owner !is obj.owner)
			return;

		DryDockConstructible cons(obj, dryDock);
		cons.buildCost *= constructionCost;
		queueConstructible(obj, cons);
	}

	void exportLaborTo(Object& obj, Object@ exportTo) {
		if(!canExport)
			return;
		if(!exportTo.hasConstruction || !exportTo.canImportLabor)
			return;

		ExportConstructible cons(obj, exportTo);
		cons.buildCost *= constructionCost;
		queueConstructible(obj, cons);
	}

	void addSupportShipConstruction(Object& obj, int id, const Design@ dsg, uint amount) {
		int index = shipConsIndex(id);
		if(index == -1)
			return;
		ShipConstructible@ cons = cast<ShipConstructible>(queue[index]);
		if(cons is null)
			return;

		uint maxAmount = floor(cons.getSupportSupplyFree() / dsg.size);
		amount = min(amount, maxAmount);
		if(amount == 0)
			return;

		if(!payDesignCosts(obj, dsg, amount))
			return;

		int cost = getBuildCost(dsg, amount);
		int take = obj.owner.consumeBudget(cost, true);
		if(take == -1) {
			reverseDesignCosts(obj, dsg, amount);
			return;
		}

		if(!cons.addSupports(obj, dsg, amount, cycle=take))
			obj.owner.refundBudget(cost, take);

		int maint = getMaintenanceCost(dsg, amount);
		cons.maintainCost += maint;
		cons.buildCost += cost;

		if(cons.started)
			obj.owner.modMaintenance(maint, MoT_Construction);

		deltaConstruction = true;
	}

	void removeSupportShipConstruction(Object& obj, int id, const Design@ dsg, uint amount) {
		int index = shipConsIndex(id);
		if(index == -1)
			return;
		ShipConstructible@ cons = cast<ShipConstructible>(queue[index]);
		if(cons is null)
			return;

		cons.removeSupports(dsg, amount, refund = obj);
		deltaConstruction = true;
	}

	void buildAsteroid(Object& obj, Asteroid@ asteroid, uint resId, Object@ constructFrom) {
		if(capabilities & CC_Asteroid == 0)
			return;

		Object@ pathFrom = obj;
		if(constructFrom !is null) {
			if(!allowConstructFrom(obj, constructFrom))
				return;
			@pathFrom = constructFrom;
		}
	
		const ResourceType@ res = getResource(resId);
		if(res is null)
			return;
	
		double cost = asteroid.getAvailableCostFor(resId);
		if(cost < 0.0)
			return;
		if(!asteroid.canDevelop(obj.owner))
			return;
	
		TradePath path(obj.owner);
		path.generate(getSystem(pathFrom.region), getSystem(asteroid.region));
		if(!path.isUsablePath)
			return;
		double costFactor = 1.0 + config::ASTEROID_COST_STEP * double(path.pathSize - 1);
	
		AsteroidConstructible cons(obj, asteroid, res, cost * costFactor);
		queueConstructible(obj, cons);
	}

	void buildConstruction(Object& obj, uint consId, Object@ objTarg = null, vec3d pointTarg = vec3d()) {
		const ConstructionType@ type = getConstructionType(consId);
		if(type is null)
			return;

		Targets targs(type.targets);
		if(targs.length != 0) {
			if(targs[0].type == TT_Object) {
				targs[0].filled = true;
				@targs[0].obj = objTarg;
			}
			else if(targs[0].type == TT_Point) {
				targs[0].filled = true;
				targs[0].point = pointTarg;
			}
		}

		if(!type.canBuild(obj, targs))
			return;

		ConstructionConstructible cons(obj, type, targs);
		queueConstructible(obj, cons);
	}

	void startTerraform(Object& obj, Planet@ planet, uint resId) {
		if(capabilities & CC_Terraform == 0)
			return;
		if(config::ENABLE_TERRAFORMING == 0)
			return;

		const ResourceType@ res = getResource(resId);
		if(res is null || !res.canTerraform(obj, planet))
			return;
		if(planet.owner !is obj.owner || obj is planet)
			return;
		if(planet.isTerraforming())
			return;

		double cost = res.terraformCost * terraformCost * constructionCost;
		double labor = res.terraformLabor;
		if(cost < 0.0)
			return;

		TradePath path(obj.owner);
		path.generate(getSystem(obj.region), getSystem(planet.region));
		if(!path.isUsablePath)
			return;


		double costFactor = 1.0 + config::TERRAFORM_COST_STEP * double(path.pathSize - 1);
		cost *= costFactor;
		labor *= costFactor;

		if(cost < 0.0)
			return;

		TerraformConstructible cons(obj, planet, res, cost, labor);
		queueConstructible(obj, cons);
	}

	void startBuildingConstruction(Object& obj, uint id, vec2i position) {
		auto@ type = getBuildingType(id);
		if(type is null)
			return;
		queueConstructible(obj, BuildingConstructible(obj, position, type));
	}

	void cancelBuildingConstruction(Object& obj, uint id, vec2i position) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			auto@ cons = cast<BuildingConstructible>(queue[i]);
			if(cons is null)
				continue;
			if(cons.position != position || cons.building.id != id)
				continue;
			cancelConstruction(obj, cons.id);
			break;
		}
	}

	void startRetrofitConstruction(Object& obj, Object@ fleet, int buildCost, double laborCost, int extraMaint, Object@ constructFrom) {
		if(capabilities & CC_Ship == 0) {
			fleet.stopFleetRetrofit(obj);
			return;
		}

		if(constructFrom !is null) {
			if(!allowConstructFrom(obj, constructFrom)) {
				fleet.stopFleetRetrofit(obj);
				return;
			}
		}

		RetrofitConstructible cons(obj, fleet, buildCost, laborCost, extraMaint);
		@cons.constructFrom = constructFrom;
		cons.buildCost *= constructionCost;
		if(!queueConstructible(obj, cons))
			fleet.stopFleetRetrofit(obj);
	}

	array<const Design@> retrofitCosts;
	void retrofitDesignCost(Object& obj, Object@ fleet, const Design@ dsg) {
		retrofitCosts.insertLast(dsg);
	}

	void retrofitDesignCostFinish(Object& obj, Object@ fleet) {
		for(uint i = 0, cnt = retrofitCosts.length; i < cnt; ++i) {
			auto@ dsg = retrofitCosts[i];
			if(!payDesignCosts(obj, dsg)) {
				for(uint n = 0; n < i; ++n)
					reverseDesignCosts(obj, dsg, cancel=false);
				for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
					auto@ cons = cast<RetrofitConstructible>(queue[i]);
					if(cons is null)
						continue;
					if(cons.fleet !is fleet)
						continue;
					cancelConstruction(obj, cons.id);
				}
				break;
			}

		}
		retrofitCosts.length = 0;
	}

	void buildSupport(Object& obj, uint id, const Design@ design, Object@ buildFor) {
		if(capabilities & CC_Supports == 0)
			return;
		if(supportDesign !is null)
			return;
		if(!payDesignCosts(obj, design))
			return;

		@supportDesign = design;
		@supportFor = buildFor;
		supportId = id;

		supportFor.supportBuildStarted(supportId, design, obj);
		deltaConstruction = true;
	}

	void transferBuildSupport(uint id, Object@ buildFor) {
		if(capabilities & CC_Supports == 0)
			return;
		if(supportId != id)
			return;

		@supportFor = buildFor;
	}

	void cancelBuildSupport(Object& obj, uint id) {
		if(capabilities & CC_Supports == 0)
			return;
		if(supportId != id)
			return;
		if(supportDesign !is null)
			reverseDesignCosts(obj, supportDesign, cancel=true);

		@supportDesign = null;
		@supportFor = null;
		deltaConstruction = true;
	}

	void modConstructionHPBonus(double mod) {
		hpBonus += mod;
	}

	double get_constructionHPBonus() {
		return hpBonus;
	}

	bool writeConstructionDelta(Message& msg) {
		if(!deltaConstruction) {
			if(queue.length > 0) {
				msg.write1();
				msg.write0();

				if(deltaStored) {
					msg.write1();
					msg << float(laborStorage);
					msg << float(storedLabor);
					msg.write0();
				}
				else {
					msg.write0();
				}

				queue[0].write(msg);
				return true;
			}
			if(deltaStored) {
				msg.write1();
				msg.write0();

				msg.write1();
				msg << float(laborStorage);
				msg << float(storedLabor);
				msg.write1();
				return true;
			}
			return false;
		}
		msg.write1();
		msg.write1();
		writeConstruction(msg);
		deltaConstruction = false;
		return true;
	}

	void destroyConstruction(Object& obj) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			queue[i].remove(obj);
		queue.length = 0;
	}

	void writeConstruction(Message& msg) {
		uint cnt = queue.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			queue[i].write(msg);
		
		msg << rally;
		if(rally) {
			msg.writeBit(rallyObj !is null);
			if(rallyObj !is null)
				msg << rallyObj;
			else
				msg.writeMedVec3(rallyPoint);
		}

		msg << capabilities;
		msg << repeating;
		msg.writeBit(supportDesign !is null);

		msg << float(LaborIncome);
		msg << float(LaborFactor);
		msg << float(DistributedLabor);
		msg << float(constructionCost);
		msg << canExport;
		msg << canImport;

		msg << supportSpeed;
		msg << shipCost;
		msg << orbitalCost;
		msg << float(terraformCost);
		msg << float(orbitalMaint);

		msg << float(laborStorage);
		msg << float(storedLabor);
	}
};
