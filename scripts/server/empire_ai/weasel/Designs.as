import empire_ai.weasel.WeaselAI;

import util.design_export;
import util.random_designs;

interface RaceDesigns {
	bool preCompose(DesignTarget@ target);
	bool postCompose(DesignTarget@ target);
	bool design(DesignTarget@ target, int size, const Design@& output);
};

enum DesignPurpose {
	DP_Scout,
	DP_Combat,
	DP_Defense,
	DP_Support,
	DP_Gate,
	DP_Slipstream,
	DP_Mothership,
	DP_Miner,

	DP_COUNT,
	DP_Unknown,
};

tidy final class DesignTarget {
	int id = -1;
	const Design@ active;
	string customName;

	array<const Design@> potential;
	array<double> scores;

	uint purpose;
	double targetBuildCost = 0;
	double targetMaintenance = 0;
	double targetLaborCost = 0;

	double dps = 0.0;
	double hp = 0.0;
	double supplyDrain = 0.0;

	double targetSize = 0;
	bool findSize = false;

	Designer@ designer;

	DesignTarget() {
	}

	DesignTarget(uint type, double targetSize) {
		this.purpose = type;
		this.targetSize = targetSize;
	}

	uint get_designType() {
		switch(purpose) {
			case DP_Scout: return DT_Flagship;
			case DP_Combat: return DT_Flagship;
			case DP_Defense: return DT_Station;
			case DP_Support: return DT_Support;
			case DP_Gate: return DT_Station;
			case DP_Slipstream: return DT_Flagship;
			case DP_Mothership: return DT_Flagship;
		}
		return DT_Flagship;
	}
	
	void save(Designs& designs, SaveFile& file) {
		if(active !is null) {
			file.write1();
			file << active;
			file << dps;
			file << supplyDrain;
			file << hp;
		}
		else {
			file.write0();
		}

		file << purpose;
		file << targetBuildCost;
		file << targetMaintenance;
		file << targetLaborCost;
		file << targetSize;
		file << findSize;
		file << customName;
	}

	void load(Designs& designs, SaveFile& file) {
		if(file.readBit()) {
			file >> active;
			file >> dps;
			file >> supplyDrain;
			file >> hp;
		}

		file >> purpose;
		file >> targetBuildCost;
		file >> targetMaintenance;
		file >> targetLaborCost;
		file >> targetSize;
		file >> findSize;
		file >> customName;
	}

	void prepare(AI& ai) {
		@designer = Designer(designType, targetSize, ai.empire, compose=false);
		designer.randomHull = true;

		switch(purpose) {
			case DP_Scout:
				designer.composeScout();
			break;
			case DP_Combat:
				designer.composeFlagship();
			break;
			case DP_Defense:
				designer.composeStation();
			break;
			case DP_Support:
				designer.composeSupport();
			break;
			case DP_Gate:
				designer.composeGate();
			break;
			case DP_Slipstream:
				designer.composeSlipstream();
			break;
			case DP_Mothership:
				designer.composeMothership();
			break;
		}
	}

	double weight(double value, double goal) {
		if(value < goal)
			return sqr(value / goal);
		else if(value > goal * 1.5)
			return goal / value;
		return 1.0;
	}

	double costWeight(double value, double goal) {
		if(findSize) {
			if(value < goal)
				return 1.0;
			else
				return 0.000001;
		}
		else {
			if(value < goal)
				return goal / value;
			else
				return pow(0.2, ((value / goal) - 1.0) * 10.0);
		}
	}

	double evaluate(AI& ai, const Design& dsg) {
		double w = 1.0;

		//Try to stick as close to our target as we can
		if(targetBuildCost != 0)
			w *= costWeight(dsg.total(HV_BuildCost), targetBuildCost);
		if(targetLaborCost != 0)
			w *= costWeight(dsg.total(HV_LaborCost), targetLaborCost);
		if(targetMaintenance != 0)
			w *= costWeight(dsg.total(HV_MaintainCost), targetMaintenance);

		double predictHP = 0.0;
		double predictDPS = 0.0;
		double predictDrain = 0.0;

		//Value support capacity where appropriate
		if(purpose == DP_Combat) {
			double supCap = dsg.total(SV_SupportCapacity);
			double avgHP = 0, avgDPS = 0, avgDrain = 0.0;
			cast<Designs>(ai.designs).getSupportAverages(avgHP, avgDPS, avgDrain);

			predictHP += supCap * avgHP;
			predictDPS += supCap * avgDPS;
			predictDrain += supCap * avgDrain;
		}

		//Value combat strength where appropriate
		if(purpose != DP_Scout && purpose != DP_Slipstream && purpose != DP_Mothership) {
			predictDPS += dsg.total(SV_DPS);
			predictHP += dsg.totalHP + dsg.total(SV_ShieldCapacity);
			predictDrain += dsg.total(SV_SupplyDrain);

			if(purpose != DP_Support) {
				w *= (predictHP * predictDPS) * 0.001;

				double supplyStores = dsg.total(SV_SupplyCapacity);
				double actionTime = supplyStores / predictDrain;
				w *= weight(actionTime, ai.behavior.fleetAimSupplyDuration);
			}
		}

		//Value acceleration on a target
		if(purpose != DP_Defense && purpose != DP_Gate) {
			double targetAccel = 2.0;
			if(purpose == DP_Support)
				targetAccel *= 1.5;
			else if(purpose == DP_Scout)
				targetAccel *= 3.0;

			w *= weight(dsg.total(SV_Thrust) / max(dsg.total(HV_Mass), 0.01), targetAccel);
		}

		//Penalties for having important systems easy to shoot down
		uint holes = 0;
		for(uint i = 0, cnt = dsg.subsystemCount; i < cnt; ++i) {
			auto@ sys = dsg.subsystem(i);
			if(!sys.type.hasTag(ST_Important))
				continue;
			//TODO: We should be able to penalize for exposed supply storage
			if(sys.type.hasTag(ST_NoCore))
				continue;

			vec2u core = sys.core;
			for(uint d = 0; d < 6; ++d) {
				if(!traceContainsArmor(dsg, core, d))
					holes += 1;
			}
		}
		
		if(holes != 0)
			w /= pow(0.9, double(holes));

		//TODO: Check FTL

		return w;
	}

	bool traceContainsArmor(const Design@ dsg, const vec2u& startPos, uint direction) {
		vec2u pos = startPos;
		while(dsg.hull.active.valid(pos)) {
			if(!dsg.hull.active.advance(pos, HexGridAdjacency(direction)))
				break;

			auto@ sys = dsg.subsystem(pos.x, pos.y);
			if(sys is null)
				continue;
			if(sys.type.hasTag(ST_IsArmor))
				return true;
		}
		return false;
	}

	bool contains(const Design& dsg) {
		if(active is null)
			return false;
		if(dsg.mostUpdated() is active.mostUpdated())
			return true;
		return false;
	}

	const Design@ design(AI& ai, Designs& designs) {
		int trySize = targetSize;
		if(findSize) {
			trySize = randomd(0.75, 1.25) * targetSize;
			trySize = 5 * round(double(designer.size) / 5.0);
		}
		if(designs.race !is null) {
			const Design@ fromRace;
			if(designs.race.design(this, trySize, fromRace))
				return fromRace;
		}
		if(designer !is null) {
			designer.size = trySize;
			return designer.design(1);
		}
		return null;
	}

	void choose(AI& ai, const Design@ dsg, bool randomizeName=true) {
		set(dsg);
		@designer = null;
		findSize = false;

		string baseName = dsg.name;
		if(customName.length != 0) {
			baseName = customName;
		}
		else if(randomizeName) {
			if(dsg.hasTag(ST_IsSupport))
				baseName = autoSupportNames[randomi(0,autoSupportNames.length-1)];
			else
				baseName = autoFlagNames[randomi(0,autoFlagNames.length-1)];
		}

		string name = baseName;
		uint try = 0;
		while(ai.empire.getDesign(name) !is null) {
			name = baseName + " ";
			appendRoman(++try, name);
		}
		if(name != dsg.name)
			dsg.rename(name);

		//Set design settings/support behavior
		if(purpose == DP_Support) {
			if(dsg.total(SV_SupportSupplyCapacity) > 0.01) {
				DesignSettings settings;
				settings.behavior = SG_Brawler;
				dsg.setSettings(settings);
			}
			else if(dsg.totalHP > 50 * dsg.size) {
				DesignSettings settings;
				settings.behavior = SG_Shield;
				dsg.setSettings(settings);
			}
			else {
				DesignSettings settings;
				settings.behavior = SG_Cannon;
				dsg.setSettings(settings);
			}
		}


		ai.empire.addDesign(ai.empire.getDesignClass("AI", true), dsg);

		if(cast<Designs>(ai.designs).log)
			ai.print("Chose design for purpose "+uint(purpose)+" at size "+dsg.size);
	}

	void step(AI& ai, Designs& designs) {
		if(active is null) {
			if(designer is null) {
				if(designs.race is null || !designs.race.preCompose(this))
					prepare(ai);
				if(designs.race !is null && designs.race.postCompose(this))
					return;
			}
			if(potential.length >= ai.behavior.designEvaluateCount) {
				//Find the best design out of all our potentials
				const Design@ best;
				double bestScore = 0.0;

				for(uint i = 0, cnt = potential.length; i < cnt; ++i) {
					double w = scores[i];
					if(w > bestScore) {
						bestScore = w;
						@best = potential[i];
					}
				}
				potential.length = 0;
				scores.length = 0;

				if(best !is null)
					choose(ai, best);
			}
			else if(designer !is null && active is null) {
				//Add a new design onto the list to be evaluated
				const Design@ dsg = design(ai, designs);
				if(dsg !is null && !dsg.hasFatalErrors()) {
					potential.insertLast(dsg);
					scores.insertLast(evaluate(ai, dsg));

					/*if(designs.log)*/
					/*	ai.print("Designed for purpose "+uint(purpose)+" at size "+dsg.size+", weight "+evaluate(ai, dsg));*/
				}
			}
		}
		else {
			set(active.mostUpdated());
		}
	}

	void set(const Design@ dsg) {
		if(active is dsg)
			return;

		@active = dsg;
		targetBuildCost = dsg.total(HV_BuildCost);
		targetMaintenance = dsg.total(HV_MaintainCost);
		targetLaborCost = dsg.total(HV_LaborCost);
		targetSize = dsg.size;

		dps = dsg.total(SV_DPS);
		hp = dsg.totalHP + dsg.total(SV_ShieldCapacity);
		supplyDrain = dsg.total(SV_SupplyDrain);
	}
};

