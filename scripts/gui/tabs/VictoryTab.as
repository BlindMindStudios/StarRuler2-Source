#priority init -200
import tabs.Tab;
import tabs.tabbar;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiEmpire;
import elements.GuiSkinElement;
import elements.GuiListbox;
import elements.GuiPanel;
import elements.MarkupTooltip;
import util.formatting;
import icons;
from multiplayer import wantSpectator;

class VictoryTab : Tab {
	GuiText@ heading;

	GuiSkinElement@ victorPanel;
	GuiMarkupText@ description;
	GuiEmpire@ victor;

	GuiSkinElement@ buttonBar;
	GuiPanel@ buttonPanel;

	GuiButton@ rankingsButton;
	GuiListbox@ rankings;

	array<StatPage@> stats;
	array<GuiButton@> statButtons;
	Alignment@ statAlign;

	Sprite typeIcon;

	VictoryTab() {
		super();

		@heading = GuiText(this, Alignment(Left, Top+30, Right, Top+90));
		heading.horizAlign = 0.5;
		heading.font = FT_Big;
		heading.color = colors::Green;
		heading.stroke = colors::Black;

		@victorPanel = GuiSkinElement(this, Alignment(Left+0.1f, Top+90, Right-0.1f, Top+242), SS_Panel);

		@victor = GuiEmpire(victorPanel, Alignment(Left+6, Top+6, Width=140, Height=140));

		@description = GuiMarkupText(victorPanel, Alignment(Left+220, Top+20, Right-6, Bottom-6));
		description.defaultFont = FT_Subtitle;

		@buttonBar = GuiSkinElement(this, Alignment(Left+0.1f, Top+242+20, Right-0.1f, Height=42), SS_PlainBox);
		@buttonPanel = GuiPanel(this, Alignment(Left+0.1f, Top+242, Right-0.1f, Height=62));
		buttonPanel.vertType = ST_Never;

		@statAlign = Alignment(Left+0.1f, Top+242+62, Right-0.1f, Bottom-30);

		if(!playerEmpire.valid) {
			victorPanel.visible = false;
			heading.visible = false;
			buttonBar.alignment.top.pixels = 32;
			buttonPanel.alignment.top.pixels = 12;
			statAlign.top.pixels = 74;
		}

		@rankingsButton = GuiButton(buttonPanel, Alignment(Left, Bottom-40, Width=135, Height=40), locale::V_RANKINGS);
		rankingsButton.buttonIcon = Sprite(material::PointsIcon);
		rankingsButton.toggleButton = true;
		rankingsButton.pressed = true;
		rankingsButton.font = FT_Bold;
		@rankings = GuiListbox(this, statAlign);
		rankings.itemHeight = 40;
		rankings.disabled = true;
		rankings.vertPadding = 8;
		rankings.style = SS_Panel;

		addStat(ST_Int, stat::Points, 60, locale::STAT_POINTS, Sprite(material::PointsIcon), 2000);
		addStat(ST_Float, stat::Military, 60, locale::STAT_STRENGTH, icons::Strength, 5000);
		addStat(ST_Int, stat::Planets, 15, locale::STAT_PLANETS, icons::Planet, 10);
		addStat(ST_Int, stat::Ships, 15, locale::STAT_SHIPS, icons::Defense, 10);
		addStat(ST_Float, stat::Budget, 60, locale::STAT_BUDGET, icons::Money, 2000);
		addStat(ST_Float, stat::NetBudget, 60, locale::STAT_NET_BUDGET, icons::Money, 2000);
		addStat(ST_Float, stat::EnergyIncome, 60, locale::STAT_ENERGY_INCOME, icons::Energy, 2);
		addStat(ST_Float, stat::InfluenceIncome, 60, locale::STAT_INFLUENCE_INCOME, icons::Influence, 3/60.0);
		addStat(ST_Float, stat::ResearchIncome, 60, locale::STAT_RESEARCH_INCOME, icons::Research, 2);
		addStat(ST_Float, stat::ResearchTotal, 60, locale::STAT_RESEARCH_TOTAL, icons::Research, 1000);

		updateAbsolutePosition();
		update();

		locked = true;
	}

