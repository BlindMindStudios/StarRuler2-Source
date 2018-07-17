import tabs.Tab;
import elements.GuiButton;
import elements.GuiProgressbar;
import elements.GuiPanel;
import elements.GuiMarkupText;
import elements.GuiEmpire;
import elements.GuiOverlay;
import elements.GuiSkinElement;
import elements.MarkupTooltip;
import dialogs.QuestionDialog;
import attitudes;
import abilities;

from overlays.InfoBar import AbilityAction;

import tabs.tabbar;

class LevelMarker : BaseGuiElement {
	const AttitudeLevel@ lvl;
	Color color;
	bool reached;
	bool hovered = false;

	LevelMarker(IGuiElement@ parent) {
		super(parent, recti(0,0, 42,70));
		noClip = true;
		auto@ tt = addLazyMarkupTooltip(this, width=300);
		tt.FollowMouse = false;
		tt.offset = vec2i(0, 5);
	}

	string get_tooltip() {
		string tt;
		tt += format("[font=Medium]$1 $2[/font]\n", locale::LEVEL, toString(lvl.level+1));
		tt += lvl.description;
		return tt;
	}

	void update(Attitude& att) {
		double finalProgress = att.levels[att.maxLevel].threshold;
		double pct = clamp(lvl.threshold / finalProgress, 0.0, 1.0);

		reached = att.level >= lvl.level+1;
		position = vec2i(parent.size.x * pct - size.width / 2, 0);

		if(reached)
			color = Color(0x000000ff).interpolate(att.type.color, 0.4);
		else
			color = Color(0x666666ff);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Entered:
				if(evt.caller is this)
					hovered = true;
			break;
			case GUI_Mouse_Left:
				if(evt.caller is this)
					hovered = false;
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() override {
		if(hovered) {
			drawLine(AbsolutePosition.topLeft + vec2i(size.width/2, 2),
					 AbsolutePosition.topLeft + vec2i(size.width/2, size.height-35),
					 Color(0xffffff40), 12);
		}

		drawLine(AbsolutePosition.topLeft + vec2i(size.width/2, 2),
				 AbsolutePosition.topLeft + vec2i(size.width/2, size.height),
				 Color(0x00000080), 5);

		drawLine(AbsolutePosition.topLeft + vec2i(size.width/2, 2),
				 AbsolutePosition.topLeft + vec2i(size.width/2, size.height),
				 color, 3);

		recti iconPos = recti_area(5,size.height-32, 32,32) + AbsolutePosition.topLeft;
		if(hovered)
			drawRectangle(iconPos.padded(-4), Color(0xffffff40));
		drawRectangle(iconPos.padded(-2), Color(0x00000080));
		drawRectangle(iconPos, color);

		lvl.icon.draw(iconPos.aspectAligned(lvl.icon.aspect));
		BaseGuiElement::draw();
	}
};

class DiscardConfirm : QuestionDialogCallback {
	const AttitudeType@ type;

	DiscardConfirm(const AttitudeType@ type) {
		@this.type = type;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			playerEmpire.discardAttitude(type.id);
	}
};

class AttitudeBox : BaseGuiElement {
	Attitude@ att;

	GuiMarkupText@ title;
	GuiMarkupText@ progressText;
	GuiProgressbar@ bar;

	array<LevelMarker@> markers;
	array<AbilityAction@> abilities;

	GuiButton@ discardButton;
	GuiMarkupText@ discardText;

