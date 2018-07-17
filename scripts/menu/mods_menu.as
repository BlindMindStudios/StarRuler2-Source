import menus;
import saving;
import dialogs.MessageDialog;
import dialogs.QuestionDialog;
import dialogs.InputDialog;
import elements.GuiMarkupText;
import settings.game_settings;
from irc_window import LinkableMarkupText;
import icons;

class ModAction : MenuAction {
	Mod@ mod;
	DynamicTexture@ tex;
	bool prevEnabled;

	ModAction(Mod@ mod, DynamicTexture@ tex) {
		super(Sprite(tex.material), mod.name, 0);
		@this.mod = mod;
		@this.tex = tex;
		prevEnabled = mod.enabled;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		if(!mod.forCurrentVersion)
			color = Color(0xaa4040ff);
		else if(!mod.enabled)
			color = Color(0x888888ff);
		else
			color = colors::White;
		MenuAction::draw(ele, flags, absPos);

		int h = absPos.height;
		recti iPos = recti_area(vec2i(absPos.botRight.x-h-80+8, absPos.topLeft.y+10), vec2i(h-18, h-18));
		recti tPos = recti_area(vec2i(absPos.botRight.x-80, absPos.topLeft.y+2), vec2i(78, h-2));
		const Font@ ft = ele.skin.getFont(FT_Bold);
		if(mod.enabled) {
			icons::Plus.draw(iPos);
			ft.draw(pos=tPos, text=locale::ENABLED, stroke=colors::Black, color=colors::Green);
		}
		else {
			icons::Minus.draw(iPos);
			ft.draw(pos=tPos, text=locale::DISABLED, stroke=colors::Black, color=colors::Red);
		}

		if(mod.isNew && mod.forCurrentVersion) {
			recti iPos = recti_area(vec2i(absPos.botRight.x-h-80*2+4, absPos.topLeft.y+6), vec2i(h-10, h-10));
			recti tPos = recti_area(vec2i(absPos.botRight.x-80*2, absPos.topLeft.y+2), vec2i(78, h-2));
			const Font@ ft = ele.skin.getFont(FT_Bold);
			spritesheet::CardCategoryIcons.draw(5, iPos);
			ft.draw(pos=tPos, text=locale::NEW, stroke=colors::Black, color=Color(0xffff00ff));
		}
	}

	int opCmp(const ModAction@ other) const {
		if(mod.isNew && !other.mod.isNew)
			return -1;
		if(other.mod.isNew && !mod.isNew)
			return 1;
		if(mod.enabled && !other.mod.enabled)
			return -1;
		if(other.mod.enabled && !mod.enabled)
			return 1;
		return 0;
	}
};

bool inOpenPage = false;
class ModsMenu : MenuBox, IInputDialogCallback {
	ModBox box;
	int prevSelected = -1;
	array<ModAction@> actions;

	GuiButton@ newButton;
	GuiButton@ editButton;

	ModsMenu() {
		super();
		items.alignment.bottom.pixels = 40;
		@newButton = GuiButton(this, Alignment(Left+0.5f-202, Bottom-35, Width=200, Height=30), locale::NEW_MOD);
		newButton.visible = !inOpenPage;
		@editButton = GuiButton(this, Alignment(Left+0.5f+2, Bottom-35, Width=200, Height=30), locale::EDIT_MOD);
		editButton.visible = items.selected >= 1 && !inOpenPage;
	}

	void buildMenu() {
		title.text = locale::MODS_MENU;
		selectable = true;
		items.required = true;

		if(inOpenPage)
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 10), locale::MENU_CONTINUE_MAIN, 0));
		else
			items.addItem(MenuAction(Sprite(spritesheet::MenuIcons, 11), locale::MENU_BACK, 0));

		string sel = "";
		if(prevSelected >= 1 && uint(prevSelected-1) < actions.length)
			sel = actions[prevSelected-1].mod.name;
		actions.length = 0;

		for(uint i = 0, cnt = modCount; i < cnt; ++i) {
			auto@ mod = getMod(i);
			if(!mod.listed)
				continue;

			DynamicTexture tex;

			if(fileExists(path_join(mod.abspath, "logo.png")))
				tex.load(path_join(mod.abspath, "logo.png"));

			ModAction action(mod, tex);
			actions.insertLast(action);
		}
		actions.sortAsc();
		for(uint i = 0, cnt = actions.length; i < cnt; ++i) {
			actions[i].value = int(i+1);
			if(actions[i].mod.name == sel)
				prevSelected = i;
			if(prevSelected == -1 && actions[i].mod.isNew)
				prevSelected = i+1;
			items.addItem(actions[i]);
		}
		if(prevSelected < 1)
			prevSelected = 1;
		if(items.selected < 1)
			items.selected = min(prevSelected, items.itemCount-1);
		update();
	}

	void update() {
		if(items.selected < 1 || uint(items.selected-1) >= actions.length)
			return;
		auto@ mod = actions[items.selected-1].mod;
		if(mod !is null)
			box.update(mod, actions[items.selected-1].tex.material);
		editButton.visible = items.selected >= 1 && !inOpenPage;
		newButton.visible = !inOpenPage;
	}

	void changeCallback(InputDialog@ dialog) {}
	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			string dirname = dialog.getTextInput(0);
			if(!createNewMod(dirname)) {
				message("Could not create mod: invalid directory '"+dirname+"'");
				return;
			}
			editMod(dirname);
		}
	}

	void editMod(const string& modName) {
		array<string> mods;
		mods.insertLast(modName);

		GameSettings settings;
		settings.defaults();
		settings.galaxies[0].map_id = "ModEditor.ModEditor";

		Message msg;
		settings.write(msg);

		watchResources = true;
		switchToMods(mods);
		startNewGame(msg);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked) {
			if(event.caller is newButton) {
				InputDialog@ dialog = InputDialog(this, this);
				dialog.addTitle("Create New Mod");
				dialog.accept.text = "Create";
				dialog.addTextInput("Mod Directory", "");

				auto@ tbox = cast<GuiTextbox>(dialog.getInput(0));
				tbox.setIdentifierLimit();
				tbox.characterLimit.insert(' ');

				addDialog(dialog);
				dialog.focusInput();
				return true;
			}
			else if(event.caller is editButton) {
				if(items.selected < 1 || uint(items.selected-1) >= actions.length)
					return true;
				Mod@ mod = actions[items.selected-1].mod;
				editMod(mod.name);
				return true;
			}
		}
		return MenuBox::onGuiEvent(event);
	}

	void onSelected(const string& name, int value) {
		if(value == 0) {
			switchToMenu(main_menu, false);
			saveModState();
			inOpenPage = false;

			if(!game_running) {
				array<string> mods;
				bool changed = false;
				for(uint i = 0, cnt = actions.length; i < cnt; ++i) {
					if(actions[i].mod.enabled != actions[i].prevEnabled)
						changed = true;
					if(actions[i].mod.enabled)
						mods.insertLast(actions[i].mod.name);
				}
				if(changed)
					switchToMods(mods);
			}
			return;
		}
		else {
			prevSelected = value;
			items.selected = value;
			update();
		}
	}

	void animate(MenuAnimation type) {
		if(type == MAni_LeftOut || type == MAni_RightOut)
			showDescBox(null);
		MenuBox::animate(type);
	}

	void completeAnimation(MenuAnimation type) {
		if(type == MAni_LeftShow || type == MAni_RightShow)
			showDescBox(box);
		MenuBox::completeAnimation(type);
	}

	void draw() {
		for(uint i = 0, cnt = actions.length; i < cnt; ++i)
			actions[i].tex.stream();
		MenuBox::draw();
	}
};