	void addStat(StatType type, stat::EmpireStat Stat, int FilterDuration, const string& name, const Sprite& icon, double baseMax = 1) {
		StatPage page(this, statAlign, type, Stat, FilterDuration, name, baseMax);
		page.visible = false;
		stats.insertLast(page);

		int index = stats.length;
		GuiButton btn(buttonPanel, Alignment(Left+135*index, Bottom-40, Width=135, Height=40), name);
		btn.toggleButton = true;
		btn.pressed = false;
		btn.buttonIcon = icon;
		btn.font = FT_Bold;
		statButtons.insertLast(btn);
	}

	Color get_activeColor() {
		return Color(0xffc283ff);
	}

	Color get_inactiveColor() {
		return Color(0xffb900ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x8d7949ff);
	}		

	Sprite get_icon() {
		return typeIcon;
	}

	void switchPage(uint page) {
		rankings.visible = page == 0;
		rankingsButton.pressed = page == 0;

		for(uint i = 0, cnt = stats.length; i < cnt; ++i) {
			stats[i].visible = i+1 == page;
			statButtons[i].pressed = i+1 == page;
		}
	}

	void tick(double time) {
		update();
	}

	int lastUpdate = systemTime - 1000;
	bool fullUpdate = true;
	uint nextUpdateIndex = 0;
	
	void update() {
		if(systemTime - lastUpdate < 1000)
			return;
		lastUpdate = systemTime;
	
		Empire@ winner = playerEmpire;
		int myVictory = playerEmpire.Victory;

		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			if(getEmpire(i).Victory == 1) {
				@winner = getEmpire(i);
				break;
			}
		}

		//Show the appropriate victory message
		if(myVictory == 1) {
			heading.text = locale::V_WON_TITLE;
			heading.color = colors::Green;
			description.text = format(locale::V_WON_TEXT, formatEmpireName(winner), formatEmpireName(playerEmpire));
			typeIcon = Sprite(material::PointsIcon);
		}
		else if(myVictory == -2 && playerEmpire.SubjugatedBy.Victory == 1) {
			heading.text = locale::V_LESSER_TITLE;
			heading.color = Color(0xfff500ff);
			description.text = format(locale::V_LESSER_TEXT, formatEmpireName(winner), formatEmpireName(playerEmpire));
			typeIcon = Sprite(material::PointsIcon);
		}
		else {
			heading.text = locale::V_LOST_TITLE;
			heading.color = colors::Red;
			description.text = format(locale::V_LOST_TEXT, formatEmpireName(winner), formatEmpireName(playerEmpire));
			typeIcon = Sprite(material::SystemUnderAttack);
		}

		if(victorPanel.visible)
			title = heading.text;
		else
			title = locale::V_SCORES;

