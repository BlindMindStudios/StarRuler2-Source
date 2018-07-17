import resources;
import constructible;
import bool getCheatsEverOn() from "cheats";
#include "include/resource_constants.as"

enum ConstructionCapability {
	CC_Ship = 0x1,
	CC_Orbital = 0x2,
	CC_Asteroid = 0x4,
	CC_Terraform = 0x8,
	CC_Supports = 0x10,
};

tidy class Construction : Component_Construction {
	Constructible[] queue;
	uint capabilities = 0;
	bool buildingSupport = false;

	double LaborIncome = 0;
	double LaborFactor = 0;
	double DistributedLabor = 0;

	double laborStorage = 0;
	double storedLabor = 0;

	bool canExport = true;
	bool canImport = false;

	int nextID = 0;
	int supportSpeed = 100;
	int shipCost = 100;
	int orbitalCost = 100;
	double orbitalMaint = 1.0;
	double terraformCost = 1.0;
	double constructionCost = 1.0;
	
	bool rally = false;
	bool repeating = false;
	Object@ rallyObj;
	vec3d rallyPoint;

	double get_constructionCostMod() const {
		return constructionCost;
	}

	bool get_canBuildSupports() {
		return capabilities & CC_Supports != 0;
	}

	bool get_canBuildShips() {
		return capabilities & CC_Ship != 0;
	}

	bool get_canBuildOrbitals() {
		return capabilities & CC_Orbital != 0;
	}

	bool get_canBuildAsteroids() {
		return capabilities & CC_Asteroid != 0;
	}

	bool get_canTerraform() {
		return capabilities & CC_Terraform != 0;
	}

	bool get_canExportLabor() {
		return canExport;
	}

	bool get_canImportLabor() {
		return canImport;
	}

	double get_terraformCostMod() const {
		return terraformCost;
	}

	uint get_constructionCount() const {
		return queue.length;
	}

	bool get_constructingSupport() const {
		return buildingSupport;
	}

	double get_laborIncome() const {
		return LaborIncome * LaborFactor;
	}

	bool get_isRepeating() const {
		return repeating;
	}

	int constructibleIndex(int id) {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			if(queue[i].id == id)
				return i;
		return -1;
	}

	string get_constructionName(uint num) {
		if(num >= queue.length)
			return "(null)";
		return queue[num].name;
	}

	float get_constructionProgress() const {
		if(queue.length == 0)
			return -1.f;
		if(queue[0].totalLabor <= 0)
			return 1.f;
		return queue[0].curLabor / queue[0].totalLabor;
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

	double get_orbitalMaintenanceMod(const Object& obj) const {
		double cost = 1.0;
		cost *= clamp(orbitalMaint, 0.01f, 1.f);
		return cost;
	}

	void getConstructionQueue() {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i)
			yield(queue[i]);
	}

	void getConstructionQueue(uint limit) {
		for(uint i = 0, cnt = min(queue.length, limit); i < cnt; ++i)
			yield(queue[i]);
	}

	const Design@ get_constructionDesign() const {
		if(queue.length == 0)
			return null;
		const Constructible@ top = queue[0];
		if(top.dsg !is null)
			return top.dsg;
		return null;
	}

	void cancelConstruction(Object& obj, int id) {
		int index = constructibleIndex(id);
		if(index == -1)
			return;
		queue.removeAt(index);
	}

	void queueConstructible(Object& obj, Constructible@ cons) {
		cons.id = nextID++;
		queue.insertLast(cons);
		if(queue.length == 1)
			cons.started = true;
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
	}

	void buildOrbital(Object& obj, int type) {
		/*if(capabilities & CC_Orbital == 0)*/
		/*	return;*/
		/*const OrbitalDef@ def = getOrbitalDef(type);*/
		/*Constructible cons;*/
		/*cons.type = CT_Orbital;*/
		/*@cons.orbital = def;*/
		/*cons.buildCost = def.buildCost;*/
		/*cons.totalLabor = def.laborCost;*/
		/*cons.buildCost = ceil(double(cons.buildCost) * double(get_orbitalBuildCost(obj)) / 100.0);*/

		/*if(def !is null)*/
		/*	queueConstructible(obj, cons);*/
	}

	void buildFlagship(Object& obj, const Design@ design) {
		if(capabilities & CC_Ship == 0)
			return;
		if(design is null || design.hasTag(ST_IsSupport)) {
			error("Invalid design for ship construction at " + obj.name);
			return;
		}

		Constructible@ cons = Constructible(design);
		getBuildCost(design, cons.buildCost, cons.maintainCost, cons.totalLabor, 1);
		cons.buildCost = ceil(double(cons.buildCost) * double(get_shipBuildCost(obj)) / 100.0);
		queueConstructible(obj, cons);
	}
	
	void clearRally() {
		rally = false;
		@rallyObj = null;
	}
	
	void rallyTo(Object& obj, Object@ dest) {
		if(dest is null || !dest.valid || !dest.isVisibleTo(obj.owner))
			clearRally();
		rally = true;
		@rallyObj = dest;
		rallyPoint = dest.position;
	}
	
	void rallyTo(vec3d position) {
		rally = true;
		rallyPoint = position;
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

	double get_laborStorageCapacity() const {
		return laborStorage;
	}

	double get_currentLaborStored() const {
		return storedLabor;
	}

	void constructionTick(Object& obj, double time) {
		if(rally && rallyObj !is null && rallyObj.isVisibleTo(obj.owner))
			rallyPoint = rallyObj.position;
		
		if(laborIncome >= LABOR_ACHIEVE_THRESH && obj.owner is playerEmpire && !getCheatsEverOn())
			unlockAchievement("ACH_LABOR200");
	}

	void readConstructionDelta(Message& msg) {
		if(msg.readBit()) {
			readConstruction(msg);
		}
		else {
			if(msg.readBit()) {
				laborStorage = msg.read_float();
				storedLabor = msg.read_float();
				if(msg.readBit())
					return;
			}

			if(queue.length == 0)
				queue.length = 1;
			queue[0].read(msg);
		}
	}
	
	void readCommon(Message& msg) {
	}

	void readConstruction(Message& msg) {
		uint cnt = msg.readSmall();
		queue.length = cnt;

		for(uint i = 0; i < cnt; ++i)
			queue[i].read(msg);
		if(cnt > 0)
			nextID = queue[cnt-1].id + 1;
		
		msg >> rally;
		if(rally) {
			if(msg.readBit()) {
				msg >> rallyObj;
				rallyPoint = rallyObj.position;
			}
			else {
				rallyPoint = msg.readMedVec3();
			}
		}

		msg >> capabilities;
		msg >> repeating;
		msg >> buildingSupport;

		LaborIncome = msg.read_float();
		LaborFactor = msg.read_float();
		DistributedLabor = msg.read_float();
		constructionCost = msg.read_float();
		msg >> canExport;
		msg >> canImport;

		msg >> supportSpeed;
		msg >> shipCost;
		msg >> orbitalCost;
		terraformCost = msg.read_float();
		orbitalMaint = msg.read_float();

		laborStorage = msg.read_float();
		storedLabor = msg.read_float();
	}
}
