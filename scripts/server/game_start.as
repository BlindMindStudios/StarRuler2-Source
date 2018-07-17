#priority init 1000
#priority sync 10
import empire_ai.EmpireAI;
import settings.map_lib;
import settings.game_settings;
import maps;
import map_systems;
import regions.regions;
import artifacts;
from map_generation import generatedSystems, generatedGalaxyGas, GasData;
from empire import Creeps, majorEmpireCount, initEmpireDesigns, sendChatMessage;

import void createWormhole(SystemDesc@ from, SystemDesc@ to) from "objects.Oddity";
import Artifact@ makeArtifact(SystemDesc@ system, uint type = uint(-1)) from "map_effects";

//Galaxy positioning
Map@[] galaxies;

vec3d mapLeft;
vec3d mapRight;
double galaxyRadius = 0;

const double GALAXY_MIN_SPACING = 60000.0;
const double GALAXY_MAX_SPACING = 120000.0;
const double GALAXY_HEIGHT_MARGIN = 50000.0;

bool overlaps(Map@ from, vec3d point, Map@ to) {
	return point.distanceTo(from.origin) < GALAXY_MIN_SPACING + from.radius + to.radius;
}

//Homeworld searches
class HomeworldSearch {
	ScriptThread@ thread;
	vec3d goal;
	SystemData@ result;
	Map@ map;
	Empire@ emp;
};

double findHomeworld(double time, ScriptThread& thread) {
	HomeworldSearch@ search;
	thread.getObject(@search);
	
	@search.result = search.map.findHomeworld(search.emp, search.goal);
	thread.stop();
	return 0;
}

class QualityCalculation {
	array<Map@> galaxies;
	array<SystemData@>@ homeworlds;
}

void calculateQuality(QualityCalculation@ data) {
	uint homeworldCount = data.homeworlds.length;
	array<double> dists(homeworldCount);
	
	for(uint g = 0, gcnt = data.galaxies.length; g < gcnt; ++g) {
		Map@ mp = data.galaxies[g];
		mp.calculateHomeworldDistances();
		
		for(uint i = 0, end = mp.systemData.length; i < end; ++i) {
			SystemData@ system = mp.systemData[i];
			mp.calculateQuality(system, data.homeworlds, dists);
		}
	}
}

