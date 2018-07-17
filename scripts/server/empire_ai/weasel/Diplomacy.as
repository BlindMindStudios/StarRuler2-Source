// Diplomacy
// ---------
// Acts as an adaptor for using the generically developed DiplomacyAI.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Development;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Resources;
import empire_ai.weasel.War;
import empire_ai.weasel.Intelligence;

import influence;
from empire_ai.DiplomacyAI import DiplomacyAI, VoteData, CardAI, VoteState;

import systems;

class Diplomacy : DiplomacyAI, IAIComponent {
	Systems@ systems;
	Fleets@ fleets;
	Planets@ planets;
	Construction@ construction;
	Development@ development;
	Resources@ resources;
	War@ war;
	Intelligence@ intelligence;

	//Adapt to AI component
	AI@ ai;
	double prevFocus = 0;
	bool logCritical = false;
	bool logErrors = true;

	double getPrevFocus() { return prevFocus; }
	void setPrevFocus(double value) { prevFocus = value; }

	void setLog() { log = true; }
	void setLogCritical() { logCritical = true; }

	void set(AI& ai) { @this.ai = ai; }
	void start() {}

	void tick(double time) {}
	void turn() {}

	void postLoad(AI& ai) {}
	void postSave(AI& ai) {}
	void loadFinalize(AI& ai) {}

	//Actual AI component implementations
	void create() {
		@systems = cast<Systems>(ai.systems);
		@fleets = cast<Fleets>(ai.fleets);
		@planets = cast<Planets>(ai.planets);
		@development = cast<Development>(ai.development);
		@construction = cast<Construction>(ai.construction);
		@resources = cast<Resources>(ai.resources);
		@war = cast<War>(ai.war);
		@intelligence = cast<Intelligence>(ai.intelligence);
	}

	//IMPLEMENTED BY DiplomacyAI
	/*void save(SaveFile& file) {}*/
	/*void load(SaveFile& file) {}*/

	uint nextStep = 0;
	void focusTick(double time) {
		summarize();

		switch(nextStep++ % 3) {
			case 0:
				buyCards();
			break;
			case 1:
				considerActions();
			break;
			case 2:
				considerVotes();
			break;
		}
	}

	//Adapt to diplomacy AI
	Empire@ get_empire() {
		return ai.empire;
	}

	uint get_allyMask() {
		return ai.allyMask;
	}

	int getStanding(Empire@ emp) {
		//TODO: Use relations module for this generically
		if(emp.isHostile(ai.empire))
			return -50;
		if(ai.allyMask & emp.mask != 0)
			return 100;
		return 0;
	}

	void print(const string& str) {
		ai.print(str);
	}

