import elements.BaseGuiElement;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiButton;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.GuiContextMenu;
import elements.GuiProgressbar;
import elements.MarkupTooltip;
import targeting.ObjectTarget;
import resources;
import research;
import icons;
#include "include/resource_constants.as"

import tabs.tabbar;
from tabs.ResearchTab import createResearchTab;
from tabs.DiplomacyTab import createDiplomacyTab;

const double UPDATE_INTERVAL = 0.05;

class ResourceDisplay : BaseGuiElement {
	Color color;
	GuiSprite@ icon;
	BaseGuiElement@ value;
	int padding = 4;
	MarkupTooltip@ ttip;

	GuiMarkupText@ upperText;
	GuiMarkupText@ lowerText;

	ResourceDisplay(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);
		updateAbsolutePosition();
		@value = BaseGuiElement(this, recti());

		@ttip = MarkupTooltip("", 320, 0.5f, true, false);
		ttip.StaticPosition = true;
		ttip.Lazy = true;
		ttip.LazyUpdate = true;
		@tooltipObject = ttip;
	}

	void addIcon(const Sprite& sprt) {
		@icon = GuiSprite(this, recti_area(vec2i(), sprt.size));
		icon.desc = sprt;
	}

	void addTexts() {
		@upperText = GuiMarkupText(value, recti());
		upperText.defaultFont = FT_Medium;
		upperText.memo = true;
		@lowerText = GuiMarkupText(value, recti());
		lowerText.memo = true;
		lowerText.defaultColor = Color(0xaaaaaaff);
	}

	int get_baseValueWidth() {
		return 0;
	}

	void update() {
		//Center the elements
		int width = 0;
		if(icon !is null)
			width += icon.size.width + padding;

		if(value !is null) {
			int valueWidth = this.baseValueWidth;
			if(upperText !is null) {
				valueWidth = max(valueWidth, upperText.textWidth);
				upperText.position = vec2i(0, 1);
				upperText.size = vec2i(300, size.height/2);
			}
			if(lowerText !is null) {
				valueWidth = max(valueWidth, lowerText.textWidth);
				lowerText.position = vec2i(2, size.height/2-1);
				lowerText.size = vec2i(300, size.height/2);
			}
			width += valueWidth;
			value.size = vec2i(valueWidth+padding, size.height);
		}

		int pos = (size.width - width) / 2;
		if(icon !is null) {
			icon.position = vec2i(pos, (size.height - icon.size.height) / 2 - 2);
			pos += icon.size.width + padding;
		}
		if(value !is null) {
			value.size = vec2i(value.size.width, size.height);
			value.position = vec2i(pos, 0);
		}
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		if(value !is null)
			update();
		if(ttip !is null) {
			ttip.width = max(size.width, 250);
			ttip.offset = absolutePosition.topLeft + vec2i(min(size.width-250,0), size.height);
		}
	}

	void draw() {
		skin.draw(SS_PlainBox, SF_Normal, AbsolutePosition.padded(0,-2,0,1));

		Color topColor = color;
		topColor.a = 0x30;

		Color botColor = color;
		botColor.a = 0x10;

		drawRectangle(AbsolutePosition, topColor, topColor, botColor, botColor);

		BaseGuiElement::draw();
	}
};

