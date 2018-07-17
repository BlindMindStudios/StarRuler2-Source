import elements.BaseGuiElement;
import elements.GuiDraggable;
import elements.GuiPanel;
import elements.GuiTextbox;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiBackgroundPanel;
import elements.GuiMarkupText;
import elements.GuiResizeHandle;
import elements.MarkupTooltip;
import dialogs.InputDialog;
import version;
#include "dialogs/include/UniqueDialogs.as"

#section gui
from tabs.WikiTab import showWikiPage, openGeneralLink;
void openWiki(const string& link, int button) {
	if(button == 0)
		showWikiPage(link, false);
	else if(button == 2)
		showWikiPage(link, true);
}
#section menu
void openWiki(const string& link, int button) {
	if(button == 0)
		openBrowser(format("http://wiki.starruler2.com/$1", link.replaced(" ", "_")));
}
void openGeneralLink(const string& link, int button = 0) {
	if(link.findFirst(URI_HINT) != -1) {
		if(button == 0)
			openBrowser(link);
	}
	else {
		openWiki(link, button);
	}
}
#section all

const uint SENDER_WIDTH = 110;
const string URI_HINT = "://";
const string LEFT_BRACKET = "[";
const double FLASH_TIME = 1.0;
const array<Color> NICK_COLORS = {
	Color(0x759ca6ff),
	Color(0x8675a6ff),
	Color(0xa87590ff),
	Color(0xa67577ff),
	Color(0x7da675ff),
	Color(0x75a685ff)
};

enum Dialogs {
	D_ChangeNick,
};

class ChangeNick : InputDialogCallback {
	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			string name = dialog.getTextInput(0);
			IRC.nickname = name;

			settings::sNickname = name;
			saveSettings();
		}
	}
};

class LinkableMarkupText : GuiMarkupText {
	LinkableMarkupText(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@tooltipObject = MarkupTooltip(400, 0.f, true, true);
	}

	void onLinkClicked(const string& link, int button) override {
		openGeneralLink(link, button);
	}
};

bool isNickBold(const string& nick) {
	if(nick.length == 0)
		return false;
	return nick == "GGLucas" || nick == "ThyReaper" || nick == "Firgof" || nick == "*" || nick[0] == '@';
}

Color getNickColor(const string& nick) {
	uint8 amt = 0;
	for(uint i = 0, cnt = nick.length; i < cnt; ++i)
		amt += uint8(nick[i]);
	return NICK_COLORS[amt % NICK_COLORS.length];
}

uint missedMessages = 0;
void updateHighlights(IRCChannel@ chan, const string& myNick) {
	Lock lock(chan.mutex);
	uint msgCount = chan.messageCount;
	bool isPM = chan.isPM;
	for(uint i = 0; i < msgCount; ++i) {
		IRCMessageType type = chan.message_types[i];
		if(type == IMT_Action || type == IMT_Message) {
			uint id = chan.message_ids[i];
			if(id > chan.handledId) {
				bool highlight = false;
				if(isPM) {
					highlight = true;
				}
				else {
					string msg = chan.messages[i];
					highlight = msg.contains_nocase(myNick);
				}

				if(highlight) {
					sound::notify.play(priority=true);

					if(window is null || !window.visible)
						ircButton.flash();
					if(window is null || window.activeChannel !is chan)
						chan.highlight = true;
				}
				if(window is null || !window.visible)
					++missedMessages;
				chan.handledId = id;
			}
		}
	}
}

class ChannelDisplay : BaseGuiElement {
	array<string> senders;
	array<string> messages;
	array<LinkableMarkupText@> markups;
	array<bool> nicksBold;
	array<bool> isHighlight;
	array<Color> nickColors;
	string lastChan;
	uint prevId = 0;

