import menus;
import elements.GuiTextbox;
from load_menu import SaveItem;

class SaveData {
	string filename;
	
	SaveData(const string& Filename) {
		filename = Filename;
	}
};

double SaveThread(double time, ScriptThread& thread) {
	SaveData@ data;
	thread.getObject(@data);
	
	saveGame(path_join(baseProfile["saves"], data.filename)+".sr2");
	
	thread.stop();
	return 0;
}

class SaveMenu : MenuBox {
	GuiTextbox@ saveName;
	GuiButton@ saveButton;

	SaveMenu() {
		super();

		items.alignment.top = Top+40;
		items.alignment.bottom = Bottom-40;

		@saveName = GuiTextbox(this, Alignment(Left+12, Bottom-36, Right-212, Bottom-4));
		saveName.text = "quicksave";
		saveName.font = FT_Medium;

		@saveButton = GuiButton(this, Alignment(Right-206, Bottom-36, Right-12, Bottom-4), "Save");
		saveButton.font = FT_Medium;
	}

	void buildMenu() {
		title.text = locale::SAVE_GAME;

		items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 11), locale::MENU_BACK, 0));

		string dir = baseProfile["saves"];
		FileList files(dir, "*.sr2");

		uint cnt = files.length;
		array<SaveItem@> list;
		for(uint i = 0; i < cnt; ++i)
			list.insertLast(SaveItem(files.path[i]));
		list.sortDesc();
		for(uint i = 0; i < cnt; ++i)
			items.addItem(list[i]);
	}

	void onSelected(const string& name, int value) {
		if(value == 0) {
			switchToMenu(main_menu, false);
			return;
		}
		else if(value == 1) {
			saveName.text = name;
			return;
		}
	}

	bool onGuiEvent(const GuiEvent& event) {
			if((event.type == GUI_Clicked && event.caller is saveButton) ||
				(event.type == GUI_Confirmed && event.caller is saveName))
			{
				//double start = getExactTime();
				ScriptThread@ thread = ScriptThread("save_menu::SaveThread", @SaveData(saveName.text));
				saveWorldScreen(path_join(baseProfile["saves"], saveName.text)+".png");
				
				while(thread.running)
					sleep(0);
				
				//double end = getExactTime();
				//print(format("Saving took $1 seconds", string(end-start)));
				switchToMenu(main_menu, false, true);
				switchToGame();
				return true;
			}
		return MenuBox::onGuiEvent(event);
	}
};

void init() {
	@save_menu = SaveMenu();
}
