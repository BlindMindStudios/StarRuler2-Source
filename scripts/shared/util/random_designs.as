from util.design_designer import DesignType, autoSupportNames, autoFlagNames;
import util.design_export;
import designs;

export DesignType;
export Designer;
export autoSupportNames, autoFlagNames;

import int getTraitID(const string&) from "traits";

const array<double> DIRWEIGHT = {1.0, 0.2, 1.0, 1.0, 0.2, 1.0};

tidy class SubsystemData {
	int id = 0;
	int defId = -1;
	array<vec2u> hexes;
	int rotation = -1;
	vec2u core;
	int fillerCount = 0;

	void set_def(const SubsystemDef@ def) {
		defId = def.index;
	}

	const SubsystemDef@ get_def() {
		return getSubsystemDef(defId);
	}
};

tidy class HexData {
	bool marked = false;
	bool cleared = false;
	int freeAdj = 6;
	int markedAdj = 0;

	//SubsystemData@ subsys;
	int subsysId = -1;
	const ModuleDef@ module;

	//Clear new data in clear() below

	SubsystemData@ subsys(Designer& dsg) {
		if(subsysId == -1)
			return null;
		return dsg.subsystems[subsysId];
	}
};

enum HexMask {
	HM_DownLeft = 0x1,
	HM_Down = 0x2,
	HM_DownRight = 0x4,
	HM_UpRight = 0x8,
	HM_Up = 0x10,
	HM_UpLeft = 0x20,

	HM_ALL = HM_DownLeft | HM_Down | HM_DownRight | HM_UpRight | HM_Up | HM_UpLeft,
};

