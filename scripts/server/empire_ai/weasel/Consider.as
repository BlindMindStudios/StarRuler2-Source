// Consider
// --------
// Helps AI usage hints to consider various things in the empire.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Development;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Colonization;
import empire_ai.weasel.Intelligence;

import buildings;
import ai.consider;
from ai.artifacts import ArtifactConsider;


class Consider : AIComponent, Considerer {
	Systems@ systems;
	Fleets@ fleets;
	Planets@ planets;
	Construction@ construction;
	Development@ development;
	Resources@ resources;
	Intelligence@ intelligence;
	Colonization@ colonization;

	void create() {
		@systems = cast<Systems>(ai.systems);
		@fleets = cast<Fleets>(ai.fleets);
		@planets = cast<Planets>(ai.planets);
		@development = cast<Development>(ai.development);
		@construction = cast<Construction>(ai.construction);
		@resources = cast<Resources>(ai.resources);
		@intelligence = cast<Intelligence>(ai.intelligence);
		@colonization = cast<Colonization>(ai.colonization);
	}

	Empire@ get_empire() {
		return ai.empire;
	}

	Object@ secondary;
	ArtifactConsider@ artifactConsider;
	double bestWeight;
	ImportData@ request;
	const BuildingType@ bldType;
	ConsiderComponent@ comp;
	ConsiderFilter@ cfilter;

	double get_selectedWeight() {
		return bestWeight;
	}

	Object@ get_currentSupplier() {
		return secondary;
	}

	ArtifactConsider@ get_artifact() {
		return artifactConsider;
	}

	void set_artifact(ArtifactConsider@ cons) {
		@artifactConsider = cons;
	}

	double get_idleTime() {
		if(request !is null)
			return gameTime - request.idleSince;
		return 0.0;
	}

	double timeSinceMatchingColonize() {
		if(request is null)
			return INFINITY;
		return colonization.timeSinceMatchingColonize(request.spec);
	}

	const BuildingType@ get_building() {
		return bldType;
	}

	void set_building(const BuildingType@ type) {
		@bldType = type;
	}

	ConsiderComponent@ get_component() {
		return comp;
	}

	void set_component(ConsiderComponent@ comp) {
		@this.comp = comp;
	}

	void set_filter(ConsiderFilter@ filter) {
		@this.cfilter = filter;
	}

	void clear() {
		@secondary = null;
		@artifactConsider = null;
		@request = null;
		@comp = null;
		@bldType = null;
		@cfilter = null;
	}

	Object@ OwnedSystems(const ConsiderHook& hook, uint limit = uint(-1)) {
		Object@ best;
		bestWeight = 0.0;

		uint offset = randomi(0, systems.owned.length-1);
		uint cnt = min(systems.owned.length, limit);
		for(uint i = 0; i < cnt; ++i) {
			uint index = (i+offset) % systems.owned.length;
			Region@ obj = systems.owned[index].obj;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ Fleets(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			Object@ fleet = fleets.fleets[i].obj;
			if(fleet !is null) {
				if(cfilter !is null && !cfilter.filter(fleet))
					continue;
				double w = hook.consider(this, fleet);
				if(w > bestWeight) {
					bestWeight = w;
					@best = fleet;
				}
			}
		}

		clear();
		return best;
	}

	Object@ BorderSystems(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = systems.border.length; i < cnt; ++i) {
			Region@ obj = systems.border[i].obj;
			if(obj.PlanetsMask & ~ai.mask == 0)
				continue;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}
		for(uint i = 0, cnt = systems.outsideBorder.length; i < cnt; ++i) {
			Region@ obj = systems.outsideBorder[i].obj;
			if(obj.PlanetsMask & ~ai.mask == 0)
				continue;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ OtherSystems(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = intelligence.intel.length; i < cnt; ++i) {
			auto@ intel = intelligence.intel[i];
			if(intel is null)
				continue;

			for(uint i = 0, cnt = intel.theirOwned.length; i < cnt; ++i) {
				Region@ obj = intel.theirOwned[i].obj;
				if(obj.PlanetsMask & ~ai.mask == 0)
					continue;
				if(obj !is null) {
					if(cfilter !is null && !cfilter.filter(obj))
						continue;
					double w = hook.consider(this, obj);
					if(w > bestWeight) {
						bestWeight = w;
						@best = obj;
					}
				}
			}
		}

		clear();
		return best;
	}

	Object@ ImportantPlanets(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			Object@ obj = development.focuses[i].obj;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ AllPlanets(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = planets.planets.length; i < cnt; ++i) {
			Object@ obj = planets.planets[i].obj;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ SomePlanets(const ConsiderHook& hook, uint count, bool alwaysImportant) {
		Object@ best;
		bestWeight = 0.0;
		if(alwaysImportant) {
			for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
				Object@ obj = development.focuses[i].obj;
				if(obj !is null) {
					if(cfilter !is null && !cfilter.filter(obj))
						continue;
					double w = hook.consider(this, obj);
					if(w > bestWeight) {
						bestWeight = w;
						@best = obj;
					}
				}
			}
		}

		uint planetCount = planets.planets.length;
		uint offset = randomi(0, planetCount-1);
		uint cnt = min(count, planetCount);
		for(uint i = 0; i < cnt; ++i) {
			uint index = (offset+i) % planetCount;
			Object@ obj = planets.planets[index].obj;
			if(obj !is null) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ FactoryPlanets(const ConsiderHook& hook) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = construction.factories.length; i < cnt; ++i) {
			Object@ obj = construction.factories[i].obj;
			if(obj !is null && obj.isPlanet) {
				if(cfilter !is null && !cfilter.filter(obj))
					continue;
				double w = hook.consider(this, obj);
				if(w > bestWeight) {
					bestWeight = w;
					@best = obj;
				}
			}
		}

		clear();
		return best;
	}

	Object@ MatchingImportRequests(const ConsiderHook& hook, const ResourceType@ type, bool considerExisting) {
		Object@ best;
		bestWeight = 0.0;
		for(uint i = 0, cnt = resources.requested.length; i < cnt; ++i) {
			ImportData@ req = resources.requested[i];
			if(!considerExisting) {
				if(req.beingMet || req.claimedFor)
					continue;
			}
			if(req.spec.meets(type, req.obj, req.obj)) {
				@secondary = null;
				@request = req;
				double w = hook.consider(this, req.obj);
				if(w > bestWeight) {
					if(cfilter !is null && !cfilter.filter(req.obj))
						continue;
					bestWeight = w;
					@best = req.obj;
				}
			}
		}
		if(considerExisting) {
			for(uint i = 0, cnt = resources.used.length; i < cnt; ++i) {
				ExportData@ res = resources.used[i];
				ImportData@ req = res.request;
				if(req !is null && req.spec.meets(type, req.obj, req.obj)) {
					@secondary = res.obj;
					@request = req;
					double w = hook.consider(this, req.obj);
					if(w > bestWeight) {
						if(cfilter !is null && !cfilter.filter(req.obj))
							continue;
						bestWeight = w;
						@best = req.obj;
					}
				}
			}
		}

		clear();
		return best;
	}
};

AIComponent@ createConsider() {
	return Consider();
}
