import influence;
import hooks;
import util.formatting;
import icons;
import notifications;
from influence import ICardNotification, InfluenceStore;
from planet_effects import GenericEffect;
from bonus_effects import BonusEffect;
import hook_globals;
import target_filters;
import systems;

#section server
from influence_global import startInfluenceVote, createInfluenceEffect, dismissEffect, getInfluenceEffectOwner, getInfluenceEffect, rotateInfluenceStack, fillInfluenceStackWithLeverage, playInfluenceCard_server;
from notifications import NotificationStore;
from game_start import galaxies;
#section shadow
from influence_global import getInfluenceEffectOwner;
#section all

//BonusMoney(<Amount>, <Per Quality>)
// Activating this card gives you <Amount> bonus money.
// The amount is increased by <Per Quality> for every addition quality the card has.
class BonusMoney : InfluenceCardEffect {
	Document doc("Gives special funds to the empire.");
	Argument amt("Amount", AT_Integer, doc="Base funds to award.");
	Argument qual("Per Quality", AT_Integer, "0", doc="Additional funds to award per card quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Money;
		name = locale::CARD_MONEY_GAIN;
		tooltip = locale::CARD_MONEY_GAIN;
		text = formatMoney(arguments[0].integer + card.extraQuality * arguments[1].integer);
		highlight = arguments[1].integer > 0 && card.extraQuality > 0;
		return IVM_Property;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		card.owner.addBonusBudget(arguments[0].integer + card.extraQuality * arguments[1].integer);
	}
#section all
};

//StartVote(<Vote>, <Target>)
// Start a new vote with the specified target at its target.
class StartVote : InfluenceCardEffect {
	Document doc("Starts a specified vote against the card's target.");
	Argument vote("Vote", AT_InfluenceVote, doc="Type of vote to start.");
	Argument targ("Target", TT_Any, EMPTY_DEFAULT);
	const InfluenceVoteType@ voteType;

	void init(InfluenceCardType@ type) override {
		@voteType = getInfluenceVoteType(arguments[0].str);
		if(voteType is null)
			error("Error: StartVote() could not find vote "+arguments[0].str);
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Targets voteTargs = voteType.targets;
		if(arguments[1].integer != -1 && voteTargs.length != 0)
			voteTargs[0] = arguments[1].fromTarget(targets);

		startInfluenceVote(card.owner, voteType, voteTargs, card);
	}
#section all
};

//CreateEffect(<Effect>, <Target>, <Duration> = 0, <Quality Duration> = 0)
// Create a new influence effect.
// If duration is set to 0, the default from the effect is used.
// Quality duration increases the duration for every quality the card has.
class CreateEffect : InfluenceCardEffect {
	Document doc("Creates an influence effect.");
	Argument vote("Effect", AT_InfluenceEffect, doc="Type of effect to start.");
	Argument targ("Target", TT_Any, EMPTY_DEFAULT);
	Argument dur("Duration", AT_Decimal, "0", doc="Duration in seconds.");
	Argument qual("Quality Duration", AT_Decimal, "0", doc="Additional duration in seconds per quality.");
	const InfluenceEffectType@ effectType;

	void init(InfluenceCardType@ type) override {
		@effectType = getInfluenceEffectType(arguments[0].str);
		if(effectType is null)
			error("Error: CreateEffect() could not find effect "+arguments[0].str);
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		if(effectType.reservation == 0)
			return IVM_None;
		sprt = icons::InfluenceUpkeep;
		name = locale::INFLUENCE_UPKEEP;
		text = toString(effectType.reservation * 100.0, 0)+"%";
		tooltip = format(locale::INFLUENCE_TT_UPKEEP, text);
		highlight = false;
		return IVM_Property;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Targets effTargs = effectType.targets;
		if(arguments[1].integer != -1 && effTargs.length != 0)
			effTargs[0] = arguments[1].fromTarget(targets);

		double duration = arguments[2].decimal;
		if(arguments[3].decimal != 0) {
			if(duration == 0)
				duration = effectType.defaultDuration;
			duration += double(card.extraQuality) * arguments[3].decimal;
		}
		createInfluenceEffect(card.owner, effectType, effTargs, duration);
	}
#section all
};

//ShowUpkeep(<Upkeep>)
// Show an upkeep variable on the card.
class ShowUpkeep : InfluenceCardEffect {
	Document doc("Shows an upkeep cost for this card.");
	Argument upkeep("Upkeep", AT_Decimal, doc="Base amount of upkeep.");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional upkeep per quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int quality = card.extraQuality;
		double value = arguments[0].decimal + double(quality) * arguments[1].decimal;
		sprt = icons::InfluenceUpkeep;
		name = locale::INFLUENCE_UPKEEP;
		text = toString(value * 100.0, 0)+"%";
		tooltip = format(locale::INFLUENCE_TT_UPKEEP, text);
		highlight = arguments[1].decimal != 0 && quality != 0;
		return IVM_Property;
	}
};

//TargetFindRegion(<Target>)
// Replace the target in <Target> by the region the target is in.
class TargetFindRegion : InfluenceCardEffect {
	Document doc("Redirects a target to the region the target is in.");
	Argument targ(TT_Object);

	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Target@ targ = arguments[0].fromTarget(targets);
		if(targ is null || targ.obj is null)
			return;
		if(targ.obj.isRegion)
			return;
		@targ.obj = targ.obj.region;
	}
};

//ShowDuration(<Duration>, <Per Quality> = 0)
// Show a duration variable on the card.
class ShowDuration : InfluenceCardEffect {
	Document doc("Shows a duration for this card.");
	Argument dur("Duration", AT_Decimal, doc="Base duration in seconds.");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional duration per quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int quality = card.extraQuality;
		double time = arguments[0].decimal + double(quality) * arguments[1].decimal;

		sprt = icons::Duration;
		name = locale::INFLUENCE_DURATION;
		text = formatTime(time);
		tooltip = format(locale::INFLUENCE_TT_DURATION, text);
		highlight = arguments[1].decimal != 0 && quality != 0;
		return IVM_Property;
	}
};

//ShowPopulation(<Population>, <Per Quality> = 0)
// Show a population value on the card.
class ShowPopulation : InfluenceCardEffect {
	Document doc("Shows a population for this card.");
	Argument pop("Amount", AT_Decimal, doc="Base population.");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional population per quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Population;
		name = locale::INFLUENCE_POPULATION;
		text = standardize(arguments[0].decimal + arguments[1].decimal * double(card.extraQuality), true);
		tooltip = "";
		highlight = arguments[1].decimal != 0 && card.extraQuality != 0;
		return IVM_Property;
	}
};

//ShowLabor(<Labor>, <Per Quality> = 0)
// Show a labor value on the card.
class ShowLabor : InfluenceCardEffect {
	Document doc("Shows labor for this card.");
	Argument labor("Amount", AT_Decimal, doc="Base labor.");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional labor per quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Labor;
		name = locale::RESOURCE_LABOR;
		text = standardize(arguments[0].decimal + arguments[1].decimal * double(card.extraQuality), true);
		tooltip = "";
		highlight = arguments[1].decimal != 0 && card.extraQuality != 0;
		return IVM_Property;
	}
};

//ShowEffectiveness(<Labor>, <Per Quality> = 0)
// Show an effectiveness value on the card.
class ShowEffectiveness : InfluenceCardEffect {
	Document doc("Shows effectiveness for this card.");
	Argument effective("Amount", AT_Decimal, doc="Base effectiveness.");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional effectiveness per quality.");

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Effectiveness;
		name = locale::EFFECTIVENESS;
		text = toString((arguments[0].decimal + arguments[1].decimal * double(card.extraQuality)) * 100.0, 0)+"%";
		tooltip = "";
		highlight = arguments[1].decimal != 0 && card.extraQuality != 0;
		return IVM_Property;
	}
};

//ApplyRegionTargetCostMod(<Target>)
// Apply any influence cost modifiers from targets in this region.
class ApplyRegionTargetCostMod : InfluenceCardEffect {
	Document doc("Applies cost modifiers from the target region.");
	Argument targ(TT_Object);

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(targets is null)
			return 0;
		Object@ obj = arguments[0].fromConstTarget(targets).obj;
		if(obj is null)
			return 0;
		if(!obj.isRegion)
			@obj = obj.region;
		if(obj !is null && obj.isRegion)
			return cast<Region>(obj).TargetCostMod;
		return 0;
	}
};

//LoyaltyPlayCost(<Target>, <Factor> = 1.0)
// Increase the play cost of the card by <Factor> for every loyalty
// that <Target> has.
class LoyaltyPlayCost : InfluenceCardEffect {
	Document doc("Increases the cost to play this card for each loyalty the target has.");
	Argument targ(TT_Object);
	Argument effective("Amount", AT_Decimal, "1.0", doc="Increase per loyalty.");

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(targets is null)
			return INDETERMINATE;
		Object@ obj = arguments[0].fromConstTarget(targets).obj;
		if(obj is null)
			return INDETERMINATE;
		if(obj.isStar)
			@obj = obj.region;
		if(obj.isRegion) {
			int loyalty = 0;
			for(uint i = 0, cnt = obj.planetCount; i < cnt; ++i) {
				Planet@ pl = obj.planets[i];
				if(pl !is null && pl.owner !is null && pl.owner.valid && pl.owner !is card.owner) {
					loyalty += pl.getLoyaltyFacing(card.owner);
				}
			}
			return round(double(loyalty) * arguments[1].decimal);
		}
		else {
			if(!obj.hasSurfaceComponent)
				return 0;
			return round(double(obj.getLoyaltyFacing(card.owner)) * arguments[1].decimal);
		}
	}
};

