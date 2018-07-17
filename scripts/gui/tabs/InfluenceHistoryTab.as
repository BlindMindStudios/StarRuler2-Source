import tabs.Tab;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiSkinElement;
import elements.GuiBackgroundPanel;
import influence;
import util.formatting;

from tabs.tabbar import popTab, browseTab, get_ActiveTab;
from tabs.InfluenceVoteTab import createInfluenceVoteTab;

const double UPDATE_TIMER = 1.0;

class InfluenceHistoryTab : Tab {
	uint limit = 10;
	int beforeId = -1;
	bool reverse = true;

	GuiBackgroundPanel@ bg;

	GuiButton@ backButton;
	GuiButton@ olderButton;
	GuiButton@ newerButton;

	InfluenceVote[] votes;
	VoteBox@[] boxes;

	double updateTime = 0.0;

	InfluenceHistoryTab() {
		super();
		title = locale::VOTE_HISTORY;

		@bg = GuiBackgroundPanel(this, Alignment(Left+8, Top+8, Right-8, Bottom-8));
		bg.title = locale::VOTE_HISTORY;
		bg.titleColor = Color(0x00bffeff);
		bg.picture = Sprite(material::Propositions);

		@backButton = GuiButton(this, recti(14, 40, 212, 70), locale::DIPLOMACY_BACK);

		@newerButton = GuiButton(this, Alignment(Left+0.5f-222, Top+40, Left+0.5f-2, Top+70), locale::NEWER);

		@olderButton = GuiButton(this, Alignment(Left+0.5f+2, Top+40, Left+0.5f+222, Top+70), locale::OLDER);

		update();
		updateAbsolutePosition();
	}

	void tick(double time) {
		updateTime -= time;
		if(updateTime <= 0) {
			update();
			updateTime += UPDATE_TIMER;
		}
	}

	void update() {
		if(reverse) {
			votes.syncFrom(getInfluenceVoteHistory(limit+1, beforeId, true));
		}
		else {
			votes.syncFrom(getInfluenceVoteHistory(limit+1, beforeId, false));
			if(votes.length <= limit) {
				beforeId = -1;
			}
			else {
				beforeId = votes[limit].id;
				votes.removeAt(limit);
			}
			votes.reverse();
		}

		uint oldCnt = boxes.length;
		uint newCnt = min(votes.length, limit);
		for(uint i = newCnt; i < oldCnt; ++i)
			boxes[i].remove();
		boxes.length = newCnt;

		for(uint i = 0; i < newCnt; ++i) {
			if(boxes[i] is null)
				@boxes[i] = VoteBox(this);
			boxes[i].set(votes[i]);
			boxes[i].position = vec2i(16, 78 + i * 32);
		}

		olderButton.disabled = reverse && votes.length <= limit;
		newerButton.disabled = votes.length == 0 || beforeId == -1;
		reverse = true;
	}

	void hide() {
		Tab::hide();
	}

	void updateAbsolutePosition() {
		//Update box list size
		uint show = max((size.height - 80) / 32, 2);
		if(show != limit) {
			limit = show;
			update();
		}

		Tab::updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is backButton) {
				popTab(this);
				return true;
			}
			else if(event.caller is olderButton) {
				if(votes.length < limit)
					return true;
				beforeId = votes[limit-1].id;
				update();
				return true;
			}
			else if(event.caller is newerButton) {
				if(votes.length == 0)
					return true;
				reverse = false;
				beforeId = votes[0].id;
				update();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
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

class VoteBox : BaseGuiElement {
	uint prevId = uint(-1);
	InfluenceVote@ vote;

	GuiText@ timeBox;
	GuiMarkupText@ titleBox;
	GuiText@ statusBox;

	GuiButton@ detailsButton;

	VoteBox(IGuiElement@ parent) {
		super(parent, recti(0, 0, parent.size.width - 48, 32));

		@timeBox = GuiText(this, recti(4, 6, 120, 26));
		timeBox.font = FT_Small;
		timeBox.color = Color(0x888888ff);
		timeBox.horizAlign = 0.5;

		@titleBox = GuiMarkupText(this, Alignment(Left+124, Top+6, Right-208, Top+26));

		@statusBox = GuiText(this, Alignment(Right-204, Top+6, Right-4, Top+26));

		@detailsButton = GuiButton(this, Alignment(Right-84, Top+4, Right-4, Top+28), locale::VIEW);
		updateAbsolutePosition();
	}

	void set(InfluenceVote@ newVote) {
		//Only update data when set to a different vote
		if(vote !is null && newVote.id == prevId) {
			@vote = newVote;
			return;
		}

		@vote = newVote;
		prevId = vote.id;

		//Set the data fields
		titleBox.text = formatEmpireName(vote.startedBy)+": "+vote.formatTitle();
		timeBox.text = formatGameTime(vote.startedAt)+" - "+formatGameTime(vote.endedAt);

		if(vote.succeeded) {
			statusBox.text = locale::PASSED;
			statusBox.color = Color(0x00ff00ff);
		}
		else {
			statusBox.text = locale::FAILED;
			statusBox.color = Color(0xff0000ff);
		}
	}

	void remove() {
		@vote = null;
		BaseGuiElement::remove();
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();

		int w = parent.size.width - 24;
		if(size.width != w)
			size = vec2i(w, size.height);
	}

	void draw() {
		skin.draw(SS_InfluenceVoteBox, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is detailsButton) {
					browseTab(ActiveTab, createInfluenceVoteTab(vote.id), true);
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}
};

Tab@ createInfluenceHistoryTab() {
	return InfluenceHistoryTab();
}

