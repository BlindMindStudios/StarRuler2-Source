// Relations
// ---------
// Manages the relationships we have with other empires, including treaties, hatred, and wars.
//

import empire_ai.weasel.WeaselAI;

import empire_ai.weasel.Intelligence;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Planets;

import warandpeace;
import influence;
from influence_global import activeTreaties, influenceLock, joinTreaty, leaveTreaty, declineTreaty, Treaty, sendPeaceOffer, createTreaty, offerSurrender, demandSurrender, leaveTreatiesWith;

enum HateType {
	HT_SystemPresence,
	HT_FleetPresence,
	HT_COUNT
};

class Hate {
	uint type;
	double amount = 0.0;
	Object@ obj;
	SystemAI@ sys;

	void save(Relations& relations, SaveFile& file) {
		file << type;
		file << amount;
		file << obj;
		relations.systems.saveAI(file, sys);
	}

	void load(Relations& relations, SaveFile& file) {
		file >> type;
		file >> amount;
		file >> obj;
		@sys = relations.systems.loadAI(file);
	}

	bool get_valid() {
		if(type == HT_SystemPresence)
			return sys !is null;
		if(type == HT_FleetPresence)
			return obj !is null && sys !is null;
		return true;
	}

	bool update(AI& ai, Relations& relations, Relation& rel, double time) {
		if(type == HT_SystemPresence) {
			amount = 0.25;
			if(sys.seenPresent & rel.empire.mask == 0)
				return false;
			if(sys.seenPresent & ai.empire.mask == 0)
				return false;
		}
		else if(type == HT_FleetPresence) {
			if(!obj.valid || obj.owner !is rel.empire)
				return false;
			if(sys.seenPresent & ai.empire.mask == 0)
				return false;
			if(obj.region !is sys.obj)
				return false;
			if(obj.getFleetStrength() < 1000.0)
				amount = 0.1;
			else
				amount = 0.5;
		}

		rel.hate += amount * time;
		return true;
	}

	string dump() {
		switch(type) {
			case HT_SystemPresence:
				return "system presence in "+sys.obj.name;
			case HT_FleetPresence:
				return "fleet presence "+obj.name+" in "+sys.obj.name;
		}
		return "unknown";
	}
};

final class Relation {
	Empire@ empire;

	//Whether we've met this empire
	bool contacted = false;

	//Whether we're currently at war
	bool atWar = false;

	//Last time we tried to make peace
	double lastPeaceTry = 0;

	//Whether this is our war of aggression
	bool aggressive = false;

	//Whether this is our ally
	bool allied = false;

	//Our relationship data
	double hate = 0.0;
	array<Hate@> hates;

	//Masks
	uint borderedTo = 0;
	uint alliedTo = 0;

	//Whether we consider this empire a threat to us
	bool isThreat = false;

	//How much we would value having this empire as an ally
	double allyValue = 0.0;
	//How much we think we can beat this empire and all its allies
	double defeatable = 0.0;
	//Relative strength of this empire to us in a vacuum
	double relStrength = 0.0;

	//How much we've lost to them in this recent war
	double warLost = 0.0;
	//How much we've taken from them in this recent war
	double warTaken = 0.0;

	void save(Relations& relations, SaveFile& file) {
		file << contacted;
		file << atWar;
		file << aggressive;
		file << allied;

		file << hate;
		uint cnt = hates.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			hates[i].save(relations, file);

		file << borderedTo;
		file << alliedTo;
		file << isThreat;
		file << allyValue;
		file << defeatable;
		file << relStrength;
		file << warTaken;
		file << warLost;
		file << lastPeaceTry;
	}

	void load(Relations& relations, SaveFile& file) {
		file >> contacted;
		file >> atWar;
		file >> aggressive;
		file >> allied;

		file >> hate;
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Hate ht;
			ht.load(relations, file);
			if(ht.valid)
				hates.insertLast(ht);
		}

