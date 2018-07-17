export CampaignScenario;
export getCampaignScenarioCount, getCampaignScenario;
export completeCampaignScenario, reloadCampaignCompletion;

class CampaignScenario {
	uint id;
	string ident;

	string name;
	string description;
	Sprite picture;
	Sprite icon;
	Color color;

	array<string> dependencies;
	string mapName;

	bool completed = false;

	bool get_isAvailable() const {
		for(uint i = 0, cnt = dependencies.length; i < cnt; ++i) {
			auto@ other = getCampaignScenario(i);
			if(other !is null && !other.completed)
				return false;
		}
		return true;
	}
};

array<CampaignScenario@> campaignList;
dictionary campaignIdents;

uint getCampaignScenarioCount() {
	return campaignList.length;
}

const CampaignScenario@ getCampaignScenario(uint index) {
	if(index >= campaignList.length)
		return null;
	return campaignList[index];
}

const CampaignScenario@ getCampaignScenario(const string& ident) {
	CampaignScenario@ scen;
	if(!campaignIdents.get(ident, @scen))
		return null;
	return scen;
}

void loadScenarios(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	CampaignScenario@ scen;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(key == "Scenario") {
			@scen = CampaignScenario();
			scen.ident = value;
			scen.id = campaignList.length;
			campaignList.insertLast(scen);
			campaignIdents.set(scen.ident, @scen);
		}
		else if(scen is null) {
			file.error("Missing 'Scenario: ID' line.");
		}
		else if(key == "Name") {
			scen.name = localize(value);
		}
		else if(key == "Description") {
			scen.description = localize(value);
		}
		else if(key == "Icon") {
			scen.icon = getSprite(value);
		}
		else if(key == "Picture") {
			scen.picture = getSprite(value);
		}
		else if(key == "Color") {
			scen.color = toColor(value);
		}
		else if(key == "Map") {
			scen.mapName = value;
		}
		else if(key == "Dependency") {
			scen.dependencies.insertLast(value);
		}
	}
}

void preInit() {
	FileList list("data/campaign", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadScenarios(list.path[i]);
	reloadCampaignCompletion();
}

void completeCampaignScenario(const string& ident) {
	reloadCampaignCompletion();
	CampaignScenario@ scen;
	if(campaignIdents.get(ident, @scen) && scen !is null)
		scen.completed = true;

	WriteFile file(path_join(modProfile, "campaign"));
	for(uint i = 0, cnt = campaignList.length; i < cnt; ++i) {
		if(campaignList[i].completed)
			file.writeLine(campaignList[i].ident);
	}
}

void reloadCampaignCompletion() {
	for(uint i = 0, cnt = campaignList.length; i < cnt; ++i)
		campaignList[i].completed = false;

	ReadFile completed(path_join(modProfile, "campaign"), true);
	CampaignScenario@ scen;
	while(completed++) {
		if(campaignIdents.get(completed.line, @scen) && scen !is null)
			scen.completed = true;
	}
}
