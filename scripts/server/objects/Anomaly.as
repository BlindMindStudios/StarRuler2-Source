import resources;
import regions.regions;
import saving;
import anomalies;
import bool getCheatsEverOn() from "cheats";

Anomaly@ createAnomaly(const vec3d& position, uint typeID) {
	ObjectDesc desc;
	desc.type = OT_Anomaly;
	desc.radius = 15.0;
	desc.position = position;
	desc.name = getAnomalyType(typeID).name;
	desc.flags |= objNoDamage;

	Anomaly@ anomaly = Anomaly(desc);
	anomaly.rotation = quaterniond_fromAxisAngle(random3d(1.0), randomd(-pi,pi));
	anomaly.setup(typeID);
	return anomaly;
}

tidy class AnomalyScript {
	const AnomalyType@ type;
	const AnomalyState@ state;
	array<const AnomalyOption@> options;
	array<float> progresses(getEmpireCount(), 0.0);
	bool delta = false;
	bool choiceDelta = false;
	StrategicIconNode@ icon;
	
	float get_progress(Player& player, const Anomaly& obj) {
		if(player == SERVER_PLAYER)
			return 1.0;
		else if(player.emp is null || !player.emp.valid)
			return 0.0;
		else
			return progresses[player.emp.index];
	}
	
	float getEmpireProgress(Empire@ emp) {
		if(emp is null || !emp.valid)
			return 0.0;
		else
			return progresses[emp.index];
	}
	
	string get_narrative(Player& player, const Anomaly& obj) {
		if(get_progress(player, obj) < 1.f)
			return type.desc;
		else if(state !is null && state.narrative.length > 0)
			return state.narrative;
		else
			return type.narrative;
	}
	
	uint get_anomalyType(Player& player, const Anomaly& obj) {
		if(player != SERVER_PLAYER && (get_progress(player, obj) < 1.f || type is null))
			return 0;
		else
			return type.id;
	}
	
	bool get_isOptionSafe(uint index) {
		if(index < options.length)
			return options[index].isSafe;
		else
			return false;
	}
	
	uint getOptionCount() const {
		return options.length;
	}
	
	uint get_optionCount(Player& player, const Anomaly& obj) {
		if(get_progress(player, obj) < 1.f)
			return 0;
		else
			return options.length;
	}
	
	uint get_option(Player& player, const Anomaly& obj, uint index) {
		if(get_progress(player, obj) < 1.f || index >= options.length)
			return 0;
		else
			return options[index].id;
	}

	void clearOptions() {
		options.length = 0;
	}

	void addOption(uint id) {
		options.insertLast(type.options[id]);
	}
	
	string get_model(Player& player, const Anomaly& obj) {
		if(type is null)
			return "";
		else if(get_progress(player, obj) >= 1.f && state !is null && state.modelName.length > 0)
			return state.modelName;
		else
			return type.modelName;
	}
	
	string get_material(Player& player, const Anomaly& obj) {
		if(type is null)
			return "";
		else if(get_progress(player, obj) >= 1.f && state !is null && state.matName.length > 0)
			return state.matName;
		else
			return type.matName;
	}
	
	void setup(Anomaly& obj, uint typeID) {
		@type = getAnomalyType(typeID);
		if(type is null)
			@type = getAnomalyType(0);
		
		auto@ state = type.getState();
		progressToState(obj, state.id);
		
		makeMesh(obj);
	}

	void progressToState(Anomaly& obj, uint stateID) {
		@state = type.states[stateID];
		if(state !is null) {
			for(uint i = 0; i < state.options.length; ++i) {
				auto option = state.options[i];
				if(option.chance < 1.f && randomd() > option.chance)
					continue;
				float chance = state.option_chances[i];
				if(chance < 1.f && randomd() > chance)
					continue;
				options.insertLast(option);
			}
		}
		if(options.length == 0) {
			playParticleSystem("AnomalyCollapse", obj.position, obj.rotation, obj.radius, obj.visibleMask);
			obj.destroy();
		}
		choiceDelta = true;
	}
	
	void choose(Anomaly& obj, Empire@ emp, uint option, Object@ target = null) {
		if(option >= options.length || getEmpireProgress(emp) < 1.f)
			return;

		auto@ opt = options[option];

		Targets@ targs;
		if(opt.targets.length != 0) {
			@targs = Targets(opt.targets);
			@targs.fill(0).obj = target;
		}
		
		options.length = 0;
		opt.choose(obj, emp, targs);

		if(options.length == 0) {
			playParticleSystem("AnomalyCollapse", obj.position, obj.rotation, obj.radius, obj.visibleMask);
			obj.destroy();
		}
		choiceDelta = true;
	}
	
	void choose(Player& player, Anomaly& obj, uint option, Object@ target = null) {
		choose(obj, player.emp, option, target);
	}
	
	void addProgress(Anomaly& obj, Empire@ emp, float amount) {
		uint index = uint(emp.index);
		if(index < progresses.length) {
			float p = progresses[index];
			if(p < 1.f) {
				p += amount / type.scanTime;
				delta = true;
				if(p >= 1.f) {
					emp.notifyAnomaly(obj);
					progresses[index] = 1.f;
					
					if(emp.valid && !getCheatsEverOn()) {
						if(emp is playerEmpire) {
							unlockAchievement("ACH_SCAN_ANOMALY");
							modStat("STAT_ANOMS", 1);
						}
						
						if(mpServer && emp.player !is null)
							clientAchievement(emp.player, "ACH_SCAN_ANOMALY");
					}
				}
				else {
					progresses[index] = p;
				}
			}
		}
	}

	void load(Anomaly& obj, SaveFile& file) {
		loadObjectStates(obj, file);
		@type = getAnomalyType(file.readIdentifier(SI_AnomalyType));
		if(type is null)
			setup(obj, getDistributedAnomalyType().id);
		else
			makeMesh(obj);
		
		uint count = 0;
		file >> count;
		options.length = count;
		for(uint i = 0; i < count; ++i) {
			uint id = 0;
			file >> id;
			@options[i] = type.options[id % type.options.length];
		}
		
		for(uint i = 0; i < progresses.length; ++i)
			file >> progresses[i];

		uint stateId = 0;
		file >> stateId;
		if(stateId < type.states.length)
			@state = type.states[stateId];
	}

	void save(Anomaly& obj, SaveFile& file) {
		saveObjectStates(obj, file);
		file.writeIdentifier(SI_AnomalyType, type.id);
		file << uint(options.length);
		for(uint i = 0; i < options.length; ++i)
			file << options[i].id;
		for(uint i = 0; i < progresses.length; ++i)
			file << progresses[i];
		if(state is null) {
			uint id = uint(-1);
			file << id;
		}
		else
			file << state.id;
	}

	void postInit(Anomaly& obj) {
		updateRegion(obj);
	}

	void destroy(Anomaly& obj) {
		if(obj.region !is null)
			obj.region.removeStrategicIcon(-1, icon);
		icon.markForDeletion();
		leaveRegion(obj);
	}

	void makeMesh(Anomaly& obj) {
		MeshDesc mesh;
		if(type !is null) {
			@mesh.model = getModel(type.modelName);
			@mesh.material = getMaterial(type.matName);
		}
		else {
			@mesh.model = model::Debris;
			@mesh.material = material::Asteroid;
		}
		mesh.memorable = true;
		bindMesh(obj, mesh);

		@icon = StrategicIconNode();
		icon.establish(obj, 0.0225, spritesheet::AnomalyIcons, 0);
		icon.memorable = true;
		
		if(obj.region !is null) {
			obj.region.addStrategicIcon(-1, obj, icon);
			Node@ node = obj.getNode();
			if(node !is null)
				node.hintParentObject(obj.region, false);
		}
	}

	double tick(Anomaly& obj, double time) {
		if(icon !is null)
			icon.visible = obj.isVisibleTo(playerEmpire);
		Region@ reg = obj.region;
		if(reg !is null)
			obj.donatedVision |= reg.DonateVisionMask;
		return 0.2;
	}
	
	void writeProgress(Message& msg) {
		for(uint i = 0; i < progresses.length; ++i) {
			float p = progresses[i];
			if(p <= 0.0) {
				msg.write0();
			}
			else {
				msg.write1();
				msg.writeFixed(p, 0.0, 1.0, 7);
			}
		}
	}

	void writeChoices(Message& msg) {
		msg.writeSmall(type.id);
		msg.writeSmall(state.id);
		msg.writeSmall(options.length);
		for(uint i = 0; i < options.length; ++i)
			msg.writeLimited(options[i].id, type.options.length);
	}

	void syncInitial(const Anomaly& obj, Message& msg) {
		writeChoices(msg);
		writeProgress(msg);
	}

	bool syncDelta(const Anomaly& obj, Message& msg) {
		if(!delta && !choiceDelta)
			return false;
		writeProgress(msg);
		if(choiceDelta) {
			msg.write1();
			writeChoices(msg);
		}
		else {
			msg.write0();
		}
		delta = false;
		choiceDelta = false;
		return true;
	}

	void syncDetailed(const Anomaly& obj, Message& msg) {
		writeProgress(msg);
		writeChoices(msg);
	}
};
