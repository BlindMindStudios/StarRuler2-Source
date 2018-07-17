import tabs.Tab;
from tabs.tabbar import newTab, switchToTab;

Tab@ createStatsTab() {
	return StatsTab();
}

class StatsTabCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = createStatsTab();
		newTab(editor);
		switchToTab(editor);
	}
}

void init() {
	addConsoleCommand("stats_tab", StatsTabCommand());
}

array<int> valuePoints;
int findNearest(int start, int bound) {
	int above = start;
	bool validAbove = false;
	
	while(!validAbove && above > 0) {
		validAbove = true;
		
		for(uint i = 0, cnt = valuePoints.length; i < cnt; ++i) {
			int pt = valuePoints[i];
			if(above > pt - 24 && above < pt + 24) {
				validAbove = false;
				above = pt - 24;
			}
		}
	}
	
	int below = start;
	bool validBelow = false;
	
	while(!validBelow && below < bound) {
		validBelow = true;
		
		for(uint i = 0, cnt = valuePoints.length; i < cnt; ++i) {
			int pt = valuePoints[i];
			if(below > pt - 24 && below < pt + 24) {
				validBelow = false;
				below = pt + 24;
			}
		}
	}
	
	if(validAbove) {
		if(!validBelow) {
			start = above;
		}
		else {
			int aDiff = abs(above - start);
			int bDiff = abs(below - start);
			if(aDiff < bDiff)
				start = above;
			else
				start = below;
		}
	}
	else if(validBelow) {
		start = below;
	}
	
	valuePoints.insertLast(start);
	return start;
}

interface StatTracker {
	void update();
	void draw(const Skin@ skin, recti bound);
};

class StatsTab : Tab {
	uint endTime = 0;
	array<StatTracker@> stats;
	
	double nextUpdate = 0;

	StatsTab() {
		super();
		title = locale::STATS_TAB;
		
		stats.insertLast(IntegerStat(stat::Planets, Color(0xff9955ff), 15, " Planets"));
		stats.insertLast(IntegerStat(stat::Ships, Color(0x4422ffff), 15, " Ships"));
		stats.insertLast(IntegerStat(stat::ShipsDestroyed, Color(0xff2222ff), 15, " Killed"));
		stats.insertLast(FloatStat(stat::Budget, Color(0x22ff22ff), 60, " $"));
		stats.insertLast(FloatStat(stat::Energy, Color(0xffff22ff), 60, " Energy"));
		stats.insertLast(FloatStat(stat::FTL, Color(0xff22ffff), 60, " FTL"));
		stats.insertLast(IntegerStat(stat::Influence, Color(0xffffffff), 60, " Influence"));
	}
	
	void updateStats() {
		for(uint i = 0, end = stats.length; i < end; ++i)
			stats[i].update();
	}
	
	void draw() {
		if(gameTime > nextUpdate) {
			nextUpdate = gameTime + 1.0;
			updateStats();
		}
		
		endTime = uint(gameTime);
		
		valuePoints.length = 0;
	
		skin.draw(SS_DiplomacyBG, SF_Normal, AbsolutePosition);
		
		recti statBound = recti_centered(AbsolutePosition, AbsolutePosition.size - vec2i(64,16)) - vec2i(60,0);
		skin.draw(SS_Panel, SF_Normal, statBound);
		
		statBound = recti_centered(statBound, statBound.size - vec2i(1,1));
		
		for(uint i = 0, end = stats.length; i < end; ++i)
			stats[i].draw(skin, statBound);
		
		Tab::draw();
	}
}

final class IntegerStat : StatTracker {
	int minVal = 0, maxVal = 100;
	stat::EmpireStat stat;
	Color color;
	int filterDuration = 1;
	array<vec2i> data;
	string suffix;
	
	IntegerStat(stat::EmpireStat Stat, const Color& col, int FilterDuration, string Suffix) {
		stat = Stat;
		color = col;
		filterDuration = FilterDuration;
		suffix = Suffix;
	}
	
	void update() {
		minVal = 0;
		maxVal = 100;
		data.length = 0;
	
		StatHistory history(playerEmpire, stat);
		
		while(history.advance(1)) {
			int val = history.intVal;
			
			if(val > maxVal)
				maxVal = val;
			if(val < minVal)
				minVal = val;
			
			data.insertLast(vec2i(int(history.time), val));
		}
	}
	
