//Deals with definition specifications. A definition specification takes a loaded datafile
//structure and defines properties for its fields so it can be represented with a UI.

import hooks;
import editor.loader;
import editor.completion;
import icons;

class FileDef {
	array<BlockDef@> blocks;
	BlockDef defaultBlock;
	BlockDef@ curBlock;
	string localeFile;

	FileDef() {
		@curBlock = defaultBlock;
	}

	BlockDef@ getBlock(const string& key) {
		return defaultBlock.getBlock(key);
	}

	BlockDef@ block(const string& key, const string& doc, const string& hookType = "", const string& hookModule = "") {
		@curBlock = defaultBlock.block(key, doc, hookType, hookModule);
		curBlock.closeDefault = false;
		return curBlock;
	}

	void unblock() {
		@curBlock = defaultBlock;
	}

	FieldDef@ field(const string& key, ArgumentType type, const string& defaultValue, const string& doc, const Sprite& icon = Sprite(), bool repeatable = false) {
		return curBlock.field(key, type, defaultValue, doc, icon, repeatable);
	}

	void onChange() {}
};

class BlockDef {
	string key;
	string doc;
	string hookType;
	string hookModule;
	string hookPrefix;
	string editMode;
	bool hasIdentifier = true;
	bool identifierLimit = true;
	bool closeDefault = true;
	array<BlockDef@> blocks;
	array<FieldDef@> fields;
	array<Completion@>@ duplicateCheck;

	BlockDef@ getBlock(const string& key) {
		for(uint i = 0, cnt = blocks.length; i < cnt; ++i) {
			if(blocks[i].key == key)
				return blocks[i];
		}
		return null;
	}

	FieldDef@ getField(const string& key) {
		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			if(fields[i].key == key)
				return fields[i];
		}
		return null;
	}

	FieldDef@ getField(LineDesc@ line) {
		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			if(fields[i].condition is null)
				continue;
			if(fields[i].condition.matches(line)) {
				fields[i].condition.modify(line);
				return fields[i];
			}
		}
		return null;
	}

	BlockDef@ block(const string& key, const string& doc, const string& hookType = "", const string& hookModule = "") {
		BlockDef b;
		b.key = key;
		b.doc = doc;
		b.hookType = hookType;
		b.hookModule = hookModule;
		blocks.insertLast(b);
		return b;
	}

	FieldDef@ field(const string& key, ArgumentType type, const string& defaultValue, const string& doc, const Sprite& icon = Sprite(), bool repeatable = false) {
		FieldDef f;
		f.index = fields.length;
		f.key = key;
		f.type = type;
		f.defaultValue = defaultValue;
		f.doc = doc;
		f.icon = icon;
		f.repeatable = repeatable;
		fields.insertLast(f);
		return f;
	}

	BlockDef& checkDuplicates(array<Completion@>@ dups) {
		@duplicateCheck = dups;
		return this;
	}

	BlockDef& setEditMode(const string& mode) {
		editMode = mode;
		return this;
	}
};

class FieldCondition {
	bool matches(LineDesc@ line) { return false; }
	void modify(LineDesc@ line) {}
};

class VariableCondition : FieldCondition {
	bool matches(LineDesc@ line) {
		if(!line.isKey)
			return false;
		if(line.value.length != 0 && line.value[0] == '=')
			return true;
		return false;
	}

	void modify(LineDesc@ line) {
		line.line = line.key+" :"+line.value;
		line.isKey = false;
	}
};

class ValueCondition : FieldCondition {
	bool matches(LineDesc@ line) {
		if(line.isKey)
			return false;
		int pos = line.line.findFirst("=");
		return pos != -1;
	}
};

class FieldDef {
	uint index;
	string key;
	string defaultValue;
	string doc;
	Sprite icon;
	ArgumentType type;
	FieldCondition@ condition;
	bool fullLine = false;
	array<string>@ options;
	bool repeatable = false;
	int fieldPriority = 0;

	FieldDef& setOptions(array<string>@ opts) {
		@options = opts;
		return this;
	}

	FieldDef& setCondition(FieldCondition@ cond) {
		@this.condition = cond;
		return this;
	}

	FieldDef& setFullLine(bool value) {
		this.fullLine = value;
		return this;
	}

	FieldDef& setPriority(int prior) {
		fieldPriority = prior;
		return this;
	}
};

class StatusFile : FileDef {
	array<string> visibilities = {"Everybody", "Owner", "Origin Empire", "Owner and Origin Empire", "Nobody", "Global"};

	StatusFile() {
		localeFile = "statuses.txt";
		block("Status", doc="A type of status effect that can be added to an object.",
				hookType="statuses::IStatusHook", hookModule="status_effects").checkDuplicates(statusCompletions);
			field("Name", AT_Locale, "", doc="Name of the status.");
			field("Description", AT_Locale, "", doc="Description of the status.");
			field("Icon", AT_Sprite, "", doc="Icon used to represent the status.");
			field("Color", AT_Color, "", doc="The status' representative color.");
			field("Condition Frequency", AT_Decimal, "0", doc="How often this status appears on planets as a planet condition, relative to other statuses' condition frequency.");
			field("Condition Tier", AT_Integer, "0", doc="The minimum level the planet's resource must be for this status to be able to appear as a planet condition.");
			field("Condition Type", AT_Custom, "", doc="The planet type a planet must have in order for this status to be able to appear as a planet condition..");
			field("Unique", AT_Boolean, "False", doc="Unique statuses indicate that the status cannot affect an object more than once, so should not be given a stack count display.");
			field("Collapses", AT_Boolean, "False", doc="A status that collapses will show a stack count instead of being a separate status for each instance. The status hooks are responsible for dealing with stack counts on an individual basis.");
			field("Visible To", AT_Selection, "Everybody", doc="Which empires the status can be seen by when looking at the object.").setOptions(visibilities);
	}

	void onChange() {
		loadCompletions(statusCompletions, "data/statuses", "Status");
	}
};

class AbilityFile : FileDef {
	AbilityFile() {
		localeFile = "abilities.txt";
		block("Ability", doc="An ability that objects can trigger.",
				hookType="abilities::IAbilityHook", hookModule="ability_effects").checkDuplicates(abilityCompletions);
			field("Name", AT_Locale, "", doc="Name of the ability.");
			field("Description", AT_Locale, "", doc="Description of the ability.");
			field("Icon", AT_Sprite, "", doc="Icon used to represent the ability.");
			field("Energy Cost", AT_Decimal, "0", doc="The base energy cost to activate the ability. Can be modified further by hooks.");
			field("Cooldown", AT_Decimal, "0", doc="The base cooldown between uses of the ability. Can be modified further by hooks.");
			field("Range", AT_Decimal, "", doc="The base maximum distance that the ability can be casted from. Can be modified further by hooks.");
			field("Hotkey", AT_Custom, "", doc="If set, create a hotkey for activating this ability when the object is selected to the specified key combination.");
			field("Hide Global", AT_Boolean, "False", doc="Hide this from the global action bar if added as an empire ability.");
			field("Target", AT_TargetSpec, "", /*repeatable=true,*/ doc="A type of target this ability needs to be triggered on.");
			field("Activate Sound", AT_Custom, "", doc="Name of the sound effect to be played in the UI for the person that triggers this ability.");
	}

	void onChange() {
		loadCompletions(abilityCompletions, "data/abilities", "Ability");
	}
};

