import hooks;
import influence;
import attributes;
import systems;
import saving;
from bonus_effects import BonusEffect;
import empire_effects;

#section server
from influence_global import modInfluenceStackSize, getLastInfluenceVoteId, getActiveInfluenceVotes, getInfluenceVotesSince, getLastInfluenceEffectId, getInfluenceEffectsSince, getSenateLeader;
#section all

#section server
tidy final class VisionEffect {
	array<bool> currentVision;
	array<Empire@> empires;
	uint mask = 0;

	//A new system that matches 'mask' should be
	//given vision over roughly every interval seconds.
	double interval = 30.0;
	double intervalMod = 0.8;
	double minInterval = 2.5;
	double maxInterval = 40.0;
	double timer = 0.0;
	uint sysIndex = 0;

	void save(SaveFile& file) {
		file << sysIndex;
		file << timer;
		file << interval;
		file << intervalMod;
		file << minInterval;
		file << maxInterval;
		file << mask;

		uint cnt = currentVision.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << currentVision[i];

		cnt = empires.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << empires[i];
	}

	void load(SaveFile& file) {
		if(file < SV_0015) {
			init();
			return;
		}

		file >> sysIndex;
		file >> timer;
		file >> interval;
		file >> intervalMod;
		file >> minInterval;
		file >> maxInterval;
		file >> mask;

		uint cnt = 0;
		file >> cnt;
		currentVision.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> currentVision[i];

		file >> cnt;
		empires.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> empires[i];
	}

	void init() {
		currentVision.length = systemCount;
		for(uint i = 0, cnt = currentVision.length; i < cnt; ++i)
			currentVision[i] = false;
	}

	void update(double time) {
		timer -= time;
		if(timer >= 0.0)
			return;

		double sysInt = interval / double(currentVision.length);
		const SystemDesc@ found;
		timer -= sysInt;
		while(timer < 0) {
			timer += sysInt;

			auto@ sys = getSystem(sysIndex);
			if(!currentVision[sysIndex]) {
				if(sys.object.TradeMask & mask != 0) {
					@found = sys;
					break;
				}
			}
			else {
				if(sys.object.TradeMask & mask == 0) {
					for(uint i = 0, cnt = empires.length; i < cnt; ++i)
						sys.object.revokeVision(empires[i]);
					currentVision[sysIndex] = false;
				}
			}

			sysIndex = (sysIndex + 1) % currentVision.length;
			if(sysIndex == 0 && found is null) {
				interval = min(interval / intervalMod, maxInterval);
				timer = sysInt;
				return;
			}
		}

		if(found !is null) {
			for(uint i = 0, cnt = empires.length; i < cnt; ++i)
				found.object.grantVision(empires[i]);
			currentVision[sysIndex] = true;
			timer = sysInt * double(currentVision.length - sysIndex);
			interval = max(interval * intervalMod, minInterval);
		}
		else {
			timer = sysInt;
		}
	}

	void disable() {
		for(uint n = 0, ncnt = currentVision.length; n < ncnt; ++n) {
			if(currentVision[n]) {
				auto@ sys = getSystem(n);
				for(uint i = 0, cnt = empires.length; i < cnt; ++i)
					sys.object.revokeVision(empires[i]);
			}
		}
	}
};
#section all

class GrantVisionOver : InfluenceEffectEffect {
	Document doc("Grants vision over a target empire.");
	Argument targ(TT_Empire);

#section server
	void onStart(InfluenceEffect@ eff) const override {
		Empire@ to = arguments[0].fromTarget(eff.targets).emp;

		VisionEffect ve;
		ve.init();
		ve.empires.insertLast(eff.owner);
		ve.mask = to.mask;

		eff.data[hookIndex].store(@ve);
	}

	bool onTick(InfluenceEffect@ eff, double time) const override {
		VisionEffect@ ve;
		eff.data[hookIndex].retrieve(@ve);
		if(ve is null)
			return true;
		ve.update(time);
		return false;
	}

