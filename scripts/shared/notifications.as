export NotifyType, NotifyTriggerMode, Notification;
export yieldNotification, receiveNotifications;
export createNotification, readNotification, loadNotification;
export VoteNotification;
export WarStatusNotification, WarStatusType;
export WarEventNotification, WarEventType;
export WonderNotification;
export CardNotification;
export RenameNotification;
export AnomalyNotification;
export FlagshipBuiltNotification;
export StructureBuiltNotification;
export EmpireMetNotification;
export GenericNotification;
export TreatyEventNotification, TreatyEventType;
export DonationNotification;

import influence;
from influence import ICardNotification, TreatyEventType;
import saving;
import util.formatting;
import buildings;
import icons;

enum NotifyType {
	NT_Vote,
	NT_WarStatus,
	NT_WarEvent,
	NT_Wonder,
	NT_Card,
	NT_Renamed,
	NT_Anomaly,
	NT_FlagshipBuilt,
	NT_StructureBuilt,
	NT_Generic,
	NT_MetEmpire,
	NT_TreatyEvent,
	NT_Donation,

	NT_COUNT,
	NT_INVALID,
};

enum NotifyTriggerMode {
	NTM_Ignore,
	NTM_KillClass,
	NTM_KillEvents,
	NTM_KillTop
};

// {{{ Basic Notification
class Notification : Serializable, Savable {
	double time = gameTime;

	//Way that events are dismissed when viewed
	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillEvents;
	}

	//The class context specifier for out-of-context notifications
	string formatClass() const {
		return "";
	}

	//The textual string of this notification
	string formatEvent() const {
		return "";
	}
	
	//Notification sound to play when the notice appears
	const SoundSource@ get_sound() const {
		return sound::alert_generic;
	}

	//The iconic representation of this notification
	Sprite get_icon() const {
		return Sprite();
	}

	//Model to display 3D icon
	const Model@ get_model() const {
		return null;
	}

	//Material to display 3D icon
	const Material@ get_material() const {
		return null;
	}

	//Whether to pulse the icon
	bool get_pulseIcon() const {
		return false;
	}

	//The type of notification
	NotifyType get_type() const {
		return NT_INVALID;
	}

	//Object that this notification relates to
	Object@ get_relatedObject() const {
		return null;
	}

	//How many times the icon should flash when this event happens
	int get_flashCount() const {
		return 3;
	}

	//Should be transitive and commutative, or weirdness can happen.
	bool sharesClass(const Notification& other) const {
		return false;
	}

	//Networking
	void write(Message& msg) {
		msg << uint(type);
		msg << time;
	}

	void read(Message& msg) {
		msg >> time;
	}

	//Saving and loading
	void save(SaveFile& file) {
		file << uint(type);
		file << time;
	}

	void load(SaveFile& file) {
		file >> time;
	}
};
// }}}
// {{{ Vote Notification
class VoteNotification : Notification {
	InfluenceVoteStub vote;
	InfluenceVoteEvent event;

	NotifyType get_type() const override {
		return NT_Vote;
	}

	Sprite get_icon() const override {
		return Sprite(spritesheet::Notifications, 0);
	}

	string formatClass() const override {
		if(vote.startedBy is defaultEmpire)
			return vote.formatTitle();
		return formatEmpireName(vote.startedBy)+": "+vote.formatTitle();
	}

	bool sharesClass(const Notification& other) const override {
		const VoteNotification@ notif = cast<const VoteNotification>(other);
		if(notif is null)
			return false;
		return notif.vote.id == vote.id;
	}

