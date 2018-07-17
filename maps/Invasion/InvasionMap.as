#priority init 5001
#include "include/map.as"

#section server
import systems;
from game_start import galaxies;
import camps;
from empire import Creeps, Pirates;
import empire_data;
import object_creation;
import research;
import remnant_designs;
import artifacts;
from objects.Artifact import createArtifact;
from achievements import giveAchievement;

import void addModifierToEmpire(Empire@ emp, const string& spec) from "bonus_effects";
#section all

enum MapSetting {
	M_SysCount,
	M_SystemSpacing,
	M_Flatten,
};

const double BASE_STRENGTH = 6000.0;
const double DOUBLE_WAVES = 3.0;
const double HARD_DIFF_MIN = 1.0;

class InvasionMap : Map {
	InvasionMap() {
		super();

		name = locale::INVASION_MAP;
		description = locale::INVASION_MAP_DESC;

		color = 0xff4eaeff;
		icon = "maps/Invasion/invasion.png";

		sortIndex = -140;
		dlc = "Heralds";

		eatsPlayers = true;
		isUnique = true;
	}

#section client
	void makeSettings() {
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);

		auto@ diff = Dropdown(locale::INV_DIFFICULTY, "INVASION_DIFFICULTY");
		diff.addOption(locale::EASY, 0.25);
		diff.addOption(locale::NORMAL, 0.5);
		diff.addOption(locale::HARD, 1.0);
		diff.set(0.5);

		Description(locale::INVASION_MAP_TEXT, lines=2);
	}

