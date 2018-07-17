import resources;
import research;
import influence_global;
import buildings;
import void declareWar(Empire@ from, Empire& to) from "warandpeace";

string[] planetNames = {
	"Nist",
	"Tullio",
	"Centris",
	"Paquil",
	"Standev"
};

int64 expendHash() {
	return int64(ACT_Expend) << ACT_BIT_OFFSET;
}

bool isTargetOf(BasicAI@ ai, const InfluenceVoteStub@ vote, Empire@ emp) {
	if(vote.targets is null)
		return false;
	
	for(uint i = 0, cnt = vote.targets.targets.length; i < cnt; ++i) {
		auto@ targ = vote.targets.targets[i];
		switch(targ.type) {
			case TT_Empire:
				if(targ.emp is emp) {
					return true;
				}
				break;
			case TT_Object:
				{
					if(vote.type is getInfluenceVoteType("AnnexSystem")) {
						auto@ reg = ai.getPlanRegion(targ.obj);
						if(reg !is null)
							if(reg.planetMask & emp.mask != 0)
								return true;
					}
					else {
						if(targ.obj !is null && targ.obj.owner is emp)
							return true;
					}
				} break;
		}
	}
	return false;
}
	
class ExpendResources : Action {
	bool idleColony = true;
	Action@ queued = null;
	Action@ expandQueue = null;
	int64 qhash = 0, eqhash = 0;
	uint nextStep = randomi(0,100);

	ExpendResources() {
	}

	ExpendResources(BasicAI@ ai, SaveFile& msg) {
		msg >> idleColony;
		msg >> qhash;
		if(msg >= SV_0019)
			msg >> eqhash;
	}

	void postLoad(BasicAI@ ai) {
		if(qhash != 0)
			@queued = ai.locateAction(qhash);
		if(eqhash != 0)
			@expandQueue = ai.locateAction(eqhash);
		@expandQueue = null;
		//TODO: Actually don't save/load this
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << idleColony;

		if(queued !is null)
			qhash = queued.hash;
		else
			qhash = 0;
		msg << qhash;
		
		if(expandQueue !is null)
			eqhash = expandQueue.hash;
		else
			eqhash = 0;
		msg << eqhash;
	}
	
	int64 get_hash() const {
		return expendHash();
	}

	ActionType get_actionType() const {
		return ACT_Expend;
	}
	
	string get_state() const {
		return "Spending spare resources";
	}
	
	uint totalSupport = 0;
	const InfluenceCardType@ cardNamePlanet, cardEnhance, cardInvestigate, cardSpy, cardLeverage, cardAnnex, cardRider,
								cardProtect, cardUprising;
	const InfluenceVoteType@ annexVote, annexSysVote, investigate;
	
	array<const InfluenceCardType@> sites, supports, hardSupport;
	array<const InfluenceVoteType@> siteVotes;
	
	void fillCardTypes() {
		@cardNamePlanet = getInfluenceCardType("NamePlanet");
		@cardEnhance = getInfluenceCardType("Enhance");
		@cardInvestigate = getInfluenceCardType("Investigate");
		@cardSpy = getInfluenceCardType("Spy");
		@cardLeverage = getInfluenceCardType("Leverage");
		@cardAnnex = getInfluenceCardType("AnnexPlanet");
		@cardRider = getInfluenceCardType("Rider");
		@cardProtect = getInfluenceCardType("ProtectSystem");
		@cardUprising = getInfluenceCardType("Uprising");
		
		supports.insertLast(getInfluenceCardType("Negotiate"));
		supports.insertLast(getInfluenceCardType("EnergyClash"));
		supports.insertLast(getInfluenceCardType("AncientIntuition"));
		supports.insertLast(getInfluenceCardType("Intelligence"));
		
		hardSupport.insertLast(getInfluenceCardType("Promises"));
		hardSupport.insertLast(getInfluenceCardType("Assurances"));
		hardSupport.insertLast(getInfluenceCardType("Rhetoric"));
		
		sites.insertLast(getInfluenceCardType("UnitedResearch"));
		sites.insertLast(getInfluenceCardType("SenateBuilding"));
		sites.insertLast(getInfluenceCardType("GalaxyMall"));
		
		siteVotes.insertLast(getInfluenceVoteType("UnitedResearch"));
		siteVotes.insertLast(getInfluenceVoteType("SenateBuilding"));
		
		@annexVote = getInfluenceVoteType("AnnexPlanet");
		@annexSysVote = getInfluenceVoteType("AnnexSystem");
		@investigate = getInfluenceVoteType("Investigate");
	}
	
	bool opposeVote(BasicAI@ ai, const InfluenceVoteStub@ vote, array<InfluenceCard>& cards, bool useHard = false) {
		InfluenceCard@ fallback;
	
		uint off = randomi(0,cards.length-1);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ card = cards[(i+off) % cnt];
			auto@ type = card.type;
			if(supports.find(type) >= 0) {
				Targets targs = card.targets;
				targs[0].filled = true;
				targs[0].side = false;
				playInfluenceCard_server(ai.empire, card.id, targs, vote.id);
				return true;
			}
			else if(type is cardLeverage) {
				//Will probably usually fail, but we hate the server
				Targets targs = card.targets;
				targs[0].filled = true;
				targs[0].side = false;
				playInfluenceCard_server(ai.empire, card.id, targs, vote.id);
				return true;
			}
			else if(fallback is null && useHard && hardSupport.find(type) >= 0) {
				@fallback = card;
			}
		}
		
