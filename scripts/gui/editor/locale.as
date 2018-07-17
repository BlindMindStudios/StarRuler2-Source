import elements.GuiMarkupText;
import elements.GuiButton;
import elements.GuiTextbox;
import elements.GuiText;
import editor.fields;
import dialogs.Dialog;
import string getLocaleFile(IGuiElement@ elem) from "editor.editor";

bool localesInitialized = false;
void initLocaleMap() {
	if(localesInitialized) {
		loadLocaleMap();
		localesInitialized = true;
	}
}

dictionary localeMap;
dictionary localeValues;
string localeName;
void loadLocaleMap() {
	localeName = settings::sLocale;

	string resolved = resolve("locales/"+localeName);
	if(!fileExists(resolved))
		localeName = "english";
	localeMap.deleteAll();

	string folder = topMod.abspath+"/locales/"+localeName;
	FileList list(folder, "*.txt", true, false);
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		ReadFile file(list.path[i]);
		string fname = "locales/"+localeName+"/"+list.basename[i];
		while(file++) {
			localeMap.set(file.key, fname);
			localeValues.set(file.key, file.value);
		}
	}
}

string getFromLocale(string ident) {
	loadLocaleMap();
	if(ident.length != 0 && ident[0] == '#')
		ident = ident.substr(1);
	string val;
	if(!localeValues.get(ident, val))
		val = localize(ident);
	return val;
}

void changeLocale(string ident, string value, string filename = "misc.txt") {
	initLocaleMap();
	if(topMod !is baseMod)
		filename = topMod.ident+"_"+filename;
	if(ident.length != 0 && ident[0] == '#')
		ident = ident.substr(1);

	//Check if it's in an existing locale
	string fname;
	if(localeMap.get(ident, fname)) {
		filename = path_join(topMod.abspath, fname);
		changeLocaleIn(filename, ident, value);
		localeValues.set(ident, value);
	}
	else {
		localeMap.set(ident, "locales/"+localeName+"/"+filename);
		filename = path_join(path_join(topMod.abspath, "locales/"+localeName), filename);
		changeLocaleIn(filename, ident, value);
		localeValues.set(ident, value);
	}
}

void ensureFile(const string& path) {
	string dir = path_up(path);
	array<string> folders;
	while(!fileExists(dir) && dir.length != 0) {
		folders.insertLast(dir);
		dir = path_up(dir);
	}
	for(int i = int(folders.length-1); i >= 0; --i)
		makeDirectory(folders[i]);
}

void changeLocaleIn(const string& filename, const string& ident, const string& value) {
	array<string> lines;
	int pos = -1;

	//Read existing file
	if(fileExists(filename)) {
		ReadFile read(filename);
		read.allowLines = true;
		read.allowMultiline = false;
		read.skipEmpty = false;
		read.skipComments = false;
		bool inMulti = false;
		while(read++) {
			if(inMulti) {
				if(read.line.trimmed().startswith(">>"))
					inMulti = false;
				continue;
			}
			if(read.key == ident) {
				pos = lines.length;
				if(read.value.trimmed().startswith("<<"))
					inMulti = true;
				read.key = "";
				continue;
			}
			lines.insertLast(read.line);
		}
	}
	else {
		if(value.length == 0)
			return;
		ensureFile(filename);
	}

	for(int i = lines.length-1; i >= 0; --i) {
		if(lines[i].trimmed().length == 0)
			lines.removeAt(i);
		else
			break;
	}

	//Manipulate lines
	if(value.length != 0) {
		string line = ident+": ";
		if(value.findFirst("\n") == -1) {
			line += escape(value);
		}
		else {
			line += "<<\r\n";
			array<string>@ splt = value.split("\n");
			for(uint i = 0, cnt = splt.length; i < cnt; ++i) {
				if(splt[i].length == 0)
					line += "\r\n";
				else
					line += "\t"+splt[i].trimmed()+"\r\n";
			}
			line += ">>";
		}

		if(pos == -1)
			lines.insertLast(line);
		else
			lines.insertAt(pos, line);
	}

	//Write new file
	WriteFile write(filename);
	for(uint i = 0, cnt = lines.length; i < cnt; ++i)
		write.writeLine(lines[i]);
}

class LocaleEditor : Dialog {
	LocaleField@ field;
	GuiButton@ accept;
	GuiButton@ cancel;

