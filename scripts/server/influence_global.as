import influence;
import saving;
import attributes;
from influence import InfluenceStore;
from empire import majorEmpireCount;
import notifications;
from notifications import NotificationStore;
import util.formatting;
from achievements import giveAchievement;

Mutex influenceLock;

// {{{ Galactic Influence
locked_int galacticInfluence = 0;
bool activeDelta = false;
double leaderCardTimer = 0;

Empire@ SenateLeader;
Empire@ getSenateLeader() {
	return SenateLeader;
}

void electSenateLeader(Empire@ emp) {
	{
		Lock lck(influenceLock);
		@SenateLeader = emp;
	}

	if(emp is playerEmpire || emp.player !is null)
		giveAchievement(emp, "ACH_SENATE_LEADER");
}

void modGalacticInfluence(int mod) {
	galacticInfluence += mod;
}

double getInfluenceIncome(int stock, int stored, double factor) {
	int total = max(galacticInfluence.value, 0);
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
	int total = max(galacticInfluence.value, 0);
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
// }}}
// {{{ Cards
array<StackInfluenceCard@> cardStack;
array<StackInfluenceCard@> deck;
int nextStackId = 1;
uint stackSize;
double drawInterval;
bool stackDelta = false;

double drawTimer = 0.0;

double getInfluenceDrawInterval() {
	return drawInterval;
}

double getInfluenceDrawTimer() {
	return drawTimer;
}

void saveStack(SaveFile& file) {
	file << drawTimer;
	file << nextStackId;
	file << stackSize;
	file << drawInterval;

	uint cnt = cardStack.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << cardStack[i];

	cnt = deck.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << deck[i];
}

void loadStack(SaveFile& file) {
	file >> drawTimer;
	file >> nextStackId;
	file >> stackSize;
	file >> drawInterval;

	uint cnt = 0;
	file >> cnt;
	cardStack.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		@cardStack[i] = StackInfluenceCard(file);

	if(file >= SV_0034) {
		file >> cnt;
		deck.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@deck[i] = StackInfluenceCard(file);
	}
}

void writeStack(Message& msg, bool initial = false) {
	if(initial)
		msg << drawInterval;

	msg << drawTimer;

	if(stackDelta || initial) {
		msg.write1();
		Lock lock(influenceLock);
		uint cnt = cardStack.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << cardStack[i];

		if(!initial)
			stackDelta = false;
	}
	else {
		msg.write0();
	}
}

void initStack() {
	Lock lock(influenceLock);

	//Precalculate stack
	stackSize = clamp(config::CARD_STACK_BASE + config::CARD_STACK_PER_PLAYER * majorEmpireCount,
				config::CARD_STACK_MIN, config::CARD_STACK_MAX);
	drawInterval = config::CARD_STACK_DRAW_INTERVAL;

	//Create the initial deck
	generateDeck();

	//Cut down first deck to a randomized size
	deck.reverse();
	deck.length = randomi(stackSize, deck.length);
	deck.reverse();

	//Create the initial stack
	for(uint i = 0; i < stackSize; ++i)
		drawOntoStack();

	//Set stack card placement
	for(uint i = 0, cnt = cardStack.length; i < cnt; ++i)
		cardStack[i].placement = i;

	//Start the timers
	drawTimer = drawInterval;
}

void modInfluenceStackSize(int mod) {
	Lock lock(influenceLock);
	stackSize = clamp(stackSize + mod, config::CARD_STACK_MIN, config::CARD_STACK_MAX);
}

void generateDeck() {
	Lock lock(influenceLock);

	//Create all the cards
	array<StackInfluenceCard@> events;
	deck.reserve(getInfluenceDeckSize());

	for(uint i = 0, cnt = getInfluenceCardTypeCount(); i < cnt; ++i) {
		auto@ type = getInfluenceCardType(i);

		if(type.cls == ICC_Event && config::ENABLE_INFLUENCE_EVENTS == 0)
			continue;
		if(type.dlc.length != 0 && !hasDLC(type.dlc))
			continue;
		if(!type.canGenerateOnStack())
			continue;

		int amt = int(floor(type.frequency));
		double partial = type.frequency - floor(type.frequency);
		if(randomd() < partial)
			amt += 1;
		for(int n = 0; n < amt; ++n) {
			StackInfluenceCard card;
			card.id = nextStackId++;
			type.generate(card);

			if(type.cls == ICC_Event)
				events.insertLast(card);
			else
				deck.insertLast(card);
		}
	}

	//Shuffle the deck
	for(int i = deck.length - 1; i >= 0; --i) {
		int swapIndex = randomi(0, i);

		auto@ first = deck[i];
		auto@ second = deck[swapIndex];

		@deck[i] = second;
		@deck[swapIndex] = first;
	}

	//Seed in the events
	if(events.length != 0) {
		uint eventCount = round(randomd(config::INFLUENCE_EVENT_FREQ_MIN, config::INFLUENCE_EVENT_FREQ_MAX) * double(deck.length));
		eventCount = min(eventCount, events.length);

		uint spacing = deck.length / max(eventCount, 2);
		uint index = randomi(0, spacing/2);
		for(uint i = 0; i < eventCount; ++i) {
			uint takeIndex = randomi(0, events.length-1);

			deck.insertAt(index, events[takeIndex]);
			events.removeAt(takeIndex);

			index += spacing;
		}
	}

	//Print out the deck
	//print("Generated deck: "+deck.length);
	//for(int i = deck.length - 1; i >= 0; --i) {
	//	print(" * "+deck[i].type.name);
	//}
}

void drawOntoStack() {
	Lock lock(influenceLock);

	//Generate new deck if needed
	if(deck.length == 0)
		generateDeck();

	//Take card from the top of the deck
	StackInfluenceCard@ card = deck.last;
	deck.removeLast();

	//Add the card to the stack
	cardStack.insertLast(card);
	card.enterStack();

	//Activate event cards
	if(card.type.cls == ICC_Event) {
		@card.owner = defaultEmpire;
		card.play(Targets(card.targets));
	}

	stackDelta = true;
}

void rotateInfluenceStack() {
	Lock lock(influenceLock);
	for(int i = cardStack.length - 1; i >= 0; --i) {
		auto@ card = cardStack[i];
		if(card.purchasedBy !is null || i == 0)
			cardStack.removeAt(i);
	}

	while(cardStack.length < stackSize)
		drawOntoStack();

	for(uint i = 0, cnt = cardStack.length; i < cnt; ++i)
		cardStack[i].placement = i;

	stackDelta = true;
	drawTimer = drawInterval;
}

void tickStack(double time) {
	Lock lock(influenceLock);

	//Draw new cards periodically
	drawTimer -= time;
	while(drawTimer <= 0.0)
		rotateInfluenceStack();

	//Tick all the cards on the stack
	for(uint i = 0, cnt = cardStack.length; i < cnt; ++i)
		cardStack[i].tickStack(time);
}

array<const StackInfluenceCard@>@ getInfluenceStack() {
	array<const StackInfluenceCard@> cards;
	{
		Lock lock(influenceLock);
		cards.length = cardStack.length;
		for(uint i = 0; i < cards.length; ++i) {
			StackInfluenceCard card;
			card = cardStack[i];
			@cards[i] = card;
		}
	}
	
	return cards;
}

void disableBuyCardsTargetedAgainst(Empire& emp) {
	Lock lock(influenceLock);
	for(uint i = 0, cnt = cardStack.length; i < cnt; ++i) {
		auto@ card = cardStack[i];
		if(card.purchasedBy !is null)
			continue;
		if(card.targets.length == 0)
			continue;

		auto@ targ = card.targets[0];
		if(targ.filled && targ.emp is emp) {
			@card.purchasedBy = emp;
			stackDelta = true;
		}
	}
}

void buyCardFromInfluenceStack(Player& pl, int id) {
	Empire@ emp = pl.emp;
	if(emp is null || !emp.valid)
		return;
	buyCardFromInfluenceStack(emp, id, pay=true);
}

void buyCardFromInfluenceStack(Empire@ emp, int id, bool pay = true) {
	StackInfluenceCard@ card;
	{
		Lock lock(influenceLock);
		uint index = 0;
		for(uint i = 0, cnt = cardStack.length; i < cnt; ++i) {
			if(cardStack[i].id == id) {
				index = i;
				@card = cardStack[i];
				break;
			}
		}

		if(card is null)
			return;

		if(!card.canPurchase(emp))
			return;

		if(pay) {
			if(!card.purchaseConsume(emp))
				return;

			int cost = card.getPurchaseCost(emp);
			if(!emp.consumeInfluence(cost))
				return;

			emp.modAttribute(EA_InfluenceCardsBought, AC_Add, 1.0);

			int extraQuality = floor(emp.InfluenceBuysExtraQuality);
			if(extraQuality != 0) {
				card.quality += extraQuality;
				card.quality = max(card.quality, card.type.minQuality);
				if(!card.type.canOverquality || card.type.minQuality == card.type.maxQuality)
					card.quality = min(card.quality, card.type.maxQuality);
			}

			int extraUses = floor(emp.InfluenceBuysExtraUses);
			if(extraUses != 0)
				card.uses += extraUses;
		}

		//Remove from the stack
		@card.purchasedBy = emp;
		card.leaveStack(true);
	}

	//Add to the empire
	int cardId = cast<InfluenceStore>(emp.InfluenceManager).addCard(emp, card);
	if(card.type.cls == ICC_Instant)
		cast<InfluenceStore>(emp.InfluenceManager).playCard(emp, cardId, card.targets);

	stackDelta = true;
}

void getInfluenceCardStack() {
	Lock lock(influenceLock);
	for(uint i = 0, cnt = cardStack.length; i < cnt; ++i)
		yield(cardStack[i]);
}

void playInfluenceCard(Player& pl, int id, Targets@ targets, uint voteId = uint(-1)) {
	Empire@ emp = pl.emp;
	if(emp is null || !emp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote;
	if(voteId != uint(-1))
		@vote = getInfluenceVoteByID(voteId);
	cast<InfluenceStore>(emp.InfluenceManager).playCard(emp, id, targets, true, vote = vote);
}

void playInfluenceCard_server(Empire@ emp, int id, Targets@ targets, uint voteId = uint(-1)) {
	if(emp is null || !emp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote;
	if(voteId != uint(-1))
		@vote = getInfluenceVoteByID(voteId);
	cast<InfluenceStore>(emp.InfluenceManager).playCard(emp, id, targets, true, vote = vote);
}

void fillInfluenceStackWithLeverage(Empire@ against, int count = -1) {
	if(against is null || !against.valid)
		return;
	auto@ type = getInfluenceCardType("Leverage");
	if(type is null)
		return;
	Lock lock(influenceLock);
	if(count == -1)
		count = cardStack.length;
	for(int i = 0; i < count; ++i) {
		StackInfluenceCard card;
		card.id = nextStackId++;
		type.generate(card);
		auto@ targ = card.targets.fill("onEmpire");
		if(targ is null)
			return;
		@targ.emp = against;
		deck.insertLast(card);
	}
}
// }}}
// {{{ Votes
array<InfluenceVote@> voteList;
array<InfluenceVote@> activeVotes;
bool activeVoteDelta = false;

void saveVotes(SaveFile& file) {
	uint cnt = voteList.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << voteList[i];

	cnt = activeVotes.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << activeVotes[i].id;
}

void loadVotes(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;
	voteList.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		@voteList[i] = InfluenceVote(file);

	file >> cnt;
	activeVotes.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		uint id = 0;
		file >> id;
		@activeVotes[i] = voteList[id];
	}
}

void writeVotes(Message& msg, bool initial = false) {
	Lock lock(influenceLock);
	msg.writeAlign();
	uint pos = msg.reserve();
	uint amount = 0;
	for(uint i = 0, cnt = voteList.length; i < cnt; ++i) {
		if(voteList[i].delta || initial) {
			msg << i;
			msg << voteList[i];
			++amount;
			if(!initial)
				voteList[i].delta = false;
		}
	}
	msg.fill(pos, amount);

	if(activeVoteDelta || initial) {
		msg.write1();
		if(!initial)
			activeVoteDelta = false;

		uint cnt = activeVotes.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << activeVotes[i].id;
	}
	else {
		msg.write0();
	}
}

uint getLastInfluenceVoteId() {
	return voteList.length - 1;
}

InfluenceVote@ getInfluenceVoteByID(uint id) {
	Lock lock(influenceLock);
	if(id >= voteList.length)
		return null;
	return voteList[id];
}

void syncInfluenceVote(uint id, InfluenceVote& vote) {
	Lock lock(influenceLock);
	if(id >= voteList.length)
		return;
	vote = voteList[id];
}

void getInfluenceVoteByID_client(Player& pl, uint id) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null)
		return;
	if(plEmp is spectatorEmpire)
		@plEmp = null;
	Lock lock(influenceLock);
	if(id >= voteList.length)
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
	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeVotes.length; i < cnt; ++i) {
		auto@ vote = activeVotes[i];
		if(plEmp is null || vote.isPresent(plEmp)) {
			activeVotes[i].write(startYield(), plEmp);
			finishYield();
		}
	}
}

