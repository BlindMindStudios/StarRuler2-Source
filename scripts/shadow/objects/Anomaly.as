import resources;
import regions.regions;
import saving;
import anomalies;

tidy class AnomalyScript {
	const AnomalyType@ type;
	const AnomalyState@ state;
	array<const AnomalyOption@> options;
	array<float> progresses(getEmpireCount(), 0);
	StrategicIconNode@ icon;
	
	float get_progress(Player& player, const Anomaly& obj) {
		if(player.emp is null || !player.emp.valid)
			return 0.0;
		else
			return progresses[player.emp.index];
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
		if(get_progress(player, obj) < 1.f || type is null)
			return 0;
		else
			return type.id;
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

	void postInit(Anomaly& obj) {
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
		
		if(obj.region !is null)
			obj.region.addStrategicIcon(-1, obj, icon);
	}

	double tick(Anomaly& obj, double time) {
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
		return 0.2;
	}
	
	void readProgress(Message& msg) {
		for(uint i = 0; i < progresses.length; ++i) {
			if(msg.readBit())
				progresses[i] = msg.readFixed(0.0, 1.0, 7);
			else
				progresses[i] = 0.0;
		}
	}

	void readChoices(Message& msg) {
		@type = getAnomalyType(msg.readSmall());
		@state = type.states[msg.readSmall()];
		options.length = msg.readSmall();
		for(uint i = 0; i < options.length; ++i)
			@options[i] = type.options[msg.readLimited(type.options.length)];
	}

	void syncInitial(Anomaly& obj, Message& msg) {
		readChoices(msg);
		readProgress(msg);
		makeMesh(obj);
	}

	void syncDelta(Anomaly& obj, Message& msg, double tDiff) {
		readProgress(msg);
		if(msg.readBit())
			readChoices(msg);
	}

	void syncDetailed(Anomaly& obj, Message& msg, double tDiff) {
		readProgress(msg);
		readChoices(msg);
	}
};
