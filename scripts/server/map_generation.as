#priority init 1500
import object_creation;
import map_systems;
from map_systems import IMapHook;
from regions.regions import addRegion;
import settings.map_lib;
import settings.game_settings;
import statuses;
import planet_types;
from empire import Creeps, majorEmpireCount;
import Artifact@ makeArtifact(SystemDesc@ system, uint type = uint(-1)) from "map_effects";
import void createWormhole(SystemDesc@ from, SystemDesc@ to) from "objects.Oddity";
import void mapCopyRegion(SystemDesc@ from, SystemDesc@ to, uint typeMask = ~0)  from "map_effects";
import util.map_tools;

//Global data to be access after generation
array<SystemDesc@> generatedSystems;
array<GasData@> generatedGalaxyGas;
array<GalaxyData@> generatedGalaxies;
NameGenerator sysNames;

Node@ getCullingNode(const vec3d& pos) {
	/*uint cnt = generatedGalaxies.length;
	if(cnt > 1) {
		for(uint i = 0; i < cnt; ++i) {
			auto@ glx = generatedGalaxies[i];
			if(glx.origin.distanceToSQ(pos) < glx.radius * glx.radius)
				return glx.cullingNode;
		}
	}*/
	
	return null;
}

void init() {
	sysNames.preventDuplicates = true;
	sysNames.read("data/system_names.txt");

	GlobalUniqueSystems.length = getSystemTypeCount();
	for(uint i = 0, cnt = GlobalUniqueSystems.length; i < cnt; ++i)
		GlobalUniqueSystems[i] = false;
}

//Default constants
const uint HOMEWORLD_TARGET_LINKS = 4;
array<bool> GlobalUniqueSystems;

//A single map generation script
class MapGeneration {
	GalaxyData gdat;
	MapSettings@ settings;

	array<bool> uniqueSystems(getSystemTypeCount(), false);
	array<GasData@> gasses;
	array<SystemDesc@> systems;
	array<SystemData@> systemData;
	array<SystemData@> homeworlds;
	array<SystemData@> wormholes;
	array<SystemData@> possibleHomeworlds;
	uint wormholeIndex = 0;
	double gasSideLen = 1000.0;
	bool haveLinks = false;
	bool autoGenerateLinks = true;
	int galaxyQuality = 0;

	uint estPlayerCount = 1;
	uint universePlayerCount = 1;

	array<Empire@> teamEmpires;
	array<SystemData@> teamPositions;

	Node@ cullingNode;

	vec3d origin;
	vec3d leftExtent;
	vec3d rightExtent;
	double radius;

	Region@ region;
	Star@ star;

	ObjectDesc sysDesc;
	ObjectDesc starDesc;
	ObjectDesc planetDesc;
	LightDesc lightDesc;
	SystemDesc@ system;

	MapGeneration() {
		sysDesc.type = OT_Region;
		sysDesc.flags |= objNoPhysics;
		sysDesc.delayedCreation = true;

		starDesc.type = OT_Star;
		starDesc.radius = 100.0;

		planetDesc.flags |= objMemorable;
		planetDesc.type = OT_Planet;
		planetDesc.delayedCreation = true;

		lightDesc.diffuse = Colorf(2.7f, 2.0f, 1.0f);
		lightDesc.specular = lightDesc.diffuse;
		lightDesc.att_quadratic = 1.f/(2000.f*2000.f);
	}

	void modSettings(GameSettings& settings) {
	}

	double getSetting(uint index, double def = 0.0) {
		return settings.getSetting(index, def);
	}

	void placeSystems() {
	}

	void placeLinks() {
	}
	
	void prepareSystem(SystemData@ data, SystemDesc@ desc) {
		if(data.homeworlds !is null && data.mirrorSystem !is null)
			data.ignoreAdjacencies = true;
		desc.radius = 250.0;
		if(data.homeworlds !is null) {
			const SystemType@ hwType = getSystemType("HomeSystem");
			if(hwType !is null)
				data.systemType = hwType.id;
			@data.systemCode = null;
		}
	}