tidy class Designer {
	DesignType type;
	Empire@ owner;
	int size;
	int hexLimit;
	string className;
	bool randomHull = false;

	const Design@ baseOffDesign;
	const SubsystemDef@ baseOffSubsystem;

	vec2u gridSize;
	vec2u center;

	array<HexData> hexes;
	array<SubsystemData@> subsystems;
	array<vec2u> markedHexes;
	array<const SubsystemDef@> applied;

	array<Distributor@> composition;
	double totalFrequency = 0;

	Tag@ primaryArmor;

	Designer(uint type, int size, Empire@ emp, const string& className = "Combat", bool compose = true) {
		@this.owner = emp;
		this.type = DesignType(type);
		this.size = max(size, 1);
		this.className = className;
		@primaryArmor = tag("PrimaryArmor");

		gridSize = vec2u(getDesignGridSize(hulltag, size));
		center = vec2u(gridSize.x / 2, gridSize.y / 2 - 1);

		switch(type) {
			case DT_Support:
				hexLimit = 60;
				if(compose)
					composeSupport();
			break;
			case DT_Satellite:
				hexLimit = 70;
				if(compose)
					composeSatellite();
			break;
			case DT_Flagship:
				hexLimit = 128;
				if(compose)
					composeFlagship();
			break;
			case DT_Station:
				hexLimit = 160;
				if(compose)
					composeStation();
			break;
		}
	}

	void composeSupport() {
		composition.length = 0;

		composition.insertLast(Internal(tag("ControlCore"), 0.04, 0.06));
		composition.insertLast(Weapon(tag("Weapon"), 0.40, 0.50));
		composition.insertLast(Exhaust(tag("Engine"), 0.35, 0.40));

		composition.insertLast(Chance(0.25, Exhaust(tag("SecondaryThrust"), 0.05, 0.20)));
		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_DownLeft | HM_UpLeft | HM_Down | HM_Up, 1, 2));
	}

	void composeSatellite() {
		composition.length = 0;

		composition.insertLast(Internal(tag("ControlCore"), 0.04, 0.06));
		composition.insertLast(Internal(tag("ControlCore"), 0.04, 0.06));
		composition.insertLast(Weapon(tag("Weapon"), 0.40, 0.50, allDirections = true));
		composition.insertLast(Weapon(tag("Weapon"), 0.40, 0.50, allDirections = true));

		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_ALL, 1, 2));
	}

	void composeFlagship(bool haveSupport = true, bool tryFTL = true, bool supply = true, bool weapons = true, bool power = true, bool clear = true) {
		if(clear)
			composition.length = 0;

		//Weapons for flagships
		if(weapons) {
			composition.insertLast(Weapon(tag("Weapon") & tag("MainDPS"), 0.15, 0.25));
			composition.insertLast(Weapon(tag("Weapon") & tag("MainDPS"), 0.15, 0.25));
			composition.insertLast(Chance(0.25, Weapon(tag("Weapon") & tag("SecondaryDPS"), 0.075, 0.15)));
		}

		//Engine pair
		composition.insertLast(Exhaust(tag("Engine") & tag("GivesThrust"), 0.25, 0.35));

		//Control core
		if(owner.hasTrait(getTraitID("Ancient"))) {
			composition.insertLast(Internal(subsystem("AncientCore"), 0.025, 0.05));
			composition.insertLast(Chance(0.5, Internal(subsystem("AncientCore"), 0.025, 0.05)));

			if(power)
				composition.insertLast(Chance(0.2, Internal(tag("IsReactor"), 0.01, 0.03)));
		}
		else {
			composition.insertLast(Internal(tag("ControlCore"), 0.025, 0.05));
			composition.insertLast(Chance(0.5, Internal(tag("ControlCore"), 0.025, 0.05)));

			if(power)
				composition.insertLast(Internal(tag("IsReactor"), 0.04, 0.06));
		}

		//Shrine if needed
		if(owner.hasTrait(getTraitID("Devout")))
			composition.insertLast(Internal(tag("Prayer"), 0.05, 0.10));

		//Secondary modules
		composition.insertLast(Chance(0.5, Internal(tag("SecondaryDefense"), 0.075, 0.15)));

		if(tryFTL)
			composition.insertLast(Internal(tag("Hyperengine"), 0.10, 0.18));

		if(supply)
			composition.insertLast(Filler(subsystem("SupplyModule"), 0.09, 0.13));

		if(haveSupport)
			composition.insertLast(Filler(subsystem("SupportCapModule"), 0.04, 0.14));

		//Armor
		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_DownLeft | HM_UpLeft | HM_Down | HM_Up, 1, 1));
		for(int i = 0; i < 1 + size / 400 && i < 4; ++i)
			composition.insertLast(Chance(0.33, ArmorLayer(tag("PrimaryArmor"), HM_DownLeft | HM_UpLeft, 1, 1)));
	}

	void composeStation(bool clear = true) {
		if(clear)
			composition.length = 0;

		composition.insertLast(Weapon(tag("Weapon") & tag("MainDPS"), 0.15, 0.25, allDirections = true));
		composition.insertLast(Weapon(tag("Weapon") & tag("MainDPS"), 0.15, 0.25, allDirections = true));
		composition.insertLast(Weapon(tag("Weapon") & tag("MainDPS"), 0.15, 0.25, allDirections = true));
		composition.insertLast(Chance(0.33, Weapon(tag("Weapon") & tag("SecondaryDPS"), 0.075, 0.15)));

		//Control core
		if(owner.hasTrait(getTraitID("Ancient"))) {
			composition.insertLast(Internal(subsystem("AncientCore"), 0.025, 0.05));
			composition.insertLast(Chance(0.5, Internal(subsystem("AncientCore"), 0.025, 0.05)));

			composition.insertLast(Chance(0.2, Internal(tag("IsReactor"), 0.01, 0.03)));
		}
		else {
			composition.insertLast(Internal(tag("ControlCore"), 0.025, 0.05));
			composition.insertLast(Chance(0.5, Internal(tag("ControlCore"), 0.025, 0.05)));

			composition.insertLast(Internal(tag("IsReactor"), 0.04, 0.06));
		}

		//Shrine if needed
		composition.insertLast(Internal(tag("Prayer"), 0.15, 0.20));

		composition.insertLast(Chance(0.5, Internal(tag("SecondaryDefense"), 0.075, 0.15)));
		composition.insertLast(Filler(subsystem("SupplyModule"), 0.09, 0.13));

		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_ALL, 1, 1));
		for(int i = 0; i < 1 + size / 400 && i < 4; ++i)
			composition.insertLast(Chance(0.33, ArmorLayer(tag("PrimaryArmor"), HM_ALL, 1, 1)));
	}

	void composeGate() {
		composition.length = 0;

		composition.insertLast(HorizSpan(tag("Gate"), 1.0, 1.0));
		composition.insertLast(Internal(tag("ControlCore"), 0.02, 0.03));
		composeStation(clear=false);
	}

	void composeSlipstream() {
		composition.length = 0;
		composition.insertLast(Exhaust(tag("Engine") & tag("GivesThrust"), 0.50, 0.50));
		composition.insertLast(Internal(tag("ControlCore"), 0.05, 0.05));
		composition.insertLast(Internal(tag("ControlCore"), 0.05, 0.05));
		composition.insertLast(Internal(tag("Slipstream"), 1.00, 1.00));

		//Shrine if needed
		if(owner.hasTrait(getTraitID("Devout")))
			composition.insertLast(Internal(tag("Prayer"), 0.15, 0.20));

		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_DownLeft | HM_UpLeft | HM_Down | HM_Up, 1, 1));
	}

	void composeMothership() {
		composition.length = 0;
		composition.insertLast(Internal(tag("ControlCore"), 0.2, 0.5));
		composition.insertLast(Internal(tag("ControlCore"), 0.2, 0.5));
		composition.insertLast(Applied(tag("Mothership")));
		composeFlagship(supply=false, power=false, clear=false);
		hexLimit = 225;
	}

	void composeScout() {
		composition.length = 0;

		composition.insertLast(Exhaust(tag("Engine") & tag("GivesThrust"), 0.80, 0.80));
		composition.insertLast(Internal(tag("ControlCore"), 0.05, 0.05));
		composition.insertLast(Internal(tag("Hyperengine"), 0.50, 0.50));

		//Shrine if needed
		if(owner.hasTrait(getTraitID("Devout")))
			composition.insertLast(Internal(tag("Prayer"), 0.15, 0.20));

		composition.insertLast(ArmorLayer(tag("PrimaryArmor"), HM_DownLeft | HM_UpLeft | HM_Down | HM_Up, 1, 1));
	}

	Tag@ tag(const string& value) {
		return Tag(this, value);
	}

	SubsystemFilter@ subsystem(const string& value) {
		return SubsystemFilter(getSubsystemDef(value));
	}

	vec2u flip(const vec2u& p) {
		if(p.x % 2 == center.x % 2)
			return vec2u(p.x, center.y * 2 - p.y);
		else if(center.x % 2 == 0)
			return vec2u(p.x, center.y * 2 - p.y - 1);
		else
			return vec2u(p.x, center.y * 2 - p.y + 1);
	}

	HexGridAdjacency flip(uint d) {
		switch(d) {
			case HEX_Up:
				return HEX_Down;
			case HEX_UpRight:
				return HEX_DownRight;
			case HEX_DownRight:
				return HEX_UpRight;
			case HEX_Down:
				return HEX_Up;
			case HEX_DownLeft:
				return HEX_UpLeft;
			case HEX_UpLeft:
				return HEX_DownLeft;
		}
		return HEX_Up;
	}

	HexGridAdjacency reverse(uint d) {
		switch(d) {
			case HEX_Up:
				return HEX_Down;
			case HEX_UpRight:
				return HEX_DownLeft;
			case HEX_DownRight:
				return HEX_UpLeft;
			case HEX_Down:
				return HEX_Up;
			case HEX_DownLeft:
				return HEX_UpRight;
			case HEX_UpLeft:
				return HEX_DownRight;
		}
		return HEX_Up;
	}

	uint mask(uint d) {
		return 1<<d;
	}

	bool valid(const vec2u& p) {
		return p.x < gridSize.x && p.y < gridSize.y;
	}

	HexData@ get_hex(const vec2u& pos) {
		return hexes[pos.y * gridSize.x + pos.x];
	}

	vec2u getFreeHex() {
		for(uint tries = 0; tries < 10; ++tries) {
			vec2u offPos;

			if(tries < 9) {
				//Simple mechanism
				offPos = markedHexes[randomi(0, markedHexes.length-1)];
				if(hex[offPos].freeAdj == 0)
					continue;
			}
			else {
				//Detailed mechanism
				double sides = 0.0;
				for(uint i = 0, cnt = markedHexes.length; i < cnt; ++i) {
					auto@ dat = hex[markedHexes[i]];
					sides += dat.freeAdj;
					if(sides == 0 || randomd() < double(dat.freeAdj) / sides)
						offPos = markedHexes[i];
				}
			}

			vec2u newPos;
			double dirs = 0.0;
			for(uint d = 0; d < 6; ++d) {
				vec2u pos = offPos;
				if(!advanceHexPosition(pos, gridSize, HexGridAdjacency(d)))
					continue;
				if(hex[pos].marked)
					continue;
				double w = DIRWEIGHT[d];
				dirs += w;
				if(randomd() < w / dirs)
					newPos = pos;
			}

			return newPos;
		}

		return vec2u();
	}

	void markHex(const vec2u& pos) {
		auto@ data = hex[pos];

		data.marked = true;
		markedHexes.insertLast(pos);

		//Check for free adjacents
		for(uint d = 0; d < 6; ++d) {
			vec2u otherPos = pos;
			if(!advanceHexPosition(otherPos, gridSize, HexGridAdjacency(d))) {
				data.freeAdj -= 1;
				continue;
			}

			auto@ otherData = hex[otherPos];
			otherData.freeAdj -= 1;
		}
	}

	void unmarkHex(const vec2u& pos) {
		auto@ data = hex[pos];

		data.marked = false;
		markedHexes.removeAt(markedHexes.find(pos));

		for(uint d = 0; d < 6; ++d) {
			vec2u otherPos = pos;
			if(!advanceHexPosition(otherPos, gridSize, HexGridAdjacency(d)))
				continue;
			auto@ otherData = hex[otherPos];
			otherData.markedAdj -= 1;
		}
	}

	void markInterior() {
		markedHexes.reserve(hexLimit);
		markHex(center);

		//Interior bubble
		while(markedHexes.length < uint(hexLimit)) {
			uint tries = 0;

			vec2u pos = getFreeHex();
			if(hex[pos].marked)
				break;

			//Mark current
			markHex(pos);

			//Mark flipped version
			if(markedHexes.length < uint(hexLimit)) {
				vec2u flipPos = flip(pos);
				if(valid(flipPos) && pos != flipPos)
					markHex(flipPos);
			}
		}

		//Record how many marked hexes adjacent
		for(uint i = 0, cnt = markedHexes.length; i < cnt; ++i) {
			vec2u pos = markedHexes[i];
			for(uint d = 0; d < 6; ++d) {
				vec2u otherPos = pos;
				if(!advanceHexPosition(otherPos, gridSize, HexGridAdjacency(d)))
					continue;

				auto@ otherData = hex[otherPos];
				otherData.markedAdj += 1;
			}
		}
	}

	SubsystemData@ addSubsystem(const SubsystemDef@ def) {
		if(def is null)
			return null;
		if(def.hasTag(ST_NonContiguous)) {
			for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
				if(subsystems[i].def is def)
					return subsystems[i];
			}
		}

		SubsystemData data;
		data.id = subsystems.length;
		@data.def = def;
		subsystems.insertLast(data);
		return data;
	}

	void addHex(SubsystemData@ subsys, const vec2u& pos, const ModuleDef@ module = null) {
		if(!valid(pos))
			return;
		if(module is null)
			@module = subsys.def.defaultModule;

		auto@ hdata = hex[pos];
		hdata.subsysId = subsys.id;
		@hdata.module = module;
		subsys.hexes.insertLast(pos);

		if(hdata.marked)
			unmarkHex(pos);
	}

	void addApplied(const SubsystemDef@ def) {
		if(def !is null)
			applied.insertLast(def);
	}

	void primeSys(const SubsystemDef@ def, double frequency) {
		if(def.hasTag(ST_HighPowerUse))
			composition.insertLast(Internal(tag("IsReactor"), frequency * 0.2, frequency * 0.3));
		if(def.hasTag(ST_RangeForRaid))
			composition.insertLast(Internal(subsystem("SupportAmmoStorage"), frequency * 0.1, frequency * 0.25));
	}

	void clear() {
		if(hexes.length != 0) {
			hexes.length = gridSize.x * gridSize.y;
			for(uint i = 0, cnt = hexes.length; i < cnt; ++i) {
				auto@ dat = hexes[i];
				dat.marked = false;
				dat.cleared = false;
				dat.freeAdj = 6;
				dat.markedAdj = 0;
				dat.subsysId = -1;
				@dat.module = null;
			}
		}
		else {
			hexes.length = gridSize.x * gridSize.y;
		}

		subsystems.length = 0;
		markedHexes.length = 0;
		applied.length = 0;
	}

	const Design@ design(uint maxTries = 128) {
		for(uint i = 0; i < maxTries; ++i) {
			const Design@ dsg = _design();
			if(dsg is null)
				continue;
			/*if(dsg.errorCount != 0) {*/
			/*	print("-- "+owner.name);*/
			/*	for(uint i = 0, cnt = dsg.errorCount; i < cnt; ++i) {*/
			/*		print("err: "+dsg.errors[i].text);*/
			/*	}*/
			/*}*/
			if(i < 16) {
				if(dsg.errorCount != 0)
					continue;
			}
			else {
				if(dsg.hasFatalErrors())
					continue;
			}
			return dsg;
		}
		return null;
	}

	const Design@ _design() {
		//Clear old stuffs
		clear();

		//Mark the area that we're going to use for the interior
		if(baseOffDesign !is null) {
			for(uint i = 0, cnt = baseOffDesign.subsystemCount; i < cnt; ++i) {
				auto@ sys = baseOffDesign.subsystems[i];
				if(sys.type is baseOffSubsystem) {
					auto@ markSys = addSubsystem(sys.type);
					markSys.core = sys.core;
					for(uint n = 0, ncnt = sys.hexCount; n < ncnt; ++n)
						addHex(markSys, sys.hexagon(n));
				}
				else if(sys.type.hasTag(ST_HasInternals)) {
					for(uint n = 0, ncnt = sys.hexCount; n < ncnt; ++n)
						markHex(sys.hexagon(n));
				}
			}
			hexLimit = markedHexes.length;
		}
		else {
			markInterior();
		}

		//Use all distributors
		totalFrequency = 0;
		uint compLength = composition.length;
		for(uint i = 0; i < composition.length; ++i) {
			auto@ comp = composition[i];
			comp.prime();
			if(comp.type !is null && comp.frequency != 0)
				primeSys(comp.type, comp.frequency);
		}
		for(uint i = 0, cnt = composition.length; i < cnt; ++i) {
			if(composition[i].type !is null)
				totalFrequency += composition[i].frequency;
		}
		for(uint i = 0, cnt = composition.length; i < cnt; ++i) {
			if(composition[i].type !is null)
				composition[i].distribute(this);
		}
		composition.length = compLength;

		//Fill as of yet unmarked hexes with armor
		{
			auto@ armor = addSubsystem(primaryArmor.choose());
			for(uint i = 0, cnt = markedHexes.length; i < cnt; ++i) {
				vec2u pos = markedHexes[0];

				SubsystemData@ extendTo;
				double checks = 0.0;
				for(uint d = 0; d < 6; ++d) {
					vec2u otherPos = pos;
					if(!advanceHexPosition(otherPos, gridSize, HexGridAdjacency(d)))
						continue;

					auto@ dat = hex[otherPos];
					auto@ subsys = dat.subsys(this);
					if(subsys is null)
						continue;

					double w = 1.0;
					if(subsys.def.hasTag(ST_BadFiller))
						w /= 4.0;
					if(subsys.def.hasTag(ST_PrimaryArmor))
						w /= 10.0;
					if(subsys.fillerCount != 0)
						w /= double(subsys.fillerCount);

					checks += w;
					if(randomd() < w / checks)
						@extendTo = subsys;
				}

				if(extendTo !is null) {
					addHex(extendTo, pos);
					extendTo.fillerCount += 1;
				}
				else
					addHex(armor, pos);
			}
		}

		//Create the design
		DesignDescriptor desc;
		desc.size = size;
		desc.gridSize = vec2u(gridSize);
		@desc.owner = owner;
		desc.className = className;

		if(type == DT_Support)
			desc.name = autoSupportNames[randomi(0,autoSupportNames.length-1)];
		else
			desc.name = autoFlagNames[randomi(0,autoFlagNames.length-1)];

		for(uint i = 0, cnt = applied.length; i < cnt; ++i)
			desc.applySubsystem(applied[i]);
		
		for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
			auto@ subsys = subsystems[i];

			desc.addSystem(subsys.def);
			if(subsys.rotation != -1)
				desc.setDirection(quaterniond_fromAxisAngle(vec3d_up(), hexToRadians(HexGridAdjacency(subsys.rotation))) * vec3d_front());

			for(uint j = 0, jcnt = subsys.hexes.length(); j < jcnt; ++j) {
				vec2u pos = subsys.hexes[j];
				HexData@ hdata = hex[pos];

				desc.addHex(pos, hdata.module);
			}
		}

		if(randomHull && owner.shipset !is null) {
			string hullTag = hulltag;
			uint hullCount = 0;
			for(uint i = 0, cnt = owner.shipset.hullCount; i < cnt; ++i) {
				const Hull@ hull = owner.shipset.hulls[i];

				//Check if it matches the tag
				if(!hull.hasTag(hullTag))
					continue;
				if(hull.special)
					continue;

				//Make sure we can use this hull
				if(hull.minSize >= 0 && hull.minSize > desc.size)
					continue;
				if(hull.maxSize >= 0 && hull.maxSize < desc.size)
					continue;

				hullCount += 1;
				if(randomd() < 1.0 / double(hullCount))
					@desc.hull = hull;
			}

			if(desc.hull is null)
				@desc.hull = getBestHull(desc, hulltag, owner);
		}
		else {
			@desc.hull = getBestHull(desc, hulltag, owner);
		}

		return makeDesign(desc);
	}

	string get_hulltag() {
		string hullTag = "Flagship";
		switch(type) {
			case DT_Support: hullTag = "Support"; break;
			case DT_Satellite: hullTag = "Satellite"; break;
			case DT_Flagship: hullTag = "Flagship"; break;
			case DT_Station: hullTag = "Station"; break;
		}
		return hullTag;
	}

	vec2u markedRandom() {
		if(markedHexes.length == 0)
			return vec2u(uint(-1), uint(-1));
		return markedHexes[randomi(0, markedHexes.length-1)];
	}

	vec2u markedInternal() {
		double totalWeight = 0;
		vec2u chosen;
		for(uint i = 0, cnt = markedHexes.length; i < cnt; ++i) {
			vec2u pos = markedHexes[i];
			auto@ dat = hex[pos];

			double w = 1.0 + double(6-dat.freeAdj);
			double dist = abs(pos.x - center.x) + abs(pos.y - center.y);
			w /= (max(dist, 1.0) / 100.0);

			totalWeight += w;
			if(randomd() < w / totalWeight)
				chosen = pos;
		}
		return chosen;
	}

	vec2u markedFromDirection(uint directions) {
		vec2u found(uint(-1), uint(-1));
		double checked = 0.0;

		if(directions & HM_DownLeft != 0) {
			uint x = gridSize.x-1;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior) {
						break;
					}
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_DownLeft)));
			}
		}

		if(directions & HM_UpLeft != 0) {
			uint x = gridSize.x-1;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior)
						break;
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_UpLeft)));
			}
		}

		if(directions & HM_DownRight != 0) {
			uint x = 0;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior) {
						break;
					}
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_DownRight)));
			}
		}

		if(directions & HM_UpRight != 0) {
			uint x = 0;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior)
						break;
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_UpRight)));
			}
		}

		if(directions & HM_Up != 0) {
			uint y = gridSize.y-1;
			for(uint x = 0; x < gridSize.x; ++x) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior)
						break;
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_Up)));
			}
		}

		if(directions & HM_Down != 0) {
			uint y = 0;
			for(uint x = 0; x < gridSize.x; ++x) {
				vec2u pos(x, y);
				do {
					auto@ data = hex[pos];
					if(data.subsysId != -1 && !data.subsys(this).def.passExterior)
						break;
					if(data.marked) {
						checked += 1.0;
						if(randomd() < 1.0 / checked)
							found = pos;
						break;
					}
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_Down)));
			}
		}

		return found;
	}

	void clearDir(const vec2u& pos, uint dir) {
		vec2u clearPos = pos;
		bool shouldClear = true;
		while(advanceHexPosition(clearPos, gridSize, HexGridAdjacency(dir))) {
			auto@ dat = hex[clearPos];
			if(dat.marked || (dat.subsysId != -1 && !dat.subsys(this).def.passExterior)) {
				shouldClear = false;
				break;
			}
		}
		if(shouldClear) {
			clearPos = pos;
			while(advanceHexPosition(clearPos, gridSize, HexGridAdjacency(dir))) {
				auto@ dat = hex[clearPos];
				dat.cleared = true;
			}
		}
	}

	bool isExterior(const vec2u& fromPosition, uint directions) {
		vec2u offPos = fromPosition;
		for(uint d = 0; d < 6; ++d) {
			vec2u pos = offPos;
			if((1<<d) & directions == 0)
				continue;

			if(!advanceHexPosition(pos, gridSize, HexGridAdjacency(d)))
				return true;

			auto@ otherData = hex[pos];
			if(!otherData.marked)
				return true;
			if(otherData.subsysId == -1 || otherData.subsys(this).def.passExterior)
				return true;
		}
		return false;
	}

	void clearDirections(const vec2u& pos, uint directions) {
		if(directions & HM_DownLeft != 0)
			clearDir(pos, HEX_DownLeft);
		if(directions & HM_DownRight != 0)
			clearDir(pos, HEX_DownRight);
		if(directions & HM_Down != 0)
			clearDir(pos, HEX_Down);
		if(directions & HM_UpLeft != 0)
			clearDir(pos, HEX_UpLeft);
		if(directions & HM_UpRight != 0)
			clearDir(pos, HEX_UpRight);
		if(directions & HM_Up != 0)
			clearDir(pos, HEX_Up);
	}

	void addCoating(SubsystemData@ subsys, uint directions) {
		array<vec2u> coated;

		if(directions & HM_DownLeft != 0) {
			uint x = gridSize.x-1;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_DownLeft)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}

		if(directions & HM_UpLeft != 0) {
			uint x = gridSize.x-1;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_UpLeft)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}

		if(directions & HM_DownRight != 0) {
			uint x = 0;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_DownRight)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}

		if(directions & HM_UpRight != 0) {
			uint x = 0;
			for(uint y = 0; y < gridSize.y; ++y) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_UpRight)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}

		if(directions & HM_Down != 0) {
			uint y = 0;
			for(uint x = 0; x < gridSize.x; ++x) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_Down)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}

		if(directions & HM_Up != 0) {
			uint y = gridSize.y-1;
			for(uint x = 0; x < gridSize.x; ++x) {
				vec2u pos(x, y);
				vec2u prevPos = pos;
				bool found = false;
				do {
					auto@ data = hex[pos];
					if(data.subsysId == subsys.id && coated.find(pos) != -1)
						break;
					if(data.marked) {
						found = true;
						break;
					}
					if(data.subsysId != -1) {
						if(!data.subsys(this).def.passExterior)
							found = true;
						break;
					}
					prevPos = pos;
				}
				while(advanceHexPosition(pos, gridSize, HexGridAdjacency(HEX_Up)));

				if(found && !hex[prevPos].cleared) {
					addHex(subsys, prevPos);
					coated.insertLast(prevPos);
				}
			}
		}
	}

	int snake(SubsystemData@ subsys, uint directions, const vec2u& fromPosition) {
		int snaked = 0;
		vec2u offPos = fromPosition;
		while(true) {
			bool found = false;
			for(uint d = 0; d < 6; ++d) {
				vec2u pos = offPos;
				if(!advanceHexPosition(pos, gridSize, HexGridAdjacency(d)))
					continue;

				if((1<<d) & directions == 0)
					continue;

				auto@ otherData = hex[pos];
				if(!otherData.marked && otherData.subsysId == -1)
					return snaked;

				addHex(subsys, pos);

				offPos = pos;
				found = true;
				snaked += 1;
				break;
			}
			if(!found)
				break;
		}

		return snaked;
	}

	bool spread(SubsystemData@ subsys, double freeWeight = 0.0, uint directions = HM_ALL) {
		for(uint tries = 0; tries < 10; ++tries) {
			vec2u offPos;
			if(tries < 5) {
				//Simple mechanism
				offPos = subsys.hexes[randomi(0, subsys.hexes.length-1)];
				if(hex[offPos].markedAdj == 0)
					continue;
			}
			else {
				//Detailed mechanism
				double sides = 0.0;
				for(uint i = 0, cnt = subsys.hexes.length; i < cnt; ++i) {
					auto@ dat = hex[subsys.hexes[i]];
					sides += dat.markedAdj;
					if(sides == 0 || randomd() < double(dat.markedAdj) / sides)
						offPos = subsys.hexes[i];
				}
			}

			double totalWeight = 0.0;
			vec2u choosePos;
			for(uint d = 0; d < 6; ++d) {
				vec2u pos = offPos;
				if(!advanceHexPosition(pos, gridSize, HexGridAdjacency(d)))
					continue;

				if((1<<d) & directions == 0)
					continue;

				auto@ otherData = hex[pos];
				if(!otherData.marked)
					continue;

				double w = 1.0 + freeWeight * double(otherData.freeAdj);
				totalWeight += w;
				if(randomd() < w / totalWeight)
					choosePos = pos;
			}

			if(totalWeight != 0) {
				addHex(subsys, choosePos);
				return true;
			}
		}

		return false;
	}

	SubsystemData@ dupeMirror(SubsystemData@ subsys) {
		vec2u core = flip(subsys.core);
		if(!valid(core) || !hex[core].marked)
			return null;

		auto@ newSys = addSubsystem(subsys.def);
		newSys.core = flip(subsys.core);
		newSys.rotation = flip(subsys.rotation);
		for(uint i = 0, cnt = subsys.hexes.length; i < cnt; ++i) {
			auto@ old = hex[subsys.hexes[i]];

			vec2u pos = flip(subsys.hexes[i]);
			if(!valid(pos))
				continue;
			if(!hex[pos].marked)
				continue;

			addHex(newSys, pos, old.module);
		}

		return newSys;
	}

	bool isFree(const vec2u& pos, uint d) {
		vec2u checkPos = pos;
		while(advanceHexPosition(checkPos, gridSize, HexGridAdjacency(d))) {
			auto@ dat = hex[checkPos];
			if(dat.marked)
				return false;
			if(dat.subsysId != -1) {
				if(!dat.subsys(this).def.passExterior)
					return false;
			}
		}
		return true;
	}

	int getFreeRotation(const vec2u& pos, bool prioritize = true) {
		int dir = -1;
		double count = 0;

		if(isFree(pos, HEX_UpRight)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_UpRight;
		}

		if(isFree(pos, HEX_DownRight)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_DownRight;
		}

		if(prioritize && dir != -1)
			return dir;

		if(isFree(pos, HEX_Up)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_Up;
		}

		if(isFree(pos, HEX_Down)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_Down;
		}

		if(prioritize && dir != -1)
			return dir;

		if(isFree(pos, HEX_UpLeft)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_UpLeft;
		}

		if(isFree(pos, HEX_DownLeft)) {
			count += 1.0;
			if(randomd() < 1.0 / count)
				dir = HEX_DownLeft;
		}

		return dir;
	}
};

