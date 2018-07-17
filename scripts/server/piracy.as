from empire import Pirates;
import saving;
import object_creation;
import statuses;
import settings.map_lib;
import civilians;
from game_start import getClosestSystem, getRandomSystem, systemCount, getSystem;
from regions.regions import extentMin, extentMax;
from statuses import StatusHook;

const double PIRATE_GAMETIME = 30.0 * 60.0;
const double HOARD_TIME = 30.0;
const double SYSTEM_MAX_TIME = 80.0;
const int HOARD_MONEY = 500;
const int MAX_CARRYING = 2000;

const double NORMAL_ACCEL = 3.0;
const double CHASE_ACCEL = 10.0;

enum PirateState {
	RESTING,
	TARGETING,
	PILLAGING,
	RETURNING
};

class PirateData : Savable {
	array<Civilian@> hoards;
	PirateState state = RESTING;
	double timer = 0.0;
	double checkTimer = 5.0;
	int totalCollected = 0;
	int currentStored = 0;
	double accel = 1.0;
	Civilian@ returningTo;
	Civilian@ chasing;
	int chasingAmount = 0;

	void save(SaveFile& file) {
		uint st = uint(state);
		file << st;
		file << timer << checkTimer;
		file << totalCollected << currentStored;
		file << accel;
		file << returningTo;
		file << chasing << chasingAmount;

		uint cnt = hoards.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << hoards[i];
	}

	void load(SaveFile& file) {
		uint st = 0;
		file >> st;
		state = PirateState(st);

		file >> timer >> checkTimer;
		file >> totalCollected >> currentStored;
		file >> accel;
		file >> returningTo;
		file >> chasing >> chasingAmount;

		uint cnt = 0;
		file >> cnt;
		hoards.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@hoards[i] = cast<Civilian>(file.readObject());
	}
};

class PirateStatus : StatusHook {
	void onCreate(Object& obj, Status@ status, any@ data) override {
		PirateData dat;
		data.store(@dat);

		obj.setHoldPosition(true);
	}

	void onObjectDestroy(Object& obj, Status@ status, any@ data) override {
		PirateData@ dat;
		data.retrieve(@dat);

		Ship@ ship = cast<Ship>(obj);
		auto@ credit = ship.getKillCredit();
		if(credit !is null)
			credit.addBonusBudget(dat.currentStored + dat.totalCollected / 2);

		spawnPirateShip();
	}

	bool onTick(Object& obj, Status@ status, any@ data, double time) override {
		Ship@ ship = cast<Ship>(obj);
		PirateData@ dat;
		data.retrieve(@dat);

		double thrustPct = ship.blueprint.getEfficiencySum(SV_Thrust) / ship.blueprint.design.total(SV_Thrust);
		obj.maxAcceleration = dat.accel * thrustPct;

		if(obj.orderCount != 0) {
			if(dat.state == PILLAGING)
				dat.timer -= time * 0.5 * sqr(ship.blueprint.design.totalHP / ship.blueprint.currentHP);
			return true;
		}

		switch(dat.state) {
			case RESTING: {
				if(dat.timer <= 0.0) {
					//Find a new system to pillage
					const SystemDesc@ targetSys = findJuicySystem(status.originEmpire);
					if(targetSys is null) {
						dat.timer = HOARD_TIME;
					}
					else {
						obj.addGotoOrder(targetSys.object);
						dat.accel = NORMAL_ACCEL;
						dat.state = TARGETING;
					}
				}
				else {
					dat.timer -= time;
					dat.accel = NORMAL_ACCEL;
				}
			} break;
			case TARGETING: {
				dat.state = PILLAGING;
				dat.timer = SYSTEM_MAX_TIME;
				dat.accel = NORMAL_ACCEL;
				dat.checkTimer = 0;
			} break;
			case RETURNING: {
				dat.state = RESTING;
				dat.timer = HOARD_TIME;
				dat.accel = NORMAL_ACCEL;

				if(dat.returningTo !is null) {
					dat.returningTo.modCargoWorth(dat.currentStored * 2);
					dat.currentStored = 0;
					@dat.returningTo = null;
				}

				if(!ship.inCombat) {
					ship.Supply = ship.MaxSupply;
					ship.repairShip(10000000);
				}
			} break;
			case PILLAGING: {
				if(dat.chasing !is null) {
					if(!dat.chasing.valid) {
						dat.totalCollected += dat.chasingAmount;
						dat.currentStored += dat.chasingAmount;
					}
					@dat.chasing = null;
					dat.chasingAmount = 0;
				}
				if(dat.timer <= 0.0 || dat.currentStored > MAX_CARRYING) {
					//Prune old hoards
					@dat.returningTo = null;
					for(int i = dat.hoards.length - 1; i >= 0; --i) {
						if(!dat.hoards[i].valid)
							dat.hoards.removeAt(i);
					}

					//Check if we should create a new hoard
					double newChance = pow(0.5, double(dat.hoards.length) / (double(dat.totalCollected) / double(HOARD_MONEY)));
					if(dat.hoards.length == 0 || randomd() < newChance) {
						vec3d pos = vec3d(randomd(extentMin.x, extentMax.x), 0, randomd(extentMin.z, extentMax.z));
						pos.y = getClosestSystem(pos).position.y;

						Civilian@ civ = createCivilian(pos, Pirates, CiT_Station, radius=25.0);
						civ.name = locale::PIRATE_HOARD;
						civ.named = true;
						civ.setCargoType(CT_Goods);
						dat.hoards.insertLast(civ);
						@dat.returningTo = civ;
					}

					//Find a hoard to return to
					if(dat.returningTo is null) {
						double dist = INFINITY;
						for(uint i = 0, cnt = dat.hoards.length; i < cnt; ++i) {
							double d = dat.hoards[i].position.distanceTo(obj.position) * randomd(0.5, 1.5);
							if(d < dist) {
								dist = d;
								@dat.returningTo = dat.hoards[i];
							}
						}
					}
					obj.addGotoOrder(dat.returningTo);

					dat.state = RETURNING;
					dat.accel = NORMAL_ACCEL;
				}
				else {
					//Find civilian ships to kill
					if(dat.checkTimer <= 0.0) {
						vec3d center = obj.position;
						Region@ region = obj.region;
						vec3d bound(2000.0);
						if(region !is null) {
							center = region.position;
							bound = region.radius;
						}

						array<Object@>@ objs = findInBox(center - bound, center + bound, Pirates.hostileMask);
						Civilian@ found;
						for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
							Civilian@ civ = cast<Civilian>(objs[i]);
							if(civ is null)
								continue;
							Empire@ owner = civ.owner;
							if(owner is null || !Pirates.isHostile(owner))
								continue;

							@found = civ;
							break;
						}

						if(found !is null) {
							dat.accel = CHASE_ACCEL;
							obj.addAttackOrder(found);
							@dat.chasing = found;
							dat.chasingAmount = found.getCargoWorth();
							dat.checkTimer = 10.0;
						}
						else {
							dat.accel = NORMAL_ACCEL;
							dat.checkTimer = randomd(2.0, 5.0);
						}
					}
					else {
						dat.checkTimer -= time;
						dat.accel = NORMAL_ACCEL;
					}

					dat.timer -= time * sqr(ship.blueprint.design.totalHP / ship.blueprint.currentHP);
				}
			} break;
		}