void init() {
	soundScale = 500.f;
	if(isLoadedSave)
		return;

	double start = getExactTime(), end = start;
	uint hwGalaxies = 0;

	//Create galaxy map instances
	for(uint i = 0, cnt = gameSettings.galaxies.length; i < cnt; ++i) {
		Map@ desc = getMap(gameSettings.galaxies[i].map_id);

		if(desc !is null) {
			for(uint n = 0; n < gameSettings.galaxies[i].galaxyCount; ++n) {
				Map@ mp = cast<Map>(desc.create());
				@mp.settings = gameSettings.galaxies[i];
				mp.allowHomeworlds = gameSettings.galaxies[i].allowHomeworlds;
				if(mp.allowHomeworlds)
					hwGalaxies += 1;

				galaxies.insertLast(mp);
			}
		}
		else {
			error("Error: Could not find map "+gameSettings.galaxies[i].map_id);
		}
	}

	if(galaxies.length == 0) {
		auto@ _map = cast<Map>(getMap("Spiral.SpiralMap").create());
		@_map.settings = MapSettings();
		galaxies.insertLast(_map);
	}

	if(hwGalaxies == 0) {
		hwGalaxies += 1;
		galaxies[0].allowHomeworlds = true;
	}

	//Place all the systems
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
		galaxies[i].preInit();
		if(galaxies[i].allowHomeworlds)
			galaxies[i].estPlayerCount = ceil(double(majorEmpireCount) / double(hwGalaxies));
		else
			galaxies[i].estPlayerCount = 0;
		galaxies[i].universePlayerCount = majorEmpireCount;
		galaxies[i].preGenerate();
	}

	//Place the galaxies
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
		vec3d origin;

		if(i != 0) {
			double startRad = galaxies[0].radius + galaxies[i].radius + GALAXY_MIN_SPACING;
			double endRad = startRad - GALAXY_MIN_SPACING + GALAXY_MAX_SPACING;

			bool overlap = false;
			do {
				vec2d pos = random2d(startRad, endRad);

				origin = vec3d(pos.x, randomd(-GALAXY_HEIGHT_MARGIN, GALAXY_HEIGHT_MARGIN), pos.y);
				overlap = false;

				for(uint j = 0; j < i; ++j) {
					if(overlaps(galaxies[j], origin, galaxies[i])) {
						overlap = true;
						endRad += GALAXY_MIN_SPACING;
						break;
					}
				}
			}
			while(overlap);
		}

		galaxies[i].setOrigin(origin);
		galaxyRadius = max(galaxyRadius, origin.length + galaxies[i].radius * 1.4);
	}

	//Search for homeworld starting positions in multiple threads (one per empire)
	array<SystemData@> globalHomeworlds;
	{	
		array<TeamSorter> sortedEmps;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			sortedEmps.insertLast(TeamSorter(emp));
		}
		sortedEmps.sortAsc();

		array<HomeworldSearch> homeworlds(sortedEmps.length);
		uint mapCnt = galaxies.length;
		uint mapN = randomi(0, mapCnt - 1), mapC = 0;

		for(uint i = 0; i < homeworlds.length; ++i) {
			HomeworldSearch@ search = homeworlds[i];
			Empire@ emp = sortedEmps[i].emp;

			//Find a galaxy willing to host this empire
			uint j = 0;
			do {
				@search.map = galaxies[(mapN + mapC) % mapCnt];
				++mapC;
				++j;
			}
			while((!search.map.allowHomeworlds || !search.map.canHaveHomeworld(emp)) && j < mapCnt);

			if(mapC >= mapCnt) {
				mapN = randomi(0, mapCnt - 1);
				mapC = 0;
			}

			//Suggested place for this empire
			double angle = double(i) * twopi / double(majorEmpireCount);
			double rad = search.map.radius * 0.8;
			search.goal = vec3d(rad * cos(angle), 0, rad * sin(angle));
			search.goal += search.map.origin;

			//Start the search
			@search.emp = emp;
			if(search.map.possibleHomeworlds.length == 0)
				@search.thread = ScriptThread("game_start::findHomeworld", @search);
			else
				@search.result = search.map.findHomeworld(search.emp, search.goal);
		}
		
		for(uint i = 0; i < homeworlds.length; ++i) {
			HomeworldSearch@ search = homeworlds[i];
			while(search.thread !is null && search.thread.running) sleep(0);
			if(search.result !is null) {
				search.result.addHomeworld(search.emp);
				search.map.markHomeworld(search.result);
			}
			globalHomeworlds.insertLast(search.result);
		}
	}

	//Calculate system quality in threads
	{
		array<QualityCalculation> calcs(6);
		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
			galaxies[i].calculateGalaxyQuality(globalHomeworlds);

		uint n = 0, step = int(ceil(double(galaxies.length) / double(calcs.length)));
		for(uint i = 0; i < calcs.length; ++i) {
			QualityCalculation@ calc = calcs[i];
			@calc.homeworlds = @globalHomeworlds;
			for(uint j = 0; j < step && n < galaxies.length; ++j) {
				calc.galaxies.insertLast(galaxies[n]);
				n += 1;
			}
			calculateQuality(calc);
		}	
	}

	//Generate physics
	double gridSize = max(modSpacing(7500.0), (galaxyRadius * 2.0) / 150.0);
	int gridAmount = (galaxyRadius * 2.0) / gridSize;
	setupPhysics(gridSize, gridSize / 8.0, gridAmount);

	//Generate region objects
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].generateRegions();
	for(uint i = 0, cnt = generatedSystems.length; i < cnt; ++i)
		generatedSystems[i].object.finalizeCreation();

	//Actually generate maps
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].generate();

	//Regenerate the region lookup tree with the actual sizes
	regenerateRegionGroups();

	//Generate wormholes in case of multiple galaxies
	if(galaxies.length > 1) {
		uint totalSystems = 0;
		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
			totalSystems += galaxies[i].systems.length;
		uint wormholes = max(config::GALAXY_MIN_WORMHOLES * galaxies.length,
				totalSystems / config::SYSTEMS_PER_WORMHOLE);
		if(wormholes % 2 != 0)
			wormholes += 1;
		uint generated = 0;

		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
			auto@ glx = galaxies[i];

			//Figure out how many wormhole endpoints this galaxy should have
			double pct = double(glx.systems.length) / double(totalSystems);
			uint amount = max(uint(config::GALAXY_MIN_WORMHOLES), uint(round(pct * wormholes)));

			//Tell the galaxy to distribute them
			glx.placeWormholes(amount);

			generated += amount;
		}

		//Make a circle of wormhole endpoints
		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
			auto@ glx = galaxies[i];
			auto@ nextGlx = galaxies[(i+1)%cnt];

			auto@ from = glx.getWormhole();
			auto@ to = nextGlx.getWormhole();
			if(from is null || to is null)
				continue;

			createWormhole(from, to);
			glx.addWormhole(from, to);
			nextGlx.addWormhole(to, from);
		}

		//Randomly spread the remaining wormholes
		for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
			auto@ glx = galaxies[i], otherGlx;
			SystemDesc@ hole = glx.getWormhole();
			SystemDesc@ other;
			while(hole !is null) {
				uint index = randomi(0, cnt - 1);
				for(uint n = 0; n < cnt; ++n) {
					@otherGlx = galaxies[n];
					@other = otherGlx.getWormhole();

					if(other !is null)
						break;
				}

				if(other !is null) {
					createWormhole(hole, other);
					glx.addWormhole(hole, other);
					otherGlx.addWormhole(other, hole);
				}

				@hole = glx.getWormhole();
				@other = null;
				@otherGlx = null;
			}
		}
	}

	end = getExactTime();
	info("Map generation: "+toString((end - start)*1000,1)+"ms");
	start = end;

	end = getExactTime();
	info("Link generation: "+toString((end - start)*1000,1)+"ms");
	start = end;

	//Deal with generating unique spread artifacts
	if(generatedSystems.length > 1 && config::ENABLE_UNIQUE_SPREADS != 0) {
		for(uint i = 0, cnt = getArtifactTypeCount(); i < cnt; ++i) {
			auto@ type = getArtifactType(i);
			if(type.spreadVariable.length == 0)
				continue;
			if(config::get(type.spreadVariable) <= 0.0)
				continue;

			SystemDesc@ sys;
			if(type.requireContestation > 0)
				@sys = getRandomSystemAboveContestation(type.requireContestation);
			if(sys is null)
				@sys = getRandomSystem();

			if(sys !is null)
				makeArtifact(sys, type.id);
		}
	}

	//Initialization for map code
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].initDefs();
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].init();

	//Explore entire map if indicated
	if(config::START_EXPLORED_MAP != 0.0) {
		for(uint i = 0, cnt = systemCount; i < cnt; ++i)
			getSystem(i).object.ExploredMask = int(~0);
	}

	//Assign already connected players to empires
	{
		if(playerEmpire !is null && playerEmpire.valid)
			CURRENT_PLAYER.linkEmpire(playerEmpire);
		uint empInd = 0, empCnt = getEmpireCount();
		array<Player@>@ players = getPlayers();

		//First pass: players into player empires
		for(uint i = 0, plCnt = players.length; i < plCnt && empInd < empCnt; ++i) {
			Player@ pl = players[i];
			connectedPlayers.insertLast(pl);
			connectedSet.insert(pl.id);
			if(pl.emp is null) {
				for(; empInd < empCnt; ++empInd) {
					Empire@ emp = getEmpire(empInd);
					if(!emp.major)
						continue;
					if(emp.player !is null)
						continue;
					if(emp.getAIType() != ET_Player)
						continue;

					pl.linkEmpire(emp);
					++empInd;
					break;
				}
			}
		}

		//Second pass: take over AIs
		empInd = 0;
		for(uint i = 0, plCnt = players.length; i < plCnt && empInd < empCnt; ++i) {
			Player@ pl = players[i];
			if(pl.emp is null) {
				for(; empInd < empCnt; ++empInd) {
					Empire@ emp = getEmpire(empInd);
					if(!emp.major)
						continue;
					if(emp.player !is null)
						continue;

					pl.linkEmpire(emp);
					if(pl.name.length != 0)
						emp.name = pl.name;
					++empInd;
					break;
				}
			}
		}
	}
}

