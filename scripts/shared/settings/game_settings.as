import traits;
import saving;

enum EmpireType {
	ET_Player,
	ET_BumAI,
	ET_WeaselAI,
	ET_NoAI,
};

enum AIFlags {
	AIF_Aggressive = 0x1,
	AIF_Passive = 0x2,
	AIF_Biased = 0x4,

	AIF_CheatPrivileged = 0x1000,
};

const string DEFAULT_SHIPSET = "Volkur";
const int STARTING_TRAIT_POINTS = 1;

class EmpireSettings : Serializable {
	uint index = 0;
	uint type;
	string name;
	string raceName;
	string shipset;
	string effectorSkin;
	bool ready = false;
	int handicap = 0;
	int playerId = -1;
	string portrait;
	string flag;
	Color color;
	array<const Trait@> traits;
	int delta = 0;
	int difficulty = 1;
	int team = -1;

	int aiFlags = 0;
	int cheatWealth = 0;
	int cheatStrength = 0;
	int cheatAbundance = 0;

	EmpireSettings() {
		type = ET_WeaselAI;
		name = "Unknown Empire";

		for(uint i = 0, cnt = getTraitCount(); i < cnt; ++i) {
			auto@ trait = getTrait(i);
			if(trait.defaultTrait)
				traits.insertLast(trait);
		}
	}

	bool hasTrait(const Trait@ trait) {
		return traits.find(trait) != -1;
	}

	void addTrait(const Trait@ trait) {
		if(trait is null)
			return;
		if(traits.find(trait) == -1)
			traits.insertLast(trait);
	}

	void removeTrait(const Trait@ trait) {
		traits.remove(trait);
	}

	void chooseTrait(const Trait@ trait) {
		if(trait is null)
			return;
		for(int i = traits.length - 1; i >= 0; --i) {
			if(traits[i].unique == trait.unique)
				traits.removeAt(i);
		}
		traits.insertLast(trait);
	}

	void resetTraits() {
		traits.length = 0;
		for(uint i = 0, cnt = getTraitCount(); i < cnt; ++i) {
			auto@ trait = getTrait(i);
			if(trait.defaultTrait)
				traits.insertLast(trait);
		}
	}

	void read(Message& msg) {
		msg >> index;
		msg >> name;
		msg >> raceName;
		msg >> shipset;
		msg >> color;
		msg >> portrait;
		msg >> flag;
		msg >> type;
		msg >> handicap;
		msg >> playerId;
		msg >> ready;
		msg >> delta;
		msg >> difficulty;
		msg >> effectorSkin;
		msg >> team;

		msg >> aiFlags;
		msg >> cheatWealth;
		msg >> cheatStrength;
		msg >> cheatAbundance;

		uint cnt = 0;
		msg >> cnt;
		traits.length = 0;
		traits.reserve(cnt);
		for(uint i = 0; i < cnt; ++i) {
			auto@ trait = getTrait(msg.readSmall());
			if(trait !is null)
				traits.insertLast(trait);
		}
	}

	void write(Message& msg) {
		msg << index;
		msg << name;
		msg << raceName;
		msg << shipset;
		msg << color;
		msg << portrait;
		msg << flag;
		msg << type;
		msg << handicap;
		msg << playerId;
		msg << ready;
		msg << delta;
		msg << difficulty;
		msg << effectorSkin;
		msg << team;

		msg << aiFlags;
		msg << cheatWealth;
		msg << cheatStrength;
		msg << cheatAbundance;

		msg << traits.length;
		for(uint i = 0, cnt = traits.length; i < cnt; ++i)
			msg.writeSmall(traits[i].id);
	}

