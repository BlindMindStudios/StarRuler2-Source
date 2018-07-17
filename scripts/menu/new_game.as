import menus;
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiPanel;
import elements.GuiOverlay;
import elements.GuiSprite;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiSpinbox;
import elements.GuiCheckbox;
import elements.GuiDropdown;
import elements.GuiContextMenu;
import elements.GuiIconGrid;
import elements.GuiEmpire;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import elements.GuiBackgroundPanel;
import dialogs.SaveDialog;
import dialogs.LoadDialog;
import dialogs.MessageDialog;
import dialogs.QuestionDialog;
import util.settings_page;
import empire_data;
import traits;
import icons;
from util.draw_model import drawLitModel;

import void showMultiplayer() from "multiplayer_menu";

from maps import Map, maps, mapCount, getMap;

import settings.game_settings;
import util.game_options;

const int EMPIRE_SETUP_HEIGHT = 96;
const int GALAXY_SETUP_HEIGHT = 200;

const int REC_MAX_PEREMP = 25;
const int REC_MAX_OPTIMAL = 150;
const int REC_MAX_BAD = 400;
const int REC_MAX_OHGOD = 1000;

const array<Color> QDIFF_COLORS = {Color(0x00ff00ff), Color(0x1197e0ff), Color(0xff0000ff)};
const array<string> QDIFF_NAMES = {locale::AI_DIFF_EASY, locale::AI_DIFF_NORMAL, locale::AI_DIFF_HARD};
const array<string> QDIFF_DESC = {locale::AI_DIFF_EASY_DESC, locale::AI_DIFF_NORMAL_DESC, locale::AI_DIFF_HARD_DESC};
const array<Sprite> QDIFF_ICONS = {Sprite(spritesheet::AIDifficulty, 0), Sprite(spritesheet::AIDifficulty, 1), Sprite(spritesheet::AIDifficulty, 2)};

NameGenerator empireNames;
bool empireNamesInitialized = false;

class ConfirmStart : QuestionDialogCallback {
	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			new_game.start();
			hideNewGame(true);
		}
	}
};

class NewGame : BaseGuiElement {
	GameSettings settings;

	GuiBackgroundPanel@ empireBG;
	GuiBackgroundPanel@ gameBG;
	GuiBackgroundPanel@ chatBG;

	GuiButton@ backButton;
	GuiButton@ inviteButton;
	GuiButton@ playButton;

	EmpirePortraitCreation portraits;

	int nextEmpNum = 1;
	GuiPanel@ empirePanel;
	EmpireSetup@[] empires;
	GuiButton@ addAIButton;

	GuiSkinElement@ gameHeader;
	GuiButton@ mapsButton;
	array<GuiButton@> settingsButtons;
	array<GuiPanel@> settingsPanels;
	GuiButton@ resetButton;

	GuiPanel@ galaxyPanel;
	GalaxySetup@[] galaxies;
	GuiButton@ addGalaxyButton;

	GuiPanel@ mapPanel;
	GuiText@ mapHeader;
	GuiListbox@ mapList;

	GuiPanel@ chatPanel;
	GuiMarkupText@ chatLog;
	GuiTextbox@ chatBox;

	bool animating = false;
	bool hide = false;
	bool fromMP = false;
	bool choosingMap = false;

	string chatMessages;

	NewGame() {
		super(null, recti());

		@empireBG = GuiBackgroundPanel(this, Alignment(
			Left+0.05f, Top+0.1f, Left+0.5f-6, Bottom-0.1f));
		empireBG.title = locale::MENU_EMPIRES;
		empireBG.titleColor = Color(0x00ffe9ff);

		@gameBG = GuiBackgroundPanel(this, Alignment(
			Left+0.5f+6, Top+0.1f, Left+0.95f, Bottom-0.1f));

		@gameHeader = GuiSkinElement(gameBG, Alignment(Left+1, Top+1, Right-2, Top+41), SS_FullTitle);

		@mapsButton = GuiButton(gameHeader, Alignment(Left, Top+1, Width=200, Height=38));
		mapsButton.text = locale::MENU_GALAXIES;
		mapsButton.buttonIcon = Sprite(material::SystemUnderAttack);
		mapsButton.toggleButton = true;
		mapsButton.font = FT_Medium;
		mapsButton.pressed = true;
		mapsButton.style = SS_TabButton;

		@chatBG = GuiBackgroundPanel(this, Alignment(
			Left+0.05f, Bottom-0.1f-250, Left+0.5f-6, Bottom-0.1f));
		chatBG.title = locale::CHAT;
		chatBG.titleColor = Color(0xff8000ff);
		chatBG.visible = false;

		//Empire list
		@empirePanel = GuiPanel(empireBG,
			Alignment(Left, Top+34, Right, Bottom-4));

		@addAIButton = GuiButton(empirePanel,
			recti_area(vec2i(), vec2i(200, 36)),
			locale::ADD_AI);
		addAIButton.buttonIcon = icons::Add;

		//Game settings
		for(uint i = 0, cnt = GAME_SETTINGS_PAGES.length; i < cnt; ++i) {
			auto@ panel = GuiPanel(gameBG,
				Alignment(Left, Top+46, Right, Bottom-40));
			panel.visible = false;
			settingsPanels.insertLast(panel);

			auto@ page = GAME_SETTINGS_PAGES[i];
			page.create(panel);

			auto@ button = GuiButton(gameHeader, Alignment(Left+200+(i*200), Top+1, Width=200, Height=38));
			button.text = page.header;
			button.buttonIcon = page.icon;
			button.toggleButton = true;
			button.pressed = false;
			button.font = FT_Medium;
			button.style = SS_TabButton;
			settingsButtons.insertLast(button);
		}

		@resetButton = GuiButton(gameBG, Alignment(Left+0.5f-120, Bottom-40, Width=240, Height=35), locale::NG_RESET);
		resetButton.color = Color(0xff8080ff);
		resetButton.buttonIcon = icons::Reset;
		resetButton.visible = false;

		//Galaxy list
		@galaxyPanel = GuiPanel(gameBG,
			Alignment(Left, Top+46, Right, Bottom-4));
		galaxyPanel.visible = false;

		@addGalaxyButton = GuiButton(galaxyPanel,
			recti_area(vec2i(), vec2i(260, 36)),
			locale::ADD_GALAXY);
		addGalaxyButton.buttonIcon = Sprite(spritesheet::CardCategoryIcons, 3);

		//Maps choice list
		@mapPanel = GuiPanel(gameBG,
			Alignment(Left, Top+46, Right, Bottom-4));
		mapPanel.visible = true;
		choosingMap = true;

		@mapHeader = GuiText(mapPanel, Alignment(Left, Top, Right, Top+30));
		mapHeader.font = FT_Medium;
		mapHeader.horizAlign = 0.5;
		mapHeader.stroke = colors::Black;
		mapHeader.text = locale::CHOOSE_MAP;

		@mapList = GuiListbox(mapPanel,
			Alignment(Left+4, Top+34, Right-4, Bottom-4));
		mapList.itemStyle = SS_DropdownListItem;
		mapList.itemHeight = 100;

		updateMapList();

		//Chat
		@chatPanel = GuiPanel(chatBG, Alignment(Left+8, Top+34, Right-8, Bottom-38));
		@chatLog = GuiMarkupText(chatPanel, recti_area(0, 0, 100, 100));
		@chatBox = GuiTextbox(chatBG, Alignment(Left+6, Bottom-36, Right-6, Bottom-6));

		//Actions
		@playButton = GuiButton(this, Alignment(
			Right-0.05f-200, Bottom-0.1f+6, Width=200, Height=46),
			locale::START_GAME);
		playButton.buttonIcon = Sprite(spritesheet::MenuIcons, 9);

		@backButton = GuiButton(this, Alignment(
			Left+0.05f, Bottom-0.1f+6, Width=200, Height=46),
			locale::BACK);
		backButton.buttonIcon = Sprite(spritesheet::MenuIcons, 11);

		@inviteButton = GuiButton(this, Alignment(
			Left+0.05f+208, Bottom-0.1f+6, Width=200, Height=46),
			locale::INVITE_FRIEND);
		inviteButton.buttonIcon = Sprite(spritesheet::MenuIcons, 13);
		inviteButton.visible = cloud::inLobby;

		updateAbsolutePosition();
	}