class TeamSorter {
	Empire@ emp;
	TeamSorter() {}
	TeamSorter(Empire@ empire) {
		@emp = empire;
	}

	int opCmp(const TeamSorter& other) const {
		if(emp.team == -1) {
			if(other.emp.team == -1)
				return 0;
			return 1;
		}
		if(other.emp.team == -1)
			return -1;
		if(emp.team > other.emp.team)
			return 1;
		if(emp.team < other.emp.team)
			return 1;
		return 0;
	}
};

uint get_systemCount() {
	return generatedSystems.length;
}

SystemDesc@ getSystem(uint index) {
	if(index >= generatedSystems.length)
		return null;
	return generatedSystems[index];
}

SystemDesc@ getSystem(Region@ region) {
	if(region is null || region.SystemId == -1)
		return null;
	return generatedSystems[region.SystemId];
}

SystemDesc@ getSystem(const string& name) {
	//TODO: Use dictionary
	uint cnt = systemCount;
	for(uint i = 0; i < cnt; ++i) {
		if(getSystem(i).name == name)
			return getSystem(i);
	}
	return null;
}

SystemDesc@ getRandomSystem() {
	return generatedSystems[randomi(0, generatedSystems.length-1)];
}

SystemDesc@ getRandomSystemAboveContestation(double contest) {
	double roll = randomd();
	double total = 0.0;
	SystemDesc@ chosen;
	for(uint i = 0, cnt = generatedSystems.length; i < cnt; ++i) {
		auto@ sys = generatedSystems[i];
		if(sys.contestation < contest)
			continue;

		total += 1.0;
		double chance = 1.0 / total;
		if(roll < chance) {
			@chosen = sys;
			roll /= chance;
		}
		else {
			roll = (roll - chance) / (1.0 - chance);
		}
	}
	return chosen;
}