class InfluenceResource : ResourceDisplay {
	InfluenceResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::Influence;
		addIcon(icons::Influence);
		addTexts();
	}

	string get_tooltip() {
		return format(locale::GTT_INFLUENCE,
				toString(playerEmpire.Influence),
				toString(playerEmpire.InfluenceCap, 0),
				formatIncomeRate(playerEmpire.InfluenceIncome, perMinute=true),
				toString(playerEmpire.InfluencePercentage*100.0, 0)+"%",
				toString(playerEmpire.getInfluenceStock(), 0));
	}

	void update() {
		int influence = playerEmpire.Influence;
		double income = playerEmpire.InfluenceIncome;
		double percentage = playerEmpire.InfluencePercentage;
		double efficiency = playerEmpire.InfluenceEfficiency;
		int cap = playerEmpire.InfluenceCap;

		Color storedColor = colors::White;
		if(efficiency < 1.0 - 0.01)
			storedColor = Color(0xff0000ff).interpolate(storedColor, efficiency);

		upperText.text = format(
				"[color=$3]$1[/color][color=#aaa][vspace=6][font=Normal]/$2[/font][/vspace][/color]",
				toString(influence), toString(cap), toString(storedColor));

		lowerText.text = format(
				"$1 ($2%)",
				formatIncomeRate(income, perMinute=true), toString(percentage * 100.f, 0));
		ResourceDisplay::update();
	}
};

class EnergyResource : ResourceDisplay {
	EnergyResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::Energy;
		addIcon(icons::Energy);
		addTexts();
	}

	string get_tooltip() {
		double income = playerEmpire.EnergyIncome - playerEmpire.EnergyUse;
		double factor = playerEmpire.EnergyEfficiency;
		if(income > 0)
			income *= factor;

		return format(locale::GTT_ENERGY,
				toString(playerEmpire.EnergyStored, 0),
				formatIncomeRate(income),
				toString(playerEmpire.FreeEnergyStorage, 0),
				"-"+toString((1.0-factor)*100.0, 0)+"%");
	}

	void update() {
		double stored = playerEmpire.EnergyStored;
		double income = playerEmpire.EnergyIncome - playerEmpire.EnergyUse;
		double factor = playerEmpire.EnergyEfficiency;
		if(income > 0)
			income *= factor;

		upperText.text = toString(stored, 0);
		lowerText.text = formatIncomeRate(income);
		ResourceDisplay::update();
	}
};

class FTLResource : ResourceDisplay {
	FTLResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::FTLResource;
		addIcon(icons::FTL);
		addTexts();
	}

	string get_tooltip() {
		return format(locale::GTT_FTL,
				toString(playerEmpire.FTLStored, 0),
				toString(playerEmpire.FTLCapacity, 0),
				formatIncomeRate(playerEmpire.FTLIncome - playerEmpire.FTLUse));
	}

	void update() {
		double stored = playerEmpire.FTLStored;
		double income = playerEmpire.FTLIncome - playerEmpire.FTLUse;
		double capacity = playerEmpire.FTLCapacity;

		upperText.text = format(
				"$1[color=#aaa][vspace=6][font=Normal]/$2[/font][/vspace][/color]",
				toString(stored, 0), toString(capacity, 0));

		lowerText.text = formatIncomeRate(income);
		ResourceDisplay::update();
	}
};

class ResearchResource : ResourceDisplay {
	array<TechnologyNode> researching;

	GuiProgressbar@ techBar;
	GuiSprite@ techIcon;

	ResearchResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::Research;
		addIcon(icons::Research);
		addTexts();