	void updateMapList() {
		mapList.clearItems();
		for(uint i = 0, cnt = mapCount; i < cnt; ++i) {
			auto@ mp = getMap(i);
			if(mp.isUnique) {
				bool found = false;
				for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
					if(galaxies[i].mp.id == mp.id) {
						found = true;
						break;
					}
				}
				if(found)
					continue;
			}
			if(mp.isListed && !mp.isScenario && (mp.dlc.length == 0 || hasDLC(mp.dlc)))
				mapList.addItem(MapElement(mp));
		}
	}

	void init() {
		if(!empireNamesInitialized) {
			empireNames.read("data/empire_names.txt");
			empireNames.useGeneration = false;
			empireNamesInitialized = true;
		}

		portraits.reset();
		clearEmpires();
		addEmpire(true, getRacePreset(0));
		if(!mpServer && !fromMP) {
			addEmpire(false);
			addEmpire(false);
			RaceChooser(empires[0], true);
		}
		updateAbsolutePosition();

		switchPage(0);

		if(fromMP) {
			mapPanel.visible = false;
			galaxyPanel.visible = true;
			choosingMap = false;
		}
		else {
			mapPanel.visible = true;
			galaxyPanel.visible = false;
			choosingMap = true;
			updateMapList();
		}

		addGalaxyButton.visible = !fromMP;
		addAIButton.visible = !fromMP;
		chatMessages = "";

		if(fromMP) {
			playButton.text = locale::MP_NOT_READY;
			playButton.color = colors::Orange;
		}
		else {
			playButton.text = locale::START_GAME;
			playButton.color = colors::White;
		}
	}

	void addChat(const string& str) {
		chatMessages += str+"\n";
		bool wasBottom = chatPanel.vert.pos >= (chatPanel.vert.end - chatPanel.vert.page);
		chatLog.text = chatMessages;
		chatPanel.updateAbsolutePosition();
		if(wasBottom) {
			chatPanel.vert.pos = max(0.0, chatPanel.vert.end - chatPanel.vert.page);
			chatPanel.updateAbsolutePosition();
		}
	}

	void resetAIColors() {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			auto@ setup = empires[i];
			if(setup.player)
				continue;
			setup.settings.color = colors::Invisible;
		}
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			auto@ setup = empires[i];
			if(setup.player)
				continue;
			setUniqueColor(setup);
		}
	}

	void resetAIRaces() {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			auto@ setup = empires[i];
			if(setup.player)
				continue;
			setup.settings.raceName = "";
		}
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			auto@ setup = empires[i];
			if(setup.player)
				continue;
			setup.applyRace(getUniquePreset());
		}
	}

	RacePreset@ getUniquePreset() {
		uint index = randomi(0, getRacePresetCount() - 1);
		for(uint i = 0, cnt = getRacePresetCount(); i < cnt; ++i) {
			auto@ preset = getRacePreset((index+i) % cnt);
			if(preset.dlc.length != 0 && !hasDLC(preset.dlc))
				continue;
			bool has = false;
			for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
				if(empires[n].settings.raceName == preset.name) {
					has = true;
					break;
				}
			}
			if(!has) {
				return preset;
			}
		}
		for(uint i = 0, cnt = getRacePresetCount(); i < cnt; ++i) {
			auto@ preset = getRacePreset((index+i) % cnt);
			if(preset.dlc.length != 0 && !hasDLC(preset.dlc))
				continue;
			return preset;
		}
		return getRacePreset(index);
	}

	void setUniqueColor(EmpireSetup@ setup) {
		bool found = false;
		Color setColor;
		for(uint i = 0, cnt = getEmpireColorCount(); i < cnt; ++i) {
			Color col = getEmpireColor(i).color;
			bool has = false;
			for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
				if(empires[n] !is setup && empires[n].settings.color.color == col.color) {
					has = true;
					break;
				}
			}
			if(!has) {
				found = true;
				setColor = col;
				break;
			}
		}
		if(!found) {
			Colorf rnd;
			rnd.fromHSV(randomd(0, 360.0), randomd(0.5, 1.0), 1.0);
			setColor = Color(rnd);
		}
		setup.settings.color = setColor;
		setup.update();
	}

	void tick(double time) {
		if(mapIcons.length == 0) {
			mapIcons.length = mapCount;
			for(uint i = 0, cnt = mapCount; i < cnt; ++i) {
				auto@ mp = getMap(i);
				if(mp.isListed && !mp.isScenario && mp.icon.length != 0)
					mapIcons[i].load(mp.icon);
			}
		}
		inviteButton.visible = cloud::inLobby;
		addAIButton.disabled = empires.length >= 28;
		if(mpServer) {
			bool allReady = true;
			for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
				auto@ emp = empires[n];
				if(emp.playerId != -1 && emp.playerId != CURRENT_PLAYER.id) {
					emp.found = false;
					if(!emp.settings.ready)
						allReady = false;
				}
			}

			array<Player@>@ players = getPlayers();
			for(uint i = 0, cnt = players.length; i < cnt; ++i) {
				Player@ pl = players[i];
				if(pl == CURRENT_PLAYER)
					continue;

				//Find if we already have an empire
				bool found = false;
				for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
					auto@ emp = empires[n];
					if(emp.playerId == pl.id) {
						emp.found = true;
						found = true;
						if(pl.name.length != 0 && emp.name.text.length == 0)
							emp.name.text = pl.name;
					}
				}

				if(!found) {
					auto@ emp = addEmpire(false, getRacePreset(0));
					emp.name.text = pl.name;
					emp.address = pl.address;
					emp.setPlayer(pl.id);
				}
			}

			//Prune disconnected players
			for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
				auto@ emp = empires[n];
				if(emp.playerId != -1 && !emp.found) {
					removeEmpire(emp);
					--n; --ncnt;
				}
			}

			//Update play button
			if(allReady)
				playButton.color = colors::Green;
			else
				playButton.color = colors::Orange;
		}
		else if(fromMP) {
			if(game_running) {
				hideNewGame(true);
				switchToMenu(main_menu, snap=true);
				return;
			}
			if(awaitingGalaxy) {
				hideNewGame(true);
				switchToMenu(main_menu, snap=true);
				showMultiplayer();
				return;
			}

			auto@ pl = findPlayer(CURRENT_PLAYER.id);
			if(pl !is null && pl.settings.ready) {
				playButton.text = locale::MP_READY;
				playButton.color = colors::Green;
			}
			else {
				playButton.text = locale::MP_NOT_READY;
				playButton.color = colors::Orange;
			}

			if(!mpIsConnected()) {
				message("Lost connection to server:\n    "
						+localize("DISCONNECT_"+uint(mpDisconnectReason)));

				hideNewGame(true);
				switchToMenu(main_menu, snap=true);
				showMultiplayer();
			}
		}
	}

	EmpireSetup@ addEmpire(bool player = false, const RacePreset@ preset = null) {
		if(empires.length >= 28)
			return null;
		uint y = empires.length * (EMPIRE_SETUP_HEIGHT + 8) + 8;
		EmpireSetup@ emp = EmpireSetup(this,
			Alignment(Left+4, Top+y, Right-4, Top+y + EMPIRE_SETUP_HEIGHT),
			player);
		portraits.randomize(emp.settings);
		if(player && settings::sNickname.length != 0)
			emp.name.text = settings::sNickname;
		else
			emp.name.text = "Empire "+(nextEmpNum++);
		if(preset is null) {
			if(player)
				@preset = getRacePreset(0);
			else
				@preset = getUniquePreset();
		}
		emp.defaultName = emp.name.text;
		addAIButton.position = vec2i((empirePanel.size.width - addAIButton.size.width)/2, y + EMPIRE_SETUP_HEIGHT + 4);
		emp.update();
		empires.insertLast(emp);
		empirePanel.updateAbsolutePosition();
		if(preset !is null)
			emp.applyRace(preset);
		else if(!player)
			emp.resetName();
		if(!player)
			setUniqueColor(emp);
		return emp;
	}

	EmpireSetup@ findPlayer(int id) {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			if(empires[i].playerId == id)
				return empires[i];
		}
		return null;
	}

	void clearEmpires() {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i)
			empires[i].remove();
		empires.length = 0;
		nextEmpNum = 2;
		updateEmpirePositions();
	}

	void removeEmpire(EmpireSetup@ emp) {
		emp.remove();
		empires.remove(emp);
		updateEmpirePositions();
	}

	void updateEmpirePositions() {
		uint cnt = empires.length;
		for(uint i = 0; i < cnt; ++i) {
			EmpireSetup@ emp = empires[i];
			emp.alignment.top.pixels = i * (EMPIRE_SETUP_HEIGHT + 8) + 8;
			emp.alignment.bottom.pixels = emp.alignment.top.pixels + EMPIRE_SETUP_HEIGHT;
			emp.updateAbsolutePosition();
		}
		addAIButton.position = vec2i((empirePanel.size.width - addAIButton.size.width)/2, cnt * (EMPIRE_SETUP_HEIGHT + 8) + 6);
	}

	GalaxySetup@ addGalaxy(Map@ mp) {
		uint y = galaxies.length * (GALAXY_SETUP_HEIGHT + 8) + 8;
		GalaxySetup@ glx = GalaxySetup(this,
			Alignment(Left+8, Top+y, Right-8, Top+y + GALAXY_SETUP_HEIGHT),
			mp);

		if(mp.eatsPlayers) {
			for(uint i = 0, cnt = galaxies.length; i < cnt; ++i)
				galaxies[i].setHomeworlds(false);
		}
		else {
			bool haveEating = false;
			for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
				if(galaxies[i].mp.eatsPlayers) {
					haveEating = true;
				}
			}

			if(haveEating)
				glx.setHomeworlds(false);
		}

		addGalaxyButton.position = vec2i((galaxyPanel.size.width - addGalaxyButton.size.width)/2, y + GALAXY_SETUP_HEIGHT);
		galaxies.insertLast(glx);
		galaxyPanel.updateAbsolutePosition();
		updateGalaxyPositions();
		return glx;
	}

	void removeGalaxy(GalaxySetup@ glx) {
		glx.remove();
		galaxies.remove(glx);
		updateGalaxyPositions();

		if(glx.mp.eatsPlayers) {
			bool haveEating = false;
			for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
				if(galaxies[i].mp.eatsPlayers) {
					haveEating = true;
				}
			}

			if(!haveEating) {
				for(uint i = 0, cnt = galaxies.length; i < cnt; ++i) {
					galaxies[i].setHomeworlds(true);
				}
			}
		}

		if(galaxies.length == 0) {
			mapHeader.text = locale::CHOOSE_MAP;
			mapPanel.visible = true;
			galaxyPanel.visible = false;
			choosingMap = true;
			updateMapList();
		}
	}

	void updateGalaxyPositions() {
		uint cnt = galaxies.length;
		for(uint i = 0; i < cnt; ++i) {
			GalaxySetup@ glx = galaxies[i];
			glx.alignment.top.pixels = i * (GALAXY_SETUP_HEIGHT + 8) + 8;
			glx.alignment.bottom.pixels = glx.alignment.top.pixels + GALAXY_SETUP_HEIGHT;
			glx.updateAbsolutePosition();
		}
		addGalaxyButton.position = vec2i((galaxyPanel.size.width - addGalaxyButton.size.width)/2, cnt * (GALAXY_SETUP_HEIGHT + 8) + 6);
		galaxyPanel.updateAbsolutePosition();
	}

	void apply() {
		apply(settings);
	}

	void reset() {
		uint newCnt = settings.empires.length;
		uint oldCnt = empires.length;
		for(uint i = newCnt; i < oldCnt; ++i) {
			removeEmpire(empires[i]);
			--i; --oldCnt;
		}
		for(uint i = 0; i < newCnt; ++i) {
			EmpireSetup@ setup;
			if(i >= oldCnt)
				@setup = addEmpire();
			else
				@setup = empires[i];
			auto@ sett = settings.empires[i];
			if(setup.playerId == sett.playerId
					&& setup.playerId == CURRENT_PLAYER.id) {
				if(setup.settings.delta > sett.delta)
					setup.apply(settings.empires[i]);
				else
					setup.load(settings.empires[i]);
			}
			else {
				setup.load(settings.empires[i]);
			}
		}
		updateEmpirePositions();

		newCnt = settings.galaxies.length;
		oldCnt = galaxies.length;
		for(uint i = newCnt; i < oldCnt; ++i) {
			removeGalaxy(galaxies[i]);
			--i; --oldCnt;
		}
		for(uint i = 0; i < newCnt; ++i) {
			GalaxySetup@ setup;
			if(i >= oldCnt)
				@setup = addGalaxy(getMap(settings.galaxies[i].map_id));
			else
				@setup = galaxies[i];
			setup.load(settings.galaxies[i]);
		}
		updateGalaxyPositions();

		for(uint i = 0, cnt = GAME_SETTINGS_PAGES.length; i < cnt; ++i)
			GAME_SETTINGS_PAGES[i].load(settings);

		addGalaxyButton.visible = !mpClient;
		addAIButton.visible = !mpClient;
	}

	void reset(GameSettings& settings) {
		this.settings = settings;
		reset();
	}

	void apply(GameSettings& settings) {
		uint empCnt = empires.length;
		settings.empires.length = empCnt;
		for(uint i = 0; i < empCnt; ++i) {
			settings.empires[i].index = i;
			empires[i].apply(settings.empires[i]);
		}

		uint glxCnt = galaxies.length;
		settings.galaxies.length = glxCnt;
		for(uint i = 0; i < glxCnt; ++i)
			galaxies[i].apply(settings.galaxies[i]);

		for(uint i = 0, cnt = GAME_SETTINGS_PAGES.length; i < cnt; ++i)
			GAME_SETTINGS_PAGES[i].apply(settings);
	}

	void start(){
		apply();

		Message msg;
		settings.write(msg);

		startNewGame(msg);
	}

	void switchPage(uint page) {
		mapsButton.pressed = page == 0;
		galaxyPanel.visible = page == 0 && !choosingMap;
		mapPanel.visible = page == 0 && choosingMap;
		if(mapPanel.visible)
			updateMapList();
		//if(page == 0)
		//	gameHeader.color = Color(0xff003fff);
		resetButton.visible = page != 0 && !mpClient;

		for(uint i = 0, cnt = settingsButtons.length; i < cnt; ++i) {
			settingsButtons[i].pressed = page == i+1;
			settingsPanels[i].visible = page == i+1;
			//if(page == i+1)
			//	gameHeader.color = GAME_SETTINGS_PAGES[i].color;
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Clicked:
				if(event.caller is playButton) {
					if(fromMP) {
						auto@ pl = findPlayer(CURRENT_PLAYER.id);
						if(pl !is null) {
							pl.settings.ready = !pl.settings.ready;
							pl.submit();
						}
					}
					else {
						if(mpServer) {
							bool allReady = true;
							for(uint n = 0, ncnt = empires.length; n < ncnt; ++n) {
								auto@ emp = empires[n];
								if(emp.playerId != -1 && emp.playerId != CURRENT_PLAYER.id) {
									if(!emp.settings.ready)
										allReady = false;
								}
							}

							if(!allReady) {
								question(locale::MP_CONFIRM_NOT_READY, ConfirmStart());
								return true;
							}
						}
						else {
							uint sysCount = 0;
							apply();
							for(uint i = 0, cnt = settings.galaxies.length; i < cnt; ++i)
								sysCount += settings.galaxies[i].systemCount * settings.galaxies[i].galaxyCount;
							uint empCount = empires.length;
							if(sysCount > REC_MAX_OHGOD) {
								question(locale::NG_WARN_OHGOD, ConfirmStart());
								return true;
							}
							else if(sysCount > REC_MAX_BAD) {
								question(locale::NG_WARN_BAD, ConfirmStart());
								return true;
							}
							else if(sysCount > REC_MAX_OPTIMAL) {
								question(locale::NG_WARN_OPTIMAL, ConfirmStart());
								return true;
							}
							else if(sysCount > REC_MAX_PEREMP * empCount) {
								question(locale::NG_WARN_PEREMP, ConfirmStart());
								return true;
							}
						}
						start();
						hideNewGame(true);
					}
					return true;
				}
				else if(event.caller is backButton) {
					if(!game_running)
						mpDisconnect();
					hideNewGame();
					return true;
				}
				else if(event.caller is inviteButton) {
					cloud::inviteFriend();
					return true;
				}
				else if(event.caller is addAIButton) {
					addEmpire();
					return true;
				}
				else if(event.caller is addGalaxyButton) {
					mapHeader.text = locale::ADD_GALAXY;
					mapPanel.visible = true;
					galaxyPanel.visible = false;
					updateMapList();
					choosingMap = true;
					return true;
				}
				else if(event.caller is resetButton) {
					for(uint i = 0, cnt = GAME_SETTINGS_PAGES.length; i < cnt; ++i) {
						if(settingsPanels[i].visible)
							GAME_SETTINGS_PAGES[i].reset();
					}
					return true;
				}
				else if(event.caller is mapsButton) {
					switchPage(0);
					return true;
				}
				else {
					for(uint i = 0, cnt = settingsButtons.length; i < cnt; ++i) {
						if(event.caller is settingsButtons[i]) {
							switchPage(i+1);
							return true;
						}
					}
				}
			break;
			case GUI_Confirmed:
				if(event.caller is chatBox) {
					string message = chatBox.text;
					if(message.length != 0)
						menuChat(message);
					chatBox.text = "";
				}
			break;
			case GUI_Changed:
				if(event.caller is mapList) {
					if(mapList.selected != -1)
						addGalaxy(cast<MapElement>(mapList.selectedItem).mp);
					if(galaxies.length != 0) {
						mapList.clearSelection();
						mapPanel.visible = false;
						galaxyPanel.visible = true;
						choosingMap = false;
					}
					return true;
				}
			break;
			case GUI_Animation_Complete:
				animating = false;
				return true;
		}

		return BaseGuiElement::onGuiEvent(event);
	}

	void updateAbsolutePosition() {
		if(!animating) {
			if(!hide) {
				size = parent.size;
				position = vec2i(0, 0);
			}
			else {
				size = parent.size;
				position = vec2i(size.x, 0);
			}
		}
		if(fromMP || mpServer) {
			chatBG.visible = true;
			chatLog.size = vec2i(chatPanel.size.width-20, chatLog.size.height);
			empireBG.alignment.bottom.pixels = 262;
		}
		else {
			chatBG.visible = false;
			empireBG.alignment.bottom.pixels = 0;
		}
		addAIButton.position = vec2i((empirePanel.size.width - addAIButton.size.width)/2, addAIButton.position.y);
		addGalaxyButton.position = vec2i((galaxyPanel.size.width - addGalaxyButton.size.width)/2, addGalaxyButton.position.y);
		BaseGuiElement::updateAbsolutePosition();
	}

	void animateIn() {
		animating = true;
		hide = false;

		rect = recti_area(vec2i(parent.size.x, 0), parent.size);
		animate_time(this, recti_area(vec2i(), parent.size), MSLIDE_TIME);
	}

	void animateOut() {
		animating = true;
		hide = true;

		rect = recti_area(vec2i(), parent.size);
		animate_time(this, recti_area(vec2i(parent.size.x, 0), parent.size), MSLIDE_TIME);
	}
};