	AttitudeBox(IGuiElement@ parent) {
		super(parent, recti());

		@title = GuiMarkupText(this, Alignment(Left+12, Top+8, Right-12, Top+40));
		title.defaultFont = FT_Medium;
		title.defaultStroke = colors::Black;

		@progressText = GuiMarkupText(this, Alignment(Left+20, Top+36, Right-12, Top+65));
		progressText.defaultColor = Color(0x888888ff);
		progressText.defaultStroke = colors::Black;

		@bar = GuiProgressbar(this, Alignment(Left+12, Top+65, Right-220, Top+110));

		@discardButton = GuiButton(this, Alignment(Right-140, Top+3, Right-4, Top+36));
		discardButton.color = colors::Red;
		@discardText = GuiMarkupText(discardButton, Alignment(Left, Top+6, Right, Bottom));
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.type == GUI_Clicked) {
			if(event.caller is discardButton) {
				auto@ diag = question(format(locale::ATT_CONFIRM_DISCARD, att.type.name),
						locale::DISCARD, locale::CANCEL, DiscardConfirm(att.type));
				diag.titleBox.color = Color(0xff0000ff);
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void update() {
		if(att is null || att.type is null)
			return;
		updateAbsolutePosition();

		double curProgress = att.progress;
		double nextProgress = att.levels[att.nextLevel].threshold;
		double finalProgress = att.levels[att.maxLevel].threshold;

		//Progress data
		if(nextProgress > curProgress) {
			progressText.text = format("[color=#aaa][b]$1 $2:[/b][/color] $3",
				locale::LEVEL, toString(att.nextLevel), 
				format(att.type.progress, toString(nextProgress-curProgress, 0)));
		}
		else {
			progressText.text = locale::ATT_MAX_LEVEL;
		}

		title.text = att.type.name;
		bar.frontColor = att.type.color;
		bar.progress = curProgress / finalProgress;

		//Level markers
		uint prevCnt = markers.length;
		uint newCnt = att.type.levels.length;
		for(uint i = newCnt; i < prevCnt; ++i)
			markers[i].remove();
		markers.length = newCnt;
		for(uint i = prevCnt; i < newCnt; ++i)
			@markers[i] = LevelMarker(bar);

		for(uint i = 0; i < newCnt; ++i) {
			@markers[i].lvl = att.type.levels[i];
			markers[i].update(att);
		}

		//Discarding
		int discardCost = att.getDiscardCost(playerEmpire);
		discardText.text = "[center]"+format(locale::ATT_DISCARD, toString(discardCost))+"[/center]";
		discardButton.disabled = playerEmpire.Influence < discardCost;

		//Abilities
		prevCnt = abilities.length;
		newCnt = 0;

		for(uint i = 0, cnt = att.allHookCount; i < cnt; ++i) {
			Ability@ abl;
			if(newCnt < prevCnt)
				@abl = abilities[newCnt].abl;
			@abl = att.allHooks[i].showAbility(att, playerEmpire, abl);
			if(abl !is null) {
				if(newCnt >= prevCnt) {
					AbilityAction act(abl, abl.type.name);
					act.independent = true;
					@act.parent = this;
					abilities.insertLast(act);
				}
				newCnt += 1;
			}
		}

		for(uint i = newCnt; i < prevCnt; ++i)
			abilities[i].remove();

		int y = 62;
		if(newCnt > 1)
			y = 40;
		abilities.length = newCnt;
		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			auto@ btn = abilities[i];
			btn.init();
			btn.position = vec2i(size.width-184, y);
			btn.size = vec2i(172, 50);
			y += 50;
		}
	}

	void addAbility(Ability@ abl, uint& newCnt) {
	}

	void draw() override {
		if(att is null || att.type is null)
			return;
		skin.draw(SS_EmpireBox, SF_Normal, AbsolutePosition, att.type.color);
		BaseGuiElement::draw();
	}
};

class AttitudesTab : Tab {
	array<AttitudeBox@> boxes;
	array<Attitude> attitudes;

	GuiButton@ takeButton;
	GuiMarkupText@ takeText;

	GuiSkinElement@ header;
	GuiEmpire@ portrait;
	GuiMarkupText@ headerText;

	GuiPanel@ panel;

	AttitudesTab() {
		super();
		title = locale::ATTITUDES_TAB;

		@panel = GuiPanel(this, Alignment());
		@takeButton = GuiButton(panel, recti_area(0,0, 280,60));
		@takeText = GuiMarkupText(takeButton, Alignment(Left, Top+15, Right, Bottom));
		takeText.defaultFont = FT_Subtitle;

		@header = GuiSkinElement(panel, Alignment(Left+0.5f-400, Top+16, Left+0.5f+400, Top+200), SS_Panel);
		@portrait = GuiEmpire(header, Alignment(Left+4, Top+4, Left+180, Bottom-4));

		@headerText = GuiMarkupText(header, Alignment(Left+188, Top+8, Right-8, Bottom-8));
		headerText.text = locale::ATT_HEADER_DESC;
		updateAbsolutePosition();
	}

	Color get_activeColor() {
		return Color(0x63ebdbff);
	}

	Color get_inactiveColor() {
		return Color(0x6dd6caff);
	}
	
	Color get_seperatorColor() {
		return Color(0x37837aff);
	}

	TabCategory get_category() {
		return TC_Attitudes;
	}

	Sprite get_icon() {
		return Sprite(material::TabAttitude);
	}

