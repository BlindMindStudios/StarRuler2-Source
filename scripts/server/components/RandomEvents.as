import random_events;

tidy class RandomEvents : Component_RandomEvents, EventContainer, Savable {
	Mutex mtx;
	array<CurrentEvent@> events;
	int nextEventId = 0;

	double nextRandomEvent = -1;
	array<const RandomEvent@> considering;
	set_int eventsEncountered;
	array<int> encounteredList;
	CurrentEvent consEvt;

	void save(SaveFile& file) {
		file << nextEventId;
		file << nextRandomEvent;

		uint cnt = events.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << events[i];

		cnt = considering.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file.writeIdentifier(SI_RandomEvent, considering[i].id);

		cnt = encounteredList.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file.writeIdentifier(SI_RandomEvent, encounteredList[i]);
	}

	void load(SaveFile& file) {
		file >> nextEventId;
		file >> nextRandomEvent;

		uint cnt = 0;
		file >> cnt;
		events.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@events[i] = CurrentEvent();
			file >> events[i];
		}

		file >> cnt;
		considering.length = 0;
		considering.reserve(cnt);
		for(uint i = 0; i < cnt; ++i) {
			auto@ type = getRandomEvent(file.readIdentifier(SI_RandomEvent));
			if(type !is null)
				considering.insertLast(type);
		}

		file >> cnt;
		encounteredList.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			encounteredList[i] = file.readIdentifier(SI_RandomEvent);
			eventsEncountered.insert(encounteredList[i]);
		}
	}

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

	void create(CurrentEvent@ evt) {
		CurrentEvent newEvent = evt;

		Lock lck(mtx);
		newEvent.id = nextEventId++;
		eventsEncountered.insert(evt.type.id);
		encounteredList.insertLast(evt.type.id);
		events.insertLast(newEvent);
	}

	void setNextEvent() {
		if(config::RANDOM_EVENT_OCCURRENCE == 0) {
			nextRandomEvent = INFINITY;
			return;
		}
		double time = 600.0 / config::RANDOM_EVENT_OCCURRENCE;
		double mod = max(time - config::RANDOM_EVENT_MIN_INTERVAL, 0.0);
		nextRandomEvent = gameTime + normald(time-mod, time+mod);
	}

	void spawnRandomEvent(Empire& emp, uint typeId) {
		auto@ type = getRandomEvent(typeId);
		if(type is null)
			return;

		CurrentEvent evt;
		evt.clear(type);
		@evt.owner = emp;
		if(evt.consider()) {
			evt.create();
			create(evt);
		}
	}

	void eventsTick(Empire& emp, double time) {
		if(emp.isAI && emp !is playerEmpire) {
			nextRandomEvent = -1;
			return;
		}

		//Tick existing events
		for(uint i = 0, cnt = events.length; i < cnt; ++i) {
			auto@ evt = events[i];
			if(evt.timer > 0) {
				evt.timer -= time;
				if(evt.timer <= 0) {
					int optId = -1;
					for(uint i = 0, cnt = evt.options.length; i < cnt; ++i) {
						if(evt.options[i].defaultOption) {
							optId = evt.options[i].id;
							break;
						}
					}
					if(optId != -1)
						chooseEventOption(emp, evt.id, optId);
					else
						events.removeAt(i);
					--i; --cnt;
				}
			}
		}

		//Consider new events
		if(nextRandomEvent < 0) {
			setNextEvent();
		}
		else if(considering.length != 0) {
			const RandomEvent@ checkType;
			double tot = 0;
			for(uint i = 0, cnt = considering.length; i < cnt; ++i) {
				double freq = considering[i].frequency;
				tot += freq;
				if(randomd() < freq / tot)
					@checkType = considering[i];
			}

			if(checkType !is null) {
				consEvt.clear(checkType);
				@consEvt.owner = emp;
				if(consEvt.consider()) {
					consEvt.create();
					create(consEvt);
					considering.length = 0;
				}
				else {
					considering.remove(checkType);
				}
				if(considering.length == 0)
					setNextEvent();
			}
			else {
				setNextEvent();
			}
		}
		else if(nextRandomEvent < gameTime) {
			for(uint i = 0, cnt = getRandomEventCount(); i < cnt; ++i) {
				auto@ type = getRandomEvent(i);
				if(type.mode != RTM_Random)
					continue;
				if(type.frequency <= 0)
					continue;
				if(type.unique && eventsEncountered.contains(type.id))
					continue;
				considering.insertLast(type);
			}
			if(considering.length == 0)
				setNextEvent();
		}
	}

	void chooseEventOption(Empire& emp, int evtId, uint optId) {
		Lock lck(mtx);
		auto@ evt = getEventByID(evtId);
		if(evt !is null) {
			for(uint i = 0, cnt = evt.options.length; i < cnt; ++i) {
				if(evt.options[i].id == optId) {
					evt.options[i].trigger(evt);
					break;
				}
			}
			events.remove(evt);
		}
	}

	void writeEvents(Message& msg) {
		if(events.length == 0) {
			msg.write0();
			return;
		}
		Lock lck(mtx);
		msg.write1();
		msg.writeSmall(events.length);
		for(uint i = 0, cnt = events.length; i < cnt; ++i)
			msg << events[i];
	}
};
