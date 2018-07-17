import random_events;

tidy class RandomEvents : Component_RandomEvents {
	Mutex mtx;
	array<CurrentEvent> events;

	CurrentEvent@ getEventByID(int id) {
		for(uint i = 0, cnt = events.length; i < cnt; ++i) {
			if(events[i].id == id)
				return events[i];
		}
		return null;
	}

	int get_currentEventID() {
		if(events.length == 0)
			return -1;
		Lock lck(mtx);
		if(events.length == 0)
			return -1;
		return events[0].id;
	}

	bool hasCurrentEvents() {
		return events.length != 0;
	}

	void getCurrentEvents() {
		Lock lck(mtx);
		for(uint i = 0, cnt = events.length; i < cnt; ++i)
			yield(events[i]);
	}

	void getEvent(int id) {
		Lock lck(mtx);
		auto@ evt = getEventByID(id);
		if(evt !is null)
			yield(evt);
	}

	void chooseEventOption(Empire& emp, int evtId, uint optId) {
		Lock lck(mtx);
		for(uint i = 0, cnt = events.length; i < cnt; ++i) {
			if(events[i].id == evtId) {
				events.removeAt(i);
				break;
			}
		}
	}

	void readEvents(Message& msg) {
		if(!msg.readBit()) {
			if(events.length != 0) {
				Lock lck(mtx);
				events.length = 0;
			}
			return;
		}
		Lock lck(mtx);
		events.length = msg.readSmall();
		for(uint i = 0, cnt = events.length; i < cnt; ++i)
			msg >> events[i];
	}
};
