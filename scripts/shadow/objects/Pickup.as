import pickups;
import regions.regions;

tidy class PickupScript {
	void destroy(Pickup& obj) {
		leaveRegion(obj);
	}

	void syncInitial(Pickup& obj, Message& msg) {
		msg >> obj.PickupType;
		obj.readPickup(msg);
		obj.initPickup();
	}

	void syncDelta(Pickup& obj, Message& msg, double tDiff) {
		obj.readPickup(msg);
	}

	double tick(Pickup& obj, double time) {
		updateRegion(obj);
		obj.tickPickup(time);
		return 0.5;
	}
};

tidy class PickupControl : Component_PickupControl {
	const PickupType@ type;
	Object@[] protectors;
	vec3d offset;

	PickupControl() {
	}

	void generateMesh(Object& obj) {
		MeshDesc mesh;
		@mesh.model = type.model;
		@mesh.material = type.material;
		@mesh.iconSheet = type.iconSheet;
		mesh.iconIndex = type.iconIndex;
		mesh.memorable = true;
		bindMesh(obj, mesh);

		Node@ node = obj.getNode();
		node.customColor = true;
		node.color = Color(0x998888ff);
	}

	void initPickup(Object& obj) {
		Pickup@ pickup = cast<Pickup>(obj);
		@type = getPickupType(pickup.PickupType);

		generateMesh(obj);
	}

	Object@ getProtector() {
		if(protectors.length == 0)
			return null;
		return protectors[0];
	}

	bool get_isPickupProtected() {
		return protectors.length != 0;
	}

	void tickPickup(Object& pickup, double time) {
		if(protectors.length != 0) {
			if(offset.zero)
				offset = protectors[0].position - pickup.position;
			auto@ prot = protectors[0];
			pickup.position = prot.position + offset;
			pickup.velocity = prot.velocity;
			pickup.acceleration = prot.acceleration;
		}
	}

	void readPickup(Object& obj, Message& msg) {
		uint cnt = 0, prevCnt = protectors.length;
		msg >> cnt;
		protectors.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> protectors[i];
	}
};