		return true;
	}

	void save(Status@ status, any@ data, SaveFile& file) override {
		PirateData@ dat;
		data.retrieve(@dat);
		file << dat;
	}

	void load(Status@ status, any@ data, SaveFile& file) override {
		PirateData dat;
		file >> dat;
		data.store(@dat);
	}
};

const SystemDesc@ findJuicySystem(Empire@ limitEmpire = null) {
	//Find an occupied system with low defenses
	double totalFreq = 0.0;
	double roll = randomd();
	const SystemDesc@ result;

	for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
		auto@ sys = getSystem(i);
		uint plMask = sys.object.PlanetsMask;
		if(plMask == 0)
			continue;
		if(limitEmpire !is null && plMask & limitEmpire.mask == 0)
			continue;
		double freq = randomd(0.6, 1.0);
		double totStr = 0;
		for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n) {
			Empire@ other = getEmpire(n);
			if(!other.major)
				continue;
			if(limitEmpire !is null && other !is limitEmpire)
				continue;
			if(plMask & other.mask == 0)
				continue;
			freq *= sqr(double(sys.object.getPlanetCount(other)));
			freq /= double(sys.object.getStrength(other) + 1);
		}
		if(sys.object.hasTradeStations())
			freq *= 4.0;

		totalFreq += freq;
		double chance = freq / totalFreq;
		if(roll < chance) {
			@result = sys;
			roll /= chance;
		}
		else {
			roll = (roll - chance) / (1.0 - chance);
		}
	}
	return result;
}

bool shouldSpawn = false;
bool hasLoaded = false;
void init() {
	if(!isLoadedSave)
		shouldSpawn = true;
}

void tick(double time) {
	if(isLoadedSave && !hasLoaded) {
		shouldSpawn = START_VERSION >= SV_0084 && gameTime < PIRATE_GAMETIME;
		hasLoaded = true;
	}
	if(!shouldSpawn)
		return;
	if(gameTime < PIRATE_GAMETIME)
		return;
	spawnPirateShip();
	shouldSpawn = false;
}

bool isHalloween() {
	//I'm sorry I'm sorry I'm sorry I'm sorry
	int64 now = getSystemTime();
	int month = toInt(strftime("%m", now));
	int day = toInt(strftime("%d", now));

	return month == 10 && day >= 29 && day <= 31;
}

void spawnPirateShip(Empire@ limitEmpire = null) {
	if(config::ENABLE_DREAD_PIRATE == 0)
		return;
	const Design@ dsg;
	if(isHalloween())
		@dsg = Pirates.getDesign("The Flying Dutchman");
	else
		@dsg = Pirates.getDesign("Dread Pirate");
	vec3d pos = vec3d(randomd(extentMin.x, extentMax.x), 0, randomd(extentMin.z, extentMax.z));
	pos.y = getClosestSystem(pos).position.y;

	Ship@ ship = createShip(pos, dsg, Pirates, free=true);

	auto@ status = getStatusType("PirateShip");
	if(status !is null)
		ship.addStatus(status.id, originEmpire=limitEmpire);
	else
		error("Error: Could not find 'PirateShip' status for managing pirate vessel.");
}
