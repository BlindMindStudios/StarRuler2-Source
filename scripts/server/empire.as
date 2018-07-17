import resources;
import util.design_export;
import influence;
from influence import InfluenceStore;
import saving;
import ftl;
import settings.game_settings;
import abilities;
from empire_ai.EmpireAI import EmpireAI;
import void initCreepCampTypes() from "camps";
import util.convar;

import void EGCoordinationTick(Empire& emp, double time) from "gameplay.extragalactic";

ConVar ai_full_speed("ai_full_speed", 0);

Empire@ Creeps;
Empire@ Pirates;
uint majorEmpireCount = 0;

array<ScriptThread@> threads;
DesignSet creepDesigns;
DesignSet pirateDesigns;

uint getMajorEmpireCount() {
	return majorEmpireCount;
}

void init(Empire& emp) {
	emp.initResearch();
	emp.initAttributes();
	emp.modFTLCapacity(+250);
	emp.modFTLIncome(+1);
	emp.modTotalBudget(+550, MoT_Planet_Income);

	//Handle handicap
	if(emp.handicap < 0) {
		emp.modTotalBudget(-emp.handicap * 40.0, MoT_Handicap);
		emp.handicap = 0;
	}
	else if(emp.handicap > 0) {
		int take = min(10, emp.handicap);
		emp.modMaintenance(take * 40.0, MoT_Handicap);
		emp.handicap -= take;
	}

	//Add abilities
	for(uint i = 0, cnt = getAbilityTypeCount(); i < cnt; ++i) {
		auto@ abl = getAbilityType(i);
		if(abl.empireDefault)
			emp.addAbility(abl.id);
	}

	//Initialize traits
	emp.initTraits();

	//Initialize the AI
	if(emp.hasEmpireAI)
		cast<EmpireAI@>(emp.EmpireAI).init(emp);

	EmpireTickData@ tickData = EmpireTickData(emp);
	threads.insertLast(ScriptThread("empire::empireTickThread", @tickData));
}

void sendPeriodic(Empire& emp, Message& msg) {
	msg.writeBit(emp.major);
	if(!emp.major)
		return;

	msg << emp.visionMask << emp.hostileMask;
	msg << emp.GlobalLoyalty.value;
	msg.writeSignedSmall(emp.Victory);
	emp.writeResources(msg);
	if(!emp.writeAbilityDelta(msg))
		msg.write0();
	emp.writeNotifications(msg, true);
	emp.writeResearch(msg);
	emp.writeInfluenceManager(msg);
	emp.writeAttributes(msg);
	emp.writeObjects(msg);
	emp.writeSyncedStates(msg);
	emp.writeEvents(msg);
	emp.writeDelta(msg);
	emp.writeAttitudes(msg, false);
}

void syncInitial(Empire& emp, Message& msg) {
	emp.writeNotifications(msg, false);
	emp.writeInfluenceManager(msg, true);
	emp.writeAttributes(msg, true);
	emp.writeObjects(msg, true);
	emp.writeResearch(msg, true);
	emp.writeSyncedStates(msg);
	emp.writeAbilities(msg);
	emp.writeTraits(msg);
	emp.writeAttitudes(msg, true);
	emp.writeEvents(msg);

	msg << emp.major;
	msg << emp.backgroundDef;
	msg << emp.portraitDef;
	msg << emp.flagDef;
	msg << emp.flagID;
	msg << emp.RaceName;
	msg << emp.ColonizerModel;
	msg << emp.ColonizerMaterial;
}

void initEmpireDesigns() {
	//Read default blueprints
	creepDesigns.readDirectory("data/designs/creeps");
	creepDesigns.log = true;
	pirateDesigns.readDirectory("data/designs/pirates");
	pirateDesigns.log = true;

	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		Empire@ emp = getEmpire(i);

		if(emp is Creeps) {
			//Give the creeps their blueprints
			creepDesigns.createFor(emp);
		}
		else if(emp is Pirates) {
			//Give the pirates their blueprints
			pirateDesigns.createFor(emp);
		}
	}
}

void init() {
	if(isLoadedSave)
		return;

	//Initialize empires
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp = getEmpire(i);

		//Initialize the AI settings
		if(i < gameSettings.empires.length) {
			if(emp.hasEmpireAI)
				cast<EmpireAI@>(emp.EmpireAI).init(emp, gameSettings.empires[i]);
		}

		init(emp);
	}

	//Post-initialize traits
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
		getEmpire(i).postInitTraits();
}

