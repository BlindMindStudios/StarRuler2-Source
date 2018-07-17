#priority init 1550
import hooks;
import settings.map_lib;

export SystemType, SystemUniqueness;
export getSystemType, getSystemTypeCount;
export getDistributedSystemType;

enum SystemUniqueness {
	SU_NonUnique,
	SU_Galaxy,
	SU_Global,
};

tidy final class SystemType {
	uint id;
	string ident;

	SystemUniqueness unique = SU_NonUnique;
	double frequency = 0;
	array<Hook@> hooks;

	array<string> baseNames;
	array<const SystemType@> bases;

	void generate(SystemData@ data, SystemDesc@ system) const {
		Object@ current;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			auto@ hook = cast<IMapHook@>(hooks[i]);
			if(hook !is null)
				hook.trigger(data, system, current);
		}
		for(uint i = 0, cnt = bases.length; i < cnt; ++i)
			bases[i].generate(data, system);
	}

	void postGenerate(SystemData@ data, SystemDesc@ system) const {
		Object@ current;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			auto@ hook = cast<IMapHook@>(hooks[i]);
			if(hook !is null)
				hook.postTrigger(data, system, current);
		}
		for(uint i = 0, cnt = bases.length; i < cnt; ++i)
			bases[i].postGenerate(data, system);
	}
};

interface IMapHook {
	void trigger(SystemData@ data, SystemDesc@ system, Object@& current) const;
	void postTrigger(SystemData@ data, SystemDesc@ system, Object@& current) const;
};

class MapHook : IMapHook, Hook {
	void trigger(SystemData@ data, SystemDesc@ system, Object@& current) const {}
	void postTrigger(SystemData@ data, SystemDesc@ system, Object@& current) const {}
};

void parseLine(int indent, const string& line, SystemType@ type) {
	auto@ hook = cast<IMapHook@>(parseHook(type.hooks, indent, line, "map_effects::"));
	if(hook is null && !isScriptDebug)
		error(" Invalid map hook: "+escape(line));
}

void loadSystems(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	SystemType@ type;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			if(type is null) {
				error("Missing 'System: ID' line in " + filename);
				continue;
			}

			string line = file.line;
			parseLine(file.indent, line, type);
		}
		else if(key == "System") {
			if(type !is null)
				addSystemType(type);
			@type = SystemType();
			type.ident = value;
		}
		else if(type is null) {
			error("Missing 'System: ID' line in " + filename);
		}
		else if(key == "Frequency") {
			type.frequency = toDouble(value);
			if(type.unique != SU_NonUnique)
				type.frequency *= config::UNIQUE_SYSTEM_OCCURANCE / 0.3;
		}
		else if(key == "Inherit") {
			type.baseNames.insertLast(value);
		}
		else if(key == "Unique") {
			if(value.equals_nocase("global"))
				type.unique = SU_Global;
			else if(value.equals_nocase("galaxy"))
				type.unique = SU_Galaxy;
			else
				error("Error: Unknown system uniqueness: "+value);
			type.frequency *= config::UNIQUE_SYSTEM_OCCURANCE / 0.3;
		}
		else {
			string line = file.line;
			parseLine(file.indent, line, type);
		}
	}
	
	if(type !is null)
		addSystemType(type);
}

void init() {
	FileList list("data/systems", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadSystems(list.path[i]);

	for(uint i = 0, cnt = systemTypes.length; i < cnt; ++i) {
		SystemType@ type = systemTypes[i];
		for(uint n = 0, ncnt = type.baseNames.length; n < ncnt; ++n) {
			const SystemType@ base = getSystemType(type.baseNames[n]);
			if(base !is null)
				type.bases.insertLast(base);
			else
				error(" Error: Base system type not found: "+type.baseNames[n]);
		}
	}
}

SystemType@[] systemTypes;
dictionary idents;
double totalFrequency = 0;

const SystemType@ getSystemType(uint id) {
	if(id >= systemTypes.length)
		return null;
	return systemTypes[id];
}

const SystemType@ getSystemType(const string& ident) {
	SystemType@ anomaly;
	if(idents.get(ident, @anomaly))
		return anomaly;
	return null;
}

uint getSystemTypeCount() {
	return systemTypes.length;
}

const SystemType@ getDistributedSystemType() {
	uint count = systemTypes.length;
	double num = randomd(0, totalFrequency);
	for(uint i = 0, cnt = systemTypes.length; i < cnt; ++i) {
		const SystemType@ type = systemTypes[i];
		double freq = type.frequency;
		if(num <= freq)
			return type;
		num -= freq;
	}
	return systemTypes[systemTypes.length-1];
}

void addSystemType(SystemType@ type) {
	type.id = systemTypes.length;
	systemTypes.insertLast(type);
	idents.set(type.ident, @type);
	totalFrequency += type.frequency;
}
