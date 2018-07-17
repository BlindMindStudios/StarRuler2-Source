import saving;
import hooks;

enum RandomTriggerMode {
	RTM_Random,
};

class RandomEvent {
	uint id;
	string ident;
	string name;
	string text;
	array<EventOption@> options;
	Targets targets;
	RandomTriggerMode mode = RTM_Random;
	double frequency = 1.0;
	bool unique = true;
	double timer = 180.0;

	array<IRandomEventHook@> hooks;

	RandomEvent() {
		targets.add("Owner", TT_Empire);
	}

	void init() {
		for(uint n = 0, ncnt = hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(hooks[n])+" on random event "+ident);
			else
				cast<Hook>(hooks[n]).initTargets(targets);
		}
		for(uint i = 0, cnt = options.length; i < cnt; ++i)
			options[i].init(this);
	}

	const EventOption@ getOption(uint id) const {
		for(uint i = 0, cnt = options.length; i < cnt; ++i) {
			if(options[i].id == id)
				return options[i];
		}
		return null;
	}
};

class EventOption {
	uint id;
	string ident;
	string text;
	Sprite icon;
	bool defaultOption = false;
	bool safe = true;

	array<EventResult@> inner;
	EventResult result;

	void init(RandomEvent@ evt) {
		result.init(evt);
		for(uint i = 0, cnt = inner.length; i < cnt; ++i)
			inner[i].init(evt);
	}

	bool shouldAdd(CurrentEvent& evt) const {
		for(uint i = 0, cnt = result.block.hooks.length; i < cnt; ++i) {
			if(!result.block.hooks[i].shouldAdd(evt, this))
				return false;
		}
		return true;
	}

	void trigger(CurrentEvent& evt) const {
		result.trigger(evt, this);

		double total = 0.0;
		for(uint i = 0, cnt = inner.length; i < cnt; ++i)
			total += inner[i].frequency;
		double roll = randomd(0.0, total);
		for(uint i = 0, cnt = inner.length; i < cnt; ++i) {
			roll -= inner[i].frequency;
			if(roll <= 0) {
				inner[i].trigger(evt, this);
				break;
			}
		}
	}
};

class EventResult {
	double frequency = 1.0;
	array<OnBlock@> inner;
	OnBlock block;

	void init(RandomEvent@ evt) {
		block.init(evt);
		for(uint i = 0, cnt = inner.length; i < cnt; ++i)
			inner[i].init(evt);
	}

	void trigger(CurrentEvent& evt, const EventOption& opt) const {
		block.trigger(evt, opt);
		for(uint i = 0, cnt = inner.length; i < cnt; ++i)
			inner[i].trigger(evt, opt);
	}
};

class OnBlock {
	array<IRandomOptionHook@> hooks;
	string targetName;
	uint targetIndex = uint(-1);

	void init(RandomEvent@ evt) {
		for(uint n = 0, ncnt = hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(hooks[n])+" on random event.");
			else
				cast<Hook>(hooks[n]).initTargets(evt.targets);
		}
		if(targetName.length != 0) {
			targetIndex = uint(evt.targets.getIndex(targetName));
			if(targetIndex >= evt.targets.length)
				error("Error: 'On' block could not find target '"+targetName+"' in event "+evt.ident);
		}
	}

	void trigger(CurrentEvent& evt, const EventOption& opt) const {
		for(uint n = 0, ncnt = hooks.length; n < ncnt; ++n) {
			if(targetIndex >= evt.targets.length)
				hooks[n].trigger(evt, opt, null);
			else
				hooks[n].trigger(evt, opt, evt.targets[targetIndex]);
		}
	}
};

interface EventContainer {
	void create(CurrentEvent@ evt);
};

class CurrentEvent : Serializable, Savable {
	int id = -1;
	const RandomEvent@ type;
	Targets targets;
	array<const EventOption@> options;
	double timer = -1;

	CurrentEvent() {}

