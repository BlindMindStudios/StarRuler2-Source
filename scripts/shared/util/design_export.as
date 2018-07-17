import designs;
import design_settings;
const int DESIGN_SERIALIZE_VERSION = 1;

JSONTree@ serialize_design(const Design@ dsg, const DesignClass@ cls = null) {
	JSONTree tree;
	JSONNode@ root = tree.root.makeObject();

	root["__VERSION__"] = DESIGN_SERIALIZE_VERSION;
	root["name"] = dsg.name;
	root["size"] = int(dsg.size);
	root["hull"] = dsg.hull.baseHull.ident;
	root["type"] = getHullTypeTag(dsg.hull);
	root["gridWidth"] = dsg.hull.active.width;
	root["gridHeight"] = dsg.hull.active.height;
	if(dsg.forceHull)
		root["forceHull"].setBool(true);
	if(cls !is null)
		root["class"] = cls.name;
	else if(dsg.cls !is null)
		root["class"] = dsg.cls.name;

	JSONNode@ sysList = root["subsystems"].makeArray();

	auto@ settings = cast<const DesignSettings>(dsg.settings);
	if(settings !is null) {
		JSONNode@ node = root["settings"].makeObject();
		settings.write(node);
	}

	uint sysCnt = dsg.subsystemCount;
	for(uint i = 0; i < sysCnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		if(sys.type.isHull)
			continue;
		if(sys.type.isApplied)
			continue;

		JSONNode@ node = sysList.pushBack().makeObject();
		node["type"] = sys.type.id;

		if(sys.direction != vec3d_front()) {
			JSONNode@ dir = node["direction"].makeArray();
			dir.pushBack() = sys.direction.x;
			dir.pushBack() = sys.direction.y;
			dir.pushBack() = sys.direction.z;
		}

		JSONNode@ hexes = node["hexes"].makeArray();
		uint hexCnt = sys.hexCount;
		for(uint j = 0; j < hexCnt; ++j) {
			vec2u hex = sys.hexagon(j);
			JSONNode@ coord = hexes.pushBack().makeArray();
			coord.pushBack() = hex.x;
			coord.pushBack() = hex.y;

			if(sys.module(j) !is sys.type.defaultModule)
				coord.pushBack() = sys.module(j).id;
		}
	}

	@sysList = null;
	for(uint i = 0; i < sysCnt; ++i) {
		const Subsystem@ sys = dsg.subsystems[i];
		if(!sys.type.isApplied)
			continue;

		if(sysList is null)
			@sysList = root["appliedSubsystems"].makeArray();
		sysList.pushBack() = sys.type.id;
	}

	return tree;
}

void write_design(const Design@ dsg, const string& filename, const DesignClass@ cls = null, bool pretty = true) {
	serialize_design(dsg, cls).writeFile(filename, pretty);
}