		if(fallback !is null) {
			Targets targs = fallback.targets;
			targs[0].filled = true;
			targs[0].side = false;
			playInfluenceCard_server(ai.empire, fallback.id, targs, vote.id);
			return true;
		}
		
		return false;
	}
	
	bool supportVote(BasicAI@ ai, const InfluenceVoteStub@ vote, array<InfluenceCard>& cards, bool useHard = false) {
		InfluenceCard@ fallback;
		int influence = ai.empire.Influence;
	
		uint off = randomi(0,cards.length-1);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ card = cards[(i+off) % cnt];
			
			auto@ type = card.type;
			if(supports.find(type) >= 0) {
				Targets targs = card.targets;
				targs[0].filled = true;
				targs[0].side = true;
				if(card.getPlayCost(null, targs) > influence)
					continue;
				playInfluenceCard_server(ai.empire, card.id, targs, vote.id);
				return true;
			}
			else if(type is cardLeverage) {
				//Will probably usually fail, but we hate the server
				Targets targs = card.targets;
				targs[0].filled = true;
				targs[0].side = true;
				if(card.getPlayCost(null, targs) > influence)
					continue;
				playInfluenceCard_server(ai.empire, card.id, targs, vote.id);
				return true;
			}
			else if(fallback is null && useHard && hardSupport.find(type) >= 0) {
				@fallback = card;
			}
		}
		
		if(fallback !is null) {
			Targets targs = fallback.targets;
			targs[0].filled = true;
			targs[0].side = true;
			playInfluenceCard_server(ai.empire, fallback.id, targs, vote.id);
			return true;
		}
		
		return false;
	}
	
	bool playRider(BasicAI@ ai, const InfluenceVoteStub@ vote, array<InfluenceCard>& cards) {
		uint off = randomi(0,cards.length-1);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ card = cards[(i+off) % cnt];
			auto@ type = card.type;
			if(type is cardRider) {
				Targets targs = card.targets;
				playInfluenceCard_server(ai.empire, card.id, targs, vote.id);
				return true;
			}
		}
		
		return false;
	}
	
	bool playRandomAction(BasicAI@ ai, array<InfluenceCard>& cards) {
		if(cards.length == 0)
			return false;
		int influence = ai.empire.Influence;
		auto@ card = cards[randomi(0,cards.length-1)];
		for(uint i = 0; (card.type.cls == ICC_Support || card.getPlayCost(null, null) > influence) && i < 5; ++i)
			@card = cards[randomi(0,cards.length-1)];
		Targets targs = card.targets;
		
		if(card.type is cardNamePlanet) {
			if(ai.usesMotherships)
				return false;
			Planet@ pl = ai.homeworld;
			if(pl is null || pl.owner !is ai.empire || pl.named)
				if(ai.factories.length > 0)
					@pl = cast<Planet>(ai.factories[randomi(0, ai.factories.length-1)]);
				else
					@pl = null;
			
			if(pl !is null && pl.owner is ai.empire && !pl.named) {
				auto@ targPlanet = targs[0];
				targPlanet.filled = true;
				@targPlanet.obj = @pl;
				
				auto@ targName = targs[1];
				targName.filled = true;
				if(pl is ai.homeworld)
					targName.str = ai.empire.name + " Prime";
				else
					targName.str = planetNames[randomi(0,planetNames.length-1)];
				
				playInfluenceCard_server(ai.empire, card.id, targs);
				return true;
			}
		}
		else if(card.type is cardAnnex) {
			SysSearch search;
			auto@ sys = search.random(ai.exploredSystems);
			if(sys !is null) {
				Planet@ pl;
				uint ownerMask = 0xffffffff & ~(ai.empire.mask | ai.allyMask | 1);
				if(sys.planetMask & ownerMask != 0) {
					for(uint i = 0, cnt = sys.planets.length; i < cnt; ++i) {
						Planet@ p = sys.planets[i];
						if(p.owner.mask & ownerMask != 0) {
							@pl = p;
							break;
						}
					}
				}
			
				if(pl !is null) {
					auto@ targPlanet = targs[0];
					targPlanet.filled = true;
					@targPlanet.obj = pl;
					
					playInfluenceCard_server(ai.empire, card.id, targs);
					return true;
				}
			}
		}
		else if(sites.find(card.type) >= 0) {
			if(totalSupport < 3)
				return false;
			
			auto@ targPlanet = targs[0];
			targPlanet.filled = true;
			@targPlanet.obj = @ai.homeworld;
			
			playInfluenceCard_server(ai.empire, card.id, targs);
			return true;
		}
		else if(card.type is cardInvestigate) {
			if(totalSupport < 2)
				return false;
			
			auto@ targEmp = targs[0];
			if(!targEmp.filled || targEmp is null) {
				@targEmp.emp = getEmpire(randomi(0,getEmpireCount()-1));
				targEmp.filled = true;
			}
			
			if(targEmp.emp !is ai.empire && targEmp.emp.valid && !ai.empire.isHostile(targEmp.emp) && targEmp.emp.mask & ai.allyMask == 0) {
				playInfluenceCard_server(ai.empire, card.id, targs);
				return true;
			}
		}
		else if(card.type is cardEnhance && ai.skillDiplo >= DIFF_Hard) {
			auto@ targCard = targs[0];
			targCard.filled = true;
			targCard.id = cards[randomi(0,cards.length-1)].id;
			playInfluenceCard_server(ai.empire, card.id, targs);
			return true;
		}
		else if(card.type is cardSpy && ai.skillDiplo >= DIFF_Medium) {
			auto@ targEmp = targs[0];
			if(!targEmp.filled && ai.enemies.length > 0) {
				targEmp.filled = true;
				@targEmp.emp = ai.enemies[randomi(0,ai.enemies.length-1)];
			}
			
			if(targEmp.emp !is null && targEmp.emp.valid && ai.empire.isHostile(targEmp.emp)) {
				playInfluenceCard_server(ai.empire, card.id, targs);
				return true;
			}
		}
		else if(ai.protect !is null) {
			auto@ sys = ai.protect;
			if(card.type is cardProtect) {
				if(sys.region.ProtectedMask.value & ai.empire.mask == 0 && (sys.planetMask & sys.region.ContestedMask) & ai.empire.mask != 0) {
					auto@ targSys = targs[0];
					targSys.filled = true;
					@targSys.obj = sys.region;
					playInfluenceCard_server(ai.empire, card.id, targs);
					@ai.protect = null;
					return true;
				}
			}
			else if(card.type is cardUprising) {
				uint friendMask = ai.empire.mask | ai.allyMask;
				if((sys.planetMask & sys.region.ContestedMask) & friendMask != 0) {
					for(uint p = 0, pcnt = sys.planets.length; p < pcnt; ++p) {
						auto@ pl = sys.planets[p];
						if(pl.owner.mask & friendMask != 0 && pl.isContested && !pl.isProtected(ai.empire)) {
							auto@ targSys = targs[0];
							targSys.filled = true;
							@targSys.obj = pl;
							playInfluenceCard_server(ai.empire, card.id, targs);
							@ai.protect = null;
							return true;
						}
					}
				}
			}
		}
		
		return false;
	}
	
	array<InfluenceCard> cards;
	
	bool spendInfluence(BasicAI@ ai) {
		if(supports.length == 0)
			fillCardTypes();
		
		if(ai.empire.getInfluenceCardCount() != cards.length) {
			cards.length = 0;
			cards.syncFrom(ai.empire.getInfluenceCards());
			
			totalSupport = 0;
			for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
				auto@ card = cards[i];
				if(supports.find(card.type) >= 0) {
					auto amt = card.getWeight();
					if(amt != INDETERMINATE)
						totalSupport += amt;
				}
			}
		}
		
		if(cards.length != 0) {
			auto@ votes = getActiveInfluenceVotes_server();
			uint cnt = votes.length;
			uint off = randomi(0,cnt-1);
			for(uint i = 0; i < cnt; ++i) {
				auto@ vote = votes[(i+off) % cnt];
				int stance = 0;
				
				auto@ startRelation = ai.getRelation(vote.startedBy);
				
				if(vote.startedBy is ai.empire)
					stance = 2;
				else if(ai.empire.hostileMask & vote.startedBy.mask != 0)
					stance = -1;
				else if(isTargetOf(ai, vote, ai.empire))
					stance = -2;
				else if(vote.startedBy.mask & ai.allyMask != 0 || startRelation.standing > 50)
					stance = startRelation.standing > 75 ? 2 : 1;
				else if(siteVotes.find(vote.type) >= 0)
					stance = -1;
				else if(ai.getRelation(vote.startedBy).standing < -10)
					stance = -1;
				else if(ai.callOuts.contains(vote.id)) {
					stance = randomi(0,1) == 0 ? 1 : -1;
					ai.callOuts.erase(vote.id);
				}
				
				if(stance <= -1) {
					auto@ trueVote = getInfluenceVoteByID(vote.id);
					if(trueVote.totalFor > trueVote.totalAgainst) {
						if(trueVote.totalAgainst + totalSupport >= trueVote.totalFor) {
							if(opposeVote(ai, vote, cards, useHard = (stance == -2)))
								return true;
						}
						else {
							if(playRider(ai, vote, cards))
								return true;
						}
					}
				}
				else if(stance >= 1) {
					auto@ trueVote = getInfluenceVoteByID(vote.id);
					if(trueVote.totalFor <= trueVote.totalAgainst && trueVote.totalAgainst < trueVote.totalFor + totalSupport)
						if(supportVote(ai, vote, cards, useHard = (stance == 2)))
							return true;
				}
				else {
					if(playRider(ai, vote, cards))
						return true;
				}
			}
		}
	
		if(ai.empire.Influence > max(1, int(ai.empire.InfluenceCap * 0.5))) {
			if(randomi(0,3) != 0)
				if(playRandomAction(ai, cards))
					return true;

			auto@ cards = getInfluenceStack();
			if(cards.length > 0) {
				buyCardFromInfluenceStack(ai.empire, cards[min(randomi(0, cards.length-1), randomi(0, cards.length-1))].id, pay=true);
				return true;
			}
		}
		
		return false;
	}
	
	array<TechnologyNode@> techs;
	
	bool spendResearch(BasicAI@ ai) {
		if(techs.length == 0) {
			auto@ dat = ai.empire.getTechnologyNodes();
			TechnologyNode@ n = TechnologyNode();
			while(receive(dat, n)) {
				techs.insertLast(n);
				@n = TechnologyNode();
			}
		}
		
		double pts = ai.empire.ResearchPoints;
		
		uint offset = randomi(0,techs.length-1);
		for(uint i = 0, cnt = techs.length / (7 - ai.skillEconomy) + 1; i < cnt; ++i) {
			uint index = (i + offset) % techs.length;
			auto@ tech = techs[index];
			if(!tech.available || tech.bought)
				continue;
			double pointCost = tech.getPointCost(ai.empire);
			if(pointCost > 0 && pts > pointCost) {
				ai.empire.research(index, false);
				techs.length = 0;
				return true;
			}
		}
		return false;
	}
	
	bool perform(BasicAI@ ai) {
		switch(nextStep++ % 7) {
			case 0:
				if(ai.empire.ResearchPoints >= 100.0)
					if(spendResearch(ai))
						return false;
			//Fall through if there was nothing to spend
			case 1:
				//Export idle waters to idle foods
				//Otherwise, export idle foods to idle level 1s
				if(ai.skillEconomy >= DIFF_Medium && !ai.usesMotherships && !ai.isMachineRace) {
					auto@ foods = ai.getResourceList(RT_Food, onlyExportable=true);
					int water = ai.getResourceList(RT_Water, onlyExportable=true)[0];
					
					bool found = false;
					{
						auto@ waterWorlds = ai.planets[water].idle;
						if(waterWorlds.length > 0) {
							auto@ waterPl = waterWorlds[randomi(0,waterWorlds.length-1)];
							if(waterPl.Population > 0.9999 && waterPl.isPrimaryDestination(null)) {
								//Look for an idle level 0 food world in the same territory
								auto@ terr = waterPl.region.getTerritory(ai.empire);
								
								for(uint i = 0; i < foods.length; ++i) {
									auto@ foodWorlds = ai.planets[foods[i]].idle;
									if(foodWorlds.length == 0)
										continue;
									auto@ foodPl = foodWorlds[randomi(0,foodWorlds.length-1)];
									auto@ reg = foodPl.region;
									if(reg !is null && reg.getTerritory(ai.empire) is terr && foodPl.resourceLevel == 0 && foodPl.Population > 0.9999 && foodPl.isPrimaryDestination(null)) {
										found = true;
										waterPl.exportResource(0, foodPl);
										break;
									}
								}
							}
						}
					}
					
					if(!found && ai.skillEconomy >= DIFF_Hard) {
						Planet@ foodPl;
						for(uint i = 0; i < foods.length; ++i) {
							auto@ foodWorlds = ai.planets[foods[i]].idle;
							if(foodWorlds.length == 0)
								continue;
							auto@ pl = foodWorlds[randomi(0,foodWorlds.length-1)];
							if(pl.level == 0 && pl.Population > 0.9999 && pl.isPrimaryDestination(null)) {
								@foodPl = pl;
								break;
							}
						}
						
						if(foodPl !is null) {
							//Look for an idle level 1 resource world in the same territory
							auto@ terr = foodPl.region.getTerritory(ai.empire);
							auto@ level1s = ai.getResourceList(RT_LevelOne);
							
							for(uint i = 0, l1cnt = level1s.length; i < 3 && i < l1cnt; ++i) {
								auto@ level1Worlds = ai.planets[level1s[randomi(0,l1cnt-1)]].idle;
								if(level1Worlds.length == 0)
									continue;
								auto@ level1Pl = level1Worlds[randomi(0,level1Worlds.length-1)];
								if(level1Pl.region.getTerritory(ai.empire) is terr && level1Pl.resourceLevel == 1 && level1Pl.isPrimaryDestination(null)) {
									found = true;
									foodPl.exportResource(0, level1Pl);
									break;
								}
							}
						}
					}
					
					if(found)
						break;
				}
			case 2:
				//Colonize food and water worlds (Without unbalancing the ratio too much)
				// We delay this behavior for 9 minutes, which is about when the homeworld can reach level 2 (otherwise we may colonize a useless water first)
				if(ai.skillEconomy >= DIFF_Medium && gameTime > 9.0 * 60.0 && !ai.isMachineRace) {
					auto@ foods = ai.getResourceList(RT_Food, onlyExportable=true);
					int water = ai.getResourceList(RT_Water, onlyExportable=true)[0];
					auto@ level1s = ai.getResourceList(RT_LevelOne);
					
					uint freeWaters = ai.planets[water].idle.length;
					uint freeFoods = 0;
					for(uint i = 0, cnt = foods.length; i < cnt; ++i)
						freeFoods += ai.planets[foods[i]].idle.length;
					
					bool busy = false;
					if(ai.empire.EstNextBudget > 300) {
						if(freeFoods <= freeWaters && freeFoods < 2) {
							ai.addIdle(ai.colonizeByResource(foods, execute=false));
							busy = true;
						}
						
						if(freeWaters <= freeFoods && freeWaters < 2) {
							ai.addIdle(ai.colonizeByResource(ai.getResourceList(RT_Water, onlyExportable=true), execute=false));
							busy = true;
						}
					}
					
					if(((freeFoods > 0 && freeWaters > 0) || ai.skillEconomy >= DIFF_Hard) && gameTime > 6.0 * 60.0) {
						//Improve level 1 resource planets to level 1
						//Otherwise, capture a new level 1
						for(uint i = 0, cnt = level1s.length; i < cnt; ++i) {
							PlanetList@ planets = ai.planets[level1s[i]];
							for(uint j = 0, jcnt = planets.idle.length; j < jcnt; ++j) {
								Planet@ planet = planets.idle[j];
								if(planet.resourceLevel < 1) {
									ai.addIdle(ai.requestPlanetImprovement(planet, 1));
									return false;
								}
							}
						}
						
						if(ai.empire.EstNextBudget > 300 || (freeFoods > 0 && freeWaters > 0)) {
							ai.addIdle(ai.colonizeByResource(level1s, execute=false));
							return false;
						}
					}
					
					if(busy)
						return false;
				}
			case 3:
				if(queued !is null) {
					if(ai.performAction(queued))
						@queued = null;
					return false;
				}
				
				{
					int freeBudget = min(ai.empire.RemainingBudget, ai.empire.EstNextBudget);

					if(freeBudget > 240 && ai.fleets[FT_Scout].length < 1) {
						@queued = ai.requestFleetBuild(FT_Scout);
						return false;
					}
					else if(!ai.usesMotherships && ai.skillEconomy >= DIFF_Medium && freeBudget > 450 && gameTime > 24.0 * 60.0 && ai.empire.FTLCapacity < 500.0) {
						//TODO: Mothership race can build an orbital instead
						Planet@ pl = ai.homeworld;
						if(pl !is null && pl.owner is ai.empire)
							ai.requestBuilding(pl, getBuildingType("FTLStorage"));
					}
					else if(ai.needsAltars && ai.empire.TotalPopulation > ai.empire.getAttribute(getEmpAttribute("AltarSupportedPopulation"))) {

						auto@ res = getResource("Altar");
						if(res is null)
							return false;

						auto@ altars = ai.planetsByResource[res.id];
						uint index = randomi(0, altars.length);
						if(index != 0) {
							Planet@ pl = altars.planets[index-1];
							if(pl !is null && pl.level < 5) {
								//We can't stick these in the strategy's @queued, because we may not always have the resources to level up a planet unilaterally.
								ai.addIdle(ai.requestPlanetImprovement(pl, pl.level+1));
								return false;
							}
						}

						Planet@ pl = ai.empire.planetList[randomi(0, ai.empire.planetCount - 1)];
						if(pl !is null)
							@queued = ai.requestBuilding(pl, getBuildingType("Altar"), force=true);
					}
					else if(ai.usesMotherships && freeBudget > 4800 && ai.fleets[FT_Mothership].length < 2) {
						@queued = ai.requestFleetBuild(FT_Mothership);
					}
					else if(ai.needsMainframes && ai.mainframeMod !is null && freeBudget >= 500) {
						//Make sure all factories have an available fling beacon
						if(ai.factories.length > 0) {
							auto@ factory = ai.factories[randomi(0, ai.factories.length - 1)];
							auto@ reg = factory.region;
							if(reg !is null) {
								Orbital@ orb = ai.empire.getClosestOrbital(ai.mainframeMod.id, reg.position);
								if(orb is null || orb.position.distanceTo(reg.position) > reg.radius) {
									@queued = ai.requestOrbital(reg, OT_Mainframe);
									return false;
								}
							}
						}
					}
					else {
						if(ai.ftl == FTL_Fling && freeBudget > 550) {
							//Make sure all factories have an available fling beacon
							if(ai.factories.length > 0) {
								auto@ factory = ai.factories[randomi(0, ai.factories.length - 1)];
								auto@ reg = factory.region;
								if(reg !is null && (!ai.empire.hasFlingBeacons || ai.empire.getFlingBeacon(factory.position) is null)) {
									@queued = ai.requestOrbital(reg, OT_FlingBeacon);
									return false;
								}
							}
						}
						else if(ai.ftl == FTL_Gate && freeBudget > 600 && ai.empire.FTLIncome > 1.0/3.0) {
							//Make sure all factories have an available fling beacon
							if(ai.factories.length > 0) {
								auto@ factory = ai.factories[randomi(0, ai.factories.length - 1)];
								auto@ reg = factory.region;
								if(reg !is null) {
									auto@ gate = ai.empire.getStargate(factory.position);
									if(gate is null || gate.position.distanceTo(factory.position) > 10000.0) {
										@queued = ai.requestOrbital(reg, OT_Gate);
										return false;
									}
								}
							}
						}
					
						int buildCost = 450;
						auto@ dsg = ai.dsgFlagships[FST_Combat];
						if(dsg !is null)
							buildCost = dsg.total(HV_BuildCost);

						int buildThres = buildCost * 2;
						if(ai.skillCombat >= DIFF_Medium)
							buildThres = min(buildThres, buildCost + 500);
						
						if(freeBudget > buildCost + 250 && ai.fleets[FT_Combat].length == 0) {
							@queued = ai.requestFleetBuild(FT_Combat);
							return false;
						}
						else if(freeBudget > buildThres) {
							@queued = ai.requestFleetBuild(FT_Combat);
							return false;
						} 
						else if(freeBudget > 250 && ai.skillEconomy > DIFF_Medium) {
							if(ai.factories.length > 0) {
								auto@ leader = ai.factories[randomi(0,ai.factories.length-1)];
								if(leader.valid && leader.owner is ai.empire)
									ai.fillFleet(leader, freeBudget - 150);
							}
						}
					}
				}
			case 4:
				if(ai.empire.EnergyStored > 1500) {
					Artifact@ artifact;
					switch(randomi(0,3)) {
						case 0:
							//Arcology
							if(ai.homeworld !is null && ai.homeworld.owner is ai.empire) {
								@artifact = ai.getArtifact(getArtifactType("NatureDevice"), ai.homeworld.region);
								if(artifact !is null) {
									artifact.activateAbilityFor(ai.empire, 0, ai.homeworld);
									return false;
								}
							}
							break;
						case 1:
							//Ancient Embassy
							@artifact = ai.getArtifact(getArtifactType("AncientEmbassy"));
							if(artifact !is null && ai.exploredSystems.length > 0) {
								//Choose a random system in another player's territory
								Region@ target;
								for(uint i = 0; i < 15; ++i) {
									auto@ sys = ai.exploredSystems[randomi(0,ai.exploredSystems.length-1)];
									if(sys.planetMask & ~(ai.empire.mask | 0x1) != 0) {
										@target = sys.region;
										break;
									}
								}
								
								if(target !is null) {
									vec2d off = random2d(target.radius * 0.5, target.radius * 0.8);
									artifact.activateAbilityFor(ai.empire, 0, target.position + vec3d(off.x, 0.0, off.y));
									return false;
								}
							}
							break;
						case 2:
							//Espionage Probe
							@artifact = ai.getArtifact(getArtifactType("SpyProbe"));
							if(artifact !is null && ai.exploredSystems.length > 0) {
								//Choose a random system in another player's territory
								Region@ target;
								for(uint i = 0; i < 15; ++i) {
									auto@ sys = ai.exploredSystems[randomi(0,ai.exploredSystems.length-1)];
									if(sys.planetMask & ~(ai.empire.mask | 0x1) != 0 && sys.region.VisionMask & ai.empire.visionMask != 0) {
										@target = sys.region;
										break;
									}
								}
								
								if(target !is null) {
									artifact.activateAbilityFor(ai.empire, 0, target);
									return false;
								}
							}
							break;
						case 3:
							//Revenant part
							switch(randomi(0,3)) {
								case 0: @artifact = ai.getArtifact(getArtifactType("RevenantCannon")); break;
								case 1: @artifact = ai.getArtifact(getArtifactType("RevenantCore")); break;
								case 2: @artifact = ai.getArtifact(getArtifactType("RevenantChassis")); break;
								case 3: @artifact = ai.getArtifact(getArtifactType("RevenantEngine")); break;
							}
							
							if(artifact !is null)
								artifact.activateAbilityFor(ai.empire, 0);
					}
				}
			case 5: {
				double forceExpand;
				if(ai.skillEconomy < DIFF_Medium)
					forceExpand = 10.0 * 60.0;
				else if(ai.skillEconomy < DIFF_Hard)
					forceExpand = 5.0 * 60.0;
				else
					forceExpand = 1.5 * 60.0;
				
				if(ai.timeSinceLastExpand > forceExpand && gameTime > 7.0 * 60.0) {
					ai.requestExpansion();
					return false;
				}
				}
			case 6:
				ai.requestExploration();
				return false;
		}
		
		return false;
	}
}