#section server
	void modSettings(GameSettings& settings) override {
		config::ENABLE_INFLUENCE_VICTORY = 0.0;
		settings.setNamed("ENABLE_INFLUENCE_VICTORY", 0.0);

		config::ENABLE_DREAD_PIRATE = 0.0;
		settings.setNamed("ENABLE_DREAD_PIRATE", 0.0);
	}

	bool ensureConnectedLinks() override {
		return true;
	}

	void placeSystems() {
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		uint players = estPlayerCount;
		if(players == 0)
			players = 3;

		double radSize = spacing * 10.0 * double(players+1);
		double startDist = (radSize / (2.0 * pi)) + (spacing * 6.0);

		double heightDiff = spacing * 0.2;

		double radial = twopi / double(players+1);
		double startRad = radial / double(players+1);

		int edgeType = -1;
		auto@ sysType = getSystemType("AncientSystem");
		if(sysType !is null)
			edgeType = sysType.id;

		for(uint i = 0; i < players; ++i) {
			PlayerData dat;
			playerData.insertLast(dat);

			vec3d homePos = quaterniond_fromAxisAngle(vec3d_up(), startRad) * vec3d_front(startDist);
			if(!flatten)
				homePos.y += randomd(-heightDiff, heightDiff);

			//Create the homeworld
			auto@ hwSys = addSystem(homePos);
			hwSys.assignGroup = i;
			addPossibleHomeworld(hwSys);

			EndSystem hwEnd;
			hwEnd.index = hwSys.index;
			@dat.homeworld = hwEnd;

			//Create the edge systems
			double edgeRad = -0.3 * pi;
			for(uint n = 0; n < 3; ++n) {
				vec3d edgePos = homePos;
				edgePos += quaterniond_fromAxisAngle(vec3d_up(), edgeRad) * homePos.normalized(spacing * 0.6);

				auto@ sys = addSystem(edgePos, sysType=edgeType);
				sys.assignGroup = i;
				addLink(sys, hwSys);

				EndSystem es;
				es.index = sys.index;
				dat.edges.insertLast(es);

				edgeRad += 0.3 * pi;
			}

			//Create the extra layers
			for(uint l = 0; l < 5; ++l) {
				uint layCnt = 2+l;

				double totRad = pi * 0.25 * double(layCnt);
				double radStep = totRad / double(layCnt);
				double rad = totRad * -0.5 + radStep * 0.5;

				double sysDist = spacing * double(l+1);

				for(uint n = 0; n < layCnt; ++n) {
					vec3d sysPos = homePos;
					sysPos -= quaterniond_fromAxisAngle(vec3d_up(), rad) * homePos.normalized(sysDist);
					if(!flatten)
						sysPos.y += randomd(-heightDiff, heightDiff);

					auto@ sys = addSystem(sysPos);
					sys.assignGroup = i;

					EndSystem es;
					es.index = sys.index;
					dat.inner.insertLast(es);

					rad += radStep;
				}
			}

			startRad += radial + (radial / double(players+1));
		}
	}

	void preInit() {
		//Modify creep empire
		Pirates.name = locale::REMNANT_DEFENSE_LINE;
		Pirates.color = Color(0x4fd07bff);

		//Create invasion empire
		{
			@Invaders = Empire();
			Invaders.name = locale::INVADER;
			Invaders.color = Color(0xff4040ff);
			Invaders.major = false;
			Invaders.visionMask = ~0;

			auto@ flag = getEmpireFlag(randomi(0, getEmpireFlagCount()-1));
			Invaders.flagDef = flag.flagDef;
			Invaders.flagID = flag.id;
			@Invaders.flag = getMaterial(Creeps.flagDef);
			@Invaders.shipset = getShipset("ALL");
		}

		//Empires are allied with creeps here
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;

			Pirates.setHostile(emp, false);
			emp.setHostile(Pirates, false);

			Invaders.setHostile(emp, true);
			emp.setHostile(Invaders, true);

			emp.modTotalBudget(+500);
		}

		Pirates.setHostile(Invaders, true);
		Invaders.setHostile(Pirates, true);
	}

	void init() {
		if(isLoadedSave)
			return;

		//See if we should load strengths
		loadStrengthList("maps/Invasion/strengths.txt");

		//Add the global modifiers
		uint majorMask = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;

			emp.Victory = -2;

			addModifierToEmpire(emp, "StationHull::MaintenanceModFactor(0.0)");
			addModifierToEmpire(emp, "StationHull::HPModFactor(0.25)");
			addModifierToEmpire(emp, "StationHull::RangeModFactor(0.5)");
			addModifierToEmpire(emp, "StationHull::LaborModFactor(2.0)");
			addModifierToEmpire(emp, "StationHull::MaintCostFactor(0.0)");
			addModifierToEmpire(emp, "MaintCostFactor(0.0)");
			majorMask |= emp.mask;

			Object@ hw = emp.Homeworld;
			if(hw is null)
				@hw = emp.HomeObj;
			if(hw !is null)
				hw.modLaborIncome(+5.0 / 60.0);
		}

		//YOU WILL SIT IN THE CIRCLE AND SING KUMBAYA DAMNIT
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp.major)
				emp.ForcedPeaceMask |= majorMask;
		}

		//Spawn remnant defenses
		const Design@ defStation = Creeps.getDesign("Defense Station");
		for(uint i = 0, cnt = playerData.length; i < cnt; ++i) {
			auto@ dat = playerData[i];

			dat.homeworld.index += systems[0].index;
			@dat.homeworld.desc = getSystem(dat.homeworld.index);

			for(uint n = 0, ncnt = dat.inner.length; n < ncnt; ++n) {
				auto@ sys = dat.inner[n];
				sys.index += systems[0].index;
				@sys.desc = getSystem(sys.index);
			}

			for(uint n = 0, ncnt = dat.edges.length; n < ncnt; ++n) {
				auto@ sys = dat.edges[n];
				sys.index += systems[0].index;
				@sys.desc = getSystem(sys.index);
				double radius = sys.desc.radius;

				//Give everyone vision over this system
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
					sys.desc.object.grantVision(getEmpire(i));

				//Spawn defense stations
				vec3d offset = (sys.desc.position - dat.homeworld.desc.position).normalized(radius * 0.75);

				auto@ obj = createShip(sys.desc.position + offset, defStation, Pirates, free=true);
				obj.orbitDuration(1000000000000.0);
				sys.defenses.insertLast(obj);

				@obj = createShip(sys.desc.position + quaterniond_fromAxisAngle(vec3d_up(), pi * 0.2) * offset, defStation, Pirates, free=true);
				obj.orbitDuration(1000000000000.0);
				sys.defenses.insertLast(obj);

				@obj = createShip(sys.desc.position + quaterniond_fromAxisAngle(vec3d_up(), -pi * 0.2) * offset, defStation, Pirates, free=true);
				obj.orbitDuration(1000000000000.0);
				sys.defenses.insertLast(obj);
			}
		}
	}