void getInfluenceVoteHistory_client(Player& player, uint limit, int beforeId = -1, bool reverse = true) {
	Empire@ plEmp = player.emp;
	if(plEmp is null)
		return;
	Lock lock(influenceLock);
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

array<InfluenceVoteStub@>@ getActiveInfluenceVotes() {
	array<InfluenceVoteStub@> stubs;
	if(activeVotes.isEmpty())
		return stubs;
	{
		Lock lock(influenceLock);
		stubs.length = activeVotes.length;
		for(uint i = 0, cnt = activeVotes.length; i < cnt; ++i)
			@stubs[i] = InfluenceVoteStub(activeVotes[i]);
	}
	
	return stubs;
}

array<InfluenceVoteStub@>@ getInfluenceVotesSince(uint id) {
	if(activeVotes.isEmpty())
		return null;
	array<InfluenceVoteStub@>@ stubs = null;
	{
		Lock lock(influenceLock);
		for(uint i = 0, cnt = activeVotes.length; i < cnt; ++i) {
			if(id != uint(-1) && activeVotes[i].id <= id)
				continue;
			if(stubs is null)
				@stubs = array<InfluenceVoteStub@>();
			stubs.insertLast(InfluenceVoteStub(activeVotes[i]));
		}
	}
	return stubs;
}

array<InfluenceVoteStub@>@ getActiveInfluenceVotes_server() {
	return getActiveInfluenceVotes();
}

InfluenceVote@ startInfluenceVote(Empire@ byEmpire, const InfluenceVoteType@ type, Targets@ targets, InfluenceCard@ fromCard = null) {
	Lock lock(influenceLock);
	InfluenceVote vote(type);
	if(!vote.checkTargets(targets))
		return null;
	if(byEmpire !is defaultEmpire)
		vote.empiresPresent &= byEmpire.ContactMask.value;
	vote.id = voteList.length;
	vote.targets = targets;
	voteList.insertLast(vote);
	activeVotes.insertLast(vote);
	vote.start(targets, byEmpire, fromCard);
	activeVoteDelta = true;
	return vote;
}

void tickVotes(double time) {
	Lock lock(influenceLock);
	for(int i = activeVotes.length - 1; i >= 0; --i) {
		auto@ vote = activeVotes[i];
		if(vote.active) {
			vote.tick(time);
		}
		if(!vote.active) {
			activeVotes.removeAt(i);
			activeVoteDelta = true;
		}
	}
}

void withdrawVote_client(Player& pl, uint voteId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.active && vote.startedBy is plEmp)
		vote.withdraw();
}

