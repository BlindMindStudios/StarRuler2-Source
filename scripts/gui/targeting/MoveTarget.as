import targeting.targeting;
from obj_selection import selectedObjects, getSelectionPosition, selectedObject;
from navigation.elevation import getElevationIntersect;
import targeting.PointTarget;
import movement;
import ftl;

enum MoveMode {
	MM_Normal,
	MM_Facing,
	MM_Height,
};

const double VECTOR_DELAY = 0.2;
const double VECTOR_PROGRESS_DELAY = 0.1;
const int VECTOR_RADIAL_SIZE = 24;
const int FACING_LENGTH = 200;
const Color VECTOR_RADIAL_COLOR(0x39a086aa);

class MoveTarget : PointTarget {
	MoveMode mode = MM_Normal;
	vec3d destination;
	bool hasFacing = false;
	bool hasHeight = false;
	double origHeight = 0;
	vec3d facingDestination;
	vec2i startAt = mousePos;
	vec2i dragPos = startAt;
	double startTime = frameTime;

	vec3d get_origin() {
		if(shiftKey) {
			Object@ obj = selectedObject;
			return obj.finalMoveDestination;
		}
		else {
			return getSelectionPosition(true);
		}
	}

	quaterniond get_facing() {
		return quaterniond_fromVecToVec(vec3d_front(), facingDestination - destination);
	}

	bool hover(const vec2i& mpos) override {
		if(mode == MM_Facing || mode == MM_Height)
			return true;
		PointTarget::hover(mpos);
		destination = hovered;

		//Keep height if in the same region
		if(!ctrlKey) {
			vec3d orig = origin;
			Region@ targRegion = getRegion(destination);
			Region@ curRegion = getRegion(orig);

			if(curRegion !is null && targRegion is curRegion) {
				double hdiff = orig.y - curRegion.position.y;

				line3dd ray = activeCamera.screenToRay(mpos);
				ray.start.y -= hdiff;
				ray.end.y -= hdiff;

				if(getElevationIntersect(ray, destination))
					destination.y += hdiff;
			}
		}
		return true;
	}

	bool onMouseButton(int button, bool pressed) override {
		if(!pressed) {
			if(button == 0) {
				mode = MM_Height;
				if(!hasHeight)
					origHeight = destination.y;
				return true;
			}
			else if(button == 1) {
				targetingClick();
				return true;
			}
		}
		else {
			if(button == 0) {
				mode = MM_Facing;
				return true;
			}
		}
		return false;
	}

	bool onMouseDragged(int buttons, int x, int y, int dx, int dy) override {
		if(buttons == 0x2) {
			dragPos.x += dx;
			dragPos.y -= dy;

			if(mode == MM_Normal) {
				double curTime = frameTime;
				if(curTime - startTime > VECTOR_DELAY) {
					mode = MM_Height;
					if(!hasHeight)
						origHeight = destination.y;
				}
				else if(dragPos.distanceTo(startAt) < 4)
					return true;
			}
			if(mode == MM_Height) {
				double delta = double(dy) * 0.5;
				destination.y += delta;
				hasHeight = true;
				if(hasFacing)
					facingDestination.y += delta;
				return true;
			}
		}
		else if(buttons == 0x3) {
			dragPos.x += dx;
			dragPos.y -= dy;

			if(mode == MM_Facing) {
				if(dragPos.distanceTo(startAt) > FACING_LENGTH)
					dragPos = startAt + (dragPos - startAt).normalize(FACING_LENGTH);
				PointTarget::hover(dragPos);
				facingDestination = hovered;
				facingDestination.y = destination.y;
				hasFacing = true;
				return true;
			}
		}

		cancelTargeting();
		return false;
	}

	bool onMouseDragEnd(int buttons) override {
		if(mode == MM_Height) {
			targetingClick();
			return true;
		}
		else if(mode == MM_Facing) {
			mode = MM_Height;
			return true;
		}
		cancelTargeting();
		return false;
	}

	bool click() override {
		if(playerEmpire.ForbidDeepSpace != 0) {
			if(getRegion(destination) is null) {
				cancelTargeting();
				return false;
			}
		}
		return true;
	}

	vec3d get_position() override {
		return destination;
	}
};