//RegionLoyaltyPlayCost(<Target>, <Factor> = 1.0)
// Increase the play cost of the card by <Factor> for every loyalty
// that enemies have in the <Target> system.
class RegionLoyaltyPlayCost : InfluenceCardEffect {
	Document doc("Increases the cost to play this card for each loyalty the target system's planets have.");
	Argument targ(TT_Object);
	Argument effective("Amount", AT_Decimal, "1.0", doc="Increase per loyalty.");

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(targets is null)
			return INDETERMINATE;
		Object@ obj = arguments[0].fromConstTarget(targets).obj;
		if(obj is null)
			return INDETERMINATE;
		if(!obj.isRegion)
			@obj = obj.region;
		if(obj.isRegion) {
			int loyalty = 0;
			for(uint i = 0, cnt = obj.planetCount; i < cnt; ++i) {
				Planet@ pl = obj.planets[i];
				if(pl !is null && pl.owner !is null && pl.owner.valid && pl.owner !is card.owner) {
					loyalty += pl.getLoyaltyFacing(card.owner);
				}
			}
			return round(double(loyalty) * arguments[1].decimal);
		}
		else {
			return 0;
		}
	}
};

//LogVoteEvent(<Support>, <Oppose>)
// Log a vote event with messages when this card is played into a vote.
class LogVoteEvent : InfluenceCardEffect {
	Document doc("Logs a vote event when the card is played.");
	//TODO: Really? 7 arguments?
	
	LogVoteEvent() {
		argument("Support", AT_Locale, "");
		argument("Oppose", AT_Locale, "");
		argument("Neutral", AT_Locale, "");
		argument("Argument", AT_Decimal, "0");
		argument("ArgumentQuality", AT_Decimal, "0");
		argument("MoneyArgument", AT_Decimal, "0");
		argument("MoneyArgumentQuality", AT_Decimal, "0");
	}

	bool formatEvent(const InfluenceCard@ card, const InfluenceVoteEvent@ evt, string& text) const {
		array<string> args;
		args.insertLast(formatEmpireName(card.owner, contactCheck=playerEmpire));
		args.insertLast(evt.weight > 0 ? toString(evt.weight) : toString(-evt.weight));
		evt.cardEvent.targets.formatInto(args);
		args.insertLast(standardize(arguments[3].decimal + arguments[4].decimal * card.extraQuality, true));
		args.insertLast(formatMoney(arguments[5].decimal + floor(arguments[6].decimal * card.extraQuality)));

		auto side = evt.playedSide;
		switch(side) {
			case ICS_Support:
				text += format(arguments[0].str, args);
			break;
			case ICS_Oppose:
				text += format(arguments[1].str, args);
			break;
			case ICS_Neutral:
				text += format(arguments[2].str, args);
			break;
		}
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const {
		vote.addCardEvent(card, targets, weight);
	}
#section all
};

//AnonymousVoteEvent(<Support>, <Oppose>)
// Log a vote event with messages when this card is played into a vote.
class AnonymousVoteEvent : InfluenceCardEffect {
	Document doc("Logs an anonymous vote event when the card is played.");
	//TODO: You're funny.
	
	AnonymousVoteEvent() {
		argument("Support", AT_Locale, "");
		argument("Oppose", AT_Locale, "");
		argument("Neutral", AT_Locale, "");
		argument("Argument", AT_Decimal, "0");
		argument("ArgumentQuality", AT_Decimal, "0");
		argument("MoneyArgument", AT_Decimal, "0");
		argument("MoneyArgumentQuality", AT_Decimal, "0");
	}

	bool formatEvent(const InfluenceCard@ card, const InfluenceVoteEvent@ evt, string& text) const {
		array<string> args;
		args.insertLast("---");
		args.insertLast(evt.weight > 0 ? toString(evt.weight) : toString(-evt.weight));
		evt.cardEvent.targets.formatInto(args);
		args.insertLast(standardize(arguments[3].decimal + arguments[4].decimal * card.extraQuality, true));
		args.insertLast(formatMoney(arguments[5].decimal + floor(arguments[6].decimal * card.extraQuality)));

		auto side = evt.playedSide;
		switch(side) {
			case ICS_Support:
				text += format(arguments[0].str, args);
			break;
			case ICS_Oppose:
				text += format(arguments[1].str, args);
			break;
			case ICS_Neutral:
				text += format(arguments[2].str, args);
			break;
		}
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const {
		auto@ evt = vote.addCardEvent(card, targets, weight);
		@evt.emp = defaultEmpire;
		@evt.cardEvent.card.owner = defaultEmpire;
	}
#section all
};

class AnonymizeVoteSupport : InfluenceCardEffect {
	Document doc("The weight this card adds is anonymous and cannot be traced back to an empire.");

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const {
		vote.empireVotes[card.owner.index] -= weight;
	}
#section all
};

//GenerateRandomEmpire(<Target>, <Generic Chance> = 0)
// Fill <Target> with a random empire when generating a random card.
// If <Generic Chance> is specified, that percentage of
//  generated cards will have no pre-specified empire.
class GenerateRandomEmpire : InfluenceCardEffect {
	Document doc("Chooses a random empire to force this card to target.");
	Argument targ(TT_Empire);
	Argument chance("Generic Chance", AT_Decimal, "0", doc="Chance for this card to appear without a fixed target.");

#section server
	void generate(InfluenceCard@ card) const {
		auto@ targ = arguments[0].fromTarget(card.targets);
		if(targ !is null) {
			double genChance = arguments[1].decimal;
			if(genChance == 0 || randomd() > genChance) {
				targ.filled = true;
				while(targ.emp is null || !targ.emp.major)
					@targ.emp = getEmpire(randomi(0, getEmpireCount()-1));
			}
			else {
				targ.filled = false;
			}
		}
	}
#section all
};

//DisappearSelfBuy(<Target>)
// If <Target> refers to the empire that bought the card,
// the card disappears from the game instead of entering the player's hand.
class DisappearSelfBuy : InfluenceCardEffect {
	Document doc("This card will vanish if owned by the same empire as the target.");
	Argument targ(TT_Empire);

#section server
	void onGain(InfluenceCard@ card, int uses, bool wasBuy) const override {
		if(wasBuy) {
			auto@ targ = arguments[0].fromTarget(card.targets);
			if(targ.filled && targ.emp is card.owner)
				card.uses -= uses;
		}
	}
#section all
}

//TakeCardUse(<Card>, <Uses> = 1)
// Remove a number of uses from a target card.
class TakeCardUse : InfluenceCardEffect {
	Document doc("Removes uses from a target card.");
	Argument targ(TT_Card);
	Argument uses("Uses", AT_Integer, "1", doc="Number of uses to remove.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ targ = arguments[0].fromTarget(targets);
		if(targ !is null)
			card.owner.takeCardUse(targ.id, arguments[1].integer);
	}
#section all
};

//GainCardCopy(<Card>, <Uses> = 1, <Maximum Quality> = False, <Add Quality> = 0)
// Gain a new copy of the card, increasing quality if necessary.
class GainCardCopy : InfluenceCardEffect {
	Document doc("Copies a target card.");
	Argument targ(TT_Card);
	Argument uses("Uses", AT_Integer, "1", doc="Number of uses to give to the copied card. Use 0 to copy the number of uses.");
	Argument maxQual("Maximum Quality", AT_Boolean, "False", doc="Whether to give the copy the highest possibly quality.");
	Argument qual("Add Quality", AT_Integer, "0", doc="How much quality to add to the copied card.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ cardTarg = arguments[0].fromTarget(targets);
		if(cardTarg is null)
			return;

		card.owner.copyCardTo(cardTarg.id, card.owner, arguments[1].integer, arguments[2].boolean, arguments[3].integer);
	}
#section all
};

//CopyCardTo(<Card>, <Empire>, <Uses> = 0)
// Give a copy of the card to the other empire.
// If <Uses> is not specified, the amount of uses on the card is used.
class CopyCardTo : InfluenceCardEffect {
	Document doc("Copies a target card to another empire.");
	Argument targCard("Card", TT_Card);
	Argument targEmp("Empire", TT_Empire);
	Argument uses("Uses", AT_Integer, "0", doc="Number of uses to give to the copied card. Use 0 to copy the number of uses.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ cardTarg = arguments[0].fromTarget(targets);
		if(cardTarg is null)
			return;

		auto@ empTarg = arguments[1].fromTarget(targets);
		if(empTarg is null)
			return;

		card.owner.copyCardTo(cardTarg.id, empTarg.emp, arguments[2].integer);
	}
#section all
};

//NotifyAll(<Text>)
// Send a notification to all empires.
class NotifyAll : InfluenceCardEffect {
	Document doc("Sends a notification message to all other empires.");
	Argument msg("Text", AT_Locale, doc="Message to send.");
	Argument contact("Contact Only", AT_Boolean, "True", doc="Whether to limit the notification to contacted empires.");

