#priority init 10000
import saving;

/*enum PresetStats {
};*/

const array<string> preset_stats = {};

string getObjectStatMode(int id) {
	switch(id)
	{
		case OSM_Set: return "Set";
		case OSM_Add: return "Add";
		case OSM_Multiply: return "Multiply";
	}
	return "Set";
}

int getObjectStatMode(const string& ident) {
	if(ident.equals_nocase("set"))
		return OSM_Set;
	if(ident.equals_nocase("add"))
		return OSM_Add;
	if(ident.equals_nocase("multiply"))
		return OSM_Multiply;
	return OSM_Set;
}

#section client
int getObjectStatId(const string& ident, bool create = true) {
	return getObjectStat_client(ident);
}

string getObjectStatIdent(int id) {
	return getObjectStatIdent_client(id);
}

#section server-side
const double OBJECT_STAT_SYNC_RESOLUTION = 0.01;

tidy class ObjectStatType {
	int id;
	string ident;
	bool isInt = false;
	bool shouldSync = true;

	ObjectStatType(const string& name)
	{
		ident = name;
		isInt = name.contains("#");
		shouldSync = !name.contains("&");
	}

	uint64 key(Empire@ forEmpire) const {
		return OBJ_STAT_MASK | uint64(forEmpire.id) << 32 | uint64(id);
	}

	void mod(Object@ obj, Empire@ emp, int mode, double value) const {
		if(isInt) {
			int dirtyResolution = 0;
			if(!shouldSync)
				dirtyResolution = -1;
			obj.modStatInt(key(emp), ObjectStatMode(mode), int(value), dirtyResolution);
		}
		else {
			double dirtyResolution = OBJECT_STAT_SYNC_RESOLUTION;
			if(!shouldSync)
				dirtyResolution = -1.0;
			obj.modStatDouble(key(emp), ObjectStatMode(mode), int64(value), dirtyResolution);
		}
	}

	void reverse(Object@ obj, Empire@ emp, int mode, double value) const {
		switch(mode) {
			case OSM_Set:
				throw("Cannot reverse a stat modified with Set mode.");
			return;
			case OSM_Multiply:
				if(value == 0.0) {
					throw("Cannot reverse a stat multiplied by 0.");
					return;
				}
				value = 1.0 / value;
			break;
			case OSM_Add:
				value *= -1.0;
			break;
		}

		mod(obj, emp, mode, value);
	}
};

array<ObjectStatType@> objectStats;
dictionary objectStatIdents;

void preInit() {
	for(uint i = 0, cnt = preset_stats.length; i < cnt; ++i)
		getObjectStat(preset_stats[i], create=true);
}

uint getObjectStatCount() {
	return objectStats.length;
}

const ObjectStatType@ getObjectStat(int id) {
	if(id < 0 || uint(id) >= objectStats.length)
		return null;
	return objectStats[id];
}

const ObjectStatType@ getObjectStat(const string& ident, bool create = true) {
	int id = -1;
	if(!objectStatIdents.get(ident, id)) {
		if(create) {
			id = int(objectStats.length);
			ObjectStatType stat(ident);
			stat.id = id;
			objectStats.insertLast(stat);
			objectStatIdents.set(ident, id);
			return stat;
		}
		else {
			return null;
		}
	}
	return objectStats[id];
}

int getObjectStatId(const string& ident, bool create = true) {
	auto@ stat = getObjectStat(ident, create);
	if(stat is null)
		return -1;
	else
		return stat.id;
}

int getObjectStatId_client(string ident) {
	int id = -1;
	if(objectStatIdents.get(ident, id))
		return id;
	return -1;
}

string getObjectStatIdent(int id) {
	if(id < 0 || uint(id) >= objectStats.length)
		return "";
	return objectStats[id].ident;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = objectStats.length; i < cnt; ++i)
		file.addIdentifier(SI_ObjectStat, int(i), objectStats[i].ident);
}
