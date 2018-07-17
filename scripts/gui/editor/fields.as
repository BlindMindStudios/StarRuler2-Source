//UI elements for different types of fields.
import elements.BaseGuiElement;
import elements.GuiTextbox;
import elements.GuiText;
import elements.GuiMarkupText;
import elements.GuiCheckbox;
import elements.GuiSprite;
import elements.MarkupTooltip;
import elements.GuiPanel;
import elements.GuiButton;
import elements.GuiContextMenu;
import elements.GuiDropdown;
import editor.completion;
import dialogs.MaterialChooser;
import tile_resources;
import dialogs.ColorDialog;
import icons;
import hooks;
import attributes;
from hooks import TARGET_TYPE_NAMES, getTargetType;
import void openHookEditor(HookField@) from "editor.hooks";
import void openHookList(HookField@) from "editor.hooks";
import void openHookList(HookField@,bool) from "editor.hooks";
import void openLocaleEditor(LocaleField@) from "editor.locale";
import string getFromLocale(string) from "editor.locale";

class Field : BaseGuiElement {
	bool isDefault = false;
	bool verbose = false;
	string docText;
	string defaultValue;

	GuiSprite@ icon;
	GuiText@ label;
	GuiMarkupText@ doc;
	GuiButton@ resetButton;

	Field(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);

		@icon = GuiSprite(this, Alignment(Left+15, Top+0.5f-15, Width=30, Height=30));
		@label = GuiText(this, Alignment(Left+68, Top+4, Left+400, Top+26));
		label.vertAlign = 0.5;
		label.font = FT_Bold;
		@doc = GuiMarkupText(this, Alignment(Left+68, Top+26, Left+385, Bottom-4));
		doc.defaultFont = FT_Small;
		doc.defaultColor = Color(0xaaaaaaff);
		doc.visible = false;
		@resetButton = GuiButton(this, Alignment(Right-34, Top+0.5f-14, Right-6, Top+0.5f+14));
		resetButton.setIcon(icons::Refresh * Color(0xff8000ff));
		resetButton.style = SS_IconButton;
		resetButton.color = Color(0xff8000ff);
		setMarkupTooltip(resetButton, "Reset the value of this field back to its default.");
	}

	void addOption(const string& ident, const string& text = "") {}

	void setVerbose(bool value) {
		if(verbose == value)
			return;
		verbose = value;
		doc.visible = verbose;
	}

	void setValue(int value) {
	}

	void set(const string& label, const string& doc = "", const string& defaultValue = "", const Sprite& icon = Sprite()) {
		if(icon.valid)
			this.icon.desc = icon;
		this.label.text = label;
		this.doc.text = doc;
		this.docText = doc;
		this.defaultValue = defaultValue;
		setMarkupTooltip(this.label, format("[b]$1[/b]\n$2", label, doc));
		update();
	}

	string get_value() {
		return "";
	}

	void set_value(const string& v) {
	}

	void focus() {
	}

	bool get_isValid() {
		return true;
	}

	void set_tabIndex(int ind) {
	}

	void update() {
		if(value == defaultValue) {
			isDefault = true;
			label.color = Color(0xaaaaaaff);
			resetButton.visible = false;
		}
		else {
			isDefault = false;
			label.color = Color(0x00c0ffff);
			resetButton.visible = true;
		}
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) {
		if(source is this || source is label || source is icon || source is doc) {
			if(evt.button == 0) {
				if(evt.type == MET_Button_Down) {
					focus();
					return true;
				}
			}
		}
		return BaseGuiElement::onMouseEvent(evt, source);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed)
			update();
		if(evt.type == GUI_Clicked) {
			if(evt.caller is resetButton) {
				value = defaultValue;
				update();
				emitConfirmed();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	uint get_needHeight() {
		if(!verbose)
			return 30;
		return 50 + min((docText.length / 60) * 20, 80);
	}

	void draw() {
		Color col(0xaaaaffff);
		if(isDefault)
			col = Color(0xaaaaaaff);
		if(!isValid)
			col = Color(0xff8080ff);
		skin.draw(SS_PlainBox, SF_Normal, recti_area(AbsolutePosition.topLeft, vec2i(395, size.height)), col);
		skin.draw(SS_PlainBox, SF_Normal, recti_area(AbsolutePosition.topLeft+vec2i(395,0), vec2i(size.width-395, size.height)), col);
		BaseGuiElement::draw();
	}
};

class TextField : Field {
	GuiTextbox@ box;
	bool changed = false;
	uint lines = 1;

	TextField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@box = GuiTextbox(this, Alignment(Left+400, Top+0.5f-14, Right-42, Top+0.5f+14));
	}

	string get_value() {
		return box.text;
	}

	void setLines(uint value) {
		lines = value;
		box.alignment.top.pixels = -lines*14;
		box.alignment.bottom.pixels = lines*14;
		box.multiLine = lines > 1;
		updateAbsolutePosition();
	}

	void set_value(const string& v) {
		box.text = v;
		update();
	}

	void focus() {
		box.focus(true);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
	}

	uint get_needHeight() {
		if(!verbose)
			return 30 * lines;
		return max(50 + min((docText.length / 60) * 20, 80), 30 * lines);
	}

	void update() {
		Field::update();
		box.style = isDefault ? SS_HoverTextbox : SS_Textbox;

		if(isValid) {
			box.bgColor = colors::White;
		}
		else {
			box.bgColor = colors::Red;
			label.color = colors::Red;
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed)
			changed = true;
		if(evt.type == GUI_Focus_Lost && evt.caller is box && changed) {
			update();
			emitConfirmed();
			changed = false;
		}
		return Field::onGuiEvent(evt);
	}
};

