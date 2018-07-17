import dialogs.MessageDialog;
import dialogs.InputDialog;
import dialogs.Dialog;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiPanel;
import elements.GuiBackgroundPanel;
import elements.GuiTextbox;
import elements.GuiResizeHandle;
import influence;

class PlayEmpireDialog : Dialog {
	GuiButton@[] buttons;
	Empire@[] empires;

	PlayEmpireDialog() {
		super(null);

		addTitle(locale::PLAY_EMPIRE_TITLE, closeButton=false);

		height = 32;

		//Empires
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major)
				continue;

			GuiText text(window, recti(12, height, width-212, height+30));
			text.text = emp.name;
			text.color = emp.color;
			text.font = FT_Subtitle;

			GuiButton btn(window, recti(width-200, height, width-12, height+30));
			btn.text = locale::PLAY_EMPIRE;
			btn.color = emp.color;
			buttons.insertLast(btn);
			empires.insertLast(emp);
			height += 34;
		}

		//Spectating
		{
			GuiButton btn(window, recti(width-200, height, width-12, height+30));
			btn.text = locale::SPECTATE;
			buttons.insertLast(btn);
			empires.insertLast(null);
			height += 34;
		}

		height += 12;

		updatePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked) {
			for(uint i = 0, cnt = buttons.length(); i < cnt; ++i) {
				if(buttons[i] is cast<GuiButton@>(event.caller)) {
					Empire@ emp = empires[i];
					if(emp is null) {
						close();
						playAsEmpire(spectatorEmpire);
						wantSpectator = true;
					}
					else {
						playAsEmpire(emp);
						wantSpectator = false;
					}
					if(chooseOpen) {
						chooseOpen = false;
						close();
					}
					return true;
				}
			}
		}
		return Dialog::onGuiEvent(event);
	}
};

class PlayEmpire : ConsoleCommand {
	void execute(const string& args) {
		int id = toInt(args);
		Empire@ emp;
		if(id == -1)
			@emp = spectatorEmpire;
		else
			@emp = getEmpireByID(id);
		if(emp !is null)
			playAsEmpire(emp);
		else
			throw("Invalid empire id: "+args);
	}
}

void change_emp(bool pressed) {
	chooseOpen = true;
	wantSpectator = false;
	if(dialog is null || dialog.Closed) {
		@dialog = PlayEmpireDialog();
		addDialog(dialog);
	}
}

bool wasMPClient = false;
bool wantSpectator = false;
bool chooseOpen = false;
Dialog@ dialog;
MPChatWindow@ mpChatWin;
void init() {
	if(mpClient) {
		addConsoleCommand("play_emp", PlayEmpire());
		wasMPClient = true;
	}
	if(mpClient || mpServer)
		@mpChatWin = MPChatWindow();
	keybinds::Global.addBind(KB_CHANGE_EMPIRE, "change_emp");
	keybinds::Global.addBind(KB_MP_CHAT, "mp_chat");
}

void tick(double time) {
	if(wasMPClient && !mpIsConnected()) {
		message("Lost connection to server:\n    "
				+localize("DISCONNECT_"+uint(mpDisconnectReason)));
		wasMPClient = false;
	}

	if(mpClient) {
		if(dialog is null || dialog.Closed) {
			if(playerEmpire is spectatorEmpire && !wantSpectator) {
				@dialog = PlayEmpireDialog();
				addDialog(dialog);
			}
		}
		else if(!chooseOpen) {
			if(playerEmpire !is spectatorEmpire || wantSpectator) {
				dialog.close();
				@dialog = null;
			}
		}
	}

	if(mpChatWin !is null)
		mpChatWin.tick(time);
}

class MPChatWindow : GuiDraggable {
	GuiBackgroundPanel@ bg;
	GuiPanel@ panel;
	GuiMarkupText@ log;
	GuiTextbox@ input;
	GuiResizeHandle@ handle;
	GuiButton@ closeButton;

	GuiDropdown@ mode;
	array<uint> modeMasks;

	array<string> messages;

	Mutex mtx;
	array<string> waitingMessages;

	MPChatWindow() {
		super(null, recti_area(vec2i(screenSize.width - 412, 200), vec2i(400, 200)));
		@bg = GuiBackgroundPanel(this, Alignment_Fill());
		bg.title = locale::CHAT;
		bg.titleColor = Color(0xb3fe00ff);

		@closeButton = GuiButton(bg, Alignment(Right-31, Top+3, Right-5, Top+28), "X");
		closeButton.color = colors::Red;

		@handle = GuiResizeHandle(this, Alignment(Right-12, Bottom-12, Right, Bottom));
		handle.minSize = vec2i(200, 100);

		@panel = GuiPanel(bg, Alignment(Left+7, Top+34, Right-8, Bottom-38));
		@log = GuiMarkupText(panel, recti_area(0, 0, 100, 100));
		@input = GuiTextbox(bg, Alignment(Left+6, Bottom-36, Right-136, Bottom-6));

		@mode = GuiDropdown(bg, Alignment(Right-133, Bottom-36, Right-6, Bottom-6));

		log.text = locale::MP_CHAT_INTRO;

		updateMode();
		updateAbsolutePosition();
	}