	int getTraitPoints() {
		int points = STARTING_TRAIT_POINTS;
		for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
			points += traits[i].gives;
			points -= traits[i].cost;
		}
		return points;
	}

	bool hasTraitConflicts() {
		for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
			if(traits[i].hasConflicts(traits))
				return true;
		}
		return false;
	}

	void copyRaceFrom(const EmpireSettings& other) {
		raceName = other.raceName;
		shipset = other.shipset;
		portrait = other.portrait;
		traits = other.traits;
		effectorSkin = other.effectorSkin;
	}
};

class SettingsContainer : Savable {
	double[] settings;

	double get_opIndex(uint index) {
		//Dynamically allocate for map settings, since
		//we don't know how many there will be here
		if(index >= settings.length) {
			uint oldcnt = settings.length;
			settings.length = index+1;
			for(uint i = oldcnt; i <= index; ++i)
				settings[i] = INFINITY;
		}

		return settings[index];
	}

	void set_opIndex(uint index, double val) {
		//Dynamically allocate for map settings, since
		//we don't know how many there will be here
		if(index >= settings.length) {
			uint oldcnt = settings.length;
			settings.length = index+1;
			for(uint i = oldcnt; i <= index; ++i)
				settings[i] = INFINITY;
		}

		settings[index] = val;
	}

	double getSetting(uint index, double def = 0.0) {
		if(index >= settings.length)
			return def;
		double val = settings[index];
		if(val == INFINITY)
			return def;
		return val;
	}

	void setNamed(const string& name, double value) {
	}

	double getNamed(const string& name, double defaultValue = INFINITY) {
		return defaultValue;
	}

	void clearNamed(const string& name) {
	}

	void save(SaveFile& file) {
		uint cnt = settings.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << settings[i];
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		settings.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> settings[i];
	}
}

class MapSettings : SettingsContainer, Serializable {
	string map_id;
	GameSettings@ parent;
	uint galaxyCount = 1;
	bool allowHomeworlds = true;

	void read(Message& msg) {
		//Read global settings
		msg >> map_id;
		msg >> galaxyCount;
		msg >> allowHomeworlds;

		//Read global settings
		uint setcnt = 0;
		msg >> setcnt;
		settings.length = setcnt;
		for(uint i = 0; i < setcnt; ++i)
			msg >> settings[i];
	}

	uint get_systemCount() {
		if(settings.length == 0)
			return 0;
		return getSetting(0, 0.0);
	}

	void write(Message& msg) {
		//Write global settings
		msg << map_id;
		msg << galaxyCount;
		msg << allowHomeworlds;

		//Write global settings
		uint setcnt = settings.length;
		msg << setcnt;
		for(uint i = 0; i < setcnt; ++i)
			msg << settings[i];
	}

	void setNamed(const string& name, double value) {
		parent.setNamed(name, value);
	}
};

class GameSettings : SettingsContainer, Serializable {
	string map_id;
	EmpireSettings[] empires;
	MapSettings[] galaxies;
	dictionary namedSettings;

	GameSettings() {
	}

	void defaults() {
		empires.length = 3;
		empires[0].type = ET_Player;
		empires[0].name = "Empire 1";
		empires[0].raceName = "The First";
		//empires[0].chooseTrait(getTrait("Flux"));
		//empires[0].chooseTrait(getTrait("Empire"));
		empires[1].name = "Empire 2";
		empires[1].effectorSkin = "Skin1";
		empires[1].shipset = "Gevron";
		empires[1].raceName = "Terrakin";
		empires[1].difficulty = 2;
		empires[2].name = "Empire 3";
		empires[2].effectorSkin = "Skin2";
		empires[2].raceName = "Terrakin";
		empires[2].difficulty = 2;

		//empires[0].chooseTrait(getTrait("Ancient"));
		//empires[0].chooseTrait(getTrait("Sublight"));
		//empires[0].chooseTrait(getTrait("Extragalactic"));
		//empires[0].chooseTrait(getTrait("Gate"));
		//empires[0].chooseTrait(getTrait("Jumpdrive"));
		//empires[0].chooseTrait(getTrait("Sublight"));
		//empires[1].chooseTrait(getTrait("Extragalactic"));
		//empires[2].chooseTrait(getTrait("Extragalactic"));

		/*empires[1].aiFlags = AIF_CheatPrivileged;*/
		/*empires[2].aiFlags = AIF_CheatPrivileged;*/

		galaxies.length = 1;
		//galaxies[0].map_id = "Invasion.InvasionMap";
		galaxies[0].map_id = "Clusters.ClustersMap";
		//galaxies[0].map_id = "Expanse.ExpanseMap";
		//galaxies[0].map_id = "Rings.RingsMap";
		galaxies[0].galaxyCount = 1;
		//galaxies[0][0] = 40;

		settings.length = 0;
		namedSettings.deleteAll();
	}

