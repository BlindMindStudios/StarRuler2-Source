import systems;

tidy class TerritoryScript {
	TerritoryNode@ node;
	set_int inner;
	set_int edges;

	bool regionDelta = false;
	array<Region@> regions;
	array<Region@> visionPending;
	array<bool> visionPendingOp;

	void postInit(Territory& obj) {
		obj.sightRange = 0.0;
		@node = TerritoryNode();
		node.setOwner(obj.owner);
	}

	void destroy(Territory& obj) {
		node.markForDeletion();
		@node = null;
	}

	void save(Territory& obj, SaveFile& file) {
		uint cnt = regions.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << regions[i];

		cnt = visionPending.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << visionPending[i];
			file << visionPendingOp[i];
		}
	}

	void load(Territory& obj, SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		regions.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@regions[i] = cast<Region>(file.readObject());

		file >> cnt;
		visionPending.length = cnt;
		visionPendingOp.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@visionPending[i] = cast<Region>(file.readObject());
			file >> visionPendingOp[i];
		}
	}

	void postLoad(Territory& obj) {
		@node = TerritoryNode();
		node.setOwner(obj.owner);

		for(uint i = 0, cnt = regions.length; i < cnt; ++i) {
			Region@ region = regions[i];
			node.addInner(region.id, region.position, region.radius);
			inner.insert(region.id);

			if(edges.contains(region.id)) {
				node.removeEdge(region.id);
				edges.erase(region.id);
			}

			//Add edges from this region
			SystemDesc@ desc = getSystem(region.SystemId);
			for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
				uint adj = desc.adjacent[i];
				SystemDesc@ other = getSystem(adj);

				if(inner.contains(other.object.id))
					continue;
				if(edges.contains(other.object.id))
					continue;

				edges.insert(other.object.id);
				node.addEdge(other.object.id, other.position, other.radius);
			}
		}

		//Reverse pending vision to get to old state
		for(int i = visionPending.length - 1; i >= 0; --i) {
			Region@ region = visionPending[i];
			if(visionPendingOp[i])
				node.removeInner(region.id);
			else
				node.addInner(region.id, region.position, region.radius);
		}
	}

	double tick(Territory& obj, double time) {
		for(uint i = 0, cnt = visionPending.length; i < cnt; ++i) {
			Region@ region = visionPending[i];
			if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
				if(visionPendingOp[i])
					node.addInner(region.id, region.position, region.radius);
				else
					node.removeInner(region.id);

				visionPending.removeAt(i);
				visionPendingOp.removeAt(i);
				--i; --cnt;
			}
		}
		return 1.0;
	}

	bool canTradeTo(Region@ region) const {
		return inner.contains(region.id) || edges.contains(region.id);
	}

	uint getRegionCount() const {
		return regions.length;
	}

	Region@ getRegion(uint i) const {
		if(i >= regions.length)
			return null;
		return regions[i];
	}

	void add(Territory& obj, Region@ region) {
		if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
			node.addInner(region.id, region.position, region.radius);
		}
		else {
			visionPending.insertLast(region);
			visionPendingOp.insertLast(true);
		}

		inner.insert(region.id);
		regions.insertLast(region);
		regionDelta = true;

		if(edges.contains(region.id)) {
			node.removeEdge(region.id);
			edges.erase(region.id);
		}

		//Add edges from this region
		SystemDesc@ desc = getSystem(region.SystemId);
		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			uint adj = desc.adjacent[i];
			SystemDesc@ other = getSystem(adj);

			if(inner.contains(other.object.id))
				continue;
			if(edges.contains(other.object.id))
				continue;

			edges.insert(other.object.id);
			node.addEdge(other.object.id, other.position, other.radius);
		}
	}

	void remove(Territory& obj, Region@ region) {
		if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask != 0) {
			node.removeInner(region.id);
		}
		else {
			visionPending.insertLast(region);
			visionPendingOp.insertLast(false);
		}

		inner.erase(region.id);
		regions.remove(region);
		regionDelta = true;

		//Remove edges from this region
		SystemDesc@ desc = getSystem(region.SystemId);
		bool isEdge = false;
		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			uint adj = desc.adjacent[i];
			SystemDesc@ other = getSystem(adj);

			if(inner.contains(other.object.id))
				isEdge = true;

			if(!edges.contains(other.object.id))
				continue;

			bool found = false;
			for(uint j = 0, jcnt = other.adjacent.length; j < jcnt; ++j) {
				SystemDesc@ chk = getSystem(other.adjacent[j]);
				if(inner.contains(chk.object.id)) {
					found = true;
					break;
				}
			}

			if(!found) {
				edges.erase(other.object.id);
				node.removeEdge(other.object.id);
			}
		}

		//Check if this should be added back as an edge
		if(isEdge) {
			edges.insert(region.id);
			node.addEdge(region.id, region.position, region.radius);
		}
	}

	void _writeRegions(const Territory& obj, Message& msg) {
		uint cnt = regions.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << regions[i];
	}

	void syncInitial(const Territory& obj, Message& msg) {
		_writeRegions(obj, msg);
	}

	void syncDetailed(const Territory& obj, Message& msg) {
		_writeRegions(obj, msg);
	}

	bool syncDelta(const Territory& obj, Message& msg) {
		if(!regionDelta)
			return false;

		if(regionDelta) {
			msg.write1();
			_writeRegions(obj, msg);
			regionDelta = false;
		}
		else {
			msg.write0();
		}

		return true;
	}
};