class AnomalyFile : FileDef {
	AnomalyFile() {
		localeFile = "anomalies.txt";
		auto@ anom = block("Anomaly", doc="A type of anomaly that can be investigated.").checkDuplicates(anomalyCompletions);
			anom.field("Name", AT_Locale, "", doc="Name of the anomaly.");
			anom.field("Description", AT_Locale, "", doc="Basic, unscanned description of the anomaly.");
			anom.field("Narrative", AT_Locale, "", doc="Narrative for a scanned anomaly not in any state.");
			anom.field("Model", AT_Model, "Debris", doc="Model for the unscanned anomaly.");
			anom.field("Material", AT_Material, "Asteroid", doc="Model material for the unscanned anomaly.");
			anom.field("Frequency", AT_Decimal, "1", doc="How often this anomaly appears, relative to other anomalies' frequency.");
			anom.field("Scan Time", AT_Decimal, "60", doc="Amount of time in seconds that the anomaly takes to scan.");
			anom.field("Unique", AT_Boolean, "False", doc="Whether this anomaly is unique and can only occur once in a game.");

		auto@ state = anom.block("State", doc="One of the states that the anomaly can trigger when scanned.");
			state.field("Narrative", AT_Locale, "", doc="Description of the anomaly in this state.");
			state.field("Model", AT_Model, "Debris", doc="Model for the anomaly in this state.");
			state.field("Material", AT_Material, "Asteroid", doc="Model material for the anomaly in this state.");
			state.field("Frequency", AT_Decimal, "1", doc="How often the anomaly scans to this state, relative to other states' frequency.");
			state.field("Choice", AT_Custom, "", repeatable=true, doc="Indicates an available choice when the anomaly is in this state.");

		auto@ option = anom.block("Option", doc="One of the option choices that can be added to a state.",
				hookType="anomalies::IAnomalyHook", hookModule="anomaly_effects");
			option.field("Description", AT_Locale, "", doc="The description for triggering the option.");
			option.field("Icon", AT_Sprite, "", doc="Icon used to represent the option.");
			option.field("Chance", AT_Custom, "100%", doc="Chance for this option to appear, if no specific chance is given in the state.");
			option.field("Safe", AT_Boolean, "True", doc="Whether this option is safe and cannot result in unwanted consequences. Mainly used by the AI for decision making.");
			option.field("Target", AT_TargetSpec, "", /*repeatable=true,*/ doc="A type of target this option needs to be triggered on.");

		auto@ result = option.block("Result", doc="A possible result when the option is chosen.",
			hookType="anomalies::IAnomalyHook", hookModule="anomaly_effects");
		result.identifierLimit = false;
	}

	void onChange() {
		loadCompletions(anomalyCompletions, "data/anomalies", "Anomaly");
	}
};

class ArtifactFile : FileDef {
	ArtifactFile() {
		localeFile = "artifacts.txt";
		block("Artifact", doc="A type of artifact that can be found and used.").checkDuplicates(artifactCompletions);
			field("Name", AT_Locale, "", doc="Name of the artifact.");
			field("Description", AT_Locale, "", doc="Description of what the artifact does.");
			field("Icon", AT_Sprite, "ArtifactIcon::0", doc="Icon used to represent the artifact on the interface.");
			field("Strategic Icon", AT_Sprite, "ArtifactIcon::0", doc="Icon used for the artifact at strategic zoom.");
			field("Icon Size", AT_Decimal, "0.02", doc="Size of the artifact's distant icon.");
			field("Model", AT_Model, "Artifact", doc="Model for the artifact.");
			field("Material", AT_Material, "VolkurGenericPBR", doc="Model material for the artifact.");
			field("Physical Size", AT_Decimal, "5.0", doc="Physical size of the artifact in the world.");
			field("Mass", AT_Decimal, "300", doc="Mass of the artifact. Affects tractor beams.");
			field("Frequency", AT_Decimal, "1", doc="How often this artifact appears, relative to other artifacts' frequency.");
			field("Time Frequency", AT_Decimal, "0", doc="Increase to the artifact's base frequency for every 20 minutes of game time that passes.");
			field("Single Use", AT_Boolean, "True", doc="Whether the artifact disappears after it has been used once.");
			field("Single Use", AT_Boolean, "True", doc="Whether the artifact disappears after it has been used once.");
			field("Orbit", AT_Boolean, "False", doc="Whether the artifact orbits the star or stays at a static position.");
			field("Unique", AT_Boolean, "False", doc="Unique artifacts can only be generated into the galaxy once.");
			field("Natural", AT_Boolean, "False", doc="Natural artifacts are not generated by seed ships, but only spawn when the game starts.");
			field("Collapses", AT_Boolean, "True", doc="Whether multiple instances of this artifact are considered the same, and collapsed into a stacked view.");
			field("Can Donate", AT_Boolean, "True", doc="Whether this artifact can be donated to another player.");
			field("Can Own", AT_Boolean, "True", doc="Whether it is possible for a player to gain exclusive access to this artifact.");
			field("Require Contestation", AT_Decimal, "0", doc="If nonzero, this artifact type can only spawn in systems with a minimum contestation value. Contestation is an abstract number based on how many empires are close enough to potentially contest the system.");
			field("Spread Variable", AT_Custom, "", doc="If specified, turns this artifact into a 'Spread Artifact'. If the game_config parameter specified is active, exactly one instance of this artifact will be created when the universe is generated. Implies False for Can Donate and Can Own, and a 0 Frequency.");
			field("Tag", AT_Custom, "", repeatable=true, doc="Add a named tag to this artifact.");
			field("Ability", AT_Ability, "", repeatable=true, doc="This artifact grants the capability of using the specified ability.");
			field("AI", AT_Custom, "", repeatable=true, doc="Behaviour the AI follows for using this artifact.");
	}

	void onChange() {
		loadCompletions(artifactCompletions, "data/artifacts", "Artifact");
	}
};

class InfluenceFile : FileDef {
	array<string> cardClasses = {"Support", "Vote", "Effect", "Action", "Event", "Instant", "Misc"};
	array<string> cardRarities = {"Common", "Uncommon", "Rare", "Epic", "Basic"};
	array<string> cardSides = {"Neutral", "Both", "Oppose", "Support"};

