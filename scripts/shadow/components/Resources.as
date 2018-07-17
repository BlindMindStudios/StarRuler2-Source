import resources;
import systems;
import planet_levels;
from resources import _tempResource;

tidy class ObjectResources : Component_Resources {
	TradePath@[] resourcePaths;
	Object@[] pathsActive;
	Resource[] nativeResources;
	Resource primaryResource;
	Resource[] resources;
	QueuedImport[] queuedImports;
	Resources availableResources;
	array<QueuedResource@> queuedExports;

	int ExportDisabled = 0;
	int ImportDisabled = 0;
	uint ResourceModId = 0;
	bool terraforming = false;
	double resVanishBonus = 0.0;

	ObjectResources() {
	}

	bool isTerraforming() {
		return terraforming;
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

	bool get_nativeResourceUsable(uint i) {
		if(i >= nativeResources.length)
			return false;
		return nativeResources[i].usable;
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

	bool get_nativeResourceLocked(Player& pl, Object& obj, uint i) {
		Empire@ forEmp = pl.emp;
		if(pl == SERVER_PLAYER)
			@forEmp = obj.owner;
		if(i >= nativeResources.length)
			return false;
		auto@ r = nativeResources[i];
		if(forEmp is obj.owner)
			return r.locked;
		for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
			QueuedResource@ q = queuedExports[i];
			if(q.forEmpire is forEmp && r.id == q.id)
				return q.locked;
		}
		return false;
	}

	float get_resourceVanishRate() const {
		return 1.f / (1.f + resVanishBonus);
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

	Object@ get_nativeResourceDestination(Player& pl, const Object& obj, uint i) {
		if(i >= nativeResources.length)
			return null;
		Empire@ emp = pl.emp;
		Resource@ r = nativeResources[i];

		//Find the current export
		if(r.exportedTo !is null && (emp is obj.owner || pl == SERVER_PLAYER))
			return r.exportedTo;

		//Try to find a queued export
		for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
			QueuedResource@ q = queuedExports[i];
			if(q.forEmpire is emp && r.id == q.id)
				return q.to;
		}
		return null;
	}

	Object@ getNativeResourceDestination(const Object& obj, Empire@ emp, uint i) {
		if(i >= nativeResources.length)
			return null;
		Resource@ r = nativeResources[i];

		//Find the current export
		if(r.exportedTo !is null && emp is obj.owner)
			return nativeResources[i].exportedTo;

		//Try to find a queued export
		for(uint i = 0, cnt = queuedExports.length; i < cnt; ++i) {
			QueuedResource@ q = queuedExports[i];
			if(q.forEmpire is emp && r.id == q.id)
				return q.to;
		}

		return null;
	}

	uint getNativeIndex(int id) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			if(nativeResources[i].id == id)
				return i;
		}
		return uint(-1);
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
		if(to !is null) {
			//NOTE: Approximation of trade rules
			auto@ src = obj.region;
			auto@ dst = to.region;
			if(src !is null && dst !is null && src !is dst &&
				src.getTerritory(obj.owner) !is dst.getTerritory(obj.owner))
			return locale::EXPBLOCK_DISCONNECTED;
		}
		if(!r.usable)
			return locale::EXPBLOCK_UNUSABLE;
		return "";
	}

	void getAvailableResources() {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			yield(resources[i]);
	}

	Object@ get_availableResourceOrigin(uint index) const {
		if(index >= resources.length)
			return null;
		return resources[index].origin;
	}

	void getImportedResources(const Object& obj) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i)
			if(resources[i].origin is null || obj !is resources[i].origin)
				yield(resources[i]);
	}
	
	bool get_hasAutoImports(Player& pl, Object& obj) {
		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i)
			if(queuedImports[i].origin is null && pl.emp is queuedImports[i].forEmpire)
				return true;
		return false;
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
		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
			if(queuedImports[i].forEmpire is emp)
				yield(queuedImports[i]);
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

	uint get_queuedImportCount() {
		return queuedImports.length;
	}

	uint get_queuedImportType(Player& pl, Object& obj, uint i) {
		if(pl.emp !is queuedImports[i].forEmpire)
			return uint(-1);
		return queuedImports[i].type.id;
	}

	Object@ get_queuedImportOrigin(Player& pl, Object& obj, uint i) {
		if(pl.emp !is queuedImports[i].forEmpire)
			return null;
		return queuedImports[i].origin;
	}

	void getResourceAmounts() {
		yield(availableResources);
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

		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i) {
			const QueuedImport@ imp = queuedImports[i];
			if(imp.forEmpire is emp && imp.type.cls is cls)
				count += 1;
		}

		return count;
	}

	bool get_hasAutoImports(Player& pl, const Object& obj) {
		for(uint i = 0, cnt = queuedImports.length; i < cnt; ++i)
			if(queuedImports[i].origin is null && pl.emp is queuedImports[i].forEmpire)
				return true;
		return false;
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

	Resource@ resourceFrom(Object@ from, int id) {
		for(uint i = 0, cnt = resources.length; i < cnt; ++i) {
			Resource@ r = resources[i];
			if(r.origin is from && r.id == id)
				return r;
		}
		return null;
	}

	void setAvailableResourceVanish(Object& obj, Object@ from, int id, double vanishTime) {
		Resource@ r = resourceFrom(from, id);
		if(r !is null)
			r.vanishTime = vanishTime;
	}

	bool get_exportEnabled() {
		return ExportDisabled == 0;
	}

	bool get_importEnabled() {
		return ImportDisabled == 0;
	}

	void clearLines(Resource@ res, TradePath@ path, Object@ from, Object@ to) {
		uint cnt = path.pathSize;
		if(cnt == 1) {
			path.origin.object.removeTradePathing(-1, from, res.id);
		}
		else {
			for(uint i = 0; i < cnt-1; ++i) {
				SystemDesc@ node = path.pathNode[i];
				SystemDesc@ next = path.pathNode[i+1];;
				node.object.removeTradePathing(next.index, from, res.id);
			}
		}
	}

	void updateLines(Resource@ res, TradePath@ path, Object@ from, Object@ to) {
		uint cnt = path.pathSize;
		if(cnt == 1) {
			path.origin.object.addTradePathing(-1, from, to, res.id, res.type.id);
		}
		else {
			for(uint i = 0; i < cnt-1; ++i) {
				SystemDesc@ node = path.pathNode[i];
				SystemDesc@ next = path.pathNode[i+1];;
				node.object.addTradePathing(next.index, from, to, res.id, res.type.id);
			}
		}
	}

	void resourceTick(Object& obj, double time) {
		//Vanish any native resources
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			Resource@ r = nativeResources[i];
			if(!r.usable || obj.owner is null || !obj.owner.valid)
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

			if(r.exportedTo !is null) {
				float rate = r.exportedTo.resourceVanishRate;
				r.vanishTime += time * rate;
				r.exportedTo.setAvailableResourceVanish(obj, r.id, r.vanishTime);
			}
			else {
				r.vanishTime += time * get_resourceVanishRate();
				setAvailableResourceVanish(obj, obj, r.id, r.vanishTime);
			}
		}
	}

	void destroyObjResources(Object& obj) {
		for(uint i = 0, cnt = nativeResources.length; i < cnt; ++i) {
			Resource@ r = nativeResources[i];
			TradePath@ path = resourcePaths[i];
			if(pathsActive[i] !is null)
				clearLines(r, path, r.origin, pathsActive[i]);
		}
	}

	uint get_resourceModID() {
		return ResourceModId;
	}

	void _readRes(Object& obj, Message& msg) {
		msg >> terraforming;
		resVanishBonus = msg.read_float();
		availableResources.read(msg);

		{
			uint cnt = msg.readSmall();
			nativeResources.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				Resource@ r = nativeResources[i];
				r.read(msg);

				if(r.type.vanishMode != VM_Never) {
					if(r.exportedTo !is null)
						r.exportedTo.setAvailableResourceVanish(obj, r.id, r.vanishTime);
					else
						setAvailableResourceVanish(obj, obj, r.id, r.vanishTime);
				}
			}
		}

		{
			uint cnt = msg.readSmall();
			resources.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				resources[i].read(msg);
		}

		{
			uint cnt = msg.readSmall();
			queuedImports.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				queuedImports[i].readQueued(msg);
		}

		{
			uint cnt = msg.readSmall();
			queuedExports.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				@queuedExports[i] = QueuedResource();
				queuedExports[i].read(msg);
			}
		}

		if(nativeResources.length != 0)
			primaryResource.descFrom(nativeResources[0]);
		else
			primaryResource.descFrom(null);
		++ResourceModId;
	}

	void _readPath(Object& obj, Message& msg) {
		uint cnt = msg.readSmall();

		if(cnt != resourcePaths.length) {
			uint prev = resourcePaths.length;
			resourcePaths.length = cnt;
			pathsActive.length = cnt;
			for(uint i = prev; i < cnt; ++i) {
				@resourcePaths[i] = TradePath(obj.owner);
				@pathsActive[i] = null;
			}
		}

		for(uint i = 0; i < cnt; ++i) {
			TradePath@ path = resourcePaths[i];
			Resource@ r = nativeResources[i];
			if(pathsActive[i] !is null)
				clearLines(r, path, r.origin, pathsActive[i]);
			@path.forEmpire = obj.owner;
			path.read(msg);

			if(path.isUsablePath) {
				@pathsActive[i] = r.exportedTo;
				updateLines(r, path, r.origin, r.exportedTo);
			}
			else {
				@pathsActive[i] = null;
			}
		}
	}

	void readResourceDelta(Object& obj, Message& msg) {
		if(msg.readBit())
			_readRes(obj, msg);
		if(msg.readBit())
			_readPath(obj, msg);
	}

	void readResources(Object& obj, Message& msg) {
		_readRes(obj, msg);
		_readPath(obj, msg);

		if(msg.readBit())
			msg >> ImportDisabled;
		else
			ImportDisabled = 0;
		
		if(msg.readBit())
			msg >> ExportDisabled;
		else
			ExportDisabled = 0;
	}
}
