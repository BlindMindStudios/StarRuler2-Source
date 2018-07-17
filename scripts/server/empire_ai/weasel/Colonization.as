// Colonization
// ------------
// Deals with colonization for requested resources.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.ImportData;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Creeping;

import util.formatting;

import systems;

interface RaceColonization {
	bool orderColonization(ColonizeData& data, Planet@ sourcePlanet);
	double getGenericUsefulness(const ResourceType@ type);
};

final class ColonizeData {
	int id = -1;
	Planet@ target;
	Planet@ colonizeFrom;
	bool completed = false;
	bool canceled = false;
	double checkTime = -1.0;

	void save(Colonization& colonization, SaveFile& file) {
		file << target;
		file << colonizeFrom;
		file << completed;
		file << canceled;
		file << checkTime;
	}

	void load(Colonization& colonization, SaveFile& file) {
		file >> target;
		file >> colonizeFrom;
		file >> completed;
		file >> canceled;
		file >> checkTime;
	}
};

tidy final class WaitUsed {
	ImportData@ forData;
	ExportData@ resource;

	void save(Colonization& colonization, SaveFile& file) {
		colonization.resources.saveImport(file, forData);
		colonization.resources.saveExport(file, resource);
	}

	void load(Colonization& colonization, SaveFile& file) {
		@forData = colonization.resources.loadImport(file);
		@resource = colonization.resources.loadExport(file);
	}
};

final class ColonizePenalty : Savable {
	Planet@ pl;
	double until;

	void save(SaveFile& file) {
		file << pl;
		file << until;
	}

	void load(SaveFile& file) {
		file >> pl;
		file >> until;
	}
};

final class PotentialColonize {
	Planet@ pl;
	const ResourceType@ resource;
	double weight = 0;
};

final class ColonizeLog {
	int typeId;
	double time;
};

tidy final class ColonizeQueue {
	ResourceSpec@ spec;
	Planet@ target;
	ColonizeData@ step;
	ImportData@ forData;
	ColonizeQueue@ parent;
	array<ColonizeQueue@> children;

	void save(Colonization& colonization, SaveFile& file) {
		file << spec;
		file << target;

		colonization.saveColonize(file, step);
		colonization.resources.saveImport(file, forData);

		uint cnt = children.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			children[i].save(colonization, file);
	}

	void load(Colonization& colonization, SaveFile& file) {
		@spec = ResourceSpec();
		file >> spec;
		file >> target;

		@step = colonization.loadColonize(file);
		@forData = colonization.resources.loadImport(file);

		uint cnt = 0;
		file >> cnt;
		children.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@children[i] = ColonizeQueue();
			@children[i].parent = this;
			children[i].load(colonization, file);
		}
	}
};

final class Colonization : AIComponent {
	const ResourceClass@ foodClass, waterClass, scalableClass;

	Resources@ resources;
	Planets@ planets;
	Systems@ systems;
	Budget@ budget;
	Creeping@ creeping;
	RaceColonization@ race;

	array<ColonizeQueue@> queue;
	array<ColonizeData@> colonizing;
	array<ColonizeData@> awaitingSource;
	array<WaitUsed@> waiting;
	array<ColonizePenalty@> penalties;
	set_int penaltySet;
	int nextColonizeId = 0;
	array<ColonizeLog@> colonizeLog;

	array<PotentialSource@> sources;
	double sourceUpdate = 0;

	//Maximum colonizations that can still be done this turn
	uint remainColonizations = 0;
	//Amount of colonizations that have happened so far this budget cycle
	uint curColonizations = 0;
	//Amount of colonizations that happened the previous budget cycle
	uint prevColonizations = 0;

	//Whether to automatically find sources and order colonizations
	bool performColonization = true;
	bool queueColonization = true;

	Object@ colonizeWeightObj;

	void create() {
		@resources = cast<Resources>(ai.resources);
		@planets = cast<Planets>(ai.planets);
		@systems = cast<Systems>(ai.systems);
		@budget = cast<Budget>(ai.budget);
		@creeping = cast<Creeping>(ai.creeping);
		@race = cast<RaceColonization>(ai.race);

		//Get some hueristic resource classes
		@foodClass = getResourceClass("Food");
		@waterClass = getResourceClass("WaterType");
		@scalableClass = getResourceClass("Scalable");
	}

