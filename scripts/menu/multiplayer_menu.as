import menus;
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiSpinbox;
import elements.GuiCheckbox;
import elements.GuiOverlay;
import elements.GuiProgressbar;
import elements.GuiBackgroundPanel;
import dialogs.MessageDialog;
import dialogs.InputDialog;
import icons;
from irc_window import showIRC;
from new_game import showNewGame;

from maps import Map, maps, mapCount, getMap;

import util.game_options;

class ServerDesc {
	GameServer srv;
	bool found = false;
};

class ServerElement : GuiListElement {
	string text;
	Color color;
	bool disabled = false;

	void set(const string& txt) {
		text = txt;
	}

	string get() {
		return text;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();
		vec2i textOffset(ele.horizPadding, (absPos.size.height - baseLine) / 2);

		if(ele.itemStyle == SS_NULL)
			ele.skin.draw(SS_ListboxItem, flags, absPos);
		font.draw(absPos.topLeft + textOffset, text, color);
	}

	bool get_isSelectable() {
		return !disabled;
	}
};

class PasswordDialog : InputDialogCallback {
	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			string pwd = dialog.getTextInput(0);
			mp_list.join(pwd);
		}
	}
};

class IPJoin : InputDialogCallback {
	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted)
			mp_list.join(dialog.getTextInput(0), toInt(dialog.getTextInput(1)), dialog.getTextInput(2));
	}
};

class Multiplayer : BaseGuiElement {
	GuiBackgroundPanel@ gamesBG;
	GuiBackgroundPanel@ optionsBG;
	GuiBackgroundPanel@ hostBG;

	GuiProgressbar@ transferProgress;

	GuiButton@ backButton, joinButton, queueButton;
	GuiButton@ hostButton, hostLoadButton;
	GuiButton@ refreshButton;
	GuiButton@ ircButton;
	GuiButton@ ipButton;
	
	GuiText@ nickLabel;
	GuiTextbox@ nick;

	GuiText@ serverNameLabel;
	GuiTextbox@ serverName;

	GuiText@ passwordLabel;
	GuiTextbox@ passwordBox;

	GuiText@ portLabel;
	GuiTextbox@ portBox;

	GuiCheckbox@ publicToggle;
	GuiCheckbox@ punchToggle;
	
	GuiText@ noServers;
	GuiListbox@ servers;
	array<ServerDesc@> gameServers;
	array<GameServer> newServers;
	
	GuiText@ inQueue;
	GuiButton@ queueAccept, queueReject, queueLeave;

	GuiText@ connectingText;
	GuiButton@ cancelButton;

	bool animating = false;
	bool hide = false;
	bool connecting = false;
	double nextRefresh = 0.0;