const Design@ scaleDesign(const Design@ orig, int newSize) {
	DesignDescriptor desc;
	resizeDesign(orig, newSize, desc);
	
	return makeDesign(desc);
}

final class Designs : AIComponent {
	RaceDesigns@ race;

	int nextTargetId = 0;
	array<DesignTarget@> designing;
	array<DesignTarget@> completed;
	array<DesignTarget@> automatic;

	void create() {
		@race = cast<RaceDesigns>(ai.race);
	}

	void start() {
		//Design some basic support sizes
		design(DP_Support, 1);
		design(DP_Support, 2);
		design(DP_Support, 4);
		design(DP_Support, 8);
		design(DP_Support, 16);
	}

	void save(SaveFile& file) {
		file << nextTargetId;

		uint cnt = designing.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveDesign(file, designing[i]);
			designing[i].save(this, file);
		}

		cnt = automatic.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveDesign(file, automatic[i]);
			if(!isDesigning(automatic[i])) {
				file.write1();
				automatic[i].save(this, file);
			}
			else {
				file.write0();
			}
		}

		cnt = completed.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			saveDesign(file, completed[i]);
			if(!isDesigning(completed[i])) {
				file.write1();
				completed[i].save(this, file);
			}
			else {
				file.write0();
			}
		}
	}

	bool isDesigning(DesignTarget@ targ) {
		for(uint i = 0, cnt = designing.length; i < cnt; ++i) {
			if(designing[i] is targ)
				return true;
		}
		return false;
	}

	void load(SaveFile& file) {
		file >> nextTargetId;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ targ = loadDesign(file);
			targ.load(this, file);
			designing.insertLast(targ);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ targ = loadDesign(file);
			if(file.readBit())
				targ.load(this, file);
			automatic.insertLast(targ);
		}

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ targ = loadDesign(file);
			if(file.readBit())
				targ.load(this, file);
			completed.insertLast(targ);
		}
	}

	array<DesignTarget@> loadIds;
	DesignTarget@ loadDesign(int id) {
		if(id == -1)
			return null;
		for(uint i = 0, cnt = loadIds.length; i < cnt; ++i) {
			if(loadIds[i].id == id)
				return loadIds[i];
		}
		DesignTarget data;
		data.id = id;
		loadIds.insertLast(data);
		return data;
	}
	DesignTarget@ loadDesign(SaveFile& file) {
		int id = -1;
		file >> id;
		if(id == -1)
			return null;
		else
			return loadDesign(id);
	}
	void saveDesign(SaveFile& file, DesignTarget@ data) {
		int id = -1;
		if(data !is null)
			id = data.id;
		file << id;
	}
	void postLoad(AI& ai) {
		loadIds.length = 0;
	}

	const Design@ get_currentSupport() {
		for(int i = automatic.length - 1; i >= 0; --i) {
			if(automatic[i].purpose == DP_Support && automatic[i].active !is null)
				return automatic[i].active;
		}
		return null;
	}

	void getSupportAverages(double& hp, double& dps, double& supDrain) {
		hp = 0;
		dps = 0;
		supDrain = 0;
		uint count = 0;
		for(uint i = 0, cnt = automatic.length; i < cnt; ++i) {
			auto@ targ = automatic[i];
			if(targ.purpose != DP_Support)
				continue;
			if(targ.active is null)
				continue;

			hp += targ.hp / double(targ.targetSize);
			dps += targ.dps / double(targ.targetSize);
			supDrain += targ.supplyDrain / double(targ.targetSize);
			count += 1;
		}

		if(count == 0) {
			hp = 40.0;
			dps = 0.30;
			supDrain = 1.0;
		}
		else {
			hp /= double(count);
			dps /= double(count);
			supDrain /= double(count);
		}
	}

	DesignPurpose classify(Object@ obj) {
		if(obj is null || !obj.isShip)
			return DP_Combat;
		Ship@ ship = cast<Ship>(obj);
		return classify(ship.blueprint.design);
	}

	DesignPurpose classify(const Design@ dsg, DesignPurpose defaultPurpose = DP_Combat) {
		if(dsg is null)
			return defaultPurpose;

		for(uint i = 0, cnt = automatic.length; i < cnt; ++i) {
			if(automatic[i].contains(dsg))
				return DesignPurpose(automatic[i].purpose);
		}

		for(uint i = 0, cnt = completed.length; i < cnt; ++i) {
			if(completed[i].contains(dsg))
				return DesignPurpose(completed[i].purpose);
		}

		if(dsg.hasTag(ST_Mothership))
			return DP_Mothership;
		if(dsg.hasTag(ST_Gate))
			return DP_Gate;
		if(dsg.hasTag(ST_Slipstream))
			return DP_Slipstream;
		if(dsg.hasTag(ST_Support))
			return DP_Support;
		if(dsg.hasTag(ST_Station))
			return DP_Defense;

		double dps = dsg.total(SV_DPS);
		if(dsg.total(SV_MiningRate) > 0)
			return DP_Miner;
		if(dsg.size == 16.0 && dsg.total(SV_DPS) < 2.0)
			return DP_Scout;
		if(dps > 0.1 * dsg.size || dsg.total(SV_SupportCapacity) > 0)
			return DP_Combat;
		return defaultPurpose;
	}

	DesignTarget@ design(uint purpose, int size, int targetCost = 0, int targetMaint = 0, double targetLabor = 0, bool findSize = false) {
		for(uint i = 0, cnt = automatic.length; i < cnt; ++i) {
			auto@ target = automatic[i];
			if(target.purpose != purpose)
				continue;
			if(target.targetSize != size)
				continue;
			if(targetCost != 0 && target.targetBuildCost > targetCost)
				continue;
			if(targetMaint != 0 && target.targetMaintenance > targetMaint)
				continue;
			if(targetLabor != 0 && target.targetLaborCost > targetLabor)
				continue;
			if(target.findSize != findSize)
				continue;
			return target;
		}

		DesignTarget targ(purpose, size);
		targ.findSize = findSize;
		targ.targetBuildCost = targetCost;
		targ.targetMaintenance = targetMaint;
		targ.targetLaborCost = targetLabor;

		automatic.insertLast(targ);
		return design(targ);
	}

	DesignTarget@ design(DesignTarget@ target) {
		target.id = nextTargetId++;
		designing.insertLast(target);
		return target;
	}

	DesignTarget@ get(const Design@ dsg) {
		for(uint i = 0, cnt = automatic.length; i < cnt; ++i) {
			if(automatic[i].contains(dsg))
				return automatic[i];
		}
		return null;
	}

	DesignTarget@ scale(const Design@ dsg, int newSize) {
		if(dsg.newer !is null) {
			auto@ newTarg = get(dsg.newest());
			if(newTarg.targetSize == newSize)
				return newTarg;
			@dsg = dsg.newest();
		}

		DesignTarget@ previous = get(dsg);

		uint purpose = DP_Combat;
		if(previous !is null)
			purpose = previous.purpose;
		else
			purpose = classify(dsg);

		DesignTarget target(purpose, newSize);
		target.id = nextTargetId++;
		@target.active = scaleDesign(dsg, newSize);

		ai.empire.changeDesign(dsg, target.active, ai.empire.getDesignClass(dsg.cls.name, true));

		if(previous !is null)
			automatic.remove(previous);
		automatic.insertLast(target);

		return target;
	}

	uint chkInd = 0;
	void tick(double time) {
		if(designing.length != 0) {
			//chkInd = (chkInd+1) % designing.length;
			// Getting 1 design first is better than getting all of them later
			chkInd = 0;
			auto@ target = designing[chkInd];
			target.step(ai, this);

			if(target.active !is null) {
				designing.removeAt(chkInd);
				if(automatic.find(target) == -1)
					completed.insertLast(target);
			}
		}
	}
};

AIComponent@ createDesigns() {
	return Designs();
}
