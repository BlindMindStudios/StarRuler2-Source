import dialogs.Dialog;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiCheckbox;
import elements.GuiDropdown;
import elements.GuiSpinbox;

const int INPUT_LINE_HEIGHT = 26;

interface IInputDialogCallback {
	void inputCallback(InputDialog@ dialog, bool accepted);
	void changeCallback(InputDialog@ dialog);
};

class InputDialogCallback : IInputDialogCallback {
	void inputCallback(InputDialog@ dialog, bool accepted) {
	}

	void changeCallback(InputDialog@ dialog) {
	}
};

class InputDialog : Dialog {
	IInputDialogCallback@ callback;
	BaseGuiElement@[] inputs;
	GuiButton@ accept;
	GuiButton@ cancel;
	int curPos;

	InputDialog(IInputDialogCallback@ CB, IGuiElement@ bind) {
		@callback = CB;
		curPos = DIALOG_PADDING;
		super(bind);

		Dialog::addTitle("", FT_Bold);
		curPos += 26;

		@accept = GuiButton(bg, recti());
		accept.text = locale::ACCEPT;
		accept.tabIndex = 100;
		@accept.callback = this;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;

		alignAcceptButtons(accept, cancel);
	}

	uint get_inputCount() {
		return inputs.length;
	}

	void focus() {
		Dialog::focus();
		focusInput();
	}

	//**Generic functions for adding lines
	void addLine(BaseGuiElement& label, int h = INPUT_LINE_HEIGHT) {
		@label.parent = window;
		@label.alignment = Alignment(Left+12, Top+curPos, Right-12, Top+curPos + h);

		curPos += h + 6;
		height += h + 6;
	}

	int addInput(BaseGuiElement& input, int h = INPUT_LINE_HEIGHT) {
		@input.parent = window;
		@input.alignment = Alignment(Left+12, Top+curPos, Right-12, Top+curPos + h);
		input.tabIndex = inputs.length();

		curPos += h + 6;
		height += h + 6;
		inputs.insertLast(input);
		return inputs.length() - 1;
	}

	int addInput(BaseGuiElement@ label, BaseGuiElement& input, int h = INPUT_LINE_HEIGHT) {
		if(label !is null) {
			@label.parent = window;
			@label.alignment = Alignment(Left+12, Top+curPos, Left+0.3f-6, Top+curPos + h);
		}

		@input.parent = window;
		@input.alignment = Alignment(Left+0.3f+6, Top+curPos, Right-12, Top+curPos + h);
		input.tabIndex = inputs.length;

		curPos += h + 6;
		height += h + 6;
		inputs.insertLast(input);
		return inputs.length - 1;
	}

	BaseGuiElement@ getInput(int num) {
		return inputs[num];
	}

	void focusInput(uint num = 0) {
		if(num < inputs.length) {
			setGuiFocus(inputs[num]);
		}
		else {
			setGuiFocus(null);
		}
	}

	//**Text label lines
	void addTitle(const string& title, FontType font = FT_Bold, bool closeButton = true, const Color& color = DIALOG_TITLE_COLOR) {
		titleText.text = title;
		titleText.font = font;
		titleBox.color = color;
	}

	int addLabel(const string& label, FontType font = FT_Normal, double align = 0.0, bool register = false) {
		GuiText@ txt = GuiText(null, recti(), label);
		@txt.parent = window;
		@txt.alignment = Alignment(Left+12, Top+curPos, Right-12, Top+curPos + INPUT_LINE_HEIGHT);
		txt.font = font;
		txt.horizAlign = align;
		txt.wordWrap = true;

		int h = txt.getTextDimension().height;
		h += (INPUT_LINE_HEIGHT - txt.skin.getFont(txt.font).getLineHeight());
		if(h != INPUT_LINE_HEIGHT) {
			@txt.alignment = Alignment(Left+12, Top+curPos, Right-12, Top+curPos + h);
		}

		curPos += h + 6;
		height += h + 6;

		if(register) {
			inputs.insertLast(txt);
			return inputs.length - 1;
		}
		else {
			return -1;
		}
	}

