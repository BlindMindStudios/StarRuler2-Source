#priority init 2000
import hooks;
import saving;
import abilities;

export AttitudeLevel, AttitudeType, Attitude;
export getAttitudeID, getAttitudeIdent, getAttitudeType;
export getAttitudeTypeCount;

#section server
from achievements import giveAchievement;
#section all

interface IAttitudeHook {
	Ability@ showAbility(Attitude& att, Empire& emp, Ability@ abl) const;
	bool canTake(Empire& emp) const;

	void enable(Attitude& att, Empire& emp, any@ data) const;
	void disable(Attitude& att, Empire& emp, any@ data) const;
	void tick(Attitude& att, Empire& emp, any@ data, double time) const;

	void save(any@ data, SaveFile& file) const;
	void load(any@ data, SaveFile& file) const;
};

class AttitudeHook : Hook, IAttitudeHook {
	Ability@ showAbility(Attitude& att, Empire& emp, Ability@ abl) const { return null; }
	bool canTake(Empire& emp) const { return true; }

	void enable(Attitude& att, Empire& emp, any@ data) const {}
	void disable(Attitude& att, Empire& emp, any@ data) const {}
	void tick(Attitude& att, Empire& emp, any@ data, double time) const {}

	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}
};

tidy class AttitudeLevel {
	uint level = 0;
	Sprite icon;
	string description;
	double threshold = 0;
	array<IAttitudeHook@> hooks;
};

tidy class AttitudeAction {
	string name;
	string description;
	Color color;
	Sprite icon;

	array<IAttitudeHook@> hooks;
};

tidy class AttitudeType {
	uint id;
	string ident;
	string name;
	string description;
	string progress;
	Color color;
	int sort = 0;

	array<IAttitudeHook@> hooks;
	array<AttitudeLevel@> levels;

	bool canTake(Empire& emp) const {
		if(emp.hasAttitude(id))
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canTake(emp))
				return false;
		}
		return true;
	}

	int opCmp(const AttitudeType@ other) const {
		if(other is null)
			return -1;
		if(other.sort < sort)
			return 1;
		if(other.sort > sort)
			return -1;
		return 0;
	}
};

tidy class Attitude : Serializable, Savable {
	const AttitudeType@ type;
	double progress = 0.0;
	uint level = 0;
	array<any> data;
	bool delta = true;

	int getDiscardCost(Empire& emp) {
		return config::ATTITUDE_DISCARD_COST + config::ATTITUDE_DISCARD_LEVEL_COST * level;
	}

	int get_nextLevel() {
		return clamp(level+1, 0, type.levels.length);
	}

	int get_prevLevel() {
		return clamp(int(level)-1, 0, int(type.levels.length));
	}

	int get_maxLevel() {
		return type.levels.length;
	}

	uint get_allHookCount() {
		uint hookCnt = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n < type.levels.length)
				hookCnt += type.levels[n].hooks.length;
		}
		return hookCnt;
	}

	const IAttitudeHook@ get_allHooks(uint index) {
		if(index < type.hooks.length)
			return type.hooks[index];
		index -= type.hooks.length;

		for(uint n = 0; n < level; ++n) {
			if(n < type.levels.length) {
				if(index < type.levels[n].hooks.length)
					return type.levels[n].hooks[index];
				index -= type.levels[n].hooks.length;
			}
		}
		return null;
	}

	const AttitudeLevel@ get_levels(uint level) {
		if(level == 0)
			return null;
		return type.levels[clamp(int(level)-1, 0, int(type.levels.length)-1)];
	}

	void write(Message& msg) {
		msg.writeLimited(type.id, getAttitudeTypeCount());
		msg << float(progress);
		msg.writeSmall(level);
	}

	void read(Message& msg) {
		@type = getAttitudeType(msg.readLimited(getAttitudeTypeCount()));
		progress = msg.read_float();
		level = msg.readSmall();
	}

	void save(SaveFile& file) {
		file.writeIdentifier(SI_AttitudeType, type.id);
		file << progress;
		file << level;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].save(data[i], file);

		uint h = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n >= type.levels.length)
				continue;
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].save(data[h+i], file);
			h += type.levels[n].hooks.length;
		}
	}

	void load(SaveFile& file) {
		@type = getAttitudeType(file.readIdentifier(SI_AttitudeType));
		file >> progress;
		file >> level;

		uint hookCnt = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n < type.levels.length)
				hookCnt += type.levels[n].hooks.length;
		}
		data.length = hookCnt;

		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].load(data[i], file);

		uint h = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n >= type.levels.length)
				continue;
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].load(data[h+i], file);
			h += type.levels[n].hooks.length;
		}
	}

