import notifications;
from notifications import NotificationStore;
import influence;
import buildings;
from influence_global import getInfluenceVoteByID, getTreatyDesc;

tidy class Notifications : Component_Notifications, Savable, NotificationStore {
	Mutex mtx;
	array<Notification@> list;

	void save(SaveFile& file) {
		uint cnt = list.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			list[i].save(file);
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		list.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@list[i] = loadNotification(file);
	}

	uint get_notificationCount() const {
		return list.length;
	}

	void getNotifications(uint limit, int beforeId = -1, bool reverse = true) {
		Lock lock(mtx);
		if(reverse) {
			if(beforeId == -1 || beforeId > int(list.length))
				beforeId = list.length;
			if(beforeId == 0)
				return;
			for(int i = beforeId - 1; i >= 0; --i) {
				Notification@ n = list[i];
				yieldNotification(n);
				if(--limit == 0)
					break;
			}
		}
		else {
			int cnt = list.length;
			if(beforeId == -1 || beforeId > cnt)
				beforeId = 0;
			if(beforeId >= cnt)
				return;
			for(int i = beforeId; i < cnt; ++i) {
				Notification@ n = list[i];
				yieldNotification(n);
				if(--limit == 0)
					break;
			}
		}
	}

	void addNotification(Empire& emp, Notification@ n) {
		Lock lock(mtx);
		list.insertLast(n);
	}

	void notifyVote(Empire& emp, int voteId, int eventId) {
		VoteNotification n;

		InfluenceVote@ vote = getInfluenceVoteByID(voteId);
		n.vote = InfluenceVoteStub(vote);
		n.event = vote.events[eventId];

		addNotification(emp, n);
	}

	void notifyGeneric(Empire& emp, string title, string desc, string icon = "", Empire@ fromEmp = null, Object@ forObject = null) {
		GenericNotification n;
		@n.fromEmp = fromEmp;
		@n.obj = forObject;
		n.title = title;
		n.desc = desc;
		n.iconDesc = icon;
		addNotification(emp, n);
	}

	void notifyWarStatus(Empire& emp, Empire@ withEmpire, uint type) {
		WarStatusNotification n;
		n.statusType = type;
		@n.withEmpire = withEmpire;
		addNotification(emp, n);
	}

	void notifyWarEvent(Empire& emp, Object@ obj, uint type) {
		WarEventNotification n;
		n.eventType = type;
		@n.obj = obj;
		addNotification(emp, n);
	}

	void notifyRename(Empire& emp, Object@ obj, string fromName, string toName) {
		RenameNotification n;
		@n.obj = obj;
		@n.fromEmpire = obj.owner;
		n.fromName = fromName;
		n.toName = toName;
		addNotification(emp, n);
	}

	void notifyAnomaly(Empire& emp, Object@ obj) {
		AnomalyNotification n;
		@n.obj = obj;
		addNotification(emp, n);
	}

	void notifyFlagship(Empire& emp, Object@ obj) {
		FlagshipBuiltNotification n;
		@n.obj = obj;
		addNotification(emp, n);
	}

	void notifyStructure(Empire& emp, Object@ obj, uint type) {
		StructureBuiltNotification n;
		@n.obj = obj;
		@n.bldg = getBuildingType(type);
		addNotification(emp, n);
	}

	void notifyEmpireMet(Empire& emp, Object@ obj, Empire@ metEmp, bool gainsBonus = false) {
		EmpireMetNotification n;
		@n.region = obj;
		@n.metEmpire = metEmp;
		n.gainsBonus = gainsBonus;
		addNotification(emp, n);
	}

	void notifyTreaty(Empire& emp, uint treatyId, uint eventType, Empire@ empOne = null, Empire@ empTwo = null) {
		auto@ treaty = getTreatyDesc(treatyId);
		if(treaty is null)
			return;

		TreatyEventNotification n;
		n.treaty = treaty;
		n.eventType = eventType;
		@n.empOne = empOne;
		@n.empTwo = empTwo;

		addNotification(emp, n);
	}

	uint prevSynced = 0;
	void writeNotifications(Message& msg, bool delta) {
		Lock lock(mtx);
		uint start, cnt;
		if(delta) {
			start = prevSynced;
			cnt = list.length - prevSynced;
		}
		else {
			start = 0;
			cnt = list.length;
		}

		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << list[start + i];

		if(delta)
			prevSynced = list.length;
	}
};