SystemDesc@ getClosestSystem(const vec3d& point) {
	SystemDesc@ closest;
	double dist = INFINITY;
	for(uint i = 0, cnt = generatedSystems.length; i < cnt; ++i) {
		double d = generatedSystems[i].position.distanceToSQ(point);
		if(d < dist) {
			dist = d;
			@closest = generatedSystems[i];
		}
	}
	return closest;
}

void syncInitial(Message& msg) {
	uint cnt = generatedSystems.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i)
		generatedSystems[i].write(msg);

	cnt = galaxies.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i)
		msg << galaxies[i].id;
	
	cnt = generatedGalaxyGas.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i) {
		GasData@ gas = generatedGalaxyGas[i];
		
		msg.writeSmallVec3(gas.position);
		msg << float(gas.scale);
		
		if(gas.gdat.cullingNode !is null) {
			msg.write1();
			msg.writeSmallVec3(gas.gdat.cullingNode.position);
			msg << float(gas.gdat.cullingNode.scale);
		}
		else {
			msg.write0();
		}
		
		uint sCnt = gas.sprites.length;
		msg.writeSmall(sCnt);
		for(uint s = 0; s < sCnt; ++s) {
			GasSprite@ sprite = gas.sprites[s];
			msg.writeSmallVec3(sprite.pos);
			msg << float(sprite.scale);
			msg << sprite.color;
			msg.writeBit(sprite.structured);
		}
	}
}

bool doSystemSync = false;
bool sendPeriodic(Message& msg) {
	if(!doSystemSync)
		return false;

	doSystemSync = false;
	uint cnt = generatedSystems.length;
	msg << cnt;
	for(uint i = 0; i < cnt; ++i)
		generatedSystems[i].write(msg);
	return true;
}