	Object@ considerImportantPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			Object@ obj = development.focuses[i].obj;
			double w = hook.consider(this, targets, vote, card, obj);
			if(w > bestWeight) {
				@best = obj;
				bestWeight = w;
			}
		}

		return best;
	}

	Object@ considerOwnedPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		//Consider our important ones first
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			Object@ obj = development.focuses[i].obj;
			double w = hook.consider(this, targets, vote, card, obj);
			if(w > bestWeight) {
				@best = obj;
				bestWeight = w;
			}
		}

		//Consider some random other ones
		uint planetCount = planets.planets.length;
		if(planetCount != 0) {
			uint offset = randomi(0, planetCount-1);
			for(uint n = 0; n < 5; ++n) {
				Object@ obj = planets.planets[(offset+n) % planetCount].obj;
				double w = hook.consider(this, targets, vote, card, obj);
				if(w > bestWeight) {
					@best = obj;
					bestWeight = w;
				}
			}
		}

		return best;
	}

	Object@ considerImportantSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			Object@ obj = development.focuses[i].obj.region;
			if(obj is null)
				continue;
			double w = hook.consider(this, targets, vote, card, obj);
			if(w > bestWeight) {
				@best = obj;
				bestWeight = w;
			}
		}

		return best;
	}

	Object@ considerOwnedSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		//Consider our important ones first
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i) {
			Object@ obj = development.focuses[i].obj.region;
			if(obj is null)
				continue;
			double w = hook.consider(this, targets, vote, card, obj);
			if(w > bestWeight) {
				@best = obj;
				bestWeight = w;
			}
		}

		//Consider some random other ones
		uint sysCount = systems.owned.length;
		if(sysCount != 0) {
			uint offset = randomi(0, sysCount-1);
			for(uint n = 0; n < 5; ++n) {
				Object@ obj = systems.owned[(offset+n) % sysCount].obj;
				double w = hook.consider(this, targets, vote, card, obj);
				if(w > bestWeight) {
					@best = obj;
					bestWeight = w;
				}
			}
		}

		return best;
	}

	Object@ considerDefendingSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = war.battles.length; i < cnt; ++i) {
			auto@ battle = war.battles[i];
			Region@ sys = battle.system.obj;
			if(sys.SiegedMask & empire.mask == 0)
				continue;

			double w = hook.consider(this, targets, vote, card, sys);
			if(w > bestWeight) {
				@best = sys;
				bestWeight = w;
			}
		}

		return best;
	}

	Object@ considerDefendingPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = war.battles.length; i < cnt; ++i) {
			auto@ battle = war.battles[i];
			Region@ sys = battle.system.obj;
			if(sys.SiegedMask & empire.mask == 0)
				continue;

			for(uint n = 0, ncnt = battle.system.planets.length; n < ncnt; ++n) {
				Object@ pl = battle.system.planets[n];
				if(pl.owner !is empire)
					continue;

				double w = hook.consider(this, targets, vote, card, pl);
				if(w > bestWeight) {
					@best = pl;
					bestWeight = w;
				}
			}
		}

		return best;
	}

	Object@ considerEnemySystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(!empire.isHostile(emp))
				continue;

			auto@ intel = intelligence.get(emp);
			if(intel is null)
				continue;

			for(uint n = 0, ncnt = intel.theirBorder.length; n < ncnt; ++n) {
				auto@ sysIntel = intel.theirBorder[n];

				double w = hook.consider(this, targets, vote, card, sysIntel.obj);
				if(w > bestWeight) {
					@best = sysIntel.obj;
					bestWeight = w;
				}
			}
		}

		return best;
	}

	Object@ considerEnemyPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(!empire.isHostile(emp))
				continue;

			auto@ intel = intelligence.get(emp);
			if(intel is null)
				continue;

			for(uint n = 0, ncnt = intel.theirBorder.length; n < ncnt; ++n) {
				auto@ sysIntel = intel.theirBorder[n];

				for(uint j = 0, jcnt = sysIntel.planets.length; j < jcnt; ++j) {
					Planet@ pl = sysIntel.planets[j];
					if(pl.visibleOwnerToEmp(empire) !is emp)
						continue;

					double w = hook.consider(this, targets, vote, card, pl);
					if(w > bestWeight) {
						@best = pl;
						bestWeight = w;
					}
				}
			}
		}

		return best;
	}

	Object@ considerFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		Object@ best;
		double bestWeight = 0.0;
		for(uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			Object@ fleet = fleets.fleets[i].obj;
			if(fleet !is null) {
				double w = hook.consider(this, targets, vote, card, fleet);
				if(w > bestWeight) {
					@best = fleet;
					bestWeight = w;
				}
			}
		}
		return best;
	}

	Object@ considerEnemyFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestWeight = 0.0;
		Object@ best;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(!empire.isHostile(emp))
				continue;

			auto@ intel = intelligence.get(emp);
			if(intel is null)
				continue;

			for(uint n = 0, ncnt = intel.fleets.length; n < ncnt; ++n) {
				auto@ flIntel = intel.fleets[n];
				if(!flIntel.known)
					continue;

				double w = hook.consider(this, targets, vote, card, flIntel.obj);
				if(w > bestWeight) {
					@best = flIntel.obj;
					bestWeight = w;
				}
			}
		}

		return best;
	}

	Object@ considerMatchingImportRequests(const CardAI& hook, Targets& targets, VoteState@ vote, const InfluenceCard@ card, const ResourceType@ type, bool considerExisting) {
		Object@ best;
		double bestWeight = 0.0;
		for(uint i = 0, cnt = resources.requested.length; i < cnt; ++i) {
			ImportData@ req = resources.requested[i];
			if(req.spec.meets(type)) {
				double w = hook.consider(this, targets, vote, card, req.obj, null);
				if(w > bestWeight) {
					bestWeight = w;
					@best = req.obj;
				}
			}
		}
		if(considerExisting) {
			for(uint i = 0, cnt = resources.used.length; i < cnt; ++i) {
				ExportData@ res = resources.used[i];
				ImportData@ req = res.request;
				if(req !is null && req.spec.meets(type)) {
					double w = hook.consider(this, targets, vote, card, req.obj, res.obj);
					if(w > bestWeight) {
						bestWeight = w;
						@best = req.obj;
					}
				}
			}
		}
		return best;
	}
};

IAIComponent@ createDiplomacy() {
	return Diplomacy();
}