	Multiplayer() {
		super(null, recti());

		@gamesBG = GuiBackgroundPanel(this, Alignment(
			Left+0.05f, Top+0.1f, Right-0.05f, Bottom-0.1f-242));
		gamesBG.title = locale::MENU_GAMES;
		gamesBG.titleColor = Color(0x00ff00ff);

		@optionsBG = GuiBackgroundPanel(this, Alignment(
			Left+0.05f, Bottom-0.1f-230, Right-0.5f-6, Bottom-0.1f));
		optionsBG.title = locale::MP_OPTIONS;
		optionsBG.titleColor = Color(0xd0ffefff);

		@hostBG = GuiBackgroundPanel(this, Alignment(
			Left+0.5f+6, Bottom-0.1f-230, Right-0.05f, Bottom-0.1f));
		hostBG.title = locale::MP_HOST_OPTIONS;
		hostBG.titleColor = Color(0xd0ffefff);
		
		@noServers = GuiText(gamesBG, Alignment(Left+12,Top+33,Right-4,Top+55), locale::MP_NO_GAMES);
		noServers.color = Color(0xaaaaaaff);
		noServers.font = FT_Italic;
		@servers = GuiListbox(gamesBG, Alignment(Left+4,Top+33,Right-4,Bottom-42));
		servers.visible = false;
		
		@nickLabel = GuiText(optionsBG, recti(12, 33, 110, 60), locale::NICKNAME);
		@nick = GuiTextbox(optionsBG, recti(122, 33, 280, 60), settings::sNickname);

		@serverNameLabel = GuiText(hostBG, recti(12, 33, 110, 60), locale::MP_SERVER_NAME);
		@serverName = GuiTextbox(hostBG, recti(122, 33, 380, 60), settings::sNickname+"'s Game");
		serverName.tabIndex = 1;

		@passwordLabel = GuiText(hostBG, recti(11, 66, 110, 93), locale::PASSWORD);
		@passwordBox = GuiTextbox(hostBG, recti(122, 66, 380, 93), "");
		passwordBox.tabIndex = 2;

		@publicToggle = GuiCheckbox(hostBG, recti(12, 99, 140, 126), locale::MP_PUBLIC, true);
		publicToggle.tabIndex = 3;
		@punchToggle = GuiCheckbox(hostBG, recti(150, 99, 280, 126), locale::MP_PUNCHTHROUGH, true);
		punchToggle.tabIndex = 4;

		@portLabel = GuiText(hostBG, recti(12, 132, 110, 158), locale::MP_PORT);
		@portBox = GuiTextbox(hostBG, recti(122, 132, 250, 158), "2048");
		portBox.tabIndex = 5;

		@refreshButton = GuiButton(gamesBG, Alignment(
			Right-174, Bottom-40, Width=170, Height=36),
			locale::REFRESH);
		refreshButton.buttonIcon = Sprite(spritesheet::MenuIcons, 12);

		@ircButton = GuiButton(gamesBG, Alignment(
			Left+4, Bottom-40, Width=200, Height=36),
			locale::MP_IRC_CHAT);
		ircButton.buttonIcon = icons::Chat;

		@ipButton = GuiButton(gamesBG, Alignment(
			Left+208, Bottom-40, Width=200, Height=36),
			locale::MP_JOIN_IP);
		ipButton.buttonIcon = Sprite(spritesheet::MenuIcons, 13);
		
		@joinButton = GuiButton(this, Alignment(
			Right-0.05f-200, Bottom-0.1f+6, Width=200, Height=46),
			locale::MP_JOIN);
		joinButton.buttonIcon = Sprite(spritesheet::MenuIcons, 13);

		@hostButton = GuiButton(this, Alignment(
			Right-0.05f-412, Bottom-0.1f+6, Width=200, Height=46),
			locale::MP_HOST);
		hostButton.buttonIcon = Sprite(spritesheet::MenuIcons, 14);

		@hostLoadButton = GuiButton(this, Alignment(
			Right-0.05f-624, Bottom-0.1f+6, Width=200, Height=46),
			locale::MP_HOST_LOAD);
		hostLoadButton.buttonIcon = Sprite(spritesheet::MenuIcons, 15);

		@backButton = GuiButton(this, Alignment(
			Left+0.05f, Bottom-0.1f+6, Width=200, Height=46),
			locale::BACK);
		backButton.buttonIcon = Sprite(spritesheet::MenuIcons, 11);

		if(cloud::isActive) {
			@queueButton = GuiButton(this, Alignment(
				Right-0.05f-836, Bottom-0.1f+6, Width=200, Height=46),
				locale::MP_QUEUE);
			queueButton.buttonIcon = Sprite(spritesheet::MenuIcons, 4);
		
			@inQueue = GuiText(gamesBG, Alignment(Left+12,Top+33,Right-4,Top+61), locale::MP_QUEUE_ACTIVE);
			inQueue.font = FT_Medium;
			inQueue.horizAlign = 0.5;
			inQueue.visible = false;
			
			@queueAccept = GuiButton(gamesBG, Alignment(
				Left+0.5f-205, Top+65, Width=200, Height=46),
				locale::MP_QUEUE_ACCEPT);
			queueAccept.font = FT_Medium;
			queueAccept.color = Color(0x88ff88ff);
			queueAccept.visible = false;
			
			@queueReject = GuiButton(gamesBG, Alignment(
				Left+0.5f+5, Top+65, Width=200, Height=46),
				locale::MP_QUEUE_REJECT);
			queueReject.font = FT_Medium;
			queueReject.color = Color(0xff8888ff);
			queueReject.visible = false;
			
			@queueLeave = GuiButton(gamesBG, Alignment(
				Left+0.5f-100, Top+65, Width=200, Height=46),
				locale::MP_QUEUE_LEAVE);
			queueLeave.font = FT_Medium;
			queueLeave.visible = false;
		}

		@connectingText = GuiText(this, Alignment(Left, Top+0.5f-56, Right, Top+0.5f));
		connectingText.font = FT_Medium;
		connectingText.horizAlign = 0.5;
		connectingText.visible = false;

		@cancelButton = GuiButton(this, Alignment(
			Left+0.5f-100, Top+0.5f-16, Width=200, Height=46),
			locale::CANCEL);
		cancelButton.visible = false;

		@transferProgress = GuiProgressbar(this, Alignment(Left+0.25f, Bottom-0.25f-25, Right-0.25f, Bottom-0.25f+25));
		transferProgress.frontColor = colors::Orange;
		transferProgress.visible = false;

		updateAbsolutePosition();
	}