	string formatEvent() const override {
		return event.formatEvent();
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << vote;
		msg << event;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> vote;
		msg >> event;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << vote;
		file << event;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> vote;
		file >> event;
	}
};
// }}}
// {{{ Card Notification
class CardNotification : Notification, ICardNotification {
	InfluenceCardPlayEvent event;
	InfluenceCard@ subjectCard;
	InfluenceEffect@ subjectEffect;
	int voteId = -1;

	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillClass;
	}

	NotifyType get_type() const override {
		return NT_Card;
	}

	Sprite get_icon() const override {
		return event.card.type.icon;
	}

	string formatClass() const override {
		return formatEmpireName(event.card.owner)+": "+event.card.formatTitle();
	}

	string formatEvent() const override {
		return event.formatNotification(this);
	}

	Object@ get_relatedObject() const {
		for(uint i = 0, cnt = event.targets.length; i < cnt; ++i) {
			auto@ targ = event.targets[i];
			if(targ.obj !is null)
				return targ.obj;
		}
		return null;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << event;
		msg << voteId;

		if(subjectCard !is null) {
			msg.write1();
			msg << subjectCard;
		}
		else {
			msg.write0();
		}

		if(subjectEffect !is null) {
			msg.write1();
			msg << subjectEffect;
		}
		else {
			msg.write0();
		}
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> event;
		msg >> voteId;

		if(msg.readBit()) {
			if(subjectCard is null)
				@subjectCard = InfluenceCard(msg);
			else
				msg >> subjectCard;
		}

		if(msg.readBit()) {
			if(subjectEffect is null)
				@subjectEffect = InfluenceEffect(msg);
			else
				msg >> subjectEffect;
		}
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << event;
		file << voteId;

		if(subjectCard !is null) {
			file.write1();
			file << subjectCard;
		}
		else {
			file.write0();
		}

		if(subjectEffect !is null) {
			file.write1();
			file << subjectEffect;
		}
		else {
			file.write0();
		}
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> event;
		if(file >= SV_0080)
			file >> voteId;

		if(file.readBit()) {
			if(subjectCard is null)
				@subjectCard = InfluenceCard(file);
			else
				file >> subjectCard;
		}

		if(file.readBit()) {
			if(subjectEffect is null)
				@subjectEffect = InfluenceEffect(file);
			else
				file >> subjectEffect;
		}
	}
};
// }}}
// {{{ War Status Notification
enum WarStatusType {
	WST_War,
	WST_ProposePeace,
	WST_AcceptPeace,
};

class WarStatusNotification : Notification {
	Empire@ withEmpire;
	uint statusType;

	NotifyTriggerMode get_triggerMode() const override {
		return NTM_KillClass;
	}

	NotifyType get_type() const override {
		return NT_WarStatus;
	}
	
	const SoundSource@ get_sound() const {
		if(statusType == WST_War)
			return sound::alert_combat;
		else
			return sound::alert_generic;
	}

	Sprite get_icon() const override {
		return Sprite(spritesheet::Notifications, 1);
	}

	string formatClass() const override {
		return format(locale::WAR_STATUS, formatEmpireName(withEmpire));
	}

	bool sharesClass(const Notification& other) const override {
		const WarStatusNotification@ notif = cast<const WarStatusNotification>(other);
		return notif !is null && notif.withEmpire is withEmpire;
	}

	string formatEvent() const override {
		switch(statusType) {
			case WST_War:
				return format(locale::WAR_STATUS_WAR, formatEmpireName(withEmpire));
			case WST_ProposePeace:
				return format(locale::WAR_STATUS_PROPOSE, formatEmpireName(withEmpire));
			case WST_AcceptPeace:
				return format(locale::WAR_STATUS_ACCEPT, formatEmpireName(withEmpire));
		}
		return "--";
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << withEmpire;
		msg << statusType;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> withEmpire;
		msg >> statusType;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << withEmpire;
		file << statusType;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> withEmpire;
		file >> statusType;
	}
};
// }}}
// {{{ War Event Notification
enum WarEventType {
	WET_ContestedSystem,
	WET_LostPlanet,
};

class WarEventNotification : Notification {
	Object@ obj;
	uint eventType;

	Object@ get_relatedObject() const override {
		return obj;
	}

	NotifyTriggerMode get_triggerMode() const override {
		return NTM_KillTop;
	}

	NotifyType get_type() const override {
		return NT_WarEvent;
	}
	
	const SoundSource@ get_sound() const {
		if(eventType == WET_LostPlanet)
			return sound::alert_lostasset;
		else
			return sound::alert_combat;
	}

	Sprite get_icon() const override {
		switch(eventType) {
		case WET_LostPlanet:
			return Sprite(spritesheet::Notifications, 2);
	  }
	  return Sprite(material::SystemUnderAttack);
	}	