void drawRace(const Skin@ skin, const recti& absPos, const string& name,
		const string& portrait, const array<const Trait@>@ traits = null, bool showTraits = true) {
	const Font@ normal = skin.getFont(FT_Normal);
	const Font@ bold = skin.getFont(FT_Bold);
	recti namePos = recti_area(absPos.topLeft + vec2i(8, 0), vec2i(absPos.width * 0.35, absPos.height));

	//Portrait
	auto@ prt = getEmpirePortrait(portrait);
	if(prt !is null) {
		prt.portrait.draw(recti_area(absPos.topLeft + vec2i(8, 0), vec2i(absPos.height, absPos.height)));
		namePos.topLeft.x += absPos.height+8;
	}

	//Race name
	bold.draw(pos=namePos, text=name);

	//FTL Method
	recti ftlPos = recti_area(absPos.topLeft + vec2i(absPos.width*0.35 + 16, 0),
			vec2i(absPos.width * 0.35, absPos.height));

	//Traits
	if(traits !is null) {
		recti pos = recti_area(vec2i(absPos.botRight.x - 32, absPos.topLeft.y + 3), vec2i(24, 24));
		for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
			auto@ trait = traits[i];
			if(trait.unique == "FTL") {
				trait.icon.draw(recti_area(ftlPos.topLeft, vec2i(absPos.height, absPos.height)).aspectAligned(trait.icon.aspect));
				ftlPos.topLeft.x += absPos.height+8;
				normal.draw(text=trait.name, pos=ftlPos);
			}
			else if(showTraits) {
				traits[i].icon.draw(pos.aspectAligned(traits[i].icon.aspect));
				pos -= vec2i(24, 0);
			}
		}
	}
}

Color colorFromNumber(int num) {
	float hue = (num*26534371)%360;
	Colorf col;
	col.fromHSV(hue, 1.f, 1.f);
	return Color(col);
}

class RaceElement : GuiListElement {
	const RacePreset@ preset;

	RaceElement(const RacePreset@ preset) {
		@this.preset = preset;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		drawRace(ele.skin, absPos, preset.name, preset.portrait, preset.traits);
	}
};

class CustomRaceElement : GuiListElement {
	const EmpireSettings@ settings;

	CustomRaceElement(const EmpireSettings@ settings) {
		@this.settings = settings;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		drawRace(ele.skin, absPos, settings.raceName, settings.portrait, settings.traits);
	}
};

class CurrentRaceElement : GuiListElement {
	EmpireSettings@ settings;
	bool valid = true;

	CurrentRaceElement(EmpireSettings@ settings) {
		@this.settings = settings;
	}

	void update() {
		valid = settings.getTraitPoints() >= 0 && !settings.hasTraitConflicts();
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		if(!valid) {
			Color color(0xff0000ff);
			color.a = abs((frameTime % 1.0) - 0.5) * 2.0 * 255.0;
			ele.skin.draw(SS_Button, SF_Normal, absPos.padded(-5, -3), color);
		}
		drawRace(ele.skin, absPos, settings.raceName, settings.portrait, traits=settings.traits, showTraits=false);
	}
};

class CustomizeOption : GuiListElement {
	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		const Font@ bold = ele.skin.getFont(FT_Bold);

		recti namePos = recti_area(absPos.topLeft + vec2i(8, 0), vec2i(absPos.width * 0.95, absPos.height));
		icons::Customize.draw(recti_area(absPos.topLeft + vec2i(8, 0), vec2i(absPos.height, absPos.height)));
		namePos.topLeft.x += absPos.height+8;

		bold.draw(pos=namePos, text=locale::CUSTOMIZE_RACE, color=Color(0xff8000ff));
	}
};

class TraitList : GuiIconGrid {
	array<const Trait@> traits;

	TraitList(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		MarkupTooltip tt(350, 0.f, true, true);
		tt.Lazy = true;
		tt.LazyUpdate = false;
		tt.Padding = 4;
		@tooltipObject = tt;
	}

	uint get_length() override {
		return traits.length;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";

		auto@ trait = traits[hovered];
		return format("[color=$1][b]$2[/b][/color]\n$3",
			toString(trait.color), trait.name, trait.description);
	}

	void drawElement(uint i, const recti& pos) override {
		traits[i].icon.draw(pos.aspectAligned(traits[i].icon.aspect));
	}
};

class ChangeWelfare : GuiContextOption {
	ChangeWelfare(const string& text, uint index) {
		value = int(index);
		this.text = text;
		icon = Sprite(spritesheet::ConvertIcon, index);
	}

	void call(GuiContextMenu@ menu) override {
		playerEmpire.WelfareMode = uint(value);
	}
};

const Sprite[] DIFF_SPRITES = {
	Sprite(material::HappyFace),
	Sprite(material::StatusPeace),
	Sprite(material::StatusWar),
	Sprite(material::StatusCeaseFire),
	Sprite(spritesheet::AttributeIcons, 3),
	Sprite(spritesheet::AttributeIcons, 0),
	Sprite(spritesheet::VoteIcons, 3),
	Sprite(spritesheet::VoteIcons, 3, colors::Red)
};

const Color[] DIFF_COLORS = {
	colors::Green,
	colors::White,
	colors::White,
	colors::White,
	colors::Orange,
	colors::Red,
	colors::Red,
	colors::Red
};

const string[] DIFF_TOOLTIPS = {
	locale::DIFF_PASSIVE,
	locale::DIFF_EASY,
	locale::DIFF_NORMAL,
	locale::DIFF_HARD,
	locale::DIFF_MURDEROUS,
	locale::DIFF_CHEATING,
	locale::DIFF_SAVAGE,
	locale::DIFF_BARBARIC,
};

class ChangeDifficulty : GuiMarkupContextOption {
	int level;
	EmpireSetup@ setup;

	ChangeDifficulty(EmpireSetup@ setup, int value, const string& text) {
		level = value;
		set(text);
		@this.setup = setup;
	}

	void call(GuiContextMenu@ menu) override {
		setup.settings.difficulty = level;
		setup.update();
	}
};

class ChangeTeam : GuiMarkupContextOption {
	int team;
	EmpireSetup@ setup;

	ChangeTeam(EmpireSetup@ setup, int value) {
		team = value;
		if(value >= 0)
			set(format("[b][color=$2]$1[/color][/b]", format(locale::TEAM_TEXT, toString(value)),
						toString(colorFromNumber(value))));
		else
			set(format("[b][color=#aaa]$1...[/color][/b]", locale::NO_TEAM));
		@this.setup = setup;
	}

	void call(GuiContextMenu@ menu) override {
		setup.settings.team = team;
		setup.submit();
	}
};

class Chooser : GuiIconGrid {
	Color spriteColor;
	array<Color> colors;
	array<Sprite> sprites;

	uint selected = 0;

	Chooser(IGuiElement@ parent, Alignment@ align, const vec2i& itemSize) {
		super(parent, align);
		horizAlign = 0.5;
		vertAlign = 0.0;
		iconSize = itemSize;
		updateAbsolutePosition();
	}

	void add(const Color& col) {
		colors.insertLast(col);
	}

	void add(const Sprite& sprt) {
		sprites.insertLast(sprt);
	}

	uint get_length() override {
		return max(colors.length, sprites.length);
	}

	void drawElement(uint index, const recti& pos) override {
		if(uint(selected) == index)
			drawRectangle(pos, Color(0xffffff30));
		if(uint(hovered) == index)
			drawRectangle(pos, Color(0xffffff30));
		if(index < colors.length)
			drawRectangle(pos.padded(5), colors[index]);
		if(index < sprites.length)
			sprites[index].draw(pos, spriteColor);
	}
};

class RaceChooser : GuiOverlay {
	EmpireSetup@ setup;
	GuiSkinElement@ panel;

	GuiText@ header;
	GuiPanel@ list;

	const RacePreset@ selectedRace;
	array<GuiButton@> presetButtons;
	array<const RacePreset@> racePresets;

	GuiSprite@ portrait;
	GuiSprite@ flag;
	GuiSprite@ bgDisplay;

	GuiPanel@ descScroll;
	GuiMarkupText@ description;

	GuiPanel@ loreScroll;
	GuiMarkupText@ lore;

	GuiButton@ playButton;
	GuiButton@ customizeButton;
	GuiButton@ loadButton;
	GuiButton@ backButton;
	bool isInitial;
	bool hasChosenRace = false;
	bool chosenShipset = false;

	Chooser@ flags;
	Chooser@ colors;
	ShipsetChooser@ shipsets;

