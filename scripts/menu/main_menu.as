import menus;
import settings.game_settings;
from new_game import showNewGame;
from multiplayer_menu import showMultiplayer;
from irc_window import openIRC, closeIRC, LinkableMarkupText;
import dialogs.QuestionDialog;
import icons;

// TODO: Switch this out once we fix multiple starts.
const bool M_BROKEN = false;

enum MenuActions {
	MA_NewGame,
	MA_EndGame,
	MA_Tutorial,
	MA_Campaign,
	MA_LoadGame,
	MA_SaveGame,
	MA_Options,
	MA_Resume,
	MA_Quit,
	MA_OpenIRC,
	MA_CloseIRC,
	MA_Multiplayer,
	MA_Disconnect,
	MA_Sandbox,
	MA_Update,
	MA_Mods,
};

class MainMenu : MenuBox {
	MenuNews news;

	MainMenu() {
		super();
	}

	void buildMenu() {
		if(game_running && gameSpeed == 0)
			title.text = locale::PAUSED_MENU;
		else
			title.text = locale::MAIN_MENU;

		if(game_running) {
			if(gameSpeed == 0 && settings::bMenuPause)
				items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 10), locale::RESUME_GAME, MA_Resume));
			else
				items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 10), locale::RETURN_TO_GAME, MA_Resume));
		}

		if(mpClient)
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 8), locale::DISCONNECT, MA_Disconnect));
		else if(game_running)
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 8), locale::END_GAME, MA_EndGame));
		
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 3), locale::TUTORIAL, MA_Tutorial));
		//items.addItem(MenuAction(Sprite(material::TabPlanets), locale::CAMPAIGN, MA_Campaign));
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 0), locale::NEW_GAME, MA_NewGame));
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 1), locale::LOAD_GAME, MA_LoadGame));
		
		if(game_running && !mpClient)
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 2), locale::SAVE_GAME, MA_SaveGame));
		items.addItem(MenuAction(Sprite(spritesheet::ResourceIconsSmall, 46), locale::MODS_MENU, MA_Mods));
		if(!game_running && !STEAM_EQUIV_BUILD)
			items.addItem(MenuAction(icons::Refresh, locale::CHECK_FOR_UPDATES, MA_Update));
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 4), locale::MULTIPLAYER, MA_Multiplayer));
		items.addItem(MenuAction(Sprite(material::TabDesigns), locale::SANDBOX, MA_Sandbox));
		if(IRC.running)
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 5), locale::CLOSE_IRC, MA_CloseIRC));
		else
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 6), locale::OPEN_IRC, MA_OpenIRC));
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 7), locale::MENU_OPTIONS, MA_Options));
		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 8), locale::QUIT_GAME, MA_Quit));
	}

	void tick(double time) {
		if(!game_running && !menu_container.animating && menu_container.visible) {
			if(mpIsConnected())
				showNewGame(true);
			else if(mpIsConnecting() || cloud::queueRequest)
				showMultiplayer();
		}
	}

	void startTutorial() {
		GameSettings settings;
		settings.defaults();
		settings.galaxies[0].map_id = "Tutorial.Tutorial";

		Message msg;
		settings.write(msg);
		if(topMod !is baseMod) {
			array<string> basemods = {"base"};
			switchToMods(basemods);
		}
		startNewGame(msg);
	}

	void startSandbox() {
		GameSettings settings;
		settings.defaults();
		settings.galaxies[0].map_id = "Sandbox.Sandbox";

		Message msg;
		settings.write(msg);
		startNewGame(msg);
	}
	
	void _stopGame() {
		stopGame();
		refresh();
	}

	void animate(MenuAnimation type) {
		if(type == MAni_LeftOut || type == MAni_RightOut)
			showDescBox(null);
		MenuBox::animate(type);
	}

	void completeAnimation(MenuAnimation type) {
		if(type == MAni_LeftShow || type == MAni_RightShow)
			showDescBox(news);
		MenuBox::completeAnimation(type);
	}

	void onSelected(const string& name, int value) {
		switch(value) {
			case MA_Resume:
				switchToGame();
			break;
			case MA_NewGame:
				showNewGame();
			break;
			case MA_Tutorial:
				if(game_running)
					question(locale::PROMPT_TUTORIAL, ConfirmChoice(MenuChoice(this.startTutorial)));
				else
					startTutorial();
			break;
			case MA_Campaign:
				switchToMenu(campaign_menu);
			break;
			case MA_Sandbox:
				if(game_running)
					question(locale::PROMPT_SANDBOX, ConfirmChoice(MenuChoice(this.startSandbox)));
				else
					startSandbox();
			break;
			case MA_Options:
				switchToMenu(options_menu);
			break;
			case MA_LoadGame:
				switchToMenu(load_menu);
			break;
			case MA_SaveGame:
				switchToMenu(save_menu);
			break;
			case MA_Mods:
				switchToMenu(mods_menu);
			break;
			case MA_EndGame:
				if(game_running)
					question(locale::PROMPT_END, ConfirmChoice(MenuChoice(this._stopGame)));
				else
					_stopGame();
			break;
			case MA_Disconnect:
				if(game_running)
					question(locale::PROMPT_DISCONNECT, ConfirmChoice(MenuChoice(this._stopGame)));
				else {
					mpDisconnect();
					_stopGame();
				}
			break;
			case MA_OpenIRC:
				if(!IRC.running) {
					IRC.nickname = settings::sNickname;
					IRC.connect();
					openIRC();
					refresh();
				}
			break;
			case MA_CloseIRC:
				if(IRC.running) {
					IRC.disconnect();
					closeIRC();
					refresh();
				}
			break;
			case MA_Quit:
				if(game_running)
					question(locale::PROMPT_QUIT, ConfirmChoice(quitGame));
				else
					quitGame();
			break;
			case MA_Multiplayer:
				showMultiplayer();
			break;
			case MA_Update:
				checkForUpdates();
			break;
		}
	}
};