	void refresh() {
		if(mpIsQuerying())
			return;
		mpQueryServers();
		for(uint n = 0, ncnt = gameServers.length; n < ncnt; ++n)
			gameServers[n].found = false;
	}

	void tick(double time) {
		if(!visible)
			return;
		
		if(gamesBG.visible) {
			if(!cloud::isActive || !cloud::inQueue) {
				if(queueButton !is null) {
					inQueue.visible = false;
					queueAccept.visible = false;
					queueReject.visible = false;
					queueLeave.visible = false;
					
					queueButton.visible = true;
				}
				
				joinButton.visible = true;
				ipButton.visible = true;
				refreshButton.visible = true;
				hostButton.disabled = false;
				hostLoadButton.disabled = false;
				
				servers.visible = gameServers.length != 0;
				noServers.visible = gameServers.length == 0;
			}
			else {
				inQueue.visible = true;
				bool queueRequested = cloud::queueRequest;
				queueAccept.visible = queueRequested;
				queueReject.visible = queueRequested;
				queueLeave.visible = !queueRequested;
				
				uint ready = 0, players = 0;
				
				if(queueRequested)
					inQueue.text = locale::MP_QUEUE_READY;
				else if(cloud::getQueuePlayerWait(ready, players)) {
					inQueue.text = format(locale::MP_QUEUE_WAITING, ready, players);
					queueLeave.visible = false;
				}
				else {
					uint players = cloud::queuePlayers;
					if(players == 0)
						inQueue.text = locale::MP_QUEUE_ACTIVE;
					else
						inQueue.text = format(locale::MP_QUEUE_ACTIVE_PLAYERS, players);
				}
				
				queueButton.visible = false;
				joinButton.visible = false;
				ipButton.visible = false;
				refreshButton.visible = false;
				hostButton.disabled = true;
				hostLoadButton.disabled = true;
				
				servers.visible = false;
				noServers.visible = false;
			}
		}
		
		if(!connectingText.visible) {
			if(!menu_container.animating && cloud::isQueueReady) {
				if(mpClient) {
					showConnecting();
					showMenu();
					hideMultiplayer(snap=true);
					showNewGame(true);
					return;
				}
				if(mpServer) {
					showMenu();
					hideMultiplayer(snap=true);
					showNewGame();
					return;
				}
			}

			if(awaitingGalaxy)
				showConnecting();
		}
		
		if(connectingText.visible) {
			if(awaitingGalaxy) {
				connectingText.text = locale::MP_WAITING_TRANSFER;
			}
			else if(mpIsConnected()) {
				connectingText.text = locale::MP_WAITING_START;
				showMenu();
				hideMultiplayer();
				showNewGame(true);
			}
			else if(!mpIsConnecting()) {
				mpDisconnect();
				showMenu();
				message(locale::MP_CANNOT_CONNECT+":\n    "
						+localize("DISCONNECT_"+uint(mpDisconnectReason)));
			}
		}
		else if(mpIsConnecting()) {
			connectingText.text = "Connecting...";
			showConnecting();
			updateAbsolutePosition();
		}
		if(awaitingGalaxy) {
			float pct = galaxySendProgress;
			transferProgress.visible = true;
			transferProgress.progress = pct;
			transferProgress.text = toString(pct * 100.f, 0)+"%";
		}
		else {
			transferProgress.visible = false;
		}

		nextRefresh -= time;
		if(nextRefresh <= 0.0) {
			nextRefresh = 30.0;
			refresh();
		}

		bool serversChanged = false;
		int sel = servers.selected;
		GameAddress selAddr;
		if(sel != -1 && uint(sel) < gameServers.length)
			selAddr = gameServers[sel].srv.address;

		//Get new servers
		mpGetServers(newServers);
		if(newServers.length != 0) {
			for(uint i = 0, cnt = newServers.length; i < cnt; ++i) {
				//See if we already have this server
				bool found = false;
				for(uint n = 0, ncnt = gameServers.length; n < ncnt; ++n) {
					if(gameServers[n].srv.address == newServers[i].address) {
						gameServers[n].srv = newServers[i];
						gameServers[n].found = true;
						found = true;
						break;
					}
				}

				if(!found) {
					ServerDesc desc;
					desc.srv = newServers[i];
					desc.found = true;
					gameServers.insertLast(desc);
				}
			}
			newServers.length = 0;
			serversChanged = true;
		}

		//Prune old servers
		if(!mpIsQuerying()){
			for(uint n = 0, ncnt = gameServers.length; n < ncnt; ++n) {
				if(!gameServers[n].found) {
					gameServers.removeAt(n);
					--n; --ncnt;
					serversChanged = true;
				}
			}
		}

		//Update servers list
		if(serversChanged) {
			servers.clearItems();
			servers.selected = -1;

			for(uint n = 0, ncnt = gameServers.length; n < ncnt; ++n) {
				ServerDesc@ desc = gameServers[n];
				string name = desc.srv.name;
				bool haveMods = true;
				if(name.length == 0)
					name = "Game at "+desc.srv.address.toString();
				if(desc.srv.players > 0) {
					name += " ("+desc.srv.players;
					if(desc.srv.maxPlayers > 0) {
						name += "/"+desc.srv.maxPlayers;
						name += " Players)";
					}
					else if(desc.srv.players > 1) {
						name += " Players)";
					}
					else {
						name += " Player)";
					}
				}
				if(desc.srv.started)
					name += " (In Progress)";
				if(desc.srv.isLocal)
					name += " (LAN)";
				if(desc.srv.password)
					name += " ("+locale::PASSWORD+")";
				if(desc.srv.mod.length != 0) {
					string modString;
					array<string>@ modList = desc.srv.mod.split("\n");
					for(uint i = 0, cnt = modList.length; i < cnt; ++i) {
						if(i != 0)
							modString += ", ";
						modString += modList[i];
						if(getMod(modList[i]) is null)
							haveMods = false;
					}
					name += " (Mods: "+modString+")";
				}

				ServerElement elem;
				if(desc.srv.version != MP_VERSION) {
					elem.disabled = true;
					elem.color = colors::Red;
					name += " "+locale::MP_VERSION_MISMATCH;
				}
				else if(!haveMods) {
					elem.disabled = true;
					elem.color = colors::Red;
					name += " "+locale::MP_MISSING_MODS;
				}
				else if(desc.srv.password) {
					elem.color = Color(0xfffa00ff);
				}

				elem.text = name;
				servers.addItem(elem);

				if(desc.srv.address == selAddr)
					servers.selected = n;
			}

			if(joinButton.visible) {
				servers.visible = gameServers.length != 0;
				noServers.visible = gameServers.length == 0;
			}
		}

		joinButton.disabled = (servers.selected == -1);
		refreshButton.disabled = mpIsQuerying();
		portLabel.visible = !punchToggle.checked;
		portBox.visible = !punchToggle.checked;
	}

