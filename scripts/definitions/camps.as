#priority init 2001
import pickups;
import statuses;
from pickups import IPickupHook, PickupHook;
import saving;
import hooks;

export CampType;
export getCreepCamp, getCreepCampCount;
export getDistributedCreepCamp;

#section server
from empire import Creeps;
#section all

tidy final class CampType {
	uint id = 0;
	string ident;

	double frequency = 1.0;
	double pickupFrequency = 0.0;

	int flagshipSize = 0;
	double supportOccupation = 1.0;
	double targetStrength = 0.0;

	array<string> def_region_statuses;
	array<const StatusType@> region_statuses;
	array<string> def_statuses;
	array<const StatusType@> statuses;

	array<PickupType@> pickups;
	array<string> def_ships;
	array<const Design@> ships;
	array<string> shipNames;
	array<uint> shipMins;
	array<uint> shipMaxes;

	void init() {
		statuses.length = 0;
		for(uint i = 0, cnt = def_statuses.length; i < cnt; ++i) {
			auto@ type = getStatusType(def_statuses[i]);
			if(type is null) {
				error("ERROR: Could not find status '"+def_statuses[i]+"' in creep camp '"+ident+"'.");
				continue;
			}
			statuses.insertLast(type);
		}
		for(uint i = 0, cnt = def_region_statuses.length; i < cnt; ++i) {
			auto@ type = getStatusType(def_region_statuses[i]);
			if(type is null) {
				error("ERROR: Could not find region status '"+def_region_statuses[i]+"' in creep camp '"+ident+"'.");
				continue;
			}
			region_statuses.insertLast(type);
		}

#section server
		for(uint i = 0, cnt = def_ships.length; i < cnt; ++i) {
			string line = def_ships[i];
			const Design@ dsg;
			uint min = 1, max = 1;
			string name;

			if(line.findFirst("[") != -1 && line.findFirst("]") != -1) {
				int fpos = line.findFirst("[");
				int epos = line.findFirst("]");

				name = localize(line.substr(fpos+1, epos-fpos-1));
				line = line.substr(0, fpos);
			}

			@dsg = Creeps.getDesign(line.trimmed());
			if(dsg is null) {
				//Check if we have a number
				int pos = line.findFirst(" ");
				if(pos == -1) {
					error(" Error: invalid design spec "+escape(line.trimmed()));
					return;
				}

				string counts = line.substr(0, pos).trimmed();
				string design = line.substr(pos).trimmed();

				if(counts[counts.length-1] != 'x') {
					error(" Error: could not find design "+escape(line.trimmed()));
					return;
				}

				int dashPos = counts.findFirst("-");
				if(dashPos == -1) {
					min = max = toUInt(counts.substr(0, counts.length-1));
				}
				else {
					min = toUInt(counts.substr(0, dashPos));
					max = toUInt(counts.substr(dashPos+1, counts.length-dashPos-2));
				}

				@dsg = Creeps.getDesign(design);
				if(dsg is null) {
					error(" Error: could not find design "+escape(line.trimmed()));
					return;
				}
			}

			ships.insertLast(dsg);
			shipMins.insertLast(min);
			shipMaxes.insertLast(max);
			shipNames.insertLast(name);
		}
#section all
	}
};

void parseLine(string& line, CampType@ c, ReadFile@ file) {
	//Try to find the design
	if(line.findFirst("(") == -1) {
		c.def_ships.insertLast(line);
	}
	else {
		if(c.pickups.length == 0) {
			error("Missing 'Pickup:' line for: "+escape(line));
			return;
		}

		//Hook line
		auto@ hook = cast<IPickupHook>(parseHook(line, "pickup_effects::", instantiate=false, file=file));
		if(hook !is null)
			c.pickups[c.pickups.length-1].hooks.insertLast(hook);
	}
}

