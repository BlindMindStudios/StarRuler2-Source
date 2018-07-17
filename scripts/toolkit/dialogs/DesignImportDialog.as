#section disable menu
import dialogs.Dialog;
import elements.GuiFileChooser;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiDropdown;
import dialogs.MessageDialog;
import util.design_export;

class DesignImportDialog : Dialog {
	GuiFileChooser@ chooser;
	GuiText@ label;
	GuiDropdown@ classList;
	GuiButton@ confirm;

	DesignImportDialog(IGuiElement@ bind) {
		super(bind);
		addTitle(locale::IMPORT_DESIGNS);

		@chooser = GuiFileChooser(window, Alignment(Left+12, Top+38, Right-12, Bottom-38),
			modProfile["designs"], "", CFM_Multiple);
		chooser.list.autoMultiple = true;

		@label = GuiText(window, Alignment(Left+16, Bottom-34, Left+0.35f, Bottom-12), locale::IMPORT_INTO_CLASS);

		@classList = GuiDropdown(window, Alignment(Left+0.35f+4, Bottom-34, Left+0.8f, Bottom-12));
		classList.addItem(locale::SAVED_CLASS);

		uint cnt = playerEmpire.designClassCount;
		for(uint i = 0; i < cnt; ++i)
			classList.addItem(playerEmpire.getDesignClass(i).name);

		@confirm = GuiButton(window, Alignment(Left+0.8f+4, Bottom-34, Right-12, Bottom-12), locale::IMPORT);
		height = 500;
	}

	//Event callbacks
	bool showDesign(const Design@ dsg) {
		return false;
	}

	void clickConfirm() {
		const DesignClass@ inClass;
		if(classList.selected > 0)
			@inClass = playerEmpire.getDesignClass(classList.selected - 1);

		string errors;
		bool hasErrors = false;
		const Design@ errDesign;

		array<string> selected;
		chooser.getSelectedFiles(selected, true);
		for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
			DesignDescriptor desc;
			string fname = getBasename(selected[i]);
			if(!read_design(selected[i], desc)) {
				errors += "\n"+fname+":\n    - ";
				errors += locale::ERROR_INVALID_FILE+"\n";
				hasErrors = true;
				continue;
			}

			//Report design renames
			const Design@ prevDesign = playerEmpire.getDesign(desc.name);
			if(prevDesign !is null && !prevDesign.obsolete) {
				errors += "\n"+fname+":\n    - ";
				desc.name = uniqueDesignName(desc.name, playerEmpire);
				errors += format(locale::ERROR_DUPLICATE_DESIGN, desc.name);
				errors += "\n";
				hasErrors = true;
				@prevDesign = null;
			}

			//Report all design errors
			@desc.hull = getBestHull(desc, getHullTypeTag(desc.hull));
			const Design@ dsg = makeDesign(desc);
			if(dsg.hasFatalErrors()) {
				uint errCnt = dsg.errorCount;
				errors += "\n"+fname+":\n";
				for(uint j = 0; j < errCnt; ++j)
					errors += "    - "+dsg.errors[j].text+"\n";
				hasErrors = true;
				@errDesign = dsg;
				continue;
			}

			if(desc.settings !is null)
				dsg.setSettings(desc.settings);

			const DesignClass@ cls = inClass;
			if(cls is null && desc.className.length != 0)
				@cls = playerEmpire.getDesignClass(desc.className);
			if(cls is null)
				@cls = playerEmpire.getDesignClass(locale::DOWNLOAD_DESIGN_CLASS, true);
			if(prevDesign !is null)
				playerEmpire.changeDesign(prevDesign, dsg, cls);
			else
				playerEmpire.addDesign(cls, dsg);
		}

		//Report errors
		if(hasErrors) {
			if(selected.length == 1 && errDesign !is null) {
				if(showDesign(errDesign))
					return;
			}
			message(locale::IMPORT_ERRORS + "\n" + errors, null, elem);
		}
	}

	void confirmDialog() {
		clickConfirm();
		close();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is chooser && event.type == GUI_Confirmed) {
			clickConfirm();
			close();
			return true;
		}
		if(event.caller is confirm && event.type == GUI_Clicked) {
			clickConfirm();
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

DesignImportDialog@ importDesigns(IGuiElement@ bind = null) {
	DesignImportDialog dlg(bind);
	addDialog(dlg);
	return dlg;
}
