int64 colonyHash(Planet@ target) {
	return (int64(ACT_Colonize) << ACT_BIT_OFFSET) | int64(target.id);
}

class Colonize : Action {
	bool requested = false;
	int64 Hash;
	Planet@ dest;
	Object@ source;
	float best = 0;
	SysSearch search;
	uint enroute = 0;
	bool colonyAttempted = false;
	
	Colonize(BasicAI@ ai, Planet@ target) {
		@dest = target;
		Hash = colonyHash(target);
	}

	Colonize(BasicAI@ ai, SaveFile& msg) {
		msg >> requested;
		msg >> Hash;
		msg >> source;
		msg >> dest;
		msg >> best;
		search.load(msg);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << requested;
		msg << Hash;
		msg << source;
		msg << dest;
		msg << best;
		search.save(msg);
		
		if(source !is null)
			enroute = 1;
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return Hash;
	}
	
	void reset(BasicAI@ ai) {
		if(source !is null && source.isShip)
			ai.freeFleet(cast<Ship>(source), FT_Mothership);
		@source = null;
		requested = false;
		best = 0;
		enroute = 0;
		search.reset();
	}

	ActionType get_actionType() const {
		return ACT_Colonize;
	}
	
	string get_state() const {
		if(dest is null)
			return "Nothing";
		else if(source is null)
			return "Colonizing " + dest.name;
		else
			return "Colonizing " + dest.name + " from " +  source.name;
	}
	
	Planet@ findSourcePlanet(BasicAI@ ai) {
		const uint tries = 8;
		for(uint try = 0; try < tries; ++try) {
			PlanRegion@ reg = search.next(ai.ourSystems);
			
			if(reg is null) {
				//The search is over, dispatch colony ships if possible
				if(source !is null) {
					return cast<Planet>(source);
				}
				else {
					reset(ai);
				}
				break;
			}
			else {
				for(uint i = 0, cnt = reg.planets.length; i < cnt; ++i) {
					Planet@ pl = reg.planets[i];
					if(pl is null || pl.owner !is ai.empire)
						continue;
					
					double pop = pl.population;
					if(pop < 1.5 || pl.isSendingColonyShips || pl.quarantined)
						continue;
					
					double maxPop = double(pl.maxPopulation);
					if(pop > maxPop * 0.5) {
						//Weight primarily by time (square root of distance due to newtonian motion)
						double weight = 1000.0 / pow(pl.position.distanceToSQ(dest.position), 0.25);
						
						//Strongly prefer planets near max population
						if(pop >= maxPop - 1.0)
							weight *= 8.0;
						//Prefer full planets
						weight *= pop / maxPop;
						
						if(weight > best) {
							@source = pl;
							best = float(weight);
						}
					}
				}	
			}
		}
		return null;
	}
	
	void sendColonizers(BasicAI@ ai, bool allowAuto = true) {
		if(ai.usesMotherships) {
			//Find an idle mothership and bring it over
			auto@ mother = ai.getAvailableFleet(FT_Mothership, build=false);
			if(mother !is null && !mother.hasOrders) {
				auto ablID = mother.findAbilityOfType(getAbilityID("MothershipColonize"));
				double range = mother.getAbilityRange(ablID, dest) * 0.99;
				moveToFastest(mother, dest.position + (mother.position - dest.position).normalize(range), ai.ftl);
				mother.addAbilityOrder(ablID, dest, range, append=true);
				@source = mother;
				ai.addIdle(this);
			}
			else if(mother !is null) {
				ai.freeFleet(mother, FT_Mothership);
			}
			return;
		}
	
		//Easy AIs use auto-colonize
		if(ai.skillEconomy < DIFF_Medium || allowAuto || ai.isMachineRace) {
			ai.empire.autoColonize(dest);
		}
		else {					
			//Multiple colony orders may try to request colonization from the same planet
			if(source !is null && source.isSendingColonyShips) {
				@source = null;
				best = 0;
			}
			
			findSourcePlanet(ai);
			if(source !is null) {
				ai.focus = source.position;
				source.colonize(dest, 1.0);
				requested = true;
				enroute += 1;
			}
		}
	}
	