	void setLabel(int num, const string& label) {
		GuiText@ txt = cast<GuiText>(getInput(num));
		if(txt !is null)
			txt.text = label;
	}

	//**Textbox input lines
	int addTextInput(const string& label, const string& defaultText, int height = INPUT_LINE_HEIGHT) {
		GuiText@ lbl = GuiText(null, recti(), label);

		GuiTextbox@ box = GuiTextbox(null, recti(), defaultText);
		@box.callback = this;

		int i = addInput(lbl, box, height);

		if(height > INPUT_LINE_HEIGHT) {
			box.multiLine = true;
			lbl.vertAlign = 0.0;
		}

		box.updateTextPosition();
		return i;
	}

	string getTextInput(int num) {
		GuiTextbox@ box = cast<GuiTextbox@>(getInput(num));
		return box.text;
	}

	void focusTextInput(int num, bool selectAll = false) {
		GuiTextbox@ box = cast<GuiTextbox@>(getInput(num));
		box.focus(selectAll);
	}

	//**Spinbox input lines
	int addSpinboxInput(const string& label, double defaultValue = 0.0, double step = 1.0,
			double minValue = -INFINITY, double maxValue = INFINITY, int decimals = 0) {
		GuiText@ lbl = GuiText(null, recti(), label);

		GuiSpinbox@ box = GuiSpinbox(null, recti(), defaultValue);
		@box.callback = this;
		box.step = step;
		box.decimals = decimals;
		box.min = minValue;
		box.max = maxValue;
		box.value = defaultValue;

		return addInput(lbl, box);
	}

	double getSpinboxInput(int num) {
		GuiSpinbox@ box = cast<GuiSpinbox@>(getInput(num));
		return box.value;
	}

	//**Checkbox input lines
	int addToggle(const string& label, bool defaultValue) {
		GuiCheckbox@ box = GuiCheckbox(null, recti(), label, defaultValue);
		@box.callback = this;

		return addInput(null, box);
	}

	bool getToggle(int num) {
		GuiCheckbox@ box = cast<GuiCheckbox@>(getInput(num));
		return box.checked;
	}

	//** Dropdown lines
	int addSelection(const string& label) {
		GuiText@ lbl = GuiText(null, recti(), label);
		lbl.vertAlign = 0.0;

		GuiDropdown@ box = GuiDropdown(null, recti());

		return addInput(lbl, box);
	}

	void addItem(const string& value, bool select = false) {
		addItem(inputs.length() - 1, value, select);
	}

	void addItem(int num, const string& value, bool select = false) {
		GuiDropdown@ box = cast<GuiDropdown@>(getInput(num));
		box.addItem(value);

		if(select)
			box.selected = box.itemCount - 1;
	}

	int getSelection(int num) {
		GuiDropdown@ box = cast<GuiDropdown@>(getInput(num));
		return box.selected;
	}

	string getSelectionValue(int num) {
		GuiDropdown@ box = cast<GuiDropdown@>(getInput(num));
		int sel = box.selected;
		if(sel >= 0)
			return box.getItem(sel);
		else
			return "";
	}

	//Close callback
	void close() {
		close(false);
	}

	void close(bool accepted) {
		if(callback !is null)
			callback.inputCallback(this, accepted);
		Dialog::close();
	}

	void confirmDialog() {
		close(true);
	}

	//Event callbacks
	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked && (event.caller is accept || event.caller is cancel)) {
			close(event.caller is accept);
			return true;
		}
		else if(event.type == GUI_Confirmed) {
			int ind = -1;
			for(uint i = 0, cnt = inputs.length(); i < cnt; ++i) {
				if(inputs[i] is cast<BaseGuiElement@>(event.caller)) {
					ind = i;
					break;
				}
			}
			if(ind < 0)
				return false;
			if(uint(ind) == inputs.length() - 1)
				close(true);
			else
				setGuiFocus(inputs[ind + 1]);
			return true;
		}
		else if(event.type == GUI_Changed) {
			if(callback !is null)
				callback.changeCallback(this);
		}
		return Dialog::onGuiEvent(event);
	}
};