	void setNamed(const string& name, double value) {
		namedSettings.set(name, value);
	}

	double getNamed(const string& name, double defaultValue = INFINITY) {
		double value = defaultValue;
		if(!namedSettings.get(name, value))
			value = defaultValue;
		return value;
	}

	void clearNamed(const string& name) {
		namedSettings.delete(name);
	}

	void read(Message& msg) {
		if(msg.empty) {
			defaults();
			return;
		}

		//Read named settings
		uint cnt = msg.readSmall();
		namedSettings.deleteAll();
		string name; float value = 0.f;
		for(uint i = 0; i < cnt; ++i) {
			msg >> name;
			msg >> value;

			namedSettings.set(name, double(value));
		}

		//Read empire settings
		uint empcnt = 0;
		msg >> empcnt;
		empires.length = empcnt;
		for(uint i = 0; i < empcnt; ++i)
			empires[i].read(msg);

		//Read galaxy settings
		uint galaxycnt = 0;
		msg >> galaxycnt;
		galaxies.length = galaxycnt;
		for(uint i = 0; i < galaxycnt; ++i)
			galaxies[i].read(msg);

		//Read global settings
		uint setcnt = 0;
		msg >> setcnt;
		settings.length = setcnt;
		for(uint i = 0; i < setcnt; ++i)
			msg >> settings[i];
	}

	void write(Message& msg) {
		//Write named settings
		auto it = namedSettings.iterator();
		string name; double value = 0.0;
		msg.writeSmall(namedSettings.getSize());
		while(it.iterate(name, value)) {
			msg << name;
			msg << float(value);
		}

		//Read empire settings
		uint empcnt = empires.length;
		msg << empcnt;
		for(uint i = 0; i < empcnt; ++i)
			empires[i].write(msg);

		//Read galaxy settings
		uint galaxycnt = galaxies.length;
		msg << galaxycnt;
		for(uint i = 0; i < galaxycnt; ++i)
			galaxies[i].write(msg);

		//Write global settings
		uint setcnt = settings.length;
		msg << setcnt;
		for(uint i = 0; i < setcnt; ++i)
			msg << settings[i];
	}
};

GameSettings settings;

GameSettings@ get_gameSettings() {
	return settings;
}

double getGameSetting(uint index) {
	return settings.getSetting(index, 0.0);
}

double getGameSetting(uint index, double def) {
	return settings.getSetting(index, def);
}

double modSpacing(double spacing) {
	return (spacing - 2000.0) * config::SYSTEM_SIZE * config::PLANET_FREQUENCY + 2000.0;
}

void onGameSettings(Message& msg) {
	initTraits();
	settings.read(msg);

	auto it = settings.namedSettings.iterator();
	string name; double value = 0.0;
	while(it.iterate(name, value))
		config::set(name, value);

	config::GFX_DISTANCE_MOD = 6500.0 / modSpacing(6500.0);

	if(!hasDLC("Heralds"))
		config::EXPERIENCE_GAIN_FACTOR = 0.0;
}

void save(SaveFile& file) {
	file << settings;
}

void load(SaveFile& file) {
	if(file >= SV_0048)
		file >> settings;
}
