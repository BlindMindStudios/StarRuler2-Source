import tabs.Tab;
import elements.GuiEmpire;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiSkinElement;
import elements.GuiMarkupText;
import elements.GuiImage;
import elements.GuiSprite;
import elements.GuiContextMenu;
import elements.GuiBackgroundPanel;
import elements.GuiCheckbox;
import elements.GuiTextbox;
import elements.GuiInfluenceCard;
import elements.GuiProgressbar;
import elements.GuiIconGrid;
import elements.GuiSprite;
import elements.MarkupTooltip;
import elements.GuiOfferList;
import dialogs.QuestionDialog;
import dialogs.InputDialog;
import util.formatting;
import systems;
import resources;
import influence;
import traits;
from gui import animate_time, animate_retarget;
import void zoomTo(Object@) from "tabs.GalaxyTab";

from tabs.tabbar import ActiveTab, browseTab, newTab, switchToTab, findTab;
from tabs.InfluenceVoteTab import createInfluenceVoteTab, InfluenceVoteTab;
from tabs.InfluenceHistoryTab import createInfluenceHistoryTab;

const int INFLUENCE_BOX_WIDTH = 100;
const int EMPIRE_BOX_WIDTH = 400;
const int EMPIRE_BOX_SPACING = 12;
const int MIN_SUB_HEIGHT = 100;

const double CARD_ANIM_TIME = 1.0;
const double CARD_ANIM_REMOVE_TIME = 0.4;

const double INFLUENCE_UPDATE_TIMER = 0.2;
const double WAR_UPDATE_TIMER = 0.2;
const double RANKS_UPDATE_TIMER = 0.2;
const double VOTES_UPDATE_TIMER = 0.2;
const double EFFECTS_UPDATE_TIMER = 0.2;
const double TREATIES_UPDATE_TIMER = 0.6;
const double CARDS_UPDATE_TIMER = 0.5;

class DiplomacyTab : Tab {
	GuiPanel@ panel;
	GuiSkinElement@ playerPanel;
	GuiSkinElement@ playerHeading;
	GuiEmpire@ playerIcon;
	GuiSprite@ leaderIcon;
	GuiText@ playerName;
	GuiSprite@ playerFlag;

	GuiSprite@ strIcon;
	GuiText@ strText;

	GuiSprite@ plIcon;
	GuiText@ plText;

	GuiSprite@ ptsIcon;
	GuiText@ ptsText;

	GuiSprite@ infIcon;
	GuiText@ infText;

	GuiButton@ electButton;
	GuiButton@ unifyButton;
	GuiButton@ actionButton;

	BaseGuiElement@ empirePanel;
	EmpireBox@[] empires;
	GuiText@ noEmpireText;

	GuiProgressbar@ drawProgress;
	GuiBackgroundPanel@ stackBG;
	BaseGuiElement@ stackPanel;
	array<InfluenceCard@> cardStack;
	array<StackCard@> stackBoxes;

	GuiBackgroundPanel@ cardBG;
	BaseGuiElement@ cardPanel;
	array<InfluenceCard@> cards;
	array<GuiInfluenceCard@> cardBoxes;

	GuiBackgroundPanel@ voteBG;
	GuiButton@ historyButton;
	BaseGuiElement@ votePanel;
	GuiText@ noVotesText;

	InfluenceVote[] votes;
	VoteBox@[] voteBoxes;

	GuiBackgroundPanel@ effectBG;
	BaseGuiElement@ effectPanel;
	GuiText@ noEffectsText;

	InfluenceEffect[] effects;
	EffectBox@[] effectBoxes;

	GuiBackgroundPanel@ treatyBG;
	BaseGuiElement@ treatyPanel;
	GuiText@ noTreatyText;
	TreatyBox@[] treatyBoxes;

	Treaty[] treaties;

	double influenceUpdate = 0.0;
	double warUpdate = 0.0;
	double ranksUpdate = 0.0;
	double votesUpdate = 0.0;
	double effectsUpdate = 0.0;
	double cardsUpdate = 0.0;
	double treatiesUpdate = 0.0;
	uint seenVote = 0;

	double drawInterval = 0.0;
	double drawTimer = 0.0;

	DiplomacyTab() {
		super();
		title = locale::DIPLOMACY;
		@panel = GuiPanel(this, Alignment_Fill());
		panel.horizType = ST_Never;
		drawInterval = getInfluenceDrawInterval();

		//Player empire
		@playerPanel = GuiSkinElement(panel, recti(12, 12, 612, 160), SS_PlayerEmpireBox);
		@playerFlag = GuiSprite(playerPanel, Alignment().padded(24));
		playerFlag.horizAlign = 1.0;

		@playerIcon = GuiEmpire(playerPanel, recti(8, 8, 140, 140));
		@playerHeading = GuiSkinElement(playerPanel, recti(), SS_CenterTitle);
		@playerName = GuiText(playerPanel, recti(0, 2, 612, 26));
		playerName.horizAlign = 0.5;
		playerName.font = FT_Bold;

		@leaderIcon = GuiSprite(playerIcon, Alignment(Left, Bottom-52, Left+52, Bottom));
		leaderIcon.desc = Sprite(material::LeaderIcon);
		setMarkupTooltip(leaderIcon, locale::TT_SENATE_LEADER);
		leaderIcon.visible = false;

		@infIcon = GuiSprite(playerPanel, recti(148, 34, 198, 64));
		infIcon.desc = Sprite(material::PoliticalStrengthIcon);
		@infText = GuiText(playerPanel, recti(204, 34, 318, 64));
		infText.color = Color(0xccccccff);

		@strIcon = GuiSprite(playerPanel, recti(148, 68, 198, 98));
		strIcon.desc = Sprite(material::MilitaryStrengthIcon);
		@strText = GuiText(playerPanel, recti(204, 68, 318, 98));
		strText.color = Color(0xccccccff);

		@plIcon = GuiSprite(playerPanel, recti(148, 102, 198, 132));
		plIcon.desc = Sprite(material::TerritoryStrengthIcon);
		@plText = GuiText(playerPanel, recti(204, 102, 318, 132));
		plText.color = Color(0xccccccff);

		@ptsIcon = GuiSprite(playerPanel, recti(328, 34, 358, 64));
		ptsIcon.desc = Sprite(material::PointsIcon);
		@ptsText = GuiText(playerPanel, recti(364, 34, 590, 64));
		ptsText.color = Color(0xccccccff);

		@electButton = GuiButton(playerPanel, recti(328, 69, 588, 97));
		electButton.visible = false;
		@unifyButton = GuiButton(playerPanel, recti(328, 69, 588, 97));
		unifyButton.visible = false;

		@actionButton = GuiButton(playerPanel, recti(328, 103, 588, 131));
		GuiSprite(actionButton, Alignment(Left+0.5f-11, Top+3, Left+0.5f+11, Bottom-3),
					Sprite(material::DownIcon));
		actionButton.visible = false;

		@empirePanel = BaseGuiElement(panel, recti(0, 0, 500, 100));

		@noEmpireText = GuiText(panel, Alignment(Left+12, Top+220, Right-12, Top+260));
		noEmpireText.text = locale::NO_MET_EMPIRES;
		noEmpireText.font = FT_Subtitle;
		noEmpireText.color = Color(0xaaaaaaff);
		noEmpireText.stroke = colors::Black;
		noEmpireText.horizAlign = 0.5;
		noEmpireText.visible = false;

		//Card stack
		@stackBG = GuiBackgroundPanel(panel, recti());
		stackBG.title = locale::CARD_STACK;
		stackBG.titleColor = Color(0x53feb3ff);
		stackBG.picture = Sprite(material::DiplomacyActions);

		@drawProgress = GuiProgressbar(stackBG, Alignment(Right-185, Top+3, Right-5, Top+28), 0.f);
		drawProgress.frontColor = Color(0x20adffff);

		@stackPanel = BaseGuiElement(stackBG, recti(8, 34, 100, 100));

		//Card list
		@cardBG = GuiBackgroundPanel(panel, recti());
		cardBG.title = locale::AVAILABLE_CARDS;
		cardBG.titleColor = Color(0xb3fe00ff);
		cardBG.picture = Sprite(material::DiplomacyActions);

		@cardPanel = BaseGuiElement(cardBG, recti(8, 34, 100, 100));

		//Vote list
		@voteBG = GuiBackgroundPanel(panel, recti());
		voteBG.title = locale::ACTIVE_VOTES;
		voteBG.titleColor = Color(0x00bffeff);
		voteBG.picture = Sprite(material::Propositions);

		@historyButton = GuiButton(voteBG, Alignment(Right-185, Top+3, Right-5, Top+28), locale::VIEW_VOTE_HISTORY);
		historyButton.color = Color(0x9be5feff);

		@votePanel = BaseGuiElement(voteBG, recti(8, 34, 100, 100));
		@noVotesText = GuiText(votePanel, recti(4, 4, 400, 24), locale::NO_VOTES);
		noVotesText.color = Color(0xaaaaaaff);

		//Effect list
		@effectBG = GuiBackgroundPanel(panel, recti());
		effectBG.title = locale::ACTIVE_INFLUENCE_EFFECTS;
		effectBG.titleColor = Color(0xfe8300ff);
		effectBG.picture = Sprite(material::ActiveEffects);

		@effectPanel = BaseGuiElement(effectBG, recti(8, 34, 100, 100));
		@noEffectsText = GuiText(effectPanel, recti(4, 4, 400, 24), locale::NO_EFFECTS);
		noEffectsText.color = Color(0xaaaaaaff);

		//Treaty list
		@treatyBG = GuiBackgroundPanel(panel, recti());
		treatyBG.title = locale::ACTIVE_TREATIES;
		treatyBG.titleColor = Color(0x7300feff);
		treatyBG.picture = Sprite(material::StatusPeace);

		@treatyPanel = BaseGuiElement(treatyBG, recti(8, 34, 400, 100));
		@noTreatyText = GuiText(treatyPanel, recti(4, 4, 400, 24), locale::NO_TREATIES);
		noTreatyText.color = Color(0xaaaaaaff);

		changeEmpire(playerEmpire);
	}