#section all
};

#section server
class PlayerData : Savable {
	Empire@ empire;
	EndSystem@ homeworld;
	array<EndSystem@> inner;
	array<EndSystem@> edges;
	uint previousWave = uint(-1);

	double stationHealth = 0.0;
	double stationEff = 0.0;

	void save(SaveFile& file) {
		file << homeworld;
		file << empire;
		file << stationHealth;
		file << stationEff;
		file << previousWave;

		uint cnt = inner.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << inner[i];

		cnt = edges.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << edges[i];
	}

	void load(SaveFile& file) {
		@homeworld = EndSystem();
		file >> homeworld;
		file >> empire;
		file >> stationHealth;
		file >> stationEff;
		if(file >= SV_0156)
			file >> previousWave;

		uint cnt = 0;

		file >> cnt;
		inner.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@inner[i] = EndSystem();
			file >> inner[i];
		}

		file >> cnt;
		edges.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@edges[i] = EndSystem();
			file >> edges[i];
		}
	}
};

class EndSystem : Savable {
	uint index;
	SystemDesc@ desc;
	array<Ship@> defenses;
	array<Ship@> invaders;
	bool isFighting = false;

	void save(SaveFile& file) {
		file << index;
		file << isFighting;

		uint cnt = defenses.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << defenses[i];

		cnt = invaders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << invaders[i];
	}

	void load(SaveFile& file) {
		file >> index;
		file >> isFighting;

		uint cnt = 0;

		file >> cnt;
		defenses.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> defenses[i];

		file >> cnt;
		invaders.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> invaders[i];
	}
};

Mutex mtx;
array<PlayerData@> playerData;
Empire@ Invaders;
double symbolicStrength = 0.0;
double waveTimer = 0.0;
array<double> WAVE_STRENGTHS;

void save(SaveFile& file) {
	if(hasInvasionMap()) {
		file.write1();

		file << Invaders;
		file << symbolicStrength;
		file << waveTimer;

		uint cnt = playerData.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << playerData[i];
	}
	else {
		file.write0();
	}
}

void loadStrengthList(const string& fname) {
	WAVE_STRENGTHS.length = 0;

	ReadFile file(fname, true);
	while(file++)
		WAVE_STRENGTHS.insertLast(toDouble(file.line));
}

void load(SaveFile& file) {
	if(file.readBit()) {
		file >> Invaders;
		file >> symbolicStrength;
		file >> waveTimer;

		uint cnt = 0;
		file >> cnt;
		playerData.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@playerData[i] = PlayerData();
			file >> playerData[i];
		}
	}

	loadStrengthList("maps/Invasion/strengths.txt");
}

double getInvasionInterval() {
	return 3.0 * 60.0;
}

double getInvasionTimer() {
	return waveTimer;
}

double getInvasionStrength() {
	return symbolicStrength;
}

void increaseInvasionStrength(double amount, bool modify = true) {
	if(modify)
		amount /= double(playerData.length);
	symbolicStrength += amount;
}

bool hasInvasionMap() {
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
		if(cast<InvasionMap>(galaxies[i]) !is null)
			return true;
	}
	return false;
}

