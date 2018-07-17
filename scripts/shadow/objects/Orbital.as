import regions.regions;
from resources import MoneyType;
import orbitals;
import saving;

const int STRATEGIC_RING = -1;
const double RECOVERY_TIME = 3.0 * 60.0;

tidy class OrbitalScript {
	OrbitalNode@ node;
	StrategicIconNode@ icon;

	OrbitalSection@ core;
	array<OrbitalSection@> sections;
	int nextSectionId = 1;
	int contestion = 0;
	bool disabled = false;
	Orbital@ master;

	double Health = 0;
	double MaxHealth = 0;
	double Armor = 0;
	double MaxArmor = 0;
	double DR = 2.5;
	double DPS = 0;

	Orbital@ getMaster() {
		return master;
	}

	bool hasMaster() {
		return master !is null;
	}

	bool isMaster(Object@ obj) {
		return master is obj;
	}

	double get_health(Orbital& orb) {
		double v = Health;
		Empire@ owner = orb.owner;
		if(owner !is null)
			v *= owner.OrbitalHealthMod;
		return v;
	}

	double get_maxHealth(Orbital& orb) {
		double v = MaxHealth;
		Empire@ owner = orb.owner;
		if(owner !is null)
			v *= owner.OrbitalHealthMod;
		return v;
	}

	double get_armor(Orbital& orb) {
		double v = Armor;
		Empire@ owner = orb.owner;
		if(owner !is null)
			v *= owner.OrbitalArmorMod;
		return v;
	}

	double get_maxArmor(Orbital& orb) {
		double v = MaxArmor;
		Empire@ owner = orb.owner;
		if(owner !is null)
			v *= owner.OrbitalArmorMod;
		return v;
	}

	double get_dps() {
		return DPS;
	}

	double get_efficiency() {
		return clamp(Health / max(1.0, MaxHealth), 0.0, 1.0);
	}

	double getValue(Player& pl, Orbital& obj, uint id) {
		double value = 0.0;
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			auto@ sec = sections[i];
			for(uint j = 0, jcnt = sec.type.hooks.length; j < jcnt; ++j) {
				if(sec.type.hooks[j].getValue(pl, obj, sec.data[j], id, value))
					return value;
			}
		}
		return 0.0;
	}

	const Design@ getDesign(Player& pl, Orbital& obj, uint id) {
		const Design@ value;
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			auto@ sec = sections[i];
			for(uint j = 0, jcnt = sec.type.hooks.length; j < jcnt; ++j) {
				if(sec.type.hooks[j].getDesign(pl, obj, sec.data[j], id, value))
					return value;
			}
		}
		return null;
	}

	Object@ getObject(Player& pl, Orbital& obj, uint id) {
		Object@ value;
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			auto@ sec = sections[i];
			if(!sec.enabled)
				continue;
			for(uint j = 0, jcnt = sec.type.hooks.length; j < jcnt; ++j) {
				if(sec.type.hooks[j].getObject(pl, obj, sec.data[j], id, value))
					return value;
			}
		}
		return null;
	}

	void getSections() {
		for(uint i = 0, cnt = sections.length; i < cnt; ++i)
			yield(sections[i]);
	}

	bool hasModule(uint typeId) {
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			auto@ sec = sections[i];
			if(sec.type.id == typeId)
				return true;
		}
		return false;
	}

	uint get_coreModule() {
		auto@ mod = core;
		if(mod is null)
			return uint(-1);
		return mod.type.id;
	}

	bool get_isStandalone() {
		auto@ mod = core;
		if(mod is null)
			return true;
		return mod.type.isStandalone;
	}

	bool get_isContested() {
		return contestion != 0;
	}

	bool get_isDisabled() {
		return disabled || (core !is null && !core.enabled);
	}

	void destroy(Orbital& obj) {
		if(icon !is null) {
			if(obj.region !is null)
				obj.region.removeStrategicIcon(STRATEGIC_RING, icon);
			icon.markForDeletion();
			@icon = null;
		}
		@node = null;

		leaveRegion(obj);
		obj.destroyObjResources();
		if(obj.hasConstruction)
			obj.destroyConstruction();
		if(obj.hasAbilities)
			obj.destroyAbilities();
	}

	bool onOwnerChange(Orbital& obj, Empire@ prevOwner) {
		regionOwnerChange(obj, prevOwner);
		obj.changeResourceOwner(prevOwner);
		return false;
	}

	float timer = 0.f;
	double prevFleet = 0.0;
	void occasional_tick(Orbital& obj) {
		Region@ prevRegion = obj.region;
		if(updateRegion(obj)) {
			Region@ newRegion = obj.region;
			if(icon !is null) {
				if(prevRegion !is null)
					prevRegion.removeStrategicIcon(STRATEGIC_RING, icon);
				if(newRegion !is null)
					newRegion.addStrategicIcon(STRATEGIC_RING, obj, icon);
			}
			obj.changeResourceRegion(prevRegion, newRegion);
			@prevRegion = newRegion;
		}

		if(icon !is null)
			icon.visible = obj.isVisibleTo(playerEmpire);

		if(node !is null) {
			double rad = 0.0;
			if(obj.hasLeaderAI && obj.SupplyCapacity > 0)
				rad = obj.getFormationRadius();
			if(rad != prevFleet) {
				node.setFleetPlane(rad);
				prevFleet = rad;
			}
		}
		
		if(obj.hasLeaderAI)
			obj.updateFleetStrength();
	}

	vec3d get_strategicIconPosition(const Orbital& obj) {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	double tick(Orbital& obj, double time) {
		//Tick construction
		double delay = 0.2;
		if(obj.hasConstruction) {
			obj.constructionTick(time);
			//if(obj.hasConstructionUnder(0.2))
			//	delay = 0.0;
		}
		if(obj.hasAbilities)
			obj.abilityTick(time);

		//Tick resources
		obj.resourceTick(time);

		//Tick orbit
		obj.moverTick(time);

		//Tick occasional stuff
		timer -= float(time);
		if(timer <= 0.f) {
			occasional_tick(obj);
			timer = 1.f;
		}

		return delay;
	}

	void _read(Orbital& obj, Message& msg) {
		uint cnt = msg.readSmall();
		sections.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			if(sections[i] is null)
				@sections[i] = OrbitalSection();
			msg >> sections[i];
		}
		
		if(core is null && sections.length != 0) {
			@core = sections[0];

			auto@ type = core.type;
			@node = cast<OrbitalNode>(bindNode(obj, "OrbitalNode"));
			if(node !is null)
				node.establish(obj, type.id);

			if(type.strategicIcon.valid) {
				@icon = StrategicIconNode();
				if(type.strategicIcon.sheet !is null)
					icon.establish(obj, type.iconSize, type.strategicIcon.sheet, type.strategicIcon.index);
				else if(type.strategicIcon.mat !is null)
					icon.establish(obj, type.iconSize, type.strategicIcon.mat);
				if(obj.region !is null)
					obj.region.addStrategicIcon(STRATEGIC_RING, obj, icon);
			}
		}
		msg >> contestion;
		msg >> disabled;
		msg >> master;
	}

	void _readHP(Orbital& obj, Message& msg) {
		msg >> Health;
		msg >> MaxHealth;
		msg >> Armor;
		msg >> MaxArmor;
		msg >> DR;
		msg >> DPS;
	}

	void syncInitial(Orbital& obj, Message& msg) {
		_read(obj, msg);
		_readHP(obj, msg);
		obj.readResources(msg);
		obj.readOrbit(msg);
		obj.readStatuses(msg);
		obj.readMover(msg);

		if(msg.readBit()) {
			if(!obj.hasConstruction)
				obj.activateConstruction();
			obj.readConstruction(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasLeaderAI)
				obj.activateLeaderAI();
			obj.readLeaderAI(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasAbilities)
				obj.activateAbilities();
			obj.readAbilities(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasCargo)
				obj.activateCargo();
			obj.readCargo(msg);
		}
	}

	void syncDelta(Orbital& obj, Message& msg, double tDiff) {
		if(msg.readBit())
			_read(obj, msg);
		if(msg.readBit())
			_readHP(obj, msg);
		if(msg.readBit())
			obj.readOrbit(msg);
		if(msg.readBit())
			obj.readResourceDelta(msg);
		if(msg.readBit()) {
			if(!obj.hasConstruction)
				obj.activateConstruction();
			obj.readConstructionDelta(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasLeaderAI)
				obj.activateLeaderAI();
			obj.readLeaderAIDelta(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasAbilities)
				obj.activateAbilities();
			obj.readAbilityDelta(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasCargo)
				obj.activateCargo();
			obj.readCargoDelta(msg);
		}
		if(msg.readBit())
			obj.readStatusDelta(msg);
		if(msg.readBit())
			obj.readOrbitDelta(msg);
		if(msg.readBit())
			obj.readMoverDelta(msg);
	}

	void syncDetailed(Orbital& obj, Message& msg, double tDiff) {
		_read(obj, msg);
		_readHP(obj, msg);
		obj.readResources(msg);
		obj.readOrbit(msg);
		obj.readStatuses(msg);
		obj.readMover(msg);

		if(msg.readBit()) {
			if(!obj.hasConstruction)
				obj.activateConstruction();
			obj.readConstruction(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasLeaderAI)
				obj.activateLeaderAI();
			obj.readLeaderAI(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasAbilities)
				obj.activateAbilities();
			obj.readAbilities(msg);
		}
		if(msg.readBit()) {
			if(!obj.hasCargo)
				obj.activateCargo();
			obj.readCargo(msg);
		}
	}
};
