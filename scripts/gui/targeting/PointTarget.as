import navigation.SmartCamera;
from input import activeCamera, mouseToGrid;
from gui import isGuiHovered;
import abilities;
import targeting.targeting;
import tabs.Tab;
import tabs.tabbar;
import Tab@ createGalaxyTab() from "tabs.GalaxyTab";

class PointTargeting {
	Tab@ returnTo;
	Sprite icon(spritesheet::ContextIcons, 1);
	bool allowMultiple = false;

	bool valid(const vec3d& pos) {
		return true;
	}

	string message(const vec3d& pos, bool valid) {
		return "";
	}

	void call(const vec3d& pos) {
	}

	string desc(const vec3d& point, bool valid) {
		return "";
	}

	double radius(const vec3d& point) {
		return 0.0;
	}

	Color get_color() {
		return Color(0x00000000);
	}
};

class AbilityTargetPoint : PointTargeting {
	Ability@ abl;
	Targets@ targs;

	AbilityTargetPoint(Ability@ abl) {
		@this.abl = abl;
		icon = abl.type.icon;
		@targs = Targets(abl.type.targets);
	}

	bool valid(const vec3d& target) override {
		targs.fill(0).point = target;
		return abl.canActivate(targs);
	}

	void call(const vec3d& target) override {
		double range = abl.getRange(targs);
		if(abl.obj !is null && abl.obj.hasLeaderAI && range != INFINITY)
			abl.obj.addAbilityOrder(abl.id, target, range, shiftKey);
		else if(abl.obj !is null)
			abl.obj.activateAbility(abl.id, target);
		else
			abl.emp.activateAbility(abl.id, target);
		if(abl.type.activateSound !is null)
			abl.type.activateSound.play(priority=true);
	}

	string message(const vec3d& target, bool valid) override {
		return abl.type.name;
	}

	string desc(const vec3d& point, bool valid) {
		if(!valid) {
			string err = abl.getTargetError(targs);
			if(err.length != 0)
				return err;
		}
		double cost = abl.getEnergyCost(targs);
		if(cost != 0 && cost != abl.type.energyCost)
			return format("$1 $2", toString(cost,0), locale::RESOURCE_ENERGY);
		return "";
	}
};

class PointTargetMode : TargetMode {
	PointTargeting@ targ;
	vec3d hovered;

	bool hover(const vec2i& mouse) override {
		hovered = mouseToGrid(mouse);
		if(!targ.valid(hovered))
			return false;
		return true;
	}

	bool click() override {
		if(!targ.valid(hovered))
			return false;
		return true;
	}

	string get_message() override {
		return targ.message(hovered, valid);
	}

	string get_desc() override {
		return targ.desc(hovered, valid);
	}

	double get_radius() {
		return targ.radius(hovered);
	}
};

class PointTargetDisplay : TargetVisuals {
	PointTargeting@ targ;
	void draw(TargetMode@ mode) override {
		if(isGuiHovered())
			return;

		Color color = targ.color;
		if(color.a == 0) {
			if(mode.valid)
				color = Color(0x00ff00ff);
			else
				color = Color(0xff0000ff);
		}

		//Draw the cursor
		drawLine(mousePos-vec2i(40, 0), mousePos+vec2i(40,0), color, 2);
		drawLine(mousePos-vec2i(0, 40), mousePos+vec2i(0,40), color, 2);
		targ.icon.draw(recti_area(mousePos-vec2i(20,20), vec2i(40,40)), color);

		//Draw the message
		const Font@ ft = font::DroidSans_11_Bold;
		string err = mode.desc;
		if(err.length != 0) {
			ft.draw(recti_area(mousePos-vec2i(200,85), vec2i(400, 20)), mode.message, horizAlign=0.5, color=color);
			@ft = font::OpenSans_11_Italic;
			ft.draw(recti_area(mousePos-vec2i(200,65), vec2i(400, 20)), err, horizAlign=0.5, color=color);
		}
		else {
			ft.draw(recti_area(mousePos-vec2i(200,65), vec2i(400, 20)), mode.message, horizAlign=0.5, color=color);
		}
	}
};

class PointTargetCB : TargetCallback {
	PointTargeting@ targ;
	void call(TargetMode@ mode) override {
		if(targ.returnTo !is null) {
			if(targ.returnTo is ActiveTab.previous)
				popTab(ActiveTab);
			else
				switchToTab(targ.returnTo);
		}
		targ.call(cast<PointTargetMode>(mode).hovered);
	}
};

void targetPoint(PointTargeting@ target, Tab@ returnTo = null, bool gotoTab = true) {
	PointTargetMode targ;
	PointTargetDisplay disp;
	PointTargetCB cb;

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

class PointTarget : TargetMode {
	Object@ originObj;
	vec3d originPos;
	vec3d hovered;
	double range = -1.0;

	vec3d get_origin() {
		if(originObj !is null)
			return originObj.node_position;
		return originPos;
	}

	bool hover(const vec2i& mouse) override {
		hovered = mouseToGrid(mouse);
		return true;
	}

	bool click() override {
		return true;
	}

	vec3d get_position() override {
		return hovered;
	}

	double get_distance() {
		return origin.distanceTo(position);
	}

	double get_radius() {
		return 0.0;
	}
};

class PointDisplay : TargetVisuals {
	BeamNode@ node;
	BeamNode@ node2;
	PlaneNode@ plane;

	Color inColor = colors::Green;
	Color outColor = colors::Red;
	Color radiusColor = Color(0x00c0ff80);

	PointDisplay() {
		@node = BeamNode(material::MoveBeam, 0.002f, vec3d(), vec3d(), true);
		node.visible = false;

		@node2 = BeamNode(material::MoveBeam, 0.002f, vec3d(), vec3d(), true);
		node2.visible = false;

		@plane = PlaneNode(material::Circle, 0.0);
		plane.visible = false;
		plane.color = radiusColor;
	}

	~PointDisplay() {
		node.visible = false;
		node.markForDeletion();
		node2.visible = false;
		node2.markForDeletion();
		plane.visible = false;
		plane.markForDeletion();
	}

	void render(TargetMode@ mode) override {
		PointTarget@ pt = cast<PointTarget>(mode);
		if(pt is null)
			return;

		if(pt.range >= 0.0 && pt.distance > pt.range) {
			vec3d origin = pt.origin;
			vec3d target = pt.position;

			vec3d dir = (target - origin).normalize(pt.range);
			vec3d midpos = origin + dir;

			//In range section
			node.position = origin;
			node.endPosition = midpos;
			node.rebuildTransform();
			node.color = inColor;
			node.visible = true;

			//Out of range section
			node2.position = midpos;
			node2.endPosition = target;
			node2.rebuildTransform();
			node2.color = outColor;
			node2.visible = true;
		}
		else {
			node.position = pt.origin;
			node.endPosition = pt.position;
			node.rebuildTransform();
			node.color = inColor;

			node.visible = true;
			node2.visible = false;
		}

		double rad = pt.radius;
		if(rad != 0) {
			plane.position = pt.position;
			plane.scale = rad;
			plane.rebuildTransform();
			plane.visible = true;
		}
		else {
			plane.visible = false;
		}
	}
};

void toggleAbilityTargetPoint(Ability@ abl) {
	auto@ om = cast<PointTargetMode>(mode);
	if(om !is null) {
		auto@ t = cast<AbilityTargetPoint>(om.targ);
		if(t !is null) {
			if(t.abl.obj is abl.obj && t.abl.id == abl.id) {
				return;
			}
		}
	}

	targetPoint(AbilityTargetPoint(abl));
}