void leaveVote_client(Player& pl, uint voteId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.active && vote.isPresent(plEmp)) {
		vote.addEvent(InfluenceVoteEvent(IVET_Leave, plEmp));
		vote.leave(plEmp);
	}
}

void makeInfluenceVoteOffer_client(Player& pl, uint voteId, InfluenceVoteOffer@ offer) {
	@offer.fromEmpire = pl.emp;
	if(offer.fromEmpire is null || !offer.fromEmpire.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.isPresent(offer.fromEmpire))
		vote.makeOffer(offer);
}

void claimInfluenceVoteOffer_client(Player& pl, uint voteId, int offerId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.isPresent(plEmp))
		vote.claimOffer(plEmp, offerId);
}

void makeInfluenceVoteOffer_server(Empire@ emp, uint voteId, InfluenceVoteOffer@ offer) {
	@offer.fromEmpire = emp;
	if(offer.fromEmpire is null || !offer.fromEmpire.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.isPresent(offer.fromEmpire))
		vote.makeOffer(offer);
}

void claimInfluenceVoteOffer_server(Empire@ emp, uint voteId, int offerId) {
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.isPresent(emp))
		vote.claimOffer(emp, offerId);
}

void voteMessage_client(Player& pl, uint voteId, string message) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	InfluenceVote@ vote = getInfluenceVoteByID(voteId);
	if(vote !is null && vote.isPresent(plEmp)) {
		InfluenceVoteEvent evt(IVET_Message, plEmp);
		evt.text = message;
		vote.addEvent(evt);
	}
}

