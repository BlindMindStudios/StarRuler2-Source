#include "include/map.as"

enum MapSetting {
	M_SystemCount,
	M_SystemSpacing,
	M_Flatten,
	M_ConnectEnds,
};

class CorkscrewMap : Map {
	CorkscrewMap() {
		super();

		name = locale::CORKSCREW_GALAXY;
		description = locale::CORKSCREW_GALAXY_DESC;

		color = 0xff5900ff;
		icon = "maps/Corkscrew/corkscrew.png";
	}

#section client
	void makeSettings() {
		Number(locale::SYSTEM_COUNT, M_SystemCount, DEFAULT_SYSTEM_COUNT, decimals=0, step=10, min=6, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
		Toggle(locale::CONNECT_ENDS, M_ConnectEnds, true, halfWidth=true);
	}

#section server
	void placeSystems() {
		uint systemCount = uint(getSetting(M_SystemCount, DEFAULT_SYSTEM_COUNT));
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;
		bool connectEnds = getSetting(M_ConnectEnds, 1.0) != 0.0;
		autoGenerateLinks = false;

		uint width = max(1, uint(ceil(log(double(systemCount))/log(10.0))));
		uint length = ceil(double(systemCount) / double(width));
		double startAngle = randomd(0.0, twopi);
		double angle = 0.0;
		double radius = spacing * 2.0;
		double height = 0.0;
		double heightDiff = spacing * 0.25;

		int xStart = -floor(double(width)/2.0);
		int xEnd = ceil(double(width)/2.0);

		vec3d pos;
		vec3d prevPos = quaterniond_fromAxisAngle(vec3d_up(), startAngle - 0.1) * vec3d_front(radius);
		prevPos.y = spacing;

		int hwStep, hwOffset;
		if(connectEnds) {
			hwStep = floor(double(systemCount) / double(max(estPlayerCount, 1)));
			hwOffset = (hwStep / 2) + randomi(-width,width);
		}
		else {
			hwStep = floor(double(systemCount) / double(max(estPlayerCount - 1, 1)));
			hwOffset = hwStep - 1 + randomi(-width,0);
		}
		
		array<SystemData@> cur(width);
		array<SystemData@> prev(width);
		int count = 0;
		for(uint n = 0; n < length; ++n) {
			//Make systems in strip
			vec3d offset;
			for(int x = xStart, i = 0; x < xEnd; ++x) {
				pos = quaterniond_fromAxisAngle(vec3d_up(), startAngle + angle) * vec3d_front(radius);
				pos.y = height + randomd(-heightDiff, heightDiff);

				if(x == xStart)
					offset = (pos - prevPos).cross(vec3d_up()).normalized(spacing);
				pos += offset * -double(x);

				if(flatten)
					pos.y = 0;
				if(x == 0)
					prevPos = pos;

				SystemData@ sys = addSystem(pos);
				@cur[i] = sys;
				++i;

				++count;
				if((count + hwOffset) % hwStep == 0)
					addPossibleHomeworld(sys);
			}

			//Make links
			for(uint i = 0; i < width; ++i) {
				if(i != 0)
					addLink(cur[i-1], cur[i]);
				if(i != width-1)
					addLink(cur[i], cur[i+1]);
				if(prev[i] !is null)
					addLink(prev[i], cur[i]);
			}
			prev = cur;

			//Update next position
			double anglePct = (spacing / (2.0 * pi * radius));
			angle += anglePct * twopi;
			radius += spacing * anglePct * double(width) * 1.5;
			height -= spacing * anglePct * 4.0;

			if(angle >= twopi)
				angle -= twopi;
		}


		uint genCnt = systemData.length;

		//Add final homeworld
		if(possibleHomeworlds.length < estPlayerCount)
			addPossibleHomeworld(systemData[randomi(genCnt-(width*2), genCnt-1)]);

		//Create the wormhole
		if(connectEnds) {
			createWormhole(	systemData[randomi(0, width-1)],
							systemData[randomi(genCnt-width, genCnt-1)]);
		}
	}
#section all
};
