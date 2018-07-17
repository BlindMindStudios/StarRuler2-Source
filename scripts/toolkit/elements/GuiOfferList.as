#section game
import influence;
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiSpinbox;
import elements.GuiIconGrid;
import elements.GuiInfluenceCard;
import elements.GuiDropdown;
import elements.MarkupTooltip;
import icons;
import util.formatting;
import util.icon_view;
import targeting.ObjectTarget;
import artifacts;
from tabs.GalaxyTab import zoomTo;
from tabs.tabbar import findTab;

export GuiOfferList;
export drawDiplomacyOffer;
export getDiplomacyOfferTooltip;
export GuiOfferGrid;

class GuiOfferList : BaseGuiElement {
	GuiPanel@ panel;
	array<GuiOffer@> offers;

	GuiButton@ moneyButton;
	GuiButton@ energyButton;
	GuiButton@ cardButton;
	GuiButton@ fleetButton;
	GuiButton@ planetButton;
	GuiButton@ artifButton;

	GuiOfferList(IGuiElement@ parent, Alignment@ align, const string& prefix = "OFFER") {
		super(parent, align);
		@panel = GuiPanel(this, Alignment().padded(0,90,0,0));

		float x = 0.f, w = 0.33f;
		int y = 0;
		@moneyButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_MONEY"));
		moneyButton.color = colors::Money;
		moneyButton.buttonIcon = icons::Money;
		x += w;

		@energyButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_ENERGY"));
		energyButton.color = colors::Energy;
		energyButton.buttonIcon = icons::Energy;
		x += w;

		@cardButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_CARD"));
		cardButton.color = colors::Influence;
		cardButton.buttonIcon = icons::Action;
		x += w;

		x = 0.f;
		y += 38;

		@fleetButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_FLEET"));
		fleetButton.color = colors::Defense;
		fleetButton.buttonIcon = icons::Strength;
		x += w;

		@planetButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_PLANET"));
		planetButton.color = colors::Planet;
		planetButton.buttonIcon = icons::Planet;
		x += w;

		@artifButton = GuiButton(this, Alignment(Left+4+x, Top+y, Left-4+x+w, Height=34), localize("#"+prefix+"_ARTIFACT"));
		artifButton.color = colors::Artifact;
		artifButton.buttonIcon = icons::Artifact;
		x += w;

		updateAbsolutePosition();
	}

	uint get_length() const {
		return offers.length;
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		uint cnt = offers.length;
		for(uint i = 0; i < cnt; ++i)
			offers[i].rect = recti_area(vec2i(8, i*38), vec2i(size.width-36, 34));
		panel.updateAbsolutePosition();
	}

