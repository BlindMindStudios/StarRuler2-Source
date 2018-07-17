import elements.GuiMarkupText;
import elements.GuiListbox;
import editor.fields;
import dialogs.Dialog;
import void fillTargetsFromTab(Field@ sourceField, TargetChooser@ fld) from "editor.editor";

class HookEditor : Dialog {
	HookField@ field;
	string typeName;
	Hook@ type;
	GuiButton@ ok;
	string suffix;

	GuiMarkupText@ text;
	array<Field@> args;

	HookEditor(HookField@ field) {
		@this.field = field;
		@type = field.type;
		super(null);
		width = 1000;
		addTitle(getClass(field.type).name);

		@text = GuiMarkupText(bg, recti_area(12,32,width-24,30));

		@ok = GuiButton(bg, recti());
		ok.text = locale::OK;

		if(isWindows) {
			//Legacy OS support
			@ok.alignment = Alignment(Left+0.4f+DIALOG_PADDING, Bottom-DIALOG_BUTTON_ROW, Right-0.4f-DIALOG_PADDING, Bottom-DIALOG_PADDING);
		}
		else {
			@ok.alignment = Alignment(Right-0.2f-DIALOG_PADDING, Bottom-DIALOG_BUTTON_ROW, Right-0.0f-DIALOG_PADDING, Bottom-DIALOG_PADDING);
		}

		update();
	}

	void focus() {
		if(args.length != 0)
			args[0].focus();
	}

	void update() {
		int y = 32;
		string doc = type.formatDeclaration();
		if(type.documentation !is null)
			doc += "\n[offset=20][i]"+type.documentation.text+"[/i][/offset]";
		text.text = doc;
		text.updateAbsolutePosition();
		y += text.size.height+12;

		array<string> argValues;
		array<string> argSpecs;
		argValues.length = type.arguments.length;
		string hookText = field.value;
		if(funcSplit(hookText, typeName, argSpecs)) {
			for(uint i = 0, cnt = argSpecs.length; i < cnt; ++i) {
				if(i >= argValues.length) {
					if(argValues.length != 0)
						argValues[argValues.length - 1] += ","+argSpecs[i].trimmed();
					continue;
				}

				//Check for named arguments
				int eqPos = argSpecs[i].findFirst("=");
				int brkPos = argSpecs[i].findFirst("(");

				if(eqPos != -1 && (brkPos == -1 || eqPos < brkPos)) {
					//Named argument
					uint index = uint(-1);
					string name = argSpecs[i].substr(0, eqPos).trimmed();
					string value = argSpecs[i].substr(eqPos+1).trimmed();
					for(uint n = 0, ncnt = argValues.length; n < ncnt; ++n) {
						if(type.arguments[n].argName.equals_nocase(name)) {
							index = n;
							break;
						}
					}

					if(index != uint(-1))
						argValues[index] = value;
				}
				else {
					argValues[i] = argSpecs[i].trimmed();
				}
			}

			int brktPos = hookText.findLast(")");
			if(brktPos != -1)
				suffix = hookText.substr(brktPos+1);
		}

		for(uint i = 0, cnt = type.arguments.length; i < cnt; ++i) {
			auto@ arg = type.arguments[i];
			auto atype = arg.type;
			if(atype == AT_VarArgs)
				atype = ArgumentType(arg.integer);
			auto@ fld = makeField(atype, bg, recti());
			if(atype == AT_Target) {
				fld.setValue(arg.integer2);
				fillTargetsFromTab(field, cast<TargetChooser>(fld));
			}

			fld.setVerbose(true);
			fld.set(arg.argName, arg.doc, arg.filled ? arg.str : "");
			if(argValues[i].length != 0)
				fld.value = argValues[i];
			else
				fld.value = fld.defaultValue;
			fld.tabIndex = i;
			fld.updateAbsolutePosition();

			int h = fld.needHeight;
			fld.size = vec2i(width-24, h);
			fld.position = vec2i(12, y);

			y += h;
			args.insertLast(fld);
		}

		if(args.length != 0)
			args[0].focus();

		y += 40;
		height = y;
		updatePosition();
		bg.updateAbsolutePosition();
	}

