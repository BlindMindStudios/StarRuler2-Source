import tabs.Tab;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiEmpire;
import elements.GuiPanel;
import elements.GuiSprite;
import elements.GuiSpinbox;
import elements.GuiTextbox;
import elements.GuiSkinElement;
import elements.GuiOverlay;
import elements.GuiInfluenceCard;
import elements.GuiProgressbar;
import elements.GuiBackgroundPanel;
import elements.GuiOfferList;
import elements.GuiIconGrid;
import elements.MarkupTooltip;
import dialogs.Dialog;
import dialogs.QuestionDialog;
import dialogs.InputDialog;
#include "dialogs/include/UniqueDialogs.as"
import icons;
import influence;
import util.formatting;
import hooks;
import void zoomTo(Object@) from "tabs.GalaxyTab";

from tabs.tabbar import popTab, ActiveTab, browseTab;
import Tab@ createDiplomacyTab() from "tabs.DiplomacyTab";

const float PARLIAMENT_HEIGHT = 0.55f;

const int DELEGATION_WIDTH = 140;
const int DELEGATION_HEIGHT = 100;
const double UPDATE_TIMER = 0.5;

enum DialogIDs {
	D_PlayCard,
};

class LeaveCallback : QuestionDialogCallback {
	int voteId;
	LeaveCallback(int id) {
		voteId = id;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			leaveInfluenceVote(voteId);
	}
};

class WithdrawCallback : QuestionDialogCallback {
	int voteId;
	WithdrawCallback(int id) {
		voteId = id;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			withdrawInfluenceVote(voteId);
	}
};

class LogEntry : GuiMarkupText {
	InfluenceVoteEvent@ evt;
	bool Hover = false;;

	LogEntry(IGuiElement@ parent, const recti& area) {
		super(parent, area);
		addLazyMarkupTooltip(this, width=400);
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hover = true;
				break;
				case GUI_Mouse_Left:
					Hover = false;
				break;
			}
		}
		return GuiMarkupText::onGuiEvent(event);
	}

	bool get_hasTip() {
		return evt.cardEvent !is null;
	}
	
	string get_tooltip() {
		if(evt.cardEvent !is null)
			return evt.cardEvent.card.formatTooltip(showUses=false);
		return "";
	}

	void draw() {
		if(Hover && hasTip) {
			clipParent();
			drawRectangle(AbsolutePosition.padded(-2), Color(0xffffff10));
			resetClip();
		}
		GuiMarkupText::draw();
	}
};

class EffectButton : GuiButton {
	InfluenceCard card;

	EffectButton(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	void draw() {
		GuiButton::draw();

		auto@ ft = skin.getFont(FT_Normal);
		if(ft.getDimension(card.type.name).x > AbsolutePosition.width)
			@ft = skin.getFont(FT_Small);
		ft.draw(pos=AbsolutePosition, horizAlign=0.5, vertAlign=0.5, text=card.type.name, color=color, stroke=colors::Black);
	}
};

class OfferDialog : Dialog {
	GuiMarkupText@ description;
	GuiOfferList@ offer;
	GuiButton@ accept;
	GuiButton@ cancel;
	GuiText@ supportLabel;
	GuiSpinbox@ supportBox;
	bool side;
	int voteId;

	OfferDialog(IGuiElement@ bind, bool support, int voteId) {
		super(bind, bindInside=true);
		width = 600;
		height = 500;
		this.voteId = voteId;
		side = support;

		@accept = GuiButton(bg, recti());
		accept.text = locale::OFFER;
		accept.tabIndex = 100;
		accept.disabled = true;
		@accept.callback = this;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;

		@description = GuiMarkupText(window, Alignment(Left+12, Top+32, Right-12, Top+58));

		@supportLabel = GuiText(window, Alignment(Left+12, Top+58, Left+250, Height=34));
		supportLabel.font = FT_Bold;
		@supportBox = GuiSpinbox(window, Alignment(Left+250, Top+58, Right-12, Height=34),
				num=3, min=1, max=100, step=1, decimals=0);
		supportBox.font = FT_Subtitle;

		if(support) {
			addTitle(locale::OFFER_FOR_TITLE, color=colors::Green);
			description.text = locale::OFFER_FOR_TEXT;
			accept.color = Color(0xaaffaaff);
			supportLabel.text = locale::OFFER_REQ_SUPPORT;
		}
		else {
			addTitle(locale::OFFER_AGAINST_TITLE, color=colors::Red);
			description.text = locale::OFFER_AGAINST_TEXT;
			accept.color = Color(0xffaaaaff);
			supportLabel.text = locale::OFFER_REQ_OPPOSE;
		}

		alignAcceptButtons(accept, cancel);
		@offer = GuiOfferList(window, Alignment(Left+4, Top+98, Right-4, Bottom-40));

		updatePosition();
	}