void save(SaveFile& msg) {
	msg << Creeps;
	msg << Pirates;
	msg << majorEmpireCount;

	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp = getEmpire(i);
		EmpireTickData@ dat;
		threads[i].getObject(@dat);
		msg << dat.lastTick;

		msg << cast<Savable>(emp.ResearchGrid);
		msg << cast<Savable>(emp.ResourceManager);
		msg << cast<Savable>(emp.EnergyManager);
		msg << cast<Savable>(emp.ObjectManager);
		msg << cast<Savable>(emp.InfluenceManager);
		msg << cast<Savable>(emp.FleetManager);
		msg << cast<Savable>(emp.Notifications);
		msg << cast<Savable>(emp.Attributes);
		msg << cast<Savable>(emp.Traits);
		msg << cast<Savable>(emp.RandomEvents);
		emp.NS.save(msg);
		msg << emp.Homeworld;
		msg << emp.HomeSystem;
		msg << emp.HomeObj;
		msg << emp.PeaceMask.value;
		msg << emp.ForcedPeaceMask.value;
		msg << emp.AllyMask.value;
		msg << emp.TotalMilitary;
		msg << emp.TotalPlanets;
		msg << emp.VotesWonCounter;
		msg << emp.major;
		msg << emp.points;
		msg << emp.prevPoints;
		msg << emp.team;
		msg << emp.DiplomacyPoints;
		msg << emp.MilitaryStrength;
		msg << emp.PoliticalStrength;
		msg << emp.EmpireStrength;
		msg << emp.Victory;
		msg << emp.cheatLevel;

		msg << emp.TotalSupportsBuilt.value;
		msg << emp.TotalSupportsActive.value;
		msg << emp.TotalFlagshipsBuilt.value;
		msg << emp.TotalFlagshipsActive.value;
		msg << emp.GlobalLoyalty.value;
		msg << emp.GlobalCharge;
		msg << emp.GlobalTrade;
		msg << emp.ContactMask.value;
		msg << emp.TradeMask.value;

		msg << emp.ModHP.value;
		msg << emp.ModArmor.value;
		msg << emp.ModShield.value;
		msg << emp.ModSpeed.value;

		msg << emp.CivilianTradeShips.value;
		msg << emp.SubjugatedBy;
		msg << emp.PathId.value;
		msg << emp.ColonizerName;
		msg << emp.ColonizerModel;
		msg << emp.ColonizerMaterial;
		msg << emp.RaceName;
		msg << emp.mutualDefenseMask;
		
		msg << cast<Savable>(emp.EmpireAI);
	}
}