tidy class Filter {
	void compute() {}
	bool filter(const SubsystemDef& def) const { return true; }
	const SubsystemDef@ choose() { return null; }
	void clear() {}
};

tidy class Tag : Filter {
	SubsystemTag tag;
	array<const SubsystemDef@> types;
	bool computed = false;
	string hullTag;
	Empire@ owner;

	Tag(Designer& dsg, const string& tag) {
		this.tag = getSubsystemTag(tag);
		hullTag = dsg.hulltag;
		@owner = dsg.owner;
	}

	const SubsystemDef@ choose() {
		compute();
		if(types.length == 0)
			return null;
		return types[randomi(0, types.length-1)];
	}

	void compute() {
		if(computed)
			return;

		computed = true;
		for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			auto@ def = getSubsystemDef(i);
			if(!def.hasTag(tag))
				continue;
			if(!def.hasHullTag(hullTag))
				continue;
			if(def.hasTag(ST_SpecialCost))
				continue;
			if(def.hasTag(ST_Disabled))
				continue;
			if(!owner.isUnlocked(def))
				continue;
			if(def.hasTag(ST_RaceSpecial) && !owner.major)
				continue;
			types.insertLast(def);
		}
	}

	bool filter(const SubsystemDef& def) const {
		if(computed)
			return types.find(def) != -1;
		return def.hasTag(tag);
	}

	Tag& opAnd(Filter& other) {
		compute();
		for(uint i = 0, cnt = types.length; i < cnt; ++i) {
			if(!other.filter(types[i])) {
				types.removeAt(i);
				--i; --cnt;
			}
		}
		other.clear();
		return this;
	}
};