	bool formatNotification(const InfluenceCard@ card, const InfluenceCardPlayEvent@ event, const ICardNotification@ n, string& text) const override {
		array<string> args;
		args.insertLast(formatEmpireName(card.owner));
		args.insertLast(card.formatTitle());
		event.targets.formatInto(args);

		text = format(arguments[0].str, args);
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is card.owner)
				continue;
			if(arguments[1].boolean && card.owner.ContactMask & emp.mask == 0)
				continue;

			CardNotification n;
			n.event.card = card;
			n.event.targets = targets;

			cast<NotificationStore>(emp.Notifications).addNotification(emp, n);
		}
	}
#section all
};

//Notify(<Empire>, <Text>)
// Send a notification to a particular empire.
class Notify : InfluenceCardEffect {
	Document doc("Sends a notification message to a target empire.");
	Argument targEmp("Empire", TT_Empire);
	Argument msg("Text", AT_Locale, doc="Message to send.");

	bool formatNotification(const InfluenceCard@ card, const InfluenceCardPlayEvent@ event, const ICardNotification@ n, string& text) const override {
		array<string> args;
		args.insertLast(formatEmpireName(card.owner));
		args.insertLast(card.formatTitle());
		event.targets.formatInto(args);

		text = format(arguments[1].str, args);
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		onPlay(card, null, targets, 0);
	}

	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const {
		auto@ targ = arguments[0].fromTarget(targets);
		if(targ is null || targ.emp is null)
			return;

		CardNotification n;
		n.event.card = card;
		n.event.targets = targets;

		if(vote !is null)
			n.voteId = vote.id;

		cast<NotificationStore>(targ.emp.Notifications).addNotification(targ.emp, n);
	}
#section all
};

//NotifyCardSubject(<Card>, <Empire>, <Text>)
// Send a notification to a particular empire, storing <Card> as a subject.
class NotifyCardSubject : InfluenceCardEffect {
	Document doc("Sends a notification message to a target empire, with reference to a particular card.");
	Argument targCard("Card", TT_Card);
	Argument targEmp("Empire", TT_Empire);
	Argument msg("Text", AT_Locale, doc="Message to send.");

	bool formatNotification(const InfluenceCard@ card, const InfluenceCardPlayEvent@ event, const ICardNotification@ notification, string& text) const override {
		array<string> args;
		args.insertLast(formatEmpireName(card.owner));
		args.insertLast(card.formatTitle());
		event.targets.formatInto(args);

		auto@ n = cast<const CardNotification>(notification);
		args.insertLast(n.subjectCard.formatTitle());

		text = format(arguments[2].str, args);
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ targ = arguments[1].fromTarget(targets);
		if(targ is null || targ.emp is null)
			return;
		auto@ cardTarg = arguments[0].fromTarget(targets);
		if(cardTarg is null)
			return;

		CardNotification n;
		n.event.card = card;
		n.event.targets = targets;

		InfluenceCard subj;
		receive(card.owner.getInfluenceCard(cardTarg.id), subj);
		@n.subjectCard = subj;

		cast<NotificationStore>(targ.emp.Notifications).addNotification(targ.emp, n);
	}
#section all
};

//NotifyAllEffectSubject(<Effect>, <Empire>, <Text>)
// Send a notification to all other empires, storing <Effect> as a subject.
class NotifyAllEffectSubject : InfluenceCardEffect {
	Document doc("Sends a notification message to all other empires, with reference to a particular effect.");
	Argument targ("Effect", TT_Effect);
	Argument msg("Text", AT_Locale, doc="Message to send.");
	Argument contact("Contact Only", AT_Boolean, "True", doc="Whether to limit the notification to contacted empires.");

	bool formatNotification(const InfluenceCard@ card, const InfluenceCardPlayEvent@ event, const ICardNotification@ notification, string& text) const override {
		auto@ n = cast<const CardNotification>(notification);

		array<string> args;
		args.insertLast(formatEmpireName(card.owner));
		args.insertLast(formatEmpireName(n.subjectEffect.owner));
		args.insertLast(card.formatTitle());
		event.targets.formatInto(args);
		args.insertLast(n.subjectEffect.formatTitle());

		text = format(arguments[1].str, args);
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ effTarg = arguments[0].fromTarget(targets);
		if(effTarg is null)
			return;

		InfluenceEffect subj = getInfluenceEffect(effTarg.id);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is card.owner)
				continue;
			if(arguments[2].boolean && card.owner.ContactMask & emp.mask == 0)
				continue;

			CardNotification n;
			n.event.card = card;
			n.event.targets = targets;

			InfluenceEffect cpy = subj;
			@n.subjectEffect = cpy;

			cast<NotificationStore>(emp.Notifications).addNotification(emp, n);
		}
	}
#section all
};

//LimitVoteToOppose(<Empire>)
// This card can only be used to oppose <Empire> in a vote.
class LimitVoteToOppose : InfluenceCardEffect {
	Document doc("Restricts the card to being used to oppose a vote.");
	Argument targ("Empire", TT_Empire);
	uint sideTarget = uint(-1);

	bool initTargets(Targets@ targets) override {
		sideTarget = uint(targets.getIndex("VoteSide"));
		return InfluenceCardEffect::initTargets(targets);
	}

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(targets is null || vote is null)
			return true;
		if(sideTarget >= targets.targets.length)
			return false;

		auto@ empTarget = arguments[0].fromConstTarget(targets);
		if(empTarget is null || empTarget.emp is null || !empTarget.emp.valid)
			return false;

		bool side = targets[sideTarget].side;
		int theirVote = vote.empireVotes[empTarget.emp.index];

		//Can't vote if they haven't voted
		if(theirVote == 0)
			return false;

		if(side) {
			//Can't vote positive if they're positive
			if(theirVote > 0)
				return false;
		}
		else {
			//Can't vote negative if they're negative
			if(theirVote < 0)
				return false;
		}

		return true;
	}
};

//GainRandomLeverage(<On Empire>, <Quality Factor> = 1.0)
// Gain random leverage on the specified empire.
// Quality factor decides the chance for how much and how powerful the leverage is.
class GainRandomLeverage : InfluenceCardEffect {
	Document doc("Generate leverage against a target empire.");
	Argument targ("On Empire", TT_Empire);
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic value to determine how valuable the leverage is.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ empTarg = arguments[0].fromTarget(targets);
		if(empTarg is null || empTarg.emp is null)
			return;

		card.owner.gainRandomLeverage(empTarg.emp, arguments[1].decimal);
	}
#section all
};

//GiveLeverageToOwner(<Effect>, <Quality Factor> = 1.0)
// Give the owner of <Effect> leverage on the card's empire.
class GiveLeverageToOwner : InfluenceCardEffect {
	Document doc("Generate leverage against the owner of the targeted effect.");
	Argument targ("Effect", TT_Effect);
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic value to determine how valuable the leverage is.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Empire@ emp = getInfluenceEffectOwner(arguments[0].fromTarget(targets).id);
		if(emp !is null)
			emp.gainRandomLeverage(card.owner, arguments[1].decimal);
	}
#section all
};

//GainCardCostLeverage(<Card>, <On Empire>, <Factor> = 1)
// Gain levearge on the empire relative to the cost of <Card>.
class GainCardCostLeverage : InfluenceCardEffect {
	Document doc("Generate leverage against target empire based on the value of a card.");
	Argument targCard("Card", TT_Card);
	Argument targEmp("On Empire", TT_Empire);
	Argument qual("Factor", AT_Decimal, "1.0", doc="Magic value to determine how valuable the leverage is.");

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ empTarg = arguments[1].fromTarget(targets);
		if(empTarg is null || empTarg.emp is null)
			return;

		auto@ cardTarg = arguments[0].fromTarget(targets);
		if(cardTarg is null)
			return;

		InfluenceCard checkCard;
		if(!receive(card.owner.getInfluenceCard(cardTarg.id), checkCard))
			return;

		int cost = checkCard.getPurchaseCost(null, uses=1);
		double quality = max(double(cost) * arguments[2].decimal, 0.5);
		card.owner.gainRandomLeverage(empTarg.emp, quality);
	}
#section all
};

//DismissEffect(<Effect>)
// Forcably dismiss a targeted effect.
class DismissEffect : InfluenceCardEffect {
	Document doc("Ends a target effect.");
	Argument targ("Effect", TT_Effect);

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ effTarg = arguments[0].fromTarget(targets);
		if(effTarg is null)
			return;

		dismissEffect(card.owner, effTarg.id);
	}
#section all
};

//DisableOnOwnedVotes()
// This card cannot be played on votes you started.
class DisableOnOwnedVotes : InfluenceCardEffect {
	Document doc("Prevents activating a card on votes started by this empire.");
	
	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const override {
		return card.owner !is vote.startedBy;
	}
};

//GainLeverageOnVoteStarter()
// 
class GainLeverageOnVoteStarter : InfluenceCardEffect {
	Document doc("Generates leverage against the started of a vote when the vote passes or fails.");
	Argument passfail("Event", AT_PassFail, doc="Which event - Pass or Fail - that causes leverage to be granted.");
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic value to determine how valuable the leverage is.");

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEnd(InfluenceCard@ card, InfluenceVote@ vote, bool passed, bool withdrawn) const override {
		if(passed != arguments[0].boolean || withdrawn)
			return;

		card.owner.gainRandomLeverage(vote.startedBy, max(arguments[1].decimal, 0.5));
	}
#section all
};

