import planet_types;

from planets.PlanetSurface import preparePlanetShader;

const double PLANET_DIST_MAX = 4000;

enum PlanetSpecial {
	PS_None,
	PS_Asteroids,
	PS_Ring
};

//Draws the physical star, its corona, and a distant star sprite
final class MoonData {
	uint style = 0;
	float size = 0.f;
};

final class PlanetNodeScript {
	bool Colonized = false;
	const Material@ emptyMat = material::ProceduralPlanet;
	const Material@ colonyMat = material::ProceduralPlanet;
	const Material@ atmosMat;
	const Model@ planetModel;
	PlanetSpecial special = PS_None;
	double ringScale = 1.0, ringAngle = 0.0;
	float ringMin = 0.f, ringMax = 1.f;
	const Material@ ringMat;
	array<MoonData@>@ moons;
	uint gfxFlags = 0;
	Planet@ obj;
	
	PlanetNodeScript(Node& node) {
		node.memorable = true;
		node.animInvis = false;
		node.autoCull = false;
	}
	
	void set_planetType(Node& node, int planetTypeID) {
		//Cache values for performance
		const PlanetType@ type = getPlanetType(planetTypeID);
		@emptyMat = type.emptyMat;
		@colonyMat = type.colonyMat;
		@planetModel = type.model;
		//@dyingMat = type.dyingMat;
		@atmosMat = type.atmosMat;
		node.transparent = atmosMat !is null;
	}
	
	void set_colonized(bool isColonized) {
		Colonized = isColonized;
	}

	void set_flags(uint newFlags) {
		gfxFlags = newFlags;
	}

	void establish(Planet@ obj) {
		@this.obj = obj;
	}
	
	void addRing(Node& node, uint rnd) {
		node.autoCull = false;
		special = PS_Ring;
		
		uint matIndex = rnd % 7;
		rnd /= 7;
		
		uint scale = rnd % 256;
		rnd /= 256;
		
		uint inner = rnd % 128;
		rnd /= 128;
		
		uint outer = rnd % 64;
		rnd /= 64;
		
		uint angle = rnd % 64;
		rnd /= 64;
		
		ringScale = 1.2 + 2.0 * double(scale) / 1024.0;
		ringMin = double(inner) * 0.9 / 1024.0;
		ringMax = max(1.0 - ((1.0 - ringMin) * double(outer)/1024.0), ringMin + 0.1);
		ringAngle = pi * (-0.07 + (0.14 * double(angle)/64.0));
		
		@ringMat = getMaterial("PlanetRing" + (1 + matIndex));
	}

	void addMoon(Node& node, float size, uint style = 0) {
		if(moons is null)
			@moons = array<MoonData@>();
		MoonData dat;
		dat.size = size;
		dat.style = style;
		moons.insertLast(dat);
	}
	
	void giveAsteroids(Node& node) {
		node.autoCull = true;
		special = PS_Asteroids;
	}
	
	bool preRender(Node& node) {
		double visScale = node.abs_scale;
		double distScale = 1.0;

		if(special == PS_Ring) {
			visScale *= ringScale * 1.5;
		}
		if(moons !is null) {
			if(node.sortDistance < 800.0 * node.abs_scale)
				visScale = max(visScale, 100.0 + node.abs_scale);
		}
		if(gfxFlags & PGA_Ringworld != 0)
			distScale = node.abs_scale / 10.0;

		return node.sortDistance * config::GFX_DISTANCE_MOD < PLANET_DIST_MAX * distScale && isSphereVisible(node.abs_position, visScale);
	}