	int prevContact = 0;
	void tick(double time) {
		if(visible) {
			influenceUpdate -= time;
			if(influenceUpdate <= 0) {
				updateInfluence();
				influenceUpdate += INFLUENCE_UPDATE_TIMER;
			}

			ranksUpdate -= time;
			if(ranksUpdate <= 0) {
				updateRanks();
				ranksUpdate += RANKS_UPDATE_TIMER;
			}

			treatiesUpdate -= time;
			if(treatiesUpdate <= 0) {
				updateTreaties();
				treatiesUpdate += TREATIES_UPDATE_TIMER;
			}

			effectsUpdate -= time;
			if(effectsUpdate <= 0) {
				updateEffects();
				effectsUpdate += EFFECTS_UPDATE_TIMER;
			}

			cardsUpdate -= time;
			if(cardsUpdate <= 0) {
				updateCards();
				cardsUpdate += CARDS_UPDATE_TIMER;
			}

			playerPanel.visible = playerEmpire !is null && playerEmpire.valid;
		}

		int newContact = playerEmpire.ContactMask.value;
		if(playerEmpire !is playerIcon.empire
				|| newContact != prevContact) {
			changeEmpire(playerEmpire);
			prevContact = newContact;
		}

		warUpdate -= time;
		if(warUpdate <= 0) {
			updateWar();
			warUpdate += WAR_UPDATE_TIMER;
		}

		votesUpdate -= time;
		if(votesUpdate <= 0) {
			updateVotes();
			votesUpdate += VOTES_UPDATE_TIMER;
		}
	}

	void show() {
		updateInfluence();
		updateRanks();
		updateEffects();
		updateWar();
		updateVotes();
		updateCards(true);

		Tab::show();
	}

	void changeEmpire(Empire@ emp) {
		@playerIcon.empire = emp;
		playerName.text = emp.name;
		playerName.color = emp.color;
		playerHeading.color = emp.color;
		playerPanel.color = emp.color;

		playerFlag.desc = Sprite(playerEmpire.flag);
		playerFlag.color = playerEmpire.color;
		playerFlag.color.a = 0x30;

		int needed = playerName.getTextDimension().width + 140;
		playerHeading.size = vec2i(needed, 26);
		playerHeading.position = vec2i((playerPanel.size.width-needed)/2, 1);

		updateEmpires();

		uint traitCnt = emp.traitCount;
		string tt = format("[color=$2][font=Subtitle]$1[/font][/color]", emp.name, toString(emp.color));
		for(uint i = 0; i < traitCnt; ++i) {
			if(tt.length != 0)
				tt += "\n\n";
			auto@ trait = getTrait(emp.getTraitType(i));
			if(trait !is null)
				tt += format("[color=$1][b]$2[/b][/color]\n$3",
					toString(trait.color), trait.name, trait.description);
		}
		setMarkupTooltip(playerIcon, tt, width=400);
	}

	void updateEmpires() {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i)
			if(empires[i] !is null)
				empires[i].remove();
		empires.length = 0;

		//Create  boxes
		uint empCnt = getEmpireCount();
		for(uint i = 0; i < empCnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp is playerEmpire)
				continue;
			if(!emp.major || !emp.valid)
				continue;
			if(playerEmpire.valid && playerEmpire.ContactMask.value & emp.mask == 0)
				continue;