	void host() {
		mpHost(gamename = serverName.text,
				port = max(toUInt(portBox.text), 1),
				isPublic = publicToggle.checked,
				punchthrough = punchToggle.checked,
				password = passwordBox.text);
	}

	void join(const string& pwd = "") {
		int index = servers.selected;
		if(index >= 0 && index <= int(gameServers.length)) {
			if(game_running) {
				stopGame();
				if(mpServer)
					mpDisconnect();
			}
			GameServer srv = gameServers[index].srv;
			if(pwd.length == 0 && srv.password) {
				InputDialog@ dialog = InputDialog(PasswordDialog(), this);
				dialog.addTitle(locale::MP_ENTER_PASSWORD);
				dialog.accept.text = locale::MP_JOIN;
				dialog.addTextInput("", "");

				addDialog(dialog);
				dialog.focusInput();
				return;
			}

			mpConnect(srv, password=pwd);

			showConnecting();
			if(srv.punchPort != -1 && srv.name.length != 0) {
				connectingText.text = "Connecting to "+srv.name+"...";
			}
			else {
				string addr = srv.address.toString(false);
				int port = srv.address.port;
				connectingText.text = "Connecting to "+addr+":"+port+"...";
			}
		}
	}

	void join(const string& hostname, int port, const string& pwd = "") {
		if(game_running) {
			stopGame();
			if(mpServer || mpClient)
				mpDisconnect();
		}
		mpConnect(hostname, port, pwd);
		showConnecting();
		connectingText.text = "Connecting to "+hostname+":"+port+"...";
	}

