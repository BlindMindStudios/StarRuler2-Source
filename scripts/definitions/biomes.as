#priority init 2010
import resources;
from saving import SaveIdentifier;

final class Biome {
	uint8 id = 0;
	string ident;
	string name;
	string description;
	Color color;

	Sprite tile;
	uint frequency = 1;
	float useWeight = 1.f;
	float buildCost = 1.f, buildTime = 1.f;
	
	//Temp and humidity range from 0 to 1 (lowest to highest)
	float temp = 0.5f, humidity = 0.5f;
	bool isCrystallic = false;
	bool isVoid = false;
	bool buildable = true;
	bool isWater = false;
	bool isMoon = false;

	vec4f picks(0.f, 0.f, 0.f, -0.025f);
	vec2f lookupRange(0.f, 0.f);
};

final class ColonizationOrder : Serializable, Savable {
	Object@ target;
	double targetPopulation;
	double inTransit;
	double totalSent;

	ColonizationOrder() {
		targetPopulation = 1.0;
		inTransit = 0.0;
		totalSent = 0.0;
	}

	void save(SaveFile& msg) {
		msg << target;
		msg << targetPopulation;
		msg << inTransit;
		msg << totalSent;
	}

	void load(SaveFile& msg) {
		msg >> target;
		msg >> targetPopulation;
		msg >> inTransit;
		if(msg >= SV_0148)
			msg >> totalSent;
	}

	void write(Message& msg) {
		msg << target;
		msg << targetPopulation;
		msg << inTransit;
	}

	void read(Message& msg) {
		msg >> target;
		msg >> targetPopulation;
		msg >> inTransit;
	}
};

namespace biomes {
	::array<::Biome@> biomes;
	::dictionary biomeIdents;
	::uint totalFrequency = 0;
};

uint getBiomeCount() {
	return biomes::biomes.length;
}

const Biome@ getBiome(uint id) {
	if(id < biomes::biomes.length)
		return biomes::biomes[id];
	else
		return null;
}

int getBiomeID(const string& ident) {
	auto@ type = getBiome(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getBiomeIdent(int id) {
	auto@ type = getBiome(id);
	if(type is null)
		return "";
	return type.ident;
}

const Biome@ getBiome(const string& name) {
	Biome@ b;
	biomes::biomeIdents.get(name, @b);
	return b;
}

const Biome@ getDistributedBiome() {
	uint num = randomi(1, biomes::totalFrequency);
	for(uint i = 0, cnt = biomes::biomes.length; i < cnt; ++i) {
		if(num <= biomes::biomes[i].frequency)
			return biomes::biomes[i];
		num -= biomes::biomes[i].frequency;
	}
	return biomes::biomes[0];
}

void addBiome(Biome@ biome) {
	biome.id = biomes::biomes.length;
	biomes::biomes.insertLast(biome);
	biomes::biomeIdents.set(biome.ident, @biome);
	biomes::totalFrequency += biome.frequency;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = biomes::biomes.length; i < cnt; ++i) {
		Biome@ type = biomes::biomes[i];
		file.addIdentifier(SI_Biome, type.id, type.ident);
	}
}