	bool perform(BasicAI@ ai) {
		//Keep trying until the planet can't be colonized
		if(dest is null || !dest.valid) {
			reset(ai);
			return true;
		}
		
		Empire@ owner = dest.visibleOwnerToEmp(ai.empire);
		if(owner is null) {
			reset(ai);
			@dest = null;
			return true;
		}
		else if(owner.valid && owner !is ai.empire) {
			reset(ai);
			@dest = null;
			return true;
		}
		
		if(owner.valid && dest.Population >= 1.0) {
			ai.addPlanet(dest);
			ai.markAsColony(dest.region).scout(ai);
			@dest = null;
			reset(ai);
			return true;
		}
		
		ai.focus = dest.position;
		
		ai.addIdle(this);
	
		if(requested) {
			if(source is null || !source.valid || source.owner !is ai.empire || source.level < 1 || (dest.IncomingPop + dest.Population) >= 1.0)
				reset(ai);
			else if(source !is null && source.isShip && !source.hasOrders)
				reset(ai);
		}
		else if(!dest.isEmpireColonizing(ai.empire)) {
			sendColonizers(ai, allowAuto=true);
		}
		else if(enroute < 2 && ai.skillEconomy >= DIFF_Medium) {
			if(dest.IncomingPop + dest.Population > 0.99)
				colonyAttempted = true;
			
			//We may encounter some form of resistance during colonization
			// If so, brute force by sending ships from a second colony
			if(colonyAttempted && dest.IncomingPop + dest.Population < 1.0) {
				PlanRegion@ pr = ai.getPlanRegion(dest.region);
				if(pr !is null)
					sendColonizers(ai);
			}
		}
		
		return false;
	}
};

int64 expandHash() {
	return (int64(ACT_Expand) << ACT_BIT_OFFSET);
}

class Expand : Action {
	SysSearch search;
	Planet@ target;
	double started = 0.0;
	
	Expand() {
	}

	Expand(BasicAI@ ai, SaveFile& msg) {
		msg >> target;
		msg >> started;
		search.load(msg);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << target;
		msg << started;
		search.save(msg);
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return expandHash();
	}

	ActionType get_actionType() const {
		return ACT_Expand;
	}
	
	string get_state() const {
		if(target is null)
			return "Expanding";
		else
			return "Expanding to " + target.name;
	}
	
	bool expandable(BasicAI@ ai, Region@ region) {
		bool tradeable = false, bridge = false;
		uint mask = ai.empire.mask;	
		const SystemDesc@ system = getSystem(region);
		Territory@ prevTerr;
		
		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
			Region@ other = getSystem(system.adjacent[i]).object;
			auto@ terr = other.getTerritory(ai.empire);
			
			if(other.TradeMask & mask != 0) {
				tradeable = true;
				if(prevTerr is null)
					@prevTerr = terr;
				else
					bridge = true;
			}
			else {
				bridge = true;
			}
		}
		
		return tradeable && bridge;
	}
	
	bool perform(BasicAI@ ai) {
		if(target !is null) {
			if(!target.valid)
				@target = null;
			else if(target.owner is ai.empire)
				return true;
			else if(target.visibleOwnerToEmp(ai.empire).valid)
				@target = null;
			else if(gameTime - started > 300.0)
				@target = null;
		}

		PlanRegion@ reg = search.random(ai.exploredSystems);
		if(reg is null) {
			ai.requestExploration();
			return false;
		}
		
		if(!expandable(ai, reg.region))
			return false;

		Planet@ bestExp;
		double expScore = 0;

		for(uint i = 0, cnt = reg.planets.length; i < cnt; ++i) {
			Planet@ pl = reg.planets[i];
			auto@ owner = pl.visibleOwnerToEmp(ai.empire);
			if(owner !is null && !owner.valid && !pl.quarantined) {
				double score = 1.0;

				const ResourceType@ res = getResource(pl.primaryResourceType);
				if(res is null) {
					score /= 1000.0;
				}
				else {
					uint resCls = ai.classifyResource(res);
					bool isFoodWater = resCls == RT_Food || resCls == RT_Water;
					if(isFoodWater) {
						if(ai.isMachineRace)
							score /= 10.0;
						else
							score *= 10.0;
					}
					score /= double(res.level+1);
					score *= double(res.rarity)+1.0;
				}

				if(score > expScore) {
					expScore = score;
					@bestExp = pl;
				}
			}
		}

		if(bestExp !is null) {
			@target = bestExp;
			ai.requestColony(bestExp);
			started = gameTime;
		}
		
		return false;
	}
};

int64 colonyByResHash(array<int>@ res) {
	int64 Hash = (int64(ACT_ColonizeRes) << ACT_BIT_OFFSET) | int64(res.length);
	for(uint i = 0, cnt = res.length; i < cnt; ++i)
		Hash ^= int64(res[i]) << i;
	return Hash;
}

class ColonizeByResource : Action {
	int64 Hash;
	Planet@ target;
	uint nextOurIndex = 0, nextOtherIndex = 0;
	ObjectReceiver@ dest;
	int64 reqHash = 0, waitHash = 0;
	array<int>@ resources;
	
