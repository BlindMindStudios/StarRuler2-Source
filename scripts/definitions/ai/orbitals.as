import hooks;
import orbitals;

import ai.consider;

interface AIOrbitals : ConsiderComponent {
	Empire@ get_empire();
	Considerer@ get_consider();

	void registerUse(OrbitalUse use, const OrbitalModule& type);
};

enum OrbitalUse {
	OU_Shipyard,
};

const array<string> OrbitalUseName = {
	"Shipyard",
};

class OrbitalAIHook : Hook, ConsiderHook {
	double consider(Considerer& cons, Object@ obj) const {
		return 0.0;
	}

	void register(AIOrbitals& orbitals, const OrbitalModule& type) const {
	}

	//Return a system or a planet to build this orbital in/around
	Object@ considerBuild(AIOrbitals& orbitals, const OrbitalModule& type) const {
		return null;
	}
};

class RegisterForUse : OrbitalAIHook {
	Document doc("Register this orbital for a particular use. Only one orbital can be used for a specific specialized use.");
	Argument use(AT_Custom, doc="Specialized usage for this orbital.");

	void register(AIOrbitals& orbitals, const OrbitalModule& type) const override {
		for(uint i = 0, cnt = OrbitalUseName.length; i < cnt; ++i) {
			if(OrbitalUseName[i] == use.str) {
				orbitals.registerUse(OrbitalUse(i), type);
				return;
			}
		}
	}
};
