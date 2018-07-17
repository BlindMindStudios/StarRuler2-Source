// Research
// --------
// Spends research points to unlock and improve things in the research grid.
//

import empire_ai.weasel.WeaselAI;

import research;

class Research : AIComponent {
	TechnologyGrid grid;
	array<TechnologyNode@> immediateQueue;

	void save(SaveFile& file) {
		uint cnt = immediateQueue.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << immediateQueue[i].id;
	}

	void load(SaveFile& file) {
		updateGrid();

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			int id = 0;
			file >> id;

			for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
				if(grid.nodes[i].id == id) {
					immediateQueue.insertLast(grid.nodes[i]);
					break;
				}
			}
		}

	}

	void updateGrid() {
		//Receive the full grid from the empire to path on
		grid.nodes.length = 0;

		DataList@ recvData = ai.empire.getTechnologyNodes();
		TechnologyNode@ node = TechnologyNode();
		while(receive(recvData, node)) {
			grid.nodes.insertLast(node);
			@node = TechnologyNode();
		}

		grid.regenBounds();
	}

	double getEndPointWeight(const TechnologyType& tech) {
		//TODO: Might want to make this configurable by data file
		return 1.0;
	}

	bool isEndPoint(const TechnologyType& tech) {
		return tech.cls >= Tech_BigUpgrade;
	}

	double findResearch(int atIndex, array<TechnologyNode@>& path, array<bool>& visited, bool initial = false) {
		if(visited[atIndex])
			return 0.0;
		visited[atIndex] = true;

		auto@ node = grid.nodes[atIndex];
		if(!initial) {
			if(node.bought)
				return 0.0;
			if(!node.hasRequirements(ai.empire))
				return 0.0;

			path.insertLast(node);

			if(isEndPoint(node.type))
				return getEndPointWeight(node.type);
		}

		vec2i startPos = node.position;
		double totalWeight = 0.0;

		array<TechnologyNode@> tmp;
		array<TechnologyNode@> chosen;
		tmp.reserve(20);
		chosen.reserve(20);

		for(uint d = 0; d < 6; ++d) {
			vec2i otherPos = startPos;
			if(grid.doAdvance(otherPos, HexGridAdjacency(d))) {
				int otherIndex = grid.getIndex(otherPos);
				if(otherIndex != -1) {
					tmp.length = 0;
					double w = findResearch(otherIndex, tmp, visited);
					if(w != 0.0) {
						totalWeight += w;
						if(randomd() < w / totalWeight) {
							chosen = tmp;
						}
					}
				}
			}
		}

		for(uint i = 0, cnt = chosen.length; i < cnt; ++i)
			path.insertLast(chosen[i]);
		return max(totalWeight, 0.01);
	}

	void queueNewResearch() {
		if(log)
			ai.print("Attempted to find new research to queue");

		//Update our grid representation
		updateGrid();

		//Find a good path to do
		array<bool> visited(grid.nodes.length, false);

		double totalWeight = 0.0;

		auto@ path = array<TechnologyNode@>();
		auto@ tmp = array<TechnologyNode@>();
		path.reserve(20);
		tmp.reserve(20);

		for(int i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(grid.nodes[i].bought) {
				tmp.length = 0;
				double weight = findResearch(i, tmp, visited, initial=true);
				if(weight != 0.0) {
					totalWeight += weight;
					if(randomd() < weight / totalWeight) {
						auto@ swp = path;
						@path = tmp;
						@tmp = swp;
					}
				}
			}
		}

		if(path.length != 0) {
			for(uint i = 0, cnt = path.length; i < cnt; ++i) {
				if(log)
					ai.print("Queue research: "+path[i].type.name+" at "+path[i].position);
				immediateQueue.insertLast(path[i]);
			}
		}
	}

	double immTimer = randomd(10.0, 60.0);
	void focusTick(double time) override {
		//Queue some new research if we have to
		if(immediateQueue.length == 0) {
			immTimer -= time;
			if(immTimer <= 0.0) {
				immTimer = 60.0;
				queueNewResearch();
			}
		}
		else {
			immTimer = 0.0;
		}

		//Deal with current queued research
		if(immediateQueue.length != 0) {
			auto@ node = immediateQueue[0];
			if(!receive(ai.empire.getTechnologyNode(node.id), node)) {
				immediateQueue.removeAt(0);
			}
			else if(!node.available || node.bought) {
				immediateQueue.removeAt(0);
			}
			else {
				double cost = node.getPointCost(ai.empire);
				if(cost == 0) {
					//Try it once and then give up
					ai.empire.research(node.id, secondary=true);
					immediateQueue.removeAt(0);

					if(log)
						ai.print("Attempt secondary research: "+node.type.name+" at "+node.position);
				}
				else if(cost <= ai.empire.ResearchPoints) {
					//If we have enough to buy it, buy it
					ai.empire.research(node.id);
					immediateQueue.removeAt(0);

					if(log)
						ai.print("Purchase research: "+node.type.name+" at "+node.position);
				}
			}
		}
	}
};

AIComponent@ createResearch() {
	return Research();
}