class LocaleField : TextField {
	GuiButton@ editButton;
	string filename;

	LocaleField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		box.alignment.left.pixels = 550;
		@editButton = GuiButton(this, Alignment(Left+400, Top+0.5f-14, Left+545, Top+0.5f+14), "Edit");
		editButton.color = colors::Green;
		editButton.buttonIcon = icons::Info;
	}

	void update() {
		TextField::update();
		box.style = SS_HoverTextbox;
		setMarkupTooltip(box, getFromLocale(value), width=450);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is editButton) {
			openLocaleEditor(this);
			return true;
		}
		return TextField::onGuiEvent(evt);
	}
};

class BoolField : Field {
	GuiCheckbox@ box;

	BoolField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@box = GuiCheckbox(this, Alignment(Left+400, Top+0.5f-12, Width=24, Height=24), "");
	}

	string get_value() {
		return box.checked ? "True" : "False";
	}

	void set_value(const string& v) {
		box.checked = toBool(v);
		update();
	}

	void set(const string& label, const string& doc = "", const string& defaultValue = "", const Sprite& icon = Sprite()) {
		Field::set(label, doc, defaultValue, icon);
		setMarkupTooltip(box, format("[b]$1[/b]\n$2", label, doc));
	}

	void focus() {
		setGuiFocus(box);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed) {
			update();
			emitConfirmed();
		}
		return Field::onGuiEvent(evt);
	}
};

class SelectionField : Field {
	GuiDropdown@ box;
	array<string> idents;

	SelectionField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@box = GuiDropdown(this, Alignment(Left+400, Top+0.5f-14, Right-42, Top+0.5f+14));
		box.itemHeight = 30;
	}

	string get_value() {
		if(box.selected < 0)
			return "";
		return idents[box.selected];
	}

	void set_value(const string& v) {
		box.selected = -1;
		for(uint i = 0, cnt = idents.length; i < cnt; ++i) {
			if(v == idents[i]) {
				box.selected = i;
				break;
			}
		}
		if(box.itemCount != 0 && box.selected < 0)
			box.selected = 0;
		update();
	}

	void focus() {
		setGuiFocus(box);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
	}

	void update() {
		Field::update();
		box.style = isDefault ? SS_HoverButton : SS_Dropdown;
		box.showOnHover = isDefault;
	}

	void addOption(const string& ident, const string& text = "") {
		box.addItem(text.length == 0 ? ident : text);
		idents.insertLast(ident);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed && evt.caller is box) {
			update();
			emitConfirmed();
			return true;
		}
		return Field::onGuiEvent(evt);
	}
};

