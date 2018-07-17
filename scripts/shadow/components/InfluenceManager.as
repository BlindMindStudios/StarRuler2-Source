import influence;
import double getInfluenceIncome(int stock, int stored, double factor) from "influence_global";
import double getInfluenceEfficiency(int stock, int stored) from "influence_global";
import double getInfluencePercentage(Empire& emp) from "influence_global";
import double getInfluenceStorage(int stock) from "influence_global";

tidy class InfluenceManager : Component_InfluenceManager {
	Mutex inflMtx;
	Mutex cardMtx;

	int influence = 0;
	int influenceIncome = 0;
	double inflFactor = 1.0;
	array<InfluenceCard@> cards;

	DiplomacyEdict edict;

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

	double get_InfluencePercentage(Empire& emp) {
		return getInfluencePercentage(emp);
	}

	double get_InfluenceCap() {
		return getInfluenceStorage(max(influenceIncome,0));
	}

	double get_InfluenceFactor() {
		return inflFactor;
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

	int getInfluenceCardQuality(int id) {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
			if(cards[i].id == id)
				return cards[i].quality;
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

	void influenceTick(Empire& emp, double time) {
	}
	
	uint getInfluenceCardCount() {
		return cards.length;
	}

	void getInfluenceCards() {
		Lock lock(cardMtx);
		for(uint i = 0, cnt = cards.length; i < cnt; ++i)
			yield(cards[i]);
	}

	void readInfluenceManager(Message& msg) {
		if(msg.readBit()) {
			Lock lock(cardMtx);
			uint cnt = msg.readSmall();
			cards.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				if(cards[i] is null)
					@cards[i] = InfluenceCard();
				msg >> cards[i];
			}
		}

		msg >> inflFactor;
		influence = msg.readSignedSmall();
		influenceIncome = msg.readSignedSmall();
		msg >> edict;
	}
}