	RaceChooser(EmpireSetup@ setup, bool isInitial = false) {
		@this.setup = setup;
		this.isInitial = isInitial;
		super(null);
		closeSelf = false;

		@panel = GuiSkinElement(this, Alignment(Left-4, Top+0.05f, Right+4, Bottom-0.05f), SS_Panel);

		@customizeButton = GuiButton(panel, Alignment(Right-232, Bottom-78, Width=220, Height=33));
		customizeButton.text = locale::CUSTOMIZE_RACE;
		customizeButton.setIcon(icons::Edit);

		@loadButton = GuiButton(panel, Alignment(Right-232, Bottom-78+33, Width=220, Height=33));
		loadButton.text = locale::LOAD_CUSTOM_RACE;
		loadButton.setIcon(icons::Load);

		int w = 250, h = 140;
		int off = max((size.width - (getRacePresetCount() * w)) / 2 - 20, 0);

		GuiSkinElement listBG(panel, Alignment(Left-4, Top+12, Right+4, Top+154), SS_PlainBox);

		@list = GuiPanel(panel, Alignment(Left+off, Top+12, Right-off, Top+174));
		updateAbsolutePosition();

		vec2i pos;
		uint curSelection = 0;
		for(uint i = 0, cnt = getRacePresetCount(); i < cnt; ++i) {
			auto@ preset = getRacePreset(i);
			if(preset.dlc.length != 0 && !hasDLC(preset.dlc))
				continue;

			racePresets.insertLast(preset);

			GuiButton btn(list, recti_area(pos.x, pos.y, w, h));
			btn.toggleButton = true;
			btn.style = SS_GlowButton;
			btn.pressed = i == 0;

			GuiSprite icon(btn, recti_area(2, 2, w*0.75, h-4));
			icon.horizAlign = 0.0;
			icon.vertAlign = 1.0;
			icon.desc = getSprite(preset.portrait);

			GuiText name(btn, recti_area(0, 0, w-4, h));
			name.font = FT_Big;
			name.stroke = colors::Black;
			name.text = preset.name;
			name.vertAlign = 0.4;
			name.horizAlign = 0.9;

			GuiSkinElement tagbar(btn, recti_area(1, h-28, w-3, 24), SS_PlainBox);
			tagbar.color = Color(0xffffff80);

			GuiText tagline(btn, recti_area(0, h-30, w-4, 24));
			tagline.font = FT_Italic;
			tagline.stroke = colors::Black;
			tagline.color = Color(0xaaaaaaff);
			tagline.text = preset.tagline;
			tagline.horizAlign = 1.0;

			TraitList traits(btn, Alignment(Left, Bottom-56, Right, Bottom-28));
			traits.iconSize = vec2i(24, 24);
			traits.horizAlign = 1.0;
			traits.fallThrough = true;
			traits.traits = preset.traits;

			if(preset.equals(setup.settings)) {
				curSelection = i;
				hasChosenRace = true;
			}

			if(!setup.player && !preset.aiSupport) {
				icon.saturation = 0.f;
				traits.visible = false;
				btn.disabled = true;
				btn.color = Color(0xffffffaa);
				name.color = Color(0xaa3030ff);

				setMarkupTooltip(btn, locale::AI_CANNOT_PLAY);
			}

			presetButtons.insertLast(btn);
			pos.x += w;
		}


		BaseGuiElement leftBG(panel, Alignment(Left+12, Top+174, Left+0.33f-6, Bottom-90));
		int y = 0;

		GuiSkinElement portBG(leftBG, Alignment(Left, Top+y, Right, Bottom), SS_PlainBox);

		@bgDisplay = GuiSprite(portBG, Alignment().padded(2), Sprite(getEmpireColor(setup.settings.color).background));
		bgDisplay.color = Color(0xffffff80);
		bgDisplay.stretchOutside = true;

		@portrait = GuiSprite(portBG, Alignment(Left+2, Top, Right-2, Height=232));
		portrait.horizAlign = 0.0;
		portrait.vertAlign = 1.0;

		@flag = GuiSprite(portBG, Alignment(Right-164, Top+4, Width=160, Height=160));
		flag.horizAlign = 1.0;
		flag.vertAlign = 0.0;
		flag.color = setup.settings.color;
		flag.color.a = 0xc0;
		flag.desc = getSprite(setup.settings.flag);

		y += 220 + 12;
		GuiSkinElement colBG(leftBG, Alignment(Left, Top+y, Right, Height=34), SS_PlainBox);
		@colors = Chooser(colBG, Alignment().padded(8, 0), vec2i(48, 32));
		for(uint i = 0, cnt = getEmpireColorCount(); i < cnt; ++i) {
			Color color = getEmpireColor(i).color;
			colors.add(color);
			if(color.color == setup.settings.color.color)
				colors.selected = i;
		}
		updateAbsolutePosition();

		y += 34 + 12;
		GuiSkinElement flagBG(leftBG, Alignment(Left, Top+y, Right, Height=110), SS_PlainBox);
		@flags = Chooser(flagBG, Alignment().padded(8, 0), vec2i(48, 48));
		flags.spriteColor = setup.settings.color;
		for(uint i = 0, cnt = getEmpireFlagCount(); i < cnt; ++i) {
			string flag = getSpriteDesc(Sprite(getEmpireFlag(i).flag));
			flags.add(getSprite(flag));
			if(flag == setup.settings.flag)
				flags.selected = i;
		}
		
		y += 110 + 12;
		GuiSkinElement shipsetBG(leftBG, Alignment(Left, Top+y, Right, Height=150), SS_PlainBox);
		@shipsets = ShipsetChooser(shipsetBG, Alignment().padded(8, 0), vec2i(160, 70));
		shipsets.selectedColor = setup.settings.color;
		shipsets.selected = 0;
		shipsets.horizAlign = 0.0;
		for(uint i = 0, cnt = getShipsetCount(); i < cnt; ++i) {
			auto@ ss = getShipset(i);
			if(ss.available && (ss.dlc.length == 0 || hasDLC(ss.dlc)))
				shipsets.add(ss);
			if(ss.ident == setup.settings.shipset)
				shipsets.selected = shipsets.length-1;
		}

		GuiSkinElement loreBox(panel, Alignment(Left+0.33f+6, Top+174, Left+0.66f-6, Bottom-90), SS_PlainBox);
		@loreScroll = GuiPanel(loreBox, Alignment().fill());
		@lore = GuiMarkupText(loreScroll, recti_area(12, 12, 376, 100));
		lore.fitWidth = true;

		GuiSkinElement descBox(panel, Alignment(Left+0.66f+6, Top+174, Right-12, Bottom-90), SS_PlainBox);
		@descScroll = GuiPanel(descBox, Alignment().fill());
		@description = GuiMarkupText(descScroll, recti_area(12, 12, 376, 100));
		description.fitWidth = true;

		@playButton = GuiButton(panel, Alignment(Left+0.5f-150, Bottom-78, Left+0.5f+150, Bottom-12));
		playButton.font = FT_Medium;
		playButton.color = Color(0x00c0ffff);

		@backButton = GuiButton(panel, Alignment(Left+12, Bottom-78, Left+220, Bottom-12), locale::BACK);
		backButton.font = FT_Medium;
		backButton.buttonIcon = icons::Back;

		selectRace(curSelection);
		updateAbsolutePosition();
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		if(shipsets !is null && shipsets.parent !is null)
			shipsets.parent.visible = screenSize.height >= 900;
		BaseGuiElement::updateAbsolutePosition();
	}

	void close() override {
		if(isInitial)
			return;
		GuiOverlay::close();
	}

	void selectRace(uint select) {
		for(uint i = 0, cnt = presetButtons.length; i < cnt; ++i)
			presetButtons[i].pressed = i == select;

		auto@ preset = racePresets[select];

		string desc;
		if(preset.isHard)
			desc += format("[font=Subtitle][color=#ffc000]$1[/color][/font]", locale::RACE_IS_HARD);
		for(uint i = 0, cnt = preset.traits.length; i < cnt; ++i) {
			if(desc.length != 0)
				desc += "\n\n";
			desc += format("[font=Medium]$1[/font][vspace=4/]\n[offset=20]", preset.traits[i].name);
			desc += preset.traits[i].description;
			desc += "[/offset]";
		}
		description.text = desc;

		string txt = format("[font=Big]$1[/font]\n", preset.name);
		txt += format("[right][font=Medium][color=#aaa]$1[/color][/font][/right]\n\n", preset.tagline);
		txt += preset.lore;
		lore.text = txt;

		if(isInitial)
			playButton.text = format(locale::PLAY_AS_RACE, preset.name);
		else
			playButton.text = format(locale::CHOOSE_A_RACE, preset.name);
		playButton.buttonIcon = getSprite(preset.portrait);

		portrait.desc = getSprite(preset.portrait);

		loreScroll.updateAbsolutePosition();
		descScroll.updateAbsolutePosition();
		@selectedRace = preset;

		if(!chosenShipset) {
			setup.settings.shipset = preset.shipset;
			for(uint i = 0, cnt = shipsets.length; i < cnt; ++i) {
				if(shipsets.items[i].ident == preset.shipset) {
					shipsets.selected = i;
					break;
				}
			}
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is flags) {
				uint sel = flags.hovered;
				if(sel != uint(-1)) {
					string sprt = getSpriteDesc(Sprite(getEmpireFlag(sel).flag));
					setup.settings.flag = sprt;
					flag.desc = getSprite(sprt);
					flags.selected = sel;
				}
				return true;
			}
			else if(evt.caller is colors) {
				uint sel = colors.hovered;
				if(sel != uint(-1)) {
					auto empCol = getEmpireColor(sel);
					Color col = empCol.color;
					setup.settings.color = col;
					bgDisplay.desc = Sprite(empCol.background);
					flag.color = col;
					flag.color.a = 0xc0;
					flags.spriteColor = col;
					shipsets.selectedColor = col;
					colors.selected = sel;
				}
				return true;
			}
			else if(evt.caller is shipsets) {
				uint sel = shipsets.hovered;
				if(sel != uint(-1)) {
					chosenShipset = true;
					setup.settings.shipset = shipsets.items[sel].ident;
					shipsets.selected = sel;
				}
				return true;
			}
			else if(evt.caller is customizeButton) {
				isInitial = false;
				if(hasChosenRace) {
					setup.applyRace(selectedRace);
					setup.submit();
				}
				setup.openRaceWindow();
				close();
				return true;
			}
			else if(evt.caller is backButton) {
				if(isInitial) {
					isInitial = false;
					new_game.backButton.emitClicked();
					close();
					return true;
				}
				close();
				return true;
			}
			else if(evt.caller is loadButton) {
				isInitial = false;
				LoadRaceDialog(null, setup.settings, setup);
				close();
				return true;
			}
			else if(evt.caller is playButton) {
				setup.applyRace(selectedRace);
				setup.submit();
				if(isInitial) {
					isInitial = false;
					setup.resetName();
					setup.ng.resetAIColors();
					setup.ng.resetAIRaces();
				}
				close();
				return true;
			}
			else {
				for(uint i = 0, cnt = presetButtons.length; i < cnt; ++i) {
					if(evt.caller.isChildOf(presetButtons[i])) {
						hasChosenRace = true;
						selectRace(i);
						return true;
					}
				}
			}
		}
		return GuiOverlay::onGuiEvent(evt);
	}
};

class EmpireSetup : BaseGuiElement, IGuiCallback {
	GuiButton@ portraitButton;
	GuiEmpire@ portrait;
	EmpireSettings settings;

	NewGame@ ng;
	GuiTextbox@ name;
	GuiButton@ removeButton;
	GuiText@ handicapLabel;
	GuiSpinbox@ handicap;
	GuiButton@ raceBox;
	GameAddress address;
	GuiButton@ colorButton;
	GuiButton@ flagButton;
	GuiButton@ difficulty;
	GuiButton@ aiSettings;
	GuiSprite@ aiIcon;
	GuiText@ aiText;
	GuiButton@ teamButton;
	GuiText@ raceName;
	GuiSprite@ raceFTLIcon;
	GuiText@ raceFTL;
	TraitList@ traitList;
	bool player;
	bool found = true;
	int playerId = -1;
	ChoosePopup@ popup;
	GuiSprite@ readyness;
	string defaultName;

	EmpireSetup(NewGame@ menu, Alignment@ align, bool Player = false) {
		super(menu.empirePanel, align);
		
		@portraitButton = GuiButton(this, Alignment(Left+8, Top+4, Left+EMPIRE_SETUP_HEIGHT, Bottom-4));
		portraitButton.style = SS_NULL;
		@portrait = GuiEmpire(portraitButton, Alignment().fill());
		@portrait.settings = settings;

		@ng = menu;
		@name = GuiTextbox(this, Alignment(Left+EMPIRE_SETUP_HEIGHT+8, Top+14, Right-310, Top+0.5f-4));
		name.font = FT_Subtitle;
		name.style = SS_HoverTextbox;
		name.selectionColor = Color(0xffffff40);

		@colorButton = GuiButton(this, Alignment(Right-302, Top+14, Width=50, Height=30));
		colorButton.style = SS_HoverButton;

		@flagButton = GuiButton(this, Alignment(Right-244, Top+14, Width=50, Height=30));
		flagButton.style = SS_HoverButton;

		@teamButton = GuiButton(this, Alignment(Right-186, Top+14, Width=50, Height=30));
		teamButton.style = SS_HoverButton;

		@difficulty = GuiButton(this, Alignment(Right-128, Top+14, Width=50, Height=30));
		difficulty.style = SS_HoverButton;
		difficulty.visible = false;

		@aiSettings = GuiButton(this, Alignment(Right-128, Top+10, Width=66, Height=38));
		aiSettings.style = SS_HoverButton;
		aiSettings.visible = false;

		@aiIcon = GuiSprite(aiSettings, Alignment().padded(1, 1, 1, 5));
		@aiText = GuiText(aiSettings, Alignment());
		aiText.horizAlign = 0.5;
		aiText.vertAlign = 0.2;
		aiText.font = FT_Small;
		aiText.stroke = colors::Black;

		@raceBox = GuiButton(this, Alignment(Left+EMPIRE_SETUP_HEIGHT+8, Top+0.5f+4, Right-8, Bottom-14));
		raceBox.style = SS_HoverButton;

		@raceName = GuiText(raceBox, Alignment(Left+8, Top, Left+0.35f, Bottom));
		raceName.font = FT_Bold;

		@raceFTLIcon = GuiSprite(raceBox, Alignment(Left+0.4f, Top, Left+0.4f+22, Bottom));
		@raceFTL = GuiText(raceBox, Alignment(Left+0.4f+26, Top, Right-0.3f, Bottom));

		@traitList = TraitList(raceBox, Alignment(Right-0.3f, Top+2, Right-30, Bottom));
		traitList.iconSize = vec2i(24, 24);
		traitList.horizAlign = 1.0;
		traitList.fallThrough = true;

		player = Player;
		@removeButton = GuiButton(this,
			Alignment(Right-50, Top, Right, Top+30));
		removeButton.color = colors::Red;
		removeButton.setIcon(icons::Remove);
		if(!player) {
			removeButton.visible = true;
			aiSettings.visible = true;
		}
		else {
			removeButton.visible = false;
			playerId = 1;
		}

		@readyness = GuiSprite(portrait, Alignment(Right-40, Bottom-40, Right, Bottom));
		readyness.visible = false;

		applyRace(getRacePreset(randomi(0, getRacePresetCount()-1)));
		updateAbsolutePosition();
	}

