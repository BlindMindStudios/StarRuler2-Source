#priority init 2000
import abilities;
import saving;
import hooks;

export ArtifactType;
export getArtifactType, getArtifactTypeCount;
export getDistributedArtifactType;
export getSeedArtifactType;

tidy final class ArtifactType {
	uint id = 0;
	string ident;
	string name;
	string description;
	Sprite icon = Sprite(spritesheet::ArtifactIcon, 0);
	Sprite strategicIcon = Sprite(spritesheet::ArtifactIcon, 0);
	double iconSize = 0.02;
	double frequency = 1.0;
	double timeFrequency = 0.0;
	double mass = 300.0;
	bool singleUse = true;
	bool orbit = false;
	bool unique = false;
	bool natural = false;
	bool collapses = true;
	bool canDonate = true;
	bool canOwn = true;
	string spreadVariable;
	double requireContestation = -INFINITY;

	const Model@ model = model::Artifact;
	const Material@ material = material::VolkurGenericPBR;
	double physicalSize = 5.0;

	array<string> ability_defs;
	array<const AbilityType@> abilities;
	array<Hook@> ai;
	array<Hook@> secondaryAI;
	double secondaryChance = 0.0;
	array<string> tags;

	bool hasTag(const string& tag) const {
		for(uint i = 0, cnt = tags.length; i < cnt; ++i) {
			if(tags[i] == tag)
				return true;
		}
		return false;
	}
};

array<ArtifactType@> artifacts;
dictionary artifactIdents;
double totalFrequency = 1.0;

int getArtifactID(const string& ident) {
	ArtifactType@ type;
	artifactIdents.get(ident, @type);
	if(type !is null)
		return int(type.id);
	return -1;
}

string getArtifactIdent(int id) {
	if(id < 0 || id >= int(artifacts.length))
		return "-";
	return artifacts[id].ident;
}

uint getArtifactTypeCount() {
	return artifacts.length;
}

const ArtifactType@ getArtifactType(uint id) {
	if(id < artifacts.length)
		return artifacts[id];
	else
		return null;
}

const ArtifactType@ getArtifactType(const string& name) {
	ArtifactType@ abl;
	artifactIdents.get(name, @abl);
	return abl;
}

void addArtifactType(ArtifactType@ abl) {
	abl.id = artifacts.length;
	artifacts.insertLast(abl);
	artifactIdents.set(abl.ident, @abl);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
		ArtifactType@ type = artifacts[i];
		file.addIdentifier(SI_Artifact, type.id, type.ident);
	}
}

void loadArtifacts(const string& filename) {
	ReadFile file(filename, false);
	
	string key, value;
	ArtifactType@ type;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(key.equals_nocase("Artifact")) {
			if(type !is null)
				addArtifactType(type);
			@type = ArtifactType();
			type.ident = value;
		}
		else if(type is null) {
			file.error("Missing Artifact ID line");
		}
		else if(key.equals_nocase("Name")) {
			type.name = localize(value);
		}
		else if(key.equals_nocase("Description")) {
			type.description = localize(value);
		}
		else if(key.equals_nocase("Icon")) {
			type.icon = getSprite(value);
		}
		else if(key.equals_nocase("Tag")) {
			type.tags.insertLast(value);
		}
		else if(key.equals_nocase("Ability")) {
			type.ability_defs.insertLast(value);
		}
		else if(key.equals_nocase("Frequency")) {
			type.frequency = toDouble(value);
		}
		else if(key.equals_nocase("Time Frequency")) {
			type.timeFrequency = toDouble(value);
		}
		else if(key.equals_nocase("Single Use")) {
			type.singleUse = toBool(value);
		}
		else if(key.equals_nocase("Size")) {
			type.physicalSize = toDouble(value);
		}
		else if(key.equals_nocase("Icon Size")) {
			type.iconSize = toDouble(value);
		}
		else if(key.equals_nocase("Strategic Icon")) {
			type.strategicIcon = getSprite(value);
		}
		else if(key.equals_nocase("Model")) {
			@type.model = getModel(value);
		}
		else if(key.equals_nocase("Material")) {
			@type.material = getMaterial(value);
		}
		else if(key.equals_nocase("Orbit")) {
			type.orbit = toBool(value);
		}
		else if(key.equals_nocase("Unique")) {
			type.unique = toBool(value);
		}
		else if(key.equals_nocase("Natural")) {
			type.natural = toBool(value);
		}
		else if(key.equals_nocase("Collapses")) {
			type.collapses = toBool(value);
		}
		else if(key.equals_nocase("Mass")) {
			type.mass = toDouble(value);
		}
		else if(key.equals_nocase("Can Donate")) {
			type.canDonate = toBool(value);
		}
		else if(key.equals_nocase("Can Own")) {
			type.canOwn = toBool(value);
		}
		else if(key.equals_nocase("AI")) {
			auto@ hook = parseHook(value, "ai.artifacts::", instantiate=false, file=file);
			if(hook !is null)
				type.ai.insertLast(hook);
		}
		else if(key.equals_nocase("Secondary AI")) {
			auto@ hook = parseHook(value, "ai.artifacts::", instantiate=false, file=file);
			if(hook !is null)
				type.secondaryAI.insertLast(hook);
		}
		else if(key.equals_nocase("Secondary Chance")) {
			type.secondaryChance = toDouble(value);
		}
		else if(key.equals_nocase("Require Contestation")) {
			type.requireContestation = toDouble(value);
		}
		else if(key.equals_nocase("Spread Variable")) {
			type.spreadVariable = value;
			type.frequency = 0;
			type.canDonate = false;
			type.canOwn = false;
		}
		else {
			file.error("Invalid line");
		}
	}
	
	if(type !is null)
		addArtifactType(type);
}