bool initialized = false;
void tick(double time) {
	if(!hasInvasionMap())
		return;

	if(!initialized && playerEmpire.valid) {
		guiDialogueAction(CURRENT_PLAYER, "Invasion.InvasionMap::SetupGUI");
		if(!isLoadedSave) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				if(!emp.major)
					continue;

				emp.replaceResearchOfType(getTechnologyID("OrbitalConstruction"), getTechnologyID("SupportCap"));
				emp.replaceResearchOfType(getTechnologyID("OrbitalConstruction2"), getTechnologyID("Damage"));
			}
		}
		initialized = true;
	}

	if(time == 0.0 || gameSpeed == 0.0 || gameTime < 0.5)
		return;

	//Check for losing systems
	for(uint i = 0, cnt = playerData.length; i < cnt; ++i) {
		auto@ dat = playerData[i];
		if(dat.homeworld.desc is null)
			@dat.homeworld.desc = getSystem(dat.homeworld.index);

		if(dat.empire is null) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ emp = getEmpire(i);
				Region@ homeReg;
				if(emp.Homeworld !is null)
					@homeReg = emp.Homeworld.region;
				else if(emp.HomeObj !is null)
					@homeReg = emp.HomeObj.region;

				if(homeReg !is null) {
					if(dat.homeworld.desc.object is homeReg)
						@dat.empire = emp;
				}
			}
		}

		for(uint j = 0, jcnt = dat.edges.length; j < jcnt; ++j) {
			auto@ sys = dat.edges[j];
			if(sys.desc is null)
				@sys.desc = getSystem(sys.index);

			//Remove lost defenses
			for(uint n = 0, ncnt = sys.defenses.length; n < ncnt; ++n) {
				if(sys.defenses[n] is null || !sys.defenses[n].valid) {
					sys.defenses.removeAt(n);
					--n; --ncnt;
				}
			}

			//Replace invaders with pickups
			vec3d lastInvader;
			for(uint n = 0, ncnt = sys.invaders.length; n < ncnt; ++n) {
				auto@ obj = sys.invaders[n];
				if(obj !is null && obj.valid)
					continue;

				if(obj !is null)
					lastInvader = obj.position;
				sys.invaders.removeAt(n);
				--n; --ncnt;
			}

			if(sys.isFighting && sys.invaders.length == 0) {
				sys.isFighting = false;

				const ArtifactType@ type;
				uint possibs = 0;
				for(uint n = 0, ncnt = getArtifactTypeCount(); n < ncnt; ++n) {
					auto@ artif = getArtifactType(n);
					if(!artif.hasTag("Invasion"))
						continue;
					possibs += 1;
					if(randomd() < 1.0 / double(possibs))
						@type = artif;
				}

				if(type !is null) {
					vec3d pos = lastInvader;
					if(pos.zero) {
						pos = sys.desc.object.position;
						vec2d off = random2d(200.0, sys.desc.object.radius * 0.8);
						pos.x += off.x;
						pos.y += randomd(-20.0, 20.0);
						pos.z += off.y;
					}

					if(symbolicStrength >= 20.0)
						giveAchievement(dat.empire, "ACH_INVASION_20");
					if(symbolicStrength >= 25.0 && config::INVASION_DIFFICULTY >= HARD_DIFF_MIN)
						giveAchievement(dat.empire, "ACH_INVASION_40");

					Artifact@ artif = createArtifact(pos, type);
					@artif.owner = dat.empire;
				}
			}

			//Remove lost edges
			if(sys.defenses.length == 0) {
				sys.desc.object.dealStarDamage(1000000000000000000);
				sys.desc.object.addSystemDPS(1000000000000000000);

				increaseInvasionStrength(2.0);

				for(uint i = 0, cnt = sys.desc.object.planetCount; i < cnt; ++i)
					sys.desc.object.planets[i].destroyQuiet();

				dat.edges.removeAt(j);
				--j; --jcnt;
			}
		}

		//Remove lost systems
		if(dat.edges.length == 0) {
			for(uint j = 0, jcnt = dat.inner.length; j < jcnt; ++j) {
				auto@ sys = dat.inner[j];
				if(sys.desc is null)
					@sys.desc = getSystem(sys.index);

				sys.desc.object.dealStarDamage(1000000000000000000);
				sys.desc.object.addSystemDPS(1000000000000000000);

				for(uint i = 0, cnt = sys.desc.object.planetCount; i < cnt; ++i)
					sys.desc.object.planets[i].destroyQuiet();
			}
			auto@ sys = dat.homeworld;
			if(sys !is null) {
				if(sys.desc is null)
					@sys.desc = getSystem(sys.index);

				sys.desc.object.dealStarDamage(1000000000000000000);
				sys.desc.object.addSystemDPS(1000000000000000000);

				for(uint i = 0, cnt = sys.desc.object.planetCount; i < cnt; ++i)
					sys.desc.object.planets[i].destroyQuiet();
			}
			dat.inner.length = 0;
		}

		//Remove lost players
		if(dat.inner.length == 0) {
			playerData.removeAt(i);
			--i; --cnt;
		}
	}

	//Increase remnant strength
	waveTimer -= time;
	if(waveTimer <= 0.0) {
		waveTimer += 3.0 * 60.0;

		//Update defense station strength
		double stHP = -1.0 + 0.5 * pow(1.3, symbolicStrength / DOUBLE_WAVES);
		double stDPS = min(-1.0+ 0.2 * pow(1.4, symbolicStrength / DOUBLE_WAVES), 0.0);

		for(uint i = 0, cnt = playerData.length; i < cnt; ++i) {
			auto@ dat = playerData[i];
			for(uint n = 0, ncnt = dat.edges.length; n < ncnt; ++n) {
				auto@ edge = dat.edges[n];
				for(uint j = 0, jcnt = edge.defenses.length; j < jcnt; ++j) {
					edge.defenses[j].modHPFactor(stHP - dat.stationHealth);
					edge.defenses[j].modFleetEffectiveness(stDPS - dat.stationEff);
				}
			}

			dat.stationHealth = stHP;
			dat.stationEff = stDPS;
		}

		//Spawn enemies
		double targetStrength;

		int waveDown = int(floor(symbolicStrength));
		int waveUp = int(ceil(symbolicStrength));

		if(uint(waveUp) >= WAVE_STRENGTHS.length) {
			double finalWave = WAVE_STRENGTHS.length;
			double baseStrength = BASE_STRENGTH;
			if(WAVE_STRENGTHS.length != 0)
				baseStrength = WAVE_STRENGTHS[WAVE_STRENGTHS.length-1];

			targetStrength = baseStrength * pow(2.0, double(symbolicStrength - finalWave) / DOUBLE_WAVES);
		}
		else {
			double downStr = WAVE_STRENGTHS[waveDown];
			double upStr = WAVE_STRENGTHS[waveUp];

			targetStrength = downStr;
			if(upStr != downStr && waveDown != waveUp)
				targetStrength += (upStr - downStr) * (symbolicStrength - double(waveDown)) / double(waveUp - waveDown);
		}

		if(config::INVASION_DIFFICULTY > 0)
			targetStrength *= config::INVASION_DIFFICULTY;

		symbolicStrength += 1.0;

		uint fleetCount = 1;
		uint maxFleets = ceil(symbolicStrength / 5.0);
		while(fleetCount < maxFleets && randomd() < 0.33)
			fleetCount += 1;

		double fleetStrength = sqr(sqrt(targetStrength) / double(fleetCount));
		array<RemnantComposition@> fleets;

		for(uint f = 0, fcnt = fleetCount; f < fcnt; ++f) {
			auto@ comp = composeRemnantFleet(fleetStrength, 0.2, emp=Invaders);
			if(comp is null)
				continue;
			fleets.insertLast(comp);
		}

		for(uint i = 0, cnt = playerData.length; i < cnt; ++i) {
			auto@ dat = playerData[i];
			if(dat.edges.length == 0)
				continue;

			EndSystem@ sys;
			uint checkCount = 0;
			for(uint i = 0, cnt = dat.edges.length; i < cnt; ++i) {
				auto@ edge = dat.edges[i];
				if(cnt != 1 && edge.index == dat.previousWave)
					continue;

				checkCount += 1;
				if(randomd() < 1.0 / double(checkCount))
					@sys = edge;
			}

			sys.isFighting = true;
			for(uint f = 0, fcnt = fleets.length; f < fcnt; ++f) {
				vec3d pos = (sys.desc.position - dat.homeworld.desc.position).normalized();
				pos = quaterniond_fromAxisAngle(vec3d_up(), randomd(-0.2, 0.2)*pi) * pos;

				vec3d spawnPos = pos * sys.desc.object.radius * 0.95;
				spawnPos += sys.desc.position;

				Ship@ invader = spawnRemnantFleet(spawnPos, fleets[f], emp=Invaders, alwaysVisible=true);
				sys.invaders.insertLast(invader);

				if(f == 0 && dat.empire !is null && dat.empire.player !is null)
					showPing(dat.empire.player, Invaders, spawnPos, 2);
			}

			dat.previousWave = sys.index;
		}
	}
}