	void generateSystems() {
		bool systemCulling = systemData.length > 1;
	
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			prepareSystem(systemData[i], systems[i]);
			generateSystem(systemData[i], systems[i], systemCulling);
		}
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			postGenerateSystem(systemData[i], systems[i]);
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			finalizeSystem(systemData[i], systems[i]);
	}

	SystemData@ addSystem(vec3d point, int quality = 0, bool canHaveHomeworld = true, int sysType = -1, const SystemCode@ code = null, SystemData@ mirrorSystem = null) {
		SystemData dat;
		dat.index = systemData.length;
		dat.position = point;
		dat.quality = quality;
		dat.canHaveHomeworld = canHaveHomeworld;
		dat.systemType = sysType;
		@dat.mirrorSystem = mirrorSystem;
		if(mirrorSystem !is null && code is null)
			@code = SystemCode();
		@dat.systemCode = code;

		systemData.insertLast(dat);
		return dat;
	}

	void preGenerate() {
		//Place systems from the map
		placeSystems();

		//Place links from the map
		placeLinks();

		//If the map has no links, automatically generate them
		if(autoGenerateLinks) {
			generateAutomatedLinks();
			while(!ensureConnectedLinks());
		}

		//Update the full extent of the map
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			vec3d pos = systemData[i].position;

			if(pos.x < leftExtent.x)
				leftExtent.x = pos.x;
			if(pos.y < leftExtent.y)
				leftExtent.y = pos.y;
			if(pos.z < leftExtent.z)
				leftExtent.z = pos.z;

			if(pos.x > rightExtent.x)
				rightExtent.x = pos.x;
			if(pos.y > rightExtent.y)
				rightExtent.y = pos.y;
			if(pos.z > rightExtent.z)
				rightExtent.z = pos.z;
		}

		radius = max((rightExtent - leftExtent).length / 2.0, 6000.0);
	}

	void setOrigin(vec3d Origin) {
		origin = Origin;
		move(origin);
	}

	vec3d getAveragePosition() {
		vec3d avg;
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			avg += systemData[i].position;
		return avg / double(systemData.length);
	}

	void move(const vec3d& move) {
		leftExtent += origin;
		rightExtent += origin;

		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			systemData[i].position += origin;
	}

	void generate() {
		//Create the culling node
		//@cullingNode = createCullingNode(origin, radius * 1.5);

		//Generate everything that was placed
		generateSystems();

		//Generate the galaxy gas
		prepGalaxyGas(max(rightExtent.x - leftExtent.x, rightExtent.y - leftExtent.y));
		generateGas();

		//Add local data to generated lists
		for(uint i = 0, cnt = gasses.length; i < cnt; ++i)
			generatedGalaxyGas.insertLast(gasses[i]);

		//Create placed wormholes
		generateWormholes();

		//Create galaxy data
		gdat.index = generatedGalaxies.length;
		gdat.origin = origin;
		gdat.radius = radius;
		gdat.systems = systems;
		@gdat.cullingNode = cullingNode;

		//Create galaxy plane node
		@gdat.plane = GalaxyPlaneNode();
		gdat.plane.establish(origin, radius);

		generatedGalaxies.insertLast(gdat);
	}
	
	//** {{{ Homeworlds
	bool canHaveHomeworld(SystemData@ data, Empire@ emp) {
		return data.canHaveHomeworld;
	}

	bool canHaveHomeworld(Empire@ emp) {
		return true;
	}

	SystemData@ addPossibleHomeworld(SystemData@ data) {
		possibleHomeworlds.insertLast(data);
		return data;
	}

	SystemData@ findHomeworld(Empire@ emp, vec3d goal) {
		if(possibleHomeworlds.length != 0) {
			SystemData@ sys;
			if(emp.team != -1 && teamPositions.length != 0 && config::TEAMS_START_CLOSE != 0) {
				double bestDist = INFINITY;
				for(uint i = 0, cnt = possibleHomeworlds.length; i < cnt; ++i) {
					auto@ check = possibleHomeworlds[i];
					double d = 0;
					for(uint n = 0, ncnt = teamEmpires.length; n < ncnt; ++n) {
						if(teamEmpires[n].team == emp.team)
							d += teamPositions[n].position.distanceTo(check.position);
					}
					if(d < bestDist) {
						@sys = check;
						bestDist = d;
					}
				}
				if(sys !is null)
					possibleHomeworlds.remove(sys);
			}
			if(sys is null) {
				uint index = randomi(0, possibleHomeworlds.length - 1);
				@sys = possibleHomeworlds[index];
				possibleHomeworlds.removeAt(index);
			}
			if(emp.team != -1) {
				teamEmpires.insertLast(emp);
				teamPositions.insertLast(sys);
			}
			return sys;
		}
		double best = 0;
		uint sysCount = systemData.length;
		SystemData@ result;
		for(uint i = 0; i < sysCount; ++i) {
			SystemData@ dat = systemData[i];
			if(!canHaveHomeworld(dat, emp))
				continue;

			double w = 1.0;

			uint linkCnt = dat.adjacent.length;
			w /= max(1, sqr(int(linkCnt) - int(HOMEWORLD_TARGET_LINKS)));

			w /= goal.distanceToSQ(dat.position);

			if(w > best) {
				best = w;
				@result = dat;
			}
		}

		return result;
	}
	
	void markHomeworld(SystemData@ dat) {
		//List this as a homeworld
		homeworlds.insertLast(dat);
	}
	// }}}

	//** {{{ Gas Generation
	void prepGalaxyGas(double sideLen) {
		gasSideLen = sideLen;
		
		gasses.length = 64;
		for(uint i = 0; i < 64; ++i) {
			int x = int(i) % 8;
			int y = int(i) / 8;
		
			GasData data;
			@data.gdat = gdat;
			data.position = vec3d((double(x) - 3.5) * sideLen / 8.0, 0.0, (double(y) - 3.5) * sideLen / 8.0) + origin;
			data.scale = sideLen / 16.0;
			data.generate(cullingNode);
			@gasses[i] = data;
		}
	}

	void generateGas() {
		Color innerBright, outerBright;
		
		switch(randomi(0,2)) {
			case 0:
				innerBright = Color(0xc08060ff);
				outerBright = Color(0x0040c0ff);
				break;
			case 1:
				innerBright = Color(0xc08060ff);
				outerBright = Color(0x006040ff);
				break;
			case 2:
				innerBright = Color(0xc08060ff);
				outerBright = Color(0x600060ff);
				break;
		}
	
		for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
			vec3d sysPos = systems[i].position;
			double edgePct = sysPos.distanceTo(origin) / (radius * 0.6);

			int brightCount = 10 + int(4.0 * edgePct);
			for(int k = 0; k < brightCount; ++k) {
				Color col = innerBright.interpolate(outerBright, edgePct);
				col.a = randomi(0x14,0x1c);
				vec3d pos = sysPos + vec3d(randomd(-10000.0, 10000.0), randomd(-8000.0,8000.0) * (1.0 - edgePct * 0.75), randomd(-10000.0, 10000.0));
				
				createGalaxyGas(pos, 7500.0 - 2000.0 * edgePct, col, k == 0);
			}
			
			int darkCount = 1 + int(3.0 * edgePct);
			for(int k = 0; k < darkCount; ++k) {
				//Color col = Color(0x200c1815).interpolate(Color(0x08060340), edgePct);
				Colorf fcol;
				fcol.fromHSV(randomd(0,360.0), randomd(0.0,0.2), randomd(0.0,0.2));
				fcol.a = randomd(0.1,0.2);
				
				vec3d pos = sysPos + vec3d(randomd(-10000.0, 10000.0), randomd(-2000.0,2000.0), randomd(-10000.0, 10000.0));
				createGalaxyGas(pos, 4200.0, Color(fcol), true);
			}
		}
	}

	GasData@ gasNodeForPoint(const vec3d& pos) {
		int x = clamp(int(((pos.x - origin.x) * (8.0 / gasSideLen)) + 4.0), 0, 7);
		int y = clamp(int(((pos.z - origin.z) * (8.0 / gasSideLen)) + 4.0), 0, 7);
		return gasses[x + (y*8)];
	}

	void createGalaxyGas(const vec3d& position, double radius, const Color& col, bool structured) {
		GasData@ gas = gasNodeForPoint(position);
		gas.addSprite(position, radius, col.rgba, structured);
	}
	// }}}

	//** {{{ Link Generation
	void addLink(uint from, uint to) {
		addLink(systemData[from], systemData[to]);
	}

	void addLink(SystemData@ from, SystemData@ to) {
		if(from.adjacent.find(to.index) == -1) {
			from.adjacent.insertLast(to.index);
			from.adjacentData.insertLast(to);
		}
		if(to.adjacent.find(from.index) == -1) {
			to.adjacent.insertLast(from.index);
			to.adjacentData.insertLast(from);
		}
		haveLinks = true;
	}

	void generateAutomatedLinks(uint targLinks = 3) {
		AngularItem[] items(16);
		uint cnt = systemData.length;
		for(uint i = 0; i < cnt; ++i) {
			SystemData@ desc = systemData[i];
			if(!desc.autoGenerateLinks)
				continue;

			//Clear angular list
			for(uint p = 0; p < 16; ++p)
				items[p].clear();

			//Add angular items to list
			for(uint j = 0; j < cnt; ++j) {
				SystemData@ other = systemData[j];
				if(other is desc)
					continue;

				vec2d offset(other.position.x - desc.position.x, other.position.z - desc.position.z);

				double angle = offset.radians() + twopi;
				double dist = offset.length;
				if(dist > 31000.0)
					continue;

				//double sz = atan(other.radius / dist);
				double sz = atan(1200.0 / dist); //TODO: Base this on something?
				
				int closest = int(angle / twopi * 16.0);
				int firstBox = int((angle - sz) / twopi * 16.0);
				int lastBox = int((angle + sz) / twopi * 16.0);
				
				for(int p = firstBox; p <= lastBox; ++p) {
					AngularItem@ item = items[(p+16) % 16];
					if(item.desc is null || item.dist > dist) {
						@item.desc = other;
						item.dist = dist;
						item.blocked = p != closest;
					}
				}
			}

			//Turn items into links
			uint linksMade = desc.adjacent.length;
			double distReq = 13000.0;
			do {
				for(uint p = 0, n = randomi(0,15); p < 16; ++p) {
					AngularItem@ item = items[n];
					if(!item.blocked && item.desc !is null && item.desc.autoGenerateLinks && item.dist <= distReq) {
						if(desc.adjacent.find(item.desc.index) == -1) {
							desc.adjacent.insertLast(item.desc.index);
							desc.adjacentData.insertLast(item.desc);
						}

						if(item.desc.adjacent.find(desc.index) == -1) {
							item.desc.adjacent.insertLast(desc.index);
							item.desc.adjacentData.insertLast(desc);
						}

						++linksMade;
						if(distReq > 13000.0 && linksMade >= targLinks)
							break;
						@item.desc = null;
					}

					n = (n+1) % 16;
				}

				//Slowly relax distance requirement until we have at least
				//the target amount of links to work with.
				distReq += 3000.0;
			} while(linksMade < targLinks && distReq <= 31000.0);
		}
	}

	void mark(SystemData@ desc, int markWith, vec3d& point, uint& count) {
		count += 1;
		point += desc.position;
		desc.marked = markWith;

		for(uint i = 0, cnt = desc.adjacent.length; i < cnt; ++i) {
			SystemData@ other = systemData[desc.adjacent[i]];
			if(other.marked != markWith)
				mark(other, markWith, point, count);
		}
	}

	bool ensureConnectedLinks() {
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			systemData[i].marked = -1;

		int ind = 0;
		array<vec3d> centers;
		array<uint> counts;
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			SystemData@ desc = systemData[i];
			if(desc.marked == -1) {
				vec3d point;
				uint count = 0;

				mark(desc, ind, point, count);

				centers.insertLast(point / double(count));
				counts.insertLast(count);
				++ind;
			}
		}

		if(ind > 1) {
			//Find the smallest subgraph.
			int smallest = 0;
			uint smallnum = counts[0];
			for(int i = 1; i < ind; ++i) {
				if(counts[i] < smallnum) {
					smallnum = counts[i];
					smallest = i;
				}
			}

			//Find the best way to connect it to any other subgraph
			SystemData@ bestSmall;
			SystemData@ bestLarge;
			double bestDist = INFINITY;
			for(int n = 0; n < ind; ++n) {
				if(n == smallest)
					continue;

				vec3d center = centers[n];
				SystemData@ closestSmall;
				double closest = INFINITY;

				//Find a system from the smaller set closest to the larger set's center
				for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
					SystemData@ desc = systemData[i];
					if(desc.marked == smallest) {
						double d = desc.position.distanceToSQ(center);
						if(d < closest) {
							@closestSmall = desc;
							closest = d;
						}
					}
				}

				//Find the system from the larger set that is closest to the smaller system
				SystemData@ closestLarge;
				closest = INFINITY;
				for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
					SystemData@ desc = systemData[i];
					if(desc.marked == n) {
						double d = desc.position.distanceToSQ(closestSmall.position);
						if(d < closest) {
							@closestLarge = desc;
							closest = d;
						}
					}
				}

				if(closest < bestDist) {
					@bestSmall = closestSmall;
					@bestLarge = closestLarge;
					bestDist = closest;
				}
			}

			//Make the link
			addLink(bestSmall, bestLarge);
			return false;
		}
		else {
			return true;
		}
	}
	//}}}

	//** {{{ System Calculation
	double getContestation(SystemData@ data, array<double>@ local) {
		double nearest = INFINITY, secondary = INFINITY;

		uint hwCnt = homeworlds.length;
		if(local.length < hwCnt)
			local.length = hwCnt;
		for(uint i = 0; i < hwCnt; ++i) {
			double dist = data.hwDistances[i];
			if(dist < nearest) {
				secondary = nearest;
				nearest = dist;
			}
			else if(dist < secondary) {
				secondary = dist;
			}
			local[i] = dist;
		}

		double pts = 0.0;

		//The nearest 2 players make up most of the points
		pts += (nearest / secondary) * 200.0 - 50.0;

		//Additional players can give bonus points
		for(uint i = 0; i < hwCnt; ++i) {
			double d = local[i];
			if(d <= secondary)
				continue;
			double pct = (nearest / d);
			if(pct > 0.5)
				pts += (pct - 0.5) * 100;
		}

		return pts;
	}

	void calculateGalaxyQuality(array<SystemData@>@ globalHomeworlds) {
		galaxyQuality = 0;
	}

	void calculateQuality(SystemData@ data, array<SystemData@>@ globalHomeworlds, array<double>@ local) {
		if(data.homeworlds !is null)
			return;
		if(homeworlds.length < 2) {
			data.quality += galaxyQuality;
			data.contestation = homeworlds.length == 0 ? INFINITY : 0;
		}
		else {
			data.contestation = getContestation(data, local);
			data.quality += galaxyQuality + max(int(data.contestation), 0);
		}
	}

	void calculateHomeworldDistances() {
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i)
			@systemData[i].hwDistances = array<double>(homeworlds.length, INFINITY);

		for(uint hwInd = 0, hwCnt = homeworlds.length; hwInd < hwCnt; ++hwInd) {
			priority_queue pqueue;
			set_int visited;

			pqueue.push(int(homeworlds[hwInd].index), INFINITY);
			systemData[homeworlds[hwInd].index].hwDistances[hwInd] = 0.0;

			while(!pqueue.empty()) {
				int index = pqueue.top();
				pqueue.pop();

				if(visited.contains(index))
					continue;
				visited.insert(index);

				auto@ dat = systemData[index];
				double curDist = dat.hwDistances[hwInd];

				for(uint i = 0, cnt = dat.adjacentData.length; i < cnt; ++i) {
					auto@ adj = dat.adjacentData[i];
					if(visited.contains(adj.index))
						continue;

					double dDist = curDist + 1000.0 + adj.position.distanceTo(dat.position);
					if(dDist < adj.hwDistances[hwInd]) {
						adj.hwDistances[hwInd] = dDist;
						pqueue.push(adj.index, -int(dDist/1000.0));
					}
				}
			}
		}
	}
	
	array<const ResourceType@>@ getDistributedResources(uint count, int quality, double contestation) {
		array<const ResourceType@> resources(count);
		if(count == 0)
			return resources;
		
		double score = 1.0;
		for(uint i = 0; i < count; ++i) {
			const ResourceType@ type = getDistributedResourceContest(contestation);
			@resources[i] = type;
			score /= type.rarityScore;
		}
		
		array<const ResourceType@> prev = resources;
		uint rolls = 0;
		
		if(quality != 0) {
			double bestScore = score;
			
			array<const ResourceType@> reroll(count);
			while(quality != 0) {
				bool getBetter = false;
				if(quality > 0) {
					getBetter = true;
					if(quality < 100) {
						if(randomi(0,99) > quality)
							break;
						quality = 0;
					}
					else {
						quality -= 100;
					}
				}
				else if(quality > -100) {
					if(randomi(0,99) > -quality)
						break;
					quality = 0;
				}
				else {
					quality += 100;
				}
				
				double rrScore = 1.0;
				for(uint i = 0; i < count; ++i) {
					const ResourceType@ type = getDistributedResourceContest(contestation);
					@reroll[i] = type;
					rrScore /= type.rarityScore;
				}
				
				rolls += 1;
				if(getBetter) {
					if(rrScore > bestScore) {
						bestScore = rrScore;
						resources = reroll;
					}
				}
				else {
					if(rrScore < bestScore) {
						bestScore = rrScore;
						resources = reroll;
					}
				}
			}
		}
		
		return resources;
	}
	//}}}

	//** {{{ System Generation
	void generateLinks(SystemData@ from, SystemDesc@ into) {
		for(uint i = 0, cnt = from.adjacent.length; i < cnt; ++i) {
			if(from.adjacent[i] > from.index)
				continue;
			SystemDesc@ other = systems[from.adjacent[i]];
			double dist = from.position.distanceTo(other.position);

			into.adjacent.insertLast(other.index);
			into.adjacentDist.insertLast(dist);

			other.adjacent.insertLast(into.index);
			other.adjacentDist.insertLast(dist);
		}
	}

	void generateRegions() {
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			SystemData@ data = systemData[i];

			//Create the region
			string name = sysNames.generate();
			sysDesc.name = name;
			sysDesc.position = data.position;
			
			//Hint the creation of the region, so we can reference its hint data in saves
			LockHint hint();
			Region@ region = cast<Region>(makeObject(sysDesc));
			region.alwaysVisible = true;

			//Remember the system position
			region.InnerRadius = 1000;
			region.OuterRadius = 1500;
			region.radius = region.OuterRadius;

			//Create the system descriptor
			SystemDesc desc;
			desc.index = generatedSystems.length;
			region.SystemId = desc.index;
			desc.name = name;
			desc.position = data.position;
			desc.radius = region.OuterRadius;
			desc.assignGroup = data.assignGroup;
			@desc.object = region;
			data.sysIndex = desc.index;

			systems.insertLast(desc);
			generatedSystems.insertLast(desc);
		}
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			auto@ data = systemData[i];
			auto@ desc = systems[i];

			generateLinks(data, desc);
			addRegion(desc.object);
		}
	}

	void generateSystem(SystemData@ data, SystemDesc@ desc, bool systemCulling = true) {
		//Hint that objects in one iteration should
		//start in the same lock
		@region = desc.object;
		@system = desc;
		desc.contestation = data.contestation;

		LockHint hint(region);

		//Create the system node
		Node@ snode;
		if(systemCulling) {
			@snode = bindCullingNode(region, desc.position, 1000.0);
			//snode.reparent(cullingNode);
		}

		//Find a valid system type
		if(data.systemCode !is null) {
			Object@ current;
			for(uint i = 0, cnt = data.systemCode.hooks.length; i < cnt; ++i) {
				auto@ hook = cast<IMapHook@>(data.systemCode.hooks[i]);
				if(hook !is null)
					hook.trigger(data, system, current);
			}
		}
		else {
			const SystemType@ type = getSystemType(data.systemType);
			if(type is null) {
				@type = getDistributedSystemType();
				data.systemType = type.id;
				while(type.unique != SU_NonUnique) {
					if(type.unique == SU_Galaxy) {
						if(uniqueSystems[type.id]) {
							@type = getDistributedSystemType();
							continue;
						}
						else {
							uniqueSystems[type.id] = true;
							break;
						}
					}
					else if(type.unique == SU_Global) {
						if(GlobalUniqueSystems[type.id]) {
							@type = getDistributedSystemType();
							continue;
						}
						else {
							GlobalUniqueSystems[type.id] = true;
							break;
						}
					}
				}
			}
			type.generate(data, desc);
		}

		if(data.mirrorSystem !is null) {
			SystemDesc@ otherDesc = systems[data.mirrorSystem.index];
			desc.radius = otherDesc.radius / 1.5;
		}

		//Set region radius
		region.InnerRadius = desc.radius;
		region.OuterRadius = desc.radius * 1.5;
		region.radius = region.OuterRadius;
		desc.radius = region.OuterRadius;

		//Update the culling node boundary based on the system data
		if(snode !is null) {
			snode.scale = region.radius + 128.0;
			snode.rebuildTransform();
		}
		
		//Clear unnecessary references
		@region = null;
		@star = null;
	}

	void postGenerateSystem(SystemData@ data, SystemDesc@ desc) {
		//Do post generation effects
		if(data.systemCode !is null) {
			Object@ current;
			for(uint i = 0, cnt = data.systemCode.hooks.length; i < cnt; ++i) {
				auto@ hook = cast<IMapHook@>(data.systemCode.hooks[i]);
				if(hook !is null)
					hook.postTrigger(data, system, current);
			}
		}
		else {
			const SystemType@ type = getSystemType(data.systemType);
			if(type !is null)
				type.postGenerate(data, desc);
		}
	}

	void finalizeSystem(SystemData@ data, SystemDesc@ desc) {
		//Do mirror copying
		if(data.mirrorSystem !is null && data.homeworlds is null)
			mapCopyRegion(systems[data.mirrorSystem.index], desc);

		//Deal with resource scarcity
		if(config::RESOURCE_SCARCITY != 0 && data.distributedResources.length != 0) {
			uint sysCnt = generatedSystems.length;
			double targSys = 20.0 * double(majorEmpireCount);
			double factor = 1.0;
			if(sysCnt > uint(targSys))
				factor = pow(double(sysCnt) - targSys, 0.1);
			double pct = (targSys * factor) / double(sysCnt) / config::RESOURCE_SCARCITY;
			if(pct < 1.0) {
				double step = 1.0 / double(data.distributedResources.length);
				uint amount = floor(pct / step);
				if(randomd() < (pct - double(amount)*step) / step)
					amount += 1;
				amount = max(amount, data.quality / 200);

				for(uint i = amount, cnt = data.distributedResources.length; i < cnt; ++i) {
					auto@ obj = data.distributedResources[amount];
					if(obj.isPlanet) {
						auto@ barren = getStatusType("Barren");
						if(barren !is null)
							obj.addStatus(barren.id);
						auto@ barrenType = getPlanetType("Barren");
						if(barrenType !is null)
							cast<Planet>(obj).PlanetType = barrenType.id;
						data.distributedConditions.remove(cast<Planet>(obj));
					}
					data.distributedResources.removeAt(amount);
				}
			}
		}

		//Finalize resource distribution
		uint resCnt = data.distributedResources.length;
		bool hasEnergy = false;
		if(resCnt != 0) {
			array<const ResourceType@>@ resources = getDistributedResources(resCnt, data.quality, data.contestation);
			for(uint i = 0; i < resCnt; ++i) {
				if(resources[i].tilePressure[TR_Energy] > 0)
					hasEnergy = true;
				data.distributedResources[i].addResource(resources[i].id);

				auto@ biome = getBiome(resources[i].nativeBiome);
				if(biome !is null)
					data.distributedResources[i].replaceFirstBiomeWith(biome.id);
				markResourceUsed(resources[i]);
			}
			data.distributedResources.length = 0;
		}

		//Finalize conditions
		for(uint i = 0, cnt = data.distributedConditions.length; i < cnt; ++i)
			data.distributedConditions[i].addRandomCondition();

		//Do handicaps
		if(data.homeworlds !is null && data.homeworlds.length == 1) {
			Empire@ emp = data.homeworlds[0];
			while(emp.handicap >= 10) {
				bool found = false;
				uint plCnt = region.planetCount;
				for(uint i = 0, index = randomi(0, plCnt-1); i < plCnt; ++i) {
					Planet@ pl = region.planets[index];
					if((pl.owner is null || !pl.owner.valid) && pl.valid && !pl.destroying) {
						pl.destroy();
						emp.handicap -= 10;
						found = true;
						break;
					}
					index = (index + 1) % plCnt;
				}

				if(!found)
					break;
			}
		}
		if(data.homeworlds !is null) {
			for(uint i = 0, cnt = data.homeworlds.length; i < cnt; ++i)
				@data.homeworlds[i].HomeSystem = desc.object;
		}

		//Ensure artifacts in systems with energy
		if(hasEnergy && data.artifacts == 0)
			makeArtifact(desc);

		//Do home system mirroring
		if(data.homeworlds !is null && data.mirrorSystem !is null) {
			if(data.mirrorSystem.homeworlds !is null) {
				SystemData@ other = data.mirrorSystem;
				SystemDesc@ otherDesc = systems[other.index];

				for(uint i = 0, cnt = desc.object.objectCount; i < cnt; ++i) {
					Object@ obj = desc.object.objects[i];
					if(obj.isAsteroid)
						obj.destroy();
				}

				uint types = 1<<uint(OT_Anomaly);
				types |= 1<<uint(OT_Artifact);
				types |= 1<<uint(OT_Asteroid);
				mapCopyRegion(otherDesc, desc, types);

				for(uint i = 0, cnt = otherDesc.object.planetCount; i < cnt; ++i) {
					Planet@ pl = otherDesc.object.planets[i];
					vec3d destPos = pl.position - other.position;
					destPos.z = -destPos.z;
					destPos += data.position;

					Planet@ mirr = desc.object.planets[i];
					mirr.orbitAround(destPos, data.position);
					if(pl !is null && mirr !is null) {
						for(uint n = 0, ncnt = mirr.nativeResourceCount; n < ncnt; ++n) {
							mirr.removeResource(mirr.nativeResourceId[0]);
							mirr.wait();
						}
						for(uint n = 0, ncnt = pl.nativeResourceCount; n < ncnt; ++n)
							mirr.addResource(pl.nativeResourceType[n]);
						mirr.wait();
					}
					mirr.mirrorSurfaceFrom(pl);
				}
			}
		}
	}
	//}}}

	//** {{{ Wormhole Generation
	void placeWormholes(uint amount) {
		uint sysCnt = systemData.length;
		for(uint i = 0; i < amount; ++i) {
			uint index = randomi(0, sysCnt - 1);
			SystemData@ data;

			for(uint n = 0; n < sysCnt; ++n) {
				@data = systemData[index];
				index = (index+1) % sysCnt;

				if(data.homeworlds !is null)
					continue;
				bool adjHW = false;
				for(uint j = 0, jcnt = data.adjacent.length; j < jcnt; ++j) {
					if(systemData[data.adjacent[j]].homeworlds !is null) {
						adjHW = true;
						break;
					}
				}
				if(adjHW)
					continue;
				break;
			}

			wormholes.insertLast(data);
		}
	}

	SystemDesc@ getWormhole() {
		if(wormholeIndex >= wormholes.length)
			return null;
		auto@ sys = generatedSystems[wormholes[wormholeIndex].sysIndex];
		wormholeIndex += 1;
		return sys;
	}

	void createWormhole(SystemData@ from, SystemData@ to) {
		from.wormholes.insertLast(to.index);
	}

	void generateWormholes() {
		for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
			auto@ data = systemData[i];
			for(uint n = 0, ncnt = data.wormholes.length; n < ncnt; ++n) {
				auto@ other = systemData[data.wormholes[n]];
				auto@ desc = systems[i];
				auto@ otherDesc = systems[other.index];

				::createWormhole(desc, otherDesc);
				addWormhole(desc, otherDesc);
				addWormhole(otherDesc, desc);
			}
		}
	}

	void addWormhole(SystemDesc@ dat, SystemDesc@ other) {
		dat.wormholes.insertLast(other.index);
	}
	//}}}

	//** {{{ Utilities
	double middleAngle(double from, double to) {
		double diff = to - from;
		if(diff < 0)
			diff += twopi;
		double newAngle = from + (diff * 0.5);
		if(newAngle >= twopi)
			newAngle -= twopi;
		return newAngle;
	}

	double angleDiff(double a, double b) {
		double diff = a - b;
		if(diff < -pi)
			diff += twopi;
		else if(diff >= pi)
			diff -= twopi;
		return abs(diff);
	}
	//}}}

	//** {{{ Game code
	void initDefs() {
	}

	void preInit() {
	}

	void init() {
	}

	void tick(double time) {
	}

	void save(SaveFile& file) {
	}

	void load(SaveFile& file) {
	}
	//}}}
};

