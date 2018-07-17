import empire_ai.DiplomacyAI;

class DiplomacyAction : DiplomacyAI, Action {
	BasicAI@ ai;

	DiplomacyAction(BasicAI@ ai) {
		@this.ai = ai;
	}

	DiplomacyAction(BasicAI@ ai, SaveFile& file) {
		@this.ai = ai;
		load(file);
	}

	void save(BasicAI@, SaveFile& file) {
		save(file);
	}

	string get_state() const {
		return "DiplomacyAI";
	}

	Empire@ get_empire() {
		return ai.empire;
	}

	uint get_allyMask() {
		return ai.allyMask;
	}

	int64 get_hash() const {
		return int64(ACT_Diplomacy) << ACT_BIT_OFFSET;
	}

	ActionType get_actionType() const {
		return ACT_Diplomacy;
	}

	int getStanding(Empire@ emp) {
		auto@ rel = ai.getRelation(emp);
		return rel.standing;
	}

	void print(const string& str) {
		::print(empire.name+": "+str);
	}

	Object@ considerOwnedPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Object@ hw = ai.empire.Homeworld;
		if(hw !is null && hw.valid && hw.owner is empire) {
			double w = hook.consider(this, targets, vote, card, hw);
			if(w != 0.0) {
				@best = hw;
				bestW = w;
			}
		}