tidy class SubsystemFilter : Filter {
	const SubsystemDef@ type;
	SubsystemFilter(const SubsystemDef@ def) {
		@this.type = def;
	}

	bool filter(const SubsystemDef& def) const {
		return def is type;
	}

	const SubsystemDef@ choose() {
		return type;
	}
};

tidy class Distributor {
	double frequency = 1.0;
	const SubsystemDef@ type;

	void prime() {
	}
	void distribute(Designer& dsg) {
	}
};

tidy class Chance : Distributor {
	double chance;
	Distributor@ inner;

	Chance(double chance, Distributor@ inner) {
		this.chance = chance;
		@this.inner = inner;
	}

	void prime() {
		if(randomd() < chance) {
			inner.prime();
			@type = inner.type;
			frequency = inner.frequency;
		}
		else {
			@type = null;
			frequency = 0.0;
		}
	}

	void distribute(Designer& dsg) {
		if(frequency == 0)
			return;
		inner.distribute(dsg);
	}
};

tidy class Weapon : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;
	bool mirror;
	bool allDirections;

	double minFreq = 0;
	double maxFreq = 0;

	Weapon(Filter@ filter, double minFreq, double maxFreq, bool mirror = true, bool allDirections = false) {
		@this.filter = filter;
		this.mirror = mirror;
		this.minFreq = minFreq;
		this.maxFreq = maxFreq;
		this.allDirections = allDirections;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		frequency = randomd(minFreq, maxFreq);
		if(type is null)
			frequency = 0.0;
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;
		double pct = frequency / dsg.totalFrequency;
		if(mirror)
			pct *= 0.5;

		int hexes = pct * double(dsg.hexLimit);
		bool limitArc = type.hasTag(ST_HexLimitArc);

		vec2u core;
		if(allDirections)
			core = dsg.markedFromDirection(HM_ALL);
		else if(!limitArc || randomd() < 0.3)
			core = dsg.markedFromDirection(HM_DownLeft | HM_UpLeft | HM_Down | HM_Up);
		else
			core = dsg.markedFromDirection(HM_DownLeft | HM_UpLeft);

		if(!dsg.valid(core))
			return;

		auto@ subsys = dsg.addSubsystem(type);
		subsys.core = core;

		if(!dsg.valid(subsys.core))
			return;

		subsys.rotation = dsg.getFreeRotation(subsys.core, prioritize=!allDirections);

		if(limitArc)
			dsg.clearDirections(subsys.core, HM_ALL);
		else
			dsg.clearDirections(subsys.core, dsg.mask(subsys.rotation));

		//Spread the subsystem
		dsg.addHex(subsys, subsys.core, subsys.def.coreModule);
		for(int i = 0; i < hexes; ++i) {
			if(!dsg.spread(subsys, freeWeight=2.0))
				break;
		}

		if(mirror) {
			auto@ dupe = dsg.dupeMirror(subsys);
			if(dupe !is null) {
				if(limitArc)
					dsg.clearDirections(dupe.core, HM_ALL);
				else
					dsg.clearDirections(dupe.core, dsg.mask(dupe.rotation));
			}
		}
	}
};

