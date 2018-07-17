#priority init 6000
import settings.game_settings;
import traits;

export EmpireColor, getEmpireColor, getEmpireColorCount;
array<EmpireColor@> colors;

final class EmpireColor {
	uint id;
	Color color;
	const Material@ background;
	string backgroundDef;
};

EmpireColor@ getEmpireColor(uint id) {
	if(id >= colors.length)
		return null;
	return colors[id];
}

EmpireColor@ getEmpireColor(const Color& col) {
	EmpireColor@ closest;
	double dist = INFINITY;
	for(uint i = 0, cnt = colors.length; i < cnt; ++i) {
		double d = sqr(int(col.r) - int(colors[i].color.r));
		d += sqr(int(col.g) - int(colors[i].color.g));
		d += sqr(int(col.b) - int(colors[i].color.b));

		if(d < dist) {
			dist = d;
			@closest = colors[i];
		}
	}
	return closest;
}

uint getEmpireColorCount() {
	return colors.length;
}

export EmpirePortrait, getEmpirePortrait, getEmpirePortraitCount;
array<EmpirePortrait@> portraits;
dictionary portraitIdents;

final class EmpirePortrait {
	uint id;
	string ident;
	const Material@ portrait;
	string portraitDef;
};

EmpirePortrait@ getEmpirePortrait(uint id) {
	if(id >= portraits.length)
		return null;
	return portraits[id];
}

EmpirePortrait@ getEmpirePortrait(const string& ident) {
	EmpirePortrait@ portrait;
	portraitIdents.get(ident, @portrait);
	return portrait;
}

uint getEmpirePortraitCount() {
	return portraits.length;
}

export EmpireFlag, getEmpireFlag, getEmpireFlagCount;
array<EmpireFlag@> flags;

final class EmpireFlag {
	uint id;
	const Material@ flag;
	string flagDef;
};

EmpireFlag@ getEmpireFlag(uint id) {
	if(id >= flags.length)
		return null;
	return flags[id];
}

EmpireFlag@ getEmpireFlag(const string& ident) {
	for(uint i = 0, cnt = flags.length; i < cnt; ++i)
		if(flags[i].flagDef == ident)
			return flags[i];
	return null;
}

uint getEmpireFlagCount() {
	return flags.length;
}

export EmpireWeaponSkin, getEmpireWeaponSkin, getEmpireWeaponSkinCount;
array<EmpireWeaponSkin@> skins;

final class EmpireWeaponSkin {
	uint id;
	Sprite icon;
	string ident;
};

EmpireWeaponSkin@ getEmpireWeaponSkin(uint id) {
	if(id >= skins.length)
		return null;
	return skins[id];
}

uint getEmpireWeaponSkinCount() {
	return skins.length;
}

export RacePreset, getRacePreset, getRacePresetCount;
array<RacePreset@> presets;

final class RacePreset {
	uint id;
	string ident;

	string name;
	string tagline;
	string description;
	string lore;
	string portrait;
	string shipset;
	string weaponSkin;
	string dlc;
	bool isHard = false;
	bool aiSupport = true;

	array<const Trait@> traits;

	void apply(EmpireSettings& settings) const {
		settings.raceName = name;
		settings.portrait = portrait;
		settings.traits = traits;
		if(settings.shipset.length == 0)
			settings.shipset = shipset;
		settings.effectorSkin = weaponSkin;
	}

	bool equals(EmpireSettings& settings) const {
		if(settings.raceName != name)
			return false;
		if(settings.portrait != portrait)
			return false;
		if(settings.traits != traits)
			return false;
		return true;
	}
};


export exportRace, importRace, loadRaces;
const int RACE_SERIALIZE_VERSION = 1;

void exportRace(EmpireSettings& settings, const string& filename) {
	JSONTree tree;
	JSONNode@ root = tree.root.makeObject();

	root["__VERSION__"] = RACE_SERIALIZE_VERSION;
	root["name"] = settings.raceName;
	root["portrait"] = settings.portrait;
	root["weaponSkin"] = settings.effectorSkin;
	root["shipset"] = settings.shipset;

	JSONNode@ sysList = root["traits"].makeArray();

	for(uint i = 0, cnt = settings.traits.length; i < cnt; ++i)
		sysList.pushBack() = settings.traits[i].ident;

	tree.writeFile(filename, true);
}

