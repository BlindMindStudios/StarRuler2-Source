import hooks;
import systems;
import influence;
import resources;

#section server
from influence_global import getRandomActiveInfluenceEffect, getSenateLeader, getTaggedEffectOwner;
#section all

interface AIDiplomacy {
	Empire@ get_empire();
	uint get_allyMask();
	uint get_selfMask();
	uint enemiesMask(int maxStanding = -20);
	int getStanding(Empire@ against);
	array<InfluenceCard>& get_cardList();

	Object@ considerOwnedPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerImportantPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerOwnedSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerDefendingSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerDefendingPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerEnemySystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerImportantSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerEnemyFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerEnemyPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null);
	Object@ considerMatchingImportRequests(const CardAI& hook, Targets& targets, VoteState@ vote, const InfluenceCard@ card, const ResourceType@ type, bool considerExisting);
	void markProtecting(Object@ obj);
};

interface VoteState {
	InfluenceVote@ get_data();
	bool get_side();

	bool get_isRaceVote();
	void set_isRaceVote(bool value);

	double get_priority();
	void set_priority(double value);

	double get_weightOppose();
	void set_weightOppose(double value);
	double get_weightSupport();
	void set_weightSupport(double value);
};

uint getTargeted(const InfluenceVote@ vote, const Argument@ targArg) {
	auto@ targ = vote.targets[targArg.integer];
	if(targ is null)
		return 0;

	uint emps = 0;
	if(targ.emp !is null) {
		emps = targ.emp.mask;
	}
	else if(targ.obj !is null) {
		if(targ.obj.isRegion)
			emps = cast<Region>(targ.obj).PlanetsMask;
		else
			emps = targ.obj.owner.mask;
	}

	return emps & ~vote.startedBy.mask;
}

class CardAI : Hook {
	void considerBuy(AIDiplomacy& ai, const StackInfluenceCard@ card, double& weight) const {}
	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const {}
	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const { return true; }
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const {}
	bool vote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs) const { return true; }
	double consider(AIDiplomacy& ai, Targets& targets, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const { return 0.0; }
	double consider(AIDiplomacy& ai, Targets& targets, VoteState@ vote, const InfluenceCard@ card, Object@ requestedAt, Object@ currentSupplier) const { return 0.0; }
};

class VoteAI : Hook {
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {}
};

class BuyWeight : CardAI {
	Document doc("This card can always be bought, and has a particular weight.");
	Argument amount(AT_Decimal, "1.0", doc="Buy weight modification.");

#section server
	void considerBuy(AIDiplomacy& ai, const StackInfluenceCard@ card, double& weight) const override {
		weight *= amount.decimal;
	}
#section all
};

class BuyAgainstEnemies : CardAI {
	Document doc("If this card is against a specific empire, value it more if that empire is an enemy.");
	Argument targ(TT_Empire, doc="Target to check.");
	Argument amount(AT_Decimal, "1.5", doc="Buy weight modification.");
	Argument max_standing(AT_Integer, "-20", doc="Anything above this standing is considered not an enemy.");

#section server
	void considerBuy(AIDiplomacy& ai, const StackInfluenceCard@ card, double& weight) const override {
		auto@ consTarg = card.targets[targ.integer];
		if(consTarg is null || consTarg.emp is null || !consTarg.filled)
			return;

		if(consTarg.emp.isHostile(ai.empire) || ai.getStanding(consTarg.emp) < max_standing.integer)
			weight *= amount.decimal;
		else
			weight /= amount.decimal;
	}
#section all
};

class VoteSupport : CardAI {
	Document doc("This card is played as a simple vote support card into votes.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(card.type.sideTarget != -1)
			targs.fill(card.type.sideTarget).side = state.side;
		if(!state.data.canVote(ai.empire, state.side)) {
			weight *= 0.0;
			return;
		}

		weight *= this.weight.decimal;
	}

	bool vote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		if(card.type.sideTarget != -1)
			targs.fill(card.type.sideTarget).side = state.side;
		return true;
	}
