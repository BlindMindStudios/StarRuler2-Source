from saving import SaveVersion;
from hooks import parseHook, Hook;

//System data is an intermediate description during map generation
final class SystemData {
	uint index;
	vec3d position;
	uint sysIndex = 0;
	int systemType = -1;
	int quality = 0;
	double contestation = 0;
	int marked = -1;
	int artifacts = 0;
	bool canHaveHomeworld = true;
	array<Empire@>@ homeworlds;
	array<double>@ hwDistances;
	SystemData@ mirrorSystem;
	uint[] adjacent;
	uint[] wormholes;
	SystemData@[] adjacentData;
	Star@ star;
	Planet@[] planets;
	Object@[] distributedResources;
	Planet@[] distributedConditions;
	const SystemCode@ systemCode;
	bool autoGenerateLinks = true;
	bool ignoreAdjacencies = false;
	uint assignGroup = uint(-1);
	
	void addHomeworld(Empire@ empire) {
		if(homeworlds is null)
			@homeworlds = array<Empire@>();
		homeworlds.insertLast(empire);
	}
};

final class SystemCode {
	array<string> commands;
	array<Hook@> hooks;
	int indent = 0;

	SystemCode& opShl(const string& code) {
		commands.insertLast(code);
		parseHook(hooks, indent, code, "map_effects::");
		indent = 0;
		return this;
	}

	SystemCode& opShl(int num) {
		indent += num;
		return this;
	}
};

//Abstract description of a system
final class SystemDesc : Serializable, Savable {
	uint index;
	string name;
	vec3d position;
	double radius;
	Region@ object;
	uint[] adjacent;
	double[] adjacentDist;
	uint[] wormholes;
	double contestation = 0;
	bool donateVision = true;
	uint assignGroup = uint(-1);

	array<uint> territories(getEmpireCount());
	array<uint> visibleTerritory(getEmpireCount());

	void read(Message& msg) {
		index = msg.readSmall();
		position = msg.readMedVec3();
		radius = msg.read_float();
		msg >> object;
		msg >> name;
		msg >> donateVision;

		uint cnt = msg.readSmall();
		adjacent.length = cnt;
		adjacentDist.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			adjacent[i] = msg.readSmall();
			adjacentDist[i] = msg.read_float();
		}

		cnt = msg.readSmall();
		wormholes.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			wormholes[i] = msg.readSmall();
	}

	uint get_spatialAdjacentCount() {
		return adjacent.length + wormholes.length;
	}

	uint get_spatialAdjacent(uint index) {
		if(index < adjacent.length)
			return adjacent[index];
		index -= adjacent.length;
		if(index < wormholes.length)
			return wormholes[index];
		return uint(-1);
	}

	bool isSpatialAdjacent(const SystemDesc& other) const {
		for(uint i = 0, cnt = adjacent.length; i < cnt; ++i) {
			if(adjacent[i] == other.index)
				return true;
		}
		return false;
	}

	bool isAdjacent(const SystemDesc& other) const {
		for(uint i = 0, cnt = adjacent.length; i < cnt; ++i) {
			if(adjacent[i] == other.index)
				return true;
		}
		for(uint i = 0, cnt = wormholes.length; i < cnt; ++i) {
			if(wormholes[i] == other.index)
				return true;
		}
		return false;
	}

	void write(Message& msg) {
		msg.writeSmall(index);
		msg.writeMedVec3(position);
		msg << float(radius);
		msg << object;
		msg << name;
		msg << donateVision;

		uint cnt = adjacent.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i) {
			msg.writeSmall(adjacent[i]);
			msg << float(adjacentDist[i]);
		}

		cnt = wormholes.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg.writeSmall(wormholes[i]);
	}

	void load(SaveFile& msg) {
		msg >> index;
		msg >> name;
		msg >> position;
		msg >> radius;
		msg >> object;
		if(msg >= SV_0082)
			msg >> contestation;
		if(msg >= SV_0099)
			msg >> donateVision;
		if(msg >= SV_0152)
			msg >> assignGroup;

		uint cnt = 0;
		msg >> cnt;
		adjacent.length = cnt;
		adjacentDist.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg >> adjacent[i];
			msg >> adjacentDist[i];
		}

		if(msg >= SV_0020) {
			cnt = 0;
			msg >> cnt;
			wormholes.length = cnt;
			for(uint i = 0; i < cnt; ++i)
				msg >> wormholes[i];
		}
	}

	void save(SaveFile& msg) {
		msg << index;
		msg << name;
		msg << position;
		msg << radius;
		msg << object;
		msg << contestation;
		msg << donateVision;
		msg << assignGroup;

		uint cnt = adjacent.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			msg << adjacent[i];
			msg << adjacentDist[i];
		}

		cnt = wormholes.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << wormholes[i];
	}
};