bool unserialize_design(JSONTree@ tree, DesignDescriptor& desc) {
	JSONNode@ root = tree.root;
	if(!root.isObject() || !root["name"].isString() || !root["size"].isInt() || !root["hull"].isString())
		return false;
	desc.name = root["name"].getString();
	desc.size = root["size"].getInt();

	if(desc.size < 1)
		return false;

	desc.forceHull = false;
	auto@ force = root.findMember("forceHull");
	if(force !is null && force.isBool())
		desc.forceHull = force.getBool();

	JSONNode@ cls = root.findMember("class");
	if(cls !is null && cls.isString())
		desc.className = cls.getString();

	desc.hullName = root["hull"].getString();
	@desc.hull = getHullDefinition(desc.hullName);

	JSONNode@ sysList = root["subsystems"];
	if(!sysList.isArray())
		return false;
	uint sysCnt = sysList.size();
	for(uint i = 0; i < sysCnt; ++i) {
		JSONNode@ node = sysList[i];
		if(!node["type"].isString())
			return false;

		const SubsystemDef@ def = getSubsystemDef(node["type"].getString());
		if(def is null)
			continue;
		desc.addSystem(def);

		JSONNode@ dir = node["direction"];
		if(dir.isArray() && dir.size() == 3)
			desc.setDirection(vec3d(dir[0].getNumber(), dir[1].getNumber(), dir[2].getNumber()));

		JSONNode@ hexes = node["hexes"];
		if(!hexes.isArray())
			return false;
		uint hexCnt = hexes.size();
		for(uint j = 0; j < hexCnt; ++j) {
			JSONNode@ coord = hexes[j];
			if(!coord.isArray() || coord.size() < 2)
				return false;
			vec2u pos(coord[0].getUint(), coord[1].getUint());

			if(coord.size() == 2) {
				desc.addHex(pos);
			}
			else {
				const ModuleDef@ mod = def.module(coord[2].getString());
				if(mod !is null)
					desc.addHex(pos, mod);
				else
					desc.addHex(pos);
			}
		}
	}

	@sysList = root["appliedSubsystems"];
	if(sysList !is null && sysList.isArray()) {
		uint sysCnt = sysList.size();
		for(uint i = 0; i < sysCnt; ++i) {
			JSONNode@ node = sysList[i];
			if(node is null || !node.isString())
				continue;

			const SubsystemDef@ def = getSubsystemDef(node.getString());
			if(def !is null)
				desc.applySubsystem(def);
		}
	}

	if(desc.hull is null) {
		JSONNode@ type = root.findMember("type");
		if(type !is null && type.isString())
			@desc.hull = getBestHull(desc, type.getString());
		if(desc.hull is null)
			return false;
	}

	JSONNode@ stNode = root.findMember("settings");
	if(stNode !is null && stNode.isObject()) {
		DesignSettings settings;
		settings.read(stNode);
		@desc.settings = settings;
	}
	else {
		@desc.settings = null;
	}

	JSONNode@ w = root.findMember("gridWidth");
	JSONNode@ h = root.findMember("gridHeight");
	if(w !is null && w.isUint() && h !is null && h.isUint())
		desc.gridSize = vec2u(w.getUint(), h.getUint());
	else
		desc.gridSize = getDesignGridSize(desc.hull, desc.size);
	return true;
}

int upload_design(const Design@ design, const string& description = "", bool waitId = false) {
#section client
	WebData dat;
	dat.addPost("name", design.name);
	dat.addPost("size", toString(design.size, 0));
	dat.addPost("author", settings::sNickname);
	dat.addPost("description", description);
	dat.addPost("color", toString(design.color));
	dat.addPost("data", serialize_design(design).toString());

	webAPICall("designs/submit", dat);
	if(waitId) {
		while(!dat.completed)
			sleep(100);
		return toInt(dat.result);
	}
#section all
	return -1;
}

bool read_design(const string& filename, DesignDescriptor& desc) {
	JSONTree tree;
	tree.readFile(filename);
	return unserialize_design(tree, desc);
}

string uniqueDesignName(string name, Empire@ emp) {
	int num = 1;
	string oldName = name;
	int pos = oldName.findLast(" Mk");
	if(pos != -1)
		oldName = oldName.substr(0, pos);

	while(emp.getDesign(name) !is null) {
		string newName = oldName;
		newName += " Mk";
		appendRoman(num, newName);

		name = newName;
		++num;
	}
	return name;
}

string getHullTypeTag(const Hull@ hull) {
	if(hull is null)
		return "";
	if(hull.hasTag("Flagship"))
		return "Flagship";
	if(hull.hasTag("Support"))
		return "Support";
	if(hull.hasTag("Satellite"))
		return "Satellite";
	if(hull.hasTag("Station"))
		return "Station";
	return "";
}

const Hull@ getBestHull(DesignDescriptor& desc, const string& hullTag, Empire@ emp = playerEmpire) {
	const Shipset@ shipset;
	if(emp is null || emp.shipset is null)
		@shipset = getShipset("Volkur");
	else
		@shipset = emp.shipset;
	if(shipset is null)
		return null;
	const Hull@ bestHull;
	double bestHullDist = INFINITY;
	for(uint i = 0, cnt = shipset.hullCount; i < cnt; ++i) {
		const Hull@ hull = shipset.hulls[i];

		//Check if it matches the tag
		if(!hull.hasTag(hullTag))
			continue;
		if(bestHull is null)
			@bestHull = hull;

		//Make sure we can use this hull
		if(hull.minSize >= 0 && hull.minSize > desc.size)
			continue;
		if(hull.maxSize >= 0 && hull.maxSize < desc.size)
			continue;

		//Check distance
		double d = hull.getMatchDistance(desc);
		if(hull is desc.hull)
			d -= 0.1;
		if(d < bestHullDist) {
			bestHullDist = d;
			@bestHull = hull;
		}
	}
	return bestHull;
}