//
class MilitaryVictory : Action {
	Action@ awaiting;
	int64 ahash = 0;
	
	MilitaryVictory() {
	}

	MilitaryVictory(BasicAI@ ai, SaveFile& msg) {
		msg >> ahash;
	}

	void postLoad(BasicAI@ ai) {
		if(ahash != 0)
			@awaiting = ai.locateAction(ahash);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		if(awaiting !is null) {
			msg << awaiting.hash;
		}
		else {
			int64 tmp = 0;
			msg << tmp;
		}
	}
	
	int64 get_hash() const {
		return int64(STRAT_Military) << ACT_BIT_OFFSET;
	}

	ActionType get_actionType() const {
		return STRAT_Military;
	}
	
	string get_state() const {
		return "Winning by military";
	}
	
	double startupTime = gameTime;
	
	bool perform(BasicAI@ ai) {
		switch(randomi(0,3)) {
			case 0: case 1:
				ai.requestBudget();
				break;
			case 2:
				ai.requestDefense();
				break;
			case 3:
			{
				set_int prevEnemies;
				for(uint i = 0, cnt = ai.enemies.length; i < cnt; ++i)
					prevEnemies.insert(ai.enemies[i].id);
				ai.enemies.length = 0;
				ai.allyMask = 0;
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					Empire@ emp = getEmpire(i);
					if(emp.valid && emp.major && emp !is ai.empire) {
						if(emp.isHostile(ai.empire))
							ai.enemies.insertLast(emp);
						else if(emp.team == ai.empire.team && emp.team != -1)
							ai.allyMask |= emp.mask;
						else if(emp.SubjugatedBy is ai.empire || ai.empire.SubjugatedBy is emp)
							ai.allyMask |= emp.mask;
					}
				}
				
				bool warred = false;
				uint borderMask = 0;
				bool checkedBorder = false;
			
				//Only start wars if we aren't in any, or we're insane.
				// Delay this logic for a while after the game loads, as it takes a while for empire strengths to update
				if((ai.enemies.length == 0 || ai.behaviorFlags & AIB_QuickToWar != 0) && gameTime > startupTime + 60.0 && ai.empire.SubjugatedBy is null) {
					int strength = ai.empire.MilitaryStrength;
					Empire@ target;
					
					auto@ border = ai.getBorder();
					for(uint i = 0, cnt = border.length; i < cnt; ++i)
						borderMask |= border[i].planetMask;
					auto@ inner = ai.ourSystems;
					for(uint i = 0, cnt = inner.length; i < cnt; ++i)
						borderMask |= inner[i].planetMask;
					checkedBorder = true;
				
					uint base = randomi(0, getEmpireCount() - 1);
					for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
						Empire@ other = getEmpire((i + base) % cnt);
						if(other is ai.empire || !other.major || ai.empire.ContactMask.value & other.mask == 0)
							continue;
						if(ai.ignoreEmpire(other) || ai.allyMask & other.mask != 0)
							continue;
						
						if(other.SubjugatedBy is null && gameTime > ai.treatyWaits[other.index]) {
							if(ai.empire.isHostile(other)) {
								if((ai.empire.points.value + 200) / (other.points.value + 200) >= 5) {
									demandSurrender(ai.empire, other);
									ai.treatyWaits[other.index] = gameTime + randomd(120.0,240.0);
								}
							}
						}
						
						if(ai.enemies.find(other) >= 0)
							continue;
						
						if(ai.empire.isHostile(other)) {
							@target = other;
							break;
						}
						
						if(ai.behaviorFlags & AIB_QuickToWar != 0 && ai.empire.getTotalFleetStrength() > 100.0) {
							@target = other;
							break;
						}
						
						//Go to war depending on how we're doing against our opponents, and if we've been able to expand recently
						int pointStr = ai.empire.points.value - other.points.value;
						int otherStr = other.MilitaryStrength;
						
						uint revCount = 0, unownedRev = 4 - ai.revenantParts.length;
						for(uint j = 0, jcnt = ai.revenantParts.length; j < jcnt; ++j) {
							auto@ part = ai.revenantParts[j];
							if(part.valid && part.owner is other)
								++revCount;
						}
						
						bool casusBelli = false;
					
						double relation = pow(2.0, double(ai.getRelation(other).standing) / 100.0);
						
						if(borderMask & other.mask != 0) {
							if(strength - otherStr > 0 && (ai.timeSinceLastExpand > 9.0 * 60.0 * relation))
								casusBelli = true;
							else if(strength - otherStr >= 0 && (ai.timeSinceLastExpand > 12.0 * 60.0 * relation || pointStr < -320 * relation || revCount >= 2))
								casusBelli = true;
						}
						
						if(!casusBelli) {
							if(strength - otherStr >= 0 && pointStr < -2250 * relation)
								casusBelli = true;
							else if(strength - otherStr >= 0 && ai.timeSinceLastExpand > 20.0 * 60.0 * relation)
								casusBelli = true;
							else if(revCount >= 3 && (revCount + unownedRev) == 4)//That's a nice giant evil ship you've got there. Would be a shame if something happened to it.
								casusBelli = true;
						}
						
						if(casusBelli)
							@target = other;
					}
					
					if(target !is null) {
						if(target.SubjugatedBy is null && ai.empire.SubjugatedBy is null) {
							if(ai.empire.ForcedPeaceMask.value & target.mask != 0)
								leaveTreatiesWith(ai.empire, target.mask);
							declareWar(ai.empire, target);
						}
						ai.enemies.insertLast(target);
						ai.requestWar(target);
						auto@ relation = ai.getRelation(target);
						relation.standing = min(relation.standing - 35, 0);
						prevEnemies.insert(target.id);
						warred = true;
					}
					else {
						ai.requestBudget();
					}
				}
				
				if(ai.enemies.length != 0) {
					for(uint i = 0, cnt = ai.enemies.length; i < cnt; ++i) {
						if(!prevEnemies.contains(ai.enemies[i].id)) {
							auto@ enemy = ai.getRelation(ai.enemies[i]);
							if(enemy.standing >= 15)
								enemy.brokeAlliance = true;
							enemy.standing = min(enemy.standing - 35, 0);
							enemy.offense = RA_War;
						}
					}
					//Consider offering surrender if we're losing badly, or offer peace to an opponent
					//Otherwise, demand that our opponents surrender if we're winning
					Empire@ other = ai.enemies[randomi(0,ai.enemies.length-1)];
					if(ai.treatyWaits[other.index] < gameTime) {
						bool treated = false;
						int relation = ai.getRelation(other).standing * max(ai.empire.points.value / 400, 1);
						
						if((ai.empire.points.value + 200) / max(other.points.value + 200 + relation, 1) >= 5) {
							demandSurrender(ai.empire, other);
							treated = true;
						}
						else if((other.points.value + 250 + relation) / max(ai.empire.points.value + 250, 1) >= 5 && ai.empire.MilitaryStrength < other.MilitaryStrength) {
							offerSurrender(ai.empire, other);
							treated = true;
						}
						else if(ai.enemies.length > 1 && ai.behaviorFlags & AIB_QuickToWar == 0) {
							//Consider peace with a weak opponent
							Empire@ weakest;
							int weakestPoints = 0, totalPoints = 0;
							
							for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
								auto@ emp = getEmpire(i);
								if(emp.valid && emp.isHostile(ai.empire)) {
									int pts = emp.points.value;
									if(pts <= 0)
										continue;
									totalPoints += pts;
									
									//Consider opponents that have offered peace as 'weak'
									if(emp.PeaceMask.value & ai.empire.mask != 0)
										pts /= 3;
									
									pts -= relation;
									
									if(weakest is null || pts < weakestPoints) {
										weakestPoints = pts;
										@weakest = emp;
									}
								}
							}
							
							if(weakest is other && (totalPoints + 150) / max(ai.empire.points.value + 150, 1) >= 2) {
								sendPeaceOffer(ai.empire, other);
								treated = true;
							}
						}
						
						if(treated)
							ai.treatyWaits[other.index] = gameTime + randomd(120.0,240.0);	
					}
					
					if(!warred)
						ai.requestWar(ai.enemies[randomi(0, ai.enemies.length-1)]);
				}
			}
			break;
		}
	
		return false;
	}
}


