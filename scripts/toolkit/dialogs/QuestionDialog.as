import dialogs.Dialog;
import elements.GuiButton;
import elements.GuiMarkupText;
import elements.GuiTextbox;
import elements.GuiText;

interface QuestionDialogCallback {
	void questionCallback(QuestionDialog@ dialog, int answer);
};

class QuestionDialog : Dialog {
	QuestionDialogCallback@ callback;
	GuiText@ txt;
	GuiButton@[] buttons;

	QuestionDialog(const string& title, const string& text, QuestionDialogCallback@ CB, IGuiElement@ bind) {
		@callback = CB;
		super(bind);

		int y = 0;
		if(title.length != 0) {
			addTitle(title);
			y += 26;
		}

		GuiMarkupText@ txt = GuiMarkupText(window, recti(DIALOG_PADDING, DIALOG_PADDING+y, width - DIALOG_PADDING, 50+y), text);
		height = txt.size.height+y;
		height += 50+DIALOG_PADDING;
	}

	string get_text() {
		return txt.text;
	}

	//Button management
	void addButton(const string& str, const Color& color = colors::White) {
		if(isWindows) {
			//Legacy OS support
			GuiButton@ btn = GuiButton(window, recti(vec2i(), vec2i(130, DIALOG_BUTTON_HEIGHT)), str);
			buttons.insertLast(btn);
			btn.color = color;

			int start = buttons.length() * (130 + DIALOG_PADDING) - DIALOG_PADDING;
			start = (width - start) / 2;

			for(uint i = 0, cnt = buttons.length(); i < cnt; ++i) {
				buttons[i].position = vec2i(start, height - DIALOG_BUTTON_ROW);
				start += 152;
			}
		}
		else {
			recti pos = recti_area(
				vec2i(width - (buttons.length() + 1) * (130 + DIALOG_PADDING), height - DIALOG_BUTTON_ROW),
				vec2i(130, DIALOG_BUTTON_HEIGHT));

			GuiButton@ btn = GuiButton(window, pos, str);
			btn.color = color;
			buttons.insertLast(btn);
		}
	}

	//Close callback
	void close() {
		close(-1);
	}

	void close(int answer) {
		if(callback !is null)
			callback.questionCallback(this, answer);
		Dialog::close();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked) {
			for(uint i = 0, cnt = buttons.length(); i < cnt; ++i) {
				if(buttons[i] is cast<GuiButton@>(event.caller)) {
					close(i);
					return true;
				}
			}
		}
		else if(event.type == GUI_Confirmed) {
			close(0);
		}
		return Dialog::onGuiEvent(event);
	}
};

enum QuestionAnswer {
	QA_Yes,
	QA_No,
};

QuestionDialog@ question(const string& msg, QuestionDialogCallback@ cb = null, IGuiElement@ bind = null) {
	QuestionDialog@ dlg = QuestionDialog(" ", msg, cb, bind);
	dlg.addButton(locale::YES, colors::Green);
	dlg.addButton(locale::NO, colors::Red);
	addDialog(dlg);
	return dlg;
}

QuestionDialog@ question(const string& msg, const string& yes, const string& no, QuestionDialogCallback@ cb = null, IGuiElement@ bind = null) {
	QuestionDialog@ dlg = QuestionDialog(" ", msg, cb, bind);
	dlg.addButton(yes, colors::Green);
	dlg.addButton(no, colors::Red);
	addDialog(dlg);
	return dlg;
}

QuestionDialog@ question(const string& title, const string& msg, QuestionDialogCallback@ cb = null, IGuiElement@ bind = null) {
	QuestionDialog@ dlg = QuestionDialog(title, msg, cb, bind);
	dlg.addButton(locale::YES, colors::Green);
	dlg.addButton(locale::NO, colors::Red);
	addDialog(dlg);
	return dlg;
}

QuestionDialog@ question(const string& title, const string& msg, const string& yes, const string& no, QuestionDialogCallback@ cb = null, IGuiElement@ bind = null) {
	QuestionDialog@ dlg = QuestionDialog(title, msg, cb, bind);
	dlg.addButton(yes, colors::Green);
	dlg.addButton(no, colors::Red);
	addDialog(dlg);
	return dlg;
}