			//Empire box
			EmpireBox box(this);
			box.set(emp);
			empires.insertLast(box);
		}

		noEmpireText.visible = empires.length == 0;
		updateAbsolutePosition();
	}

	void updateInfluence() {
		leaderIcon.visible = getSenateLeader() is playerEmpire;

		/*electButton.text = formatInfluenceCost(locale::ELECT_VOTE, getElectCost(playerEmpire));*/
		/*unifyButton.text = formatInfluenceCost(locale::UNIFY_VOTE, getUnifyCost(playerEmpire));*/

		int influence = playerEmpire.Influence;
		/*electButton.disabled = getElectCost(playerEmpire) > influence;*/
		/*unifyButton.disabled = getUnifyCost(playerEmpire) > influence;*/

		/*electButton.visible = !leaderIcon.visible;*/
		/*unifyButton.visible = leaderIcon.visible;*/
	}

	void updateRanks() {
		infText.text = format(locale::EMPIRE_INFLUENCE, toString(playerEmpire.Influence));
		ptsText.text = format(locale::EMPIRE_POINTS, toString(playerEmpire.points.value));
		strText.text = format(locale::EMPIRE_STRENGTH, standardize(sqr(playerEmpire.TotalMilitary) * 0.001, true));
		plText.text = format(locale::EMPIRE_PLANETS, toString(playerEmpire.TotalPlanets.value));

		setStrengthIcon(infIcon, playerEmpire.PoliticalStrength, locale::POLITICAL_STRENGTH);
		setStrengthIcon(strIcon, playerEmpire.MilitaryStrength, locale::MILITARY_STRENGTH);
		setStrengthIcon(plIcon, playerEmpire.EmpireStrength, locale::TERRITORY_STRENGTH);

		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			EmpireBox@ box = empires[i];
			Empire@ other = box.emp;

			box.setPoints(other.points.value);
			setStrengthIcon(box.politicalIcon, other.PoliticalStrength, locale::POLITICAL_STRENGTH);
			setStrengthIcon(box.militaryIcon, other.MilitaryStrength, locale::MILITARY_STRENGTH);
			setStrengthIcon(box.territoryIcon, other.EmpireStrength, locale::TERRITORY_STRENGTH);
		}
	}

	void updateWar() {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			EmpireBox@ box = empires[i];
			Empire@ other = box.emp;

			WarState prevState = box.state;
			WarState state = WS_Peace;
			if(playerEmpire.isHostile(other))
				state = WS_War;
			else if(isForcedPeace(playerEmpire, other))
				state = WS_Peace_Forced;

			box.setState(state);
			box.update();

			//Flash if the state was changed
			if(state != prevState)
				flash();
		}
	}

	void updateVotes() {
		votes.syncFrom(getActiveInfluenceVotes());

		uint oldCnt = voteBoxes.length;
		uint newCnt = votes.length;

		if(oldCnt != newCnt) {
			//Flash when vote count changes
			flash();

			//Put amount of active votes in title
			if(newCnt == 0)
				title = locale::DIPLOMACY;
			else
				title = locale::DIPLOMACY + " ("+newCnt+")";
		}

		for(uint i = newCnt; i < oldCnt; ++i)
			voteBoxes[i].remove();

		voteBoxes.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			@voteBoxes[i] = VoteBox(votePanel);

		for(uint i = 0; i < newCnt; ++i) {
			//Flash when spotting a new vote
			if(votes[i].id >= seenVote) {
				seenVote = votes[i].id+1;
				if(votes[i].startedBy is playerEmpire && visible)
					browseTab(this, createInfluenceVoteTab(votes[i].id), true);
				else
					flash();
			}

			voteBoxes[i].set(votes[i]);
		}


		updateVotePosition();

		if(oldCnt != newCnt)
			updateAbsolutePosition();

		noVotesText.visible = newCnt == 0;
	}

	void updateVotePosition() {
		int y = 4;
		for(uint i = 0, cnt = voteBoxes.length; i < cnt; ++i) {
			voteBoxes[i].position = vec2i(4, y);
			y += 78;
		}
		votePanel.size = vec2i(voteBG.size.width - 16, max(y+4, MIN_SUB_HEIGHT));
	}

	void updateCards(bool snap = false) {
		//Player cards
		auto@ data = playerEmpire.getInfluenceCards();
		cards.length = 0;
		InfluenceCard@ card = InfluenceCard();
		while(receive(data, card)) {
			cards.insertLast(card);
			@card = InfluenceCard();
		}

		//Card stack
		@data = getInfluenceCardStack();
		cardStack.length = 0;
		@card = StackInfluenceCard();
		while(receive(data, card)) {
			cardStack.insertLast(card);
			@card = StackInfluenceCard();
		}

		//Timer
		drawTimer = getInfluenceDrawTimer();
		drawProgress.progress = 1.0 - (drawTimer / drawInterval);
		drawProgress.text = formatTime(drawTimer);

		updateCardPosition(snap);
	}

	recti getEmpirePosition(Empire@ emp) {
		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			auto@ box = empires[i];
			if(box.emp is emp)
				return box.absolutePosition - absolutePosition.topLeft;
		}

		return recti();
	}

	void updateCardPosition(bool snap = false) {
		bool changed = false;

		//Player cards
		cardPanel.size = vec2i(cardBG.size.width - 16, cardPanel.size.height);
		int h = updateCardList(cardPanel, cards, cardBoxes);
		if(h != cardPanel.size.y) {
			cardPanel.size = vec2i(cardBG.size.width - 16, h);
			changed = true;
		}

		//Card stack
		stackPanel.size = vec2i(stackBG.size.width - 16, stackPanel.size.height);
		for(uint i = 0, cnt = stackBoxes.length; i < cnt; ++i)
			stackBoxes[i].found = false;
		for(uint i = 0, cnt = cardStack.length; i < cnt; ++i) {
			auto@ card = cardStack[i];

			//Find box
			StackCard@ box;
			for(uint n = 0, ncnt = stackBoxes.length; n < ncnt; ++n) {
				if(stackBoxes[n].card.id == card.id) {
					@box = stackBoxes[n];
					break;
				}
			}

			//Create new boxes
			if(box is null) {
				@box = StackCard(stackPanel);
				box.adding = true;

				box.position = vec2i(stackPanel.size.width + 16, 4);
				stackBoxes.insertLast(box);
			}

			box.set(card);
			box.found = true;
		}

		//Remove old boxes
		for(int i = stackBoxes.length - 1; i >= 0; --i) {
			auto@ box = stackBoxes[i];

			//Show animation for buys
			auto@ stackCard = cast<StackInfluenceCard>(box.card);
			if(stackCard.purchasedBy !is null && !box.bought) {
				if(!snap) {
					StackCard animBox(this);
					animBox.set(stackCard);

					recti fromPos = box.absolutePosition - position;
					animBox.rect = fromPos;

					recti toPos;
					if(stackCard.purchasedBy is playerEmpire)
						toPos = recti_centered(cardBG.rect, vec2i(16, 16));
					else
						toPos = recti_centered(getEmpirePosition(stackCard.purchasedBy), vec2i(16, 16));

					animBox.removing = true;
					animBox.animateTo(toPos, true);
				}
				box.bought = true;
			}

			//Remove old boxes
			if(!box.found) {
				if(snap) {
					box.remove();
				}
				else {
					recti toPos = recti_area(vec2i(-16-box.size.width, box.position.y), box.size);
					box.animateTo(toPos, true);
				}

				stackBoxes.removeAt(i);
			}
		}

		//Position boxes correctly
		int haveWidth = stackPanel.size.width;
		int perRow = floor(double(stackPanel.size.width) / double(GUI_CARD_WIDTH + 4));
		int rowWidth = min(perRow, stackBoxes.length) * (GUI_CARD_WIDTH + 4);
		int xoffset = (haveWidth - rowWidth) / 2;
		int x = xoffset, y = 4;

		for(uint i = 0, cnt = stackBoxes.length; i < cnt; ++i) {
			if(x + GUI_CARD_WIDTH + 4 >= haveWidth) {
				x = xoffset;
				y += GUI_CARD_HEIGHT + 4;
			}

			auto@ box = stackBoxes[i];
			recti pos = recti_area(vec2i(x, y), vec2i(GUI_CARD_WIDTH, GUI_CARD_HEIGHT));
			if(box.adding) {
				box.position = vec2i(box.position.x, pos.topLeft.y);
				box.adding = false;
			}
			if(snap)
				box.rect = pos;
			else
				box.animateTo(pos);
			x += GUI_CARD_WIDTH + 4;
		}

		y += GUI_CARD_HEIGHT + 4;
		if(y != stackPanel.size.y) {
			stackPanel.size = vec2i(stackBG.size.width - 16, y);
			changed = true;
		}

		if(changed)
			updateAbsolutePosition();
	}

	void updateEffects() {
		effects.syncFrom(getActiveInfluenceEffects());

		uint oldCnt = effectBoxes.length;
		uint newCnt = effects.length;

		for(uint i = newCnt; i < oldCnt; ++i)
			effectBoxes[i].remove();

		effectBoxes.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			@effectBoxes[i] = EffectBox(effectPanel);

		for(uint i = 0; i < newCnt; ++i)
			effectBoxes[i].set(effects[i]);

		updateEffectPosition();

		if(oldCnt != newCnt)
			updateAbsolutePosition();

		noEffectsText.visible = newCnt == 0;
	}

	void updateEffectPosition() {
		int y = 4;
		for(uint i = 0, cnt = effectBoxes.length; i < cnt; ++i) {
			effectBoxes[i].position = vec2i(4, y);
			y += 36;
		}
		effectPanel.size = vec2i(effectBG.size.width - 16, max(y+4, MIN_SUB_HEIGHT));
	}

	void updateTreaties() {
		treaties.syncFrom(getActiveTreaties());

		uint oldCnt = treatyBoxes.length;
		uint newCnt = treaties.length;

		for(uint i = newCnt; i < oldCnt; ++i)
			treatyBoxes[i].remove();

		treatyBoxes.length = newCnt;
		for(uint i = oldCnt; i < newCnt; ++i)
			@treatyBoxes[i] = TreatyBox(treatyPanel);

		for(uint i = 0; i < newCnt; ++i)
			treatyBoxes[i].set(treaties[i]);

		updateTreatyPosition();

		if(oldCnt != newCnt)
			updateAbsolutePosition();

		noTreatyText.visible = newCnt == 0;
	}

	void updateTreatyPosition() {
		int y = 4;
		for(uint i = 0, cnt = treatyBoxes.length; i < cnt; ++i) {
			treatyBoxes[i].position = vec2i(4, y);
			y += 68;
		}
		treatyPanel.size = vec2i(treatyBG.size.width - 16, max(y+4, MIN_SUB_HEIGHT));
	}

	void updateAbsolutePosition() {
		updateCardPosition();
		updateVotePosition();
		updateEffectPosition();
		updateTreatyPosition();

		//Arrange player box
		playerPanel.position = vec2i((size.width - playerPanel.size.width) / 2, 12);

		//Arrange empire boxes
		empirePanel.position = vec2i(12, 172);
		empirePanel.size = vec2i(size.width - 24, empirePanel.size.height);
		bool hadScroll = panel.vert.visible;

		uint w = size.width - 24;
		if(hadScroll)
			w -= 20;

		uint box = EMPIRE_BOX_WIDTH + EMPIRE_BOX_SPACING;
		uint perline = (w + 12) / box;
		uint x = (w + 12 - min(perline, empires.length) * box) / 2;
		uint y = 0;

		for(uint i = 0, cnt = empires.length; i < cnt; ++i) {
			if(x + EMPIRE_BOX_WIDTH > w) {
				x = (w + 12 - min(perline, empires.length - i) * box) / 2;
				y += 132;
			}

			empires[i].position = vec2i(x, y);
			x += EMPIRE_BOX_WIDTH + 12;
		}

		int needHeight = y + 132;
		if(empirePanel.size.height != needHeight)
			empirePanel.size = vec2i(size.width - 24, needHeight);

		//Determine organization based on the width of the screen
		w += 8;
		stackBG.position = vec2i(8, empirePanel.rect.botRight.y + 20);
		stackBG.size = vec2i(w, stackPanel.size.y + 40);

		if(size.width >= 1900) {
			//Arrange cards as a sidebar
			int start = stackBG.rect.botRight.y + 10;

			int sub_h = max(40 + cardPanel.size.y, size.height - start - 10) / 3 - 10;
			int left_w = double(w) * 0.5 - 5;
			int right_w = double(w) * 0.5 - 5;

			int total = max(10 + max(votePanel.size.y + 40, sub_h)
							+ max(effectPanel.size.y + 40, sub_h)
							+ max(treatyPanel.size.y + 40, sub_h),
						40 + cardPanel.size.y);
			total = max(total, size.height - start - 10);

			cardBG.position = vec2i(8, start);
			cardBG.size = vec2i(left_w, max(cardPanel.size.y + 40, total));

			voteBG.position = vec2i(8+left_w+10, start);
			voteBG.size = vec2i(right_w, max(votePanel.size.y + 40, sub_h));

			treatyBG.position = vec2i(8+left_w+10, voteBG.rect.botRight.y + 10);
			treatyBG.size = vec2i(right_w, max(treatyPanel.size.y + 40, sub_h));

			effectBG.position = vec2i(8+left_w+10, treatyBG.rect.botRight.y + 10);
			effectBG.size = vec2i(right_w, max(effectPanel.size.y + 40, sub_h));

		}
		else {
			//Arrange all the boxes vertically
			cardBG.position = vec2i(8, stackBG.rect.botRight.y + 10);
			cardBG.size = vec2i(w, cardPanel.size.y + 40);

			voteBG.position = vec2i(8, cardBG.rect.botRight.y + 10);
			voteBG.size = vec2i(w, votePanel.size.y + 40);

			treatyBG.position = vec2i(8, voteBG.rect.botRight.y + 10);
			treatyBG.size = vec2i(w, treatyPanel.size.y + 40);

			effectBG.position = vec2i(8, treatyBG.rect.botRight.y + 10);
			effectBG.size = vec2i(w, effectPanel.size.y + 40);
		}

		Tab::updateAbsolutePosition();
		if(hadScroll != panel.vert.visible) {
			updateAbsolutePosition();
			return;
		}
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
		skin.draw(SS_HorizAccent, SF_Normal,
				recti_area(panel.AbsolutePosition.topLeft + vec2i(0, 85),
					vec2i(AbsolutePosition.size.width, 140)));
		shader::SATURATION_LEVEL = 0.f;
		Tab::draw();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Confirmed:
				updateCards();
				cardsUpdate = 0.3;
				return true;
			case GUI_Clicked:
				if(false) {}
				/*if(evt.caller is electButton) {*/
				/*	InfluenceVote vote(getInfluenceVoteType("ElectLeaderVote"));*/
				/*	createInfluenceVote(vote);*/
				/*}*/
				/*else if(evt.caller is unifyButton) {*/
				/*	InfluenceVote vote(getInfluenceVoteType("UnifyVote"));*/
				/*	createInfluenceVote(vote);*/
				/*}*/
				else if(evt.caller is historyButton) {
					browseTab(this, createInfluenceHistoryTab(), true);
					return true;
				}
				/*else if(evt.caller is actionButton) {*/
				/*	recti pos = actionButton.absolutePosition;*/
				/*	playerContextMenu(GuiContextMenu(*/
				/*		pos.topLeft + vec2i(-12, pos.size.height),*/
				/*		pos.size.width, false));*/
				/*}*/
				else if(cast<GuiInfluenceCard>(evt.caller) !is null) {
					auto@ box = cast<GuiInfluenceCard>(evt.caller);
					if(ctrlKey) {
						sound::card_draw.play(priority=true);
						buyCardFromInfluenceStack(box.card.id);
						updateCards();
						cardsUpdate = 0.3;
					}
					else {
						sound::card_examine.play(priority=true);
						GuiInfluenceCardPopup(this, evt.caller, box.card);
					}
				}
			break;
		}
		return Tab::onGuiEvent(evt);
	}

	void playerContextMenu(GuiContextMenu@ menu) {
		//menu.addOption(ZealotOption(), format(locale::ZEALOT_OPTION, getZealotCost(playerEmpire)));
		menu.updateAbsolutePosition();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Down && event.button == 1) {
			return true;
		}
		if(event.type == MET_Button_Up && event.button == 1) {
			if(source is playerPanel || source.isChildOf(playerPanel)) {
				playerContextMenu(GuiContextMenu(mousePos));
			}
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
};