	void update() {
		bool canOffer = offer.offers.length != 0;
		for(uint i = 0, cnt = offer.offers.length; i < cnt; ++i) {
			if(!offer.offers[i].offer.canOffer(playerEmpire)) {
				canOffer = false;
				break;
			}
		}
		accept.disabled = !canOffer;
	}

	void close() {
		close(false);
	}

	void close(bool accepted) {
		if(accepted) {
			InfluenceVoteOffer off;
			off.side = side;
			offer.apply(off.offers);
			off.support = supportBox.value;
			makeInfluenceVoteOffer(voteId, off);
		}
		Dialog::close();
	}

	void confirmDialog() {
		close(true);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked && (event.caller is accept || event.caller is cancel)) {
			close(event.caller is accept);
			return true;
		}
		if(event.type == GUI_Changed) {
			update();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

class OfferDisplay : BaseGuiElement {
	uint voteId;
	InfluenceVoteOffer offer;
	GuiOfferGrid@ grid;
	GuiButton@ button;
	GuiMarkupText@ btnText;

	OfferDisplay(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@grid = GuiOfferGrid(this, recti());
		@button = GuiButton(this, recti_area(0,0, 100, 30));
		@btnText = GuiMarkupText(button, Alignment().padded(4,5, 0,0));
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		if(button !is null) {
			grid.size = vec2i(size.width, ceil(double(offer.offers.length)/3.0)*40);
			grid.position = vec2i(0, 4);
			size = vec2i(size.width, grid.size.height+45);
			button.rect = recti_area(4, size.height-38, size.width-8, 34);
		}
	}

	void update(InfluenceVoteOffer@ input, uint voteId) {
		offer = input;
		this.voteId = voteId;

		int claim = 0;
		if(playerEmpire !is null && playerEmpire.valid)
			claim = offer.claims[playerEmpire.index];

		btnText.text = format(
				offer.side ? locale::OFFER_FOR_BTN : locale::OFFER_AGAINST_BTN,
				formatEmpireName(offer.fromEmpire),
				toString(offer.support),
				playerEmpire is offer.fromEmpire ? "--" : toString(claim));
		@grid.list = offer.offers;

		if(claim >= offer.support && playerEmpire !is offer.fromEmpire) {
			button.disabled = false;
			if(offer.side)
				button.color = colors::Green;
			else
				button.color = colors::Red;
		}
		else {
			button.disabled = true;
			button.color = colors::White;
		}

		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is button) {
			claimInfluenceVoteOffer(voteId, offer.id);
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_PatternBox, SF_Normal, AbsolutePosition, offer.fromEmpire.color);
		BaseGuiElement::draw();
	}
};

class InfluenceVoteTab : Tab {
	InfluenceVote vote;

	GuiBackgroundPanel@ senateBG;
	DelegationBox@[] boxes;
	GuiPanel@ parliamentPanel;
	GuiSprite@ senateImage;
	GuiSkinElement@ titleBG;
	GuiMarkupText@ titleBox;

	GuiPanel@ cardPanel;
	InfluenceCard@[] cards;
	GuiInfluenceCard@[] cardBoxes;

	GuiBackgroundPanel@ logBG;
	GuiPanel@ logPanel;
	array<LogEntry@> logs;

	GuiProgressbar@ forBar;
	GuiProgressbar@ againstBar;

	GuiBackgroundPanel@ cardBG;
	GuiText@ messageLabel;
	GuiTextbox@ messageBox;
	GuiButton@ sendButton;

	GuiButton@ backButton;
	GuiButton@ leaveButton;
	GuiButton@ withdrawButton;

	GuiSkinElement@ votingBox;
	GuiText@ timerBox;

	GuiSkinElement@ yeaBG;
	GuiText@ yeaBox;

	GuiSkinElement@ nayBG;
	GuiText@ nayBox;

	GuiSkinElement@ totalBG;
	GuiText@ totalBox;
	GuiSprite@ totalPic;

	GuiInfluenceCard@ startCard;
	GuiSprite@ voteDesc;
	GuiButton@ zoomButton;

	GuiButton@ offerFor;
	GuiButton@ offerAgainst;

	GuiPanel@ forOfferPanel;
	array<OfferDisplay@> forOffers;
	GuiPanel@ againstOfferPanel;
	array<OfferDisplay@> againstOffers;

	int lastLog = -1;
	int lastEffects = -1;
	string plainTitle;

