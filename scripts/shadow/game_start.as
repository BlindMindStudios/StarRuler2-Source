import settings.map_lib;
import maps;
import regions.regions;

SystemDesc[] systems;
Map@[] galaxies;

void getSystems() {
	uint cnt = systems.length;
	for(uint i = 0; i < cnt; ++i)
		yield(systems[i]);
}

uint get_systemCount() {
	return systems.length;
}

SystemDesc@ getSystem(uint index) {
	if(index >= systems.length)
		return null;
	return systems[index];
}

SystemDesc@ getSystem(Region@ region) {
	if(region.SystemId == -1 || region.SystemId >= int(systems.length))
		return null;
	return systems[region.SystemId];
}

SystemDesc@ getSystem(const string& name) {
	//TODO: Use dictionary
	uint cnt = systemCount;
	for(uint i = 0; i < cnt; ++i) {
		if(getSystem(i).name == name)
			return getSystem(i);
	}
	return null;
}

void syncInitial(Message& msg) {
	//Read systems
	uint cnt = 0;
	msg >> cnt;
	systems.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		systems[i].read(msg);

	//Set player empire
	if(playerEmpire is null) {
		CURRENT_PLAYER.linkEmpire(spectatorEmpire);
		@playerEmpire = spectatorEmpire;
	}

	//Read maps
	msg >> cnt;
	galaxies.length = cnt;
	for(uint i = 0; i < cnt; ++i) {
		string ident;
		msg >> ident;
		@galaxies[i] = getMap(ident).create();
	}
	
	//Generate gas nodes & sprites
	msg >> cnt;
	for(uint i = 0; i < cnt; ++i) {
		GalaxyGas@ gas = GalaxyGas();
		gas.position = msg.readSmallVec3();
		gas.scale = msg.read_float();
		
		if(msg.readBit()) {
			vec3d origin = msg.readSmallVec3();
			double radius = msg.read_float();
			Node@ parent = createCullingNode(origin, radius);
			gas.reparent(parent);
		}
		
		gas.rebuildTransform();
		
		vec3d pos;
		float size = 0;
		uint col = 0;
		
		uint spriteCount = msg.readSmall();
		for(uint s = 0; s < spriteCount; ++s) {
			pos = msg.readSmallVec3();
			size = msg.read_float();
			msg >> col;
			bool structured = msg.readBit();
			
			gas.addSprite(pos, size, col, structured);
		}
	}
}

void recvPeriodic(Message& msg) {
	SystemUpdate upd;
	uint cnt = 0;
	msg >> cnt;
	upd.systems.length = cnt;
	for(uint i = 0; i < cnt; ++i)
		upd.systems[i].read(msg);

	isolate_run(upd);
}

class SystemUpdate : IsolateHook {
	SystemDesc[] systems;

	void call() {
		uint oldCnt = ::systems.length;
		::systems.length = systems.length;
		for(uint i = 0, cnt = systems.length; i < cnt; ++i)
			::systems[i] = systems[i];
		for(uint i = oldCnt, cnt = systems.length; i < cnt; ++i)
			addRegion(::systems[i].object);
		calcGalaxyExtents();
		regenerateRegionGroups();
		refreshClientSystems();
	}
}

void init() {
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].initDefs();
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].init();
}

void tick(double time) {
	for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
		galaxies[i].tick(time);
}