class TileResourceField : SelectionField {
	TileResourceField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		for(uint i = 0; i < TR_COUNT; ++i)
			addOption(getTileResourceIdent(i));
	}
};

class HookField : Field {
	GuiTextbox@ box;
	bool changed = false;
	bool isStatic = false;
	string hookType;
	string hookModule;
	Hook@ type;
	GuiButton@ editButton;

	HookField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@box = GuiTextbox(this, Alignment(Left+12, Top+4, Right-42, Top+40));
		box.style = SS_HoverTextbox;
		box.font = FT_Bold;

		label.visible = false;
		doc.alignment = Alignment(Left+168, Top+40, Right-18, Bottom-4);
		doc.defaultFont = FT_Italic;
		doc.visible = true;

		@editButton = GuiButton(this, Alignment(Left+18, Top+48, Width=140, Height=30), "Edit");
		editButton.buttonIcon = icons::Edit;

		resetButton.setIcon(icons::Remove);
		setMarkupTooltip(resetButton, "Remove this hook and all its associated effects.");
	}

	string get_value() {
		return box.text;
	}

	void setVerbose(bool v) {
		Field::setVerbose(v);
		doc.visible = true;
	}

	uint get_needHeight() {
		return 100 + (docText.length / 300) * 25;
	}

	void set_value(const string& v) {
		box.text = v;
		update();
	}

	void focus() {
		box.focus(true);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
	}

	void set(const string& label, const string& doc = "", const string& defaultValue = "", const Sprite& icon = Sprite()) {
		Field::set(label, doc, defaultValue, icon);
		if(defaultValue.length != 0 && hookType.length == 0) {
			hookType = defaultValue;
			int pos = defaultValue.findFirst("::");
			if(pos != -1)
				hookModule = defaultValue.substr(0, pos);
			else
				hookModule = "";
			this.defaultValue = "";
			update();
		}
	}

	void makeStatic() {
		editButton.alignment = Alignment(Left+18, Top+40, Width=140, Height=28);
		resetButton.alignment = Alignment(Left+18, Top+68, Width=140, Height=28);
		resetButton.fullIcon.remove();
		@resetButton.fullIcon = null;
		resetButton.text = "Change";
		resetButton.buttonIcon = icons::Paint;
		resetButton.style = SS_Button;
		setMarkupTooltip(resetButton, "Change which hook is applied.");
		isStatic = true;
	}

	void update() {
		Field::update();

		if(hookModule.length != 0 && hookType.length != 0)
			@type = makeHookInstance(value, hookModule+"::", hookType);
		else
			@type = null;
		resetButton.visible = true;
		if(type is null) {
			label.color = colors::Red;
			label.text = "<Hook>";
			box.textColor = colors::White;
			docText = "[color=#ff0000]Invalid hook.[/color]";
			doc.text = docText;
		}
		else {
			label.color = colors::Green;
			label.text = getClass(type).name;
			box.textColor = Color(0x00c0ffff);
			docText = type.formatDeclaration();
			if(type.documentation !is null)
				docText += "\n[offset=80]  "+type.documentation.text+"[/offset]";
			doc.text = docText;
		}
	}

	bool get_isValid() {
		return type !is null;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed) {
			changed = true;
			update();
		}
		if(evt.type == GUI_Focus_Lost && evt.caller is box && changed) {
			update();
			emitConfirmed();
			changed = false;
		}
		if(evt.type == GUI_Clicked && evt.caller is editButton) {
			if(type is null)
				openHookList(this);
			else
				openHookEditor(this);
			return true;
		}
		if(isStatic && evt.type == GUI_Clicked && evt.caller is resetButton) {
			openHookList(this, true);
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() {
		Color col(0x80ff80ff);
		if(!isValid)
			col = Color(0xff8080ff);
		skin.draw(SS_PlainBox, SF_Normal, AbsolutePosition, col);
		BaseGuiElement::draw();
	}
};

