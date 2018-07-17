import menus;
import saving;
import dialogs.MessageDialog;

const string DATE_FORMAT("%Y-%m-%d %H:%M");
class SaveItem : MenuAction {
	string fname;
	int64 mtime;
	string date;

	SaveItem(const string& filename) {
		fname = filename;
		super(getBasename(filename, false), 1);

		mtime = getModifiedTime(filename);
		date = strftime(DATE_FORMAT, mtime);
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		MenuAction::draw(ele, flags, absPos);

		const Font@ detail = ele.skin.getFont(FT_Small);
		detail.draw(pos=absPos.padded(6), text=date, vertAlign=1.0, horizAlign=1.0);
	}

	int opCmp(const SaveItem@ other) const {
		if(mtime < other.mtime)
			return -1;
		if(mtime > other.mtime)
			return 1;
		return 0;
	}
};

class LoadMenu : MenuBox {
	LoadMenu() {
		super();
	}

	void buildMenu() {
		title.text = locale::LOAD_GAME;

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
			if(mpServer && !game_running)
				mpDisconnect();
			switchToMenu(main_menu, false);
			return;
		}
		else if(value == 1) {
			string path = path_join(baseProfile["saves"], name)+".sr2";

			SaveFileInfo info;
			getSaveFileInfo(path, info);

			if(!info.hasMods()) {
				message(locale::SAVE_NO_MODS);
				return;
			}

			uint version = getSaveVersion(path);
			if(!isSaveCompatible(version)) {
				auto@ dialog = message(locale::SAVE_NO_COMPAT);
				dialog.titleColor = colors::Red;
				return;
			}

			switchToMenu(main_menu, false, true);
			loadGame(path);
			return;
		}
	}

	void hide() {
		backgroundFile = "";
		MenuBox::hide();
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Hover_Changed:
				if(event.caller is items) {
					MenuAction@ act = cast<MenuAction>(items.hoveredItem);
					if(act !is null && act.value == 1) {
						backgroundFile = path_join(baseProfile["saves"], act.text)+".png";
						if(!fileExists(backgroundFile))
							backgroundFile = "";
					}
					else
						backgroundFile = "";
					return true;
				}
			break;
		}
		return MenuBox::onGuiEvent(event);
	}
};

void init() {
	@load_menu = LoadMenu();
}
