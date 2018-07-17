bool canMove(Object& obj) {
	if(!obj.hasMover || (obj.hasOrbit && obj.maxAcceleration == 0))
		return false;
	return obj.hasLeaderAI || obj.hasSupportAI;
}

bool canMoveIndependently(Object& obj, bool isFTL = false) {
	if(!obj.hasMover || (!isFTL && obj.hasOrbit && obj.maxAcceleration == 0))
		return false;
	return obj.hasLeaderAI;
}

void orderMove(Object& obj, const vec3d& point, bool queued = false) {
	if(!obj.hasMover)
		return;
	if(obj.hasLeaderAI)
		obj.addMoveOrder(point, queued);
}

void orderMove(Object& obj, const vec3d& point, const quaterniond& facing, bool queued = false) {
	if(!obj.hasMover)
		return;
	if(obj.hasLeaderAI)
		obj.addMoveOrder(point, facing, queued);
}

array<vec3d>@ getFleetTargetPositions(array<Object@>& fleets, vec3d targetPos, quaterniond& facing = quaterniond(), bool calculateFacing = true, bool checkMovement = true, bool isFTL = false) {
	//Remove things that can't move
	if(checkMovement) {
		for(int i = fleets.length - 1; i >= 0; --i) {
			if(!canMoveIndependently(fleets[i], isFTL))
				fleets.removeAt(i);
		}
		if(fleets.length == 0)
			return array<vec3d>();
	}

	//Get facing from center of gravity.
	if(calculateFacing) {
		vec3d centerPos;
		double totalRadius = 0.0;
		for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
			centerPos += fleets[i].position * fleets[i].radius;
			totalRadius += fleets[i].radius;
		}
		centerPos /= totalRadius;
		facing = quaterniond_fromVecToVec(vec3d_front(), targetPos - centerPos);
	}

	//Calculate positions
	array<vec3d> positions(fleets.length);
	int width = ceil(sqrt(double(fleets.length)));
	if(width % 2 != 0)
		width += 1;
	int depth = ceil(double(fleets.length) / double(width));

	vec3d xoff = facing * vec3d_right();
	vec3d yoff = facing * vec3d_front();

	int x = 0, y = 0;
	bool right = true;

	double xPos = 0.0;
	double yPos = 0.0;

	double startOff = 0.0;
	positions[0] = targetPos;
	if(fleets[0].hasLeaderAI && fleets[0].SupplyCapacity > 0)
		startOff = fleets[0].getFormationRadius();
	else
		startOff = fleets[0].radius;
	double maxRad = 0;
	xPos = -startOff;

	for(uint i = 0, cnt = fleets.length; i < cnt; ++i) {
		double rad = 0.0;
		if(fleets[i].hasLeaderAI && fleets[i].SupplyCapacity > 0)
			rad = fleets[i].getFormationRadius();
		else
			rad = fleets[i].radius;

		if(x >= width/2) {
			if(right) {
				x = 1;
				xPos = -startOff;
				right = false;
			}
			else {
				x = 0;
				y += 1;
				xPos = -rad;
				yPos -= y == 1 ? maxRad : (maxRad * 2.0);
				maxRad = rad;
				right = true;
				startOff = rad;
			}
		}

		if(rad > maxRad)
			maxRad = rad;

		if(right)
			xPos += rad;
		else
			xPos -= rad;

		double yEx = 0.0;
		if(y > 0)
			yEx += rad;

		positions[i] = targetPos + (xoff * xPos) + (yoff * (yPos - yEx));
		++x;

		if(right)
			xPos += rad;
		else
			xPos -= rad;
	}

	return positions;
}