	InfluenceFile() {
		localeFile = "diplomacy.txt";
		auto@ card = block("Card", doc="A type of influence card.",
				hookType="influence::InfluenceCardEffect", hookModule="card_effects").checkDuplicates(cardCompletions);
			card.field("Name", AT_Locale, "", doc="Title of the card.");
			card.field("Description", AT_Locale, "", doc="Description of the card.");
			card.field("Icon", AT_Sprite, "", doc="Icon used to represent the card.");
			card.field("Color", AT_Color, "", doc="The card's representative color.");
			card.field("Frequency", AT_Decimal, "-1", doc="How often this card appears in the deck. A value of -1 indicates the frequency is dependent on the card rarity.");
			card.field("Collapse Uses", AT_Boolean, "True", doc="Whether multiple uses of this card should be considered the same and collapsed into a stack.");
			card.field("Points", AT_Integer, "0", doc="How many points this card adds to the empire's point total, in addition to basic points based on rarity.");
			card.field("Leader Only", AT_Boolean, "False", doc="Whether only the senate leader can play this card.");
			card.field("Class", AT_Selection, "Misc", doc="The type of card this is.").setOptions(cardClasses);
			card.field("Rarity", AT_Selection, "Common", doc="The rarity of this card in the deck.").setOptions(cardRarities);
			card.field("Side", AT_Selection, "Neutral", doc="For support cards, which sides of the vote the card can be played on.").setOptions(cardSides);
			card.field("Base Purchase Cost", AT_Integer, "0", doc="The base influence cost to buy the card off the stack.");
			card.field("Quality Purchase Cost", AT_Integer, "0", doc="The additional influence cost per extra quality this card costs to buy off the stack.");
			card.field("Uses Purchase Cost", AT_Integer, "0", doc="The additional influence cost per use this card costs to buy off the stack.");
			card.field("Placement Purchase Cost", AT_Integer, "1", doc="How much influence each space in the card stack the buy cost increases by.");
			card.field("Base Play Cost", AT_Integer, "0", doc="The base influence cost to play this card.");
			card.field("Quality Play Cost", AT_Integer, "0", doc="The additional influence cost per quality this card costs to play.");
			card.field("Base Weight", AT_Integer, "0", doc="For support cards, the base weight this adds to a vote.");
			card.field("Quality Weight", AT_Integer, "0", doc="For support cards, the extra weight this adds to a vote per extra quality.");
			card.field("Min Quality", AT_Integer, "1", doc="The minimum quality this card appears in the stack with.");
			card.field("Max Quality", AT_Integer, "1", doc="The maximum quality this card appears in the stack with.");
			card.field("Can Overquality", AT_Boolean, "True", doc="Whether this card can be boosted beyond its max quality. (For example, by Enhance cards)");
			card.field("Min Uses", AT_Integer, "1", doc="The minimum uses this card appears in the stack with.");
			card.field("Max Uses", AT_Integer, "1", doc="The maximum uses this card appears in the stack with.");
			card.field("Target", AT_TargetSpec, "", repeatable=true, doc="A type of target this card needs to be triggered on.");
			card.field("AI", AT_Custom, "", repeatable=true, doc="Behaviour the AI follows for using this card.");

		auto@ vote = block("Vote", doc="A type of influence vote.",
				hookType="influence::InfluenceVoteEffect", hookModule="vote_effects").checkDuplicates(voteCompletions);
			vote.field("Name", AT_Locale, "", doc="Title of the vote.");
			vote.field("Description", AT_Locale, "", doc="Description of the vote.");
			vote.field("Icon", AT_Sprite, "", doc="Icon used to represent the vote.");
			vote.field("Color", AT_Color, "", doc="The vote's representative color.");
			vote.field("Target", AT_TargetSpec, "", /*repeatable=true,*/ doc="A type of target this vote needs to be triggered on.");
			vote.field("AI", AT_Custom, "", repeatable=true, doc="Behaviour the AI follows for judging this vote.");

		auto@ effect = block("Effect", doc="A type of persistent influence effect.",
				hookType="influence::InfluenceEffectEffect", hookModule="influence_effects").checkDuplicates(effectCompletions);
			effect.field("Name", AT_Locale, "", doc="Title of the effect.");
			effect.field("Description", AT_Locale, "", doc="Description of the effect.");
			effect.field("Icon", AT_Sprite, "", doc="Icon used to represent the effect.");
			effect.field("Color", AT_Color, "", doc="The effect's representative color.");
			effect.field("Default Duration", AT_Decimal, "-1", doc="The default duration an effect of this type has when triggered. A negative value indicates a permanent effect.");
			effect.field("Upkeep", AT_Decimal, "0.0", doc="The portion of influence generation having this effect active consumes, from 0.0 to 1.0.");
			effect.field("Dismissable", AT_Boolean, "True", doc="Whether this effect can be dismissed at will.");
			effect.field("Dismiss Needs Owner", AT_Boolean, "True", doc="Whether only the owner of the effect can dismiss it at will.");
			effect.field("Target", AT_TargetSpec, "", /*repeatable=true,*/ doc="A type of target this effect needs to be triggered on.");
			effect.field("Tag", AT_Custom, "", repeatable=true, doc="A tag added to the effect for future identification.");

		auto@ clause = block("Clause", doc="A clause that can be added to a treaty.",
				hookType="influence::InfluenceClauseHook", hookModule="clause_effects");
			clause.field("Name", AT_Locale, "", doc="Title of the clause.");
			clause.field("Description", AT_Locale, "", doc="Description of the clause.");
			clause.field("Icon", AT_Sprite, "", doc="Icon used to represent the clause.");
			clause.field("Color", AT_Color, "", doc="The clause's representative color.");
			clause.field("Free Clause", AT_Boolean, "False", doc="Whether this clause is available to be added freely to any treaty an empire wants to make.");
			clause.field("Team Clause", AT_Boolean, "False", doc="Whether this clause should be added to treaties created for 'Teams' from the game settings.");
			clause.field("Default Clause", AT_Boolean, "False", doc="Whether this clause is checked to be added by default for new treaties, and needs to be unchecked if players do not want to propose it.");
	}

	void onChange() {
		loadCompletions(cardCompletions, "data/influence", "Card");
		loadCompletions(voteCompletions, "data/influence", "Vote");
		loadCompletions(effectCompletions, "data/influence", "Effect");
	}
};

class ResearchFile : FileDef {
	array<string> classes = {"Boost", "Upgrade", "BigUpgrade", "Unlock", "Keystone", "Secret", "Special"};

	ResearchFile() {
		localeFile = "research.txt";
		block("Technology", doc="A type of technology that can be placed on the research grid.",
				hookType="research::ITechnologyHook", hookModule="research_effects").checkDuplicates(techCompletions);
			field("Name", AT_Locale, "", doc="Name of the technology.");
			field("Blurb", AT_Locale, "", doc="Very short description of the technology's effects, for display on the grid.");
			field("Description", AT_Locale, "", doc="Description of the technology.");
			field("Class", AT_Selection, "Upgrade", doc="The type of technology. For display purposes.").setOptions(classes);
			field("Category", AT_Custom, "", doc="The category the technology is listed under in the research editor. No effect on the game.");
			field("Icon", AT_Sprite, "", doc="Icon used to represent the technology.");
			field("Symbol", AT_Sprite, "", doc="Additional symbol displayed on the technology icon.");
			field("Color", AT_Color, "", doc="The technology's representative color.");
			field("Point Cost", AT_Decimal, "0", doc="The base amount of research points this technology costs to research.");
			field("Time Cost", AT_Decimal, "0", doc="The base time in seconds this technology takes to research.");
			field("Default Unlock", AT_Boolean, "False", doc="Whether all nodes of this technology type start unlocked by default.");
			field("Secret", AT_Boolean, "False", doc="Whether this is a secret project technology.");
		block("Grid", doc="A grid or grid overlay that can be loaded. Must be in its own separate file.").setEditMode("research_grid");
	}

	void onChange() {
		loadCompletions(techCompletions, "data/research", "Technology");
	}
};

class AttitudeFile : FileDef {
	AttitudeFile() {
		localeFile = "attitudes.txt";
		auto@ attid = block("Attitude", doc="An attitude that can be taken by an empire.",
				hookType="attitudes::IAttitudeHook", hookModule="attitude_effects").checkDuplicates(attitudeCompletions);
			attid.field("Name", AT_Locale, "", doc="Name of the attitude.");
			attid.field("Description", AT_Locale, "", doc="Description of the attitude.");
			attid.field("Progress", AT_Locale, "", doc="Locale entry used to display the attitude's progress indicator.");
			attid.field("Sort", AT_Integer, "0", doc="Sort order for the attitude in the list.");
			attid.field("Color", AT_Color, "", doc="The attitude's representative color.");

		auto@ level = attid.block("Level", doc="A level that can be reached in this attitude.",
				hookType="attitudes::IAttitudeHook", hookModule="attitude_effects");
		level.hasIdentifier = false;
			level.field("Description", AT_Locale, "", doc="Description for the effect this level has.");
			level.field("Icon", AT_Sprite, "", doc="Icon to display this level on the bar.");
			level.field("Threshold", AT_Decimal, "0", doc="The amount of progress that needs to be made in this attitude to unlock this level.");
	}

