#include "include/map.as"

enum MapSetting {
	M_SystemCount,
	M_SystemSpacing,
	M_Flatten,
};

#section server
class Room {
	vec3d position;
	uint circle = 0;
	SystemData@ core;
	array<SystemData@> systems;
	array<uint> circles;
	array<Room@> corrids;
};
#section all

class ClustersMap : Map {
	ClustersMap() {
		super();

		name = locale::CLUSTERS_MAP;
		description = locale::CLUSTERS_MAP_DESC;

		sortIndex = -100;

		color = 0xd8ff00ff;
		icon = "maps/Clusters/clusters.png";
	}

#section client
	void makeSettings() {
		Number(locale::SYSTEM_COUNT, M_SystemCount, DEFAULT_SYSTEM_COUNT, decimals=0, step=10, min=20, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
	}

#section server
	void placeSystems() {
		uint systemCount = uint(getSetting(M_SystemCount, DEFAULT_SYSTEM_COUNT));
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		//Calculate amount of 'rooms'
		uint roomCnt = max(ceil(pow(double(systemCount), 0.33)), double(max(estPlayerCount+1, 4)));
		uint corridorLength = clamp(ceil(double(systemCount) / 50.0), 1, 5);
		uint sysPerRoom = max(double(systemCount) / double(roomCnt) - double(corridorLength), 4.0);
		if(sysPerRoom % 2 != 0)
			sysPerRoom -= 1;
		double roomRadius = spacing * 1.5 * sqrt(double(sysPerRoom)) + spacing;
		double glxRadius = roomRadius * sqrt(double(roomCnt));
		double roomHeightVar = flatten ? 0.0 : roomRadius * 0.2;
		double sysHeightVar = flatten ? 0.0 : spacing * 0.25;

		//Generate rooms
		double angle = 0.0;
		double radius = 0.0;
		double angleStep = twopi;
		double anglePct = 0.0;
		double startAngle = randomd(0.0, twopi);

		array<Room@> rooms;
		Room@ circleStart;
		uint circle = 0;
		uint circleCnt = 0;

		for(uint i = 0; i < roomCnt; ++i) {
			Room room;
			room.position = quaterniond_fromAxisAngle(vec3d_up(), angle + startAngle) * vec3d_front(radius);
			room.position.y = randomd(-roomHeightVar, roomHeightVar);
			room.circle = circle;

			//Make room connections
			if(rooms.length != 0 && (roomCnt-i+circleCnt) > 2) {
				if(rooms[i-1].circle == circle)
					room.corrids.insertLast(rooms[i-1]);
			}
			if(circleStart is null)
				@circleStart = room;
			rooms.insertLast(room);
			++circleCnt;

			//Generate links to previous circle
			if(circle > 0) {
				Room@ closest;
				double closestDist = INFINITY;
				Room@ second;
				double secondDist = INFINITY;

				for(int j = int(i); j >= 0; --j) {
					if(rooms[j].circle < circle-1)
						break;
					if(rooms[j].circle > circle-1)
						continue;

					Room@ other = rooms[j];
					double d = other.position.distanceToSQ(room.position);

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
					room.corrids.insertLast(closest);
				if(second !is null)
					room.corrids.insertLast(second);
			}

			//Proceed to next room position
			angle += angleStep;
			if(angle + angleStep > twopi) {
				angle = 0.0;
				radius += roomRadius;
				startAngle = randomd(0.0, twopi);

				anglePct = (roomRadius / (2.0 * pi * radius));
				if(roomCnt - i - 1 > 0)
					angleStep = max(anglePct * twopi, twopi / double(roomCnt - i - 1));
				circle += 1;

				if(circleStart !is null && circle != 1 && circleStart !is room && circleCnt > 2)
					room.corrids.insertLast(circleStart);
				@circleStart = null;
				circleCnt = 0;
			}
		}

		//Generate systems
		for(uint i = 0; i < roomCnt; ++i) {
			Room@ room = rooms[i];

			//Generate systems
			angle = 0.0;
			radius = 0.0;
			angleStep = twopi;
			startAngle = randomd(0.0, twopi);
			circle = 0;
			int quality = 0;
			if(i == 0 && roomCnt > estPlayerCount)
				quality = 100;
			uint hwInd = randomi(0, sysPerRoom-1);
			for(uint n = 0; n < sysPerRoom; ++n) {
				//Generate system
				vec3d pos = quaterniond_fromAxisAngle(vec3d_up(), angle + startAngle) * vec3d_front(radius);
				pos.y = randomd(-sysHeightVar, sysHeightVar);
				pos += room.position;
				SystemData@ sys = addSystem(pos, quality=quality);
				if(i != 0) {
					if(hwInd == n)
						addPossibleHomeworld(sys);
				}
				else if(circle == 0) {
					auto@ blackHole = getSystemType("CoreBlackhole");
					if(blackHole !is null)
						sys.systemType = int(blackHole.id);
				}

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
					if(sysPerRoom - n - 1 > 0)
						angleStep = max(anglePct * twopi, twopi / double(sysPerRoom - n - 1));
					circle += 1;
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
#section all
};
