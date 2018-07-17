import elements.BaseGuiElement;
import util.gui_options;

interface EngineOption {
	void apply();
	void reset();
};

mixin class IsEngineBoolOption {
	string Setting;

	void set_setting(string val) {
		Setting = val;
		reset();
	}

	void apply() {
		setSettingBool(Setting, get());
	}

	void reset() {
		set(getSettingBool(Setting));
	}
};

mixin class IsEngineDoubleOption {
	string Setting;

	void set_setting(string val) {
		Setting = val;
		setMin(getSettingMinDouble(Setting));
		setMax(getSettingMaxDouble(Setting));
		reset();
	}

	void apply() {
		setSettingDouble(Setting, get());
	}

	void reset() {
		set(getSettingDouble(Setting));
	}
};

mixin class IsEngineIntegerOption {
	string Setting;

	void set_setting(string val) {
		Setting = val;
		setMin(getSettingMinInt(Setting));
		setMax(getSettingMaxInt(Setting));
		reset();
	}

	void apply() {
		setSettingInt(Setting, get());
	}

	void reset() {
		set(getSettingInt(Setting));
	}
};

class GuiEngineToggle : GuiToggleOption, EngineOption, IsEngineBoolOption {
	GuiEngineToggle(BaseGuiElement@ parent, const recti& pos, const string&in text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	GuiEngineToggle(BaseGuiElement@ parent, Alignment@ pos, const string& text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}
};

class GuiEngineSlider : GuiSliderOption, EngineOption, IsEngineDoubleOption {
	GuiEngineSlider(BaseGuiElement@ parent, const recti& pos, const string&in text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	GuiEngineSlider(BaseGuiElement@ parent, Alignment@ pos, const string& text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}
};

class GuiEngineNumber : GuiNumberOption, EngineOption, IsEngineIntegerOption {
	GuiEngineNumber(BaseGuiElement@ parent, const recti& pos, const string&in text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	GuiEngineNumber(BaseGuiElement@ parent, Alignment@ pos, const string& text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}
};

class GuiEngineDecimal : GuiNumberOption, EngineOption, IsEngineDoubleOption {
	GuiEngineDecimal(BaseGuiElement@ parent, const recti& pos, const string&in text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	GuiEngineDecimal(BaseGuiElement@ parent, Alignment@ pos, const string& text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}
};

class GuiEngineDropdown : GuiDropdownOption, EngineOption, IsEngineIntegerOption {
	array<int> values;

	GuiEngineDropdown(BaseGuiElement@ parent, const recti& pos, const string&in text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	GuiEngineDropdown(BaseGuiElement@ parent, Alignment@ pos, const string& text, string& settingname) {
		super(parent, pos, text);
		setting = settingname;
	}

	void addItem(const string& name, int value) {
		values.insertLast(value);
		box.addItem(name);
	}

	void setMin(int v) {
		//Ignored
	}

	void setMax(int v) {
		//Ignored
	}

	int get() {
		return values[clamp(box.selected, 0, values.length-1)];
	}

	void set(int val) {
		for(uint i = 0, cnt = values.length; i < cnt; ++i) {
			if(val == values[i]) {
				box.selected = i;
				return;
			}
		}
	}
};