#section all
}

class VoteAlwaysNegative : CardAI {
	Document doc("This card should be played as a bad card into votes we don't like.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(!state.side)
			weight *= this.weight.decimal;
		else
			weight *= 0.0;
	}
#section all
};

class VoteAlwaysPositive : CardAI {
	Document doc("This card should be played as a card into votes we like.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(state.side)
			weight *= this.weight.decimal;
		else
			weight *= 0.0;
	}
#section all
};

class VoteNotOurs : CardAI {
	Document doc("This card should only be played if we aren't the one who started this vote.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(state.data.startedBy is ai.empire)
			weight *= 0.0;
	}
#section all
};

class VoteAgainstEmpire : CardAI {
	Document doc("This card should be played against empires voting in the opposite direction to us.");
	Argument targ(TT_Empire, doc="Empire target this is against.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument min_vote(AT_Integer, "1", doc="Minimum amount of votes they should have cast opposite to us.");
	Argument most_only(AT_Boolean, "False", doc="Only use this card against empires that have the most opposition of everyone.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Empire@ emp;

		auto@ consTarg = card.targets[targ.integer];
		if(consTarg !is null && consTarg.filled && consTarg.emp !is null) {
			@emp = consTarg.emp;
		}
		else if(most_only.boolean) {
			int bestVote = 0;
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ check = getEmpire(i);
				if(check is ai.empire)
					continue;
				if(!state.data.isPresent(check))
					continue;

				int votes = state.data.getVoteFrom(check);
				if(state.side) {
					if(votes < bestVote) {
						bestVote = votes;
						@emp = check;
					}
				}
				else {
					if(votes > bestVote) {
						bestVote = votes;
						@emp = check;
					}
				}
			}
		}
		else {
			@emp = getEmpire(randomi(0, getEmpireCount()-1));
		}

		if(emp is null || !state.data.isPresent(emp)) {
			weight *= 0.0;
			return;
		}

		if(state.side) {
			if(state.data.getVoteFrom(emp) > -min_vote.integer) {
				weight *= 0.0;
				return;
			}
		}
		else {
			if(state.data.getVoteFrom(emp) < min_vote.integer) {
				weight *= 0.0;
				return;
			}
		}

		data.store(@emp);
	}

	bool vote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Empire@ emp;
		if(!data.retrieve(@emp))
			return false;

		@targs.fill(targ.integer).emp = emp;
		if(card.type.sideTarget != -1)
			targs.fill(card.type.sideTarget).side = state.side;
		return true;
	}
#section all
};

class NotInRace : CardAI {
	Document doc("This card should not be used in a 'race' vote such as zeitgeists.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(state.isRaceVote)
			weight *= 0.0;
	}
#section all
}

class VoteOnAlly : CardAI {
	Document doc("This card should be used on allies who are voting the same way as we are.");
	Argument targ(TT_Empire, doc="Empire target this is against.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument min_vote(AT_Integer, "1", doc="Minimum amount of votes they should have cast supporting us.");
	Argument allied_only(AT_Boolean, "True", doc="Only consider empires that are actually allied to us, instead of just voting our way.");
	Argument most_only(AT_Boolean, "False", doc="Only use this card against empires that have the most support of everyone.");

#section server
	void considerVote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Empire@ emp;

		auto@ consTarg = card.targets[targ.integer];
		if(consTarg !is null && consTarg.filled && consTarg.emp !is null) {
			@emp = consTarg.emp;
		}
		else if(most_only.boolean) {
			int bestVote = 0;
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ check = getEmpire(i);
				if(check is ai.empire)
					continue;
				if(!state.data.isPresent(check))
					continue;
				if(allied_only.boolean && ai.allyMask & check.mask == 0)
					continue;

				int votes = state.data.getVoteFrom(check);
				if(state.side) {
					if(votes > bestVote) {
						bestVote = votes;
						@emp = check;
					}
				}
				else {
					if(votes < bestVote) {
						bestVote = votes;
						@emp = check;
					}
				}
			}
		}
		else {
			@emp = getEmpire(randomi(0, getEmpireCount()-1));
		}

