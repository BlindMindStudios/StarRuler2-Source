// Energy
// ------
// Manage the use of energy on artifacts and other things.
//

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Systems;

import ai.consider;

import artifacts;
import abilities;
import systems;

from ai.artifacts import Artifacts, ArtifactConsider, ArtifactAI;

double effCostEstimate(double cost, double freeStorage) {
	double free = min(cost, freeStorage);
	cost -= free;

	double effStep = config::ENERGY_EFFICIENCY_STEP;
	double eff = 0.0;
	double step = 1.0;
	while(cost > 0) {
		eff += (cost / effStep) * step;
		cost -= effStep;
		step *= 2.0;
	}
	return eff * effStep + free;
}

class ConsiderEnergy : ArtifactConsider {
	int id = -1;
	const ArtifactType@ type;
	Artifact@ artifact;
	Ability@ ability;
	Object@ target;
	vec3d pointTarget;
	double cost = 0.0;
	double value = 0.0;

	void save(AI& ai, SaveFile& file) {
		file << id;
		file << artifact;
		file << target;
		file << cost;
		file << value;
		file << pointTarget;
	}

	void load(AI& ai, SaveFile& file) {
		file >> id;
		file >> artifact;
		file >> target;
		file >> cost;
		file >> value;
		file >> pointTarget;

		if(artifact !is null)
			init(ai, artifact);
	}

	void setTarget(Object@ obj) {
		@target = obj;
	}

	Object@ getTarget() {
		return target;
	}

	bool canTarget(Object@ obj) {
		if(ability.targets.length != 0) {
			auto@ targ = ability.targets[0];
			@targ.obj = obj;
			targ.filled = true;
			return ability.isValidTarget(0, targ);
		}
		else
			return false;
	}

	void setTargetPosition(const vec3d& point) {
		pointTarget = point;
	}

	vec3d getTargetPosition() {
		return pointTarget;
	}

	bool canTargetPosition(const vec3d& point) {
		if(ability.targets.length != 0) {
			auto@ targ = ability.targets[0];
			targ.point = point;
			targ.filled = true;
			return ability.isValidTarget(0, targ);
		}
		else
			return false;
	}

	void init(AI& ai, Artifact@ artifact) {
		@this.artifact = artifact;
		@type = getArtifactType(artifact.ArtifactType);

		if(ability is null)
			@ability = Ability();
		if(type.secondaryChance > 0 && type.abilities.length >= 2
				&& randomd() < type.secondaryChance) {
			ability.id = 1;
			@ability.type = type.abilities[1];
		}
		else {
			ability.id = 0;
			@ability.type = type.abilities[0];
		}
		ability.targets = Targets(ability.type.targets);
		@ability.obj = artifact;
		@ability.emp = ai.empire;
	}

	bool isValid(AI& ai, Energy& energy) {
		return energy.canUse(artifact);
	}

	void considerEnergy(AI& ai, Energy& energy) {
		if(type !is null && type.abilities.length != 0) {
			value = 1.0;

			for(uint i = 0, cnt = type.ai.length; i < cnt; ++i) {
				ArtifactAI@ ai;
				if(ability.id == 0)
					@ai = cast<ArtifactAI>(type.ai[i]);
				else
					@ai = cast<ArtifactAI>(type.secondaryAI[i]);
				if(ai !is null) {
					if(!ai.consider(energy, this, value)) {
						value = 0.0;
						break;
					}
				}
			}
			if(type.ai.length == 0)
				value = 0.0;

			if(ability.targets.length != 0) {
				if(ability.targets[0].type == TT_Object) {
					@ability.targets[0].obj = target;
					ability.targets[0].filled = true;

					if(target is null)
						value = 0.0;
				}
				else if(ability.targets[0].type == TT_Point) {
					ability.targets[0].point = pointTarget;
					ability.targets[0].filled = true;
				}
			}

			if(value > 0.0) {
				if(!ability.canActivate(ability.targets, ignoreCost=true)) {
					value = 0.0;
				}
				else {
					cost = ability.getEnergyCost(ability.targets);
					if(cost != 0.0) {
						//Estimate the amount of turns it would take to trigger this,
						//and devalue it based on that. This is ceiled in order to allow
						//for artifacts of similar cost to not be affected by cost differences.
						double effCost = effCostEstimate(cost, energy.freeStorage);
						double estTime = effCost / max(energy.baseIncome, 0.01);
						double turns = ceil(estTime / (3.0 * 60.0));
						value /= turns;
					}
					else {
						value *= 1000.0;
					}
				}
			}
		}
		else {
			value = 0.0;
		}
	}

