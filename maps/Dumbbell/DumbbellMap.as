#include "include/map.as"

enum MapSetting {
	M_SystemCount,
	M_SystemSpacing,
	M_Flatten,
	M_Mirror,
};

class DumbbellMap : Map {
	DumbbellMap() {
		super();

		name = locale::DUMBBELL_MAP;
		description = locale::DUMBBELL_MAP_DESC;

		sortIndex = -100;

		color = 0xd252ffff;
		icon = "maps/Dumbbell/dumbbell.png";
	}

#section client
	void makeSettings() {
		Number(locale::SYSTEM_COUNT, M_SystemCount, DEFAULT_SYSTEM_COUNT, decimals=0, step=10, min=10, halfWidth=true);
		Number(locale::SYSTEM_SPACING, M_SystemSpacing, DEFAULT_SPACING, decimals=0, step=1000, min=MIN_SPACING, halfWidth=true);
		Toggle(locale::FLATTEN, M_Flatten, false, halfWidth=true);
		Toggle(locale::PERFECT_MIRROR, M_Mirror, false, halfWidth=true, tooltip=locale::TT_PERFECT_MIRROR);
	}

#section server
	void placeSystems() {
		uint systemCount = uint(getSetting(M_SystemCount, DEFAULT_SYSTEM_COUNT));
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;
		bool mirror = getSetting(M_Mirror, 0.0) != 0.0;

		//Calculate values
		double bellSystems = ceil(double(systemCount) * 0.43);
		double bellRadius = sqrt(bellSystems) * spacing * 0.5;

		//Make left bell
		genBell(vec3d(0, 0, -bellRadius*3.0), bellRadius, bellSystems);
		genCorridor(vec3d(0, 0, -bellRadius*2.0+spacing*0.75), vec3d(0, 0, -spacing), ceil(double(systemCount) * 0.07));

		if(!mirror) {
			//Make right bell
			genBell(vec3d(0, 0, bellRadius*3.0), bellRadius, bellSystems);
			genCorridor(vec3d(0, 0, 0), vec3d(0, 0, bellRadius*2.0-spacing*0.75), ceil(double(systemCount) * 0.07));
		}
		else {
			//Create empty systems opposite every generated system
			for(uint i = 0, cnt = systemData.length; i < cnt; ++i) {
				auto@ other = systemData[i];
				vec3d pos = other.position;
				pos.z = -pos.z;

				auto@ sys = addSystem(pos, mirrorSystem = other);

				if(possibleHomeworlds.find(other) != -1)
					addPossibleHomeworld(sys);
			}

			genCorridor(vec3d(0, 0, 0), vec3d(0, 0, 0), ceil(double(systemCount) * 0.07), quality=500);
		}
	}

	void genBell(vec3d around, double radius, uint systemCount) {
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		Poisson2D gen;
		gen.circleRadius = radius;
		gen.generate(radius*2.0, radius*2.0, spacing);

		SystemData@ centerMost;
		double centerDist = INFINITY;
		for(uint i = 0, cnt = min(gen.length, systemCount); i < cnt; ++i) {
			vec3d pos = around;
			vec2d offset = gen[i] - vec2d(radius, radius);
			pos.x += offset.x;
			pos.z += offset.y;
			if(!flatten)
				pos.y += randomd(-spacing * 0.3, spacing * 0.3);

			auto@ sys = addSystem(pos);

			double d = offset.length;
			if(d < centerDist) {
				@centerMost = sys;
				centerDist = d;
			}
		}

		addPossibleHomeworld(centerMost);
	}

	void genCorridor(vec3d origin, vec3d dest, uint systemWidth, int quality = 0) {
		double spacing = modSpacing(getSetting(M_SystemSpacing, DEFAULT_SPACING));
		bool flatten = getSetting(M_Flatten, 0.0) != 0.0;

		double wstep = 1.0 / ceil(sqrt(double(systemWidth)) / 0.75);
		if(origin.distanceTo(dest) < spacing)
			wstep = 1.1;
		else
			wstep = max(wstep, 1.0 / max(floor(dest.distanceTo(origin) / spacing), 1.0));
		uint height = ceil(sqrt(double(systemWidth) * 0.75));
		double w = 0.0;
		while(w <= 1.0) {
			vec3d pos = origin + (dest-origin)*w;
			pos.x -= randomd(0.8, 1.5) * spacing * (double(height-1)/2);

			for(uint n = 0; n < height; ++n) {
				vec3d sysPos = pos;
				if(!flatten)
					sysPos.y += randomd(-spacing * 0.3, spacing * 0.3);
				addSystem(sysPos, quality=quality);
				pos.x += randomd(0.8, 1.5) * spacing;
			}

			w += wstep;
		}
	}
#section all
}