	void update(array<DiplomacyOffer>& list) {
		uint cnt = list.length;
		offers.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			GuiOffer@ off = offers[i];
			if(off is null || !off.supports(list[i])) {
				if(off !is null)
					off.remove();
				@off = createOffer(panel, list[i]);
				off.load(list[i]);
				@offers[i] = off;
			}
		}
		updateAbsolutePosition();
	}

	void changed() {
		moneyButton.disabled = false;
		energyButton.disabled = false;
		for(uint i = 0, cnt = offers.length; i < cnt; ++i) {
			if(offers[i].offer.type == DOT_Money)
				moneyButton.disabled = true;
			if(offers[i].offer.type == DOT_Energy)
				energyButton.disabled = true;
		}
	}

	void addOffer(GuiOffer@ off) {
		offers.insertLast(off);
		updateAbsolutePosition();
		changed();
		emitChanged();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed && evt.caller !is this) {
			changed();
			emitChanged();
			return true;
		}
		else if(evt.type == GUI_Confirmed) {
			if(evt.value == 1) {
				for(uint i = 0, cnt = offers.length; i < cnt; ++i) {
					auto@ off = offers[i];
					if(evt.caller.isChildOf(off)) {
						off.remove();
						offers.removeAt(i);
						changed();
						emitChanged();
						return true;
					}
				}
			}
		}
		else if(evt.type == GUI_Clicked) {
			if(evt.caller is moneyButton) {
				addOffer(MoneyOffer(panel));
				return true;
			}
			if(evt.caller is energyButton) {
				addOffer(EnergyOffer(panel));
				return true;
			}
			if(evt.caller is cardButton) {
				addOffer(CardOffer(panel));
				return true;
			}
			if(evt.caller is planetButton) {
				targetObject(PlanetOfferTarget(this), findTab(this));
				return true;
			}
			if(evt.caller is fleetButton) {
				targetObject(FleetOfferTarget(this), findTab(this));
				return true;
			}
			if(evt.caller is artifButton) {
				targetObject(ArtifactOfferTarget(this), findTab(this));
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void apply(array<DiplomacyOffer>& list) {
		list.length = offers.length;
		for(uint i = 0, cnt = offers.length; i < cnt; ++i)
			offers[i].apply(list[i]);
	}
};

class GuiOffer : BaseGuiElement {
	DiplomacyOffer offer;
	GuiButton@ removeButton;

	GuiOffer(IGuiElement@ parent) {
		super(parent, recti());

		@removeButton = GuiButton(this, Alignment(Right-34, Top, Right, Bottom));
		removeButton.color = colors::Red;
		GuiSprite(removeButton, Alignment().padded(4), icons::Remove);
		updateAbsolutePosition();
	}

	bool supports(DiplomacyOffer& input) {
		return input.type == offer.type;
	}

	void load(DiplomacyOffer& input) {
		offer = input;
	}

	void apply(DiplomacyOffer& output) {
		apply();
		output = offer;
	}

	void apply() {
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is removeButton) {
			emitConfirmed(1);
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}
};

class MoneyOffer : GuiOffer {
	GuiSprite@ icon;
	GuiText@ label;
	GuiSpinbox@ input;

	MoneyOffer(IGuiElement@ parent) {
		super(parent);
		offer.type = DOT_Money;

		@icon = GuiSprite(this, recti_area(4,4, 28,28), icons::Money);
		@label = GuiText(this, recti_area(40,6, 100,26), locale::OFFER_MONEY);
		label.font = FT_Bold;
		@input = GuiSpinbox(this, Alignment(Left+150, Top+4, Right-40, Bottom),
				num=200, min=100, max=INFINITY, step=100, decimals=0);
		input.color = colors::Money;

		updateAbsolutePosition();
		apply();
	}

	void apply() {
		offer.value = input.value;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed && evt.caller is input) {
			apply();
			emitChanged();
			return true;
		}
		return GuiOffer::onGuiEvent(evt);
	}
};

class EnergyOffer : GuiOffer {
	GuiSprite@ icon;
	GuiText@ label;
	GuiSpinbox@ input;

	EnergyOffer(IGuiElement@ parent) {
		super(parent);
		offer.type = DOT_Energy;

		@icon = GuiSprite(this, recti_area(4,4, 28,28), icons::Energy);
		@label = GuiText(this, recti_area(40,6, 100,26), locale::OFFER_ENERGY);
		label.font = FT_Bold;
		@input = GuiSpinbox(this, Alignment(Left+150, Top+4, Right-40, Bottom),
				num=200, min=100, max=INFINITY, step=100, decimals=0);
		input.color = colors::Energy;

		updateAbsolutePosition();
		apply();
	}

	void apply() {
		offer.value = input.value;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed && evt.caller is input) {
			apply();
			emitChanged();
			return true;
		}
		return GuiOffer::onGuiEvent(evt);
	}
};

class CardOffer : GuiOffer {
	GuiSprite@ icon;
	GuiText@ label;
	GuiDropdown@ selection;
	GuiSpinbox@ input;
	array<InfluenceCard> cards;

