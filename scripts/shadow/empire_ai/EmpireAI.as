tidy class EmpireAI : Component_EmpireAI {
	vec3d get_aiFocus() {
		return vec3d();
	}

	bool get_isAI(Empire& emp) {
		return false;
	}

	string getRelation(Player& pl, Empire& emp) {
		return "";
	}

	int getRelationState(Player& pl, Empire& emp) {
		return 0;
	}
};