	InfluenceVoteTab() {
		super();

		//Create empire delegation boxes
		@senateBG = GuiBackgroundPanel(this, Alignment(Left+8, Top+8, Right-8, Top+PARLIAMENT_HEIGHT));
		@titleBG = GuiSkinElement(senateBG, Alignment(Left, Top, Right, Top+50), SS_FullTitle);
		@titleBox = GuiMarkupText(senateBG, Alignment(Left+4, Top+2, Right-4, Top+44));
		titleBox.defaultFont = FT_Big;

		//Heading
		@votingBox = GuiSkinElement(this, Alignment(Left+0.5f-320, Top+57, Left+0.5f+320, Height=43), SS_VotingBox);
		@timerBox = GuiText(votingBox, Alignment(Left+0.5f-50, Top, Width=100, Height=43));
		timerBox.horizAlign = 0.5;
		timerBox.vertAlign = 0.5;
		timerBox.font = FT_Medium;

		@againstBar = GuiProgressbar(votingBox, Alignment(Left+47, Top+6, Left+0.5f-50, Bottom-6));
		againstBar.invert = true;
		againstBar.backColor = Color(0xffffff40);
		againstBar.frontColor = Color(0xff0000ff);
		setMarkupTooltip(againstBar, locale::INFLUENCE_TT_FAIL);

		@forBar = GuiProgressbar(votingBox, Alignment(Left+0.5f+50, Top+6, Right-47, Bottom-6));
		forBar.backColor = Color(0xffffff40);
		forBar.frontColor = Color(0x00ff00ff);
		setMarkupTooltip(forBar, locale::INFLUENCE_TT_PASS);

		GuiSprite failIcon(votingBox, Alignment(Left+2, Top+2, Left+43, Bottom-2), Sprite(spritesheet::VoteIcons, 6));
		setMarkupTooltip(failIcon, locale::INFLUENCE_TT_FAIL);
		GuiSprite passIcon(votingBox, Alignment(Right-43, Top+2, Right-2, Bottom-2), Sprite(spritesheet::CardCategoryIcons, 4));
		setMarkupTooltip(passIcon, locale::INFLUENCE_TT_PASS);

		//Vote totals
		@totalBG = GuiSkinElement(this, Alignment(Left+0.5f-60, Top+97, Left+0.5f+60, Height=40), SS_VoteTotal);
		@totalBox = GuiText(totalBG, recti(0, 0, 120, 40));
		totalBox.font = FT_Big;

		@totalPic = GuiSprite(totalBG, recti(8, 8, 32, 32));

		@yeaBG = GuiSkinElement(this, Alignment(Left+0.5f+59, Top+99, Left+0.5f+184, Height=36), SS_VoteTotal);
		@yeaBox = GuiText(yeaBG, Alignment_Fill());
		yeaBox.font = FT_Medium;
		yeaBox.horizAlign = 0.5;
		yeaBox.color = Color(0x00ff00ff);

		@nayBG = GuiSkinElement(this, Alignment(Left+0.5f-184, Top+99, Left+0.5f-59, Height=36), SS_VoteTotal);
		@nayBox = GuiText(nayBG, Alignment_Fill());
		nayBox.font = FT_Medium;
		nayBox.horizAlign = 0.5;
		nayBox.color = Color(0xff0000ff);

		//Senate floor
		@senateImage = GuiSprite(senateBG, Alignment(Left+4, Top+72, Right-4, Bottom-4));
		senateImage.color = Color(0xffffff80);
		senateImage.desc = Sprite(material::SenateBG);
		@parliamentPanel = GuiPanel(senateBG, Alignment(Left+216, Top+95, Right-216, Bottom-4));

		@startCard = GuiInfluenceCard(parliamentPanel);
		@startCard.alignment = Alignment(
				Left+0.5f-(GUI_CARD_WIDTH/2),
				Top+0.5f-(GUI_CARD_HEIGHT/2),
				Width=GUI_CARD_WIDTH, Height=GUI_CARD_HEIGHT);
		startCard.visible = false;

		@voteDesc = GuiSprite(parliamentPanel, startCard.alignment);
		voteDesc.visible = false;

		@zoomButton = GuiButton(parliamentPanel, Alignment(Left+0.5f-(GUI_CARD_WIDTH/2), Top+0.5f+(GUI_CARD_HEIGHT/2)+6, Width=GUI_CARD_WIDTH, Height=40));
		zoomButton.visible = false;
		zoomButton.text = locale::ZOOM;
		zoomButton.buttonIcon = icons::Zoom;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(!other.major)
				continue;

			int xpos = 0;
			if(i % 2 == 0)
				xpos = 1+ int(i) / 2;
			else
				xpos = -1 - int(i) / 2;
			float yoff = 0.f;
			if(abs(xpos) % 2 != 0)
				yoff = 0.2f;

			DelegationBox box(parliamentPanel, other);
			box.alignment = Alignment(
					Left-55+0.5f+(xpos * (DELEGATION_WIDTH+60)),
					Top+0.5f+yoff-(DELEGATION_HEIGHT/2),
					Width=DELEGATION_WIDTH, Height=DELEGATION_HEIGHT);
			boxes.insertLast(box);
		}