	void applyNick() {
		if(nick.text.length != 0 && nick.text != settings::sNickname) {
			settings::sNickname = nick.text;
			IRC.nickname = settings::sNickname;
			saveSettings();
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Clicked:
				if(event.caller is backButton) {
					applyNick();
					if(mpServer && !game_running)
						mpDisconnect();
					hideMultiplayer();
					return true;
				}
				else if(event.caller is queueButton) {
					if(!cloud::inQueue)
						cloud::enterQueue("1v1", 2, toString(MP_VERSION));
					return true;
				}
				else if(event.caller is queueLeave) {
					if(cloud::inQueue)
						cloud::leaveQueue();
					return true;
				}
				else if(event.caller is queueAccept) {
					cloud::acceptQueue();
					return true;
				}
				else if(event.caller is queueReject) {
					cloud::rejectQueue();
					return true;
				}
				else if(event.caller is cancelButton) {
					mpDisconnect();
					showMenu();
					return true;
				}
				else if(event.caller is hostButton) {
					if(game_running) {
						stopGame();
						if(mpServer || mpClient)
							mpDisconnect();
					}
					applyNick();
					host();
					hideMultiplayer();
					showNewGame();
					return true;
				}
				else if(event.caller is refreshButton) {
					refresh();
					return true;
				}
				else if(event.caller is ircButton) {
					showIRC();
					return true;
				}
				else if(event.caller is ipButton) {
					InputDialog@ dialog = InputDialog(IPJoin(), this);
					dialog.addTitle(locale::MP_JOIN_IP);
					dialog.accept.text = locale::MP_JOIN;
					dialog.addTextInput(locale::MP_IP, "127.0.0.1");
					dialog.addTextInput(locale::MP_PORT, "2048");
					dialog.addTextInput(locale::PASSWORD, "");

					addDialog(dialog);
					dialog.focusTextInput(0, selectAll=true);
					return true;
				}
				else if(event.caller is hostLoadButton) {
					if(game_running) {
						stopGame();
						if(mpServer || mpClient)
							mpDisconnect();
					}
					applyNick();
					host();
					hideMultiplayer();
					switchToMenu(load_menu);
					return true;
				}
				else if(event.caller is joinButton) {
					applyNick();
					join();
					return true;
				}
			break;
			case GUI_Confirmed:
				if(event.caller is servers) {
					join();
					return true;
				}
				else if(event.caller is nick) {
					applyNick();
					return true;
				}
			break;
			case GUI_Focus_Lost:
				if(event.caller is nick) {
					applyNick();
					return false;
				}
			break;
			case GUI_Animation_Complete:
				animating = false;
				return true;
		}

		return BaseGuiElement::onGuiEvent(event);
	}