void makeDonation_client(Player& pl, Empire@ toEmp, DiplomacyOffer@ offer) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid || toEmp is null || !toEmp.valid)
		return;
	makeDonation(plEmp, toEmp, offer);
}

void makeDonation(Empire@ emp, Empire@ toEmp, DiplomacyOffer@ offer) {
	if(!offer.canOffer(emp))
		return;
	offer.memo(emp);
	offer.take(emp);
	offer.give(emp, toEmp, delayMaintenance = true, preventFloat = true);

	DonationNotification n;
	n.offer = offer;
	@n.fromEmpire = emp;
	cast<NotificationStore>(toEmp.Notifications).addNotification(toEmp, n);
}
// }}}
// {{{ Effects
array<InfluenceEffect@> activeEffects;
int nextEffectId = 1;
bool activeEffectDelta = false;

void saveEffects(SaveFile& file) {
	file << nextEffectId;
	uint cnt = activeEffects.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << activeEffects[i];
}

void loadEffects(SaveFile& file) {
	file >> nextEffectId;
	uint cnt = 0;
	file >> cnt;
	activeEffects.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		@activeEffects[i] = InfluenceEffect(file);
}

void writeEffects(Message& msg, bool initial = false) {
	Lock lock(influenceLock);
	uint cnt = activeEffects.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i) {
		if(activeEffects[i].delta || initial || activeEffectDelta) {
			msg.write1();
			msg << activeEffects[i];
			if(!initial)
				activeEffects[i].delta = false;
		}
		else {
			msg.write0();
		}
	}
	if(!initial)
		activeEffectDelta = false;
}

