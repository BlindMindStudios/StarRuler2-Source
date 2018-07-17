#section disable menu
import elements.BaseGuiElement;
import planet_types;
import orbitals;
import pickups;
import artifacts;
import civilians;

#section gui
from nodes.PlanetNode import getPlanetMaterial;
#section all

from planets.PlanetSurface import preparePlanetShader;
from util.draw_model import drawLitModel;

export Gui3DDisplay;
export ObjectAction;
export Gui3DObject;
export Draw3D, makeDrawMode;

int ringworldType = -1;

void init() {
	auto@ rw = getPlanetType("Ringworld");
	if(rw !is null)
		ringworldType = rw.id;
}

interface Draw3D {
	void preRender(Object@ obj);
	void draw(const recti &in pos, quaterniond rotation);
};

class DrawModel : Draw3D {
	const Material@ mat;
	const Model@ model;
	quaterniond extraRotation;

	DrawModel(const Model@ Model, const Material@ Mat) {
		@mat = Mat;
		@model = Model;
	}

	DrawModel(const Model@ Model, const Material@ Mat, const quaterniond& rot) {
		@mat = Mat;
		@model = Model;
		extraRotation = rot;
	}

	void preRender(Object@ obj) {
	}

	void draw(const recti &in pos, quaterniond rotation) {
		drawLitModel(model, mat, pos, extraRotation * rotation);
	}
};

class DrawPlanet : Draw3D {
	const Material@ mat, atmos;
	Planet@ pl;
	Node@ node;
	
	DrawPlanet(Planet@ pl) {
		const PlanetType@ type = getPlanetType(cast<Planet>(pl).PlanetType);
		@mat = type.emptyMat;
		@atmos = type.atmosMat;
		@this.pl = pl;
		@node = pl.getNode();
	}

	void preRender(Object@ obj) {
	}

	void draw(const recti &in pos, quaterniond rotation) {
		@renderingNode = node;
#section gui
		auto@ dyntex = getPlanetMaterial(pl, mat);
		auto@ material = dyntex.material;
		if(material is null)
			return;

		auto@ plType = getPlanetType(pl.PlanetType);
		preparePlanetShader(pl);

		if(atmos !is null)
			drawLitModel(plType.model, material, pos, rotation, 1/1.025);
		else
			drawLitModel(plType.model, material, pos, rotation);

		if(atmos !is null) {
			shader::MODEL_SCALE = double(min(pos.height, pos.width)) / 2 / 1.025;

			quaterniond atmosRot;
			if(settings::bRotateUIObjects)
				atmosRot = quaterniond_fromAxisAngle(vec3d_up(), fraction(gameTime / 120.0) * twopi);
			drawLitModel(model::Sphere_max, material::FlatAtmosphere, pos, rotation * atmosRot);
		}
		@renderingNode = null;
#section all
	}
};

class DrawRingworld : Draw3D {
	DrawRingworld(Planet@ pl) {
	}

	void preRender(Object@ obj) {
	}

	void draw(const recti &in pos, quaterniond rotation) {
		quaterniond outerRot;
		outerRot *= quaterniond_fromAxisAngle(vec3d_front(), -0.25 * pi);
		outerRot *= rotation;
		drawLitModel(model::RingworldOuter, material::GenericPBR_RingworldOuter, pos, outerRot);

		quaterniond innerRot;
		innerRot *= quaterniond_fromAxisAngle(vec3d_front(), -0.25 * pi);
		innerRot *= rotation.inverted();
		drawLitModel(model::RingworldInner, material::GenericPBR_RingworldInner, pos, innerRot);

		drawLitModel(model::RingworldLiving, material::RingworldSurface, pos, outerRot);
		
//		drawLitModel(model::RingworldAtmosphere, material::RingworldAtmo, pos, outerRot);
	}
};

class DrawBlackhole : Draw3D {
	Node@ node;

	DrawBlackhole(Star@ star) {
		@node = star.getNode();
	}

	void preRender(Object@ obj) {
	}

	void draw(const recti &in pos, quaterniond rotation) {
		@renderingNode = node;

		recti square = pos.aspectAligned(1.0);
		square = square.padded(-square.width*0.2, -square.height*0.2);

		model::Sphere_max.draw(material::Blackhole, square, rotation, 0.3);
		@renderingNode = null;
	}
};

class DrawStar : Draw3D {
	Node@ node;
	double temp;
	
	DrawStar(Star@ star) {
		temp = star.temperature;
		@node = star.getNode();
	}

	void preRender(Object@ obj) {
		shader::STAR_TEMP = temp;
	}

	void draw(const recti &in pos, quaterniond rotation) {
		@renderingNode = node;

		recti square = pos.aspectAligned(1.0);
		square = square.padded(-square.width*0.2, -square.height*0.2);

		model::Sphere_max.draw(material::PopupStarSurface, square, rotation, 1/1.5);
		material::Corona.draw(square);
		@renderingNode = null;
	}
};

class Gui3DDisplay : BaseGuiElement {
	Draw3D@ drawMode;
	quaterniond rotation;

	Gui3DDisplay(BaseGuiElement@ parent, recti pos) {
		super(parent, pos);
	}

	Gui3DDisplay(BaseGuiElement@ parent, Alignment@ pos) {
		super(parent, pos);
	}

	void draw() {
		if(drawMode !is null)
			drawMode.draw(AbsolutePosition, rotation);
		BaseGuiElement::draw();
	}
};