tidy class Exhaust : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;
	bool mirror;

	double minFreq = 0;
	double maxFreq = 0;

	Exhaust(Filter@ filter, double minFreq, double maxFreq, bool mirror = true) {
		@this.filter = filter;
		this.mirror = mirror;
		this.minFreq = minFreq;
		this.maxFreq = maxFreq;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		frequency = randomd(minFreq, maxFreq);
		if(type is null)
			frequency = 0.0;
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;

		double pct = frequency / dsg.totalFrequency;
		if(mirror)
			pct *= 0.5;

		int hexes = pct * double(dsg.hexLimit);

		vec2u core = dsg.markedFromDirection(HM_DownRight);// | HM_UpRight);
		if(!dsg.valid(core))
			return;

		auto@ subsys = dsg.addSubsystem(type);
		subsys.core = core;
		dsg.clearDirections(subsys.core, HM_DownLeft | HM_UpLeft);

		//Spread the subsystem
		dsg.addHex(subsys, subsys.core, subsys.def.coreModule);
		for(int i = 0; i < hexes; ++i) {
			if(!dsg.spread(subsys, freeWeight=2.0))
				break;
		}

		if(mirror) {
			auto@ dupe = dsg.dupeMirror(subsys);
			if(dupe !is null)
				dsg.clearDirections(dupe.core, HM_DownLeft | HM_UpLeft);
		}
	}
};

