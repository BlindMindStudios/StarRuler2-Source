import tabs.Tab;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiBlueprint;
import elements.MarkupTooltip;
import elements.GuiSprite;
import dialogs.InputDialog;
from dialogs.DesignImportDialog import DesignImportDialog, addDialog;
import resources;
import tile_resources;
import icons;
import heralds_icons;
#include "dialogs/include/UniqueDialogs.as"

from tabs.tabbar import newTab, browseTab, switchToTab;
from tabs.DesignEditorTab import createDesignEditorTab, loadDesignEditor;

const uint D_EL_WIDTH = 325;
const uint D_EL_HEIGHT = 200;
const uint D_EL_SPACING = 8;
const uint D_ICON_WIDTH = 38;
const uint D_ICON_HEIGHT = 28;
const uint D_ICON_SPACING = 4;

const Color[] CLASS_COLORS = {
	Color(0x00c3ffff),
	Color(0xcf4cffff),
	Color(0xbaff4cff),
	Color(0xff6c00ff),
	Color(0xebc0ffff),
	Color(0xc7af99ff),
	Color(0xf49bcfff),
	Color(0x00ff9cff),
	Color(0x00deffff)
};

enum Dialogs {
	D_CreateClass,
};

class CreateClass : InputDialogCallback {
	DesignOverview@ overview;

	CreateClass(DesignOverview@ ovw) {
		@overview = ovw;
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			string name = dialog.getTextInput(0);
			if(name.length != 0)
				playerEmpire.getDesignClass(name);

			overview.refresh(playerEmpire);
		}
	}
};

class DesignImporter : DesignImportDialog {
	DesignImporter(IGuiElement@ bind) {
		super(bind);
	}

	bool showDesign(const Design@ dsg) {
		cast<DesignOverview>(elem).showDesignEditor(dsg);
		return true;
	}
};

class DesignOverview : Tab {
	GuiPanel@ clsPanel;
	DesignClassElement@[] classes;
	DesignElement@ selected;

	GuiButton@ createClassButton;
	GuiButton@ importButton;
	GuiButton@ showObsoleteButton;

	uint prevDesignCount = 0;

	DesignOverview() {
		super();
		
		@clsPanel = GuiPanel(this, recti());
		@clsPanel.alignment = Alignment(Left+8, Top, Right-8, Bottom);

		@createClassButton = GuiButton(clsPanel, recti(0, 0, 195, 47),
			locale::CREATE_DESIGN_CLASS);
		createClassButton.font = FT_Medium;
		createClassButton.buttonIcon = icons::Create.colorized(Color(0x8888ffff));

		@importButton = GuiButton(clsPanel, recti(0, 0, 195, 47),
			locale::IMPORT_DESIGNS);
		importButton.font = FT_Medium;
		importButton.buttonIcon = icons::Import;

		@showObsoleteButton = GuiButton(clsPanel, recti(0, 0, 195, 47),
			locale::SHOW_OBSOLETE);
		showObsoleteButton.tooltip = locale::TT_SHOW_OBSOLETE;
		showObsoleteButton.font = FT_Medium;
		showObsoleteButton.buttonIcon = icons::Obsolete;
		showObsoleteButton.toggleButton = true;

		title = locale::DESIGNS;
		refresh(playerEmpire);
	}

	Color get_activeColor() {
		return Color(0x83cfffff);
	}

	Color get_inactiveColor() {
		return Color(0x009cffff);
	}
	
	Color get_seperatorColor() {
		return Color(0x49738dff);
	}		

	TabCategory get_category() {
		return TC_Designs;
	}

	Sprite get_icon() {
		return Sprite(material::TabDesigns);
	}

	void showDesignEditor(const Design@ dsg) {
		//Keep a design editor tab in previous so we
		//don't need to create it all the time
		if(previous is null) {
			@previous = createDesignEditorTab();
			previous.locked = locked;
		}
		loadDesignEditor(previous, dsg.mostUpdated());
		browseTab(this, previous, true);
	}