enum WarState {
	WS_Peace,
	WS_Peace_Forced,
	WS_War,
};

class EmpireBox : BaseGuiElement {
	Empire@ emp;
	GuiEmpire@ picture;
	GuiSprite@ leaderIcon;
	GuiSkinElement@ nameBG;
	GuiText@ name;

	GuiSprite@ ptsIcon;
	GuiText@ ptsText;

	GuiText@ stateLabel;
	GuiImage@ statePicture;
	GuiMarkupText@ vassalText;

	GuiSprite@ relationIcon;
	GuiSprite@ politicalIcon;
	GuiSprite@ militaryIcon;
	GuiSprite@ territoryIcon;

	GuiSprite@ flag;

	GuiButton@ actionButton;

	WarState state;

	EmpireBox(DiplomacyTab@ tab) {
		super(tab.empirePanel, recti(0, 0, EMPIRE_BOX_WIDTH, 128));

		@flag = GuiSprite(this, Alignment().padded(5));
		flag.horizAlign = 1.0;
		flag.visible = false;

		@picture = GuiEmpire(this, recti(8, 8, 120, 120));

		@leaderIcon = GuiSprite(picture, Alignment(Left, Bottom-52, Left+52, Bottom));
		leaderIcon.desc = Sprite(material::LeaderIcon);
		setMarkupTooltip(leaderIcon, locale::TT_SENATE_LEADER);
		leaderIcon.visible = false;

		@nameBG = GuiSkinElement(this, recti(120, 1, 280, 27), SS_CenterTitle);

		@name = GuiText(this, recti(0, 2, EMPIRE_BOX_WIDTH, 26));
		name.font = FT_Bold;
		name.horizAlign = 0.5;

		@statePicture = GuiImage(this, recti(132, 34, 162, 64), null);
		@stateLabel = GuiText(this, recti(172, 34, 330, 64));
		@vassalText = GuiMarkupText(this, recti(132, 36, 360, 64));
		vassalText.visible = false;

		@ptsIcon = GuiSprite(this, recti(132, 68, 162, 98));
		ptsIcon.desc = Sprite(material::PointsIcon);
		@ptsText = GuiText(this, recti(172, 68, 330, 98));
		ptsText.color = Color(0xccccccff);

		@actionButton = GuiButton(this, Alignment(Left+0.5f-50, Bottom-26, Left+0.5f+50, Bottom-2));
		actionButton.style = SS_BaselineButton;

		@relationIcon = GuiSprite(this, Alignment(Left+280, Top+0.5f-25, Width=50, Height=50));

		@politicalIcon = GuiSprite(this, recti(335, 16, 385, 46));
		politicalIcon.desc = Sprite(material::PoliticalStrengthIcon);

		@militaryIcon = GuiSprite(this, recti(335, 50, 385, 80));
		militaryIcon.desc = Sprite(material::MilitaryStrengthIcon);

		@territoryIcon = GuiSprite(this, recti(335, 84, 385, 114));
		territoryIcon.desc = Sprite(material::TerritoryStrengthIcon);

		GuiSprite(actionButton, Alignment(Left+0.5f-11, Top+4, Left+0.5f+11, Bottom-4),
					Sprite(material::DownIcon));

		setState(WS_Peace);
	}