	void showDifficulties() {
		GuiContextMenu menu(mousePos);
		menu.itemHeight = 54;
		menu.addOption(ChangeDifficulty(this, 0, locale::DIFF_PASSIVE));
		menu.addOption(ChangeDifficulty(this, 1, locale::DIFF_EASY));
		menu.addOption(ChangeDifficulty(this, 2, locale::DIFF_NORMAL));
		menu.addOption(ChangeDifficulty(this, 3, locale::DIFF_HARD));
		menu.addOption(ChangeDifficulty(this, 4, locale::DIFF_MURDEROUS));
		menu.addOption(ChangeDifficulty(this, 5, locale::DIFF_CHEATING));
		menu.addOption(ChangeDifficulty(this, 6, locale::DIFF_SAVAGE));
		menu.addOption(ChangeDifficulty(this, 7, locale::DIFF_BARBARIC));

		menu.updateAbsolutePosition();
	}

	void showAISettings() {
		AIPopup popup(aiSettings, this);
		aiSettings.Hovered = false;
		aiSettings.Pressed = false;
	}

	void showTeams() {
		GuiContextMenu menu(mousePos);
		menu.itemHeight = 30;

		//Figure out how many distinct teams we have
		uint distinctTeams = 0;
		uint teamMask = 0;
		int maxTeam = 0;
		for(uint i = 0, cnt = ng.empires.length; i < cnt; ++i) {
			int team = ng.empires[i].settings.team;
			if(team < 0)
				continue;

			maxTeam = max(maxTeam, team);
			uint mask = 1<<(team-1);
			if(mask & teamMask == 0) {
				teamMask |= mask;
				++distinctTeams;
			}
		}

		//Add more teams than we currently have
		menu.addOption(ChangeTeam(this, -1));
		for(uint i = 1; i <= min(max(distinctTeams+5, maxTeam+1), 30); ++i)
			menu.addOption(ChangeTeam(this, i));

		menu.updateAbsolutePosition();
	}
	
	void forceAITraits(EmpireSettings& settings) {
		for(uint i = 0, cnt = settings.traits.length; i < cnt; ++i) {
			auto@ trait = settings.traits[i];
			if(!trait.aiSupport) {
				if(trait.unique.length == 0) {
					settings.traits.removeAt(i);
					--cnt; --i;
				}
				else {
					const Trait@ repl;
					uint replCount = 0;
					for(uint n = 0, ncnt = getTraitCount(); n < ncnt; ++n) {
						auto@ other = getTrait(n);
						if(other.unique == trait.unique && other.aiSupport && other.hasDLC) {
							replCount += 1;
							if(randomd() < 1.0 / double(replCount))
								@repl = other;
						}
					}

					if(repl !is null) {
						@settings.traits[i] = repl;
					}
					else {
						settings.traits.removeAt(i);
						--cnt; --i;
					}
				}
			}
		}
	}

	void applyRace(const RacePreset@ preset) {
		preset.apply(settings);
		if(!player) {
			forceAITraits(settings);
			if(defaultName == name.text)
				resetName();
		}
		update();
	}

	void applyRace(const EmpireSettings@ custom) {
		settings.copyRaceFrom(custom);
		if(!player) {
			forceAITraits(settings);
			if(defaultName == name.text)
				resetName();
		}
	}

	void resetName() {
		string race = settings.raceName;
		if(race.startswith_nocase("the "))
			race = race.substr(4);
		name.text = format(localize(empireNames.generate()), race);
		defaultName = name.text;
	}

	void setPlayer(int id) {
		player = id != -1;
		playerId = id;
		name.disabled = player || !mpClient;
		removeButton.visible = !mpClient && (!player || id != CURRENT_PLAYER.id);
		aiSettings.visible = !player;
		readyness.visible = player && id != 1;

		bool editable = id == CURRENT_PLAYER.id || (!mpClient && id == -1);
		raceBox.disabled = !editable;
		colorButton.disabled = !editable;
		flagButton.disabled = !editable;
		teamButton.disabled = !editable;
		aiSettings.disabled = !editable;
	}

	void openRaceWindow() {
		TraitsWindow win(this);
	}

	void update() {
		updateTraits();

		if(difficulty.visible) {
			difficulty.color = DIFF_COLORS[settings.difficulty];
			setMarkupTooltip(difficulty, locale::TT_DIFF+"\n"+DIFF_TOOLTIPS[settings.difficulty], width=300);
			if(difficulty.color.color != colors::White.color)
				difficulty.style = SS_Button;
			else
				difficulty.style = SS_HoverButton;
		}

		if(aiSettings.visible) {
			aiIcon.desc = QDIFF_ICONS[clamp(settings.difficulty, 0, 2)];
			aiText.color = QDIFF_COLORS[clamp(settings.difficulty, 0, 2)];
			aiText.text = getAIName(settings);
		}

		name.textColor = settings.color;
		raceName.text = settings.raceName;
		for(uint i = 0, cnt = settings.traits.length; i < cnt; ++i) {
			auto@ trait = settings.traits[i];
			if(trait.unique == "FTL") {
				raceFTLIcon.desc = trait.icon;
				raceFTL.text = trait.name;
			}
		}
	}

	void updateTraits() {
		traitList.traits.length = 0;
		for(uint i = 0, cnt = getTraitCount(); i < cnt; ++i) {
			auto@ trait = getTrait(i);
			if(settings.hasTrait(trait) && trait.unique != "FTL")
				traitList.traits.insertLast(trait);
		}
		if(settings.ready) {
			readyness.tooltip = locale::MP_PLAYER_READY;
			readyness.desc = icons::Ready;
		}
		else {
			readyness.tooltip = locale::MP_PLAYER_NOT_READY;
			readyness.desc = icons::NotReady;
		}
	}

	void submit() {
		if(mpClient)
			changeEmpireSettings(settings);
		if(!player)
			forceAITraits(settings);
		settings.delta += 1;
		update();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is removeButton) {
					if(player)
						mpKick(playerId);
					else
						ng.removeEmpire(this);
					return true;
				}
				else if(evt.caller is difficulty) {
					showDifficulties();
					return true;
				}
				else if(evt.caller is aiSettings) {
					showAISettings();
					return true;
				}
				else if(evt.caller is teamButton) {
					showTeams();
					return true;
				}
				else if(evt.caller is raceBox || evt.caller is portraitButton) {
					RaceChooser(this);
					raceBox.Hovered = false;
					return true;
				}
				else if(evt.caller is colorButton) {
					vec2i pos(evt.caller.absolutePosition.topLeft.x,
							evt.caller.absolutePosition.botRight.y);
					uint cnt = getEmpireColorCount();
					vec2i size(220, ceil(double(cnt)/4.0) * 38.0);
					@popup = ChoosePopup(pos, size, vec2i(48, 32));
					@popup.callback = this;
					popup.extraHeight = 60;
					ColorPicker picker(popup.overlay, recti_area(pos+vec2i(20,size.y+2), vec2i(size.x-40, 50)));
					@picker.callback = this;
					for(uint i = 0; i < cnt; ++i)
						popup.add(getEmpireColor(i).color);
					return true;
				}
				else if(evt.caller is flagButton) {
					vec2i pos(evt.caller.absolutePosition.topLeft.x,
							evt.caller.absolutePosition.botRight.y);
					uint cnt = getEmpireFlagCount();
					vec2i size(220, ceil(double(cnt)/4.0) * 52.0);
					@popup = ChoosePopup(pos, size, vec2i(48, 48));
					@popup.callback = this;
					popup.spriteColor = settings.color;
					for(uint i = 0; i < cnt; ++i)
						popup.add(Sprite(getEmpireFlag(i).flag));
					return true;
				}
				else if(evt.caller is popup) {

				}
			break;
			case GUI_Confirmed:
				if(evt.caller is popup) {
					if(popup.colors.length > 0)
						settings.color = getEmpireColor(evt.value).color;
					else if(popup.sprites.length > 0)
						settings.flag = getEmpireFlag(evt.value).flagDef;
					@popup = null;
					submit();
					return true;
				}
				if(cast<ColorPicker>(evt.caller) !is null) {
					settings.color = cast<ColorPicker>(evt.caller).picked;
					popup.remove();
					@popup = null;
					submit();
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void apply(EmpireSettings& es) {
		es = settings;
		es.name = name.text;
		es.playerId = playerId;

		if(player || playerId != -1)
			es.type = ET_Player;
		else if(es.type == ET_Player)
			es.type = ET_WeaselAI;
	}

	void load(EmpireSettings& es) {
		name.text = es.name;
		player = es.type == uint(ET_Player);
		setPlayer(es.playerId);
		settings = es;
		update();
	}

	void draw() {
		Color color = settings.color;

		skin.draw(SS_EmpireSetupItem, SF_Normal, AbsolutePosition.padded(-10, 0), color);
		BaseGuiElement::draw();

		if(colorButton.visible) {
			setClip(colorButton.absoluteClipRect);
			drawRectangle(colorButton.absolutePosition.padded(6), color);
		}

		auto@ flag = getEmpireFlag(settings.flag);
		if(flag !is null && flagButton.visible) {
			setClip(flagButton.absoluteClipRect);
			flag.flag.draw(recti_centered(flagButton.absolutePosition,
						vec2i(flagButton.size.height, flagButton.size.height)),
					color);
		}

		if(difficulty.visible) {
			setClip(difficulty.absoluteClipRect);
			DIFF_SPRITES[settings.difficulty].draw(recti_centered(difficulty.absolutePosition,
						vec2i(difficulty.size.height, difficulty.size.height)));
		}

		if(teamButton.visible) {
			setClip(teamButton.absoluteClipRect);
			if(settings.team >= 0) {
				material::TabDiplomacy.draw(recti_centered(teamButton.absolutePosition,
							vec2i(teamButton.size.height, teamButton.size.height)));
				skin.getFont(FT_Small).draw(
					pos=teamButton.absolutePosition,
					text=locale::TEAM,
					horizAlign=0.5, vertAlign=0.0,
					stroke=colors::Black,
					color=colors::White);
				skin.getFont(FT_Medium).draw(
					pos=teamButton.absolutePosition,
					text=toString(settings.team),
					horizAlign=0.5, vertAlign=1.0,
					stroke=colors::Black,
					color=colorFromNumber(settings.team));
			}
			else {
				shader::SATURATION_LEVEL = 0.f;
				material::TabDiplomacy.draw(recti_centered(teamButton.absolutePosition,
							vec2i(teamButton.size.height, teamButton.size.height)),
						Color(0xffffff80), shader::Desaturate);
			}
		}
	}
};

string getAIName(EmpireSettings& settings) {
	string text;
	text = QDIFF_NAMES[clamp(settings.difficulty, 0, 2)];

	if(settings.aiFlags & AIF_Passive != 0)
		text += "|";
	if(settings.aiFlags & AIF_Aggressive != 0)
		text += "@";
	if(settings.aiFlags & AIF_Biased != 0)
		text += "^";
	if(settings.aiFlags & AIF_CheatPrivileged != 0)
		text += "$";
	if(settings.type == ET_BumAI)
		text += "?";

	int cheatLevel = 0;
	if(settings.cheatWealth > 0)
		cheatLevel += ceil(double(settings.cheatWealth) / 10.0);
	if(settings.cheatStrength > 0)
		cheatLevel += settings.cheatStrength;
	if(settings.cheatAbundance > 0)
		cheatLevel += settings.cheatAbundance;

	if(cheatLevel > 0) {
		if(cheatLevel > 3)
			cheatLevel = 3;
		while(cheatLevel > 0) {
			text += "+";
			cheatLevel -= 1;
		}
	}

	return text;
}

class AIPopup : BaseGuiElement {
	GuiOverlay@ overlay;

	GuiListbox@ difficulties;

	GuiText@ behaveHeading;
	GuiText@ cheatHeading;

	EmpireSetup@ setup;

	GuiCheckbox@ aggressive;
	GuiCheckbox@ passive;
	GuiCheckbox@ biased;
	GuiCheckbox@ legacy;

	GuiCheckbox@ wealth;
	GuiSpinbox@ wealthAmt;
	GuiCheckbox@ strength;
	GuiSpinbox@ strengthAmt;
	GuiCheckbox@ abundance;
	GuiSpinbox@ abundanceAmt;
	GuiCheckbox@ privileged;

	GuiButton@ okButton;