tidy class Internal : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;

	double minFreq = 0;
	double maxFreq = 0;

	Internal(Filter@ filter, double minFreq, double maxFreq) {
		@this.filter = filter;
		this.minFreq = minFreq;
		this.maxFreq = maxFreq;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		frequency = randomd(minFreq, maxFreq);
		if(type is null)
			frequency = 0.0;
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;

		double pct = frequency / dsg.totalFrequency;
		int hexes = pct * double(dsg.hexLimit);

		auto@ subsys = dsg.addSubsystem(type);
		subsys.core = dsg.markedInternal();

		//Spread the subsystem
		dsg.addHex(subsys, subsys.core, subsys.def.coreModule);
		for(int i = 0; i < hexes; ++i) {
			if(!dsg.spread(subsys, freeWeight=-0.1))
				break;
		}
	}
};

tidy class Applied : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;

	Applied(Filter@ filter) {
		@this.filter = filter;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;
		dsg.addApplied(type);
	}
};

tidy class HorizSpan : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;

	double minFreq = 0;
	double maxFreq = 0;

	HorizSpan(Filter@ filter, double minFreq, double maxFreq) {
		@this.filter = filter;
		this.minFreq = minFreq;
		this.maxFreq = maxFreq;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		frequency = randomd(minFreq, maxFreq);
		if(type is null)
			frequency = 0.0;
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;

		double pct = frequency / dsg.totalFrequency;

		auto@ subsys = dsg.addSubsystem(type);
		subsys.core = dsg.markedInternal();

		//Spread the subsystem
		dsg.addHex(subsys, subsys.core, subsys.def.coreModule);

		int snaked = 0;
		snaked += dsg.snake(subsys, HM_UpLeft|HM_DownLeft, subsys.core);
		snaked += dsg.snake(subsys, HM_UpRight|HM_DownRight, subsys.core);

		int hexes = pct * double(dsg.hexLimit) - snaked;
		for(int i = 0; i < hexes; ++i) {
			if(!dsg.spread(subsys, freeWeight=-0.1))
				break;
		}

		//Clear outside of all hexes
		for(uint i = 0, cnt = subsys.hexes.length; i < cnt; ++i) {
			if(dsg.isExterior(subsys.hexes[i], HM_DownLeft)) {
				dsg.clearDirections(subsys.hexes[i], HM_DownLeft);
				break;
			}
			if(dsg.isExterior(subsys.hexes[i], HM_UpLeft)) {
				dsg.clearDirections(subsys.hexes[i], HM_UpLeft);
				break;
			}
		}
		for(uint i = 0, cnt = subsys.hexes.length; i < cnt; ++i) {
			if(dsg.isExterior(subsys.hexes[i], HM_DownRight)) {
				dsg.clearDirections(subsys.hexes[i], HM_DownRight);
				break;
			}
			if(dsg.isExterior(subsys.hexes[i], HM_UpRight)) {
				dsg.clearDirections(subsys.hexes[i], HM_UpRight);
				break;
			}
		}
	}
};