//LimitPerVote(<Amount>, <Per Empire> = True, <Per Side> = False)
// Limit this card from being planet <Amount> times per vote.
class LimitPerVote : InfluenceCardEffect {
	Document doc("Limits the card from being played a set amount of times.");
	Argument amt("Amount", AT_Integer);
	Argument perEmp("Per Empire", AT_Boolean, "True", doc="Whether the limit applies separately for each empire.");
	Argument perSide("Per Side", AT_Boolean, "False", doc="Whether the limit applies separately for each side in a vote.");
	Argument match("Match Targets", AT_Boolean, "False", doc="Whether the limit applies only against a particular target.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return false;
		InfluenceCardSide matchSide = ICS_Both;
		Empire@ matchEmp;
		const Targets@ matchTargets;
		if(arguments[1].boolean)
			@matchEmp = card.owner;
		if(arguments[2].boolean && card.type.sideMode == ICS_Both)
			matchSide = targets[card.type.sideTarget].side ? ICS_Support : ICS_Oppose;
		if(arguments[3].boolean) {
			if(targets is null)
				@matchTargets = card.targets;
			else
				@matchTargets = targets;
		}
		uint count = vote.countPlayed(card.type, matchEmp, matchSide, matchTargets);
		if(count >= uint(arguments[0].integer))
			return false;
		return true;
	}
};

class RequireValidVoteStarter : InfluenceCardEffect {
	Document doc("Can only be played if the vote starter is a valid empire. That is, this is not a zeitgeist or other event.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return false;
		if(vote.startedBy is null || !vote.startedBy.valid || !vote.startedBy.major)
			return false;
		return true;
	}
};

//PurchaseMoneyCost(<Amount>, <Per Quality> = 0, <Per Use> = 0, <Per Placement> = 0)
// Add a cost to purchasing this card.
class PurchaseMoneyCost : InfluenceCardEffect {
	Document doc("Adds a money purchase cost to this card.");
	Argument amt("Amount", AT_Integer, doc="Base amount to cost");
	Argument qual("Per Quality", AT_Integer, "0", doc="Additional cost per quality.");
	Argument use("Per Use", AT_Integer, "0", doc="Additional cost per available use.");
	Argument place("Per Placement", AT_Integer, "0", doc="Additional cost based on far it is from falling off the stack.");

	int getCost(int extraQuality, int extraUses, int placement) {
		int cost = arguments[0].integer;
		cost += arguments[1].integer * extraQuality;
		if(extraUses > 0)
			cost += arguments[2].integer * extraUses;
		cost += arguments[3].integer * placement;
		return cost;
	}

	bool hasPurchaseCost(const InfluenceCard@ card, Empire@ byEmpire, int placement) const override {
		int cost = getCost(card.extraQuality, card.uses - 1, placement);
		return byEmpire.canPay(cost);
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		auto@ stackCard = cast<const StackInfluenceCard>(card);
		if(stackCard is null)
			return IVM_None;
		
		sprt = icons::Money;
		name = locale::CARD_PURCHASE_MONEY;
		tooltip = locale::CARD_PURCHASE_MONEY;
		text = formatMoney(getCost(card.extraQuality, card.uses - 1, stackCard.placement));
		highlight = false;
		return IVM_PurchaseCost;
	}

#section server
	bool purchaseConsume(InfluenceCard@ card, Empire@ byEmpire, int placement) const override {
		int cost = getCost(card.extraQuality, card.uses - 1, placement);
		if(byEmpire.consumeBudget(cost) == -1)
			return false;
		return true;
	}

	void purchaseConsumeRewind(InfluenceCard@ card, Empire@ byEmpire, int placement) const override {
		int cost = getCost(card.extraQuality, card.uses - 1, placement);
		byEmpire.refundBudget(cost, byEmpire.BudgetCycleId);
	}
#section all
};

//PlayMoneyCost(<Amount>, <Per Quality> = 0)
// Add a cost to playing this card.
class PlayMoneyCost : InfluenceCardEffect {
	Document doc("Adds a money cost to play this card.");
	Argument amt("Amount", AT_Integer, doc="Base amount to cost");
	Argument qual("Per Quality", AT_Integer, "0", doc="Additional cost per quality.");

	int getCost(int extraQuality) {
		int cost = arguments[0].integer;
		cost += arguments[1].integer * extraQuality;
		return cost;
	}

	bool canPlay(const InfluenceCard@ card, const Targets@ targets) const override {
		int cost = getCost(card.extraQuality);
		return card.owner.canPay(cost);
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Money;
		name = locale::CARD_PLAY_MONEY;
		tooltip = locale::CARD_PLAY_MONEY;
		text = formatMoney(getCost(card.extraQuality));
		highlight = false;
		return IVM_Property;
	}

#section server
	bool playConsume(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		int cost = getCost(card.extraQuality);
		if(card.owner.consumeBudget(cost) == -1)
			return false;
		return true;
	}

	void playConsumeRewind(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		int cost = getCost(card.extraQuality);
		card.owner.refundBudget(cost, card.owner.BudgetCycleId);
	}
#section all
};

//PlayEnergyCost(<Amount>, <Per Quality> = 0)
// Add an energy cost to playing this card.
class PlayEnergyCost : InfluenceCardEffect {
	Document doc("Adds an energy cost to play this card.");
	Argument amt("Amount", AT_Decimal, doc="Base amount to cost");
	Argument qual("Per Quality", AT_Decimal, "0", doc="Additional cost per quality.");

	double getCost(int extraQuality) {
		int cost = arguments[0].decimal;
		cost += arguments[1].decimal * extraQuality;
		return cost;
	}

	bool canPlay(const InfluenceCard@ card, const Targets@ targets) const override {
		double cost = getCost(card.extraQuality);
		return card.owner.EnergyStored >= cost;
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Energy;
		name = locale::CARD_PLAY_ENERGY;
		tooltip = locale::CARD_PLAY_ENERGY;
		text = standardize(getCost(card.extraQuality), true);
		highlight = arguments[1].decimal > 0 && card.extraQuality > 0;
		return IVM_Property;
	}

#section server
	bool playConsume(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		double cost = getCost(card.extraQuality);
		if(card.owner.consumeEnergy(cost, consumePartial=false) >= cost - 0.001)
			return false;
		return true;
	}

	void playConsumeRewind(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		double cost = getCost(card.extraQuality);
		card.owner.modEnergyStored(+cost);
	}
#section all
};

//PlayEnergyCostPerPlay(<Base Cost>, <Per Play>, <Same Side> = True, <Same Empire> = False, <Match Targets> = False, <Per Quality> = 0)
// Adds weight to a card relative to how many times cards of that type
// have been played before.
class PlayEnergyCostPerPlay : InfluenceCardEffect {
	Document doc("Adds an energy cost to play the card based on previous uses of this card type in the vote.");
	//TODO: Arrrg
	
	PlayEnergyCostPerPlay() {
		argument("Base Cost", AT_Decimal);
		argument("Per Play", AT_Decimal);
		argument("Same Side", AT_Boolean, "True");
		argument("Same Empire", AT_Boolean, "False");
		argument("Match Targets", AT_Boolean, "False");
		argument("Per Quality", AT_Decimal, "0");
	}

	double getCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) {
		uint count = 0;
		if(vote !is null) {
			InfluenceCardSide matchSide = ICS_Both;
			Empire@ matchEmp;
			const Targets@ matchTargets;
			if(arguments[2].boolean)
				@matchEmp = card.owner;
			if(arguments[3].boolean && card.type.sideMode == ICS_Both && targets !is null)
				matchSide = targets[card.type.sideTarget].side ? ICS_Support : ICS_Oppose;
			if(arguments[4].boolean) {
				if(targets is null)
					@matchTargets = card.targets;
				else
					@matchTargets = targets;
			}
			count = vote.countPlayed(card.type, matchEmp, matchSide, matchTargets);
		}

		double cost = arguments[0].decimal;
		cost += arguments[1].decimal * double(count);
		cost += arguments[5].decimal * card.extraQuality;
		return cost;
	}

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const override {
		double cost = getCost(card, vote, targets);
		return card.owner.EnergyStored >= cost;
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Energy;
		name = locale::CARD_PLAY_ENERGY;
		tooltip = locale::CARD_PLAY_ENERGY;
		text = standardize(getCost(card, vote, card.targets), true);
		highlight = arguments[1].decimal > 0 && card.extraQuality > 0;
		return IVM_Property;
	}

#section server
	bool playConsume(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		double cost = getCost(card, vote, targets);
		if(card.owner.consumeEnergy(cost, consumePartial=false) < cost - 0.001)
			return false;
		return true;
	}

	void playConsumeRewind(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		double cost = getCost(card, vote, targets);
		card.owner.modEnergyStored(+cost);
	}
#section all
};

//GainRandomCard()
// Gain a fully random card.
//TODO: Make this reject cards that would be deleted immediately (Self-target negative cards)
void gainRandomCard(Empire@ emp) {
	const InfluenceCardType@ type;
	do {
		@type = getDistributedInfluenceCardType();
	}
	while(type.cls == ICC_Instant || type.cls == ICC_Event);

	auto@ newCard = type.generate();
	cast<InfluenceStore>(emp.InfluenceManager).addCard(emp, newCard);
}

