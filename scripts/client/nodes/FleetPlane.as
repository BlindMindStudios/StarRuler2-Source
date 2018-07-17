const double MAX_SIZE = 4000.0;
const double APPROACH_EPSILON = 0.0002;

bool SHOW_FLEET_PLANES = true;
bool SHOW_FLEET_ICONS = true;

void setFleetPlanesShown(bool enabled) {
	SHOW_FLEET_PLANES = enabled;
}

bool getFleetPlanesShown() {
	return SHOW_FLEET_PLANES;
}

void setFleetIconsShown(bool enabled) {
	SHOW_FLEET_ICONS = enabled;
}

bool getFleetIconsShown() {
	return SHOW_FLEET_ICONS;
}

const Color FTLColor(0x00c0ff80);
const Color CombatColor(0xffc60080);
vec4f CombatVec;
vec4f FTLVec;

void init() {
	CombatColor.toVec4(CombatVec);
	FTLColor.toVec4(FTLVec);
}

class FleetPlaneNodeScript {
	Object@ leader;
	Sprite fleetIcon;
	double radius;
	bool hasPlane = false;
	bool withFleet = false;
	bool rotate = true;
	bool wasVisible = false;

	FleetPlaneNodeScript(Node& node) {
		node.transparent = true;
		node.visible = false;
		node.needsTransform = false;
		node.fixedSize = true;
		node.createPhysics();
	}
	
	void establish(Node& node, Object& obj, double rad) {
		@leader = obj;
		radius = rad;

		if(obj.isShip) {
			const Design@ dsg = cast<Ship>(obj).blueprint.design;
			if(dsg !is null)
				fleetIcon = dsg.fleetIcon;
		}
		
		node.scale = radius;
		node.position = obj.position;
		@node.object = obj;
		node.rebuildTransform();
	}
	
	void set_hasSupply(bool supply) {
		hasPlane = supply;
	}

	void set_hasFleet(bool has) {
		withFleet = has;
	}

	bool preRender(Node& node) {
		if(node.visible && leader !is null) {
			node.position = leader.node_position;
			
			double size = leader.radius;
			size = 0.2 * (1.0 + size) / (3.0 + size);
			if(wasVisible)
				size *= node.sortDistance * 0.25;
			else
				size *= cameraPos.distanceTo(node.position) * 0.25;
			size = min(size, MAX_SIZE);
			if(leader.selected)
				size *= 1.1;
			node.scale = size * 0.5;
			rotate = !leader.hasOrbit;
			
			node.rebuildTransform();
			wasVisible = true;
			return true;
		}
		else {
			wasVisible = false;
			return false;
		}
	}

	void render(Node& node) {
		if(hasPlane && node.sortDistance < 2000.0 && node.sortDistance >= 500.0 && SHOW_FLEET_PLANES) {
			Color color(0xffffff14);
			if(node.sortDistance < 600.0)
				color.a = double(color.a) * (node.sortDistance - 500.0) / 100.0;
			renderPlane(material::FleetCircle, node.abs_position, radius, color);
		}
		
		double iconDist = 600.0 * leader.radius;
		
		if(node.sortDistance > iconDist && SHOW_FLEET_ICONS) {
			//TODO: Use leader's node instead
			
			vec3d camFacing = cameraFacing, camUp = cameraUp;
			double rot = 0.0;
			
			if(rotate) {
				vec3d objFacing = leader.node_rotation * vec3d_front();
				double alongDot = camFacing.dot(objFacing);
				
				if(alongDot > -0.9999 && alongDot < 0.9999) {
					objFacing -= camFacing * alongDot;
					objFacing.normalize();
					
					vec3d camRight = camFacing.cross(camUp).normalized();
					rot = acos(camRight.dot(objFacing));
					if(camRight.cross(camFacing).dot(objFacing) < 0)
						rot = -rot;
				}
				else {
					rot = alongDot > 0 ? pi * 0.5 : pi * -0.5;
				}
			}
			
			Empire@ owner = leader.owner;
			Color col = owner.color;
			if(node.sortDistance < iconDist * 2.0)
				col.a = uint8(255.0 * (node.sortDistance - iconDist) / iconDist);
			node.color = col;

			Ship@ ship = cast<Ship>(leader);
			if(ship !is null && ship.isFTLing)
				shader::GLOW_COLOR = FTLVec;
			else if(owner is playerEmpire && leader.inCombat)
				shader::GLOW_COLOR = CombatVec;
			else
				shader::GLOW_COLOR.w = 0.f;
			
			shader::APPROACH = APPROACH_EPSILON;
			if(fleetIcon.valid)
				renderBillboard(fleetIcon.sheet, fleetIcon.index, node.abs_position, node.scale * 2.0, rot);
			else
				renderBillboard(spritesheet::ShipGroupIcons, 0, node.abs_position, node.scale * 2.0, rot);
		}
	}
};