	void save(SaveFile& file) {
		file << nextColonizeId;
		file << remainColonizations;
		file << curColonizations;
		file << prevColonizations;

		uint cnt = colonizing.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveColonize(file, colonizing[i]);
			colonizing[i].save(this, file);
		}

		cnt = waiting.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			waiting[i].save(this, file);

		cnt = penalties.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			penalties[i].save(file);

		cnt = colonizeLog.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file.writeIdentifier(SI_Resource, colonizeLog[i].typeId);
			file << colonizeLog[i].time;
		}

		cnt = queue.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			queue[i].save(this, file);
	}

	void load(SaveFile& file) {
		file >> nextColonizeId;
		file >> remainColonizations;
		file >> curColonizations;
		file >> prevColonizations;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadColonize(file);
			if(data !is null) {
				data.load(this, file);
				if(data.target !is null) {
					colonizing.insertLast(data);
					if(data.colonizeFrom is null)
						awaitingSource.insertLast(data);
				}
				else {
					data.canceled = true;
				}
			}
			else {
				ColonizeData().load(this, file);
			}
		}

		file >> cnt;
		waiting.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@waiting[i] = WaitUsed();
			waiting[i].load(this, file);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			ColonizePenalty pen;
			pen.load(file);
			if(pen.pl !is null) {
				penaltySet.insert(pen.pl.id);
				penalties.insertLast(pen);
			}
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			ColonizeLog logEntry;
			logEntry.typeId = file.readIdentifier(SI_Resource);
			file >> logEntry.time;
			colonizeLog.insertLast(logEntry);
		}

		file >> cnt;
		queue.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@queue[i] = ColonizeQueue();
			queue[i].load(this, file);
		}
	}

	array<ColonizeData@> loadIds;
	ColonizeData@ loadColonize(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = loadIds.length; i < cnt; ++i) {
			if(loadIds[i].id == id)
				return loadIds[i];
		}
		ColonizeData data;
		data.id = id;
		loadIds.insertLast(data);
		return data;
	}
	ColonizeData@ loadColonize(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadColonize(id);
	}
	void saveColonize(SaveFile& file, ColonizeData@ data) {
		int id = -1;
		if(data !is null)
			id = data.id;
		file << id;
	}
	void postLoad(AI& ai) {
		loadIds.length = 0;
	}

	bool canBeColonized(Planet& target) {
		if(!target.valid)
			return false;
		if(target.owner.valid)
			return false;
		return true;
	}

	bool canColonize(Planet& source) {
		if(source.level == 0)
			return false;
		if(source.owner !is ai.empire)
			return false;
		return true;
	}

	double getSourceWeight(PotentialSource& source, ColonizeData& data) {
		double w = source.weight;
		w /= data.target.position.distanceTo(source.pl.position);
		return w;
	}

	void updateSources() {
		planets.getColonizeSources(sources);
	}

	void focusTick(double time) {
		if(sourceUpdate < gameTime && performColonization) {
			updateSources();
			if(sources.length == 0 && gameTime < 60.0)
				sourceUpdate = gameTime + 1.0;
			else
				sourceUpdate = gameTime + 10.0;
		}

		//Find some new colonizations we can queue up from resources
		fillQueueFromRequests();

		//If we've gained any requests, see if we can order another colonize
		if(remainColonizations > 0
				&& (budget.Progress < ai.behavior.colonizeMaxBudgetProgress || gameTime < 3.0 * 60.0)
				&& (sources.length > 0 || !performColonization) && canColonize()
				&& queueColonization) {
			//Actually go order some colonizations from the queue
			if(orderFromQueue()) {
				doColonize();
			}
			else if(awaitingSource.length == 0) {
				if(genericExpand() !is null)
					doColonize();
			}
		}

		//Find colonization sources for everything that needs them
		if(awaitingSource.length != 0 && performColonization) {
			for(uint i = 0, cnt = awaitingSource.length; i < cnt; ++i) {
				auto@ target = awaitingSource[i];

				PotentialSource@ src;
				double bestSource = 0;

				for(uint j = 0, jcnt = sources.length; j < jcnt; ++j) {
					double w = getSourceWeight(sources[j], target);
					if(w > bestSource) {
						bestSource = w;
						@src = sources[j];
					}
				}

				if(src !is null) {
					orderColonization(target, src.pl);
					sources.remove(src);
					--i; --cnt;
				}
			}
		}

		//Check if any resources we're waiting for are being used
		for(uint i = 0, cnt = waiting.length; i < cnt; ++i) {
			auto@ wait = waiting[i];
			if(wait.resource.obj is null || !wait.resource.obj.valid || wait.resource.obj.owner !is ai.empire || wait.resource.request !is null) {
				wait.forData.isColonizing = false;
				waiting.removeAt(i);
				--i; --cnt;
			}
		}

		//Prune old colonization penalties
		for(uint i = 0, cnt = penalties.length; i < cnt; ++i) {
			auto@ pen = penalties[i];
			if(pen.pl !is null && pen.pl.owner is ai.empire)
				pen.pl.forceAbandon();
			if(pen.until < gameTime) {
				if(pen.pl !is null)
					penaltySet.erase(pen.pl.id);
				penalties.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void orderColonization(ColonizeData& data, Planet& sourcePlanet) {
		if(log)
			ai.print("start colonizing "+data.target.name, sourcePlanet);

		if(race !is null) {
			if(race.orderColonization(data, sourcePlanet))
				return;
		}

		@data.colonizeFrom = sourcePlanet;
		awaitingSource.remove(data);

		sourcePlanet.colonize(data.target);
	}

	void tick(double time) {
		//Check if we've finished colonizing anything
		for(uint i = 0, cnt = colonizing.length; i < cnt; ++i) {
			auto@ c = colonizing[i];

			//Remove if we can no longer colonize it
			Empire@ visOwner = c.target.visibleOwnerToEmp(ai.empire);
			if(visOwner !is ai.empire && (visOwner is null || visOwner.valid)) {
				//Fail out this colonization
				cancelColonization(c);
				--i; --cnt;
				continue;
			}

			//Check for succesful colonization
			if(visOwner is ai.empire) {
				double population = c.target.population;
				if(population >= 1.0) {
					finishColonization(c);
					colonizing.removeAt(i);
					--i; --cnt;
					continue;
				}
				else {
					if(c.checkTime == -1.0) {
						c.checkTime = gameTime;
					}
					else {
						double grace = ai.behavior.colonizeFailGraceTime;
						if(population > 0.9)
							grace *= 2.0;
						if(c.checkTime + grace < gameTime) {
							//Fail out this colonization and penalize the target
							creeping.requestClear(systems.getAI(c.target.region));
							cancelColonization(c, penalize=ai.behavior.colonizePenalizeTime);
							--i; --cnt;
							continue;
						}
					}
				}
			}

			//This colonization is still waiting for a good source
			if(c.colonizeFrom is null)
				continue;

			//Check for failed colonization
			if(!canColonize(c.colonizeFrom) || !performColonization) {
				if(c.target.owner is ai.empire && performColonization)
					c.target.stopColonizing(c.target);

				@c.colonizeFrom = null;
				awaitingSource.insertAt(0, c);
			}
		}

		//Update the colonization queue
		updateQueue();
	}

	void cancelColonization(ColonizeData@ data, double penalize = 0) {
		if(data.colonizeFrom !is null && data.colonizeFrom.owner is ai.empire)
			data.colonizeFrom.stopColonizing(data.target);
		if(data.colonizeFrom is null)
			awaitingSource.remove(data);
		if(data.target.owner is ai.empire)
			data.target.forceAbandon();
		data.canceled = true;
		sourceUpdate = 0;
		colonizing.remove(data);

		if(penalize != 0) {
			ColonizePenalty pen;
			@pen.pl = data.target;
			pen.until = gameTime + penalize;

			penaltySet.insert(pen.pl.id);
			penalties.insertLast(pen);
		}
	}

	void finishColonization(ColonizeData@ data) {
		if(data.colonizeFrom is null)
			awaitingSource.remove(data);

		PlanetAI@ plAI = planets.register(data.target);

		ColonizeLog logEntry;
		logEntry.typeId = data.target.primaryResourceType;
		logEntry.time = gameTime;
		colonizeLog.insertLast(logEntry);

		data.completed = true;
		sourceUpdate = 0;
	}

	double timeSinceMatchingColonize(ResourceSpec& spec) {
		for(int i = colonizeLog.length - 1; i >= 0; --i) {
			auto@ res = getResource(colonizeLog[i].typeId);
			if(res !is null && spec.meets(res))
				return gameTime - colonizeLog[i].time;
		}
		return gameTime;
	}

	bool isColonizing(Planet& pl) {
		for(uint i = 0, cnt = colonizing.length; i < cnt; ++i) {
			if(colonizing[i].target is pl)
				return true;
		}
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			if(isColonizing(pl, queue[i]))
				return true;
		}
		return false;
	}

	bool isColonizing(Planet& pl, ColonizeQueue@ q) {
		if(q.target is pl)
			return true;
		for(uint i = 0, cnt = q.children.length; i < cnt; ++i) {
			if(isColonizing(pl, q.children[i]))
				return true;
		}
		return false;
	}

	double getGenericUsefulness(const ResourceType@ type) {
		//Return a relative value for colonizing the resource this planet has in a vacuum,
		//rather than as an explicit requirement for a planet.
		double weight = 1.0;
		if(type.level == 0) {
			weight *= 2.0;
		}
		else {
			weight /= sqr(double(1 + type.level));
			weight *= 0.001;
		}
		if(type.cls is foodClass || type.cls is waterClass)
			weight *= 10.0;
		if(type.cls is scalableClass)
			weight *= 0.0001;
		if(type.totalPressure > 0)
			weight *= double(type.totalPressure);
		if(race !is null)
			weight *= race.getGenericUsefulness(type);
		return weight;
	}

	ColonizeData@ colonize(Planet& pl) {
		if(log)
			ai.print("queue colonization", pl);

		ColonizeData data;
		data.id = nextColonizeId++;
		@data.target = pl;

		budget.spend(BT_Colonization, 0, ai.behavior.colonizeBudgetCost);

		colonizing.insertLast(data);
		awaitingSource.insertLast(data);
		return data;
	}

	ColonizeData@ colonize(ResourceSpec@ spec) {
		Planet@ newColony;
		double totalWeight = 0.0;

		for(uint i = 0, cnt = potentials.length; i < cnt; ++i) {
			auto@ p = potentials[i];

			Region@ reg = p.pl.region;
			if(reg is null)
				continue;
			if(!spec.meets(p.resource))
				continue;
			if(isColonizing(p.pl))
				continue;

			auto@ sys = systems.getAI(reg);
			double w = 1.0;
			if(sys.border)
				w *= 0.25;
			if(sys.obj.PlanetsMask & ~ai.mask != 0)
				w *= 0.25;

			totalWeight += w;
			if(randomd() < w / totalWeight)
				@newColony = p.pl;
		}

		if(newColony !is null)
			return colonize(newColony);
		else
			return null;
	}

	array<PotentialColonize@> potentials;
	void checkSystem(SystemAI@ sys) {
		uint presentMask = sys.seenPresent;
		if(presentMask & ai.mask == 0) {
			if(!ai.behavior.colonizeEnemySystems && (presentMask & ai.enemyMask) != 0)
				return;
			if(!ai.behavior.colonizeNeutralOwnedSystems && (presentMask & ai.neutralMask) != 0)
				return;
			if(!ai.behavior.colonizeAllySystems && (presentMask & ai.allyMask) != 0)
				return;
		}

		double sysWeight = 1.0;
		if(presentMask & ai.mask == 0)
			sysWeight *= ai.behavior.weightOutwardExpand;

		uint plCnt = sys.planets.length;
		for(uint n = 0; n < plCnt; ++n) {
			Planet@ pl = sys.planets[n];
			Empire@ visOwner = pl.visibleOwnerToEmp(ai.empire);
			if(!pl.valid || visOwner.valid)
				continue;
			if(isColonizing(pl))
				continue;
			if(penaltySet.contains(pl.id))
				continue;
			if(pl.quarantined)
				continue;

			int resId = pl.primaryResourceType;
			if(resId == -1)
				continue;

			PotentialColonize p;
			@p.pl = pl;
			@p.resource = getResource(resId);
			p.weight = 1.0 * sysWeight;
			//TODO: this should be weighted according to the position of the planet,
			//we should try to colonize things in favorable positions
			potentials.insertLast(p);
		}
	}

	double nextPotentialCheck = 0.0;
	array<PotentialColonize@>@ getPotentialColonize() {
		if(gameTime < nextPotentialCheck)
			return potentials;

		potentials.length = 0;
		for(uint i = 0, cnt = systems.owned.length; i < cnt; ++i)
			checkSystem(systems.owned[i]);
		for(uint i = 0, cnt = systems.outsideBorder.length; i < cnt; ++i)
			checkSystem(systems.outsideBorder[i]);

		if(systems.owned.length == 0) {
			Region@ homeSys = ai.empire.HomeSystem;
			if(homeSys !is null) {
				auto@ homeAI = systems.getAI(homeSys);
				if(homeAI !is null)
					checkSystem(homeAI);
			}
			else {
				for(uint i = 0, cnt = systems.all.length; i < cnt; ++i) {
					if(systems.all[i].visible)
						checkSystem(systems.all[i]);
				}
			}
		}

		if(potentials.length == 0 && gameTime < 60.0)
			nextPotentialCheck = gameTime + 1.0;
		else
			nextPotentialCheck = gameTime + randomd(10.0, 40.0);

		//TODO: This should be able to colonize across empires we have trade agreements with?
		return potentials;
	}

	bool canColonize() {
		if(remainColonizations == 0)
			return false;
		if(curColonizations >= ai.behavior.guaranteeColonizations) {
			if(!budget.canSpend(BT_Colonization, 0, ai.behavior.colonizeBudgetCost))
				return false;
		}
		if(ai.behavior.maxConcurrentColonizations <= colonizing.length)
			return false;
		return true;
	}

	void doColonize() {
		remainColonizations -= 1;
		curColonizations += 1;
		budget.spend(BT_Colonization, 0, ai.behavior.colonizeBudgetCost);
	}

	ColonizeData@ genericExpand() {
		auto@ potentials = getPotentialColonize();

		//Do generic expansion using any remaining colonization steps we have
		if(ai.behavior.colonizeGenericExpand) {
			double totalWeight = 0;
			PotentialColonize@ expand;

			for(uint i = 0, cnt = potentials.length; i < cnt; ++i) {
				auto@ p = potentials[i];
				double weight = p.weight * getGenericUsefulness(p.resource);
				modPotentialWeight(p, weight);

				Region@ reg = p.pl.region;
				if(reg is null)
					continue;
				if(reg.PlanetsMask & ai.mask != 0)
					continue;
				if(weight == 0)
					continue;
				totalWeight += weight;
				if(randomd() < weight / totalWeight)
					@expand = p;
			}

			if(expand !is null) {
				auto@ data = colonize(expand.pl);
				potentials.remove(expand);
				return data;
			}
		}
		return null;
	}

	void turn() {
		//Figure out how much we can colonize
		remainColonizations = ai.behavior.maxColonizations;

		prevColonizations = curColonizations;
		curColonizations = 0;

		updateSources();

		if(log) {
			ai.print("Empire colonization standings at "+formatGameTime(gameTime)+":");
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ other = getEmpire(i);
				if(other.major)
					ai.print("  "+ai.pad(other.name, 20)+" - "+ai.pad(other.TotalPlanets.value+" planets", 15)+" - "+other.points.value+" points");
			}
		}
	}

	bool shouldQueueFor(const ResourceSpec@ spec, ColonizeQueue@ inside = null) {
		auto@ list = inside is null ? this.queue : inside.children;
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ q = list[i];

			//haven't managed to resolve it fully, skip it as well
			if(spec.type == RST_Level_Specific) {
				if(q.spec.type == RST_Level_Specific && q.spec.level == spec.level) {
					if(!isResolved(q))
						return false;
				}
			}

			//Check anything inner to this tree element
			if(!shouldQueueFor(spec, q))
				return false;
		}

		return true;
	}

	bool shouldQueueFor(ImportData@ imp, ColonizeQueue@ inside = null) {
		auto@ list = inside is null ? this.queue : inside.children;
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ q = list[i];

			//If we already have this in our queue tree, don't colonize it again
			if(imp.forLevel) {
				if(q.forData is imp)
					return false;
				if(q.parent !is null && q.parent.step !is null && q.parent.step.target is imp.obj) {
					if(q.spec == imp.spec)
						return false;
				}
			}

			//If we're already trying to get something of this level, but we
			//haven't managed to resolve it fully, skip it as well
			if(imp.spec.type == RST_Level_Specific) {
				if(q.spec.type == RST_Level_Specific && q.spec.level == imp.spec.level) {
					if(!isResolved(q))
						return false;
				}
			}

			//Check anything inner to this tree element
			if(!shouldQueueFor(imp, q))
				return false;
		}

		return true;
	}

	ColonizeQueue@ queueColonize(ResourceSpec& spec, bool place = true) {
		ColonizeQueue q;
		@q.spec = spec;

		if(place)
			queue.insertLast(q);
		return q;
	}

	bool unresolvedInQueue() {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			auto@ q = queue[i];
			if(q.parent !is null)
				continue;
			if(!isResolved(q))
				return true;
		}
		return false;
	}

	bool isResolved(ColonizeQueue@ q) {
		if(q.step is null || q.step.canceled)
			return false;
		for(uint i = 0 , cnt = q.children.length; i < cnt; ++i) {
			if(!isResolved(q.children[i]))
				return false;
		}
		return true;
	}

	bool isResolved(ImportData@ req, ColonizeQueue@ inside = null) {
		auto@ list = inside is null ? this.queue : inside.children;
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ q = list[i];
			if(q.forData is req)
				return isResolved(q);
			if(isResolved(req, inside=q))
				return true;
		}
		return false;
	}

	Planet@ resolve(ColonizeQueue@ q) {
		if(q.step !is null)
			return q.step.target;

		auto@ potentials = getPotentialColonize();
		PotentialColonize@ take;
		double takeWeight = 0.0;

		for(uint i = 0, cnt = potentials.length; i < cnt; ++i) {
			auto@ p = potentials[i];
			if(!q.spec.meets(p.resource))
				continue;

			if(p.weight > takeWeight) {
				takeWeight = p.weight;
				@take = p;
			}
		}

		if(take !is null) {
			@q.target = take.pl;
			potentials.remove(take);

			array<ResourceSpec@> allReqs;
			for(uint i = 1, cnt = take.resource.level; i <= cnt; ++i) {
				const PlanetLevel@ lvl = getPlanetLevel(take.pl, i);
				if(lvl !is null) {
					array<ResourceSpec@> reqList;
					array<ResourceSpec@> curReqs;
					curReqs = allReqs;

					const ResourceRequirements@ reqs = lvl.reqs;
					for(uint i = 0, cnt = reqs.reqs.length; i < cnt; ++i) {
						auto@ need = reqs.reqs[i];

						bool found = false;
						for(uint n = 0, ncnt = curReqs.length; n < ncnt; ++n) {
							if(curReqs[n].implements(need)) {
								found = true;
								curReqs.removeAt(n);
								break;
							}
						}

						if(!found)
							reqList.insertLast(implementSpec(need));
					}

					reqList.sortDesc();

					auto@ resRace = cast<RaceResources>(race);
					if(resRace !is null)
						resRace.levelRequirements(take.pl, i, reqList);

					for(uint i = 0, cnt = reqList.length; i < cnt; ++i) {
						auto@ spec = reqList[i];
						allReqs.insertLast(spec);

						auto@ inner = queueColonize(spec, place=false);

						@inner.parent = q;
						q.children.insertLast(inner);

						resolve(inner);
					}
				}
			}

			return take.pl;
		}

		return null;
	}

	void kill(ColonizeQueue@ q) {
		for(uint i = 0, cnt = q.children.length; i < cnt; ++i)
			kill(q.children[i]);
		q.children.length = 0;
		if(q.forData !is null)
			q.forData.isColonizing = false;
		@q.parent = null;
	}

	void modPotentialWeight(PotentialColonize@ c, double& weight) {
		if(colonizeWeightObj !is null)
			weight /= c.pl.position.distanceTo(colonizeWeightObj.position)/1000.0;
	}

	bool update(ColonizeQueue@ q) {
		//See if we can find a matching import request
		if(q.forData is null && q.parent !is null && q.parent.target !is null) {
			for(uint i = 0, cnt = resources.requested.length; i < cnt; ++i) {
				auto@ req = resources.requested[i];
				if(req.isColonizing)
					continue;
				if(req.obj !is q.parent.target)
					continue;
				if(req.spec != q.spec)
					continue;

				req.isColonizing = true;
				@q.forData = req;
			}
		}

		//Cancel everything if our request is already being met
		if(q.forData !is null && q.forData.beingMet) {
			kill(q);
			return false;
		}

		//If it's not resolved, try to resolve it
		if(q.target is null)
			resolve(q);
		
		//If the colonization failed, try to find a new planet for it
		if((q.step !is null && q.step.canceled) || (q.step is null && q.target !is null && !canBeColonized(q.target))) {
			auto@ potentials = getPotentialColonize();
			PotentialColonize@ take;
			double takeWeight = 0.0;

			for(uint i = 0, cnt = potentials.length; i < cnt; ++i) {
				auto@ p = potentials[i];
				if(!q.spec.meets(p.resource))
					continue;

				double w = p.weight;
				modPotentialWeight(p, w);

				if(w > takeWeight) {
					takeWeight = p.weight;
					@take = p;
				}
			}

			if(take !is null) {
				@q.target = take.pl;
				@q.step = null;
				potentials.remove(take);
			}
		}

		for(uint i = 0, cnt = q.children.length; i < cnt; ++i) {
			if(!update(q.children[i])) {
				@q.children[i].parent = null;
				q.children.removeAt(i);
				--i; --cnt;
			}
		}

		if(q.children.length == 0 && q.step !is null && q.step.completed) {
			if(q.forData !is null) {
				q.forData.isColonizing = false;

				PlanetAI@ plAI = planets.getAI(q.target);
				if(plAI !is null) {
					if(plAI.resources.length != 0) {
						WaitUsed wait;
						@wait.forData = q.forData;
						@wait.resource = plAI.resources[0];
						waiting.insertLast(wait);
						q.forData.isColonizing = true;
					}
				}
			}
			return false;
		}
		return true;
	}

	void updateQueue() {
		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			auto@ q = queue[i];
			if(!update(q)) {
				queue.removeAt(i);
				--i; --cnt;
			}
		}
	}

	bool orderFromQueue(ColonizeQueue@ inside = null) {
		auto@ list = inside is null ? this.queue : inside.children;
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ q = list[i];
			if(q.step is null && q.target !is null) {
				@q.step = colonize(q.target);
				return true;
			}

			if(orderFromQueue(q))
				return true;
		}
		return false;
	}

	void dumpQueue(ColonizeQueue@ inside = null) {
		auto@ list = inside is null ? this.queue : inside.children;

		string prefix = "";
		if(inside !is null) {
			prefix += " ";
			ColonizeQueue@ top = inside.parent;
			while(top !is null) {
				prefix += " ";
				@top = top.parent;
			}
		}

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ q = list[i];

			string txt = "- "+q.spec.dump();
			if(q.forData !is null)
				txt += " for request "+q.forData.obj.name+"";
			else if(q.parent !is null && q.parent.target !is null)
				txt += " for parent "+q.parent.target.name+"";
			if(q.target !is null)
				txt += " ==> "+q.target.name;
			print(prefix+txt);

			dumpQueue(q);
		}
	}

	void fillQueueFromRequests() {
		for(uint i = 0, cnt = resources.requested.length; i < cnt && remainColonizations > 0; ++i) {
			auto@ req = resources.requested[i];
			if(!req.isOpen)
				continue;
			if(!req.cycled)
				continue;
			if(req.claimedFor)
				continue;
			if(req.isColonizing)
				continue;

			if(shouldQueueFor(req)) {
				auto@ q = queueColonize(req.spec);
				@q.forData = req;
				req.isColonizing = true;
			}
		}
	}

};

AIComponent@ createColonization() {
	return Colonization();
}
