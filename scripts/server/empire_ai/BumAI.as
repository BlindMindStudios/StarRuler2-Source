import settings.game_settings;
from empire_ai.EmpireAI import AIController;

class BumAI : AIController {
	array<Planet@> planets;
	
	void debugAI() {
	}
	
	vec3d get_aiFocus() {
		return vec3d();
	}
	
	int getDifficultyLevel() {
		return 0;
	}
	
	void commandAI(string cmd) {
	}

	void aiPing(Empire@ fromEmpire, vec3d position, uint type) {
	}

	void init(Empire& emp, EmpireSettings& settings) {
	}
	
	void init(Empire& emp) {
	}

	void tick(Empire& emp, double time) {
		if(planets.length > 0) {
			Planet@ planet = planets[0];
			if(planet.constructionCount == 0) {
				planet.buildFlagship(emp.designs[0]);
			}
		}
		else {
			uint objects = emp.objectCount;
			for(uint i = 0; i < objects; ++i) {
				Planet@ pl = cast<Planet>(emp.objects[i]);
				if(pl !is null)
					planets.insertLast(pl);
			}
		}
	}

	void pause(Empire& emp) {
	}

	void resume(Empire& emp) {
	}

	void load(SaveFile& msg) {
	}

	void save(SaveFile& msg) {
	}
	
	string getOpinionOf(Empire& emp, Empire@ other) {
		return "";
	}
	
	int getStandingTo(Empire& emp, Empire@ other) {
		return 0;
	}
};

AIController@ createBumAI() {
	return BumAI();
}
