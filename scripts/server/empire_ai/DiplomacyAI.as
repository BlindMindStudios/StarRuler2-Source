import hooks;
import influence;
import resources;
import influence_global;

from ai.diplomacy import CardAI, VoteAI, AIDiplomacy, VoteState;

const float RESERVE_MIN = 0.33f;

const int MONEY_MIN_PER_SUPP = 30;
const int MONEY_MAX_PER_SUPP = 200;
const int MONEY_FAIR_PER_SUPP = 60;

const int ENERGY_MIN_PER_SUPP = 50;
const int ENERGY_MAX_PER_SUPP = 200;
const int ENERGY_FAIR_PER_SUPP = 80;

const double SHIP_FAIR_PER_SUPP = 20.0;
const int PL_FAIR_PER_RESLV = 5;
const int ARTIFACT_FAIR = 1;

enum VoteStance {
	S_Neutral,
	S_GivenUp,
	S_For,
	S_Against,
};

final class VoteData : Savable, VoteState {
	uint voteId = 0;
	double forWeight = 1.0;
	double againstWeight = 1.0;
	double importance = 1.0;
	uint stance = S_Neutral;
	bool isRace = false;
	int ourOffer = -1;
	int pursueOffer = -1;
	bool prompted = false;

	InfluenceVote vote;

	bool get_takenStance() {
		return stance == S_For || stance == S_Against;
	}

	bool get_side() {
		if(stance == S_Neutral && prompted)
			return forWeight >= againstWeight;
		return stance == S_For;
	}

	void save(SaveFile& file) {
		file << voteId;
		file << stance;
		file << ourOffer;
		file << pursueOffer;
		file << prompted;
	}

	void load(SaveFile& file) {
		file >> voteId;
		file >> stance;
		file >> ourOffer;
		file >> pursueOffer;
		file >> prompted;
	}

	InfluenceVote@ get_data() {
		return vote;
	}

	bool get_isRaceVote() {
		return isRace;
	}

	void set_isRaceVote(bool value) {
		isRace = value;
	}

	double get_priority() {
		return importance;
	}

	void set_priority(double value) {
		importance = value;
	}

	double get_weightOppose() {
		return againstWeight;
	}

	void set_weightOppose(double value) {
		againstWeight = value;
	}

	double get_weightSupport() {
		return forWeight;
	}

	void set_weightSupport(double value) {
		forWeight = value;
	}
};

class DiplomacyAI : AIDiplomacy {
	bool log = false;
	float reservePct;

	int influenceCap;
	int freeInfluence;
	int reservedInfluence;

	array<InfluenceCard> cards;
	array<VoteData@> votes;

	int totalSupport = 0;
	int totalSupportCost = 0;