		file >> borderedTo;
		file >> alliedTo;
		file >> isThreat;
		file >> allyValue;
		file >> defeatable;
		file >> relStrength;
		file >> warTaken;
		file >> warLost;
		file >> lastPeaceTry;
	}

	void trackSystem(AI& ai, Relations& relations, SystemAI@ sys) {
		for(uint i = 0, cnt = hates.length; i < cnt; ++i) {
			auto@ ht = hates[i];
			if(ht.type != HT_SystemPresence)
				continue;
			if(ht.sys is sys)
				return;
		}

		Hate ht;
		ht.type = HT_SystemPresence;
		@ht.sys = sys;
		hates.insertLast(ht);

		if(relations.log)
			ai.print("Gain hate of "+empire.name+": "+ht.dump());
	}

	void trackFleet(AI& ai, Relations& relations, FleetIntel@ intel, SystemAI@ sys) {
		for(uint i = 0, cnt = hates.length; i < cnt; ++i) {
			auto@ ht = hates[i];
			if(ht.type != HT_FleetPresence)
				continue;
			if(ht.obj is intel.obj && ht.sys is sys)
				return;
		}

		Hate ht;
		ht.type = HT_FleetPresence;
		@ht.sys = sys;
		@ht.obj = intel.obj;
		hates.insertLast(ht);

		if(relations.log)
			ai.print("Gain hate of "+empire.name+": "+ht.dump());
	}

	void tick(AI& ai, Relations& relations, double time) {
		if(!contacted) {
			if(ai.empire.ContactMask & empire.mask != 0)
				contacted = true;
		}

		bool curWar = ai.empire.isHostile(empire);
		if(curWar != atWar)
			atWar = curWar;
		if(!atWar) {
			aggressive = false;
			warLost = 0.0;
			warTaken = 0.0;
			lastPeaceTry = 0.0;
		}

		borderedTo = relations.intelligence.get(empire).borderedTo;
		alliedTo = empire.mask | empire.mutualDefenseMask | empire.ForcedPeaceMask.value;

		defeatable = relations.intelligence.defeatability(alliedTo, ai.mask | ai.allyMask);
		relStrength = relations.intelligence.defeatability(ai.mask, empire.mask);
		isThreat = defeatable < 0.8 && (borderedTo & ai.empire.mask) != 0;

		//Check how valuable of an ally this empire would make
		allyValue = 1.0;
		for(uint i = 0, cnt = relations.relations.length; i < cnt; ++i) {
			auto@ other = relations.relations[i];
			if(other is null || other is this || other.empire is null)
				continue;
			if(other.borderedTo & empire.mask == 0)
				continue;
			if(alliedTo & empire.mask != 0)
				continue;

			if(other.atWar)
				allyValue *= 3.0;
			else if(other.isThreat)
				allyValue *= 1.5;
		}

		//Become aggressive here if we're aggressive against one of its allies
		if(atWar && !aggressive) {
			for(uint i = 0, cnt = relations.relations.length; i < cnt; ++i) {
				auto@ other = relations.relations[i];
				if(other is null || other is this || other.empire is null)
					continue;
				if(other.aggressive && this.alliedTo & other.empire.mask != 0) {
					aggressive = true;
					break;
				}
			}
		}

		//Update our hatred of them
		for(uint i = 0, cnt = hates.length; i < cnt; ++i) {
			if(!hates[i].update(ai, relations, this, time)) {
				if(relations.log)
					ai.print("Hate with "+empire.name+" expired: "+hates[i].dump());
				hates.removeAt(i);
				--i; --cnt;
			}
		}

		hate *= pow(ai.behavior.hateDecayRate, time / 60.0);
		if(ai.behavior.biased && !empire.isAI)
			hate += 1.0;

		//If we really really hate them, declare war
		if(!atWar || !aggressive) {
			double reqHate = 100.0;
			if(defeatable < 1.0)
				reqHate *= sqr(1.0 / defeatable);
			reqHate *= pow(2.0, relations.warCount());

			if(hate > reqHate && (!ai.behavior.passive || atWar) && defeatable >= ai.behavior.hatredWarOverkill) {
				//Make sure our other requirements for war are met
				if(relations.fleets.haveCombatReadyFleets()) {
					if(canDeclareWar(ai)) {
						if(relations.log)
							ai.print("Declaring hatred war on "+empire.name+": "+hate+" / "+reqHate);
						if(atWar)
							aggressive = true;
						else
							relations.declareWar(empire, aggressive=true);
					}
				}
			}
		}
	}

	bool isAllied(AI& ai) {
		return alliedTo & ai.empire.mask != 0;
	}

	bool canDeclareWar(AI& ai) {
		if(empire.SubjugatedBy !is null)
			return false;
		if(ai.empire.SubjugatedBy !is null)
			return false;
		if(!contacted)
			return false;
		if(ai.empire.ForcedPeaceMask & empire.mask != 0)
			return false;
		return true;
	}
};