		@techBar = GuiProgressbar(value, Alignment(Left, Bottom-0.5f+3, Left+100, Bottom-4));
		techBar.strokeColor = colors::Black;
		techBar.textHorizAlign = 0.9;
		@techIcon = GuiSprite(techBar, Alignment(Left+2, Top+0.5f-12, Left+2+24, Top+0.5f+12));
		techIcon.noClip = true;
	}

	int get_baseValueWidth() {
		if(techBar is null || !techBar.visible)
			return 0;
		return 100;
	}

	string get_tooltip() {
		string tt = format(locale::GTT_RESEARCH,
				toString(playerEmpire.ResearchPoints, 0),
				formatIncomeRate(playerEmpire.ResearchRate));
		for(uint i = 0, cnt = researching.length; i < cnt; ++i) {
			tt += "\n"+format(locale::GTT_RESEARCH_TECH,
				researching[i].type.name, formatTime(researching[i].timer),
				toString(researching[i].type.color));
		}
		return tt;
	}

	void update() {
		double stored = playerEmpire.ResearchPoints;
		double income = playerEmpire.ResearchRate;

		upperText.text = toString(stored, 0);
		lowerText.text = formatIncomeRate(income);

		researching.syncFrom(playerEmpire.getResearchingNodes());
		if(researching.length != 0) {
			researching.sortAsc();

			techBar.visible = true;
			lowerText.visible = false;

			auto@ activeTech = researching[0];
			techBar.text = formatTime(activeTech.timer);
			techIcon.desc = activeTech.type.icon;
			techBar.frontColor = activeTech.type.color;
			techBar.textColor = activeTech.type.color.interpolate(colors::White, 0.75f);
			techBar.progress = 1.0 - (activeTech.timer / activeTech.getTimeCost(playerEmpire));
		}
		else {
			techBar.visible = false;
			lowerText.visible = true;
		}

		ResourceDisplay::update();
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

class BudgetResource : ResourceDisplay {
	array<TechnologyNode> researching;

	GuiProgressbar@ cycleBar;

	GuiButton@ welfareButton;
	GuiSprite@ welfareIcon;

	GuiText@ nextBudget;

	BudgetResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::Money;
		addIcon(icons::Money);
		addTexts();

		@cycleBar = GuiProgressbar(value, Alignment(Left, Bottom-0.5f+3, Left+120, Bottom-4));
		cycleBar.font = FT_Small;
		
		@nextBudget = GuiText(value, Alignment(Left+120, Bottom-0.5f+1, Left+200, Bottom-1));
		nextBudget.horizAlign = 0.5;

		@welfareButton = GuiButton(value, Alignment(Right-84+40-25, Top, Width=50, Height=24));
		@welfareIcon = GuiSprite(welfareButton, Alignment(Left+8, Top-5, Right-8, Bottom+5),
				Sprite(spritesheet::ConvertIcon, 0));

		setMarkupTooltip(welfareButton, locale::WELFARE_TT, hoverStyle=false);
	}

	int get_baseValueWidth() {
		return 200;
	}

	string get_tooltip() {
		string tt = format(locale::GTT_MONEY,
				formatMoneyChange(playerEmpire.RemainingBudget, colored=true),
				formatMoneyChange(playerEmpire.EstNextBudget, colored=true),
				formatTime(playerEmpire.BudgetCycle - playerEmpire.BudgetTimer),
				getSpriteDesc(welfareIcon.desc));
		tt += format("\n[font=Medium]$1[/font]\n", locale::RESOURCE_BUDGET);
		for(int i = MoT_COUNT - 1; i >= 0; --i) {
			int money = playerEmpire.getMoneyFromType(i);
			if(money != 0) {
				tt += format("$1: [right]$2[/right]",
					localize("MONEY_TYPE_"+i), formatMoneyChange(money, true));
			}
		}

		int bonusMoney = playerEmpire.BonusBudget;
		if(bonusMoney != 0)
			tt += "\n\n"+format(locale::GTT_BONUS_MONEY, formatMoney(bonusMoney));

		float debtFactor = playerEmpire.DebtFactor;
		if(debtFactor > 1.f) {
			float effFactor = pow(0.5f, debtFactor-1.f);
			tt += "\n\n"+format(locale::GTT_FLEET_PENALTY, "-"+toString((1.f - effFactor)*100.f, 0)+"%");
		}
		if(debtFactor > 0.f) {
			float growthFactor = 1.f;
			for(; debtFactor > 0; debtFactor -= 1.f)
				growthFactor *= 0.33f + 0.67f * (1.f - min(debtFactor, 1.f));
			tt += "\n\n"+format(locale::GTT_DEBT_PENALTY, "-"+toString((1.f - growthFactor)*100.f, 0)+"%");
		}
		return tt;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is welfareButton && evt.type == GUI_Clicked) {
			GuiContextMenu menu(mousePos);
			menu.itemHeight = 54;
			string money = formatMoney(350.0 / playerEmpire.WelfareEfficiency);
			menu.addOption(ChangeWelfare(format(locale::WELFARE_INFLUENCE, money), 0));
			menu.addOption(ChangeWelfare(format(locale::WELFARE_ENERGY, money), 1));
			menu.addOption(ChangeWelfare(format(locale::WELFARE_RESEARCH, money), 2));
			menu.addOption(ChangeWelfare(format(locale::WELFARE_LABOR, money), 3));
			menu.addOption(ChangeWelfare(format(locale::WELFARE_DEFENSE, money), 4));
			menu.updateAbsolutePosition();
			return true;
		}
		return ResourceDisplay::onGuiEvent(evt);
	}

	void update() {
		//NOTE: Maybe related to spectating?
		if(playerEmpire is null)
			return;
		
		//Current budget
		int curBudget = playerEmpire.RemainingBudget;
		int bonusBudget = playerEmpire.BonusBudget;

		Color color(0xffffffff);
		if(curBudget < 0)
			color = Color(0xff0000ff);
		else if(curBudget - bonusBudget < 0)
			color = Color(0xff8000ff);
		else
			color = Color(0xffffffff);

		upperText.defaultColor = color;
		upperText.text = formatMoney(curBudget, roundUp=false);

		welfareIcon.desc = Sprite(spritesheet::ConvertIcon, playerEmpire.WelfareMode);

		//Cycle timer
		double cycle = playerEmpire.BudgetCycle;
		double timer = playerEmpire.BudgetTimer;

		cycleBar.text = formatTime(cycle - timer);
		if(cycle == 0)
			cycleBar.progress = 0.f;
		else
			cycleBar.progress = timer / cycle;

		if(cycleBar.progress < (1.0 / 3.0))
			cycleBar.frontColor = colors::Money;
		else if(cycleBar.progress < (2.0 / 3.0))
			cycleBar.frontColor = colors::Money.interpolate(colors::Red, 0.3);
		else
			cycleBar.frontColor = colors::Money.interpolate(colors::Red, 0.6);

		//Next budget
		int upcoming = playerEmpire.EstNextBudget;
		if(upcoming < 0)
			nextBudget.color = Color(0xbb0000ff);
		else
			nextBudget.color = Color(0xbbbbbbff);
		nextBudget.text = formatMoney(upcoming);

		ResourceDisplay::update();
	}
};