	AIPopup(IGuiElement@ around, EmpireSetup@ setup) {
		@overlay = GuiOverlay(null);
		overlay.closeSelf = false;
		overlay.fade.a = 0;
		@this.setup = setup;

		recti pos = recti_area(
				vec2i(around.absolutePosition.botRight.x, around.absolutePosition.topLeft.y),
				vec2i(600, 200));
		if(pos.botRight.y > screenSize.y)
			pos += vec2i(0, screenSize.y - pos.botRight.y);
		if(pos.botRight.x > screenSize.x)
			pos += vec2i(screenSize.x - pos.botRight.x, 0);

		super(overlay, pos);
		updateAbsolutePosition();
		setGuiFocus(this);

		@difficulties = GuiListbox(this, Alignment(Left+4, Top+4, Left+250, Bottom-4));
		difficulties.required = true;
		difficulties.itemHeight = 64;

		for(uint i = 0; i < 3; ++i) {
			difficulties.addItem(GuiMarkupListText(
				format("[color=$1][font=Medium][stroke=#000]$2[/stroke][/font][/color]\n[color=#aaa][i]$3[/i][/color]",
					toString(QDIFF_COLORS[i]), QDIFF_NAMES[i], QDIFF_DESC[i])));
		}

		@behaveHeading = GuiText(this, Alignment(Left+260, Top+6, Left+260+170, Top+36));
		behaveHeading.font = FT_Medium;
		behaveHeading.stroke = colors::Black;
		behaveHeading.text = locale::AI_BEHAVIOR;

		pos = recti_area(vec2i(260, 36), vec2i(170, 30));

		@aggressive = GuiCheckbox(this, pos, locale::AI_AGGRESSIVE);
		setMarkupTooltip(aggressive, locale::AI_AGGRESSIVE_DESC);
		pos += vec2i(0, 30);

		@passive = GuiCheckbox(this, pos, locale::AI_PASSIVE);
		setMarkupTooltip(passive, locale::AI_PASSIVE_DESC);
		pos += vec2i(0, 30);

		@biased = GuiCheckbox(this, pos, locale::AI_BIASED);
		setMarkupTooltip(biased, locale::AI_BIASED_DESC);
		pos += vec2i(0, 30);

		@legacy = GuiCheckbox(this, pos, locale::AI_LEGACY);
		legacy.textColor = Color(0xaaaaaaff);
		legacy.visible = !hasDLC("Heralds");
		setMarkupTooltip(legacy, locale::AI_LEGACY_DESC);
		pos += vec2i(0, 30);

		@cheatHeading = GuiText(this, Alignment(Left+260+165, Top+6, Right-12, Top+36));
		cheatHeading.font = FT_Medium;
		cheatHeading.stroke = colors::Black;
		cheatHeading.text = locale::AI_CHEATS;

		pos = recti_area(vec2i(260+165, 36), vec2i(170, 30));

		@wealth = GuiCheckbox(this, recti_area(pos.topLeft, vec2i(110, 30)), locale::AI_WEALTH);
		setMarkupTooltip(wealth, locale::AI_WEALTH_DESC);
		@wealthAmt = GuiSpinbox(this, recti_area(pos.topLeft+vec2i(115, 0), vec2i(50, 30)), 10, 0, 1000, 1, 0);
		pos += vec2i(0, 30);

		@strength = GuiCheckbox(this, recti_area(pos.topLeft, vec2i(110, 30)), locale::AI_STRENGTH);
		setMarkupTooltip(strength, locale::AI_STRENGTH_DESC);
		@strengthAmt = GuiSpinbox(this, recti_area(pos.topLeft+vec2i(115, 0), vec2i(50, 30)), 1, 0, 100, 1, 0);
		pos += vec2i(0, 30);

		@abundance = GuiCheckbox(this, recti_area(pos.topLeft, vec2i(110, 30)), locale::AI_ABUNDANCE);
		setMarkupTooltip(abundance, locale::AI_ABUNDANCE_DESC);
		@abundanceAmt = GuiSpinbox(this, recti_area(pos.topLeft+vec2i(115, 0), vec2i(50, 30)), 1, 0, 100, 1, 0);
		pos += vec2i(0, 30);

		@privileged = GuiCheckbox(this, pos, locale::AI_PRIVILEGED);
		setMarkupTooltip(privileged, locale::AI_PRIVILEGED_DESC);
		pos += vec2i(0, 30);

		@okButton = GuiButton(this, Alignment(Left+260+135, Bottom-34, Width=70, Height=30), locale::OK);

		reset();
	}

	void reset() {
		difficulties.selected = clamp(setup.settings.difficulty, 0, 2);
		aggressive.checked = setup.settings.aiFlags & AIF_Aggressive != 0;
		passive.checked = setup.settings.aiFlags & AIF_Passive != 0;
		biased.checked = setup.settings.aiFlags & AIF_Biased != 0;
		privileged.checked = setup.settings.aiFlags & AIF_CheatPrivileged != 0;
		legacy.checked = setup.settings.type == ET_BumAI;
		if(legacy.checked)
			legacy.visible = true;

		wealth.checked = setup.settings.cheatWealth > 0;
		wealthAmt.visible = wealth.checked;
		if(wealth.checked)
			wealthAmt.value = setup.settings.cheatWealth;

		strength.checked = setup.settings.cheatStrength > 0;
		strengthAmt.visible = strength.checked;
		if(strength.checked)
			strengthAmt.value = setup.settings.cheatStrength;

		abundance.checked = setup.settings.cheatAbundance > 0;
		abundanceAmt.visible = abundance.checked;
		if(abundance.checked)
			abundanceAmt.value = setup.settings.cheatAbundance;
	}

	void apply() {
		uint flags = 0;
		if(aggressive.checked)
			flags |= AIF_Aggressive;
		if(passive.checked)
			flags |= AIF_Passive;
		if(biased.checked)
			flags |= AIF_Biased;
		if(privileged.checked)
			flags |= AIF_CheatPrivileged;

		if(legacy.checked)
			setup.settings.type = ET_BumAI;
		else
			setup.settings.type = ET_WeaselAI;

		wealthAmt.visible = wealth.checked;
		if(wealthAmt.visible)
			setup.settings.cheatWealth = wealthAmt.value;
		else
			setup.settings.cheatWealth = 0;

		strengthAmt.visible = strength.checked;
		if(strengthAmt.visible)
			setup.settings.cheatStrength = strengthAmt.value;
		else
			setup.settings.cheatStrength = 0;

		abundanceAmt.visible = abundance.checked;
		if(abundanceAmt.visible)
			setup.settings.cheatAbundance = abundanceAmt.value;
		else
			setup.settings.cheatAbundance = 0;

		setup.settings.difficulty = difficulties.selected;
		setup.settings.aiFlags = flags;
		setup.submit();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Changed) {
			if(evt.caller is passive) {
				if(passive.checked)
					aggressive.checked = false;
				apply();
				return true;
			}
			if(evt.caller is aggressive) {
				if(aggressive.checked)
					passive.checked = false;
				apply();
				return true;
			}
			apply();
		}
		if(evt.type == GUI_Clicked) {
			if(evt.caller is okButton) {
				apply();
				remove();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void remove() {
		overlay.remove();
		@overlay = null;
		BaseGuiElement::remove();
	}

	void draw() override {
		clearClip();
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class ChoosePopup : GuiIconGrid {
	GuiOverlay@ overlay;
	int extraHeight = 0;

	Color spriteColor;
	array<Color> colors;
	array<Sprite> sprites;

	ChoosePopup(const vec2i& pos, const vec2i& size, const vec2i& itemSize) {
		@overlay = GuiOverlay(null);
		overlay.closeSelf = false;
		overlay.fade.a = 0;
		super(overlay, recti_area(pos, size));
		horizAlign = 0.5;
		vertAlign = 0.0;
		iconSize = itemSize;
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is this && evt.type == GUI_Clicked) {
			if(hovered != -1)
				emitConfirmed(uint(hovered));
			overlay.close();
			return true;
		}
		return GuiIconGrid::onGuiEvent(evt);
	}

	void remove() {
		overlay.remove();
		@overlay = null;
		GuiIconGrid::remove();
	}

	void add(const Color& col) {
		colors.insertLast(col);
	}

	void add(const Sprite& sprt) {
		sprites.insertLast(sprt);
	}

	uint get_length() override {
		return max(colors.length, sprites.length);
	}

	void drawElement(uint index, const recti& pos) override {
		if(uint(hovered) == index)
			drawRectangle(pos, Color(0xffffff30));
		if(index < colors.length)
			drawRectangle(pos.padded(5), colors[index]);
		if(index < sprites.length)
			sprites[index].draw(pos, spriteColor);
	}

	void draw() override {
		clearClip();
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition.padded(0,0,0,-extraHeight));
		GuiIconGrid::draw();
	}
};

class ColorPicker : BaseGuiElement {
	Color picked;
	bool pressed = false;
	
	ColorPicker(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		updateAbsolutePosition();
	}

	void draw() {
		shader::HSV_VALUE = 1.f;
		shader::HSV_SAT_START = 0.5f;
		shader::HSV_SAT_END = 1.f;
		drawRectangle(AbsolutePosition, material::HSVPalette, Color());
		if(AbsolutePosition.isWithin(mousePos)) {
			clearClip();
			recti area = recti_area(mousePos-vec2i(10), vec2i(20));
			drawRectangle(area.padded(-1), colors::Black);
			drawRectangle(area, getColor(mousePos-AbsolutePosition.topLeft));
		}
		BaseGuiElement::draw();
	}

	Color getColor(vec2i offset) {
		Colorf col;
		float hue = float(offset.x) / float(AbsolutePosition.width) * 360.f;
		float sat = (1.f - float(offset.y) / float(AbsolutePosition.height)) * 0.5f + 0.5f;
		col.fromHSV(hue, sat, 1.f);
		col.a = 1.f;
		return Color(col);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Down || (event.type == MET_Moved && pressed)) {
			pressed = true;
			picked = getColor(mousePos - AbsolutePosition.topLeft);

			GuiEvent evt;
			@evt.caller = this;
			evt.type = GUI_Changed;
			onGuiEvent(evt);
			return true;
		}
		else if(pressed && event.type == MET_Button_Up) {
			pressed = false;
			emitConfirmed();
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
};

class PortraitChooser : GuiIconGrid {
	array<Sprite> sprites;
	uint selected = 0;
	Color selectedColor;

	PortraitChooser(IGuiElement@ parent, Alignment@ align, const vec2i& itemSize) {
		super(parent, align);
		horizAlign = 0.5;
		vertAlign = 0.0;
		iconSize = itemSize;
		updateAbsolutePosition();
	}

	void add(const Sprite& sprt) {
		sprites.insertLast(sprt);
	}

	uint get_length() override {
		return sprites.length;
	}

	void drawElement(uint index, const recti& pos) override {
		if(selected == index)
			drawRectangle(pos, selectedColor);
		if(uint(hovered) == index)
			drawRectangle(pos, Color(0xffffff30));
		if(index < sprites.length)
			sprites[index].draw(pos);
	}
};

class ShipsetChooser : GuiIconGrid {
	array<const Shipset@> items;
	uint selected = 0;
	Color selectedColor;

	ShipsetChooser(IGuiElement@ parent, Alignment@ align, const vec2i& itemSize) {
		super(parent, align);
		horizAlign = 0.5;
		vertAlign = 0.0;
		iconSize = itemSize;
		updateAbsolutePosition();
	}

	void add(const Shipset@ shipset) {
		items.insertLast(shipset);
	}

	uint get_length() override {
		return items.length;
	}

	void drawElement(uint index, const recti& pos) override {
		if(selected == index) {
			Color col = selectedColor;
			col.a = 0x15;
			drawRectangle(pos, col);
		}
		if(uint(hovered) == index)
			drawRectangle(pos, Color(0xffffff15));
		if(index < items.length) {
			const Shipset@ shipset = items[index];
			const Hull@ hull = shipset.hulls[0];
			if(hull !is null) {
				quaterniond rot;
				rot = quaterniond_fromAxisAngle(vec3d_front(), -0.9);
				rot *= quaterniond_fromAxisAngle(vec3d_up(), 0.6);
				rot *= quaterniond_fromAxisAngle(vec3d_right(), -0.5);
				setClip(pos);
				Color lightColor = colors::White;
				if(selected == index) {
					NODE_COLOR = Colorf(selectedColor);
					lightColor = selectedColor;
				}
				else
					NODE_COLOR = Colorf(1.f, 1.f, 1.f, 1.f);
				drawLitModel(hull.model, hull.material, pos+vec2i(-4,0), rot, 1.9, lightColor=lightColor);
				clearClip();
			}

			const Font@ ft = skin.getFont(FT_Bold);
			if(selected == index || uint(hovered) == index)
				ft.draw(text=shipset.name, pos=pos.padded(0,4),
						horizAlign=0.5, vertAlign=0.0, stroke=colors::Black,
						color=(selected == index ? selectedColor : colors::White));
		}
	}
};

class WeaponSkinChooser : GuiIconGrid {
	array<const EmpireWeaponSkin@> items;
	uint selected = 0;
	Color selectedColor;

	WeaponSkinChooser(IGuiElement@ parent, Alignment@ align, const vec2i& itemSize) {
		super(parent, align);
		horizAlign = 0.5;
		vertAlign = 0.0;
		iconSize = itemSize;
		updateAbsolutePosition();
	}

	void add(const EmpireWeaponSkin@ it) {
		items.insertLast(it);
	}

	uint get_length() override {
		return items.length;
	}

	void drawElement(uint index, const recti& pos) override {
		if(selected == index) {
			Color col = selectedColor;
			col.a = 0x15;
			drawRectangle(pos, col);
		}
		if(uint(hovered) == index)
			drawRectangle(pos, Color(0xffffff15));
		if(index < items.length)
			items[index].icon.draw(pos);
	}
};

class TraitDisplay : BaseGuiElement {
	const Trait@ trait;
	GuiSprite@ icon;
	GuiMarkupText@ name;
	GuiMarkupText@ description;
	GuiText@ points;
	GuiText@ conflicts;
	GuiCheckbox@ check;
	bool hovered = false;
	bool conflict = false;

	TraitDisplay(IGuiElement@ parent) {
		super(parent, recti());

		@icon = GuiSprite(this, Alignment(Left+20, Top+12, Left+52, Bottom-12));

		@name = GuiMarkupText(this, Alignment(Left+65, Top+8, Right-168, Top+38));
		name.defaultFont = FT_Medium;
		name.defaultStroke = colors::Black;

		@description = GuiMarkupText(this, Alignment(Left+124, Top+34, Right-168, Bottom-8));

		@conflicts = GuiText(this, Alignment(Right-360, Top+8, Right-56, Bottom-8));
		conflicts.vertAlign = 0.1;
		conflicts.horizAlign = 1.0;

		@points = GuiText(this, Alignment(Right-160, Top+8, Right-56, Bottom-8));
		points.horizAlign = 1.0;
		points.font = FT_Subtitle;

		@check = GuiCheckbox(this, Alignment(Right-48, Top+0.5f-20, Right-8, Top+0.5f+20), "");
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				hovered = true;
			break;
			case GUI_Mouse_Left:
				hovered = false;
			break;
			case GUI_Changed:
				if(evt.caller is check) {
					check.checked = !check.checked;
					emitClicked();
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ caller) override {
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0)
					return true;
			break;
			case MET_Button_Up:
				if(evt.button == 0) {
					emitClicked();
					return true;
				}
			break;
		}
		return BaseGuiElement::onMouseEvent(evt, caller);
	}

	void set(const Trait@ trait, bool selected, bool conflict) {
		@this.trait = trait;
		this.conflict = conflict;
		description.text = trait.description;
		icon.desc = trait.icon;
		name.defaultColor = trait.color;

		if(trait.gives > 0) {
			points.text = format(locale::RACE_POINTS_POS, toString(trait.gives));
			points.color = colors::Green;
			points.visible = true;
		}
		else if(trait.cost > 0) {
			points.text = format(locale::RACE_POINTS_NEG, toString(trait.cost));
			points.color = colors::Red;
			points.visible = true;
		}
		else {
			points.text = locale::RACE_POINTS_NEU;
			points.color = Color(0xaaaaaaff);
			points.visible = false;
		}

		bool displayConflicts = false;
		if(trait.conflicts.length > 0) {
			if(conflict) {
				conflicts.color = colors::Red;
				conflicts.font = FT_Bold;
				conflicts.vertAlign = 0.2;
			}
			else {
				conflicts.color = Color(0xaaaaaaff);
				conflicts.font = FT_Italic;
				conflicts.vertAlign = 0.1;
			}
			string str = locale::CONFLICTS+" ";
			for(uint i = 0, cnt = trait.conflicts.length; i < cnt; ++i) {
				if(!trait.conflicts[i].available)
					continue;
				if(i != 0)
					str += ", ";
				str += trait.conflicts[i].name;
				displayConflicts = true;
			}

			conflicts.text = str;
		}
		if(displayConflicts) {
			conflicts.visible = true;
			points.vertAlign = 0.7;
		}
		else {
			conflicts.visible = false;
			points.vertAlign = 0.5;
		}

		if(trait.unique.length != 0) {
			check.style = SS_Radiobox;
			if(description.alignment.right.pixels != 52) {
				description.alignment.right.pixels = 52;
				description.updateAbsolutePosition();
			}
		}
		else {
			check.style = SS_Checkbox;
			if(description.alignment.right.pixels != 168) {
				description.alignment.right.pixels = 168;
				description.updateAbsolutePosition();
			}
		}

		name.text = trait.name;
		check.checked = selected;
	}

	void draw() {
		if(check.checked)
			skin.draw(SS_Glow, SF_Normal, AbsolutePosition, trait.color);
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition.padded(4), trait.color);
		if(hovered)
			drawRectangle(AbsolutePosition.padded(8), Color(0xffffff10));
		BaseGuiElement::draw();
	}
};

class SaveRaceDialog : SaveDialog {
	EmpireSettings settings;
	EmpireSetup@ setup;