	void tick(double time) override {
		if(!visible)
			return;
		if(playerEmpire is null || !playerEmpire.valid) {
			attitudes.length = 0;
		}
		else {
			attitudes.syncFrom(playerEmpire.getAttitudes());
			@portrait.empire = playerEmpire;
		}

		uint prevCnt = boxes.length;
		uint newCnt = attitudes.length;
		for(uint i = newCnt; i < prevCnt; ++i)
			boxes[i].remove();
		boxes.length = newCnt;
		for(uint i = prevCnt; i < newCnt; ++i)
			@boxes[i] = AttitudeBox(panel);

		int y = 216, h = 150;
		for(uint i = 0; i < newCnt; ++i) {
			@boxes[i].att = attitudes[i];
			@boxes[i].alignment = Alignment(Left+0.1f, Top+y, Right-0.1f, Top+y+h);
			boxes[i].update();
			y += h+8;
		}

		bool haveTakeable = false;
		for(uint i = 0, cnt = getAttitudeTypeCount(); i < cnt; ++i) {
			auto@ att = getAttitudeType(i);
			if(att.canTake(playerEmpire)) {
				haveTakeable = true;
				break;
			}
		}

		if(haveTakeable) {
			takeButton.visible = true;

			int extraCost = playerEmpire.getNextAttitudeCost();
			takeButton.position = vec2i((size.width-takeButton.size.width)/2, y+20);
			takeText.text = "[center]"+format(locale::ATT_TAKE_COST, toString(extraCost))+"[/center]";
		}
		else {
			takeButton.visible = false;
		}

		if(prevCnt != newCnt)
			updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is takeButton) {
				TakeAttitudeOverlay(this);
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition, Color(0x6dd6caff));
		BaseGuiElement::draw();
	}
};

class GuiFlatButton : GuiButton {
	bool taken = false;
	bool available = false;

	GuiFlatButton(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
		navigable = true;
		style = SS_NULL;
	}

	void draw() {
		if(!available) {
			if(flags & SF_Active != 0)
				drawRectangle(AbsolutePosition, color.interpolate(Color(0x00000080), 0.6));
			else
				drawRectangle(AbsolutePosition, Color(0x00000040));
		}
		else {
			if(flags & SF_Active != 0)
				drawRectangle(AbsolutePosition, color);
			else
				drawRectangle(AbsolutePosition, Color(0x00000060));
		}

		if(flags & SF_Hovered != 0)
			drawRectangle(AbsolutePosition, Color(0xffffff20));

		if(!available) {
			drawLine(AbsolutePosition.topLeft+vec2i(size.width/5, size.height/2+3),
					AbsolutePosition.botRight-vec2i(size.width/5, size.height/2-3),
					Color(0x444444ff), 3);
		}

		if(taken) {
			vec2i tl = AbsolutePosition.topLeft + vec2i(2,2);
			vec2i br = AbsolutePosition.botRight - vec2i(2,2);

			drawLine(vec2i(tl.x,tl.y), vec2i(br.x,tl.y), color.interpolate(colors::White, 0.2), 3);
			drawLine(vec2i(tl.x,tl.y), vec2i(tl.x,br.y), color.interpolate(colors::White, 0.2), 3);

			drawLine(vec2i(br.x,tl.y), vec2i(br.x,br.y), color.interpolate(colors::White, 0.2), 3);
			drawLine(vec2i(tl.x,br.y), vec2i(br.x,br.y), color.interpolate(colors::White, 0.2), 3);


			Color acolor = color;
			acolor.a = 0x50;
			drawRectangle(AbsolutePosition, acolor);
		}
		GuiButton::draw();
	}
}

class TakeAttitudeOverlay : GuiOverlay {
	GuiSkinElement@ bg;
	GuiPanel@ leftPanel;
	GuiPanel@ rightPanel;
	GuiMarkupText@ text;

	array<const AttitudeType@> attitudes;
	array<GuiButton@> buttons;
	const AttitudeType@ selected;
	GuiButton@ takeButton;
	GuiMarkupText@ takeText;
	GuiMarkupText@ takeCaption;