void describeDesign(const Design@ orig, DesignDescriptor& desc) {
	desc.name = orig.name;
	desc.className = orig.cls.name;
	desc.gridSize = vec2u(orig.hull.gridSize);
	desc.size = orig.size;
	@desc.hull = orig.hull;
	@desc.owner = orig.owner;

	uint sysCnt = orig.subsystemCount;
	for(uint i = 0; i < sysCnt; ++i) {
		const Subsystem@ sys = orig.subsystems[i];
		if(sys.type.isHull)
			continue;
		if(sys.type.isApplied) {
			desc.applySubsystem(sys.type);
			continue;
		}

		desc.addSystem(sys.type);
		desc.setDirection(sys.direction);
		uint hexCnt = sys.hexCount;
		for(uint j = 0; j < hexCnt; ++j) {
			vec2u hex = sys.hexagon(j);
			desc.addHex(hex, sys.module(j));
		}
	}
}

void resizeDesign(const Design@ orig, int newSize, DesignDescriptor& desc) {
	describeDesign(orig, desc);
	desc.size = newSize;
}

class DesignSet {
	DesignDescriptor[] designs;
	bool limitShipset = false;
	bool softLimitRetry = false;
	bool log = false;

	void readDirectory(const string& directory) {
		FileList list(directory, "*.design", true);
		uint cnt = list.length;
		designs.resize(cnt);
		for(uint i = 0; i < cnt; ++i)
			read_design(list.path[i], designs[i]);
	}

	void createFor(Empire@ emp, bool overrideLimit = false) const {
		bool foundAny = false;
		for(uint i = 0, cnt = designs.length; i < cnt; ++i) {
			DesignDescriptor desc = designs[i];
			@desc.owner = emp;
			string hullName = format(desc.hullName, emp.shipset.ident);
			@desc.hull = getHullDefinition(hullName);
			if(desc.hull is null) {
				hullName = format("$1FlagTiny", emp.shipset.ident);
				@desc.hull = getHullDefinition(hullName);

				if(desc.hull is null) {
					if(!limitShipset || overrideLimit) {
						hullName = format(desc.hullName, "Volkur");
						@desc.hull = getHullDefinition(hullName);
						if(desc.hull is null) {
							if(desc.hull is null)
								@desc.hull = getHullDefinition("VolkurFlagTiny");
						}
					}
					if(desc.hull is null)
						continue;
				}
			}
			if(limitShipset && !overrideLimit) {
				if(emp.shipset is null || !emp.shipset.hasHull(desc.hull))
					continue;
			}
			else {
				if(emp.shipset !is null && !emp.shipset.hasHull(desc.hull))
					@desc.hull = getBestHull(desc, getHullTypeTag(desc.hull), emp);
			}
			if(desc.hull is null)
				continue;
			if(desc.className.length == 0)
				desc.className = "Default";

			const Design@ dsg = makeDesign(desc);
			if(log && dsg !is null && dsg.hasFatalErrors()) {
				print(emp.name+" Importing "+desc.name+":");
				for(uint i = 0, cnt = dsg.errorCount; i < cnt; ++i)
					print("   "+dsg.errors[i].text);
			}
			if(dsg is null || dsg.hasFatalErrors())
				continue;
			if(emp.getDesign(dsg.name) !is null)
				continue;
			if(desc.settings !is null)
				dsg.setSettings(desc.settings);

			const DesignClass@ cls = emp.getDesignClass(desc.className);
			emp.addDesign(cls, dsg);
			foundAny = true;
		}
		if(softLimitRetry && !foundAny && !overrideLimit)
			createFor(emp, overrideLimit=true);
	}
};
