#include "include/map.as"

#section server
import saving;
import map_loader;
import util.design_designer;
from empire import Creeps;
from game_start import generateNewSystem, SystemGenerateHook;
import object_creation;
import ship_groups;
import map_systems;
import statuses;
from remnant_designs import spawnRemnantFleet, loadRemnantDesigns;

class Room {
	vec3d position;
	SystemData@ core;
	uint circle = 0;
	double angle = 0;
	array<SystemData@> systems;
	array<uint> circles;
	array<Room@> corrids;
};
#section all

enum MapSetting {
	M_SysCount,
	M_SystemSpacing,
	M_Flatten,
};

const uint INITIAL_EXPANSE = 3;
const double REMNANT_FACTOR = 2.0;

class ExpanseMap : Map {
	ExpanseMap() {
		super();

		name = locale::EXPANSE_MAP;
		description = locale::EXPANSE_MAP_DESC;

		sortIndex = -120;
		eatsPlayers = true;

		color = 0x5273ffff;
		icon = "maps/Expanse/expanse.png";
	}

#section client
	void makeSettings() {
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);
		Description(locale::EXPANSE_MAP_TEXT, lines=3);
	}

#section server
	array<Room@> rooms;

	void preGenerate() {
		Map::preGenerate();
		radius *= 3.0;
	}

	void generateRegions() {
		radius /= 3.0;
		Map::generateRegions();
	}

	void placeSystems() {
		//Generate remnant homeworld
		loadMap("maps/Expanse/coreMap.txt").generate(this);

		//Generate base clusters
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		//Calculate amount of 'rooms'
		uint players = estPlayerCount;
		if(players == 0)
			players = 3;

		uint roomCnt = players+1;
		uint corridorLength = 2;
		uint sysPerRoom = 7;
		double roomRadius = spacing * 1.5 * sqrt(double(sysPerRoom)) + spacing;
		double roomHeightVar = flatten ? 0.0 : roomRadius * 0.2;
		double sysHeightVar = flatten ? 0.0 : spacing * 0.25;

		double playerOffset = max(roomRadius / (twopi / double(players)), roomRadius);

		//Generate rooms
		double angle = 0.0;
		double radius = 0.0;
		double angleStep = twopi;
		double anglePct = 0.0;
		double startAngle = randomd(0.0, twopi);

		Room@ circleStart;
		uint circle = 0;
		uint circleCnt = 0;

		for(uint i = 0; i < roomCnt; ++i) {
			Room room;
			room.position = quaterniond_fromAxisAngle(vec3d_up(), angle + startAngle) * vec3d_front(radius);
			if(i != 0)
				room.position.y = randomd(-roomHeightVar, roomHeightVar);
			room.circle = circle;
			room.angle = angle + startAngle;

			rooms.insertLast(room);
			if(i != 0)
				room.corrids.insertLast(rooms[0]);
			++circleCnt;

			//Proceed to next room position
			angle += angleStep;
			if(angle + angleStep > twopi) {
				angle = 0.0;
				radius += playerOffset;
				startAngle = randomd(0.0, twopi);
				angleStep = twopi / max(double(roomCnt - i - 1), 1.0);
				circle += 1;

				circleCnt = 0;
			}
		}

		//Generate systems
		for(uint i = 0; i < roomCnt; ++i) {
			Room@ room = rooms[i];

			//Generate systems
			uint sysCount = sysPerRoom;
			angle = 0.0;
			radius = i == 0 ? 9000 : 0;
			angleStep = twopi;
			if(radius != 0) {
				anglePct = (spacing / (2.0 * pi * radius));
				if(sysCount > 0)
					angleStep = max(anglePct * twopi, twopi / double(sysCount));
			}
			startAngle = randomd(0.0, twopi);
			circle = 0;
			int quality = 0;
			if(i == 0 && roomCnt > estPlayerCount)
				quality = 200;
			for(uint n = 0; n < sysCount; ++n) {
				//Generate system
				vec3d pos = quaterniond_fromAxisAngle(vec3d_up(), angle + startAngle) * vec3d_front(radius);
				if(!flatten)
					pos.y = randomd(-sysHeightVar, sysHeightVar);
				pos += room.position;
				SystemData@ sys = addSystem(pos, quality=quality);
				if(circle == 0 && (i != 0 || roomCnt == estPlayerCount))
					addPossibleHomeworld(sys);
				sys.assignGroup = i;

				room.systems.insertLast(sys);
				room.circles.insertLast(circle);

				//Generate links to previous circle
				if(circle > 0) {
					SystemData@ closest;
					double closestDist = INFINITY;
					SystemData@ second;
					double secondDist = INFINITY;

					for(int j = int(n); j >= 0; --j) {
						if(room.circles[j] < circle-1)
							break;
						if(room.circles[j] > circle-1)
							continue;

						SystemData@ other = room.systems[j];
						double d = other.position.distanceToSQ(sys.position);

						if(d < closestDist) {
							@second = closest;
							secondDist = closestDist;
							closestDist = d;
							@closest = other;
						}
						else if(d < secondDist) {
							@second = other;
							secondDist = d;
						}
					}

					if(closest !is null)
						addLink(sys, closest);
					if(second !is null)
						addLink(sys, second);
				}

				//Proceed to next system position
				angle += angleStep;
				if(angle + angleStep > twopi) {
					angle = 0.0;
					radius += spacing;
					startAngle = randomd(0.0, twopi);

					anglePct = (spacing / (2.0 * pi * radius));
					if(sysCount - n - 1 > 0)
						angleStep = max(anglePct * twopi, twopi / double(sysCount - n - 1));
					circle += 1;
				}
			}

			//Make expanse systems
			if(i != 0) {
				double aStep = min(twopi / double(roomCnt - 1), pi*0.33);
				double minAngle = room.angle - aStep * 0.5;
				double maxAngle = room.angle + aStep * 0.5;
				aStep = (maxAngle - minAngle) / double(INITIAL_EXPANSE);
				for(uint n = 0; n < INITIAL_EXPANSE; ++n) {
					double ang = minAngle + double(n) * aStep + aStep * 0.5;
					double rad = room.position.length + radius;
					vec3d pos = quaterniond_fromAxisAngle(vec3d_up(), ang) * vec3d_front(rad);
					pos.y = room.position.y;
					if(!flatten)
						pos.y += randomd(-spacing*0.5, spacing*0.5);

					auto@ sys = addSystem(pos);
					sys.assignGroup = i;

					ExpanseSystem es;
					es.index = sys.index;
					es.shouldExpand = true;
					es.minAngle = minAngle;
					es.maxAngle = maxAngle;
					es.circle = 0;
					es.radius = rad;
					es.field = i;
					es.position = n;
					es.spacing = spacing;
					es.flatten = flatten;
					trackSystems.insertLast(es);
				}
			}
		}

		//Generate corridors
		for(uint i = 0; i < roomCnt; ++i) {
			Room@ room = rooms[i];

			for(uint n = 0, ncnt = room.corrids.length; n < ncnt; ++n) {
				Room@ other = room.corrids[n];

				//Build corridor between rooms
				vec3d offset = (other.position - room.position);
				double offdist = offset.length;
				double spacStep = spacing / offdist;
				double corStart = roomRadius * 0.5 / offdist;
				double corEnd = 1.0 - corStart;
				uint len = clamp(floor((corEnd - corStart) / spacStep), 1, corridorLength);
				double corStep = (corEnd - corStart) / double(len);
				corStart += corStep * 0.5;

				SystemData@ first, last;
				for(uint x = 0; x < len; ++x) {
					vec3d corPos = room.position + offset * (corStep * x + corStart);
					if(room.circle == other.circle)
						corPos = corPos.normalized(room.position.length - roomRadius * 0.25);

					auto@ sys = addSystem(corPos, quality=200);
					if(last !is null)
						addLink(last, sys);
					@last = sys;
					if(x == 0)
						@first = last;
				}

				//Find systems to link to
				double dist = INFINITY;
				SystemData@ closest;
				for(uint j = 0, jcnt = room.systems.length; j < jcnt; ++j) {
					double d = room.systems[j].position.distanceToSQ(first.position);
					if(d < dist) {
						@closest = room.systems[j];
						dist = d;
					}
				}
				addLink(closest, first);

				dist = INFINITY;
				for(uint j = 0, jcnt = other.systems.length; j < jcnt; ++j) {
					double d = other.systems[j].position.distanceToSQ(last.position);
					if(d < dist) {
						@closest = other.systems[j];
						dist = d;
					}
				}
				addLink(closest, last);
			}
		}
	}

	void createRemnant(SystemDesc@ system, double size, ExpanseSystem@ es = null) {
		int fleetSize = ceil(size / double(es.defenders.length + es.queuedFleets) / 25.0) * 25;

		vec3d pos = system.position;
		vec2d offset = random2d(500, system.radius*0.85);
		pos.x += offset.x;
		pos.z += offset.y;

		auto@ ship = spawnRemnantFleet(pos, fleetSize, 0.4);
		if(es !is null && ship !is null) {
			es.defenders.insertLast(ship);
			if(es.queuedFleets > 0)
				es.queuedFleets--;
		}
	}
	
	void createRemnants(SystemDesc@ system, double size, ExpanseSystem@ es, bool queued = false) {
		es.queuedFleets = max(randomd(pow(size, 0.14), pow(size, 0.24)), 1.0);
		if(queued)
			return;
		
		while(es.queuedFleets > 0)
			createRemnant(system, size, es);
	}

	void setPlanetsLocked(SystemDesc@ system, bool value) {
		auto@ status = getStatusType("BlockedColonization");
		uint plCnt = system.object.planetCount;
		for(uint i = 0, cnt = plCnt; i < cnt; ++i) {
			if(status !is null) {
				if(value)
					system.object.planets[i].addStatus(status.id);
				else
					system.object.planets[i].removeStatusInstanceOfType(status.id);
			}
			else {
				system.object.planets[i].setQuarantined(value);
			}
		}
	}

	ExpanseSystem@ setExpanseSystem(SystemDesc@ sys, double remnantSize) {
		ExpanseSystem es;
		@es.system = sys;
		es.remnantSize = remnantSize;
		es.origin = origin;

		createRemnants(sys, remnantSize, es);
		setPlanetsLocked(sys, true);

		trackSystems.insertLast(es);

		return es;
	}

	array<ExpanseSystem@> trackSystems;

	void init() {
		for(uint i = 0, cnt = trackSystems.length; i < cnt; ++i) {
			auto@ es = trackSystems[i];
			es.origin = origin;
			@es.system = getSystem(systems[0].index + es.index);
			es.remnantSize = 100;
			createRemnants(es.system, es.remnantSize, es);
			setPlanetsLocked(es.system, true);
		}

		setExpanseSystem(getSystem(0), randomd(1200, 1800));
		for(uint i = 0, cnt = rooms[0].systems.length; i < cnt; ++i) {
			auto@ sys = getSystem(systems[0].index + rooms[0].systems[i].index);
			setExpanseSystem(sys, randomd(200, 600));
		}
	}

	void tick(double time) {
		bool madeFleet = false;
		
		for(uint i = 0, cnt = trackSystems.length; i < cnt; ++i) {
			auto@ es = trackSystems[i];
			if(es.system is null)
				continue;
			if(es.queuedFleets > 0) {
				if(!madeFleet) {
					createRemnant(es.system, es.remnantSize, es);
					madeFleet = true;
				}
			}
			else if(es.defended) {
				bool defended = false;
				for(uint n = 0, ncnt = es.defenders.length; n < ncnt; ++n) {
					auto@ defender = es.defenders[n];
					if(defender !is null && defender.valid) {
						defended = true;
						break;
					}
				}

				if(!defended) {
					setPlanetsLocked(es.system, false);
					es.defended = false;
					es.defenders.length = 0;

					if(es.shouldExpand)
						expandSystem(es);
				}
			}
		}
	}

	void expandSystem(ExpanseSystem@ es) {
		//Reveal the two closest systems in the next ring
		for(uint i = 0; i < 2; ++i) {
			bool found = false;
			for(uint n = 0, ncnt = trackSystems.length; n < ncnt; ++n) {
				auto@ other = trackSystems[n];
				if(other.field == es.field && other.circle == es.circle+1 && other.position == es.position+i) {
					found = true;
					break;
				}
			}

			if(found)
				continue;

			ExpanseSystem new;
			new.origin = es.origin;
			new.circle = es.circle+1;
			new.spacing = es.spacing;
			new.position = es.position+i;
			new.flatten = es.flatten;
			new.field = es.field;
			new.minAngle = es.minAngle;
			new.maxAngle = es.maxAngle;
			new.radius = es.radius + es.spacing;
			new.index = generatedSystems.length;
			new.shouldExpand = true;
			new.remnantSize = es.remnantSize * REMNANT_FACTOR;

			double aStep = (new.maxAngle - new.minAngle) / double(INITIAL_EXPANSE + new.circle);
			double ang = new.minAngle + double(new.position) * aStep + aStep * 0.5;

			vec3d pos = quaterniond_fromAxisAngle(vec3d_up(), ang) * vec3d_front(new.radius) + new.origin;
			pos.y = es.system.position.y;

			trackSystems.insertLast(new);

			SystemIniter hook;
			@hook.mp = this;
			@hook.es = new;
			generateNewSystem(pos, 2000.0, hook);
		}
	}

	void initSystem(ExpanseSystem@ es) {
		auto@ desc = es.system;
		const SystemType@ sysType;
		do {
			@sysType = getDistributedSystemType();
		}
		while(sysType.unique != SU_NonUnique);

		SystemData data;
		data.index = es.system.index;
		data.position = es.system.position;
		desc.radius = 250;

		sysType.generate(data, es.system);

		desc.object.InnerRadius = desc.radius;
		desc.object.OuterRadius = desc.radius * 1.5;
		desc.object.radius = desc.object.OuterRadius;
		desc.radius = desc.object.OuterRadius;
		desc.object.getNode().scale = desc.object.radius + 128.0;
		desc.object.getNode().rebuildTransform();

		postGenerateSystem(data, es.system);
		finalizeSystem(data, es.system);

		createRemnants(es.system, es.remnantSize * randomd(0.85, 1.15), es, queued=true);
		setPlanetsLocked(es.system, true);
	}

	void save(SaveFile& file) {
		uint cnt = trackSystems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << trackSystems[i];
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		trackSystems.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@trackSystems[i] = ExpanseSystem();
			file >> trackSystems[i];
		}

		if(file < SV_0107)
			loadRemnantDesigns(file);
	}

