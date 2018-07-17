import construction.Constructible;
import buildings;
import saving;

tidy class BuildingConstructible : Constructible {
	vec2i position;
	const BuildingType@ building;

	bool isTimed = false;
	double timeProgress = 0;

	BuildingConstructible(Object& obj, vec2i pos, const BuildingType@ type) {
		position = pos;
		@building = type;

		totalLabor = type.laborCost;
		if(totalLabor == 0) {
			totalLabor = max(type.buildTime, 1.0) / obj.buildingConstructRate / obj.owner.BuildingConstructRate / obj.owner.ImperialBldConstructionRate;
			isTimed = true;
		}
	}

	BuildingConstructible(SaveFile& file) {
		Constructible::load(file);
		uint id = file.readIdentifier(SI_Building);
		@building = getBuildingType(id);
		file >> position;
		if(file >= SV_0149) {
			file >> isTimed;
			file >> timeProgress;
		}
	}

	void save(SaveFile& file) {
		Constructible::save(file);
		file.writeIdentifier(SI_Building, building.id);
		file << position;
		file << isTimed;
		file << timeProgress;
	}

	ConstructibleType get_type() {
		return CT_Building;
	}

	bool get_canComplete() {
		return !isTimed || timeProgress >= totalLabor;
	}

	string get_name() {
		return building.name;
	}

	TickResult tick(Object& obj, double time) override {
		if(!building.canProgress(obj))
			return TR_UnusedLabor;

		if(isTimed) {
			timeProgress += time;
			curLabor = timeProgress;
		}

		double progress = curLabor / max(totalLabor, 0.001);
		obj.setBuildingCompletion(position.x, position.y, progress);
		return isTimed ? TR_VanishLabor : TR_UsedLabor;
	}

	void cancel(Object& obj) {
		Constructible::cancel(obj);
		vec2i pos = position;
		position = vec2i(-1, -1);
		obj.forceDestroyBuilding(pos);
	}

	void complete(Object& obj) {
		obj.setBuildingCompletion(position.x, position.y, 1.f);
	}

	void write(Message& msg) {
		Constructible::write(msg);
		msg << building.id;
		msg << isTimed;
	}

	bool repeat(Object& obj) {
		return false;
	}
};
