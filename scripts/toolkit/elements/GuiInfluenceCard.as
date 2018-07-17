#section disable menu
import elements.BaseGuiElement;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiSprite;
import elements.GuiOverlay;
import elements.GuiDropdown;
import elements.GuiSkinElement;
import elements.GuiButton;
import elements.GuiMarkupText;
import elements.GuiEmpire;
import elements.MarkupTooltip;
import elements.GuiBackgroundPanel;
import influence;
import icons;
import hooks;
import util.formatting;
from gui import animate_time, navigateInto;

#section game
import tabs.Tab;
import targeting.ObjectTarget;
#section all

export GuiInfluenceCard;
export updateCardList;
export GuiInfluenceCardPopup;
export GUI_CARD_WIDTH, GUI_CARD_HEIGHT;
export drawCardIcon;

const int GUI_CARD_WIDTH = 207;
const int GUI_CARD_HEIGHT = 137;

const vec2i CARD_ART_OFFSET(2, 32);
const vec2i CARD_ART_SIZE(201,99);

class GuiInfluenceCard : BaseGuiElement {
	InfluenceCard@ card;
	bool Hovered = false;
	bool Focused = false;
	bool Pressed = false;
	bool disabled = false;
	Color disabledColor;

	Color cardColor = colors::White;
	GuiMarkupText@ title;

	GuiSprite@ qualityIcon;
	GuiSprite@ typeIcon;

	GuiSprite@ leaderIcon;

	GuiEmpire@ empireIcon;
	GuiSprite@ purchaseIcon;
	GuiText@ purchaseCost;

	array<GuiSprite@> varIcons;
	array<GuiText@> varTexts;

	GuiInfluenceCard(IGuiElement@ ParentElement) {
		super(ParentElement, recti(0, 0, GUI_CARD_WIDTH, GUI_CARD_HEIGHT));
		updateAbsolutePosition();

		@title = GuiMarkupText(this, recti(10, 5, GUI_CARD_WIDTH - 10, 30));

		@leaderIcon = GuiSprite(this, recti_area(8, 34, 34, 34));
		leaderIcon.desc = Sprite(material::LeaderIcon);
		setMarkupTooltip(leaderIcon, locale::TT_LEADER_CARD, false);
		leaderIcon.visible = false;

		@purchaseIcon = GuiSprite(this, recti_area(GUI_CARD_WIDTH - 50, GUI_CARD_HEIGHT - 50, 44, 44));
		purchaseIcon.desc = icons::InfluencePurchaseCost;
		@purchaseCost = GuiText(this, recti_area(GUI_CARD_WIDTH - 120, GUI_CARD_HEIGHT - 45, 70, 44));
		purchaseCost.vertAlign = 0.5;
		purchaseCost.horizAlign = 1.0;
		purchaseCost.font = FT_Big;
		purchaseCost.stroke = colors::Black;

		@typeIcon = GuiSprite(this, recti_area(GUI_CARD_WIDTH - 42, 34, 34, 34));

		@qualityIcon = GuiSprite(this, recti_area(GUI_CARD_WIDTH - 72, 6, 64, 22));
		qualityIcon.color = Color(0xffffff40);
		setMarkupTooltip(qualityIcon, locale::INFLUENCE_TT_QUALITY, false);

		navigable = true;
	}

