import regions.regions;
import saving;
import oddity_navigation;
import systems;
import oddities;

void createSlipstream(const vec3d& from, const vec3d& to, double timer = -1.0, Empire@ revealEmp = null) {
	ObjectDesc desc;
	desc.type = OT_Oddity;
	desc.radius = 15.0;
	desc.position = from;
	desc.flags |= objNoPhysics;
	desc.flags |= objNoDamage;
	if(revealEmp !is null)
		@desc.owner = revealEmp;
	desc.name = locale::SLIPSTREAM_TEAR;

	auto@ input = Oddity(desc);
	input.noCollide = true;

	desc.position = to;
	auto@ output = Oddity(desc);
	output.noCollide = true;

	input.linkTo(output);
	output.linkTo(input);

	input.setGate(true);
	output.setGate(true);

	input.setTimer(timer);
	output.setTimer(timer);

	input.makeVisuals(Odd_Slipstream);
	output.makeVisuals(Odd_Slipstream);

	input.linkVision(true);
	output.linkVision(true);
}

void createWormhole(SystemDesc@ from, SystemDesc@ to) {
	vec3d fromPos = from.position;
	vec2d offset = random2d(100.0, from.radius - 100.0);
	fromPos.x += offset.x;
	fromPos.z += offset.y;

	vec3d toPos = to.position;
	offset = random2d(100.0, to.radius - 100.0);
	toPos.x += offset.x;
	toPos.z += offset.y;

	ObjectDesc desc;
	desc.type = OT_Oddity;
	desc.radius = 25.0;
	desc.position = fromPos;
	desc.flags |= objNoPhysics;
	desc.flags |= objNoDamage;
	desc.name = locale::WORMHOLE;

	auto@ input = Oddity(desc);
	input.noCollide = true;

	desc.position = toPos;
	auto@ output = Oddity(desc);
	output.noCollide = true;

	input.linkTo(output);
	output.linkTo(input);

	input.setGate(true);
	output.setGate(true);

	input.makeVisuals(Odd_Wormhole);
	output.makeVisuals(Odd_Wormhole);

	input.linkVision(true);
	output.linkVision(true);

	input.setSuperior(true);
	output.setSuperior(true);
}

Oddity@ createNebula(const vec3d& position, double radius, uint color = 0xf0c87040, Region@ region = null) {
	ObjectDesc desc;
	desc.type = OT_Oddity;
	desc.radius = radius;
	desc.position = position;
	desc.flags |= objNoPhysics;
	desc.flags |= objNoDamage;

	auto@ nebula = Oddity(desc);
	if(region !is null) {
		@nebula.region = region;
		region.enterRegion(nebula);
	}
	nebula.noCollide = true;
	nebula.makeVisuals(Odd_Nebula, color=color);

	return nebula;
}