	void fillContextMenu(GuiContextMenu@ menu) {
		menu.itemHeight = 40;

		if(emp.SubjugatedBy is null && playerEmpire.SubjugatedBy is null) {
			//War status change
			if(state == WS_Peace)
				menu.addOption(WarOption(emp), locale::DECLARE_WAR, Sprite(material::StatusWar));
			else if(state == WS_War)
				menu.addOption(PeaceOption(emp), locale::PROPOSE_PEACE, Sprite(material::StatusPeace));

			//New treaty
			menu.addOption(ProposeTreatyOption(emp), locale::PROPOSE_TREATY, Sprite(material::Propositions));
		}

		//Invite to treaty
		array<Treaty> treaties;
		treaties.syncFrom(getActiveTreaties());
		for(uint i = 0, cnt = treaties.length; i < cnt; ++i) {
			if(treaties[i].canInvite(playerEmpire, emp))
				menu.addOption(InviteTreatyOption(emp, treaties[i]));
		}

		if(emp.SubjugatedBy is null && playerEmpire.SubjugatedBy is null) {
			if(emp.team == -1 || config::ALLOW_TEAM_SURRENDER != 0)
				menu.addOption(DemandSurrenderOption(emp),
						playerEmpire.isHostile(emp) ? locale::DEMAND_SURRENDER_OPTION : locale::DEMAND_SUBJUGATE_OPTION,
						Sprite(material::LoyaltyIcon));

			if(playerEmpire.team == -1 || config::ALLOW_TEAM_SURRENDER != 0)
				menu.addOption(OfferSurrenderOption(emp),
						playerEmpire.isHostile(emp) ? locale::SURRENDER_OPTION : locale::OFFER_SUBJUGATE_OPTION,
						Sprite(material::LoyaltyIcon, Color(0xff0000ff)));
		}

		//Donations
		if(!playerEmpire.isHostile(emp))
			menu.addOption(DonationOption(this, emp), locale::DONATE_OPTION, icons::Donate);

		//Edicts
		bool haveVassals = false;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			if(getEmpire(i).SubjugatedBy is playerEmpire) {
				haveVassals = true;
				break;
			}
		}
		if(haveVassals) {
			if(playerEmpire.isHostile(emp)) {
				menu.addOption(ConquerEdictOption(emp),
						format(locale::EDICT_CONQUER_OPTION, formatEmpireName(emp)),
						Sprite(material::StatusWar));
			}
		}

		menu.finalize();
	}

	void update() {
		leaderIcon.visible = getSenateLeader() is emp;
		flag.desc = Sprite(emp.flag);
		flag.color = emp.color;
		flag.color.a = 0x20;

		if(emp.SubjugatedBy !is null) {
			string txt = format(locale::VASSAL_TEXT, formatEmpireName(emp.SubjugatedBy));
			if(playerEmpire.isHostile(emp))
				txt = format("[color=#f00][b]$1[/b][/color]", txt);

			vassalText.text = txt;
			vassalText.updateAbsolutePosition();

			stateLabel.visible = false;
			vassalText.visible = true;
			statePicture.visible = false;
		}
		else if(playerEmpire.SubjugatedBy is emp) {
			vassalText.text = locale::PARENT_VASSAL_TEXT;
			vassalText.updateAbsolutePosition();

			stateLabel.visible = false;
			vassalText.visible = true;
			statePicture.visible = false;
		}
		else {
			stateLabel.visible = true;
			statePicture.visible = true;
			vassalText.visible = false;
		}

		if(emp.isAI && emp.SubjugatedBy is null && emp.getRelation().length != 0) {
			int rel = emp.getRelationState();
			relationIcon.visible = true;
			relationIcon.desc = getRelationIcon(rel);
		}
		else {
			relationIcon.visible = false;
		}
	}

	void setPoints(int pts) {
		ptsText.text = format(locale::EMPIRE_POINTS, toString(pts));
	}

	void setState(WarState newState) {
		state = newState;

		if(state == WS_Peace || state == WS_Peace_Forced) {
			stateLabel.color = Color(0xccccccff);
			stateLabel.text = locale::PEACEFUL;
			stateLabel.font = FT_Normal;
		}
		else {
			stateLabel.color = Color(0xff0000ff);
			stateLabel.text = locale::WAR;
			stateLabel.font = FT_Bold;
		}

		switch(state) {
			case WS_Peace_Forced:
			case WS_Peace:
				@statePicture.mat = material::StatusPeace;
			break;
			case WS_War:
				@statePicture.mat = material::StatusWar;
			break;
		}
	}

	string traitTooltip;
	void set(Empire@ empire) {
		@emp = empire;
		@picture.empire = empire;

		name.text = empire.name;

		int needed = name.getTextDimension().width + 140;
		nameBG.size = vec2i(needed, 26);
		nameBG.position = vec2i((EMPIRE_BOX_WIDTH-needed)/2, 1);

		name.color = empire.color;
		nameBG.color = empire.color;
		actionButton.color = empire.color;

		uint traitCnt = empire.traitCount;
		traitTooltip = "";
		for(uint i = 0; i < traitCnt; ++i) {
			if(traitTooltip.length != 0)
				traitTooltip += "\n\n";
			auto@ trait = getTrait(empire.getTraitType(i));
			if(trait !is null)
				traitTooltip += format("[color=$1][b]$2[/b][/color]\n$3",
					toString(trait.color), trait.name, trait.description);
		}
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Down && event.button == 1) {
			return true;
		}
		if(event.type == MET_Button_Up && event.button == 1) {
			fillContextMenu(GuiContextMenu(mousePos));
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				if(evt.caller is relationIcon || evt.caller is picture) {
					string tt = format("[color=$2][font=Medium]$1[/font][/color]", emp.name, toString(emp.color));
					if(emp.isAI) {
						int rel = emp.getRelationState();
						string relationText = emp.getRelation();
						if(relationText.length != 0) {
							string relTT = format(locale::TT_RELATION, emp.name, relationText);
							tt += "\n\n"+relTT;
							setMarkupTooltip(relationIcon, relTT, width=300);
							relationIcon.visible = true;
						}
						else {
							setMarkupTooltip(relationIcon, "", width=300);
							relationIcon.visible = false;
						}
					}
					if(config::HIDE_EMPIRE_RELATIONS == 0) {
						for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
							auto@ other = getEmpire(i);
							if(other.major && other !is emp && other !is playerEmpire) {
								if(emp.isHostile(other))
									tt += "\n\n"+format(locale::RELATION_WAR, formatEmpireName(other));
							}
						}
					}
					tt += "\n\n"+traitTooltip;
					setMarkupTooltip(picture, tt, width=400);
				}
			break;
			case GUI_Clicked:
				if(evt.caller is actionButton) {
					fillContextMenu(GuiContextMenu(
						absolutePosition.topLeft + vec2i(-12, size.height),
						size.width, false));
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() {
		if(emp is null)
			return;
		skin.draw(SS_EmpireBox, SF_Normal, AbsolutePosition, emp.color);
		BaseGuiElement::draw();
	}
};

