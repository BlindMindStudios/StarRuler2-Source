import elements.BaseGuiElement;
import elements.GuiListbox;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiButton;
import dialogs.QuestionDialog;
import dialogs.InputDialog;

export ChooseFileMode, GuiFileChooser;

enum ChooseFileMode {
	CFM_Filename,
	CFM_Single,
	CFM_Multiple,
};

enum FileType {
	FT_Other,
	FT_Design,
	FT_Directory,
	FT_Back,
};

class FileChooserElement : GuiListElement {
	string path;
	string extension;
	FileType type;

	FileChooserElement() {
		path = "../";
		type = FT_Back;
	}

	FileChooserElement(FileList@ flist, uint num) {
		path = flist.basename[num];

		if(flist.isDirectory[num]) {
			type = FT_Directory;
			path += "/";
		}
		else {
			extension = flist.extension[num];
			if(extension == "design")
				type = FT_Design;
			else
				type = FT_Other;
		}
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();
		vec2i textOffset(ele.horizPadding + 24, (ele.lineHeight - baseLine) / 2);

		if(ele.itemStyle == SS_NULL)
			ele.skin.draw(SS_ListboxItem, flags, absPos);
		spritesheet::FileIcons.draw(type, recti_area(absPos.topLeft + vec2i(ele.horizPadding, 2), vec2i(20, 20)));
		font.draw(absPos.topLeft + textOffset, path);
	}
};

class FileChooserConfirm : QuestionDialogCallback {
	GuiFileChooser@ chooser;
	FileChooserConfirm(GuiFileChooser@ Chooser) {
		@chooser = Chooser;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			chooser.emitConfirmed();
	}
};

class FileChooserConfirmDelete : QuestionDialogCallback {
	GuiFileChooser@ chooser;
	FileChooserConfirmDelete(GuiFileChooser@ Chooser) {
		@chooser = Chooser;
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			chooser.deleteFiles();
	}
};

class FileChooserConfirmMkdir : InputDialogCallback {
	GuiFileChooser@ chooser;
	FileChooserConfirmMkdir(GuiFileChooser@ Chooser) {
		@chooser = Chooser;
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(!accepted)
			return;
		makeDirectory(chooser.realPath(dialog.getTextInput(0)));
		chooser.updateFiles();
	}
};

class GuiFileChooser : BaseGuiElement {
	string filter = "*";
	string root;
	string current;
	ChooseFileMode mode;
	bool PromptOverwrite = true;

	GuiListbox@ list;
	FileList flist;

	GuiText@ label;
	GuiTextbox@ filename;
	GuiButton@ confirm;

	GuiButton@ deleteButton;
	GuiButton@ mkdirButton;

	GuiFileChooser(IGuiElement@ Parent, Alignment@ align, const string& Root, const string&in Initial, ChooseFileMode Mode, bool Management = true) {
		super(Parent, align);
		_GuiFileChooser(Root, Initial, Mode, Management);
	}

	GuiFileChooser(IGuiElement@ Parent, const recti& pos, const string&in Root, const string&in Initial, ChooseFileMode Mode, bool Management = true) {
		super(Parent, pos);
		_GuiFileChooser(Root, Initial, Mode, Management);
	}

	void _GuiFileChooser(const string& Root, const string&in Initial, ChooseFileMode Mode, bool Management) {
		root = Root;
		current = Initial;
		mode = Mode;

		if(mode == CFM_Filename) {
			@list = GuiListbox(this, Alignment(Left, Top+(Management ? 26 : 0), Right, Bottom-28));

			@label = GuiText(this, Alignment(Left+4, Bottom-24, Left+0.25f, Bottom-2), locale::FILENAME_LABEL);

			@filename = GuiTextbox(this, Alignment(Left+0.25f+4, Bottom-24, Left+0.75f, Bottom-2));

			@confirm = GuiButton(this, Alignment(Left+0.75f+4, Bottom-24, Right, Bottom-2), locale::SAVE);
		}
		else {
			@list = GuiListbox(this, Alignment(Left, Top+(Management ? 26 : 0), Right, Bottom));

			if(mode == CFM_Multiple)
				list.multiple = true;
		}

		list.DblClickConfirm = true;
		list.autoMultiple = false;
		list.itemHeight = 24;

		if(Management) {
			@deleteButton = GuiButton(this, Alignment(Left, Top, Left+0.2f, Top+22), locale::DELETE);
			deleteButton.disabled = true;

			@mkdirButton = GuiButton(this, Alignment(Right-0.3f, Top, Right, Top+22), locale::NEW_DIRECTORY);
		}

		updateFiles();
		updateAbsolutePosition();
	}

	string realPath(string file) {
		return path_join(path_join(root, current), file);
	}

	void deleteFiles() {
		uint cnt = list.itemCount;
		for(uint i = 0; i < cnt; ++i) {
			if(!list.isSelected(i))
				continue;
			FileChooserElement@ elem = cast<FileChooserElement>(list.getItemElement(i));
			if(elem is null || elem.type == FT_Back)
				continue;
			deleteFile(realPath(elem.path));
		}
		updateFiles();
	}