// {{{ Automation data structures
final class AngularItem {
	double dist = 0.0;
	SystemData@ desc;
	bool blocked = false;
	
	void clear() {
		@desc = null;
		blocked = false;
	}
};

//}}}

// {{{ Gas data structures
final class GasSprite {
	vec3d pos;
	double scale;
	uint color;
	bool structured;
};

final class GasData {
	GalaxyData@ gdat;
	GalaxyGas@ node;
	GasSprite[] sprites;
	vec3d position;
	double scale;

	void generate(Node@ parent = null) {
		@node = GalaxyGas();
		node.position = position;
		node.scale = scale;
		if(parent !is null)
			node.reparent(parent);
		node.rebuildTransform();
	}

	void addSprite(vec3d pos, double scale, uint color, bool structured) {
		GasSprite sprt;
		sprt.pos = pos;
		sprt.scale = scale;
		sprt.color = color;
		sprt.structured = structured;

		sprites.insertLast(sprt);
		node.addSprite(pos, scale, color, structured);
	}

	void save(SaveFile& msg) {
		msg << position;
		msg << scale;
		msg << gdat.index;

		uint cnt = sprites.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i) {
			GasSprite@ sprt = sprites[i];
			msg << sprt.pos;
			msg << sprt.scale;
			msg << sprt.color;
			msg << sprt.structured;
		}
	}

	void load(SaveFile& msg) {
		msg >> position;
		msg >> scale;

		uint gindex = 0;
		msg >> gindex;
		@gdat = generatedGalaxies[gindex];
		generate(gdat.cullingNode);

		uint cnt = 0;
		msg >> cnt;
		sprites.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			GasSprite@ sprt = sprites[i];
			msg >> sprt.pos;
			msg >> sprt.scale;
			msg >> sprt.color;
			bool structured = true;
			if(msg >= SV_0041)
				msg >> structured;

			node.addSprite(sprt.pos, sprt.scale, sprt.color, structured);
		}
	}
};
//}}}

// {{{ Galaxy data structures
final class GalaxyData {
	uint index = 0;
	vec3d origin;
	double radius;
	SystemDesc@[] systems;
	Node@ cullingNode;
	GalaxyPlaneNode@ plane;

	void save(SaveFile& msg) {
		msg << origin;
		msg << radius;

		uint cnt = systems.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << systems[i].index;
	}

	void load(SaveFile& msg) {
		msg >> origin;
		msg >> radius;
		@cullingNode = createCullingNode(origin, radius * 1.5);

		@plane = GalaxyPlaneNode();
		plane.establish(origin, radius);

		uint cnt = 0;
		msg >> cnt;
		systems.length = cnt;

		uint ind = 0;
		for(uint i = 0; i < cnt; ++i) {
			msg >> ind;
			@systems[i] = generatedSystems[ind];
		}
	}
};
//}}}
