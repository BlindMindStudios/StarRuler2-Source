import util.random_designs;
import ship_groups;
import object_creation;
from empire import Creeps;

export Creeps;
export getRemnantDesign;
export spawnRemnantFleet;
export composeRemnantFleet;
export RemnantComposition;

array<const Design@> flagships;
array<const Design@> supportShips;

class RemnantComposition {
	const Design@ flagship;
	array<const Design@> supports;
	array<int> supportCounts;

	void dump() {
		if(flagship is null)
			return;
		print("Flag: "+flagship.name+" - "+flagship.totalHP+" * "+flagship.total(SV_DPS));
		for(uint i = 0, cnt = supports.length; i < cnt; ++i)
			print("Support: "+supportCounts[i]+"x "+supports[i].name+" - "+supports[i].totalHP+" * "+supports[i].total(SV_DPS));
	}
};

RemnantComposition@ composeRemnantFleet(double targetStrength, double margin = 0.1, Empire@ emp = Creeps) {
	RemnantComposition compose;
	targetStrength *= 1000.0;

	double estHP = 0.0;
	double estDPS = 0.0;

	int flagSize = 0;

	//Find the closest flagship size to this strength we have
	double foundDiff = 0.0;
	for(uint i = 0, cnt = flagships.length; i < cnt; ++i) {
		auto@ dsg = flagships[i];
		if(dsg.owner !is emp)
			continue;

		double hp = dsg.totalHP;
		double dps = dsg.total(SV_DPS);

		double diff = abs((hp * dps) - (targetStrength * 0.5));
		if(diff < foundDiff) {
			flagSize = dsg.size;
			foundDiff = diff;
		}
	}

	if(flagSize == 0)
		flagSize = 128;

	//Iterate until we find something close enough in strength
	while(true) {
		if(flagSize < 16) {
			@compose.flagship = null;
			break;
		}

		const Design@ flag = getRemnantDesign(DT_Flagship, flagSize, emp);
		@compose.flagship = flag;

		double hp = flag.totalHP;
		hp += flag.total(SV_ShieldCapacity);

		double dps = flag.total(SV_DPS);

		if((hp * dps) > targetStrength * (1.0 + margin)) {
			flagSize = double(flagSize) * sqrt((targetStrength * 0.5) / (hp * dps));
			continue;
		}

		int supCap = flag.total(SV_SupportCapacity);
		int supAdded = 0;

		compose.supports.length = 0;
		compose.supportCounts.length = 0;
		while((hp * dps) < targetStrength && supAdded < supCap) {
			int supSize = pow(2, round(::log(double(supCap) * randomd(0.005, 0.03))/::log(2.0)));
			if(supSize <= 0 || supSize >= supCap - supAdded)
				break;

			const Design@ supDsg = getRemnantDesign(DT_Support, supSize, emp);
			if(supDsg is null)
				break;

			double supHP = supDsg.totalHP;
			double supDPS = supDsg.total(SV_DPS);

			int count = clamp((supCap - supAdded)/supSize, 1, int(ceil((randomd(0.01, 0.1)*supCap)/double(supSize))));
			int realCount = 0;
			for(int i = 0; i < count; ++i) {
				hp += supHP;
				dps += supDPS;
				realCount += 1;
				supAdded += supSize;

				if(hp * dps >= targetStrength)
					break;
				if(supAdded + supDsg.size > supCap)
					break;
			}

			compose.supports.insertLast(supDsg);
			compose.supportCounts.insertLast(realCount);
		}

		if(abs((hp * dps) - targetStrength) > targetStrength * margin) {
			flagSize = double(flagSize) * sqrt(targetStrength / (hp * dps));
			continue;
		}
		else {
			break;
		}
	}

	return compose;
}

Ship@ spawnRemnantFleet(const vec3d& position, RemnantComposition@ compose, Empire@ emp = Creeps, bool alwaysVisible = false) {
	if(compose.flagship is null)
		return null;
	if(compose.flagship.outdated)
		@compose.flagship = compose.flagship.owner.updateDesign(compose.flagship, true);

	Ship@ leader = createShip(position, compose.flagship, emp, free=true, memorable=true);
	leader.setAutoMode(AM_RegionBound);
	leader.sightRange = 0;
	leader.setRotation(quaterniond_fromAxisAngle(vec3d_up(), randomd(-pi, pi)));
	if(alwaysVisible)
		leader.alwaysVisible = true;

	for(uint i = 0, cnt = compose.supports.length; i < cnt; ++i) {
		const Design@ sup = compose.supports[i];
		if(sup !is null) {
			if(sup.outdated)
				@sup = sup.owner.updateDesign(sup, true);
			for(uint n = 0, ncnt = compose.supportCounts[i]; n < ncnt; ++n) {
				Ship@ ship = createShip(leader.position, sup, emp, leader, free=true);
				if(alwaysVisible)
					ship.alwaysVisible = true;
			}
		}
	}

	return leader;
}

