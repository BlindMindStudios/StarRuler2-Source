import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Planets;

import buildings;

class Verdant : Race, RaceDesigns {
	Designs@ designs;
	Development@ development;
	Planets@ planets;

	array<const Design@> defaultDesigns;
	array<uint> defaultGoals;

	const SubsystemDef@ sinewSubsystem;
	const SubsystemDef@ supportSinewSubsystem;

	const BuildingType@ stalk;

	void create() override {
		@designs = cast<Designs>(ai.designs);
		@development = cast<Development>(ai.development);
		@planets = cast<Planets>(ai.planets);

		@sinewSubsystem = getSubsystemDef("VerdantSinew");
		@supportSinewSubsystem = getSubsystemDef("VerdantSupportSinew");
		@stalk = getBuildingType("Stalk");
	}

	void start() override {
		ReadLock lock(ai.empire.designMutex);
		for(uint i = 0, cnt = ai.empire.designCount; i < cnt; ++i) {
			const Design@ dsg = ai.empire.getDesign(i);
			if(dsg.newer !is null)
				continue;
			if(dsg.updated !is null)
				continue;

			uint goal = designs.classify(dsg, DP_Unknown);
			if(goal == DP_Unknown)
				continue;

			defaultDesigns.insertLast(dsg);
			defaultGoals.insertLast(goal);
		}
	}

	void save(SaveFile& file) override {
		uint cnt = defaultDesigns.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			file << defaultDesigns[i];
			file << defaultGoals[i];
		}
	}

	void load(SaveFile& file) override {
		uint cnt = 0;
		file >> cnt;
		defaultDesigns.length = cnt;
		defaultGoals.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			file >> defaultDesigns[i];
			file >> defaultGoals[i];
		}
	}

	uint plCheck = 0;
	void focusTick(double time) override {
		//Check if we need to build stalks anywhere
		for(uint i = 0, cnt = development.focuses.length; i < cnt; ++i)
			checkForStalk(development.focuses[i].plAI);

		uint plCnt = planets.planets.length;
		if(plCnt != 0) {
			for(uint n = 0; n < min(plCnt, 5); ++n) {
				plCheck = (plCheck+1) % plCnt;
				auto@ plAI = planets.planets[plCheck];
				checkForStalk(plAI);
			}
		}
	}

	void checkForStalk(PlanetAI@ plAI) {
		if(plAI is null)
			return;
		Planet@ pl = plAI.obj;
		if(pl.pressureCap <= 0 && pl.totalPressure >= 1) {
			if(planets.isBuilding(plAI.obj, stalk))
				return;
			if(pl.getBuildingCount(stalk.id) != 0)
				return;

			planets.requestBuilding(plAI, stalk, expire=180.0);
		}
	}

	bool preCompose(DesignTarget@ target) override {
		return false;
	}

	bool postCompose(DesignTarget@ target) override {
	//	auto@ d = target.designer;

	//	//Add an extra engine
	//	if(target.purpose == DP_Combat)
	//		d.composition.insertAt(0, Exhaust(tag("Engine") & tag("GivesThrust"), 0.25, 0.35));

	//	//Remove armor layers we don't need
	//	for(uint i = 0, cnt = d.composition.length; i < cnt; ++i) {
	//		if(cast<ArmorLayer>(d.composition[i]) !is null) {
	//			d.composition.removeAt(i);
	//			--i; --cnt;
	//		}
	//	}

		return false;
	}

	bool design(DesignTarget@ target, int size, const Design@& output) {
		//All designs are rescales of default designs
		const Design@ baseDesign;
		uint possible = 0;
		for(uint i = 0, cnt = defaultDesigns.length; i < cnt; ++i) {
			if(defaultGoals[i] == target.purpose) {
				possible += 1;
				if(randomd() < 1.0 / double(possible))
					@baseDesign = defaultDesigns[i];
			}
		}

		if(baseDesign is null)
			return false;

		//if(target.designer !is null) {
		//	@target.designer.baseOffDesign = baseDesign;
		//	if(target.purpose != DP_Support)
		//		@target.designer.baseOffSubsystem = sinewSubsystem;
		//	else
		//		@target.designer.baseOffSubsystem = supportSinewSubsystem;
		//	@output = target.designer.design();
		//}

		if(output is null)
			@output = scaleDesign(baseDesign, size);
		return true;
	}
};

AIComponent@ createVerdant() {
	return Verdant();
}
