import influence;
import saving;
from influence import InfluenceStore;
from influence_global import influenceLock;
import void modGalacticInfluence(int mod) from "influence_global";
import double getInfluenceIncome(int stock, int stored, double factor) from "influence_global";
import double getInfluenceEfficiency(int stock, int stored) from "influence_global";
import double getInfluenceStorage(int stock) from "influence_global";
import double getInfluencePercentage(Empire& emp) from "influence_global";

const double INTELLIGENCE_TIMEOUT = 80.0;

tidy class InfluenceReservation : Savable {
	int id = -1;
	double timer = -1.0;
	double factor = 1.0;

	InfluenceReservation() {
	}

	InfluenceReservation(SaveFile& file) {
		load(file);
	}

	void save(SaveFile& file) {
		file << id << timer << factor;
	}

	void load(SaveFile& file) {
		file >> id >> timer >> factor;
	}
}

tidy class InfluenceManager : Component_InfluenceManager, InfluenceStore, Savable {
	Mutex inflMtx;
	Mutex cardMtx;

	//Current influence stored
	int influence = 0;
	int influenceIncome = 0;

	//Stored partial generation
	double partialInfluence = 0.0;
	double StatRecordDelay = 5.0;

	//Reservations on influence income
	array<InfluenceReservation@> reservations;
	int nextReservationId = 1;
	double inflFactor = 1.0;
	double inflFactorMod = 0.0;

	//Available cards to use
	array<InfluenceCard@> cards;
	int nextCardId = 1;
	bool cardDelta = false;
	array<double>@ intelligenceTimer;

	//Edicts
	DiplomacyEdict edict;

	InfluenceManager() {
	}

	void load(SaveFile& file) {
		file >> influence;
		file >> influenceIncome;
		file >> partialInfluence;
		file >> StatRecordDelay;

		if(partialInfluence != partialInfluence)
			partialInfluence = 0.0;

		uint cnt = 0;
		file >> cnt;
		cards.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@cards[i] = InfluenceCard(file);

		file >> nextCardId;
		file >> inflFactor;
		file >> inflFactorMod;
		file >> nextReservationId;

		file >> cnt;
		reservations.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@reservations[i] = InfluenceReservation(file);

		if(file >= SV_0018) {
			file >> cnt;
			@intelligenceTimer = array<double>(cnt, -1.0);
			for(uint i = 0; i < cnt; ++i)
				file >> intelligenceTimer[i];
		}

		if(file >= SV_0070)
			file >> edict;
	}

	void save(SaveFile& file) {
		file << influence;
		file << influenceIncome;
		file << partialInfluence;
		file << StatRecordDelay;

		uint cnt = cards.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << cards[i];

		file << nextCardId;
		file << inflFactor;
		file << inflFactorMod;
		file << nextReservationId;

		cnt = reservations.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << reservations[i];

		cnt = intelligenceTimer.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << intelligenceTimer[i];

		file << edict;
	}

	int get_Influence() {
		return influence;
	}

	int getInfluenceStock() {
		return max(influenceIncome, 0);
	}

	double get_InfluenceIncome() {
		return getInfluenceIncome(max(influenceIncome,0), influence, inflFactor);
	}

	double get_InfluenceEfficiency() {
		return getInfluenceEfficiency(max(influenceIncome,0), influence);
	}

	double get_InfluenceCap() {
		return getInfluenceStorage(max(influenceIncome,0));
	}

	double get_InfluenceFactor() {
		return inflFactor;
	}

	void modInfluenceFactor(double amount) {
		inflFactorMod += amount;
		_calcReservation();
	}

	double get_InfluencePercentage(Empire& emp) {
		return getInfluencePercentage(emp);
	}

	uint getEdictType() {
		return edict.type;
	}

	Empire@ getEdictEmpire() {
		return edict.empTarget;
	}

	Object@ getEdictObject() {
		return edict.objTarget;
	}

	void clearEdict(Empire& emp) {
		Lock lck(inflMtx);
		edict.clear();
	}

	void conquerEdict(Empire& emp, Empire@ onEmpire) {
		Lock lck(inflMtx);
		edict.type = DET_Conquer;
		@edict.empTarget = onEmpire;
	}

	void addInfluence(double amount) {
		Lock lock(inflMtx);
		partialInfluence += amount;

		int take = floor(partialInfluence);
		if(take != 0) {
			influence += take;
			partialInfluence -= double(take);
		}
	}

	void modInfluenceIncome(int amount) {
		Lock lock(inflMtx);
		modGalacticInfluence(amount);
		influenceIncome += amount;
	}

	int reserveInfluence(double factor, double timer = -1.0) {
		int id = 0;
		{
			Lock lock(inflMtx);
			InfluenceReservation res;
			res.factor = (1.0 - factor);
			res.timer = timer;
			res.id = nextReservationId++;

			reservations.insertLast(res);
			inflFactor *= (1.0 - factor);
			id = res.id;
		}
		return id;
	}

	void _calcReservation() {
		double factor = max(1.0 + inflFactorMod, 0.0);
		for(uint i = 0, cnt = reservations.length; i < cnt; ++i)
			factor *= reservations[i].factor;
		inflFactor = factor;
	}

	void removeInfluenceReservation(int id) {
		Lock lock(inflMtx);
		for(uint i = 0, cnt = reservations.length; i < cnt; ++i) {
			if(reservations[i].id == id) {
				reservations.removeAt(i);
				_calcReservation();
				return;
			}
		}
	}

	bool consumeInfluence(int amount) {
		//Consume an amount
		Lock lock(inflMtx);
		if(influence >= amount) {
			influence -= amount;
			return true;
		}
		return false;
	}

	void modInfluence(int amount) {
		Lock lock(inflMtx);
		influence = max(influence + amount, 0);
	}

	void influenceTick(Empire& emp, double time) {
		StatRecordDelay -= time;
		bool recordStats = StatRecordDelay <= 0;
		if(recordStats)
			StatRecordDelay += 5.0;
			
		{
			Lock lock(inflMtx);

			//Tick down timed reservations
			bool changed = false;
			for(uint i = 0, cnt = reservations.length; i < cnt; ++i) {
				InfluenceReservation@ res = reservations[i];
				if(res.timer < 0)
					continue;

				res.timer -= time;
				if(res.timer <= 0) {
					reservations.removeAt(i);
					changed = true;
					--i; --cnt;
				}
			}
			if(changed)
				_calcReservation();

			//Generate passive influence
			double income = getInfluenceIncome(max(influenceIncome,0), influence, inflFactor);
			double generate = time * income;
			if(generate != 0)
				addInfluence(generate);
			
			if(recordStats) {
				emp.recordStat(stat::Influence, influence);
				emp.recordStat(stat::InfluenceIncome, income);
			}

			//Edicts
			if(edict.type == DET_Conquer) {
				if(!emp.isHostile(edict.empTarget)) {
					emp.clearEdict();
				}
			}
		}

		{
			Lock glock(influenceLock);
			Lock lock(cardMtx);
			for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
				if(cards[i].tick(time))
					cardDelta = true;
			}
		}

		{
			if(intelligenceTimer is null)
				@intelligenceTimer = array<double>(getEmpireCount(), -1.0);
			for(uint i = 0, cnt = intelligenceTimer.length; i < cnt; ++i) {
				if(intelligenceTimer[i] < 0)
					continue;
				auto@ other = getEmpire(i);
				intelligenceTimer[i] -= time;
				if(intelligenceTimer[i] <= 0.0) {
					//Find the intelligence card
					auto@ type = ::getInfluenceCardType("Intelligence");
					if(type is null)
						break;
					auto@ card = type.create(uses=1);
					@card.owner = emp;
					auto@ targ = card.targets.fill("onEmpire");
					if(targ is null)
						break;
					@targ.emp = other;

					for(uint j = 0, cnt = cards.length; j < cnt; ++j) {
						auto@ check = cards[j];
						if(check.canCollapseUses(card)) {
							check.uses -= 1;
							check.lose(1, false);
							if(check.uses == 0) {
								cards.removeAt(j);
								cards.sortAsc();
								intelligenceTimer[i] = -1.0;
								break;
							}

							intelligenceTimer[i] = INTELLIGENCE_TIMEOUT;
							cardDelta = true;
							break;
						}
					}
				}
			}
		}
	}

	void gainCard(Empire& emp, uint typeId, int uses = 1, int quality = 0) {
		auto@ type = ::getInfluenceCardType(typeId);
		if(type is null)
			return;

		InfluenceCard@ card = type.create(uses=uses, quality=1+quality);
		addCard(emp, card);
	}

	int addCard(Empire& emp, InfluenceCard@ fromCard, bool wasBuy = true) {
		InfluenceCard card = fromCard;
		@card.owner = emp;

		Lock glock(influenceLock);
		Lock lock(cardMtx);
		if(card.type.collapseUses && card.uses > 0) {
			for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
				if(cards[i].canCollapseUses(card)) {
					cardDelta = true;
					cards[i].uses += card.uses;
					cards[i].gain(card.uses, wasBuy);
					if(card.uses == 0) {
						cards.removeAt(i);
						cards.sortAsc();
						return -1;
					}
					return cards[i].id;
				}
			}
		}
		card.id = nextCardId++;
		cards.insertLast(card);
		cards.sortAsc();
		cardDelta = true;
		card.gain(card.uses, wasBuy);
		if(card.uses == 0) {
			cards.remove(card);
			cards.sortAsc();
			return -1;
		}
		return card.id;
	}

	void playCard(Empire& emp, int id, Targets@ targets, bool pay = true, InfluenceVote@ vote = null) {
		Lock glock(influenceLock);
		Lock lock(cardMtx);

		InfluenceCard@ card;
		uint index = 0;
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id) {
				index = i;
				@card = cards[i];
				break;
			}
		}

		if(card is null)
			return;

		if(vote !is null) {
			if(!card.canPlay(vote, targets))
				return;
		}
		else {
			if(!card.canPlay(targets))
				return;
		}

		if(pay) {
			if(!card.playConsume(targets, vote))
				return;

			int cost = card.getPlayCost(vote, targets);
			if(cost > 0 && !emp.consumeInfluence(cost))
				return;
		}

		if(vote !is null)
			card.play(vote, targets);
		else
			card.play(targets);

		if(card.uses == 0) {
			cards.remove(card);
			cards.sortAsc();
		}
		cardDelta = true;
	}

	uint getInfluenceCardType(int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				return cards[i].type.id;
		}
		return uint(-1);
	}

	int getInfluenceCardUses(int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				return cards[i].uses;
		}
		return 0;
	}

	uint getUsesOfCardType(uint id) {
		Lock lock(cardMtx);
		uint uses = 0;
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].type.id == id && cards[i].uses != -1)
				uses += uint(cards[i].uses);
		}
		return uses;
	}

	int getInfluenceCardQuality(int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				return cards[i].quality;
		}
		return 0;
	}

	int getCostOfCard(Empire& emp, int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				return cards[i].getPurchaseCost(emp);
		}
		return 0;
	}

	void getInfluenceCard(int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				yield(cards[i]);
		}
	}
	
	uint getInfluenceCardCount() {
		return cards.length;
	}

	void getInfluenceCards() {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i)
			yield(cards[i]);
	}

	void takeCardUse(int id, uint amount = 1) {
		Lock glock(influenceLock);
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ card = cards[i];
			if(card.id == id) {
				if(amount == uint(-1)) {
					card.lose(card.uses, false);
					card.uses = 0;
				}
				else if(card.uses > 0) {
					card.uses = max(0, card.uses - amount);
					card.lose(amount, false);
				}
				if(card.uses == 0) {
					cards.remove(card);
					cards.sortAsc();
					cardDelta = true;
				}
				return;
			}
		}
	}

	void copyCardTo(int id, Empire@ otherEmp, int uses = 0, bool maxQuality = false, int addQuality = 0) {
		InfluenceCard copy;
		bool found = false;

		{
			Lock glock(influenceLock);
			Lock lock(cardMtx);
			for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
				auto@ card = cards[i];
				if(card.id == id) {
					copy = card;
					found = true;
					break;
				}
			}
		}

		if(!found)
			return;

		if(maxQuality)
			copy.quality = copy.type.maxQuality;
		if(addQuality != 0) {
			copy.quality += addQuality;
			if(!copy.type.canOverquality)
				copy.quality = clamp(copy.quality, copy.type.minQuality, copy.type.maxQuality);
			else
				copy.quality = max(copy.quality, copy.type.minQuality);
		}
		if(uses != 0)
			copy.uses = uses;
		cast<InfluenceStore>(otherEmp.InfluenceManager).addCard(otherEmp, copy);
	}

	void gainRandomLeverage(Empire& emp, Empire@ towards, double qualityFactor = 1.0) {
		if(!emp.valid || !emp.major)
			return;
		int cardAmount = 1;
		if(qualityFactor > 3.0) {
			cardAmount = randomi(1, ceil(qualityFactor / 3.0));
			qualityFactor /= double(cardAmount);
		}

		auto@ type = ::getInfluenceCardType("Leverage");
		if(type is null)
			return;

		qualityFactor = pow(randomd(), (2.0 / qualityFactor));
		int quality = type.minQuality + floor(double(type.maxQuality - type.minQuality + 1) * qualityFactor);
		auto@ card = type.create(uses=cardAmount, quality=quality);

		auto@ targ = card.targets.fill("onEmpire");
		if(targ is null)
			return;
		@targ.emp = towards;

		if(card !is null)
			addCard(emp, card);
	}

	bool gainIntelligence(Empire& emp, Empire@ towards, uint amount = 1) {
		if(!emp.valid || !emp.major)
			return false;
		auto@ type = ::getInfluenceCardType("Intelligence");
		if(type is null)
			return true;

		auto@ card = type.create(uses=amount);
		@card.owner = emp;
		auto@ targ = card.targets.fill("onEmpire");
		if(targ is null)
			return true;
		@targ.emp = towards;
		intelligenceTimer[towards.index] = INTELLIGENCE_TIMEOUT;

		Lock glock(influenceLock);
		Lock lock(cardMtx);

		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			auto@ other = cards[i];
			if(other.canCollapseUses(card)) {
				if(other.uses < 3) {
					auto prevUses = other.uses;
					other.uses = min(3, other.uses + amount);
					other.gain(other.uses - prevUses, false);
					cardDelta = true;
					return true;
				}
				else {
					return false;
				}
			}
		}

		addCard(emp, card);
		return true;
	}

	void writeInfluenceManager(Message& msg, bool initial) {
		if(initial || cardDelta) {
			msg.write1();
			Lock lock(cardMtx);
			uint cnt = cards.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				msg << cards[i];
			if(!initial)
				cardDelta = false;
		}
		else {
			msg.write0();
		}

		msg << inflFactor;
		msg.writeSignedSmall(influence);
		msg.writeSignedSmall(influenceIncome);
		msg << edict;
	}
};
