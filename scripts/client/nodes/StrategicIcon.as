export StrategicIcon;

bool SHOW_STRATEGIC_ICONS = true;

bool getStrategicIconsShown() {
	return SHOW_STRATEGIC_ICONS;
}

void setStrategicIconsShown(bool enabled) {
	SHOW_STRATEGIC_ICONS = enabled;
}

const double POS_CHANGE_THRES = 1000.0;
class StrategicIcon {
	double animate_pct = 0;
	float lastDist = -1e10f;
	float alpha = 1.f;
	vec3d strategicPos;
	vec3d originPos;
	vec3d animPos;
	bool wasVisible = false;

	StrategicIcon(Node& node) {
		node.transparent = true;
		node.fixedSize = true;
		node.needsTransform = false;
		node.createPhysics();
	}

	void setStrategic(Node& node, vec3d position, vec3d origin) {
		if(animate_pct > 0 && animate_pct < 1)
			return;

		if(wasVisible && animate_pct >= 1 && strategicPos.distanceToSQ(position) > POS_CHANGE_THRES) {
			animPos = strategicPos;
			animate_pct = 0;
		}
		strategicPos = position;
		originPos = origin;
	}

	void clearStrategic() {
		originPos = vec3d();
		strategicPos = vec3d();
	}

	void update(Node& node, const vec3d& realPos, double SIZE, double OUTSIDE_DISTANCE, double OUTSIDE_SIZE_MAX,
		double ANIMATE_TIME, double FADE_DIST_MIN, double FADE_DIST_MAX)
	{
		vec3d real = animPos.zero ? realPos : animPos;
		vec3d origin = originPos.zero ? real : originPos;
		vec3d strategic = strategicPos.zero ? real : strategicPos;

		//Figure out animation state
		double originDist = getCameraDistance(origin) * config::GFX_DISTANCE_MOD;
		double dist = node.sortDistance * config::GFX_DISTANCE_MOD;
		if(abs(dist - lastDist) > OUTSIDE_DISTANCE / 2 || !wasVisible) {
			//Snap when changing distance rapidly
			if(originDist > OUTSIDE_DISTANCE)
				animate_pct = 1.f;
			else
				animate_pct = 0.f;
		}
		else {
			//Animate moving to the edge of the system
			if(originDist > OUTSIDE_DISTANCE)
				animate_pct = min(animate_pct + frameLength / ANIMATE_TIME, 1.0);
			else
				animate_pct = max(0.0, animate_pct - frameLength / ANIMATE_TIME);
		}

		//Do fading
		if(dist < FADE_DIST_MAX) {
			if(dist < FADE_DIST_MIN)
				alpha = 0.f;
			else
				alpha = (dist - FADE_DIST_MIN) / (FADE_DIST_MAX - FADE_DIST_MIN);
		}
		else {
			alpha = 1.f;
		}
		
		//Figure out animated position and size
		vec3d pos;
		double width;
		if(animate_pct > 0) {
			pos = real.interpolate(strategic, animate_pct);
			width = SIZE * min(node.sortDistance, OUTSIDE_SIZE_MAX / config::GFX_DISTANCE_MOD) / (pixelSizeRatio / uiScale);

			if(animate_pct >= 1)
				animPos = vec3d();
		}
		else {
			pos = real;
			width = SIZE * node.sortDistance / (pixelSizeRatio / uiScale);
		}
		
		wasVisible = true;

		if(node.position != pos || node.scale != width) {
			node.scale = width;
			node.position = pos;
			node.rebuildTransform();
		}
		lastDist = dist;
	}
};

const double OUTSIDE_DISTANCE = 12000.0;
const double OUTSIDE_SIZE_MAX = 25000.0;
const double ANIMATE_TIME = 0.45;

const double FADE_DIST_MIN = 750;
const double FADE_DIST_MAX = 1000;

class StrategicIconNodeScript : StrategicIcon {
	bool ownerColor = true;
	Object@ object;
	const SpriteSheet@ sheet;
	const Material@ mat;
	uint icon;
	Color color;
	double size;
	Region@ region;

	StrategicIconNodeScript(Node& node) {
		node.transparent = true;
		node.visible = false;
		node.needsTransform = false;
		node.fixedSize = true;
		node.createPhysics();
		super(node);
	}
	
	void establish(Node& node, Object@ obj, double Size, const SpriteSheet& sht, uint index) {
		@sheet = sht;
		icon = index;
		size = Size;
		establish(node, obj);
	}

	void establish(Node& node, Object@ obj, double Size, const Material& material) {
		@mat = material;
		icon = 0;
		size = Size;
		establish(node, obj);
	}

	void establish(Node& node, Object@ obj) {
		@node.object = obj;
		@object = obj;
		@region = obj.region;
		node.hintParentObject(region, false);
		node.position = obj.position;
		node.rebuildTransform();
	}

	void setColor(Node& node, uint col) {
		ownerColor = false;
		color = Color(col);
		node.color = Colorf(color);
	}

	void clearColor() {
		ownerColor = true;
	}
	
	bool preRender(Node& node) {
		if(object is null)
			return false;
			
		double objDist = getCameraDistance(object.position);
		double fadeDist = 1.0e4 * max(5.0, object.radius);
		if(objDist > fadeDist)
			return false;
	
		bool isMemory = false;
		if(object.visible) {
			node.visible = true;
		}
		else if(node.memorable && object.known) {
			node.visible = true;
			isMemory = true;
		}
		else if(!node.visible) {
			return false;
		}
		
		if(object.region !is region) {
			@region = object.region;
			node.hintParentObject(region, false);
		}

		double dist = node.sortDistance * config::GFX_DISTANCE_MOD;

		StrategicIcon::update(node, object.node_position, size,
			OUTSIDE_DISTANCE, OUTSIDE_SIZE_MAX, ANIMATE_TIME,
			FADE_DIST_MIN, FADE_DIST_MAX);
		
		if(isMemory)
			alpha *= 0.7f;
		if(objDist > 0.8 * fadeDist)
			alpha *= 1.0 - (objDist - 0.8 * fadeDist) / (0.2 * fadeDist);
		
		if(alpha < 0.004f || !SHOW_STRATEGIC_ICONS)
			return false;

		node.color.a = alpha;
		if(ownerColor) {
			Empire@ owner = object.owner;
			if(owner !is null) {
				color = owner.color;
				color.a = 0xff * alpha;
				node.color = Colorf(color);
			}
		}
		return true;
	}

	void render(Node& node) {
		if(sheet !is null)
			renderBillboard(sheet, icon, node.abs_position, node.scale, 0, color);
		else if(mat !is null)
			renderBillboard(mat, node.abs_position, node.scale, 0, color);
	}
};
