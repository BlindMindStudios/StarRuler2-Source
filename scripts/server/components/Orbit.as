const double orbitSpeedFactor = 2.0;

tidy class Orbit : Component_Orbit, Savable {
	Object@ center_obj;
	vec3d center_pos;
	double radius;
	
	double yearPos;
	double yearLen;

	double dayPos;
	double dayLen;
	bool delta = false;

	Orbit() {
		dayLen = 0;
		yearLen = 0;
	}
	
	void load(SaveFile& data) {
		data >> center_obj;
		if(center_obj is null)
			data >> center_pos;
		
		data >> radius;
		data >> yearPos;
		data >> yearLen;
		data >> dayPos;
		data >> dayLen;
	}
	
	void save(SaveFile& data) {
		data << center_obj;
		if(center_obj is null)
			data << center_pos;
		
		data << radius;
		data << yearPos;
		data << yearLen;
		data << dayPos;
		data << dayLen;
	}

	void orbitTick(Object& obj, double time) {
		if(yearLen != 0) {
			yearPos = (yearPos + time) % yearLen;
			vec3d position;
			
			quaterniond rotation = quaterniond_fromAxisAngle(vec3d_up(), yearPos / yearLen * twopi);
			position = rotation * vec3d_front(radius);
			
			if(center_obj is null) {
				position += center_pos;
			}
			else {
				if(!center_obj.initialized)
					return;
				position += center_obj.position;
			}
			
			if(time > 0.01) {
				vec3d newVel = (position - obj.position) / time;
				obj.acceleration = (newVel - obj.velocity) / time;
				obj.velocity = newVel;
			}
			obj.position = position;

			if(obj.hasMover)
				obj.clearMovement();
		}
		else {
			obj.position += obj.velocity * time;
			obj.velocity += obj.acceleration * time;
		}
		if(dayLen != 0) {
			if(dayLen < 0) {
				vec3d center = obj.position;
				if(center_obj is null)
					center = center_pos;
				else
					center = center_obj.position;

				obj.rotation = quaterniond_fromVecToVec(vec3d_front(), obj.position - center);
			}
			else {
				dayPos = (dayPos + time) % dayLen;
				obj.rotation = quaterniond_fromAxisAngle(vec3d_up(), dayPos / dayLen * twopi);
			}
		}
	}

	void setOrbitPct(Object& obj, double pct) {
		yearPos = yearLen * pct;
		orbitTick(obj, 0);
		delta = true;
	}

	void orbitRadius(Object& obj, double newRadius) {
		radius = newRadius;
		orbitTick(obj, 0);
		delta = true;
	}

	void orbitAround(Object& obj, vec3d point) {
		orbitAround_minRad(obj, point, 0.0);
	}

	void orbitAround(Object& obj, double minRadius, vec3d point) {
		orbitAround_minRad(obj, point, minRadius);
	}

	void stopOrbit() {
		yearLen = 0;
	}
	
	bool get_inOrbit() {
		return yearLen != 0;
	}

	void remakeStandardOrbit(Object& obj, bool orbitPlanets = true) {
		Region@ reg = obj.region;
		yearLen = 0;
		if(reg is null)
			return;
		if(reg.starCount == 0)
			return;
		if(obj.position.distanceTo(reg.position) < obj.radius)
			return;
		Object@ orbObj;
		if(orbitPlanets && !obj.isPlanet)
			@orbObj = reg.getOrbitObject(obj.position);
		if(orbObj !is null)
			obj.orbitAround(orbObj);
		else
			obj.orbitAround(200, reg.position);
	}

	Object@ getOrbitingAround() {
		return center_obj;
	}

	bool get_hasOrbitCenter() const {
		return center_obj !is null;
	}

	bool isOrbitingAround(Object@ around) const {
		if(around is center_obj)
			return true;
		return false;
	}

	void orbitAround(Object& obj, vec3d position, vec3d origin) {
		obj.position = position;
		orbitAround(obj, origin);
	}
	
	void orbitAround_minRad(Object& obj, vec3d point, double minRadius = 0) {
		vec3d offset = (obj.position - point);
		center_pos = point;
		@center_obj = null;
		radius = max(offset.length, minRadius);
		double angle = (vec2d(obj.position.x, -obj.position.z) - vec2d(point.x, -point.z)).radians();
		if(angle < 0)
			angle += twopi;
		yearLen = sqrt(pow(radius, 3.0)) / orbitSpeedFactor;
		yearPos = yearLen * angle / twopi;
		orbitTick(obj, 0);
		delta = true;
	}
	
	void orbitAround(Object& obj, vec3d point, double orbRadius) {
		center_pos = point;
		@center_obj = null;
		radius = orbRadius;
		yearLen = sqrt(pow(radius, 3.0)) / orbitSpeedFactor;
		double angle = (vec2d(obj.position.x, -obj.position.z) - vec2d(point.x, -point.z)).radians();
		if(angle < 0)
			angle += twopi;
		yearPos = yearLen * angle / twopi;
		orbitTick(obj, 0);
		delta = true;
	}
	
	void orbitAround(Object& obj, Object& around, double orbRadius, double angle) {
		@center_obj = around;
		radius = orbRadius;
		yearLen = sqrt(pow(radius, 3.0)) / orbitSpeedFactor;
		yearPos = yearLen * angle / twopi;
		orbitTick(obj, 0);
		delta = true;
	}
	
	void orbitAround(Object& obj, Object& around, double orbRadius) {
		@center_obj = around;
		radius = orbRadius;
		yearLen = sqrt(pow(radius, 3.0)) / orbitSpeedFactor;
		double angle = (vec2d(obj.position.x, -obj.position.z) - vec2d(around.position.x, -around.position.z)).radians();
		if(angle < 0)
			angle += twopi;
		yearPos = yearLen * angle / twopi;
		orbitTick(obj, 0);
		delta = true;
	}

	void orbitAround(Object& obj, Object& around) {
		@center_obj = around;
		radius = max(obj.position.distanceTo(around.position), obj.radius + around.radius);
		yearLen = sqrt(pow(radius, 3.0)) / orbitSpeedFactor;
		double angle = (vec2d(obj.position.x, -obj.position.z) - vec2d(around.position.x, -around.position.z)).radians();
		if(angle < 0)
			angle += twopi;
		yearPos = yearLen * angle / twopi;
		orbitTick(obj, 0);
		delta = true;
	}
	
	void orbitSpin(Object& obj, double dayLength, bool staticPos) {
		dayLen = dayLength;
		if(staticPos && dayLen > 0)
			dayPos = gameTime % dayLen;
		else
			dayPos = 0;
		orbitTick(obj, 0);
		delta = true;
	}

	void orbitDuration(double duration) {
		yearLen = duration;
	}

	void writeOrbit(const Object& obj, Message& msg) {
		msg << float(yearLen);
		msg << float(dayLen);
		msg.writeFixed(dayPos, 0.0, dayLen);

		if(center_obj !is null) {
			msg.write1();
			msg << center_obj;
		}
		else {
			msg.write0();
			msg.writeMedVec3(center_pos);
		}

		msg << float(radius);
		msg.writeFixed(yearPos, 0.0, yearLen);

		if(yearLen == 0) {
			msg.writeMedVec3(obj.position);
			msg.writeSmallVec3(obj.velocity);
		}
	}

	void readOrbit(Object& obj, Message& msg) {
		yearLen = msg.read_float();
		dayLen = msg.read_float();
		dayPos = msg.readFixed(0.0, dayLen);

		if(msg.readBit()) {
			msg >> center_obj;
		}
		else {
			center_pos = msg.readMedVec3();
			@center_obj = null;
		}

		radius = msg.read_float();
		yearPos = msg.readFixed(0.0, yearLen);

		if(yearLen == 0) {
			obj.position = msg.readMedVec3();
			obj.velocity = msg.readSmallVec3();
		}
	}

	bool writeOrbitDelta(const Object& obj, Message& msg) {
		if(!delta && yearLen != 0)
			return false;
		delta = false;
		msg.write1();
		writeOrbit(obj, msg);
		return true;
	}

	void readOrbitDelta(Object& obj, Message& msg) {
		readOrbit(obj, msg);
	}
}
