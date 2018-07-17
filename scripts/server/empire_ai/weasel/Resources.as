import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.ImportData;

import resources;
import planet_levels;
import system_pathing;
import systems;

interface RaceResources {
	void levelRequirements(Object& obj, int targetLevel, array<ResourceSpec@>& specs);
};

final class Resources : AIComponent {
	RaceResources@ race;

	array<ImportData@> requested;
	array<ImportData@> active;
	int nextImportId = 0;

	array<ExportData@> available;
	array<ExportData@> used;
	int nextExportId = 0;

	void create() {
		@race = cast<RaceResources>(ai.race);
	}

	void save(SaveFile& file) {
		file << nextImportId;
		file << nextExportId;

		uint cnt = 0;

		cnt = requested.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveImport(file, requested[i]);
			file << requested[i];
		}

		cnt = active.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveImport(file, active[i]);
			file << active[i];
		}

		cnt = available.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveExport(file, available[i]);
			file << available[i];
			saveImport(file, available[i].request);
		}

		cnt = used.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveExport(file, used[i]);
			file << used[i];
			saveImport(file, used[i].request);
		}
	}

	void load(SaveFile& file) {
		file >> nextImportId;
		file >> nextExportId;

		uint cnt = 0;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadImport(file);
			file >> data;
			requested.insertLast(data);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadImport(file);
			file >> data;
			active.insertLast(data);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadExport(file);
			file >> data;
			@data.request = loadImport(file);
			available.insertLast(data);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadExport(file);
			file >> data;
			@data.request = loadImport(file);
			used.insertLast(data);
		}
	}

	array<ImportData@> importIds;
	ImportData@ loadImport(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = importIds.length; i < cnt; ++i) {
			if(importIds[i].id == id)
				return importIds[i];
		}
		ImportData data;
		data.id = id;
		importIds.insertLast(data);
		return data;
	}
	ImportData@ loadImport(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadImport(id);
	}
	void saveImport(SaveFile& file, ImportData@ data) {
		int id = -1;
		if(data !is null)
			id = data.id;
		file << id;
	}
	array<ExportData@> exportIds;
	ExportData@ loadExport(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = exportIds.length; i < cnt; ++i) {
			if(exportIds[i].id == id)
				return exportIds[i];
		}
		ExportData data;
		data.id = id;
		exportIds.insertLast(data);
		return data;
	}
	ExportData@ loadExport(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadExport(id);
	}
	void saveExport(SaveFile& file, ExportData@ data) {
		int id = -1;
		if(data !is null)
			id = data.id;
		file << id;
	}
	void postLoad(AI& ai) {
		importIds.length = 0;
		exportIds.length = 0;
	}

	void start() {
		focusTick(0);
	}

	void tick(double time) {
	}

	uint checkIdx = 0;
	void focusTick(double time) {
		//Do a check to make sure our resource export setup is still correct
		if(used.length != 0) {
			checkIdx = (checkIdx+1) % used.length;
			ExportData@ res = used[checkIdx];
			if(res.request !is null && res.request.obj !is null && !res.isExportedTo(res.request.obj)) {
				if(log)
					ai.print("Break export to "+res.request.obj.name+": link changed underfoot", res.obj);
				breakImport(res);
			}
			else {
				bool valid = true;
				if(res.obj is null || res.obj.owner !is ai.empire || !res.obj.valid)
					valid = false;
				//Don't break these imports, we want to wait for the decay to happen
				else if((res.request is null || !res.request.obj.hasSurfaceComponent || res.request.obj.decayTime <= 0) && !res.obj.isAsteroid && !res.usable) {
					valid = false;
				}
				else if(res.request !is null) {
					if(res.request.obj.owner !is ai.empire || !res.request.obj.valid)
						valid = false;
				}
				if(!valid)
					breakImport(res);
			}

		}

		//TODO: Make sure universal unique only applies once per planet

		//Match requested with available
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ req = requested[i];
			req.cycled = true;

			if(req.obj is null)
				continue;
			if(req.beingMet) {
				ai.print("Error: Requested is being met", req.obj);
				continue;
			}

			ExportData@ source;
			double sourceWeight = 0.0;

			for(uint j = 0, jcnt = available.length; j < jcnt; ++j) {
				auto@ av = available[j];
				if(av.request !is null) {
					ai.print("Error: Available is being used", av.obj);
					continue;
				}

				if(!req.spec.meets(av.resource, av.obj, req.obj))
					continue;
				if(!av.usable || av.obj is null || !av.obj.valid || av.obj.owner !is ai.empire)
					continue;
				if(!canTradeBetween(av.obj, req.obj))
					continue;
				if(av.localOnly && av.obj !is req.obj)
					continue;

				double weight = 1.0;
				if(req.obj is av.obj)
					weight = INFINITY;

				if(weight > sourceWeight) {
					sourceWeight = weight;
					@source = av;
				}
			}

			if(source !is null) {
				link(req, source);
				--i; --cnt;
			}
		}
	}

	void turn() {
	}

	bool get_hasOpenRequests() {
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ req = requested[i];
			if(req.isOpen)
				return true;
		}
		return false;
	}

	TradePath tradePather;
	int tradeDistance(Region& fromRegion, Region& toRegion) {
		@tradePather.forEmpire = ai.empire;
		tradePather.generate(getSystem(fromRegion), getSystem(toRegion), keepCache=true);
		if(!tradePather.valid)
			return -1;
		return tradePather.pathSize - 1;
	}

	bool canTradeBetween(Object& fromObj, Object& toObj) {
		Region@ fromRegion = fromObj.region;
		if(fromRegion is null)
			return false;
		Region@ toRegion = toObj.region;
		if(toRegion is null)
			return false;
		return canTradeBetween(fromRegion, toRegion);
	}

	bool canTradeBetween(Region& fromRegion, Region& toRegion) {
		if(fromRegion.sharesTerritory(ai.empire, toRegion))
			return true;
		int dist = tradeDistance(fromRegion, toRegion);
		if(dist < 0)
			return false;
		return true;
	}

	void link(ImportData@ req, ExportData@ source) {
		//Manage the data
		@source.request = req;
		@source.developUse = null;
		req.set(source);

		requested.remove(req);
		active.insertLast(req);

		req.beingMet = true;

		available.remove(source);
		used.insertLast(source);

		if(log)
			ai.print("link "+source.resource.name+" from "+source.obj.name+" to "+req.obj.name);

		//Perform the actual export
		if(source.obj !is req.obj)
			source.obj.exportResourceByID(source.resourceId, req.obj);
		else
			source.obj.exportResourceByID(source.resourceId, null);
	}

	ImportData@ requestResource(Object& toObject, ResourceSpec& spec, bool forLevel = false, bool activate = true, bool prioritize = false) {
		ImportData data;
		data.idleSince = gameTime;
		data.id = nextImportId++;
		@data.obj = toObject;
		@data.spec = spec;
		data.forLevel = forLevel;

		if(log)
			ai.print("requested resource: "+spec.dump(), toObject);

		if(activate) {
			if(prioritize)
				requested.insertAt(0, data);
			else
				requested.insertLast(data);
		}
		return data;
	}

	ExportData@ availableResource(Object& fromObject, const ResourceType& resource, int id) {
		ExportData data;
		data.id = nextExportId++;
		@data.obj = fromObject;
		@data.resource = resource;
		data.resourceId = id;

		if(log)
			ai.print("available resource: "+resource.name, fromObject);

		available.insertLast(data);
		return data;
	}

	void checkReplaceCurrent(ExportData@ res) {
		//If the planet that this resource is on is currently importing this same resource, switch it around
		if(res.request !is null)
			return;

		for(uint i = 0, cnt = used.length; i < cnt; ++i) {
			auto@ other = used[i];
			auto@ request = other.request;
			if(request is null)
				continue;
			if(request.obj !is res.obj)
				continue;

			if(request.spec.meets(res.resource, res.obj, res.obj)) {
				//Swap the import with using the local resource
				if(other.resource.exportable) {
					breakImport(other);
					link(request, res);
					return;
				}
			}
		}
	}

	array<Resource> checkResources;
	array<ExportData@>@ availableResource(Object& fromObject) {
		array<ExportData@> list;

		checkResources.syncFrom(fromObject.getNativeResources());

		uint nativeCount = checkResources.length;
		for(uint i = 0; i < nativeCount; ++i) {
			auto@ r = checkResources[i].type;
			if(r !is null)
				list.insertLast(availableResource(fromObject, r, checkResources[i].id));
		}

		return list;
	}

	ExportData@ findResource(Object@ obj, int resourceId) {
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(available[i].obj is obj && available[i].resourceId == resourceId)
				return available[i];
		}
		for(uint i = 0, cnt = used.length; i < cnt; ++i) {
			if(used[i].obj is obj && used[i].resourceId == resourceId)
				return used[i];
		}
		return null;
	}

	ImportData@ findUnclaimed(ExportData@ forResource) {
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ req = requested[i];
			if(req.claimedFor)
				continue;
			if(req.beingMet)
				continue;

			if(!req.spec.meets(forResource.resource, forResource.obj, req.obj))
				continue;
			if(!canTradeBetween(req.obj, forResource.obj))
				continue;

			return req;
		}
		return null;
	}

	void breakImport(ImportData@ data) {
		if(data.fromObject !is null) {
			auto@ source = findResource(data.fromObject, data.resourceId);
			if(source !is null) {
				breakImport(source);
				return;
			}
		}

		@data.fromObject = null;
		data.resourceId = -1;
		data.beingMet = false;
		data.idleSince = gameTime;

		active.remove(data);
		requested.insertAt(0, data);
	}

	void breakImport(ExportData@ data) {
		if(data.request !is null) {
			if(data.request.obj !is data.obj)
				data.obj.exportResource(data.resourceId, null);

			data.request.beingMet = false;
			@data.request.fromObject = null;
			data.request.resourceId = -1;
			data.request.idleSince = gameTime;

			active.remove(data.request);
			requested.insertAt(0, data.request);

			@data.request = null;
		}

		used.remove(data);
		available.insertLast(data);
	}

	void cancelRequest(ImportData@ data) {
		if(data.beingMet) {
			breakImport(data);
			active.remove(data);
		}
		else {
			requested.remove(data);
		}
	}

	void removeResource(ExportData@ data) {
		if(data.request !is null) {
			breakImport(data);
			used.remove(data);
			@data.obj = null;
		}
		else {
			available.remove(data);
			@data.obj = null;
		}
	}

	ImportData@ claimImport(ImportData@ data) {
		data.beingMet = true;
		requested.remove(data);
		active.insertLast(data);
		return data;
	}

	void relinquishImport(ImportData@ data) {
		data.beingMet = false;
		active.remove(data);
		requested.insertLast(data);
	}

	void organizeImports(Object& obj, int targetLevel, ImportData@ before = null) {
		//Organize any imports for this object so it tries to get to a particular target level
		if(log)
			ai.print("Organizing imports for level", obj, targetLevel);

		//Get the requirement list
		const PlanetLevel@ lvl = getPlanetLevel(obj, targetLevel);
		if(lvl is null) {
			ai.print("Error: could not find planet level", obj, targetLevel);
			return; //Welp, can't do nothing here
		}

		//Collect all the requests this planet currently has outstanding
		array<ImportData@> activeRequests;
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ req = requested[i];
			if(req.obj !is obj)
				continue;
			if(!req.forLevel)
				continue;

			activeRequests.insertLast(req);
		}
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			auto@ req = active[i];
			if(req.obj !is obj)
				continue;
			if(!req.forLevel)
				continue;

			activeRequests.insertLast(req);
		}

		//TODO: This needs to be able to deal with dummy resources

		//Match import requests with level requirements
		array<ResourceSpec@> addSpecs;
		const ResourceRequirements@ reqs = lvl.reqs;

		for(uint i = 0, cnt = reqs.reqs.length; i < cnt; ++i) {
			auto@ need = reqs.reqs[i];
			for(uint n = 0; n < need.amount; ++n)
				addSpecs.insertLast(implementSpec(need));
		}

		if(race !is null)
			race.levelRequirements(obj, targetLevel, addSpecs);

		for(uint i = 0, cnt = addSpecs.length; i < cnt; ++i) {
			auto@ spec = addSpecs[i];

			bool foundMatch = false;
			for(uint j = 0, jcnt = activeRequests.length; j < jcnt; ++j) {
				if(activeRequests[j].spec == spec) {
					foundMatch = true;
					activeRequests.removeAt(j);
					break;
				}
			}

			if(foundMatch) {
				addSpecs.removeAt(i);
				--i; --cnt;
			}
		}

		//Cancel any import requests that we don't need anymore
		for(uint i = 0, cnt = activeRequests.length; i < cnt; ++i)
			cancelRequest(activeRequests[i]);

		//Insert any imports above any imports of the planet we're exporting to
		int place = -1;
		if(before !is null) {
			for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
				if(requested[i] is before) {
					place = int(i);
					break;
				}
			}
		}

		//Insert everything we need to add
		addSpecs.sortDesc();
		for(uint i = 0, cnt = addSpecs.length; i < cnt; ++i) {
			ImportData@ req = requestResource(obj, addSpecs[i], forLevel=true, activate=false);
			if(place == -1) {
				requested.insertLast(req);
			}
			else {
				requested.insertAt(place, req);
				place += 1;
			}
		}
	}

	void killImportsTo(Object& obj) {
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			if(requested[i].obj is obj) {
				cancelRequest(requested[i]);
				--i; --cnt;
			}
		}
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].obj is obj) {
				cancelRequest(active[i]);
				--i; --cnt;
			}
		}
	}

	void killResourcesFrom(Object& obj) {
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(available[i].obj is obj) {
				removeResource(available[i]);
				--i; --cnt;
			}
		}
		for(uint i = 0, cnt = used.length; i < cnt; ++i) {
			if(used[i].obj is obj) {
				removeResource(used[i]);
				--i; --cnt;
			}
		}
	}

	ImportData@ getImport(const string& fromName, uint index = 0) {
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			if(requested[i].obj.name.equals_nocase(fromName)) {
				if(index == 0)
					return requested[i];
				else
					index -= 1;
			}
		}
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			if(active[i].obj.name.equals_nocase(fromName)) {
				if(index == 0)
					return active[i];
				else
					index -= 1;
			}
		}
		return null;
	}

	ExportData@ getExport(const string& fromName, uint index = 0) {
		for(uint i = 0, cnt = available.length; i < cnt; ++i) {
			if(available[i].obj.name.equals_nocase(fromName)) {
				if(index == 0)
					return available[i];
				else
					index -= 1;
			}
		}
		for(uint i = 0, cnt = used.length; i < cnt; ++i) {
			if(used[i].obj.name.equals_nocase(fromName)) {
				if(index == 0)
					return used[i];
				else
					index -= 1;
			}
		}
		return null;
	}

	void getImportsOf(array<ImportData@>& output, uint resType, Planet@ toPlanet = null) {
		for(uint i = 0, cnt = active.length; i < cnt; ++i) {
			auto@ req = active[i];
			if(req.spec.type != RST_Specific)
				continue;
			if(req.spec.resource.id != resType)
				continue;
			if(toPlanet !is null && req.obj !is toPlanet)
				continue;
			output.insertLast(req);
		}
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			auto@ req = requested[i];
			if(req.spec.type != RST_Specific)
				continue;
			if(req.spec.resource.id != resType)
				continue;
			if(toPlanet !is null && req.obj !is toPlanet)
				continue;
			output.insertLast(req);
		}
	}

	void dumpRequests(Object@ forObject = null) {
		for(uint i = 0, cnt = requested.length; i < cnt; ++i) {
			if(forObject !is null && requested[i].obj !is forObject)
				continue;
			print(requested[i].obj.name+" requests "+requested[i].spec.dump());
		}
		if(forObject !is null) {
			for(uint i = 0, cnt = used.length; i < cnt; ++i) {
				if(used[i].request is null || used[i].request.obj !is forObject)
					continue;
				print(used[i].request.obj.name+" is getting "+used[i].request.spec.dump()+" from "+used[i].obj.name);
			}
		}
	}
};

AIComponent@ createResources() {
	return Resources();
}
