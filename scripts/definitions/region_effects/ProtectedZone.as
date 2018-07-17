#include "include/region_effect_spec.as"

class _Type : RegionEffectType {
	_Type() {
		ident = "ProtectedZone";
		implementationClass = "ProtectedZone";
	}
};

class ProtectedZone : RegionEffect {
	bool tick(Region& region, double time) override {
		region.ProtectedMask |= forEmpire.mask;
		return true;
	}

	void changeEffectOwner(Region& region, Empire@ prevOwner, Empire@ newOwner) override {
		region.ProtectedMask &= ~prevOwner.mask;
		region.ProtectedMask |= newOwner.mask;
	}

	void end(Region& region) override {
		region.ProtectedMask &= ~forEmpire.mask;
	}
};
