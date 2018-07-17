import tabs.Tab;
import tabs.tabbar;
import abilities;
import hooks;
from gui import isGuiHovered;

import targeting.targeting;
from obj_selection import hoveredObject, uiObject, selectedObjects;

export ObjectTargeting;
export AbilityTargetObject;
export targetObject;
export toggleAbilityTargetObject;

import Tab@ createGalaxyTab() from "tabs.GalaxyTab";

class ObjectTargeting {
	Tab@ returnTo;
	Sprite icon(spritesheet::ContextIcons, 1);
	bool allowMultiple = false;
	bool isTemporary = false;
	bool drawCrosshair = true;
	Color validIconColor = colors::Green;
	Color errorIconColor = colors::Red;
	vec2i iconSize(40, 40);

	bool valid(Object@ target) {
		return true;
	}

	void call(Object@ target) {
	}

	string message(Object@ target, bool valid) {
		return target.name;
	}

	string desc(Object@ target, bool valid) {
		return "";
	}

	string emptyMessage() {
		return "";
	}

	void hover(Object@ target, const vec2i& mouse) {
	}

	void draw(Object@ target, bool valid) {
	}

	void clear() {
	}

	void cancel() {
	}
};

class AbilityTargetObject : ObjectTargeting {
	Ability@ abl;
	Targets@ targs;

	AbilityTargetObject(Ability@ abl) {
		@this.abl = abl;
		@targs = Targets(abl.type.targets);
		icon = abl.type.icon;
	}

	bool valid(Object@ target) override {
		@targs.fill(0).obj = target;
		return abl.canActivate(targs);
	}

	void call(Object@ target) override {
		@targs.fill(0).obj = target;
		double range = abl.getRange(targs);
		array<Object@> objects = selectedObjects;
		if(objects.find(abl.obj) == -1)
			objects.insertLast(abl.obj);
		bool playedSound = false;
		for(uint i = 0, cnt = objects.length; i < cnt; ++i) {
			Object@ obj = objects[i];
			if(obj is null || (!obj.isArtifact && !obj.owner.controlled) || !obj.hasAbilities)
				continue;
			int ablId = -1;
			if(obj is abl.obj)
				ablId = abl.id;
			else
				ablId = obj.findAbilityOfType(abl.type.id);
			if(ablId != -1) {
				if(obj !is null) {
					if(obj.hasLeaderAI && range != INFINITY)
						obj.addAbilityOrder(ablId, target, range, shiftKey);
					else
						obj.activateAbility(ablId, target);
				}
				else
					abl.emp.activateAbility(ablId, target);
				if(abl.type.activateSound !is null && !playedSound) {
					abl.type.activateSound.play(priority=true);
					playedSound = true;
				}
			}
		}
	}

	string message(Object@ target, bool valid) override {
		return abl.type.name;
	}

	string desc(Object@ target, bool valid) {
		if(!valid) {
			string err = abl.getTargetError(targs);
			if(err.length != 0)
				return err;
		}
		return abl.formatCosts(targs);
	}
};

class ObjectMode : TargetMode {
	Object@ obj;
	ObjectTargeting@ targ;
	
	bool isValidTarget(Object@ obj) override {
		if(obj is null)
			return false;
		if(!targ.valid(obj))
			return false;
		return true;
	}

	bool hover(const vec2i& mouse) override {
		@obj = hoveredObject;
		if(obj is null)
			@obj = uiObject;
		targ.hover(obj, mouse);
		return isValidTarget(obj);
	}

	bool click() override {
		if(obj is null) {
			if(targ.isTemporary)
				return true;
			return false;
		}
		if(!targ.valid(obj)) {
			if(targ.isTemporary) {
				@obj = null;
				return true;
			}
			return false;
		}
		return true;
	}

	string get_message() override {
		if(obj is null)
			return targ.emptyMessage();
		return targ.message(obj, valid);
	}

	string get_desc() override {
		if(obj is null)
			return "";
		return targ.desc(obj, valid);
	}