//
class InfluenceVictory : Action, ObjectReceiver {
	Action@ awaiting;
	Planet@ improve;
	int64 ahash = 0;
	
	InfluenceVictory() {
	}

	InfluenceVictory(BasicAI@ ai, SaveFile& msg) {
		msg >> ahash;
		msg >> improve;
	}

	void postLoad(BasicAI@ ai) {
		if(ahash != 0)
			@awaiting = ai.locateAction(ahash);
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		if(awaiting !is null) {
			msg << awaiting.hash;
		}
		else {
			int64 tmp = 0;
			msg << tmp;
		}
		msg << improve;
	}
	
	int64 get_hash() const {
		return int64(STRAT_Influence) << ACT_BIT_OFFSET;
	}

	ActionType get_actionType() const {
		return STRAT_Influence;
	}
	
	bool giveObject(BasicAI@ ai, Object@ obj) {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null) {
			const ResourceType@ native = getResource(pl.primaryResourceType);
			if(native.tilePressure[TR_Influence] > 0 && pl.level < native.level) {
				@improve = pl;
				@awaiting = null;
			}
		}
		return true;
	}
	
	string get_state() const {
		return "Winning by influence";
	}
	
	bool perform(BasicAI@ ai) {
		switch(randomi(0,5)) {
			case 0: case 1:
				ai.requestBudget();
				return false;
			case 2:
				ai.requestDefense();
				return false;
		}
		
		if(awaiting !is null) {
			if(ai.performAction(awaiting))
				@awaiting = null;
		}
		else if(improve !is null) {
			const ResourceType@ native = getResource(improve.primaryResourceType);
			if(native.tilePressure[TR_Influence] > 0 && improve.level < native.level)
				@awaiting = ai.requestPlanetImprovement(improve, native.level);
			@improve = null;
		}
		else {
			int[] influenceRes;
			auto@ res = getResource("Plastics");
			if(res !is null)
				influenceRes.insertLast(res.id);
			@res = getResource("Spice");
			if(res !is null)
				influenceRes.insertLast(res.id);
			if(influenceRes.length != 0)
				ai.colonizeByResource(influenceRes, this);
		}
	
		return false;
	}
}