	bool consider() {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].consider(this))
				return false;
		}
		for(uint i = 0, cnt = type.options.length; i < cnt; ++i) {
			if(type.options[i].shouldAdd(this))
				options.insertLast(type.options[i]);
		}
		return options.length != 0;
	}
	
	void create() {
		timer = type.timer;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].create(this);
	}

	Empire@ get_owner() const {
		if(targets.length == 0)
			return null;
		return targets[0].emp;
	}

	void set_owner(Empire@ emp) {
		if(targets.length == 0)
			return;
		@targets[0].emp = emp;
		targets[0].filled = true;
	}

	bool isValidTarget(uint index, const Target@ targ) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].isValidTarget(this, index, targ))
				return false;
		}
		return true;
	}

	void clear(const RandomEvent& type) {
		@this.type = type;
		targets = type.targets;
		options.length = 0;
		timer = 0;
	}

	void write(Message& msg) {
		msg.writeSmall(id);
		msg.writeSmall(type.id);
		msg << targets;
		msg << timer;
		msg.writeSmall(options.length);
		for(uint i = 0, cnt = options.length; i < cnt; ++i)
			msg.writeSmall(options[i].id);
	}

	void read(Message& msg) {
		id = msg.readSmall();
		@type = getRandomEvent(msg.readSmall());
		msg >> targets;
		msg >> timer;
		options.length = msg.readSmall();
		for(uint i = 0, cnt = options.length; i < cnt; ++i)
			@options[i] = type.getOption(msg.readSmall());
	}

	void save(SaveFile& file) {
		file << id;
		file.writeIdentifier(SI_RandomEvent, type.id);
		file << targets;
		file << timer;

		uint cnt = options.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file.writeIdentifier(SI_RandomEventOption, options[i].id);
	}

	void load(SaveFile& file) {
		file >> id;
		@type = getRandomEvent(file.readIdentifier(SI_RandomEvent));
		file >> targets;
		file >> timer;
		uint cnt = 0;
		file >> cnt;
		options.length = 0;
		options.reserve(cnt);
		for(uint i = 0; i < cnt; ++i) {
			auto@ opt = type.getOption(file.readIdentifier(SI_RandomEventOption));
			if(opt !is null)
				options.insertLast(opt);
		}
	}
};

interface IRandomEventHook {
	bool consider(CurrentEvent& evt) const;
	void create(CurrentEvent& evt) const;
	bool isValidTarget(CurrentEvent& evt, uint index, const Target@ targ) const;
};

class RandomEventHook : Hook, IRandomEventHook {
	bool consider(CurrentEvent& evt) const { return true; }
	void create(CurrentEvent& evt) const {}
	bool isValidTarget(CurrentEvent& evt, uint index, const Target@ targ) const { return true; }
};

interface IRandomOptionHook {
	bool shouldAdd(CurrentEvent& evt, const EventOption& option) const;
	void trigger(CurrentEvent& evt, const EventOption& option, const Target@ targ) const;
};

class RandomOptionHook : Hook, IRandomOptionHook {
	bool shouldAdd(CurrentEvent& evt, const EventOption& option) const { return true; }
	void trigger(CurrentEvent& evt, const EventOption& option, const Target@ targ) const {}
};

RandomEvent@[] randomEvents;
uint optionId = 0;
dictionary idents;

const RandomEvent@ getRandomEvent(uint id) {
	if(id >= randomEvents.length)
		return null;
	return randomEvents[id];
}

const RandomEvent@ getRandomEvent(const string& ident) {
	RandomEvent@ camp;
	if(idents.get(ident, @camp))
		return camp;
	return null;
}

int getRandomEventID(const string& ident) {
	auto@ type = getRandomEvent(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getRandomEventIdent(int id) {
	auto@ type = getRandomEvent(id);
	if(type is null)
		return "";
	return type.ident;
}

uint getRandomEventCount() {
	return randomEvents.length;
}

void addRandomEvent(RandomEvent@ type) {
	type.id = randomEvents.length;
	randomEvents.insertLast(type);
	idents.set(type.ident, @type);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = randomEvents.length; i < cnt; ++i) {
		auto type = randomEvents[i];
		file.addIdentifier(SI_RandomEvent, type.id, type.ident);
		for(uint n = 0, ncnt = type.options.length; n < ncnt; ++n) {
			auto@ opt = type.options[n];
			file.addIdentifier(SI_RandomEventOption, opt.id, opt.ident);
		}
	}
}

void loadRandomEvents(const string& filename) {
	ReadFile file(filename, true);
	while(true) {
		if(file.key.equals_nocase("Event")) {
			if(!loadEvent(file))
				break;
		}
		else {
			if(!file++)
				break;
		}
	}
}

bool loadEvent(ReadFile@ file) {
	RandomEvent evt;
	evt.ident = file.value;
	addRandomEvent(evt);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		if(file.fullLine) {
			auto@ hook = cast<IRandomEventHook>(parseHook(file.line, "event_effects::", instantiate=false));
			if(hook !is null)
				evt.hooks.insertLast(hook);
			if(!file++)
				return false;
			if(file.indent <= blockIndent)
				return true;
		}
		else if(file.key.equals_nocase("Option")) {
			if(!loadOption(evt, file))
				return false;
		}
		else {
			if(file.key.equals_nocase("Name")) {
				evt.name = localize(file.value);
			}
			else if(file.key.equals_nocase("Text")) {
				evt.text = localize(file.value);
			}
			else if(file.key.equals_nocase("Frequency")) {
				evt.frequency = toDouble(file.value);
			}
			else if(file.key.equals_nocase("Unique")) {
				evt.unique = toBool(file.value);
			}
			else if(file.key.equals_nocase("Target")) {
				parseTarget(evt.targets, file.value);
			}
			else if(file.key.equals_nocase("Timer")) {
				evt.timer = toDouble(file.value);
			}
			else if(file.key.equals_nocase("Mode")) {
				if(file.value.equals_nocase("Random"))
					evt.mode = RTM_Random;
				else
					file.error("Unknown random event mode: "+file.value);
			}
			else {
				auto@ hook = cast<IRandomEventHook>(parseHook(file.line, "event_effects::", instantiate=false));
				if(hook !is null)
					evt.hooks.insertLast(hook);
			}
			if(!file++)
				return false;
		}
	}
	return true;
}