class GainRandomCard : InfluenceCardEffect {
	Document doc("Genereates a random card.");
	
#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		gainRandomCard(card.owner);
	}
#section all
};

//CostPerPlay(<Cost>, <Same Side> = True, <Same Empire> = False, <Match Targets> = False)
// Adds cost to playing a card relative to how many times cards of that type
// have been played before.
class CostPerPlay : InfluenceCardEffect {
	Document doc("Adds cost to play this card based on previous uses of the same type of card in this vote.");
	Argument addCost("Cost", AT_Decimal, doc="Cost added per prior use.");
	Argument sameSide("Same Side", AT_Boolean, "True", doc="Only count prior uses on the same side.");
	Argument sameEmp("Same Empire", AT_Boolean, "False", doc="Only count prior uses by the same empire.");
	Argument match("Match Targets", AT_Boolean, "False", doc="Only count prior uses against the same target.");

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return 0;
		InfluenceCardSide matchSide = ICS_Both;
		Empire@ matchEmp;
		const Targets@ matchTargets;
		if(arguments[1].boolean)
			@matchEmp = card.owner;
		if(arguments[2].boolean && card.type.sideMode == ICS_Both && targets !is null)
			matchSide = targets[card.type.sideTarget].side ? ICS_Support : ICS_Oppose;
		if(arguments[3].boolean) {
			if(targets is null)
				@matchTargets = card.targets;
			else
				@matchTargets = targets;
		}
		uint count = vote.countPlayed(card.type, matchEmp, matchSide, matchTargets);
		return floor(double(count) * arguments[0].decimal);
	}
};

//WeightPerPlay(<Weight>, <Same Side> = True, <Same Empire> = False, <Match Targets> = False)
// Adds weight to a card relative to how many times cards of that type
// have been played before.
class WeightPerPlay : InfluenceCardEffect {
	Document doc("Adds weight to this card based on previous uses of the same type of card in this vote.");
	Argument weight("Weight", AT_Decimal, doc="Weight added per prior use.");
	Argument sameSide("Same Side", AT_Boolean, "True", doc="Only count prior uses on the same side.");
	Argument sameEmp("Same Empire", AT_Boolean, "False", doc="Only count prior uses by the same empire.");
	Argument match("Match Targets", AT_Boolean, "False", doc="Only count prior uses against the same target.");

	int getWeight(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return 0;
		InfluenceCardSide matchSide = ICS_Both;
		Empire@ matchEmp;
		const Targets@ matchTargets;
		if(arguments[1].boolean)
			@matchEmp = card.owner;
		if(arguments[2].boolean && card.type.sideMode == ICS_Both && targets !is null)
			matchSide = targets[card.type.sideTarget].side ? ICS_Support : ICS_Oppose;
		if(arguments[3].boolean) {
			if(targets is null)
				@matchTargets = card.targets;
			else
				@matchTargets = targets;
		}
		uint count = vote.countPlayed(card.type, matchEmp, matchSide, matchTargets);
		return floor(double(count) * arguments[0].decimal);
	}
};

class AddWeightEmpireAttribute : InfluenceCardEffect {
	Document doc("Adds weight to the card from an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to take weight from.");

	int getWeight(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(card.owner is null)
			return 0;
		return floor(card.owner.getAttribute(attribute.integer));
	}
};

//WeightPerEmpirePresent(<Weight>, <Weigh Self> = False)
// Adds weight relative to how many people are in the vote.
class WeightPerEmpirePresent : InfluenceCardEffect {
	WeightPerEmpirePresent() {
		argument("Weight", AT_Decimal);
		argument("Weigh Self", AT_Boolean, "False");
	}

	int getWeight(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		double num = 0.0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(!arguments[1].boolean && other is card.owner)
				continue;
			if(vote !is null && !vote.isPresent(other))
				continue;
			num += arguments[0].decimal;
		}
		return num;
	}
};

//AddWeightToNextSupport(<Side>, <Amount>, <Per Quality> = 0, <Allow Self> = False)
// Add weight to the next support of <Side>.
// If <Allow Self> is true, cards played by the same empire also work.
class AddWeightToNextSupport : InfluenceCardEffect {
	AddWeightToNextSupport() {
		target("Side", TT_Side);
		argument("Amount", AT_Integer);
		argument("Per Quality", AT_Decimal, "0");
		argument("Allow Self", AT_Boolean, "False");
		argument("Limited", AT_Boolean, "True");
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int amt = arguments[1].integer;
		amt += floor(arguments[2].decimal * double(card.extraQuality));

		sprt = icons::InfluenceWeight;
		name = locale::CARD_DESC_WEIGHT;
		tooltip = format(locale::INFLUENCE_TT_WEIGHT_NEXT, toString(amt));
		text = toString(amt);
		highlight = arguments[2].decimal > 0 && card.extraQuality > 0;
		return IVM_Property;
	}

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEffect(InfluenceCard@ card, InfluenceVote@ vote) const override {
		bool triggered = false;
		card.data[hookIndex].store(triggered);
	}

	void onVoteEvent(InfluenceCard@ card, InfluenceVote@ vote, InfluenceVoteEvent@ event) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		if(triggered || !arguments[4].boolean)
			return;
		Target@ targ = arguments[0].fromTarget(card.targets);
		if(targ is null)
			return;
		if(!InfluenceSideEquals(event.playedSide, targ.side))
			return;
		if(!arguments[3].boolean && card.owner is event.emp)
			return;

		int amt = arguments[1].integer;
		amt += floor(arguments[2].decimal * double(card.extraQuality));

		if(targ.side == false)
			amt = -amt;

		vote.vote(event.emp, amt);
		event.weight += amt;

		triggered = true;
		card.data[hookIndex].store(triggered);
	}

	void save(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		file << triggered;
	}

	void load(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		file >> triggered;
		card.data[hookIndex].store(triggered);
	}
#section all
};

//AddWeightToNextSupportBy(<Empire>, <Amount>, <Per Quality> = 0)
// Add weight to the next support card played by <Empire>.
// If <Allow Self> is true, cards played by the same empire also work.
class AddWeightToNextSupportBy : InfluenceCardEffect {
	AddWeightToNextSupportBy() {
		target("Empire", TT_Empire);
		argument("Amount", AT_Integer);
		argument("Per Quality", AT_Decimal, "0");
		argument("Limited", AT_Boolean, "True");
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int amt = arguments[1].integer;
		amt += floor(arguments[2].decimal * double(card.extraQuality));

		sprt = icons::InfluenceWeight;
		name = locale::CARD_DESC_WEIGHT;
		tooltip = format(locale::INFLUENCE_TT_WEIGHT_NEXT, toString(amt));
		text = toString(amt);
		highlight = arguments[2].decimal > 0 && card.extraQuality > 0;
		return IVM_Property;
	}

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEffect(InfluenceCard@ card, InfluenceVote@ vote) const override {
		bool triggered = false;
		card.data[hookIndex].store(triggered);
	}

	void onVoteEvent(InfluenceCard@ card, InfluenceVote@ vote, InfluenceVoteEvent@ event) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		if(triggered || !arguments[3].boolean)
			return;
		Target@ targ = arguments[0].fromTarget(card.targets);
		if(targ is null)
			return;
		if(targ.emp !is event.emp)
			return;
		auto side = event.playedSide;
		if(side == ICS_Neutral)
			return;

		int amt = arguments[1].integer;
		amt += floor(arguments[2].decimal * double(card.extraQuality));

		if(side == ICS_Oppose)
			amt = -amt;

		vote.vote(event.emp, amt);
		event.weight += amt;

		triggered = true;
		card.data[hookIndex].store(triggered);
	}

	void save(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		file << triggered;
	}

	void load(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		file >> triggered;
		card.data[hookIndex].store(triggered);
	}
#section all
};

//GiveMoneyToNextSupport(<Side>, <Amount>, <Per Quality> = 0, <Allow Self> = False)
// Give bonus money to the next player to play a card supporting <Side>.
// If <Allow Self> is true, cards played by the same empire also work.
class GiveMoneyToNextSupport : InfluenceCardEffect {
	GiveMoneyToNextSupport() {
		target("Side", TT_Side);
		argument("Amount", AT_Integer);
		argument("Per Quality", AT_Integer, "0");
		argument("Allow Self", AT_Boolean, "False");
	}

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEffect(InfluenceCard@ card, InfluenceVote@ vote) const override {
		bool triggered = false;
		card.data[hookIndex].store(triggered);
	}

	void onVoteEvent(InfluenceCard@ card, InfluenceVote@ vote, InfluenceVoteEvent@ event) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		if(triggered)
			return;
		Target@ targ = arguments[0].fromTarget(card.targets);
		if(targ is null)
			return;
		if(!InfluenceSideEquals(event.playedSide, targ.side))
			return;
		if(!arguments[3].boolean && card.owner is event.emp)
			return;

		int amt = arguments[1].integer;
		amt += arguments[2].integer * card.extraQuality;

		event.emp.addBonusBudget(amt);

		triggered = true;
		card.data[hookIndex].store(triggered);
	}

	void save(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		card.data[hookIndex].retrieve(triggered);
		file << triggered;
	}

	void load(InfluenceCard@ card, SaveFile& file) const override {
		bool triggered = true;
		file >> triggered;
		card.data[hookIndex].store(triggered);
	}