#section server
	void start(Empire& emp) {
		//Start the attitude in the empire
		data.length = type.hooks.length;
		level = 0;
		progress = 0.0;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].enable(this, emp, data[i]);
	}

	void tick(Empire& emp, double time) {
		double prevProgress = progress;

		//Tick all the base hooks
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].tick(this, emp, data[i], time);

		//Tick all the levels we currently have
		uint h = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n >= type.levels.length)
				continue;
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].tick(this, emp, data[h+i], time);
			h += type.levels[n].hooks.length;
		}

		//Make sure we have the appropriate levels according to progress
		if(prevProgress != progress) {
			checkProgress(emp);
			delta = true;
		}
	}

	void checkProgress(Empire& emp) {
		uint getLevel = 0;
		for(uint i = 0, cnt = type.levels.length; i < cnt; ++i) {
			if(type.levels[i].threshold <= progress)
				getLevel += 1;
			else
				break;
		}

		changeLevel(emp, getLevel);
	}

	void changeLevel(Empire& emp, uint newLevel) {
		if(level == newLevel)
			return;

		//Disable old levels
		uint h = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n >= type.levels.length)
				continue;
			if(n < newLevel) {
				h += type.levels[n].hooks.length;
				continue;
			}
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].disable(this, emp, data[h+i]);
			h += type.levels[n].hooks.length;
		}

		//Change amount of data we have stored
		uint hookCnt = type.hooks.length;
		for(uint n = 0; n < newLevel; ++n) {
			if(n < type.levels.length)
				hookCnt += type.levels[n].hooks.length;
		}
		data.length = hookCnt;

		//Set level
		uint prevLevel = level;
		level = newLevel;
		delta = true;

		//Enable new levels
		h = type.hooks.length;
		for(uint n = 0; n < newLevel; ++n) {
			if(n >= type.levels.length)
				continue;
			if(n < prevLevel) {
				h += type.levels[n].hooks.length;
				continue;
			}
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].enable(this, emp, data[h+i]);
			h += type.levels[n].hooks.length;
		}

		if(level == 5) {
			if(emp.getLevelAttitudeCount(5) >= 3)
				giveAchievement(emp, "ACH_ATTIDS");
		}
	}

	void end(Empire& emp) {
		//Disable base hooks
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].disable(this, emp, data[i]);

		//Disable any levels we have
		uint h = type.hooks.length;
		for(uint n = 0; n < level; ++n) {
			if(n >= type.levels.length)
				continue;
			for(uint i = 0, cnt = type.levels[n].hooks.length; i < cnt; ++i)
				type.levels[n].hooks[i].disable(this, emp, data[h+i]);
			h += type.levels[n].hooks.length;
		}
	}
#section all
};

array<AttitudeType@> attitudeTypes;
dictionary attitudeIdents;