void setStrengthIcon(GuiSprite@ sprite, int str, const string& prefix) {
	if(str == -1) {
		sprite.color = Color(0xff8080aa);
		@sprite.shader = shader::Desaturate;
		sprite.tooltip = prefix+" "+locale::STR_WEAK;
	}
	else if(str == 0) {
		sprite.color = Color(0xffffffaa);
		@sprite.shader = shader::Desaturate;
		sprite.tooltip = prefix+" "+locale::STR_AVERAGE;
	}
	else {
		sprite.color = Color(0xffffffff);
		@sprite.shader = null;
		sprite.tooltip = prefix+" "+locale::STR_STRONG;
	}
}

class StackCard : GuiInfluenceCard {
	bool removing = false;
	bool animating = false;
	bool found = true;
	bool adding = false;
	bool bought = false;

	StackCard(IGuiElement@ parent) {
		super(parent);
	}

	void animateTo(const recti& pos, bool force = false) {
		if(animating && !force)
			return;
		if(pos == rect)
			return;
		animate_time(this, pos, removing ? CARD_ANIM_REMOVE_TIME : CARD_ANIM_TIME);
		animating = true;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Animation_Complete) {
			animating = false;
			if(removing)
				remove();
			return true;
		}
		return GuiInfluenceCard::onGuiEvent(evt);
	}
};

class VoteBox : BaseGuiElement {
	uint prevId = uint(-1);
	InfluenceVote@ vote;

	GuiMarkupText@ titleBox;
	GuiSprite@ icon;

	GuiProgressbar@ forBar;
	GuiProgressbar@ againstBar;

	GuiText@ timerBox;
	GuiText@ totalBox;
	GuiSprite@ totalPic;

	GuiButton@ zoomButton;

	bool Hovered = false;

	VoteBox(IGuiElement@ parent) {
		super(parent, recti(0, 0, parent.size.width - 32, 74));

		@titleBox = GuiMarkupText(this, Alignment(Left+74, Top+6, Right-74, Top+38));
		titleBox.defaultFont = FT_Subtitle;

		@totalBox = GuiText(this, Alignment(Right-74, Top+6, Right-12, Bottom-6));
		totalBox.horizAlign = 0.5;
		totalBox.font = FT_Big;
		totalBox.stroke = colors::Black;

		@totalPic = GuiSprite(this, Alignment(Right-74, Top+6, Right-12, Bottom-6));
		totalPic.color = Color(0xffffff20);

		@icon = GuiSprite(this, Alignment(Left+4, Top+4, Left+70, Bottom-4));

		@againstBar = GuiProgressbar(this, Alignment(Left+47+74, Top+40, Left+0.5f-50, Bottom-6));
		againstBar.invert = true;
		againstBar.backColor = Color(0xffffff40);
		againstBar.frontColor = Color(0xff0000ff);

		@timerBox = GuiText(this, Alignment(Left+0.5f-50, Top+40, Left+0.5f+50, Bottom-6));
		timerBox.horizAlign = 0.5;
		timerBox.vertAlign = 0.5;
		timerBox.font = FT_Medium;

		@forBar = GuiProgressbar(this, Alignment(Left+0.5f+50, Top+40, Right-47-74, Bottom-6));
		forBar.backColor = Color(0xffffff40);
		forBar.frontColor = Color(0x00ff00ff);

		GuiSprite failIcon(this, Alignment(Left+76+11, Top+40, Left+76+11+32, Bottom-2), Sprite(spritesheet::VoteIcons, 6));
		setMarkupTooltip(failIcon, locale::INFLUENCE_TT_FAIL);
		GuiSprite passIcon(this, Alignment(Right-43-74, Top+40, Right-11-74, Bottom-2), Sprite(spritesheet::CardCategoryIcons, 4));
		setMarkupTooltip(passIcon, locale::INFLUENCE_TT_PASS);

		@zoomButton = GuiButton(this, Alignment(Right-74-80-47, Top+6, Right-74-47, Top+38));
		zoomButton.visible = false;
		zoomButton.text = locale::ZOOM;
		zoomButton.buttonIcon = icons::Zoom;

		updateAbsolutePosition();
	}

	void set(InfluenceVote@ newVote) {
		//Only update mutable data when set to the same vote
		if(vote !is null && newVote.id == prevId) {
			@vote = newVote;
			update();
			return;
		}
		@vote = newVote;
		prevId = vote.id;

		//Set the data fields
		if(vote.startedBy.major)
			titleBox.text = formatEmpireName(vote.startedBy)+": "+vote.formatTitle();
		else
			titleBox.text = vote.formatTitle();

		Color color;
		if(vote.startedBy !is null && vote.startedBy.major)
			color = vote.startedBy.color;

		string desc = vote.formatDescription();
		if(desc.length != 0) {
			setMarkupTooltip(this, format("[font=Medium][color=$3]$1[/color][/font]\n$2",
						vote.formatTitle(), desc, toString(color)), width=350);
		}
		else {
			setMarkupTooltip(this, "", width=350);
		}

		icon.desc = vote.type.icon;

		if(vote.targets.length != 0 && vote.targets[0].type == TT_Object)
			zoomButton.visible = true;
		else
			zoomButton.visible = false;

		update();
	}

	void update() {
		if(vote is null)
			return;

		string totalText = toString(abs(vote.totalFor - vote.totalAgainst));
		if(vote.totalFor > vote.totalAgainst)
			totalText = "+"+totalText;
		else if(vote.totalAgainst > vote.totalFor)
			totalText = "-"+totalText;
		totalBox.text = totalText;

		Color timerColor;
		string timeText;
		if(vote.totalFor > vote.totalAgainst) {
			totalPic.desc = Sprite(material::ThumbsUp);
			totalBox.color = Color(0x00ff00ff);

			timerColor = Color(0x00ff00ff);
			timeText = formatTime(vote.remainingTime);
		}
		else {
			totalPic.desc = Sprite(material::ThumbsDown);
			totalBox.color = Color(0xff0000ff);

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
	}

	void remove() {
		@vote = null;
		BaseGuiElement::remove();
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		int w = parent.size.width - 32;
		if(size.width != w)
			size = vec2i(w, size.height);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				if(evt.caller is this)
					Hovered = true;
			break;
			case GUI_Mouse_Left:
				if(evt.caller is this)
					Hovered = false;
			break;
			case GUI_Clicked:
				if(evt.caller is zoomButton) {
					if(vote.targets.length != 0 && vote.targets[0].type == TT_Object) {
						zoomTo(vote.targets[0].obj);
						return true;
					}
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source.isChildOf(this)) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0 || event.button == 2)
						return true;
				break;
				case MET_Button_Up:
					if(event.button == 0 || event.button == 2) {
						if(event.button == 2)
							newTab(createInfluenceVoteTab(vote.id));
						else
							browseTab(ActiveTab, createInfluenceVoteTab(vote.id), true);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		Color color;
		if(vote !is null && vote.type !is null)
			color = vote.type.color;
		skin.draw(SS_PatternBox, SF_Normal, AbsolutePosition, color);
		if(Hovered)
			skin.draw(SS_SubtleGlow, SF_Normal, AbsolutePosition, color);
		BaseGuiElement::draw();
	}
};

class TreatyBox : BaseGuiElement, QuestionDialogCallback {
	Treaty treaty;
	GuiMarkupText@ titleBox;
	GuiMarkupText@ signatories;
	GuiSpriteGrid@ clauses;
	GuiButton@ btn;
	GuiButton@ btn1;
	GuiButton@ btn2;

