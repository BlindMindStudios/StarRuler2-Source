import elements.BaseGuiElement;
import elements.MarkupTooltip;
import elements.GuiMarkupText;
import util.game_options;
import elements.GuiText;

class SettingsPage {
	GameOption@[] options;
	BaseGuiElement@ cur;
	uint lineHeight = 34;
	uint linePadding = 4;
	uint line = 0;
	bool half = false;

	void clear() {
		options.length = 0;
		@cur = null;
		lineHeight = 30;
		line = 0;
	}

	void create(BaseGuiElement@ pane, SettingsContainer@ gs = null) {
		clear();
		@cur = pane;
		makeSettings();
		reset();

		if(gs !is null)
			load(gs);
	}

	Alignment@ nextAlignment(bool halfWidth = false) {
		if(!halfWidth && half) {
			half = false;
			++line;
		}
		Alignment align(Left+8, Top+linePadding+line*lineHeight, Right-24, Top+line*lineHeight + lineHeight);
		if(halfWidth) {
			if(half) {
				align.left.percent = 0.5f;
				++line;
			}
			else {
				align.right.percent = 0.5f;
			}
			half = !half;
		}
		else {
			++line;
			half = false;
		}
		return align;
	}

	void emptyline() {
		line += 1;
		if(half) {
			half = false;
			line += 1;
		}
	}

	GuiText@ Title(const string& title, FontType font = FT_Medium, Alignment@ align = null) {
		if(align is null)
			@align = nextAlignment();
		GuiText ele(cur, align, title);
		ele.font = font;
		ele.stroke = colors::Black;
		return ele;
	}

	GuiMarkupText@ Description(const string& text, uint lines = 1) {
		auto@ align = nextAlignment();
		align.bottom.pixels += lineHeight * lines-1;
		line += lines-1;

		GuiMarkupText ele(cur, align);
		ele.text = text;
		return ele;
	}

	GuiGameToggle@ Toggle(const string& text, const string& configName, Alignment@ align = null, const string& tooltip = "", bool halfWidth=false) {
		return Toggle(text, config(configName), config::get(configName) != 0.0, align, tooltip, halfWidth);
	}

	GuiGameToggle@ Toggle(const string& text, uint setting, bool value, Alignment@ align = null, const string& tooltip = "", bool halfWidth=false) {
		if(align is null)
			@align = nextAlignment(halfWidth);
		GuiGameToggle ele(cur, align, text, setting);
		if(tooltip.length != 0)
			setMarkupTooltip(ele, tooltip, width=300);
		ele.set(value);
		ele.defaultValue = value;
		options.insertLast(ele);
		return ele;
	}

	GuiGameSlider@ Slider(const string& text, uint setting, double value, double min, double max, Alignment@ align = null) {
		if(align is null)
			@align = nextAlignment();
		GuiGameSlider ele(cur, align, text, setting);
		ele.defaultValue = value;
		ele.set(value);
		ele.setMin(min);
		ele.setMax(max);
		options.insertLast(ele);
		return ele;
	}

	GuiGameNumber@ Number(const string& text, const string& configName, int decimals = 0, double step = 1.0, Alignment@ align = null, double min=0.0, double max=INFINITY, bool halfWidth=false, const string& tooltip = "") {
		return Number(text, config(configName), config::get(configName), decimals, step, align, min, max, halfWidth, tooltip);
	}

	GuiGameNumber@ Number(const string& text, uint setting, double value, int decimals = 0, double step = 1.0, Alignment@ align = null, double min=0.0, double max=INFINITY, bool halfWidth=false, const string& tooltip = "") {
		if(align is null)
			@align = nextAlignment(halfWidth);
		GuiGameNumber ele(cur, align, text, setting);
		ele.decimals = decimals;
		ele.step = step;
		ele.defaultValue = value;
		ele.setMin(min);
		ele.setMax(max);
		ele.set(value);
		if(tooltip.length != 0)
			setMarkupTooltip(ele, tooltip, width=300);
		options.insertLast(ele);
		return ele;
	}

	GuiGameOccurance@ Occurance(const string& text, const string& configName, double min = 0.0, double max = 2.0, Alignment@ align = null, const string& tooltip = "") {
		return Occurance(text, config(configName), config::get(configName), min, max, align, tooltip);
	}

	GuiGameOccurance@ Occurance(const string& text, uint setting, double value, double min = 0.0, double max = 2.0, Alignment@ align = null, const string& tooltip = "") {
		if(align is null)
			@align = nextAlignment();
		GuiGameOccurance ele(cur, align, text, setting);
		ele.defaultValue = value;
		ele.set(value);
		ele.setMin(min);
		ele.setMax(max);
		if(tooltip.length != 0)
			setMarkupTooltip(ele, tooltip, width=300);
		options.insertLast(ele);
		return ele;
	}

	GuiGameFrequency@ Frequency(const string& text, const string& configName, double min = 0.0, double max = 2.0, Alignment@ align = null) {
		return Frequency(text, config(configName), config::get(configName), min, max, align);
	}

	GuiGameFrequency@ Frequency(const string& text, uint setting, double value, double min = 0.0, double max = 2.0, Alignment@ align = null) {
		if(align is null)
			@align = nextAlignment();
		GuiGameFrequency ele(cur, align, text, setting);
		ele.defaultValue = value;
		ele.set(value);
		ele.setMin(min);
		ele.setMax(max);
		options.insertLast(ele);
		return ele;
	}

	GuiGameDropdown@ Dropdown(const string& text, const string& configName, Alignment@ align = null) {
		return Dropdown(text, config(configName), config::get(configName), align);
	}

	GuiGameDropdown@ Dropdown(const string& text, uint setting, double value, Alignment@ align = null) {
		if(align is null)
			@align = nextAlignment();
		GuiGameDropdown ele(cur, align, text, setting);
		ele.defaultValue = value;
		ele.set(value);
		options.insertLast(ele);
		return ele;
	}

	void makeSettings() {
		throw("SettingsPage does not implement makeSettings().");
	}

	void reset() {
		uint cnt = options.length;
		for(uint i = 0; i < cnt; ++i)
			options[i].reset();
	}

	void load(SettingsContainer& gs) {
		uint cnt = options.length;
		for(uint i = 0; i < cnt; ++i)
			options[i].load(gs);
	}

	void apply(SettingsContainer& gs) {
		uint cnt = options.length;
		for(uint i = 0; i < cnt; ++i)
			options[i].apply(gs);
	}
};

class GameSettingsPage : SettingsPage {
	Color color;
	string header;
	Sprite icon;

	GameSettingsPage() {
		GAME_SETTINGS_PAGES.insertLast(this);
	}
};

array<GameSettingsPage@> GAME_SETTINGS_PAGES;