	ChannelDisplay(IGuiElement@ parent) {
		super(parent, recti(0, 0, 20, 20));
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() override {
		int w = parent.updatePosition.width;
		if(w >= 720)
			w -= 120;
		size = vec2i(w, max(20, size.height));
		BaseGuiElement::updateAbsolutePosition();
	}

	void update(IRCChannel@ chan) {
		chan.highlight = false;
		uint msgCount = chan.messageCount;
		if(chan.messageId != prevId || msgCount != messages.length || chan.name != lastChan) {
			lastChan = chan.name;
			messages.length = msgCount;
			senders.length = msgCount;
			nicksBold.length = msgCount;
			nickColors.length = msgCount;
			isHighlight.length = msgCount;
			prevId = chan.messageId;
			string myNick = IRC.nickname;

			uint prevMarkups = markups.length;
			for(uint i = msgCount; i < prevMarkups; ++i) {
				if(markups[i] !is null) {
					markups[i].remove();
					@markups[i] = null;
				}
			}
			markups.length = msgCount;

			{
				Lock lock(chan.mutex);
				for(uint i = 0; i < msgCount; ++i) {
					IRCMessageType type = chan.message_types[i];
					string sender = chan.message_senders[i];
					uint8 sender_type = chan.message_sender_types[i];
					uint id = chan.message_ids[i];
					nickColors[i] = getNickColor(sender);
					string msg = chan.messages[i];

					if(type == IMT_Action || type == IMT_Message)
						isHighlight[i] = msg.contains_nocase(myNick);
					else
						isHighlight[i] = false;

					bool needMarkup = msg.findFirst(LEFT_BRACKET) != -1;
					if(sender_type != '@' && sender_type != '+') {
						if(needMarkup)
							msg = bbescape(msg, allowWikiLinks=true);
					}

					switch(type) {
						case IMT_Join:
							senders[i] = "*";
							msg = format(locale::IRC_JOIN, sender, chan.name, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_Part:
							senders[i] = "*";
							msg = format(locale::IRC_PART, sender, chan.name, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_Quit:
							senders[i] = "*";
							msg = format(locale::IRC_QUIT, sender, msg, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_Action:
							senders[i] = "*";
							msg = format(locale::IRC_ACTION, sender, msg, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_Nick:
							senders[i] = "*";
							msg = format(locale::IRC_NICK, sender, msg, toString(nickColors[i]), toString(getNickColor(msg)));
							needMarkup = true;
						break;
						case IMT_Kick:
							senders[i] = "*";
							msg = format(locale::IRC_KICK, sender, msg, toString(nickColors[i]), toString(getNickColor(msg)));
							needMarkup = true;
						break;
						case IMT_Topic:
							senders[i] = "*";
							msg = format(locale::IRC_TOPIC, sender, msg, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_Mode:
							senders[i] = "*";
							msg = format(locale::IRC_MODE, sender, msg, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_UMode:
							senders[i] = "*";
							msg = format(locale::IRC_UMODE, sender, msg, toString(nickColors[i]));
							needMarkup = true;
						break;
						case IMT_TopicIs:
							senders[i] = "*";
							msg = format(locale::IRC_TOPIC_IS, chan.name, msg, toString(nickColors[i]));
						break;
						case IMT_Disconnect:
							senders[i] = "*";
							msg = locale::IRC_DISCONNECT;
							needMarkup = true;
						break;
						default: {
							if(sender_type != ' ') {
								senders[i] = " "+sender;
								senders[i][0] = sender_type;
							}
							else {
								senders[i] = sender;
							}
						} break;
					}

					bool hasLinks = msg.findFirst(URI_HINT) != -1;
					if(hasLinks) {
						msg = makebbLinks(msg);
						needMarkup = true;
					}

					messages[i] = msg;
					nicksBold[i] = isNickBold(senders[i]);

					auto@ elem = markups[i];
					if(needMarkup) {
						if(elem is null) {
							@elem = LinkableMarkupText(this, recti_area(0, 0, size.width-SENDER_WIDTH-27, 20));
							@markups[i] = elem;
						}

						elem.text = msg;
						elem.updateAbsolutePosition();
					}
					else {
						if(elem !is null) {
							elem.remove();
							@markups[i] = null;
						}
					}
				}
			}
		}
	}

	void draw() override {
		const Font@ ft = skin.getFont(FT_Normal);
		const Font@ bold = skin.getFont(FT_Bold);
		recti leftPos = recti_area(AbsolutePosition.topLeft+vec2i(4, 6), vec2i(SENDER_WIDTH, 20));
		recti rightPos = recti_area(AbsolutePosition.topLeft+vec2i(SENDER_WIDTH+13, 7), vec2i(size.width-SENDER_WIDTH-27, 20));

		uint msgCount = messages.length;
		vec2i npos;
		for(uint i = 0; i < msgCount; ++i) {
			if(isHighlight[i])
				drawRectangle(leftPos, Color(0xff888820));
			if(nicksBold[i])
				bold.draw(leftPos, senders[i], locale::ELLIPSIS, nickColors[i], 1.0, 0.5);
			else
				ft.draw(leftPos, senders[i], locale::ELLIPSIS, nickColors[i], 1.0, 0.5);

			auto@ elem = markups[i];
			if(elem is null) {
				npos = ft.draw(rightPos, vec2i(), 20, messages[i], Color(0xffffffff), true);
			}
			else {
				vec2i markupSize = elem.size;
				elem.size = vec2i(size.width-SENDER_WIDTH-27, markupSize.y);
				elem.position = rightPos.topLeft - AbsolutePosition.topLeft - vec2i(0, 1);
				npos = vec2i(rightPos.topLeft.x, rightPos.topLeft.y+markupSize.y);
			}

			int ydiff = npos.y - rightPos.topLeft.y;
			if(npos.x > rightPos.topLeft.x)
				ydiff += 20;

			leftPos += vec2i(0, ydiff);
			rightPos += vec2i(0, ydiff);
		}

		int needHeight = max(rightPos.topLeft.y - AbsolutePosition.topLeft.y, 20);
		if(size.height != needHeight) {
			size = vec2i(parent.updatePosition.width, needHeight);

			//Hax
			GuiPanel@ par = cast<GuiPanel>(parent);
			bool wasBottom = par.vert.pos >= (par.vert.end - par.vert.page);
			par.updateAbsolutePosition();
			if(wasBottom) {
				par.vert.pos = max(0.0, par.vert.end - par.vert.page);
				par.updateAbsolutePosition();
			}
		}

		BaseGuiElement::draw();
	}
};

class ChanButton : GuiButton {
	IRCChannel@ channel;

	ChanButton(IGuiElement@ parent) {
		super(parent, recti());
	}
};

class IRCInput : GuiTextbox {
	IRCWindow@ window;

	IRCInput(IRCWindow@ win, Alignment@ align) {
		@window = win;
		super(win, align);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(event.type == KET_Key_Down) {
			if(event.key == KEY_TAB) {
				return true;
			}
		}
		else if(event.type == KET_Key_Up) {
			if(event.key == KEY_TAB) {
				tabComplete();
				return true;
			}
		}
		return GuiTextbox::onKeyEvent(event, source);
	}

	void tabComplete() {
		if(Text.length == 0)
			return;

		//Get word before cursor
		string before;
		IRCChannel@ chan = window.activeChannel;

		int pos = curs-1;
		for(; pos > 0; --pos) {
			if(Text[pos] == ' ') {
				++pos;
				break;
			}
		}
		if(pos >= 0 && pos < curs)
			before = Text.substr(pos, curs-pos);
		else if(pos > 0)
			return;

		//Find nickname in opposite direction of use.
		string found;
		for(int i = window.disp.senders.length - 1; i >= 0; --i) {
			string compare = window.disp.senders[i].substr(1);
			if((before.length == 0 || compare.startswith_nocase(before))
				&& compare.length > 1) {
				found = compare;
				break;
			}
		}

		//No nickname found, try user list
		if(found.length == 0) {
			for(uint i = 0, cnt = window.activeUsers.length; i < cnt; ++i) {
				string compare = window.activeUsers[i].substr(1);
				if(compare.startswith_nocase(before)) {
					found = compare;
					break;
				}
			}
		}

		//Append to textbox
		if(found.length != 0) {
			if(pos > 0)
				Text = Text.substr(0, pos);
			else
				Text = "";
			Text += found;
			if(pos <= 0)
				Text += ": ";
			else
				Text += " ";

			curs = Text.length;
		}
	}

	void remove() {
		@window = null;
		GuiTextbox::remove();
	}
}

class IRCWindow : GuiDraggable {
	GuiBackgroundPanel@ bg;
	GuiPanel@ panel;
	ChannelDisplay@ disp;
	GuiTextbox@ messageBox;
	GuiButton@ nickButton;
	GuiButton@ closeButton;
	GuiResizeHandle@ handle;

	BaseGuiElement@ chanList;
	array<ChanButton@> chanButtons;

	IRCChannel@ activeChannel;
	array<string> activeUsers;
	array<string> userMarks;
	array<string> usersCut;
	array<Color> userColors;
	array<bool> usersBold;

	GuiSkinElement@ userBG;
	GuiPanel@ userPanel;
	BaseGuiElement@ userList;
	string prevUsers;

	IRCWindow() {
		super(null, IRC.display);
		visible = IRC.display.width != 0;

		@bg = GuiBackgroundPanel(this, Alignment_Fill());
		bg.titleColor = Color(0xb3fe00ff);

		@handle = GuiResizeHandle(this, Alignment(Right-12, Bottom-12, Right, Bottom));
		handle.minSize = vec2i(450, 200);

		@nickButton = GuiButton(bg, Alignment(Right-185, Top+3, Right-33, Top+28));
		nickButton.visible = false;

		@closeButton = GuiButton(bg, Alignment(Right-31, Top+3, Right-5, Top+28), "X");

		@panel = GuiPanel(this, Alignment(Left+10, Top+32, Right-10, Bottom-44));

		@chanList = BaseGuiElement(this, Alignment(Left+10, Bottom-70, Right-10, Bottom-44));
		chanList.visible = false;

		@disp = ChannelDisplay(panel);

		@messageBox = IRCInput(this, Alignment(Left+10, Bottom-40, Right-10, Bottom-10));

		@userBG = GuiSkinElement(this, Alignment(Right-150, Top+34, Right-10, Bottom-44), SS_LightPanel);
		@userPanel = GuiPanel(userBG, Alignment().fill());
		userPanel.horizType = ST_Never;
		@userList = BaseGuiElement(userPanel, recti(0, 0, 140, 20));

		userBG.visible = false;

		updateAbsolutePosition();
	}

	void remove() override {
		GuiDraggable::remove();
	}

	void updateAbsolutePosition() {
		if(panel !is null) {
			bool showUsers = size.width >= 750 && (activeChannel !is null && !activeChannel.isPM);
			if(showUsers) {
				panel.alignment.right.pixels = 160;
				userBG.visible = true;
			}
			else {
				panel.alignment.right.pixels = 10;
				userBG.visible = false;
			}
		}

		GuiDraggable::updateAbsolutePosition();
	}

	void updateUsers() {
		if(activeChannel is null)
			return;

		activeChannel.getUsers(activeUsers);
		activeUsers.sortDesc();
		uint userCnt = activeUsers.length;

		usersCut.length = userCnt;
		userMarks.length = userCnt;
		usersBold.length = userCnt;
		userColors.length = userCnt;
		for(uint i = 0; i < userCnt; ++i) {
			usersCut[i] = activeUsers[i].substr(1);
			userMarks[i] = activeUsers[i].substr(0, 1);
			usersBold[i] = isNickBold(activeUsers[i]);
			userColors[i] = getNickColor(usersCut[i]);
		}

		int h = userCnt * 24;
		if(h != userList.size.height) {
			userList.size = vec2i(140, h);
			userPanel.updateAbsolutePosition();
		}
	}

	void draw() {
		GuiDraggable::draw();

		if(userBG.visible) {
			const Font@ font = skin.getFont(FT_Normal);
			vec2i pos = userList.AbsolutePosition.topLeft + vec2i(6, 6);
			int start = userBG.absolutePosition.topLeft.y;
			int end = userBG.absolutePosition.botRight.y;
			setClip(userBG.absoluteClipRect);
			int w = 130;
			if(userPanel.vert.visible)
				w -= 20;
			for(uint i = 0, cnt = activeUsers.length; i < cnt; ++i) {
				if(pos.y < start - 20 || pos.y > end) {
					pos.y += 20;
					continue;
				}

				Color col = userColors[i];
				const Font@ ft = font;
				if(usersBold[i] && ft.bold !is null)
					@ft = ft.bold;

				ft.draw(pos=recti_area(pos, vec2i(14, 20)),
					text=userMarks[i], color=col,
					ellipsis=locale::SHORT_ELLIPSIS, horizAlign=1.0);
				ft.draw(pos=recti_area(pos+vec2i(15,0), vec2i(w-15, 20)),
						text=usersCut[i], ellipsis=locale::ELLIPSIS, color=col);
				pos.y += 20;
			}
		}
	}

	void update(double time) {
		if(visible) {
			IRC.display = rect;
			prevSize = rect;
			missedMessages = 0;
		}
		else {
			IRC.display = recti();
		}

		if(!IRC.connected)
			return;

		if(IRC.channelCount == 0) {
			IRC.join("#starruler");
			return;
		}

		if(activeChannel is null || activeChannel.closed)
			setActiveChannel(IRC.channels[0]);

		Lock lock(IRC.mutex);

		if(visible) {
			//Update window elements
			if(activeChannel !is null)
				bg.title = activeChannel.topic;
			nickButton.text = format(locale::IRC_NICKNAME, IRC.nickname);
			nickButton.visible = true;

			//Update the active channel
			if(activeChannel.messageId != disp.prevId || activeChannel.getUserCount() != activeUsers.length)
				updateUsers();
			disp.update(activeChannel);

			//Update the channel list buttons
			uint chanCnt = IRC.channelCount;
			if(chanCnt > 1) {
				chanList.visible = true;
				panel.alignment.bottom.pixels = 74;

				uint oldCnt = chanButtons.length;
				uint newCnt = chanCnt;

				for(uint i = newCnt; i < oldCnt; ++i)
					chanButtons[i].remove();
				chanButtons.length = newCnt;
				for(uint i = oldCnt; i < newCnt; ++i) {
					@chanButtons[i] = ChanButton(chanList);
					chanButtons[i].toggleButton = true;
				}

				int x = 0;
				int h = chanList.size.height;
				int w = chanList.size.width;
				if(userBG.visible)
					w -= 150;
				w = min(160, w / chanCnt);
				for(uint i = 0; i < chanCnt; ++i) {
					IRCChannel@ chan = IRC.channels[i];
					@chanButtons[i].channel = chan;
					chanButtons[i].text = chan.name;
					chanButtons[i].pressed = chan is activeChannel;

					if(chan.highlight)
						chanButtons[i].color = Color(0xff8000ff);
					else
						chanButtons[i].color = Color(0xffffffff);

					chanButtons[i].size = vec2i(w, h);
					chanButtons[i].position = vec2i(x, 0);
					x += w;
				}
			}
			else {
				chanList.visible = false;
				panel.alignment.bottom.pixels = 44;

				uint oldCnt = chanButtons.length;
				for(uint i = 0; i < oldCnt; ++i)
					chanButtons[i].remove();
				chanButtons.length = 0;
			}
		}

		//Update highlights
		{
			string myNick = IRC.nickname;
			uint chanCnt = IRC.channelCount;
			for(uint i = 0; i < chanCnt; ++i)
				updateHighlights(IRC.channels[i], myNick);
		}
	}

	void promptNickChange() {
		if(focusDialog(D_ChangeNick))
			return;

		InputDialog@ dialog = InputDialog(ChangeNick(), this);
		dialog.accept.text = locale::CHANGE_NICK;
		dialog.addTextInput(locale::NICKNAME, IRC.nickname);

		addDialog(D_ChangeNick, dialog);
		dialog.focusInput();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case MET_Button_Up:
				if(handle.dragging)
					handle.dragging = false;
				setGuiFocus(messageBox);
			break;
		}
		return GuiDraggable::onMouseEvent(event, source);
	}

	void setActiveChannel(IRCChannel@ chan) {
		@activeChannel = chan;
		bool showUsers = size.width >= 750 && (chan !is null && !chan.isPM);
		if(showUsers != userBG.visible)
			updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is messageBox) {
			if(evt.type == GUI_Confirmed) {
				if(activeChannel is null)
					return true;

				IRC.send(activeChannel, messageBox.text);
				messageBox.clear();
				return true;
			}
		}
		else if(evt.caller is closeButton) {
			if(evt.type == GUI_Clicked) {
				visible = false;
				return true;
			}
		}
		else if(evt.caller is nickButton) {
			if(evt.type == GUI_Clicked) {
				promptNickChange();
				return true;
			}
		}
		else if(evt.type == GUI_Clicked) {
			ChanButton@ but = cast<ChanButton>(evt.caller);
			if(but !is null)
				setActiveChannel(but.channel);
		}
		return GuiDraggable::onGuiEvent(evt);
	}
};

IRCWindow@ window;
IRCButton@ ircButton;
recti prevSize;

void openIRC() {
	IRC.display = recti_centered(recti(vec2i(0, 0), screenSize), vec2i(750, 500));
	if(window is null)
		@window = IRCWindow();
}

void closeIRC() {
	if(window !is null)
		window.visible = false;
	IRC.display = recti();
}

void showIRC() {
	if(!IRC.running) {
		IRC.nickname = settings::sNickname;
		IRC.connect();
		openIRC();
	}
	else {
		if(window is null) {
			openIRC();
		}
		else {
			window.visible = !window.visible;
			if(!window.visible) {
				IRC.display = recti();
			}
			else if(IRC.display.width == 0) {
				if(prevSize.width != 0)
					IRC.display = prevSize;
				else
					IRC.display = recti_centered(recti(vec2i(0, 0), screenSize), vec2i(750, 500));
				window.rect = IRC.display;
			}
		}
	}
}

class IRCButtonEvent : onButtonClick {
	bool onClick(GuiButton@ btn) {
		ircButton.flashes = 0;
		IRC.highlight = false;

		if(window is null) {
			openIRC();
		}
		else {
			window.visible = !window.visible;
			if(!window.visible) {
				IRC.display = recti();
			}
			else if(IRC.display.width == 0) {
				if(prevSize.width != 0)
					IRC.display = prevSize;
				else
					IRC.display = recti_centered(recti(vec2i(0, 0), screenSize), vec2i(750, 500));
				window.rect = IRC.display;
			}
		}
		return true;
	}
};

class ChangeNickCommand : ConsoleCommand {
	void execute(const string& args) {
		string name = args;
		IRC.nickname = name;

		settings::sNickname = name;
		saveSettings();
	}
};

class IRCButton : GuiButton {
	int flashes = 0;
	double flashTime = 0;
	GuiText@ missed;

	IRCButton(Alignment@ align) {
		super(null, align);
		spriteStyle = Sprite(material::IRCButton);
		visible = false;

		@missed = GuiText(this, Alignment().padded(4));
		missed.horizAlign = 1.0;
		missed.vertAlign = 0.6;
		missed.stroke = colors::Black;
		missed.color = Color(0xff8000ff);
		missed.font = FT_Bold;
	}

	void flash() {
		flashes += 3;
		IRC.highlight = true;
	}

	void draw() {
		//Show flashes
		if(flashTime > 0.0) {
			float pct = 0.f;
			if(flashTime < FLASH_TIME * 0.5)
				pct = 1.f - (FLASH_TIME * 0.5 - flashTime) / (FLASH_TIME * 0.5);
			else
				pct = 1.f - (flashTime - FLASH_TIME * 0.5) / (FLASH_TIME * 0.5);

			color = Color(0xffaaaaff).interpolate(Color(0xff8000ff), pct);
			flashTime -= frameLength;
		}
		else {
			if(flashes > 0) {
				--flashes;
				flashTime = FLASH_TIME;
			}

			if(IRC.highlight)
				color = Color(0xffaaaaff);
			else
				color = colors::White;
		}

		if(missedMessages != 0) {
			missed.text = toString(missedMessages);
			missed.visible = true;
		}
		else {
			missed.visible = false;
		}

		GuiButton::draw();
	}
};

void init() {
#section game
	@ircButton = IRCButton(Alignment(Right-32, Top+20, Width=32, Height=64));

#section menu
	@ircButton = IRCButton(Alignment(Right-32, Top+100, Width=32, Height=64));

	setNickname(settings::sNickname);
	addConsoleCommand("nick", ChangeNickCommand());

	string ver = SCRIPT_VERSION;
	int pos = ver.findLast(" ");
	if(pos != -1)
		ver = ver.substr(pos+1);
	IRC_HOSTNAME = "SR2"+ArchName+ArchBits+ver;
	if(cloud::isActive)
		IRC_HOSTNAME += "S";
	if(!IS_STEAM_BUILD)
		IRC_HOSTNAME += "G";
	if(hasDLC("Heralds"))
		IRC_HOSTNAME += "H";
#section all

	@ircButton.onClick = IRCButtonEvent();
}

void onGameStateChange() {
	if(window !is null) {
		if(IRC.display.width == 0) {
			window.visible = false;
		}
		else {
			window.rect = IRC.display;
			window.visible = true;
		}
		window.update(1.0);
	}
}

void tick(double time) {
#section menu
	if(game_state != GS_Menu)
		return;
#section gui
	if(game_state != GS_Game)
		return;
#section all

	if(IRC.running) {
		if(!ircButton.visible) {
			ircButton.visible = true;

			if(window is null)
				@window = IRCWindow();
		}
		ircButton.bringToFront();
	}
	else {
		if(ircButton.visible)
			ircButton.visible = false;
		if(window !is null && window.visible)
			window.visible = false;
	}

	if(window !is null)
		window.update(time);
}