#section all
}

#section server
class SystemIniter : SystemGenerateHook {
	ExpanseMap@ mp;
	ExpanseSystem@ es;
	void call(SystemDesc@ desc) {
		@es.system = desc;
		mp.initSystem(es);
	}
}

class ExpanseSystem : Savable {
	uint index = 0;
	uint circle = 0;
	uint position = 0;
	uint field = 0;
	SystemDesc@ system;
	vec3d origin;
	array<Ship@> defenders;
	double minAngle = 0, maxAngle = 0;
	double radius = 0;
	double remnantSize = 0;
	double spacing = 6500;
	bool defended = true;
	bool shouldExpand = false;
	bool flatten = false;
	uint queuedFleets = 0;

	void save(SaveFile& file) {
		file << index << circle;
		file << position << field;
		file << system.index;

		uint cnt = defenders.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << defenders[i];
		
		file << minAngle << maxAngle;
		file << radius << remnantSize;
		file << defended << shouldExpand;
		file << spacing << flatten;
		file << origin;
		file << queuedFleets;
	}

	void load(SaveFile& file) {
		file >> index >> circle;
		file >> position >> field;

		uint index = 0;
		file >> index;
		@system = getSystem(index);

		uint cnt = 0;
		file >> cnt;
		defenders.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> defenders[i];
		
		file >> minAngle >> maxAngle;
		file >> radius >> remnantSize;
		file >> defended >> shouldExpand;
		file >> spacing >> flatten;
		file >> origin;
		if(file >= SV_0088)
			file >> queuedFleets;
	}
};
#section all
