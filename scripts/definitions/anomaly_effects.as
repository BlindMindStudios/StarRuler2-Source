import hooks;
import anomalies;
import research;
from anomalies import IAnomalyHook, AnomalyHook;
import bonus_effects;
import target_filters;

class ProgressToState : AnomalyHook {
	Document doc("Progresses the anomaly to a specified state.");
	Argument goal("State", AT_Custom, doc="ID of the target state.");
	const AnomalyState@ state;

#section server
	void init(AnomalyType@ type) override {
		@state = type.getState(goal.str);
		if(state is null)
			error("ProgressState(): Could not find state "+goal.str);
	}

	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const override {
		if(state !is null)
			obj.progressToState(state.id);
	}
#section all
};

//Trigger(<Object>, <Hook>(...))
// Run <Hook> as a single-time effect hook on <Planet>.
class Trigger : AnomalyHook {
	Document doc("Runs another type of hook on the target when the activated.");
	Argument planet(TT_Object);
	Argument hookID("Hook", AT_Hook, "bonus_effects::BonusEffect", doc="Hook to run.");
	BonusEffect@ hook;

	bool instantiate() override {
		@hook = cast<BonusEffect>(parseHook(hookID.str, "bonus_effects::"));
		if(hook is null) {
			error("BonusEffect(): could not find inner hook: "+escape(hookID.str));
			return false;
		}
		return AnomalyHook::instantiate();
	}

#section server
	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const override {
		auto@ objTarg = arguments[0].fromTarget(targets);
		if(objTarg is null || objTarg.obj is null)
			return;
		hook.activate(objTarg.obj, emp);
	}
#section all
};
