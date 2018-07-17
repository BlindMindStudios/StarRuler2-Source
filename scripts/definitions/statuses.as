#priority init 2000
import hooks;
import saving;
import planet_types;
import resources;

export StatusType;
export Status;
export StatusInstance;
export getStatusType, getStatusTypeCount;
export getStatusID;
export getRandomCondition;
export StatusVisibility;

enum StatusVisibility {
	StV_Everybody,
	StV_Owner,
	StV_Origin,
	StV_OwnerAndOrigin,
	StV_Global,
	StV_Nobody,
};

tidy final class StatusType {
	uint id;
	string ident;
	string name;
	string description;
	Sprite icon;
	Color color;
	StatusVisibility visibility = StV_Everybody;

	bool unique = false;
	bool collapses = false;
	array<IStatusHook@> hooks;

	string def_conditionType;
	const PlanetType@ conditionType;
	uint conditionTier = 0;
	double conditionFrequency = 0.0;

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const {
		if(!obj.hasStatuses)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].shouldApply(emp, region, obj))
				return false;
		}
		return true;
	}
};

interface IStatusHook {
	void onCreate(Object& obj, Status@ status, any@ data);
	void onDestroy(Object& obj, Status@ status, any@ data);
	void onObjectDestroy(Object& obj, Status@ status, any@ data);
	bool onTick(Object& obj, Status@ status, any@ data, double time);
	void onAddStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data);
	void onRemoveStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data);
	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner);
	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion);
	void save(Status@ status, any@ data, SaveFile& file);
	void load(Status@ status, any@ data, SaveFile& file);

	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const;
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color) const;
};

class StatusHook : Hook, IStatusHook {
	void onCreate(Object& obj, Status@ status, any@ data) {}
	void onDestroy(Object& obj, Status@ status, any@ data) {}
	void onObjectDestroy(Object& obj, Status@ status, any@ data) {}
	bool onTick(Object& obj, Status@ status, any@ data, double time) { return true; }
	void onAddStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	void onRemoveStack(Object& obj, Status@ status, StatusInstance@ instance, any@ data) {}
	bool onOwnerChange(Object& obj, Status@ status, any@ data, Empire@ prevOwner, Empire@ newOwner) { return true; }
	bool onRegionChange(Object& obj, Status@ status, any@ data, Region@ prevRegion, Region@ newRegion) { return true; }
	void save(Status@ status, any@ data, SaveFile& file) {}
	void load(Status@ status, any@ data, SaveFile& file) {}
	bool shouldApply(Empire@ emp, Region@ region, Object@ obj) const { return true; }
	bool getVariable(Object@ obj, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
};

tidy final class Status : Serializable, Savable {
	const StatusType@ type;
	int stacks = 0;
	any[] data;
	Empire@ originEmpire;
	Object@ originObject;

	Status() {
	}

	Status(const StatusType@ type) {
		set(type);
	}

	string getTooltip(Object@ valueObject = null) const {
		string tt;

		string name = type.name;
		if(!type.unique && stacks > 1)
			name += format(" (x $1)", toString(stacks));
		tt = format("[font=Medium][color=$3]$1[/color][/font]\n$2",
			name, type.description, toString(type.color));

		string vname, vvalue;
		Sprite vicon;
		Color color;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].getVariable(valueObject, vicon, vname, vvalue, color)) {
				tt += format("[nl/]\n[img=$1;22][b][color=$4]$2[/color][/b] [offset=120]$3[/offset][/img]",
					getSpriteDesc(vicon), vname, vvalue, toString(color));
				color = colors::White;
			}
		}
		return tt;
	}

	bool isVisibleTo(Object& obj, Empire@ emp) const {
		if(emp is null || !emp.valid)
			return type.visibility == StV_Everybody;
		switch(type.visibility) {
			case StV_Everybody:
			case StV_Global:
				return true;
			case StV_Owner:
				return emp is obj.owner;
			case StV_Origin:
				return emp is originEmpire;
			case StV_OwnerAndOrigin:
				return emp is originEmpire || emp is obj.owner;
			case StV_Nobody:
				return false;
		}
		return false;
	}

	void set(const StatusType@ type) {
		@this.type = type;
		stacks = 0;
		data.length = type.hooks.length;
	}

	void write(Message& msg) {
		msg.writeSmall(type.id);
		msg.writeSmall(stacks);
		msg << originEmpire;
		msg << originObject;
	}

	void read(Message& msg) {
		@type = getStatusType(msg.readSmall());
		stacks = msg.readSmall();
		data.length = type.hooks.length;
		msg >> originEmpire;
		msg >> originObject;
	}

	void save(SaveFile& file) {
		file.writeIdentifier(SI_Status, type.id);
		file << stacks;
		file << originEmpire;
		file << originObject;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].save(this, data[i], file);
	}

	void load(SaveFile& file) {
		@type = getStatusType(file.readIdentifier(SI_Status));
		file >> stacks;
		if(file >= SV_0083) {
			file >> originEmpire;
			file >> originObject;
		}
		data.length = type.hooks.length;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].load(this, data[i], file);
	}

	void create(Object& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onCreate(obj, this, data[i]);
	}

	void destroy(Object& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onDestroy(obj, this, data[i]);
	}

	void objectDestroy(Object& obj) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onObjectDestroy(obj, this, data[i]);
	}

	StatusInstance@ instance(Object& obj) {
		StatusInstance inst;
		@inst.status = this;
		stacks += 1;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onAddStack(obj, this, inst, data[i]);
		return inst;
	}

	void remove(Object& obj, StatusInstance@ inst) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onRemoveStack(obj, this, inst, data[i]);
		stacks -= 1;
	}

	bool tick(Object& obj, double time) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].onTick(obj, this, data[i], time))
				return false;
		}
		return true;
	}

	bool ownerChange(Object& obj, Empire@ prevOwner, Empire@ newOwner) {
		bool keep = true;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].onOwnerChange(obj, this, data[i], prevOwner, newOwner))
				keep = false;
		}
		return keep;
	}

	bool regionChange(Object& obj, Region@ prevRegion, Region@ newRegion) {
		bool keep = true;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].onRegionChange(obj, this, data[i], prevRegion, newRegion))
				keep = false;
		}
		return keep;
	}
};