tidy class OddityScript {
	StrategicIconNode@ icon;
	bool gate = false;
	bool superior = false;
	double timer = -1.0;
	uint visualType = uint(-1);
	uint visualColor = 0xffffffff;
	Object@ link;

	bool visionLinked = false;
	Region@ visionRegion;
	uint visionMask = 0;
	uint prevMemory = 0;

	bool delta = false;

	void save(Oddity& obj, SaveFile& file) {
		saveObjectStates(obj, file);
		file << gate;
		file << timer;
		file << visualType;
		file << link;
		file << visionLinked;
		file << visionRegion;
		file << visionMask;
		file << superior;
		file << prevMemory;
		file << visualColor;
	}

	void load(Oddity& obj, SaveFile& file) {
		loadObjectStates(obj, file);
		file >> gate;
		file >> timer;
		file >> visualType;
		file >> link;
		file >> visionLinked;
		file >> visionRegion;
		file >> visionMask;
		if(file >= SV_0020)
			file >> superior;
		if(file >= SV_0067)
			file >> prevMemory;
		if(file >= SV_0099)
			file >> visualColor;

		makeVisuals(obj, visualType, fromCreation=false, color=visualColor);
		if(gate)
			addOddityGate(obj);
	}

	uint getVisualType() {
		return visualType;
	}

	uint getVisualColor() {
		return visualColor;
	}

	bool isGate() {
		return gate;
	}

	vec3d getGateDest() {
		if(link !is null)
			return link.position;
		return vec3d();
	}

	Object@ getLink() {
		return link;
	}

	double getTimer() {
		return timer;
	}

	void setGate(Oddity& obj, bool value) {
		if(value == gate)
			return;
		gate = value;
		if(gate)
			addOddityGate(obj);
		else
			removeOddityGate(obj);
		delta = true;
	}

	void linkVision(bool value) {
		visionLinked = value;
		delta = true;
	}

	void linkTo(Oddity& obj, Object@ other) {
		@link = other;
		obj.rotation = quaterniond_fromVecToVec(vec3d_front(), (other.position - obj.position).normalized(), vec3d_up());
		delta = true;
	}

	void setTimer(double value) {
		timer = value;
		delta = true;
	}

	void setSuperior(bool value) {
		superior = value;
	}

	vec3d get_strategicIconPosition(Oddity& obj) {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	void makeVisuals(Oddity& obj, uint type, bool fromCreation = true, uint color = 0xffffffff) {
		visualType = type;
		visualColor = color;
		@icon = makeOddityVisuals(obj, type, fromCreation, color=color);
	}

	void destroy(Oddity& obj) {
		if(obj.region !is null)
			obj.region.removeStrategicIcon(-1, icon);
		if(icon !is null)
			icon.markForDeletion();
		leaveRegion(obj);
		updateVision(visionRegion, visionMask, 0);
		if(gate)
			removeOddityGate(obj);
		removeAmbientSource(CURRENT_PLAYER, obj.id);
	}

	void updateVision(Region@ onRegion, uint fromMask, uint toMask) {
		if(onRegion is null)
			return;
		if(fromMask == toMask)
			return;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(fromMask & emp.mask != 0) {
				if(toMask & emp.mask == 0)
					onRegion.revokeVision(emp);
			}
			else {
				if(toMask & emp.mask != 0)
					onRegion.grantVision(emp);
			}
		}
	}

	double tick(Oddity& obj, double time) {
		//Handle region changes
		Region@ prevRegion = obj.region;
		if(updateRegion(obj)) {
			Region@ newRegion = obj.region;
			if(icon !is null) {
				if(prevRegion !is null)
					prevRegion.removeStrategicIcon(-1, icon);
				if(newRegion !is null)
					newRegion.addStrategicIcon(-1, obj, icon);
			}
			updateVision(visionRegion, visionMask, 0);
			visionMask = 0;
			@visionRegion = null;
			@prevRegion = newRegion;
		}

		if(icon !is null)
			icon.visible = obj.isVisibleTo(playerEmpire);

		if(link !is null && !link.valid)
			@link = null;

		//Handle vision sharing
		Region@ newRegion;
		uint newMask = 0;
		if(visionLinked && link !is null) {
			@newRegion = link.region;
			if(prevRegion is null)
				obj.donatedVision |= link.visibleMask;
		}
		if(prevRegion !is null)
			newMask = prevRegion.BasicVisionMask;

		if(newRegion !is visionRegion) {
			updateVision(visionRegion, visionMask, 0);
			updateVision(newRegion, 0, newMask);
			@visionRegion = newRegion;
			visionMask = newMask;
		}
		else {
			updateVision(visionRegion, visionMask, newMask);
			visionMask = newMask;
		}

		//Handle memories
		if(obj.memoryMask != prevMemory) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				auto@ emp = getEmpire(i);
				if((prevMemory & emp.mask) != (obj.memoryMask & emp.mask))
					emp.PathId += 1;
			}
			prevMemory = obj.memoryMask;
		}

		//Kill the oddity gate if the region blocks ftl at all
		if(gate && !superior && prevRegion !is null) {
			if(prevRegion.BlockFTLMask.value & obj.owner.mask != 0) {
				if(link !is null)
					link.destroy();
				obj.destroy();
			}
		}

		//Handle timer
		if(timer >= 0.0) {
			timer -= time;
			if(timer <= 0.0)
				obj.destroy();
		}

		return 0.25;
	}

	void _write(const Oddity& obj, Message& msg) {
		msg << gate;
		msg << timer;
		msg << visualType;
		msg << visualColor;
		msg << link;
	}

	void syncInitial(const Oddity& obj, Message& msg) {
		_write(obj, msg);
	}

	bool syncDelta(const Oddity& obj, Message& msg) {
		bool used = false;
		if(delta) {
			used = true;
			delta = false;
			msg.write1();
			_write(obj, msg);
		}
		else
			msg.write0();
		return used;
	}

	void syncDetailed(const Oddity& obj, Message& msg) {
		_write(obj, msg);
	}
};