	string formatClass() const override {
		Region@ region = cast<Region>(obj);
		if(region is null)
			@region = obj.region;
		if(region is null)
			return format(locale::WAR_EVT, "--");
		return format(locale::WAR_EVT, region.name);
	}

	bool sharesClass(const Notification& other) const override {
		const WarEventNotification@ notif = cast<const WarEventNotification>(other);
		if(notif is null)
			return false;

		const Region@ myRegion = cast<const Region@>(obj);
		if(myRegion is null)
			@myRegion = obj.region;

		const Region@ theirRegion = cast<const Region@>(notif.obj);
		if(theirRegion is null)
			@theirRegion = notif.obj.region;

		return myRegion !is null && myRegion is theirRegion;
	}

	string formatEvent() const override {
		switch(eventType) {
			case WET_ContestedSystem:
				return format(locale::WAR_EVT_CONTEST, obj.name);
			case WET_LostPlanet:
				return format(locale::WAR_EVT_LOST, obj.name);
		}
		return "--";
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << obj;
		msg << eventType;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> obj;
		msg >> eventType;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << obj;
		file << eventType;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> obj;
		file >> eventType;
	}
};
// }}}
// {{{ Treaty Event Notification
class TreatyEventNotification : Notification {
	Treaty treaty;
	uint eventType;
	Empire@ empOne;
	Empire@ empTwo;

	NotifyTriggerMode get_triggerMode() const override {
		return NTM_KillClass;
	}

	NotifyType get_type() const override {
		return NT_TreatyEvent;
	}
	
	const SoundSource@ get_sound() const {
		return sound::alert_generic;
	}

	Sprite get_icon() const override {
		if(eventType == TET_Subjugate)
			return Sprite(material::LoyaltyIcon);
		return Sprite(material::Propositions);
	}	

	string formatClass() const override {
		return treaty.name;
	}

	bool sharesClass(const Notification& other) const override {
		const TreatyEventNotification@ notif = cast<const TreatyEventNotification>(other);
		if(notif is null)
			return false;
		return notif.treaty.id == treaty.id;
	}

	string formatEvent() const override {
		string text = "---";
		switch(eventType) {
			case TET_Invite: text = empTwo is null ? locale::NOTIF_TREATY_INVITE_OTHER : locale::NOTIF_TREATY_INVITE; break;
			case TET_Leave: text = locale::NOTIF_TREATY_LEAVE; break;
			case TET_Dismiss: text = locale::NOTIF_TREATY_DISMISS; break;
			case TET_Join: text = locale::NOTIF_TREATY_JOIN; break;
			case TET_Decline: text = locale::NOTIF_TREATY_DECLINE; break;
			case TET_Subjugate: text = locale::NOTIF_VASSAL; break;
		}
		return format(text, treaty.name,
				formatEmpireName(empOne), formatEmpireName(empTwo),
				formatEmpireName(treaty.leader),
				treaty.leader !is null ? formatEmpireName(treaty.leader)+"'s '" : "");
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << treaty;
		msg << eventType;
		msg << empOne;
		msg << empTwo;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> treaty;
		msg >> eventType;
		msg >> empOne;
		msg >> empTwo;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << treaty;
		file << eventType;
		file << empOne;
		file << empTwo;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> treaty;
		file >> eventType;
		file >> empOne;
		file >> empTwo;
	}
};
// }}}
// {{{ Wonder Notification
class WonderNotification : Notification {
	Empire@ fromEmpire;

	NotifyType get_type() const override {
		return NT_Wonder;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << fromEmpire;

		uint did = 0;
		msg << did;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> fromEmpire;

		uint did = 0;
		msg >> did;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << fromEmpire;
		file.writeIdentifier(SI_PlanetDesignation, 0);
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> fromEmpire;
		uint did = file.readIdentifier(SI_PlanetDesignation);
	}
};
// }}}
// {{{ Rename Notification
class RenameNotification : Notification {
	Empire@ fromEmpire;
	Object@ obj;
	string fromName;
	string toName;

	NotifyType get_type() const override {
		return NT_Renamed;
	}

	Object@ get_relatedObject() const override {
		return obj;
	}

