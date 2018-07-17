class Completion {
	string ident;
	string name;
	string description;
	string longDescription;
	string category;
	string cls;
	Sprite icon;
	Color color;

	string format(bool shortForm = true, uint limit = 60) {
		string desc = description;
		if(desc.length > limit)
			desc = desc.substr(0, limit-3)+"...";

		if(shortForm)
			return ::format(
				"[img=$3;30x30][vspace=4/][color=$4][b]$5[/b][/color][/img]",
				name, desc, getSpriteDesc(icon), toString(color), ident);
		else
			return ::format(
				"[img=$3;40x40][color=$4][b]$5[/b] ($1)\n[offset=20][i]$2[/i][/offset][/color][/img]",
				name, desc, getSpriteDesc(icon), toString(color), ident);
	}
};

void loadCompletions(array<Completion@>@ arr, const string& folder, const string& blockName) {
	arr.length = 0;
	FileList list(folder, "*.txt", true);
	Completion@ compl;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		ReadFile file(list.path[i], true);
		
		uint index = 0;
		int indent = 0;
		while(file++) {
			if(indent == -1)
				indent = file.indent;
			if(file.indent > indent)
				continue;
			if(file.indent < indent && compl !is null)
				@compl = null;
			if(file.key.equals_nocase(blockName)) {
				@compl = Completion();
				arr.insertLast(compl);
				compl.ident = file.value;
				compl.name = compl.ident;
				indent = -1;
			}
			else if(compl is null) {
				continue;
			}
			else if(file.key.equals_nocase("Name")) {
				compl.name = localize(file.value);
			}
			else if(file.key.equals_nocase("Description")) {
				if(compl.description.length == 0)
					compl.description = localize(file.value);
				compl.longDescription = localize(file.value);
			}
			else if(file.key.equals_nocase("Blurb")) {
				compl.description = localize(file.value);
			}
			else if(file.key.equals_nocase("Icon")) {
				if(!compl.icon.valid)
					compl.icon = getSprite(file.value);
			}
			else if(file.key.equals_nocase("Sprite")) {
				if(!compl.icon.valid)
					compl.icon = getSprite(file.value);
			}
			else if(file.key.equals_nocase("Small Icon")) {
				compl.icon = getSprite(file.value);
			}
			else if(file.key.equals_nocase("Color")) {
				compl.color = toColor(file.value);
			}
			else if(file.key.equals_nocase("Base Color")) {
				compl.color = toColor(file.value);
			}
			else if(file.key.equals_nocase("Category")) {
				compl.category = file.value;
			}
			else if(file.key.equals_nocase("Class")) {
				compl.cls = file.value;
			}
		}
	}
}

array<Completion@> abilityCompletions;
array<Completion@> resourceCompletions;
array<Completion@> buildingCompletions;
array<Completion@> constructionCompletions;
array<Completion@> statusCompletions;
array<Completion@> subsysCompletions;
array<Completion@> traitCompletions;
array<Completion@> orbitalCompletions;
array<Completion@> artifactCompletions;
array<Completion@> techCompletions;
array<Completion@> biomeCompletions;
array<Completion@> cardCompletions;
array<Completion@> voteCompletions;
array<Completion@> effectCompletions;
array<Completion@> anomalyCompletions;
array<Completion@> creepCompletions;
array<Completion@> eventCompletions;
array<Completion@> cargoCompletions;
array<Completion@> attitudeCompletions;

bool completionsInitialized = false;
void initCompletions() {
	if(completionsInitialized)
		return;
	completionsInitialized = true;

	loadCompletions(abilityCompletions, "data/abilities", "Ability");
	loadCompletions(resourceCompletions, "data/resources", "Resource");
	loadCompletions(buildingCompletions, "data/buildings", "Building");
	loadCompletions(constructionCompletions, "data/constructions", "Construction");
	loadCompletions(statusCompletions, "data/statuses", "Status");
	loadCompletions(subsysCompletions, "data/subsystems", "Subsystem");
	loadCompletions(traitCompletions, "data/traits", "Trait");
	loadCompletions(orbitalCompletions, "data/orbitals", "Module");
	loadCompletions(artifactCompletions, "data/artifacts", "Artifact");
	loadCompletions(techCompletions, "data/research", "Technology");
	loadCompletions(biomeCompletions, "data/biomes", "Biome");
	loadCompletions(cardCompletions, "data/influence", "Card");
	loadCompletions(voteCompletions, "data/influence", "Vote");
	loadCompletions(effectCompletions, "data/influence", "Effect");
	loadCompletions(anomalyCompletions, "data/anomalies", "Anomaly");
	loadCompletions(creepCompletions, "data/creeps", "Camp");
	loadCompletions(eventCompletions, "data/random_events", "Event");
	loadCompletions(cargoCompletions, "data/cargo", "Cargo");
	loadCompletions(attitudeCompletions, "data/attitudes", "Attitude");
}