	void onChange() {
		loadCompletions(attitudeCompletions, "data/attitudes", "Attitude");
	}
};

class ResourceFile : FileDef {
	array<string> vanishModes = {"Never", "Always", "When Exported", "Exported In Combat", "Custom"};
	array<string> resourceModes = {"Normal", "Universal", "Universal Unique", "Non Requirement"};
	array<string> resourceRarities = {"Common", "Uncommon", "Rare", "Epic", "Mythical", "Unique"};
	array<string> affinityTypes = {
		"", "Money", "Influence", "Energy", "Research", "Defense", "Labor",
		"Money + Influence", "Energy + Money", "Research + Defense", "Energy + Defense",
		"Influence + Research", "ALL"
	};

	ResourceFile() {
		localeFile = "resources.txt";
		block("Resource", doc="A type of resource that can be found in the galaxy.",
				hookType="resources::IResourceHook", hookModule="resource_effects").checkDuplicates(resourceCompletions);
			field("Name", AT_Locale, "", doc="Name of the resource.");
			field("Description", AT_Locale, "", doc="Full description of the resource.");
			field("Blurb", AT_Locale, "", doc="Short blurb to describe the resource. Defaults to Description if left empty.");
			field("Small Icon", AT_Sprite, "", doc="Small icon used for compact interface display, and on the planet's distant icon in the 3D world.");
			field("Icon", AT_Sprite, "", doc="Large icon used in detailed interface display.");
			field("Native Biome", AT_PlanetBiome, "", doc="The biome that is most likely to hold this resource.");
			field("Class", AT_Custom, "", doc="Identifier of the resource class this belongs in.");
			field("Level", AT_Integer, "0", doc="The planet level required to produce this resource.");
			field("Frequency", AT_Decimal, "1", doc="Global multiplier to the occurrence of this resource, at the expense of every other resource.");
			field("Distribution", AT_Decimal, "1", doc="Multiplier to the occurrence of this resource in its level/rarity class.");
			field("Cargo Worth", AT_Integer, "0", doc="How much money killing a cargo ship is worth per unit of resource. Civilian ships carry multiple units of a resource, dependent on their type and size of ship.");
			field("Artificial", AT_Boolean, "False", doc="Whether this is considered an 'artificial' resource and not affected by terraforming.");
			field("Exportable", AT_Boolean, "True", doc="Whether this resource can be exported from its original planet, or is static on its source.");
			field("Unique", AT_Boolean, "False", doc="A unique resource can only be generated in one system in the entire universe.");
			field("Require Contestation", AT_Decimal, "0", doc="If nonzero, this resource type can only spawn in systems with a minimum contestation value. Contestation is an abstract number based on how many empires are close enough to potentially contest the system.");
			field("Mode", AT_Selection, "Normal", doc="How this resource affects planet levelup. Universal resources (Drugs) can count as any other resource. Universal Unique resources only work once per planet.").setOptions(resourceModes);
			field("Rarity", AT_Selection, "Common", doc="The resource's base rarity level.").setOptions(resourceRarities);
			field("Display Requirement", AT_Boolean, "True", doc="Whether this resource should be listed as a possibility for levelup, regardless of whether it can actually be used.");
			field("Display Weight", AT_Integer, "0", doc="What order this resource should be displayed in relative to other resources in a list.");
			field("Asteroid Frequency", AT_Decimal, "0", doc="How often this resource appears on asteroids, relative to other resources that appear on asteroids.");
			field("Asteroid Labor", AT_Decimal, "0", doc="The base amount of labor this resource costs to build an asteroid base for.");
			field("Terraform Cost", AT_Integer, "0", doc="Base amount of money it takes to terraform a planet to this resource.");
			field("Terraform Labor", AT_Integer, "0", doc="Base amount of labor it takes to terraform a planet to this resource.");
			field("Limitless Level", AT_Boolean, "False", doc="Whether the resource level counts as being a limitless level, instead of its minimum level for penalty purposes.");
			field("Rarity Level", AT_Integer, "-1", doc="If not set to -1, override the occurrence of this resource as if it was a different level.");
			field("Vanish Time", AT_Decimal, "-1", doc="For temporary resources, the amount of time before the resource vanishes.");
			field("Vanish Mode", AT_Selection, "Never", doc="Condition for when the resource is ticking down or not.").setOptions(vanishModes);
			field("Can Be Terraformed", AT_Boolean, "True", doc="Whether planets with this as their primary resource can be terraformed to something else.");
			field("Pressure", AT_TileResourceSpec, "", repeatable=true, doc="An amount of pressure this resource provides.");
			field("Affinity", AT_Selection, "", repeatable=true, doc="A resource's affinities indicate what types of resources it is associated with. Icons for each of the specified affinities will be shown next to the name of the resource. These do not currently have a gameplay effect.")
				.setOptions(affinityTypes);
	}

	void onChange() {
		loadCompletions(resourceCompletions, "data/resources", "Resource");
	}
};

class BuildingFile : FileDef {
	BuildingFile() {
		localeFile = "buildings.txt";
		block("Building", doc="A type of building that is built on a planet surface.",
			hookType="buildings::IBuildingHook", hookModule="building_effects").checkDuplicates(buildingCompletions);
			field("Name", AT_Locale, "", doc="Name of the building.");
			field("Description", AT_Locale, "", doc="Description of the building.");
			field("Sprite", AT_Sprite, "", doc="Picture used to display the building.");
			field("Category", AT_Custom, "", doc="Category under which the building is listed in the build list.");
			field("Size", AT_Custom, "1x1", doc="Size in tiles of the building on the surface grid.");
			field("Base Cost", AT_Integer, "0", doc="Base money cost to purchase this imperial building.");
			field("Tile Cost", AT_Integer, "0", doc="Extra build cost added for every tile that is not developed.");
			field("Base Maintenance", AT_Integer, "0", doc="Base maintenance cost for this imperial building.");
			field("Tile Maintenance", AT_Integer, "0", doc="Extra maintenance cost for every tile of the building that is not developed.");
			field("Labor Cost", AT_Decimal, "0", doc="How much labor this building costs to construct.");
			field("In Queue", AT_Boolean, "False", doc="Whether this building should be built in the construction queue. Automatically enabled if a labor cost is specified.");
			field("Build Time", AT_Decimal, "0", doc="For buildings with no labor cost, the time it takes to construct on the surface.");
			field("Civilian", AT_Boolean, "False", doc="Whether this is a civilian building.");
			field("Upgrades From", AT_Building, "", doc="For civilian buildings, what other building this is an 'upgrade' to.");
			field("City", AT_Boolean, "False", doc="Whether this is a city.");
			field("Saturation", AT_TileResourceSpec, "", repeatable=true, doc="For civilian structures, the amount of pressure this building takes up to be built.");
			field("Production", AT_TileResourceSpec, "", repeatable=true, doc="For civilian structures, the amount of units of resource generation this building grants.");
			field("Pressure Cap", AT_Integer, "1", repeatable=true, doc="For civilian structures, the amount of pressure capacity this building takes up from the total cap when built.");
			field("Build Affinity", AT_PlanetBiome, "", repeatable=true, doc="Undeveloped tiles of the specified biome do not add their 'Tile Cost' to the building's initial build cost.");
			field("Maintenance Affinity", AT_PlanetBiome, "", repeatable=true, doc="Undeveloped tiles of the specified biome do not add their 'Maintenance Cost' to the building's maintenance cost.");
	}