	Object@ get_target() override {
		return obj;
	}
};

class ObjectDisplay : TargetVisuals {
	ObjectTargeting@ targ;

	void draw(TargetMode@ mode) override {
		if(isGuiHovered() && uiObject is null)
			return;

		Color color;
		if(mode.valid)
			color = Color(0x00ff00ff);
		else
			color = Color(0xff3333ff);
		if(mode.target is null)
			color = Color(0xaaaaaaff);

		Color iconColor = color;
		if(mode.target !is null && targ !is null) {
			if(mode.valid)
				iconColor = targ.validIconColor;
			else
				iconColor = targ.errorIconColor;
		}

		//Draw the cursor
		vec2i isize = vec2i(40, 40);
		Sprite icon = spritesheet::ContextIcons+1;

		if(targ !is null) {
			icon = targ.icon;
			isize = targ.iconSize;
		}
		icon.draw(recti_area(mousePos-isize/2, isize), iconColor);
		if(targ is null || targ.drawCrosshair) {
			drawLine(mousePos-vec2i(isize.x, 0), mousePos+vec2i(isize.x,0), color, 2);
			drawLine(mousePos-vec2i(0, isize.y), mousePos+vec2i(0,isize.y), color, 2);
		}

		if(targ !is null)
			targ.draw(mode.target, mode.valid);

		//Draw the message
		const Font@ ft = font::DroidSans_11_Bold;
		string err = mode.desc;
		if(err.length != 0) {
			ft.draw(recti_area(mousePos-vec2i(200,isize.y+30), vec2i(400, 20)), mode.message, horizAlign=0.5, color=color, stroke=colors::Black);
			@ft = font::OpenSans_11_Italic;
			ft.draw(recti_area(mousePos-vec2i(200,isize.y+5), vec2i(400, 20)), err, horizAlign=0.5, color=color, stroke=colors::Black);
		}
		else {
			ft.draw(recti_area(mousePos-vec2i(200,isize.y+5), vec2i(400, 20)), mode.message, horizAlign=0.5, color=color, stroke=colors::Black);
		}
	}
};

class ObjectCB : TargetCallback {
	ObjectTargeting@ targ;

	void call(TargetMode@ mode) override {
		if(targ.isTemporary && mode.target is null) {
			clear();
			return;
		}
		if(!mode.isShifted || !shiftKey)
			clear();
		targ.call(mode.target);
		targ.clear();
	}

	void clear() {
		targ.clear();
		if(targ.returnTo !is null) {
			if(targ.returnTo is ActiveTab.previous)
				popTab(ActiveTab);
			else
				switchToTab(targ.returnTo);
		}
	}

	void cancel(bool wasExplicit) {
		clear();
		if(wasExplicit)
			targ.cancel();
	}
};

void targetObject(ObjectTargeting@ target, Tab@ returnTo = null, bool gotoTab = true) {
	ObjectMode targ;
	ObjectDisplay disp;
	ObjectCB cb;

	@target.returnTo = returnTo;
	@targ.targ = target;
	@disp.targ = target;
	@cb.targ = target;

	startTargeting(targ, disp, cb);
	if(target.allowMultiple)
		targ.autoMultiple = true;

	if(gotoTab) {
		Tab@ tab = findTab(TC_Galaxy);
		if(tab !is null) {
			switchToTab(tab);
		}
		else {
			if(returnTo !is null)
				browseTab(ActiveTab, createGalaxyTab(), true);
			else
				switchToTab(newTab(createGalaxyTab()));
		}
	}
}

void toggleAbilityTargetObject(Ability@ abl) {
	auto@ om = cast<ObjectMode>(mode);
	if(om !is null) {
		auto@ t = cast<AbilityTargetObject>(om.targ);
		if(t !is null) {
			if(t.abl.obj is abl.obj && t.abl.id == abl.id) {
				return;
			}
		}
	}

	targetObject(AbilityTargetObject(abl));
}