array<Player@> connectedPlayers;
set_int connectedSet;
double timer = 0.0;
void tick(double time) {
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].tick(time);

	timer += time;
	if(timer >= 1.0) {
		timer = 0.0;
		array<Player@>@ players = getPlayers();

		//Send connect events
		for(uint i = 0, cnt = players.length; i < cnt; ++i) {
			Player@ pl = players[i];
			string name = pl.name;
			if(name.length == 0)
				continue;
			if(!connectedSet.contains(pl.id)) {
				string msg = format("[color=#aaa]"+locale::MP_CONNECT_EVENT+"[/color]", 
					format("[b]$1[/b]", bbescape(name)));
				sendChatMessage(msg, offset=30);
				connectedPlayers.insertLast(pl);
				connectedSet.insert(pl.id);
			}
		}

		connectedSet.clear();
		for(uint i = 0, cnt = players.length; i < cnt; ++i)
			connectedSet.insert(players[i].id);

		//Send disconnect events
		for(uint i = 0, cnt = connectedPlayers.length; i < cnt; ++i) {
			if(!connectedSet.contains(connectedPlayers[i].id)) {
				Color color;
				string name = connectedPlayers[i].name;
				Empire@ emp = connectedPlayers[i].emp;
				if(emp !is null)
					color = emp.color;

				string msg = format("[color=#aaa]"+locale::MP_DISCONNECT_EVENT+"[/color]", 
					format("[b][color=$1]$2[/color][/b]", toString(color), bbescape(name)));
				sendChatMessage(msg, offset=30);
				connectedPlayers.removeAt(i);
				--i; --cnt;
			}
		}
	}
}

void getSystems() {
	uint cnt = generatedSystems.length;
	for(uint i = 0; i < cnt; ++i)
		yield(generatedSystems[i]);
}

void generateNewSystem(const vec3d& pos, double radius, const string& name = "", bool makeLinks = true) {
	generateNewSystem(pos, radius, null, name, makeLinks);
}

void generateNewSystem(const vec3d& pos, double radius, SystemGenerateHook@ hook, const string& name = "", bool makeLinks = true, const string& type = "") {
	//Because things access the generated systems list from outside of a locked context for performance, and
	//creating new systems is a very very rare thing, we just use an isolation hook here, which pauses the
	//execution of the entire game, runs the hook, then resumes.
	SystemGenerator sys;
	sys.position = pos;
	sys.radius = radius;
	sys.makeLinks = makeLinks;
	sys.makeType = type;
	sys.name = name;
	@sys.hook = hook;
	isolate_run(sys);
}

interface SystemGenerateHook {
	void call(SystemDesc@ desc);
}

class SystemGenerator : IsolateHook {
	vec3d position;
	double radius;
	string name;
	SystemGenerateHook@ hook;
	bool makeLinks = true;
	string makeType;