	SaveRaceDialog(IGuiElement@ bind, EmpireSettings@ settings, EmpireSetup@ setup) {
		this.settings = settings;
		@this.setup = setup;
		super(bind, modProfile["races"], settings.raceName+".race");
	}

	void clickConfirm() override {
		exportRace(settings, path);
	}
};

class LoadRaceDialog : LoadDialog {
	EmpireSettings settings;
	EmpireSetup@ setup;
	TraitsWindow@ win;

	LoadRaceDialog(TraitsWindow@ win, EmpireSettings@ settings, EmpireSetup@ setup) {
		this.settings = settings;
		@this.setup = setup;
		@this.win = win;
		super(win, modProfile["races"]);
	}

	void clickConfirm() override {
		importRace(setup.settings, path);
		if(win !is null)
			win.update();
		setup.submit();
	}
};

class TraitElement : GuiListElement {
	const Trait@ trait;

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		recti iconPos = recti_area(absPos.topLeft+vec2i(10, 5), vec2i(absPos.height-10, absPos.height-10));
		trait.icon.draw(iconPos);

		recti textPos = absPos.padded(absPos.height + 10, 0, 10, 4);
		ele.skin.getFont(FT_Medium).draw(
			text=trait.name, pos=textPos);
	}

	string get_tooltipText() {
		return format("[color=$1][b]$2[/b][/color]\n$3",
			toString(trait.color), trait.name, trait.description);
	}
};

class TraitsWindow : BaseGuiElement {
	GuiOverlay@ overlay;
	EmpireSetup@ setup;

	GuiBackgroundPanel@ bg;

	GuiListbox@ categories;
	array<const TraitCategory@> usedCategories;

	GuiPanel@ profilePanel;

	GuiText@ nameLabel;
	GuiTextbox@ name;

	GuiText@ portraitLabel;
	PortraitChooser@ portrait;

	GuiText@ shipsetLabel;
	ShipsetChooser@ shipset;

	GuiText@ weaponSkinLabel;
	WeaponSkinChooser@ weaponSkin;

	GuiText@ traitsLabel;
	GuiListbox@ traitList;

	GuiText@ pointsLabel;

	GuiPanel@ traitPanel;
	GuiText@ noTraits;
	array<TraitDisplay@> traits;

	GuiButton@ acceptButton;
	GuiButton@ saveButton;
	GuiButton@ loadButton;

	TraitsWindow(EmpireSetup@ setup) {
		@this.setup = setup;
		@overlay = GuiOverlay(null);
		overlay.closeSelf = false;
		super(overlay, Alignment(Left+0.11f, Top+0.11f, Right-0.11f, Bottom-0.11f));
		updateAbsolutePosition();

		@bg = GuiBackgroundPanel(this, Alignment().fill());
		bg.titleColor = Color(0xff8000ff);
		bg.title = locale::CUSTOMIZE_RACE;

		@categories = GuiListbox(bg, Alignment(Left+4, Top+32, Left+250, Bottom-4));
		categories.itemHeight = 44;
		categories.style = SS_PlainOverlay;
		categories.itemStyle = SS_TabButton;
		categories.addItem(GuiMarkupListText(locale::RACE_PROFILE));
		categories.required = true;

		for(uint i = 0, cnt = getTraitCategoryCount(); i < cnt; ++i) {
			auto@ cat = getTraitCategory(i);
			bool hasTraits = false;
			for(uint n = 0, ncnt = getTraitCount(); n < ncnt; ++n) {
				if(getTrait(n).category is cat && getTrait(n).available && getTrait(n).hasDLC) {
					hasTraits = true;
					break;
				}
			}
			if(hasTraits) {
				categories.addItem(GuiMarkupListText(cat.name));
				usedCategories.insertLast(cat);
			}
		}

		@acceptButton = GuiButton(bg, Alignment(Right-140, Bottom-40, Right-3, Bottom-3), locale::ACCEPT);
		@loadButton = GuiButton(bg, Alignment(Right-274, Bottom-40, Right-154, Bottom-3), locale::LOAD);
		@saveButton = GuiButton(bg, Alignment(Right-400, Bottom-40, Right-280, Bottom-3), locale::SAVE);
		@pointsLabel = GuiText(bg, Alignment(Left+264, Bottom-40, Right-410, Bottom-3));
		pointsLabel.font = FT_Medium;

		Alignment panelAlign(Left+258, Top+32, Right-4, Bottom-40);

		@profilePanel = GuiPanel(bg, panelAlign);
		@traitPanel = GuiPanel(bg, panelAlign);
		traitPanel.visible = false;

		int y = 8;

		@nameLabel = GuiText(profilePanel, Alignment(Left+12, Top+y, Left+200, Top+y+30), locale::RACE_NAME, FT_Bold);
		@name = GuiTextbox(profilePanel, Alignment(Left+200, Top+y, Right-12, Top+y+30), setup.settings.raceName);
		y += 38;

		int h = 80 + (getEmpirePortraitCount() / ((size.width - 200) / 70)) * 80;
		@portraitLabel = GuiText(profilePanel, Alignment(Left+12, Top+y, Left+200, Top+y+30), locale::PORTRAIT, FT_Bold);
		@portrait = PortraitChooser(profilePanel, Alignment(Left+200, Top+y, Right-12, Top+y+h), vec2i(70, 70));
		portrait.selectedColor = setup.settings.color;
		
		portrait.selected = randomi(0, getEmpirePortraitCount()-1);
		portrait.horizAlign = 0.0;
		for(uint i = 0, cnt = getEmpirePortraitCount(); i < cnt; ++i) {
			auto@ img = getEmpirePortrait(i);
			portrait.add(Sprite(img.portrait));
			if(img.ident == setup.settings.portrait)
				portrait.selected = i;
		}
		y += h+8;

		h = 80 + (getShipsetCount() / ((size.width - 200) / 150)) * 80;
		@shipsetLabel = GuiText(profilePanel, Alignment(Left+12, Top+y, Left+200, Top+y+30), locale::SHIPSET, FT_Bold);
		@shipset = ShipsetChooser(profilePanel, Alignment(Left+200, Top+y, Right-12, Top+y+h), vec2i(150, 70));
		shipset.selectedColor = setup.settings.color;
		shipset.selected = 0;
		shipset.horizAlign = 0.0;
		for(uint i = 0, cnt = getShipsetCount(); i < cnt; ++i) {
			auto@ ss = getShipset(i);
			if(ss.available && (ss.dlc.length == 0 || hasDLC(ss.dlc)))
				shipset.add(ss);
			if(ss.ident == setup.settings.shipset)
				shipset.selected = shipset.length-1;
		}
		y += h+8;

		@weaponSkinLabel = GuiText(profilePanel, Alignment(Left+12, Top+y, Left+200, Top+y+30), locale::WEAPON_SKIN, FT_Bold);
		@weaponSkin = WeaponSkinChooser(profilePanel, Alignment(Left+200, Top+y, Right-12, Top+y+80), vec2i(120, 70));
		weaponSkin.selectedColor = setup.settings.color;
		weaponSkin.selected = 0;
		weaponSkin.horizAlign = 0.0;
		for(uint i = 0, cnt = getEmpireWeaponSkinCount(); i < cnt; ++i) {
			auto@ skin = getEmpireWeaponSkin(i);
			weaponSkin.add(skin);
			if(skin.ident == setup.settings.effectorSkin)
				weaponSkin.selected = weaponSkin.length-1;
		}
		y += 88;

		@traitsLabel = GuiText(profilePanel, Alignment(Left+12, Top+y, Left+200, Top+y+30), locale::TRAITS, FT_Bold);
		@traitList = GuiListbox(profilePanel, Alignment(Left+200, Top+y, Right-12, Bottom-8));
		traitList.itemStyle = SS_StaticListboxItem;
		traitList.itemHeight = 50;
		addLazyMarkupTooltip(traitList);
		@noTraits = GuiText(profilePanel, Alignment(Left+240, Top+y+10, Right-12, Top+y+50), locale::NO_TRAITS);
		noTraits.color = Color(0xaaaaaaff);
		noTraits.vertAlign = 0.0;
		y += 58;

		update();
		updateAbsolutePosition();
	}