	void set(InfluenceCard@ c, InfluenceVote@ vote = null, bool showVariables = true, bool centerTitle = false) {
		@card = c;

		//Title on top
		string ttext = card.formatTitle();
		if(showVariables) {
			if(card.uses < 0)
				ttext += " ("+locale::USES_UNLIMITED+")";
			else if(card.uses > 1)
				ttext += " ("+card.uses+"x)";
		}

		if(ttext.length > 20) {
			title.defaultFont = FT_Small;
			title.position = vec2i(6, 6);
		}
		else {
			title.defaultFont = FT_Normal;
			title.position = vec2i(10, 4);
		}
		if(centerTitle)
			ttext = "[center]"+ttext+"[/center]";
		title.text = ttext;
		title.updateAbsolutePosition();

		typeIcon.desc = getInfluenceCardClassSprite(card.type.cls);
		leaderIcon.visible = card.type.leaderOnly;
		setMarkupTooltip(typeIcon, getInfluenceCardClassTooltip(card.type.cls), false);

		//Purchase cost
		auto@ stackCard = cast<StackInfluenceCard>(c);
		disabled = false;
		if(stackCard !is null) {
			if(stackCard.purchasedBy !is null) {
				if(empireIcon is null) {
					@empireIcon = GuiEmpire(this, Alignment(Right-60, Bottom-60, Width=55, Height=55));
					empireIcon.padding = 4;
					empireIcon.background = SS_EmpireBox;
				}

				if(playerEmpire.valid && playerEmpire.ContactMask & stackCard.purchasedBy.mask != 0) {
					empireIcon.visible = true;
					@empireIcon.empire = stackCard.purchasedBy;
					setMarkupTooltip(empireIcon, format(locale::INFLUENCE_TT_BOUGHTBY,
								formatEmpireName(stackCard.purchasedBy)), false);
				}
				else {
					empireIcon.visible = false;
				}

				purchaseIcon.visible = false;
				purchaseCost.visible = false;
				disabled = true;
				disabledColor = stackCard.purchasedBy.color;
			}
			else {
				int cost = card.getPurchaseCost(playerEmpire);
				bool canPurchase = card.canPurchase(playerEmpire);

				purchaseIcon.visible = canPurchase;
				purchaseCost.visible = canPurchase;
				purchaseCost.text = toString(cost);
				purchaseCost.font = FT_Big;

				if(canPurchase) {
					string tt = format(locale::INFLUENCE_TT_BUY_COST, toString(cost));
					setMarkupTooltip(purchaseIcon, tt, false);
					setMarkupTooltip(purchaseCost, tt, false);
				}

				if(empireIcon !is null)
					empireIcon.visible = false;
			}
		}
		else {
			purchaseIcon.visible = false;
			purchaseCost.visible = false;

			if(empireIcon !is null)
				empireIcon.visible = false;
		}

		//Rarity
		cardColor = getInfluenceCardRarityColor(c.type.rarity);

		//Quality
		if(c.quality > c.type.minQuality) {
			int qlev = c.quality - c.type.minQuality;

			int qdist = c.type.maxQuality - c.type.minQuality + 1;
			if(qdist > 4)
				qlev = floor(double(qlev) / double(qdist) * 4) + 1;

			if(qlev > 0) {
				qualityIcon.desc = Sprite(spritesheet::PlanetLevelIcons, qlev-1);
				qualityIcon.visible = true;
			}
			else {
				qualityIcon.visible = false;
			}
		}
		else {
			qualityIcon.visible = false;
		}

		//Variables
		uint index = 0;
		Sprite sprt;
		string name, text, tooltip;
		bool highlight = false;
		if(showVariables) {
			if(card.getCostVariable(sprt, name, tooltip, text, highlight, vote = vote))
				addVar(index, IVM_Property, sprt, name,  tooltip,text, highlight);
			if(card.getWeightVariable(sprt, name, tooltip, text, highlight, vote = vote))
				addVar(index, IVM_Property, sprt, name,  tooltip,text, highlight);
			for(uint i = 0, cnt = card.type.hooks.length; i < cnt; ++i) {
				uint mode = card.type.hooks[i].getVariable(card, vote, sprt, name, tooltip, text, highlight);
				if(mode != IVM_None)
					addVar(index, mode, sprt, name, tooltip, text, highlight);
			}
		}
		for(uint i = index, cnt = varIcons.length; i < cnt; ++i) {
			varIcons[i].remove();
			varTexts[i].remove();
		}
		varIcons.length = index;
		varTexts.length = index;
	}