int getLastInfluenceEffectId() {
	return nextEffectId - 1;
}

void getActiveInfluenceEffects_client() {
	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i)
		yield(activeEffects[i]);
}

array<InfluenceEffect@>@ getActiveInfluenceEffects() {
	array<InfluenceEffect@> stubs;
	if(activeEffects.isEmpty())
		return stubs;
	{
		Lock lock(influenceLock);
		stubs.length = activeEffects.length;
		for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i) {
			InfluenceEffect eff;
			eff = activeEffects[i];
			@stubs[i] = eff;
		}
	}
	
	return stubs;
}

InfluenceEffect@ getRandomActiveInfluenceEffect() {
	if(activeEffects.length == 0)
		return null;
	InfluenceEffect eff;
	{
		Lock lock(influenceLock);
		if(activeEffects.length == 0)
			return null;
		eff = activeEffects[randomi(0, activeEffects.length-1)];
	}
	return eff;
}

Empire@ getTaggedEffectOwner(const string& tag) {
	if(activeEffects.length == 0)
		return null;
	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i) {
		if(activeEffects[i].type.hasTag(tag))
			return activeEffects[i].owner;
	}
	return null;
}

array<InfluenceEffect@>@ getInfluenceEffectsSince(int id) {
	if(activeEffects.isEmpty())
		return null;
	array<InfluenceEffect@>@ stubs = null;
	{
		Lock lock(influenceLock);
		for(uint i = 0, cnt = activeEffects.length; i < cnt; ++i) {
			if(activeEffects[i].id <= id)
				continue;
			if(stubs is null)
				@stubs = array<InfluenceEffect@>();
			InfluenceEffect eff;
			eff = activeEffects[i];
			stubs.insertLast(eff);
		}
	}
	return stubs;
}

InfluenceEffect@ createInfluenceEffect(Empire@ byEmpire, const InfluenceEffectType@ type, Targets@ targets, double duration = 0.0) {
	Lock lock(influenceLock);
	InfluenceEffect effect(type);
	if(!effect.checkTargets(targets))
		return null;
	effect.id = nextEffectId++;
	effect.targets = targets;
	activeEffects.insertLast(effect);
	effect.start(targets, byEmpire, duration);
	activeEffectDelta = true;
	return effect;
}

void tickEffects(double time) {
	Lock lock(influenceLock);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.active)
			effect.tick(time);
		if(!effect.active) {
			activeEffectDelta = true;
			activeEffects.removeAt(i);
		}
	}
}

void dismissEffect_client(Player& pl, int id) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id) {
			if(!effect.canDismiss(plEmp))
				return;
			effect.dismiss(plEmp);
			if(!effect.active) {
				activeEffectDelta = true;
				activeEffects.removeAt(i);
			}
			return;
		}
	}
}

void dismissEffect(Empire@ byEmpire, int id) {
	Lock lock(influenceLock);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id) {
			effect.dismiss(byEmpire);
			if(!effect.active) {
				activeEffectDelta = true;
				activeEffects.removeAt(i);
			}
			return;
		}
	}
}

InfluenceEffect@ getInfluenceEffect(int id) {
	Lock lock(influenceLock);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id)
			return effect;
	}
	return null;
}

Empire@ getInfluenceEffectOwner(int id) {
	Lock lock(influenceLock);
	for(int i = activeEffects.length - 1; i >= 0; --i) {
		auto@ effect = activeEffects[i];
		if(effect.id == id)
			return effect.owner;
	}
	return null;
}

