import util.design_export;
import designs;
import int getTraitID(const string&) from "traits";

final class SubsystemData {
	int sysId;
	vec2u core;
	vec2u[] hexes;
	vec3d direction;

	SubsystemData() {
		direction = vec3d_front();
	}

	const SubsystemDef@ get_def() {
		return getSubsystemDef(sysId);
	}
};

final class HexData {
	int subsystem;
	int module;

	HexData() {
		subsystem = -1;
		module = -1;
	}

	HexData(int sys, int mod) {
		subsystem = sys;
		module = mod;
	}
};
	
void randomize(array<int>& arr) {
	for(int i = 0, bnd = arr.length - 1; i < bnd; ++i) {
		int ind = randomi(i, bnd);
		if(i == ind)
			continue;
		int s = arr[i];
		arr[i] = arr[ind];
		arr[ind] = s;
	}
}
	
void randomize(array<HexStep>& arr) {
	HexStep local;
	for(int i = 0, bnd = arr.length - 1; i < bnd; ++i) {
		int ind = randomi(i, bnd);
		if(i == ind)
			continue;
		HexStep@ first = arr[i];
		HexStep@ other = arr[ind];
		local = first;
		first = other;
		other = local;
	}
}
	
void randomize(array<HexGridAdjacency>& arr) {
	HexGridAdjacency local;
	for(int i = 0, bnd = arr.length - 1; i < bnd; ++i) {
		int ind = randomi(i, bnd);
		if(i == ind)
			continue;
		HexGridAdjacency first = arr[i];
		HexGridAdjacency other = arr[ind];
		local = first;
		first = other;
		other = local;
	}
}

enum DesignType {
	DT_Support,
	DT_Flagship,
	DT_Station,
	DT_Satellite,
};

string[] autoSupportNames = {
	"Fiddle",
	"Rose",
	"Evergreen",
	"Hammer",
	"Sickle",
	"River",
	"Grave",
	"Demon",
	"Aquaria",
	"Tiny",
	"Bear",
	"Beast",
	"Cliff",
	"Fjord",
	"Delta",
	"Needle",
	"Stick",
	"Sheen",
	"Trunk"
};

string[] autoFlagNames = {
	"Azrael",
	"Olympus",
	"Volcanic",
	"Diamond",
	"Grandiose",
	"Voyage",
	"Erebus",
	"Weaver",
	"Hive",
	"Justice",
	"Venture"
};