	PlanRegion@ expansion;
	Action@ waitingOn;
	
	ColonizeByResource(array<int>@ Resources, ObjectReceiver@ requester) {
		@dest = requester;
		@resources = Resources;
		
		Hash = colonyByResHash(Resources);
	}

	ColonizeByResource(BasicAI@ ai, SaveFile& msg) {
		msg >> Hash;
		msg >> target;
		msg >> nextOurIndex;
		msg >> nextOtherIndex;
		msg >> reqHash;

		uint cnt = 0;
		msg >> cnt;
		@resources = array<int>(cnt);
		for(uint i = 0; i < cnt; ++i)
			resources[i] = msg.readIdentifier(SI_Resource);
		
		Region@ reg;
		msg >> reg;
		if(reg !is null)
			@expansion = ai.getPlanRegion(reg);
		msg >> waitHash;
	}

	void postLoad(BasicAI@ ai) {
		if(reqHash != 0)
			@dest = cast<ObjectReceiver>(ai.locateAction(reqHash));
		if(waitHash != 0)
			@waitingOn = ai.locateAction(waitHash);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << Hash;
		msg << target;
		msg << nextOurIndex;
		msg << nextOtherIndex;

		if(dest !is null) {
			msg << cast<Action>(dest).hash;
		}
		else {
			int64 tmp = 0;
			msg << tmp;
		}

		uint cnt = resources.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg.writeIdentifier(SI_Resource, resources[i]);
		
		msg << (expansion is null ? null : expansion.region);
		msg << (waitingOn !is null ? waitingOn.hash : int64(0));
	}
	
	int64 get_hash() const {
		return Hash;
	}

	ActionType get_actionType() const {
		return ACT_ColonizeRes;
	}
	
	string get_state() const {
		if(target is null)
			return "Looking for source of "+getResource(resources[0]).name+" (+" + (resources.length-1) + " others) resources";
		else
			return "Awaiting ownership of " + target.name;
	}
	
	void reset() {
		nextOtherIndex = 0;
		nextOurIndex = 0;
		@target = null;
	}
	
	//TODO: Determine trade access based on territories instead
	bool isTradeable(BasicAI@ ai, Region@ region) {
		uint mask = ai.empire.mask;
		if(region.TradeMask & mask != 0)
			return true;
	
		const SystemDesc@ system = getSystem(region);
		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
			Region@ other = getSystem(system.adjacent[i]).object;
			if(other.TradeMask & mask != 0)
				return true;
		}
		
		if(ai.usesMotherships && ai.ourSystems.length == 0)
			return true;
		