		GuiSkinElement leftBar(senateBG, Alignment(Left, Top+49, Left+210, Bottom-2), SS_PlainBox);
		leftBar.color = Color(0xffffff80);

		GuiSkinElement rightBar(senateBG, Alignment(Right-210, Top+49, Right, Bottom-2), SS_PlainBox);
		rightBar.color = Color(0xffffff80);

		//Buttons
		@backButton = GuiButton(senateBG, Alignment(Left+6, Top+52, Left+204, Height=36), locale::DIPLOMACY_BACK);
		backButton.buttonIcon = icons::Back;
		@leaveButton = GuiButton(senateBG, Alignment(Right-206, Bottom-42, Right-6, Height=36), locale::VOTE_LEAVE);
		leaveButton.buttonIcon = icons::Exclaim;
		leaveButton.visible = false;
		@withdrawButton = GuiButton(senateBG, Alignment(Right-206, Top+52, Right-6, Height=36), locale::VOTE_WITHDRAW);
		withdrawButton.buttonIcon = icons::Close;

		//Offers
		@offerFor = GuiButton(senateBG, recti(0,0, 160,50));
		offerFor.color = Color(0x80ff80ff);
		GuiSprite(offerFor, recti_area(5,5, 40,40), Sprite(spritesheet::CardCategoryIcons, 4, Color(0xffffff80)));
		GuiText(offerFor, Alignment().padded(45,0,0,0), locale::OFFER_FOR);
		@offerAgainst = GuiButton(senateBG, recti(0,0, 160,50));
		GuiSprite(offerAgainst, recti_area(5,5, 40,40), Sprite(spritesheet::VoteIcons, 6, Color(0xffffff80)));
		GuiText(offerAgainst, Alignment().padded(45,0,0,0), locale::OFFER_AGAINST);
		offerAgainst.color = Color(0xff8080ff);

		@againstOfferPanel = GuiPanel(senateBG, Alignment(Left+4, Top+94, Left+206, Bottom-60));
		@forOfferPanel = GuiPanel(senateBG, Alignment(Right-206, Top+94, Right-4, Bottom-60));

		//Cardlist
		@cardBG = GuiBackgroundPanel(this, Alignment(Left+0.4f+4, Top+PARLIAMENT_HEIGHT+8, Right-8, Bottom-8));
		cardBG.picture = Sprite(material::DiplomacyActions);
		cardBG.titleColor = Color(0x8ebc00ff);
		cardBG.title = locale::AVAILABLE_CARDS;

		@cardPanel = GuiPanel(this, Alignment(Left+0.4f+8, Top+PARLIAMENT_HEIGHT+42, Right-12, Bottom-12));

		//Create log box
		@logBG = GuiBackgroundPanel(this, Alignment(Left+8, Top+PARLIAMENT_HEIGHT+8, Right-0.6f-4, Bottom-8));
		logBG.titleColor = Color(0x00c7feff);
		logBG.title = locale::VOTE_LOG;

		@logPanel = GuiPanel(logBG, Alignment(Left+8, Top+34, Right-8, Bottom-46));

		//@logBox = GuiMarkupText(logPanel, recti(0, 0, 100, 100));

		//Create chat box
		@messageLabel = GuiText(this, Alignment(Left+24, Bottom-50, Left+84, Bottom-18), locale::SAY_LABEL);

		@messageBox = GuiTextbox(this, Alignment(Left+84, Bottom-50, Right-0.6f-168, Bottom-14));

		@sendButton = GuiButton(this, Alignment(Right-0.6f-164, Bottom-50, Right-0.6f-14, Bottom-14), locale::SEND);
		sendButton.buttonIcon = icons::Chat;

	}

	double updateTime = 0.0;
	void tick(double time) {
		if(visible) {
			updateTime -= time;
			if(updateTime <= 0.0) {
				update(vote.id);
				updateTime += UPDATE_TIMER;
			}
		}
		Tab::tick(time);
	}

	void show() {
		update(vote.id);
		if(parliamentPanel.horiz.visible)
			parliamentPanel.horiz.pos = (parliamentPanel.horiz.end - parliamentPanel.horiz.page) * 0.5;
		Tab::show();
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();

		//Log size
		int y = 0;
		for(uint i = 0, cnt = logs.length; i < cnt; ++i) {
			logs[i].position = vec2i(0, y);
			logs[i].size = vec2i(logPanel.size.width, logs[i].size.height);
			y += logs[i].size.height;
		}

		//Offer bars
		offerAgainst.position = vec2i(25, senateBG.size.height-57);
		offerFor.position = vec2i(senateBG.size.width - 185, senateBG.size.height-57);

		completeEffects();
	}