	void addVar(uint& index, uint mode, const Sprite& sprt, const string& name, const string& tooltip, const string& text, bool highlight) {
		if(mode == IVM_PurchaseCost) {
			if(purchaseIcon !is null) {
				purchaseIcon.desc = sprt;
				purchaseCost.text = text;
				if(purchaseCost.getTextDimension().x >= purchaseCost.size.width)
					purchaseCost.font = FT_Medium;
				else
					purchaseCost.font = FT_Big;
			}
			return;
		}

		if(varIcons.length <= index) {
			varIcons.resize(index+1);
			varTexts.resize(index+1);
		}

		auto@ icon = varIcons[index];
		if(icon is null) {
			@icon = GuiSprite(this, recti_area(vec2i(8, GUI_CARD_HEIGHT - 30 - 26*index), vec2i(24, 24)));
			@varIcons[index] = icon;
		}

		setMarkupTooltip(icon, tooltip, false);
		icon.desc = sprt;

		auto@ txt = varTexts[index];
		if(txt is null) {
			@txt = GuiText(this, recti_area(vec2i(38, GUI_CARD_HEIGHT - 29 - 26*index), vec2i(40, 24)));
			txt.stroke = colors::Black;
			@varTexts[index] = txt;
		}

		setMarkupTooltip(txt, tooltip, false);
		txt.text = text;

		if(highlight) {
			txt.font = FT_Bold;
			txt.color = Color(0xffcd00ff);
		}
		else {
			txt.font = FT_Normal;
			txt.color = colors::White;
		}

		index += 1;
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hovered = true;
				break;
				case GUI_Mouse_Left:
					Hovered = false;
				break;
				case GUI_Focused:
					Focused = true;
				break;
				case GUI_Focus_Lost:
					Focused = false;
				break;
				case GUI_Controller_Down:
					if(event.caller is this) {
						if(event.value == GP_A) {
							Pressed = true;
							return true;
						}
					}
				break;
				case GUI_Controller_Up:
					if(Focused) {
						if(event.value == GP_A) {
							Pressed = false;
							emitClicked();
							return true;
						}
					}
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case MET_Button_Down:
				if(event.button == 0) {
					Pressed = true;
					return true;
				}
			break;
			case MET_Button_Up:
				if(event.button == 0) {
					if(Pressed) {
						Pressed = false;
						emitClicked();
					}
					return true;
				}
			break;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
	
	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
	}

	uint get_flags() {
		uint flags = SF_Normal;
		if(disabled)
			flags |= SF_Disabled;
		if(Pressed)
			flags |= SF_Active;
		if(Hovered)
			flags |= SF_Hovered;
		if(Focused)
			flags |= SF_Focused;
		return flags;
	}
	
	void draw() {
		if(card is null)
			return;

		uint index = 0;
		if(Hovered)
			index = 2;
		else if(Pressed || Focused)
			index = 1;

		if(card.uses > 1)
			spritesheet::ActionCard.draw(index, AbsolutePosition+vec2i(3,3), cardColor);
		recti ipos = recti_area(AbsolutePosition.topLeft+CARD_ART_OFFSET, CARD_ART_SIZE);
		drawRectangle(ipos, Color(0x202020ff));
		if(card.type.icon.valid)
			card.type.icon.draw(ipos.aspectAligned(card.type.icon.aspect));
		spritesheet::ActionCard.draw(index, AbsolutePosition, cardColor);
		if(disabled)
			spritesheet::ActionCard.draw(4, AbsolutePosition, disabledColor);
		skin.draw(SS_FullTitle, SF_Normal, recti_area(
			AbsolutePosition.topLeft + vec2i(2, 2),
			vec2i(GUI_CARD_WIDTH - 6, 30)), card.type.color);
		BaseGuiElement::draw();
	}
};

int updateCardList(IGuiElement@ panel, array<InfluenceCard@> cards, GuiInfluenceCard@[]@ boxes, double horizAlign = 0.0, InfluenceVote@ vote = null, bool filterPlayable = true) {
	uint oldCnt = boxes.length;
	uint newCnt = cards.length;

	//Remove old boxes
	for(uint i = newCnt; i < oldCnt; ++i) {
		if(boxes[i] !is null)
			boxes[i].remove();
	}
	boxes.length = newCnt;

	//Do alignment
	vec2i pos(4, 4);
	if(horizAlign != 0.0) {
		int perRow = floor(double(panel.size.width) / double(GUI_CARD_WIDTH + 4));
		int rowWidth = min(perRow, newCnt) * (GUI_CARD_WIDTH + 4);
		pos.x = (panel.size.width - rowWidth) / 2;
	}

	//Update boxes
	uint n = 0;
	for(uint i = 0; i < newCnt; ++i) {
		//Figure out if the card is usable
		if(vote !is null) {
			if(filterPlayable) {
				if(!cards[i].canPlay(vote, null))
					continue;
			}
			else {
				if(cards[i].type.cls != ICC_Support)
					continue;
			}
		}

		//Create box if needed
		if(boxes[n] is null)
			@boxes[n] = GuiInfluenceCard(panel);

		//Update the card box
		GuiInfluenceCard@ box = boxes[n];
		box.set(cards[i], vote);

		//Position the card
		box.position = pos;

		pos.x += GUI_CARD_WIDTH + 4;
		if(pos.x + GUI_CARD_WIDTH > panel.size.width - 20) {
			pos.x = 4;
			pos.y += GUI_CARD_HEIGHT + 4;
		}
		++n;
	}

	for(uint i = n; i < newCnt; ++i) {
		if(boxes[i] !is null) {
			boxes[i].remove();
			@boxes[i] = null;
		}
	}

	if(pos.x == 4)
		return pos.y;
	else
		return pos.y + GUI_CARD_HEIGHT + 4;
}

