import util.settings_page;

GamePage page;
class GamePage : GameSettingsPage {
	void makeSettings() {
		color = colors::Green;
		header = locale::NG_GAME_OPTIONS;
		icon = Sprite(material::TabPlanets);

		Title(locale::NG_UNIVERSE_GENERATION);
		Frequency(locale::NG_PLANET_FREQUENCY, "PLANET_FREQUENCY", min = 0.2, max = 3.0);
		Occurance(locale::NG_ANOMALY_OCCURANCE, "ANOMALY_OCCURANCE");
		Occurance(locale::NG_REMNANT_OCCURANCE, "REMNANT_OCCURANCE");
		Occurance(locale::NG_ASTEROID_OCCURANCE, "ASTEROID_OCCURANCE");
		Occurance(locale::NG_RESOURCE_ASTEROID_OCCURANCE, "RESOURCE_ASTEROID_OCCURANCE");
		Occurance(locale::NG_UNIQUE_SYSTEM_OCCURANCE, "UNIQUE_SYSTEM_OCCURANCE");
		Occurance(locale::NG_UNIQUE_RESOURCE_OCCURANCE, "UNIQUE_RESOURCE_OCCURANCE");
		Occurance(locale::NG_RESOURCE_SCARCITY, "RESOURCE_SCARCITY", max=2.0, tooltip=locale::NGTT_RESOURCE_SCARCITY);
		Occurance(locale::NG_CIVILIAN_TRADE, "CIVILIAN_TRADE_MULT", max=10.0, tooltip=locale::NGTT_CIVILIAN_TRADE);
		Frequency(locale::NG_ARTIFACT_FREQUENCY, "ARTIFACT_FREQUENCY", min = 0.2, max = 3.0);
		Frequency(locale::NG_SYSTEM_SIZE, "SYSTEM_SIZE", min = 0.2, max = 3.0);

		emptyline();
		Title(locale::NG_GAME_OPTIONS);
		//Occurance(locale::NG_RANDOM_EVENTS, "RANDOM_EVENT_OCCURRENCE", max=3.0);
		Toggle(locale::NG_ENABLE_DREAD_PIRATE, "ENABLE_DREAD_PIRATE", halfWidth=true, tooltip=locale::NGTT_ENABLE_DREAD_PIRATE);
		/*Toggle(locale::NG_ENABLE_CIVILIAN_TRADE, "ENABLE_CIVILIAN_TRADE", halfWidth=true);*/
		Toggle(locale::NG_ENABLE_INFLUENCE_EVENTS, "ENABLE_INFLUENCE_EVENTS", halfWidth=true, tooltip=locale::NGTT_ENABLE_INFLUENCE_EVENTS);
		Toggle(locale::NG_DISABLE_STARTING_FLEETS, "DISABLE_STARTING_FLEETS", halfWidth=true, tooltip=locale::NGTT_DISABLE_STARTING_FLEETS);
		Toggle(locale::NG_REMNANT_AGGRESSION, "REMNANT_AGGRESSION", halfWidth=true, tooltip=locale::NGTT_REMNANT_AGGRESSION);
		Toggle(locale::NG_ALLOW_TEAM_SURRENDER, "ALLOW_TEAM_SURRENDER", halfWidth=true, tooltip=locale::NGTT_ALLOW_TEAM_SURRENDER);
		Toggle(locale::NG_START_EXPLORED_MAP, "START_EXPLORED_MAP", halfWidth=true, tooltip=locale::NGTT_START_EXPLORED_MAP);

		auto@ tforming = Toggle(locale::NG_ENABLE_TERRAFORMING, "ENABLE_TERRAFORMING", halfWidth=true, tooltip=locale::NGTT_ENABLE_TERRAFORMING);
		if(hasDLC("Heralds")) {
			tforming.DefaultValue = false;
			tforming.set(false);
		}

		emptyline();
		Title(locale::NG_VICTORY_OPTIONS);
		Number(locale::NG_TIME_LIMIT, "GAME_TIME_LIMIT", tooltip=locale::NGTT_TIME_LIMIT, halfWidth=true, step=10);
		Toggle(locale::NG_ENABLE_REVENANT_PARTS, "ENABLE_REVENANT_PARTS", tooltip=locale::NGTT_ENABLE_REVENANT_PARTS);
		if(hasDLC("Heralds"))
			Toggle(locale::NG_ENABLE_INFLUENCE_VICTORY, "ENABLE_INFLUENCE_VICTORY", tooltip=locale::NGTT_ENABLE_INFLUENCE_VICTORY);
	}
};
