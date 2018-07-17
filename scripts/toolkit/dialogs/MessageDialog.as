import dialogs.Dialog;
import elements.GuiButton;
import elements.GuiMarkupText;
import elements.GuiTextbox;

interface MessageDialogCallback {
	void messageCallback(MessageDialog@ dialog);
};

class MessageDialog : Dialog {
	MessageDialogCallback@ callback;
	GuiMarkupText@ txt;
	GuiButton@ ok;

	MessageDialog(const string& text, MessageDialogCallback@ CB, IGuiElement@ bind) {
		@callback = CB;
		super(bind);
		addTitle(locale::NOTICE);

		@ok = GuiButton(bg, recti());
		ok.text = locale::OK;

		if(isWindows) {
			//Legacy OS support
			@ok.alignment = Alignment(Left+0.4f+DIALOG_PADDING, Bottom-DIALOG_BUTTON_ROW, Right-0.4f-DIALOG_PADDING, Bottom-DIALOG_PADDING);
		}
		else {
			@ok.alignment = Alignment(Right-0.2f-DIALOG_PADDING, Bottom-DIALOG_BUTTON_ROW, Right-0.0f-DIALOG_PADDING, Bottom-DIALOG_PADDING);
		}

		@txt = GuiMarkupText(window, recti(DIALOG_PADDING, DIALOG_PADDING+22, width - DIALOG_PADDING, 50), text);
		height = txt.size.height+22;
		height += 56;
	}

	//Close callback
	void close() {
		if(callback !is null)
			callback.messageCallback(this);
		Dialog::close();
	}

	//Event callbacks
	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked && event.caller is ok && !Closed) {
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

MessageDialog@ message(const string& msg, MessageDialogCallback@ cb = null, IGuiElement@ bind = null) {
	MessageDialog@ dlg = MessageDialog(msg, cb, bind);
	addDialog(dlg);
	return dlg;
}