	void render(Node& node) {
		if(gfxFlags & PGA_Ringworld != 0) {
			double lodDist = node.sortDistance / (node.abs_scale * pixelSizeRatio);
			node.applyTransform();

			material::GenericPBR_RingworldOuter.switchTo();
			model::RingworldOuter.draw(lodDist);

			//Poor man's opposite direction rotation
			applyAbsTransform(vec3d(), vec3d(1.0), node.rotation.inverted());
			applyAbsTransform(vec3d(), vec3d(1.0), node.rotation.inverted());
			material::GenericPBR_RingworldInner.switchTo();
			model::RingworldInner.draw(lodDist);
			undoTransform();
			undoTransform();

			preparePlanetShader(obj);
			getPlanetMaterial(obj, material::RingworldSurface).switchTo();

			model::RingworldLiving.draw(lodDist);

//			material::RingworldAtmo.switchTo();
//			model::RingworldAtmosphere.draw(lodDist);

			undoTransform();
			return;
		}

		bool hasAtmos = atmosMat !is null;
		if(hasAtmos && node.sortDistance * config::GFX_DISTANCE_MOD < PLANET_DIST_MAX * pixelSizeRatio * node.abs_scale * 0.25)
			drawBuffers();
	
		node.applyTransform();
		
		const Material@ baseMat;
		if(Colonized)
			@baseMat = colonyMat;
		else
			@baseMat = emptyMat;

		preparePlanetShader(obj);
		getPlanetMaterial(obj, baseMat).switchTo();
		planetModel.draw(node.sortDistance / (node.abs_scale * pixelSizeRatio));
		
		if(hasAtmos) {
			applyAbsTransform(vec3d(), vec3d(1.015), quaterniond_fromAxisAngle(vec3d_up(), fraction(gameTime / 240.0) * twopi));
			
			atmosMat.switchTo();
			//Use the same lod as the planet to avoid weirdness
			model::Sphere_max.draw(node.sortDistance / (node.abs_scale * pixelSizeRatio));
			undoTransform();
		}
		
		if(special == PS_Asteroids) {
			material::AsteroidPegmatite.switchTo();			
			applyAbsTransform(vec3d(2.0,2.0,2.0), vec3d(0.01), quaterniond());
			model::Asteroid1.draw();
			undoTransform();
			
			material::AsteroidMagnetite.switchTo();	
			applyAbsTransform(vec3d(2.3,1.5,1.95), vec3d(0.0125), quaterniond_fromAxisAngle(vec3d(0,0.32,-0.1).normalize(), 1.3));
			model::Asteroid2.draw();
			undoTransform();
			
			material::AsteroidTonalite.switchTo();
			applyAbsTransform(vec3d(2.4,2.8,2.1), vec3d(0.008), quaterniond_fromAxisAngle(vec3d(1).normalize(), 0.782));
			model::Asteroid3.draw();
			undoTransform();
		}
		else if(special == PS_Ring) {
			auto ringRot = node.abs_rotation.inverted() *
				quaterniond_fromAxisAngle(vec3d_front(), ringAngle) *
				quaterniond_fromAxisAngle(vec3d_up(), ((gameTime / 30.0) % (2.0 * pi)));
			
			vec3d starDir = node.parent.abs_position - node.abs_position;
			starDir = (node.abs_rotation * ringRot).inverted() * starDir;
			
			shader::STAR_DIRECTION = vec2f(starDir.x, starDir.z);
			shader::PLANET_RING_RATIO = 1.0 / ringScale;
			shader::RING_MIN = ringMin;
			shader::RING_MAX = ringMax;
			
			applyAbsTransform(vec3d(), vec3d(ringScale), ringRot);
			ringMat.switchTo();
			model::PlanetRing.draw();
			undoTransform();
		}

		//if(gfxFlags & PGA_SpaceElevator != 0) {
			//TODO
		//}
		
		undoTransform();

		if(moons !is null && node.sortDistance < 800.0 * node.abs_scale) {
			for(uint i = 0, cnt = moons.length; i < cnt; ++i) {
				auto@ dat = moons[i];

				uint st = dat.style;
				double rot = fraction(gameTime / (1.0 + 12.0 * double(st % 256) / 255.0)) * twopi;
				st >>= 8;
				double angle = fraction(gameTime / (10.0 + 40.0 * double(st % 256) / 255.0)) * twopi;
				st >>= 8;
				double distance = double(st % 256) / 255.0 * 7.0 + 2.0;
				st >>= 8;
				vec3d offset = quaterniond_fromAxisAngle(vec3d_up(), angle) * vec3d_front(distance * node.abs_scale);

				applyTransform(node.abs_position + offset, vec3d(dat.size), quaterniond_fromAxisAngle(vec3d_up(), rot));
				material::ProceduralMoon.switchTo();
				model::Moon_Sphere_max.draw(node.sortDistance / (dat.size * pixelSizeRatio));
				undoTransform();
			}
		}
	}
};

class DynTex {
	DynamicTexture@ tex;
	Object@ obj;
	double lastRender = 0.0;
	uint modId = uint(-1);
	const Material@ baseMat;
	double delay = 0;

	DynTex() {
		@tex = DynamicTexture();
	}

	void cache(Object& obj, const Material@ baseMat) {
		if(!obj.valid)
			return;
		if(this.obj is obj && modId == obj.surfaceModId && baseMat is this.baseMat)
			return;
		if(modId != uint(-1) && frameTime < delay && this.obj is obj && baseMat is this.baseMat)
			return;

		@this.obj = obj;
		@this.baseMat = baseMat;

		vec2u size = vec2u(obj.originalGridSize);
		if(size.x == 0 || size.y == 0) {
			@this.obj = null;
			return;
		}

		Image img(size, 4);

		uint shown = obj.getSurfaceData(img);
		modId = shown;
		if(shown == uint(-1)) {
			@this.obj = null;
			return;
		}

		const Texture@ prevTex = tex.material.texture7;
		tex.material = baseMat;
		@tex.material.texture7 = prevTex;
		@tex.image[7] = img;
		delay = frameTime + 1.0;
	}

	const Material@ get_material() {
		if(obj is null)
			return null;
		tex.stream();
		lastRender = frameTime;
		return tex.material;
	}

	void switchTo() {
		if(obj is null)
			return;
		tex.stream();
		tex.material.switchTo();
		lastRender = frameTime;
	}
};

const uint MIN_CACHED = 8;
const uint MAX_CACHED = 32;
const double DISCARD_TIME = 2.0;
array<DynTex@> cachedTextures;

DynTex@ getPlanetMaterial(Object& obj, const Material@ baseMat) {
	DynTex@ tex;

	//Check if we already have this planet in our cache
	for(uint i = 0, cnt = cachedTextures.length; i < cnt; ++i) {
		if(cachedTextures[i].obj is obj) {
			@tex = cachedTextures[i];
			break;
		}
	}

	//Check if there's any old caches we can override
	if(tex is null && cachedTextures.length > MIN_CACHED) {
		for(uint i = 0, cnt = cachedTextures.length; i < cnt; ++i) {
			if(frameTime - cachedTextures[i].lastRender > DISCARD_TIME) {
				@tex = cachedTextures[i];
				break;
			}
		}
	}

	//Check if we can create a new cache
	if(tex is null && cachedTextures.length < MAX_CACHED) {
		@tex = DynTex();
		cachedTextures.insertLast(tex);
	}

	//Forcefully override the least recently used cache
	if(tex is null) {
		double bestTime = INFINITY;
		for(uint i = 0, cnt = cachedTextures.length; i < cnt; ++i) {
			double rt = cachedTextures[i].lastRender;
			if(rt < bestTime) {
				@tex = cachedTextures[i];
				bestTime = rt;
				break;
			}
		}
	}

	tex.cache(obj, baseMat);
	return tex;
}