final class TargetingOption {
	uint target = uint(-1);
	GuiDropdown@ dropdown;
	GuiTextbox@ textbox;
	array<Target@> potentials;
	Target defaultTarget;

	TargetingOption(uint index) {
		target = index;
	}

	void create(IGuiElement@ elem, int y, Target@ target) {
		Alignment align(Left+CARD_ART_SIZE.x+30, Bottom-y, Right-30, Bottom-y+34);
		if(target.type == TT_String)
			@textbox = GuiTextbox(elem, align, target.str);
		else
			@dropdown = GuiDropdown(elem, align);
		defaultTarget = target;
	}

	void add(InfluenceCard@ card, Target@ targ, const string& name) {
		if(!card.isValidTarget(target, targ))
			return;
		if(dropdown is null)
			return;

		dropdown.addItem(GuiMarkupListText(name));
		potentials.insertLast(targ);

		if(targ == defaultTarget)
			dropdown.selected = potentials.length - 1;
	}

	void fill(Targets@ targets) {
		if(target >= targets.targets.length)
			return;

		if(dropdown !is null) {
			uint sel = uint(dropdown.selected);
			if(sel >= potentials.length) {
				targets[target].filled = false;
				return;
			}

			targets[target].filled = true;
			targets[target] = potentials[sel];
		}
		else if(textbox !is null) {
			targets[target].filled = true;
			targets[target].str = textbox.text;
		}
	}
};

class GuiInfluenceCardPopup : BaseGuiElement {
	GuiOverlay@ overlay;
	IGuiElement@ around;
	int cardId = -1;
	int cost = 0;
	bool animating = false;

	int awaitsObjectTarget = -1;

	InfluenceVote@ vote;
	InfluenceCard@ card;
	Targets targets;

	GuiBackgroundPanel@ panel;
	GuiSprite@ qualityIcon;
	GuiSprite@ image;
	GuiMarkupText@ description;

	array<TargetingOption@> options;
	array<Empire@> targetEmpireList;

	GuiButton@ supportButton;
	GuiButton@ opposeButton;

	bool haveButtons = false;

	GuiButton@ purchaseButton;
	GuiSprite@ purchaseIcon;
	GuiText@ purchaseCost;

	GuiButton@ playButton;

	array<GuiSprite@> varIcons;
	array<GuiText@> varNames;
	array<GuiText@> varTexts;