	void showDesignEditor(const Hull@ hull, const DesignClass@ cls, const string& name, uint size) {
		//Keep a design editor tab in previous so we
		//don't need to create it all the time
		if(previous is null) {
			@previous = createDesignEditorTab();
			previous.locked = locked;
		}
		loadDesignEditor(previous, hull, cls, name, size);
		browseTab(this, previous, true);
	}

	void refresh(Empire@ emp) {
		//Keep designs locked while we're doing this
		ReadLock lock(emp.designMutex);
		prevDesignCount = emp.designCount;

		const Design@ sel;
		if(selected !is null) {
			@sel = selected.dsg;
			selected.selected = false;
			@selected = null;
		}

		//Create panel with list of designs in classes
		uint designCount = emp.designClassCount;
		for(uint i = designCount; i < classes.length; ++i)
			classes[i].remove();

		classes.length = designCount;
		uint y = 6;
		for(uint i = 0; i < designCount; ++i) {
			const DesignClass@ cls = emp.getDesignClass(i);

			//Make a new design class or repurpose one
			DesignClassElement@ el;
			if(classes[i] !is null) {
				@el = classes[i];
			}
			else {
				@el = DesignClassElement(clsPanel, this);
				@classes[i] = el;
			}

			//Update the design class list
			el.refresh(cls);
			if(el.visible) {
				el.position = vec2i(0, y);
				y += el.size.height;
			}
		}

		if(sel !is null) {
			for(uint i = 0, cnt = classes.length; i < cnt; ++i) {
				for(uint n = 0, ncnt = classes[i].designs.length; n < ncnt; ++n) {
					if(classes[i].designs[n].dsg is sel) {
						@selected = classes[i].designs[n];
						selected.selected = true;
						break;
					}
				}
			}
		}

		createClassButton.position = vec2i(0, y + 4);
		importButton.position = vec2i(205, y + 4);
		if(!importButton.visible)
			showObsoleteButton.position = vec2i(205, y + 4);
		else
			showObsoleteButton.position = vec2i(410, y + 4);
		clsPanel.updateAbsolutePosition();
		gui_root.updateHover();
	}

	void show() {
		visible = true;
		refresh(playerEmpire);
	}

	void hide() {
		visible = false;
	}

	double timer = 0.0;
	void tick(double time) {
		if(visible) {
			timer += time;
			if(playerEmpire.designCount != prevDesignCount || timer >= 1.5) {
				refresh(playerEmpire);
				timer = 0.0;
			}
		}
	}

	void updateAbsolutePosition() {
		refresh(playerEmpire);
		BaseGuiElement::updateAbsolutePosition();
	}
	
	void draw() {
		//Draw the global background
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);

		BaseGuiElement::draw();
	}

	void selectDesign(const Design@ dsg) {
		uint clsCnt = classes.length;
		for(uint i = 0; i < clsCnt; ++i) {
			DesignClassElement@ clsEl = classes[i];

			uint dsgCnt = clsEl.designs.length;
			for(uint j = 0; j < dsgCnt; ++j) {
				DesignElement@ dsgEl = clsEl.designs[j];
				if(dsgEl.dsg !is dsg) {
					dsgEl.deselect();
				}
				else {
					dsgEl.select();
					@selected = dsgEl;
				}
			}
		}
	}

	void clickDesign(const Design@ dsg, int button = 0) {
		if(button == 2 || (button == 0 && ctrlKey)) {
			Tab@ tab = createDesignEditorTab(dsg);
			tab.locked = locked;
			newTab(this, tab);

			if(shiftKey)
				switchToTab(tab);
		}
		else if(button == 0) {
			showDesignEditor(dsg);
		}
	}

	void scrollToClass(const DesignClass@ cls) {
		uint clsCnt = classes.length;
		for(uint i = 0; i < clsCnt; ++i) {
			DesignClassElement@ clsEl = classes[i];

			if(clsEl.cls !is cls)
				continue;

			clsPanel.vertPosition = clsEl.position.y;
			break;
		}
	}

	void promptCreateClass() {
		if(focusDialog(D_CreateClass))
			return;

		InputDialog@ dialog = InputDialog(CreateClass(this), this);
		dialog.addTitle(locale::CREATE_DESIGN_CLASS);
		dialog.accept.text = locale::CREATE;
		dialog.addTextInput(locale::NAME, "");

		addDialog(D_CreateClass, dialog);
		dialog.focusInput();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this) {
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is createClassButton) {
				promptCreateClass();
				return true;
			}
			else if(event.caller is importButton) {
				DesignImporter diag(this);
				addDialog(diag);
				return true;
			}
			else if(event.caller is showObsoleteButton) {
				refresh(playerEmpire);
				return true;
			}
			else {
				uint clsCnt = classes.length;
				for(uint i = 0; i < clsCnt; ++i) {
					DesignClassElement@ clsEl = classes[i];

					uint dsgCnt = clsEl.designs.length;
					for(uint j = 0; j < dsgCnt; ++j) {
						DesignElement@ dsgEl = clsEl.designs[j];

						if(event.caller is dsgEl) {
							clickDesign(dsgEl.dsg, event.value);
							return true;
						}
					}
				}
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};

