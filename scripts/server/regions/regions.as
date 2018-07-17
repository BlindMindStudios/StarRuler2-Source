Region@[] regions;
RegionSplit regionGroup(true);

tidy class RegionSplit {
	planed plane;
	RegionSplit@ back, front;
	array<Region@> regs;
	bool xSplit;
	double maxRegionSize = 0;

	RegionSplit() {
		xSplit = true;
	}

	RegionSplit(bool useXSplit) {
		xSplit = useXSplit;
	}
	
	Region@ findClosest(const vec3d& point, double& nearest) const {
		Region@ closest;
		if(back !is null) {
			double dist = plane.distFromPlane(point);
			
			if(dist > 0.0) {
				if(dist > -nearest)
					@closest = front.findClosest(point, nearest);
				if(dist < nearest) {
					Region@ c = back.findClosest(point, nearest);
					if(c !is null)
						@closest = c;
				}
			}
			else {
				if(dist < nearest)
					@closest = back.findClosest(point, nearest);
				if(dist > -nearest) {
					Region@ c = front.findClosest(point, nearest);
					if(c !is null)
						@closest = c;
				}
			}
		}
		
		for(uint i = 0, cnt = regs.length; i < cnt; ++i) {
			Region@ reg = regs[i];
			double dist = reg.position.distanceTo(point) - reg.OuterRadius;
			if(dist < nearest) {
				@closest = reg;
				nearest = dist;
			}
		}
		
		return closest;
	}
	
	Region@ findRegion(const vec3d& point) const {
		if(back !is null) {
			double dist = plane.distFromPlane(point);
			if(dist < maxRegionSize) {
				Region@ region = back.findRegion(point);
				if(region !is null)
					return region;
			}
			if(dist > -maxRegionSize) {
				Region@ region = front.findRegion(point);
				if(region !is null)
					return region;
			}
			return null;
		}
		else {
			for(uint i = 0, cnt = regs.length; i < cnt; ++i) {
				Region@ region = regs[i];
				if(point.distanceToSQ(region.position) < region.OuterRadius * region.OuterRadius)
					return region;
			}
			return null;
		}
	}
	
	void addRegion(Region@ region) {
		if(region.OuterRadius > maxRegionSize)
			maxRegionSize = region.OuterRadius;
	
		if(back !is null) {
			if(plane.inFront(region.position))
				front.addRegion(region);
			else
				back.addRegion(region);
		}
		else {
			regs.insertLast(region);
			//Once we have enough regions, split into two nodes
			if(regs.length > 4) {
				//TODO: Decide a better middle point (median, rather than mean)
				vec3d avg;
				for(uint i = 0, cnt = regs.length; i < cnt; ++i)
					avg += regs[i].position;
				avg /= double(regs.length);
					
				if(xSplit)
					plane = planed(avg, vec3d_front());
				else
					plane = planed(avg, vec3d_right());
				
				@back = RegionSplit(!xSplit);
				@front = RegionSplit(!xSplit);
				
				for(uint i = 0, cnt = regs.length; i < cnt; ++i)
					addRegion(regs[i]);
				regs.length = 0;
			}
		}
	}
};

Region@ findNearestRegion(const vec3d& point) {
	double dist = 1.0e35;
	return regionGroup.findClosest(point, dist);
}

void regenerateRegionGroups() {
	RegionSplit newSplit(true);
	for(uint i = 0, cnt = regions.length; i < cnt; ++i)
		newSplit.addRegion(regions[i]);
	regionGroup =  newSplit;
	calcGalaxyExtents();
}

void addRegion(Region@ region) {
	regions.insertLast(region);
	regionGroup.addRegion(region);
}

bool inRegion(Region@ region, Object& obj) {
	return obj.position.distanceToSQ(region.position) < region.OuterRadius * region.OuterRadius;
}

bool inRegion(Region@ region, const vec3d& position) {
	return position.distanceToSQ(region.position) < region.OuterRadius * region.OuterRadius;
}

