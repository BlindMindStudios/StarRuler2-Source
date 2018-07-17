import resources;
import tile_resources;
import saving;

export ResourceSpecType;
export ResourceSpec;
export implementSpec;

export ImportData;
export ExportData;

enum ResourceSpecType {
	RST_Specific,
	RST_Level_Specific,
	RST_Level_Minimum,
	RST_Pressure_Type,
	RST_Pressure_Level0,
	RST_Class,
};

tidy final class ResourceSpec : Savable {
	uint type = RST_Specific;
	const ResourceType@ resource;
	const ResourceClass@ cls;
	uint level = 0;
	uint pressureType = 0;
	bool isLevelRequirement = false;
	bool isForImport = true;
	bool allowUniversal = true;

	void save(SaveFile& file) {
		file << type;
		if(resource !is null) {
			file.write1();
			file.writeIdentifier(SI_Resource, resource.id);
		}
		else {
			file.write0();
		}
		if(cls !is null) {
			file.write1();
			file << cls.ident;
		}
		else {
			file.write0();
		}
		file << level;
		file << pressureType;
		file << isLevelRequirement;
		file << isForImport;
		file << allowUniversal;
	}

	void load(SaveFile& file) {
		file >> type;
		if(file.readBit())
			@resource = getResource(file.readIdentifier(SI_Resource));
		if(file.readBit()) {
			string clsName;
			file >> clsName;
			@cls = getResourceClass(clsName);
		}
		file >> level;
		file >> pressureType;
		file >> isLevelRequirement;
		file >> isForImport;
		file >> allowUniversal;
	}

	bool opEquals(const ResourceSpec& other) const {
		if(type != other.type)
			return false;
		if(isLevelRequirement != other.isLevelRequirement)
			return false;
		switch(type) {
			case RST_Specific:
				return other.resource is resource;
			case RST_Level_Specific:
			case RST_Level_Minimum:
				return other.level == level;
			case RST_Pressure_Type:
			case RST_Pressure_Level0:
				return other.pressureType == pressureType;
			case RST_Class:
				return other.cls is cls;
		}
		return true;
	}

	bool meets(const ResourceType@ check, Object@ fromObj = null, Object@ toObj = null) const {
		if(check is null)
			return false;
		if(allowUniversal && isLevelRequirement) {
			if(check.mode == RM_UniversalUnique || check.mode == RM_Universal) {
				//HACK: The AI shouldn't use drugs for food and water
				switch(type) {
					case RST_Level_Specific:
					case RST_Level_Minimum:
						return level >= 2;
				}
				return false;
			}
		}
		if(isForImport && !check.exportable && (fromObj is null || fromObj !is toObj))
			return false;
		if(isLevelRequirement && check.mode == RM_NonRequirement)
			return false;
		switch(type) {
			case RST_Specific:
				return check is resource;
			case RST_Level_Specific:
				return check.level == level;
			case RST_Level_Minimum:
				return check.level >= level;
			case RST_Pressure_Type:
				return check.tilePressure[pressureType] >= max(check.totalPressure * 0.4, 1.0);
			case RST_Pressure_Level0:
				return check.level == 0 && check.tilePressure[pressureType] >= max(check.totalPressure * 0.4, 1.0);
			case RST_Class:
				return check.cls is cls;
		}
		return false;
	}

	bool implements(const ResourceRequirement& req) const {
		if(!isLevelRequirement)
			return false;
		switch(req.type) {
			case RRT_Resource:
				return this.type == RST_Specific && this.resource is req.resource;
			case RRT_Class:
			case RRT_Class_Types:
				return this.type == RST_Class && this.cls is req.cls;
			case RRT_Level:
			case RRT_Level_Types:
				return this.type == RST_Level_Specific && this.level == req.level;
		}
		return false;
	}

	string dump() {
		switch(type) {
			case RST_Specific:
				return resource.name;
			case RST_Level_Specific:
				return "Tier "+level;
			case RST_Level_Minimum:
				return "Tier "+level+"+";
			case RST_Pressure_Type:
				return "Any "+getTileResourceIdent(pressureType);
			case RST_Pressure_Level0:
				return "Level 0 "+getTileResourceIdent(pressureType);
			case RST_Class:
				return "Of "+cls.ident;
		}
		return "??";
	}

	int get_resourceLevel() const {
		switch(type) {
			case RST_Specific:
				return 0;
			case RST_Level_Specific:
				return level;
			case RST_Level_Minimum:
				return level;
			case RST_Pressure_Type:
				return 0;
			case RST_Pressure_Level0:
				return 0;
			case RST_Class:
				return 0;
		}
		return 0;
	}

	int opCmp(const ResourceSpec@ other) const {
		int level = this.resourceLevel;
		int otherLevel = other.resourceLevel;
		if(level > otherLevel)
			return 1;
		if(level < otherLevel)
			return -1;
		return 0;
	}
};