	TreatyBox(IGuiElement@ parent) {
		super(parent, recti(0, 0, parent.size.width - 32, 64));

		@titleBox = GuiMarkupText(this, Alignment(Left+4, Top+6, Right-350, Top+30));
		@signatories = GuiMarkupText(this, Alignment(Left+4, Bottom-30, Right, Bottom-6));
		@clauses = GuiSpriteGrid(this, Alignment(Right-350, Top+6, Right-184, Bottom-6), vec2i(34,34));

		@btn = GuiButton(this, Alignment(Right-184, Top+8, Right-8, Bottom-8));
		btn.visible = false;

		@btn1 = GuiButton(this, Alignment(Right-184, Top+4, Right-8, Top+0.5f-1));
		btn1.visible = false;
		@btn2 = GuiButton(this, Alignment(Right-184, Top+0.5f+1, Right-8, Bottom-4));
		btn2.visible = false;

		updateAbsolutePosition();
	}

	void set(Treaty@ newTreaty) {
		treaty = newTreaty;

		//Update title
		string title;
		if(treaty.leader !is null) {
			title = format("$1's [b]$2[/b]",
					formatEmpireName(treaty.leader),
					treaty.name);
		}
		else {
			title = format("[b]$1[/b]",
					treaty.name);
		}
		titleBox.text = title;

		//Update signatories
		string emps;
		for(uint i = 0, cnt = treaty.joinedEmpires.length; i < cnt; ++i) {
			if(emps.length != 0)
				emps += ", ";
			emps += formatEmpireName(treaty.joinedEmpires[i]);
		}
		if(emps.length == 0)
			emps = locale::NO_SIGNATORIES;
		else
			emps = locale::SIGNED_BY+" "+emps;
		signatories.text = emps;

		//Update clause icons
		clauses.clear();
		for(uint i = 0, cnt = treaty.clauses.length; i < cnt; ++i)
			clauses.add(treaty.clauses[i].type.icon);

		//Update tooltip
		setMarkupTooltip(this, treaty.getTooltip(), width=350);

		//Update button action
		if(treaty.inviteMask & playerEmpire.mask != 0) {
			btn1.text = locale::JOIN_TREATY;
			btn1.buttonIcon = Sprite(material::Propositions);
			btn1.color = colors::Green;

			btn2.text = locale::DECLINE_TREATY;
			btn2.buttonIcon = icons::Remove;
			btn2.color = colors::Red;

			btn.visible = false;
			btn1.visible = true;
			btn2.visible = true;
		}
		else if(treaty.presentMask & playerEmpire.mask != 0 && treaty.canLeave(playerEmpire)) {
			btn.text = treaty.leader is playerEmpire ? locale::DISMISS_TREATY : locale::LEAVE_TREATY;
			btn.buttonIcon = icons::Remove;
			btn.color = colors::Red;
			btn.visible = true;
			btn1.visible = false;
			btn2.visible = false;
		}
		else {
			btn.visible = false;
			btn1.visible = false;
			btn2.visible = false;
		}
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		int w = parent.size.width - 32;
		if(size.width != w)
			size = vec2i(w, size.height);
	}

	void draw() {
		skin.draw(SS_TreatyBox, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			joinTreaty(treaty.id);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is btn) {
					if(treaty.presentMask & playerEmpire.mask != 0 && treaty.canLeave(playerEmpire)) {
						leaveTreaty(treaty.id);
					}
					return true;
				}
				else if(evt.caller is btn1) {
					if(treaty.inviteMask & playerEmpire.mask != 0) {
						if(treaty.hasClause("ConstClause"))
							question(
								locale::PERMANENT_PROMPT,
								locale::JOIN_TREATY, locale::CANCEL,
								this).titleBox.color = Color(0xe00000ff);
						else
							joinTreaty(treaty.id);
					}
					return true;
				}
				else if(evt.caller is btn2) {
					if(treaty.inviteMask & playerEmpire.mask != 0) {
						declineTreaty(treaty.id);
					}
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}
};

class EffectBox : BaseGuiElement {
	int prevId = -1;
	InfluenceEffect@ eff;

	GuiMarkupText@ titleBox;
	GuiText@ timerBox;
	GuiText@ costBox;
	GuiButton@ dismissButton;

	EffectBox(IGuiElement@ parent) {
		super(parent, recti(0, 0, parent.size.width - 32, 32));

		@titleBox = GuiMarkupText(this, Alignment(Left+4, Top+4, Right-432, Top+26));

		@timerBox = GuiText(this, Alignment(Right-428, Top+4, Right-328, Top+26));

		@costBox = GuiText(this, Alignment(Right-328, Top+4, Right-168, Top+26));

		@dismissButton = GuiButton(this, Alignment(Right-164, Top+2, Right-4, Bottom-2), locale::EFFECT_DISMISS);
		dismissButton.buttonIcon = icons::Close;
		updateAbsolutePosition();
	}

	void set(InfluenceEffect@ newEffect) {
		//Only update mutable data when set to the same effect
		if(eff !is null && newEffect.id == prevId) {
			@eff = newEffect;
			prevId = eff.id;
			update();
			return;
		}

		@eff = newEffect;
		prevId = eff.id;

		//Set the data fields
		if(eff.owner !is null && eff.owner.major)
			titleBox.text = formatEmpireName(eff.owner)+": "+eff.formatTitle();
		else
			titleBox.text = eff.formatTitle();

		Color color;
		if(eff.owner !is null && eff.owner.major)
			color = eff.owner.color;
		setMarkupTooltip(this, format("[font=Medium][color=$3]$1[/color][/font]\n$2",
					eff.formatTitle(), eff.formatDescription(), toString(color)), width=350);

		update();
	}

	void update() {
		//Update timer
		if(eff.remainingTime < 0) {
			timerBox.visible = false;
		}
		else {
			timerBox.visible = true;
			timerBox.text = formatTime(eff.remainingTime);

			if(eff.remainingTime < 60.0) {
				timerBox.color = Color(0xff0000ff).interpolate(
					Color(0xffffffff), eff.remainingTime / 60.0);
				timerBox.font = FT_Bold;
			}
			else {
				timerBox.color = Color(0xffffffff);
				timerBox.font = FT_Normal;
			}
		}

		//Update cost
		if(eff.type.reservation != 0) {
			costBox.visible = true;
			costBox.text = format(locale::EFFECT_UPKEEP, toString(eff.type.reservation*100, 0));
		}
		else {
			costBox.visible = false;
		}

		//Update dismissing
		dismissButton.visible = eff.canDismiss(playerEmpire);
	}

	void remove() {
		@eff = null;
		BaseGuiElement::remove();
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		int w = parent.size.width - 32;
		if(size.width != w)
			size = vec2i(w, size.height);
	}

	void draw() {
		skin.draw(SS_InfluenceEffectBox, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is dismissButton) {
					question(locale::EFFECT_CONFIRM_DISMISS, DismissEffect(eff.id));
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}
}

class DismissEffect : QuestionDialogCallback {
	int id;
	DismissEffect(int id) {
		this.id = id;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			dismissInfluenceEffect(id);
	}
}

class WarOption : GuiContextOption {
	Empire@ emp;
	WarOption(Empire@ empire) {
		@emp = empire;
	}

	void call(GuiContextMenu@ menu) {
		question(
			locale::DECLARE_WAR,
			format(locale::PROMPT_WAR, formatEmpireName(emp)),
			locale::DECLARE_WAR, locale::CANCEL,
			WarCallback(emp)).titleBox.color = Color(0xe00000ff);
	}
};

class PeaceOption : GuiContextOption {
	Empire@ emp;
	PeaceOption(Empire@ empire) {
		@emp = empire;
	}

	void call(GuiContextMenu@ menu) {
		sendPeaceOffer(emp);
	}
};

class WarCallback : QuestionDialogCallback {
	Empire@ emp;
	WarCallback(Empire@ onEmpire) {
		@emp = onEmpire;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			declareWar(emp);
	}
};

class ProposeTreatyOption : GuiContextOption {
	Empire@ emp;
	ProposeTreatyOption(Empire@ empire) {
		@emp = empire;
	}