void load(SaveFile& msg) {
	msg >> Creeps;
	if(msg >= SV_0084)
		msg >> Pirates;
	msg >> majorEmpireCount;

	initCreepCampTypes();

	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp = getEmpire(i);
		EmpireTickData dat(emp);
		msg >> dat.lastTick;

		msg >> cast<Savable>(emp.ResearchGrid);
		msg >> cast<Savable>(emp.ResourceManager);
		msg >> cast<Savable>(emp.EnergyManager);
		msg >> cast<Savable>(emp.ObjectManager);
		if(msg < SV_0119)
			msg >> cast<Savable>(emp.EmpireAI);
		msg >> cast<Savable>(emp.InfluenceManager);
		msg >> cast<Savable>(emp.FleetManager);
		msg >> cast<Savable>(emp.Notifications);

		emp.initAttributes();
		msg >> cast<Savable>(emp.Attributes);
		emp.syncAttributes();

		if(msg >= SV_0012)
			msg >> cast<Savable>(emp.Traits);
		if(msg >= SV_0125)
			msg >> cast<Savable>(emp.RandomEvents);

		emp.NS.load(msg);

		Object@ hw;
		msg >> hw;
		@emp.Homeworld = cast<Planet>(hw);
		if(msg >= SV_0153) {
			msg >> emp.HomeSystem;
		}
		else {
			if(emp.Homeworld !is null)
				@emp.HomeSystem = emp.Homeworld.region;
		}
		if(msg >= SV_0113) {
			msg >> hw;
			@emp.HomeObj = hw;
		}

		msg >> emp.PeaceMask.value;
		msg >> emp.ForcedPeaceMask.value;
		msg >> emp.AllyMask.value;
		msg >> emp.TotalMilitary;
		msg >> emp.TotalPlanets;
		msg >> emp.VotesWonCounter;
		msg >> emp.major;
		msg >> emp.points;
		if(msg >= SV_0069)
			msg >> emp.prevPoints;
		if(msg >= SV_0064)
			msg >> emp.team;
		msg >> emp.DiplomacyPoints;
		msg >> emp.MilitaryStrength;
		msg >> emp.PoliticalStrength;
		msg >> emp.EmpireStrength;
		if(msg >= SV_0042)
			msg >> emp.Victory;
		if(msg >= SV_0155)
			msg >> emp.cheatLevel;

		msg >> emp.TotalSupportsBuilt.value;
		msg >> emp.TotalSupportsActive.value;
		msg >> emp.TotalFlagshipsBuilt.value;
		msg >> emp.TotalFlagshipsActive.value;
		msg >> emp.GlobalLoyalty.value;
		msg >> emp.GlobalCharge;
		if(msg >= SV_0026)
			msg >> emp.GlobalTrade;
		if(msg >= SV_0053)
			msg >> emp.ContactMask.value;
		else
			emp.ContactMask.value = int(~0);
		if(msg >= SV_0057)
			msg >> emp.TradeMask.value;
		else
			emp.TradeMask.value = emp.mask;
	
		msg >> emp.ModHP.value;
		msg >> emp.ModArmor.value;
		msg >> emp.ModShield.value;
		msg >> emp.ModSpeed.value;

		if(msg >= SV_0048)
			msg >> emp.CivilianTradeShips.value;
		if(msg >= SV_0061)
			msg >> emp.SubjugatedBy;
		if(msg >= SV_0067)
			msg >> emp.PathId.value;
		if(msg >= SV_0109) {
			msg >> emp.ColonizerName;
			if(msg >= SV_0118) {
				msg >> emp.ColonizerModel;
				msg >> emp.ColonizerMaterial;
			}
			if(msg >= SV_0125)
				msg >> emp.RaceName;
			if(msg >= SV_0149)
				msg >> emp.mutualDefenseMask;
		}
		
		if(msg >= SV_0119)
			msg >> cast<Savable>(emp.EmpireAI);

		@emp.background = getMaterial(emp.backgroundDef);
		@emp.flag = getMaterial(emp.flagDef);
		@emp.portrait = getMaterial(emp.portraitDef);

		if(emp.flag is material::error)
			@emp.flag = getMaterial("emp_flag_flag1");
		if(emp.portrait is material::error)
			@emp.portrait = getMaterial("emp_portrait_feyh");
		if(emp.background is material::error)
			@emp.background = getMaterial("emp_bg_blue");

		if(msg < SV_0085)
			emp.initResearch();
		if(msg < SV_0134)
			emp.ResearchUnlockSpeed = 1.0;

		threads.insertLast(ScriptThread("empire::empireTickThread", @dat));
	}
}

void tick(double time) {
	//Restart any disabled threads (can happen if there was an error)
	for(uint i = 0, cnt = threads.length; i < cnt; ++i) {
		if(!threads[i].running && threads[i].wasError)
			threads[i].start("empire::empireTickThread");
	}
	
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i)
		getEmpire(i).cacheVision();
}

void deinit() {
	uint cnt = threads.length;
	for(uint i = 0; i < cnt; ++i)
		threads[i].stop();
	for(uint i = 0; i < cnt; ++i)
		while(threads[i].running)
			sleep(0);
	threads.length = 0;
}

void playAsEmpire(Player& pl, Empire@ emp) {
	if(emp.player !is null || (!emp.valid && emp !is spectatorEmpire)) {
		info("Player attempted to play as disallowed empire.");
		return;
	}
	if(emp !is spectatorEmpire) {
		pl.linkEmpire(emp);
		string msg = format("[color=#aaa]"+locale::MP_PLAY_EVENT+"[/color]",
			format("[b][color=$1]$2[/color][/b]", toString(emp.color), bbescape(pl.name)),
			format("[b][color=$1]$2[/color][/b]", toString(emp.color), bbescape(emp.name)));
		sendChatMessage(msg, offset=30);
	}
	else {
		string msg = format("[color=#aaa]"+locale::MP_SPECTATING_EVENT+"[/color]",
			format("[b]$1[/b]", bbescape(pl.name)));
		sendChatMessage(msg, offset=30);
		pl.linkEmpire(spectatorEmpire);
	}
	allowPlayEmpire(pl, emp);
	if(pl == CURRENT_PLAYER)
		@playerEmpire = emp;
}