		//Update rankings
		array<EmpSorter> sorted;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ other = getEmpire(i);
			if(other.major) {
				EmpSorter sort;
				@sort.emp = other;
				sorted.insertLast(sort);
			}
		}
		sorted.sortAsc();

		rankings.clearItems();
		for(uint i = 0, cnt = sorted.length; i < cnt; ++i) {
			Empire@ emp = sorted[i].emp;
			string text = "";

			text += format(" #$1", toString(i+1));
			text += format("[offset=100][img=$2;28;$3/] $1[/offset]", formatEmpireName(emp),
					getSpriteDesc(Sprite(emp.flag)), toString(emp.color));

			if(hasGameEnded()) {
				string victory = "";
				if(emp.SubjugatedBy !is null)
					victory = format("[color=#aaa]$1[/color]", format(locale::V_SUBJUGATED, formatEmpireName(emp.SubjugatedBy)));
				else if(emp.Victory == 1)
					victory = format("[color=#0f0]$1[/color]", locale::V_WON_TITLE);
				else
					victory = format("[color=#f00]$1[/color]", locale::V_LOST_TITLE);
				text += format("[offset=450]$1[/offset]", victory);
			}
			else {
				string victory;
				if(emp.SubjugatedBy !is null)
					victory = format("[color=#aaa]$1[/color]", format(locale::V_SUBJUGATED, formatEmpireName(emp.SubjugatedBy)));
				text += format("[offset=450]$1[/offset]", victory);
			}

			text += format("[offset=880]$1[/offset]", format(locale::EMPIRE_POINTS, toString(emp.points.value)));
			rankings.addItem(GuiMarkupListText(text, FT_Subtitle));
		}

		//Update stats data
		if(fullUpdate) {
			fullUpdate = false;
			for(uint i = 0, cnt = stats.length; i < cnt; ++i)
				stats[i].update();
		}
		else {
			//TODO: Even this probably isn't necessary, make sure
			stats[(nextUpdateIndex++) % stats.length].update();
		}

		victorPanel.color = winner.color;
		@victor.empire = winner;

		if(!victorPanel.visible && playerEmpire.valid) {
			locked = false;
			shownVictory = false;
			closeTab(this);
		}
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is rankingsButton) {
				switchPage(0);
				return true;
			}
			else {
				for(uint i = 0, cnt = statButtons.length; i < cnt; ++i) {
					if(event.caller is statButtons[i]) {
						switchPage(i+1);
						return true;
					}
				}
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class EmpSorter {
	Empire@ emp;

	int opCmp(const EmpSorter& other) const {
		if(other.emp.Victory != emp.Victory) {
			if(emp.Victory == 1)
				return -1;
			if(emp.Victory == -1)
				return 1;
			if(other.emp.Victory == 1)
				return 1;
			if(other.emp.Victory == -1)
				return -1;
			if(emp.Victory == -2) {
				if(other.emp.Victory == 0)
					return 1;
				if(emp.SubjugatedBy.Victory == 1)
					return -1;
			}
			if(other.emp.Victory == -2) {
				if(emp.Victory == 0)
					return -1;
				if(other.emp.SubjugatedBy.Victory == 1)
					return 1;
			}
		}
		if(emp.points.value > other.emp.points.value)
			return -1;
		if(emp.points.value < other.emp.points.value)
			return 1;
		return 0;
	}
};

class StatPage : BaseGuiElement {
	stat::EmpireStat stat;
	StatType type;
	array<StatTracker@> trackers;
	double endTime = 0;
	double minVal = 0;
	double maxVal = 0;
	double baseMin = 0;
	double baseMax = 1;
	bool sqrScale = false;

	StatPage(IGuiElement@ parent, Alignment@ align, StatType type, stat::EmpireStat Stat, int FilterDuration, const string& name, double baseMax = 1) {
		super(parent, align);
		this.stat = Stat;
		this.type = type;
		this.baseMax = baseMax;
		if(stat == stat::Military) {
			this.sqrScale = true;
			this.baseMin = 2000;
		}
		for(uint i = 0, cnt = getEmpireCount(); i <cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(emp.major)
				trackers.insertLast(StatTracker(type, Stat, emp.color, FilterDuration, emp, sqrScale));
		}

		addLazyMarkupTooltip(this, width=300, update=true);
	}

	double getOffsetTime(int offset) {
		return double(offset-52) / double(size.x-64) * endTime;
	}

	string formatValue(double amt, bool shortForm = false) {
		if(stat == stat::Budget || stat == stat::NetBudget)
			return formatMoney(int(amt));
		if(stat == stat::EnergyIncome || stat == stat::ResearchIncome)
			return standardize(amt, true)+locale::PER_SECOND;
		if(stat == stat::InfluenceIncome)
			return standardize(amt * 60.0, true)+locale::PER_MIN;
		if(type == ST_Int) {
			if(shortForm && amt >= 1000)
				return standardize(amt, true);
			else
				return toString(floor(amt), 0);
		}
		return standardize(amt, true);
	}

	string get_tooltip() override {
		int mx = mousePos.x;
		if(mx < AbsolutePosition.topLeft.x+52 || mx > AbsolutePosition.botRight.x-12)
			return "";
		string text;
		double time = getOffsetTime(mx - absolutePosition.topLeft.x);
		text += format("[center][font=Subtitle]$1[/font][/center]", formatGameTime(time));
		for(uint i = 0, cnt = trackers.length; i < cnt; ++i) {
			double amt = trackers[i].getClosest(time).y;
			text += format("[b]$1[offset=150]$2[/offset][/b]\n",
						formatEmpireName(trackers[i].emp),
						formatValue(amt));
		}
		return text;
	}

	void update() {
		endTime = gameTime;
		minVal = baseMin; maxVal = baseMax;
		for(uint i = 0, cnt = trackers.length; i < cnt; ++i) {
			trackers[i].update();
			minVal = min(minVal, trackers[i].minVal);
			maxVal = max(maxVal, trackers[i].maxVal);
		}
		for(uint i = 0, cnt = trackers.length; i < cnt; ++i) {
			trackers[i].minVal = minVal;
			trackers[i].maxVal = maxVal;
		}
	}

	void draw() {
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition);

		const Font@ ft = skin.getFont(FT_Normal);

		{
			int interval = 100;
			vec2i pos(154, size.height-15);
			while(pos.x < size.x) {
				double time = double(pos.x-52) / double(size.x-64) * endTime;
				ft.draw(pos=recti_centered(pos+AbsolutePosition.topLeft, vec2i(200,30)),
						horizAlign=0.5, text=formatTime(time), color=Color(0xaaaaaaff));
				drawLine(vec2i(pos.x, 12)+AbsolutePosition.topLeft,
						vec2i(pos.x, size.height-40)+AbsolutePosition.topLeft,
						Color(0xaaaaaa20));
				pos.x += interval;
			}
		}

		{
			int interval = 40;
			vec2i pos(26, size.height-40);
			string prevVal;
			if(type == ST_Int) {
				double mult = ceil(double(size.height-52) / ceil(maxVal-minVal));
				interval = ceil(ceil(double(interval) / mult) * mult);
			}
			while(pos.y > 14) {
				double val = 0;
				if(sqrScale)
					val = minVal + (maxVal - minVal) * sqr(1.0 - (double(pos.y-12) / double(size.y-52)));
				else
					val = minVal + (maxVal - minVal) * (1.0 - (double(pos.y-12) / double(size.y-52)));
				string valDisp = formatValue(val, true);
				if(valDisp != prevVal) {
					ft.draw(pos=recti_centered(pos+AbsolutePosition.topLeft, vec2i(200,30)),
							horizAlign=0.5, text=valDisp, color=Color(0xaaaaaaff));
					prevVal = valDisp;
				}
				drawLine(vec2i(42, pos.y)+AbsolutePosition.topLeft,
						vec2i(size.width-12, pos.y)+AbsolutePosition.topLeft,
						Color(0xaaaaaa20));
				pos.y -= interval;
			}

			if(minVal < 0 && maxVal > 0 && !sqrScale) {
				int y = size.height-40 - size.y * (-minVal) / (maxVal - minVal);
				drawLine(vec2i(42, y)+AbsolutePosition.topLeft,
						vec2i(size.width-12, y)+AbsolutePosition.topLeft,
						Color(0xaa000040), size=3);
			}
		}

		for(uint i = 0, cnt = trackers.length; i < cnt; ++i)
			trackers[i].draw(skin, AbsolutePosition.padded(42,12,12,40));

		if(AbsolutePosition.isWithin(mousePos)) {
			int mx = mousePos.x;
			if(mx >= AbsolutePosition.topLeft.x+52 && mx <= AbsolutePosition.botRight.x-12) {
				drawLine(vec2i(mx, AbsolutePosition.topLeft.y+12),
						vec2i(mx, AbsolutePosition.botRight.y-40),
						Color(0xaaaaaaff));
			}
		}

		BaseGuiElement::draw();
	}
};

