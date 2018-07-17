#priority init 2500
from resources import ResourceRequirements;
import saving;

class PlanetLevelChain {
	uint id;
	string ident;
	array<PlanetLevel@> levels;

	void inherit(const PlanetLevelChain& other) {
		levels.length = other.levels.length;
		for(uint i = 0, cnt = levels.length; i < cnt; ++i) {
			if(levels[i] is null)
				@levels[i] = PlanetLevel();
			levels[i] = other.levels[i];
		}
	}
};

class PlanetLevel {
	uint level = 0;
	string name;
	ResourceRequirements reqs;
	uint population = 1;
	double popGrowth = 0.3;
	double requiredPop = 0.0;
	int baseIncome = 100;
	int resourceIncome = 0;
	int baseLoyalty = 10;
	int baseSupport = 0;
	uint basePressure = 0;
	uint exportPressurePenalty = 0;
	double neighbourLoyalty = 0.0;
	int points = 10;
	Sprite icon;
};

array<PlanetLevelChain@> levelChains;
dictionary levelChainIdents;
PlanetLevelChain baseLevelChain;

int getLevelChainID(const string& ident) {
	auto@ type = getLevelChain(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getLevelChainIdent(int id) {
	auto@ type = getLevelChain(id);
	if(type is null)
		return "";
	return type.ident;
}

const PlanetLevelChain@ getLevelChain(uint id) {
	if(id >= levelChains.length)
		return null;
	return levelChains[id];
}

const PlanetLevelChain@ getLevelChain(const string& ident) {
	PlanetLevelChain@ def;
	if(levelChainIdents.get(ident, @def))
		return def;
	return null;
}

uint getLevelChainCount() {
	return levelChains.length;
}

const PlanetLevel@ getPlanetLevel(const Object& planet) {
	auto@ chain = getLevelChain(planet.levelChain);
	if(chain is null)
		return null;
	uint level = planet.level;
	if(level >= chain.levels.length)
		return null;
	return chain.levels[level];
}

const PlanetLevel@ getPlanetLevel(uint chainId, uint level) {
	auto@ chain = getLevelChain(chainId);
	if(chain is null)
		return null;
	if(level >= chain.levels.length)
		return null;
	return chain.levels[level];
}

const PlanetLevel@ getPlanetLevel(const Object& planet, uint level) {
	auto@ chain = getLevelChain(planet.levelChain);
	if(chain is null)
		return null;
	if(level >= chain.levels.length)
		return null;
	return chain.levels[level];
}

double getPlanetLevelRequiredPop(const Object& planet, uint level) {
	auto@ lvl = getPlanetLevel(planet, level);
	if(lvl is null)
		return 0.0;
	return lvl.requiredPop;
}

double getPlanetLevelRequiredPop(uint chainId, uint level) {
	auto@ lvl = getPlanetLevel(chainId, level);
	if(lvl is null)
		return 0.0;
	return lvl.requiredPop;
}

int getMaxPlanetLevel(uint chainId) {
	auto@ chain = getLevelChain(chainId);
	if(chain is null)
		return 0;
	return chain.levels.length-1;
}

int getMaxPlanetLevel(const Object& planet) {
	auto@ chain = getLevelChain(planet.levelChain);
	if(chain is null)
		return 0;
	return chain.levels.length-1;
}

bool readLevelChain(ReadFile& file) {
	PlanetLevelChain chain;
	chain.ident = file.value;

	chain.id = levelChains.length;
	levelChains.insertLast(chain);
	levelChainIdents.set(chain.ident, @chain);

	chain.inherit(baseLevelChain);

	int indent = file.indent;

	bool advance = true;
	string key, value;
	uint nextLevel = 0;
	while(!advance || file++) {
		key = file.key;
		value = file.value;

		if(file.indent <= indent) {
			chain.levels.length = nextLevel;
			return true;
		}

		if(key == "Level") {
			PlanetLevel@ lvl;

			if(nextLevel < chain.levels.length) {
				@lvl = chain.levels[nextLevel];
			}
			else {
				@lvl = PlanetLevel();
				lvl.level = nextLevel;
				chain.levels.insertLast(lvl);
			}
			nextLevel += 1;

			advance = !readLevel(file, lvl);
		}
		else {
			advance = true;
		}
	}

	chain.levels.length = nextLevel;
	return false;
}

bool readLevel(ReadFile& file, PlanetLevel& lvl) {
	string key, value;
	int indent = file.indent;
	while(file++) {
		key = file.key;
		value = file.value;

		if(file.indent <= indent)
			return true;

		if(key == "Required") {
			if(lvl.reqs !is null)
				lvl.reqs.parse(value);
		}
		else if(key == "Population") {
			if(lvl !is null)
				lvl.population = toUInt(value);
		}
		else if(key == "PopGrowth") {
			if(lvl !is null)
				lvl.popGrowth = toDouble(value);
		}
		else if(key == "RequiredPop") {
			if(lvl !is null)
				lvl.requiredPop = toDouble(value);
		}
		else if(key == "BaseIncome") {
			if(lvl !is null)
				lvl.baseIncome = toInt(value);
		}
		else if(key == "ResourceIncome") {
			if(lvl !is null)
				lvl.resourceIncome = toInt(value);
		}
		else if(key == "BasePressure") {
			if(lvl !is null)
				lvl.basePressure = toUInt(value);
		}
		else if(key == "BaseLoyalty") {
			if(lvl !is null)
				lvl.baseLoyalty = toInt(value);
		}
		else if(key == "NeighbourLoyalty") {
			if(lvl !is null)
				lvl.neighbourLoyalty = toDouble(value);
		}
		else if(key == "ExportPressurePenalty") {
			if(lvl !is null)
				lvl.exportPressurePenalty = toUInt(value);
		}
		else if(key == "Name") {
			if(lvl !is null)
				lvl.name = localize(value);
		}
		else if(key == "Icon") {
			lvl.icon = getSprite(value);
		}
		else if(key == "Points") {
			lvl.points = toInt(value);
		}
		else if(key == "BaseSupport") {
			lvl.baseSupport = toInt(value);
		}
		else {
			file.error("Unknown level property: "+file.line);
		}
	}

	return false;
}

void preInit() {
	baseLevelChain.id = 0;
	baseLevelChain.ident = "base";
	levelChains.insertLast(baseLevelChain);
	levelChainIdents.set(baseLevelChain.ident, @baseLevelChain);
}

void init() {
	ReadFile file(resolve("data/planet_levels.txt"));

	bool advance = true;
	string key, value;
	while(!advance || file++) {
		key = file.key;
		value = file.value;

		if(key == "Level") {
			PlanetLevel@ lvl = PlanetLevel();

			lvl.level = baseLevelChain.levels.length;
			baseLevelChain.levels.insertLast(lvl);

			advance = !readLevel(file, lvl);
		}
		else if(key == "Level Chain") {
			advance = !readLevelChain(file);
		}
		else {
			advance = true;
		}
	}
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = levelChains.length; i < cnt; ++i) {
		auto type = levelChains[i];
		file.addIdentifier(SI_PlanetLevelChain, type.id, type.ident);
	}
}
