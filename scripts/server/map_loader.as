import maps;

#section server
import object_creation;
import scenario;
import systems;
#section all

final class MapSystem {
	string name;
	vec3d position;
	array<string> effects;
	bool canHaveHomeworld = true;
};

final class MapFile {
	array<MapSystem> systems;
	
	void generate(Map@ map) {
		for(uint i = 0, cnt = systems.length; i < cnt; ++i) {
			auto@ sys = systems[i];
			SystemCode code;
			
			if(sys.name.length > 0)
				code << "NameSystem(" + sys.name + ")";
			
			for(uint j = 0, jcnt = sys.effects.length; j < jcnt; ++j)
				code << sys.effects[j];
			
			map.addSystem(sys.position, code=code, canHaveHomeworld=sys.canHaveHomeworld);
		}
	}
};

MapFile@ loadMap(const string& filename) {
	ReadFile file(resolve(filename), true);
	
	MapFile mp;
	MapSystem@ sys;
	
	string key, value;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine && sys !is null) {
			sys.effects.insertLast(file.line);
		}
		else if(key == "System") {
			mp.systems.length = mp.systems.length + 1;
			@sys = mp.systems.last;
			sys.name = value;
		}
		else if(sys is null) {
			error("Invalid map: " + filename);
			break;
		}
		else if(key == "Effect") {
			sys.effects.insertLast(value);
		}
		else if(key == "Position") {
			sys.position = toVec3d(value);
		}
		else if(key == "Homeworld") {
			sys.canHaveHomeworld = toBool(value);
		}
		else {
			sys.effects.insertLast(file.line);
		}
	}
	
	return mp;
}
