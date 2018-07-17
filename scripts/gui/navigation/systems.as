#priority init 100
from settings.map_lib import SystemDesc;
import void recalculateElevation() from "navigation.elevation";
import void promptExtentRefresh() from "tabs.GalaxyTab";

SystemDesc[] Systems;

uint get_systemCount() {
	return Systems.length;
}

SystemDesc@ getSystem(uint index) {
	return Systems[index];
}

SystemDesc@ getSystem(Region@ region) {
	if(region is null || region.SystemId == -1)
		return null;
	return Systems[region.SystemId];
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

SystemDesc@ getSystem(const vec3d& point) {
	//TODO: This really should not be O(n), implement a better
	//structure for these lookups
	for(uint i = 0, cnt = Systems.length; i < cnt; ++i) {
		SystemDesc@ sys = Systems[i];
		if(point.distanceToSQ(sys.position) < sys.radius * sys.radius)
			return sys;
	}
	return null;
}

bool loaded = false, doRefresh = false;
void init() {
	if(loaded)
		return;
	Systems.syncFrom(getSystems());
}

void tick(double time) {
	if(doRefresh) {
		Systems.length = 0;
		Systems.syncFrom(getSystems());
		doRefresh = false;
		promptExtentRefresh();
		recalculateElevation();
	}
}

void save(SaveFile& data) {
	data << uint(Systems.length);
	for(uint i = 0; i < Systems.length; ++i)
		Systems[i].save(data);
}

void load(SaveFile& data) {
	loaded = true;
	uint count = 0;
	data >> count;
	Systems.length = count;
	for(uint i = 0; i < Systems.length; ++i)
		Systems[i].load(data);
}

void refreshClientSystems() {
	doRefresh = true;
}
