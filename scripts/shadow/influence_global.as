from empire import majorEmpireCount;
import influence;

// {{{ Galactic Influence
int galacticInfluence = 0;
Empire@ SenateLeader;

Empire@ getSenateLeader() {
	return SenateLeader;
}

double getInfluenceIncome(int stock, int stored, double factor) {
	int total = max(galacticInfluence, 0);
	if(stock == 0 || total == 0)
		return 0;
	double pct = double(stock) / double(total);

	//Per budget cycle, distribute 6 points per empire in the game, but don't distribute more than 1 per influence generation
	return min(double(stock) * config::INFLUENCE_STAKE_MAX + ceil(sqrt(double(stock))),
			double(majorEmpireCount) * config::INFLUENCE_PER_EMPIRE * pct) / 180.0
		* getInfluenceEfficiency(stock, stored) * factor;
}

double getInfluenceEfficiency(int stock, int stored) {
	double storage = getInfluenceStorage(stock);
	if(stored > storage)
		return storage / double(stored);
	return 1.0;
}

double getInfluenceStorage(int stock) {
	return double(stock + ceil(sqrt(double(stock)))) * config::INFLUENCE_STAKE_STORE;
}

double getInfluencePercentage(int amt) {
	int total = max(galacticInfluence, 0);
	if(total == 0)
		return 0.0;
	return double(amt) / double(total);
}

double getInfluencePercentage(Empire& emp) {
	double totalGen = 0.0, myGen = 0.0;
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		Empire@ other = getEmpire(i);
		if(!other.major)
			continue;

		double gen = getInfluenceIncome(other.getInfluenceStock(), other.Influence, other.InfluenceFactor);
		totalGen += gen;
		if(emp is other)
			myGen = gen;
	}
	if(totalGen == 0)
		return 0.0;
	return double(myGen) / double(totalGen);
}

void objectRenamed(Object@ obj, string name, bool setNamed = true) {
	obj.name = name;
	if(setNamed)
		obj.named = true;
}
// }}}
// {{{ Cards
Mutex stackMtx;
array<StackInfluenceCard@> cardStack;
double drawInterval;

double drawTimer = 0.0;

double getInfluenceDrawInterval() {
	return drawInterval;
}

double getInfluenceDrawTimer() {
	return drawTimer;
}

void readStack(Message& msg, bool initial = false) {
	Lock lock(stackMtx);
	if(initial)
		msg >> drawInterval;

	msg >> drawTimer;

	if(msg.readBit()) {
		uint cnt = 0;
		msg >> cnt;
		cardStack.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(cardStack[i] is null)
				@cardStack[i] = StackInfluenceCard(msg);
			else
				msg >> cardStack[i];
		}
	}
}

void getInfluenceCardStack() {
	Lock lock(stackMtx);
	for(uint i = 0; i < cardStack.length; ++i)
		yield(cardStack[i]);
}
// }}}
// {{{ Votes
Mutex voteMtx;
array<InfluenceVote@> voteList;
array<InfluenceVote@> activeVotes;

void readVotes(Message& msg, bool initial = false) {
	Lock lock(voteMtx);

	msg.readAlign();
	uint deltas = 0;
	msg >> deltas;

	for(uint i = 0; i < deltas; ++i) {
		uint index = 0;
		msg >> index;

		if(index >= voteList.length)
			voteList.length = index+1;

		if(voteList[index] is null)
			@voteList[index] = InfluenceVote(msg);
		else
			msg >> voteList[index];
	}

	if(msg.readBit()) {
		uint cnt = 0;
		msg >> cnt;
		activeVotes.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			uint id = 0;
			msg >> id;

			@activeVotes[i] = voteList[id];
		}
	}
}

void tickVotes(double time) {
	Lock lock(voteMtx);
	for(uint i = 0, cnt = activeVotes.length; i < cnt; ++i) {
		if(activeVotes[i] !is null && activeVotes[i].active)
			activeVotes[i].tick(time);
	}
}

InfluenceVote@ getInfluenceVoteByID(uint id) {
	Lock lock(voteMtx);
	if(id >= voteList.length)
		return null;
	return voteList[id];
}