	array<Treaty> treaties;
	void updateMode() {
		string prev;
		if(uint(mode.selected) < mode.itemCount)
			prev = mode.getItemElement(mode.selected).get();

		modeMasks.length = 0;
		uint ind = 0;

		mode.setItem(ind++, locale::MP_CHAT_ALL);
		modeMasks.insertLast(0xffffffff);

		mode.setItem(ind++, locale::MP_CHAT_ALLIES);
		modeMasks.insertLast(playerEmpire.mask);

		mode.setItem(ind++, locale::MP_CHAT_PEACE);
		modeMasks.insertLast(playerEmpire.mask);

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			auto@ other = getEmpire(i);
			if(other is playerEmpire)
				continue;
			if(!other.major)
				continue;

			if(playerEmpire.ForcedPeaceMask & other.mask != 0)
				modeMasks[1] |= other.mask;
			if(!playerEmpire.isHostile(other))
				modeMasks[2] |= other.mask;

			mode.setItem(ind++, format(locale::MP_CHAT_TO, other.name));
			modeMasks.insertLast(other.mask | playerEmpire.mask);
		}

		treaties.syncFrom(getActiveTreaties());
		for(uint i = 0, cnt = treaties.length; i < cnt; ++i) {
			auto@ treaty = treaties[i];
			mode.setItem(ind++, format(locale::MP_CHAT_TO, treaty.name));
			modeMasks.insertLast(treaty.presentMask | playerEmpire.mask);
		}

		mode.removeItemsFrom(ind);

		mode.selected = 0;
		for(uint i = 0, cnt = modeMasks.length; i < cnt; ++i) {
			if(mode.getItemElement(i).get() == prev) {
				mode.selected = i;
				break;
			}
		}
	}

	double timer = 0;
	void tick(double time) {
		Lock lck(mtx);
		for(uint i = 0, cnt = waitingMessages.length; i < cnt; ++i)
			addChat(waitingMessages[i]);
		if(waitingMessages.length != 0 && !visible)
			visible = true;
		waitingMessages.length = 0;

		timer -= time;
		if(timer <= 0.0) {
			updateMode();
			timer = 1.0;
		}
	}

	void addChat(const string& str) {
		messages.insertLast(str);
		if(messages.length > 80)
			messages.removeAt(0);
		string content;
		for(uint i = 0, cnt = messages.length; i < cnt; ++i)
			content += messages[i]+"\n";
		bool wasBottom = panel.vert.pos >= (panel.vert.end - panel.vert.page);
		log.text = content;
		panel.updateAbsolutePosition();
		if(wasBottom) {
			panel.vert.pos = max(0.0, panel.vert.end - panel.vert.page);
			panel.updateAbsolutePosition();
		}
	}

	void queueMessage(const string& str) {
		Lock lck(mtx);
		waitingMessages.insertLast(str);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is input) {
			if(evt.type == GUI_Confirmed) {
				string text = input.text;
				if(text.length != 0) {
					if(mode.selected == 0 || uint(mode.selected) >= modeMasks.length) {
						mpChat(text);
					}
					else {
						uint mask = modeMasks[mode.selected];
						string spec = mode.getItemElement(mode.selected).get();
						mpChat(text, mask, spec);
					}
				}
				input.text = "";
				return true;
			}
		}
		else if(evt.caller is closeButton) {
			if(evt.type == GUI_Clicked) {
				visible = false;
				return true;
			}
		}
		return GuiDraggable::onGuiEvent(evt);
	}

	void updateAbsolutePosition() override {
		GuiDraggable::updateAbsolutePosition();
		if(log !is null)
			log.size = vec2i(panel.size.width-20, log.size.height);
	}
};

void mp_chat(bool pressed) {
	if(!pressed && (mpClient || mpServer)) {
		if(mpChatWin is null)
			@mpChatWin = MPChatWindow();
		mpChatWin.visible = true;
		mpChatWin.bringToFront();
		setGuiFocus(mpChatWin.input);
	}
}

void chatMessage(string text) {
	if(mpChatWin !is null)
		mpChatWin.queueMessage(text);
}