	GuiInfluenceCardPopup(IGuiElement@ Parent, IGuiElement@ Around, InfluenceCard@ card, bool animate = true, InfluenceVote@ vote = null, bool playable = true) {
		@around = Around;
		@overlay = GuiOverlay(Parent);
		overlay.closeSelf = false;
		super(overlay, recti(0, 0, 600, 400));
		@this.card = card;
		@this.vote = vote;
		cardId = card.id;

		targets = card.targets;
		card.targetDefaults(targets);

		@panel = GuiBackgroundPanel(this, Alignment_Fill());
		panel.titleStyle = SS_FullTitle;
		panel.markup = true;
		panel.titleColor = card.type.color;

		string ttext = card.formatTitle();
		if(card.uses < 0)
			ttext += " ("+locale::USES_UNLIMITED+")";
		else if(card.uses > 1)
			ttext += " ("+card.uses+"x)";
		panel.title = ttext;

		//Quality
		@qualityIcon = GuiSprite(panel, Alignment(Right-72, Top+6, Width=64, Height=22));
		qualityIcon.color = Color(0xffffff40);
		setMarkupTooltip(qualityIcon, locale::INFLUENCE_TT_QUALITY, false);

		if(card.quality > card.type.minQuality) {
			int qlev = card.quality - card.type.minQuality;

			int qdist = card.type.maxQuality - card.type.minQuality + 1;
			if(qdist > 4)
				qlev = floor(double(qlev) / double(qdist) * 4) + 1;

			if(qlev > 0) {
				qualityIcon.desc = Sprite(spritesheet::PlanetLevelIcons, qlev-1);
				qualityIcon.visible = true;
			}
			else {
				qualityIcon.visible = false;
			}
		}
		else {
			qualityIcon.visible = false;
		}

		@image = GuiSprite(this, recti_area(vec2i(16, 36), CARD_ART_SIZE));
		image.desc = card.type.icon;

		@description = GuiMarkupText(this, recti(26+CARD_ART_SIZE.x, 36, size.width-16, CARD_ART_SIZE.y+96));
		description.text = card.formatDescription();

		int btnWidth = (size.width - CARD_ART_SIZE.x - 42);
		int btnStart = CARD_ART_SIZE.x + 30;
		if(cast<StackInfluenceCard>(card) !is null) {
			bool canPurchase = card.canPurchase(playerEmpire);

			if(canPurchase) {
				@purchaseIcon = GuiSprite(this, Alignment(Right-50, Bottom-50, Width=44, Height=44));
				purchaseIcon.desc = icons::InfluencePurchaseCost;

				@purchaseCost = GuiText(this, Alignment(Right-120, Bottom-45, Width=70, Height=44));
				purchaseCost.vertAlign = 0.5;
				purchaseCost.horizAlign = 1.0;
				purchaseCost.font = FT_Big;

				cost = card.getPurchaseCost(playerEmpire);
				purchaseCost.text = toString(cost);

				@purchaseButton = GuiButton(this, Alignment(
							Left+((btnWidth-160)/2+btnStart), Bottom-44,
							Width=160, Height=34), locale::PURCHASE_CARD);
				purchaseButton.color = Color(0x20adffff);
				purchaseButton.disabled = !card.hasPurchaseCost(playerEmpire);
				haveButtons = true;
			}
		}
		else if(playable) {
			if(card.type.cls == ICC_Support) {
				if(vote !is null) {
					if(card.type.sideMode == ICS_Neutral) {
						@playButton = GuiButton(this, Alignment(
									Left+((btnWidth-160)/2+btnStart), Bottom-44,
									Width=160, Height=34), locale::PLAY_NEUTRAL);
						playButton.color = Color(0xffad20ff);
						haveButtons = true;
					}
					else if(card.type.sideMode == ICS_Both) {
						@supportButton = GuiButton(this, Alignment(
									Left+((btnWidth-160)/2+btnStart)-84, Bottom-44,
									Width=160, Height=34), locale::PLAY_SUPPORT);
						supportButton.color = Color(0xddffdbff);
						haveButtons = true;

						@opposeButton = GuiButton(this, Alignment(
									Left+((btnWidth-160)/2+btnStart)+84, Bottom-44,
									Width=160, Height=34), locale::PLAY_OPPOSE);
						opposeButton.color = Color(0xffe3dbff);
						haveButtons = true;
					}
					else if(card.type.sideMode == ICS_Support) {
						@supportButton = GuiButton(this, Alignment(
									Left+((btnWidth-160)/2+btnStart), Bottom-44,
									Width=160, Height=34), locale::PLAY_SUPPORT);
						supportButton.color = Color(0xddffdbff);
						haveButtons = true;
					}
					else if(card.type.sideMode == ICS_Oppose) {
						@opposeButton = GuiButton(this, Alignment(
									Left+((btnWidth-160)/2+btnStart), Bottom-44,
									Width=160, Height=34), locale::PLAY_OPPOSE);
						opposeButton.color = Color(0xffe3dbff);
						haveButtons = true;
					}
				}
			}
			else {
				@playButton = GuiButton(this, Alignment(
							Left+((btnWidth-160)/2+btnStart), Bottom-44,
							Width=160, Height=34), locale::PLAY_CARD);
				playButton.color = Color(0xffad20ff);
				haveButtons = true;
			}

			if(haveButtons) {
				uint targCnt = targets.targets.length;
				int y = 82;
				for(uint i = 0; i < targCnt; ++i) {
					auto@ targ = targets.targets[i];
					if(card.targets[i].filled)
						continue;
					if(targ.type == TT_Empire) {
						TargetingOption opt(i);
						opt.create(this, y, targ);
						options.insertLast(opt);

						for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
							Empire@ emp = getEmpire(i);
							if(!emp.major)
								continue;
							if(playerEmpire.ContactMask & emp.mask == 0)
								continue;

							Target targ(TT_Empire);
							targ.filled = true;
							@targ.emp = emp;

							opt.add(card, targ, formatEmpireName(emp));
						}

						y += 40;
					}
					else if(targ.type == TT_Card) {
						array<InfluenceCard> cards;
						cards.syncFrom(playerEmpire.getInfluenceCards());

						TargetingOption opt(i);
						opt.create(this, y, targ);
						options.insertLast(opt);

						for(uint i = 0, cnt = cards.length; i < cnt; ++i) {
							auto@ c = cards[i];

							Target targ(TT_Card);
							targ.filled = true;
							targ.id = c.id;

							opt.add(card, targ, c.formatBlurb());
						}

						y += 40;
					}
					else if(targ.type == TT_Effect) {
						array<InfluenceEffect> effects;
						effects.syncFrom(getActiveInfluenceEffects());

						TargetingOption opt(i);
						opt.create(this, y, targ);
						options.insertLast(opt);

						for(uint i = 0, cnt = effects.length; i < cnt; ++i) {
							auto@ eff = effects[i];
							if(eff.owner !is null && playerEmpire.valid && playerEmpire.ContactMask & eff.owner.mask == 0)
								continue;

							Target targ(TT_Effect);
							targ.filled = true;
							targ.id = eff.id;

							string title = eff.formatTitle();
							title = format("$3: [color=$2]$1[/color]", title, toString(eff.type.color), formatEmpireName(eff.owner));

							opt.add(card, targ, title);
						}

						y += 40;
					}
					else if(targ.type == TT_String) {
						TargetingOption opt(i);
						opt.create(this, y, targ);
						options.insertLast(opt);
						
						y += 40;
					}
					else if(targ.type == TT_Object) {
						awaitsObjectTarget = int(i);
					}
				}
			}
		}

