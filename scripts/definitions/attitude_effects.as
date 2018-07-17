import attitudes;
from attitudes import AttitudeHook;
import hooks;

import abilities;
import empire_effects;
import bonus_effects;
import systems;

class ProgressFromAttribute : AttitudeHook {
	Document doc("Take the progress value for this attitude from an empire attribute.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument multiply(AT_Decimal, "1.0", doc="Multiplication factor to attitude progress from attribute.");
	Argument retroactive(AT_Boolean, "False", doc="If set, count increases in the attribute from the start of the game, instead of from when this attitude was taken.");
	Argument monotonic(AT_Boolean, "True", doc="If not set, the attribute progress can be decreased by the attribute going down.");

#section server
	void enable(Attitude& att, Empire& emp, any@ data) const {
		double offset = 0;
		if(!retroactive.boolean)
			offset = emp.getAttribute(attribute.integer);
		data.store(offset);
	}

	void tick(Attitude& att, Empire& emp, any@ data, double time) const {
		double offset = 0;
		data.retrieve(offset);

		double next = emp.getAttribute(attribute.integer);
		if(next != offset) {
			if(!monotonic.boolean || next > offset) {
				data.store(next);
				att.progress += (next - offset) * multiply.decimal * emp.AttitudeProgressFactor;
			}
		}
	}

	void save(any@ data, SaveFile& file) const {
		double offset = 0;
		data.retrieve(offset);
		file << offset;
	}

	void load(any@ data, SaveFile& file) const {
		double offset = 0;
		file >> offset;
		data.store(offset);
	}
#section all
};

class Conflict : AttitudeHook {
	Document doc("This attitude can not be taken if a particular other attitude has already been taken.");
	Argument attitude(AT_Attitude, doc="Attitude to conflict with.");

	bool canTake(Empire& emp) const {
		return !emp.hasAttitude(attitude.integer);
	}
};

class TiedAbility : AttitudeHook {
	Document doc("An ability is tied to this attitude.");
	Argument ability(AT_Ability, doc="Ability to create tied to this attitude.");

	Ability@ showAbility(Attitude& att, Empire& emp, Ability@ abl) const {
		if(abl is null)
			@abl = Ability();
		if(receive(emp.getAbilityOfType(ability.integer), abl))
			return abl;
		return null;
	}

#section server
	void enable(Attitude& att, Empire& emp, any@ data) const {
		int id = emp.addAbility(ability.integer);
		data.store(id);
	}

	void disable(Attitude& att, Empire& emp, any@ data) const {
		int id = -1;
		data.retrieve(id);
		emp.removeAbility(id);
	}

	void save(any@ data, SaveFile& file) const {
		int id = -1;
		data.retrieve(id);
		file << id;
	}

	void load(any@ data, SaveFile& file) const {
		int id = -1;
		file >> id;
		data.store(id);
	}
#section all
};

class ProgressFromEmpirePopulation : AttitudeHook {
	Document doc("Take the progress value for this attitude from the empire's total population.");
	Argument multiply(AT_Decimal, "1.0", doc="Multiplication factor to attitude progress from attribute.");
	Argument monotonic(AT_Boolean, "True", doc="If not set, the attribute progress can be decreased by the attribute going down.");

#section server
	void enable(Attitude& att, Empire& emp, any@ data) const {
		double offset = 0;
		data.store(offset);
	}

	void tick(Attitude& att, Empire& emp, any@ data, double time) const {
		double offset = 0;
		data.retrieve(offset);

		double next = emp.TotalPopulation;
		if(next != offset) {
			if(!monotonic.boolean || next > offset) {
				data.store(next);
				att.progress += (next - offset) * multiply.decimal;
			}
		}
	}

	void save(any@ data, SaveFile& file) const {
		double offset = 0;
		data.retrieve(offset);
		file << offset;
	}

	void load(any@ data, SaveFile& file) const {
		double offset = 0;
		file >> offset;
		data.store(offset);
	}
#section all
};

tidy final class ScoutData {
	set_int flagged;
	array<uint> systems;
};

class ProgressFromScoutedSystems : AttitudeHook {
	Document doc("Progress based on the time that you are scouting systems owned by other players.");

#section server
	void enable(Attitude& att, Empire& emp, any@ data) const {
		ScoutData info;
		data.store(@info);
	}

	void tick(Attitude& att, Empire& emp, any@ data, double time) const {
		ScoutData@ info;
		data.retrieve(@info);

		uint offset = randomi(0, systemCount-1);
		for(uint n = 0; n < 10; ++n) {
			uint index = (n+offset) % systemCount;
			const SystemDesc@ sys = getSystem(index);

			bool haveScouted = true;
			if(sys.object.PlanetsMask & emp.mask != 0)
				haveScouted = false;
			else if(sys.object.PlanetsMask & ~(emp.mask | emp.ForcedPeaceMask.value | emp.visionMask) == 0)
				haveScouted = false;
			else if(sys.object.BasicVisionMask & emp.mask == 0)
				haveScouted = false;

			bool haveRecorded = info.flagged.contains(sys.index);

			if(haveRecorded && !haveScouted) {
				info.flagged.erase(sys.index);
				info.systems.remove(sys.index);
			}
			else if(!haveRecorded && haveScouted) {
				info.flagged.insert(sys.index);
				info.systems.insertLast(sys.index);
			}
		}

		if(info.systems.length != 0)
			att.progress += time * double(info.systems.length) / 60.0 * emp.AttitudeProgressFactor;
	}

	void save(any@ data, SaveFile& file) const {
		ScoutData@ info;
		data.retrieve(@info);

		uint cnt = info.systems.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << info.systems[i];
	}

	void load(any@ data, SaveFile& file) const {
		ScoutData info;
		data.store(@info);

		uint cnt = 0;
		file >> cnt;
		info.systems.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			file >> info.systems[i];
			info.flagged.insert(info.systems[i]);
		}
	}
#section all
};