	void showConnecting() {
		gamesBG.visible = false;
		optionsBG.visible = false;
		joinButton.visible = false;
		backButton.visible = false;
		hostButton.visible = false;
		hostLoadButton.visible = false;
		hostBG.visible = false;
		if(queueButton !is null)
			queueButton.visible = false;

		connectingText.visible = true;
		cancelButton.visible = true;
		updateAbsolutePosition();
	}

	void showMenu() {
		gamesBG.visible = true;
		optionsBG.visible = true;
		joinButton.visible = true;
		backButton.visible = true;
		hostButton.visible = true;
		hostLoadButton.visible = true;
		hostBG.visible = true;
		if(queueButton !is null)
			queueButton.visible = true;

		connectingText.visible = false;
		cancelButton.visible = false;
		updateAbsolutePosition();
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
		BaseGuiElement::updateAbsolutePosition();
	}

	void animateIn() {
		animating = true;
		showMenu();

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

class AcceptQueue : ConsoleCommand {	
	void execute(const string& args) {
		if(cloud::queueRequest)
			cloud::acceptQueue();
	}
};

class RejectQueue : ConsoleCommand {	
	void execute(const string& args) {
		if(cloud::queueRequest)
			cloud::rejectQueue();
	}
};

class LeaveQueue : ConsoleCommand {	
	void execute(const string& args) {
		if(cloud::inQueue)
			cloud::leaveQueue();
	}
};

Multiplayer@ mp_list;
void init() {
	if(cloud::isActive) {
		if(settings::sNickname == "SRPlayer" || settings::sNickname.length == 0) {
			settings::sNickname = cloud::getNickname();
			saveSettings();
		}
	}
	@mp_list = Multiplayer();
	mp_list.visible = false;
	
	addConsoleCommand("accept_queue", AcceptQueue());
	addConsoleCommand("reject_queue", RejectQueue());
	addConsoleCommand("leave_queue", LeaveQueue());
}

void tick(double time) {
	if(mp_list.visible)
		mp_list.tick(time);
}

void showMultiplayer() {
	mp_list.visible = true;
	menu_container.animateOut();
	mp_list.animateIn();
	mp_list.nextRefresh = 0.0;
}

void onGameStateChange() {
	if(game_state == GS_Menu) {
		if(game_running && !mp_list.gamesBG.visible) {
			mp_list.showMenu();
			hideMultiplayer(true);
		}
	}
}

void hideMultiplayer(bool snap = false) {
	menu_container.visible = true;
	if(!snap) {
		menu_container.animateIn();
		mp_list.animateOut();
	}
	else {
		mp_list.visible = false;
		animate_remove(mp_list);
		animate_remove(menu_container);
		menu_container.show();
	}
}