		//Add variables
		uint index = 0;
		Sprite sprt;
		string name, text, tooltip;
		bool highlight = false;
		if(card.getCostVariable(sprt, name, tooltip, text, highlight, vote=vote))
			addVar(index, IVM_Property, sprt, name, tooltip, text, highlight);
		if(card.getWeightVariable(sprt, name, tooltip, text, highlight, vote=vote))
			addVar(index, IVM_Property, sprt, name, tooltip, text, highlight);
		for(uint i = 0, cnt = card.type.hooks.length; i < cnt; ++i) {
			uint mode = card.type.hooks[i].getVariable(card, vote, sprt, name, tooltip, text, highlight);
			if(mode != IVM_None)
				addVar(index, mode, sprt, name, tooltip, text, highlight);
		}

		for(uint i = index, cnt = varIcons.length; i < cnt; ++i) {
			varIcons[i].remove();
			varTexts[i].remove();
		}
		varIcons.length = index;
		varTexts.length = index;

		updateAbsolutePosition();
		if(animate) {
			recti target = targetPosition;
			rect = around.absolutePosition - Parent.absolutePosition.topLeft;
			animating = true;
			animate_time(this, target, 0.2);
		}

		navigateInto(this);
		onChange();
	}

	void onChange() {
		bool playable = true;
		for(uint i = 0, cnt = options.length; i < cnt; ++i) {
			options[i].fill(targets);
			if(!card.isValidTarget(options[i].target, targets.targets[options[i].target]))
				playable = false;
		}

		if(awaitsObjectTarget == -1 && playable) {
			if(vote !is null)
				playable = card.canPlay(vote, targets);
			else
				playable = card.canPlay(targets);
		}

		if(card.type.sideMode != ICS_Neutral) {
			auto@ targ = targets.fill("VoteSide");
			if(targ !is null) {
				if(supportButton !is null) {
					targ.side = true;
					supportButton.disabled = !card.canPlay(vote, targets)
						|| playerEmpire.Influence < card.getPlayCost(vote, targets);
				}
				if(opposeButton !is null) {
					targ.side = false;
					opposeButton.disabled = !card.canPlay(vote, targets)
						|| playerEmpire.Influence < card.getPlayCost(vote, targets);
				}
			}
		}

		if(playButton !is null) {
			if(vote !is null) {
				playButton.disabled = !playable
					|| playerEmpire.Influence < card.getPlayCost(vote, targets);
			}
			else {
				playButton.disabled = !playable
					|| (playerEmpire.Influence < card.getPlayCost(null, targets) && awaitsObjectTarget == -1);
			}
		}

		if(purchaseButton !is null) {
			int cost = card.getPurchaseCost(playerEmpire);
			purchaseButton.disabled = !card.hasPurchaseCost(playerEmpire);
		}
	}

	void addVar(uint& index, uint mode, const Sprite& sprt, const string& name, const string& tooltip, const string& text, bool highlight) {
		if(mode == IVM_PurchaseCost) {
			if(purchaseIcon !is null) {
				purchaseIcon.desc = sprt;
				purchaseCost.text = text;
				if(purchaseCost.getTextDimension().x >= purchaseCost.size.width)
					purchaseCost.font = FT_Medium;
				else
					purchaseCost.font = FT_Big;
			}
			return;
		}

		if(varIcons.length <= index) {
			varIcons.resize(index+1);
			varTexts.resize(index+1);
			varNames.resize(index+1);
		}

		auto@ icon = varIcons[index];
		if(icon is null) {
			@icon = GuiSprite(this, Alignment(Left+8, Bottom - 30 - 26*index, Width=24, Height=24));
			@varIcons[index] = icon;
		}

		icon.desc = sprt;
		setMarkupTooltip(icon, tooltip, false);

		auto@ nm = varNames[index];
		if(nm is null) {
			@nm = GuiText(this, Alignment(Left+38, Bottom - 32 - 26*index, Width=CARD_ART_SIZE.x-90, Height=30));
			@varNames[index] = nm;
		}

		nm.text = name;
		setMarkupTooltip(nm, tooltip, false);

		auto@ txt = varTexts[index];
		if(txt is null) {
			@txt = GuiText(this, Alignment(Left+CARD_ART_SIZE.x-50, Bottom - 32 - 26*index, Width=50, Height=30));
			txt.horizAlign = 1.0;
			@varTexts[index] = txt;
		}

		txt.text = text;
		setMarkupTooltip(txt, tooltip, false);

		if(highlight) {
			txt.font = FT_Bold;
			txt.color = Color(0xffcd00ff);
		}
		else {
			txt.font = FT_Normal;
			txt.color = colors::White;
		}

		index += 1;
	}

	void play() {
		for(uint i = 0, cnt = options.length; i < cnt; ++i)
			options[i].fill(targets);

		if(vote !is null) {
			if(awaitsObjectTarget != -1) {
#section game
				targetObject(CardTargeting(card, uint(awaitsObjectTarget), targets, vote), cast<Tab>(overlay.parent));
#section all
			}
			else {
				sound::card_play.play(priority=true);
				playInfluenceCard(cardId, targets, voteId = vote.id);
			}
		}
		else {
			if(awaitsObjectTarget != -1) {
#section game
				targetObject(CardTargeting(card, uint(awaitsObjectTarget), targets), cast<Tab>(overlay.parent));
#section all
			}
			else {
				sound::card_play.play(priority=true);
				playInfluenceCard(cardId, targets);
			}
		}
		overlay.close();
		emitConfirmed();
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Clicked:
				if(event.caller is supportButton) {
					targets.fill("VoteSide").side = true;
					for(uint i = 0, cnt = options.length; i < cnt; ++i)
						options[i].fill(targets);
					if(awaitsObjectTarget != -1) {
#section game
						targetObject(CardTargeting(card, uint(awaitsObjectTarget), targets, vote), cast<Tab>(overlay.parent));
#section all
					}
					else {
						sound::card_play.play(priority=true);
						playInfluenceCard(cardId, targets, voteId = vote.id);
					}
					overlay.close();
					emitConfirmed();
					return true;
				}
				else if(event.caller is opposeButton) {
					targets.fill("VoteSide").side = false;
					for(uint i = 0, cnt = options.length; i < cnt; ++i)
						options[i].fill(targets);
					if(awaitsObjectTarget != -1) {
#section game
						targetObject(CardTargeting(card, uint(awaitsObjectTarget), targets, vote), cast<Tab>(overlay.parent));
#section all
					}
					else {
						sound::card_play.play(priority=true);
						playInfluenceCard(cardId, targets, voteId = vote.id);
					}
					overlay.close();
					emitConfirmed();
					return true;
				}
				else if(event.caller is purchaseButton) {
					sound::card_draw.play(priority=true);
					buyCardFromInfluenceStack(cardId);
					overlay.close();
					emitConfirmed();
					return true;
				}
				else if(event.caller is playButton) {
					play();
					return true;
				}
			break;
			case GUI_Confirmed:
				if(event.caller !is this) {
					if(playButton !is null)
						play();
					return true;
				}
			break;
			case GUI_Changed:
				onChange();
				return true;
			case GUI_Animation_Complete:
				animating = false;
				updateAbsolutePosition();
				return true;
			case GUI_Controller_Down:
				return true;
			case GUI_Controller_Up:
				overlay.close();
				return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	recti get_targetPosition() {
		if(around is null || overlay is null || overlay.parent is null)
			return recti();

		int bpos = CARD_ART_SIZE.y + varTexts.length * 30;
		int afterdesc = 8 + 40 * options.length;
		if(haveButtons)
			afterdesc += 40;
		bpos = max(bpos, description.size.height + afterdesc);

		vec2i sz = vec2i(size.width, bpos+38);
		vec2i pos = (around.absolutePosition.topLeft - overlay.parent.absolutePosition.topLeft);
		pos -= (sz - around.size) / 2;
		if(pos.x < 4)
			pos.x = 4;
		if(pos.x + sz.x > overlay.size.x - 4)
			pos.x = overlay.size.x - sz.x - 4;
		if(pos.y < 4)
			pos.y = 4;
		if(pos.y + sz.y > overlay.size.y - 4)
			pos.y = overlay.size.y - sz.y - 4;
		return recti_area(pos, sz);
	}

	void updateAbsolutePosition() {
		if(!animating)
			rect = targetPosition;
		BaseGuiElement::updateAbsolutePosition();
	}

	void remove() {
		setGuiFocus(around);
		@around = null;
		BaseGuiElement::remove();
	}

	double update = 0.0;
	void draw() override {
		update += frameLength;
		if(update >= 1.0) {
			onChange();
			update = 0.0;
		}
		BaseGuiElement::draw();
	}
};

