#priority init 1501
import maps;

#section game
import dialogue;
#section all

ModEditor _map;
class ModEditor : Map {
	ModEditor() {
		super();

		isListed = false;
		isScenario = true;
	}

#section server
	void prepareSystem(SystemData@ data, SystemDesc@ desc) {
		@data.homeworlds = null;
		Map::prepareSystem(data, desc);
	}

	bool canHaveHomeworld(SystemData@ data, Empire@ emp) {
		return false;
	}

	void preGenerate() {
		Map::preGenerate();
		radius = 40000;
	}

	void placeSystems() {
		addSystem(vec3d(0, 0, 0), code=SystemCode()
			<< "NameSystem(Sandbox)"
			<< "MakeStar(Temperature = 5778, Radius = 75)"
			<< "ExpandSystem(2000)"
		);
	}

	void modSettings(GameSettings& settings) {
		settings.empires.length = 2;
		settings.empires[0].name = "Player";
		settings.empires[1].name = "Enemy";
		settings.empires[1].shipset = "Gevron";
		settings.empires[1].type = ET_NoAI;
		config::ENABLE_UNIQUE_SPREADS = 0.0;
		config::DISABLE_STARTING_FLEETS = 1.0;
		config::ENABLE_DREAD_PIRATE = 0.0;
		config::ENABLE_INFLUENCE_EVENTS = 0.0;
	}

	void init() {
		Empire@ player = getEmpire(0);
		Empire@ enemy = getEmpire(1);
		
		player.Victory = -2;
		enemy.Victory = -2;
	}

	bool initialized = false;
	void tick(double time) {
		if(!initialized) {
			guiDialogueAction(CURRENT_PLAYER, "ModEditor.ModEditor::SetupGUI");
			initialized = true;
		}
	}
#section all
};

#section gui
import tabs.tabbar;
import tabs.HomeTab;
import editor.editor;
import editor.modinfo;
import editor.overview;
from tabs.GlobalBar import GlobalBar;
from tabs.WikiTab import createWikiTab;

class SetupGUI : DialogueAction {
	void call() {
		isEditor = true;

		//Clean global bar
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.container.visible = false;

		//Remove existing tabs
		tabBar.goButton.visible = false;
		tabBar.homeButton.visible = false;
		for(uint i = 1, cnt = tabs.length; i < cnt; ++i)
			closeTab(tabs[1]);

		auto@ infoTab = createModInfoTab();
		infoTab.locked = true;
		newTab(infoTab);
		switchToTab(infoTab);

		auto@ overviewTab = createOverviewTab();
		overviewTab.locked = true;
		newTab(overviewTab);

		auto@ wikiTab = createWikiTab("Modding");
		wikiTab.locked = true;
		newTab(wikiTab);

		closeTab(tabs[0]);
	}
};

bool isEditor = false;
void tick(double time) {
	if(!isEditor)
		return;

	//Make any home tabs into overview tabs
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		auto@ tab = tabs[i];
		if(cast<HomeTab>(tab) !is null)
			browseTab(tab, createOverviewTab());
	}

}
