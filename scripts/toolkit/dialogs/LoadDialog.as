import dialogs.Dialog;
import elements.GuiFileChooser;

class LoadDialog : Dialog {
	GuiFileChooser@ chooser;
	GuiButton@ confirm;

	LoadDialog(IGuiElement@ bind, const string& folder) {
		super(bind);
		addTitle(locale::LOAD);
		@window.callback = this;

		@chooser = GuiFileChooser(window, Alignment(Left+12, Top+38, Right-12, Bottom-12), folder, "", CFM_Single);
		@confirm = GuiButton(window, Alignment(Left+0.8f+4, Bottom-42, Right-12, Bottom-12), locale::LOAD);
		confirm.disabled = true;

		height = 500;
		addDialog(this);
	}

	void focus() {
		Dialog::focus();
	}

	string get_path() {
		return chooser.getSelectedPath(true);
	}

	//Event callbacks
	void clickConfirm() {
	}

	bool onGuiEvent(const GuiEvent& event) {
		if((event.caller is chooser && event.type == GUI_Confirmed)
			|| (event.caller is confirm && event.type == GUI_Clicked)) {
			if(chooser.selectedCount != 0)
				clickConfirm();
			close();
			return true;
		}
		if(event.caller is chooser && event.type == GUI_Changed)
			confirm.disabled = chooser.selectedCount == 0;
		return Dialog::onGuiEvent(event);
	}
};