	void onChange() {
		loadCompletions(buildingCompletions, "data/buildings", "Building");
	}
};

class ConstructionFile : FileDef {
	ConstructionFile() {
		localeFile = "constructions.txt";
		block("Construction", doc="A construction that can be built generically.",
			hookType="constructions::IConstructionHook", hookModule="construction_effects").checkDuplicates(constructionCompletions);
			field("Name", AT_Locale, "", doc="Name of the construction.");
			field("Description", AT_Locale, "", doc="Description of the construction.");
			field("Icon", AT_Sprite, "", doc="Picture used to display the construction.");
			field("Category", AT_Custom, "", doc="Category under which the construction is listed in the build list.");
			field("Build Cost", AT_Integer, "0", doc="Base money cost for constructing this.");
			field("Labor Cost", AT_Integer, "0", doc="Base labor cost for constructing this. Only one of Time or Labor cost must be specified.");
			field("Time Cost", AT_Integer, "0", doc="Time cost for constructing this, independent of labor generation. Only one of Time or Labor cost must be specified.");
			field("Maintenance Cost", AT_Integer, "0", doc="Base maintenance for constructing this. Note: Applied permanently after being constructed.");
			field("Target", AT_TargetSpec, "", /*repeatable=true,*/ doc="A type of target this construction needs to be triggered on.");
			field("In Context", AT_Boolean, "False", doc="Whether to show this construction in the context menu where appropriate.");
	}

	void onChange() {
		loadCompletions(constructionCompletions, "data/constructions", "Construction");
	}
};

class BiomeFile : FileDef {
	BiomeFile() {
		localeFile = "biomes.txt";
		block("Biome", doc="A type of biome for on a planet.").checkDuplicates(biomeCompletions);
			field("Name", AT_Locale, "", doc="Title of the biome.");
			field("Description", AT_Locale, "", doc="Description of the biome.");
			field("Sprite", AT_Sprite, "", doc="Icon used to represent the biome.");
			field("Color", AT_Color, "", doc="The biome's representative color.");
			field("Temperature", AT_Decimal, "0.5", doc="The biome's relative temperature, from 0 to 1.");
			field("Humidity", AT_Decimal, "0.5", doc="The biome's relative humidity, from 0 to 1.");
			field("Frequency", AT_Integer, "1", doc="The relative frequency this biome appears in.");
			field("UseWeight", AT_Decimal, "1", doc="Relative weight for civilians to develop this tile compared to other tiles.");
			field("BuildCost", AT_Decimal, "1", doc="Multiplier to imperial building cost on this tile.");
			field("BuildTime", AT_Decimal, "1", doc="Multiplier to civilian build time of this tile.");
			field("IsVoid", AT_Boolean, "False", doc="Whether this is a void.");
			field("IsWater", AT_Boolean, "False", doc="Whether this is water.");
			field("IsCrystallic", AT_Boolean, "False", doc="Whether this is crystallic.");
			field("IsMoon", AT_Boolean, "False", doc="Whether this is on a moon.");
			field("Buildable", AT_Boolean, "False", doc="Whether this can have buildings on it.");
			field("Picks", AT_Custom, "", doc="Special UV values for biomes using the procedural planet shader.");
			field("Lookup Range", AT_Custom, "", doc="Special UV values for biomes using the procedural planet shader.");
	}

	void onChange() {
		loadCompletions(biomeCompletions, "data/biomes", "Biome");
	}
};

class CreepFile : FileDef {
	CreepFile() {
		localeFile = "creeps.txt";
		auto@ camp = block("Camp", doc="A particular type of remnant camp that can be spawned.").checkDuplicates(creepCompletions);
			camp.field("Frequency", AT_Decimal, "1", doc="Frequency of this camp spawning, relative to other types of camps' frequency.");
			camp.field("Ship", AT_Custom, "", repeatable=true, doc="A remnant ship spawned to defend the pickup in this camp.");
			camp.field("Target Strength", AT_Decimal, "", doc="If specified, generate a random fleet close to the specified strength.");
			camp.field("Flagship Size", AT_Integer, "", doc="If specified, generate a random remnant design of this size to protect the camp.");
			camp.field("Support Occupation", AT_Decimal, "1.0", doc="If a flagship size is specified for a randomized design, how much of its support capacity should be filled with support ships.");
			camp.field("Remnant Status", AT_Status, "", repeatable=true, doc="Add a status effect that is added to all remnant flagships generated in this creep camp.");
			camp.field("Region Status", AT_Status, "", repeatable=true, doc="While this camp is not yet defeated, all objects in the system it is in are given the specified status.");

		auto@ pickup = camp.block("Pickup", doc="A possible type of pickup reward to be spawned with this camp.",
				hookType="pickup_effects::IPickupHook", hookModule="pickup_effects");
			pickup.field("Frequency", AT_Decimal, "1", doc="Frequency of the camp having this pickup, relative to the other pickups' frequency.");
			pickup.field("Name", AT_Locale, "", doc="Name of the pickup.");
			pickup.field("Description", AT_Locale, "", doc="Description of the pickup.");
			pickup.field("Verb", AT_Locale, "#VERB_PICKUP", doc="Verb used for the pickup option.");
			pickup.field("Model", AT_Model, "Research_Station", doc="Model for the pickup.");
			pickup.field("Material", AT_Material, "GenericPBR_Research_Station", doc="Model material for the pickup.");
			pickup.field("Physical Size", AT_Decimal, "5.0", doc="Physical size of the pickup in the world.");
	}

	void onChange() {
		loadCompletions(creepCompletions, "data/creeps", "Camp");
	}
};

class OrbitalFile : FileDef {
	OrbitalFile() {
		localeFile = "orbitals.txt";
		block("Module", doc="A type of orbital module that can be constructed.",
				hookType="orbital_effects::IOrbitalEffect", hookModule="orbital_effects").checkDuplicates(orbitalCompletions);
			field("Name", AT_Locale, "", doc="Name of the orbital.");
			field("Description", AT_Locale, "", doc="Description of the orbital.");
			field("Blurb", AT_Locale, "", doc="Short blurb to describe the orbital. Defaults to Description if left empty.");
			field("Icon", AT_Sprite, "", doc="Icon used to represent the orbital.");
			field("Icon Size", AT_Decimal, "0.03", doc="Size of the orbitals's distant icon.");
			field("Distant Icon", AT_Sprite, "", doc="Icon used in the 3D view on the orbital's distant icon.");
			field("Strategic Icon", AT_Sprite, "", doc="Icon used in the 3D view for the orbital's strategic icon.");
			field("Spin", AT_Decimal, "30", doc="Speed at which the orbital spins.");
			field("Solid", AT_Boolean, "True", doc="Whether the orbital is considered solid and pushes things away.");
			field("Maintenance", AT_Integer, "0", doc="The orbital's maintenance cost.");
			field("Build Cost", AT_Integer, "0", doc="The orbital's build cost.");
			field("Labor Cost", AT_Decimal, "0", doc="The orbital's labor cost.");
			field("Combat Repair", AT_Boolean, "True", doc="Whether the orbital can repair when in combat.");
			field("Can Fling", AT_Boolean, "True", doc="Whether this orbital can be FTLed with fling.");
			field("Health", AT_Decimal, "0", doc="The orbital's base maximum health.");
			field("Armor", AT_Decimal, "0", doc="The orbital's base maximum armor. Armor is additional health on top of base health that has damage reduction.");
			field("Size", AT_Decimal, "10", doc="The physical size of the orbital in the world.");
			field("Mass", AT_Decimal, "-1", doc="The physical mass of the orbital (used in tractoring). Set to -1 to auto-calculate based on Size.");
			field("Model", AT_Model, "", doc="Model for the orbital.");
			field("Material", AT_Material, "", doc="Model material for the orbital.");
	}

