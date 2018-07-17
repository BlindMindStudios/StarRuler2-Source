import tabs.Tab;
import tabs.tabbar;
import editor.editor;
import dialogs.MessageDialog;
import dialogs.InputDialog;
import elements.GuiSkinElement;
import icons;
import cloud_mods;

class ModInfoFile : FileDef {
	array<string> compatModes = {"", "200"};

	ModInfoFile() {
		field("Name", AT_Custom, "", doc="The mod's full name.");
		field("Description", AT_Custom, "", doc="Description of the mod and its contents.");
		field("Base Mod", AT_Boolean, "False", doc="Whether this mod is considered a full base mod. Only one base mod may be active at the same time. [b][color=#f00]Should only be checked for total conversion mods that want to override all base files.[/color][/b]");
		field("Derives From", AT_Custom, "", doc="Inherit the file structure of a different mod. [b]Should only be used for specific extentions of different mods.[/b]");
		field("Override", AT_Custom, "", repeatable=true, doc="[b]Only applies when Deriving From a different mod.[/b] Ignore any files in the specified directory from the base mod.");
		field("Compatibility", AT_Selection, "", doc="Which version of the game this mod was created/updated for.").setOptions(compatModes);
	}
};

class Legal : onButtonClick {
	bool onClick(GuiButton@ btn) {
		cloud::openLegalPrompt();
		return true;
	}
};

array<string> contentTags = {
	"Shipsets",
	"Subsystems",
	"Resources",
	"Races",
	"Maps",
	"Graphics",
	"Sounds"
};

class ModInfoTab : Tab, IInputDialogCallback {
	GuiPanel@ editPanel;
	BlockEditor@ editor;
	GuiMarkupText@ header;
	GuiButton@ uploadButton;
	GuiText@ folderText;
	GuiButton@ folderButton;
	MessageDialog@ diag;

	ModInfoTab() {
		super();
		title = "modinfo.txt";

		GuiSkinElement bg(this, Alignment(Left+12, Top+12, Right-12, Top+200-12), SS_PlainBox);

		@header = GuiMarkupText(this, Alignment(Left+24, Top+24, Right-24, Top+200-46-12));

		@folderText = GuiText(this, Alignment(Left+424, Top+200-46-12, Right-234, Height=40));
		folderText.color = Color(0xaaaaaaff);
		folderText.font = FT_Italic;
		folderText.horizAlign = 1.0;
		folderText.vertAlign = 0.9;
		folderText.text = topMod.abspath;

		@folderButton = GuiButton(this, Alignment(Right-224, Top+200-46-12, Width=200, Height=40), "Open Directory");
		folderButton.buttonIcon = spritesheet::FileIcons+2;

		@uploadButton = GuiButton(this, Alignment(Left+24, Top+200-46-12, Width=400, Height=40), "Upload to Steam Workshop");
		uploadButton.buttonIcon = icons::Export;
		uploadButton.color = Color(0xffff00ff);

		@editPanel = GuiPanel(this, Alignment(Left+12, Top+200, Right-12, Bottom-12));
		@editor = BlockEditor(editPanel);
		editor.parse(path_join(topMod.abspath, "modinfo.txt"), ModInfoFile());

		for(uint i = 0, cnt = editor.fields.length; i < cnt; ++i) {
			if(editor.fields[i].def.key == "Description")
				cast<TextField>(editor.fields[i].elem).setLines(5);
		}

		updateAbsolutePosition();
	}

	void changeCallback(InputDialog@ dialog) {}
	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			array<string> tags;
			tags.insertLast(dialog.getSelectionValue(1));
			for(uint i = 0; i < contentTags.length; ++i)
				if(dialog.getToggle(i + 2))
					tags.insertLast(contentTags[i]);

			uploadMod(topMod.name, dialog.getTextInput(0), tags);
			@diag = message("Uploading to steam workshop...");
		}
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Confirmed) {
			for(uint i = 0, cnt = editor.fields.length; i < cnt; ++i) {
				if(editor.fields[i].def.key == "Name") {
					string val = editor.fields[i].elem.value;
					if(val.length == 0)
						editor.fields[i].elem.value = topMod.ident;
					topMod.name = editor.fields[i].elem.value;
				}
				else if(editor.fields[i].def.key == "Description") {
					string val = editor.fields[i].elem.value;
					topMod.description = val;
					
				}
			}

			editor.commit();
			string path = path_join(topMod.abspath, "modinfo.txt");
			editor.file.save(path);
			saveModState();
			updateAbsolutePosition();
			return true;
		}
		else if(evt.type == GUI_Clicked) {
			if(evt.caller is uploadButton) {
				InputDialog@ dialog = InputDialog(this, this);
				dialog.width = 650;
				dialog.addTitle("Upload to Steam Workshop");
				dialog.accept.text = "Upload";
				dialog.accept.color = colors::Green;

				dialog.addTextInput("Change Note", "", height=200);

				dialog.addSelection("Type");
				dialog.addItem("Mod");

				for(uint i = 0; i < contentTags.length; ++i)
					dialog.addToggle("Tag: " + contentTags[i], false);

				dialog.height += 60;
				GuiButton legalBtn(dialog.bg, Alignment(Left+0.5f-250, Bottom-84, Width=500, Height=34));
				legalBtn.text = "By submitting this item, you agree to the workshop terms of service.";
				@legalBtn.onClick = Legal();

				addDialog(dialog);
				dialog.focusInput();
				return true;
			}
			else if(evt.caller is folderButton) {
				openFileManager(topMod.abspath);
				return true;
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void update() {
		string txt = format("Welcome to the mod editor. You are currently editing the [b]$1[/b] mod.", topMod.name);
		bool errors = false;

		if(!fileExists(path_join(topMod.abspath, "logo.png"))) {
			txt += format(
				"\n\n[b][color=#f00]Please ensure a thumbnail picture for your mod is located in $1.[/color][/b]",
				escape(path_join(topMod.abspath, "logo.png").replaced("\\","/"))
			);
			errors = true;
		}

		uploadButton.visible = cloud::isActive;
		uploadButton.disabled = errors;

		header.text = txt;
	}

	double timer = 0.0;
	void tick(double time) {
		timer -= time;
		if(timer <= 0.0) {
			timer = 1.0;
			update();
		}

		if(diag !is null) {
			if(diag.Closed) {
				@diag = null;
			}
			else {
				switch(uploadStage) {
				case 0:
					diag.txt.text = "Finished uploading to steam workshop!";
					diag.ok.visible = true;
				break;
				case 1:
					diag.txt.text = "Uploading to steam workshop.... Creating item...";
					diag.ok.visible = false;
				break;
				case 2:
					diag.txt.text = "Uploading to steam workshop.... Updating item....";
					diag.ok.visible = false;
				break;
				case 3:
					diag.txt.text = "Uploading to steam workshop.... "+uploadPercent+"%";
					diag.ok.visible = false;
				break;
				}
			}
		}
	}

	Sprite get_icon() {
		return icons::Info;
	}

	Color get_activeColor() {
		return Color(0x74fc4eff);
	}

	Color get_inactiveColor() {
		return Color(0x37ff00ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x408c2bff);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createModInfoTab() {
	return ModInfoTab();
}
