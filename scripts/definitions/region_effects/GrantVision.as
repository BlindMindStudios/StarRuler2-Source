#include "include/region_effect_spec.as"

class _Type : RegionEffectType {
	_Type() {
		ident = "GrantVision";
		implementationClass = "GrantVision";
	}
};

class GrantVision : RegionEffect {
	double timer = 0.0;

	GrantVision(Empire@ emp, double timer) {
		@this.forEmpire = emp;
		this.timer = timer;
		@this.type = definition;
	}

#section server
	void save(SaveFile& file) override {
		file << timer;
	}

	void load(SaveFile& file) override {
		file >> timer;
	}

	bool tick(Region& region, double time) override {
		timer -= time;
		if(timer <= 0)
			return false;
		return true;
	}

	void start(Region& region) override {
		region.grantVision(forEmpire);
	}

	void end(Region& region) override {
		region.revokeVision(forEmpire);
	}
#section all
};
