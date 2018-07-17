import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Systems;

from ai.orbitals import AIOrbitals, OrbitalAIHook, OrbitalUse;
import ai.consider;

import orbitals;
import saving;

final class OrbitalAI {
	Object@ obj;
	const OrbitalModule@ type;
	double prevTick = 0;
	Object@ around;

	void init(AI& ai, Orbitals& orbitals) {
		if(obj.isOrbital)
			@type = getOrbitalModule(cast<Orbital>(obj).coreModule);
	}

	void save(Orbitals& orbitals, SaveFile& file) {
		file << obj;
	}

	void load(Orbitals& orbitals, SaveFile& file) {
		file >> obj;
	}

	void remove(AI& ai, Orbitals& orbitals) {
	}

	void tick(AI& ai, Orbitals& orbitals, double time) {
		//Deal with losing planet ownership
		if(obj is null || !obj.valid || obj.owner !is ai.empire) {
			orbitals.remove(this);
			return;
		}

		//Record what we're orbiting around
		if(around !is null) {
			if(!obj.isOrbitingAround(around))
				@around = obj.getOrbitingAround();
		}
		else {
			if(obj.hasOrbitCenter)
				@around = obj.getOrbitingAround();
		}
	}
};

class Orbitals : AIComponent, AIOrbitals {
	Budget@ budget;
	Systems@ systems;

	array<OrbitalAI@> orbitals;
	uint orbIdx = 0;

	void create() {
		@budget = cast<Budget>(ai.budget);
		@systems = cast<Systems>(ai.systems);

		//Register specialized orbital types
		for(uint i = 0, cnt = getOrbitalModuleCount(); i < cnt; ++i) {
			auto@ type = getOrbitalModule(i);
			for(uint n = 0, ncnt = type.ai.length; n < ncnt; ++n) {
				auto@ hook = cast<OrbitalAIHook>(type.ai[n]);
				if(hook !is null)
					hook.register(this, type);
			}
		}
	}

	Empire@ get_empire() {
		return ai.empire;
	}

	Considerer@ get_consider() {
		return cast<Considerer>(ai.consider);
	}

	OrbitalAI@ getInSystem(const OrbitalModule@ module, Region@ reg) {
		if(module is null)
			return null;
		for(uint i = 0, cnt = orbitals.length; i < cnt; ++i) {
			if(orbitals[i].type is module) {
				if(orbitals[i].obj.region is reg)
					return orbitals[i];
			}
		}
		return null;
	}

	bool haveInSystem(const OrbitalModule@ module, Region@ reg) {
		if(module is null)
			return false;
		for(uint i = 0, cnt = orbitals.length; i < cnt; ++i) {
			if(orbitals[i].type is module) {
				if(orbitals[i].obj.region is reg)
					return true;
			}
		}
		return false;
	}

	bool haveAround(const OrbitalModule@ module, Object@ around) {
		if(module is null)
			return false;
		for(uint i = 0, cnt = orbitals.length; i < cnt; ++i) {
			if(orbitals[i].type is module) {
				if(orbitals[i].around is around)
					return true;
			}
		}
		return false;
	}

	void registerUse(OrbitalUse use, const OrbitalModule& type) {
		switch(use) {
			case OU_Shipyard:
				@ai.defs.Shipyard = type;
			break;
		}
	}

	void save(SaveFile& file) {
		uint cnt = orbitals.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = orbitals[i];
			saveAI(file, data);
			data.save(this, file);
		}
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadAI(file);
			if(data !is null)
				data.load(this, file);
			else
				OrbitalAI().load(this, file);
		}
	}

	OrbitalAI@ loadAI(SaveFile& file) {
		Object@ obj;
		file >> obj;

		if(obj is null)
			return null;

		OrbitalAI@ data = getAI(obj);
		if(data is null) {
			@data = OrbitalAI();
			@data.obj = obj;
			data.prevTick = gameTime;
			orbitals.insertLast(data);
		}
		return data;
	}

	void saveAI(SaveFile& file, OrbitalAI@ ai) {
		Object@ obj;
		if(ai !is null)
			@obj = ai.obj;
		file << obj;
	}

	void start() {
		checkForOrbitals();
	}

	void checkForOrbitals() {
		auto@ data = ai.empire.getOrbitals();
		Object@ obj;
		while(receive(data, obj)) {
			if(obj !is null)
				register(obj);
		}
	}

	void tick(double time) {
		double curTime = gameTime;

		if(orbitals.length != 0) {
			orbIdx = (orbIdx+1) % orbitals.length;

			auto@ data = orbitals[orbIdx];
			data.tick(ai, this, curTime - data.prevTick);
			data.prevTick = curTime;
		}
	}

	uint prevCount = 0;
	double checkTimer = 0;
	void focusTick(double time) override {
		//Check for any newly obtained planets
		uint curCount = ai.empire.orbitalCount;
		checkTimer += time;
		if(curCount != prevCount || checkTimer > 60.0) {
			checkForOrbitals();
			prevCount = curCount;
			checkTimer = 0;
		}
	}

	OrbitalAI@ getAI(Object& obj) {
		for(uint i = 0, cnt = orbitals.length; i < cnt; ++i) {
			if(orbitals[i].obj is obj)
				return orbitals[i];
		}
		return null;
	}

	OrbitalAI@ register(Object& obj) {
		OrbitalAI@ data = getAI(obj);
		if(data is null) {
			@data = OrbitalAI();
			@data.obj = obj;
			data.prevTick = gameTime;
			orbitals.insertLast(data);
			data.init(ai, this);
		}
		return data;
	}

	void remove(OrbitalAI@ data) {
		data.remove(ai, this);
		orbitals.remove(data);
	}
};

AIComponent@ createOrbitals() {
	return Orbitals();
}
