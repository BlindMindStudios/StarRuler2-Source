import research;
import saving;
import unlock_tags;
import achievements;
import unlock_tags;

tidy class ResearchGrid : Component_ResearchGrid, Savable {
	ReadWriteMutex mtx;

	TechnologyGrid@ grid;
	double researchRate = 0;
	double points = 0;
	double totalGenerated = 0;

	bool delta = false;
	bool gridDelta = false;

	Mutex unlockMtx;
	array<int> tagUnlocks;
	bool unlockDelta = false;

	double StatRecordDelay = 5.0;

	ResearchGrid() {}
	
	void save(SaveFile& file) {
		file << researchRate;
		file << points;
		file << grid;
		file << totalGenerated;

		uint cnt = tagUnlocks.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file.writeIdentifier(SI_UnlockTag, i);
			file << tagUnlocks[i];
		}
	}
	
	void load(SaveFile& file) {
		if(file < SV_0085) {
			loadOld(file);
			return;
		}
		file >> researchRate;
		file >> points;

		@grid = TechnologyGrid();
		file >> grid;
		file >> totalGenerated;

		tagUnlocks.length = getUnlockTagCount();
		for(uint i = 0, cnt = tagUnlocks.length; i < cnt; ++i)
			tagUnlocks[i] = 0;
		if(file >= SV_0091) {
			uint cnt = 0;
			file >> cnt;
			for(uint i = 0; i < cnt; ++i) {
				int id = file.readIdentifier(SI_UnlockTag);
				int val = 0;
				file >> val;

				if(id >= 0 && uint(id) < tagUnlocks.length)
					tagUnlocks[id] = val;
			}
		}
	}

	double get_ResearchRate(Empire& emp) {
		return researchRate * ResearchEfficiency * emp.ResearchGenerationFactor;
	}

	double get_ResearchPoints() {
		return points;
	}

	double get_ResearchEfficiency() {
		return 2000.0 / (2000.0 + totalGenerated);
	}

	void modResearchRate(double mod) {
		WriteLock lock(mtx);
		researchRate += mod;
	}
	
	bool gaveAchievement = false;

	void researchTick(Empire& emp, double time) {
		{
			WriteLock lock(mtx);
			double genPts = researchRate * time * ResearchEfficiency * emp.ResearchGenerationFactor;
			totalGenerated += genPts;
			points += genPts;

			for(uint i = 0; i < grid.nodes.length; ++i) {
				if(grid.nodes[i].timer >= 0)
					delta = true;
				grid.nodes[i].tick(emp, grid, time);
			}
		}
		
		StatRecordDelay -= time;
		bool recordStats = StatRecordDelay <= 0;
		if(recordStats) {
			emp.recordStat(stat::ResearchIncome, float(researchRate * ResearchEfficiency * emp.ResearchGenerationFactor));
			emp.recordStat(stat::ResearchTotal, totalGenerated);
			StatRecordDelay += 5.0;
			
			if(!gaveAchievement && totalGenerated >= 25000.0) {
				gaveAchievement = true;
				giveAchievement(emp, "ACH_MAX_TECH");
			}
		}
		
	}

	void generatePoints(Empire& emp, double pts, bool modified = true, bool penalized = true) {
		WriteLock lock(mtx);
		double genPts = pts;
		if(modified)
			genPts *= ResearchEfficiency;
		points += genPts;
		if(penalized)
			totalGenerated += genPts;
	}

	bool consumeResearchPoints(int amount) {
		WriteLock lock(mtx);
		if(points < amount)
			return false;
		points -= amount;
		return true;
	}

	void freeResearchPoints(int amount) {
		WriteLock lock(mtx);
		points += amount;
	}

	void reduceResearchPenalty(int points) {
		WriteLock lock(mtx);
		totalGenerated = max(0.0, totalGenerated - points);
	}

	void initResearch(Empire& emp) {
		WriteLock lock(mtx);
		if(hasDLC("Heralds"))
			@grid = getTechnologyGridSpec("Heralds").create();
		else
			@grid = getTechnologyGridSpec("Base").create();
		tagUnlocks.length = getUnlockTagCount();
		for(uint i = 0, cnt = tagUnlocks.length; i < cnt; ++i)
			tagUnlocks[i] = 0;

		//DLC unlock tags
		for(uint i = 0, cnt = dlcs.length; i < cnt; ++i) {
			if(!hasDLC(dlcs[i]))
				continue;
			int tag = getUnlockTag(dlcs[i]+"DLC");
			tagUnlocks[tag] = 1;
		}

		//Pick some secret projects
		for(uint n = 0; n < uint(config::PICK_SECRET_PROJECTS); ++n) {
			TechnologyNode@ node;
			double total = 0.0;
			for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
				auto@ other = grid.nodes[i];
				if(!other.secret || other.type.secretFrequency <= 0.0)
					continue;
				if(other.secretPicked)
					continue;
				if(!other.canBeSecret(emp))
					continue;

				total += other.type.secretFrequency;
				if(randomd() < other.type.secretFrequency / total)
					@node = other;
			}

			if(node is null)
				break;

			node.secretPicked = true;
		}
	}

	void getTechnologyNodes() {
		if(grid is null)
			return;
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i)
			yield(grid.nodes[i]);
	}

	void getResearchingNodes() {
		if(grid is null)
			return;
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

	void getTechnologyNode(int id) {
		ReadLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(id == grid.nodes[i].id) {
				yield(grid.nodes[i]);
				return;
			}
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

	TechnologyNode@ getNode(int id) {
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			if(grid.nodes[i].id == id)
				return grid.nodes[i];
		}
		return null;
	}

	void setResearchQueued(Empire& emp, int id, bool queued) {
		WriteLock lock(mtx);
		auto@ node = getNode(id);
		if(node is null)
			return;
		if(node.bought)
			return;

		node.queued = queued;
	}

	void research(Empire& emp, int id, bool secondary = false, bool queue = false) {
		WriteLock lock(mtx);
		auto@ node = getNode(id);
		if(node is null)
			return;
		if(node.bought)
			return;
		if(!node.canUnlock(emp)) {
			if(queue && !secondary) {
				node.queued = true;
				delta = true;
			}
			return;
		}

		auto cost = node.getPointCost(emp);
		if(secondary) {
			if(emp.ForbidSecondaryUnlock != 0 && cost != 0)
				return;
			if(!node.canSecondaryUnlock(emp))
				return;
			if(!node.consumeSecondary(emp))
				return;
			node.secondaryUnlock = true;
			totalGenerated += node.getPointCost(emp);
		}
		else {
			if(cost == 0)
				return;
			if(cost > points) {
				if(queue) {
					node.queued = true;
					delta = true;
				}
				return;
			}
			points -= cost;
		}

		node.buy(emp);
		grid.markBought(node.position, emp);
		delta = true;
	}

	bool isTagUnlocked(int id) {
		if(id < 0 || uint(id) >= tagUnlocks.length)
			return false;
		return tagUnlocks[id] > 0;
	}

	void setTagUnlocked(int id, bool unlocked) {
		if(id < 0 || uint(id) >= tagUnlocks.length) {
			error("Error: cannot set unlocked for out-of-range tag "+id+" - "+getUnlockTagIdent(id));
			return;
		}
		Lock lck(unlockMtx);
		if(unlocked)
			tagUnlocks[id] += 1;
		else
			tagUnlocks[id] -= 1;
		unlockDelta = true;
	}

	void removeResearchOfType(int typeId) {
		WriteLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			auto@ node = grid.nodes[i];
			if(int(node.type.id) == typeId) {
				if(!node.unlocked) {
					grid.nodes.removeAt(i);
					--i;
					--cnt;
				}
			}
		}
		grid.regenGrid();
		gridDelta = true;
	}

	void replaceResearchAt(vec2i pos, int replaceWith) {
		auto@ otherType = getTechnology(replaceWith);
		if(otherType is null)
			return;

		WriteLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			auto@ node = grid.nodes[i];
			if(node.position == pos) {
				if(!node.unlocked) {
					@node.type = otherType;
					if(otherType.defaultUnlock)
						grid.markUnlocked(node.position);
				}
			}
		}
		gridDelta = true;
	}

	void replaceResearchOfType(int typeId, int replaceWith) {
		auto@ otherType = getTechnology(replaceWith);
		if(otherType is null)
			return;

		WriteLock lock(mtx);
		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			auto@ node = grid.nodes[i];
			if(int(node.type.id) == typeId) {
				if(!node.unlocked) {
					@node.type = otherType;
					if(otherType.defaultUnlock)
						grid.markUnlocked(node.position);
				}
			}
		}
		gridDelta = true;
	}

	void replaceResearchGrid(string name) {
		auto@ gridType = getTechnologyGridSpec(name);
		if(gridType is null)
			return;

		WriteLock lock(mtx);
		@grid = gridType.create();
		gridDelta = true;
	}

	void overlayResearchGrid(string name) {
		auto@ gridType = getTechnologyGridSpec(name);
		if(gridType is null)
			return;

		WriteLock lock(mtx);
		@grid = gridType.create();
		gridDelta = true;
	}

	void revealSecretProject(Empire& emp, bool pickedOnly) {
		WriteLock lock(mtx);

		TechnologyNode@ pick;
		double count = 0;

		for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
			auto@ node = grid.nodes[i];
			if(!node.secret)
				continue;
			if(pickedOnly && !node.secretPicked)
				continue;
			if(node.available)
				continue;
			if(!node.canBeSecret(emp))
				continue;

			count += 1.0;
			if(randomd() < 1.0 / count)
				@pick = node;
		}

		if(pick !is null) {
			pick.secretPicked = true;
			pick.secret = false;
		}
	}

	//Networking
	void writeResearch(Message& msg, bool initial) {
		ReadLock lock(mtx);
		msg << researchRate;
		msg << points;
		msg << totalGenerated;

		if(initial) {
			msg.write1();
			msg.write1();
		}
		else {
			msg.writeBit(delta);
			msg.writeBit(gridDelta);
		}

		if(initial || unlockDelta) {
			msg.write1();
			uint cnt = tagUnlocks.length;
			msg.writeSmall(cnt);
			for(uint i = 0; i < cnt; ++i)
				msg.writeBit(tagUnlocks[i] > 0);
			if(!initial)
				unlockDelta = false;
		}
		else {
			msg.write0();
		}

		if(initial || delta || gridDelta) {
			if(initial || gridDelta) {
				msg << grid.minPos;
				msg << grid.maxPos;
				msg << grid.nodes.length;
			}

			for(uint i = 0, cnt = grid.nodes.length; i < cnt; ++i) {
				if(initial || gridDelta)
					grid.nodes[i].write(msg);
				else
					grid.nodes[i].writeStatus(msg);
			}

			if(!initial) {
				delta = false;
				gridDelta = false;
			}
		}
	}

	//Skip over data from old savegames
	void loadOld(SaveFile& file) {
		int tmp = 0;
		int64 tmp64 = 0;
		double tmpD = 0;
		bool tmpB = false;
		Object@ tmpO;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			//load field
			file >> tmp;
			file >> tmp;
			if(file < SV_0072)
				file >> tmp;
			file >> tmpD;
			file >> tmpD;
		}

		if(file.readBit())
			file >> tmp;

		file >> researchRate;
		file >> tmpD;
		file >> tmp;
		file >> tmp;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			//load project
			file >> tmp;
			uint type = 0;
			file >> type;
			for(uint n = 0; n < 7; ++n)
				file >> tmp;
			file >> tmpB;
			//load hooks
			if(tmpB) {
				if(type == 24 || type == 25) {
					file >> tmpD;
				}
				else if(type == 27) {
					uint sub = 0;
					file >> sub;
					for(uint j = 0; j < sub; ++j) {
						file >> tmpO;
						file >> tmpD;
						file >> tmpB;
						if(tmpB && file >= SV_0013)
							file >> tmp64;
					}
				}
			}
		}

		file >> tmp;
		for(uint i = 0; i < 7; ++i)
			file >> tmp;
	}
};