	CardOffer(IGuiElement@ parent) {
		super(parent);
		offer.type = DOT_Card;

		@icon = GuiSprite(this, recti_area(4,4, 28,28), icons::Influence);
		@label = GuiText(this, recti_area(40,6, 100,26), locale::OFFER_CARD);
		label.font = FT_Bold;

		@selection = GuiDropdown(this, Alignment(Left+150, Top+4, Right-140, Bottom));
		cards.syncFrom(playerEmpire.getInfluenceCards());

		for(uint i = 0, cnt = cards.length; i < cnt; ++i)
			selection.addItem(GuiMarkupListText(cards[i].formatBlurb()));

		@input = GuiSpinbox(this, Alignment(Right-136, Top+4, Right-40, Bottom),
				num=1, min=1, max=INFINITY, step=1, decimals=0);
		input.font = FT_Bold;

		updateAbsolutePosition();
		apply();
	}

	void apply() {
		if(uint(selection.selected) >= selection.itemCount) {
			offer.id = -1;
		}
		else {
			offer.id = cards[selection.selected].id;
			offer.value = int(input.value);
			icon.desc = cards[selection.selected].type.icon;
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed && (evt.caller is input || evt.caller is selection)) {
			apply();
			emitChanged();
			return true;
		}
		return GuiOffer::onGuiEvent(evt);
	}
};

class ObjectOffer : GuiOffer {
	GuiText@ label;

	ObjectOffer(IGuiElement@ parent, Object@ obj) {
		super(parent);
		if(obj.isPlanet)
			offer.type = DOT_Planet;
		else if(obj.isShip)
			offer.type = DOT_Fleet;
		else if(obj.isArtifact)
			offer.type = DOT_Artifact;
		@offer.obj = obj;

		@label = GuiText(this, Alignment(Left+50, Top, Right-40, Bottom));
		label.font = FT_Bold;
		label.stroke = colors::Black;
		label.color = obj.owner.color;
		label.text = obj.name;

		updateAbsolutePosition();
	}

	void load(DiplomacyOffer& input) {
		offer = input;
		label.color = offer.obj.owner.color;
		label.text = offer.obj.name;
	}

	void draw() override {
		drawObjectIcon(offer.obj, recti_area(AbsolutePosition.topLeft, vec2i(size.height, size.height)));
		GuiOffer::draw();
	}
};

class PlanetOfferTarget : ObjectTargeting {
	GuiOfferList@ list;

	PlanetOfferTarget(GuiOfferList@ list) {
		@this.list = list;
		allowMultiple = true;
	}

	bool valid(Object@ target) {
		return target !is null && target.isPlanet && target.owner is playerEmpire;
	}

	void call(Object@ target) {
		list.addOffer(ObjectOffer(list.panel, target));
	}

	string message(Object@ target, bool valid) {
		return locale::OFFER_PLANET;
	}
};

class FleetOfferTarget : ObjectTargeting {
	GuiOfferList@ list;

	FleetOfferTarget(GuiOfferList@ list) {
		@this.list = list;
		allowMultiple = true;
	}

	bool valid(Object@ target) {
		Ship@ ship = cast<Ship>(target);
		if(ship is null || !ship.valid)
			return false;
		if(!ship.hasLeaderAI || ship.owner !is playerEmpire)
			return false;
		if(ship.blueprint.design.hasTag(ST_CannotDonate))
			return false;
		return true;
	}

	void call(Object@ target) {
		list.addOffer(ObjectOffer(list.panel, target));
	}

	string message(Object@ target, bool valid) {
		return locale::OFFER_FLEET;
	}
};

class ArtifactOfferTarget : ObjectTargeting {
	GuiOfferList@ list;

	ArtifactOfferTarget(GuiOfferList@ list) {
		@this.list = list;
		allowMultiple = true;
	}

	bool valid(Object@ target) {
		if(target is null || !target.isArtifact)
			return false;
		Region@ region = target.region;
		return target.valid && target.owner !is null
			&& (!target.owner.valid || target.owner is playerEmpire)
			&& region !is null && region.TradeMask & playerEmpire.mask != 0
			&& getArtifactType(cast<Artifact>(target).ArtifactType).canDonate;
	}

	void call(Object@ target) {
		list.addOffer(ObjectOffer(list.panel, target));
	}

	string message(Object@ target, bool valid) {
		return locale::OFFER_ARTIFACT;
	}
};