bool updateRegion(Object& obj, bool takeVision = true) {
	Region@ prevRegion = obj.region;
	if(prevRegion !is null) {
		if(takeVision)
			obj.donatedVision |= prevRegion.DonateVisionMask;
		if(inRegion(prevRegion, obj))
			return false;
		prevRegion.leaveRegion(obj);
	}
	
	Region@ newRegion = getRegion(obj.position);
	if(newRegion is null && prevRegion is null)
		return false;
	
	@obj.region = newRegion;
	if(newRegion !is null) {
		newRegion.enterRegion(obj);

		Node@ node = obj.getNode();
		if(node !is null)
			node.hintParentObject(newRegion);
	}
	else {
		Node@ node = obj.getNode();
		if(node !is null)
			node.reparent(null);
	}
	return true;
}

void leaveRegion(Object& obj) {
	Region@ reg = obj.region;
	if(reg !is null) {
		obj.region.leaveRegion(obj);
		@obj.region = null;
	}
}

void regionOwnerChange(Object& obj, Empire@ prevOwner) {
	if(obj.region !is null)
		obj.region.regionObjectOwnerChange(obj, prevOwner, obj.owner);
}

Region@ getRegion(const vec3d& point) {
	return regionGroup.findRegion(point);
}

Region@ getRegion_client(vec3d point) {
	return regionGroup.findRegion(point);
}

bool calcExtents = true;
vec3d extentMin, extentMax;
void calcGalaxyExtents() {
	if(calcExtents) {
		for(uint i = 0, cnt = regions.length; i < cnt; ++i) {
			auto@ sys = regions[i];
			if(i == 0) {
				extentMin = sys.position - vec3d(sys.radius);
				extentMax = sys.position + vec3d(sys.radius);
			}
			else {
				insertExtent(sys.position - vec3d(sys.radius), sys.position + vec3d(sys.radius));
			}
		}

		calcExtents = false;
	}
}

void insertExtent(const vec3d& lower, const vec3d& upper) {
	if(extentMin.x > lower.x)
		extentMin.x = lower.x;
	if(extentMin.y > lower.y)
		extentMin.y = lower.y;
	if(extentMin.z > lower.z)
		extentMin.z = lower.z;
	if(extentMax.x < upper.x)
		extentMax.x = upper.x;
	if(extentMax.y < upper.y)
		extentMax.y = upper.y;
	if(extentMax.z < upper.z)
		extentMax.z = upper.z;
}

bool isOutsideUniverseExtents_client(vec3d pos, double margin = 500.0) {
	return isOutsideUniverseExtents(pos, margin);
}

bool isOutsideUniverseExtents(const vec3d& pos, double margin = 500.0) {
	return pos.x < extentMin.x-margin || pos.y < extentMin.y-margin || pos.z < extentMin.z-margin
		|| pos.x > extentMax.x+margin || pos.y > extentMax.y+margin || pos.z > extentMax.z+margin;
}

void limitToUniverseExtents(vec3d& pos, double margin = 500.0) {
	pos.x = clamp(pos.x, extentMin.x-margin, extentMax.x+margin);
	pos.y = clamp(pos.y, extentMin.y-margin, extentMax.y+margin);
	pos.z = clamp(pos.z, extentMin.z-margin, extentMax.z+margin);
}

#section server
void syncInitial(Message& msg) {
	uint cnt = regions.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i)
		msg << regions[i];
}

void save(SaveFile& msg) {
	uint cnt = regions.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i)
		msg << regions[i];
}

void load(SaveFile& msg) {
	uint cnt = 0;
	msg >> cnt;
	regions.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		msg >> regions[i];
		regionGroup.addRegion(regions[i]);
	}
	calcGalaxyExtents();
}

#section shadow
void syncInitial(Message& msg) {
	//Read systems
	uint cnt = 0;
	msg >> cnt;
	regions.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		msg >> regions[i];
		regionGroup.addRegion(regions[i]);
	}
	calcGalaxyExtents();
}