HexGridAdjacency flipDir(HexGridAdjacency d) {
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

HexGridAdjacency stepDir(HexGridAdjacency from, int dir) {
	int d = int(from) - dir;
	if(d < 0)
		d += 6;
	else if(d >= 6)
		d -= 6;
	return HexGridAdjacency(d);
}

final class HexStep {
	vec2u hex;
	HexGridAdjacency dir;
	
	HexStep() {}
	
	HexStep(const vec2u& Pos, HexGridAdjacency Dir) {
		hex = Pos;
		dir = Dir;
	}
};

enum HexLocation {
	HL_Internal,
	HL_Back,
	HL_Side,
	HL_Front
};

class Designer {
	DesignType type;
	vec2u bound;
	vec2u topLeft, botRight;
	SubsystemData@[] subsystems;
	HexData[] hexes;
	vec2u center;
	HexGridb grid, used, place;
	HexGridi location;
	Empire@ owner;
	double scale = 1.0;
	string className, name;
	
	int weaponCount = -1;
	bool supplies = true;
	bool support = true;
	int engineSize = 0;
	int hyperSize = 0;
	int armorLevel = 0;

	bool needShrine = false;
	bool randomHull = false;
	
	uint hexLimit = 0;
	
	void prepare(DesignType Type, double size, Empire@ emp, const string& ClassName, const string& Name = "") {
		@owner = emp;
		scale = size;
		type = Type;
		bound = vec2u(getDesignGridSize(type == DT_Support ? "Support" : "Flagship", size));
		center = vec2u(bound.x / 2, bound.y / 2 - 1);
		grid.resize(bound.x, bound.y);
		used.resize(bound.x, bound.y);
		place.resize(bound.x, bound.y);
		location.resize(bound.x, bound.y);
		className = ClassName;
		name = Name;
		
		weaponCount = -1;
		supplies = true;
		support = true;
		engineSize = 0;
		hyperSize = 0;
		armorLevel = 0;

		needShrine = emp.hasTrait(getTraitID("Devout"));
		
		switch(Type) {
			case DT_Support: hexLimit = 60; break;
			case DT_Flagship: hexLimit = 128; break;
			case DT_Station: hexLimit = 160; break;
		}
	}
	
	vec2u flip(vec2u p) const {
		if(p.x % 2 == center.x % 2)
			return vec2u(p.x, center.y * 2 - p.y);
		else if(center.x % 2 == 0)
			return vec2u(p.x, center.y * 2 - p.y - 1);
		else
			return vec2u(p.x, center.y * 2 - p.y + 1);
	}
	
	void test() {
		uint pass = 0;
		for(uint i = 0; i < 100; ++i)
			if(design(1, false) !is null)
				++pass;
		error("Pass: " + pass + "/" + 100 + " (" + (pass) + "%)");
	}

	//Attempt to design a ship with the given specs
	const Design@ design(uint maxTries = 128, bool doTest = false) {
		if(doTest)
			test();
		for(uint i = 0; i < maxTries; ++i) {
			subsystems.length = 0;
			hexes.length = 0;
			hexes.length = bound.x * bound.y;
			grid.clear(false);
			used.clear(false);
			location.clear(HL_Internal);
			
			bool generated = false;
			for(uint i = 0; i < 10; ++i) {
				if(generate(center, hexLimit)) {
					generated = true;
					break;
				}
			}
			if(!generated)
				continue;
			
			bool success = false;
			switch(type) {
				case DT_Support:
					success = _designSupport(); break;
				case DT_Flagship:
					success = _designFlagship(); break;
			}
			
			if(!success)
				continue;
			
			DesignDescriptor desc;
			desc.size = scale;
			desc.gridSize = bound;
			@desc.owner = owner;
			desc.className = className;
			desc.name = name;
			if(name.length > 0)
				desc.name = name;
			else if(type == DT_Support)
				desc.name = autoSupportNames[randomi(0,autoSupportNames.length-1)];
			else
				desc.name = autoFlagNames[randomi(0,autoFlagNames.length-1)];
			
			for(uint i = 0, cnt = subsystems.length(); i < cnt; ++i) {
				const SubsystemDef@ def = subsystems[i].def;
				desc.addSystem(def);
				desc.setDirection(subsystems[i].direction);

				for(uint j = 0, jcnt = subsystems[i].hexes.length(); j < jcnt; ++j) {
					vec2u pos = subsystems[i].hexes[j];
					HexData@ hdata = hex[pos];

					desc.addHex(pos, def.modules[hdata.module]);
				}
			}
			
			if(randomHull && owner.shipset !is null) {
				string hullTag = type == DT_Support ? "Support" : "Flagship";
				uint hullCount = 0;
				for(uint i = 0, cnt = owner.shipset.hullCount; i < cnt; ++i) {
					const Hull@ hull = owner.shipset.hulls[i];

					//Check if it matches the tag
					if(!hull.hasTag(hullTag))
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
			}
			else {
				@desc.hull = getBestHull(desc, type == DT_Support ? "Support" : "Flagship", owner);
			}

			if(desc.hull is null)
				return null;
			
			auto@ dsg = makeDesign(desc);
			if(dsg !is null && !dsg.hasFatalErrors())
				return dsg;
		}
		
		return null;
	}
	
	HexData@ get_hex(vec2u p) {
		return hexes[p.x + p.y * bound.width];
	}
	
	void categorize() {
		for(uint y = 0; y < bound.y; ++y) {
			for(uint x = 0; x < bound.x; ++x) {
				vec2u pos = vec2u(x, y);
				if(place[pos]) break;
				location[pos] = HL_Back;
			}
		}
		
		for(uint x = 0; x < bound.x; ++x) {
			vec2u pos = vec2u(x, 0);
			do {
				if(place[pos]) break;
				location[pos] = HL_Side;
			} while(location.advance(pos, HEX_Down));
			
			pos = vec2u(x, bound.y-1);
			do {
				if(place[pos]) break;
				location[pos] = HL_Side;
			} while(location.advance(pos, HEX_Up));
		}
		
		for(uint y = 0; y < bound.y; ++y) {
			for(int x = bound.x-1; x >= 0; --x) {
				vec2u pos = vec2u(x, y);
				if(place[pos]) break;
				location[pos] = HL_Front;
			}
		}
	}
	
	SubsystemData@ addSubsystem(const SubsystemDef@ type, vec2u at, bool onlyInternal = true) {
		if(type is null || !grid.valid(at) || used[at] || (onlyInternal && !place[at]))
			return null;
	
		SubsystemData@ data;
		if(type.hasCore) {
			@data = SubsystemData();
			int index = subsystems.length;
			subsystems.insertLast(@data);
			data.sysId = type.index;
			data.hexes.insertLast(at);
		
			data.core = at;
			hex[at] = HexData(index, type.coreModule.index);
			grid[at] = true;
			used[at] = true;
		}
		else {
			int index = -1;
			for(uint i = 0, cnt = subsystems.length; i < cnt; ++i) {
				if(subsystems[i].def is type) {
					index = i;
					break;
				}
			}
			
			if(index >= 0) {
				@data = subsystems[index];
			}
			else {
				@data = SubsystemData();
				index = subsystems.length;
				subsystems.insertLast(@data);
				data.sysId = type.index;
			}
		
			data.hexes.insertLast(at);
			hex[at] = HexData(index, type.defaultModule.index);
			grid[at] = true;
			used[at] = true;
		}
		
		return data;
	}
	
	void expand(SubsystemData@ sys, vec2u to, bool onlyInternal = true) {
		if(sys is null || !grid.valid(to) || used[to] || (onlyInternal && !place[to]))
			return;
		int index = subsystems.find(sys);
		sys.hexes.insertLast(to);
		hex[to] = HexData(index, sys.def.defaultModule.index);
		grid[to] = true;
		used[to] = true;
	}
	
	void occupyLine(vec2u from, HexGridAdjacency dir) {
		if(grid.valid(from))
			used[from] = true;
		while(grid.advance(from, dir)) {
			used[from] = true;
			location[from] = HL_Back;
		}
	}
	
	vec2u advance(vec2u p, HexGridAdjacency dir) const {
		grid.advance(p, dir);
		return p;
	}
	
	vec2u advance(vec2u p, HexGridAdjacency dir, HexGridAdjacency dir2) const {
		grid.advance(p, dir);
		grid.advance(p, dir2);
		return p;
	}
	
	vec2u advance(vec2u p, HexGridAdjacency dir, HexGridAdjacency dir2, HexGridAdjacency dir3) const {
		grid.advance(p, dir);
		grid.advance(p, dir2);
		grid.advance(p, dir3);
		return p;
	}
	
	vec2u advance(vec2u p, HexGridAdjacency dir, HexGridAdjacency dir2, HexGridAdjacency dir3, HexGridAdjacency dir4) const {
		grid.advance(p, dir);
		grid.advance(p, dir2);
		grid.advance(p, dir3);
		grid.advance(p, dir4);
		return p;
	}
	
	double biased(int bias) {
		double r = randomd();
		
		if(bias > 0) {
			while(bias-- > 0)
				r = max(r, randomd());
		}
		else {
			while(bias++ < 0)
				r = min(r, randomd());
		}
		return r;
	}
	
	array<const SubsystemDef@>@ getSubsystems(const string& tag, const string& tag2 = "", const string& tag3 = "") {
		array<const SubsystemDef@> list;
		string hullTag;
		switch(type) {
			case DT_Support: hullTag = "Support"; break;
			case DT_Flagship: hullTag = "Flagship"; break;
			case DT_Station: hullTag = "Station"; break;
		}
		
		for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			auto@ type = getSubsystemDef(i);
			if(owner.isUnlocked(type) && type.hasTag(tag) && type.hasHullTag(hullTag) && !type.hasTag(ST_SpecialCost)
				&& (tag2.length == 0 || type.hasTag(tag2))
				&& (tag3.length == 0 || type.hasTag(tag3)) )
				list.insertLast(type);
		}
		
		return list;
	}
	
	void rebound(const vec2u &in pos) {
		topLeft.x = min(pos.x, topLeft.x);
		topLeft.y = min(pos.y, topLeft.y);
		botRight.x = max(pos.x, botRight.x);
		botRight.y = max(pos.y, botRight.y);
	}
	
	array<int> rotDirs = {-2,-1,0,1,2};
	array<HexStep> cellsActive, cellSwap;
	bool generate(vec2u center, int hexes) {
		auto@ cells = @cellsActive;
		
		place.clear(false);
		topLeft = center;
		botRight = center;
		
		cells.length = 0;
		place[center] = true;
		hexes -= 1;
		for(uint i = 0; i < 6; ++i)
			cells.insertLast(HexStep(advance(center, HexGridAdjacency(i)), HexGridAdjacency(i)));
		randomize(cells);
		
		uint newCount = max(randomi(1,cells.length), randomi(1, cells.length));
		if(newCount < cells.length)
			cells.length = newCount;
		
		auto@ swap = @cellSwap;
		
		while(hexes > 0 && cells.length > 0) {
			swap.length = 0;
			
			bool addedAny = false;
			uint i = 0;
			for(uint cnt = min(randomi(0, cells.length-1), randomi(0, cells.length-1)); i < cnt; ++i)
				swap.insertLast(cells[i]);
				
			for(uint cnt = cells.length; i < cnt && hexes > 0; ++i) {
				auto@ cell = cells[i];
				vec2u p = cell.hex;
				if(!place.valid(p))
					continue;
				auto f = flip(p);
				if(!place.valid(f))
					continue;
				
				if(!place[p]) {
					if(f == p) {
						hexes -= 1;
						rebound(p);
					}
					else {
						if(hexes == 1)
							continue;
						place[f] = true;
						hexes -= 2;
						
						rebound(p);
						rebound(f);
					}
					place[p] = true;
					
					addedAny = true;
					
					uint split = min(randomi(1,5), randomi(3,5));
					randomize(rotDirs);
					
					for(uint d = 0; d < split; ++d) {
						auto dir = stepDir(cell.dir, rotDirs[d]);
						swap.insertLast(HexStep(advance(cell.hex, dir), dir));
					}
				}
			}
			
			if(swap.length == 0)
				break;
				
			randomize(swap);
			auto@ s = @swap;
			@swap = cells;
			@cells = s;
		}
		return hexes == 0;
	}

	bool spread(const SubsystemDef@ type, vec2u pos, int size, bool mirror, const array<HexGridAdjacency>& dirs, const array<HexGridAdjacency>@ occupy = null, double angle = 0) {
		auto@ cells = @cellsActive;
		
		int initSize = size;
		
		if(occupy !is null) {
			for(uint i = 0, cnt = occupy.length; i < cnt; ++i) {
				vec2u p = pos;
				auto dir = occupy[i];
				bool first = true;
				while(grid.valid(p)) {
					if(used[p])
						return false;
					if(!first && place[p])
						return false;
					first = false;
					if(!grid.advance(p, dir))
						break;
				}
			}
		}
		
		auto@ upper = addSubsystem(type, pos);
		if(upper is null)
			return false;
		if(angle != 0)
			upper.direction = quaterniond_fromAxisAngle(vec3d_up(), angle) * upper.direction;
		SubsystemData@ lower;
		if(mirror) {
			@lower = addSubsystem(type, flip(pos));
			if(lower is null)
				return false;
			if(angle != 0)
				lower.direction = quaterniond_fromAxisAngle(vec3d_up(), -angle) * lower.direction;
		}
		
		if(occupy !is null) {
			for(uint i = 0, cnt = occupy.length; i < cnt; ++i) {
				occupyLine(pos, occupy[i]);
				if(lower !is null)
					occupyLine(flip(pos), flipDir(occupy[i]));
			}
		}
		
		cells.length = 0;
		for(uint i = 0, cnt = dirs.length; i < cnt; ++i)
			cells.insertLast(HexStep(advance(pos, dirs[i]), dirs[i]));
		
		auto@ swap = @cellSwap;
		while(size > 0) {
			swap.length = 0;
			randomize(cells);
		
			bool addedAny = false;
			uint i = 0;
			for(uint cnt = min(randomi(0, cells.length/2), randomi(0, cells.length/2)); i < cnt; ++i)
				swap.insertLast(cells[i]);
			
			for(uint cnt = cells.length; i < cnt && size > 0; ++i) {
				vec2u p = cells[i].hex;
				if(!used[p] && place[p]) {
					auto@ cell = cells[i];
					expand(upper, p);
					auto f = flip(p);
					if(p == f) {
						size -= 1;
					}
					else {
						expand(mirror ? lower : upper, f);
						size -= 2;
					}
					addedAny = true;
					
					uint split = 5;//min(randomi(1,5), randomi(3,5));
					randomize(rotDirs);
					
					for(uint d = 0; d < split; ++d) {
						auto dir = stepDir(cell.dir, rotDirs[d]);
						swap.insertLast(HexStep(advance(cell.hex, dir), dir));
					}
				}
			}
			
			if(swap.length == 0)
				break;
			
			auto@ s = @swap;
			@swap = cells;
			@cells = s;
		}
		
		return true;
	}
	
	vec2u findExternal(vec2u pos, HexGridAdjacency dir) {
		vec2u prev = pos;
		while(place[pos]) {
			prev = pos;
			if(!place.advance(pos, dir))
				break;
		}
		return prev;
	}
	
	vec2u findExternal(vec2u pos, vec2i dir) {
		vec2u prev = pos;
		while(place.valid(pos) && place[pos]) {
			prev = pos;
			pos.x += dir.x;
			pos.y += dir.y;
		}
		return prev;
	}
	
	bool _designFlagship() {
		vec2u pos;
		array<HexGridAdjacency> dirs, occupy;
		dirs.length = 0; occupy.length = 0;
		
		auto@ bridgeTypes = getSubsystems("ControlCore");
		if(bridgeTypes.length == 0)
			return false;
		
		//error("Bridge");
		if(randomi(0,2) != 0) {
			dirs.length = 0; occupy.length = 0;
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpLeft);
			dirs.insertLast(HEX_UpRight);
			
			bool success = spread(bridgeTypes[randomi(0,bridgeTypes.length-1)], center,
				randomi(1,3), false, dirs);
			if(!success)
				return false;
				
			if(randomi(0,1) == 0)
				addSubsystem(bridgeTypes[randomi(0,bridgeTypes.length-1)],
					randomi(0,1) == 0 ? center - vec2u(randomi(1,2)*2,0) : center + vec2u(randomi(1,2)*2,0));
		}
		else {
			dirs.length = 0; occupy.length = 0;
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpLeft);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_Down);
			dirs.insertLast(HEX_DownLeft);
			dirs.insertLast(HEX_DownRight);
			
			bool success = spread(bridgeTypes[randomi(0,bridgeTypes.length-1)], center - vec2u(0, randomi(1,2)),
				randomi(0,2), true, dirs);
			if(!success)
				return false;
		}

		//error("Shrine, race specific");
		if(needShrine) {
			auto@ shrineTypes = getSubsystems("Prayer");
			if(shrineTypes.length != 0) {
				dirs.length = 0; occupy.length = 0;
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpLeft);
				dirs.insertLast(HEX_UpRight);
				dirs.insertLast(HEX_Down);
				dirs.insertLast(HEX_DownLeft);
				dirs.insertLast(HEX_DownRight);

				if(randomi(0,1) == 0)
					spread(shrineTypes[randomi(0, shrineTypes.length-1)], center + vec2u(randomi(1, center.x * 1 / 3) * 2, 0),
						randomi(8, 20), false, dirs, occupy);
				else
					spread(shrineTypes[randomi(0, shrineTypes.length-1)], vec2u(randomi(center.x / 2, center.x * 5 / 3), randomi(center.y/2, center.y-1)),
						randomi(8, 20), true, dirs, occupy);
			}
		}
		
		//error("Reactor");
		if(supplies || randomi(0,1) == 0) {
			auto@ reactors = getSubsystems("IsReactor");
			if(reactors.length == 0)
				return false;
			const SubsystemDef@ reactor = reactors[randomi(0,reactors.length-1)];
			if(randomi(0,1) == 0) {
				array<HexGridAdjacency> dirs;
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpLeft);
				dirs.insertLast(HEX_UpRight);
				
				bool success = false;
				for(uint i = 0; i < 3; ++i) {
					bool s = spread(reactor, randomi(0,2) == 0 ? center + vec2u(randomi(1,center.x/4) * 2, 0) : center - vec2u(randomi(1,center.x/3) * 2, 0),
						randomi(2,7), false, dirs);
					if(s)
						success = true;
				}
				if(!success)
					return false;
			}
			else {
				array<HexGridAdjacency> dirs;
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpLeft);
				dirs.insertLast(HEX_UpRight);
				dirs.insertLast(HEX_Down);
				dirs.insertLast(HEX_DownLeft);
				dirs.insertLast(HEX_DownRight);
				
				bool success = false;
				for(uint i = 0; i < 3; ++i) {
					bool s = spread(reactor, vec2u(randomi(topLeft.x, botRight.x), randomi(topLeft.y, center.y-1)),
						randomi(4,9), true, dirs);
					if(s)
						success = true;
				}
				
				if(!success)
					return false;
			}
		}
		
		//error("2nd Defense");
		auto@ secondaryDefense = getSubsystems("SecondaryDefense");
		if(secondaryDefense.length != 0 && randomi(0,2) == 0) {
			dirs.length = 0; occupy.length = 0;
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_DownRight);
			dirs.insertLast(HEX_UpLeft);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_DownLeft);
			dirs.insertLast(HEX_Down);
			
			if(randomi(0,1) == 0)
				spread(secondaryDefense[randomi(0, secondaryDefense.length-1)], center + vec2u(randomi(1, center.x * 1 / 3) * 2, 0),
					randomi(0, hexes.length / 28), false, dirs, occupy);
			else
				spread(secondaryDefense[randomi(0, secondaryDefense.length-1)], vec2u(randomi(center.x / 2, center.x * 5 / 3), randomi(center.y/2, center.y-1)),
					randomi(0, hexes.length / 28), true, dirs, occupy);
		}
		
		//error("Engines");
		auto@ engineTypes = getSubsystems("Engine", "GivesThrust");
		if(engineTypes.length == 0)
			return false;
		
		bool engineSuccess = false;
		for(uint try = 0; try < 6; ++try) {
			auto@ engineType = engineTypes[randomi(0,engineTypes.length-1)];
			int engines = randomi(1,2);
			if(engines == 1) {
				if(engineType.hasTag("ExteriorCore")) {
					occupy.insertLast(HEX_UpLeft);
					occupy.insertLast(HEX_DownLeft);
				}
				else {
					dirs.insertLast(HEX_UpLeft);
				}
				
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpRight);
				
				int dLeft = int(topLeft.x - center.x) / 2;
				int dRight = -1;
				
				bool success = false;
				for(uint try = 0; try < 2; ++try) {
					vec2u p = center + vec2u(randomi(dLeft,dRight) * 2, 0);
					if(occupy.length != 0)
						p = findExternal(p, vec2i(-2, 0));
				
					success = spread(engineType, p,
						min(randomi(5, 22), randomi(5, 22)) + engineSize, false, dirs, occupy);
					if(success)
						break;
				}
				if(success) {
					engineSuccess = true;
					break;
				}
			}
			else if(engines == 2) {
				dirs.length = 0; occupy.length = 0;
				if(engineType.hasTag("ExteriorCore")) {
					occupy.insertLast(HEX_UpLeft);
					if(randomi(0,1) == 0)
						dirs.insertLast(HEX_Up);
				}
				else {
					dirs.insertLast(HEX_Up);
					dirs.insertLast(HEX_UpLeft);
					dirs.insertLast(HEX_DownLeft);
				}
				dirs.insertLast(HEX_UpRight);
				dirs.insertLast(HEX_DownRight);
				dirs.insertLast(HEX_Down);
				
				bool success = false;
				for(uint try = 0; try < 2; ++try) {
					vec2u p = vec2u(randomi(topLeft.x,center.x), randomi(topLeft.y, center.y-1));
					if(occupy.length != 0)
						p = findExternal(p, occupy[0]);
					
					success = spread(engineType, p,
						min(randomi(0, 6), randomi(2, 6)) + engineSize + hexes.length / 28, true, dirs, occupy);
					if(success)
						break;
				}
				if(success) {
					engineSuccess = true;
					break;
				}
			}
		}
		if(!engineSuccess)
			return false;
		
		//error("Hyperdrive");
		auto@ hyperTypes = getSubsystems("Hyperengine");
		if(hyperTypes.length != 0) {
			auto@ hyperType = hyperTypes[randomi(0,hyperTypes.length-1)];
			
			dirs.length = 0; occupy.length = 0;		
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_UpLeft);
			
			int dLeft = int(topLeft.x - center.x) / 2;
			int dRight = int(botRight.x - center.x) / 2;
			
			bool success = false;
			for(uint try = 0; try < 3; ++try) {
				success = spread(hyperType, center + vec2u(randomi(dLeft,dRight) * 2, 0),
					randomi(5, 30) + hyperSize, false, dirs);
				if(success)
					break;
			}
			if(!success)
				return false;
			//Very small hyperdrives will render ships unusable
			if(subsystems.last.hexes.length == 1)
				return false;
		}
		
		//error("Weapons");
		auto@ weapons = getSubsystems("Weapon", "MainDPS");
		if(weapons.length == 0)
			return false;
		
		bool weaponSuccess = (weaponCount == 0);
		for(uint i = 0, cnt = weaponCount >= 0 ? weaponCount : randomi(1,3); i < cnt; ++i) {
			dirs.length = 0; occupy.length = 0;
	
			if(i == 2) {
				auto@ secondary = getSubsystems("Weapon", "SecondaryDPS");
				for(uint i = 0, cnt = secondary.length; i < cnt; ++i)
					weapons.insertLast(secondary[i]);
			}
			
			const SubsystemDef@ wepType = weapons[randomi(0,weapons.length-1)];
			bool homing = wepType.hasTag("Homing");
			
			bool success = false;
			if(i != 0 || randomi(0,homing ? 2 : 1) != 0) {
				if(!homing)
					occupy.insertLast(HEX_UpRight);
				else {
					switch(randomi(0,2)) {
						case 0: occupy.insertLast(HEX_UpLeft); break;
						case 1: occupy.insertLast(HEX_Up); break;
						case 2: occupy.insertLast(HEX_UpRight); break;
					}
				}
			
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_DownRight);
				dirs.insertLast(HEX_UpLeft);
				dirs.insertLast(HEX_UpRight);
				dirs.insertLast(HEX_DownLeft);
				dirs.insertLast(HEX_Down);
				
				for(uint try = 0; try < 6; ++try) {
					success = spread(wepType, findExternal(vec2u(randomi(topLeft.x, botRight.x), randomi(topLeft.y, center.y-1)), occupy[0]),
						(randomi(2, 8) + hexes.length / 24) * (3 / min(cnt,3)), true, dirs, occupy, hexToRadians(occupy[0]) + pi * randomd(-0.05, 0.05));
					if(success)
						break;
				}
			}
			else {
				int dLeft = 1;
				int dRight = int(botRight.x - center.x) / 2;
				
				occupy.insertLast(HEX_UpRight);
				occupy.insertLast(HEX_DownRight);
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpLeft);
				
				for(uint try = 0; try < 2; ++try) {
					success = spread(wepType, findExternal(center + vec2u(randomi(dLeft, dRight) * 2, 0), vec2i(2, 0)),
						(randomi(2, 8) + hexes.length / 24) * (3 / min(cnt,3)), false, dirs, occupy);
					if(success)
						break;
				}
			}
			
			if(success)
				weaponSuccess = true;
		}
		
		if(!weaponSuccess)
			return false;
		
		auto@ supplyModule = getSubsystemDef("SupplyModule");
		auto@ supportCap = getSubsystemDef("SupportCapModule");
		
		//error("Supplies");
		if(supplies) {
			dirs.length = 0; occupy.length = 0;
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_UpLeft);
			dirs.insertLast(HEX_DownRight);
			dirs.insertLast(HEX_DownLeft);
			dirs.insertLast(HEX_Down);
			
			int count = randomi(1, 3);
			
			bool success = false;
			for(uint try = 0; try < 6; ++try) {
				success = spread(supplyModule, vec2u(randomi(topLeft.x, botRight.x), randomi(topLeft.y, center.y)),
					count, true, dirs);
				if(success)
					break;
			}
			if(!success)
				return false;
		}
		
		//error("Support");
		if(support) {
			dirs.length = 0; occupy.length = 0;
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_UpLeft);
			dirs.insertLast(HEX_DownRight);
			dirs.insertLast(HEX_DownLeft);
			dirs.insertLast(HEX_Down);
			
			int count = randomi(1,4);
			
			bool success = false;
			for(uint try = 0; try < 6; ++try) {
				success = spread(supportCap, vec2u(randomi(topLeft.x, botRight.x), randomi(topLeft.y, center.y)),
					count, true, dirs);
				if(success)
					break;
			}
			if(!success)
				return false;
		}
		
		double rearArmor = biased(-2 + armorLevel);
		double sideArmor = biased(-1 + armorLevel);
		double frontArmor = biased(+1 + armorLevel);
		double internalBits = 1.0;
		
		auto@ armors = getSubsystems("IsArmor");
		auto@ frontPlate = armors.length != 0 ? armors[randomi(0,armors.length-1)] : null;
		auto@ sidePlate = armors.length != 0 ? armors[randomi(0,armors.length-1)] : null;
		auto@ rearPlate = armors.length != 0 ? armors[randomi(0,armors.length-1)] : null;
		
		categorize();
		
		//error("Fillin");
		for(pos.x = 0; pos.x < bound.width; ++pos.x) {
			for(pos.y = 0; pos.y <= center.y; ++pos.y) {
				if(used[pos])
					continue;
				
				int expandDir = -1;
				
				auto placeType = HL_Internal;
				if(!place[pos]) {
					placeType = HexLocation(location[pos]);
					bool placeable = false;
					if(placeType == HL_Internal)
						placeable = true;
					
					if(!placeable) {
						uint base = randomi(0,6);
						for(uint d = 0; d < 6; ++d) {
							vec2u p = pos;
							if(grid.advance(p, HexGridAdjacency((d + base) % 6)) && location[p] == HL_Internal) {
								if(expandDir == -1 && used[p])
									expandDir = d;
								placeable = true;
							}
						}
					}
					
					if(!placeable)
						continue;
				}
				
				SubsystemData@ expandUpper, expandLower;
				vec2u posUpper, posLower;
				
				const SubsystemDef@ armorType;
				bool makeSupply = false, makeSupport = false;
				
				switch(placeType) {
					case HL_Internal:
					if(randomd() < internalBits) {
						if(expandDir != -1 && randomd() < 0.85) {
							posUpper = pos;
							grid.advance(posUpper, HexGridAdjacency(expandDir));
							@expandUpper = subsystems[hex[posUpper].subsystem];
							
							posLower = flip(pos);
							grid.advance(posLower, flipDir(HexGridAdjacency(expandDir)));
							@expandLower = subsystems[hex[posLower].subsystem];
						}
						else {
							switch(randomi(0,6)) {
								case 0: case 1: makeSupply = supplies; break;
								case 2: case 3: makeSupport = support; break;
								case 4: default:
									//@armorType = frontPlate;
								break;
							}
							//If we didn't generate supplies or support, fall back to armor
							@armorType = frontPlate;
						}
					}
					break;
					case HL_Back:
						if(randomd() < rearArmor)
							@armorType = rearPlate;
					break;
					case HL_Side:
						if(randomd() < sideArmor)
							@armorType = sidePlate;
					break;
					case HL_Front:
						if(randomd() < frontArmor)
							@armorType = frontPlate;
					break;
				}
				
				if(expandUpper !is null) {
					expand(expandUpper, posUpper);
					expand(expandLower, posLower);
				}
				else if(makeSupply) {
					auto@ m = addSubsystem(supplyModule, pos);
					expand(m, flip(pos));
				}
				else if(makeSupport) {
					auto@ m = addSubsystem(supportCap, pos);
					expand(m, flip(pos));
				}
				else if(armorType !is null) {
					auto@ m = addSubsystem(armorType, pos, onlyInternal = false);
					expand(m, flip(pos), onlyInternal = false);
				}
			}
		}
		
		return true;
	}

	bool _designSupport() {
		vec2u pos;
		auto@ armors = getSubsystems("IsArmor");
		auto@ plate = armors.length != 0 ? armors[randomi(0,armors.length-1)] : null;
		
		uint engines = 1;
		if(randomi(0,2) == 0)
			engines = 2;
		
		uint guns = 1;
		switch(randomi(0,4)) {
			case 2: case 3:
				guns = 2; break;
			case 4:
				guns = 3; break;
		}
		
		auto@ bridgeTypes = getSubsystems("ControlCore");
		if(bridgeTypes.length == 0)
			return false;
		
		auto@ bridge = addSubsystem(bridgeTypes[randomi(0,bridgeTypes.length-1)], center);
		if(randomi(0,1) == 0) {
			expand(bridge, advance(bridge.core, HEX_Down));
			expand(bridge, advance(bridge.core, HEX_Up));
		}
		
		auto@ weapons = getSubsystems("Weapon");
		if(weapons.length == 0)
			return false;
		const SubsystemDef@ wepType = weapons[randomi(0,weapons.length-1)];
		
		double wepFraction = normald(0.4, 0.65);
		
		int wepCount = weaponCount >= 0 ? weaponCount : guns;
		bool gunSuccess = wepCount == 0;
		
		while(wepCount > 0) {
			bool homing = wepType.hasTag("Homing");
			
			bool success = false;
			if(wepCount == 1) {
				wepCount -= 1;
				array<HexGridAdjacency> dirs, occupy;
				occupy.insertLast(HEX_UpRight);
				occupy.insertLast(HEX_DownRight);
				
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_UpLeft);
				
				bool success = spread(wepType, findExternal(center + vec2u(randomi(1, center.x/4) * 2, 0), vec2i(2,0)),
					wepFraction * hexLimit, false, dirs, occupy);
				if(success)
					gunSuccess = true;
			}
			else if(wepCount >= 2) {
				wepCount -= 2;
				array<HexGridAdjacency> dirs, occupy;
				if(!homing)
					occupy.insertLast(HEX_UpRight);
				else {
					switch(randomi(0,2)) {
						case 0: occupy.insertLast(HEX_UpLeft); break;
						case 1: occupy.insertLast(HEX_Up); break;
						case 2: occupy.insertLast(HEX_UpRight); break;
					}
				}
				
				dirs.insertLast(HEX_Up);
				dirs.insertLast(HEX_DownRight);
				dirs.insertLast(HEX_UpLeft);
				dirs.insertLast(HEX_DownLeft);
				dirs.insertLast(HEX_Down);
				
				vec2u attempt = homing ?
					vec2u(randomi(topLeft.x, botRight.x), randomi(topLeft.y, center.y-1)) :
					vec2u(randomi(center.x, botRight.x), randomi(topLeft.y, center.y-1));
				
				bool success = spread(wepType, findExternal(attempt, occupy[0]),
					wepFraction * hexLimit, true, dirs, occupy, pi * randomd(0.2, 0.3));
				if(success)
					gunSuccess = true;
			}
		}
		
		if(!gunSuccess)
			return false;
		
		auto@ engineTypes = getSubsystems("Engine");
		if(engineTypes.length == 0)
			return false;
		auto@ engineType = engineTypes[randomi(0,engineTypes.length-1)];
		
		if(engines == 1) {
			array<HexGridAdjacency> dirs, occupy;
			occupy.insertLast(HEX_UpLeft);
			occupy.insertLast(HEX_DownLeft);
			
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpRight);
			
			bool success = spread(engineType, findExternal(center - vec2u(randomi(1,center.x/2 - 1) * 2, 0), vec2i(-2,0)),
				(1.0 - wepFraction) * hexLimit, false, dirs, occupy);
			if(!success)
				return false;
		}
		else if(engines == 2) {
			array<HexGridAdjacency> dirs, occupy;
			occupy.insertLast(HEX_UpLeft);
			
			dirs.insertLast(HEX_Up);
			dirs.insertLast(HEX_UpRight);
			dirs.insertLast(HEX_DownRight);
			dirs.insertLast(HEX_Down);
			
			bool success = spread(engineType, findExternal(vec2u(randomi(0,center.x/2) * 2 + 1, randomi(center.y/2, center.y-1)), occupy[0]),
				(1.0 - wepFraction) * hexLimit, true, dirs, occupy);
			if(!success)
				return false;
		}
		
		//Attach armor to the design
		double rearArmor = biased(-3 + armorLevel);
		double sideArmor = biased(-2 + armorLevel);
		double frontArmor = biased(armorLevel);
		double internalArmor = 1.0;
		
		SubsystemData@ armor;
		
		categorize();
		
		for(pos.x = 0; pos.x < bound.width; ++pos.x) {
			for(pos.y = 0; pos.y <= center.y; ++pos.y) {
				if(used[pos])
					continue;
				
				int expandDir = -1;
				
				auto placeType = HL_Internal;
				if(!place[pos]) {
					placeType = HexLocation(location[pos]);
					bool placeable = false;
					if(placeType == HL_Internal)
						placeable = true;
					
					if(!placeable) {
						uint base = randomi(0,6);
						for(uint d = 0; d < 6; ++d) {
							vec2u p = pos;
							if(grid.advance(p, HexGridAdjacency((d + base) % 6)) && location[p] == HL_Internal) {
								if(expandDir == -1 && used[p])
									expandDir = d;
								placeable = true;
							}
						}
					}
					
					if(!placeable)
						continue;
				}
				
				SubsystemData@ expandUpper, expandLower;
				vec2u posUpper, posLower;
				
				bool makeArmor = false;
				switch(placeType) {
					case HL_Internal:
						if(randomd() < internalArmor) {
							if(expandDir != -1) {
								posUpper = pos;
								grid.advance(posUpper, HexGridAdjacency(expandDir));
								@expandUpper = subsystems[hex[posUpper].subsystem];
								
								posLower = flip(pos);
								grid.advance(posLower, flipDir(HexGridAdjacency(expandDir)));
								@expandLower = subsystems[hex[posLower].subsystem];
							}
							else {
								makeArmor = true;
							}
						}
					break;
					case HL_Back:
						if(randomd() < rearArmor)
							makeArmor = true;
					break;
					case HL_Side:
						if(randomd() < sideArmor)
							makeArmor = true;
					break;
					case HL_Front:
						if(randomd() < frontArmor)
							makeArmor = true;
					break;
				}
				
				if(makeArmor) {
					if(armor !is null)
						expand(armor, pos, onlyInternal = false);
					else
						@armor = addSubsystem(plate, pos, onlyInternal = false);
					if(armor !is null)
						expand(armor, flip(pos), onlyInternal = false);
					else
						@armor = addSubsystem(plate, flip(pos), onlyInternal = false);
				}
				else if(expandUpper !is null) {
					expand(expandUpper, posUpper);
					expand(expandLower, posLower);
				}
			}
		}
		
		return true;
	}
};