	void onEnd(InfluenceEffect@ eff) const override {
		VisionEffect@ ve;

		eff.data[hookIndex].retrieve(@ve);
		if(ve !is null)
			ve.disable();

		@ve = null;
		eff.data[hookIndex].store(@ve);
	}

	void save(InfluenceEffect@ effect, SaveFile& file) const {
		VisionEffect@ ve;
		effect.data[hookIndex].retrieve(@ve);
		ve.save(file);
	}

	void load(InfluenceEffect@ effect, SaveFile& file) const {
		VisionEffect ve;
		effect.data[hookIndex].store(@ve);
		ve.load(file);
	}
#section all
};

class GrantEveryoneVisionOver : InfluenceEffectEffect {
	Document doc("Grants vision over a empire to everyone.");
	Argument targ(TT_Empire);

#section server
	void onStart(InfluenceEffect@ eff) const override {
		Empire@ to = arguments[0].fromTarget(eff.targets).emp;

		VisionEffect ve;
		ve.init();
		ve.mask = to.mask;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(emp.major && emp !is to)
				ve.empires.insertLast(emp);
		}

		eff.data[hookIndex].store(@ve);
	}

	bool onTick(InfluenceEffect@ eff, double time) const override {
		VisionEffect@ ve;
		eff.data[hookIndex].retrieve(@ve);
		if(ve is null)
			return true;
		ve.update(time);
		return false;
	}

	void onEnd(InfluenceEffect@ eff) const override {
		VisionEffect@ ve;

		eff.data[hookIndex].retrieve(@ve);
		if(ve !is null)
			ve.disable();

		@ve = null;
		eff.data[hookIndex].store(@ve);
	}

	void save(InfluenceEffect@ effect, SaveFile& file) const {
		VisionEffect@ ve;
		effect.data[hookIndex].retrieve(@ve);
		ve.save(file);
	}

	void load(InfluenceEffect@ effect, SaveFile& file) const {
		VisionEffect ve;
		effect.data[hookIndex].store(@ve);
		ve.load(file);
	}
#section all
};

//CancelOnWar(<Target>)
// Cancel the effect when the owner becomes at war with the target.
class CancelOnWar : InfluenceEffectEffect {
	Document doc("Ends the influence effect when war is declared between this empire and the target.");
	Argument targ(TT_Empire);

#section server
	bool onTick(InfluenceEffect@ eff, double time) const override {
		Empire@ to = arguments[0].fromTarget(eff.targets).emp;
		if(eff.owner !is null && eff.owner.isHostile(to))
			eff.end();
		return false;
	}
#section all
};

class CancelIfNotLeader : InfluenceEffectEffect {
	Document doc("Cancel the effect if the owner is not the senate leader.");

#section server
	bool onTick(InfluenceEffect@ eff, double time) const override {
		if(eff.owner !is getSenateLeader())
			eff.end();
		return false;
	}
#section all
};

class CancelIfAttributeLT : InfluenceEffectEffect {
	Document doc("Cancel the effect if the owner's attribute is too low.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

#section server
	bool onTick(InfluenceEffect@ eff, double time) const override {
		Empire@ owner = eff.owner;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) < value.decimal)
			eff.end();
		return false;
	}
#section all
};

//ModAttribute(<Attribute>, <Mode>, <Value>)
// Modify an empire attribute while the effect is active.
// Mode is one of: Add, AddBase, AddFactor, Multiply
class ModAttribute : InfluenceEffectEffect {
	Document doc("Changes an empire's specified attribute.");
	Argument attr("Attribute", AT_EmpAttribute, doc="ID of the empire attribute to affect.");
	Argument mode("Mode", AT_AttributeMode, doc="How to change the attribute (Add, AddBase, AddFactor, Multiply).");
	Argument val("Value", AT_Decimal, doc="Value to change by.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		eff.owner.modAttribute(uint(arguments[0].integer), arguments[1].integer, arguments[2].decimal);
	}