enum StatType {
	ST_Int,
	ST_Float,
}

final class StatTracker {
	double minVal = 0, maxVal = 1;
	stat::EmpireStat stat;
	Color color;
	int filterDuration = 1;
	array<vec2d> data;
	Empire@ emp;
	StatType type;
	double endTime;
	bool sqrScale = false;
	
	array<vec2i> points;
	vec2i lastSize;
	
	StatTracker(StatType type, stat::EmpireStat Stat, const Color& col, int FilterDuration, Empire@ emp = playerEmpire, bool sqrScale = false) {
		stat = Stat;
		color = col;
		filterDuration = FilterDuration;
		this.type = type;
		@this.emp = emp;
		this.sqrScale = sqrScale;
	}

	vec2d getClosest(double time) {
		vec2d closest(0, 0);
		double dist = INFINITY;
		//Don't make me do a binary search you monster
		for(uint i = 0, cnt = data.length; i < cnt; ++i) {
			double d = abs(data[i].x - time);
			if(d < dist) {
				dist = d;
				closest = data[i];
			}
		}
		return closest;
	}
	
	void rebuildPoints(vec2i size) {
		array<vec3d> pts(1);
		
		vec2d factor(double(size.x) / endTime, -double(size.y) / (maxVal - minVal));
		vec2d offset(0.0, -minVal);
		
		uint lastX = 0;
		for(uint i = 0, cnt = data.length; i < cnt; ++i) {
			vec2d pt = data[i] + offset;
			pt.x *= factor.x;
			
			if(!sqrScale) {
				pt.y *= factor.y;
			}
			else {
				if(pt.y != 0)
					pt.y = -double(size.y) * sqrt(pt.y / (maxVal - minVal));
			}

			uint x = int(pt.x);
			if(i == 0 && x != 0)
				pts[0] = vec3d(0.0, pt.y, 1.0);
		
			if(x != lastX)
				pts.resize(pts.length + 1);
			pts[pts.length-1] += vec3d(pt.x, pt.y, 1.0);
		}
		
		int maxTimeDelta = max(int(ceil(double(size.x * filterDuration) / endTime)), int(1));
		
		points.length = 0;
		points.reserve(pts.length + 1);
		for(uint i = 0, cnt = pts.length; i < cnt; ++i) {
			vec3d pt = pts[i];
			vec2i px = vec2i(pt.x / pt.z, pt.y / pt.z + 0.5);
			if(i > 0) {
				vec2i prev = points.last;
				if(prev.x < px.x - maxTimeDelta)
					points.insertLast(vec2i(px.x - 1, prev.y));
			}
			points.insertLast(px);
		}
		
		if(points.last.x < size.x - 1)
			points.insertLast(vec2i(size.x - 1, points.last.y));
	
		lastSize = size;
	}
	