		auto@ reso = getRandomResource(randomi(0, 3));
		if(reso !is null) {
			auto@ list = ai.planetsByResource[reso.id];
			for(uint i = 0, cnt = list.length; i < cnt; ++i) {
				Object@ pl = list.planets[i];

				double w = hook.consider(this, targets, vote, card, pl);
				if(w > bestW) {
					bestW = w;
					@best = pl;
				}
			}
		}
		return best;
	}

	Object@ considerImportantPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Object@ hw = ai.empire.Homeworld;
		if(hw !is null && hw.valid && hw.owner is empire) {
			double w = hook.consider(this, targets, vote, card, hw);
			if(w != 0.0) {
				@best = hw;
				bestW = w;
			}
		}

		auto@ reso = getRandomResource(randomi(2, 3));
		if(reso !is null) {
			auto@ list = ai.planetsByResource[reso.id];
			for(uint i = 0, cnt = list.length; i < cnt; ++i) {
				Object@ pl = list.planets[i];

				double w = hook.consider(this, targets, vote, card, pl);
				if(w > bestW) {
					bestW = w;
					@best = pl;
				}
			}
		}
		return best;
	}

	Object@ considerOwnedSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Object@ hw = ai.empire.Homeworld;
		if(hw !is null && hw.valid && hw.owner is empire) {
			Region@ reg = hw.region;
			if(reg !is null) {
				double w = hook.consider(this, targets, vote, card, reg);
				if(w != 0.0) {
					@best = reg;
					bestW = w;
				}
			}
		}

		auto@ reso = getRandomResource(randomi(0, 3));
		if(reso !is null) {
			auto@ list = ai.planetsByResource[reso.id];
			for(uint i = 0, cnt = list.length; i < cnt; ++i) {
				Object@ pl = list.planets[i];
				Region@ reg = pl.region;
				if(reg !is null) {
					double w = hook.consider(this, targets, vote, card, reg);
					if(w > bestW) {
						bestW = w;
						@best = reg;
					}
				}
			}
		}
		return best;
	}

	Object@ considerImportantSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Object@ hw = ai.empire.Homeworld;
		if(hw !is null && hw.valid && hw.owner is empire) {
			Region@ reg = hw.region;
			if(reg !is null) {
				double w = hook.consider(this, targets, vote, card, reg);
				if(w != 0.0) {
					@best = reg;
					bestW = w;
				}
			}
		}

		auto@ reso = getRandomResource(randomi(2, 3));
		if(reso !is null) {
			auto@ list = ai.planetsByResource[reso.id];
			for(uint i = 0, cnt = list.length; i < cnt; ++i) {
				Object@ pl = list.planets[i];
				Region@ reg = pl.region;
				if(reg !is null) {
					double w = hook.consider(this, targets, vote, card, reg);
					if(w > bestW) {
						bestW = w;
						@best = reg;
					}
				}
			}
		}
		return best;
	}

	void markProtecting(Object@ obj) {
		@ai.protect = null;
	}

	Object@ considerDefendingSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		auto@ sys = ai.protect;
		if(sys is null)
			return null;

		uint friendMask = empire.mask | allyMask;
		if((sys.planetMask & sys.region.ContestedMask) & empire.mask != 0) {
			double w = hook.consider(this, targets, vote, card, sys.region);
			if(w > bestW) {
				bestW = w;
				@best = sys.region;
			}
		}

		return best;
	}

	Object@ considerDefendingPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		auto@ sys = ai.protect;
		if(sys is null)
			return null;

		uint friendMask = empire.mask | allyMask;
		if((sys.planetMask & sys.region.ContestedMask) & empire.mask != 0) {
			for(uint p = 0, pcnt = sys.planets.length; p < pcnt; ++p) {
				Object@ pl = sys.planets[p];
				double w = hook.consider(this, targets, vote, card, pl);
				if(w > bestW) {
					bestW = w;
					@best = sys.region;
				}
			}
		}

		return best;
	}

	Object@ considerEnemySystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		uint enemies = enemiesMask();
		for(uint n = 0; n < 5; ++n) {
			auto@ fromSys = ai.ourSystems[randomi(0,ai.ourSystems.length-1)];
			for(uint adj = 0, adjCnt = fromSys.system.adjacent.length; adj < adjCnt; ++adj) {
				auto@ otherSys = getSystem(fromSys.system.adjacent[adj]);
				Object@ other = otherSys.object;
				if(otherSys.object.PlanetsMask & enemies == 0)
					continue;

				double w = hook.consider(this, targets, vote, card, other);
				if(w > bestW) {
					bestW = w;
					@best = other;
				}
			}
		}
		return best;
	}

	Object@ considerEnemyPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		uint enemies = enemiesMask();
		for(uint n = 0; n < 5; ++n) {
			auto@ fromSys = ai.ourSystems[randomi(0,ai.ourSystems.length-1)];
			for(uint adj = 0, adjCnt = fromSys.system.adjacent.length; adj < adjCnt; ++adj) {
				auto@ otherSys = getSystem(fromSys.system.adjacent[adj]);
				Object@ other = otherSys.object;
				if(otherSys.object.PlanetsMask & enemies == 0)
					continue;

				auto@ stored = ai.findSystem(otherSys.object);
				if(stored is null)
					continue;

				uint off = randomi(0,stored.planets.length-1);
				for(uint i = 0, cnt = stored.planets.length; i < cnt; ++i) {
					Object@ pl = stored.planets[(i+off) % cnt];
					if(pl.owner.mask & enemies != 0) {
						double w = hook.consider(this, targets, vote, card, other);
						if(w > bestW) {
							bestW = w;
							@best = other;
						}
					}
				}

			}
		}
		return best;
	}

	Object@ considerFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Object@ flt = empire.getStrongestFleet();
		if(flt !is null) {
			double w = hook.consider(this, targets, vote, card, flt);
			if(w != 0.0) {
				@best = flt;
				bestW = w;
			}
		}

		return best;
	}

	Object@ considerEnemyFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		double bestW = 0.0;
		Object@ best;

		Empire@ ofEmp = getEmpire(randomi(0, getEmpireCount()-1));
		if(empire.isHostile(ofEmp)) {
			Object@ flt = ai.empire.getStrongestFleet();
			if(flt !is null && flt.isVisibleTo(ai.empire)) {
				double w = hook.consider(this, targets, vote, card, flt);
				if(w != 0.0) {
					@best = flt;
					bestW = w;
				}
			}
		}

		return best;
	}

	//Returns true if the action is finished
	uint nextStep = 0;
	bool perform(BasicAI@ ai) {
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
		return false;
	}

	void postLoad(BasicAI@ ai) {
	}
};

Action@ loadDiplomacyAI(BasicAI@ ai, SaveFile& file) {
	return DiplomacyAction(ai, file);
}

Action@ createDiplomacyAI(BasicAI@ ai) {
	return DiplomacyAction(ai);
}
