import artifacts;
import regions.regions;
import saving;
import systems;
import object_creation;
import statuses;
from artifact_seeding import ArtifactCount;
from empire import Creeps;

Artifact@ createArtifact(const vec3d& position, const ArtifactType@ type, Region@ region = null) {
	if(type is null)
		return null;
	ObjectDesc desc;
	desc.type = OT_Artifact;
	desc.radius = type.physicalSize;
	desc.position = position;
	desc.name = type.name;
	desc.delayedCreation = true;
	desc.flags |= objNoDamage;

	Artifact@ obj = Artifact(desc);
	obj.ArtifactType = type.id;
	if(region !is null)
		@obj.region = region;
	obj.finalizeCreation();
	if(region !is null)
		region.enterRegion(obj);
	return obj;
}

tidy class ArtifactScript {
	const ArtifactType@ type;
	StrategicIconNode@ icon;
	uint regMask = 0;
	double deepSpaceTime = 0;
	double expire = -1.0;

	void postInit(Artifact& obj) {
		@type = getArtifactType(obj.ArtifactType);
		if(type is null) {
			error("Invalid artifact created...");
			printTrace();
			obj.destroy();
			return;
		}

		obj.setNeutralAbilities(true);
		obj.setAbilityDestroy(type.singleUse);
		for(uint i = 0, cnt = type.abilities.length; i < cnt; ++i)
			obj.createAbility(type.abilities[i].id);

		if(type.orbit && obj.region !is null)
			obj.orbitAround(obj.region.position);

		makeMesh(obj);
		ArtifactCount += 1;
	}

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

			if(obj.region !is null) {
				if(!obj.region.initialized)
					@obj.region = null;
				else
					obj.region.addStrategicIcon(-1, obj, icon);
			
				if(obj.region !is null) {
					Node@ node = obj.getNode();
					node.hintParentObject(obj.region, false);
				}
			}
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
		ArtifactCount -= 1;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;
			if(regMask & other.mask != 0) {
				regMask &= ~other.mask;
				other.unregisterArtifact(obj);
			}
		}
	}

	void setExpire(double time) {
		expire = time;
	}

	bool onOwnerChange(Artifact& obj, Empire@ prevOwner) {
		regionOwnerChange(obj, prevOwner);
		if(obj.owner !is null && obj.owner.valid)
			obj.setNeutralAbilities(false);
		else
			obj.setNeutralAbilities(true);
		return false;
	}

	double tick(Artifact& obj, double time) {
		Region@ prevRegion = obj.region;
		if(updateRegion(obj)) {
			Region@ newRegion = obj.region;
			if(icon !is null) {
				if(prevRegion !is null)
					prevRegion.removeStrategicIcon(-1, icon);
				if(newRegion !is null)
					newRegion.addStrategicIcon(-1, obj, icon);
			}
			@prevRegion = newRegion;
			
			Node@ node = obj.getNode();
			if(node !is null)
				node.hintParentObject(newRegion, false);
		}
		
		if(obj.region is null) {
			deepSpaceTime += time;
			if(deepSpaceTime > 14.0 * 60.0) {
				deepSpaceTime = randomd(-30.0,30.0);
				
				Ship@ ship = createShip(obj.position + random3d(4000.0),
					Creeps.getDesign("Gravitar"), Creeps, free = true);
				ship.addAbilityOrder(0, obj, obj.radius + ship.radius + 5.0, append=true);
				auto@ reg = findNearestRegion(obj.position);
				ship.addMoveOrder(reg.position + (obj.position - reg.position).normalize(reg.radius * 0.8) + random3d(10.0), append=true);
				ship.addAbilityOrder(0, ship, obj.radius + ship.radius + 5.0, append=true);
				ship.addMoveOrder(obj.position + random3d(10.0), append=true);
				ship.addStatus(getStatusID("GravitarShip"));
			}
		}
		else if(deepSpaceTime > 0.0) {
			deepSpaceTime -= time * 0.5;
		}

		if(expire > 0) {
			expire -= time;
			if(expire <= 0.001)
				obj.destroy();
		}

		if(prevRegion is null && isOutsideUniverseExtents(obj.position))
			limitToUniverseExtents(obj.position);

		Empire@ owner = obj.owner;
		if(owner !is null && owner.valid && !type.canOwn)
			@obj.owner = defaultEmpire;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;

			bool usable = false;
			if(owner !is null && owner.valid && owner !is other) {
				usable = false;
			}
			else if(prevRegion !is null) {
				if(prevRegion.PlanetsMask != 0) {
					usable = prevRegion.PlanetsMask & other.mask != 0;
				}
				else {
					usable = hasPlanetsAdjacent(other, prevRegion)
						&& obj.memoryMask & other.mask != 0;
				}
			}
			if(usable) {
				if(regMask & other.mask == 0) {
					regMask |= other.mask;
					other.registerArtifact(obj);
				}
			}
			else {
				if(regMask & other.mask != 0) {
					regMask &= ~other.mask;
					other.unregisterArtifact(obj);
				}
			}
		}

		icon.visible = obj.isVisibleTo(playerEmpire);
		obj.abilityTick(time);
		obj.orbitTick(time);
		return 0.5;
	}

	vec3d get_strategicIconPosition(Artifact& obj) {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	void load(Artifact& obj, SaveFile& file) {
		loadObjectStates(obj, file);
		@type = getArtifactType(file.readIdentifier(SI_Artifact));
		obj.ArtifactType = type.id;
		file >> cast<Savable>(obj.Abilities);
		file >> cast<Savable>(obj.Orbit);
		if(file >= SV_0029)
			file >> regMask;
		if(file >= SV_0121)
			file >> expire;
	}

	void postLoad(Artifact& obj) {
		makeMesh(obj);
	}

	void save(Artifact& obj, SaveFile& file) {
		saveObjectStates(obj, file);
		file.writeIdentifier(SI_Artifact, type.id);
		file << cast<Savable>(obj.Abilities);
		file << cast<Savable>(obj.Orbit);
		file << regMask;
		file << expire;
	}

	void syncInitial(const Artifact& obj, Message& msg) {
		msg.writeSmall(type.id);
		obj.writeOrbit(msg);
		obj.writeAbilities(msg);
	}

	bool syncDelta(const Artifact& obj, Message& msg) {
		bool used = false;
		if(obj.writeAbilityDelta(msg))
			used = true;
		else
			msg.write0();
		if(obj.writeOrbitDelta(msg))
			used = true;
		else
			msg.write0();

		return used;
	}

	void syncDetailed(const Artifact& obj, Message& msg) {
		obj.writeOrbit(msg);
		obj.writeAbilities(msg);
	}
};