	void execute(AI& ai, Energy& energy) {
		if(artifact !is null && type.abilities.length != 0) {
			if(energy.log)
				ai.print("Activate artifact "+artifact.name, artifact.region);

			if(ability.type.targets.length != 0) {
				if(ability.type.targets[0].type == TT_Object)
					artifact.activateAbilityTypeFor(ai.empire, ability.type.id, target);
				else if(ability.type.targets[0].type == TT_Point)
					artifact.activateAbilityTypeFor(ai.empire, ability.type.id, pointTarget);
			}
			else {
				artifact.activateAbilityTypeFor(ai.empire, ability.type.id);
			}
		}
	}

	int opCmp(const ConsiderEnergy@ other) const {
		if(value < other.value)
			return -1;
		if(value > other.value)
			return 1;
		return 0;
	}
};

class Energy : AIComponent, Artifacts {
	Systems@ systems;

	double baseIncome;
	double freeStorage;

	array<ConsiderEnergy@> queue;
	int nextEnergyId = 0;

	void save(SaveFile& file) {
		file << nextEnergyId;

		uint cnt = queue.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			queue[i].save(ai, file);
	}

	void load(SaveFile& file) {
		file >> nextEnergyId;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			ConsiderEnergy c;
			c.load(ai, file);

			if(c.artifact !is null)
				queue.insertLast(c);
		}
	}

	void create() {
		@systems = cast<Systems>(ai.systems);
	}

	Considerer@ get_consider() {
		return cast<Considerer>(ai.consider);
	}

	Empire@ get_empire() {
		return ai.empire;
	}

	bool canUse(Artifact@ artifact) {
		if(artifact is null || !artifact.valid)
			return false;
		Empire@ owner = artifact.owner;
		if(owner.valid && owner !is ai.empire)
			return false;
		Region@ reg = artifact.region;
		if(reg is null)
			return false;
		if(reg.PlanetsMask != 0)
			return reg.PlanetsMask & ai.mask != 0;
		else
			return hasTradeAdjacent(ai.empire, reg);
	}

	ConsiderEnergy@ registerArtifact(Artifact@ artifact) {
		if(!canUse(artifact))
			return null;

		for(uint i = 0, cnt = queue.length; i < cnt; ++i) {
			if(queue[i].artifact is artifact)
				return queue[i];
		}

		ConsiderEnergy c;
		c.id = nextEnergyId++;
		c.init(ai, artifact);

		if(log)
			ai.print("Detect artifact "+artifact.name, artifact.region);

		queue.insertLast(c);
		return c;
	}

	uint updateIdx = 0;
	bool update() {
		if(queue.length == 0)
			return false;
		updateIdx = (updateIdx+1) % queue.length;
		auto@ c = queue[updateIdx];
		double prevValue = c.value;

		//Make sure this is still valid
		if(!c.isValid(ai, this)) {
			queue.removeAt(updateIdx);
			return false;
		}

		//Update the current target and value
		c.considerEnergy(ai, this);

		/*if(log)*/
		/*	ai.print(c.artifact.name+": consider "+c.value+" for cost "+c.cost, c.target);*/

		//Only re-sort when needed
		bool changed = false;
		if(prevValue != c.value) {
			if(updateIdx > 0) {
				if(c.value > queue[updateIdx-1].value)
					changed = true;
			}
			if(updateIdx < queue.length-1) {
				if(c.value < queue[updateIdx+1].value)
					changed = true;
			}
		}

		return changed;
	}

	uint sysIdx = 0;
	void updateSystem() {
		uint totCnt = systems.owned.length + systems.outsideBorder.length;
		if(totCnt == 0)
			return;

		sysIdx = (sysIdx+1) % totCnt;
		SystemAI@ sys;
		if(sysIdx < systems.owned.length)
			@sys = systems.owned[sysIdx];
		else
			@sys = systems.outsideBorder[sysIdx - systems.owned.length];

		for(uint i = 0, cnt = sys.artifacts.length; i < cnt; ++i)
			registerArtifact(sys.artifacts[i]);
	}

	void tick(double time) {
		//Update current income
		baseIncome = empire.EnergyIncome;
		freeStorage = empire.FreeEnergyStorage;

		//See if we can use anything right now
		if(queue.length != 0) {
			auto@ c = queue[0];
			if(!c.isValid(ai, this)) {
				queue.removeAt(0);
			}
			else if(c.value > 0.0 && ai.empire.EnergyStored >= c.cost) {
				c.execute(ai, this);
				queue.removeAt(0);
			}
		}
	}

	void focusTick(double time) {
		//Consider artifact usage
		bool changed = false;
		for(uint n = 0; n < min(queue.length, max(ai.behavior.artifactFocusConsiderCount, queue.length/20)); ++n) {
			if(update())
				changed = true;
		}

		//Re-sort consideration
		if(changed)
			queue.sortDesc();

		//Try to find new artifacts
		updateSystem();
	}
};

AIComponent@ createEnergy() {
	return Energy();
}