	void updateFiles() {
		//Navigate to new directory
		string dir = path_join(root, current);
		flist.navigate(dir, filter);

		//Fill file list
		list.clearItems();
		if(current.length != 0)
			list.addItem(FileChooserElement());
		uint cnt = flist.length;
		for(uint i = 0; i < cnt; ++i)
			if(flist.isDirectory[i])
				list.addItem(FileChooserElement(flist, i));
		for(uint i = 0; i < cnt; ++i)
			if(!flist.isDirectory[i])
				list.addItem(FileChooserElement(flist, i));
	}

	uint get_selectedCount() {
		return list.selectedCount;
	}

	void getSelectedFiles(array<string>@ output, bool fullPath = true) {
		uint cnt = list.itemCount;
		for(uint i = 0; i < cnt; ++i) {
			if(!list.isSelected(i))
				continue;
			FileChooserElement@ elem = cast<FileChooserElement>(list.getItemElement(i));
			if(elem is null)
				continue;
			if(elem.type == FT_Directory || elem.type == FT_Back)
				continue;
			if(fullPath)
				output.insertLast(path_join(path_join(root, current), elem.path));
			else
				output.insertLast(path_join(current, elem.path));
		}
	}

	string getSelectedPath(bool fullPath = true) {
		string fname;
		if(filename !is null) {
			fname = filename.text;
			if(fname.length == 0)
				return fname;
		}
		else {
			if(list.selectedCount == 0)
				return "";
			fname = cast<FileChooserElement>(list.selectedItem).path;
		}
		if(fullPath)
			return path_join(path_join(root, current), fname);
		else
			return path_join(current, fname);
	}

	string get_selectedFilename() {
		return filename.text;
	}

	void set_selectedFilename(string fname) {
		filename.text = fname;
	}

	void clickConfirm() {
		if(mode == CFM_Filename && PromptOverwrite) {
			string path = getSelectedPath(true);
			if(path.length != 0 && fileExists(path)) {
				string basepath = getSelectedPath(false);
				string text = format(locale::CONFIRM_OVERWRITE, basepath);
				question(text, locale::OVERWRITE, locale::CANCEL, FileChooserConfirm(this));
			}
			else {
				emitConfirmed();
			}
		}
		else {
			emitConfirmed();
		}
	}

	void promptMkdir() {
		InputDialog@ dialog = InputDialog(FileChooserConfirmMkdir(this), this);
		dialog.accept.text = locale::CREATE_DIRECTORY;
		dialog.addTextInput(locale::DIRECTORY_LABEL, "");

		addDialog(dialog);
		dialog.focusInput();
	}

	void promptDelete() {
		if(selectedCount == 0)
			return;
		string text = locale::CONFIRM_DELETE_FILES+"\n";
		uint cnt = list.itemCount;
		for(uint i = 0; i < cnt; ++i) {
			if(!list.isSelected(i))
				continue;
			FileChooserElement@ elem = cast<FileChooserElement>(list.getItemElement(i));
			if(elem is null || elem.type == FT_Back)
				continue;
			text += "\n"+elem.path;
		}

		question(text, locale::DELETE, locale::CANCEL, FileChooserConfirmDelete(this));
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_DEL) {
					return true;
				}
			break;
			case KET_Key_Up:
				if(event.key == KEY_DEL) {
					promptDelete();
					return true;
				}
			break;
		}
		if(source !is list && !source.isChildOf(list))
			return list.onKeyEvent(event, list);
		else
			return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is list) {
			switch(event.type) {
				case GUI_Changed:
					if(mode == CFM_Filename) {
						FileChooserElement@ elem = cast<FileChooserElement>(list.selectedItem);
						if(elem is null || elem.type == FT_Directory || elem.type == FT_Back)
							return true;
						filename.text = elem.path;
					}
					deleteButton.disabled = list.selectedCount == 0;
					emitChanged();
				break;
				case GUI_Confirmed: {
					FileChooserElement@ elem = cast<FileChooserElement>(list.getItemElement(event.value));
					if(elem is null)
						return true;
					if(elem.type == FT_Back) {
						if(current.length != 0) {
							current = path_up(current);
							updateFiles();
						}
						return true;
					}
					else if(elem.type == FT_Directory) {
						current = path_join(current, elem.path);
						updateFiles();
						return true;
					}
					else {
						clickConfirm();
						return true;
					}
				}
			}
		}
		else if(event.type == GUI_Clicked) {
			if(event.caller is confirm) {
				clickConfirm();
				return true;
			}
			else if(event.caller is deleteButton) {
				promptDelete();
				return true;
			}
			else if(event.caller is mkdirButton) {
				promptMkdir();
				return true;
			}
		}
		else if(event.caller is filename) {
			if(event.type == GUI_Confirmed) {
				clickConfirm();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
};
