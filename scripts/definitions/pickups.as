#priority init 1000
import hooks;
from saving import SaveIdentifier;

export PickupType;
export getPickupTypeCount, getPickupType, addPickupType;
export getDistributedPickupType;

tidy final class PickupType {
	uint id = 0;
	string ident;

	string name;
	string description;
	string verb = locale::VERB_PICKUP;
	string dlc;

	array<IPickupHook@> hooks;
	double physicalSize = 5.0;
	const Model@ model = model::Research_Station;
	const Material@ material = material::GenericPBR_Research_Station;

	double frequency = 1.0;

	const SpriteSheet@ iconSheet = spritesheet::OrbitalIcons;
	uint iconIndex = 12;

	double get_totalRarity() {
		return 1.0 / frequency;
	}

	string getName(Pickup& pickup) const {
		return name;
	}

	bool canPickup(Pickup& pickup, Object& obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canPickup(pickup, obj))
				return false;
		}
		return true;
	}

	void onPickup(Pickup& pickup, Object& obj) const {
		uint repeats = obj.owner.RemnantPickupMult;
		if(frequency == 0.0)
			repeats = 1;

		for(uint n = 0; n < repeats; ++n) {
			for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
				hooks[i].onPickup(pickup, obj);
		}
	}

	void onClear(Pickup& pickup, Object& obj) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].onClear(pickup, obj);
	}
};

interface IPickupHook {
	bool canPickup(Pickup& pickup, Object& obj) const;
	void onPickup(Pickup& pickup, Object& obj) const;
	void onClear(Pickup& pickup, Object& obj) const;
};

class PickupHook : Hook, IPickupHook {
	bool canPickup(Pickup& pickup, Object& obj) const { return true; }
	void onPickup(Pickup& pickup, Object& obj) const {}
	void onClear(Pickup& pickup, Object& obj) const {}
};

array<PickupType@> list;
dictionary idents;
double totalFrequency = 0.0;

uint getPickupTypeCount() {
	return list.length;
}

const PickupType@ getPickupType(uint id) {
	if(id < list.length)
		return list[id];
	else
		return null;
}

const PickupType@ getDistributedPickupType() {
	double num = randomd(0, totalFrequency);
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		const PickupType@ type = list[i];
		double freq = type.frequency;
		if(num <= freq)
			return type;
		num -= freq;
	}
	return list[list.length-1];
}

const PickupType@ getPickupType(const string& name) {
	PickupType@ type;
	idents.get(name, @type);
	return type;
}

void addPickupType(PickupType@ type) {
	type.id = list.length;
	list.insertLast(type);
	idents.set(type.ident, @type);
	totalFrequency += type.frequency;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		PickupType@ type = list[i];
		file.addIdentifier(SI_Pickup, type.id, type.ident);
	}
}

void init() {
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n)
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook: "+addrstr(type.hooks[n])+" in "+type.ident);
	}
}
