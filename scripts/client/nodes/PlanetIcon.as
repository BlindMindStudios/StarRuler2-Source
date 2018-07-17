import resources;
import planet_types;
import util.convar;
import nodes.StrategicIcon;
import planet_levels;

const double APPROACH_EPSILON = 0.002;
const double OUTSIDE_DISTANCE = 12000.0;
const double OUTSIDE_SIZE_MAX = 25000.0;
const double ANIMATE_TIME = 0.45;
const double GRAVITY_DISC_MAX_DIST = 1000.0;

const double FADE_DIST_MIN = 250;
const double FADE_DIST_MAX = 300;
const double VERY_DISTANT_START = 56000.0;
const double VERY_DISTANT_END = 80000.0;

vec4f DISABLE_NORMAL, DISABLE_POPULATION;

ConVar PlanetIconSize("planet_icon_size", 0.0225);
ConVar PlanetResourceSize("planet_resource_size", 0.4);
ConVar PlanetTypeSize("planet_type_size", 0.7);
ConVar PlanetSelectedSize("planet_selected_size", 1.0);
const ResourceClass@ foodClass;
const ResourceClass@ scalableClass;

void init() {
	@foodClass = getResourceClass("Food");
	@scalableClass = getResourceClass("Scalable");

	colors::Red.toVec4(DISABLE_NORMAL);
	Color(0xff6300ff).toVec4(DISABLE_POPULATION);
}

bool SHOW_PLANET_PLANES = true;
bool SHOW_PLANET_ICONS = true;

void setPlanetPlanesShown(bool enabled) {
	SHOW_PLANET_PLANES = enabled;
}

bool getPlanetPlanesShown() {
	return SHOW_PLANET_PLANES;
}

void setPlanetIconsShown(bool enabled) {
	SHOW_PLANET_ICONS = enabled;
}

bool getPlanetIconsShown() {
	return SHOW_PLANET_ICONS;
}

final class PlanetIconNodeScript : StrategicIcon {
	Planet@ pl;
	uint level;
	uint typeIcon;
	uint resourceIcon = uint(-1);
	ResourceSheet@ rs;
	const Material@ levelMat, flag;
	vec4f disableColor;
	Color color;
	const ResourceType@ type;

	Empire@ captureEmp;
	float capturePct = 0.f;
	
	float resourceClass = -1.f;
	bool plane = false;
	bool isPlayer = false;
	bool isDisabled = true;
	bool isExported = false;
	bool isMaterial = false;
	bool isDecaying = false;
	bool isBeingColonized = false;
	bool isMemory = false;
	bool isLowPop = false;

	PlanetIconNodeScript(Node& node) {
		node.visible = false;
		super(node);
	}

	void establish(Node& node, Planet& planet) {
		@pl = planet;
		typeIcon = getPlanetType(planet.PlanetType).distantIcon.index;
		@node.object = planet;
		node.position = planet.position;
		node.rebuildTransform();
	}
	
	void setOwner(Empire@ owner) {
		if(owner !is null && owner.valid) {
			color = owner.color;
			@flag = owner.flag;
			isPlayer = true;
		}
		else {
			color = Color(0xb0b0b0ff);
			isPlayer = false;
		}
	}

	void setLevel(uint lvl) {
		level = lvl;
		if(rs !is null) {
			@levelMat = rs.getMaterial(level);
		}
		else switch(level) {
			case 0: @levelMat = material::PlanetLevel0; break;
			case 1: @levelMat = material::PlanetLevel1; break;
			case 2: @levelMat = material::PlanetLevel2; break;
			case 3: @levelMat = material::PlanetLevel3; break;
			case 4: @levelMat = material::PlanetLevel4; break;
			case 5: default: @levelMat = material::PlanetLevel5; break;
		}
	}

	void setResource(uint id) {
		@type = getResource(id);
		if(type is null) {
			resourceIcon = uint(-1);
			resourceClass = -1.f;
		}
		else {
			@rs = type.distantSheet;
			resourceIcon = type.smallIcon.index;
			if(type.level > 0 && type.level <= 3)
				resourceClass = 3.f + float(type.level);
			else if(type.cls is foodClass)
				resourceClass = 7.f;
			else if(type.cls is scalableClass)
				resourceClass = 16.f;
			else
				resourceClass = -1.f;
		}
		setLevel(level);
	}

	void setState(bool dis, bool exp, bool mat, bool decay) {
		isDisabled = dis;
		isExported = exp;
		isMaterial = mat;
		isDecaying = decay;
	}