class CompletionField : TextField {
	array<Completion@>@ completions;
	Completion@ activeCompletion;
	bool requireListed = true;
	GuiButton@ completeButton;
	GuiSprite@ complIcon;

	CompletionField(IGuiElement@ parent, const recti& pos, array<Completion@>@ completions = null) {
		@this.completions = completions;
		super(parent, pos);
		box.alignment.left.pixels = 580;
		@complIcon = GuiSprite(this, Alignment(Left+548, Top+0.5f-14, Width=28, Height=28));
		@completeButton = GuiButton(this, Alignment(Left+400, Top+0.5f-14, Left+545, Top+0.5f+14), "Choose...");
		completeButton.color = colors::Green;
		completeButton.buttonIcon = icons::Exclaim;
	}

	void set_active(Completion@ compl) {
		@activeCompletion = compl;
		if(compl !is null) {
			complIcon.visible = true;
			complIcon.desc = compl.icon;
		}
		else {
			complIcon.visible = false;
		}
	}

	bool get_isValid() {
		if(!requireListed || completions is null)
			return true;
		string v = value;
		if(v == defaultValue)
			return true;
		for(uint i = 0, cnt = completions.length; i < cnt; ++i) {
			if(completions[i].ident.equals_nocase(v)) {
				@active = completions[i];
				return true;
			}
		}
		@active = null;
		return false;
	}

	void update() {
		TextField::update();
		if(activeCompletion !is null)
			box.bgColor = activeCompletion.color;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is completeButton) {
			GuiContextMenu menu(mousePos, width=500);
			menu.flexWidth = false;
			menu.itemHeight = 30;

			for(uint i = 0, cnt = completions.length; i < cnt; ++i)
				menu.addOption(CompletionOption(this, completions[i]));

			menu.finalize();
			return true;
		}
		return TextField::onGuiEvent(evt);
	}
};

class CompletionOption : GuiMarkupContextOption {
	Completion@ compl;
	Field@ field;

	CompletionOption(Field@ field, Completion@ compl) {
		@this.compl = compl;
		@this.field = field;
		super(compl.format());
	}

	void call(GuiContextMenu@ menu) {
		field.value = compl.ident;
		field.emitConfirmed();
	}
}

class SpriteField : TextField, MaterialChoiceCallback {
	GuiButton@ completeButton;
	GuiSprite@ complIcon;

	SpriteField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		box.alignment.left.pixels = 580;
		@complIcon = GuiSprite(this, Alignment(Left+548, Top+0.5f-14, Width=28, Height=28));
		@completeButton = GuiButton(this, Alignment(Left+400, Top+0.5f-14, Left+545, Top+0.5f+14), "Choose...");
		completeButton.color = colors::Green;
		completeButton.buttonIcon = icons::Exclaim;
	}

	bool get_isValid() {
		return value == defaultValue || getSprite(value).valid;
	}

	void update() {
		TextField::update();
		complIcon.desc = getSprite(value);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is completeButton) {
			openMaterialChooser(this);
			return true;
		}
		return TextField::onGuiEvent(evt);
	}

	void onMaterialChosen(const Material@ material, const string& id) {
		value = id;
		emitConfirmed();
	}

	void onSpriteSheetChosen(const SpriteSheet@ spritebank, uint spriteIndex, const string& id) {
		value = id+"::"+spriteIndex;
		emitConfirmed();
	}
};

class ColorField : TextField, ColorDialogCallback {
	GuiButton@ completeButton;
	GuiSprite@ complIcon;