	DelegationBox@ getDelegation(Empire@ emp) {
		for(uint i = 0, cnt = boxes.length; i < cnt; ++i) {
			if(boxes[i].emp is emp)
				return boxes[i];
		}
		return null;
	}

	void update(int voteId) {
		uint prevId = vote.id;
		if(!receive(getInfluenceVoteByID(voteId), vote)) {
			vote.id = voteId;
			return;
		}

		//Update vote data
		if(prevId != vote.id || senateBG.title.length == 0) {
			string implTitle = vote.formatTitle();
			titleBox.text = implTitle;
			plainTitle = titleBox.plainText + " ("+vote.startedBy.name+")";
			if(vote.startedBy.major)
				titleBox.text = "[center]"+formatEmpireName(vote.startedBy)+": "+implTitle+"[/center]";
			else
				titleBox.text = "[center]"+implTitle+"[/center]";
		}

		title = format("[$1y/$2n] ", toString(vote.totalFor), toString(vote.totalAgainst))+plainTitle;

		if(vote.targets.length != 0 && vote.targets[0].type == TT_Object && vote.targets[0].obj !is null) {
			zoomButton.text = format(locale::ZOOM_TO, formatObjectName(vote.targets[0].obj));
			zoomButton.visible = true;
		}
		else
			zoomButton.visible = false;

		//Update delegation votes
		for(uint i = 0, cnt = boxes.length; i < cnt; ++i) {
			boxes[i].set(vote.empireVotes[i],
				vote.isPresent(boxes[i].emp) && (playerEmpire.ContactMask & boxes[i].emp.mask != 0),
				vote.startedBy is boxes[i].emp, false/*vote.getTarget() is boxes[i].emp*/,
				boxes[i].emp is getSenateLeader());
			boxes[i].update(vote);
		}

		//Update total votes
		yeaBox.text = format(locale::VOTES_FOR, toString(vote.totalFor));
		nayBox.text = format(locale::VOTES_AGAINST, toString(vote.totalAgainst));

		string totalText = toString(abs(vote.totalFor - vote.totalAgainst));
		if(vote.totalFor > vote.totalAgainst)
			totalText = "+"+totalText;
		else if(vote.totalAgainst > vote.totalFor)
			totalText = "-"+totalText;
		totalBox.text = totalText;

		vec2i totDim = totalBox.getTextDimension();
		totalBox.position = vec2i((totalBG.size.width - totDim.x - 30)/2, 0);
		totalPic.position = vec2i(totalBox.position.x + totDim.x + 6, 8);

		Color timerColor;
		string timeText;
		if(vote.totalFor > vote.totalAgainst) {
			totalPic.desc = Sprite(material::ThumbsUp);
			totalBox.color = Color(0x00ff00ff);
			totalBG.color = Color(0x00ff00ff);
			titleBG.color = Color(0x7cff00ff);

			timerColor = Color(0x00ff00ff);
			timeText = formatTime(vote.remainingTime);
		}
		else {
			totalPic.desc = Sprite(material::ThumbsDown);
			totalBox.color = Color(0xff0000ff);
			totalBG.color = Color(0xff0000ff);
			titleBG.color = Color(0xff7c00ff);

			timerColor = Color(0xff0000ff);
			timeText = formatTime(vote.remainingTime);
		}

		//Update timer
		if(vote.currentTime < 0.0) {
			forBar.progress = 0.f;
			againstBar.progress = vote.currentTime / config::INFLUENCE_FAIL_THRES;
		}
		else {
			againstBar.progress = 0.f;
			forBar.progress = vote.currentTime / config::INFLUENCE_PASS_THRES;
		}
		timerBox.text = timeText;
		timerBox.color = timerColor;

		//Update cards
		auto@ data = playerEmpire.getInfluenceCards();
		cards.length = 0;
		InfluenceCard@ card = InfluenceCard();
		while(receive(data, card)) {
			cards.insertLast(card);
			@card = InfluenceCard();
		}
		updateCardList(cardPanel, cards, cardBoxes, vote = vote, filterPlayable = false);

		bool active = vote.active && vote.isPresent(playerEmpire);

		//Update offers
		uint cntOffFor = 0, cntOffAgainst = 0;
		if(active) {
			for(uint i = 0, cnt = vote.offers.length; i < cnt; ++i) {
				if(vote.offers[i].side) {
					if(cntOffFor >= forOffers.length)
						forOffers.resize(cntOffFor+1);
					if(forOffers[cntOffFor] is null)
						@forOffers[cntOffFor] = OfferDisplay(forOfferPanel, recti_area(0,0,202,34));
					auto@ off = forOffers[cntOffFor];
					off.update(vote.offers[i], voteId);
					cntOffFor += 1;
				}
				else {
					if(cntOffAgainst >= againstOffers.length)
						againstOffers.resize(cntOffAgainst+1);
					if(againstOffers[cntOffAgainst] is null)
						@againstOffers[cntOffAgainst] = OfferDisplay(againstOfferPanel, recti_area(0,0,202,34));
					auto@ off = againstOffers[cntOffAgainst];
					off.update(vote.offers[i], voteId);
					cntOffAgainst += 1;
				}
			}
		}
		for(uint i = cntOffFor; i < forOffers.length; ++i) {
			if(forOffers[i] !is null)
				forOffers[i].remove();
		}
		forOffers.length = cntOffFor;
		for(uint i = cntOffAgainst; i < againstOffers.length; ++i) {
			if(againstOffers[i] !is null)
				againstOffers[i].remove();
		}
		againstOffers.length = cntOffAgainst;
		forOfferPanel.updateAbsolutePosition();
		againstOfferPanel.updateAbsolutePosition();

		int y = 0;
		for(uint i = 0; i < cntOffFor; ++i) {
			forOffers[i].position = vec2i(0, y);
			y += forOffers[i].size.height;
		}
		y = 0;
		for(uint i = 0; i < cntOffAgainst; ++i) {
			againstOffers[i].position = vec2i(0, y);
			y += againstOffers[i].size.height;
		}

		//Update button state
		leaveButton.visible = false;
		sendButton.visible = active;
		messageLabel.visible = active;
		messageBox.visible = active;
		cardPanel.visible = active;
		cardBG.visible = active;
		withdrawButton.visible = active && vote.startedBy is playerEmpire;
		offerFor.visible = active;
		offerAgainst.visible = active;
		offerFor.disabled = !vote.canVote(playerEmpire, true);
		offerAgainst.disabled = !vote.canVote(playerEmpire, false);

		if(active) {
			@logBG.alignment = Alignment(Left+8, Top+PARLIAMENT_HEIGHT+8, Right-0.6f-4, Bottom-8);
			if(!votingBox.visible)
				logBG.updateAbsolutePosition();
			votingBox.visible = true;
		}
		else {
			@logBG.alignment = Alignment(Left+8, Top+PARLIAMENT_HEIGHT+8, Right-8, Bottom-8);
			if(votingBox.visible)
				logBG.updateAbsolutePosition();
			votingBox.visible = false;
		}

		//Update log
		if(lastLog != int(vote.events.length) || lastEffects != int(vote.effects.length)) {
			//Log events
			uint oldCnt = logs.length;
			uint newCnt = vote.events.length;
			for(uint i = newCnt; i < oldCnt; ++i)
				logs[i].remove();
			logs.length = newCnt;

			resetEffects();

			int y = 0, w = logPanel.size.width;
			for(uint i = 0; i < newCnt; ++i) {
				if(logs[i] is null)
					@logs[i] = LogEntry(logPanel, recti(0, 0, w, 30));
				auto@ log = logs[i];

				InfluenceVoteEvent@ evt = vote.events[i];
				@log.evt = evt;
				if(evt.type == IVET_Start) {
					if(evt.cardEvent !is null) {
						startCard.set(evt.cardEvent.card, showVariables = false, centerTitle = true);
						startCard.visible = true;
						voteDesc.visible = false;

						setMarkupTooltip(startCard, evt.cardEvent.card.formatTooltip(showUses=false), width=450);
					}
					else {
						startCard.visible = false;
						voteDesc.visible = true;

						voteDesc.desc = vote.type.icon;
						setMarkupTooltip(voteDesc, "[font=Medium]"+vote.formatTitle()+"[/font]\n"+vote.formatDescription(), width=450);
					}
				}
				else if(evt.isActiveEffect(vote)) {
					addEffect(evt.cardEvent.card);
				}

				string text;
				text += formatTimeStamp(evt.time)+"[offset=80]";
				text += evt.formatEvent();
				text += "[/offset]";
				log.text = text;
				log.updateAbsolutePosition();
				log.position = vec2i(0, y);
				y += log.size.height;
			}

			for(uint i = 0, cnt = vote.effects.length; i < cnt; ++i) {
				if(vote.effects[i].isActiveEffect(vote))
					addEffect(vote.effects[i]);
			}

			completeEffects();

			lastLog = int(vote.events.length);
			lastEffects = int(vote.effects.length);
		}
	}

