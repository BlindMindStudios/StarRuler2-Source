import tabs.Tab;
import elements.GuiButton;

from tabs.tabbar import popTab, browseTab;
from tabs.DiplomacyTab import createDiplomacyTab;
from tabs.GalaxyTab import createGalaxyTab;
from tabs.DesignOverviewTab import createDesignOverviewTab;
from tabs.WikiTab import createWikiTab;
from tabs.ResearchTab import createResearchTab;
from tabs.PlanetsTab import createPlanetsTab;
from tabs.AttitudesTab import createAttitudesTab;
from community.Home import createCommunityHome;

class HomeTab : Tab {
	GuiButton@ galaxyButton;
	GuiButton@ researchButton;
	GuiButton@ designsButton;
	GuiButton@ diplomacyButton;
	GuiButton@ planetsButton;
	GuiButton@ wikiButton;
	GuiButton@ menuButton;
	GuiButton@ attButton;

	HomeTab() {
		super();
		title = "Home";

		int w = 300, hw = w/2;
		@galaxyButton = GuiButton(this, Alignment(Left+0.5f-w-hw, Top+20, Width=w-10, Height=80), locale::GALAXY);
		galaxyButton.font = FT_Medium;
		galaxyButton.buttonIcon = Sprite(material::SystemUnderAttack);
		galaxyButton.color = Color(0xff9600ff);
		@researchButton = GuiButton(this, Alignment(Left+0.5f-hw, Top+20, Width=w-10, Height=80), locale::RESEARCH);
		researchButton.font = FT_Medium;
		researchButton.buttonIcon = Sprite(material::TabResearch);
		researchButton.color = Color(0xd482ffff);
		@designsButton = GuiButton(this, Alignment(Left+0.5f+hw, Top+20, Width=w-10, Height=80), locale::DESIGNS);
		designsButton.font = FT_Medium;
		designsButton.buttonIcon = Sprite(material::TabDesigns);
		designsButton.color = Color(0x009cffff);
		@diplomacyButton = GuiButton(this, Alignment(Left+0.5f-w-hw, Top+110, Width=w-10, Height=80), locale::DIPLOMACY);
		diplomacyButton.font = FT_Medium;
		diplomacyButton.buttonIcon = Sprite(material::TabDiplomacy);
		diplomacyButton.color = Color(0x37ff00ff);
		@planetsButton = GuiButton(this, Alignment(Left+0.5f-hw, Top+110, Width=w-10, Height=80), locale::PLANETS_TAB);
		planetsButton.font = FT_Medium;
		planetsButton.buttonIcon = Sprite(material::TabPlanets);
		planetsButton.color = Color(0xccff00ff);
		@wikiButton = GuiButton(this, Alignment(Left+0.5f+hw, Top+110, Width=w-10, Height=80), locale::COMMUNITY_HOME_TITLE);
		wikiButton.font = FT_Medium;
		wikiButton.buttonIcon = Sprite(spritesheet::MenuIcons, 3);
		wikiButton.color = Color(0xff0077ff);

		if(hasDLC("Heralds")) {
			@attButton = GuiButton(this, Alignment(Left+0.5f-w-hw, Top+200, Width=w-10, Height=80), locale::ATTITUDES_TAB);
			attButton.font = FT_Medium;
			attButton.buttonIcon = Sprite(material::TabGalaxy);
			attButton.color = Color(0x63ebdbff);
		}

		@menuButton = GuiButton(this, Alignment(Left+0.5f-hw, Bottom-90, Width=w-10, Height=80), locale::MAIN_MENU);
		menuButton.font = FT_Medium;
		menuButton.color = Color(0xaaaaaaff);
	}

	void hide() {
		if(previous !is null)
			popTab(this);
		Tab::hide();
	}

	Color get_seperatorColor() {
		return Color(0x8e8e8eff);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case KET_Key_Up:
					if(event.key == KEY_ESC) {
						if(previous !is null)
							popTab(this);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is galaxyButton) {
				browseTab(this, createGalaxyTab(), false);
				return true;
			}
			else if(event.caller is researchButton) {
				browseTab(this, createResearchTab(), false);
				return true;
			}
			else if(event.caller is designsButton) {
				browseTab(this, createDesignOverviewTab(), false);
				return true;
			}
			else if(event.caller is diplomacyButton) {
				browseTab(this, createDiplomacyTab(), false);
				return true;
			}
			else if(event.caller is planetsButton) {
				browseTab(this, createPlanetsTab(), false);
				return true;
			}
			else if(event.caller is wikiButton) {
				browseTab(this, createCommunityHome(), false);
				return true;
			}
			else if(event.caller is attButton) {
				browseTab(this, createAttitudesTab(), false);
				return true;
			}
			else if(event.caller is menuButton) {
				switchToMenu();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createHomeTab() {
	return HomeTab();
}

bool isHomeTab(Tab@ tab) {
	return cast<HomeTab@>(tab) !is null;
}