	string formatClass() const override {
		string txt = format(locale::RENAME_NOTIF, toName);
		txt = format("[color=$1]$2[/color]", toString(fromEmpire.color), txt);
		return txt;
	}

	string formatEvent() const override {
		return format(locale::RENAME_EVT, formatEmpireName(fromEmpire), fromName, toName);
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << fromEmpire;
		msg << obj;
		msg << fromName;
		msg << toName;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> fromEmpire;
		msg >> obj;
		msg >> fromName;
		msg >> toName;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << fromEmpire;
		file << obj;
		file << fromName;
		file << toName;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> fromEmpire;
		file >> obj;
		file >> fromName;
		file >> toName;
	}
};
// }}}
// {{{ Anomaly Notification
class AnomalyNotification : Notification {
	Object@ obj;

	NotifyType get_type() const override {
		return NT_Anomaly;
	}

	string formatClass() const override {
		Region@ reg = obj.region;
		if(reg !is null)
			return format(locale::ANOMALY_NOTIFICATION, reg.name);
		return format(locale::ANOMALY_NOTIFICATION, "???");
	}

	Object@ get_relatedObject() const override {
		return obj;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << obj;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> obj;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << obj;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> obj;
	}
};
// }}}
// {{{ Generic Notification
class GenericNotification : Notification {
	Empire@ fromEmp;
	Object@ obj;
	string iconDesc;
	string title;
	string desc;

	NotifyType get_type() const override {
		return NT_Generic;
	}

	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillClass;
	}

	array<string>@ getParts() {
		array<string> parts;
		if(fromEmp !is null) {
			parts.insertLast(bbescape(fromEmp.name));
			parts.insertLast(toString(fromEmp.color));
		}
		else {
			parts.insertLast("--");
			parts.insertLast("#ffffff");
		}
		if(obj !is null) {
			parts.insertLast(obj.name);
			parts.insertLast(toString(obj.owner.color));
		}
		else {
			parts.insertLast("--");
			parts.insertLast("#ffffff");
		}
		return parts;
	}

	string formatClass() const override {
		return format(localize(title), getParts());
	}

	string formatEvent() const override {
		return format(localize(desc), getParts());
	}

	Sprite get_icon() const override {
		return getSprite(iconDesc);
	}

	Object@ get_relatedObject() const override {
		return obj;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << fromEmp;
		msg << obj;
		msg << iconDesc;
		msg << title;
		msg << desc;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> fromEmp;
		msg >> obj;
		msg >> iconDesc;
		msg >> title;
		msg >> desc;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << fromEmp;
		file << obj;
		file << iconDesc;
		file << title;
		file << desc;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> fromEmp;
		file >> obj;
		file >> iconDesc;
		file >> title;
		file >> desc;
	}
};
// }}}
// {{{ Flagship Built Notification
class FlagshipBuiltNotification : Notification {
	Object@ obj;

	NotifyType get_type() const override {
		return NT_FlagshipBuilt;
	}

	string formatClass() const override {
		return format(locale::BUILT_NOTIFICATION, obj.name);
	}
	
	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillClass;
	}

	Object@ get_relatedObject() const override {
		return obj;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << obj;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> obj;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << obj;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> obj;
	}
};
// }}}
// {{{ Structure Built Notification
class StructureBuiltNotification : Notification {
	Object@ obj;
	const BuildingType@ bldg;

	NotifyType get_type() const override {
		return NT_StructureBuilt;
	}

	Sprite get_icon() const override {
		return bldg.sprite;
	}

	string formatClass() const override {
		return format(locale::BUILT_ON_NOTIFICATION, bldg.name, obj.name);
	}
	
	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillClass;
	}

	Object@ get_relatedObject() const override {
		return obj;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << obj;
		msg.writeSmall(bldg.id);
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> obj;
		uint tid = msg.readSmall();
		@bldg = getBuildingType(tid);
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << obj;
		file.writeIdentifier(SI_Building, bldg.id);
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> obj;	
		uint tid = file.readIdentifier(SI_Building);
		@bldg = getBuildingType(tid);
	}
};
// }}}
// {{{ Empire Met Notification
class EmpireMetNotification : Notification {
	Empire@ metEmpire;
	Object@ region;
	bool gainsBonus = false;