		if(emp is null || !state.data.isPresent(emp)) {
			weight *= 0.0;
			return;
		}

		if(state.side) {
			if(state.data.getVoteFrom(emp) < min_vote.integer) {
				weight *= 0.0;
				return;
			}
		}
		else {
			if(state.data.getVoteFrom(emp) > -min_vote.integer) {
				weight *= 0.0;
				return;
			}
		}

		data.store(@emp);
	}

	bool vote(AIDiplomacy& ai, VoteState& state, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Empire@ emp;
		if(!data.retrieve(@emp))
			return false;

		@targs.fill(targ.integer).emp = emp;
		if(card.type.sideTarget != -1)
			targs.fill(card.type.sideTarget).side = state.side;
		return true;
	}
#section all
};

class PlayOnImportantPlanets : CardAI {
	Document doc("This card should be played on important planets in the empire when possible.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument min_level(AT_Integer, "2", doc="Don't target planets of a lower level than this.");

#section server
	double consider(AIDiplomacy& ai, Targets& targets, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		if(int(obj.level) < min_level.integer)
			return 0.0;

		@targets.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targets[targ.integer]))
			return 0.0;

		double w = 0.8;
		if(obj.primaryResourceExported)
			w *= 0.5;
		return w;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ check = ai.considerImportantPlanets(this, targs, null, card);
		if(check !is null) {
			data.store(@check);
			if(check.primaryResourceExported)
				weight *= 0.5;
			weight *= this.weight.decimal;
			return;
		}

		weight *= 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};