	void update() {
		minVal = INFINITY;
		maxVal = -INFINITY;
		data.length = 0;
	
		StatHistory history(emp, stat);
		endTime = gameTime;
		
		while(history.advance(1)) {
			double val = 0;
			if(type == ST_Int)
				val = history.intVal;
			else
				val = history.floatVal;
			
			if(val > maxVal)
				maxVal = val;
			if(val < minVal)
				minVal = val;
			
			data.insertLast(vec2d(history.time, val));
		}
		
		lastSize = vec2i();
	}
	
	void draw(const Skin@ skin, recti bound) {
		vec2i size = bound.size;
		if(size != lastSize)
			rebuildPoints(size);
		
		if(points.length == 0) {
			drawLine(bound.topLeft + vec2i(0, bound.height), bound.botRight, color);
			return;
		}
		
		vec2i corner = bound.topLeft + vec2i(0,size.y);
		vec2i prev = points[0] + corner;
		
		uint lines = points.length - 1;
		uint index = 0;
		while(index < lines) {
			drawPolygonStart(PT_LineStrip, min(lines - index, 250));
			drawPolygonPoint(prev, color);
			for(uint i = 0; i < 250 && index + i < lines; ++i) {
				vec2i pt = points[index + i + 1] + corner;
				drawPolygonPoint(pt);
				prev = pt;
			}
			drawPolygonEnd();
			index += 250;
		}
	}
};

Tab@ createVictoryTab() {
	return VictoryTab();
}

void init() {
	/*auto@ tab = createVictoryTab();*/
	/*newTab(tab);*/
	/*switchToTab(tab);*/
}

bool shownVictory = false;
void tick(double time) {
	if(!shownVictory && (hasGameEnded() || (wantSpectator && !playerEmpire.valid))) {
		auto@ tab = createVictoryTab();
		newTab(tab);
		if(hasGameEnded())
			switchToTab(tab);
		shownVictory = true;
	}
}
