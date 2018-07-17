import planet_loyalty;

vec4f ContestedVec;
vec4f GainingVec;
vec4f LosingVec;
vec4f ProtectedVec;
vec4f ZealotVec;

enum DebrisType {
	DT_Rock00,
	DT_Rock01,
	DT_Rock02,
	DT_Rock03,
	DT_Rock04,
	DT_Rock05,
	DT_Rock06,
	DT_Rock07,
	DT_Rock08,
	DT_Rock09,
	DT_Rock10,
	DT_Rock11,

	DT_Metal00,
	DT_Metal01,
	DT_Metal02,
	DT_Metal03,
	DT_Metal04,
	DT_Metal05,
	DT_Metal06,
	DT_Metal07,
	DT_Metal08,
	DT_Metal09,
	DT_Metal10,
	DT_Metal11,
	DT_Metal12,
	DT_Metal13,
	DT_Metal14,
	DT_Metal15,
	DT_Metal16,
	DT_Metal17,
	DT_Metal18,
	DT_Metal19,
	DT_Metal20,
	DT_Metal21,
	DT_Metal22,
	DT_Metal23,
	DT_Metal24,
	DT_Metal25,
	DT_Metal26,
	DT_Metal27,
	DT_Metal28,
	DT_Metal29,
	DT_Metal30,
	DT_Metal31,
	DT_Metal32,
	DT_Metal33,
	DT_Metal34,
	DT_Metal35,
	
	DT_COUNT,
	
	DT_ROCK_START = DT_Rock00,
	DT_ROCK_END = DT_Rock11,
	
	DT_METAL_START = DT_Metal00,
	DT_METAL_END = DT_Metal35
};

void init() {
	ContestedColors[CM_Contested].toVec4(ContestedVec);
	ContestedVec.w = 0.5f;

	ContestedColors[CM_GainingLoyalty].toVec4(GainingVec);
	GainingVec.w = 0.5f;

	ContestedColors[CM_LosingLoyalty].toVec4(LosingVec);
	LosingVec.w = 0.5f;

	ContestedColors[CM_Protected].toVec4(ProtectedVec);
	ProtectedVec.w = 0.5f;

	ContestedColors[CM_Zealot].toVec4(ZealotVec);
	ZealotVec.w = 0.5f;
}

bool SHOW_SYSTEM_PLANES = true;
void setSystemPlanesShown(bool enabled) {
	SHOW_SYSTEM_PLANES = enabled;
}

bool getSystemPlanesShown() {
	return SHOW_SYSTEM_PLANES;
}

final class SystemDebris {
	DebrisType type;
	quaterniond rot;
	vec3d pos, vel, axis;
	float scale, life, rotSpeed;
	float spawnTime;
	bool draw = false;
	double dist = 0;
	
	int opCmp(const SystemDebris& other) {
		return int(type) - int(other.type);
	}
};

class SystemPlaneNodeScript {
	Region@ obj;
	vec3d origin;
	float outerRadius;
	float innerRadius;
	uint contested = CM_None;
	bool decaying = false;
	Color primaryColor;
	float alpha = 1.f;
	
	bool drawPlane = false, drawDebris = false;
	array<SystemDebris@> debris;

	SystemPlaneNodeScript(Node& node) {
	}

	void setContested(uint mode) {
		contested = mode;
	}
	
	void establish(Node& node, Region& region) {
		@obj = region;
		origin = region.position;
		outerRadius = region.OuterRadius;
		innerRadius = region.InnerRadius;

		node.scale = region.radius;
		node.position = origin;
		node.rebuildTransform();
	}

	void setPrimaryEmpire(Empire@ emp) {
		if(emp !is null)
			primaryColor = emp.color;
		else
			primaryColor = Color(0xaaaaaaff);
	}
	
	void addMetalDebris(vec3d position, uint count = 1) {
		double spread = double(count) - 1.0;
	
		for(uint i = 0; i < count; ++i) {
			SystemDebris d;
			d.type = DebrisType(randomi(DT_METAL_START,DT_METAL_END));
			vec2d off = random2d(200.0, innerRadius);
			d.pos = position + random3d(spread);
			d.scale = randomd(1.0,2.0);
			d.axis = random3d(1.0);
			d.rotSpeed = randomd(pi * -0.125, pi * 0.125);
			double dist = cameraPos.distanceTo(d.pos);			
			d.vel = random3d(-8.0,8.0);
			d.life = randomd(30.0,60.0);
			d.spawnTime = frameGameTime;
			d.rot = quaterniond_fromAxisAngle(random3d(1.0), randomd(0.0,twopi));
			debris.insertLast(d);
		}
	}
	