	void onChange() {
		loadCompletions(orbitalCompletions, "data/orbitals", "Module");
	}
};

class TraitFile : FileDef {
	TraitFile() {
		localeFile = "traits.txt";
		block("Trait", doc="A trait that can be taken at game start.",
				hookType="trait_effects::ITraitEffect", hookModule="trait_effects").checkDuplicates(traitCompletions);
			field("Name", AT_Locale, "", doc="Name of the trait.");
			field("Description", AT_Locale, "", doc="Description of the trait.");
			field("Icon", AT_Sprite, "", doc="Icon used to represent the trait.");
			field("Color", AT_Color, "", doc="The trait's representative color.");
			field("Costs Points", AT_Integer, "0", doc="Amount of points this trait costs to take.");
			field("Gives Points", AT_Integer, "0", doc="Amount of points this trait gives when taken.");
			field("Category", AT_Custom, "", doc="Category that the trait is listed in.");
			field("Order", AT_Integer, "0", doc="Order of the trait in the category's list.");
			field("Unique", AT_Custom, "", doc="If specified, only one trait with the same 'unique' tag can be chosen at a time.");
			field("Default", AT_Boolean, "False", doc="Whether this trait should be chosen by default.");
			field("AI Support", AT_Boolean, "True", doc="Whether the AI knows how to deal with this trait.");
			field("Available", AT_Boolean, "True", doc="Whether this trait is available to be chosen at all.");
			field("Conflict", AT_Trait, "", repeatable=true, doc="Another trait that cannot be taken at the same time as this trait.");
	}

	void onChange() {
		loadCompletions(traitCompletions, "data/traits", "Trait");
	}
};

class SubsystemFile : FileDef {
	SubsystemFile() {
		localeFile = "subsystems.txt";
		auto@ sys = block("Subsystem", doc="A subsystem type that can be placed on a design.",
				hookType="subsystem_effects::SubsystemHook", hookModule="subsystem_effects").checkDuplicates(subsysCompletions);
		sys.hookPrefix = "Hook: ";
		sys.field("Name", AT_Locale, "", doc="The subsystem's name.");
		sys.field("Description", AT_Locale, "", doc="The subsystem's description.");
		sys.field("BaseColor", AT_Color, "", doc="Color of the hexagon base/floor that the subsystem is drawn on.");
		sys.field("TypeColor", AT_Color, "", doc="Color contribution of this subsystem to the ship's overall type color.");
		sys.field("Elevation", AT_Integer, "0", doc="Elevation of this subsystem's hexes in the isometric hex view.");
		sys.field("Tags", AT_Custom, "", doc="A list of comma-separated arbitrary tags that the subsystem is assigned with.");
		sys.field("Hull", AT_Custom, "", doc="List of comma-separated hull types that this subsystem can be used on.");
		sys.field("EvaluationOrder", AT_Integer, "0", doc="Subsystems with lower evaluation orders are executed before higher ones. This is significant for the order in which modifiers and asserts are executed.");
		sys.field("DamageOrder", AT_Integer, "0", doc="Indicates the order in which this subsystem's GlobalDamage events are run. This does not have any effect on normal hex-based damage, only on globaldamage interception steps that happen beforehand.");
		sys.field("OnCheckErrors", AT_Custom, "", doc="Script function that is used to check the subsystem for design errors when placed.");

		vars(sys);
		sysInner(sys);
		effBlock(sys);

		auto@ templ = block("Template", doc="All blocks inside this template are added to subsystems that match the template's condition.");
		templ.identifierLimit = false;
		sysInner(templ);
		effBlock(templ);

		auto@ defaults = templ.block("Defaults", doc="Default values for variables that can be overwritten.");
		defaults.hasIdentifier = false;
		vars(defaults);
	}

	void sysInner(BlockDef@ sys) {
		sys.field("AddShipModifier", AT_Custom, "", repeatable=true, doc="If this subsystem is present, the specified modifier is applied to every subsystem on the ship with a higher evaluation order.");
		sys.field("AddPostModifier", AT_Custom, "", repeatable=true, doc="This modifier is added to this subsystem after all other subsystems have been evaluated.");
		sys.field("AddAdjacentModifier", AT_Custom, "", repeatable=true, doc="If this subsystem is present, the specified modifier is applied to every hex adjacent to this hex.");

		auto@ modif = sys.block("Modifier", doc="A modifier function that can be applied to this subsystem.");
		modif.identifierLimit = false;
		modif.field("Stage", AT_Integer, "", doc="Sets a static evaluation stage for this modifier. Not needed in most cases.");
		vars(modif);

		auto@ modu = sys.block("Module", doc="Every hex on the subsystem has exactly one module on it. Modules are parts of the subsystem that can behave differently, ie the default module, modifiers, or the core/turret module.",
				hookType="subsystem_effects::SubsystemHook", hookModule="subsystem_effects");
		modu.hookPrefix = "Hook: ";
		modu.field("Name", AT_Locale, "", doc="Name of the module.");
		modu.field("Description", AT_Locale, "", doc="Description of the module.");
		modu.field("Color", AT_Color, "", doc="The module's color.");
		modu.field("Required", AT_Boolean, "False", doc="Whether every subsystem is required to have at least one of these modules. 'Core' modules are implied to be required.");
		modu.field("Unique", AT_Boolean, "False", doc="Whether subsystems can only have up to one of these modules in them. 'Core' modules are implied to be unique.");
		modu.field("Vital", AT_Boolean, "False", doc="Whether subsystems are deactivated when a module of this type is destroyed. 'Core' modules are implied to be vital.");
		modu.field("DefaultUnlock", AT_Boolean, "False", doc="Whether empires have access to this module by default. 'Core' and 'Default' modules are implied to be unlocked by default.");
		modu.field("Sprite", AT_Sprite, "", doc="Sprite that is rendered on the isometric design view.");
		modu.field("DrawMode", AT_Integer, "0", doc="The way the sprite is drawn on the design. 0 indicates a singular sprite, 1 is used for rotatable turrets.");
		modu.field("OnEnable", AT_Custom, "", doc="Script function that is called when this module gets enabled.");
		modu.field("OnDisable", AT_Custom, "", doc="Script function that is called when this module gets disabled.");
		modu.field("AddModifier", AT_Custom, "", repeatable=true, doc="If this module is present in a subsystem, the specified modifier is added to the entire subsystem.");
		modu.field("AddUniqueModifier", AT_Custom, "", repeatable=true, doc="If this module is present in a subsystem, the specified modifier is added to the entire subsystem, but only once, regardless of the amount of modules.");
		modu.field("AddAdjacentModifier", AT_Custom, "", repeatable=true, doc="The specified modifier is applied to every hex adjacent to the module's hex.");

		vars(modu);
		effBlock(modu);
		asserts(modu);

		auto@ efftr = sys.block("Effector", doc="An effector that can trigger projectiles on objects.");
		vals(efftr);

		asserts(sys);
	}