	void onEnd(InfluenceEffect@ eff) const override {
		double value = arguments[2].decimal;
		if(arguments[1].integer == int(AC_Multiply))
			value = 1.0 / value;
		else
			value = -value;
		eff.owner.modAttribute(uint(arguments[0].integer), arguments[1].integer, value);
	}
#section all
};


//ModAttributeAll(<Attribute>, <Mode>, <Value>)
// Modify an attribute on all empires while an effect is active.
// Mode is one of: Add, AddBase, AddFactor, Multiply
class ModAttributeAll : InfluenceEffectEffect {
	Document doc("Changes all empires' specified attribute.");
	Argument attr("Attribute", AT_EmpAttribute, doc="ID of the empire attribute to affect.");
	Argument mode("Mode", AT_AttributeMode, doc="How to change the attribute (Add, AddBase, AddFactor, Multiply).");
	Argument val("Value", AT_Decimal, doc="Value to change by.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, arguments[2].decimal);
		}
	}

	void onEnd(InfluenceEffect@ eff) const override {
		double value = arguments[2].decimal;
		if(arguments[1].integer == int(AC_Multiply))
			value = 1.0 / value;
		else
			value = -value;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, value);
		}
	}
#section all
};

//ModAttributeOther(<Attribute>, <Mode>, <Value>)
// Modify an attribute on all other empires while an effect is active.
// Mode is one of: Add, AddBase, AddFactor, Multiply
class ModAttributeOther: InfluenceEffectEffect {
	Document doc("Changes all other empires' specified attribute.");
	Argument attr("Attribute", AT_EmpAttribute, doc="ID of the empire attribute to affect.");
	Argument mode("Mode", AT_AttributeMode, doc="How to change the attribute (Add, AddBase, AddFactor, Multiply).");
	Argument val("Value", AT_Decimal, doc="Value to change by.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is eff.owner)
				continue;
			emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, arguments[2].decimal);
		}
	}

	void onEnd(InfluenceEffect@ eff) const override {
		double value = arguments[2].decimal;
		if(arguments[1].integer == int(AC_Multiply))
			value = 1.0 / value;
		else
			value = -value;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is eff.owner)
				continue;
			emp.modAttribute(uint(arguments[0].integer), arguments[1].integer, value);
		}
	}
#section all
};

//ModAttributeTarget(<Target>, <Attribute>, <Mode>, <Value>)
// Modify an attribute on a particular empire while the effect is active.
// Mode is one of: Add, AddBase, AddFactor, Multiply
class ModAttributeTarget: InfluenceEffectEffect {
	Document doc("Changes a targeted empire's specified attribute.");
	Argument targ(TT_Empire);
	Argument attr("Attribute", AT_EmpAttribute, doc="ID of the empire attribute to affect.");
	Argument mode("Mode", AT_AttributeMode, doc="How to change the attribute (Add, AddBase, AddFactor, Multiply).");
	Argument val("Value", AT_Decimal, doc="Value to change by.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		Target@ targ = arguments[0].fromTarget(eff.targets);
		if(targ is null || targ.emp is null)
			return;
		targ.emp.modAttribute(uint(arguments[1].integer), arguments[2].integer, arguments[3].decimal);
	}

	void onEnd(InfluenceEffect@ eff) const override {
		Target@ targ = arguments[0].fromTarget(eff.targets);
		if(targ is null || targ.emp is null)
			return;
		double value = arguments[3].decimal;
		if(arguments[2].integer == int(AC_Multiply))
			value = 1.0 / value;
		else
			value = -value;
		targ.emp.modAttribute(uint(arguments[1].integer), arguments[2].integer, value);
	}
#section all
};

//ModInfluenceStackSize(<Amount>)
// Increase the size of the influence stack by <Amount>.
class ModInfluenceStackSize : InfluenceEffectEffect {
	Document doc("Changes how many cards are available to purchase at a time while active.");
	Argument val("Amount", AT_Integer, doc="Number of cards to add.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		modInfluenceStackSize(+arguments[0].integer);
	}