GuiOffer@ createOffer(IGuiElement@ parent, DiplomacyOffer@ input) {
	if(input.type == DOT_Money)
		return MoneyOffer(parent);
	if(input.type == DOT_Energy)
		return EnergyOffer(parent);
	if(input.type == DOT_Planet)
		return ObjectOffer(parent, input.obj);
	if(input.type == DOT_Fleet)
		return ObjectOffer(parent, input.obj);
	return GuiOffer(parent);
}

class GuiOfferGrid : GuiIconGrid {
	array<DiplomacyOffer>@ list;

	GuiOfferGrid(IGuiElement@ parent, const recti& pos) {
		super(parent, recti());
		iconSize = vec2i(64, 34);
		addLazyMarkupTooltip(this, width=300);
	}

	uint get_length() override {
		if(list is null)
			return 0;
		return list.length;
	}

	string get_tooltip() override {
		if(hovered < 0 || hovered >= int(length))
			return "";
		return getDiplomacyOfferTooltip(list[hovered]);
	}

	void drawElement(uint i, const recti& pos) override {
		if(list is null)
			return;
		drawDiplomacyOffer(list[i], pos);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is this && evt.type == GUI_Clicked) {
			if(hovered < 0 || hovered >= int(length))
				return true;
			auto@ off = list[hovered];
			zoomTo(off.obj);
			return true;
		}
		return GuiIconGrid::onGuiEvent(evt);
	}
};

void drawDiplomacyOffer(DiplomacyOffer& offer, const recti& position) {
	switch(offer.type) {
		case DOT_Money:
		{
			icons::Money.draw(recti_area(position.topLeft+vec2i(5,5), vec2i(position.height-10, position.height-10)));
			font::DroidSans_11_Bold.draw(
				pos=position, horizAlign=0.95, vertAlign=0.5,
				text=formatMoney(offer.value), stroke=colors::Black);
		}
		break;
		case DOT_Energy:
		{
			icons::Energy.draw(recti_area(position.topLeft+vec2i(5,5), vec2i(position.height-10, position.height-10)));
			font::DroidSans_11_Bold.draw(
				pos=position, horizAlign=0.95, vertAlign=0.5,
				text=standardize(offer.value, true), stroke=colors::Black);
		}
		break;
		case DOT_Planet:
		{
			drawObjectIcon(offer.obj, position.aspectAligned(1.0));
			font::DroidSans_8.draw(
				pos=position, horizAlign=0.5, vertAlign=0.0,
				text=offer.obj.name, stroke=colors::Black);
		}
		break;
		case DOT_Fleet:
		{
			drawObjectIcon(offer.obj, position.aspectAligned(1.0));
			font::DroidSans_8.draw(
				pos=position, horizAlign=0.5, vertAlign=0.0,
				text=formatShipName(cast<Ship>(offer.obj)), stroke=colors::Black);
		}
		break;
		case DOT_Artifact:
		{
			icons::Artifact.draw(position.aspectAligned(1.0));
			font::DroidSans_8.draw(
				pos=position, horizAlign=0.5, vertAlign=0.0,
				text=formatObjectName(offer.obj), stroke=colors::Black);
		}
		break;
		case DOT_Card:
		{
			InfluenceCard card;
			if(offer.bound !is null && receive(offer.bound.getInfluenceCard(offer.id), card)) {
				drawCardIcon(card, position, int(offer.value));
				font::DroidSans_8.draw(
					pos=position, horizAlign=0.5, vertAlign=0.0,
					text=card.formatTitle(pretty=false), stroke=colors::Black);
				if(int(offer.value) != 0) {
					font::DroidSans_8.draw(
						pos=position, horizAlign=0.5, vertAlign=1.0,
						text=toString(int(offer.value),0)+"x", stroke=colors::Black,
						color=colors::Red);
				}
			}
		}
		break;
	}
}

string getDiplomacyOfferTooltip(DiplomacyOffer& offer) {
	switch(offer.type) {
		case DOT_Planet:
		case DOT_Fleet:
			return format(locale::OFFER_TT_OBJ, offer.blurb);
	}
	return format(locale::OFFER_TT, offer.blurb);
}