#section all
};

//RequireRemainingTime(<Amount>)
// This card can only be played if there is at least <Amount> seconds remaining
// on the vote timer.
class RequireRemainingTime : InfluenceCardEffect {
	Document doc("This card can only be played if there is at least the specified amount of seconds remaining in the vote.");
	Argument amount(AT_Decimal, doc="Amount of seconds remaining to require.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return true;
		return vote.minimumRemaining >= arguments[0].decimal;
	}
};

class ExtendRemainingTimeTo : InfluenceCardEffect {
	Document doc("When this card is played, the vote remaining timer is extended to at least this amount. If the timer is still longer than the specified amount of seconds, nothing is changed.");
	Argument amount(AT_Decimal, doc="Amount of seconds remaining to ensure are still available.");

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		vote.extendTo(amount.decimal);
	}
#section all
};

//CalloutEmpire(<Target>, <Leverage Quality> = 1.0)
// If the targeted empire hasn't voted on either side of the proposition
// since this card was played, when the vote ends you gain leverage.
class CalloutEmpire : InfluenceCardEffect {
	CalloutEmpire() {
		target("Target", TT_Empire);
		argument("Leverage Quality", AT_Decimal, "1.0");
	}

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEnd(InfluenceCard@ card, InfluenceVote@ vote, bool passed, bool withdrawn) const override {
		if(withdrawn)
			return;

		Target@ targ = arguments[0].fromTarget(card.targets);
		if(targ is null || targ.emp is null)
			return;

		bool found = false;
		for(int i = vote.events.length - 1; i >= 0; --i ) {
			auto@ evt = vote.events[i];
			//Stop looking when we find ourself
			if(evt.cardEvent !is null && evt.cardEvent.wasEventOf(card, matchTargets = true))
				break;

			//Look for a vote from the targeted empire
			if(evt.emp is targ.emp) {
				if(evt.playedSide != ICS_Neutral) {
					found = true;
					break;
				}
			}
		}

		if(!found)
			card.owner.gainRandomLeverage(targ.emp, arguments[1].decimal);
	}
#section all
};

//NameObject(<Object>, <Name>)
// Name an object something else.
class NameObject : InfluenceCardEffect {
	NameObject() {
		target("Object", TT_Object);
		target("Name", TT_String);
	}

	bool isValidTarget(const InfluenceCard@ card, uint index, const Target@ targ) const override {
		if(index == uint(arguments[0].integer))
			return targ.obj !is null;
		if(index == uint(arguments[1].integer))
			return targ.str.length > 0;
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ objTarg = arguments[0].fromTarget(targets);
		if(objTarg is null || objTarg.obj is null)
			return;

		auto@ nameTarg = arguments[1].fromTarget(targets);
		if(nameTarg is null || nameTarg.str.length == 0)
			return;

		if(objTarg.obj.isRegion) {
			objTarg.obj.renameSystem(nameTarg.str);
		}
		else {
			objTarg.obj.name = nameTarg.str;
			objTarg.obj.named = true;
			objectRenamed(ALL_PLAYERS, objTarg.obj, nameTarg.str);
		}
	}
#section all
};

class Trigger : InfluenceCardEffect {
	BonusEffect@ hook;

	Document doc("Trigger a single-time effect on a targeted object.");
	Argument object_target(TT_Object, doc="Object target to trigger on.");
	Argument function(AT_Hook, "bonus_effects::BonusEffect", doc="Hook to call on the object.");
	Argument per_quality(AT_Integer, "0", doc="If non-zero, this hook is only called once for every additional quality the card has.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[1].str, "bonus_effects::"));
		if(hook is null) {
			error("BonusEffect(): could not find inner hook: "+escape(arguments[1].str));
			return false;
		}
		return InfluenceCardEffect::instantiate();
	}

	bool isValidTarget(const InfluenceCard@ card, uint index, const Target@ targ) const override {
		if(index == uint(arguments[0].integer))
			return targ.obj !is null;
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ objTarg = arguments[0].fromTarget(targets);
		if(objTarg is null || objTarg.obj is null)
			return;

		uint repeats = 1;
		if(arguments[2].integer != 0)
			repeats = (card.extraQuality / arguments[2].integer);
		for(uint i = 0; i < repeats; ++i)
			hook.activate(objTarg.obj, card.owner);
	}
#section all
};

//TriggerVotePresent(<Hook>(...), <Per Quality> = 0, <Trigger Self> = False)
// Trigger a hook on all empires present in the vote.
class TriggerVotePresent : InfluenceCardEffect {
	BonusEffect@ hook;

	TriggerVotePresent() {
		argument("Hook", AT_Hook, "bonus_effects::BonusEffect");
		argument("Per Quality", AT_Integer, "0");
		argument("Trigger Self", AT_Boolean, "False");
	}

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(hook is null) {
			error("TriggerVotePresent(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return InfluenceCardEffect::instantiate();
	}

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(!vote.isPresent(other))
				continue;
			if(!arguments[2].boolean && other is card.owner)
				continue;
			hook.activate(null, other);
		}
	}
#section all
};

//OnOwner(<Hook>(...), <Per Quality> = 0)
class OnOwner : InfluenceCardEffect {
	BonusEffect@ hook;

	OnOwner() {
		argument("Hook", AT_Hook, "bonus_effects::EmpireTrigger");
		argument("Per Quality", AT_Integer, "0");
	}

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(hook is null) {
			error("BonusEffect(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return InfluenceCardEffect::instantiate();
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		uint repeats = 1;
		if(arguments[1].integer != 0)
			repeats = (card.extraQuality / arguments[1].integer);
		for(uint i = 0; i < repeats; ++i)
			hook.activate(null, card.owner);
	}
#section all
};

//OnPlanet(<Planet>, <Hook>(...), <Per Quality> = 0)
// Run <Hook> as a single-time planet effect hook on <Planet>.
//  Because of the single-time nature, effects with ticks or data will not function.
// If <Per Quality> is not 0, the hook is instead executed for every extra <Per Quality> the card has.
class OnPlanet : InfluenceCardEffect {
	GenericEffect@ hook;

	OnPlanet() {
		target("Planet", TT_Object);
		argument("Hook", AT_Hook, "planet_effects::GenericEffect");
		argument("Per Quality", AT_Integer, "0");
	}

	bool instantiate() override {
		@hook = cast<GenericEffect>(parseHook(arguments[1].str, "planet_effects::"));
		if(hook is null) {
			error("GenericEffect(): could not find inner hook: "+escape(arguments[1].str));
			return false;
		}
		return InfluenceCardEffect::instantiate();
	}

	bool isValidTarget(const InfluenceCard@ card, uint index, const Target@ targ) const override {
		if(index == uint(arguments[0].integer))
			return targ.obj !is null && targ.obj.isPlanet;
		return true;
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ objTarg = arguments[0].fromTarget(targets);
		if(objTarg is null || objTarg.obj is null || !objTarg.obj.isPlanet)
			return;

		uint repeats = 1;
		if(arguments[2].integer != 0)
			repeats = (card.extraQuality / arguments[2].integer);
		for(uint i = 0; i < repeats; ++i)
			hook.enable(objTarg.obj, null);
	}
#section all
};

//TargetDefaultPlanetName(<Target>)
// Set the string in <Target> to a randomized planet name by default.
NameGenerator planetNames;
bool planetNamesInitialized = false;
class TargetDefaultPlanetName : InfluenceCardEffect {
	TargetDefaultPlanetName() {
		target("Target", TT_String);

		if(!planetNamesInitialized) {
			planetNamesInitialized = true;
			planetNames.read("data/planet_names.txt");
			planetNames.useGeneration = false;
		}
	}

	void targetDefaults(const InfluenceCard@ card, Targets@ targets) const override {
		Target@ targ = arguments[0].fromTarget(targets);
		if(targ is null)
			return;
		targ.str = planetNames.generate();
		targ.filled = true;
	}
};

string getRandomPlanetName() {
	if(!planetNamesInitialized) {
		planetNamesInitialized = true;
		planetNames.read("data/planet_names.txt");
		planetNames.useGeneration = false;
	}
	return planetNames.generate();
}

//TargetDefaultFlagshipName(<Target>)
// Set the string in <Target> to a randomized flagship name by default.
NameGenerator flagshipNames;
bool flagshipNamesInitialized = false;
class TargetDefaultFlagshipName : InfluenceCardEffect {
	TargetDefaultFlagshipName() {
		target("Target", TT_String);

		if(!flagshipNamesInitialized) {
			flagshipNamesInitialized = true;
			flagshipNames.read("data/flagship_names.txt");
			flagshipNames.useGeneration = false;
		}
	}