bool sendPeriodic(Message& msg) {
	if(!hasInvasionMap())
		return false;
	msg << symbolicStrength;
	msg << waveTimer;
	return true;
}

#section shadow
from game_start import galaxies;

double symbolicStrength = 0.0;
double waveTimer = 0.0;

void recvPeriodic(Message& msg) {
	msg >> symbolicStrength;
	msg >> waveTimer;
}

bool hasInvasionMap() {
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
		if(cast<InvasionMap>(galaxies[i]) !is null)
			return true;
	}
	return false;
}

double getInvasionInterval() {
	return 3.0 * 60.0;
}

double getInvasionTimer() {
	return waveTimer;
}

double getInvasionStrength() {
	return symbolicStrength;
}

bool initialized = false;
void tick(double time) {
	if(!hasInvasionMap())
		return;

	if(!initialized && playerEmpire.valid) {
		guiDialogueAction("Invasion.InvasionMap::SetupGUI");
		initialized = true;
	}
}

#section gui
import dialogue;
import elements.BaseGuiElement;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiProgressbar;
import util.formatting;
import tabs.tabbar;

class InvasionUI : BaseGuiElement {
	GuiText@ waveLabel;
	GuiProgressbar@ bar;
	GuiText@ strengthLabel;
	GuiText@ strength;