	array<EffectButton@> effects;
	array<InfluenceCard@> events;

	uint effIndex = 0;
	void resetEffects() {
		effIndex = 0;
	}

	void addEffect(InfluenceCard@ evt) {
		EffectButton@ btn;

		if(effIndex >= effects.length) {
			@btn = EffectButton(this, recti_area(0, 0, 80, 52));
			effects.insertLast(btn);
			events.insertLast(evt);
		}
		else {
			@btn = effects[effIndex];
			@events[effIndex] = evt;
		}

		btn.setIcon(evt.type.icon);
		btn.card = evt;
		auto@ emp = evt.owner;
		if(emp !is null) {
			btn.color = emp.color;
			setMarkupTooltip(btn, "[font=Medium]"+formatEmpireName(emp)+": [/font]"+evt.formatTooltip(showUses=false), width=450);
		}

		effIndex += 1;
	}

	void completeEffects() {
		for(uint i = effIndex, cnt = events.length; i < cnt; ++i)
			effects[i].remove();
		events.length = effIndex;
		effects.length = effIndex;

		if(effects.length != 0) {
			int w = senateBG.rect.width - 24 - 216 - 216;
			int step = min(w/effects.length, 86);
			int offset = 12 + 216 + (w - effects.length*step) / 2;
			for(uint i = 0, cnt = effects.length; i < cnt; ++i)
				effects[i].position = vec2i(senateBG.rect.topLeft.x + offset + i*step, senateBG.rect.topLeft.y+132);
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is backButton) {
				if(previous is null)
					browseTab(this, createDiplomacyTab());
				else
					popTab(this);
				return true;
			}
			else if(event.caller is sendButton) {
				sendMessage();
				return true;
			}
			else if(event.caller is offerFor) {
				OfferDialog(this, true, vote.id);
				return true;
			}
			else if(event.caller is offerAgainst) {
				OfferDialog(this, false, vote.id);
				return true;
			}
			else if(event.caller is leaveButton) {
				question(
					locale::PROMPT_LEAVE,
					locale::LEAVE, locale::CANCEL,
					LeaveCallback(vote.id));
			}
			else if(event.caller is withdrawButton) {
				question(
					locale::PROMPT_WITHDRAW,
					locale::WITHDRAW, locale::CANCEL,
					WithdrawCallback(vote.id));
			}
			else if(event.caller is zoomButton) {
				if(vote.targets.length != 0 && vote.targets[0].type == TT_Object) {
					zoomTo(vote.targets[0].obj);
					return true;
				}
			}
			else if(cast<GuiInfluenceCard>(event.caller) !is null) {
				auto@ gcard = cast<GuiInfluenceCard>(event.caller);
				bool playable = true;
				if(gcard is startCard)
					playable = false;
				GuiInfluenceCardPopup(this, event.caller, gcard.card, vote = vote, playable = playable);
			}
			else {
				for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
					if(effects[i] is event.caller)
						GuiInfluenceCardPopup(this, event.caller, events[i], vote = vote, playable = false);
				}
			}
		}
		else if(event.type == GUI_Confirmed) {
			if(event.caller is messageBox) {
				sendMessage();
				return true;
			}
		}
		return Tab::onGuiEvent(event);
	}

	void sendMessage() {
		string message = messageBox.text;
		messageBox.text = "";

		if(!vote.active || !vote.isPresent(playerEmpire))
			return;
		sendInfluenceVoteMessage(vote.id, message);
		update(vote.id);
	}

	Color get_activeColor() {
		return Color(0x74fc4eff);
	}

	Color get_inactiveColor() {
		return Color(0x37ff00ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x408c2bff);
	}

	TabCategory get_category() {
		return TC_Diplomacy;
	}

	Sprite get_icon() {
		return Sprite(material::TabDiplomacy);
	}

	void draw() {
		skin.draw(SS_DiplomacyBG, SF_Normal, AbsolutePosition);
		Tab::draw();
	}
};