ArtifactType@ getRandomArtifactType() {
	uint count = artifacts.length;
	double num = randomd(0, totalFrequency);
	ArtifactType@ type;
	for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
		@type = artifacts[i];
		double freq = type.frequency;
		if(num <= freq)
			break;
		num -= freq;
	}
	if(type is null)
		@type = artifacts[artifacts.length-1];
	return type;
}

const ArtifactType@ getDistributedArtifactType(bool isUse = true) {
	auto@ type = getRandomArtifactType();
	if(type.unique && isUse) {
		totalFrequency -= type.frequency;
		type.frequency = 0;
	}
	return type;
}

const ArtifactType@ getDistributedArtifactType(double contestation, bool isUse = true) {
	uint tries = 0;
	ArtifactType@ type;
	while(tries < 10) {
		@type = getRandomArtifactType();
		if(type.requireContestation <= contestation)
			break;
		tries += 1;
	}
	if(type.unique && isUse) {
		totalFrequency -= type.frequency;
		type.frequency = 0;
	}
	return type;
}

const ArtifactType@ getSeedArtifactType(bool isUse = true) {
	double total = 0.0;
	for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
		auto@ type = artifacts[i];
		if(type.frequency <= 0 || !type.singleUse || type.natural)
			continue;
		double freq = type.frequency + type.timeFrequency * (gameTime / 1200.0);
		total += freq;
	}
	double num = randomd(0, total);
	ArtifactType@ type;
	for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
		@type = artifacts[i];
		if(type.frequency <= 0 || !type.singleUse || type.natural)
			continue;
		double freq = type.frequency + type.timeFrequency * (gameTime / 1200.0);
		if(num <= freq)
			break;
		num -= freq;
	}
	if(type is null)
		@type = artifacts[artifacts.length-1];
	if(type !is null && type.unique && isUse) {
		totalFrequency -= type.frequency;
		type.frequency = 0;
	}
	return type;
}

void preInit() {
	FileList list("data/artifacts", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadArtifacts(list.path[i]);
}

void init() {
	totalFrequency = 0.0;
	for(uint i = 0, cnt = artifacts.length; i < cnt; ++i) {
		auto@ type = artifacts[i];
		totalFrequency += type.frequency;
		for(uint j = 0, jcnt = type.ability_defs.length; j < jcnt; ++j) {
			auto@ abl = getAbilityType(type.ability_defs[j]);
			if(abl !is null)
				type.abilities.insertLast(abl);
			else
				error("Error: could not find ability "+type.ability_defs[j]+" in artifact "+type.ident);
		}
		for(uint n = 0, ncnt = type.ai.length; n < ncnt; ++n) {
			if(!type.ai[n].instantiate())
				error("Could not instantiate AI hook: "+addrstr(type.ai[n])+" in artifact "+type.ident);
		}
	}
}