class Relations : AIComponent {
	Intelligence@ intelligence;
	Systems@ systems;
	Fleets@ fleets;
	Planets@ planets;

	array<Relation@> relations;

	bool expansionLocked = false;
	double treatyRespond = 0;
	double treatyConsider = 0;

	double warPoints = 0.0;

	void create() {
		@intelligence = cast<Intelligence>(ai.intelligence);
		@fleets = cast<Fleets>(ai.fleets);
		@systems = cast<Systems>(ai.systems);
		@planets = cast<Planets>(ai.planets);
	}

	void start() {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp is ai.empire)
				continue;
			if(!emp.major)
				continue;

			Relation r;
			@r.empire = emp;

			if(relations.length <= uint(emp.index))
				relations.length = uint(emp.index)+1;
			@relations[emp.index] = r;
		}
	}

	void save(SaveFile& file) {
		uint cnt = relations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(relations[i] is null) {
				file.write0();
				continue;
			}

			file.write1();
			relations[i].save(this, file);
		}

		file << expansionLocked;
		file << treatyRespond;
		file << treatyConsider;
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		relations.length = cnt;

		for(uint i = 0; i < cnt; ++i) {
			if(!file.readBit())
				continue;

			@relations[i] = Relation();
			@relations[i].empire = getEmpire(i);
			relations[i].load(this, file);
		}

		file >> expansionLocked;
		file >> treatyRespond;
		file >> treatyConsider;
	}

	double getPointValue(Object@ obj) {
		if(obj is null)
			return 0.0;
		if(obj.isShip) {
			auto@ dsg = cast<Ship>(obj).blueprint.design;
			if(dsg !is null)
				return dsg.size;
		}
		else if(obj.isPlanet) {
			return 10.0 * pow(3.0, double(obj.level));
		}
		return 0.0;
	}

	void recordTakenFrom(Empire& emp, double amount) {
		if(!emp.valid)
			return;
		if(log)
			ai.print("Taken value "+amount+" from "+emp.name);
		auto@ rel = get(emp);
		if(rel !is null)
			rel.warTaken += amount;
	}

	void recordLostTo(Empire& emp, double amount) {
		if(!emp.valid)
			return;
		if(log)
			ai.print("Lost value "+amount+" to "+emp.name);
		auto@ rel = get(emp);
		if(rel !is null)
			rel.warLost += amount;
	}

	void recordLostTo(Empire& emp, Object@ obj) {
		recordLostTo(emp, getPointValue(obj));
	}

	void recordTakenFrom(Empire& emp, Object@ obj) {
		recordTakenFrom(emp, getPointValue(obj));
	}

	Relation@ get(Empire@ emp) {
		if(emp is null)
			return null;
		if(!emp.major)
			return null;
		if(uint(emp.index) >= relations.length)
			return null;
		return relations[emp.index];
	}

	bool isFightingWar(bool aggressive = false) {
		for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
			if(relations[i] is null)
				continue;
			if(relations[i].atWar) {
				if(!aggressive || relations[i].aggressive)
					return true;
			}
		}
		return false;
	}

	uint warCount() {
		uint count = 0;
		for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
			if(relations[i] is null)
				continue;
			if(relations[i].atWar)
				count += 1;
		}
		return count;
	}

	void declareWar(Empire@ onEmpire, bool aggressive = true) {
		//Break all treaties
		leaveTreatiesWith(ai.empire, onEmpire.mask);

		//Declare actual war
		auto@ rel = get(onEmpire);
		rel.aggressive = aggressive;
		::declareWar(ai.empire, onEmpire);
	}

	uint sysIdx = 0;
	uint relIdx = 0;
	void tick(double time) override {
		//Find new ways to hate other empires
		if(systems.all.length != 0) {
			sysIdx = (sysIdx+1) % systems.all.length;
			auto@ sys = systems.all[sysIdx];
			if(sys.owned && sys.seenPresent & ~ai.mask != 0) {
				for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
					auto@ rel = relations[i];
					if(rel is null)
						continue;
					if(sys.seenPresent & rel.empire.mask != 0)
						rel.trackSystem(ai, this, sys);
				}
			}
		}

		if(relations.length != 0) {
			relIdx = (relIdx+1) % relations.length;
			auto@ rel = relations[relIdx];
			auto@ itl = intelligence.intel[relIdx];
			if(rel !is null && itl !is null) {
				for(uint i = 0, cnt = itl.fleets.length; i < cnt; ++i) {
					if(!itl.fleets[i].visible)
						continue;

					auto@ inSys = systems.getAI(itl.fleets[i].obj.region);
					if(inSys !is null && inSys.owned)
						rel.trackFleet(ai, this, itl.fleets[i], inSys);
				}
			}
		}
	}

	uint relInd = 0;
	void focusTick(double time) override {
		//Update our current relations
		if(relations.length != 0) {
			relInd = (relInd+1) % relations.length;
			if(relations[relInd] !is null)
				relations[relInd].tick(ai, this, time);
		}

		//Compute how many points we have in total that can be taken
		warPoints = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(fleets.fleets[i].obj);
			if(ship !is null && ship.valid && ship.owner is ai.empire)
				warPoints += getPointValue(ship);
		}
		for(uint i = 0, cnt = planets.planets.length; i < cnt; ++i) {
			Planet@ pl = cast<Planet>(planets.planets[i].obj);
			if(pl !is null && pl.valid && pl.owner is ai.empire)
				warPoints += getPointValue(pl);
		}

		//Become aggressive if we cannot expand anywhere anymore
		expansionLocked = true;
		for(uint i = 0, cnt = systems.outsideBorder.length; i < cnt; ++i) {
			auto@ sys = systems.outsideBorder[i];
			if(sys.seenPresent == 0) {
				bool havePlanets = false;
				for(uint n = 0, ncnt = sys.planets.length; n < ncnt; ++n) {
					if(sys.planets[n].quarantined)
						continue;
					havePlanets = true;
					break;
				}
				if(havePlanets) {
					expansionLocked = false;
					break;
				}
			}
		}

		//Deal with our AI's aggressive behavior
		if(ai.behavior.aggressive || (expansionLocked && ai.behavior.aggressiveWhenBoxedIn && !ai.behavior.passive)) {
			//Try to make sure we're always fighting at least one aggressive war
			bool atWar = false, aggro = false;
			for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
				if(relations[i] is null)
					continue;
				if(relations[i].atWar) {
					atWar = true;
					if(relations[i].aggressive)
						aggro = true;
				}
			}

			if(!atWar) {
				if(fleets.haveCombatReadyFleets()) {
					//Declare war on people who share our border and are defeatable
					Empire@ best;
					double bestWeight = 0;

					for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
						auto@ rel = relations[i];
						if(rel is null)
							continue;

						auto@ intel = intelligence.get(rel.empire);
						if(intel.shared.length == 0 && intel.theirBorder.length == 0)
							continue;
						if(!rel.canDeclareWar(ai))
							continue;
						if(!ai.behavior.biased || rel.empire.isAI) {
							if(rel.defeatable < ai.behavior.aggressiveWarOverkill)
								continue;
						}

						double w = rel.defeatable * rel.hate;
						if(rel.isAllied(ai))
							w *= 0.01;
						if(w > bestWeight) {
							bestWeight = w;
							@best = rel.empire;
						}
					}

					if(best !is null) {
						if(log)
							ai.print("Declare aggressive war against "+best.name);
						declareWar(best, aggressive=true);
					}
				}
			}
			else if(!aggro) {
				//Start going aggressive on someone defeatable we are already at war with
				Empire@ best;
				double bestWeight = 0;

				for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
					auto@ rel = relations[i];
					if(rel is null)
						continue;
					if(!rel.atWar)
						continue;
					if(rel.defeatable < ai.behavior.aggressiveWarOverkill)
						continue;

					double w = rel.defeatable * rel.hate;
					if(w > bestWeight) {
						bestWeight = w;
						@best = rel.empire;
					}
				}

				if(best !is null) {
					//Go aggressive then!
					if(log)
						ai.print("Become aggressive against "+best.name);
					get(best).aggressive = true;
				}
			}
		}

		//Respond to treaties
		if(gameTime > treatyRespond) {
			treatyRespond = gameTime + randomd(8.0, 20.0);

			Treaty@ respondTreaty;

			{
				Lock lck(influenceLock);
				for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
					auto@ trty = activeTreaties[i];
					if(trty.inviteMask & ai.mask != 0 && trty.presentMask & ai.mask == 0) {
						Message msg;
						trty.write(msg);

						@respondTreaty = Treaty();
						respondTreaty.read(msg);
						break;
					}
				}
			}

			if(respondTreaty !is null) {
				bool accept = false;
				Empire@ invitedBy = respondTreaty.leader;
				if(invitedBy is null)
					@invitedBy = respondTreaty.joinedEmpires[0];
				Relation@ other = get(invitedBy);

				if(respondTreaty.hasClause("SubjugateClause")) {
					//This is a surrender offer or demand
					if(respondTreaty.leader is null) {
						//An offer
						accept = true;
					}
					else if(respondTreaty.joinedEmpires.length != 0) {
						//A demand
						auto@ other = get(respondTreaty.joinedEmpires[0]);
						if(other.defeatable < ai.behavior.surrenderMinStrength) {
							if(warPoints / (other.warLost + warPoints) < ai.behavior.acceptSurrenderRatio) {
								accept = true;
							}
						}
					}
				}
				else if(respondTreaty.hasClause("MutualDefenseClause")
						|| respondTreaty.hasClause("AllianceClause")) {
					//This is an alliance treaty
					if(other.atWar) {
						//Need to be at peace first
						accept = false;
					}
					else {
						//See if this empire can help us defeat someone
						if(other.allyValue >= 3.0 && other.relStrength >= 0.5)
							accept = true;
					}
				}
				else if(respondTreaty.hasClause("PeaceClause")) {
					//This is a peace offering
					accept = shouldPeace(other);
				}
				else if(respondTreaty.hasClause("VisionClause")) {
					//This is a vision sharing treaty
					if(other !is null)
						accept = !other.isThreat && !other.atWar && other.hate <= 50.0;
				}
				else if(respondTreaty.hasClause("TradeClause")) {
					//This is a trade sharing treaty
					if(other !is null)
						accept = !other.isThreat && !other.atWar && other.hate <= 10.0;
				}

				if(accept) {
					if(log)
						ai.print("Accept treaty: "+respondTreaty.name, emp=invitedBy);
					joinTreaty(ai.empire, respondTreaty.id);
				}
				else {
					if(log)
						ai.print("Reject treaty: "+respondTreaty.name, emp=invitedBy);
					declineTreaty(ai.empire, respondTreaty.id);
				}
			}
		}

		//See if we should send a treaty over to someone
		if(gameTime > treatyConsider) {
			treatyConsider = gameTime + randomd(100.0, 300.0);

			uint offset = randomi(0, relations.length-1);
			for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
				auto@ other = relations[(i+offset) % cnt];
				if(other is null)
					continue;

				//Check if we should make peace with them
				if(other.atWar) {
					if(other.lastPeaceTry < gameTime - 600.0 && shouldPeace(other, isOffer=true)) {
						if(other.aggressive)
							other.aggressive = false;
						if(log)
							ai.print("Send peace offer.", emp=other.empire);
						other.lastPeaceTry = gameTime;
						sendPeaceOffer(ai.empire, other.empire);
						break;
					}
				}

				if(other.atWar) {
					//Check if we should try to surrender to them
					if(other.defeatable < ai.behavior.surrenderMinStrength) {
						if(warPoints / (other.warLost + warPoints) < ai.behavior.offerSurrenderRatio) {
							if(log)
								ai.print("Send surrender offer.", emp=other.empire);
							offerSurrender(ai.empire, other.empire);
							break;
						}
					}

					//Check if we should try to demand their surrender
					if(other.defeatable >= 1.0 / ai.behavior.surrenderMinStrength && other.warTaken >= warPoints * 0.1) {
						if(log)
							ai.print("Demand surrender.", emp=other.empire);
						demandSurrender(ai.empire, other.empire);
						break;
					}
				}

				//Check if we should try to ally with them
				if(!other.atWar && !other.isThreat && other.allyValue >= 3.0) {
					Treaty treaty;
					treaty.addClause(getInfluenceClauseType("AllianceClause"));
					treaty.addClause(getInfluenceClauseType("VisionClause"));
					treaty.addClause(getInfluenceClauseType("MutualDefenseClause"));

					if(treaty.canInvite(ai.empire, other.empire)) {
						treaty.inviteMask = other.empire.mask;

						//Generate treaty name
						string genName;
						uint genCount = 0;
						for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
							auto@ reg = getSystem(i).object;
							if(reg.TradeMask & (ai.mask | other.empire.mask) != 0) {
								genCount += 1;
								if(randomd() < 1.0 / double(genCount))
									genName = reg.name;
							}
						}
						treaty.name = format(locale::TREATY_NAME_GEN, genName);

						if(log)
							ai.print("Send alliance offer.", emp=other.empire);
						createTreaty(ai.empire, treaty);
					}
				}
			}
		}
	}

	bool shouldPeace(Relation@ other, bool isOffer = false) {
		bool accept = false;
		if(other.aggressive) {
			//We're trying to conquer these people, don't accept peace unless
			//we're fighting someone scarier or we're losing
			double otherWar = 0.0;
			uint otherInd = uint(-1);
			for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
				auto@ rel = relations[i];
				if(rel is null || rel is other)
					continue;
				if(rel.empire.mask & other.alliedTo != 0)
					continue;
				if(!rel.atWar)
					continue;
				otherWar = max(otherWar, rel.defeatable);
				otherInd = i;
			}

			if(otherInd != uint(-1) && otherWar < other.defeatable) {
				accept = true;
				if(!relations[otherInd].aggressive)
					relations[otherInd].aggressive = otherWar >= ai.behavior.aggressiveWarOverkill;
			}
			else if(other.defeatable < 0.25) {
				accept = true;
			}
		}
		else {
			//We don't have any ~particular qualms with these people, peace should be good
			if(!isOffer) {
				if(other.defeatable < 0.5 || other.hate < 50.0)
					accept = true;
			}
		}
		return accept;
	}

	void turn() override {
		if(log) {
			ai.print("Relations Report on Empires:");
			ai.print(" war points: "+warPoints);
			for(uint i = 0, cnt = relations.length; i < cnt; ++i) {
				auto@ rel = relations[i];
				if(rel is null)
					continue;
				ai.print(" "+ai.pad(rel.empire.name, 15)
						+" war: "+ai.pad(rel.atWar+" / "+rel.aggressive, 15)
						+" threat: "+ai.pad(""+rel.isThreat, 8)
						+" defeatable: "+ai.pad(toString(rel.defeatable,2), 8)
						+" hate: "+ai.pad(toString(rel.hate,0), 8)
						+" ally value: "+ai.pad(toString(rel.allyValue,1), 8)
						+" taken: "+ai.pad(toString(rel.warTaken,1), 8)
						+" lost: "+ai.pad(toString(rel.warLost,1), 8)
				);
			}
		}
	}
};

AIComponent@ createRelations() {
	return Relations();
}

void relationRecordLost(AI& ai, Empire& emp, Object@ obj) {
	cast<Relations>(ai.relations).recordLostTo(emp, obj);
}
