import tabs.Tab;
import tabs.tabbar;
import editor.files;
import editor.editor;
import elements.GuiPanel;
import elements.GuiSkinElement;
import dialogs.QuestionDialog;
from tabs.ResearchTab import ResearchEditor;
import icons;

class OverviewTab : Tab, QuestionDialogCallback {
	GuiPanel@ filePanel;
	FileFolder@ files;
	string selFile;
	GuiButton@ editButton;
	GuiButton@ deleteButton;

	array<GuiButton@> buttons;

	GuiButton@ researchGridBtn;
	GuiButton@ researchGridBtn2;

	OverviewTab() {
		super();
		title = "Overview";

		GuiSkinElement bg(this, Alignment(Left, Top, Left+400, Bottom), SS_Panel);
		@filePanel = GuiPanel(this, Alignment(Left, Top, Left+400, Bottom-50));
		@files = FileFolder(filePanel, recti());

		@editButton = GuiButton(this, Alignment(Left+200-154, Bottom-46, Width=150, Height=42), "Edit");
		editButton.buttonIcon = icons::Paint;
		editButton.color = colors::Green;
		editButton.visible = false;

		@deleteButton = GuiButton(this, Alignment(Left+200+4, Bottom-46, Width=150, Height=42), "Delete");
		deleteButton.buttonIcon = icons::Delete;
		deleteButton.color = colors::Red;
		deleteButton.visible = false;

		GuiMarkupText desc(this, Alignment(Left+412, Top+12, Right-12, Top+42));
		desc.text = "[i]Choose what type of data files to edit, or choose a specific file contained in your mod from the sidebar to edit.[/i]";

		for(uint i = 0, cnt = fileClasses.length; i < cnt; ++i) {
			GuiButton btn(this, Alignment(Left+412+(i%3)*258, Top+42+(i/3)*50, Width=250, Height=42));
			btn.font = FT_Medium;

			string txt = fileClasses[i];
			txt[0] = uppercase(txt[0]);
			btn.text = txt;

			buttons.insertLast(btn);
		}

		int y = ceil(double(fileClasses.length) / 3.0) * 50 + 42 + 50;
		@researchGridBtn = GuiButton(this, Alignment(Left+412, Top+y, Width=250, Height=42), "Research Grid");
		researchGridBtn.font = FT_Medium;

		if(hasDLC("Heralds")) {
			@researchGridBtn2 = GuiButton(this, Alignment(Left+712, Top+y, Width=250, Height=42), "Grid (Heralds)");
			researchGridBtn2.font = FT_Medium;
		}

		updateAbsolutePosition();
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

	Sprite get_icon() {
		return icons::Edit;
	}

	void show() override {
		files.load(topMod.abspath, base="./", resolve=false);
		selFile = "";
		editButton.visible = false;
		deleteButton.visible = false;
		Tab::show();
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			string path = path_join(topMod.abspath, selFile);
			if(fileExists(path))
				::deleteFile(path);
			show();
		}
	}

	void open(Tab@ tab, int button = 0) {
		if(tab !is null) {
			if(locked || button == 2) {
				newTab(tab);
				switchToTab(tab);
			}
			else {
				browseTab(tab, true);
			}
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is editButton) {
				open(createEditorTab(selFile), evt.value);
				return true;
			}
			else if(evt.caller is deleteButton) {
				question("Are you sure you wish to delete "+selFile+" from the mod? This cannot be undone.\n\nIf the file consisted of changes to a base mod file, deleting the file from your mod will revert the changes back to the original version.", this);
			}
			else if(evt.caller is researchGridBtn) {
				open(ResearchEditor("base_grid.txt", "Base"));
				return true;
			}
			else if(evt.caller is researchGridBtn2) {
				open(ResearchEditor("heralds_grid.txt", "Heralds"));
				return true;
			}
			else for(uint i = 0, cnt = buttons.length; i < cnt; ++i) {
				if(buttons[i] is evt.caller) {
					auto@ tab = createEditorTab(fileFolders[i], cast<FileDef>(getClass(fileTypes[i]).create()));
					open(tab, evt.value);
					return true;
				}
			}
		}
		else if(evt.type == GUI_Confirmed) {
			if(evt.caller is files) {
				setGuiFocus(this);
				selFile = files.getSelection().basePath.substr(2);
				editButton.visible = canEditFile(selFile);
				deleteButton.visible = selFile != "modinfo.txt";
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createOverviewTab() {
	return OverviewTab();
}
