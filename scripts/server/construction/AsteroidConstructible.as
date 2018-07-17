import construction.Constructible;
import resources;

tidy class AsteroidConstructible : Constructible {
	Asteroid@ asteroid;
	const ResourceType@ resource;

	AsteroidConstructible(Object& obj, Asteroid@ a, const ResourceType@ r, double cost) {
		@asteroid = a;
		@resource = r;
		totalLabor = cost;
	}

	AsteroidConstructible(SaveFile& file) {
		Constructible::load(file);
		uint rid = file.readIdentifier(SI_Resource);
		@resource = getResource(rid);
		file >> asteroid;
	}

	void save(SaveFile& file) {
		Constructible::save(file);
		file.writeIdentifier(SI_Resource, resource.id);
		file << asteroid;
	}

	ConstructibleType get_type() {
		return CT_Asteroid;
	}

	string get_name() {
		return format(locale::BUILD_ASTEROID, resource.name);
	}

	TickResult tick(Object& obj, double time) override {
		if(!asteroid.valid)
			return TR_Remove;
		if(!asteroid.canDevelop(obj.owner))
			return TR_Remove;
		return TR_UsedLabor;
	}

	void complete(Object& obj) {
		asteroid.setup(obj, obj.owner, resource.id);
	}

	void write(Message& msg) {
		Constructible::write(msg);
		msg << resource.id;
	}

	bool repeat(Object& obj) {
		return false;
	}
};