	void asserts(BlockDef@ sys) {
		auto@ ass = sys.block("Assert", doc="A criterion that must be satisfied for the subsystem.");
		ass.identifierLimit = false;
		ass.field("Unique", AT_Boolean, "False", doc="Whether this criterion should only be checked once per ship.");
		ass.field("Fatal", AT_Boolean, "True", doc="Whether failing this criterion makes the design invalid and unable to be saved.");
		ass.field("Message", AT_Locale, "", doc="The message for failing the criterion.");

		auto@ req = sys.block("Requires", doc="A list of ship variable requirements.");
		vals(req);
		req.hasIdentifier = false;

		auto@ prov = sys.block("Provides", doc="A list of ship variable provisions.");
		vals(prov);
		prov.hasIdentifier = false;
	}

	void effBlock(BlockDef@ sys) {
		auto@ eff = sys.block("Effect", doc="An effect that is active while the subsystem or module is.");
		vals(eff);
	}

	void vars(BlockDef@ sys) {
		sys.field("Variable", AT_VariableDef, "", repeatable=true, doc="An arbitrary variable that can store data about this subsystem and be used.")
			.setCondition(VariableCondition()).setFullLine(true);
	}

	void vals(BlockDef@ blk) {
		blk.field("Value", AT_ValueDef, "", repeatable=true, doc="A filled in value for a particular block.")
			.setCondition(ValueCondition()).setFullLine(true);
	}

	void onChange() {
		loadCompletions(subsysCompletions, "data/subsystems", "Subsystem");
	}
};

class EffectorFile : FileDef {
	array<string> efficiencyModes = {"Normal", "Reload Only", "Duration Only", "Reload Partial", "Duration Partial"};
	array<string> physicalTypes = {"Instant", "Projectile", "Missile", "Beam", "Aimed Missile"};

	EffectorFile() {
		auto@ efftr = block("Effector", doc="An effector that can trigger projectiles on objects.");
		field("Value", AT_Custom, "", repeatable=true, doc="A value that can be passed in by the subsystem using the effector. A default value can also be specified.");
		field("Range", AT_Custom, "", doc="Formula based on values for the range at which this effector can activate.");
		field("Lifetime", AT_Custom, "", doc="Formula based on values for the lifetime of the projectile.");
		field("Speed", AT_Custom, "", doc="Formula based on values for the speed of the projectile.");
		field("Tracking", AT_Custom, "", doc="Formula based on values for the projectile/turret's tracking speed.");
		field("Spread", AT_Custom, "", doc="Formula based on values for the spread angle of the turret. A higher spread means a more inaccurate weapon.");
		field("CapTarget", AT_Custom, "", doc="Formula based on values for the amount of times to fire before switching targets.");
		field("FireArc", AT_Custom, "", doc="Formula based on values for the firing arc angle of the turret, expressed in radians.");
		field("TargetTolerance", AT_Custom, "", doc="Formula based on values for how far from the firing arc turrets will target enemies, expressed in radians.");
		field("FireTolerance", AT_Custom, "", doc="Formula based on values for how far from the firing arc turrets will fire at enemies, expressed in radians.");
		field("TargetAlgorithm", AT_Custom, "", doc="Algorithm used for targeting nearby enemies. Should be set to 'SingleTarget' almost all of the time.");
		field("Activation", AT_Custom, "", doc="Function that governs the activation cycle of the turret.");
		field("OnTrigger", AT_Custom, "", doc="Function that can be called when the effector triggers.");
		field("CanTarget", AT_Custom, "", doc="Expression that determines whether this turret can fire at a particular object.");
		field("AutoTarget", AT_Custom, "", doc="Expression that determines whether this turret should automatically target a particular object when in range.");
		field("Physical", AT_Boolean, "True", doc="Whether the projectile should be physically simulated and can miss, or should always hits its intended target.");
		field("EfficiencyMode", AT_Selection, "Normal", doc="The way increased or decreased efficiency effects the turret's behaviour. When set to reload, the reload time of the turret is affected by efficiency. When set to duration, the duration of a beam is affected by efficiency. When set to partial, only part of the increased efficiency is used this way, and the rest is passed along to the effect (to, for example, deal increased damage).")
			.setOptions(efficiencyModes);
		field("PhysicalType", AT_Selection, "Instant", doc="The type of projectile that is emitted by this effector.")
			.setOptions(physicalTypes);
		field("PhysicalSize", AT_Decimal, "1.0", doc="The relative physical size of the projectile.");
		gfx(efftr);

		auto@ skin = efftr.block("Skin", doc="A secondary graphical skin for this effector that can be selected from a subsystem or from the empire's weapon skin.");
		skin.field("Inherit", AT_Custom, "", doc="Copy over the graphical values from a different non-default skin.").setPriority(-100);
		gfx(skin);

		auto@ eff = efftr.block("Effect", doc="An effect that is activated on the target object when hit. Only one is allowed per effector.");
		eff.field("Value", AT_ValueDef, "", repeatable=true, doc="A filled in value that is passed to the effect.")
			.setCondition(ValueCondition()).setFullLine(true);
	}

	array<string> gfxTypes = {"Sprite", "Line", "Beam"};
	void gfx(BlockDef@ b) {
		b.field("GfxType", AT_Selection, "Sprite", doc="The type of graphics associated with the projectile.")
			.setOptions(gfxTypes);
		b.field("GfxSize", AT_Decimal, "1.0", doc="The relative size of the projectile graphics.");
		b.field("Trail", AT_Material, "", doc="The material for the graphics trail.");
		b.field("TrailCol", AT_Custom, "", doc="The color(s) for the graphics trail.");
		b.field("Color", AT_Color, "", doc="The override color for the projectile.");
		b.field("Color", AT_Color, "", doc="The override color for the projectile.");
		b.field("ImpactGfx", AT_Custom, "", doc="Particle system to play when the projectile impacts.");
		b.field("Material", AT_Material, "", doc="Material to display the projectile with.");
		b.field("ImpactSfx", AT_Custom, "", doc="Sound effect to play when the projectile impacts.");
		b.field("FireSfx", AT_Custom, "", repeatable=true, doc="Sound effect to play when the turret fires. When multiple FireSfx entries are specified, one is chosen randomly every time the weapon fires.");
		b.field("FirePitchVariance", AT_Decimal, "0", doc="Variance in the fire sound's pitch.");
	}
};

class MaterialFile : FileDef {
	array<string> sheetModes = {"Horizontal", "Vertical"};
	MaterialFile() {
		defaultBlock.doc = "[font=Subtitle]Note: Changes to material files will not be updated on other pages until the game is restarted.[/font]";

		auto@ mat = block("Material", doc="A material that can be rendered on models or in the GUI.");
		mat.closeDefault = true;
		common(mat);

		auto@ sheet = block("SpriteSheet", doc="A material that consists of multiple sprites laid out in a spritesheet.");
		sheet.closeDefault = true;
		sheet.field("Size", AT_Custom, "", doc="Size of each individual sprite in the sheet, expressed as 'width,height'.");
		sheet.field("Spacing", AT_Integer, "", doc="Spacing in front of each individual sprite in the sheet, in pixels.");
		sheet.field("Mode", AT_Selection, "Horizontal", doc="Whether the spritesheet should be numbered left to right first (horizontal), or top to bottom first (vertical).")
			.setOptions(sheetModes);
		common(sheet);

		auto@ grp = block("MaterialGroup", doc="A group of materials automatically generated from all images in a folder, according to a template.");
		grp.closeDefault = true;
		grp.field("Folder", AT_File, "", doc="Path to the folder that images are taken from.");
		grp.field("Prefix", AT_Custom, "", doc="Prefix added to the filenames in the folder to make the names of the related materials.");
		grp.field("Template", AT_Custom, "", doc="A material declared earlier in the file that materials generated from the folder are based on.");
	}

