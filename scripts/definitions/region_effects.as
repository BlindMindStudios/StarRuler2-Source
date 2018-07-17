#priority init 2000
from saving import SaveIdentifier;

export RegionEffectType, RegionEffect;
export getRegionEffectCount, getRegionEffect;

class RegionEffectType {
	uint id = 0;
	string ident;
	string name;
	string description;

	AnyClass@ implementation;
	string implementationClass;

	RegionEffect@ create() const {
		RegionEffect@ eff = cast<RegionEffect>(implementation.create());
		@eff.type = this;
		return eff;
	}
};

tidy class RegionEffect {
	int id = -1;
	const RegionEffectType@ type;
	Empire@ forEmpire;

	void start(Region& region) {
	}

	bool tick(Region& region, double time) {
		return true;
	}

	void end(Region& region) {
	}

	void changeEffectOwner(Region& region, Empire@ prevOwner, Empire@ newOwner) {
	}

	void ownerChange(Region& region, Object& obj, Empire@ prevOwner, Empire@ newOwner) {
	}

	void enable(Region& region, Object& obj) {
	}

	void disable(Region& region, Object& obj) {
	}

	void load(SaveFile& file) {
	}

	void save(SaveFile& file) {
	}
};

array<RegionEffectType@> effects;
dictionary effectIdents;

uint getRegionEffectCount() {
	return effects.length;
}

const RegionEffectType@ getRegionEffect(uint id) {
	if(id < effects.length)
		return effects[id];
	else
		return null;
}

const RegionEffectType@ getRegionEffect(const string& name) {
	RegionEffectType@ eff;
	effectIdents.get(name, @eff);
	return eff;
}

void addRegionEffect(RegionEffectType@ eff) {
	eff.id = effects.length;
	effects.insertLast(eff);
	effectIdents.set(eff.ident, @eff);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
		RegionEffectType@ type = effects[i];
		file.addIdentifier(SI_RegionEffect, type.id, type.ident);
	}
}