	void call(GuiContextMenu@ menu) {
		TreatyDialog(ActiveTab, emp);
	}
};

class InviteTreatyOption : GuiMarkupContextOption {
	Empire@ emp;
	Treaty treaty;
	InviteTreatyOption(Empire@ empire, Treaty@ treaty) {
		@emp = empire;
		this.treaty = treaty;

		string txt = "[vspace=10/]"+format(locale::INVITE_TO_TREATY, treaty.name, formatEmpireName(empire));
		for(uint i = 0, cnt = treaty.clauses.length; i < cnt; ++i)
			txt += format("  [img=$1;24/]", getSpriteDesc(treaty.clauses[i].type.icon));
		super(txt);
	}

	void call(GuiContextMenu@ menu) {
		inviteToTreaty(treaty.id, emp);
	}
};

class ConquerEdictOption : GuiMarkupContextOption {
	Empire@ emp;
	ConquerEdictOption(Empire@ empire) {
		@emp = empire;
		super("");
	}

	void call(GuiContextMenu@ menu) {
		playerEmpire.conquerEdict(emp);
	}
};

class DemandSurrenderOption : GuiContextOption {
	Empire@ emp;
	DemandSurrenderOption(Empire@ empire) {
		@emp = empire;
	}

	void call(GuiContextMenu@ menu) {
		demandSurrender(emp);
	}
};

class OfferSurrenderOption : GuiContextOption, QuestionDialogCallback {
	Empire@ emp;
	OfferSurrenderOption(Empire@ empire) {
		@emp = empire;
	}

	void call(GuiContextMenu@ menu) {
		question(
			locale::SURRENDER_OPTION,
			format(locale::SURRENDER_PROMPT, formatEmpireName(emp)),
			locale::OFFER, locale::CANCEL,
			this).titleBox.color = Color(0xe00000ff);
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			offerSurrender(emp);
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		drawRectangle(absPos, Color(0xff000020));
		GuiContextOption::draw(ele, flags, absPos);
	}
};

class TreatyDialog : Dialog {
	Empire@ withEmpire;
	GuiMarkupText@ description;
	GuiButton@ accept;
	GuiButton@ cancel;

	GuiText@ nameLabel;
	GuiTextbox@ nameBox;

	GuiPanel@ clausePanel;
	array<const InfluenceClauseType@> clauses;
	array<GuiCheckbox@> clauseChecks;

	TreatyDialog(IGuiElement@ bind, Empire@ withEmpire) {
		@this.withEmpire = withEmpire;
		super(bind, bindInside=true);
		width = 500;
		height = 400;

		@accept = GuiButton(bg, recti());
		accept.text = locale::PROPOSE;
		accept.tabIndex = 100;
		accept.color = Color(0xaaffaaff);
		@accept.callback = this;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;

		@description = GuiMarkupText(window, Alignment(Left+12, Top+32, Right-12, Top+85));
		description.text = locale::TREATY_DESC;

		//Generate a random treaty name
		string genName;
		array<string> names;
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto@ reg = getSystem(i).object;
			if(reg.TradeMask & playerEmpire.mask != 0)
				names.insertLast(reg.name);
			if(reg.visiblePrimaryEmpire is withEmpire)
				names.insertLast(reg.name);
		}
		if(names.length > 0)
			genName = names[randomi(0, names.length-1)];
		else
			genName = getSystem(randomi(0, systemCount-1)).object.name;
		genName = format(locale::TREATY_NAME_GEN, genName);

		//Name input
		@nameLabel = GuiText(window, Alignment(Left+18, Top+85, Left+100, Height=34), locale::NAME);
		nameLabel.font = FT_Bold;
		@nameBox = GuiTextbox(window, Alignment(Left+100, Top+85, Right-18, Height=34), genName);
		nameBox.font = FT_Subtitle;

		//Clause selection
		@clausePanel = GuiPanel(window, Alignment(Left+12, Top+125, Right-12, Bottom-40));
		int y = 0;
		for(uint i = 0, cnt = getInfluenceClauseTypeCount(); i < cnt; ++i) {
			auto@ type = getInfluenceClauseType(i);
			if(!type.freeClause)
				continue;

			GuiSprite(clausePanel, Alignment(Left+12, Top+y, Width=30, Height=30), type.icon);
			clauses.insertLast(type);

			GuiCheckbox check(clausePanel, Alignment(Left+46, Top+y, Right-22, Height=30),
				type.name, type.defaultClause);
			clauseChecks.insertLast(check);
			setMarkupTooltip(check, format("[b]$1[/b]\n$2", type.name, type.description), width=350);

			y += 40;
		}

		addTitle(locale::PROPOSE_TREATY, color=colors::Green);
		alignAcceptButtons(accept, cancel);

		updatePosition();
	}

	void close() {
		close(false);
	}

	void close(bool accepted) {
		if(accepted) {
			Treaty treaty;
			treaty.name = nameBox.text;
			for(uint i = 0, cnt = clauses.length; i < cnt; ++i) {
				if(clauseChecks[i].checked)
					treaty.addClause(clauses[i]);
			}
			treaty.inviteMask |= withEmpire.mask;
			
			createTreaty(treaty);
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
		return Dialog::onGuiEvent(event);
	}
};

class DonationOption : GuiContextOption {
	Empire@ emp;
	IGuiElement@ bind;
	DonationOption(IGuiElement@ bind, Empire@ empire) {
		@emp = empire;
		@this.bind = bind;
	}

	void call(GuiContextMenu@ menu) {
		DonateDialog(findTab(bind), emp);
	}
};

class DonateDialog : Dialog {
	GuiMarkupText@ description;
	GuiOfferList@ offer;
	GuiButton@ accept;
	GuiButton@ cancel;
	Empire@ toEmp;

	DonateDialog(IGuiElement@ bind, Empire@ toEmpire) {
		super(bind, bindInside=true);
		width = 600;
		height = 500;
		@toEmp = toEmpire;

		@accept = GuiButton(bg, recti());
		accept.text = locale::DONATE;
		accept.tabIndex = 100;
		accept.disabled = true;
		@accept.callback = this;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;

		@description = GuiMarkupText(window, Alignment(Left+12, Top+32, Right-12, Top+58));
		addTitle(locale::DONATE_OPTION, color=colors::Green);
		description.text = locale::DONATE_TEXT;
		accept.color = Color(0xaaffaaff);

		alignAcceptButtons(accept, cancel);
		@offer = GuiOfferList(window, Alignment(Left+4, Top+58, Right-4, Bottom-40), prefix="DONATE");

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
			for(uint i = 0, cnt = offer.offers.length; i < cnt; ++i)
				makeDonation(toEmp, offer.offers[i].offer);
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

Sprite getRelationIcon(int num) {
	if(num < 0)
		return Sprite(material::MaskAngry);
	else if(num > 0)
		return Sprite(material::MaskHappy);
	return Sprite(material::MaskNeutral);
}

Tab@ createDiplomacyTab() {
	return DiplomacyTab();
}

void showInfluenceVote(uint voteId) {
	Tab@ tab = findTab(TC_Diplomacy);
	if(tab is null) {
		@tab = createInfluenceVoteTab(voteId);
		newTab(tab);
		switchToTab(tab);
	}
	else {
		InfluenceVoteTab@ ivt = cast<InfluenceVoteTab>(tab);
		if(ivt !is null) {
			ivt.update(voteId);
			switchToTab(ivt);
		}
		else {
			switchToTab(tab);
			browseTab(tab, createInfluenceVoteTab(voteId), true);
		}
	}
}

void showDiplomacy() {
	Tab@ found = findTab(TC_Diplomacy);
	if(cast<DiplomacyTab>(found) !is null)
		switchToTab(found);
	else
		browseTab(TC_Diplomacy, createDiplomacyTab(), true, true);
}

bool isDiplomacyVisible() {
	return cast<DiplomacyTab>(ActiveTab) !is null;
}
