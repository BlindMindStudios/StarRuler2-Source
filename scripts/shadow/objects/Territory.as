import systems;

tidy class TerritoryScript {
	TerritoryNode@ node;
	set_int inner;
	set_int edges;

	array<Region@> regions;
	array<Region@> visionPending;
	array<bool> visionPendingOp;
	Empire@ prevEmpire = playerEmpire;

	double tick(Territory& obj, double time) {
		if(playerEmpire !is prevEmpire) {
			@prevEmpire = playerEmpire;

			//Apply anything that was waiting
			for(uint i = 0, cnt = visionPending.length; i < cnt; ++i) {
				Region@ region = visionPending[i];
				if(visionPendingOp[i])
					node.addInner(region.id, region.position, region.radius);
				else
					node.removeInner(region.id);
			}

			visionPending.length = 0;
			visionPendingOp.length = 0;

			//Remove vision on systems we aren't supposed to see
			for(uint i = 0, cnt = regions.length; i < cnt; ++i) {
				Region@ region = regions[i];
				if(obj.owner is playerEmpire || region.VisionMask & playerEmpire.visionMask == 0) {
					node.removeInner(region.id);
					visionPending.insertLast(region);
					visionPendingOp.insertLast(true);
				}
			}

			return 1.0;
		}

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

	void _readRegions(Territory& obj, Message& msg) {
		uint cnt = 0;
		msg >> cnt;

		set_int newSet;
		for(uint i = 0; i < cnt; ++i) {
			Region@ region = cast<Region>(msg.readObject());
			newSet.insert(region.id);

			//Add new regions
			if(!inner.contains(region.id))
				add(obj, region);

			//TODO: Check if this could ever result in
			//an out-of-order delta putting a region
			//in the wrong territory.
			region.setTerritory(obj.owner, obj);
		}

		//Remove old regions
		for(uint i = 0, ocnt = regions.length; i < ocnt; ++i) {
			Region@ region = regions[i];
			if(!newSet.contains(region.id)) {
				remove(obj, region);
				region.clearTerritory(obj.owner, obj);
				--i; --ocnt;
			}
		}
	}

	void destroy(Territory& obj) {
		node.markForDeletion();
		@node = null;
	}

	void syncInitial(Territory& obj, Message& msg) {
		@node = TerritoryNode();
		node.setOwner(obj.owner);

		_readRegions(obj, msg);
	}

	void syncDetailed(Territory& obj, Message& msg, double tDiff) {
		_readRegions(obj, msg);
	}

	void syncDelta(Territory& obj, Message& msg, double tDiff) {
		if(msg.readBit())
			_readRegions(obj, msg);
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
};
