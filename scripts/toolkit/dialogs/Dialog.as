import elements.BaseGuiElement;
import elements.GuiDraggable;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiButton;
import dialogs.IDialog;
from gui import navigateInto;

from dialog import addDialog, closeDialog, closeDialogs;

const int DIALOG_BUTTON_HEIGHT = 32;
const int DIALOG_PADDING = 7;
const int DIALOG_BUTTON_ROW = DIALOG_BUTTON_HEIGHT + DIALOG_PADDING;
const Color DIALOG_TITLE_COLOR(0x00bffeff);

class Dialog : IDialog, IGuiCallback {
	bool Closed;
	IGuiElement@ elem;
	IGuiElement@ lastFocus;
	GuiSkinElement@ bg;
	BaseGuiElement@ window;
	GuiSkinElement@ titleBox;
	GuiText@ titleText;
	GuiButton@ closeBtn;

	int height;
	int width;

	Dialog(IGuiElement@ bind, bool bindInside = false) {
		Closed = false;
		@elem = bind;
		width = 500;
		height = 38+DIALOG_PADDING;

		@lastFocus = getGuiFocus();
		@window = GuiDraggable(bindInside ? bind : null, recti());
		@window.callback = this;

		@bg = GuiSkinElement(window, Alignment_Fill(), SS_Dialog);

		updatePosition();
	}

	void addTitle(const string& title, FontType font = FT_Bold, bool closeButton = true, const Color& color = Color(0x00bffeff)) {
		if(titleBox is null)
			@titleBox = GuiSkinElement(window, recti_area(vec2i(1, 1), vec2i(width-3, 26)), SS_WindowTitle);
		else
			titleBox.size = vec2i(width-3, 26);
		if(titleText is null) {
			@titleText = GuiText(window, recti_area(vec2i(8, 4), vec2i(width-16, 22)));
			titleText.font = font;
			height += 26;
		}

		titleBox.color = color;
		titleText.text = title;

		if(closeButton && closeBtn is null) {
			vec2i size = window.skin.getSize(SS_GameTabClose, SF_Normal);
			int off = (26 - size.y) / 2 + 1;
			@closeBtn = GuiButton(window, Alignment(Right-off-size.x, Top+off, Width=size.x, Height=size.y));
			closeBtn.style = SS_GameTabClose;
		}
	}

	void set_titleColor(const Color& color) {
		if(titleBox !is null)
			titleBox.color = color;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		return false;
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_ESC) {
					return true;
				}
				else if(event.key == KEY_ENTER) {
					return true;
				}
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					cancelDialog();
					return true;
				}
				else if(event.key == KEY_ENTER) {
					confirmDialog();
					return true;
				}
			break;
		}
		return false;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is closeBtn && event.type == GUI_Clicked) {
			cancelDialog();
			return true;
		}
		return false;
	}

	void set_position(const vec2i& pos) {
		window.position = pos;
	}

	void updatePosition() {
		recti pos;
		if(elem is null)
			pos = recti(vec2i(), screenSize);
		else
			pos = elem.absolutePosition;
		pos = recti_centered(pos, vec2i(width, height));

		if(titleBox !is null)
			titleBox.size = vec2i(width-3, 26);
		window.position = pos.topLeft;
		window.size = pos.size;
		window.updateAbsolutePosition();
	}

	void focus() {
		window.bringToFront();
		navigateInto(window);
	}

	void cancelDialog() {
		close();
	}

	void confirmDialog() {
		window.emitConfirmed();
	}

	void close() {
		Closed = true;
		window.remove();
		setGuiFocus(lastFocus);
	}

	bool get_closed() {
		return Closed;
	}

	IGuiElement@ get_bound() {
		return elem;
	}
};

void alignAcceptButtons(BaseGuiElement@ accept, BaseGuiElement@ cancel) {
	if(isWindows) {
		//Legacy OS support
		@accept.alignment = Alignment(Left+0.2f+12, Bottom-0.0f-DIALOG_BUTTON_ROW, Left+0.5f-6, Bottom-0.0f-DIALOG_PADDING);

		@cancel.alignment = Alignment(Right-0.5f+6, Bottom-0.0f-DIALOG_BUTTON_ROW, Right-0.2f-12, Bottom-0.0f-DIALOG_PADDING);
	}
	else {
		@accept.alignment = Alignment(Right-0.3f, Bottom-0.0f-DIALOG_BUTTON_ROW, Right-0.0f-DIALOG_PADDING, Bottom-0.0f-DIALOG_PADDING);

		@cancel.alignment = Alignment(Right-0.6f, Bottom-0.0f-DIALOG_BUTTON_ROW, Right-0.3f-DIALOG_PADDING, Bottom-0.0f-DIALOG_PADDING);
	}
}