	void draw(const Skin@ skin, recti bound) {
		if(data.length == 0) {
			drawLine(bound.topLeft + vec2i(0, bound.height), bound.botRight, color);
			return;
		}
	
		vec2i size = bound.size;
		
		float endTime = float(gameTime);
		vec2f factor(1.f / endTime, -1.f / float(maxVal));
		
		int secondStep = int(max(float(size.x) / endTime, 1.f));
		int timeStep = int(max(float(size.x * filterDuration) / endTime, float(filterDuration)));
		vec2i corner = bound.topLeft + vec2i(0,size.y);
		vec2i prev = corner;
		
		//Draw segments
		for(uint i = 0, cnt = data.length; i < cnt; ++i) {
			vec2f ptf = vec2f(data[i]);
			vec2i pt = corner + vec2i(float(size.x) * ptf.x * factor.x, float(size.y) * ptf.y * factor.y);
			
			if(i != 0 && prev.x >= pt.x - timeStep) {
				drawLine(prev, pt, color);
			}
			else {
				vec2i med = vec2i(pt.x - secondStep, prev.y);
				drawLine(prev, med, color);
				drawLine(med, pt, color);
			}
			prev = pt;
		}
		
		//Draw final segment until current moment if nothing has changed
		if(data[data.length - 1].x < int(endTime)) {
			vec2i end = vec2i(corner.x + size.x, prev.y);
			drawLine(prev, end, color);
			prev = end;
		}
		
		vec2i around = prev + vec2i(6, 0);
		around.y = findNearest(around.y - bound.topLeft.y, size.height) + bound.topLeft.y - 8;
		skin.draw(FT_Normal, around, string(data[data.length - 1].y) + suffix, color);
	}
};

final class FloatStat : StatTracker {
	float minVal = 0, maxVal = 100.f;
	stat::EmpireStat stat;
	Color color;
	int filterDuration = 1;
	array<vec2f> data;
	string suffix;
	
	FloatStat(stat::EmpireStat Stat, const Color& col, int FilterDuration, string Suffix) {
		stat = Stat;
		color = col;
		filterDuration = FilterDuration;
		suffix = Suffix;
	}
	
	void update() {
		minVal = 0;
		maxVal = 100;
		data.length = 0;
	
		StatHistory history(playerEmpire, stat);
		
		while(history.advance(1)) {
			float val = history.floatVal;
			
			if(val > maxVal)
				maxVal = val;
			if(val < minVal)
				minVal = val;
			
			data.insertLast(vec2f(history.time, val));
		}
	}
	
	void draw(const Skin@ skin, recti bound) {
		if(data.length == 0) {
			drawLine(bound.topLeft + vec2i(0, bound.height), bound.botRight, color);
			return;
		}
	
		vec2i size = bound.size;
		
		float endTime = float(gameTime);
		vec2f factor(1.f / endTime, -1.f / float(maxVal));
		
		int secondStep = int(max(float(size.x) / endTime, 1.f));
		int timeStep = int(max(float(size.x * filterDuration) / endTime, float(filterDuration)));
		vec2i corner = bound.topLeft + vec2i(0,size.y);
		vec2i prev = corner;
		
		//Draw segments
		for(uint i = 0, cnt = data.length; i < cnt; ++i) {
			vec2f ptf = data[i];
			vec2i pt = corner + vec2i(float(size.x) * ptf.x * factor.x, float(size.y) * ptf.y * factor.y);
			
			if(i != 0 && prev.x >= pt.x - timeStep) {
				drawLine(prev, pt, color);
			}
			else {
				vec2i med = vec2i(pt.x - secondStep, prev.y);
				drawLine(prev, med, color);
				drawLine(med, pt, color);
			}
			prev = pt;
		}
		
		//Draw final segment until current moment if nothing has changed
		if(data[data.length - 1].x < int(endTime)) {
			vec2i end = vec2i(corner.x + size.x, prev.y);
			drawLine(prev, end, color);
			prev = end;
		}
		
		
		vec2i around = prev + vec2i(6, 0);
		around.y = findNearest(around.y - bound.topLeft.y, size.height) + bound.topLeft.y - 8;
		skin.draw(FT_Normal, around, standardize(data[data.length - 1].y) + suffix, color);
	}
};
