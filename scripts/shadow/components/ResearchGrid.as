import research;

tidy class ResearchGrid : Component_ResearchGrid {
	ReadWriteMutex mtx;

	TechnologyGrid grid;

	array<bool>@ tagUnlocks;

	double researchRate = 0;
	double points = 0;
	double totalGenerated = 0;

	double get_ResearchRate(Empire& emp) {
		return researchRate * ResearchEfficiency * emp.ResearchGenerationFactor;
	}

	double get_ResearchEfficiency() {
		return 2000.0 / (2000.0 + totalGenerated);
	}

	double get_ResearchPoints() {
		return points;
	}

	void getTechnologyNodes() {
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i)
			yield(grid.nodes[i]);
	}

	void getTechnologyNode(int id) {
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(id == grid.nodes[i].id) {
				yield(grid.nodes[i]);
				return;
			}
		}
	}

	TechnologyNode@ getNode(int id) {
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(grid.nodes[i].id == id)
				return grid.nodes[i];
		}
		return null;
	}

	void setResearchQueued(Empire& emp, int id, bool queued) {
		//PREDICTIVE
		WriteLock lock(mtx);
		auto@ node = getNode(id);
		if(node is null)
			return;
		if(node.bought)
			return;

		node.queued = queued;
	}

	void research(Empire& emp, int id, bool secondary = false, bool queue = false) {
		//PREDICTIVE
		WriteLock lock(mtx);
		auto@ node = getNode(id);
		if(node is null)
			return;
		if(node.bought)
			return;

		if(queue) {
			if(node.canUnlock(emp))
				node.queued = true;
		}
	}

	void getResearchingNodes() {
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			auto@ node = grid.nodes[i];
			if(!node.bought)
				continue;
			if(node.unlocked)
				continue;
			if(!node.unlockable)
				continue;
			yield(grid.nodes[i]);
		}
	}

	void getTechnologyNode(vec2i pos) {
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(pos == grid.nodes[i].position) {
				yield(grid.nodes[i]);
				return;
			}
		}
	}

	bool isTagUnlocked(int id) {
		if(tagUnlocks is null)
			return false;
		if(id < 0 || uint(id) >= tagUnlocks.length)
			return false;
		return tagUnlocks[id];
	}

	void readResearch(Message& msg) {
		WriteLock lock(mtx);
		msg >> researchRate;
		msg >> points;
		msg >> totalGenerated;
		bool delta = msg.readBit();
		bool gridDelta = msg.readBit();

		if(msg.readBit()) {
			uint cnt = msg.readSmall();
			if(tagUnlocks is null)
				@tagUnlocks = array<bool>(cnt, false);
			for(uint i = 0; i < cnt; ++i) {
				bool unlocked = msg.readBit();
				if(i < tagUnlocks.length)
					tagUnlocks[i] = unlocked;
			}
		}

		if(delta || gridDelta) {
			if(gridDelta) {
				msg >> grid.minPos;
				msg >> grid.maxPos;

				uint cnt = 0;
				msg >> cnt;
				grid.nodes.length = cnt;
			}

			for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
				if(grid.nodes[i] is null)
					@grid.nodes[i] = TechnologyNode();
				if(gridDelta)
					grid.nodes[i].read(msg);
				else
					grid.nodes[i].readStatus(msg);
			}

			if(gridDelta)
				grid.regenGrid();
		}
	}
};