void drawCardIcon(const InfluenceCard@ card, const recti& pos, int uses = 0) {
	Sprite icon = card.type.icon;
	vec2i iconSize = icon.size;
	recti iconPos;
	if(uses == 0)
		uses = card.uses;
	if(iconSize.y != 0) {
		iconPos = pos.padded(6, 6);
		iconPos = iconPos.aspectAligned(double(iconSize.width) / double(iconSize.height));
	}

	Empire@ purchaser;
	auto@ stackCard = cast<const StackInfluenceCard@>(card);
	if(stackCard !is null)
		@purchaser = stackCard.purchasedBy;

	Color col;
	if(purchaser !is null)
		col = purchaser.color;

	icon.draw(iconPos);

	//Draw uses
	int x = 4;
	if(uses > 1) {
		for(int i = 0; i < uses; ++i) {
			drawRectangle(recti_area(vec2i(pos.topLeft.x+x, pos.botRight.y-9), vec2i(5, 5)), Color(0x991c1cff));
			x += 8;
		}
	}

	//Draw quality
	uint quality = card.extraQuality;
	x = pos.size.x - 9;
	for(uint i = 0; i < quality; ++i) {
		drawRectangle(recti_area(vec2i(pos.topLeft.x+x, pos.topLeft.y+4), vec2i(5, 5)), Color(0xe4d154ff));
		x -= 8;
	}

	//Draw purchaser
	if(purchaser !is null)
		spritesheet::ContextIcons.draw(1, iconPos, col);
}