void markDesignObsolete(Player& pl, const Design@ dsg, bool value) {
	if(pl.controls(dsg.owner))
		dsg.setObsolete(value);
}

class EmpireTickData {
	double lastTick = gameTime;
	double aiTickTimer = -1.0;
	uint nextStep = 0;
	Empire@ empire;
	
	double[] tickMoments(5, gameTime);
	
	EmpireTickData(Empire& Emp) {
		@empire = @Emp;
		//Attempt to distribute empire ticks over time
		nextStep = empire.id;
		lastTick += double(empire.id % 4) * 0.25 / 4.0;
		aiTickTimer -= double(empire.id % 4) * 0.25 / 4.0;
	}
};

double empireTickThread(double time, ScriptThread& thread) {
	if(!game_running)
		return 0.05;

	EmpireTickData@ data;
	thread.getObject(@data);
	Empire@ emp = data.empire;
	
	double curTime = gameTime;
	double tick = curTime - data.lastTick;
	double speed = gameSpeed;
	
	if(speed > 0.0) {
		if(ai_full_speed.value == 1.0)
			speed = 1.0;
		data.aiTickTimer += tick / speed;
		if(data.aiTickTimer > 0.25) {
			emp.aiTick(data.aiTickTimer);
			data.aiTickTimer = randomd(-0.02,0.02);
		}
	}
	
	if(tick >= 0.05) {
		data.lastTick = curTime;
		
		switch(data.nextStep++ % 5) {
			case 0: {
				double t = curTime - data.tickMoments[0];
				if(t > 0.0) {
					emp.resourceTick(t);
					EGCoordinationTick(emp, t);
				}
				data.tickMoments[0] = curTime;
				} break;
			case 1: {
				double t = curTime - data.tickMoments[1];
				if(t > 0.0)
					emp.planetTick(t);
				data.tickMoments[1] = curTime;
				} break;
			case 2: {
				double t = curTime - data.tickMoments[2];
				if(t > 0.0)
					emp.influenceTick(t);
				data.tickMoments[2] = curTime;
				} break;
			case 3: {
				double t = curTime - data.tickMoments[3];
				if(t > 0.0) {
					emp.researchTick(t);
					emp.powerTick(t);
				}
				data.tickMoments[3] = curTime;
				} break;
			case 4: {
				double t = curTime - data.tickMoments[4];
				if(t > 0.0) {
					emp.attributesTick(t);
					emp.traitsTick(t);
					emp.eventsTick(t);
				}
				data.tickMoments[4] = curTime;
				} break;
		}
		
		return 0.05;
	}
	else {
		return 0.05 - tick;
	}
}

bool sendPeriodic(Message& msg) {
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i)
		sendPeriodic(getEmpire(i), msg);
	return true;
}

void syncInitial(Message& msg) {
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i)
		syncInitial(getEmpire(i), msg);
}

void sendChatMessage(const string& text, const string& user = "*", const Color& color = colors::White, int offset = 100) {
	string msg = format("[b][color=$1]$2[/color][/b][offset=$4]$3[/offset]",
		toString(color), bbescape(user), text, toString(offset));
	recvMPChat(ALL_PLAYERS, msg);
}

void chatMessage(Player& pl, string text, uint empMask = 0xffffffff, string spec = "") {
	Color color;
	if(pl.emp !is null)
		color = pl.emp.color;
	string txt = bbescape(text);
	if(spec.length != 0)
		txt = "[color=#aaa]("+bbescape(spec)+")[/color] "+txt;
	string msg = format("[b][color=$1]$2[/color][/b][offset=100]$3[/offset]",
		toString(color), bbescape(pl.name), txt);
	if(empMask == 0xffffffff) {
		recvMPChat(ALL_PLAYERS, msg);
	}
	else {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(empMask & other.mask != 0 && other.player !is null)
				recvMPChat(other.player, msg);
		}
	}
}
