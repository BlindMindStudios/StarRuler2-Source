import saving;
export getGlobal;

Mutex globMutex;
class HookGlobal {
	uint id = 0;
	string ident;
	double value = 0.0;
	bool delta = true;

	void add(double amount) {
		Lock lock(globMutex);
		value += amount;
		delta = true;
	}
};

array<HookGlobal> globals;
dictionary idents;

HookGlobal@ getGlobal(uint id) {
	if(id >= globals.length)
		return null;
#section gui
	globals[id].value = getGlobalValue(id);
#section all
	return globals[id];
}

HookGlobal@ getGlobal(const string& ident) {
	HookGlobal@ glob;
	if(idents.get(ident, @glob)) {
#section gui
		glob.value = getGlobalValue(glob.id);
#section all
		return glob;
	}

	@glob = HookGlobal();
	glob.id = globals.length;
	glob.ident = ident;
	globals.insertLast(glob);
	idents.set(ident, @glob);
	return glob;
}

#section server-side
double getGlobalValue_client(uint id) {
	auto@ glob = getGlobal(id);
	if(glob !is null)
		return glob.value;
	else
		return 0.0;
}

#section shadow
void syncInitial(Message& msg) {
	for(uint i = 0, cnt = globals.length; i < cnt; ++i)
		msg >> globals[i].value;
}

void recvPeriodic(Message& msg) {
	uint deltas = msg.readSmall();
	for(uint i = 0; i < deltas; ++i) {
		uint id = msg.readSmall();
		msg >> globals[id].value;
	}
}

#section server
void save(SaveFile& file) {
	uint cnt = globals.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i) {
		file.writeIdentifier(SI_Global, globals[i].id);
		file << globals[i].value;
	}
}

void load(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;
	for(uint i = 0; i < cnt; ++i) {
		uint id = file.readIdentifier(SI_Global);
		if(id == uint(-1))
			continue;
		file >> globals[id].value;
	}
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = globals.length; i < cnt; ++i) {
		auto type = globals[i];
		file.addIdentifier(SI_Global, type.id, type.ident);
	}
}

bool sendPeriodic(Message& msg) {
	uint deltas = 0;
	for(uint i = 0, cnt = globals.length; i < cnt; ++i) {
		if(globals[i].delta)
			deltas += 1;
	}
	if(deltas == 0)
		return false;

	Lock lock(globMutex);
	msg.writeSmall(deltas);
	for(uint i = 0, cnt = globals.length; i < cnt && deltas > 0; ++i) {
		if(globals[i].delta) {
			msg.writeSmall(i);
			msg << globals[i].value;
			globals[i].delta = false;
			--deltas;
		}
	}
	return true;
}

void syncInitial(Message& msg) {
	for(uint i = 0, cnt = globals.length; i < cnt; ++i)
		msg << globals[i].value;
}