enum ObjectAction {
	OA_LeftClick,
	OA_RightClick,
	OA_DoubleClick,
	OA_MiddleClick,
};

Draw3D@ makeDrawMode(Object@ obj) {
	if(obj is null || !obj.valid || !obj.initialized)
		return null;
	switch(obj.type) {
		case OT_Planet: {
			Planet@ pl = cast<Planet>(obj);
			if(pl.PlanetType == ringworldType)
				return DrawRingworld(pl);
			else
				return DrawPlanet(pl);
		}
		case OT_Orbital: {
			const OrbitalModule@ def = getOrbitalModule(cast<Orbital>(obj).coreModule);
			return DrawModel(def.model, def.material);
		}
		case OT_Ship: {
			const Hull@ hull = cast<Ship>(obj).blueprint.design.hull;
			return DrawModel(hull.model, hull.material);
		}
		case OT_ColonyShip: {
			const Model@ model;
			const Material@ material;

			const Shipset@ ss = obj.owner.shipset;
			const ShipSkin@ skin;
			if(ss !is null)
				@skin = ss.getSkin("Colonizer");

			if(obj.owner.ColonizerModel.length != 0) {
				@model = getModel(obj.owner.ColonizerModel);
				@material = getMaterial(obj.owner.ColonizerMaterial);
			}
			else if(skin !is null) {
				@model = skin.model;
				@material = skin.material;
			}
			else {
				@model = model::ColonyShip;
				@material = material::VolkurGenericPBR;
			}

			return DrawModel(model, material);
		}
		case OT_Freighter: {
			const Model@ model = model::Fighter;
			const Material@ material = material::Ship10;

			const Shipset@ ss = obj.owner.shipset;
			if(ss !is null) {
				auto@ skin = ss.getSkin(cast<Freighter>(obj).skin);
				if(skin !is null) {
					@model = skin.model;
					@material = skin.material;
				}
			}
			return DrawModel(model, material);
		}
		case OT_Asteroid: {
			const Model@ model;
			const Material@ material;
			switch(obj.id % 4) {
				case 0:	
					@model = model::Asteroid1; break;
				case 1:
					@model = model::Asteroid2; break;
				case 2:
					@model = model::Asteroid3; break;
				case 3:
					@model = model::Asteroid4; break;
			}
			switch(obj.id % 3) {
				case 0:
					@material = material::AsteroidPegmatite; break;
				case 1:
					@material = material::AsteroidMagnetite; break;
				case 2:
					@material = material::AsteroidTonalite; break;
			}
			return DrawModel(model, material);
		}
		case OT_Anomaly: {
			Anomaly@ anom = cast<Anomaly>(obj);
			return DrawModel(getModel(anom.model), getMaterial(anom.material));
		}
		case OT_Artifact: {
			Artifact@ art = cast<Artifact>(obj);
			auto@ type = getArtifactType(art.ArtifactType);
			return DrawModel(type.model, type.material, quaterniond_fromAxisAngle(vec3d_up(), 0.5*pi));
		}
		case OT_Star: {
			Star@ star = cast<Star>(obj);
			if(star.temperature > 0)
				return DrawStar(star);
			else
				return DrawBlackhole(star);
		}

		case OT_Pickup: {
			const PickupType@ type = getPickupType(cast<Pickup>(obj).PickupType);
			return DrawModel(type.model, type.material);
		}
		case OT_Civilian: {
			uint type = cast<Civilian>(obj).getCivilianType();
			return DrawModel(getCivilianModel(obj.owner, type, obj.radius), getCivilianMaterial(obj.owner, type, obj.radius));
		}
	}
	return null;
}

class Gui3DObject : Gui3DDisplay {
	Object@ obj;
	double dblClick = 0;
	quaterniond internalRotation;
	bool objectRotation = settings::bRotateUIObjects;

	Gui3DObject(BaseGuiElement@ parent, recti pos, Object@ Obj = null) {
		super(parent, pos);
		@object = Obj;
	}

	Gui3DObject(BaseGuiElement@ parent, Alignment@ pos, Object@ Obj = null) {
		super(parent, pos);
		@object = Obj;
	}

	void set_object(Object@ Obj) {
		if(Obj is obj)
			return;
		@obj = Obj;
		@drawMode = makeDrawMode(Obj);
	}

	Object@ get_object() {
		return obj;
	}

	void draw() {
		if(obj is null)
			return;

		//Update from object values
		if(objectRotation) {
			rotation = internalRotation * obj.node_rotation;
			rotation.normalize();
		}
		else {
			rotation = internalRotation;
		}
		if(drawMode !is null)
			drawMode.preRender(obj);

		Empire@ owner = obj.owner;
		if(owner !is null)
			NODE_COLOR = owner.color;
		Gui3DDisplay::draw();
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) {
		switch(evt.type) {
			case MET_Button_Up:
				if(evt.button == 0) {
					if(frameTime < dblClick) {
						emitClicked(OA_DoubleClick);
					}
					else {
						emitClicked(OA_LeftClick);
						dblClick = frameTime + 0.2;
					}
					return true;
				}
				else if(evt.button == 1) {
					emitClicked(OA_RightClick);
					return true;
				}
				else if(evt.button == 2) {
					emitClicked(OA_MiddleClick);
					return true;
				}
			break;
		}
		return BaseGuiElement::onMouseEvent(evt, source);
	}
};
