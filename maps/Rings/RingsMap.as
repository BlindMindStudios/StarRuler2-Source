#include "include/map.as"

#section server
import util.map_util;
#section all

enum MapSetting {
	M_SystemCount,
	M_SystemSpacing,
	M_Flatten,
};

class RingsMap : Map {
	RingsMap() {
		super();

		name = locale::RINGS_MAP;
		description = locale::RINGS_MAP_DESC;

		dlc = "Heralds";
		sortIndex = -110;

		color = 0xffd73cff;
		icon = "maps/Rings/rings.png";
	}

#section client
	void makeSettings() {
		Number(locale::SYSTEM_COUNT, M_SystemCount, DEFAULT_SYSTEM_COUNT, decimals=0, step=10, min=6, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
	}

#section server
	void placeSystems() {
		RegionMap regionGroup;

		uint systemCount = uint(getSetting(M_SystemCount, DEFAULT_SYSTEM_COUNT));
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		uint ringCount = max(floor(pow(double(systemCount), 0.33)), 1.0);
		uint sysPerRing = ceil(double(systemCount) / double(ringCount));
		double baseRadius = (sysPerRing * spacing * 1.2) / twopi;

		vec3d ringPos;
		double ringRadius;
		vec3d ringAxis = vec3d_up();

		for(uint i = 0; i < ringCount; ++i) {
			if(i == 0) {
				ringPos = vec3d(0.0, 0.0, 0.0);
				ringRadius = randomd(0.9, 1.5) * baseRadius;
			}
			else {
				//Start somewhere random on the previous ring
				ringPos += quaterniond_fromAxisAngle(ringAxis, randomd(0, twopi)) * vec3d(ringRadius, 0.0, 0.0);
				ringRadius = randomd(0.9, 1.5) * baseRadius;

				if(!flatten)
					ringAxis = quaterniond_fromAxisAngle(vec3d_right(), randomd(-0.2*pi, 0.2*pi)) * quaterniond_fromAxisAngle(vec3d_front(), randomd(-0.2*pi, 0.2*pi)) * vec3d_up();
			}

			double angleStep = twopi / double(sysPerRing);
			double angle = randomd(0, angleStep);
			for(uint n = 0; n < sysPerRing; ++n) {
				vec3d sysPos = ringPos;
				sysPos += quaterniond_fromAxisAngle(ringAxis, angle) * vec3d(ringRadius, 0.0, 0.0);

				vec3d flatPos = sysPos;
				flatPos.y = 0;

				if(regionGroup.findRegion(flatPos) !is null) {
					angle += angleStep;
					continue;
				}

				auto@ sys = addSystem(sysPos);
				regionGroup.addSystem(flatPos, spacing * 0.8);
				angle += angleStep;
			}
		}

		move(vec3d() - getAveragePosition());
	}
#section all
};
