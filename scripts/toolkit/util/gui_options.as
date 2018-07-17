import elements.BaseGuiElement;
import elements.GuiCheckbox;
import elements.GuiText;
import elements.GuiScrollbar;
import elements.GuiSpinbox;
import elements.GuiTextbox;
import elements.GuiDropdown;

class GuiToggleOption : BaseGuiElement {
	GuiCheckbox@ check;

	GuiToggleOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos);
		_GuiToggleOption(text);
	}

	GuiToggleOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos);
		_GuiToggleOption(text);
	}

	void _GuiToggleOption(const string& text) {
		@check = GuiCheckbox(this, Alignment_Fill(), text);
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is check && event.type == GUI_Changed) {
			emitChanged();
			if(check.checked)
				check.textColor = colors::White;
			else
				check.textColor = Color(0x888888ff);
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool get() {
		return check.checked;
	}

	void set(bool value) {
		check.checked = value;
		if(check.checked)
			check.textColor = colors::White;
		else
			check.textColor = Color(0x888888ff);
	}
};

funcdef void settingChanged();

class GuiSliderOption : BaseGuiElement {
	GuiScrollbar@ bar;
	GuiText@ label;
	GuiText@ value;
	settingChanged@ onChanged;

	GuiSliderOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos);
		_GuiSliderOption(text);
	}

	GuiSliderOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos);
		_GuiSliderOption(text);
	}

	void _GuiSliderOption(const string& text) {
		@label = GuiText(this, recti(), text);
		@label.alignment = Alignment(Left, Top, Left+0.4f, Bottom);

		@value = GuiText(this, recti());
		@value.alignment = Alignment(Right-74, Top, Right-0.0f-4, Bottom);
		value.horizAlign = 1.0;

		@bar = GuiScrollbar(this, recti());
		@bar.alignment = Alignment(Left+0.4f+4, Top+1, Right-0.0f-78, Bottom-1);
		bar.up.visible = false;
		bar.down.visible = false;

		bar.orientation = SO_Horizontal;
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is bar && event.type == GUI_Changed) {
			value.text = toString(bar.pos, 1);
			if(onChanged !is null)
				onChanged();
			emitChanged();
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	double get() {
		return round(bar.pos * 10.0) / 10.0;
	}

	void set(double val) {
		bar.pos = val;
		value.text = toString(bar.pos, 1);
	}

	void setMin(double val) {
		bar.start = val;
	}

	void setMax(double val) {
		bar.end = val;
		bar.page = 0.0;
		bar.bar = (bar.end - bar.start) / 10.0;
		bar.scroll = 0.1;
	}
};

class GuiOccuranceOption : BaseGuiElement {
	GuiScrollbar@ bar;
	GuiCheckbox@ label;
	GuiText@ value;
	double defaultValue = 1.0;

	GuiOccuranceOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos);
		_(text);
	}

	GuiOccuranceOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos);
		_(text);
	}

	void _(const string& text) {
		@label = GuiCheckbox(this, recti(), text);
		@label.alignment = Alignment(Left, Top, Left+0.4f, Bottom);

		@value = GuiText(this, recti());
		@value.alignment = Alignment(Right-74, Top, Right-0.0f-4, Bottom);
		value.horizAlign = 1.0;

		@bar = GuiScrollbar(this, recti());
		@bar.alignment = Alignment(Left+0.4f+4, Top+1, Right-0.0f-78, Bottom-1);
		bar.up.visible = false;
		bar.down.visible = false;

		bar.orientation = SO_Horizontal;
		updateAbsolutePosition();
		label.emitClicked();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is bar && event.type == GUI_Changed) {
			value.text = toString(bar.pos*100.0, 0)+"%";
			label.checked = bar.pos != 0.0;
			label.emitClicked();
			emitChanged();
			return true;
		}
		if(event.caller is label) {
			Color color;
			FontType font = FT_Normal;

			double v = get();
			if(!label.checked) {
				color = Color(0x888888ff);
			}
			else if(v > defaultValue*1.1) {
				font = FT_Bold;
				color = colors::Green;
			}
			else if(v < defaultValue*0.9) {
				font = FT_Bold;
				color = colors::Red;
			}

			label.textColor = color;
			value.color = color;
			label.font = font;
			value.font = font;
			if(event.type == GUI_Changed) {
				emitChanged();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	double get() {
		return label.checked ? round(bar.pos*100.0) / 100.0 : 0.0;
	}

	void set(double val) {
		bar.pos = val;
		value.text = toString(bar.pos*100.0, 0)+"%";
		label.checked = val != 0.0;
		label.emitClicked();
	}

	void setMin(double val) {
		bar.start = val;
	}

	void setMax(double val) {
		bar.end = val;
		bar.bar = 0.25;
		bar.page = 0.0;
		bar.scroll = 0.1;
	}
};

class GuiFrequencyOption : GuiSliderOption {
	double defaultValue = 1.0;

	GuiFrequencyOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos, text);
	}

	GuiFrequencyOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos, text);
	}

	double get() {
		return round(bar.pos*100.0) / 100.0;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is bar && event.type == GUI_Changed) {
			value.text = toString(bar.pos*100.0, 0)+"%";

			Color color;
			FontType font = FT_Normal;

			double v = get();
			if(v > defaultValue*1.1) {
				font = FT_Bold;
				color = colors::Green;
			}
			else if(v < defaultValue*0.9) {
				font = FT_Bold;
				color = colors::Red;
			}

			label.color = color;
			label.font = font;
			value.color = color;
			value.font = font;

			emitChanged();
			return true;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void set(double val) {
		bar.pos = val;
		bar.emitChanged();
	}
};

class GuiNumberOption : BaseGuiElement {
	GuiSpinbox@ value;
	GuiText@ label;
	bool changed = false;

	GuiNumberOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos);
		_GuiNumberOption(text);
	}

	GuiNumberOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos);
		_GuiNumberOption(text);
	}

	void _GuiNumberOption(const string& text) {
		@label = GuiText(this, recti(), text);
		@label.alignment = Alignment(Left, Top, Left+0.4f, Bottom);

		@value = GuiSpinbox(this, recti());
		@value.alignment = Alignment(Left+0.4f+2, Top+2, Right-0.0f-2, Bottom-2);
		value.min = 0.0;
		
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is value){
			if(event.type == GUI_Changed) {
				emitChanged();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void set_step(double step) {
		value.step = step;
	}

	void set_decimals(int dec) {
		value.decimals = dec;
	}

	double get() {
		return value.value;
	}

	void set(double val) {
		value.value = val;
	}

	void setMin(double val) {
		value.min = val;
	}

	void setMax(double val) {
		value.max = val;
	}
};

class GuiDropdownOption : BaseGuiElement {
	GuiDropdown@ box;
	GuiText@ label;
	bool changed = false;

	GuiDropdownOption(BaseGuiElement@ parent, const recti& pos, const string&in text) {
		super(parent, pos);
		_GuiDropdownOption(text);
	}

	GuiDropdownOption(BaseGuiElement@ parent, Alignment@ pos, const string& text) {
		super(parent, pos);
		_GuiDropdownOption(text);
	}

	void _GuiDropdownOption(const string& text) {
		@label = GuiText(this, recti(), text);
		@label.alignment = Alignment(Left, Top, Left+0.4f, Bottom);

		@box = GuiDropdown(this, recti());
		@box.alignment = Alignment(Left+0.5f+2, Top, Right-0.0f-2, Bottom);
		
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is box){
			if(event.type == GUI_Changed) {
				emitChanged();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};
