import saving;
import systems;
import resources;
import planet_levels;
import statuses;
from resources import _tempResource;
import bool getCheatsEverOn() from "cheats";

tidy class NativeResource : Resource {
	TradePath@ path;

	int opCmp(const NativeResource@ other) const {
		return Resource::opCmp(other);
	}
};

const ResourceClass@ foodCls;
void init() {
	@foodCls = getResourceClass("Food");
}

tidy class ObjectResources : Component_Resources, Savable {
	int nextResourceID = 0;
	NativeResource@[] nativeResources;
	Resource@[] resources;
	Resource primaryResource;
	array<QueuedImport@>@ queuedImports;
	Resources availableResources;
	array<QueuedResource@>@ queuedExports;

	int[] pressures = array<int>(TR_COUNT, 0);
	int totalPressure = 0;

	bool deltaRes = false;
	bool deltaPath = false;
	bool resourcesEnabled = true;
	bool terraforming = false;
	double ResourceCheck = 1.0;
	float resEfficiency = 1.f;
	double resEfficiencyBonus = 0.0;
	double resVanishBonus = 0.0;

	int ExportDisabled = 0;
	int ImportDisabled = 0;

	uint ResourceModId = 0;
	uint ResourceLevel = 999;

	locked_Civilian civilian;
	double civilianTimer = 200.0;
	
	ObjectResources() {}
	
	void save(SaveFile& file) {
		file << ExportDisabled;
		file << ImportDisabled;

		uint cnt = nativeResources.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			nativeResources[i].save(file);
			nativeResources[i].type.nativeSave(nativeResources[i], file);
		}

		cnt = resources.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			resources[i].save(file);
			if(resources[i].usable)
				resources[i].type.save(resources[i], file);
		}

		cnt = 0;
		if(queuedExports !is null)
			cnt = queuedExports.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << queuedExports[i];

		cnt = 0;
		if(queuedImports !is null)
			cnt = queuedImports.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << queuedImports[i];

		availableResources.save(file);

		file << nextResourceID;
		file << ResourceModId;
		file << ResourceLevel;
		file << resourcesEnabled;
		file << deltaPath;
		file << deltaRes;
		file << terraforming;
		file << resEfficiency;
		file << resEfficiencyBonus;
		file << resVanishBonus;

		for(uint i = 0; i < TR_COUNT; ++i)
			file << pressures[i];
		file << totalPressure;

		file << civilian.get();
		file << civilianTimer;
	}
	
	void load(SaveFile& file) {
		file >> ExportDisabled;
		file >> ImportDisabled;

		uint cnt = 0;
		file >> cnt;
		nativeResources.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			NativeResource r;
			r.load(file);

			@nativeResources[i] = r;
			@r.path = TradePath(r.origin.owner);
			r.type.nativeLoad(r, file);
		}

		if(cnt != 0)
			primaryResource.descFrom(nativeResources[0]);
		else
			primaryResource.descFrom(null);

		file >> cnt;
		resources.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			Resource r;
			r.load(file);
			if(r.usable || file < SV_0074)
				r.type.load(r, file);
			@resources[i] = r;
		}

		file >> cnt;
		if(cnt > 0) {
			@queuedExports = array<QueuedResource@>(cnt);
			for(uint i = 0; i < cnt; ++i) {
				@queuedExports[i] = QueuedResource();
				file >> queuedExports[i];
			}
		}

		file >> cnt;
		if(cnt > 0) {
			@queuedImports = array<QueuedImport@>(cnt);
			for(uint i = 0; i < cnt; ++i) {
				@queuedImports[i] = QueuedImport();
				file >> queuedImports[i];
			}
		}

		availableResources.load(file);

		file >> nextResourceID;
		file >> ResourceModId;
		file >> ResourceLevel;
		file >> resourcesEnabled;
		file >> deltaPath;
		file >> deltaRes;
		file >> terraforming;

		file >> resEfficiency;
		file >> resEfficiencyBonus;
		file >> resVanishBonus;
		for(uint i = 0; i < TR_COUNT; ++i)
			file >> pressures[i];
		file >> totalPressure;

		if(file >= SV_0048) {
			civilian.set(cast<Civilian>(file.readObject()));
			file >> civilianTimer;
		}
		else
			civilianTimer = randomd(0.0, 180.0);
	}

	void resourcesPostLoad(Object& obj) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			TradePath@ path = nativeResources[i].path;
			Resource@ r = nativeResources[i];

			if(r.exportedTo !is null) {
				@path.origin = getSystem(obj.region);
				@path.goal = getSystem(r.exportedTo.region);
			}
		}
	}

	void setResourceLevel(Object& obj, uint level, bool wasManual) {
		ResourceLevel = level;
		checkResources(obj, wasManual);
		++ResourceModId;
	}

	void modPressure(uint resource, int amount) {
		if(resource >= TR_COUNT)
			return;
		pressures[resource] += amount;
		totalPressure += amount;
	}

	int get_resourcePressure(uint resource) const {
		if(resource >= TR_COUNT)
			return 0;
		return pressures[resource];
	}

	uint get_resourcesProducing(uint resource) {
		if(resource >= TR_COUNT)
			return 0;
		uint amount = 0;
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			if(resources[i].type.tilePressure[resource] > 0.001f)
				++amount;
		}
		return amount;
	}

	int get_totalResourcePressure() const {
		return totalPressure;
	}

	uint get_resourceModID() {
		return ResourceModId;
	}

	void bumpResourceModId() {
		ResourceModId++;
	}

	void getNativeResources(Player& pl, const Object& obj) {
		Empire@ plEmp = pl.emp;
		if(plEmp is obj.owner || pl == SERVER_PLAYER) {
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
				yield(nativeResources[i]);
		}
		else {
			Resource@ res = _tempResource();
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
				res = nativeResources[i];
				@res.exportedTo = null;

				if(queuedExports !is null) {
					for(uint n = 0, ncnt = queuedExports.length; n < ncnt; ++n) {
						QueuedResource@ q = queuedExports[n];
						if(q.forEmpire is plEmp && res.id == q.id)
							@res.exportedTo = q.to;
					}
				}

				yield(res);
			}
		}
	}

	void getAvailableResources() {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			yield(resources[i]);
	}

	Civilian@ getAssignedCivilian() {
		return civilian.get();
	}

	void setAssignedCivilian(Civilian@ civ) {
		civilian.set(civ);
	}

	double getCivilianTimer() {
		return civilianTimer;
	}

	void setCivilianTimer(double time) {
		civilianTimer = time;
	}

	uint getUniqueFoodCount(int modBy = 0) {
		uint uniques = 0;
		for(uint i = 0, cnt = availableResources.length; i < cnt; ++i) {
			if(getResource(availableResources.types[i]).cls is foodCls) {
				int amt = availableResources.amounts[i] + modBy;
				if(amt > 0)
					uniques += 1;
			}
		}

		return uniques;
	}

	uint getFoodCount() {
		uint count = 0;
		for(uint i = 0, cnt = availableResources.length; i < cnt; ++i) {
			if(getResource(availableResources.types[i]).cls is foodCls)
				count += availableResources.amounts[i];
		}
		return count;
	}

	uint getAvailableOfTier(uint tier) {
		uint count = 0;
		for(uint i = 0, cnt = availableResources.length; i < cnt; ++i) {
			auto@ res = getResource(availableResources.types[i]);
			if(res.mode == RM_NonRequirement)
				continue;
			if(res.level == tier)
				count += availableResources.amounts[i];
		}
		return count;
	}

	Object@ get_availableResourceOrigin(uint index) const {
		if(index >= resources.length)
			return null;
		return resources[index].origin;
	}

	void redirectAllImports(Object& obj, Object@ toObject) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			auto@ res = resources[i];
			if(res.origin is null)
				continue;
			if(res.origin is obj)
				continue;
			if(res.origin.owner !is obj.owner)
				continue;

			res.origin.exportResourceByID(res.id, toObject);
		}
	}

	double pressureFromAsteroids(Object& obj, uint type) {
		double pres = 0.0;
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Object@ source = resources[i].origin;
			if(source !is null && source.isAsteroid)
				pres += resources[i].type.tilePressure[type];
		}
		return pres;
	}

	void getImportedResources(const Object& obj) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			if(resources[i].origin is null || obj !is resources[i].origin)
				yield(resources[i]);
	}
	
	bool get_hasAutoImports(Player& pl, const Object& obj) {
		if(queuedImports is null)
			return false;
		Empire@ plEmp = pl.emp;
		if(pl == SERVER_PLAYER)
			@plEmp = obj.owner;
		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i)
			if(queuedImports[i].origin is null && (plEmp is null || plEmp is queuedImports[i].forEmpire))
				return true;
		return false;
	}

	uint getTradedResourceCount() const {
		uint tradedNative = 0;
		uint usableNative = 0;
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(!nativeResources[i].usable)
				continue;
			++usableNative;
			if(nativeResources[i].exportedTo !is null)
				++tradedNative;
		}

		return (resources.length - (usableNative - tradedNative)) + tradedNative;
	}

	void getAllResources(Player& pl, const Object& obj) {
		Empire@ emp = pl.emp;
		if(emp is obj.owner || pl == SERVER_PLAYER) {
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
				yield(nativeResources[i]);
			for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
				if(obj !is resources[i].origin)
					yield(resources[i]);
			}
		}
		else {
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
				yield(nativeResources[i]);
		}
		
		if(queuedImports !is null) {
			for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
				if(queuedImports[i].forEmpire is emp)
					yield(queuedImports[i]);
			}
		}
	}

	void getQueuedImports(Player& pl, const Object& obj) {
		Empire@ emp = pl.emp;
		if(queuedImports !is null) {
			for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
				if(queuedImports[i].forEmpire is emp)
					yield(queuedImports[i]);
			}
		}
	}

	void getQueuedImportsFor(const Object& obj, Empire@ emp) {
		if(queuedImports !is null) {
			for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
				if(queuedImports[i].forEmpire is emp)
					yield(queuedImports[i]);
			}
		}
	}

	void getResourcesFor(const Object& obj, Empire@ emp) {
		if(emp is obj.owner) {
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
				yield(nativeResources[i]);
			for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
				if(obj !is resources[i].origin)
					yield(resources[i]);
			}
		}
		else {
			for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
				yield(nativeResources[i]);
		}
		
		if(queuedImports !is null) {
			for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
				if(queuedImports[i].forEmpire is emp)
					yield(queuedImports[i]);
			}
		}
	}

	void getResourceAmounts() {
		yield(availableResources);
	}

	void modDummyResource(Object& obj, uint resource, int amount, bool manual = false) {
		const ResourceType@ type = getResource(resource);
		if(type is null)
			return;
		availableResources.modAmount(type, amount);
		++ResourceModId;
		deltaRes = true;
		checkResources(obj, manual);
	}

	void createResource(Object& obj, uint resource) {
		addResource(obj, resource);
	}

	int addResource(Object& obj, uint resource) {
		auto@ type = getResource(resource);
		if(type is null)
			return -1;

		NativeResource r;
		r.id = nextResourceID++;
		@r.type = type;
		@r.origin = obj;
		r.data.length = r.type.hooks.length;
		r.usable = resourcesEnabled && ResourceLevel >= r.type.level;
		@r.path = TradePath(obj.owner);

		nativeResources.insertLast(r);
		r.type.onGenerate(obj, r);
		if(r.usable) {
			obj.addAvailableResource(obj, r.id, r.type.id, true);
			if(r.type.vanishMode != VM_Never)
				obj.setAvailableResourceVanish(obj, r.id, r.vanishTime);
		}
		deltaRes = true;
		++ResourceModId;
		checkResources(obj);
		nativeResources.sortDesc();
		primaryResource.descFrom(nativeResources[0]);

		return r.id;
	}

	uint getNativeIndex(int id) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id)
				return i;
		}
		return uint(-1);
	}

	void startTerraform(Object& obj) {
		terraforming = true;
		deltaRes = true;
		checkResources(obj, true);
	}

	void stopTerraform(Object& obj) {
		terraforming = false;
		deltaRes = true;
		checkResources(obj, true);
	}

	bool isTerraforming() {
		return terraforming;
	}

	void terraformTo(Object& obj, uint resId) {
		Empire@ owner = obj.owner;
		if(owner.valid && !getCheatsEverOn()) {
			if(owner is playerEmpire)
				unlockAchievement("ACH_TERRAFORM");
			if(mpServer && owner.player !is null)
				clientAchievement(owner.player, "ACH_TERRAFORM");
		}
	
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(!nativeResources[i].type.artificial)
				obj.removeResource(nativeResources[i].id);
		}
		obj.addResource(resId);

		auto@ barrenStatus = getStatusType("Barren");
		if(barrenStatus !is null)
			obj.removeStatusType(barrenStatus.id);
		terraforming = false;
	}

	void removeResource(Object& obj, int id, bool wasManual = false) {
		NativeResource@ r;
		uint index = 0;
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id) {
				@r = nativeResources[i];
				index = i;
				break;
			}
		}

		if(r is null)
			return;

		if(r.exportedTo !is null) {
			clearLines(r, r.path, obj, r.exportedTo);
			r.exportedTo.removeAvailableResource(obj, r.id, wasManual);
		}
		else {
			if(r.usable)
				obj.removeAvailableResource(obj, r.id, wasManual);
		}

		if(queuedExports !is null) {
			for(int i = queuedExports.length - 1; i >= 0; --i) {
				auto@ q = queuedExports[i];
				if(q.to !is null)
					q.to.removeQueuedImport(q.forEmpire, obj, q.id);
				queuedExports.removeAt(i);
			}
			
			if(queuedExports.length == 0)
				@queuedExports = null;
		}

		r.type.onDestroy(obj, r);
		nativeResources.removeAt(index);

		checkResources(obj);
		++ResourceModId;
		deltaRes = true;
		deltaPath = true;
	}

	void setResourceDisabled(Object& obj, int nativeId, bool disabled, bool wasManual) {
		Resource@ r;
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == nativeId) {
				@r = nativeResources[i];
				break;
			}
		}

		if(r !is null) {
			if(disabled)
				++r.disabled;
			else if(r.disabled > 0)
				--r.disabled;
			checkResources(obj, wasManual);
			deltaRes = true;
		}
	}

	void setResourceLocked(int nativeId, bool locked) {
		Resource@ r;
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == nativeId) {
				@r = nativeResources[i];
				break;
			}
		}

		if(r !is null)
			r.locked = locked;
	}

	void disableResources(Object& obj) {
		resourcesEnabled = false;
		checkResources(obj);
	}

	void enableResources(Object& obj) {
		if(!resourcesEnabled) {
			resourcesEnabled = true;
			checkResources(obj);
			if(obj.owner !is null)
				obj.owner.checkAutoImport(obj);
		}
	}

	uint getResourceTargetLevel(Object& obj) {
		//Check planet levels
		int maxPlanetLevel= getMaxPlanetLevel(obj);
		for(uint i = 1, cnt = maxPlanetLevel; i <= cnt; ++i) {
			const PlanetLevel@ lvl = getPlanetLevel(obj, i);
			if(lvl !is null && !lvl.reqs.satisfiedBy(availableResources))
				return i-1;
		}
		return maxPlanetLevel;
	}

	bool get_areResourcesEnabled() {
		return resourcesEnabled;
	}

	uint get_nativeResourceCount() {
		return nativeResources.length;
	}

	uint get_nativeResourceType(uint i) {
		if(i >= nativeResources.length)
			return uint(-1);
		return nativeResources[i].type.id;
	}

	int get_nativeResourceId(uint i) {
		if(i >= nativeResources.length)
			return -1;
		return nativeResources[i].id;
	}

	uint get_nativeResourceTotalLevel() const {
		uint level = 0;
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
			level += nativeResources[i].type.level;
		return level;
	}

	uint get_nativeResourceByID(int id) const {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id)
				return nativeResources[i].type.id;
		}
		return uint(-1);
	}
	
	bool isPrimaryDestination(Object& obj, Object@ dest) {
		if(primaryResource.type is null)
			return false;
		if(primaryResource.exportedTo is dest)
			return true;
		if(obj is dest && primaryResource.exportedTo is null)
			return true;
		return false;
	}

	uint get_primaryResourceType() const {
		if(primaryResource.type is null)
			return uint(-1);
		return primaryResource.type.id;
	}

	uint get_primaryResourceLevel() const {
		if(primaryResource.type is null)
			return 0;
		return primaryResource.type.level;
	}

	uint get_primaryResourceLimitLevel(const Object& obj) const {
		if(primaryResource.type is null)
			return 0;
		if(primaryResource.type.limitlessLevel)
			return getMaxPlanetLevel(obj.levelChain);
		return primaryResource.type.level;
	}

	int get_primaryResourceId() const {
		return primaryResource.id;
	}

	bool get_primaryResourceUsable() const {
		return primaryResource.usable;
	}

	bool get_primaryResourceLocked() const {
		return primaryResource.locked;
	}

	bool get_primaryResourceExported() const {
		return primaryResource.exportedTo !is null;
	}

	Object@ get_nativeResourceDestination(Player& pl, const Object& obj, uint i) {
		if(i >= nativeResources.length)
			return null;
		Resource@ r = nativeResources[i];

		//Find the current export
		Empire@ plEmp = pl.emp;
		if(r.exportedTo !is null && (plEmp is obj.owner || pl == SERVER_PLAYER))
			return nativeResources[i].exportedTo;

		//Try to find a queued export
		if(queuedExports !is null) {
			for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
				QueuedResource@ q = queuedExports[i];
				if(q.forEmpire is plEmp && r.id == q.id)
					return q.to;
			}
		}
		return null;
	}

	Object@ getNativeResourceDestinationByID(const Object& obj, Empire@ emp, int id) {
		uint index = getNativeIndex(id);
		return getNativeResourceDestination(obj, emp, index);
	}

	Object@ getNativeResourceDestination(const Object& obj, Empire@ emp, uint i) {
		if(i >= nativeResources.length)
			return null;
		Resource@ r = nativeResources[i];

		//Find the current export
		if(r.exportedTo !is null && emp is obj.owner)
			return nativeResources[i].exportedTo;

		//Try to find a queued export
		if(queuedExports !is null) {
			for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
				QueuedResource@ q = queuedExports[i];
				if(q.forEmpire is emp && r.id == q.id)
					return q.to;
			}
		}

		return null;
	}

	bool get_nativeResourceUsable(uint i) {
		if(i >= nativeResources.length)
			return false;
		return nativeResources[i].usable;
	}

	bool getNativeResourceUsableByID(int id) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id)
				return nativeResources[i].usable;
		}
		return false;
	}

	bool get_nativeResourceLocked(Player& pl, Object& obj, uint i) {
		Empire@ forEmp = pl.emp;
		if(pl == SERVER_PLAYER)
			@forEmp = obj.owner;
		if(i >= nativeResources.length)
			return false;
		auto@ r = nativeResources[i];
		if(forEmp is obj.owner)
			return r.locked;
		if(queuedExports !is null) {
			for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
				QueuedResource@ q = queuedExports[i];
				if(q.forEmpire is forEmp && r.id == q.id)
					return q.locked;
			}
		}
		return false;
	}

	bool hasImportedResources(const Object& obj) const {
		if(resources.length == 0)
			return false;
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			if(obj !is resources[i].origin)
				return true;
		}
		return false;
	}

	uint getImportsOfClass(Player& pl, const Object& obj, uint clsId) const {
		const ResourceClass@ cls = getResourceClass(clsId);
		if(cls is null)
			return 0;

		uint count = 0;
		Empire@ emp = pl.emp;
		if(emp is obj.owner) {
			for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
				if(resources[i].type.cls is cls)
					count += 1;
			}
		}

		if(queuedImports !is null) {
			for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
				const QueuedImport@ imp = queuedImports[i];
				if(imp.forEmpire is emp && imp.type.cls is cls)
					count += 1;
			}
		}

		return count;
	}

	uint get_availableResourceCount() const {
		return resources.length;
	}

	uint get_usableResourceCount() const {
		uint amt = 0;
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			if(resources[i].usable)
				amt += 1;
		}
		return amt;
	}

	uint get_availableResourceType(uint index) const {
		if(index >= resources.length)
			return uint(-1);
		return resources[index].type.id;
	}

	bool get_availableResourceUsable(uint index) const {
		if(index >= resources.length)
			return false;
		return resources[index].usable;
	}

	bool isResourceAvailable(uint id) const {
		return availableResources.getAmount(getResource(id)) != 0;
	}

	uint getAvailableResourceAmount(uint id) const {
		return availableResources.getAmount(getResource(id));
	}

	void exportResource(Player& pl, Object& obj, uint index, Object@ to) {
		if(pl == SERVER_PLAYER)
			exportResource(obj, obj.owner, index, to);
		else
			exportResource(obj, pl.emp, index, to);
	}

	void exportResourceByID(Player& pl, Object& obj, int id, Object@ to) {
		uint index = getNativeIndex(id);
		if(pl == SERVER_PLAYER)
			exportResource(obj, obj.owner, index, to);
		else
			exportResource(obj, pl.emp, index, to);
	}

	void exportResource(Object& obj, Empire@ forEmpire, uint index, Object@ to) {
		if(to !is null && !to.hasResources)
			return;
		if(index >= nativeResources.length)
			return;
		if(to !is null && (to.region is null || obj.region is null))
			return;

		//If this is ordered by not our owner, we queue it
		if(forEmpire !is obj.owner) {
			queueExportResource(forEmpire, obj, index, to);
			return;
		}
		else {
			NativeResource@ r = nativeResources[index];
			if(r.locked)
				return;
		}

		//If this is ordered to something by a different owner, we queue it
		if(to !is null && obj.owner !is to.owner) {
			queueExportResource(forEmpire, obj, index, to);
			@to = null;
		}
		else {
			//Remove old queues
			queueExportResource(forEmpire, obj, index, null);
		}

		_exportResource(obj, index, to, true);
	}
	
	string getDisabledReason(Object& obj, int id) {
		uint index = getNativeIndex(id);
		if(index >= nativeResources.length)
			return "Not present";
		auto@ r = nativeResources[index];
		if(!r.type.exportable)
			return "";
		auto@ to = r.exportedTo;
		if(ExportDisabled != 0)
			return locale::EXPBLOCK_DISABLED;
		if((to !is null && to.region is null) || obj.region is null)
			return locale::EXPBLOCK_DEEPSPACE;
		if(!obj.owner.valid) {
			if(obj.isAsteroid)
				return locale::EXPBLOCK_UNMINED;
			else if(obj.isPlanet)
				return locale::EXPBLOCK_UNCOLONIZED;
			else
				return locale::EXPBLOCK_UNOWNED;
		}
		if(to !is null && obj.owner !is to.owner)
			return locale::EXPBLOCK_UNOWNED;
		if(obj.hasSurfaceComponent) {
			if(obj.population < 1.0)
				return format(locale::EXPBLOCK_POP, uint(1));
			else if(obj.resourceLevel < r.type.level)
				return format(locale::EXPBLOCK_LOWLEVEL, r.type.level);
			else if(obj.population < getPlanetLevelRequiredPop(obj, r.type.level))
				return format(locale::EXPBLOCK_POP, uint(getPlanetLevelRequiredPop(obj, r.type.level)));
		}
		TradePath@ path = r.path;
		if(path.goal !is null && (!path.valid || !path.isUsablePath))
			return locale::EXPBLOCK_DISCONNECTED;
		if(!r.usable)
			return locale::EXPBLOCK_UNUSABLE;
		return "";
	}

	void _exportResource(Object& obj, uint index, Object@ to, bool wasManual = false) {
		//Remove from our current export
		NativeResource@ r = nativeResources[index];
		TradePath@ path = r.path;
		if((!r.type.exportable || ExportDisabled != 0) && to !is null)
			return;
		if(r.exportedTo is null && to is null)
			return;

		if(r.exportedTo !is null) {
			r.exportedTo.removeAvailableResource(obj, r.id, wasManual);
			if(r.usable)
				clearLines(r, path, obj, r.exportedTo);
		}
		else {
			if(r.usable)
				obj.removeAvailableResource(obj, r.id, wasManual);
		}

		//Add to our new export
		if(to !is null) {
			if(!to.valid)
				return;
			//Must export to things in regions
			Region@ fromRegion = obj.region, toRegion = to.region;
			if(fromRegion is null || toRegion is null)
				return;
			
			to.addAvailableResource(obj, r.id, r.type.id, r.usable);
			if(r.type.vanishMode != VM_Never)
				to.setAvailableResourceVanish(obj, r.id, r.vanishTime);

			@r.exportedTo = to;
			path.clear();
			@path.origin = getSystem(fromRegion);
			@path.goal = getSystem(toRegion);

			civilianTimer = randomd(0.0, 3.0 * 60.0);
		}
		else {
			if(r.usable) {
				obj.addAvailableResource(obj, r.id, r.type.id, true);
				if(r.type.vanishMode != VM_Never)
					obj.setAvailableResourceVanish(obj, r.id, r.vanishTime);
			}

			@r.exportedTo = null;
			path.clear();
		}

		//Check resource enabled state
		checkResources(obj);
		++ResourceModId;
		deltaRes = true;
		deltaPath = true;
	}

	void queueExportResource(Empire@ forEmpire, Object& obj, uint index, Object@ to, bool locked = false) {
		//Find existing
		Resource@ r = nativeResources[index];
		QueuedResource@ q;
		if(queuedExports !is null) {
			for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
				if(queuedExports[i].forEmpire is forEmpire && queuedExports[i].id == r.id) {
					@q = queuedExports[i];
					break;
				}
			}
		}

		if(to !is null) {
			if(q is null) {
				@q = QueuedResource();
				q.id = r.id;
				@q.forEmpire = forEmpire;
				if(queuedExports is null)
					@queuedExports = array<QueuedResource@>();
				queuedExports.insertLast(q);
			}
			else {
				if(q.locked)
					return;
				if(q.to !is null)
					q.to.removeQueuedImport(forEmpire, obj, r.id);
			}

			@q.to = to;
			q.locked = locked;
			q.to.addQueuedImport(forEmpire, obj, r.id, r.type.id);

			deltaRes = true;
			++ResourceModId;
		}
		else if(q !is null) {
			if(q.locked)
				return;
			if(q.to !is null)
				q.to.removeQueuedImport(forEmpire, obj, r.id);
			if(queuedExports !is null) {
				queuedExports.remove(q);
				if(queuedExports.length == 0)
					@queuedExports = null;
			}

			deltaRes = true;
			++ResourceModId;
		}
	}

	void addQueuedImport(Object& obj, Empire@ fromEmpire, Object@ from, int id, uint resource) {
		QueuedImport r;
		@r.forEmpire = fromEmpire;
		r.id = id;
		@r.type = getResource(resource);
		@r.origin = from;
		@r.exportedTo = obj;
		r.usable = false;
		if(queuedImports is null)
			@queuedImports = array<QueuedImport@>();
		queuedImports.insertLast(r);
		++ResourceModId;

		if(r.type is null)
			return;

		deltaRes = true;
	}

	void removeQueuedImport(Object& obj, Empire@ fromEmpire, Object@ from, int id) {
		_removeQueuedImport(obj, fromEmpire, from, id);
	}

	bool _removeQueuedImport(Object& obj, Empire@ fromEmpire, Object@ from, int id) {
		if(queuedImports is null)
			return false;
	
		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
			QueuedImport@ r = queuedImports[i];
			if(r.forEmpire is fromEmpire && r.origin is from && r.id == id) {
				queuedImports.removeAt(i);
				deltaRes = true;
				if(queuedImports.length == 0)
					@queuedImports = null;
				++ResourceModId;
				return true;
			}
		}
		return false;
	}

	uint get_queuedImportCount() {
		return queuedImports is null ? 0 : queuedImports.length;
	}

	uint get_queuedImportType(Player& pl, Object& obj, uint i) {
		if(queuedImports is null || i >= queuedImports.length || pl.emp !is queuedImports[i].forEmpire)
			return uint(-1);
		return queuedImports[i].type.id;
	}

	Object@ get_queuedImportOrigin(Player& pl, Object& obj, uint i) {
		if(queuedImports is null || i >= queuedImports.length || pl.emp !is queuedImports[i].forEmpire)
			return null;
		return queuedImports[i].origin;
	}

	void addAvailableResource(Object& obj, Object@ from, int id, uint resource, bool usable) {
		if(from !is null && obj !is from && ImportDisabled != 0) {
			from.clearExportResource(id);
			return;
		}

		deltaRes = true;
		Resource r;
		r.id = id;
		@r.type = getResource(resource);
		@r.origin = from;
		r.data.length = r.type.hooks.length;
		r.usable = usable;
		if(obj is from)
			@r.exportedTo = null;
		else
			@r.exportedTo = obj;
		resources.insertLast(r);
		++ResourceModId;

		Empire@ fromOwner = from.owner;
		_removeQueuedImport(obj, fromOwner, from, id);

		if(usable)
			_addedResource(obj, r);

		if(obj.hasAutoImports)
			obj.owner.gotImportFor(obj, r.type.id);
	}

	void clearExportResource(Object& obj, int id) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id) {
				if(nativeResources[i].exportedTo !is null)
					_exportResource(obj, i, null, true);
				break;
			}
		}
	}

	void setExportEnabled(Object& obj, bool value) {
		if(value) {
			ExportDisabled--;
		}
		else {
			if(ExportDisabled == 0) {
				for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
					if(nativeResources[i].exportedTo !is null)
						_exportResource(obj, i, null);
			}
			ExportDisabled++;
		}
		++ResourceModId;
	}

	void setImportEnabled(Object& obj, bool value) {
		if(value) {
			ImportDisabled--;
		}
		else {
			if(ImportDisabled == 0) {
				for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
					Resource@ r = resources[i];
					if(r.origin !is null && r.origin !is obj)
						r.origin.clearExportResource(r.id);
				}
			}
			ImportDisabled++;
		}
		++ResourceModId;
	}
	
	Resource@ resourceFrom(Object@ from, int id) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			if(r.origin is from && r.id == id)
				return r;
		}
		return null;
	}

	void enableAvailableResource(Object& obj, Object@ from, int id) {
		Resource@ r = resourceFrom(from, id);
		if(r !is null && !r.usable) {
			++ResourceModId;
			deltaRes = true;
			r.usable = true;
			_addedResource(obj, r);
		}
	}

	void setAvailableResourceVanish(Object& obj, Object@ from, int id, double vanishTime) {
		Resource@ r = resourceFrom(from, id);
		if(r !is null) {
			if(int(r.vanishTime) != int(vanishTime))
				deltaRes = true;
			r.vanishTime = vanishTime;
		}
	}

	void _addedResource(Object& obj, Resource@ r) {
		availableResources.modAmount(r.type, +1);
		r.type.onAdd(obj, r);
		r.efficiency = r.origin.resourceEfficiency;
		deltaRes = true;
		++ResourceModId;

		Region@ reg = obj.region;
		if(reg !is null) {
			Territory@ terr = obj.region.getTerritory(obj.owner);
			if(terr !is null)
				r.type.onTerritoryAdd(obj, r, terr);
		}

		for(uint i = 0; i < TR_COUNT; ++i) {
			if(r.type.tilePressure[i] != 0) {
				int prs = max(round(float(r.type.tilePressure[i]) * float(r.efficiency)), 0.f);
				pressures[i] += prs;
				totalPressure += prs;
			}
		}

		uint affCnt = r.type.affinities.length;
		if(affCnt != 0 && obj.hasSurfaceComponent) {
			for(uint i = 0; i < affCnt; ++i)
				obj.addAffinity(r.type.affinities[i]);
		}
	}

	void _removedResource(Object& obj, Resource@ r) {
		availableResources.modAmount(r.type, -1);
		r.type.onRemove(obj, r);
		deltaRes = true;

		Region@ reg = obj.region;
		if(reg !is null) {
			Territory@ terr = obj.region.getTerritory(obj.owner);
			if(terr !is null)
				r.type.onTerritoryRemove(obj, r, terr);
		}

		for(uint i = 0; i < TR_COUNT; ++i) {
			if(r.type.tilePressure[i] != 0) {
				int prs = max(round(float(r.type.tilePressure[i]) * float(r.efficiency)), 0.f);
				pressures[i] -= prs;
				totalPressure -= prs;
			}
		}

		uint affCnt = r.type.affinities.length;
		if(affCnt != 0 && obj.hasSurfaceComponent) {
			for(uint i = 0; i < affCnt; ++i)
				obj.removeAffinity(r.type.affinities[i]);
		}
	}

	void destroyObjResources(Object& obj) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			NativeResource@ r = nativeResources[i];
			TradePath@ path = r.path;
			if(r.exportedTo !is null) {
				r.exportedTo.removeAvailableResource(obj, r.id);
				if(r.usable)
					clearLines(r, path, obj, r.exportedTo);
			}
			else if(r.usable) {
				removeAvailableResource(obj, obj, r.id);
			}
		}

		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			removeAvailableResource(obj, r.origin, r.id);
			--i; --cnt;
		}
	}

	void removeAvailableResource(Object& obj, Object@ from, int id, bool wasManual = false) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			if(r.origin is from && r.id == id) {
				++ResourceModId;
				deltaRes = true;
				if(r.usable) {
					_removedResource(obj, r);
					r.usable = false;
				}
				resources.removeAt(i);
				if(wasManual)
					checkResources(obj, true);
				break;
			}
		}
	}

	void disableAvailableResource(Object& obj, Object@ from, int id, bool wasManual = false) {
		Resource@ r = resourceFrom(from, id);
		if(r !is null && r.usable) {
			deltaRes = true;
			++ResourceModId;
			r.usable = false;
			_removedResource(obj, r);
			if(wasManual)
				checkResources(obj, true);
		}
	}

	void changeResourceTerritory(Object& obj, Territory@ prev, Territory@ next) {
		//Trigger any owner change hooks on resources
		uint resCnt = resources.length;
		for(uint i = 0; i < resCnt; ++i) {
			Resource@ r = resources[i];
			if(r.usable) {
				if(prev !is null)
					r.type.onTerritoryRemove(obj, r, prev);
				if(next !is null)
					r.type.onTerritoryAdd(obj, r, next);
			}
		}
	}

	void clearLines(Resource@ res, TradePath@ path, Object@ from, Object@ to) {
		uint cnt = path.pathSize;
		if(cnt == 0) {
			return;
		}
		else if(cnt == 1) {
			path.origin.object.removeTradePathing(-1, from, res.id);
		}
		else {
			for(uint i = 0; i < cnt-1; ++i) {
				SystemDesc@ node = path.pathNode[i];
				SystemDesc@ next = path.pathNode[i+1];
				node.object.removeTradePathing(next.index, from, res.id);
			}
		}
	}

	void updateLines(Resource@ res, TradePath@ path, Object@ from, Object@ to) {
		uint cnt = path.pathSize;
		if(cnt == 0) {
			return;
		}
		else if(cnt == 1) {
			path.origin.object.addTradePathing(-1, from, to, res.id, res.type.id);
		}
		else {
			for(uint i = 0; i < cnt-1; ++i) {
				SystemDesc@ node = path.pathNode[i];
				SystemDesc@ next = path.pathNode[i+1];
				node.object.addTradePathing(next.index, from, to, res.id, res.type.id);
			}
		}
	}

	void checkResources(Object& obj, bool wasManual = false) {
		//Unlock resources
		bool haveLocalEnableds = false;
		uint cnt = nativeResources.length;
		for(uint i = 0; i < cnt; ++i) {
			NativeResource@ r = nativeResources[i];
			//Check usability
			bool prev = r.usable;
			r.usable = resourcesEnabled && ResourceLevel >= r.type.level
				&& r.disabled == 0 && (!terraforming || r.type.artificial);
			r.efficiency = obj.resourceEfficiency;
			
			bool exporting = r.exportedTo !is null;

			//Check pathing
			if(exporting) {
				TradePath@ path = r.path;
				bool usablePath = path.isUsablePath;
				if(path.valid && !usablePath && prev)
					clearLines(r, path, obj, r.exportedTo);
				if(r.usable) {
					if(!usablePath) {
						if(path.goal is null)
							@path.goal = getSystem(r.exportedTo.region);
						if(path.origin is null)
							@path.origin = getSystem(obj.region);
						if(path.goal !is null && path.origin !is null) {
							path.generate();
							deltaPath = true;
						}
						if(path.isUsablePath)
							updateLines(r, path, obj, r.exportedTo);
					}
					if(!path.valid)
						r.usable = false;
				}
			}

			//Disable and enable
			if(r.usable && !prev) {
				++ResourceModId;
				deltaRes = true;
				if(r.exportedTo !is null) {
					r.exportedTo.enableAvailableResource(obj, r.id);
				}
				else {
					obj.addAvailableResource(obj, r.id, r.type.id, true);
					if(r.type.vanishMode != VM_Never)
						obj.setAvailableResourceVanish(obj, r.id, r.vanishTime);
					haveLocalEnableds = true;
				}
			}
			else if(prev && !r.usable) {
				++ResourceModId;
				deltaRes = true;
				if(r.exportedTo !is null) {
					r.exportedTo.disableAvailableResource(obj, r.id, wasManual);
				}
				else {
					obj.removeAvailableResource(obj, r.id, wasManual);
				}
			}

			if(exporting) {
				Empire@ otherOwner = r.exportedTo.owner;

				//Check if exporting to wrong owner
				if(otherOwner !is obj.owner) {
					//Cancel exports to foreign empires
					queueExportResource(obj.owner, obj, i, r.exportedTo, r.locked);
					_exportResource(obj, i, null);
					r.locked = false;
				}

				//Check if exporting to a destroyed object
				else if(!r.exportedTo.valid)
					_exportResource(obj, i, null);
			}
		}

		//Check if anything queued is now available again
		if(queuedExports !is null) {
			for(uint i = 0; queuedExports !is null &&  i < queuedExports.length; ++i) {
				QueuedResource@ q = queuedExports[i];
				if(q.forEmpire is obj.owner && q.to.owner is obj.owner) {
					//Find native resource index from id
					int rIndex = -1;
					for(uint n = 0, rcnt = nativeResources.length; n < rcnt; ++n) {
						if(nativeResources[n].id == q.id) {
							rIndex = int(n);
							break;
						}
					}

					queuedExports.removeAt(i);
					--i; --cnt;

					if(rIndex != -1) {
						_exportResource(obj, uint(rIndex), q.to);
						break;
					}
				}
			}
			
			//queuedExports can become null as a result of _exportResource
			if(queuedExports !is null && queuedExports.length == 0)
				@queuedExports = null;
		}

		if(nativeResources.length != 0)
			primaryResource.descFrom(nativeResources[0]);
		else
			primaryResource.descFrom(null);

		//Inform the surface if we have one
		if(wasManual && obj.hasSurfaceComponent)
			obj.onManualResourceRemoved();
		if(haveLocalEnableds)
			obj.owner.checkAutoImport(obj);
	}

	void modResourceEfficiencyBonus(double amt) {
		resEfficiencyBonus += amt;
	}

	float get_resourceEfficiency(const Object& obj) const {
		float eff = resEfficiency * (1.0 + resEfficiencyBonus);
		if(primaryResource.type !is null && primaryResource.type.level == 3)
			eff *= obj.owner.Tier3PressureFactor;
		return eff;
	}

	void set_resourceEfficiency(float val) {
		resEfficiency = val;
	}

	float get_resourceVanishRate() const {
		return 1.f / (1.f + resVanishBonus);
	}

	void modResourceVanishBonus(double val) {
		resVanishBonus += val;
		deltaRes = true;
	}

	void updateResourcePressures(Object& obj) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			if(!r.usable)
				continue;
			float prevEff = max(r.efficiency, 0.f);
			float newEff = max(r.origin.resourceEfficiency, 0.f);
			if(prevEff != newEff) {
				for(uint i = 0; i < TR_COUNT; ++i) {
					float prs = r.type.tilePressure[i];
					if(prs != 0.f) {
						int prevPrs = round(prs * prevEff);
						int newPrs = round(prs * newEff);
						pressures[i] += newPrs - prevPrs;
						totalPressure += newPrs - prevPrs;
					}
				}
				r.efficiency = newEff;

				if(abs(newEff - prevEff) >= 0.1)
					deltaRes = true;
			}
		}
	}

	bool get_exportEnabled() {
		return ExportDisabled == 0;
	}

	bool get_importEnabled() {
		return ImportDisabled == 0;
	}

	void changeResourceOwner(Object& obj, Empire@ prevOwner) {
		//Move path owners
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i)
			@nativeResources[i].path.forEmpire = obj.owner;

		//Remove any exports to other empires
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			NativeResource@ r = nativeResources[i];
			@r.path.forEmpire = obj.owner;
			if(r.exportedTo !is null && r.exportedTo.owner !is obj.owner) {
				//Add previous export as queued
				if(r.locked)
					queueExportResource(prevOwner, obj, i, r.exportedTo, r.locked);
				_exportResource(obj, i, null);
				r.locked = false;
			}
		}

		Territory@ prevTerr, newTerr;
		Region@ region = obj.region;
		if(region !is null) {
			@prevTerr = region.getTerritory(prevOwner);
			@newTerr = region.getTerritory(obj.owner);
		}

		uint resCnt = resources.length;
		for(uint i = 0; i < resCnt; ++i) {
			Resource@ r = resources[i];

			if(r.usable) {
				//Trigger owner change hooks on resources
				r.type.onOwnerChange(obj, r, prevOwner, obj.owner);

				//Trigger territory change hooks
				if(prevTerr !is null)
					r.type.onTerritoryRemove(obj, r, prevTerr);

				if(newTerr !is null)
					r.type.onTerritoryAdd(obj, r, newTerr);
			}
		}

		//Check if we should engage any queued exports
		if(queuedExports !is null) {
			for(uint i = 0; queuedExports !is null && i < queuedExports.length; ++i) {
				QueuedResource@ q = queuedExports[i];
				if(q.forEmpire is obj.owner && q.to.owner is obj.owner) {
					//Find native resource index from id
					int rIndex = -1;
					for(uint n = 0, rcnt = nativeResources.length; n < rcnt; ++n) {
						if(nativeResources[n].id == q.id) {
							rIndex = int(n);
							break;
						}
					}

					queuedExports.removeAt(i);
					--i;

					if(rIndex != -1) {
						_exportResource(obj, uint(rIndex), q.to);
					}
				}
			}
			
			if(queuedExports !is null && queuedExports.length == 0)
				@queuedExports = null;
		}

		if(obj.owner !is null)
			obj.owner.checkAutoImport(obj);
	}

	void changeResourceRegion(Object& obj, Region@ prevRegion, Region@ newRegion) {
		//Check territories
		Territory@ prevTerr, newTerr;
		Region@ region = obj.region;
		if(region !is null)
			@newTerr = region.getTerritory(obj.owner);
		if(prevRegion !is null)
			@prevTerr = prevRegion.getTerritory(obj.owner);

		if(prevTerr !is newTerr) {
			uint resCnt = resources.length;
			for(uint i = 0; i < resCnt; ++i) {
				Resource@ r = resources[i];

				//Trigger territory change hooks
				if(prevTerr !is null)
					r.type.onTerritoryRemove(obj, r, prevTerr);

				if(newTerr !is null)
					r.type.onTerritoryAdd(obj, r, newTerr);
			}
		}

		//Resource hooks
		uint resCnt = resources.length;
		for(uint i = 0; i < resCnt; ++i) {
			Resource@ r = resources[i];
			if(r.usable)
				r.type.onRegionChange(obj, r, prevRegion, newRegion);
		}
	}

	void resourceTick(Object& obj, double time) {
		//Periodic resource checks
		if(ResourceCheck <= 0.0) {
			ResourceCheck = randomd(1.0, 2.0);
			checkResources(obj);
			updateResourcePressures(obj);
		}
		else
			ResourceCheck -= time;

		//Vanish any native resources
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			Resource@ r = nativeResources[i];
			if(obj.owner is null || !obj.owner.valid)
				continue;
			r.type.nativeTick(obj, r, time);

			if(!r.usable)
				continue;
			switch(r.type.vanishMode) {
				case VM_WhenExported:
					if(r.exportedTo is null)
						continue;
				break;
				case VM_ExportedInCombat:
					if(r.exportedTo is null) {
						if(r.origin is null || !r.origin.inCombat)
							continue;
					}
					else {
						if(!r.exportedTo.inCombat)
							continue;
					}
				break;
				case VM_Always:
					break;
				case VM_Custom:
					if(!r.type.shouldVanish(obj, r))
						continue;
				break;
				default:
					continue;
			}

			int prevTime = r.vanishTime;
			if(r.exportedTo !is null) {
				float rate = r.exportedTo.resourceVanishRate;
				r.vanishTime += time * rate;
				r.exportedTo.setAvailableResourceVanish(obj, r.id, r.vanishTime);
			}
			else {
				r.vanishTime += time * get_resourceVanishRate();
				setAvailableResourceVanish(obj, obj, r.id, r.vanishTime);
			}
			if(prevTime != int(r.vanishTime))
				deltaRes = true;
			if(r.vanishTime >= r.type.vanishTime)
				obj.removeResource(r.id);
		}

		//Tick any resources with tick hooks
		uint resCnt = resources.length;
		for(uint i = 0; i < resCnt; ++i) {
			Resource@ r = resources[i];
			if(r.usable)
				r.type.onTick(obj, r, time);
		}

		//Deal with civilian trade
		civilianTimer += time;
	}

	void _writeRes(Message& msg) {
		msg << terraforming;
		msg << float(resVanishBonus);
		availableResources.write(msg);

		{
			uint cnt = nativeResources.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				nativeResources[i].write(msg);
		}

		{
			uint cnt = resources.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				resources[i].write(msg);
		}

		{
			uint cnt = queuedImports is null ? 0 : queuedImports.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				queuedImports[i].writeQueued(msg);
		}

		{
			uint cnt = queuedExports is null ? 0 : queuedExports.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				queuedExports[i].write(msg);
		}
	}

	void _writePath(Message& msg) {
		uint cnt = nativeResources.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			nativeResources[i].path.write(msg);
	}

	bool writeResourceDelta(Message& msg) {
		if(!deltaRes && !deltaPath)
			return false;

		msg.write1();
		if(deltaRes) {
			deltaRes = false;
			msg.write1();
			_writeRes(msg);
		}
		else {
			msg.write0();
		}

		if(deltaPath) {
			deltaPath = false;
			msg.write1();
			_writePath(msg);
		}
		else {
			msg.write0();
		}

		return true;
	}

	void writeResources(Message& msg) {
		_writeRes(msg);
		_writePath(msg);

		msg.writeBit(ImportDisabled != 0);
		if(ImportDisabled != 0)
			msg << ImportDisabled;
		msg.writeBit(ExportDisabled != 0);
		if(ExportDisabled != 0)
			msg << ExportDisabled;
	}
};
