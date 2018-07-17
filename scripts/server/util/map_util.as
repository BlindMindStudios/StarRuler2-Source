tidy class RegionData {
	vec3d position;
	double radius;
};

tidy class RegionMap {
	planed plane;
	RegionMap@ back, front;
	array<RegionData@> regs;
	bool xSplit;
	double maxRegionSize = 0;

	RegionMap() {
		xSplit = true;
	}

	RegionMap(bool useXSplit) {
		xSplit = useXSplit;
	}
	
	RegionData@ findClosest(const vec3d& point, double& nearest) const {
		RegionData@ closest;
		if(back !is null) {
			double dist = plane.distFromPlane(point);
			
			if(dist > 0.0) {
				if(dist > -nearest)
					@closest = front.findClosest(point, nearest);
				if(dist < nearest) {
					RegionData@ c = back.findClosest(point, nearest);
					if(c !is null)
						@closest = c;
				}
			}
			else {
				if(dist < nearest)
					@closest = back.findClosest(point, nearest);
				if(dist > -nearest) {
					RegionData@ c = front.findClosest(point, nearest);
					if(c !is null)
						@closest = c;
				}
			}
		}
		
		for(uint i = 0, cnt = regs.length; i < cnt; ++i) {
			RegionData@ reg = regs[i];
			double dist = reg.position.distanceTo(point) - reg.radius;
			if(dist < nearest) {
				@closest = reg;
				nearest = dist;
			}
		}
		
		return closest;
	}
	
	RegionData@ findRegion(const vec3d& point) const {
		if(back !is null) {
			double dist = plane.distFromPlane(point);
			if(dist < maxRegionSize) {
				RegionData@ region = back.findRegion(point);
				if(region !is null)
					return region;
			}
			if(dist > -maxRegionSize) {
				RegionData@ region = front.findRegion(point);
				if(region !is null)
					return region;
			}
			return null;
		}
		else {
			for(uint i = 0, cnt = regs.length; i < cnt; ++i) {
				RegionData@ region = regs[i];
				if(point.distanceToSQ(region.position) < region.radius * region.radius)
					return region;
			}
			return null;
		}
	}

	void addSystem(const vec3d& position, double radius) {
		RegionData dat;
		dat.position = position;
		dat.radius = radius;
		addRegion(dat);
	}

	bool hasExisting(const vec3d& position, double radius) {
		double closest = INFINITY;
		auto@ dat = findClosest(position, closest);
		if(dat is null)
			return false;
		return dat.position.distanceToSQ(position) < radius * radius;
	}
	
	void addRegion(RegionData@ region) {
		if(region.radius > maxRegionSize)
			maxRegionSize = region.radius;
	
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
				
				@back = RegionMap(!xSplit);
				@front = RegionMap(!xSplit);
				
				for(uint i = 0, cnt = regs.length; i < cnt; ++i)
					addRegion(regs[i]);
				regs.length = 0;
			}
		}
	}
};
