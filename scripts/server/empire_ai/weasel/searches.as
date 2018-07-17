Object@ findEnemy(Region@ region, Empire@ emp, uint empireMask, bool fleets = true, bool stations = true, bool planets = false) {
	array<Object@>@ objs = findInBox(region.position - vec3d(region.radius), region.position + vec3d(region.radius), empireMask);
	uint offset = randomi(0, objs.length-1);
	uint cnt = objs.length;
	for(uint i = 0; i < cnt; ++i) {
		Object@ obj = objs[(i+offset)%cnt];
		Empire@ owner = obj.owner;

		if(!obj.valid) {
			continue;
		}
		else if(owner is null || owner.mask & empireMask == 0) {
			continue;
		}
		else if(emp !is null && !obj.isVisibleTo(emp)) {
			continue;
		}
		else if(obj.region !is region) {
			continue;
		}
		else {
			uint type = obj.type;
			switch(type) {
				case OT_Ship:
					if(!obj.hasLeaderAI)
						continue;
					if(cast<Ship>(obj).isStation) {
						if(!stations)
							continue;
					}
					else {
						if(!fleets)
							continue;
					}
					if(obj.getFleetStrength() < 100.0)
						continue;
				break;
				case OT_Orbital:
					if(!stations)
						continue;
				break;
				case OT_Planet:
					if(!planets)
						continue;
				break;
				default:
					continue;
			}
		}

		return obj;
	}
	return null;
}

array<Object@>@ findEnemies(Region@ region, Empire@ emp, uint empireMask, bool fleets = true, bool stations = true, bool planets = false) {
	array<Object@>@ objs = findInBox(region.position - vec3d(region.radius), region.position + vec3d(region.radius), empireMask);
	array<Object@> outObjs;
	for(int i = objs.length-1; i >= 0; --i) {
		Object@ obj = objs[i];
		Empire@ owner = obj.owner;

		bool remove = false;
		if(!obj.valid) {
			remove = true;
		}
		else if(owner is null || owner.mask & empireMask == 0) {
			remove = true;
		}
		else if(emp !is null && !obj.isVisibleTo(emp)) {
			remove = true;
		}
		else if(obj.region !is region) {
			remove = true;
		}
		else {
			uint type = obj.type;
			switch(type) {
				case OT_Ship:
					if(!obj.hasLeaderAI)
						remove = true;
					if(cast<Ship>(obj).isStation) {
						if(!stations)
							remove = true;
					}
					else {
						if(!fleets)
							remove = true;
					}
					if(obj.getFleetStrength() < 100.0)
						remove = true;
				break;
				case OT_Orbital:
					if(!stations)
						remove = true;
				break;
				case OT_Planet:
					if(!planets)
						remove = true;
				break;
				default:
					remove = true;
			}
		}

		if(!remove)
			outObjs.insertLast(obj);
	}
	return outObjs;
}

array<Object@>@ findType(Region@ region, Empire@ emp, uint objectType, uint empireMask = ~0) {
	// Specialized for safe object buckets
	array<Object@>@ objs;
	DataList@ data;
	switch(objectType)
	{
		case OT_Planet:
			@data = region.getPlanets();
		break;
		case OT_Pickup:
			@data = region.getPickups();
		break;
		case OT_Anomaly:
			@data = region.getAnomalies();
		break;
		case OT_Artifact:
			@data = region.getArtifacts();
		break;
		case OT_Asteroid:
			@data = region.getAsteroids();
		break;
	}

	if(data !is null)
	{
		@objs = array<Object@>();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj !is null)
				objs.insertLast(obj);
		}
	}
	else {
		// No object bucket retrieval mechanism, do a full physics search
		@objs = findInBox(region.position - vec3d(region.radius), region.position + vec3d(region.radius), empireMask);
	}

	// Generic search using physics system
	array<Object@> outObjs;
	for(int i = objs.length-1; i >= 0; --i) {
		Object@ obj = objs[i];
		Empire@ owner = obj.owner;

		bool remove = false;
		if(!obj.valid) {
			remove = true;
		}
		else if(owner is null || owner.mask & empireMask == 0) {
			remove = true;
		}
		else if(emp !is null && !obj.isVisibleTo(emp)) {
			remove = true;
		}
		else if(obj.region !is region) {
			remove = true;
		}
		else {
			uint type = obj.type;
			if(type != objectType)
				remove = true;
		}

		if(!remove)
			outObjs.insertLast(obj);
	}
	return outObjs;
}

array<Object@>@ findAll(Region@ region, uint empireMask = ~0) {
	return findInBox(region.position - vec3d(region.radius), region.position + vec3d(region.radius), empireMask);
}

double getTotalFleetStrength(Region@ region, uint empireMask, bool fleets = true, bool stations = true, bool planets = true) {
	auto@ objs = findAll(region, empireMask);
	double str = 0.0;
	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		Object@ obj = objs[i];
		Empire@ owner = obj.owner;
		if(!obj.valid)
			continue;
		if(owner is null || owner.mask & empireMask == 0)
			continue;
		if(obj.region !is region)
			continue;

		uint type = obj.type;
		switch(type) {
			case OT_Ship:
				if(!obj.hasLeaderAI)
					continue;
				if(cast<Ship>(obj).isStation) {
					if(!stations)
						continue;
				}
				else {
					if(!fleets)
						continue;
				}
				if(obj.getFleetStrength() < 100.0)
					continue;
			break;
			case OT_Orbital:
				if(!stations)
					continue;
			break;
			case OT_Planet:
				if(!planets)
					continue;
			break;
			default:
				continue;
		}

		str += sqrt(obj.getFleetStrength());
	}
	return str * str;
}