#section game
class CardTargeting : ObjectTargeting {
	InfluenceCard@ card;
	Targets@ targets;
	uint index;
	InfluenceVote@ vote;

	bool canPlay = false;
	bool canPay = false;

	CardTargeting(InfluenceCard@ card, uint index, Targets@ targets, InfluenceVote@ vote = null) {
		this.index = index;
		@this.vote = vote;
		@this.card = card;
		@this.targets = targets;
	}

	bool valid(Object@ obj) override {
		@targets.targets[index].obj = obj;
		targets.targets[index].filled = true;
		if(vote is null) {
			if(!card.canPlay(targets)) {
				canPlay = false;
				return false;
			}
		}
		else {
			if(!card.canPlay(vote, targets)) {
				canPlay = false;
				return false;
			}
		}
		canPlay = true;
		if(playerEmpire.Influence < card.getPlayCost(vote, targets)) {
			canPay = false;
			return false;
		}
		canPay = false;
		return true;
	}

	void call(Object@ obj) override {
		@targets.targets[index].obj = obj;
		targets.targets[index].filled = true;
		sound::card_play.play(priority=true);
		if(vote is null)
			playInfluenceCard(card.id, targets);
		else
			playInfluenceCard(card.id, targets, voteId = vote.id);
	}

	string message(Object@ obj, bool valid) override {
		if(!canPlay)
			return card.formatTitle(pretty=false);
		@targets.targets[index].obj = obj;
		targets.targets[index].filled = true;
		int cost = card.getPlayCost(vote, targets);
		return format(locale::PLAY_CARD_OPTION, card.formatTitle(pretty=false), toString(cost));
	}

	string desc(Object@ target, bool valid) {
		if(valid)
			return "";
		@targets[index].obj = target;
		targets[index].filled = true;
		return card.getTargetError(targets);
	}
};
#section all