	GuiText@ identLabel;
	GuiTextbox@ identBox;
	GuiButton@ identLoad;

	GuiText@ valueLabel;
	GuiTextbox@ valueBox;

	GuiText@ previewLabel;
	GuiPanel@ previewPanel;
	GuiMarkupText@ previewBox;

	bool changed = false;
	string localeIdent;
	string suffix;
	string origValue;

	LocaleEditor(LocaleField@ field) {
		@this.field = field;
		super(null);
		width = 1000;
		addTitle("Edit Locale");

		string value;
		localeIdent = field.value;
		suffix = "";

		if(localeIdent.length == 0 || localeIdent[0] != '#') {
			value = localeIdent;
			localeIdent = "";
		}
		else {
			int sep = localeIdent.findFirst(":");
			if(sep != -1) {
				suffix = localeIdent.substr(sep);
				localeIdent = localeIdent.substr(0, sep);
			}
			value = getFromLocale(localeIdent);
			origValue = value;
		}

		@identLabel = GuiText(bg, Alignment(Left+10, Top+34, Width=80, Height=30), "Locale Key:");
		identLabel.font = FT_Bold;
		@identBox = GuiTextbox(bg, Alignment(Left+100, Top+34, Width=400, Height=30), localeIdent);
		identBox.setIdentifierLimit();
		identBox.characterLimit.insert('#');
		@identLoad = GuiButton(bg, Alignment(Left+508, Top+34, Width=80, Height=30), "Load");
		setMarkupTooltip(identLoad, "Load the value of the specified locale key into the value box. Will override anything already written.");

		@valueLabel = GuiText(bg, Alignment(Left+10, Top+70, Left+0.5f-6, Top+100), "Value:");
		valueLabel.font = FT_Bold;
		@valueBox = GuiTextbox(bg, Alignment(Left+12, Top+100, Left+0.5f-6, Bottom-60));
		valueBox.multiLine = true;

		@previewLabel = GuiText(bg, Alignment(Left+0.5f+4, Top+70, Right-12, Top+100), "Preview:");
		previewLabel.font = FT_Bold;
		@previewPanel = GuiPanel(bg, Alignment(Left+0.5f+6, Top+100, Right-12, Bottom-60));
		@previewBox = GuiMarkupText(previewPanel, recti_area(0,0,482,100));

		@accept = GuiButton(bg, recti());
		accept.text = locale::ACCEPT;
		accept.tabIndex = 100;
		@accept.callback = this;
		accept.color = colors::Green;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;
		cancel.color = colors::Red;

		alignAcceptButtons(accept, cancel);

		valueBox.text = value;
		previewBox.text = value;
		valueBox.scroll = 0;

		height = 500;
		update();
		bg.updateAbsolutePosition();
	}

	void update() {
		previewBox.text = valueBox.text;
	}

	void confirm() {
		if(changed) {
			if(identBox.text.length != 0) {
				string fname = field.filename;
				if(fname.length == 0)
					fname = getLocaleFile(field);
				if(origValue != valueBox.text)
					changeLocale(identBox.text, valueBox.text, fname);
			}
		}

		localeIdent = identBox.text;
		if(localeIdent.length == 0) {
			field.value = valueBox.text;
		}
		else {
			if(localeIdent[0] != '#')
				localeIdent = "#"+localeIdent;
			field.value = localeIdent+suffix;
		}
		field.emitConfirmed();
	}

	void focus() {
		valueBox.focus();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked && event.caller is accept && !Closed) {
			confirm();
			close();
			return true;
		}
		if(event.type == GUI_Clicked && event.caller is cancel && !Closed) {
			close();
			return true;
		}
		if(event.type == GUI_Changed && (event.caller is valueBox || event.caller is identBox)) {
			previewBox.text = valueBox.text;
			previewPanel.updateAbsolutePosition();
			changed = true;
			return true;
		}
		if(event.type == GUI_Clicked) {
			if(event.caller is identLoad) {
				string v = getFromLocale(identBox.text);
				valueBox.text = v;
				previewBox.text = v;
				previewPanel.updateAbsolutePosition();
				changed = true;
				return true;
			}
		}
		return Dialog::onGuiEvent(event);
	}
};

void openLocaleEditor(LocaleField@ field) {
	LocaleEditor ed(field);
	addDialog(ed);
	ed.focus();
}