bool importRace(EmpireSettings& settings, const string& filename) {
	JSONTree tree;
	tree.readFile(filename);

	JSONNode@ root = tree.root;
	if(!root.isObject() || !root["name"].isString() || !root["portrait"].isString())
		return false;

	settings.raceName = root["name"].getString();
	settings.portrait = root["portrait"].getString();

	auto@ skinElem = root["weaponSkin"];
	if(skinElem.isString())
		settings.effectorSkin = skinElem.getString();

	auto@ shipset = root["shipset"];
	if(shipset.isString())
		settings.shipset = shipset.getString();

	JSONNode@ traits = root["traits"];
	if(!traits.isArray())
		return false;

	settings.traits.length = 0;
	uint cnt = traits.size();
	for(uint i = 0; i < cnt; ++i) {
		JSONNode@ node = traits[i];
		if(!node.isString())
			continue;
		auto@ trait = getTrait(node.getString());
		if(trait !is null && trait.available)
			settings.traits.insertLast(trait);
	}

	return true;
}

void loadRaces(array<EmpireSettings@>& list, const string& folder, bool recursive = true) {
	FileList files(folder, "*.race", recursive);
	uint cnt = files.length;
	for(uint i = 0; i < cnt; ++i) {
		EmpireSettings settings;
		if(importRace(settings, files.path[i]))
			list.insertLast(settings);
	}
}

RacePreset@ getRacePreset(uint id) {
	if(id >= presets.length)
		return null;
	return presets[id];
}

uint getRacePresetCount() {
	return presets.length;
}

export EmpirePortraitCreation;
class EmpirePortraitCreation {
	array<EmpireColor@> availColors;
	array<EmpirePortrait@> availPortraits;
	array<EmpireFlag@> availFlags;

	void reset() {
		availColors.length = 0;
		availPortraits.length = 0;
		availFlags.length = 0;
	}

	void randomize(EmpireSettings& settings, bool fillOnly = false) {
		if(settings.color.color == colors::White.color || !fillOnly) {
			if(availColors.length == 0)
				availColors = colors;

			int index = 0;
			settings.color = availColors[index].color;
			availColors.removeAt(index);
		}

		if(settings.portrait == uint(-1) || !fillOnly) {
			if(availPortraits.length == 0)
				availPortraits = portraits;

			int index = randomi(0, availPortraits.length-1);
			settings.portrait = availPortraits[index].ident;
			availPortraits.removeAt(index);
		}

		if(settings.flag == uint(-1) || !fillOnly) {
			if(availFlags.length == 0)
				availFlags = flags;

			int index = randomi(0, availFlags.length-1);
			settings.flag = availFlags[index].flagDef;
			availFlags.removeAt(index);
		}
	}

	void apply(EmpireSettings& settings, Empire@ emp) {
		//Fill in the random variables
		randomize(settings, fillOnly = true);

		//Set materials
		emp.color = settings.color;

		auto@ color = getEmpireColor(emp.color);
		emp.backgroundDef = color.backgroundDef;
		@emp.background = color.background;

		auto@ prt = getEmpirePortrait(settings.portrait);
		if(prt is null)
			@prt = getEmpirePortrait(emp.id % getEmpirePortraitCount());
		emp.portraitDef = prt.portraitDef;
		@emp.portrait = prt.portrait;

		auto@ flag = getEmpireFlag(settings.flag);
		if(flag is null)
			@flag = getEmpireFlag(emp.id % getEmpireFlagCount());
		emp.flagDef = flag.flagDef;
		emp.flagID = flag.id;
		@emp.flag = flag.flag;
	}
};