const Design@ getRemnantDesign(uint type, int size, Empire@ emp = Creeps) {
	auto@ remnants = flagships;
	if(type == DT_Support)
		@remnants = supportShips;
	if(size == 0)
		size = 1;

	//Find existing designs at this size
	array<const Design@> designs;
	for(uint i = 0, cnt = remnants.length; i < cnt; ++i) {
		if(int(remnants[i].size) == size && remnants[i].owner is emp)
			designs.insertLast(remnants[i]);
	}

	if(designs.length == 0 || randomd() < 1.0/double(designs.length)) {
		//Create a new design of this type
		Designer@ designer;
		
		if(type == DT_Flagship && randomd() < 0.05) {
			@designer = Designer(type, size * 3, emp, "Defense");
			designer.randomHull = true;
			designer.composeFlagship(haveSupport=false, tryFTL=false);
		}
		else {
			@designer = Designer(type, size, emp, "Defense");
			designer.randomHull = true;
			if(type == DT_Flagship)
				designer.composeFlagship(tryFTL=false);
		}
		
		auto@ dsg = designer.design(128);
		if(dsg !is null) {
			string name;
			if(emp is Creeps) {
				name = "Remnant "+dsg.name;
				uint try = 0;
				while(emp.getDesign(name) !is null) {
					name = "Remnant "+dsg.name + " ";
					appendRoman(++try, name);
				}
			}
			else {
				name = locale::INVADER;
				uint try = 0;
				while(emp.getDesign(name) !is null) {
					name = locale::INVADER+" ";
					appendRoman(++try, name);
				}
			}

			dsg.rename(name);

			emp.addDesign(emp.getDesignClass("Defense"), dsg);
			remnants.insertLast(dsg);
			@dsg = dsg.mostUpdated();
		}
		return dsg;
	}
	else {
		return designs[randomi(0, designs.length-1)].mostUpdated();
	}
}

Ship@ spawnRemnantFleet(const vec3d& position, int size, double occupation = 1.0, Empire@ emp = Creeps) {
	const Design@ dsg = getRemnantDesign(DT_Flagship, size, emp);
	if(dsg is null)
		return null;
	if(dsg.outdated)
		@dsg = dsg.owner.updateDesign(dsg, true);

	Ship@ leader = createShip(position, dsg, emp, free=true, memorable=true);
	leader.setAutoMode(AM_RegionBound);
	leader.sightRange = 0;
	leader.setRotation(quaterniond_fromAxisAngle(vec3d_up(), randomd(-pi, pi)));

	uint supports = dsg.total(SV_SupportCapacity) * occupation;
	if(supports != 0) {
		uint supportTypes = randomd(1, 4);
		for(uint n = 0; n < supportTypes; ++n) {
			uint supportCount = randomd(5,50);
			int supportSize = floor(double(supports) / double(supportTypes) / double(supportCount));
			if(supportSize > 5)
				supportSize = floor(double(supportSize) / 5.0) * 5;
			const Design@ sup = getRemnantDesign(DT_Support, supportSize, emp);
			if(sup !is null) {
				if(sup.outdated)
					@sup = sup.owner.updateDesign(sup, true);
				for(uint i = 0; i < supportCount; ++i)
					createShip(leader.position, sup, emp, leader, free=true);
			}
		}
	}
	return leader;
}

void save(SaveFile& file) {
	uint cnt = flagships.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i) {
		file << flagships[i].owner;
		file << flagships[i].id;
	}

	cnt = supportShips.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i) {
		file << supportShips[i].owner;
		file << supportShips[i].id;
	}
}

void loadRemnantDesigns(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;
	flagships.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp;
		if(file >= SV_0140)
			file >> emp;
		else
			@emp = Creeps;

		int id = 0;
		file >> id;
		@flagships[i] = emp.getDesign(id);
	}

	file >> cnt;
	supportShips.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp;
		if(file >= SV_0140)
			file >> emp;
		else
			@emp = Creeps;

		int id = 0;
		file >> id;
		@supportShips[i] = emp.getDesign(id);
	}
}

void load(SaveFile& file) {
	loadRemnantDesigns(file);
}
