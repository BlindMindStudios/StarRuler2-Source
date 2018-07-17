import pickups;
import camps;
import saving;
import regions.regions;
import attributes;

tidy class PickupScript {
	void postInit(Pickup& obj) {
		obj.initPickup();
	}

	void syncInitial(const Pickup& obj, Message& msg) {
		msg << obj.PickupType;
		obj.writePickup(msg);
	}

	bool syncDelta(const Pickup& obj, Message& msg) {
		if(obj.claimPickupDelta()) {
			obj.writePickup(msg);
			return true;
		}
		return false;
	}

	void destroy(Pickup& obj) {
		leaveRegion(obj);
	}

	void load(Pickup& obj, SaveFile& msg) {
		cast<PickupControl>(obj.PickupControl).load(obj, msg);
	}

	void postLoad(Pickup& obj) {
		cast<PickupControl>(obj.PickupControl).postLoad(obj);
	}

	void save(Pickup& obj, SaveFile& msg) {
		cast<PickupControl>(obj.PickupControl).save(obj, msg);
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
	bool pickupDelta = false;

	const CampType@ campType;

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

	void setCampType(uint id) {
		@campType = getCreepCamp(id);
	}

	void load(Pickup& obj, SaveFile& msg) {
		uint tid = msg.readIdentifier(SI_Pickup);
		@type = getPickupType(tid);

		uint cnt = 0;
		msg >> cnt;
		protectors.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> protectors[i];

		obj.PickupType = type.id;
		generateMesh(obj);

		if(msg >= SV_0095) {
			if(msg.readBit())
				@campType = getCreepCamp(msg.readIdentifier(SI_CreepCamp));
		}
	}

	void postLoad(Pickup& obj) {
		if(protectors.length != 0)
			offset = protectors[0].position - obj.position;
	}

	void save(Pickup& obj, SaveFile& msg) {
		msg.writeIdentifier(SI_Pickup, type.id);
		uint cnt = protectors.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << protectors[i];

		msg.writeBit(campType !is null);
		if(campType !is null)
			msg.writeIdentifier(SI_CreepCamp, campType.id);
	}

	void initPickup(Object& obj) {
		Pickup@ pickup = cast<Pickup>(obj);
		@type = getPickupType(pickup.PickupType);

		pickup.name = type.getName(pickup);
		pickup.radius = type.physicalSize;
		generateMesh(obj);
	}

	bool claimPickupDelta() {
		if(pickupDelta) {
			pickupDelta = false;
			return true;
		}
		return false;
	}

	bool get_isPickupProtected() {
		return protectors.length != 0;
	}

	void addPickupProtector(Object& obj, Object& protector) {
		protectors.insertLast(protector);
		if(protectors.length == 1)
			offset = protectors[0].position - obj.position;
	}

	Object@ getProtector() {
		if(protectors.length == 0)
			return null;
		return protectors[0];
	}

	void tickPickup(Object& pickup, double time) {
		bool wasProtected = protectors.length != 0;
		if(protectors.length != 0) {
			auto@ prot = protectors[0];
			pickup.position = prot.position + offset;
			pickup.velocity = prot.velocity;
			pickup.acceleration = prot.acceleration;
		}
		else {
			pickup.velocity = vec3d();
			pickup.acceleration = vec3d();
		}
		
		Object@ lastHit;
		for(uint i = 0, cnt = protectors.length; i < cnt; ++i) {
			Object@ prot = protectors[i];
			if(!prot.valid || prot.owner.major) {
				protectors.removeAt(i);
				pickupDelta = true;
				--i; --cnt;
				if(cnt == 0) {
					if(prot.isShip)
						@lastHit = getObjectByID(cast<Ship>(prot).lastHit);
				}
			}
		}

		if(wasProtected && protectors.length == 0) {
			if(gameTime <= 5.0) {
				pickup.destroy();
				return;
			}

			if(lastHit !is null) {
				Empire@ hitEmp = lastHit.owner;
				if(hitEmp !is null)
					hitEmp.modAttribute(EA_RemnantsCleared, AC_Add, 1.0);

				if(lastHit.hasSupportAI)
					@lastHit = cast<Ship>(lastHit).Leader;
				if(lastHit !is null)
					type.onClear(cast<Pickup>(pickup), lastHit);
			}

			Region@ reg = pickup.region;
			if(campType !is null && reg !is null) {
				for(uint i = 0, cnt = campType.region_statuses.length; i < cnt; ++i)
					reg.removeRegionStatus(null, campType.region_statuses[i].id);
			}
		}
	}

	void pickupPickup(Object& obj, Object& by) {
		Pickup@ pickup = cast<Pickup>(obj);
		if(!type.canPickup(pickup, by))
			return;
		if(isPickupProtected)
			return;
		type.onPickup(pickup, by);
		obj.destroy();
	}

	void writePickup(Message& msg) {
		uint cnt = protectors.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << protectors[i];
	}
};
