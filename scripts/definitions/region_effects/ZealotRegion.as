#include "include/region_effect_spec.as"

export ZealotRegion, ZealotRegionEffect, createZealotRegionEffect;
const RegionEffectType@ get_ZealotRegion() {
	return definition;
}

ZealotRegionEffect@ createZealotRegionEffect(Empire@ empire, Empire@ other) {
	ZealotRegionEffect eff;
	@eff.type = definition;
	@eff.forEmpire = empire;
	@eff.other = other;

	return eff;
}

class _Type : RegionEffectType {
	_Type() {
		ident = "ZealotRegion";
		implementationClass = "ZealotRegionEffect";
	}
};

const uint MAX_PER_TICK = 100;
const double STR_FACTOR = 0.5 / (6.0 * 60.0);

class ZealotRegionEffect : RegionEffect {
	Empire@ other;
	double accStr = 0.0;
	double storedTime = 0.0;

#section server
	void save(SaveFile& file) override {
		file << other;
		file << accStr;
		file << storedTime;
	}

	void load(SaveFile& file) override {
		file >> other;
		file >> accStr;
		file >> storedTime;
	}

	bool tick(Region& region, double time) override {
		storedTime += time;
		if(storedTime < 1.0)
			return true;

		double str = region.getStrength(other) * STR_FACTOR * storedTime;
		accStr += str;
		storedTime = 0.0;

		if(accStr > 1.0) {
			uint objCount = region.objectCount;
			uint index = randomi(0, objCount-1);
			uint cnt = min(objCount, MAX_PER_TICK);
			for(uint i = 0; i < cnt; ++i) {
				Ship@ obj = cast<Ship>(region.objects[i]);
				if(obj !is null && obj.owner is other) {
					//Check if we can take over this ship
					if(!obj.hasLeaderAI || obj.supportCount == 0) {
						double size = obj.blueprint.design.size;
						double chance = accStr / size;
						chance *= chance;

						if(chance > 1.0 || randomd() < chance) {
							@obj.owner = forEmpire;
							accStr -= size;
							if(accStr < 1.0)
								break;
						}
					}
				}

				index = (index+1) % cnt;
			}
		}
		return true;
	}
#section all
};