	void setBeingColonized(bool value) {
		isBeingColonized = value;
	}

	void setCapture(Empire@ emp, float pct) {
		@captureEmp = emp;
		capturePct = pct;
	}
	
	bool preRender(Node& node) {
		if(!SHOW_PLANET_ICONS && !SHOW_PLANET_PLANES)
			return false;
		if(pl is null)
			return false;
			
		isMemory = false;
		
		{
			if(pl.visible) {
				node.visible = true;
			}
			else if(pl.known) {
				isMemory = true;
				node.visible = true;
			}
			else if(!node.visible) {
				return false;
			}
		}
		
		if(!isMemory) {
			Empire@ owner = pl.owner;
			if(owner !is null && owner.valid) {
				color = owner.color;
				isPlayer = true;
			}
			else {
				color = Color(0xb0b0b0ff);
				isPlayer = false;
			}
		}
		
		double dist = node.sortDistance * config::GFX_DISTANCE_MOD;
		plane = dist < GRAVITY_DISC_MAX_DIST;

		vec3d plPos = pl.node_position;
		StrategicIcon::update(node, plPos, PlanetIconSize.value,
			OUTSIDE_DISTANCE, OUTSIDE_SIZE_MAX, ANIMATE_TIME,
			FADE_DIST_MIN * 10, FADE_DIST_MAX * 10);

		if(pl.owner is playerEmpire) {
			if(isDisabled) {
				isLowPop = false;
				if(type is null) {
					disableColor = DISABLE_NORMAL;
				}
				else {
					if(pl.resourceLevel >= type.level &&
						pl.population < getPlanetLevelRequiredPop(pl, type.level)) {
						disableColor = DISABLE_POPULATION;
					}
					else {
						disableColor = DISABLE_NORMAL;
					}
				}
			}
			else {
				isLowPop = pl.resourceLevel > pl.level;
				disableColor = DISABLE_POPULATION;
			}
		}

		if(isMemory)
			alpha *= 0.7f;
			
		return true;
	}