	void targetDefaults(const InfluenceCard@ card, Targets@ targets) const override {
		Target@ targ = arguments[0].fromTarget(targets);
		if(targ is null)
			return;
		targ.str = flagshipNames.generate();
		targ.filled = true;
	}
};

string getRandomFlagshipName() {
	if(!flagshipNamesInitialized) {
		flagshipNamesInitialized = true;
		flagshipNames.read("data/flagship_names.txt");
		flagshipNames.useGeneration = false;
	}
	return flagshipNames.generate();
}

//OnSucceedDistributeRandomCardsToSide(<Amount>, <To Self> = False)
// If the vote this card was played in succeeds in the side the card was played in,
// distribute <Amount> random influence cards to empires that voted on that
// side, proportional to their contributions.
class OnSucceedDistributeRandomCardsToSide : InfluenceCardEffect {
	OnSucceedDistributeRandomCardsToSide() {
		argument("Amount", AT_Integer);
		argument("To Self", AT_Boolean, "False");
	}

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEnd(InfluenceCard@ card, InfluenceVote@ vote, bool passed, bool withdrawn) const override {
		auto side = card.getSide(card.targets);
		if(!InfluenceSideEquals(side, passed))
			return;

		//Total all the relevant votes
		double total = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!vote.isPresent(emp))
				continue;
			if(!arguments[1].boolean && emp is card.owner)
				continue;
			total += vote.getVoteFrom(emp, side);
		}

		//Pass out random cards
		for(int n = 0; n < arguments[0].integer; ++n) {
			//Roll empire to pass to
			Empire@ passTo;
			double roll = randomd(0.0, total);
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				if(!vote.isPresent(emp))
					continue;
				if(!arguments[1].boolean && emp is card.owner)
					continue;
				roll -= vote.getVoteFrom(emp, side);
				if(roll <= 0.0) {
					@passTo = emp;
					break;
				}
			}

			if(passTo is null)
				continue;

			//Generate the card
			const InfluenceCardType@ type;
			do {
				@type = getDistributedInfluenceCardType();
			}
			while(type.cls == ICC_Instant || type.cls == ICC_Event);

			auto@ newCard = type.generate();
			cast<InfluenceStore>(passTo.InfluenceManager).addCard(passTo, newCard);
		}
	}
#section all
};

//ModGlobal(<Global>, <Amount>)
// Modify a global value.
class ModGlobal : InfluenceCardEffect {
	ModGlobal() {
		argument("Global", AT_Global);
		argument("Amount", AT_Decimal);
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		auto@ glob = getGlobal(arguments[0].integer);
		glob.add(arguments[1].decimal);
	}
#section all
};

//PlayCostFromGlobal(<Global>, <Factor> = 1)
// Increase play cost of card based on global value.
class PlayCostFromGlobal : InfluenceCardEffect {
	PlayCostFromGlobal() {
		argument("Global", AT_Global);
		argument("Factor", AT_Decimal, "1.0");
	}

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		auto@ glob = getGlobal(arguments[0].integer);
		return int(glob.value * arguments[1].decimal);
	}
};

//PlayMoneyCostFromGlobal(<Global>, <Factor> = 1.0, <Base> = 0, <Per Quality> = 0)
// Add a cost to playing this card.
class PlayMoneyCostFromGlobal : InfluenceCardEffect {
	PlayMoneyCostFromGlobal() {
		argument("Global", AT_Global);
		argument("Factor", AT_Decimal, "1.0");
		argument("Base", AT_Integer, "0");
		argument("Per Quality", AT_Integer, "0");
	}

	int getCost(int extraQuality) {
		int cost = arguments[2].integer;
		cost += arguments[3].integer * extraQuality;
		auto@ glob = getGlobal(arguments[0].integer);
		cost += int(glob.value * arguments[1].decimal);
		return cost;
	}

	bool canPlay(const InfluenceCard@ card, const Targets@ targets) const override {
		int cost = getCost(card.extraQuality);
		return card.owner.canPay(cost);
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		sprt = icons::Money;
		name = locale::CARD_PLAY_MONEY;
		tooltip = locale::CARD_PLAY_MONEY;
		text = formatMoney(getCost(card.extraQuality));
		highlight = false;
		return IVM_Property;
	}

#section server
	bool playConsume(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		int cost = getCost(card.extraQuality);
		if(card.owner.consumeBudget(cost) == -1)
			return false;
		return true;
	}

	void playConsumeRewind(InfluenceCard@ card, Targets@ targets, InfluenceVote@ vote = null) const override {
		int cost = getCost(card.extraQuality);
		card.owner.refundBudget(cost, card.owner.BudgetCycleId);
	}
#section all
};

//ShowValue(<Sprite>, <Name>, <Amount>, <Per Quality> = 0.0, <Is Percentage> = False, <Tooltip> = "")
// Show an upkeep variable on the card.
class ShowValue : InfluenceCardEffect {
	ShowValue() {
		argument("Sprite", AT_Sprite);
		argument("Name", AT_Locale);
		argument("Amount", AT_Decimal);
		argument("Per Quality", AT_Decimal, "0.0");
		argument("Is Percentage", AT_Boolean, "False");
		argument("Tooltip", AT_Locale, "");
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int quality = card.extraQuality;
		double value = arguments[2].decimal + double(quality) * arguments[3].decimal;
		sprt = getSprite(arguments[0].str);
		name = arguments[1].str;
		if(arguments[4].boolean)
			text = toString(value * 100.0, 0)+"%";
		else
			text = standardize(value, true);
		if(arguments[5].str.length != 0)
			tooltip = format(arguments[5].str, text);
		highlight = arguments[3].decimal != 0 && quality != 0;
		return IVM_Property;
	}
};

//ShowGlobalValue(<Sprite>, <Name>, <Global>, <Factor> = 1.0, <Base> = 0.0, <Per Quality> = 0.0, <Is Percentage> = False, <Tooltip> = "", <Suffix> = "")
// Show an upkeep variable on the card.
class ShowGlobalValue : InfluenceCardEffect {
	ShowGlobalValue() {
		argument("Sprite", AT_Sprite);
		argument("Name", AT_Locale);
		argument("Global", AT_Global);
		argument("Factor", AT_Decimal, "1.0");
		argument("Base", AT_Decimal, "0.0");
		argument("Per Quality", AT_Decimal, "0.0");
		argument("Is Percentage", AT_Boolean, "False");
		argument("Tooltip", AT_Locale, "");
		argument("Suffix", AT_Locale, "");
	}

	InfluenceVariableMode getVariable(const InfluenceCard@ card, const InfluenceVote@ vote, Sprite& sprt, string& name, string& tooltip, string& text, bool& highlight) const override {
		int quality = card.extraQuality;
		double value = arguments[4].decimal + double(quality) * arguments[5].decimal;
		auto@ glob = getGlobal(arguments[2].integer);
		value += glob.value * arguments[3].decimal;
		sprt = getSprite(arguments[0].str);
		name = arguments[1].str;
		if(arguments[6].boolean)
			text = toString(value * 100.0, 0)+"%";
		else
			text = standardize(value, true);
		text += arguments[8].str;
		if(arguments[7].str.length != 0)
			tooltip = format(arguments[7].str, text);
		else
			tooltip = "";
		highlight = arguments[5].decimal != 0 && quality != 0;
		return IVM_Property;
	}
};

//TriggerAllPlanets(<Hook>(...))
// Run <Hook> as a single-time effect hook on all planets in the galaxy.
class TriggerAllPlanets : InfluenceCardEffect {
	BonusEffect@ hook;

	TriggerAllPlanets() {
		argument("Hook", AT_Hook, "bonus_effects::BonusEffect");
	}

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::"));
		if(hook is null) {
			error("BonusEffect(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return InfluenceCardEffect::instantiate();
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ sys = getSystem(i);
			for(uint n = 0, ncnt = sys.object.planetCount; n < ncnt; ++n) {
				Object@ obj = sys.object.planets[n];
				hook.activate(obj, card.owner);
			}
		}
	}
#section all
};

//InstantActivateTargetBought(<Target>)
// Instantly activate the target if bought from the stack with a target.
class InstantActivateTargetBought : InfluenceCardEffect {
	InstantActivateTargetBought() {
		target("Target", TT_Any, "");
	}

#section server
	void onGain(InfluenceCard@ card, int uses, bool wasBuy) const override {
		if(!wasBuy)
			return;
		Target@ targ = arguments[0].fromTarget(card.targets);
		if(targ is null || !targ.filled)
			return;
		playInfluenceCard_server(card.owner, card.id, card.targets);
	}
#section all
};

//FillStackWithLeverage(<Target>, <Ignore Self> = True)
// Fill the influence stack with leverage cards
class FillStackWithLeverage : InfluenceCardEffect {
	FillStackWithLeverage() {
		target("Target", TT_Empire);
	}

#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		Target@ targ = arguments[0].fromTarget(targets);
		if(targ is null)
			return;
		fillInfluenceStackWithLeverage(targ.emp);
	}
#section all
};

//InstantStackRotate()
// Immediately rotate the stack when playing this.
class InstantStackRotate : InfluenceCardEffect {
#section server
	void onPlay(InfluenceCard@ card, Targets@ targets) const override {
		rotateInfluenceStack();
	}
#section all
};

class QualityWeightLevel : InfluenceCardEffect {
	Document doc("Define the weight of the card at each quality level independently.");
	Argument resources(AT_VarArgs, AT_Integer, required=true, doc="List of weights based on quality.");

	int getWeight(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		uint index = clamp(card.extraQuality, 0, arguments.length-1);
		return arguments[index].integer;
	}
};

class QualityPlayCostLevel : InfluenceCardEffect {
	Document doc("Define the play cost of the card at each quality level independently.");
	Argument resources(AT_VarArgs, AT_Integer, required=true, doc="List of play costs based on quality.");

	int getPlayCost(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		uint index = clamp(card.extraQuality, 0, arguments.length-1);
		return arguments[index].integer;
	}
};