void getInfluenceVoteByID_client(Player& pl, uint id) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null)
		return;
	if(plEmp is spectatorEmpire)
		@plEmp = null;
	Lock lock(voteMtx);
	if(id >= voteList.length)
		return;
	if(voteList[id] is null)
		return;
	voteList[id].write(startYield(), plEmp);
	finishYield();
}

void getActiveInfluenceVotes_client(Player& pl) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null)
		return;
	if(plEmp is spectatorEmpire)
		@plEmp = null;
	Lock lock(voteMtx);
	for(uint i = 0, cnt = activeVotes.length; i < cnt; ++i) {
		auto@ vote = activeVotes[i];
		if(vote !is null && (plEmp is null || vote.isPresent(plEmp))) {
			activeVotes[i].write(startYield(), plEmp);
			finishYield();
		}
	}
}

void getInfluenceVoteHistory_client(Player& player, uint limit, int beforeId = -1, bool reverse = true) {
	Empire@ plEmp = player.emp;
	if(plEmp is null)
		return;
	Lock lock(voteMtx);
	if(reverse) {
		if(beforeId == -1 || beforeId > int(voteList.length))
			beforeId = voteList.length;
		if(beforeId == 0)
			return;
		for(int i = beforeId - 1; i >= 0; --i) {
			InfluenceVote@ vote = voteList[i];
			if(vote.active)
				continue;
			vote.write(startYield(), plEmp);
			finishYield();
			if(--limit == 0)
				break;
		}
	}
	else {
		int cnt = voteList.length;
		if(beforeId == -1 || beforeId > cnt)
			beforeId = 0;
		if(beforeId >= cnt - 1)
			return;
		for(int i = beforeId + 1; i < cnt; ++i) {
			InfluenceVote@ vote = voteList[i];
			if(vote.active)
				continue;
			vote.write(startYield(), plEmp);
			finishYield();
			if(--limit == 0)
				break;
		}
	}
}
// }}}
// {{{ Effects
Mutex effectMtx;
array<InfluenceEffect@> activeEffects;

void readEffects(Message& msg, bool initial = false) {
	Lock lock(effectMtx);
	uint cnt = 0;
	msg >> cnt;
	activeEffects.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		if(activeEffects[i] is null)
			@activeEffects[i] = InfluenceEffect();
		if(msg.readBit())
			msg >> activeEffects[i];
	}
}

void tickEffects(double time) {
	Lock lock(effectMtx);
	for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i) {
		if(activeEffects[i].active)
			activeEffects[i].tick(time);
	}
}

void getActiveInfluenceEffects_client() {
	Lock lock(effectMtx);
	for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i)
		yield(activeEffects[i]);
}

Empire@ getInfluenceEffectOwner(int id) {
	Lock lock(effectMtx);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id)
			return effect.owner;
	}
	return null;
}

bool canDismissInfluenceEffect(int id, Empire@ emp = null) {
	Lock lock(effectMtx);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id) {
			if(emp is null)
				@emp = effect.owner;
			return effect.canDismiss(emp);
		}
	}
	return false;
}
// }}}
// {{{ Treaties
Mutex treatyMtx;
array<Treaty@> activeTreaties;

void readTreaties(Message& msg, bool initial = false) {
	Lock lock(treatyMtx);
	uint cnt = 0;
	msg >> cnt;
	activeTreaties.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		if(activeTreaties[i] is null)
			@activeTreaties[i] = Treaty();
		if(msg.readBit())
			msg >> activeTreaties[i];
	}
}

void getActiveInfluenceTreaties_client(Player& pl) {
	Empire@ plEmp = pl.emp;
	Lock lock(treatyMtx);
	for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
		if(activeTreaties[i].isVisibleTo(plEmp))
			yield(activeTreaties[i]);
	}
}
// }}}

void syncInitial(Message& msg) {
	msg >> galacticInfluence;
	msg >> SenateLeader;
	readStack(msg, true);
	readVotes(msg, true);
	readEffects(msg, true);
	readTreaties(msg, true);
}

void recvPeriodic(Message& msg) {
	msg >> galacticInfluence;
	msg >> SenateLeader;
	readStack(msg);
	readVotes(msg);
	readEffects(msg);
	readTreaties(msg);
}

void tick(double time) {
	tickVotes(time);
	tickEffects(time);
}