class DesignClassElement : BaseGuiElement {
	DesignOverview@ overview;
	const DesignClass@ cls;
	DesignElement@[] designs;
	GuiButton@ createButton;

	DesignClassElement(BaseGuiElement@ pnl, DesignOverview@ ovw) {
		@overview = ovw;
		super(pnl, recti());

		@createButton = GuiButton(this,
			recti(0, 0, int(D_EL_WIDTH * 0.6),
						int(D_EL_HEIGHT * 0.3)),
			locale::CREATE_DESIGN);
		createButton.buttonIcon = icons::Create;
		createButton.font = FT_Medium;
	}

	array<DesignSorter> sorter;
	void refresh(const DesignClass@ Cls) {
		@cls = Cls;

		int width = parent.size.width - 20;
		int perRow = (width - 16) / (D_EL_WIDTH + D_EL_SPACING);

		if(perRow == 0)
			return;

		uint cnt = cls.designCount;
		for(uint i = cnt; i < designs.length; ++i)
			designs[i].remove();

		//Sort designs
		sorter.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			@sorter[i].dsg = cls.designs[i];
		sorter.sortDesc();

		designs.length = cnt;
		uint index = 0;
		for(uint i = 0; i < cnt; ++i) {
			const Design@ dsg = sorter[i].dsg;
			if(!overview.showObsoleteButton.pressed && dsg.obsolete)
				continue;

			//Make a new design class or repurpose one
			DesignElement@ el;
			if(designs[index] !is null) {
				@el = designs[index];
			}
			else {
				@el = DesignElement(this, overview);
				@designs[index] = el;
			}

			//Update the design summary
			el.refresh(dsg);
			++index;
		}
		for(uint i = index; i < cnt; ++i) {
			if(designs[i] !is null)
				designs[i].remove();
		}

		designs.length = index;
		cnt = index;
		uint itemCount = cnt + 1;
		int height = 40 + (itemCount / perRow) * (D_EL_HEIGHT + D_EL_SPACING);
		if(itemCount % perRow != 0 || cls.designCount == 0)
			height += D_EL_HEIGHT + D_EL_SPACING;

		size = vec2i(width, height);

		//Position them
		int x = 8, y = 37;
		for(uint i = 0; i < cnt; ++i) {
			DesignElement@ el = designs[i];
			el.position = vec2i(x, y);

			x += D_EL_WIDTH + D_EL_SPACING;
			if(x + D_EL_WIDTH + D_EL_SPACING > width) {
				x = 8;
				y += D_EL_HEIGHT + D_EL_SPACING;
			}
		}

		createButton.position = vec2i(
				x + D_EL_WIDTH * 0.2,
				y + D_EL_HEIGHT * 0.4);
		visible = designs.length != 0 || cls.designCount == 0;
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is createButton && event.type == GUI_Clicked) {
			overview.refresh(playerEmpire);
			overview.showDesignEditor(null, cls, "", 1.0);
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		if(cls is null)
			return;

		skin.draw(SS_DesignClass, SF_Normal,
			recti(AbsolutePosition.topLeft,
				  AbsolutePosition.botRight - vec2i(6, 6)));

		skin.draw(SS_DesignClassHeader, SF_Normal,
				recti_area(AbsolutePosition.topLeft + vec2i(1, 1),
					vec2i(AbsolutePosition.size.width-9, 30)),
			CLASS_COLORS[cls.id % CLASS_COLORS.length]);
		skin.draw(FT_Medium, AbsolutePosition.topLeft + vec2i(12, 4), cls.name);

		BaseGuiElement::draw();
	}
};