void load(const string& filename) {
	ReadFile file(filename, true);
	EmpireColor@ prevColor;
	EmpireWeaponSkin@ skin;
	RacePreset@ prevPreset;
	
	while(file++) {
		if(file.key.equals_nocase("Color")) {
			EmpireColor col;
			col.id = colors.length;
			col.color = toColor(file.value);

			@prevColor = col;
			colors.insertLast(col);
		}
		else if(file.key.equals_nocase("WeaponSkin")) {
			if(file.indent > 0 && prevPreset !is null) {
				prevPreset.weaponSkin = file.value;
			}
			else {
				@skin = EmpireWeaponSkin();
				skin.id = skins.length;
				skin.ident = file.value;

				skins.insertLast(skin);
			}
		}
		else if(file.key.equals_nocase("Preset")) {
			RacePreset preset;
			preset.id = presets.length;
			preset.ident = file.value;

			@prevPreset = preset;
			presets.insertLast(preset);
		}
		else if(file.key.equals_nocase("Name")) {
			if(prevPreset !is null) {
				prevPreset.name = localize(file.value);
			}
			else {
				file.error("Name outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("Description")) {
			if(prevPreset !is null) {
				prevPreset.description = localize(file.value);
			}
			else {
				file.error("Description outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("Tagline")) {
			if(prevPreset !is null) {
				prevPreset.tagline = localize(file.value);
			}
			else {
				file.error("Tagline outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("Hard")) {
			if(prevPreset !is null) {
				prevPreset.isHard = toBool(file.value);
			}
			else {
				file.error("Hard outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("DLC")) {
			if(prevPreset !is null) {
				prevPreset.dlc = file.value;
			}
			else {
				file.error("DLC outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("AI Support")) {
			if(prevPreset !is null) {
				prevPreset.aiSupport = toBool(file.value);
			}
			else {
				file.error("AI Support outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("Lore")) {
			if(prevPreset !is null) {
				prevPreset.lore = localize(file.value);
			}
			else {
				file.error("TaLore outside Preset block.");
			}
		}
		else if(file.key.equals_nocase("Icon")) {
			if(skin !is null) {
				skin.icon = getSprite(file.value);
			}
			else {
				file.error("Icon outside WeaponSkin block.");
			}
		}
		else if(file.key.equals_nocase("Portrait")) {
			if(file.indent > 0 && prevPreset !is null) {
				prevPreset.portrait = file.value;
			}
		}
		else if(file.key.equals_nocase("Background")) {
			if(prevColor !is null) {
				prevColor.backgroundDef = file.value;
				@prevColor.background = getMaterial(file.value);
			}
			else {
				file.error("Background outside Color block.");
			}
		}
		else if(file.key.equals_nocase("Shipset")) {
			if(prevPreset is null) {
				file.error("Shipset outside Preset block.");
			}
			else {
				prevPreset.shipset = file.value;
			}
		}
		else if(file.key.equals_nocase("Trait")) {
			if(prevPreset is null) {
				file.error("Trait outside Preset block.");
			}
			else {
				auto@ trait = getTrait(file.value);
				if(trait !is null)
					prevPreset.traits.insertLast(trait);
				else
					file.error("Could not find trait: "+file.value);
			}
		}
	}
}

void init() {
	auto@ matFlags = getMatGroup("EmpireFlags");
	for(uint i = 0, cnt = matFlags.materialCount; i < cnt; ++i) {
		EmpireFlag flag;
		flag.id = flags.length;
		@flag.flag = matFlags.getMaterial(i);
		flag.flagDef = matFlags.getMaterialName(i);

		flags.insertLast(flag);
	}
	
	auto@ matPorts = getMatGroup("EmpirePortraits");
	for(uint i = 0, cnt = matPorts.materialCount; i < cnt; ++i) {
		EmpirePortrait prt;
		prt.id = portraits.length;
		prt.portraitDef = matPorts.getMaterialName(i);
		prt.ident = prt.portraitDef;
		@prt.portrait = matPorts.getMaterial(i);

		portraits.insertLast(prt);
		portraitIdents.set(prt.ident, @prt);
	}
	
	initTraits();
	FileList list("data/empires", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		load(list.path[i]);
}

array<Color> EMPIRE_COLORS = {
	Color(0x00c3ffff), //Blue
	Color(0xff6c00ff), //Orange
	Color(0x00ff9cff), //Teal
	Color(0x884fffff), //Purple
	Color(0xd6bf2fff), //Yellow
	Color(0xd62f83ff), //Pink
	Color(0x93d62fff), //Lime
	Color(0x476bbaff), //Marine
};