	void render(Node& node) {
		Empire@ owner = pl.owner;
		Color col = color;
		col.a = alpha * 255;
		
		double dist = node.sortDistance * config::GFX_DISTANCE_MOD;
		float iconFade = 1.0;
		if(dist > VERY_DISTANT_START) {
			iconFade = float(clamp(1.0 - ((dist - VERY_DISTANT_START) / (VERY_DISTANT_END - VERY_DISTANT_START)), 0.0, 1.0));
			
			//Distant planet icons are very simple and more numerous, so we check for that first
			if(iconFade < 0.01) {
				if(pl.selected) {
					Color scol(0xffffffff);
					scol.a = col.a;

					renderBillboard(material::DistantPlanetSelected, node.abs_position,
							node.abs_scale * 2.0 * PlanetSelectedSize.value, 0, scol);
					shader::APPROACH += APPROACH_EPSILON;
				}
				renderBillboard(material::FadedPlanet, node.abs_position, node.abs_scale * 2.0, 0, col);
				return;
			}
		}

		//Capturing stuff
		if(captureEmp !is null && !isMemory) {
			captureEmp.color.toVec4(shader::CAPTURE_COLOR);
			shader::CAPTURE_PROGRESS = capturePct;
		}
		else if(pl.Population < 1.0 && !isMemory) {
			shader::CAPTURE_PROGRESS = pl.Population;
			owner.color.toVec4(shader::CAPTURE_COLOR);
		}
		else if(isDecaying) {
			shader::CAPTURE_PROGRESS = pl.decayTime / (config::LEVEL_DECAY_TIMER / owner.PlanetDecaySpeed);
			float pct = abs((frameTime % 1.0) - 0.5f) * 2.f;
			colors::Red.interpolate(colors::Orange, pct).toVec4(shader::CAPTURE_COLOR);
		}
		else {
			shader::CAPTURE_COLOR = vec4f();
		}
		
		double orbitCircleFadeIn = FADE_DIST_MAX * 10;

		//Draw the orbit plane
		if(dist < orbitCircleFadeIn && dist > 100.0 && SHOW_PLANET_PLANES) {
			double orbitSize = pl.OrbitSize;
			shader::CIRCLE_MIN = (pl.radius + 0.5f) / orbitSize;
			shader::CIRCLE_MAX = 1.f;
			Color orbitColor(0xffffff05);
			
			
			double orbitCircleFadeOut = FADE_DIST_MIN * 10;

			double a = 0.025;
			if(pl.selected)
				a = 0.035;
			else if(dist < 250.0)
				a *= (dist - 150.0) / 100.0;
			else if(dist > orbitCircleFadeOut)
				a *= 1.0 - (dist - orbitCircleFadeOut) / (orbitCircleFadeIn - orbitCircleFadeOut);
			
			if(a <= 0.0)
				orbitColor.a = 0;
			else if(a >= 1.0)
				orbitColor.a = 255;
			else
				orbitColor.a = uint8(a * 255.0);
			
			vec3d center = node.abs_position;
			if(orbitColor.a > 0)
				renderPlane(material::OrbitCircle, center, orbitSize, orbitColor);

			float prevA = shader::CAPTURE_COLOR.w;
			Color flagColor = color;
			if(isPlayer && dist > 150.0 && dist < 1850.0) {
				//NOTE: The node can be setup before the empire has a flag specified
				if(flag is null)
					@flag = owner.flag;
				flagColor.a = min(a * (6.0 * 255.0) * (1.0 - (dist - 150.0) / 1700.0), 255.0);
				if(prevA > 0.f)
					shader::CAPTURE_COLOR.w = float(flagColor.a) / 255.f * 1.5f;
			}
			else {
				flagColor.a = 0;
				shader::CAPTURE_COLOR.w = 0.f;
			}
			
			if(flagColor.a > 4) {
				center.y += 0.1;
				shader::CAPTURE_COLOR.w = float(flagColor.a) / 255.f;
				
				renderPlane(flag, center + vec3d(orbitSize * -0.9, 0.0, 0.0), orbitSize * 0.1, flagColor, pi * 0.5);
				renderPlane(flag, center + vec3d(orbitSize *  0.9, 0.0, 0.0), orbitSize * 0.1, flagColor, pi * 1.5);
				renderPlane(flag, center + vec3d(0.0, 0.0, orbitSize *  0.9), orbitSize * 0.1, flagColor, 0.0);
				renderPlane(flag, center + vec3d(0.0, 0.0, orbitSize * -0.9), orbitSize * 0.1, flagColor, pi);
			}
			shader::CAPTURE_COLOR.w = prevA;
		}

		if(col.a > 2 && SHOW_PLANET_ICONS) {
			//Draw selected border
			shader::APPROACH = APPROACH_EPSILON * (col.a != 255 ? -8.0 : 1.0);
			if(pl.selected) {
				Color scol(0xffffffff);
				scol.a = col.a;

				renderBillboard(material::DistantPlanetSelected, node.abs_position,
						node.abs_scale * 2.0 * PlanetSelectedSize.value, 0, scol);
				shader::APPROACH += APPROACH_EPSILON;
			}
			
			shader::DISTANT_SPRITE_FADE = iconFade;
			
			spritesheet::DistantPlanetType.getSourceUV(typeIcon, shader::DISTANT_SPRITE1);

			if(rs !is null)
				rs.getUV(resourceIcon, shader::DISTANT_SPRITE2);
			else if(resourceIcon < 0xffffffff)
				spritesheet::ResourceIconsSmall.getSourceUV(resourceIcon, shader::DISTANT_SPRITE2);
			else
				shader::DISTANT_SPRITE2 = vec4f();
			
			//Draw planet level icon
			shader::DISTANT_SPRITE_SCALE1 = PlanetTypeSize.value;
			shader::DISTANT_SPRITE_SCALE2 = PlanetResourceSize.value;		
			shader::IS_COLONIZING = isBeingColonized ? 1.f : 0.f;
			shader::IS_OWNED = (isPlayer && levelMat !is null) ? 1.f : 0.f;
			shader::IS_EXPORTED = isExported ? 1.f : 0.f;
			shader::IS_DECAYING = isDecaying ? 1.f : 0.f;
			shader::RESOURCE_CLASS = resourceClass;

			if(owner is playerEmpire) {
				shader::IS_DISABLED = (isDisabled || isLowPop) ? 1.f : 0.f;
				shader::IS_USED = (isMaterial || isDisabled || isDecaying || isLowPop) ? 1.f : 0.f;
				if(isDisabled || isLowPop)
					shader::DISABLE_COLOR = disableColor;
			}
			else {
				shader::IS_DISABLED = 0.f;
				shader::IS_USED = 1.f;
			}

			if(levelMat is null)
				renderBillboard(material::PlanetLevel0, node.abs_position, node.abs_scale * 2.0, 0, col);
			else
				renderBillboard(levelMat, node.abs_position, node.abs_scale * 2.0, 0, col);
		}
	}
};
