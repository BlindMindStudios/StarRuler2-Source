#section game
from settings.map_lib import SystemDesc;

#section gui
from navigation.systems import get_systemCount, getSystem;
#section server-side
from game_start import get_systemCount, getSystem;
#section menu
uint get_systemCount() { return 0; }
#section game
import system_pathing;

enum RegionEffectType {
	RET_TaxIncome,
	RET_Null,
};

class RegionEffect {
	int id = -1;
	Empire@ forEmpire;
	RegionEffectType type = RET_Null;

	void save(SaveFile& msg) {
		msg << uint(type);
		msg << id;
		msg << forEmpire;
	}

	void enable(Object& obj) {
	}

	void disable(Object& obj) {
	}

	void ownerChange(Object& obj, Empire@ prevOwner, Empire@ newOwner) {
	}
};

bool hasTradeAdjacent(Empire@ emp, Region@ region) {
	if(region is null)
		return false;
	if(region.TradeMask & emp.TradeMask.value != 0)
		return true;

	auto@ sys = getSystem(region);
	if(sys is null)
		return false;

	for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
		auto@ other = getSystem(sys.adjacent[i]);
		if(other.object.TradeMask & emp.TradeMask.value != 0)
			return true;
	}
	for(uint i = 0, cnt = sys.wormholes.length; i < cnt; ++i) {
		auto@ other = getSystem(sys.wormholes[i]);
		if(other.object.TradeMask & emp.TradeMask.value != 0)
			return true;
	}
	return false;
}

bool hasPlanetsAdjacent(Empire@ emp, Region@ region) {
	if(region is null)
		return false;
	if(region.TradeMask & emp.TradeMask.value != 0)
		return true;

	auto@ sys = getSystem(region);
	if(sys is null)
		return false;

	for(uint i = 0, cnt = sys.adjacent.length; i < cnt; ++i) {
		auto@ other = getSystem(sys.adjacent[i]);
		if(other.object.PlanetsMask & emp.mask != 0)
			return true;
	}
	for(uint i = 0, cnt = sys.wormholes.length; i < cnt; ++i) {
		auto@ other = getSystem(sys.wormholes[i]);
		if(other.object.PlanetsMask & emp.mask != 0)
			return true;
	}
	return false;
}