class MoveVisuals : TargetVisuals {
	BeamNode@ moveBeam;
	BeamNode@ facingBeam;
	BeamNode@ heightBeam;
	BeamNode@ lengthBeam;
	BeamNode@ destHeightBeam;

	MoveVisuals() {
		@moveBeam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		moveBeam.color = Color(0x00ff00ff);
		moveBeam.visible = false;

		@facingBeam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		facingBeam.color = Color(0x00adffff);
		facingBeam.visible = false;

		@heightBeam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		heightBeam.color = Color(0xaaaaaaff);
		heightBeam.visible = false;

		@destHeightBeam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		destHeightBeam.color = Color(0xaaaaaaff);
		destHeightBeam.visible = false;

		@lengthBeam = BeamNode(material::MoveBeam, 0.001f, vec3d(), vec3d(), true);
		lengthBeam.color = Color(0xaaaaaaff);
		lengthBeam.visible = false;
	}

	~MoveVisuals() {
		moveBeam.markForDeletion();
		facingBeam.markForDeletion();
		heightBeam.markForDeletion();
		destHeightBeam.markForDeletion();
		lengthBeam.markForDeletion();
	}

	void render(TargetMode@ mode) override {
		MoveTarget@ mt = cast<MoveTarget>(mode);
		if(mt is null)
			return;

		vec3d dest = mt.destination;
		vec3d origin = mt.origin;
		if(mt.hasHeight) {
			double origHeight = mt.origHeight;
			vec3d flatDest = dest;
			flatDest.y = origHeight;

			vec3d flatOrigin = origin;
			flatOrigin.y = origHeight;

			heightBeam.visible = true;
			heightBeam.abs_position = flatDest;
			heightBeam.endPosition = dest;

			lengthBeam.visible = true;
			lengthBeam.abs_position = flatOrigin;
			lengthBeam.endPosition = flatDest;
		}
		if(mt.mode != MM_Normal || frameTime - mt.startTime > VECTOR_DELAY) {
			moveBeam.visible = true;
			moveBeam.abs_position = origin;
			moveBeam.endPosition = dest;
		}
		if(mt.hasFacing) {
			vec3d facing = mt.facingDestination;
			facingBeam.visible = true;
			facingBeam.abs_position = dest;
			facingBeam.endPosition = facing;

			if(mt.hasHeight) {
				vec3d flatFacing = facing;
				flatFacing.y = mt.origHeight;

				destHeightBeam.visible = true;
				destHeightBeam.abs_position = facing;
				destHeightBeam.endPosition = flatFacing;
			}
		}
	}

	void draw(TargetMode@ mode) override {
		MoveTarget@ mt = cast<MoveTarget>(mode);
		if(mt is null)
			return;

		//Draw facing progress radial
		if(mt.mode == MM_Normal) {
			double curTime = frameTime;
			double time = curTime - mt.startTime;

			if(time > VECTOR_PROGRESS_DELAY && time < VECTOR_DELAY) {
				shader::PROGRESS = float(
						min(time - VECTOR_PROGRESS_DELAY,
							VECTOR_DELAY - VECTOR_PROGRESS_DELAY))
					/ float(VECTOR_DELAY - VECTOR_PROGRESS_DELAY);
				vec2i pos = mousePos;
				material::RadialProgress.draw(recti_area(
					pos - vec2i(VECTOR_RADIAL_SIZE / 2, VECTOR_RADIAL_SIZE / 2),
					vec2i(VECTOR_RADIAL_SIZE, VECTOR_RADIAL_SIZE)),
					VECTOR_RADIAL_COLOR);
			}
		}
	}
};