bool canDismissInfluenceEffect(int id, Empire@ emp = null) {
	Lock lock(influenceLock);
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
array<Treaty@> activeTreaties;
int nextTreatyId = 1;
bool activeTreatiesDelta = false;

void saveTreaties(SaveFile& file) {
	file << nextTreatyId;
	uint cnt = activeTreaties.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i)
		file << activeTreaties[i];
}

void loadTreaties(SaveFile& file) {
	if(file < SV_0057)
		return;
	file >> nextTreatyId;
	uint cnt = 0;
	file >> cnt;
	activeTreaties.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		@activeTreaties[i] = Treaty();
		file >> activeTreaties[i];
	}
}

void writeTreaties(Message& msg, bool initial = false) {
	Lock lock(influenceLock);
	uint cnt = activeTreaties.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i) {
		if(activeTreaties[i].delta || initial || activeTreatiesDelta) {
			msg.write1();
			msg << activeTreaties[i];
			if(!initial)
				activeTreaties[i].delta = false;
		}
		else {
			msg.write0();
		}
	}
	if(!initial)
		activeTreatiesDelta = false;
}

void getActiveInfluenceTreaties_client(Player& pl) {
	Empire@ plEmp = pl.emp;
	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
		if(activeTreaties[i].isVisibleTo(plEmp))
			yield(activeTreaties[i]);
	}
}

void createTreaty_client(Player& pl, Treaty@ treaty) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	if(plEmp.SubjugatedBy !is null)
		return;
	for(uint i = 0, cnt = treaty.clauses.length; i < cnt; ++i) {
		if(!treaty.clauses[i].type.freeClause)
			return;
	}
	uint invMask = treaty.inviteMask;
	treaty.inviteMask = 0;
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		auto@ other = getEmpire(i);
		if(other.mask & invMask == 0)
			continue;
		if(!treaty.canInvite(plEmp, other))
			return;
	}
	treaty.inviteMask = invMask;
	if(treaty.joinedEmpires.length != 0)
		return;
	createTreaty(plEmp, treaty);
}

Treaty@ createTreaty(Empire@ byEmpire, Treaty@ treaty) {
	Lock lock(influenceLock);
	treaty.init(byEmpire);
	treaty.join(byEmpire, force = true);
	treaty.id = nextTreatyId++;
	activeTreaties.insertLast(treaty);
	activeTreatiesDelta = true;
	if(treaty.joinedEmpires.length >= 2)
		treaty.start();
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		auto@ other = getEmpire(i);
		if(!other.major || treaty.inviteMask & other.mask == 0)
			continue;
		other.notifyTreaty(treaty.id, TET_Invite, byEmpire, other);
	}
	return treaty;
}

void offerSurrender_client(Player& pl, Empire@ toEmp) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	offerSurrender(plEmp, toEmp);
}

void offerSurrender(Empire@ from, Empire@ to) {
	auto@ subjugateClause = getInfluenceClauseType("SubjugateClause");
	if(subjugateClause is null)
		return;
	if(from.SubjugatedBy !is null || to.SubjugatedBy !is null)
		return;
	if(from.team != -1 && config::ALLOW_TEAM_SURRENDER == 0)
		return;

	Treaty treaty;
	treaty.inviteMask = to.mask;
	treaty.name = format(locale::SURRENDER_OFFER, formatEmpireName(from));

	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
		auto@ other = activeTreaties[i];
		if(other.leader !is null)
			continue;
		if(other.inviteMask != treaty.inviteMask)
			continue;
		if(other.presentMask != from.mask)
			continue;
		if(!other.hasClause(subjugateClause))
			continue;
		return;
	}

	treaty.addClause(subjugateClause);
	treaty.addClause(getInfluenceClauseType("ConstClause"));
	createTreaty(from, treaty);
}

void demandSurrender_client(Player& pl, Empire@ toEmp) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	demandSurrender(plEmp, toEmp);
}

void demandSurrender(Empire@ from, Empire@ to) {
	auto@ subjugateClause = getInfluenceClauseType("SubjugateClause");
	if(subjugateClause is null)
		return;
	if(from.SubjugatedBy !is null || to.SubjugatedBy !is null)
		return;
	if(to.team != -1 && config::ALLOW_TEAM_SURRENDER == 0)
		return;

	Treaty treaty;
	@treaty.leader = from;
	treaty.inviteMask = to.mask;
	treaty.name = format(locale::SURRENDER_DEMAND, formatEmpireName(to));

	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
		auto@ other = activeTreaties[i];
		if(other.leader !is treaty.leader)
			continue;
		if(other.inviteMask != treaty.inviteMask)
			continue;
		if(!other.hasClause(subjugateClause))
			continue;
		return;
	}

	treaty.addClause(subjugateClause);
	treaty.addClause(getInfluenceClauseType("ConstClause"));
	createTreaty(from, treaty);
}