	void generateDebris() {
		uint count = uint(innerRadius * settings::dSystemDebris / 10.0);
		if(debris.length < count) {
			for(uint i = debris.length; i < count; ++i) {
				SystemDebris d;
				d.type = DebrisType(randomi(DT_ROCK_START,DT_ROCK_END));
				vec2d off = random2d(200.0, innerRadius);
				d.pos = origin + vec3d(off.x, randomd(-15.0,15.0), off.y);
				d.scale = randomd(1.0,2.0);
				d.axis = random3d(1.0);
				d.rotSpeed = randomd(pi * -0.125, pi * 0.125);
				double dist = cameraPos.distanceTo(d.pos);
				if(dist < pixelSizeRatio * 2000.0 * d.scale && isSphereVisible(d.pos, d.scale))
					continue;
				
				d.vel = random3d(-8.0,8.0);
				d.life = randomd(30.0,60.0);
				d.spawnTime = frameGameTime;
				d.rot = quaterniond_fromAxisAngle(random3d(1.0), randomd(0.0,twopi));
				debris.insertLast(d);
			}
			
			debris.sortAsc();
		}
	}
	
	void tickDebris(double time) {
		vec3d cam = cameraPos;
		for(int i = int(debris.length-1); i >= 0; --i) {
			auto@ d = debris[i];
			d.life -= time;
			d.pos += d.vel * time;
			d.dist = cam.distanceTo(d.pos) / (pixelSizeRatio * d.scale);
			d.draw = d.dist < 2000.0 && isSphereVisible(d.pos, d.scale);
			
			if(d.life <= 0 && !d.draw) {
				debris.removeAt(i);
				continue;
			}
			
			if(d.draw)
				d.rot = quaterniond_fromAxisAngle(d.axis, d.rotSpeed * time) * d.rot;
		}
	}
	
	void renderDebris() {
		float curTime = frameGameTime;
		for(uint i = 0, cnt = debris.length; i < cnt; ++i) {	
			auto@ d = debris[i];
			if(!d.draw)
				continue;
			
			applyTransform(d.pos, d.scale, d.rot);
			shader::LIFE = curTime - d.spawnTime;
			switch(d.type) {
				case DT_Rock00:	
					material::AsteroidPegmatite.switchTo();
					model::Asteroid1_lod2.draw(d.dist); break;
				case DT_Rock01:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid2_lod2.draw(d.dist); break;
				case DT_Rock02:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid3_lod2.draw(d.dist); break;
				case DT_Rock03:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid4_lod2.draw(d.dist); break;
				case DT_Rock04:	
					material::AsteroidPegmatite.switchTo();
					model::Asteroid1_lod2.draw(d.dist); break;
				case DT_Rock05:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid2_lod2.draw(d.dist); break;
				case DT_Rock06:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid3_lod2.draw(d.dist); break;
				case DT_Rock07:
					material::AsteroidPegmatite.switchTo();
					model::Asteroid4_lod2.draw(d.dist); break;
				case DT_Rock08:	
					material::AsteroidMagnetite.switchTo();
					model::Asteroid1_lod2.draw(d.dist); break;
				case DT_Rock09:
					material::AsteroidMagnetite.switchTo();
					model::Asteroid2_lod2.draw(d.dist); break;
				case DT_Rock10:
					material::AsteroidMagnetite.switchTo();
					model::Asteroid3_lod2.draw(d.dist); break;
				case DT_Rock11:
					material::AsteroidMagnetite.switchTo();
					model::Asteroid4_lod2.draw(d.dist); break;
				case DT_Metal00:	
					material::Debris.switchTo();
					model::Wreckage00.draw(d.dist); break;
				case DT_Metal01:
					material::Debris.switchTo();
					model::Wreckage01.draw(d.dist); break;
				case DT_Metal02:
					material::Debris.switchTo();
					model::Wreckage02.draw(d.dist); break;
				case DT_Metal03:
					material::Debris.switchTo();
					model::Wreckage03.draw(d.dist); break;
				case DT_Metal04:
					material::Debris.switchTo();
					model::Wreckage04.draw(d.dist); break;
				case DT_Metal05:
					material::Debris.switchTo();
					model::Wreckage05.draw(d.dist); break;
				case DT_Metal06:	
					material::Debris.switchTo();
					model::Wreckage06.draw(d.dist); break;
				case DT_Metal07:
					material::Debris.switchTo();
					model::Wreckage07.draw(d.dist); break;
				case DT_Metal08:
					material::Debris.switchTo();
					model::Wreckage08.draw(d.dist); break;
				case DT_Metal09:
					material::Debris.switchTo();
					model::Wreckage09.draw(d.dist); break;
				case DT_Metal10:
					material::Debris.switchTo();
					model::Wreckage10.draw(d.dist); break;
				case DT_Metal11:
					material::Debris.switchTo();
					model::Wreckage11.draw(d.dist); break;
				case DT_Metal12:	
					material::Debris.switchTo();
					model::Wreckage12.draw(d.dist); break;
				case DT_Metal13:
					material::Debris.switchTo();
					model::Wreckage13.draw(d.dist); break;
				case DT_Metal14:
					material::Debris.switchTo();
					model::Wreckage14.draw(d.dist); break;
				case DT_Metal15:
					material::Debris.switchTo();
					model::Wreckage15.draw(d.dist); break;
				case DT_Metal16:
					material::Debris.switchTo();
					model::Wreckage16.draw(d.dist); break;
				case DT_Metal17:
					material::Debris.switchTo();
					model::Wreckage17.draw(d.dist); break;
				case DT_Metal18:	
					material::Debris.switchTo();
					model::Wreckage18.draw(d.dist); break;
				case DT_Metal19:
					material::Debris.switchTo();
					model::Wreckage19.draw(d.dist); break;
				case DT_Metal20:
					material::Debris.switchTo();
					model::Wreckage20.draw(d.dist); break;
				case DT_Metal21:
					material::Debris.switchTo();
					model::Wreckage21.draw(d.dist); break;
				case DT_Metal22:
					material::Debris.switchTo();
					model::Wreckage22.draw(d.dist); break;
				case DT_Metal23:
					material::Debris.switchTo();
					model::Wreckage23.draw(d.dist); break;
				case DT_Metal24:	
					material::Debris.switchTo();
					model::Wreckage24.draw(d.dist); break;
				case DT_Metal25:
					material::Debris.switchTo();
					model::Wreckage25.draw(d.dist); break;
				case DT_Metal26:
					material::Debris.switchTo();
					model::Wreckage26.draw(d.dist); break;
				case DT_Metal27:
					material::Debris.switchTo();
					model::Wreckage27.draw(d.dist); break;
				case DT_Metal28:
					material::Debris.switchTo();
					model::Wreckage28.draw(d.dist); break;
				case DT_Metal29:
					material::Debris.switchTo();
					model::Wreckage29.draw(d.dist); break;
				case DT_Metal30:	
					material::Debris.switchTo();
					model::Wreckage30.draw(d.dist); break;
				case DT_Metal31:
					material::Debris.switchTo();
					model::Wreckage31.draw(d.dist); break;
				case DT_Metal32:
					material::Debris.switchTo();
					model::Wreckage32.draw(d.dist); break;
				case DT_Metal33:
					material::Debris.switchTo();
					model::Wreckage33.draw(d.dist); break;
				case DT_Metal34:
					material::Debris.switchTo();
					model::Wreckage34.draw(d.dist); break;
				case DT_Metal35:
					material::Debris.switchTo();
					model::Wreckage35.draw(d.dist); break;
					
			}
			undoTransform();
		}
	}