int getAttitudeID(const string& ident) {
	auto@ type = getAttitudeType(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getAttitudeIdent(int id) {
	auto@ type = getAttitudeType(id);
	if(type is null)
		return "";
	return type.ident;
}

const AttitudeType@ getAttitudeType(uint id) {
	if(id >= attitudeTypes.length)
		return null;
	return attitudeTypes[id];
}

const AttitudeType@ getAttitudeType(const string& ident) {
	AttitudeType@ def;
	if(attitudeIdents.get(ident, @def))
		return def;
	return null;
}

uint getAttitudeTypeCount() {
	return attitudeTypes.length;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = attitudeTypes.length; i < cnt; ++i) {
		auto type = attitudeTypes[i];
		file.addIdentifier(SI_AttitudeType, type.id, type.ident);
	}
}

void addAttitude(AttitudeType@ type) {
	type.id = attitudeTypes.length;
	attitudeTypes.insertLast(type);
	attitudeIdents.set(type.ident, @type);
}

void parseLine(string& line, AttitudeType@ type, ReadFile@ file) {
	auto@ hook = cast<IAttitudeHook>(parseHook(line, "attitude_effects::", instantiate=false, file=file));
	if(hook !is null)
		type.hooks.insertLast(hook);
}

void loadAttitudes(const string& filename) {
	ReadFile file(filename, true);
	while(true) {
		if(file.key.equals_nocase("Attitude")) {
			if(!loadAttitude(file))
				break;
		}
		else {
			if(!file++)
				break;
		}
	}
}

bool loadAttitude(ReadFile@ file) {
	AttitudeType att;
	att.ident = file.value;
	addAttitude(att);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		if(file.fullLine) {
			auto@ hook = cast<IAttitudeHook>(parseHook(file.line, "attitude_effects::", instantiate=false));
			if(hook !is null)
				att.hooks.insertLast(hook);
			if(!file++)
				return false;
			if(file.indent <= blockIndent)
				return true;
		}
		else if(file.key.equals_nocase("Level")) {
			if(!loadLevel(att, file))
				return false;
		}
		else {
			if(file.key.equals_nocase("Name")) {
				att.name = localize(file.value);
			}
			else if(file.key.equals_nocase("Description")) {
				att.description = localize(file.value);
			}
			else if(file.key.equals_nocase("Progress")) {
				att.progress = localize(file.value);
			}
			else if(file.key.equals_nocase("Color")) {
				att.color = toColor(file.value);
			}
			else if(file.key.equals_nocase("Sort")) {
				att.sort = toInt(file.value);
			}
			else {
				auto@ hook = cast<IAttitudeHook>(parseHook(file.line, "attitude_effects::", instantiate=false));
				if(hook !is null)
					att.hooks.insertLast(hook);
			}
			if(!file++)
				return false;
		}
	}
	return true;
}

bool loadLevel(AttitudeType@ att, ReadFile@ file) {
	AttitudeLevel lv;
	lv.level = att.levels.length;

	att.levels.insertLast(lv);

	int blockIndent = file.indent;
	if(!file++)
		return false;

	while(true) {
		if(file.indent <= blockIndent)
			return true;
		if(file.fullLine) {
			auto@ hook = cast<IAttitudeHook>(parseHook(file.line, "attitude_effects::", instantiate=false));
			if(hook !is null)
				lv.hooks.insertLast(hook);
			if(!file++)
				return false;
		}
		else {
			if(file.key.equals_nocase("Description")) {
				lv.description = localize(file.value);
			}
			else if(file.key.equals_nocase("Threshold")) {
				lv.threshold = toDouble(file.value);
			}
			else if(file.key.equals_nocase("Icon")) {
				lv.icon = getSprite(file.value);
			}
			else {
				auto@ hook = cast<IAttitudeHook>(parseHook(file.line, "attitude_effects::", instantiate=false));
				if(hook !is null)
					lv.hooks.insertLast(hook);
			}
			if(!file++)
				return false;
		}
	}
	return true;
}

void preInit() {
	FileList list("data/attitudes", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadAttitudes(list.path[i]);
}

void init() {
	auto@ list = attitudeTypes;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
		for(uint j = 0, jcnt = type.levels.length; j < jcnt; ++j) {
			for(uint n = 0, ncnt = type.levels[j].hooks.length; n < ncnt; ++n)
				if(!cast<Hook>(type.levels[j].hooks[n]).instantiate())
					error("Could not instantiate hook: "+addrstr(type.levels[j].hooks[n])+" in "+type.ident+" level "+j);
		}
	}
}
