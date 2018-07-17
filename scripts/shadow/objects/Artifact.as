import artifacts;
import regions.regions;

tidy class ArtifactScript {
	const ArtifactType@ type;
	StrategicIconNode@ icon;

	void makeMesh(Artifact& obj) {
		MeshDesc mesh;
		@mesh.model = type.model;
		@mesh.material = type.material;
		mesh.memorable = true;

		bindMesh(obj, mesh);

		if(type.strategicIcon.valid) {
			@icon = StrategicIconNode();
			if(type.strategicIcon.sheet !is null)
				icon.establish(obj, type.iconSize, type.strategicIcon.sheet, type.strategicIcon.index);
			else if(type.strategicIcon.mat !is null)
				icon.establish(obj, type.iconSize, type.strategicIcon.mat);
			icon.memorable = true;

			if(obj.region !is null)
				obj.region.addStrategicIcon(-1, obj, icon);
		}
	}

	void destroy(Artifact& obj) {
		if(icon !is null) {
			if(obj.region !is null)
				obj.region.removeStrategicIcon(-1, icon);
			icon.markForDeletion();
			@icon = null;
		}
		leaveRegion(obj);
	}

	bool onOwnerChange(Artifact& obj, Empire@ prevOwner) {
		regionOwnerChange(obj, prevOwner);
		return false;
	}

	double tick(Artifact& obj, double time) {
		Region@ prevRegion = obj.region;
		if(updateRegion(obj)) {
			Region@ newRegion = obj.region;
			if(prevRegion !is null)
				prevRegion.removeStrategicIcon(-1, icon);
			if(newRegion !is null)
				newRegion.addStrategicIcon(-1, obj, icon);
			@prevRegion = newRegion;
		}
		icon.visible = obj.isVisibleTo(playerEmpire);

		obj.orbitTick(time);
		obj.abilityTick(time);
		return 0.2;
	}

	vec3d get_strategicIconPosition(Artifact& obj) {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	void syncInitial(Artifact& obj, Message& msg) {
		@type = getArtifactType(msg.readSmall());
		obj.ArtifactType = type.id;
		obj.readOrbit(msg);
		obj.readAbilities(msg);
		makeMesh(obj);
	}

	void syncDelta(Artifact& obj, Message& msg, double tDiff) {
		if(msg.readBit())
			obj.readAbilityDelta(msg);
		if(msg.readBit())
			obj.readOrbitDelta(msg);
	}

	void syncDetailed(Artifact& obj, Message& msg, double tDiff) {
		obj.readOrbit(msg);
		obj.readAbilities(msg);
	}
};