	ColorField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		box.alignment.left.pixels = 580;
		@complIcon = GuiSprite(this, Alignment(Left+548, Top+0.5f-14, Width=28, Height=28));
		@completeButton = GuiButton(this, Alignment(Left+400, Top+0.5f-14, Left+545, Top+0.5f+14), "Choose...");
		completeButton.color = colors::Green;
		completeButton.buttonIcon = icons::Exclaim;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is completeButton) {
			ColorDialog diag(this, null, toColor(value));
			return true;
		}
		return TextField::onGuiEvent(evt);
	}

	void colorChosen(Color Col) {
		value = toString(Col);
		emitConfirmed();
	}

	void draw() {
		TextField::draw();

		string v = value;
		if(v.length != 0)
			drawRectangle(complIcon.absolutePosition, toColor(v));
	}
};

class MaterialField : TextField {
	MaterialField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	bool get_isValid() {
		return value == defaultValue || getMaterial(value) !is material::error;
	}
};

class ModelField : TextField {
	ModelField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	bool get_isValid() {
		return value == defaultValue || getModel(value) !is model::error;
	}
};

class FileField : TextField {
	FileField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	bool get_isValid() {
		return value == defaultValue || fileExists(resolve(value));
	}
};

class TargetField : Field {
	GuiText@ varLabel;
	GuiTextbox@ box;
	GuiText@ typeLabel;
	GuiDropdown@ type;
	string typeText;
	bool changed = false;

	TargetField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@varLabel = GuiText(this, Alignment(Left+400, Top+0.5f-14, Width=60, Height=28), "Name:");
		@box = GuiTextbox(this, Alignment(Left+465, Top+0.5f-14, Left+665, Top+0.5f+14));
		@typeLabel = GuiText(this, Alignment(Left+670, Top+0.5f-14, Width=60, Height=28), "Type:");
		@type = GuiDropdown(this, Alignment(Left+735, Top+0.5f-14, Left+935, Top+0.5f+14));
		for(uint i = 0; i < TT_COUNT; ++i)
			type.addItem(TARGET_TYPE_NAMES[i]);
		type.selected = 0;
	}

	string get_value() {
		string name = box.text;
		if(name == "")
			return name;
		return name + " = "+typeText;
	}

	void set_value(const string& v) {
		int eqPos = v.findFirst("=");
		if(eqPos == -1) {
			box.text = v;
		}
		else {
			box.text = v.substr(0, eqPos).trimmed();
			typeText = v.substr(eqPos+1).trimmed();
			for(uint i = 0; i < TT_COUNT; ++i) {
				if(TARGET_TYPE_NAMES[i].equals_nocase(typeText)) {
					type.selected = i;
					break;
				}
			}
		}
		update();
	}

	void focus() {
		box.focus(true);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
		type.tabIndex = ind+1;
	}

	void update() {
		Field::update();
		box.style = isDefault ? SS_HoverTextbox : SS_Textbox;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed) {
			if(evt.caller is box) {
				changed = true;
			}
			else if(evt.caller is type) {
				typeText = TARGET_TYPE_NAMES[type.selected];
				update();
				emitConfirmed();
				return true;
			}
		}
		if(evt.type == GUI_Focus_Lost && evt.caller is box && changed) {
			update();
			emitConfirmed();
			changed = false;
		}
		return Field::onGuiEvent(evt);
	}
};

class TileResourceSpecField : Field {
	GuiTextbox@ box;
	GuiDropdown@ type;
	string typeText;
	bool changed = false;

	TileResourceSpecField(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
		@box = GuiTextbox(this, Alignment(Left+400, Top+0.5f-14, Left+495, Top+0.5f+14));
		@type = GuiDropdown(this, Alignment(Left+500, Top+0.5f-14, Left+700, Top+0.5f+14));
		for(uint i = 0; i < TR_COUNT; ++i)
			type.addItem(getTileResourceIdent(i));
		type.selected = 0;
	}