class DesignSorter {
	const Design@ dsg;

	DesignSorter(const Design@ Dsg) {
		@dsg = Dsg;
	}

	DesignSorter() {
	}

	int opCmp(const DesignSorter@ other) const {
		if(dsg.size > other.dsg.size)
			return 1;
		if(dsg.size < other.dsg.size)
			return -1;
		return 0;
	}
};

const string str_Support = "Support";
class DesignElement : BaseGuiElement {
	DesignOverview@ overview;
	GuiBlueprint@ bpview;
	const Design@ dsg;
	GuiText@ title;
	GuiText@ sizeBox;
	GuiText@ moneyBox;
	GuiText@ laborBox;
	GuiSprite@ supportIcon;
	GuiSprite@ satelliteIcon;
	GuiSprite@ flagshipIcon;
	GuiSprite@ stationIcon;

	GuiButton@ editButton;
	GuiButton@ obsoleteButton;

	bool hovered;
	bool selected;
	bool pressed;

	DesignElement(BaseGuiElement@ pnl, DesignOverview@ ovw) {
		super(pnl, recti(0, 0, D_EL_WIDTH, D_EL_HEIGHT));
		
		@overview = ovw;

		hovered = false;
		selected = false;
		pressed = false;

		@bpview = GuiBlueprint(this, recti());
		@bpview.alignment = Alignment(Left+2, Top+28, Left+1.0f-2, Bottom-28);
		bpview.displayHovered = false;

		@editButton = GuiButton(this, Alignment(Right-40, Top+38, Width=34, Height=34));
		editButton.style = SS_IconButton;
		editButton.setIcon(icons::Edit);
		setMarkupTooltip(editButton, locale::TT_EDIT_DESIGN);

		@obsoleteButton = GuiButton(this, Alignment(Right-40, Top+76, Width=34, Height=34));
		obsoleteButton.style = SS_IconButton;
		obsoleteButton.setIcon(icons::Obsolete);
		setMarkupTooltip(obsoleteButton, locale::TT_OBSOLETE_DESIGN);

		@title = GuiText(this, Alignment(Left+8, Top+3, Right-100, Top+30));
		title.font = FT_Subtitle;
		title.stroke = colors::Black;

		@sizeBox = GuiText(this, Alignment(Right-150, Top+3, Right-10, Top+30));
		sizeBox.horizAlign = 1.0;
		sizeBox.font = FT_Subtitle;
		sizeBox.stroke = colors::Black;

		@moneyBox = GuiText(this, Alignment(Left+30, Bottom-31, Right, Bottom-4));
		moneyBox.stroke = colors::Black;

		@laborBox = GuiText(this, Alignment(Left+0.5f, Bottom-31, Right-30, Bottom-4));
		laborBox.horizAlign = 1.0;
		laborBox.stroke = colors::Black;

		@supportIcon = GuiSprite(this, Alignment(Left+8, Top+38, Width=30, Height=30));
		supportIcon.desc = icons::ManageSupports;
		setMarkupTooltip(supportIcon, locale::TT_SUPPORT_DESIGN);
		supportIcon.visible = false;

		@satelliteIcon = GuiSprite(this, Alignment(Left+10, Top+38, Width=36, Height=36));
		satelliteIcon.desc = icons::Satellite;
		setMarkupTooltip(satelliteIcon, locale::TT_SATELLITE_DESIGN);
		satelliteIcon.visible = false;

		@flagshipIcon = GuiSprite(this, Alignment(Left+8, Top+38, Width=30, Height=30));
		flagshipIcon.desc = Sprite(spritesheet::AttributeIcons, 1);
		flagshipIcon.color = Color(0x00e5f7ff);
		setMarkupTooltip(flagshipIcon, locale::TT_FLAGSHIP_DESIGN);
		flagshipIcon.visible = false;

		@stationIcon = GuiSprite(this, Alignment(Left+8, Top+38, Width=30, Height=30));
		stationIcon.desc = Sprite(spritesheet::GuiOrbitalIcons, 0);
		stationIcon.color = Color(0x00e5f7ff);
		setMarkupTooltip(stationIcon, locale::TT_STATION_DESIGN);
		stationIcon.visible = false;

		updateAbsolutePosition();
	}