	void call() {
		if(name.length == 0) {
			NameGenerator sysNames;
			sysNames.read("data/system_names.txt");
			name = sysNames.generate();
		}

		ObjectDesc sysDesc;
		sysDesc.type = OT_Region;
		sysDesc.name = name;
		sysDesc.flags |= objNoPhysics;
		sysDesc.flags |= objNoDamage;
		sysDesc.delayedCreation = true;
		sysDesc.position = position;

		Region@ region = cast<Region>(makeObject(sysDesc));
		region.alwaysVisible = true;
		region.InnerRadius = radius / 1.5;
		region.OuterRadius = radius;
		region.radius = region.OuterRadius;

		SystemData dat;
		dat.index = generatedSystems.length;
		dat.position = position;
		dat.quality = 100;
		@dat.systemCode = SystemCode();

		SystemDesc desc;
		desc.index = generatedSystems.length;
		region.SystemId = desc.index;
		desc.name = region.name;
		desc.position = position;
		desc.radius = region.OuterRadius;
		@desc.object = region;

		generatedSystems.insertLast(desc);
		addRegion(desc.object);

		region.finalizeCreation();

		//Run the type
		auto@ sysType = getSystemType(makeType);
		if(sysType !is null) {
			dat.systemType = sysType.id;

			sysType.generate(dat, desc);

			region.InnerRadius = desc.radius;
			region.OuterRadius = desc.radius * 1.5;
			region.radius = region.OuterRadius;
			desc.radius = region.OuterRadius;

			sysType.postGenerate(dat, desc);

			MapGeneration gen;
			gen.finalizeSystem(dat, desc);
		}

		//Make trade lines to nearby systems
		if(makeLinks) {
			SystemDesc@ closest;
			array<SystemDesc@> nearby;
			double closestDist = INFINITY;
			for(uint i = 0, cnt = generatedSystems.length; i < cnt; ++i) {
				double d = generatedSystems[i].position.distanceTo(desc.position);
				if(generatedSystems[i] is desc)
					continue;
				if(d < 13000.0)
					nearby.insertLast(generatedSystems[i]);
				if(d < closestDist) {
					closestDist = d;
					@closest = generatedSystems[i];
				}
			}

			if(nearby.length == 0) {
				closest.adjacent.insertLast(desc.index);
				closest.adjacentDist.insertLast(closest.position.distanceTo(desc.position));
				desc.adjacent.insertLast(closest.index);
				desc.adjacentDist.insertLast(closest.position.distanceTo(desc.position));
			}
			else {
				for(uint i = 0, cnt = nearby.length; i < cnt; ++i) {
					nearby[i].adjacent.insertLast(desc.index);
					nearby[i].adjacentDist.insertLast(nearby[i].position.distanceTo(desc.position));
					desc.adjacent.insertLast(nearby[i].index);
					desc.adjacentDist.insertLast(nearby[i].position.distanceTo(desc.position));
				}
			}

			if(desc.adjacent.length == 0 || config::START_EXPLORED_MAP != 0.0) {
				desc.object.ExploredMask.value = int(~0);
			}
			else {
				for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i)
					desc.object.ExploredMask |= getSystem(desc.adjacent[i]).object.SeenMask;
			}
		}

		//Create the system node
		Node@ snode = bindCullingNode(region, desc.position, 1000.0);
		snode.scale = region.radius + 128.0;
		snode.rebuildTransform();

		calcGalaxyExtents();

		if(hook !is null)
			hook.call(desc);

		//Notify clients of changes
		refreshClientSystems(CURRENT_PLAYER);
		doSystemSync = true;
	}
};

void save(SaveFile& data) {
	data << uint(generatedSystems.length);
	for(uint i = 0; i < generatedSystems.length; ++i)
		generatedSystems[i].save(data);
	data << uint(generatedGalaxies.length);
	for(uint i = 0; i < generatedGalaxies.length; ++i)
		generatedGalaxies[i].save(data);
	data << uint(generatedGalaxyGas.length);
	for(uint i = 0; i < generatedGalaxyGas.length; ++i)
		generatedGalaxyGas[i].save(data);
	data << uint(galaxies.length);
	for(uint i = 0; i < galaxies.length; ++i) {
		data << galaxies[i].id;
		galaxies[i].save(data);
	}
}

void load(SaveFile& data) {
	uint count = 0;
	data >> count;
	generatedSystems.length = count;
	for(uint i = 0; i < generatedSystems.length; ++i) {
		SystemDesc desc;
		desc.load(data);
		@generatedSystems[i] = desc;
	}

	data >> count;
	generatedGalaxies.length = count;
	for(uint i = 0; i < count; ++i) {
		@generatedGalaxies[i] = GalaxyData();
		generatedGalaxies[i].load(data);
	}

	data >> count;
	generatedGalaxyGas.length = count;
	for(uint i = 0; i < count; ++i) {
		@generatedGalaxyGas[i] = GasData();
		generatedGalaxyGas[i].load(data);
	}

	if(data >= SV_0040) {
		data >> count;
		galaxies.length = count;

		for(uint i = 0; i < galaxies.length; ++i) {
			string ident;
			data >> ident;
			@galaxies[i] = getMap(ident).create();
			galaxies[i].load(data);
		}
	}
}