	string get_value() {
		string name = box.text;
		if(name == "")
			return name;
		return name + " "+getTileResourceIdent(type.selected);
	}

	void set_value(const string& v) {
		int eqPos = v.findFirst(" ");
		if(eqPos == -1) {
			box.text = v;
		}
		else {
			box.text = v.substr(0, eqPos).trimmed();
			typeText = v.substr(eqPos+1).trimmed();
			type.selected = getTileResource(typeText);
		}
		update();
	}

	void focus() {
		box.focus(true);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
		type.tabIndex = ind+1;
	}

	void update() {
		Field::update();
		box.style = isDefault ? SS_HoverTextbox : SS_Textbox;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed) {
			if(evt.caller is box) {
				changed = true;
			}
			else if(evt.caller is type) {
				update();
				emitConfirmed();
				return true;
			}
		}
		if(evt.type == GUI_Focus_Lost && evt.caller is box && changed) {
			update();
			emitConfirmed();
			changed = false;
		}
		return Field::onGuiEvent(evt);
	}
};

class TargetChooser : SelectionField {
	TargetType targType = TT_Any;

	TargetChooser(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	void setValue(int value) {
		targType = TargetType(value);
		label.text = label.text + " ("+TARGET_TYPE_NAMES[targType]+")";
	}

	void set(const string& label, const string& doc = "", const string& defaultValue = "", const Sprite& icon = Sprite()) {
		SelectionField::set(label, doc, defaultValue, icon);
		this.label.text = this.label.text + " ("+TARGET_TYPE_NAMES[targType]+")";
	}
};

class VariableField : Field {
	string separator;

	GuiText@ sepLabel;
	GuiTextbox@ box;
	GuiTextbox@ valueBox;
	bool changed = false;

	VariableField(IGuiElement@ parent, const recti& pos, const string& separator = "=", bool limitIdentifier = false) {
		this.separator = separator;
		super(parent, pos);

		@box = GuiTextbox(this, Alignment(Left+400, Top+0.5f-14, Left+565, Top+0.5f+14));
		if(limitIdentifier)
			box.setIdentifierLimit();
		@sepLabel = GuiText(this, Alignment(Left+570, Top+0.5f-14, Width=60, Height=28), separator);
		sepLabel.horizAlign = 0.5;
		sepLabel.font = FT_Bold;
		@valueBox = GuiTextbox(this, Alignment(Left+635, Top+0.5f-14, Left+1035, Top+0.5f+14));
	}

	string get_value() {
		if(box.text.length == 0 || valueBox.text.length == 0)
			return "";
		return box.text+" "+separator+" "+valueBox.text;
	}

	void set_value(const string& v) {
		int eqPos = v.findFirst(separator);
		if(eqPos == -1) {
			box.text = v;
			valueBox.text = "";
		}
		else {
			box.text = v.substr(0, eqPos).trimmed();
			valueBox.text = v.substr(eqPos+separator.length).trimmed();
		}
		update();
	}

	void focus() {
		box.focus(true);
	}

	void set_tabIndex(int ind) {
		box.tabIndex = ind;
		valueBox.tabIndex = ind+1;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Changed) {
			if(evt.caller is box || evt.caller is valueBox) {
				changed = true;
			}
		}
		if(evt.type == GUI_Focus_Lost && (evt.caller is box || evt.caller is valueBox) && changed) {
			update();
			emitConfirmed();
			changed = false;
		}
		return Field::onGuiEvent(evt);
	}
};