class MoveCallback : TargetCallback {
	void call(TargetMode@ mode) override {
		MoveTarget@ mt = cast<MoveTarget>(mode);
		if(mt is null)
			return;

		Object@[]@ selection = selectedObjects;
		if(selection.length == 0)
			return;

		if(selection[0].hasSupportAI) {
			//Movement targeting for supports
			Object@[] supports;
			double maxRad = 0.0;
			Empire@ owner;
			for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
				Object@ obj = selection[i];
				if(obj.owner !is null)
					@owner = obj.owner;
				if(obj.hasSupportAI && obj.owner.controlled) {
					supports.insertLast(obj);
					if(obj.radius > maxRad)
						maxRad = obj.radius;
				}
			}

			if(supports.length == 0)
				return;

			//Find fleet to transfer to
			Object@ fleet = cast<Ship>(selection[0]).Leader;
			if(fleet is null || mode.position.distanceTo(fleet.position) > fleet.getFormationRadius()) {
				if(owner !is null)
					@fleet = owner.getFleetFromPosition(mode.position);
			}
			if(fleet is null)
				return;

			//Calculate formation
			double formRad = fleet.getFormationRadius();
			uint edge = ceil(sqrt(double(supports.length)));
			double spacing = max(maxRad, 1.0) * 8;
			vec3d boxSize(edge * spacing, 0, edge * spacing);
			double boxRad = sqrt(boxSize.x * boxSize.x / 4.0 + boxSize.z * boxSize.z / 4.0);
			vec3d boxCenter = (mode.position - fleet.position);

			//Reverse entire fleet rotation
			Ship@ leadership = cast<Ship>(fleet);
			if(leadership !is null)
				boxCenter = leadership.formationDest.inverted() * boxCenter;

			//Keep entire box within bounds
			if(boxCenter.length + boxRad > formRad)
				boxCenter.length = formRad - boxRad;

			//Get the spacing vectors
			vec3d right = vec3d_right();
			vec3d front = vec3d_front();
			if(mt.hasFacing) {
				quaterniond facing = mt.facing;
				right = facing * right;
				front = facing * front;
			}
			if(leadership !is null) {
				right = leadership.formationDest.inverted() * right;
				front = leadership.formationDest.inverted() * front;
			}

			right.length = spacing;
			front.length = spacing;

			//Transfer ships to fleet
			for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
				uint x = (i % edge);
				uint y = i / edge;

				//Calculate position in formation
				vec3d pos = boxCenter;
				if(x % 2 == 0)
					pos += right * double(x / 2);
				else
					pos -= right * double(x / 2 + 1);
				if(y % 2 == 0)
					pos += front * double(y / 2);
				else
					pos -= front * double(y / 2 + 1);

				//Transfer and form up
				Ship@ ship = cast<Ship>(supports[i]);
				if(ship.Leader !is fleet)
					supports[i].transferTo(fleet, pos);
				else
					supports[i].setFleetOffset(pos);
			}
		}
		else {
			//Movement order targeting
			if(selection.length == 1) {
				Object@ from = selection[0];
				
				if(from.owner.controlled && from.hasMover && canMoveIndependently(from)) {
					sound::order_move.play(priority=true);
					if(mt.hasFacing)
						orderMove(from, mode.position, mt.facing, shiftKey);
					else
						orderMove(from, mode.position, shiftKey);
				}
			}
			else if(selection.length > 0) {
				array<Object@> orderObjs;
				//Get center to organize from
				vec3d center;
				double spacing = 1;
				for(int i = selection.length - 1; i >= 0; --i) {
					Object@ obj = selection[i];
					if(canMoveIndependently(obj)) {
						orderObjs.insertLast(obj);
						center += obj.position;
						
						double size = obj.radius;
						if(obj.hasLeaderAI)
							size = obj.getFormationRadius();
						if(size > spacing)
							spacing = size;
					}
				}

				if(orderObjs.length == 1) {
					sound::order_move.play(priority=true);
					if(mt.hasFacing)
						orderMove(orderObjs[0], mode.position, mt.facing, shiftKey);
					else
						orderMove(orderObjs[0], mode.position, shiftKey);
				}
				else {
					center /= double(orderObjs.length);
					spacing *= 2.5;
					
					//Get center of target organization
					vec3d dest = mode.position;
					sound::order_move.play(priority=true);
					
					//Form the objects up
					auto@ positions = getFleetTargetPositions(orderObjs, dest, mt.facing, !mt.hasFacing);
					for(uint i = 0, cnt = orderObjs.length; i < cnt; ++i) {
						if(mt.hasFacing)
							orderMove(orderObjs[i], positions[i], mt.facing, shiftKey);
						else
							orderMove(orderObjs[i], positions[i], shiftKey);
					}
				}
			}
		}
	}
};

void targetMovement() {
	MoveTarget targ;
	MoveCallback cb;
	MoveVisuals vis;

	startTargeting(targ, vis, cb);
}

bool isExtendedMoveTarget() {
	MoveTarget@ targ = cast<MoveTarget>(mode);
	if(targ is null)
		return false;
	return frameTime - targ.startTime > VECTOR_DELAY;
}