tidy final class StatusInstance : Savable {
	Status@ status;
	int id = -1;
	double timer = -1.0;
	Region@ boundRegion;
	Empire@ boundEmpire;

	void remove(Object& obj) {
		status.remove(obj, this);
	}

	bool tick(Object& obj, double time) {
		if(timer >= 0) {
			timer -= time;
			if(timer <= 0) {
				status.remove(obj, this);
				return false;
			}
		}
		return true;
	}

	void save(SaveFile& file) {
		file << id;
		file << timer;
		file << boundRegion;
		file << boundEmpire;
	}

	void load(SaveFile& file) {
		file >> id;
		file >> timer;
		file >> boundRegion;
		file >> boundEmpire;
	}
};

array<StatusType@> statusTypes;
dictionary statusIdents;

int getStatusID(const string& ident) {
	auto@ type = getStatusType(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getStatusIdent(int id) {
	auto@ type = getStatusType(id);
	if(type is null)
		return "";
	return type.ident;
}

const StatusType@ getStatusType(uint id) {
	if(id >= statusTypes.length)
		return null;
	return statusTypes[id];
}

const StatusType@ getStatusType(const string& ident) {
	StatusType@ def;
	if(statusIdents.get(ident, @def))
		return def;
	return null;
}

uint getStatusTypeCount() {
	return statusTypes.length;
}

const StatusType@ getRandomCondition(Planet& planet) {
	double roll = randomd();
	double freq = 0.0;
	const StatusType@ result;
	for(uint i = 0, cnt = statusTypes.length; i < cnt; ++i) {
		auto@ status = statusTypes[i];
		if(status.conditionFrequency <= 0)
			continue;
		if(status.conditionType !is null) {
			if(planet.PlanetType != status.conditionType.id)
				continue;
		}
		if(status.conditionTier != 0) {
			auto@ type = getResource(planet.primaryResourceType);
			if(type is null || type.level < status.conditionTier)
				continue;
		}
		if(!status.shouldApply(planet.owner, planet.region, planet))
			continue;

		freq += status.conditionFrequency;

		double chance = status.conditionFrequency / freq;
		if(roll < chance) {
			@result = status;
			roll /= chance;
		}
		else {
			roll = (roll - chance) / (1.0 - chance);
		}
	}
	return result;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = statusTypes.length; i < cnt; ++i) {
		auto type = statusTypes[i];
		file.addIdentifier(SI_Status, type.id, type.ident);
	}
}

void addStatus(StatusType@ type) {
	type.id = statusTypes.length;
	statusTypes.insertLast(type);
	statusIdents.set(type.ident, @type);
}

void parseLine(string& line, StatusType@ type, ReadFile@ file) {
	auto@ hook = cast<IStatusHook>(parseHook(line, "status_effects::", instantiate=false, file=file));
	if(hook !is null)
		type.hooks.insertLast(hook);
}

void loadStatus(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	StatusType@ status;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			string line = file.line;
			parseLine(line, status, file);
		}
		else if(key.equals_nocase("Status")) {
			if(status !is null)
				addStatus(status);
			@status = StatusType();
			status.ident = value;
		}
		else if(status is null) {
			file.error("Missing status ID' line");
		}
		else if(key.equals_nocase("Name")) {
			status.name = localize(value);
		}
		else if(key.equals_nocase("Description")) {
			status.description = localize(value);
		}
		else if(key.equals_nocase("Icon")) {
			status.icon = getSprite(value);
		}
		else if(key.equals_nocase("Color")) {
			status.color = toColor(value);
		}
		else if(key.equals_nocase("Condition Frequency")) {
			status.conditionFrequency = toDouble(value);
		}
		else if(key.equals_nocase("Condition Tier")) {
			status.conditionTier = toUInt(value);
		}
		else if(key.equals_nocase("Condition Type")) {
			status.def_conditionType = value;
		}
		else if(key.equals_nocase("Unique")) {
			status.unique = toBool(value);
			if(status.unique)
				status.collapses = true;
		}
		else if(key.equals_nocase("Collapses")) {
			status.collapses = toBool(value);
		}
		else if(key.equals_nocase("Visible To")) {
			if(value.equals_nocase("everybody"))
				status.visibility = StV_Everybody;
			else if(value.equals_nocase("owner"))
				status.visibility = StV_Owner;
			else if(value.equals_nocase("origin empire"))
				status.visibility = StV_Origin;
			else if(value.equals_nocase("owner and origin empire"))
				status.visibility = StV_OwnerAndOrigin;
			else if(value.equals_nocase("nobody"))
				status.visibility = StV_Nobody;
			else if(value.equals_nocase("global"))
				status.visibility = StV_Global;
			else
				file.error("Unknown status visibility: "+value);
		}
		else {
			string line = file.line;
			parseLine(line, status, file);
		}
	}
	
	if(status !is null)
		addStatus(status);
}

void preInit() {
	FileList list("data/statuses", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadStatus(list.path[i]);
}

void init() {
	auto@ list = statusTypes;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
		if(type.def_conditionType.length != 0) {
			@type.conditionType = getPlanetType(type.def_conditionType);
			if(type.conditionType is null)
				error("Error in Status "+type.ident+": could not find planet type "+type.def_conditionType);
		}
	}
}
