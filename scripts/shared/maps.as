#priority init 1500

#section server
import settings.map_lib;
import map_generation;
#section shadow
import settings.map_lib;
class MapGeneration {
	void initDefs() {}
	void init() {}
	void tick(double time) {}
};
#section client-side
import util.settings_page;
class MapGeneration : SettingsPage {}
#section all

bool mapsInitialized = false;
class Map : MapGeneration {
	uint index;
	string id;
	string name;
	string description;
	string dlc;
	AnyClass@ mapClass;

	int sortIndex = 0;

	bool isListed = true;
	bool isScenario = false;
	bool allowHomeworlds = true;
	bool eatsPlayers = false;
	bool isUnique = false;

	string icon;
	Color color;

	Map() {
		id = __module__;
		@mapClass = getClass(this);
		if(!mapsInitialized)
			addMap(this);
	}

	Map@ create() {
		Map@ other = cast<Map>(mapClass.create());
		other.id = id;
		other.index = index;
		return other;
	}

	int opCmp(const Map@ other) const {
		if(sortIndex < other.sortIndex)
			return -1;
		if(sortIndex > other.sortIndex)
			return 1;
		return 0;
	}
};

Map@[] Maps;
void addMap(Map@ map) {
	Maps.insertLast(map);
}

Map@ getMap(uint index) {
	return Maps[index];
}

Map@ getMap(const string& id) {
	uint cnt = Maps.length;
	for(uint i = 0; i < cnt; ++i)
		if(Maps[i].id == id)
			return Maps[i];
	return null;
}

uint get_mapCount() {
	return Maps.length;
}

Map@ get_maps(uint num) {
	return Maps[num];
}

void setupPhysics(double size, double fuzz, uint cells) {
	@physicsWorld = PhysicsWorld(size, fuzz, cells);
	@nodePhysicsWorld = PhysicsWorld(size, fuzz, cells);
}

void init() {
	Maps.sortDesc();
	for(uint i = 0, cnt = Maps.length; i < cnt; ++i)
		Maps[i].index = i;
	mapsInitialized = true;
}
