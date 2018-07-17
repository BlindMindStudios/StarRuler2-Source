import resources;
import buildings;

export Considerer;
export ConsiderHook;
export ArtifactConsider;

export ConsiderComponent;
export ConsiderFilter;

interface ArtifactConsider {
	void setTarget(Object@ obj);
	Object@ getTarget();
	bool canTarget(Object@ obj);
	void setTargetPosition(const vec3d& pos);
	vec3d getTargetPosition();
	bool canTargetPosition(const vec3d& pos);
};

interface ConsiderComponent {
};

interface ConsiderFilter {
	bool filter(Object@ obj);
};

interface Considerer {
	Empire@ get_empire();

	Object@ get_currentSupplier();
	ArtifactConsider@ get_artifact();
	void set_artifact(ArtifactConsider@ cons);
	double get_selectedWeight();
	double get_idleTime();

	const BuildingType@ get_building();
	void set_building(const BuildingType@ type);

	ConsiderComponent@ get_component();
	void set_component(ConsiderComponent@ comp);
	void set_filter(ConsiderFilter@ filter);

	//Consider all systems we currently have planets in
	Object@ OwnedSystems(const ConsiderHook& hook, uint limit = uint(-1));

	//Consider all systems on our empire borders
	Object@ BorderSystems(const ConsiderHook& hook);

	//Consider all systems we know other empires have planets in
	Object@ OtherSystems(const ConsiderHook& hook);

	//Consider all our fleets
	Object@ Fleets(const ConsiderHook& hook);

	//Consider planets we own that are important in some way
	Object@ ImportantPlanets(const ConsiderHook& hook);

	//Consider all our planets
	Object@ AllPlanets(const ConsiderHook& hook);

	//Consider a random selection of our planets
	Object@ SomePlanets(const ConsiderHook& hook, uint count = 5, bool alwaysImportant = true);

	//Consider any planets we're using as factories to build things
	Object@ FactoryPlanets(const ConsiderHook& hook);

	//Consider import requests that could be satisfied by the specified resource type
	Object@ MatchingImportRequests(const ConsiderHook& hook, const ResourceType@ type, bool considerExisting);
	//Time since the last colonization of theh import request we're currently considering
	double timeSinceMatchingColonize();
};

interface ConsiderHook {
	double consider(Considerer& cons, Object@ object) const;
};
