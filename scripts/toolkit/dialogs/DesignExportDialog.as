#section disable menu
import dialogs.Dialog;
import elements.GuiFileChooser;
import util.design_export;

class DesignExportDialog : Dialog {
	const Design@ dsg;
	const DesignClass@ targetClass;
	GuiFileChooser@ chooser;

	DesignExportDialog(const Design@ Dsg, const DesignClass@ Cls, IGuiElement@ bind) {
		super(bind);
		addTitle(locale::EXPORT_DESIGN);

		@dsg = Dsg;
		@targetClass = Cls;
		@window.callback = this;

		@chooser = GuiFileChooser(window, Alignment(Left+12, Top+38, Right-12, Bottom-12), modProfile["designs"], "", CFM_Filename);
		chooser.selectedFilename = dsg.name + ".design";

		height = 500;
	}

	void focus() {
		Dialog::focus();
		chooser.filename.focus(true);
	}

	//Event callbacks
	void clickConfirm() {
		write_design(dsg, chooser.getSelectedPath(true), targetClass);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is chooser && event.type == GUI_Confirmed) {
			clickConfirm();
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

DesignExportDialog@ exportDesign(const Design@ dsg, const DesignClass@ cls, IGuiElement@ bind = null) {
	DesignExportDialog dlg(dsg, cls, bind);
	addDialog(dlg);
	return dlg;
}
