import random_events;
import target_filters;
import bonus_effects;

class SelectRandomOwnedPlanet : RandomEventHook {
	Document doc("When the event is triggered, fill the specified target with a random planet owned by the empire, meeting all target filters.");
	Argument objTarget(TT_Object);

	bool consider(CurrentEvent& evt) const override {
		Target@ targ = objTarget.fromTarget(evt.targets);
		if(targ.filled)
			return true;
		Object@ selected;

		DataList@ objs = evt.owner.getPlanets();
		Object@ obj;
		double count = 0;
		while(receive(objs, obj)) {
			@targ.obj = obj;
			targ.filled = true;

			if(evt.isValidTarget(objTarget.integer, targ)) {
				count += 1;
				if(randomd() < 1.0 / count)
					@selected = obj;
			}
		}

		if(selected is null) {
			targ.filled = false;
			return false;
		}
		@targ.obj = selected;
		targ.filled = true;
		return true;
	}
};

class SendZoomTo : RandomOptionHook {
	Document doc("Tell the client to zoom to show this object when the option is triggered.");
	Argument objTarget(TT_Object);

#section server
	void trigger(CurrentEvent& evt, const EventOption& option, const Target@ on) const override {
		Target@ targ = objTarget.fromTarget(evt.targets);
		if(targ is null || targ.obj is null || evt.owner is null)
			return;
		Player@ pl = evt.owner.player;
		if(pl !is null)
			sendClientZoom(pl, targ.obj);
	}
#section all
};

class SelectRandomEmpire : RandomEventHook {
	Document doc("When the event is triggered, fill the specified target with a random empire.");
	Argument empTarget(TT_Empire);
	Argument require_contact(AT_Boolean, "True", doc="Whether to only select empires that are in contact with the event's owner.");
	Argument allow_self(AT_Boolean, "False", doc="Whether to allow the owner of the effect to be selected.");

	bool consider(CurrentEvent& evt) const override {
		Target@ targ = empTarget.fromTarget(evt.targets);
		if(targ.filled)
			return true;
		Empire@ selected;
		Empire@ owner = evt.owner;

		double count = 0;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			@targ.emp = getEmpire(i);
			targ.filled = true;

			if(!targ.emp.major)
				continue;
			if(require_contact.boolean && owner.ContactMask & targ.emp.mask == 0)
				continue;
			if(!allow_self.boolean && owner is targ.emp)
				continue;
			if(!evt.isValidTarget(empTarget.integer, targ))
				continue;

			count += 1;
			if(randomd() < 1.0 / count)
				@selected = targ.emp;
		}

		if(selected is null) {
			targ.filled = false;
			return false;
		}
		@targ.emp = selected;
		targ.filled = true;
		return true;
	}
};
