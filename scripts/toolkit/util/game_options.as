import elements.BaseGuiElement;
import util.gui_options;
import settings.game_settings;

interface GameOption {
	void apply(SettingsContainer&);
	void load(SettingsContainer&);
	void reset();
};

uint MASK_CONFIG = 0x71 << 16;

mixin class IsGameBoolOption {
	uint Setting;
	bool DefaultSetting;
	bool DefaultValue;

	void set_defaultValue(bool val) {
		DefaultSetting = val;
		DefaultValue = val;
	}

	void set_setting(int val) {
		Setting = val;
	}

	void apply(SettingsContainer& gs) {
		bool v = get();
		if(Setting & MASK_CONFIG != 0) {
			if(v != DefaultSetting)
				gs.setNamed(config::getName(Setting & ~MASK_CONFIG), v ? 1.0 : 0.0);
			else
				gs.clearNamed(config::getName(Setting & ~MASK_CONFIG));
		}
		else
			gs[Setting] = v ? 1.0 : 0.0;
	}

	void load(SettingsContainer& gs) {
		if(Setting & MASK_CONFIG != 0)
			set(gs.getNamed(config::getName(Setting & ~MASK_CONFIG), DefaultValue ? 1.0 : 0.0) != 0);
		else
			set(gs[Setting] != 0);
	}

	void reset() {
		set(DefaultValue);
	}
};

mixin class IsGameDoubleOption {
	uint Setting;
	double Default;

	void set_defaultValue(double val) {
		Default = val;
	}

	void set_setting(int val) {
		Setting = val;
	}

	void apply(SettingsContainer& gs) {
		double v = get();
		if(Setting & MASK_CONFIG != 0) {
			if(v != Default)
				gs.setNamed(config::getName(Setting & ~MASK_CONFIG), v);
			else
				gs.clearNamed(config::getName(Setting & ~MASK_CONFIG));
		}
		else
			gs[Setting] = v;
	}

	void load(SettingsContainer& gs) {
		if(Setting & MASK_CONFIG != 0)
			set(gs.getNamed(config::getName(Setting & ~MASK_CONFIG), Default));
		else
			set(gs[Setting]);
	}

	void reset() {
		set(Default);
	}
};

uint config(const string& name) {
	return MASK_CONFIG | config::getIndex(name);
}

class GuiGameToggle : GuiToggleOption, GameOption, IsGameBoolOption {
	GuiGameToggle(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameToggle(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}
};

class GuiGameSlider : GuiSliderOption, GameOption, IsGameDoubleOption {
	GuiGameSlider(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameSlider(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}
};

class GuiGameOccurance : GuiOccuranceOption, GameOption, IsGameDoubleOption {
	GuiGameOccurance(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameOccurance(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	void set_defaultValue(double val) {
		defaultValue = val;
		Default = val;
	}
};

class GuiGameFrequency : GuiFrequencyOption, GameOption, IsGameDoubleOption {
	GuiGameFrequency(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameFrequency(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	void set_defaultValue(double val) {
		defaultValue = val;
		Default = val;
	}
};

class GuiGameNumber : GuiNumberOption, GameOption, IsGameDoubleOption {
	GuiGameNumber(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameNumber(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}
};

class GuiGameDropdown : GuiDropdownOption, GameOption, IsGameDoubleOption {
	array<double> values;

	GuiGameDropdown(BaseGuiElement@ parent, const recti& pos, const string&in text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	GuiGameDropdown(BaseGuiElement@ parent, Alignment@ pos, const string& text, int settingid) {
		super(parent, pos, text);
		setting = settingid;
	}

	void addOption(const string& text, double value) {
		box.addItem(text);
		values.insertLast(value);
	}

	void set(double value) {
		uint sel = 0;
		for(uint i = 0, cnt = values.length; i < cnt; ++i) {
			if(values[i] == value) {
				sel = i;
				break;
			}
		}

		box.selected = sel;
	}

	double get() {
		if(uint(box.selected) >= values.length)
			return 0.0;
		return values[box.selected];
	}
};