void forceSubjugate(Empire& master, Empire& vassal) {
	auto@ subjugateClause = getInfluenceClauseType("SubjugateClause");
	if(subjugateClause is null)
		return;
	if(master.SubjugatedBy !is null || vassal.SubjugatedBy !is null)
		return;
	if(master.team != -1 && master.team == vassal.team)
		return;

	Treaty treaty;
	@treaty.leader = master;
	treaty.inviteMask = vassal.mask;
	treaty.name = format(locale::SURRENDER_DEMAND, formatEmpireName(master));
	treaty.addClause(subjugateClause);
	treaty.addClause(getInfluenceClauseType("ConstClause"));

	Lock lock(influenceLock);
	createTreaty(master, treaty);
	joinTreaty(vassal, treaty.id);
}

void inviteToTreaty_client(Player& pl, int treatyId, Empire@ invite) {
	if(invite is null)
		return;
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	if(!treaty.canInvite(plEmp, invite))
		return;
	treaty.invite(plEmp, invite);
}

void inviteToTreaty(Empire& emp, int treatyId, Empire& invite, bool force = false) {
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	if(!force && !treaty.canInvite(emp, invite))
		return;
	treaty.invite(emp, invite);
}

void joinTreaty_client(Player& pl, int treatyId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	joinTreaty(plEmp, treatyId);
}

void joinTreaty(Empire& emp, int treatyId, bool force = false) {
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	treaty.join(emp, force=force);
}

void leaveTreaty_client(Player& pl, int treatyId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	leaveTreaty(plEmp, treatyId);
}

void leaveTreaty(Empire& emp, int treatyId, bool force = false) {
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	if(!force && !treaty.canLeave(emp))
		return;
	if(emp !is treaty.leader) {
		treaty.leave(emp);
		_checkTreaty(treaty);
	}
	else {
		endTreaty(treaty.id);
	}
}

void sendPeaceOffer_client(Player& pl, Empire& toEmp) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	sendPeaceOffer(plEmp, toEmp);
}

void sendPeaceOffer(Empire& from, Empire@ to) {
	auto@ clause = getInfluenceClauseType("PeaceClause");
	if(clause is null)
		return;
	if(from.SubjugatedBy !is null || to.SubjugatedBy !is null)
		return;

	Treaty treaty;
	treaty.inviteMask = to.mask;
	treaty.name = format(locale::PEACE_OFFER, formatEmpireName(from));

	Lock lock(influenceLock);
	for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
		auto@ other = activeTreaties[i];
		if(other.leader !is null)
			continue;
		if(!other.hasClause(clause))
			continue;

		if(other.presentMask == to.mask) {
			if(other.inviteMask & from.mask != 0) {
				joinTreaty(from, other.id);
				return;
			}
		}
		else if(other.presentMask == from.mask) {
			if(other.inviteMask == treaty.inviteMask)
				return;
		}
	}

	treaty.addClause(clause);
	createTreaty(from, treaty);
}

void leaveTreatiesWith(Empire& emp, uint leaveMask) {
	Lock lock(influenceLock);
	for(int i = activeTreaties.length - 1; i >= 0; --i) {
		auto@ treaty = activeTreaties[i];
		if(treaty is null)
			continue;
		if(treaty.presentMask & leaveMask == 0)
			continue;
		if(!treaty.canLeave(emp))
			continue;
		if(emp !is treaty.leader) {
			treaty.leave(emp);
			_checkTreaty(treaty);
		}
		else {
			endTreaty(treaty.id);
		}
	}
}

bool isInTreatiesWith(Empire& emp, uint otherMask) {
	Lock lock(influenceLock);
	for(int i = activeTreaties.length - 1; i >= 0; --i) {
		auto@ treaty = activeTreaties[i];
		if(treaty is null)
			continue;
		if(treaty.presentMask & otherMask != 0)
			return true;
	}
	return false;
}

void declineTreaty_client(Player& pl, int treatyId) {
	Empire@ plEmp = pl.emp;
	if(plEmp is null || !plEmp.valid)
		return;
	declineTreaty(plEmp, treatyId);
}

void declineTreaty(Empire& emp, int treatyId) {
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	if(treaty.inviteMask & emp.mask == 0)
		return;
	treaty.decline(emp);
	_checkTreaty(treaty);
}