funcdef void MenuChoice();

class ConfirmChoice : QuestionDialogCallback {
	MenuChoice@ choice;
	
	ConfirmChoice(MenuChoice@ Choice) {
		@choice = Choice;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			choice();
	}
};

class MenuNews : DescBox {
	GuiPanel@ newsPanel;
	LinkableMarkupText@ newsText;
	WebData wdata;
	bool shown = false;

	GuiPanel@ modsPanel;

	GuiMarkupText@ modsText;
	GuiButton@ modsButton;
	GuiButton@ workshopButton;
	GuiButton@ internetButton;

	MenuNews() {
		@newsPanel = GuiPanel(this, Alignment(Left, Top, Right, Bottom-100));
		@newsText = LinkableMarkupText(newsPanel, recti_area(12,12,100,100));
		newsText.text = "...";
		newsText.paragraphize = true;

		@modsPanel = GuiPanel(this, Alignment(Left, Bottom-88, Right, Bottom));
		@modsText = GuiMarkupText(modsPanel, Alignment(Left+12, Top+12, Right-12, Bottom-52));
		modsText.defaultFont = FT_Bold;

		@modsButton = GuiButton(modsPanel, Alignment(Left+0.5f-204, Bottom-50, Width=200, Height=40), locale::MANAGE_MODS);
		modsButton.buttonIcon = Sprite(spritesheet::ResourceIconsSmall, 46);

		@workshopButton = GuiButton(modsPanel, Alignment(Left+0.5f+4, Bottom-50, Width=200, Height=40), locale::OPEN_WORKSHOP);
		workshopButton.buttonIcon = icons::Import;

		@internetButton = GuiButton(newsPanel, Alignment(Left+0.5f-200, Top+0.5f-30, Left+0.5f+200, Top+0.5f+30), locale::ENABLE_INTERNET);
		internetButton.visible = false;

		if(cloud::isActive) {
			settings::bEnableInternet = true;
		}
		else {
			workshopButton.visible = false;
			modsButton.alignment.left.pixels += 104;
		}

		if(settings::bEnableInternet) {
			getWikiPage("News", wdata);
		}
		else {
			internetButton.visible = true;
			newsText.text = "[font=Medium]News[/font]";
			shown = true;
		}

		refresh();
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		DescBox::updateAbsolutePosition();
		if(newsText !is null)
			newsText.size = vec2i(newsPanel.size.width-24, newsText.renderer.height+10);
	}

	void refresh() {
		uint installed = 0;
		uint enabled = 0;
		for(uint i = 0, cnt = modCount; i < cnt; ++i) {
			auto@ mod = getMod(i);
			if(!mod.listed)
				continue;
			installed += 1;
			if(mod.enabled)
				enabled += 1;
		}

		modsText.text = format("[center]"+locale::MENU_MOD_COUNTS+"[/center]", toString(installed), toString(enabled));
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is modsButton) {
				switchToMenu(mods_menu);
				return true;
			}
			else if(evt.caller is workshopButton) {
				openBrowser("http://steamcommunity.com/app/282590/workshop/");
				return true;
			}
			else if(evt.caller is internetButton) {
				internetButton.visible = false;
				shown = false;
				getWikiPage("News", wdata);

				settings::bEnableInternet = true;
				saveSettings();
				return true;
			}
		}
		return DescBox::onGuiEvent(evt);
	}

	void show() {
		DescBox::show();
		refresh();
	}

	void draw() {
		if(!shown && wdata.completed) {
			string result = wdata.result;
			newsText.text = result;
			shown = true;
			updateAbsolutePosition();
		}

		skin.draw(SS_PlainBox, SF_Normal, newsPanel.AbsolutePosition, Color(0xffffffff));
		skin.draw(SS_PlainBox, SF_Normal, modsPanel.AbsolutePosition, Color(0xffffffff));
		BaseGuiElement::draw();
	}
};

void init() {
	MainMenu menu;

	@main_menu = menu;
	showDescBox(menu.news);
	switchToMenu(menu);
}