class ModBox : DescBox {
	Mod@ mod;
	GuiPanel@ descPanel;
	GuiSprite@ picture;
	GuiMarkupText@ description;
	GuiButton@ toggleButton;

	ModBox() {
		super();

		@picture = GuiSprite(this, Alignment(Left, Top+44, Right, Top+244));

		@descPanel = GuiPanel(this, Alignment(Left+16, Top+254, Right-16, Bottom-50));
		@description = LinkableMarkupText(descPanel, recti_area(0,0,100,100));
		description.fitWidth = true;

		@toggleButton = GuiButton(this, Alignment(Left+0.5f-100, Bottom-50, Left+0.5f+100, Bottom-8));
		toggleButton.font = FT_Subtitle;
		toggleButton.visible = false;

		updateAbsolutePosition();
		updateAbsolutePosition();
	}

	void update(Mod@ mod, const Material@ mat = null) {
		@this.mod = mod;
		title.text = mod.name;
		if(mat !is null)
			picture.desc = Sprite(mat);
		string descText;
		if(!mod.forCurrentVersion)
			descText += locale::MOD_COMPATIBILITY_WARN;
		descText += mod.description;
		toggleButton.visible = true;
		toggleButton.disabled = false;

		if(mod.enabled) {
			toggleButton.color = colors::Red;
			toggleButton.buttonIcon = icons::Minus;
			toggleButton.text = locale::DISABLE_MOD;
		}
		else {
			toggleButton.color = colors::Green;
			toggleButton.buttonIcon = icons::Plus;
			toggleButton.text = locale::ENABLE_MOD;
		}

		//Check for conflicts
		for(uint i = 0, cnt = modCount; i < cnt; ++i) {
			auto@ other = getMod(i);
			if(other !is mod && other.enabled) {
				if(!other.isCompatible(mod)) {
					array<string> conflicts;
					mod.getConflicts(other, conflicts);

					descText += "\n\n[color=#f00][b]";
					descText += format(locale::MOD_INCOMPATIBLE, other.name);
					if(mod.isBase && other.isBase) {
						descText += "\n"+locale::MOD_CONFLICT_BASE;
						descText += "[/b]";
					}
					else {
						descText += "\n"+locale::MOD_CONFLICT;
						descText += "[/b]\n    ";
						for(uint i = 0, cnt = conflicts.length; i < cnt; ++i) {
							if(i != 0)
								descText += ", ";
							descText += conflicts[i];
						}
					}
					descText += "[/color]";
					toggleButton.disabled = true;
				}
			}
		}

		description.text = makebbLinks(descText);
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked && evt.caller is toggleButton) {
			bool enable = !mod.enabled;
			if(enable && !mod.forCurrentVersion) {
				question(locale::MOD_COMPATIBILITY, ModEnable(this, mod));
			}
			else {
				mod.enabled = enable;
				mod.forced = false;
				update(mod);
				saveModState();
			}
			return true;
		}
		return DescBox::onGuiEvent(evt);
	}
};

class ModEnable : QuestionDialogCallback {
	ModBox@ menu;
	Mod@ mod;

	ModEnable(ModBox@ menu, Mod@ mod) {
		@this.menu = menu;
		@this.mod = mod;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			mod.enabled = true;
			mod.forced = true;
			menu.update(mod);
			saveModState();
		}
	}
};

void init() {
	@mods_menu = ModsMenu();
}

void postInit() {
	for(uint i = 0, cnt = modCount; i < cnt; ++i) {
		if(getMod(i).isNew) {
			inOpenPage = true;
			switchToMenu(mods_menu, snap=true);
			showDescBox(cast<ModsMenu>(mods_menu).box);
			mods_menu.updateAbsolutePosition();
		}
	}
}