class ListActiveEffect : InfluenceCardEffect {
	Document doc("This card should be listed in the active effects after being played.");

	bool isActiveEffect(const InfluenceCard@ card, const InfluenceVoteEvent@ event, const InfluenceVote@ vote) const {
		if(event !is null)
			return false;
		return true;
	}
};

class AlwaysActiveEffect : InfluenceCardEffect {
	Document doc("This card should always be listed in the active effects after being played.");

	bool isActiveEffect(const InfluenceCard@ card, const InfluenceVoteEvent@ event, const InfluenceVote@ vote) const {
		if(event is null)
			return false;
		return true;
	}
};

class ListActiveIfNotVotedAfterThis : InfluenceCardEffect {
	Document doc("List this card as active if the targeted empire hasn't voted since this card was played.");
	Argument empTarget(TT_Empire);

	bool isActiveEffect(const InfluenceCard@ card, const InfluenceVoteEvent@ event, const InfluenceVote@ vote) const {
		if(event is null)
			return false;

		const Target@ targ = empTarget.fromConstTarget(event.cardEvent.targets);
		if(targ is null || targ.emp is null)
			return false;

		if(!vote.isPresent(targ.emp))
			return false;

		bool found = false;
		for(int i = vote.events.length - 1; i >= 0; --i ) {
			auto@ evt = vote.events[i];
			//Stop looking when we find ourselves
			if(evt.cardEvent !is null && evt.cardEvent.wasEventOf(card, matchTargets = true))
				break;

			//Look for a vote from the targeted empire
			if(evt.emp is targ.emp) {
				if(evt.playedSide != ICS_Neutral) {
					found = true;
					break;
				}
			}
		}

		return !found;
	}
};

class MultiplyVotePositiveSpeed : InfluenceCardEffect {
	Document doc("Votes this card is played in proceed in the positive at a multiplied rate.");
	Argument amount(AT_Decimal, doc="Speed multiplier for the vote.");

	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		vote.positiveSpeed *= amount.decimal;
	}
};

class MultiplyVoteNegativeSpeed : InfluenceCardEffect {
	Document doc("Votes this card is played in proceed in the negative at a multiplied rate.");
	Argument amount(AT_Decimal, doc="Speed multiplier for the vote.");

	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		vote.negativeSpeed *= amount.decimal;
	}
};

class AddVotePositiveCostPenalty : InfluenceCardEffect {
	Document doc("Increase the cost of positive cards played in this vote.");
	Argument amount(AT_Integer, doc="Amount extra to add to play costs.");

	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		vote.positiveCostPenalty += amount.integer;
	}
};

class AddVoteNegativeCostPenalty : InfluenceCardEffect {
	Document doc("Increase the cost of negative cards played in this vote.");
	Argument amount(AT_Integer, doc="Amount extra to add to play costs.");

	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		vote.negativeCostPenalty += amount.integer;
	}
};

class CanOnlyPlayIfSupporting : InfluenceCardEffect {
	Document doc("Card can only be played if the empire playing it has supported the vote.");
	Argument allow_neutral(AT_Boolean, "False", doc="Whether empires with 0 total votes are allowed.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		int amt = vote.getVoteFrom(card.owner);
		return amt > 0 || (allow_neutral.boolean && amt == 0);
	}
};

class CanOnlyPlayIfOpposing : InfluenceCardEffect {
	Document doc("Card can only be played if the empire playing it has opposed the vote.");
	Argument allow_neutral(AT_Boolean, "False", doc="Whether empires with 0 total votes are allowed.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		int amt = vote.getVoteFrom(card.owner);
		return amt < 0 || (allow_neutral.boolean && amt == 0);
	}
};

class RequireNotActiveEffect : InfluenceCardEffect {
	Document doc("Card can only be played into a vote if there is no currently active effect of a type.");
	Argument effect(AT_InfluenceCard, doc="Effect to check for.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		return !vote.hasActiveEffect(effect.integer);
	}
};

class RequireStartingCard : InfluenceCardEffect {
	Document doc("Can only be played if the vote was started via card.");
	Argument allow_events(AT_Boolean, "False", doc="Allow it to be played when the starting card is an event card.");

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return false;
		if(vote.events.length == 0)
			return false;
		auto@ evt = vote.events[0];
		if(evt.type != IVET_Start || evt.cardEvent is null)
			return false;
		auto@ cardType = evt.cardEvent.card.type;
		if(!allow_events.boolean && cardType.cls == ICC_Event)
			return false;
		return true;
	}
};

class GainStartingCard : InfluenceCardEffect {
	Document doc("Gain a copy of the card that started the vote if the event occurs.");
	Argument passfail("Event", AT_PassFail, doc="Which event - Pass or Fail - that causes the card to be granted.");
	Argument extra_quality(AT_Integer, "0", doc="Extra quality to add to the card when granted.");
	Argument extra_uses(AT_Integer, "0", doc="Extra uses to grant above the 1 normally granted.");

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEnd(InfluenceCard@ card, InfluenceVote@ vote, bool passed, bool withdrawn) const override {
		if(passed != arguments[0].boolean)
			return;
		if(vote is null)
			return;
		if(vote.events.length == 0)
			return;
		auto@ evt = vote.events[0];
		if(evt.type != IVET_Start || evt.cardEvent is null)
			return;

		auto@ startCard = evt.cardEvent.card;
		auto@ newCard = startCard.type.create(uses=1+extra_uses.integer, quality=startCard.quality+extra_quality.integer);

		cast<InfluenceStore>(card.owner.InfluenceManager).addCard(card.owner, newCard);
	}
#section all
};

class DelayVote : InfluenceCardEffect {
	Document doc("Stop the vote for a certain amount of time.");
	Argument duration(AT_Decimal, doc="Amount of time to stop the vote for.");

#section server
	bool get_isVoteEffect() const override {
		return true;
	}

	void onVoteEffect(InfluenceCard@ card, InfluenceVote@ vote) const override {
		double timer = 0.0;
		card.data[hookIndex].store(timer);

		vote.positiveSpeed /= 100000.0;
		vote.negativeSpeed /= 100000.0;
	}

	void onVoteTick(InfluenceCard@ card, InfluenceVote@ vote, double time) const {
		double timer = 0.0;
		card.data[hookIndex].retrieve(timer);

		timer += time;
		if(timer >= duration.decimal) {
			vote.positiveSpeed *= 100000.0;
			vote.negativeSpeed *= 100000.0;
			vote.removeCardEffect(card);
		}

		card.data[hookIndex].store(timer);
	}

	void save(InfluenceCard@ card, SaveFile& file) const override {
		double timer = 0.0;
		card.data[hookIndex].retrieve(timer);
		file << timer;
	}

	void load(InfluenceCard@ card, SaveFile& file) const override {
		double timer = 0.0;
		file >> timer;
		card.data[hookIndex].store(timer);
	}
#section all
};

class GiveLeverageTo : InfluenceCardEffect {
	Document doc("Generate leverage against the playing empire and give it to the targeted empire.");
	Argument targEmp("Empire", TT_Empire);
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic value to determine how valuable the leverage is.");

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		auto@ targ = targEmp.fromTarget(targets);
		if(targ is null || targ.emp is null)
			return;
		targ.emp.gainRandomLeverage(card.owner, qual.decimal);
	}
#section all
};

class EjectFromVote : InfluenceCardEffect {
	Document doc("Remove the targeted empire from the current vote.");
	Argument targEmp("Empire", TT_Empire);

	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(targets is null || vote is null)
			return true;

		auto@ targ = targEmp.fromConstTarget(targets);
		if(targ is null || targ.emp is null)
			return false;
		return vote.isPresent(targ.emp);
	}

#section server
	void onPlay(InfluenceCard@ card, InfluenceVote@ vote, Targets@ targets, int weight) const override {
		auto@ targ = targEmp.fromTarget(targets);
		if(targ is null || targ.emp is null)
			return;
		vote.leave(targ.emp);
	}
#section all
};

class RequireAttributeLT : InfluenceCardEffect {
	Document doc("This requires the empire's attribute to be less than a certain value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

	bool canPlay(const InfluenceCard@ card, const Targets@ targets) const override {
		Empire@ owner = card.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) >= value.decimal)
			return false;
		return true;
	}
};

class RequireAttributeGTE : InfluenceCardEffect {
	Document doc("This requires the empire's attribute to be greater or equal to a certain value.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

	bool canPlay(const InfluenceCard@ card, const Targets@ targets) const override {
		Empire@ owner = card.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) < value.decimal)
			return false;
		return true;
	}
};

class DontGenerateOnMap : InfluenceCardEffect {
	Document doc("Don't generate this effect when a particular type of map is present.");
	Argument check_map(AT_Custom, doc="Map id to check for.");

#section server
	bool canGenerateOnStack() {
		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
			if(galaxies[i].id == check_map.str) {
				return false;
			}
		}
		return true;
	}
#section all
};

class DisallowInVote : InfluenceCardEffect {
	Document doc("Don't allow this card played into this type of vote.");
	Argument vote_type(AT_InfluenceVote, doc="Vote type.");

#section server
	bool canPlay(const InfluenceCard@ card, const InfluenceVote@ vote, const Targets@ targets) const {
		if(vote is null)
			return true;
		return int(vote.type.id) != vote_type.integer;
	}
#section all
};