class DeployTarget : ObjectTargeting {
	DeployTarget() {
		icon = icons::Defense;
	}

	void call(Object@ target) {
		playerEmpire.deployDefense(target);
	}

	string message(Object@ obj, bool valid) {
		return locale::TT_DEPLOY;
	}

	bool valid(Object@ obj) {
		if(!obj.isPlanet)
			return false;
		return obj.owner !is null && obj.owner.valid;
	}
};

class DefenseResource : ResourceDisplay {
	GuiProgressbar@ bar;
	GuiButton@ button;

	DefenseResource(IGuiElement@ parent, Alignment@ align) {
		super(parent, align);

		color = colors::Defense;
		addIcon(icons::Defense);
		addTexts();

		@bar = GuiProgressbar(value, Alignment(Left, Bottom-0.5f+3, Left+100, Bottom-4));
		bar.frontColor = colors::Defense;
		bar.font = FT_Small;
		bar.visible = false;

		@button = GuiButton(value, Alignment(Left+70, Top+2, Left+100, Top+28));
		GuiSprite(button, Alignment().padded(-2), icons::Strength);
		button.visible = false;
		setMarkupTooltip(button, locale::TT_DEPLOY);
	}

	string get_tooltip() {
		return format(locale::GTT_DEFENSE,
				standardize(playerEmpire.globalDefenseRate * 60.0 / DEFENSE_LABOR_PM, true)+locale::PER_MINUTE,
				standardize(playerEmpire.globalDefenseStorage, true),
				standardize(playerEmpire.globalDefenseStored, true));
	}