class DelegationBox : BaseGuiElement {
	Empire@ emp;
	GuiEmpire@ picture;
	GuiText@ vote;
	GuiSprite@ thumb;
	GuiSprite@ mark;
	GuiSprite@ leaderIcon;
	int prevVotes = 0;
	bool involved = false;
	bool petitioner = false;
	bool target = false;
	bool leader = false;

	DelegationBox(IGuiElement@ parent, Empire@ empire) {
		super(parent, recti(0, 0, DELEGATION_WIDTH, DELEGATION_HEIGHT));

		@emp = empire;
		@picture = GuiEmpire(this,
					recti(4, 5, DELEGATION_WIDTH - 50, DELEGATION_HEIGHT - 5),
					emp);
		picture.showName = true;

		@vote = GuiText(this, recti(DELEGATION_WIDTH - 46, 0,
						DELEGATION_WIDTH, DELEGATION_HEIGHT));
		vote.horizAlign = 0.5;
		vote.vertAlign = 0.5;
		vote.font = FT_Medium;

		@thumb = GuiSprite(this, recti(0, 0, 40, 40));
		thumb.desc = Sprite(material::ThumbsUp);

		@mark = GuiSprite(this, Alignment(Left, Top, Width=42, Height=42));
		mark.visible = false;

		@leaderIcon = GuiSprite(picture, Alignment(Left, Bottom-56, Left+26, Bottom-30));
		leaderIcon.desc = Sprite(material::LeaderIcon);
		leaderIcon.tooltip = locale::SENATE_LEADER;
		leaderIcon.visible = false;

		prevVotes = -1;
		set(0, true, false, false, false);
	}