bool loadOption(RandomEvent@ evt, ReadFile@ file) {
	EventOption opt;
	opt.id = optionId++;
	if(file.value.length == 0)
		opt.ident = evt.ident+"::__"+evt.options.length;
	else
		opt.ident = evt.ident+"::"+file.value;
	evt.options.insertLast(opt);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		if(file.fullLine) {
			auto@ hook = cast<IRandomOptionHook>(parseHook(file.line, "event_effects::", instantiate=false));
			if(hook !is null)
				opt.result.block.hooks.insertLast(hook);
			if(!file++)
				return false;
		}
		else if(file.key.equals_nocase("Result")) {
			if(!loadResult(evt, opt, file))
				return false;
		}
		else if(file.key.equals_nocase("On")) {
			if(!loadOnBlock(evt, opt.result, file))
				return false;
		}
		else {
			if(file.key.equals_nocase("Text")) {
				opt.text = localize(file.value);
			}
			else if(file.key.equals_nocase("Icon")) {
				opt.icon = getSprite(file.value);
			}
			else if(file.key.equals_nocase("Default")) {
				opt.defaultOption = toBool(file.value);
			}
			else if(file.key.equals_nocase("Safe")) {
				opt.safe = toBool(file.value);
			}
			else {
				auto@ hook = cast<IRandomOptionHook>(parseHook(file.line, "event_effects::", instantiate=false));
				if(hook !is null)
					opt.result.block.hooks.insertLast(hook);
			}
			if(!file++)
				return false;
		}
	}
	return true;
}

bool loadResult(RandomEvent@ evt, EventOption@ opt, ReadFile@ file) {
	EventResult res;
	if(file.value.length != 0) {
		if(file.value[file.value.length-1] == '%')
			res.frequency = toDouble(file.value.substr(0, file.value.length-1)) / 100.0;
		else
			res.frequency = toDouble(file.value);
	}
	opt.inner.insertLast(res);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		if(file.fullLine) {
			auto@ hook = cast<IRandomOptionHook>(parseHook(file.line, "event_effects::", instantiate=false));
			if(hook !is null)
				res.block.hooks.insertLast(hook);
			if(!file++)
				return false;
		}
		else if(file.key.equals_nocase("On")) {
			if(!loadOnBlock(evt, res, file))
				return false;
		}
		else {
			{
				auto@ hook = cast<IRandomOptionHook>(parseHook(file.line, "event_effects::", instantiate=false));
				if(hook !is null)
					res.block.hooks.insertLast(hook);
			}
			if(!file++)
				return false;
		}
	}
	return true;
}

bool loadOnBlock(RandomEvent@ evt, EventResult@ res, ReadFile@ file) {
	OnBlock block;
	block.targetName = file.value;
	res.inner.insertLast(block);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		{
			auto@ hook = cast<IRandomOptionHook>(parseHook(file.line, "event_effects::", instantiate=false));
			if(hook !is null)
				block.hooks.insertLast(hook);
		}
		if(!file++)
			return false;
	}
	return true;
}

void preInit() {
	FileList list("data/random_events", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadRandomEvents(list.path[i]);
}

void init() {
	for(uint i = 0, cnt = randomEvents.length; i < cnt; ++i)
		randomEvents[i].init();
}