	int get_baseValueWidth() {
		return bar.visible ? 100 : 0;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.caller is button && evt.type == GUI_Clicked) {
			targetObject(DeployTarget());
			return true;
		}
		return ResourceDisplay::onGuiEvent(evt);
	}

	void update() {
		double income = playerEmpire.globalDefenseRate / DEFENSE_LABOR_PM;
		upperText.text = format(
				"$1[color=#aaa][vspace=6][font=Normal]$2[/font][/vspace][/color]",
				toString(income * 60.0, 0), locale::PER_MINUTE);
		ResourceDisplay::update();

		double storage = playerEmpire.globalDefenseStorage;
		double stored = playerEmpire.globalDefenseStored;

		if(storage == 0) {
			upperText.position = vec2i(0, 8);
			bar.visible = false;
			button.visible = false;
		}
		else {
			upperText.position = vec2i(0, 1);
			bar.text = standardize(floor(stored), true)+" / "+standardize(storage, true);
			bar.progress= stored / storage;
			bar.visible = true;
			button.visible = stored >= storage*0.9999;
		}
	}
};

class GlobalBar : BaseGuiElement {
	BaseGuiElement@ container;
	double updateTimer = -INFINITY;

	array<ResourceDisplay@> sections;
	ResourceDisplay@ budget;
	ResourceDisplay@ energy;
	ResourceDisplay@ ftl;
	ResourceDisplay@ influence;
	ResourceDisplay@ research;
	ResourceDisplay@ defense;

	GlobalBar() {
		super(null, recti());

		@container = BaseGuiElement(this, Alignment_Fill());
		container.StrictBounds = true;

		@budget = BudgetResource(container, Alignment());
		sections.insertLast(budget);

		@influence = InfluenceResource(container, Alignment());
		sections.insertLast(influence);

		@energy = EnergyResource(container, Alignment());
		sections.insertLast(energy);

		@ftl = FTLResource(container, Alignment());
		sections.insertLast(ftl);

		@research = ResearchResource(container, Alignment());
		sections.insertLast(research);

		@defense = DefenseResource(container, Alignment());
		sections.insertLast(defense);
		
		updateSections();
	}

	void update() {
		for(uint i = 0, cnt = sections.length; i < cnt; ++i)
			sections[i].update();
	}

	void updateSections(){ 
		float x = 0.f;
		for(uint i = 0, cnt = sections.length; i < cnt; ++i) {
			float w;
			if(size.width >= 1600)
				w = 1.f / 6.f;
			else if(i == 0)
				w = 1.f / 5.f;
			else
				w = (1.f - (1.f / 5.f)) / 5.f;

			sections[i].alignment = Alignment(Left+x, Top, Left+x+w, Bottom);
			x += w;
		}
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		int width = AbsolutePosition.width;
		BaseGuiElement::updateAbsolutePosition();
		if(width != AbsolutePosition.width)
			updateSections();
	}

	void draw() {
		if(frameTime - UPDATE_INTERVAL >= updateTimer) {
			update();
			updateTimer = frameTime;
		}

		skin.draw(SS_GlobalBar, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
}

BaseGuiElement@ createGlobalBar() {
	return GlobalBar();
}

void preReload(Message& msg) {
	globalBar.remove();
}

void postReload(Message& msg) {
	@globalBar = GlobalBar();
	@globalBar.alignment = Alignment(Left, Top+TAB_HEIGHT + 2, Right, Top+TAB_HEIGHT + 2 + GLOBAL_BAR_HEIGHT);
}

void deploy_defense(bool pressed) {
	if(pressed)
		targetObject(DeployTarget());
}

void init() {
	keybinds::Global.addBind(KB_DEPLOY_DEFENSE, "deploy_defense");
}