	uint prevVotes = uint(-1);

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		votes.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@votes[i] = VoteData();
			file >> votes[i];
		}

		file >> prevVotes;
	}

	void save(SaveFile& file) {
		uint cnt = votes.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << votes[i];

		file << prevVotes;
	}

	array<InfluenceCard>& get_cardList() {
		return cards;
	}

	uint get_selfMask() {
		Empire@ emp = empire;
		uint mask = 0;
		mask |= emp.mask;
		
		if(emp.SubjugatedBy !is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ check = getEmpire(i);
				if(check is emp.SubjugatedBy || check.SubjugatedBy is emp.SubjugatedBy)
					mask |= check.mask;
			}
		}
		return mask;
	}

	uint enemiesMask(int maxStanding = -20) {
		uint mask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other is empire)
				continue;
			if(empire.isHostile(other) || getStanding(other) < maxStanding)
				mask |= other.mask;
		}
		return mask;
	}

	void summarize() {
		//Calculate new reservation percentage
		reservePct = RESERVE_MIN;

		//Calculate actual available influence
		influenceCap = empire.InfluenceCap;

		int totalInfluence = empire.Influence;
		reservedInfluence = min(totalInfluence, int(float(influenceCap) * reservePct));
		freeInfluence = totalInfluence - reservedInfluence;

		//Sync up our held cards
		cards.syncFrom(empire.getInfluenceCards());

		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ card = cards[i];
			if(card.type.cls == ICC_Support) {
				totalSupport += card.getWeight();
				totalSupportCost += card.getPlayCost();
			}
		}
	}

	void buyCards() {
		//See if we can buy something
		if(freeInfluence <= 0)
			return;

		auto@ cardStack = getInfluenceStack();

		double totalWeight = 0.0;
		const StackInfluenceCard@ buyCard;
		for(uint i = 0, cnt = cardStack.length; i < cnt; ++i) {
			double w = getBuyWeight(cardStack[i]);
			if(w <= 0)
				continue;

			totalWeight += w;
			if(randomd() < w / totalWeight)
				@buyCard = cardStack[i];
		}

		if(buyCard !is null) {
			if(log)
				print("Buy "+buyCard.formatTitle());
			buyCardFromInfluenceStack(empire, buyCard.id);
		}
	}

	Targets targs;
	array<any> considerData;
	array<any> playData;
	void considerActions() {
		if(freeInfluence <= 0)
			return;

		double totalWeight = 0.0;
		InfluenceCard@ playCard;
		considerData.length = 10;

		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			double w = getPlayWeight(cards[i], considerData);
			if(w <= 0)
				continue;

			totalWeight += w;
			if(randomd() < w / totalWeight) {
				@playCard = cards[i];
				playData = considerData;
			}
		}

		if(playCard !is null) {
			if(log)
				print("Play "+playCard.formatTitle());
			play(playCard, playData);
		}
	}

	void considerVotes() {
		//Sync up new votes
		uint newVotes = getLastInfluenceVoteId();
		if(newVotes != prevVotes) {
			for(uint i = prevVotes+1; i <= newVotes; ++i) {
				VoteData state;
				state.voteId = i;

				syncInfluenceVote(state.voteId, state.vote);
				considerVote(state);

				votes.insertLast(state);
			}
			prevVotes = newVotes;
		}

		//See if we should vote on something
		double totalWeight = 0.0;
		VoteData@ voteOn;
		for(uint i = 0, cnt = votes.length; i < cnt; ++i) {
			double w = votes[i].importance;
			if(votes[i].prompted)
				w = (w+1.0) * 3.0;
			if(w == 0)
				continue;

			totalWeight += w;
			if(randomd() < w / totalWeight)
				@voteOn = votes[i];
		}

		if(voteOn !is null) {
			//Reconsider this vote
			syncInfluenceVote(voteOn.voteId, voteOn.vote);

			if(!voteOn.vote.active) {
				votes.remove(voteOn);
				return;
			}
			else {
				considerVote(voteOn);
				if(!voteOn.takenStance && !voteOn.prompted)
					return;
			}

			//Don't vote if the vote is already going our way
			if(!voteOn.prompted) {
				if(voteOn.side) {
					if((double(voteOn.vote.totalFor) / double(voteOn.vote.totalAgainst+1)) > randomd(1.0, 1.15)
						&& (!voteOn.isRace || voteOn.vote.highestContributor is empire))
						return;
				}
				else {
					if((double(voteOn.vote.totalAgainst) / double(voteOn.vote.totalFor)) > randomd(1.0, 1.15)
						&& (!voteOn.isRace || voteOn.vote.lowestContributor is empire))
						return;
				}
			}

			//See if we can play some cards into it
			double totalWeight = 0.0;

			InfluenceCard@ playCard;
			considerData.length = 10;

			for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
				double w = getPlayWeight(voteOn, cards[i], considerData);
				if(w <= 0)
					continue;

				totalWeight += w;
				if(randomd() < w / totalWeight) {
					@playCard = cards[i];
					playData = considerData;
				}
			}

			bool voted = false;
			if(playCard !is null) {
				if(log)
					print("Play into vote "+voteOn.vote.formatTitle()+": "+playCard.formatTitle());
				voted = vote(voteOn, playCard, playData);
				if(voted)
					voteOn.prompted = false;
			}

			if(!voted) {
				//See if we should make an offer
				if(voteOn.pursueOffer == -1 && voteOn.ourOffer == -1 && !voteOn.isRace && !voteOn.prompted)
					makeOffer(voteOn);
			}
		}
	}

	void considerVote(VoteData& state) {
		auto@ vote = state.vote;

		//Reconsider whether to support or oppose this vote
		state.forWeight = 1.0;
		state.againstWeight = 1.0;
		state.importance = 1.0;
		state.isRace = false;

		int standing = getStanding(vote.startedBy);

		//Check if our offers are valid
		bool pursueValid = false, ourValid = false;
		for(uint i = 0, cnt = state.vote.offers.length; i < cnt; ++i) {
			if(state.vote.offers[i].fromEmpire is empire) {
				state.ourOffer = state.vote.offers[i].id;
				ourValid = true;
			}
			if(state.vote.offers[i].id == state.pursueOffer)
				pursueValid = true;
		}
		if(!ourValid && state.ourOffer != -1) {
			state.ourOffer = -1;
		}
		if(!pursueValid && state.pursueOffer != -1) {
			state.pursueOffer = -1;
			state.stance = S_Neutral;
		}

		//Check if we got prompted
		if(!state.prompted) {
			//TODO
			/*if(ai.callOuts.contains(state.voteId)) {*/
			/*	state.prompted = true;*/
			/*	ai.callOuts.erase(state.voteId);*/
			/*}*/
		}

		//Our votes are good
		if(vote.startedBy is empire)
			state.forWeight *= 1000.0;

		//We don't like people we don't like
		if(empire.hostileMask & vote.startedBy.mask != 0)
			state.againstWeight *= 2.0;
		if(standing < -20 && vote.startedBy.valid)
			state.againstWeight *= 2.0;

		//We like allies
		if(vote.startedBy.mask & allyMask != 0 || standing > 50) {
			if(standing > 75)
				state.forWeight *= 4.0;
			else
				state.forWeight *= 2.0;
		}

		//Check the vote's hooks
		for(uint i = 0, cnt = vote.type.ai.length; i < cnt; ++i) {
			VoteAI@ hook = cast<VoteAI>(vote.type.ai[i]);
			if(hook !is null)
				hook.consider(this, state, vote);
		}

		//Adapt our stance accordingly
		if(state.pursueOffer == -1) {
			if(state.stance == S_Neutral) {
				if(state.forWeight > state.againstWeight) {
					if(state.importance >= 3.0 || state.forWeight > state.againstWeight * randomd(1.3, 2.2)) {
						if(state.importance >= 10.0 || canPass(state))
							state.stance = S_For;
					}
				}
				else {
					if(state.importance >= 3.0 || state.againstWeight > randomd(1.3, 2.2)) {
						bool canWin = true;
						if(state.importance >= 10.0 || canFail(state))
							state.stance = S_Against;
					}
				}
			}
			else if(state.stance == S_For) {
				if(state.againstWeight > state.forWeight * 10.0)
					state.stance = S_Against;
				else if(state.importance < 5.0 && !canPass(state, margin=2.0))
					state.stance = S_Neutral;
			}
			else if(state.stance == S_Against) {
				if(state.forWeight > state.againstWeight * 10.0)
					state.stance = S_For;
				else if(state.importance < 5.0 && !canFail(state, margin=2.0))
					state.stance = S_Neutral;
			}
		}

		//Check if we should pursue an offer
		if(state.vote.offers.length != 0 && state.pursueOffer == -1) {
			const InfluenceVoteOffer@ bestOffer;

			double bestRatio = 0.0;

			//Calculate the minimum fairity ratio we want
			bestRatio = 0.9;
			if(freeInfluence + reservedInfluence > influenceCap)
				bestRatio *= pow(0.95, double(freeInfluence + reservedInfluence - influenceCap) / 2.0);
			else
				bestRatio *= pow(1.05, double(influenceCap - freeInfluence - reservedInfluence));

			for(uint i = 0, cnt = state.vote.offers.length; i < cnt; ++i) {
				auto@ offer = state.vote.offers[i];
				if(offer.fromEmpire is empire)
					continue;
				if(offer.fromEmpire.isHostile(empire))
					continue;

				if(state.stance != S_Neutral) {
					if(offer.side != (state.stance == S_For))
						continue;
				}

				double fair = 0;
				for(uint i = 0, cnt = offer.offers.length; i < cnt; ++i) {
					auto@ thing = offer.offers[i];
					switch(thing.type) {
						case DOT_Money:
							fair += thing.value / double(MONEY_FAIR_PER_SUPP);
						break;
						case DOT_Energy:
							fair += thing.value / double(ENERGY_FAIR_PER_SUPP);
						break;
						case DOT_Card:
							fair += offer.fromEmpire.getCostOfCard(thing.id) * thing.value;
						break;
						case DOT_Fleet: {
							Ship@ ship = cast<Ship>(thing.obj);
							if(ship !is null) {
								auto@ dsg = ship.blueprint.design;
								if(dsg !is null)
									fair += dsg.size / SHIP_FAIR_PER_SUPP;
							}
						} break;
						case DOT_Planet: {
							Planet@ pl = cast<Planet>(thing.obj);
							if(pl !is null)
								fair += (pl.primaryResourceLevel+1) * PL_FAIR_PER_RESLV;
						} break;
						case DOT_Artifact:
							fair += ARTIFACT_FAIR;
						break;
					}
				}

				double offerRatio = fair / double(offer.support);

				//Offerer-specific ratio mods
				if(allyMask & offer.fromEmpire.mask != 0) {
					offerRatio *= 1.1;
				}
				else {
					int standing = getStanding(offer.fromEmpire);
					if(standing > 50)
						offerRatio *= 1.1;
					else if(standing < -10)
						offerRatio *= 0.8;
				}


				if(offerRatio > bestRatio) {
					bestRatio = offerRatio;
					@bestOffer = offer;
				}
			}

			if(bestOffer !is null) {
				state.pursueOffer = bestOffer.id;
				state.stance = bestOffer.side ? S_For : S_Against;
				if(log)
					print("pursue offer from "+bestOffer.fromEmpire.name+" on vote "+state.vote.formatTitle());
			}
		}
	}

	void checkOffer(VoteData& state) {
		if(state.pursueOffer == -1)
			return;

		//Probably faster than syncing and checking
		claimInfluenceVoteOffer_server(empire, state.voteId, state.pursueOffer);
	}

	double getVoteGap(VoteData@ state) {
		double gap = 0.0;
		if(state.side) {
			if(!state.isRace) {
				gap = state.vote.totalAgainst - state.vote.totalFor;
			}
			else {
				Empire@ bestEmp = state.vote.highestContributor;
				if(bestEmp !is null)
					gap = state.vote.getVoteFrom(bestEmp) - state.vote.getVoteFrom(empire);
			}
		}
		else {
			if(!state.isRace) {
				gap = state.vote.totalFor - state.vote.totalAgainst;
			}
			else {
				Empire@ bestEmp = state.vote.lowestContributor;
				if(bestEmp !is null)
					gap = (-state.vote.getVoteFrom(bestEmp)) - (-state.vote.getVoteFrom(empire));
			}
		}
		return gap;
	}

	bool canPass(VoteData@ state, double margin = 1.0) {
		//Check whether we can realistically pass this vote
		double gap = getVoteGap(state);
		if(gap < 0)
			return true;

		double availInfluence = freeInfluence;
		if(state.importance >= 3.0)
			availInfluence += reservedInfluence;

		double availSupport = min(availInfluence * (double(totalSupport) / double(totalSupportCost)), double(totalSupport));
		if(availSupport < gap * pow(0.5, margin))
			return false;
		return true;
	}

	bool canFail(VoteData@ state, double margin = 1.0) {
		//Check whether we can realistically fail this vote
		double gap = getVoteGap(state);
		if(gap < 0)
			return true;

		double availInfluence = freeInfluence;
		if(state.importance >= 3.0)
			availInfluence += reservedInfluence;

		double availSupport = min(availInfluence * (double(totalSupport) / double(totalSupportCost)), double(totalSupport));
		if(availSupport < gap * pow(0.5, margin))
			return false;
		return true;
	}

	void makeOffer(VoteData@ state) {
		int needSupp = getVoteGap(state);
		if(needSupp <= 0)
			return;

		InfluenceVoteOffer off;
		off.side = state.side;
		off.support = 0;

		int offerMoney = 0;
		int offerEnergy = 0;

		for(uint i = 0, cnt = randomi(1,3); i < cnt; ++i) {
			int supp = ceil(double(needSupp) * randomd(0.5, 1.0));
			if(supp == 0)
				continue;
			switch(randomi(0,2)) {
				case 0: {
					int curMoney = double(empire.RemainingBudget) * 0.8;
					if(curMoney / supp < MONEY_MIN_PER_SUPP)
						break;
					int perSupp = randomi(MONEY_MIN_PER_SUPP, min(MONEY_MAX_PER_SUPP, curMoney / supp));

					offerMoney += supp * perSupp;
					needSupp -= supp;
					off.support += supp;
				} break;
				case 1: {
					int curEnergy = double(empire.EnergyStored) * 0.8;
					if(curEnergy / supp < ENERGY_MIN_PER_SUPP)
						break;
					int perSupp = randomi(ENERGY_MIN_PER_SUPP, min(ENERGY_MAX_PER_SUPP, curEnergy / supp));

					offerEnergy += supp * perSupp;
					needSupp -= supp;
					off.support += supp;
				} break;
				case 2: {
					if(cards.length == 0)
						break;
					auto@ card = cards[randomi(0, cards.length-1)];
					int cost = card.getPurchaseCost(empire);
					if(cost != 0 && cost != INDETERMINATE) {
						if(cost > supp * 1.5)
							break;

						DiplomacyOffer offCard;
						offCard.type = DOT_Card;
						offCard.id = card.id;
						offCard.value = 1;

						off.offers.insertLast(offCard);

						needSupp -= cost;
						off.support += cost;
					}
				} break;
			}
		}

		if(offerMoney != 0) {
			DiplomacyOffer money;
			money.type = DOT_Money;
			money.value = offerMoney;

			off.offers.insertLast(money);
		}
		if(offerEnergy != 0) {
			DiplomacyOffer energy;
			energy.type = DOT_Energy;
			energy.value = offerEnergy;

			off.offers.insertLast(energy);
		}

		if(off.offers.length != 0 && off.support != 0) {
			makeInfluenceVoteOffer_server(empire, state.voteId, off);
			if(log)
				print("make offer on vote "+state.vote.formatTitle());
		}
	}

	double getBuyWeight(const StackInfluenceCard@ card) {
		if(card.type.ai.length == 0)
			return 0.0;
		if(!card.canPurchase(empire))
			return 0.0;

		int cost = card.getPurchaseCost(empire);
		if(cost > freeInfluence || cost == 0)
			return 0.0;

		double w = 1.0;

		//Weight based on buy cost
		w *= 1.0 - (double(cost) / double(freeInfluence+1));

		//Only sometimes buy leader only cards
		if(card.type.leaderOnly && getSenateLeader() !is empire)
			w *= 0.05;

		//Extra weight based on card support
		if(card.type.cls == ICC_Support) {
			int supp = card.getWeight();
			if(supp != 0 && supp != INDETERMINATE)
				w *= sqrt(double(supp * card.uses));
		}

		//Extra weight based on larger stacks
		w *= sqrt(double(card.uses));

		//Weight on AI hooks
		for(uint i = 0, cnt = card.type.ai.length; i < cnt; ++i) {
			auto@ hook = cast<CardAI>(card.type.ai[i]);
			if(hook !is null)
				hook.considerBuy(this, card, w);
		}

		return w;
	}

	double getPlayWeight(const InfluenceCard@ card, array<any>& data) {
		if(card.type.ai.length == 0)
			return 0.0;
		if(!card.canPlay(null))
			return 0.0;

		double w = 1.0;

		int cost = card.getPlayCost();
		if(cost != INDETERMINATE) {
			if(cost > freeInfluence)
				return 0.0;

			//Initial weight based on play cost
			w *= 1.0 - (double(cost) / double(freeInfluence+1));
		}

		//Weight on AI hooks
		uint hookCnt = card.type.ai.length;
		if(hookCnt > data.length)
			data.length = hookCnt;
		targs.set(card.targets);
		card.targetDefaults(targs);
		for(uint i = 0; i < hookCnt; ++i) {
			auto@ hook = cast<CardAI>(card.type.ai[i]);
			if(hook !is null)
				hook.considerAct(this, card, data[i], targs, w);
		}

		return w;
	}

	void play(InfluenceCard@ card, array<any>& data) {
		uint hookCnt = card.type.ai.length;
		targs.set(card.targets);
		card.targetDefaults(targs);
		bool canPlay = true;
		for(uint i = 0; i < hookCnt; ++i) {
			auto@ hook = cast<CardAI>(card.type.ai[i]);
			if(hook !is null) {
				if(!hook.act(this, card, data[i], targs)) {
					canPlay = false;
					break;
				}
			}
		}
		if(canPlay && card.canPlay(targs))
			playInfluenceCard_server(empire, card.id, targs);
		else if(log)
			print(" failed to play "+card.formatTitle()+" - "+canPlay);
	}

	double getPlayWeight(VoteData@ state, const InfluenceCard@ card, array<any>& data) {
		if(card.type.ai.length == 0)
			return 0.0;
		if(!card.canPlay(state.vote, null))
			return 0.0;

		//Ignore cards we shouldn't play into this anyway
		if(card.type.sideMode == ICS_Support && !state.side)
			return 0.0;
		if(card.type.sideMode == ICS_Oppose && state.side)
			return 0.0;

		int availInfluence = freeInfluence;
		if(state.importance >= 3.0)
			availInfluence += reservedInfluence;

		double w = 1.0;

		int cost = card.getPlayCost(state.vote);
		if(cost != INDETERMINATE) {
			if(cost > availInfluence)
				return 0.0;

			//Initial weight based on play cost
			w *= 1.0 - (double(cost) / double(availInfluence+1));
		}

		int weight = card.getWeight(state.vote);
		if(weight == 0)
			return 0.0;
		if(weight != INDETERMINATE)
			w *= weight;

		//Weight on AI hooks
		uint hookCnt = card.type.ai.length;
		if(hookCnt > data.length)
			data.length = hookCnt;
		targs.set(card.targets);
		card.targetDefaults(targs);
		for(uint i = 0; i < hookCnt; ++i) {
			auto@ hook = cast<CardAI>(card.type.ai[i]);
			if(hook !is null)
				hook.considerVote(this, state, card, data[i], targs, w);
		}
		return w;
	}

	bool vote(VoteData@ state, InfluenceCard@ card, array<any>& data) {
		uint hookCnt = card.type.ai.length;
		targs.set(card.targets);
		card.targetDefaults(targs);
		bool canPlay = true;
		for(uint i = 0; i < hookCnt; ++i) {
			auto@ hook = cast<CardAI>(card.type.ai[i]);
			if(hook !is null) {
				if(!hook.vote(this, state, card, data[i], targs)) {
					canPlay = false;
					break;
				}
			}
		}
		if(canPlay && card.canPlay(state.vote, targs)) {
			playInfluenceCard_server(empire, card.id, targs, state.vote.id);
			if(state.pursueOffer != -1)
				checkOffer(state);
			return true;
		}
		else {
			if(log)
				print(" failed to play "+card.formatTitle()+" - "+canPlay);
			return false;
		}
	}

	//AI IMPLEMENTATIONS
	Empire@ get_empire() {
		return null;
	}

	uint get_allyMask() {
		return 0;
	}

	int getStanding(Empire@ emp) {
		return 0;
	}

	void print(const string& str) {
	}

	Object@ considerOwnedPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerImportantPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerOwnedSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerImportantSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerDefendingSystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerDefendingPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerEnemySystems(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerEnemyFleets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}

	Object@ considerEnemyPlanets(const CardAI& hook, Targets& targets, VoteState@ vote = null, const InfluenceCard@ card = null) {
		return null;
	}
	
	Object@ considerMatchingImportRequests(const CardAI& hook, Targets& targets, VoteState@ vote, const InfluenceCard@ card, const ResourceType@ type, bool considerExisting) {
		return null;
	}

	void markProtecting(Object@ obj) {
	}
};

