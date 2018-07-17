#priority init 2000
import biomes;

void loadBiomes(const string& filename) {
	ReadFile file(filename);
	
	string key, value;
	
	Biome@ biome;
	
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(key == "Biome") {
			if(biome !is null)
				addBiome(biome);
			@biome = Biome();
			biome.ident = value;
		}
		else if(biome is null) {
			error("Missing 'Biome: ID' line in " + filename);
		}
		else if(key == "Name") {
			biome.name = localize(value);
		}
		else if(key == "Description") {
			biome.description = localize(value);
		}
		else if(key == "Color") {
			biome.color = toColor(value);
		}
		else if(key == "Sprite") {
			biome.tile = getSprite(value);
		}
		else if(key == "Frequency") {
			biome.frequency = toUInt(value);
		}
		else if(key == "UseWeight") {
			biome.useWeight = toFloat(value);
		}
		else if(key == "Humidity") {
			biome.humidity = toFloat(value);
		}
		else if(key == "Temperature") {
			biome.temp = toFloat(value);
		}
		else if(key == "IsCrystallic") {
			biome.isCrystallic = toBool(value);
		}
		else if(key == "IsVoid") {
			biome.isVoid = toBool(value);
		}
		else if(key == "IsWater") {
			biome.isWater = toBool(value);
		}
		else if(key == "IsMoon") {
			biome.isMoon = toBool(value);
		}
		else if(key == "Buildable") {
			biome.buildable = toBool(value);
		}
		else if(key == "BuildCost") {
			biome.buildCost = toFloat(value);
		}
		else if(key == "BuildTime") {
			biome.buildTime = toFloat(value);
		}
		else if(key == "Picks") {
			array<string>@ split = value.split(",");
			if(split.length >= 1)
				biome.picks.x = toFloat(split[0]);
			if(split.length >= 2)
				biome.picks.y = toFloat(split[1]);
			if(split.length >= 3)
				biome.picks.z = toFloat(split[2]);
			if(split.length >= 4)
				biome.picks.w = toFloat(split[3]);
		}
		else if(key == "Lookup Range") {
			array<string>@ split = value.split(",");
			if(split.length >= 1) {
				biome.lookupRange.x = toFloat(split[0]);
				biome.lookupRange.y = biome.lookupRange.x;
			}
			if(split.length >= 2)
				biome.lookupRange.y = toFloat(split[1]);
		}
		else {
			error("Unrecognized line in biome " + biome.ident + ": " + key + ": " + value);
		}
	}
	
	if(biome !is null)
		addBiome(biome);
}

void preInit() {
	FileList list("data/biomes", "*.txt");
	
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadBiomes(list.path[i]);
}