void loadCamps(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	CampType@ c;
	PickupType@ p;
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			if(c is null) {
				error("Missing 'Camp: ID' line in " + filename);
				continue;
			}

			string line = file.line;
			parseLine(line, c, file);
		}
		else if(key == "Camp") {
			if(c !is null)
				addCreepCamp(c);
			@c = CampType();
			c.ident = value;
			if(c.ident.length == 0)
				c.ident = filename+"__"+index;
			@p = null;

			++index;
		}
		else if(c is null) {
			error("Missing 'Camp: ID' line in " + filename);
		}
		else if(key == "Frequency") {
			if(p !is null)
				p.frequency = toDouble(value);
			else
				c.frequency = toDouble(value);
		}
		else if(key == "Pickup") {
			@p = PickupType();
			p.ident = value;
			if(p.ident.length == 0)
				p.ident = c.ident+"__"+c.pickups.length;
			c.pickups.insertLast(p);
		}
		else if(key == "DLC") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.dlc = value;
		}
		else if(key == "Name") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.name = localize(value);
		}
		else if(key == "Verb") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.verb = localize(value);
		}
		else if(key == "Description") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.description = localize(value);
		}
		else if(key == "Model") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			@p.model = getModel(value);
		}
		else if(key == "Material") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			@p.material = getMaterial(value);
		}
		else if(key == "Physical Size") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.physicalSize = toDouble(value);
		}
		else if(key == "Icon Sheet") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			@p.iconSheet = getSpriteSheet(value);
		}
		else if(key == "Icon Index") {
			if(p is null) {
				error("Missing 'Pickup:' line in " + filename);
				continue;
			}

			p.iconIndex = toUInt(value);
		}
		else if(key == "Region Status") {
			c.def_region_statuses.insertLast(value);
		}
		else if(key == "Remnant Status") {
			c.def_statuses.insertLast(value);
		}
		else if(key == "Flagship Size") {
			c.flagshipSize = toInt(value);
		}
		else if(key == "Target Strength") {
			c.targetStrength = toDouble(value);
		}
		else if(key == "Support Occupation") {
			c.supportOccupation = toDouble(value);
		}
		else if(key == "Ship") {
			parseLine(value, c, file);
		}
		else {
			string line = file.line;
			parseLine(line, c, file);
		}
	}
	
	if(c !is null)
		addCreepCamp(c);
}

bool initialized = false;
void initCreepCampTypes() {
	if(initialized)
		return;
	initialized = true;
	for(uint i = 0, cnt = campTypes.length; i < cnt; ++i)
		campTypes[i].init();
}

void preInit() {
	//Load camp types
	FileList list("data/creeps", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadCamps(list.path[i]);
}

void init() {
	if(!isLoadedSave)
		initCreepCampTypes();
}

CampType@[] campTypes;
dictionary idents;
double totalFrequency = 0;

const CampType@ getCreepCamp(uint id) {
	if(id >= campTypes.length)
		return null;
	return campTypes[id];
}

const CampType@ getCreepCamp(const string& ident) {
	CampType@ camp;
	if(idents.get(ident, @camp))
		return camp;
	return null;
}

uint getCreepCampCount() {
	return campTypes.length;
}

const CampType@ getDistributedCreepCamp() {
	double num = randomd(0, totalFrequency);
	for(uint i = 0, cnt = campTypes.length; i < cnt; ++i) {
		const CampType@ type = campTypes[i];
		double freq = type.frequency;
		if(num <= freq)
			return type;
		num -= freq;
	}
	return campTypes[campTypes.length-1];
}

void addCreepCamp(CampType@ type) {
	type.id = campTypes.length;
	campTypes.insertLast(type);
	idents.set(type.ident, @type);
	type.pickupFrequency = 0.0;

	for(uint i = 0, cnt = type.pickups.length; i < cnt; ++i) {
		auto@ pu = type.pickups[i];
		if(pu.dlc.length != 0 && !hasDLC(pu.dlc))
			pu.frequency = 0.0;

		addPickupType(pu);
		type.pickupFrequency += pu.frequency;
	}

	if(type.pickupFrequency == 0.0)
		type.frequency = 0.0;
	totalFrequency += type.frequency;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = campTypes.length; i < cnt; ++i) {
		auto type = campTypes[i];
		file.addIdentifier(SI_CreepCamp, type.id, type.ident);
	}
}