	void update() {
		int sel = categories.selected;
		profilePanel.visible = sel == 0;
		traitPanel.visible = sel != 0;

		uint index = 0;
		const TraitCategory@ cat;
		if(sel > 0)
			@cat = usedCategories[sel - 1];

		int points = STARTING_TRAIT_POINTS;
		for(uint i = 0, cnt = setup.settings.traits.length; i < cnt; ++i) {
			points += setup.settings.traits[i].gives;
			points -= setup.settings.traits[i].cost;
		}

		if(traitPanel.visible) {
			int y = 0;
			array<const Trait@> list;
			for(uint i = 0, cnt = getTraitCount(); i < cnt; ++i) {
				auto@ trait = getTrait(i);
				if(cat !is null && cat !is trait.category)
					continue;
				if(!setup.player && !trait.aiSupport)
					continue;
				if(!trait.available)
					continue;
				if(!trait.hasDLC)
					continue;
				list.insertLast(trait);
			}
			list.sortAsc();

			for(uint i = 0, cnt = list.length; i < cnt; ++i) {
				auto@ trait = list[i];
				TraitDisplay@ disp;
				if(index < traits.length) {
					@disp = traits[index];
				}
				else {
					@disp = TraitDisplay(traitPanel);
					traits.insertLast(disp);
				}

				disp.set(trait, setup.settings.hasTrait(trait), trait.hasConflicts(setup.settings.traits));
				disp.alignment.set(Left, Top+y, Right, Top+y+140);
				disp.updateAbsolutePosition();
				int needH = disp.description.renderer.height+48;
				if(needH != 140) {
					disp.alignment.set(Left, Top+y, Right, Top+y+needH);
					disp.updateAbsolutePosition();
				}

				++index;
				y += needH;
			}

			for(uint i = index, cnt = traits.length; i < cnt; ++i)
				traits[i].remove();
			traits.length = index;
			traitPanel.updateAbsolutePosition();
		}

		if(profilePanel.visible) {
			uint cnt = setup.settings.traits.length;
			traitList.removeItemsFrom(cnt);
			for(uint i = 0; i < cnt; ++i) {
				auto@ item = cast<TraitElement>(traitList.getItemElement(i));
				if(item is null) {
					@item = TraitElement();
					traitList.addItem(item);
				}

				@item.trait = setup.settings.traits[i];
			}
			noTraits.visible = cnt == 0;
		}

		if(points > 0) {
			pointsLabel.color = colors::Green;
			pointsLabel.text = format(locale::RACE_POINTS_AVAIL_POS, toString(points));
			pointsLabel.visible = true;
		}
		else if(points < 0) {
			pointsLabel.color = colors::Red;
			pointsLabel.text = format(locale::RACE_POINTS_AVAIL_NEG, toString(-points));
			pointsLabel.visible = true;
		}
		else {
			pointsLabel.color = Color(0xaaaaaaff);
			pointsLabel.text = format(locale::RACE_POINTS_AVAIL_POS, toString(points));
			pointsLabel.visible = false;
		}

		if(points >= 0 && !setup.settings.hasTraitConflicts())
			acceptButton.color = colors::Green;
		else
			acceptButton.color = colors::Red;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is acceptButton) {
			if(evt.type == GUI_Clicked) {
				overlay.close();
				return true;
			}
		}
		if(evt.caller is saveButton) {
			if(evt.type == GUI_Clicked) {
				SaveRaceDialog(this, setup.settings, setup);
				return true;
			}
		}
		else if(evt.caller is loadButton) {
			if(evt.type == GUI_Clicked) {
				LoadRaceDialog(this, setup.settings, setup);
				return true;
			}
		}
		if(evt.type == GUI_Clicked) {
			if(evt.caller is portrait) {
				int hov = portrait.hovered;
				if(hov >= 0) {
					setup.settings.portrait = getEmpirePortrait(hov).ident;
					portrait.selected = hov;
				}
				setup.submit();
				return true;
			}
			if(evt.caller is shipset) {
				int hov = shipset.hovered;
				if(hov >= 0) {
					setup.settings.shipset = shipset.items[hov].ident;
					shipset.selected = hov;
				}
				setup.submit();
				return true;
			}
			if(evt.caller is weaponSkin) {
				int hov = weaponSkin.hovered;
				if(hov >= 0) {
					setup.settings.effectorSkin = weaponSkin.items[hov].ident;
					weaponSkin.selected = hov;
				}
				setup.submit();
				return true;
			}
			
			auto@ disp = cast<TraitDisplay>(evt.caller);
			if(disp !is null) {
				if(disp.trait.unique.length != 0)
					setup.settings.chooseTrait(disp.trait);
				else if(setup.settings.hasTrait(disp.trait))
					setup.settings.removeTrait(disp.trait);
				else
					setup.settings.addTrait(disp.trait);
				update();
				setup.submit();
			}
		}
		if(evt.type == GUI_Changed) {
			if(evt.caller is name) {
				setup.settings.raceName = name.text;
				setup.submit();
				return true;
			}
			if(evt.caller is categories) {
				update();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() override {
		BaseGuiElement::draw();
	}
};

class GalaxySetup : BaseGuiElement {
	Map@ mp;
	NewGame@ ng;
	GuiText@ name;

	GuiText@ timesLabel;
	GuiSpinbox@ timesBox;

	GuiPanel@ settings;

	GuiButton@ removeButton;
	GuiButton@ hwButton;
	GuiSprite@ hwX;

	GalaxySetup(NewGame@ menu, Alignment@ align, Map@ fromMap) {
		super(menu.galaxyPanel, align);
		@mp = fromMap.create();
		@ng = menu;

		@name = GuiText(this, Alignment(Left+6, Top+5, Right-262, Height=28));
		name.text = mp.name;
		name.font = FT_Medium;
		name.color = mp.color;
		name.stroke = colors::Black;

		@timesBox = GuiSpinbox(this, Alignment(Right-190, Top+7, Width=52, Height=22), 1.0);
		timesBox.min = 1.0;
		timesBox.max = 100.0;
		timesBox.decimals = 0;
		timesBox.color = Color(0xffffff60);

		@timesLabel = GuiText(this, Alignment(Right-135, Top+7, Width=25, Height=22), "x");

		timesBox.visible = !mp.isUnique;
		timesLabel.visible = !mp.isUnique;

		@removeButton = GuiButton(this, Alignment(Right-84, Top+4, Right-25, Top+34));
		removeButton.setIcon(icons::Remove);
		removeButton.color = colors::Red;

		@hwButton = GuiButton(this, Alignment(Right-230, Top+5, Width=26, Height=26));
		hwButton.setIcon(Sprite(spritesheet::PlanetType, 2, Color(0xffffffaa)), padding=0);
		hwButton.toggleButton = true;
		hwButton.pressed = false;
		hwButton.style = SS_IconButton;
		hwButton.color = Color(0xff0000ff);
		setMarkupTooltip(hwButton, locale::NGTT_MAP_HW);
		@hwX = GuiSprite(hwButton, Alignment(), Sprite(spritesheet::QuickbarIcons, 3, Color(0xffffff80)));
		hwX.visible = false;

		@settings = GuiPanel(this,
			Alignment(Left, Top+42, Right, Bottom-4));
		mp.create(settings);
	}

	void setHomeworlds(bool value) {
		hwButton.pressed = !value;
		hwX.visible = hwButton.pressed;
		if(hwButton.pressed)
			hwButton.fullIcon.color = Color(0xffffffff);
		else
			hwButton.fullIcon.color = Color(0xffffffaa);
	}

	void apply(MapSettings& set) {
		set.map_id = mp.id;
		set.galaxyCount = timesBox.value;
		@set.parent = ng.settings;
		set.allowHomeworlds = !hwButton.pressed;
		mp.apply(set);
	}

	void load(MapSettings& set) {
		auto@ _map = getMap(set.map_id);
		if(getClass(mp) !is getClass(_map))
			@mp = cast<Map>(getClass(_map).create());
		timesBox.value = set.galaxyCount;

		hwButton.pressed = !set.allowHomeworlds;
		hwX.visible = hwButton.pressed;
		if(hwButton.pressed)
			hwButton.fullIcon.color = Color(0xffffffff);
		else
			hwButton.fullIcon.color = Color(0xffffffaa);

		mp.load(set);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is removeButton) {
					ng.removeGalaxy(this);
					return true;
				}
				else if(evt.caller is hwButton) {
					setHomeworlds(!hwButton.pressed);
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() {
		recti bgPos = AbsolutePosition.padded(-5,0,-4,0);
		clipParent(bgPos);
		skin.draw(SS_GalaxySetupItem, SF_Normal, bgPos.padded(-4,0), mp.color);
		resetClip();
		auto@ icon = mapIcons[mp.index];
		if(mp.icon.length != 0 && icon.isLoaded(0)) {
			recti pos = AbsolutePosition.padded(0,42,0,0).aspectAligned(1.0, horizAlign=1.0, vertAlign=1.0);
			icon.draw(pos, Color(0xffffff80));
		}
		BaseGuiElement::draw();
	}
};

class MapElement : GuiListElement {
	Map@ mp;

	MapElement(Map@ _map) {
		@mp = _map;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ title = ele.skin.getFont(FT_Subtitle);
		const Font@ normal = ele.skin.getFont(FT_Normal);

		ele.skin.draw(SS_ListboxItem, flags, absPos, mp.color);
		auto@ icon = mapIcons[mp.index];
		if(mp.icon.length != 0 && icon.isLoaded(0)) {
			recti pos = absPos.aspectAligned(1.0, horizAlign=1.0, vertAlign=1.0);
			icon.draw(pos, Color(0xffffff80));
		}

		title.draw(pos=absPos.resized(0, 32).padded(12,4),
				text=mp.name, color=mp.color, stroke=colors::Black);
		normal.draw(pos=absPos.padded(12,36,12+absPos.height,0), offset=vec2i(),
				lineHeight=-1, text=mp.description, color=colors::White);
	}
};

class Quickstart : ConsoleCommand {
	void execute(const string& args) {
		new_game.start();
	}
};

NewGame@ new_game;
array<DynamicTexture> mapIcons;

void init() {
	@new_game = NewGame();
	new_game.visible = false;

	addConsoleCommand("quickstart", Quickstart());
}

array<Player@> connectedPlayers;
set_int connectedSet;
void tick(double time) {
	if(new_game.visible)
		new_game.tick(time);
	if(!game_running && mpServer) {
		array<Player@>@ players = getPlayers();

		//Send connect events
		for(uint i = 0, cnt = players.length; i < cnt; ++i) {
			Player@ pl = players[i];
			if(pl.id == CURRENT_PLAYER.id)
				continue;
			string name = pl.name;
			if(name.length == 0)
				continue;
			if(!connectedSet.contains(pl.id)) {
				string msg = format("[color=#aaa]* "+locale::MP_CONNECT_EVENT+"[/color]",
					format("[b]$1[/b]", bbescape(name)));
				recvMenuJoin(ALL_PLAYERS, msg);
				connectedPlayers.insertLast(pl);
				connectedSet.insert(pl.id);
			}
		}

		connectedSet.clear();
		for(uint i = 0, cnt = players.length; i < cnt; ++i)
			connectedSet.insert(players[i].id);

		//Send disconnect events
		for(uint i = 0, cnt = connectedPlayers.length; i < cnt; ++i) {
			if(!connectedSet.contains(connectedPlayers[i].id)) {
				Color color;
				string name = connectedPlayers[i].name;

				string msg = format("[color=#aaa]* "+locale::MP_DISCONNECT_EVENT+"[/color]", 
					format("[b]$2[/b]", toString(color), bbescape(name)));
				recvMenuLeave(ALL_PLAYERS, msg);
				connectedPlayers.removeAt(i);
				--i; --cnt;
			}
		}
	}
}

void showNewGame(bool fromMP = false) {
	new_game.visible = true;
	new_game.fromMP = fromMP;
	new_game.init();
	menu_container.visible = false;
	menu_container.animateOut();
	new_game.animateIn();
}

void hideNewGame(bool snap = false) {
	new_game.fromMP = false;
	menu_container.visible = true;
	if(!snap) {
		menu_container.animateIn();
		new_game.animateOut();
	}
	else {
		animate_remove(new_game);
		new_game.visible = false;
		menu_container.show();
	}
}

void changeEmpireSettings_client(Player& pl, EmpireSettings@ settings) {
	auto@ emp = new_game.findPlayer(pl.id);
	emp.settings.raceName = settings.raceName;
	emp.settings.traits = settings.traits;
	emp.settings.portrait = settings.portrait;
	emp.settings.shipset = settings.shipset;
	emp.settings.effectorSkin = settings.effectorSkin;
	emp.settings.color = settings.color;
	emp.settings.flag = settings.flag;
	emp.settings.ready = settings.ready;
	emp.settings.team = settings.team;
	emp.update();
}

bool sendPeriodic(Message& msg) {
	if(game_running)
		return false;
	new_game.apply();
	msg << new_game.settings;
	return true;
}

void recvPeriodic(Message& msg) {
	msg >> new_game.settings;
	new_game.reset();
	new_game.updateAbsolutePosition();
}

void chatMessage(Player& pl, string text) {
	auto@ emp = new_game.findPlayer(pl.id);
	Color color = emp.settings.color;
	string msg = format("[b][color=$1]$2[/color][/b] [offset=100]$3[/offset]",
		toString(color), bbescape(emp.name.text), bbescape(text));
	recvMenuChat(ALL_PLAYERS, msg);
}

void chatMessage_client(string text) {
	new_game.addChat(text);
	sound::generic_click.play();
}

void chatJoin_client(string text) {
	new_game.addChat(text);
	sound::generic_ok.play();
}

void chatLeave_client(string text) {
	new_game.addChat(text);
	sound::generic_warn.play();
}