ResourceSpec@ implementSpec(const ResourceRequirement& req) {
	ResourceSpec spec;
	spec.isLevelRequirement = true;

	switch(req.type) {
		case RRT_Resource:
			spec.type = RST_Specific;
			@spec.resource = req.resource;
		break;
		case RRT_Class:
		case RRT_Class_Types:
			spec.type = RST_Class;
			@spec.cls = req.cls;
		break;
		case RRT_Level:
		case RRT_Level_Types:
			spec.type = RST_Level_Specific;
			spec.level = req.level;
		break;
	}
	return spec;
}

tidy final class ImportData : Savable {
	int id = -1;
	Object@ obj;
	ResourceSpec@ spec;
	const ResourceType@ resource;
	Object@ fromObject;
	int resourceId = -1;
	bool beingMet = false;
	bool forLevel = false;
	bool cycled = false;
	bool isColonizing = false;
	bool claimedFor = false;
	double idleSince = 0.0;

	void save(SaveFile& file) {
		file << obj;
		file << spec;
		if(resource !is null) {
			file.write1();
			file.writeIdentifier(SI_Resource, resource.id);
		}
		else {
			file.write0();
		}
		file << fromObject;
		file << resourceId;
		file << beingMet;
		file << forLevel;
		file << cycled;
		file << isColonizing;
		file << claimedFor;
		file << idleSince;
	}

	void load(SaveFile& file) {
		file >> obj;
		@spec = ResourceSpec();
		file >> spec;
		if(file.readBit())
			@resource = getResource(file.readIdentifier(SI_Resource));
		file >> fromObject;
		file >> resourceId;
		file >> beingMet;
		file >> forLevel;
		file >> cycled;
		file >> isColonizing;
		file >> claimedFor;
		file >> idleSince;
	}

	void set(ExportData@ source) {
		@fromObject = source.obj;
		resourceId = source.resourceId;
		@resource = source.resource;
	}

	int opCmp(const ImportData@ other) const {
		return spec.opCmp(other.spec);
	}

	bool get_isOpen() const {
		return !beingMet;
	}
};

tidy final class ExportData : Savable {
	int id = -1;
	Object@ obj;
	const ResourceType@ resource;
	int resourceId = -1;
	ImportData@ request;
	Object@ developUse;
	bool localOnly = false;

	bool get_usable() const {
		if(obj is null)
			return false;
		if(resourceId == obj.primaryResourceId)
			return obj.primaryResourceUsable;
		else
			return obj.getNativeResourceUsableByID(resourceId);
	}

	bool get_isPrimary() const {
		return resourceId == obj.primaryResourceId;
	}

	bool isExportedTo(Object@ check) const {
		if(check is obj)
			return true;
		if(resourceId == obj.primaryResourceId)
			return obj.isPrimaryDestination(check);
		else
			return obj.getNativeResourceDestinationByID(obj.owner, resourceId) is check;
	}

	void save(SaveFile& file) {
		//Does not save the request link, this is done by Resources
		file << obj;
		if(resource !is null) {
			file.write1();
			file.writeIdentifier(SI_Resource, resource.id);
		}
		else {
			file.write0();
		}
		file << resourceId;
		file << developUse;
		file << localOnly;
	}

	void load(SaveFile& file) {
		file >> obj;
		if(file.readBit())
			@resource = getResource(file.readIdentifier(SI_Resource));
		file >> resourceId;
		file >> developUse;
		file >> localOnly;
	}
};
