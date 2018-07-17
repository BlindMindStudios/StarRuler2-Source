import influence;

//These strategies are flags regarding behaviors
enum VoteStrategy {
	//Attempt to provide support (otherwise attempt to defeat)
	VS_Support = 1,
	
	//Attempt to create the vote if it isn't already present
	VS_Create = 64
};

int64 buildVoteHash(uint8 strat) {
	return (int64(ACT_Vote) << ACT_BIT_OFFSET) | (int64(strat) << 24);
}

class Vote : Action {
	uint8 strat;
	int64 Hash;
	/*InfluenceVote@ vote;*/
	
	Vote(uint8 Strat) {
		strat = Strat;
		Hash = buildVoteHash(Strat);
	}

	Vote(BasicAI@ ai, SaveFile& msg) {
		msg >> strat;
	}

	void postLoad(BasicAI@ ai) {
	}

	void save(BasicAI@ ai, SaveFile& msg) {
		msg << strat;
	}
	
	int64 get_hash() const {
		return Hash;
	}

	ActionType get_actionType() const {
		return ACT_Vote;
	}
	
	string get_state() const {
		return "Voting on proposition";
	}
	
	bool perform(BasicAI@ ai) {
		return true;
	}
	
};