tidy class Filler : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;

	double minFreq = 0;
	double maxFreq = 0;

	Filler(Filter@ filter, double minFreq, double maxFreq) {
		@this.filter = filter;
		this.minFreq = minFreq;
		this.maxFreq = maxFreq;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		frequency = randomd(minFreq, maxFreq);
		if(type is null)
			frequency = 0.0;
	}

	void distribute(Designer& dsg) override {
		double pct = frequency / dsg.totalFrequency;
		int hexes = pct * double(dsg.hexLimit);

		auto@ subsys = dsg.addSubsystem(type);

		for(int i = 0; i < hexes; ++i) {
			vec2u pos = dsg.markedRandom();
			if(!dsg.valid(pos))
				break;
			dsg.addHex(subsys, pos);
		}
	}
};

tidy class ArmorLayer : Distributor {
	Filter@ filter;
	const SubsystemDef@ def;

	uint directions = 0;
	int minLayers = 0;
	int maxLayers = 0;

	int layers = 0;

	ArmorLayer(Filter@ filter, uint directions, int minLayers, int maxLayers) {
		@this.filter = filter;
		this.directions = directions;
		this.minLayers = minLayers;
		this.maxLayers = maxLayers;
	}

	void prime() override {
		if(def !is null)
			@type = def;
		else
			@type = filter.choose();
		layers = randomi(minLayers, maxLayers);
	}

	void distribute(Designer& dsg) override {
		if(type is null)
			return;

		auto@ subsys = dsg.addSubsystem(type);
		for(int i = 0; i < layers; ++i)
			dsg.addCoating(subsys, directions);
	}
};

const Design@ createRandomDesign(uint type, int size, Empire@ emp) {
	Designer dsg(type, size, emp);
	return dsg.design();
}