	void set(int amount, bool inv, bool Petitioner, bool Target, bool Leader) {
		involved = inv;
		petitioner = Petitioner;
		target = Target;
		leader = Leader;
		leaderIcon.visible = leader;
		visible = involved;
		if(amount == prevVotes)
			return;

		if(amount == 0) {
			vote.color = Color(0xaaaaaaff);
			vote.text = "0";

			vote.position = vec2i(DELEGATION_WIDTH - 46, 0);
			vote.size = vec2i(46, DELEGATION_HEIGHT);
			thumb.visible = false;
			vote.visible =  false;
		}
		else if(amount < 0) {
			vote.color = Color(0xff0000ff);
			vote.text = toString(abs(amount));
			vote.visible = true;

			thumb.position = vec2i(DELEGATION_WIDTH - 43, 6);
			thumb.desc = Sprite(material::ThumbsDown);
			thumb.visible = true;

			vote.position = vec2i(DELEGATION_WIDTH - 46, 46);
			vote.size = vec2i(46, DELEGATION_HEIGHT-46);
		}
		else {
			vote.color = Color(0x00ff00ff);
			vote.text = toString(amount);
			vote.visible = true;

			thumb.position = vec2i(DELEGATION_WIDTH - 43, DELEGATION_HEIGHT - 46);
			thumb.desc = Sprite(material::ThumbsUp);
			thumb.visible = true;

			vote.position = vec2i(DELEGATION_WIDTH - 46, 5);
			vote.size = vec2i(46, DELEGATION_HEIGHT-46);
		}

		if(amount < 10)
			vote.font = FT_Big;
		else
			vote.font = FT_Medium;

		prevVotes = amount;
	}

	void update(InfluenceVote@ vote) {
		double pts = vote.getContribPoints(emp);
		double highest = vote.highestContribPointsValue;
		double lowest = vote.lowestContribPointsValue;

		if(pts >= highest - 0.001 && pts > 0) {
			mark.visible = true;
			mark.desc = Sprite(spritesheet::QuickbarIcons, 6);
			setMarkupTooltip(mark, format(locale::TT_HIGHEST_CONTRIBUTOR, formatEmpireName(emp)));
		}
		else if(pts <= lowest + 0.001) {
			mark.visible = true;
			mark.desc = Sprite(spritesheet::QuickbarIcons, 3);
			setMarkupTooltip(mark, format(locale::TT_LOWEST_CONTRIBUTOR, formatEmpireName(emp)));
		}
		else {
			mark.visible = false;
		}
	}

	void draw() {
		Color col = emp.color;
		if(!involved)
			col.a = 0x60;
		Color voteCol;
		if(prevVotes > 0)
			voteCol = Color(0x88ff88ff);
		else if(prevVotes < 0)
			voteCol = Color(0xff8888ff);

		if(petitioner || target) {
			clearClip();

			Color col = Color(0x00c7feff);
			if(petitioner)
				col = Color(0x00ff00ff);

			recti pos = recti_area(
				AbsolutePosition.topLeft - vec2i(0, 16),
				vec2i(DELEGATION_WIDTH-46, 22));
			skin.draw(SS_FullTitle, SF_Normal, pos, col);

			const Font@ ft = skin.getFont(FT_Small);
			if(petitioner)
				ft.draw(pos, locale::VOTE_PETITIONER, locale::ELLIPSIS, Color(0xffffffff), 0.5, 0.4);
			else
				ft.draw(pos, locale::VOTE_TARGET, locale::ELLIPSIS, Color(0xffffffff), 0.5, 0.4);
		}

		if(prevVotes != 0)
			skin.draw(SS_RoundedBox, SF_Normal, AbsolutePosition.padded(0, 4, 0, 4), voteCol);
		skin.draw(SS_RoundedBox, SF_Normal, AbsolutePosition.padded(0, 0, 46, 0), col);

		BaseGuiElement::draw();
	}
};

Tab@ createInfluenceVoteTab(int voteId) {
	InfluenceVoteTab tab;
	tab.update(voteId);
	return tab;
}

bool isVoteVisible(uint voteId) {
	InfluenceVoteTab@ tab = cast<InfluenceVoteTab>(ActiveTab);
	if(tab is null)
		return false;
	return tab.vote.id == voteId;
}