Field@ makeField(ArgumentType type, IGuiElement@ parent, const recti& pos) {
	switch(type) {
		case AT_Ability:
			return CompletionField(parent, pos, abilityCompletions);
		case AT_PlanetResource:
			return CompletionField(parent, pos, resourceCompletions);
		case AT_Building:
			return CompletionField(parent, pos, buildingCompletions);
		case AT_Status:
			return CompletionField(parent, pos, statusCompletions);
		case AT_Subsystem:
			return CompletionField(parent, pos, subsysCompletions);
		case AT_Trait:
			return CompletionField(parent, pos, traitCompletions);
		case AT_OrbitalModule:
			return CompletionField(parent, pos, orbitalCompletions);
		case AT_Artifact:
			return CompletionField(parent, pos, artifactCompletions);
		case AT_Technology:
			return CompletionField(parent, pos, techCompletions);
		case AT_PlanetBiome:
			return CompletionField(parent, pos, biomeCompletions);
		case AT_InfluenceCard:
			return CompletionField(parent, pos, cardCompletions);
		case AT_InfluenceVote:
			return CompletionField(parent, pos, voteCompletions);
		case AT_InfluenceEffect:
			return CompletionField(parent, pos, effectCompletions);
		case AT_Anomaly:
			return CompletionField(parent, pos, anomalyCompletions);
		case AT_CreepCamp:
			return CompletionField(parent, pos, creepCompletions);
		case AT_RandomEvent:
			return CompletionField(parent, pos, eventCompletions);
		case AT_Attitude:
			return CompletionField(parent, pos, attitudeCompletions);
		case AT_Boolean:
			return BoolField(parent, pos);
		case AT_Sprite:
			return SpriteField(parent, pos);
		case AT_TileResource:
			return TileResourceField(parent, pos);
		case AT_Selection:
			return SelectionField(parent, pos);
		case AT_Color:
			return ColorField(parent, pos);
		case AT_Material:
			return MaterialField(parent, pos);
		case AT_Model:
			return ModelField(parent, pos);
		case AT_File:
			return FileField(parent, pos);
		case AT_Target:
			return TargetChooser(parent, pos);
		case AT_TargetSpec:
			return TargetField(parent, pos);
		case AT_TileResourceSpec:
			return TileResourceSpecField(parent, pos);
		case AT_VariableDef:
			return VariableField(parent, pos, ":=");
		case AT_ValueDef:
			return VariableField(parent, pos, "=", true);
		case AT_Locale:
			return LocaleField(parent, pos);
		case AT_Hook:
		{
			HookField fld(parent, pos);
			fld.makeStatic();
			return fld;
		}
		case AT_EmpAttribute:
		{
			array<Completion@> attribCompletions;
			for(uint i = 0; i < getEmpAttributeCount(); ++i) {
				Completion compl;
				compl.ident = getEmpAttributeIdent(i);
				attribCompletions.insertLast(compl);
			}

			CompletionField fld(parent, pos, attribCompletions);
			fld.requireListed = false;
			return fld;
		}
		case AT_AttributeMode:
		{
			SelectionField fld(parent, pos);
			fld.addOption("Add",       "Add         (Modify the attribute by a static value)");
			fld.addOption("AddBase",   "AddBase     (Modify the base value of the attribute, before its Factor)");
			fld.addOption("AddFactor", "AddFactor   (Modify the Factor: the base value is multiplied by the Factor)");
			fld.addOption("Multiply",  "Multiply    (Add a multiplication: the entire value including Add is multiplied)");
			return fld;
		}
		case AT_ObjectStatMode:
		{
			SelectionField fld(parent, pos);
			fld.addOption("Add",       "Add         (Add a value to the object stat)");
			fld.addOption("Multiply",  "Multiply    (Multiply the object stat by a value");
			fld.addOption("Set",       "Set         (Set object stat to a new value)");
			return fld;
		}
		case AT_EmpireResource:
		{
			SelectionField fld(parent, pos);
			for(uint i = 0; i < ER_COUNT; ++i)
				fld.addOption(empResources[i], empResources[i]);
			return fld;
		}
		case AT_ObjectType:
		{
			SelectionField fld(parent, pos);
			for(uint i = 0; i < OT_COUNT; ++i)
				fld.addOption(getObjectTypeName(i));
			return fld;
		}
	}
	return TextField(parent, pos);
}

Sprite getFieldIcon(ArgumentType type) {
	return Sprite();
}
