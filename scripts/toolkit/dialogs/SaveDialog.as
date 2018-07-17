import dialogs.Dialog;
import elements.GuiFileChooser;

class SaveDialog : Dialog {
	const Design@ dsg;
	const DesignClass@ targetClass;
	GuiFileChooser@ chooser;

	SaveDialog(IGuiElement@ bind, const string& folder, const string& defaultName) {
		super(bind);
		addTitle(locale::EXPORT_DESIGN);
		@window.callback = this;

		@chooser = GuiFileChooser(window, Alignment(Left+12, Top+38, Right-12, Bottom-12), folder, "", CFM_Filename);
		chooser.selectedFilename = defaultName;

		height = 500;
		addDialog(this);
	}

	void focus() {
		Dialog::focus();
		chooser.filename.focus(true);
	}

	string get_path() {
		return chooser.getSelectedPath(true);
	}

	//Event callbacks
	void clickConfirm() {
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is chooser && event.type == GUI_Confirmed) {
			if(chooser.selectedFilename.length != 0)
				clickConfirm();
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};