		return false;
	}
	
	PlanRegion@ getBridgeSystem(BasicAI@ ai, PlanRegion@ to) {
		uint mask = ai.empire.mask;
		
		const SystemDesc@ system = to.system;
		for(uint i = 0, cnt = system.adjacent.length; i < cnt; ++i) {
			Region@ other = getSystem(system.adjacent[i]).object;
			if(isTradeable(ai, other))
				return ai.getPlanRegion(other);
		}
		
		return null;
	}
	
	bool searchForPlanets(BasicAI@ ai) {
		array<PlanRegion@>@ regions;
		uint index = 0;
		if(nextOurIndex < ai.ourSystems.length) {
			@regions = ai.ourSystems;
			index = nextOurIndex++;
			nextOtherIndex = 0;
		}
		else if(nextOtherIndex < ai.exploredSystems.length) {
			@regions = ai.exploredSystems;
			index = nextOtherIndex++;
		}
		else {
			nextOurIndex = 0;
			index = 0;
		}
		
		if(regions !is null) {			
			PlanRegion@ reg = regions[index];
			Planet@ wanted;
			for(uint i = 0, cnt = reg.planets.length; i < cnt; ++i) {
				ai.focus = reg.region.position;
			
				Planet@ pl = reg.planets[i];
				if(!pl.valid || pl.visibleOwnerToEmp(ai.empire).valid || pl.isEmpireColonizing(ai.empire) || pl.quarantined)
					continue;
				
				int native = reg.planetResources[i];
				if(resources.find(native) < 0)
					continue;
				
				@wanted = pl;
				break;
			}
			
			if(wanted !is null) {
				if(isTradeable(ai, reg.region)) {
					@target = wanted;
					@waitingOn = ai.requestColony(wanted);
					return true;
				}
				else {
					//Choose closer expansions that we can expand to
					PlanRegion@ bridge = getBridgeSystem(ai, reg);
					if(bridge !is null && (expansion is null || ai.homeworld is null || bridge.center.distanceToSQ(ai.homeworld.position) < expansion.center.distanceToSQ(ai.homeworld.position))) {
						for(uint i = 0, cnt = bridge.planets.length; i < cnt; ++i) {
							auto@ pl = bridge.planets[i];
							if(!pl.valid)
								continue;
							auto@ owner = pl.visibleOwnerToEmp(ai.empire);
							if(owner !is null && !owner.valid) {
								@expansion = bridge;
								return true;
							}
						}
						
						@expansion = bridge;
					}
				}
			}
			
			return false;
		}
		else if(expansion !is null) {
			Planet@ bestExp;
			double expScore = 0;

			for(uint i = 0, cnt = expansion.planets.length; i < cnt; ++i) {
				Planet@ pl = expansion.planets[i];
				if(!pl.visibleOwnerToEmp(ai.empire).valid) {
					double score = 1.0;

					const ResourceType@ res = getResource(pl.primaryResourceType);
					if(res is null) {
						score /= 1000.0;
					}
					else {
						uint resCls = ai.classifyResource(res);
						bool isFoodWater = resCls == RT_Food || resCls == RT_Water;
						if(isFoodWater) {
							if(ai.isMachineRace)
								score /= 10.0;
							else
								score *= 10.0;
						}
						score /= double(res.level+1);
						score *= double(res.rarity)+1.0;
					}

					if(score > expScore) {
						expScore = score;
						@bestExp = pl;
					}
				}
			}

			if(bestExp !is null) {
				@waitingOn = ai.requestColony(bestExp);
				@expansion = null;
			}
			
			if(waitingOn is null) {
				@waitingOn = ai.requestOrbital(expansion.region, OT_TradeOutpost);
			}
			
			return true;
		}
		else {
			//We can't find the resource we need anywhere, explore some more
			ai.requestExploration();
			return true;
		}
	}
	
	bool perform(BasicAI@ ai) {
		if(waitingOn !is null) {
			if(ai.performAction(waitingOn))
				@waitingOn = null;
			return false;
		}
	
		if(target !is null) {
			if(target.owner is ai.empire) {
				if(dest is null || dest.giveObject(ai, target))
					return true;
				else
					reset();
			}
			else if(target.owner.valid) {
				reset();
			}
		}
		else {
			const uint tries = 8;
			for(uint i = 0; i < tries; ++i)
				if(searchForPlanets(ai))
					break;
		}
		
		return false;
	}
};

int64 populateHash(Planet@ target) {
	return (int64(ACT_Populate) << ACT_BIT_OFFSET) | int64(target.id);
}

class Populate : Action {
	int64 Hash;
	Planet@ dest;
	Object@ source;
	
	Populate(BasicAI@ ai, Planet@ target) {
		@dest = target;
		Hash = populateHash(target);
	}

	Populate(BasicAI@ ai, SaveFile& msg) {
		msg >> source;
		msg >> dest;
		Hash = populateHash(dest);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << source;
		msg << dest;
	}

	void postLoad(BasicAI@ ai) {
	}
	
	int64 get_hash() const {
		return Hash;
	}
	
	void reset(BasicAI@ ai) {
		if(source !is null && source.isShip)
			ai.freeFleet(cast<Ship>(source), FT_Mothership);
		@source = null;
		ai.removeIdle(this);
	}

	ActionType get_actionType() const {
		return ACT_Populate;
	}
	
	string get_state() const {
		if(dest is null)
			return "Nothing";
		else if(source is null)
			return "Populating " + dest.name;
		else
			return "Populating " + dest.name + " from " +  source.name;
	}
	
	bool perform(BasicAI@ ai) {
		//Keep trying until the planet can't be colonized
		if(dest is null || !dest.valid) {
			reset(ai);
			return true;
		}
		
		if(dest.Population >= dest.maxPopulation - 0.001) {
			reset(ai);
			return true;
		}
		
		if(!ai.usesMotherships)
			return true;
		
		if(source is null) {
			auto@ mother = ai.getAvailableFleet(FT_Mothership, build=false);
			if(mother !is null && !mother.hasOrders) {
				auto ablID = mother.findAbilityOfType(getAbilityID("MothershipColonize"));
				double range = mother.getAbilityRange(ablID, dest) * 0.99;
				moveToFastest(mother, dest.position + (mother.position - dest.position).normalize(range), ai.ftl);
				mother.addAbilityOrder(ablID, dest, range, append=true);
				@source = mother;
				ai.addIdle(this);
			}
			else if(mother !is null) {
				ai.freeFleet(mother, FT_Mothership);
			}
		}
		else if(!source.valid || source.owner !is ai.empire || !source.hasOrders) {
			@source = null;
		}
		
		return false;
	}
};
