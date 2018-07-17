import orbitals;
import object_creation;
import tile_resources;
import void setInstantColonize(bool) from "planets.SurfaceComponent";
from empire import sendChatMessage;

import influence;
from bonus_effects import BonusEffect;
from generic_effects import GenericEffect;
import hooks;

bool CHEATS_ENABLED_THIS_GAME = false;
bool CHEATS_ENABLED = false;
bool getCheatsEnabled() {
	return CHEATS_ENABLED;
}

bool getCheatsEverOn() {
	return CHEATS_ENABLED_THIS_GAME;
}

void setCheatsEnabled(Player& player, bool enabled) {
	if(player != HOST_PLAYER)
		return;
	CHEATS_ENABLED = enabled;
	if(enabled)
		CHEATS_ENABLED_THIS_GAME = true;
	cheatsEnabled(ALL_PLAYERS, enabled);
	if(mpServer) {
		if(enabled)
			sendChatMessage(locale::MP_CHEATS_ENABLED, color=Color(0xaaaaaaff), offset=30);
		else
			sendChatMessage(locale::MP_CHEATS_DISABLED, color=Color(0xaaaaaaff), offset=30);
	}
}

void cheatSeeAll(Player& player, bool enabled) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.visionMask = enabled ? ~0 : player.emp.mask;
}

void cheatColonize(bool enabled) {
	if(!CHEATS_ENABLED)
		return;
	setInstantColonize(enabled);
}

void cheatSpawnFlagship(Object@ spawnAt, const Design@ design, Empire@ owner) {
	if(!CHEATS_ENABLED)
		return;
	if(design.hasTag(ST_IsSupport))
		return;
	createShip(spawnAt, design, owner, free=true);
}

void cheatSpawnFlagship(vec3d spawnAt, const Design@ design, Empire@ owner) {
	if(!CHEATS_ENABLED)
		return;
	if(design.hasTag(ST_IsSupport))
		return;
	Ship@ ship = createShip(spawnAt, design, owner, free=true);
	ship.addMoveOrder(spawnAt);
}

void cheatSpawnSupports(Object@ spawnAt, const Design@ design, uint count) {
	if(!CHEATS_ENABLED)
		return;
	if(!design.hasTag(ST_IsSupport))
		return;
	if(!spawnAt.hasLeaderAI || spawnAt.owner is null || !spawnAt.owner.valid)
		return;
	for(uint i = 0; i < count; ++i)
		createShip(spawnAt, design, spawnAt.owner);
}

void cheatSpawnSupports(vec3d spawnAt, const Design@ design, uint count, Empire@ owner) {
	if(!CHEATS_ENABLED)
		return;
	if(!design.hasTag(ST_IsSupport))
		return;
	for(uint i = 0; i < count; ++i)
		createShip(spawnAt, design, owner);
}

void cheatSpawnOrbital(vec3d spawnAt, uint orbitalType, Empire@ owner) {
	if(!CHEATS_ENABLED)
		return;
	const OrbitalModule@ def = getOrbitalModule(orbitalType);
	if(def is null)
		return;
	createOrbital(spawnAt, def, owner);
}

void cheatInfluence(Player& player, int amount) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.addInfluence(amount);
}

void cheatResearch(Player& player, double amount) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.generatePoints(amount);
}

void cheatMoney(Player& player, int amount) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.addBonusBudget(amount);
}

void cheatEnergy(Player& player, int amount) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.modEnergyStored(amount);
}

void cheatFTL(Player& player, int amount) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	if(player.emp.FTLCapacity < amount)
		player.emp.modFTLCapacity(amount);
	player.emp.modFTLStored(amount);
}

void cheatActivateAI(Player& player) {
	if(!CHEATS_ENABLED || player.emp is null || !player.emp.valid)
		return;
	player.emp.initBasicAI();
}

void cheatDebugAI(Empire@ emp) {
	if(!CHEATS_ENABLED || emp is null)
		return;
	emp.debugAI();
}

void cheatCommandAI(Empire@ emp, string cmd) {
	if(!CHEATS_ENABLED || emp is null)
		return;
	emp.commandAI(cmd);
}

void cheatTrigger(Player& player, Object@ obj, Empire@ emp, string hook) {
	Empire@ plEmp = player.emp;
	if(!CHEATS_ENABLED || plEmp is null || !plEmp.valid)
		return;
	BonusEffect@ trig = cast<BonusEffect>(parseHook(hook, "bonus_effects::", required=false));
	if(trig !is null) {
		trig.activate(obj, emp);
		return;
	}
	GenericEffect@ eff = cast<GenericEffect>(parseHook(hook, "planet_effects::"));
	if(eff !is null) {
		eff.enable(obj, null);
		return;
	}
}

void cheatChangeOwner(Object@ obj, Empire@ newOwner) {
	if(!CHEATS_ENABLED || obj is null || newOwner is null)
		return;
	if(obj.isPlanet) {
		obj.takeoverPlanet(newOwner);
	}
	else if(obj.isShip) {
		if(obj.hasLeaderAI) {
			uint cnt = obj.supportCount;
			for(uint i = 0; i < cnt; ++i)
				@obj.supportShip[i].owner = newOwner;
		}

		@obj.owner = newOwner;
	}
	else {
		@obj.owner = newOwner;
	}
}

void cheatAlliance(Empire& from, Empire& to) {
	if(!CHEATS_ENABLED)
		return;
	if(from is to)
		return;
	if(!from.valid || !to.valid)
		return;
}

void cheatDestroy(Object@ obj) {
	if(!CHEATS_ENABLED || obj is null)
		return;
	obj.destroy();
}

void cheatLabor(Object@ obj, double amount) {
	if(!CHEATS_ENABLED || obj is null)
		return;
	obj.modLaborIncome(amount);
}

void syncInitial(Message& msg) {
	msg << CHEATS_ENABLED;
	msg << CHEATS_ENABLED_THIS_GAME;
}

void save(SaveFile& msg) {
	msg << CHEATS_ENABLED;
	msg << CHEATS_ENABLED_THIS_GAME;
}

void load(SaveFile& msg) {
	msg >> CHEATS_ENABLED;
	if(msg >= SV_0025)
		msg >> CHEATS_ENABLED_THIS_GAME;
	else
		CHEATS_ENABLED_THIS_GAME = CHEATS_ENABLED;
}
