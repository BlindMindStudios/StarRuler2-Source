#priority init -100
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.GuiContextMenu;
import elements.MarkupTooltip;
import tabs.Tab;
import util.formatting;
import timing;
import influence;
from tabs.tabbar import TAB_HEIGHT, GLOBAL_BAR_HEIGHT, ActiveTab;

class ClearEdictOption : GuiContextOption {
	ClearEdictOption() {
		super(locale::EDICT_CLEAR_OPTION);
	}

	void call(GuiContextMenu@ menu) override {
		playerEmpire.clearEdict();
	}
};

class EdictDisplay : BaseGuiElement {
	GuiMarkupText@ text;
	string prevText;
	bool clicking = false;

	EdictDisplay() {
		super(null, recti_area(210,TAB_HEIGHT+GLOBAL_BAR_HEIGHT, 200, 30));
		@text = GuiMarkupText(this, recti_area(6,6, 120,24));
		text.expandWidth = true;

		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Left:
				if(evt.caller is this)
					clicking = false;
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void showMenu() {
		if(playerEmpire.SubjugatedBy !is null)
			return;

		GuiContextMenu menu(mousePos);
		menu.addOption(ClearEdictOption());
		menu.finalize();
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source is text) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 1) {
						clicking = true;
						return true;
					}
				break;
				case MET_Button_Up:
					if(event.button == 1) {
						if(clicking)
							showMenu();
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void tick(double time) {
		Empire@ master = playerEmpire.SubjugatedBy;
		uint type = 0;
		if(master is null)
			type = playerEmpire.getEdictType();
		else
			type = master.getEdictType();

		visible = (ActiveTab.category == TC_Galaxy) && type != 0;

		if(visible) {
			string txt;
			Empire@ emp; Object@ obj;
			if(master !is null) {
				@emp = master.getEdictEmpire();
				@obj = master.getEdictObject();
				txt = locale::EDICT_FROM_MASTER;
			}
			else {
				@emp = playerEmpire.getEdictEmpire();
				@obj = playerEmpire.getEdictObject();
				txt = locale::EDICT_TO_VASSALS;
			}

			txt = format(txt, formatEmpireName(master),
					format(localize("#EDICT_"+toString(type)),
						formatEmpireName(emp), formatObject(obj)));

			if(txt != prevText) {
				prevText = txt;
				text.text = txt;
				text.updateAbsolutePosition();
				size = vec2i(text.textWidth + 12, 30);

				string tt;
				if(master !is null)
					tt = locale::TT_EDICT_FROM_MASTER;
				else
					tt = locale::TT_EDICT_TO_VASSALS;

				tt = format(tt, formatEmpireName(master),
						format(localize("#TT_EDICT_"+toString(type)),
							formatEmpireName(emp), formatObject(obj)));
				setMarkupTooltip(this, tt, width=300);
			}
		}
	}

	void draw() override {
		skin.draw(SS_TimeDisplay, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

EdictDisplay@ disp;
void init() {
	@disp = EdictDisplay();
}

void tick(double time) {
	disp.tick(time);
}
