import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Colonization;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Scouting;
import empire_ai.weasel.Orbitals;
import empire_ai.weasel.Budget;

from orbitals import getOrbitalModuleID;
from constructions import ConstructionType, getConstructionType;

class Extragalactic : Race {
	Colonization@ colonization;
	Construction@ construction;
	Scouting@ scouting;
	Orbitals@ orbitals;
	Resources@ resources;
	Budget@ budget;

	array<OrbitalAI@> beacons;
	OrbitalAI@ masterBeacon;

	int beaconMod = -1;

	array<ImportData@> imports;
	array<const ConstructionType@> beaconBuilds;

	void create() {
		@colonization = cast<Colonization>(ai.colonization);
		colonization.performColonization = false;
		colonization.queueColonization = false;

		@scouting = cast<Scouting>(ai.scouting);
		scouting.buildScouts = false;

		@orbitals = cast<Orbitals>(ai.orbitals);
		beaconMod = getOrbitalModuleID("Beacon");

		@construction = cast<Construction>(ai.construction);
		@resources = cast<Resources>(ai.resources);
		@budget = cast<Budget>(ai.budget);

		beaconBuilds.insertLast(getConstructionType("BeaconHealth"));
		beaconBuilds.insertLast(getConstructionType("BeaconWeapons"));
		beaconBuilds.insertLast(getConstructionType("BeaconLabor"));
	}

	void save(SaveFile& file) override {
		uint cnt = beacons.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			orbitals.saveAI(file, beacons[i]);
		orbitals.saveAI(file, masterBeacon);

		cnt = imports.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			resources.saveImport(file, imports[i]);
	}

	void load(SaveFile& file) override {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ b = orbitals.loadAI(file);
			if(b !is null && b.obj !is null)
				beacons.insertLast(b);
		}
		@masterBeacon = orbitals.loadAI(file);

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ imp = resources.loadImport(file);
			if(imp !is null)
				imports.insertLast(imp);
		}
	}

	uint prevBeacons = 0;
	void focusTick(double time) {
		//Find our beacons
		for(uint i = 0, cnt = beacons.length; i < cnt; ++i) {
			auto@ b = beacons[i];
			if(b is null || b.obj is null || !b.obj.valid || b.obj.owner !is ai.empire) {
				if(b.obj !is null)
					resources.killImportsTo(b.obj);
				beacons.removeAt(i);
				--i; --cnt;
			}
		}

		for(uint i = 0, cnt = orbitals.orbitals.length; i < cnt; ++i) {
			auto@ orb = orbitals.orbitals[i];
			Orbital@ obj = cast<Orbital>(orb.obj);
			if(obj !is null && obj.coreModule == uint(beaconMod)) {
				if(beacons.find(orb) == -1)
					beacons.insertLast(orb);
			}
		}

		//Find our master beacon
		if(masterBeacon !is null) {
			Orbital@ obj = cast<Orbital>(masterBeacon.obj);
			if(obj is null || !obj.valid || obj.owner !is ai.empire || obj.hasMaster())
				@masterBeacon = null;
		}
		else {
			for(uint i = 0, cnt = beacons.length; i < cnt; ++i) {
				auto@ b = beacons[i];
				Orbital@ obj = cast<Orbital>(b.obj);
				if(!obj.hasMaster()) {
					@masterBeacon = b;
					ai.empire.setDefending(obj, true);
					break;
				}
			}
		}

		scouting.buildScouts = gameTime > 5.0 * 60.0;
		if(prevBeacons < beacons.length && masterBeacon !is null && gameTime > 10.0) {
			for(int i = beacons.length-1; i >= int(prevBeacons); --i) {
				//Make sure we order a scout at each beacon
				if(!scouting.buildScouts) {
					BuildFlagshipSourced build(scouting.scoutDesign);
					build.moneyType = BT_Military;
					@build.buildAt = masterBeacon.obj;
					if(beacons[i] !is masterBeacon)
						@build.buildFrom = beacons[i].obj;

					construction.build(build, force=true);
				}

				//Set the beacon to fill up other stuff
				beacons[i].obj.allowFillFrom = true;
			}
			prevBeacons = beacons.length;
		}

		//Handle with importing labor and defense to our master beacon
		if(masterBeacon !is null) {
			if(imports.length == 0) {
				//Request labor and defense at our beacon
				{
					ResourceSpec spec;
					spec.type = RST_Pressure_Type;
					spec.pressureType = TR_Labor;

					imports.insertLast(resources.requestResource(masterBeacon.obj, spec));
				}
				{
					ResourceSpec spec;
					spec.type = RST_Pressure_Type;
					spec.pressureType = TR_Defense;

					imports.insertLast(resources.requestResource(masterBeacon.obj, spec));
				}
				{
					ResourceSpec spec;
					spec.type = RST_Pressure_Level0;
					spec.pressureType = TR_Research;

					imports.insertLast(resources.requestResource(masterBeacon.obj, spec));
				}
			}
			else {
				//When our requests are met, make more requests!
				for(uint i = 0, cnt = imports.length; i < cnt; ++i) {
					if(imports[i].beingMet || imports[i].obj !is masterBeacon.obj) {
						ResourceSpec spec;
						spec = imports[i].spec;
						@imports[i] = resources.requestResource(masterBeacon.obj, spec);
					}
				}
			}

			//Build stuff on our beacon if we have enough stuff
			if(budget.canSpend(BT_Development, 300)) {
				uint offset = randomi(0, beaconBuilds.length-1);
				for(uint i = 0, cnt = beaconBuilds.length; i < cnt; ++i) {
					uint ind = (i+offset) % cnt;
					auto@ type = beaconBuilds[ind];
					if(type is null)
						continue;

					if(type.canBuild(masterBeacon.obj, ignoreCost=false)) {
						masterBeacon.obj.buildConstruction(type.id);
						break;
					}
				}
			}
		}
	}
};

AIComponent@ createExtragalactic() {
	return Extragalactic();
}