	InvasionUI() {
		super(null, Alignment(Left+0.5f-200, Top+TAB_HEIGHT+GLOBAL_BAR_HEIGHT+1, Width=400, Height=40));

		@waveLabel = GuiText(this, Alignment(Left+8, Top+4, Left+90, Bottom-4), locale::NEXT_WAVE);
		waveLabel.color = Color(0xaaaaaaff);

		@bar = GuiProgressbar(this, Alignment(Left+90, Top+8, Left+250, Bottom-8));
		bar.frontColor = Color(0xff8080ff);
		bar.font = FT_Small;
		bar.strokeColor = colors::Black;

		@strengthLabel = GuiText(this, Alignment(Left+270, Top+4, Left+330, Bottom-4), locale::NEXT_STRENGTH);
		strengthLabel.color = Color(0xaaaaaaff);

		@strength = GuiText(this, Alignment(Left+330, Top+6, Left+392, Bottom-4));
		strength.horizAlign = 0.5;
		strength.color = Color(0xff4040ff);
		strength.font = FT_Bold;

		updateAbsolutePosition();
	}

	void tick(double time) {
		visible = ActiveTab.category == TC_Galaxy;

		double timer = getInvasionTimer();
		double interval = getInvasionInterval();
		double str = getInvasionStrength();

		strength.text = standardize(str, true);
		bar.text = formatTime(timer);
		bar.progress = 1.f - (timer / interval);
	}

	void draw() {
		skin.draw(SS_PlainOverlay, SF_Normal, AbsolutePosition.padded(0,-2,0,0));
		BaseGuiElement::draw();
	}
};

class SetupGUI : DialogueAction {
	void call() {
		@ui = InvasionUI();
	}
}

InvasionUI@ ui;
void tick(double time) {
	if(ui !is null)
		ui.tick(time);
}

void preReload(Message& msg) {
	msg.writeBit(ui !is null);
	if(ui !is null)
		ui.remove();
}

void postReload(Message& msg) {
	if(msg.readBit())
		@ui = InvasionUI();
}