	void confirm() {
		string spec = typeName+"(";
		bool skipped = false, filled = false;
		for(uint i = 0, cnt = type.arguments.length; i < cnt; ++i) {
			auto@ arg = type.arguments[i];
			string value = args[i].value;
			if(arg.filled && value == arg.str) {
				skipped = true;
				continue;
			}
			if(filled)
				spec += ", ";
			if(skipped || (arg.filled && arg.type != AT_Hook))
				spec += arg.argName+" = ";
			spec += value;
			filled = true;
		}
		spec += ")";
		spec += suffix;

		field.value = spec;
		field.emitConfirmed();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked && event.caller is ok && !Closed) {
			confirm();
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

class HookSorter {
	string name;
	string text;
	AnyClass@ cls;
	Hook@ hook;

	int opCmp(const HookSorter@ other) const {
		return name.opCmp(other.name);
	}
};

class HookList : Dialog {
	HookField@ field;
	Hook@ type;
	GuiButton@ accept;
	GuiButton@ cancel;

	GuiListbox@ hookList;
	array<HookSorter@> hooks;

	HookList(HookField@ field) {
		@this.field = field;
		@type = field.type;
		super(null);
		width = 800;
		addTitle("Add Hook");

		@hookList = GuiListbox(bg, Alignment(Left+12, Top+32, Right-12, Bottom-40));
		hookList.itemHeight = 70;

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

		height = 600;
		update();
		setGuiFocus(hookList);
	}

	void update() {
		AnyClass@ intf = getClass(field.hookType);
		array<AnyClass@> classes;
		getClassesImplementing(classes, intf);

		set_int types;
		for(uint i = 0, cnt = classes.length; i < cnt; ++i) {
			auto@ cls = classes[i];
			if(types.contains(cls.id))
				continue;
			types.insert(cls.id);

			Hook@ hook = cast<Hook>(cls.create());
			if(hook is null)
				continue;
			hook.initClass();
			if(hook.documentation !is null && hook.documentation.hidden)
				continue;

			string txt = "[b]"+hook.formatDeclaration()+"[/b]";
			if(hook.documentation !is null) {
				txt += "\n[offset=24][i][color=#aaa]"+hook.documentation.text+"[/color][/i][/offset]";
			}

			HookSorter s;
			s.name = getClass(hook).name;
			s.text = txt;
			@s.cls = cls;
			@s.hook = hook;

			hooks.insertLast(s);
		}

		hooks.sortAsc();
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			GuiMarkupListText elem(hooks[i].text);
			elem.basicText = hooks[i].name;
			hookList.addItem(elem);
		}
	}

	bool confirmed = false;
	void close() {
		if(!confirmed && field.value == "")
			field.resetButton.emitClicked();
		Dialog::close();
	}

	void confirm() {
		int selected = hookList.selected;
		if(selected == -1)
			return;

		confirmed = true;
		auto@ s = hooks[selected];
		string hname = "";
		if(getClass(field.hookModule+"::"+s.name) !is s.cls)
			hname += s.cls.module.name+"::";
		hname += s.name;
		hname += "()";

		field.value = hname;
		if(s.hook.arguments.length != 0)
			openHookEditor(field);
		else
			field.emitConfirmed();
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
		if(event.type == GUI_Confirmed && event.caller is hookList && hookList.selected >= 0) {
			confirm();
			close();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

void openHookList(HookField@ field) {
	HookList hl(field);
	addDialog(hl);
	setGuiFocus(hl.hookList);
}

void openHookList(HookField@ field, bool isStatic) {
	HookList hl(field);
	if(isStatic)
		hl.confirmed = true;
	addDialog(hl);
	setGuiFocus(hl.hookList);
}

void openHookEditor(HookField@ field) {
	if(field.type is null)
		return;
	HookEditor ed(field);
	addDialog(ed);
	ed.focus();
}