	void select() {
		selected = true;
	}

	void deselect() {
		selected = false;
	}

	void refresh(const Design@ Dsg) {
		@dsg = Dsg;
		@bpview.hull = dsg.hull;
		@bpview.design = dsg;

		title.text = dsg.name;

		sizeBox.text = format(locale::DESIGN_SIZE, toString(dsg.size, 0));

		const Font@ fnt = skin.getFont(FT_Subtitle);
		@fnt = skin.getFont(FT_Normal);

		int build = 0, maintain = 0;
		double labor = 0;
		getBuildCost(dsg, build, maintain, labor);

		moneyBox.text = formatMoney(build, maintain);
		laborBox.text = standardize(labor);

		supportIcon.visible = dsg.hasTag(ST_SupportShip);
		satelliteIcon.visible = dsg.hasTag(ST_Satellite);
		stationIcon.visible = !supportIcon.visible && dsg.hasTag(ST_Station);
		flagshipIcon.visible = !supportIcon.visible && !stationIcon.visible && !satelliteIcon.visible;

		if(dsg.obsolete) {
			obsoleteButton.setIcon(icons::Unobsolete);
			setMarkupTooltip(obsoleteButton, locale::TT_UNOBSOLETE_DESIGN);
		}
		else {
			obsoleteButton.setIcon(icons::Obsolete);
			setMarkupTooltip(obsoleteButton, locale::TT_OBSOLETE_DESIGN);
		}
	}

	void draw() {
		if(dsg is null)
			return;

		uint flags = SF_Normal;
		if(selected)
			flags |= SF_Active;
		if(hovered)
			flags |= SF_Hovered;

		skin.draw(SS_DesignSummary, flags, AbsolutePosition, dsg.color);
		skin.draw(SS_FullTitle, flags, recti_area(AbsolutePosition.topLeft+vec2i(1,0),
					vec2i(AbsolutePosition.size.width-3,33)), dsg.color);
		if(hovered)
			skin.draw(SS_SubtleGlow, SF_Normal, AbsolutePosition, dsg.color);

		BaseGuiElement::draw();

		//Draw cost
		const Font@ normal = skin.getFont(FT_Normal);
		recti pos = recti_area(vec2i(AbsolutePosition.topLeft.x+4,
					AbsolutePosition.botRight.y-31), vec2i(24, 24));
		getTileResourceSprite(TR_Money).draw(pos);

		//Draw labor
		pos = recti_area(vec2i(AbsolutePosition.botRight.x-32,
					AbsolutePosition.botRight.y-31), vec2i(24, 24));
		getTileResourceSprite(TR_Labor).draw(pos + vec2i(4, 0));
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(cast<GuiButton>(source) is null) {
			switch(event.type) {
				case MET_Button_Down:
					pressed = true;
					return true;
				case MET_Button_Up:
					if(hovered && pressed) {
						GuiEvent evt;
						evt.type = GUI_Clicked;
						evt.value = event.button;
						@evt.caller = this;
						onGuiEvent(evt);
						pressed = false;
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.type == GUI_Clicked) {
			if(event.caller is editButton) {
				emitClicked(event.value);
				return true;
			}
			else if(event.caller is obsoleteButton) {
				bool value = !dsg.obsolete;
				markDesignObsolete(dsg, value);
				dsg.setObsolete(value);
				overview.refresh(playerEmpire);
				return true;
			}
		}
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					hovered = true;
				break;
				case GUI_Mouse_Left:
					hovered = false;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};

Tab@ createDesignOverviewTab() {
	return DesignOverview();
}
