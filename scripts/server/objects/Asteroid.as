import resources;
import regions.regions;
import saving;
import cargo;
import attributes;
from systems import hasTradeAdjacent;

Asteroid@ createAsteroid(const vec3d& position, Region@ region = null, bool delay = false) {
	ObjectDesc desc;
	desc.type = OT_Asteroid;
	desc.radius = 5.0;
	desc.position = position;
	desc.name = locale::ASTEROID;
	desc.flags |= objNoDamage;

	if(region !is null)
		desc.delayedCreation = true;

	Asteroid@ obj = Asteroid(desc);

	if(region !is null) {
		@obj.region = region;
		obj.finalizeCreation();
		region.enterRegion(obj);
	}
	if(!delay)
		obj.initMesh();
	return obj;
}

tidy class AsteroidScript {
	StrategicIconNode@ icon;
	MeshNode@ baseNode;

	array<const ResourceType@> available;
	array<float> costs;
	array<bool> exploited;
	array<int> nativeIds;
	bool delta = false;
	uint resourceLimit = 1;
	uint currentResources = 0;
	uint limitMod = 0;

	void load(Asteroid& obj, SaveFile& file) {
		loadObjectStates(obj, file);

		if(file >= SV_0122) {
			file >> cast<Savable>(obj.Orbit);
			file >> cast<Savable>(obj.Cargo);
		}
		else {
			file >> cast<Savable>(obj.Resources);
			file >> cast<Savable>(obj.Orbit);
		}
		if(file >= SV_0125)
			file >> cast<Savable>(obj.Resources);

		if(file < SV_0122 || file >= SV_0125) {
			Object@ origin;
			@origin = file.readObject();

			uint cnt = 0;
			file >> cnt;
			available.length = cnt;
			costs.length = cnt;
			exploited.length = cnt;
			nativeIds.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				@available[i] = getResource(file.readIdentifier(SI_Resource));
				file >> costs[i];
				file >> exploited[i];
				file >> nativeIds[i];
			}

			file >> resourceLimit;
			file >> limitMod;
			file >> currentResources;
		}

		obj.HasBase = (obj.owner !is null && obj.owner.valid) ? 1.f : 0.f;
	}

	void postLoad(Asteroid& obj) {
		makeMesh(obj);
	}

	void save(Asteroid& obj, SaveFile& file) {
		saveObjectStates(obj, file);
		file << cast<Savable>(obj.Orbit);
		file << cast<Savable>(obj.Cargo);
		file << cast<Savable>(obj.Resources);
		file << obj.origin;
		
		uint cnt = available.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file.writeIdentifier(SI_Resource, available[i].id);
			file << costs[i];
			file << exploited[i];
			file << nativeIds[i];
		}
		
		file << resourceLimit;
		file << limitMod;
		file << currentResources;
	}

	void postInit(Asteroid& obj) {
		obj.setImportEnabled(false);
		obj.setResourceLevel(4);
		obj.sightRange = 0;

		obj.modCargoStorage(+INFINITY);
	}

	void destroy(Asteroid& obj) {
		obj.destroyObjResources();
		if(obj.region !is null)
			obj.region.removeStrategicIcon(-1, icon);
		icon.markForDeletion();
		@icon = null;

		if(baseNode !is null) {
			baseNode.markForDeletion();
			@baseNode = null;
		}

		if(obj.owner !is null && obj.owner.valid)
			obj.owner.unregisterAsteroid(obj);

		leaveRegion(obj);
	}
	
	bool onOwnerChange(Asteroid& obj, Empire@ prevOwner) {
		regionOwnerChange(obj, prevOwner);
		if(prevOwner !is null && prevOwner.valid)
			prevOwner.unregisterAsteroid(obj);
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.registerAsteroid(obj);
		obj.changeResourceOwner(prevOwner);

		bool hasBase = obj.owner !is null && obj.owner.valid;
		obj.HasBase = hasBase ? 1.f : 0.f;
		if(hasBase && baseNode is null) {
			@baseNode = MeshNode(model::MiningBase, material::GenericPBR_MiningBase);
			nodeSyncObject(baseNode, obj);
		}
		else if(baseNode !is null && !hasBase) {
			baseNode.markForDeletion();
			@baseNode = null;
		}

		return false;
	}

	void initMesh(Asteroid& obj) {
		makeMesh(obj);
	}

	void makeMesh(Asteroid& obj) {
		MeshDesc mesh;
		switch(obj.id % 4) {
			case 0:	
				@mesh.model = model::Asteroid1; break;
			case 1:
				@mesh.model = model::Asteroid2; break;
			case 2:
				@mesh.model = model::Asteroid3; break;
			case 3:
				@mesh.model = model::Asteroid4; break;
			}
		switch(obj.id % 3) {
			case 0:
				@mesh.material = material::AsteroidPegmatite; break;
			case 1:
				@mesh.material = material::AsteroidMagnetite; break;
			case 2:
				@mesh.material = material::AsteroidTonalite; break;
		}
		
		mesh.memorable = true;

		@icon = StrategicIconNode();
		if(obj.cargoTypes != 0)
			icon.establish(obj, 0.015, spritesheet::OreAsteroidIcon, 0);
		else
			icon.establish(obj, 0.015, spritesheet::AsteroidIcon, 0);
		icon.memorable = true;
		
		bindMesh(obj, mesh);
		
		if(obj.region !is null) {
			if(!obj.region.initialized)
				@obj.region = null;
			else
				obj.region.addStrategicIcon(-1, obj, icon);
			
			if(obj.region !is null) {
				Node@ node = obj.getNode();
				node.hintParentObject(obj.region, false);
			}
		}

		bool hasBase = obj.owner !is null && obj.owner.valid;
		if(hasBase && baseNode is null) {
			@baseNode = MeshNode(model::MiningBase, material::GenericPBR_MiningBase);
			nodeSyncObject(baseNode, obj);
		}
	}

	float timer = 0.f;
	void occasional_tick(Asteroid& obj) {
		Region@ region = obj.region;
		bool engaged = obj.engaged;
		obj.inCombat = engaged;
		obj.engaged = false;

		if(engaged && region !is null)
			region.EngagedMask |= obj.owner.mask;
	}

	double tick(Asteroid& obj, double time) {
		Region@ prevRegion = obj.region;
		if(updateRegion(obj)) {
			Region@ newRegion = obj.region;
			if(prevRegion !is null)
				prevRegion.removeStrategicIcon(-1, icon);
			if(newRegion !is null)
				newRegion.addStrategicIcon(-1, obj, icon);
			@prevRegion = newRegion;
			
			Node@ node = obj.getNode();
			if(node !is null)
				node.hintParentObject(newRegion, false);
		}

		if(prevRegion is null && isOutsideUniverseExtents(obj.position))
			limitToUniverseExtents(obj.position);

		icon.visible = obj.isVisibleTo(playerEmpire);

		obj.orbitTick(time);
		obj.resourceTick(time);

		//Tick occasional stuff
		timer -= float(time);
		if(timer <= 0.f) {
			occasional_tick(obj);
			timer = 1.f;
		}

		//Asteroids lose ownership if not in an owned or neutral system
		if(obj.owner.valid) {
			if(prevRegion !is null && prevRegion.PlanetsMask != 0 && prevRegion.PlanetsMask & obj.owner.mask == 0) {
				if(!hasTradeAdjacent(obj.owner, prevRegion)) {
					clearSetup(obj);
					return 0.2;
				}
			}
		}

		//Asteroids are destroyed when they run out of cargo or resources
		if(obj.cargoTypes == 0 && obj.nativeResourceCount == 0)
			obj.destroy();

		return 0.2;
	}

	vec3d get_strategicIconPosition(Asteroid& obj) {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	bool canDevelop(Asteroid& obj, Empire@ emp) {
		return (!obj.owner.valid || obj.owner is emp) && currentResources < resourceLimit;
	}

	bool canGainLimit(Asteroid& obj, Empire@ emp) {
		if(!obj.owner.valid || obj.owner !is emp)
			return false;
		return resourceLimit < available.length;
	}

	void addAvailable(Asteroid& obj, uint resource, double cost) {
		const ResourceType@ type = getResource(resource);
		if(type is null)
			return;
	
		available.insertLast(type);
		costs.insertLast(cost);
		exploited.insertLast(false);
		int id = obj.addResource(type.id);
		obj.setResourceDisabled(id, true);
		nativeIds.insertLast(id);
	
		delta = true;
	}
	
	uint getAvailableCount() {
		if(currentResources >= resourceLimit)
			return 0;
		return available.length;
	}
	
	uint getAvailable(uint index) {
		if(index >= available.length)
			return uint(-1);
		if(exploited[index])
			return uint(-1);
		return available[index].id;
	}
	
	double getAvailableCost(uint index) {
		if(index >= costs.length)
			return -1.0;
		if(exploited[index])
			return -1.0;
		return costs[index];
	}
	
	double getAvailableCostFor(uint resId) {
		const ResourceType@ type = getResource(resId);
		if(type is null)
			return -1.0;
	
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(exploited[i])
				continue;
			if(available[i] is type)
				return costs[i];
		}
	
		return -1.0;
	}
	
	void setup(Asteroid& obj, Object@ origin, Empire@ emp, uint resource) {
		if(obj.owner.valid && emp !is obj.owner)
			return;
		if(currentResources >= resourceLimit)
			return;
	
		const ResourceType@ type = getResource(resource);
		if(type is null)
			return;
	
		bool found = false;
		uint foundIndex = 0;
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(exploited[i])
				continue;
			if(available[i] is type) {
				found = true;
				foundIndex = i;
				break;
			}
		}
	
		if(!found)
			return;
		Object@ queued;
		exploited[foundIndex] = true;
		obj.setResourceDisabled(nativeIds[foundIndex], false);
	
		if(!obj.owner.valid) {
			@obj.owner = emp;
			@obj.origin = origin;
			obj.name = type.name+" "+locale::ASTEROID;
			emp.modAttribute(EA_MiningBasesBuilt, AC_Add, 1);
		}
	
		//Remove all the fake resources and remember the queue
		currentResources += 1;
		if(currentResources >= resourceLimit) {
			for(uint i = 0, cnt = available.length; i < cnt; ++i) {
				if(exploited[i])
					continue;
				obj.removeResource(nativeIds[i]);
				nativeIds[i] = -1;
			}
		}
	
		delta = true;
	}

	void clearSetup(Asteroid& obj) {
		if(currentResources == 0)
			return;
		delta = true;
		currentResources = 0;

		Object@ queued = obj.nativeResourceDestination[0];
		uint qtype = obj.nativeResourceType[0];

		for(uint i = 0, cnt = obj.nativeResourceCount; i < cnt; ++i)
			obj.removeResource(obj.nativeResourceId[i]);

		Empire@ prevOwner = obj.owner;
		@obj.owner = defaultEmpire;
		@obj.origin = null;
		obj.name = locale::ASTEROID;

		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			exploited[i] = false;
			if(costs[i] <= 0)
				costs[i] = available[i].asteroidCost;

			int id = obj.addResource(available[i].id);
			obj.setResourceDisabled(id, true);
			nativeIds[i] = id;

			if(queued !is null && qtype == available[i].id && prevOwner.valid)
				obj.exportResource(prevOwner, id, queued);
		}
	}
	
	void checkLimit(Asteroid& obj, uint prevLimit) {
		bool wasLimited = currentResources >= prevLimit;
		bool nowLimited = currentResources >= resourceLimit;
	
		if(wasLimited) {
			if(!nowLimited) {
				for(uint i = 0, cnt = available.length; i < cnt; ++i) {
					if(exploited[i]) {
						obj.setResourceDisabled(nativeIds[i], false);
					}
					else {
						nativeIds[i] = obj.addResource(available[i].id);
						obj.setResourceDisabled(nativeIds[i], true);
					}
				}
			}
		}
		else {
			if(nowLimited) {
				for(uint i = 0, cnt = available.length; i < cnt; ++i) {
					if(exploited[i])
						continue;
					obj.removeResource(nativeIds[i]);
					nativeIds[i] = -1;
				}
			}
		}
	
		if(nowLimited) {
			uint requireDisable = currentResources - resourceLimit;
			for(uint i = 0, cnt = available.length; i < cnt; ++i) {
				if(!exploited[i])
					continue;
				Object@ dest = obj.getNativeResourceDestinationByID(obj.owner, nativeIds[i]);
				if(dest !is null) {
					obj.setResourceDisabled(nativeIds[i], false);
					continue;
				}
				if(requireDisable > 0) {
					obj.setResourceDisabled(nativeIds[i], true);
					requireDisable -= 1;
				}
				else {
					obj.setResourceDisabled(nativeIds[i], false);
				}
			}
			for(uint i = 0, cnt = available.length; i < cnt && requireDisable > 0; ++i) {
				if(!exploited[i])
					continue;
				Object@ dest = obj.getNativeResourceDestinationByID(obj.owner, nativeIds[i]);
				if(dest is null)
					continue;
				obj.setResourceDisabled(nativeIds[i], true);
				requireDisable -= 1;
			}
		}
	}
	
	void morphTo(Asteroid& obj, uint resId, double cost) {
		auto@ resource = getResource(resId);
		if(resource is null)
			return;
	
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(nativeIds[i] != -1)
				obj.removeResource(nativeIds[i]);
			nativeIds[i] = -1;
		}
	
		currentResources = 0;
		available.length = 0;
		exploited.length = 0;
		nativeIds.length = 0;
		costs.length = 0;
		addAvailable(obj, resource.id, cost);
	
		if(obj.owner !is null && obj.owner.valid)
			setup(obj, obj.origin, obj.owner, resource.id);
	}
	
	void setResourceLimit(Asteroid& obj, uint newLimit) {
		if(newLimit + limitMod == resourceLimit)
			return;
		uint prevLimit = resourceLimit;
		resourceLimit = newLimit + limitMod;
		checkLimit(obj, prevLimit);
	
		delta = true;
	}
	
	void modResourceLimitMod(Asteroid& obj, int mod) {
		limitMod += mod;
		uint prevLimit = resourceLimit;
		resourceLimit += mod;
	
		checkLimit(obj, prevLimit);
		delta = true;
	}
	
	void _writeAsteroid(const Asteroid& obj, Message& msg) {
		msg << obj.origin;
		uint cnt = available.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i) {
			msg.writeLimited(available[i].id, getResourceCount()-1);
			msg << costs[i];
			msg << exploited[i];
		}
		msg.writeSmall(resourceLimit);
		msg.writeSmall(currentResources);
	}

	void syncInitial(const Asteroid& obj, Message& msg) {
		_writeAsteroid(obj, msg);
		obj.writeResources(msg);
		obj.writeCargo(msg);
		obj.writeOrbit(msg);
	}

	bool syncDelta(const Asteroid& obj, Message& msg) {
		bool used = false;

		if(delta) {
			used = true;
			delta = false;
			msg.write1();
			_writeAsteroid(obj, msg);
		}
		else
			msg.write0();
		
		if(obj.writeResourceDelta(msg))
			used = true;
		else
			msg.write0();

		if(obj.writeCargoDelta(msg))
			used = true;
		else
			msg.write0();

		if(obj.writeOrbitDelta(msg))
			used = true;
		else
			msg.write0();

		return used;
	}

	void syncDetailed(const Asteroid& obj, Message& msg) {
		_writeAsteroid(obj, msg);
		obj.writeResources(msg);
		obj.writeCargo(msg);
		obj.writeOrbit(msg);
	}
};