class PlayOnImportantSystems : CardAI {
	Document doc("This card should be played on important systems in the empire when possible.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ best = ai.considerImportantSystems(this, targs, null, card);
		if(best !is null) {
			data.store(@best);
			weight *= this.weight.decimal;
			return;
		}

		weight *= 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};

class PlayOnImportantFleets : CardAI {
	Document doc("This card should be played on important fleets.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument min_size(AT_Integer, "128", doc="Minimum size to consider the flagship.");
	Argument enemies(AT_Boolean, "False", doc="Whether to play on an enemy's visible fleet instead of our own.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;

		Ship@ ship = cast<Ship>(obj);
		if(ship !is null) {
			const Design@ dsg = ship.blueprint.design;
			if(dsg is null)
				return 0.0;
			if(dsg.hasTag(ST_Mothership) || dsg.hasTag(ST_Slipstream) || dsg.hasTag(ST_Gate))
				return 0.0;
		}
		return obj.getFleetStrength();
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		//Find our strongest combat fleet
		Ship@ strongest;
		if(!enemies.boolean)
			@strongest = cast<Ship>(ai.considerFleets(this, targs, null, card));
		else
			@strongest = cast<Ship>(ai.considerEnemyFleets(this, targs, null, card));

		if(strongest is null) {
			weight *= 0.0;
			return;
		}

		auto@ dsg = strongest.blueprint.design;
		if(dsg is null || dsg.size < min_size.integer) {
			weight *= 0.0;
			return;
		}

		//Consider playing on that fleet
		@targs.fill(targ.integer).obj = strongest;
		if(!card.isValidTarget(targ.integer, targs[targ.integer])) {
			weight *= 0.0;
			return;
		}

		data.store(@strongest);
		weight *= this.weight.decimal;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Ship@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};

class PlayOnValuableCard : CardAI {
	Document doc("Play this card on another valuable card we have.");
	Argument targ(TT_Card, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument min_value(AT_Integer, "2", doc="Minimum value of the card to play this on.");

#section server
	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		double totalValue = 0.0;
		InfluenceCard@ otherCard;
		auto@ cards = ai.cardList;
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ check = cards[i];
			if(check.id == card.id)
				continue;

			targs.fill(targ.integer).id = check.id;
			if(!card.isValidTarget(targ.integer, targs[targ.integer]))
				continue;

			double val = check.getPurchaseCost(ai.empire, uses=1);
			if(val < min_value.integer)
				continue;

			totalValue += val;
			if(randomd() < val / totalValue)
				@otherCard = check;
		}

		if(otherCard !is null) {
			weight *= this.weight.decimal;

			int playOn = otherCard.id;
			data.store(playOn);
		}
		else {
			weight *= 0.0;
		}
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		int playOn = -1;
		if(!data.retrieve(playOn))
			return false;

		targs.fill(targ.integer).id = playOn;
		return true;
	}
#section all
};

class PlayOnDefendingPlanet : CardAI {
	Document doc("This card should be played on planets that are currently being defended and under contestion.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "5.0", doc="Weight of the card in relation to other cards.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;
		if(!obj.isContested)
			return 0.0;
		if(obj.isProtected(ai.empire))
			return 0.0;
		if(obj.capturePct <= 0.01)
			return 0.0;
		if(!obj.enemiesInOrbit)
			return 0.0;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ best = ai.considerDefendingPlanets(this, targs, null, card);
		if(best !is null) {
			data.store(@best);
			weight *= this.weight.decimal;
			return;
		}

		weight *= 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		ai.markProtecting(playOn);
		return true;
	}
#section all
};

class PlayOnDefendingSystem : CardAI {
	Document doc("This card should be played on systems that are currently being defended and under contestion.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "5.0", doc="Weight of the card in relation to other cards.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		Region@ reg = cast<Region>(obj);
		if(reg is null)
			return 0.0;
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;
		if(reg.ProtectedMask & ai.empire.mask != 0)
			return 0.0;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ best = ai.considerDefendingSystems(this, targs, null, card);
		if(best !is null) {
			data.store(@best);
			weight *= this.weight.decimal;
			return;
		}

		weight *= 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		ai.markProtecting(playOn);
		return true;
	}
#section all
};

class PlayOnEnemyEffect : CardAI {
	Document doc("Play this card on an influence effect of someone we don't like.");
	Argument targ(TT_Effect, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		auto@ eff = getRandomActiveInfluenceEffect();
		if(eff is null || eff.owner is null) {
			weight *= 0.0;
			return;
		}

		//Only cast on effects we dislike the owner of
		if(!ai.empire.isHostile(eff.owner) && ai.getStanding(eff.owner) >= -10) {
			weight *= 0.0;
			return;
		}

		targs.fill(targ.integer).id = eff.id;
		if(!card.isValidTarget(targ.integer, targs[targ.integer])) {
			weight *= 0.0;
			return;
		}

		int playOn = eff.id;
		data.store(playOn);

		weight *= this.weight.decimal;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		int playOn = -1;
		if(!data.retrieve(playOn))
			return false;

		targs.fill(targ.integer).id = playOn;
		return true;
	}
#section all
};

class PlayWhenInfluenceStronk : CardAI {
	Document doc("Play this card if we have strong influence compared to other empires.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(ai.empire.PoliticalStrength != +1)
			weight *= 0.0;
		else
			weight *= this.weight.decimal;
	}
#section all
};

class PlayOnEnemy : CardAI {
	Document doc("Play this card on enemies we dislike.");
	Argument targ(TT_Empire, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");
	Argument war_only(AT_Boolean, "False", doc="Only play against enemies we are at war with, instead of everyone we dislike.");

#section server
	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Empire@ emp = getEmpire(randomi(0, getEmpireCount()-1));

		auto@ curTarg = targs[targ.integer];
		if(curTarg !is null && curTarg.filled)
			@emp = curTarg.emp;
		if(emp is null) {
			weight *= 0.0;
			return;
		}

		if(!ai.empire.isHostile(emp) && (war_only.boolean || ai.getStanding(emp) >= -20)) {
			weight *= 0.0;
			return;
		}

		@targs.fill(targ.integer).emp = emp;
		if(!card.isValidTarget(targ.integer, targs[targ.integer])) {
			weight *= 0.0;
			return;
		}

		data.store(@emp);
		weight *= this.weight.decimal;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Empire@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).emp = playOn;
		return true;
	}
#section all
};

class IgnoreIfSenateLeader : CardAI {
	Document doc("Ignore this card if you are senate leader.");

#section server
	void considerBuy(AIDiplomacy& ai, const StackInfluenceCard@ card, double& weight) const override {
		if(getSenateLeader() is ai.empire)
			weight *= 0.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(getSenateLeader() is ai.empire)
			weight *= 0.0;
	}
#section all
};

class IgnoreIfAttributeGTE : CardAI {
	Document doc("Ignore this card if you have a particular attribute above a value.");
	Argument attrib(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Value to check for.");

#section server
	void considerBuy(AIDiplomacy& ai, const StackInfluenceCard@ card, double& weight) const override {
		if(ai.empire.getAttribute(attrib.integer) >= value.decimal)
			weight *= 0.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		if(ai.empire.getAttribute(attrib.integer) >= value.decimal)
			weight *= 0.0;
	}
#section all
};

class PlayOnNearbyEnemyPlanet : CardAI {
	Document doc("This card should be played on enemy planets that are nearby our space.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ planet = ai.considerEnemyPlanets(this, targs, null, card);
		data.store(@planet);

		if(planet !is null)
			weight *= this.weight.decimal;
		else
			weight = 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};

class PlayOnNearbyEnemySystem : CardAI {
	Document doc("This card should be played on enemy systems that are nearby our space.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument weight(AT_Decimal, "1.0", doc="Weight of the card in relation to other cards.");

#section server
	double consider(AIDiplomacy& ai, Targets& targs, VoteState@ vote, const InfluenceCard@ card, Object@ obj) const {
		@targs.fill(targ.integer).obj = obj;
		if(!card.isValidTarget(targ.integer, targs[targ.integer]))
			return 0.0;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ system = ai.considerEnemySystems(this, targs, null, card);
		data.store(@system);

		if(system !is null)
			weight *= this.weight.decimal;
		else
			weight = 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};



class Important : VoteAI {
	Document doc("This vote is important.");
	Argument importance(AT_Decimal, doc="Importance multiplier for the vote.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		state.priority *= importance.decimal;
	}
#section all
};

class BadFor : VoteAI {
	Document doc("This vote is bad for whoever is in the target.");
	Argument targ(TT_Any);
	Argument weight(AT_Decimal, "2.0", doc="Just how bad is this vote?");
	Argument importance(AT_Decimal, "1.0", doc="Modifier to important for related empires.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		uint emps = getTargeted(vote, targ);

		//If it's us, this is bad
		if(ai.selfMask & emps != 0) {
			state.weightOppose *= this.weight.decimal;
			state.priority *= this.importance.decimal;
		}
		//Try to protect allies a little as well
		else if(ai.allyMask & emps != 0) {
			state.weightOppose *= sqrt(this.weight.decimal);
			state.priority *= this.importance.decimal;
		}
	}
#section all
};

class GoodFor : VoteAI {
	Document doc("This vote is good for whoever is in the target.");
	Argument targ(TT_Any);
	Argument weight(AT_Decimal, "2.0", doc="Just how good is this vote?");
	Argument importance(AT_Decimal, "1.0", doc="Modifier to important for related empires.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		uint emps = getTargeted(vote, targ);

		//If it's us, this is bad
		if(ai.selfMask & emps != 0) {
			state.weightSupport *= this.weight.decimal;
			state.priority *= this.importance.decimal;
		}
		//Try to help allies a little as well
		else if(ai.allyMask & emps != 0) {
			state.weightSupport *= sqrt(this.weight.decimal);
			state.priority *= this.importance.decimal;
		}
	}
#section all
};

class GoodForNot : VoteAI {
	Document doc("This vote is good for whoever is not the target.");
	Argument targ(TT_Any);
	Argument weight(AT_Decimal, "2.0", doc="Just how good is this vote?");
	Argument importance(AT_Decimal, "1.0", doc="Modifier to important for related empires.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		uint emps = getTargeted(vote, targ);

		if((ai.selfMask | ai.allyMask) & emps == 0) {
			state.weightSupport *= this.weight.decimal;
			state.priority *= this.importance.decimal;
		}
		else if(ai.selfMask & emps == 0) {
			state.weightSupport *= sqrt(this.weight.decimal);
			state.priority *= this.importance.decimal;
		}
	}
#section all
};

class BadForSenateLeader : VoteAI {
	Document doc("This vote is bad for the current senate leader.");
	Argument weight(AT_Decimal, "2.0", doc="Just how bad is this vote?");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		Empire@ curLeader = getSenateLeader();
		uint emps = 0;
		if(curLeader !is null && curLeader !is vote.startedBy)
			emps |= curLeader.mask;

		//If it's us, this is bad
		if(ai.selfMask & emps != 0)
			state.weightOppose *= this.weight.decimal;
		//Try to protect allies a little as well
		else if(ai.allyMask & emps != 0)
			state.weightOppose *= sqrt(this.weight.decimal);
	}
#section all
};

class BenefitRace : VoteAI {
	Document doc("This vote is a race where the highest contributor benefits.");
	Argument weight(AT_Decimal, "2.0", doc="The weight of winning this vote.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		state.isRaceVote = true;
		state.weightSupport *= weight.decimal;
	}
#section all
};

class BadIfAttributeGTE : VoteAI {
	Document doc("This vote is bad if an attribute is at least a particular value.");
	Argument attrib(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, doc="Value to check for.");
	Argument weight(AT_Decimal, "2.0", doc="Just how bad is this vote?");
	Argument importance(AT_Decimal, "1.0", doc="Importance multiplier to the vote.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		if(ai.empire.getAttribute(attrib.integer) >= value.decimal) {
			state.weightOppose *= this.weight.decimal;
			state.priority *= this.importance.decimal;
		}
	}
#section all
};

class ZeitgeistVote : VoteAI {
	Document doc("This vote is a zeitgeist vote.");
	Argument tag(AT_Custom, "Zeitgeist", doc="Tag to determine for current zeitgeist effect.");
	Argument weight(AT_Decimal, "10.0", doc="Weight modification.");

#section server
	void consider(AIDiplomacy& ai, VoteState& state, const InfluenceVote@ vote) const {
		state.isRaceVote = true;
		Empire@ current = getTaggedEffectOwner(tag.str);
		if(current !is null && current.mask & ai.selfMask != 0)
			state.weightOppose *= weight.decimal;
		else
			state.weightSupport *= weight.decimal;
	}
#section all
};

class PlayAsCreatedResource : CardAI {
	Document doc("This card is used to create a resource somewhere it is useful.");
	Argument targ(TT_Object, doc="Target to fill in.");
	Argument resource(AT_PlanetResource, doc="Resource to match import requests to.");
	Argument weight(AT_Decimal, "1.0", doc="Value for activating this.");
	Argument replaces_existing(AT_Boolean, "True", doc="Whether this can be used to replace an existing import of that type or not.");

#section server
	double consider(AIDiplomacy& ai, Targets& targets, VoteState@ vote, const InfluenceCard@ card, Object@ requestedAt, Object@ currentSupplier) const {
		@targets.fill(targ.integer).obj = requestedAt;
		if(!card.isValidTarget(targ.integer, targets[targ.integer]))
			return 0.0;
		if(currentSupplier !is null)
			return 0.5;
		return 1.0;
	}

	void considerAct(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs, double& weight) const override {
		Object@ check = ai.considerMatchingImportRequests(this, targs, null, card, getResource(resource.integer), replaces_existing.boolean);
		if(check !is null) {
			data.store(@check);
			weight *= this.weight.decimal;
			return;
		}

		weight *= 0.0;
	}

	bool act(AIDiplomacy& ai, const InfluenceCard@ card, any@ data, Targets& targs) const override {
		Object@ playOn;
		if(!data.retrieve(@playOn))
			return false;

		@targs.fill(targ.integer).obj = playOn;
		return true;
	}
#section all
};