	bool preRender(Node& node) {
		if(playerEmpire !is null && playerEmpire.valid && obj.ExploredMask & playerEmpire.visionMask == 0)
			return false;

		double d = node.abs_scale * pixelSizeRatio;
		drawPlane = SHOW_SYSTEM_PLANES && (node.sortDistance < 200.0 * d);
		drawDebris = node.sortDistance < 5.0 * node.abs_scale * pixelSizeRatio;
		
		alpha = 1.0 - clamp((node.sortDistance - 150.0 * d) / (50.0 * d), 0.0, 1.0);
		
		if(drawDebris) {
			tickDebris(frameLength * gameSpeed);
			generateDebris();
		}
		
		return drawPlane || drawDebris;
	}
	
	void render(Node& node) {
		if(drawDebris)
			renderDebris();
		
		if(drawPlane) {
			shader::RADIUS = outerRadius;
			shader::INNER_RADIUS = innerRadius;

			//Calculate distance to plane
			line3dd camLine(cameraPos, cameraPos+cameraFacing);
			vec3d intersect;
			if(!camLine.intersectY(intersect, obj.position.y, false)) {
				intersect = cameraPos;
				intersect.y = obj.position.y;
				shader::PLANE_DISTANCE = sqrt(
						sqr(max(0.0, intersect.distanceTo(obj.position) - outerRadius))
						+ sqr(cameraPos.y - obj.position.y));
			}
			else {
				shader::PLANE_DISTANCE = intersect.distanceTo(cameraPos);
					max(0.0, intersect.distanceTo(obj.position) - outerRadius);
			}

			switch(contested) {
				case CM_None:
					shader::GLOW_COLOR.w = 0.f;
				break;
				case CM_Contested:
					shader::GLOW_COLOR = ContestedVec;
				break;
				case CM_LosingLoyalty:
					shader::GLOW_COLOR = LosingVec;
				break;
				case CM_GainingLoyalty:
					shader::GLOW_COLOR = GainingVec;
				break;
				case CM_Protected:
					shader::GLOW_COLOR = ProtectedVec;
				break;
				case CM_Zealot:
					shader::GLOW_COLOR = ZealotVec;
				break;
			}

			Color c = primaryColor;
			c.a = uint8(alpha * 255.f);
			
			drawPolygonStart(PT_Quads, 1, material::SystemPlane);
			drawPolygonPoint(origin + vec3d(-outerRadius, 0, -outerRadius), vec2f(0.f, 0.f), c);
			drawPolygonPoint(origin + vec3d(+outerRadius, 0, -outerRadius), vec2f(1.f, 0.f));
			drawPolygonPoint(origin + vec3d(+outerRadius, 0, +outerRadius), vec2f(1.f, 1.f));
			drawPolygonPoint(origin + vec3d(-outerRadius, 0, +outerRadius), vec2f(0.f, 1.f));
			drawPolygonEnd();
		}
	}
};