	void onEnd(InfluenceEffect@ eff) const override {
		modInfluenceStackSize(-arguments[0].integer);
	}
#section all
};

//ProtectSystem(<Target>)
// Declare the system as protected.
class ProtectSystem : InfluenceEffectEffect {
	Document doc("Prevents an empire's planets in a targeted system from sieges while active.");
	Argument targ(TT_Object);

#section server
	bool onTick(InfluenceEffect@ eff, double time) const override {
		Target@ targ = arguments[0].fromTarget(eff.targets);
		if(targ is null || targ.obj is null || !targ.obj.isRegion)
			return false;
		cast<Region>(targ.obj).ProtectedMask |= eff.owner.mask;
		return false;
	}

	void onEnd(InfluenceEffect@ eff) const override {
		Target@ targ = arguments[0].fromTarget(eff.targets);
		if(targ is null || targ.obj is null || !targ.obj.isRegion)
			return;
		cast<Region>(targ.obj).ProtectedMask &= ~eff.owner.mask;
	}
#section all
};

//GainLeverageWhenVoteStarted(<Quality Factor> = 1.0)
// Whenever a vote is started, gain leverage on the starter.
class GainLeverageWhenVoteStarted : InfluenceEffectEffect {
	Document doc("Gives leverage against any empire which starts a vote to this empire.");
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic quality value to determine how much is rewarded.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		int last = getLastInfluenceVoteId();
		eff.data[hookIndex].store(last);
	}

	bool onTick(InfluenceEffect@ eff, double time) const override {
		int last = -1;
		eff.data[hookIndex].retrieve(last);

		auto@ list = getInfluenceVotesSince(last);
		if(list is null)
			return false;

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ vote = list[i];
			if(vote.startedBy !is eff.owner && vote.startedBy.valid && eff.owner.ContactMask & vote.startedBy.mask != 0)
				eff.owner.gainRandomLeverage(vote.startedBy, arguments[0].decimal);
			last = max(last, int(vote.id));
		}

		eff.data[hookIndex].store(last);
		return false;
	}

	void save(InfluenceEffect@ eff, SaveFile& file) const override {
		int last = -1;
		eff.data[hookIndex].retrieve(last);
		file << last;
	}

	void load(InfluenceEffect@ eff, SaveFile& file) const override {
		int last = -1;
		if(file >= SV_0089)
			file >> last;
		else
			last = getLastInfluenceVoteId();
		eff.data[hookIndex].store(last);
	}
#section all
};

//GainLeverageWhenEffectStarted(<Quality Factor> = 1.0)
// Whenever a effect is started, gain leverage on the starter.
class GainLeverageWhenEffectStarted : InfluenceEffectEffect {
	Document doc("Gives leverage against any empire which starts an effect to this empire.");
	Argument qual("Quality Factor", AT_Decimal, "1.0", doc="Magic quality value to determine how much is rewarded.");

#section server
	void onStart(InfluenceEffect@ eff) const override {
		int last = getLastInfluenceEffectId();
		eff.data[hookIndex].store(last);
	}

	bool onTick(InfluenceEffect@ eff, double time) const override {
		int last = 0;
		eff.data[hookIndex].retrieve(last);

		auto@ list = getInfluenceEffectsSince(last);
		if(list is null)
			return false;

		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ effect = list[i];
			if(effect.owner !is eff.owner && effect.owner.valid && eff.owner.ContactMask & effect.owner.mask != 0)
				eff.owner.gainRandomLeverage(effect.owner, arguments[0].decimal);
			last = max(last, int(effect.id));
		}