	TakeAttitudeOverlay(IGuiElement@ parent) {
		super(parent);
		closeSelf = false;

		for(uint i = 0, cnt = getAttitudeTypeCount(); i < cnt; ++i) {
			auto@ att = getAttitudeType(i);
			/*if(att.canTake(playerEmpire))*/
			attitudes.insertLast(att);
		}
		attitudes.sortAsc();

		int h = 16 + clamp(attitudes.length/2 * 50, 370, 600) + 50;

		@bg = GuiSkinElement(this, Alignment(Left+0.5f-425, Top+0.5f-(h/2), Left+0.5f+425, Top+0.5f+(h/2)), SS_Panel);
		@leftPanel = GuiPanel(bg, Alignment(Left, Top, Left+300, Bottom-50));
		@rightPanel = GuiPanel(bg, Alignment(Left+300, Top, Right, Bottom-50));
		@text = GuiMarkupText(rightPanel, recti_area(8,8, 550-16, 100));
		text.flexHeight = true;
		@takeButton = GuiButton(bg, Alignment(Left+0.5f-140, Bottom-50, Left+0.5f+140, Bottom-8));
		@takeText = GuiMarkupText(takeButton, Alignment(Left, Top+10, Right, Bottom));
		@takeCaption = GuiMarkupText(bg, Alignment(Left+0.5f-140, Bottom-40, Left+0.5f+140, Bottom-8));
		takeCaption.defaultFont = FT_Bold;
		takeCaption.defaultColor = Color(0xaa8080ff);
		takeCaption.visible = false;

		int y = 8;
		uint sel = uint(-1);
		for(uint i = 0, cnt = attitudes.length; i < cnt; ++i) {
			int x = 8;
			if(i%2 != 0)
				x = 150;

			auto@ att = attitudes[i];

			GuiFlatButton btn(leftPanel, recti_area(x,y+2, 140, 46));
			btn.toggleButton = true;
			btn.pressed = (i == 0);
			btn.text = att.name;
			btn.color = att.color.interpolate(colors::Black, 0.75);

			if(playerEmpire.hasAttitude(att.id)) {
				btn.taken = true;
				btn.available = true;
				btn.textColor = colors::White;
			}
			else if(!att.canTake(playerEmpire)) {
				btn.taken = false;
				btn.available = false;
				btn.textColor = Color(0x666666ff);
			}
			else {
				btn.taken = false;
				btn.available = true;
				btn.textColor = colors::White;

				if(sel == uint(-1))
					sel = i;
			}

			if(i%2 != 0)
				y += 50;

			buttons.insertLast(btn);
		}

		if(sel == uint(-1))
			sel = 0;
		if(attitudes.length != 0)
			select(attitudes[sel]);
		updateAbsolutePosition();
	}

	void select(const AttitudeType@ type) {
		for(uint j = 0, cnt = buttons.length; j < cnt; ++j)
			buttons[j].pressed = (type is attitudes[j]);
		@selected = type;

		string desc = format("[font=Medium][color=$1][stroke=#000]$2[/stroke][/color][/font]\n[vspace=6/]",
				toString(type.color.interpolate(colors::White, 0.1)), type.name);

		for(uint i = 0, cnt = type.levels.length; i < cnt; ++i) {
			auto@ lvl = type.levels[i];
			desc += format("[img=$4;32][color=#aaa][b]$1 $2:[/b][/color] [color=#888]$3[/color]\n",
				locale::LEVEL, toString(i+1),
				format(type.progress, toString(lvl.threshold, 0)),
				getSpriteDesc(lvl.icon));
			desc += "[offset=20]"+lvl.description+"[/offset][/img]";
			desc += "\n[vspace=2/]";
		}

		takeButton.color = type.color;

		int extraCost = playerEmpire.getNextAttitudeCost();
		takeText.text = "[center]"+format(locale::ATT_TAKE_ATT, type.name, toString(extraCost))+"[/center]";
		takeButton.disabled = playerEmpire.Influence < extraCost;

		takeButton.visible = selected.canTake(playerEmpire);
		takeCaption.visible = !takeButton.visible;

		if(takeCaption.visible) {
			if(playerEmpire.hasAttitude(selected.id))
				takeCaption.text = "[center]"+locale::ATT_HAVE_ATTITUDE+"[/center]";
			else
				takeCaption.text = "[center]"+locale::ATT_CANNOT_ATTITUDE+"[/center]";
		}

		text.text = desc;
		rightPanel.updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.type == GUI_Clicked) {
			for(uint i = 0, cnt = buttons.length; i < cnt; ++i) {
				if(buttons[i] is event.caller) {
					select(attitudes[i]);
					return true;
				}
			}
			if(event.caller is takeButton) {
				playerEmpire.takeAttitude(selected.id);

				close();
				return true;
			}
		}
		return GuiOverlay::onGuiEvent(event);
	}
};

Tab@ createAttitudesTab() {
	return AttitudesTab();
}

void resetTabs() {
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		if(tabs[i].category == TC_Attitudes)
			browseTab(tabs[i], createAttitudesTab());
	}
}

void postReload(Message& msg) {
	resetTabs();
}