void _checkTreaty(Treaty@ treaty) {
	uint potential = 0, actual = 0;
	if(treaty.leader !is null) {
		potential += 1;
		actual += 1;
	}
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		auto@ other = getEmpire(i);
		if(other is treaty.leader)
			continue;
		if(treaty.presentMask & other.mask != 0) {
			potential += 1;
			actual += 1;
		}
		else if(treaty.inviteMask & other.mask != 0) {
			potential += 1;
		}
	}

	if(potential <= 1)
		endTreaty(treaty.id);
	else if(actual <= 1 && treaty.started)
		treaty.end();
}

void endTreaty(int treatyId) {
	Lock lock(influenceLock);
	Treaty@ treaty = getTreaty(treatyId);
	if(treaty is null)
		return;
	treaty.end();
	activeTreaties.remove(treaty);
	activeTreatiesDelta = true;
}

void tickTreaties(double time) {
	Lock lock(influenceLock);
	for(int i = activeTreaties.length - 1; i >= 0; --i) {
		auto@ treaty = activeTreaties[i];
		if(treaty.started) {
			treaty.tick(time);
			if(!treaty.started) {
				activeTreatiesDelta = true;
				activeTreaties.remove(treaty);
			}
		}
	}
}

Treaty@ getTreaty(uint id) {
	Lock lock(influenceLock);
	for(int i = activeTreaties.length - 1; i >= 0; --i) {
		auto@ treaty = activeTreaties[i];
		if(treaty.id == id)
			return treaty;
	}
	return null;
}

Treaty@ getTreatyDesc(uint id) {
	Lock lock(influenceLock);
	for(int i = activeTreaties.length - 1; i >= 0; --i) {
		auto@ treaty = activeTreaties[i];
		if(treaty.id == id) {
			Treaty output;
			output = treaty;
			return output;
		}
	}
	return null;
}
// }}}
// {{{ Rewards
void giveRandomReward(Empire& emp, double magnitude = 1.0) {
	switch(randomi(0,3)) {
		case 0: emp.addBonusBudget(int(magnitude * 100.0)); break;
		case 1: emp.addInfluence(magnitude * 0.5 * emp.InfluenceEfficiency); break;
		case 2: emp.generatePoints(magnitude * 8.0); break;
		case 3: emp.modEnergyStored(magnitude * 50.0 * emp.EnergyEfficiency); break;
	}
}
// }}}

void init() {
	if(isLoadedSave)
		return;
	initStack();
}

void tick(double time) {
	tickStack(time);
	tickVotes(time);
	tickEffects(time);
	tickTreaties(time);

	leaderCardTimer += time;
	if(leaderCardTimer >= config::SENATE_LEADER_CARD_TIMER) {
		leaderCardTimer = 0.0;

		auto@ leader = SenateLeader;
		if(leader !is null) {
			const InfluenceCardType@ giveCard;
			double checked = 0.0;
			for(uint i = 0, cnt = getInfluenceCardTypeCount(); i < cnt; ++i) {
				auto@ type = getInfluenceCardType(i);
				if(!type.leaderOnly)
					continue;
				if(type.frequency == 0)
					continue;
				if(leader.getUsesOfCardType(type.id) != 0)
					continue;

				checked += 1.0;
				if(randomd() < 1.0 / checked)
					@giveCard = type;
			}

			if(giveCard !is null) {
				InfluenceCard@ card = giveCard.create(uses=1);
				cast<InfluenceStore>(leader.InfluenceManager).addCard(leader, card);
				leader.notifyGeneric(
						locale::NOTIFY_LEADER_CARD,
						format(locale::NOTIFY_LEADER_CARD_DESC, card.formatTitle()),
						getSpriteDesc(card.type.icon));
			}
		}
	}
}

void save(SaveFile& file) {
	file << galacticInfluence;
	file << SenateLeader;
	file << leaderCardTimer;
	saveStack(file);
	saveVotes(file);
	saveEffects(file);
	saveTreaties(file);
}

void load(SaveFile& file) {
	file >> galacticInfluence;
	file >> SenateLeader;
	if(file >= SV_0141)
		file >> leaderCardTimer;
	loadStack(file);
	loadVotes(file);
	loadEffects(file);
	loadTreaties(file);
}

void syncInitial(Message& msg) {
	msg << galacticInfluence;
	msg << SenateLeader;
	writeStack(msg, true);
	writeVotes(msg, true);
	writeEffects(msg, true);
	writeTreaties(msg, true);
}

bool sendPeriodic(Message& msg) {
	msg << galacticInfluence;
	msg << SenateLeader;
	writeStack(msg);
	writeVotes(msg);
	writeEffects(msg);
	writeTreaties(msg);
	return true;
}