	NotifyType get_type() const override {
		return NT_MetEmpire;
	}

	Sprite get_icon() const override {
		return Sprite(metEmpire.portrait);
	}

	string formatClass() const override {
			return format(locale::NOTIF_MET_EMPIRE, formatEmpireName(metEmpire), region.name);
	}

	string formatEvent() const override {
		if(!gainsBonus)
			return "";
		return format(locale::NOTIF_MET_EMPIRE_BONUS, formatEmpireName(metEmpire), region.name, toString(config::INFLUENCE_CONTACT_BONUS, 0));
	}
	
	NotifyTriggerMode get_triggerMode() const {
		return NTM_KillClass;
	}

	Object@ get_relatedObject() const override {
		return region;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << metEmpire;
		msg << region;
		msg << gainsBonus;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> metEmpire;
		msg >> region;
		msg >> gainsBonus;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << metEmpire;
		file << region;
		file << gainsBonus;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> metEmpire;
		file >> region;
		if(file >= SV_0097)
			file >> gainsBonus;
	}
};
// }}}
// {{{ Donation Notification
class DonationNotification : Notification {
	DiplomacyOffer offer;
	Empire@ fromEmpire;

	NotifyType get_type() const override {
		return NT_Donation;
	}

	Sprite get_icon() const override {
		return icons::Donate;
	}

	string formatClass() const override {
		return format(locale::NOTIF_DONATION, formatEmpireName(fromEmpire), offer.blurb);
	}

	bool sharesClass(const Notification& other) const override {
		const DonationNotification@ notif = cast<const DonationNotification>(other);
		if(notif is null)
			return false;
		return notif.fromEmpire is fromEmpire;
	}
	
	NotifyTriggerMode get_triggerMode() const override {
		return NTM_KillTop;
	}

	Object@ get_relatedObject() const override {
		return offer.obj;
	}

	//Networking
	void write(Message& msg) override {
		Notification::write(msg);
		msg << fromEmpire;
		msg << offer;
	}

	void read(Message& msg) override {
		Notification::read(msg);
		msg >> fromEmpire;
		msg >> offer;
	}

	//Saving and loading
	void save(SaveFile& file) override {
		Notification::save(file);
		file << fromEmpire;
		file << offer;
	}

	void load(SaveFile& file) override {
		Notification::load(file);
		file >> fromEmpire;
		file >> offer;
	}
};
// }}}

// {{{ Data management
//Sending a list of notifications through yielding
void yieldNotification(Notification@ n) {
	n.write(startYield());
	finishYield();
}

//Receiving notification from a datalist
class Receiver : Serializable {
	Notification@ n;
	void write(Message& msg) {
	}
	void read(Message& msg) {
		@n = readNotification(msg);
	}
};
void receiveNotifications(array<Notification@>& list, DataList@ data) {
	Receiver recv;
	while(receive(data, recv))
		list.insertLast(recv.n);
}

//Interface for the empire
interface NotificationStore {
	void addNotification(Empire& emp, Notification@ n);
}

//Notification generation through messages or savefiles
Notification@ createNotification(uint type) {
	switch(type) {
		case NT_Vote: return VoteNotification();
		case NT_WarStatus: return WarStatusNotification();
		case NT_WarEvent: return WarEventNotification();
		case NT_Wonder: return WonderNotification();
		case NT_Card: return CardNotification();
		case NT_Renamed: return RenameNotification();
		case NT_Anomaly: return AnomalyNotification();
		case NT_FlagshipBuilt: return FlagshipBuiltNotification();
		case NT_StructureBuilt: return StructureBuiltNotification();
		case NT_MetEmpire: return EmpireMetNotification();
		case NT_Generic: return GenericNotification();
		case NT_TreatyEvent: return TreatyEventNotification();
		case NT_Donation: return DonationNotification();
	}
	return Notification();
}

Notification@ readNotification(Message& msg) {
	uint type = 0;
	msg >> type;

	Notification@ n = createNotification(type);
	n.read(msg);
	return n;
}

Notification@ loadNotification(SaveFile& file) {
	uint type = 0;
	file >> type;

	Notification@ n = createNotification(type);
	n.load(file);
	return n;
}
// }}}