	array<string> depthTest = {"", "Never", "Less", "LessEqual", "Equal", "GreaterEqual", "Greater", "Always", "NoDepthTest"};
	array<string> culling = {"", "None", "Front", "Back", "Both"};
	array<string> wrapModes = {"", "Repeat", "Clamp", "ClampEdge", "Mirror"};
	array<string> filters = {"", "Linear", "Nearest"};
	array<string> modes = {"", "Fill", "Line"};
	array<string> blends = {"", "Alpha", "Solid", "Add", "Overlay", "Font"};
	void common(BlockDef@ b) {
		b.field("Inherit", AT_Custom, "", doc="Copy material render data from a builtin material or one defined earlier in the file.\n\nCommonly used to inherit the Image2D engine material, indicating that a material is intended for GUI use.").setPriority(-100);

		b.field("LoadPriority", AT_Custom, "", doc="Indicates at what stage of the game the texture should be ensured to be loaded. Can be set to a number (higher is earlier), or one of 'Critical', 'Menu', 'Game', 'High', or 'Low'. Textures with a priority lower than 'Game' will be streamed while the game is already running.").setPriority(-10);

		for(uint i = 1; i <= 6; ++i) {
			string key = "Texture";
			if(i != 1)
				key += i;
			b.field(key, AT_File, "", doc="The file location of a png texture that this material renders with.").setPriority(10);
		}

		b.field("Shader", AT_Custom, "", doc="Name of the shader to use for rendering this material.");
		b.field("DepthWrite", AT_Boolean, "True", doc="Whether the material should write to the depth buffer.");
		b.field("DepthTest", AT_Selection, "", doc="How the material should test against the depth buffer.")
			.setOptions(depthTest);
		b.field("Culling", AT_Selection, "", doc="How the material should apply face culling.")
			.setOptions(culling);
		b.field("Lighting", AT_Boolean, "True", doc="Whether the material should use lighting.");
		b.field("NormalizeNormals", AT_Boolean, "False", doc="Whether to normalize the normal values when this material is rendered.");
		b.field("Shininess", AT_Decimal, "", doc="Shininess factor for lighting when this material is rendered.");
		b.field("WrapVertical", AT_Selection, "", doc="What behaviour should be used for wrapping texture lookups beyond the vertical edges of the material.")
			.setOptions(wrapModes);
		b.field("WrapHorizontal", AT_Selection, "", doc="What behaviour should be used for wrapping texture lookups beyond the horizontal edges of the material.")
			.setOptions(wrapModes);
		b.field("FilterMin", AT_Selection, "", doc="When the texture is scaled down, which texture filter method to use.")
			.setOptions(filters);
		b.field("FilterMag", AT_Selection, "", doc="When the texture is scaled up, which texture filter method to use.")
			.setOptions(filters);
		b.field("DrawMode", AT_Selection, "", doc="The mode that the texture draws on top of a model with.")
			.setOptions(modes);
		b.field("Blend", AT_Selection, "", doc="How the material blends with things rendered behind it.")
			.setOptions(blends);
		b.field("Alpha", AT_Boolean, "False", doc="Whether the material should use alpha rendering.");
		b.field("Diffuse", AT_Color, "", doc="Color to use for the material's diffuse lighting.");
		b.field("Specular", AT_Color, "", doc="Color to use for the material's specular lighting.");
	}
};

class SoundFile : FileDef {
	SoundFile() {
		auto@ snd = block("Sound", doc="A sound effect that can be played in the game.");
		snd.closeDefault = true;
		common(snd);

		auto@ strm = block("Stream", doc="A sound effect that is streamed as it is played. Should be used for longer sound effects.");
		strm.closeDefault = true;
		common(strm);
	}

	void common(BlockDef@ b) {
		field("File", AT_File, "", doc="Path to the .ogg file that contains the sound.");
		field("Volume", AT_Decimal, "1", doc="Relative volume to play the sound at.");
	}
};

class EventFile : FileDef {
	EventFile() {
		localeFile = "random_events.txt";
		auto@ evt = block("Event", doc="A random event that can be triggered in game when conditions are met.",
				hookType="random_events::IRandomEventHook", hookModule="event_effects").checkDuplicates(eventCompletions);
		evt.field("Name", AT_Locale, "", doc="Name of the random event.");
		evt.field("Text", AT_Locale, "", doc="Text and narrative of the random event.");
		evt.field("Frequency", AT_Decimal, "1.0", doc="Rate at which this random event occurs relative to other random events.");
		evt.field("Timer", AT_Decimal, "180", doc="Time in seconds that the choice is available. If it runs out, the first available Default option is chosen automatically.");
		evt.field("Unique", AT_Boolean, "True", doc="Unique events can only occur once per game.");
		evt.field("Target", AT_TargetSpec, "", repeatable=true, doc="A type of target this event triggers on.");

		auto@ opt = evt.block("Option", doc="An option that can be chosen for this event.",
				hookType="random_events::IRandomOptionHook", hookModule="event_effects");
		opt.field("Text", AT_Locale, "", doc="Text and narrative of the option.");
		opt.field("Icon", AT_Sprite, "", doc="Icon used to represent the option.");
		opt.field("Safe", AT_Boolean, "True", doc="Whether this option is safe and cannot result in horrible unwanted consequences. Mainly used by the AI for decision making.");
		opt.field("Default", AT_Boolean, "False", doc="When the timer runs out on a random event, the first available option that has Default set is chosen.");

		auto@ res = opt.block("Result", doc="One particular result that may occur. The chance specified is the chance of this result happening rather than any other result.",
				hookType="random_events::IRandomOptionHook", hookModule="event_effects");

		res.block("On", doc="Hooks inside an On block are applied on the target specified by the On block, instead of only on the event's owning empire.",
				hookType="random_events::IRandomOptionHook", hookModule="event_effects");
		opt.block("On", doc="Hooks inside an On block are applied on the target specified by the On block, instead of only on the event's owning empire.",
				hookType="random_events::IRandomOptionHook", hookModule="event_effects");
	}

	void onChange() {
		loadCompletions(eventCompletions, "data/random_events", "Event");
	}
};

class CargoFile : FileDef {
	CargoFile() {
		localeFile = "resources.txt";
		block("Cargo", doc="A type of cargo that can be stored and moved.");
			field("Name", AT_Locale, "", doc="Name of the cargo type.");
			field("Description", AT_Locale, "", doc="Description of the cargo type.");
			field("Icon", AT_Sprite, "", doc="Icon used to display the cargo.");
			field("Color", AT_Color, "", doc="Color used to display the cargo.");
			field("Storage Size", AT_Decimal, "1.0", doc="Size of one unit of this cargo in cargo storage.");
	}

	void onChange() {
		loadCompletions(cargoCompletions, "data/cargo", "Cargo");
	}
};