		eff.data[hookIndex].store(last);
		return false;
	}

	void save(InfluenceEffect@ eff, SaveFile& file) const override {
		int last = -1;
		eff.data[hookIndex].retrieve(last);
		file << last;
	}

	void load(InfluenceEffect@ eff, SaveFile& file) const override {
		int last = -1;
		if(file >= SV_0089)
			file >> last;
		else
			last = getLastInfluenceEffectId();
		eff.data[hookIndex].store(last);
	}
#section all
};

class OnEnable : InfluenceEffectEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when the effect enables.");
	Argument function(AT_Hook, "bonus_effects::EmpireTrigger");
	Argument all_empires(AT_Boolean, "False", doc="When set, trigger the hook on all empires, instead of just the effect owner.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnEnable(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return InfluenceEffectEffect::instantiate();
	}

#section server
	void onStart(InfluenceEffect@ eff) const override {
		if(hook !is null) {
			if(all_empires.boolean) {
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					auto@ emp = getEmpire(i);
					if(emp.valid && emp.major)
						hook.activate(null, emp);
				}
			}
			else {
				hook.activate(null, eff.owner);
			}
		}
	}
#section all
};

class OnDisable : InfluenceEffectEffect {
	BonusEffect@ hook;

	Document doc("Trigger a bonus effect when the effect disables.");
	Argument function(AT_Hook, "bonus_effects::EmpireTrigger");
	Argument all_empires(AT_Boolean, "False", doc="When set, trigger the hook on all empires, instead of just the effect owner.");

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(arguments[0].str, "bonus_effects::", required=false));
		if(hook is null) {
			error("OnDisable(): could not find inner hook: "+escape(arguments[0].str));
			return false;
		}
		return InfluenceEffectEffect::instantiate();
	}

#section server
	void onEnd(InfluenceEffect@ eff) const override {
		if(hook !is null) {
			if(all_empires.boolean) {
				for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
					auto@ emp = getEmpire(i);
					if(emp.valid && emp.major)
						hook.activate(null, emp);
				}
			}
			else {
				hook.activate(null, eff.owner);
			}
		}
	}
#section all
};

class OnAllEmpires : InfluenceEffectEffect {
	EmpireEffect@ eff;

	Document doc("Apply an effect to all empires, instead of just the owner of the effect.");
	Argument hookID("Hook", AT_Hook, "empire_effects::EmpireEffect");
	Argument apply_on_owner(AT_Boolean, "True", doc="Whether to also apply the effect on the owner, or just others.");

	bool instantiate() override {
		@eff = cast<EmpireEffect>(parseHook(hookID.str, "empire_effects::", required=false));
		if(eff is null) {
			error("OnAllEmpires(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return InfluenceEffectEffect::instantiate();
	}

	void onStart(InfluenceEffect@ effect) const override {
		array<any> arr(getEmpireCount());
		effect.data[hookIndex].store(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is effect.owner && !apply_on_owner.boolean)
				continue;
			eff.enable(emp, arr[i]);
		}
	}

	bool onTick(InfluenceEffect@ effect, double time) const override {
		array<any>@ arr;
		effect.data[hookIndex].retrieve(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is effect.owner && !apply_on_owner.boolean)
				continue;
			eff.tick(emp, arr[i], time);
		}
		return false;
	}

	void onEnd(InfluenceEffect@ effect) const override {
		array<any>@ arr;
		effect.data[hookIndex].retrieve(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is effect.owner && !apply_on_owner.boolean)
				continue;
			eff.disable(emp, arr[i]);
		}
	}

	void save(InfluenceEffect@ effect, SaveFile& file) const {
		array<any>@ arr;
		effect.data[hookIndex].retrieve(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is effect.owner && !apply_on_owner.boolean)
				continue;
			eff.save(arr[i], file);
		}
	}

	void load(InfluenceEffect@ effect, SaveFile& file) const {
		array<any> arr(getEmpireCount());
		effect.data[hookIndex].store(@arr);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;
			if(emp is effect.owner && !apply_on_owner.boolean)
				continue;
			eff.load(arr[i], file);
		}
	}
};
