#priority init -200
import tabs.Tab;
import tabs.tabbar;
import editor.loader;
import editor.defs;
import editor.fields;
import editor.files;
import dialogs.InputDialog;
import dialogs.QuestionDialog;
import editor.hooks;
import Tab@ createResearchEditor(const string& fname, const string& ident) from "tabs.ResearchTab";

class FieldInfo {
	LineDesc@ line;
	FieldDef@ def;
	Field@ elem;
	bool hasOriginal = false;
	string originalValue;
};

Field@ makeField(FieldDef@ def, IGuiElement@ parent, const recti& pos) {
	auto@ fld = makeField(def.type, parent, pos);
	if(def.options !is null) {
		for(uint i = 0, cnt = def.options.length; i < cnt; ++i)
			fld.addOption(def.options[i]);
	}
	return fld;
}

class BlockEditor : BaseGuiElement, QuestionDialogCallback {
	FileDesc@ file;
	BlockDef@ blockType;
	LineDesc@ headLine;
	string fname;

	array<FieldInfo@> fields;
	array<FieldInfo@> hooks;
	array<BlockEditor@> blocks;
	array<LineDesc@> extraLines;

	GuiButton@ addHookButton;
	array<GuiButton@> addBlockButtons;
	array<GuiButton@> addFieldButtons;
	array<FieldDef@> addFields;

	bool expanded = true;
	bool changed = false;

	GuiButton@ label;
	GuiTextbox@ text;
	GuiButton@ removeButton;
	GuiButton@ editButton;

	BlockEditor(IGuiElement@ elem) {
		super(elem, recti());

		@label = GuiButton(this, Alignment(Left+12, Top, Left+400, Top+44));
		label.font = FT_Medium;
		label.horizAlign = 0.0;
		label.style = SS_IconButton;
		label.buttonIcon = icons::Minus;
		@text = GuiTextbox(this, Alignment(Left+400, Top, Right-40, Top+44));
		text.font = FT_Medium;
		text.style = SS_HoverTextbox;
		text.emptyText = "Enter identifier name for element...";
		text.tabIndex = -1;
		@removeButton = GuiButton(this, Alignment(Right-40, Top+4, Right-4, Top+40));
		removeButton.color = colors::Red;
		setMarkupTooltip(removeButton, "Remove this block and its associated element from the file.");
		removeButton.setIcon(icons::Remove);
		StrictBounds = true;
	}

	void parse(const string& filename, FileDef@ def) {
		@file = FileDesc(filename);
		fname = filename;
		parseBlock(file, file.lines, -1, def.defaultBlock);
	}

	void fillTargets(Field@ sourceField, TargetChooser@ fld, bool selected = false) {
		if(!selected) {
			for(uint i = 0, cnt = blocks.length; i < cnt; ++i) {
				if(blocks[i].hasField(sourceField)) {
					blocks[i].fillTargets(sourceField, fld, true);
					return;
				}
			}
			return;
		}

		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			auto@ tf = cast<TargetField>(fields[i].elem);
			if(tf !is null) {
				auto type = TargetType(tf.type.selected);
				if(fld.targType == TT_Any || type == fld.targType)
					fld.addOption(tf.box.text, tf.box.text+" ("+TARGET_TYPE_NAMES[type]+")");
			}
		}
	}

	bool hasField(Field@ fld, bool recurse = true) {
		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			if(fields[i].elem is fld)
				return true;
		}
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].elem is fld)
				return true;
		}
		if(recurse) {
			for(uint i = 0, cnt = blocks.length; i < cnt; ++i) {
				if(blocks[i].hasField(fld))
					return true;
			}
		}
		return false;
	}

	void clear() {
		for(uint i = 0, cnt = fields.length; i < cnt; ++i)
			fields[i].elem.remove();
		fields.length = 0;
		for(uint i = 0, cnt = blocks.length; i < cnt; ++i)
			blocks[i].remove();
		blocks.length = 0;
		for(uint i = 0, cnt = addBlockButtons.length; i < cnt; ++i)
			addBlockButtons[i].remove();
		addBlockButtons.length = 0;
		for(uint i = 0, cnt = addFieldButtons.length; i < cnt; ++i)
			addFieldButtons[i].remove();
		addFieldButtons.length = 0;
		addFields.length = 0;
		extraLines.length = 0;
	}

	void insertLine(LineDesc@ line, int priority = 0) {
		//Find the right place to insert this line
		int pos = -1;
		if(pos == -1 && headLine !is null)
			pos = file.lines.find(headLine)+1;

		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			if(fields[i].line !is null && fields[i].def.fieldPriority <= priority)
				pos = max(pos, file.lines.find(fields[i].line)+1);
		}

		if(!line.isKey) {
			for(uint i = 0, cnt = extraLines.length; i < cnt; ++i)
				pos = max(pos, file.lines.find(extraLines[i])+1);
		}

		if(pos < 0 || pos > int(file.lines.length))
			file.lines.insertLast(line);
		else
			file.lines.insertAt(pos, line);
	}

	void checkDuplicates() {
		if(blockType is null || !blockType.hasIdentifier)
			return;
		bool dup = false;
		if(blockType.duplicateCheck !is null) {
			uint count = 0;
			string ident = text.text;
			for(uint i = 0, cnt = blockType.duplicateCheck.length; i < cnt; ++i) {
				if(blockType.duplicateCheck[i].ident == ident)
					count += 1;
			}
			if(count > 1)
				dup = true;
		}

		if(dup) {
			text.bgColor = colors::Red;
			text.textColor = colors::Red;
			setMarkupTooltip(text, "Duplicate identifier, '"+text.text+"' is already in use.");
		}
		else {
			text.bgColor = colors::White;
			text.textColor = colors::White;
			setMarkupTooltip(text, "");
		}
	}

	void setExpanded(bool value) {
		if(value == expanded)
			return;
		expanded = value;
		for(uint i = 0, cnt = fields.length; i < cnt; ++i)
			fields[i].elem.visible = expanded;
		for(uint i = 0, cnt = blocks.length; i < cnt; ++i)
			blocks[i].visible = expanded;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].elem.visible = expanded;
		updateAbsolutePosition();
		label.buttonIcon = (expanded ? icons::Minus : icons::Plus);
		if(addHookButton !is null)
			addHookButton.visible = expanded;
		if(editButton !is null)
			editButton.visible = expanded;
		for(uint i = 0, cnt = addBlockButtons.length; i < cnt; ++i)
			addBlockButtons[i].visible = expanded;
		for(uint i = 0, cnt = addFieldButtons.length; i < cnt; ++i)
			addFieldButtons[i].visible = expanded;
		emitChanged();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is removeButton) {
				question("Are you sure you want to delete this entire block of fields? This cannot be undone.", this);
				return true;
			}
			else if(evt.caller is addHookButton) {
				addHook();
				setExpanded(true);
				return true;
			}
			else if(evt.caller is editButton) {
				if(blockType.editMode == "research_grid") {
					auto@ tab = createResearchEditor(getBasename(fname), text.text);
					newTab(tab);
					switchToTab(tab);
				}
				return true;
			}
			else if(evt.caller is label) {
				setExpanded(!expanded);
				return true;
			}
			else if(cast<HookField>(evt.caller.parent) !is null) {
				auto@ hf = cast<HookField>(evt.caller.parent);
				if(evt.caller is hf.resetButton) {
					removeHook(hf);
					return true;
				}
			}
			else {
				for(uint i = 0, cnt = addBlockButtons.length; i < cnt; ++i) {
					if(evt.caller is addBlockButtons[i]) {
						addBlock(blockType.blocks[i]);
						setExpanded(true);
						return true;
					}
				}
				for(uint i = 0, cnt = addFieldButtons.length; i < cnt; ++i) {
					if(evt.caller is addFieldButtons[i]) {
						addField(addFields[i]);
						setExpanded(true);
						return true;
					}
				}
			}
		}
		if(evt.caller is text) {
			if(evt.type == GUI_Changed) {
				changed = true;
				checkDuplicates();
				return true;
			}
			if(evt.type == GUI_Focus_Lost) {
				if(changed) {
					emitConfirmed();
					checkDuplicates();
					changed = false;
					return true;
				}
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void addHook() {
		LineDesc line;
		line.line = "";
		line.isKey = false;
		insertLine(line);

		HookField fld(this, recti());
		fld.hookType = blockType.hookType;
		fld.hookModule = blockType.hookModule;
		fld.visible = expanded;

		FieldInfo inf;
		@inf.line = line;
		@inf.elem = fld;

		hooks.insertLast(inf);

		emitConfirmed();
		openHookList(fld);
	}

	void removeHook(HookField@ fld) {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			auto@ hook = hooks[i];
			if(fld is hook.elem) {
				if(hook.line !is null)
					file.lines.remove(hook.line);
				hook.elem.remove();
				hooks.removeAt(i);
				emitConfirmed();
				return;
			}
		}
	}

	void addField(FieldDef@ fDef) {
		FieldInfo inf;
		@inf.line = null;
		@inf.elem = makeField(fDef, this, recti());
		@inf.def = fDef;
		inf.elem.set(fDef.key, fDef.doc, fDef.defaultValue, fDef.icon);
		inf.elem.value = fDef.defaultValue;
		inf.elem.tabIndex = fields.length * 10;
		inf.elem.visible = expanded;

		fields.insertLast(inf);
		emitConfirmed();
		inf.elem.focus();
	}

	void addBlock(BlockDef@ type) {
		BlockEditor@ blk = BlockEditor(cast<IGuiElement>(this));
		blk.setType(type);

		@blk.file = file;
		@blk.headLine = LineDesc();
		if(headLine !is null)
			blk.headLine.indent = headLine.indent+1;
		blk.headLine.key = type.key;
		blk.headLine.isKey = true;
		blk.visible = expanded;
		blk.fname = fname;
		blk.setExpanded(true);
		insertLine(blk.headLine);

		for(uint i = 0, cnt = type.fields.length; i < cnt; ++i) {
			auto@ fDef = type.fields[i];
			if(fDef.repeatable)
				continue;
			FieldInfo inf;
			@inf.line = null;
			@inf.elem = makeField(fDef, blk, recti());
			@inf.def = fDef;
			inf.elem.set(fDef.key, fDef.doc, fDef.defaultValue, fDef.icon);
			inf.elem.value = fDef.defaultValue;
			inf.elem.tabIndex = blk.fields.length * 10;
			inf.elem.visible = blk.expanded;

			blk.fields.insertLast(inf);
		}

		blocks.insertLast(blk);

		emitConfirmed();
		blk.text.focus();
	}

	void removeBlock() {
		auto@ upper = cast<BlockEditor>(parent);
		if(upper !is null)
			upper.removeBlock(this);
		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			if(fields[i].line !is null)
				file.lines.remove(fields[i].line);
		}
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].line !is null)
				file.lines.remove(hooks[i].line);
		}
		for(uint i = 0, cnt = extraLines.length; i < cnt; ++i) {
			file.lines.remove(extraLines[i]);
		}
		for(uint i = 0, cnt = blocks.length; i < cnt; ++i) {
			blocks[i].removeBlock();
			--i; --cnt;
		}
		if(headLine !is null)
			file.lines.remove(headLine);
		remove();
		emitConfirmed();
	}

	void removeBlock(BlockEditor@ blk) {
		blocks.remove(blk);
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			auto@ p = cast<BaseGuiElement>(parent);
			removeBlock();
			p.emitConfirmed();
		}
	}

	void commit() {
		int indent = 0;
		if(headLine !is null) {
			indent = headLine.indent;
			headLine.value = text.text;
		}

		for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
			auto@ inf = fields[i];
			string value = inf.elem.value;
			if(value != inf.def.defaultValue || (inf.hasOriginal && value == inf.originalValue)) {
				bool newLine = false;
				if(inf.line is null) {
					//Create a new line for the field
					@inf.line = LineDesc();
					newLine = true;
				}

				inf.line.indent = indent+1;
				inf.line.isEmpty = false;

				if(inf.def.fullLine) {
					inf.line.isKey = false;
					inf.line.line = value;
				}
				else {
					inf.line.isKey = true;
					inf.line.key = inf.def.key;
					inf.line.value = value;
				}

				if(newLine)
					insertLine(inf.line, inf.def.fieldPriority);
			}
			else {
				if(inf.line !is null) {
					file.lines.remove(inf.line);
					@inf.line = null;
				}
			}
		}
		for(uint i = 0, cnt = blocks.length; i < cnt; ++i)
			blocks[i].commit();
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			auto@ inf = hooks[i];
			if(inf.line !is null) {
				inf.line.isKey = false;
				inf.line.isEmpty = false;
				if(blockType !is null && blockType.hookPrefix.length != 0)
					inf.line.line = blockType.hookPrefix+inf.elem.value;
				else
					inf.line.line = inf.elem.value;
				inf.line.indent = indent+1;
			}
		}
	}

	void setType(BlockDef@ def) {
		@blockType = def;
		label.visible = blockType.key.length != 0;
		removeButton.visible = label.visible;
		text.visible = label.visible && blockType.hasIdentifier;
		label.text = blockType.key+":";
		setMarkupTooltip(label, blockType.doc);

		if(blockType.identifierLimit)
			text.setIdentifierLimit();
		else
			text.characterLimit.clear();

		if(blockType.hookType.length != 0) {
			@addHookButton = GuiButton(this, recti(), "Add Hook");
			addHookButton.visible = expanded;
		}
		if(blockType.editMode.length != 0) {
			@editButton = GuiButton(this, recti(), "Edit");
			editButton.color = Color(0x80ff80ff);
			editButton.font = FT_Bold;
			editButton.visible = expanded;
		}
		for(uint i = 0, cnt = blockType.blocks.length; i < cnt; ++i) {
			GuiButton btn(this, recti());
			btn.text = "Add "+blockType.blocks[i].key;
			btn.visible = expanded;
			setMarkupTooltip(btn, blockType.blocks[i].doc);
			addBlockButtons.insertLast(btn);
		}
		for(uint i = 0, cnt = blockType.fields.length; i < cnt; ++i) {
			auto@ fDef = blockType.fields[i];
			if(!fDef.repeatable)
				continue;
			GuiButton btn(this, recti());
			btn.text = "Add "+fDef.key;
			btn.visible = expanded;
			setMarkupTooltip(btn, fDef.doc);
			addFieldButtons.insertLast(btn);
			addFields.insertLast(fDef);
		}
	}

	uint parseBlock(FileDesc@ file, array<LineDesc@>& lines, int pos, BlockDef@ def) {
		clear();
		@this.file = file;
		setType(def);

		int indent = -1;
		if(pos >= 0) {
			@headLine = lines[pos];
			indent = headLine.indent;
			text.text = headLine.value;
		}
		else {
			@headLine = null;
			text.text = "";
		}

		array<bool> haveFields(def.fields.length, false);
		pos += 1;
		for(int cnt = int(lines.length); pos < cnt; ++pos) {
			auto@ line = lines[pos];
			if(line.isEmpty) {
				extraLines.insertLast(line);
				continue;
			}
			if(int(line.indent) <= indent) {
				pos -= 1;
				break;
			}

			//Check if the line is associated with a field
			auto@ fDef = def.getField(line.key);
			if(fDef is null)
				@fDef = def.getField(line);
			if(fDef !is null) {
				FieldInfo inf;
				@inf.line = line;
				@inf.elem = makeField(fDef, this, recti());
				@inf.def = fDef;
				inf.elem.set(fDef.key, fDef.doc, fDef.defaultValue, fDef.icon);
				inf.elem.value = fDef.fullLine ? line.line : line.value;
				inf.elem.tabIndex = fields.length * 10;
				inf.elem.visible = expanded;
				inf.hasOriginal = true;
				inf.originalValue = inf.elem.value;

				fields.insertLast(inf);
				haveFields[fDef.index] = true;
				continue;
			}

			//Check if the line is associated with a block
			auto@ blockDef = def.getBlock(line.key);
			if(blockDef !is null) {
				BlockEditor@ blk = BlockEditor(cast<IGuiElement>(this)); //What the shit angelscript?
				pos = blk.parseBlock(file, lines, pos, blockDef);
				blk.visible = expanded;
				blk.fname = fname;
				blk.setExpanded(!blockDef.closeDefault);
				blocks.insertLast(blk);
				continue;
			}

			//Find hooks
			if(def.hookType.length != 0) {
				string str = line.line;
				if(line.isKey)
					str = line.key+":"+line.value;
				if(def.hookPrefix.length != 0 && str.trimmed().startswith_nocase(def.hookPrefix.trimmed()))
					str = str.trimmed().substr(def.hookPrefix.trimmed().length).trimmed();

				if(str.findFirst("(") != -1) {
					line.line = str;
					line.isKey = false;

					HookField fld(this, recti());
					fld.hookType = def.hookType;
					fld.hookModule = def.hookModule;
					fld.value = str;
					fld.visible = expanded;

					FieldInfo inf;
					@inf.line = line;
					@inf.elem = fld;

					hooks.insertLast(inf);
					continue;
				}
			}

			//Remember the line as spurious for this block
			extraLines.insertLast(line);
		}

		for(uint i = 0, cnt = haveFields.length; i < cnt; ++i) {
			if(haveFields[i])
				continue;
			auto@ fDef = def.fields[i];
			if(fDef.repeatable)
				continue;
			FieldInfo inf;
			@inf.line = null;
			@inf.elem = makeField(fDef, this, recti());
			@inf.def = fDef;
			inf.elem.set(fDef.key, fDef.doc, fDef.defaultValue, fDef.icon);
			inf.elem.value = fDef.defaultValue;
			inf.elem.tabIndex = fields.length * 10;
			inf.elem.visible = expanded;

			fields.insertLast(inf);
		}

		checkDuplicates();
		return pos;
	}

	uint get_needHeight() {
		int h = text !is null && label.visible ? 44 : 0;
		if(expanded) {
			for(uint i = 0, cnt = fields.length; i < cnt; ++i)
				h += fields[i].elem.needHeight;
			for(uint i = 0, cnt = blocks.length; i < cnt; ++i)
				h += blocks[i].needHeight;
			for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
				h += hooks[i].elem.needHeight;
			if(btnCount != 0)
				h += 44 * (btnCount/6+1);
		}
		return h;
	}

	uint get_btnCount() {
		uint cnt = 0;
		if(addHookButton !is null)
			cnt += 1;
		if(editButton !is null)
			cnt += 1;
		cnt += addBlockButtons.length;
		cnt += addFieldButtons.length;
		return cnt;
	}

	void updateAbsolutePosition() {
		int blockOff = 0;
		if(cast<BlockEditor>(parent) is null) {
			size = vec2i(parent.size.width-20, needHeight);
			blockOff = -30;
		}

		int y = text !is null && label.visible ? 44 : 0;
		if(expanded) {
			for(uint i = 0, cnt = fields.length; i < cnt; ++i) {
				auto@ fld = fields[i].elem;
				int h = fld.needHeight;
				fld.size = vec2i(size.width, h);
				fld.position = vec2i(0, y);
				y += h;
			}

			for(uint i = 0, cnt = blocks.length; i < cnt; ++i) {
				auto@ blk = blocks[i];
				int h = blk.needHeight;
				blk.size = vec2i(size.width-blockOff-30, h);
				blk.position = vec2i(blockOff+30, y);
				y += h;
			}

			for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
				auto@ fld = hooks[i].elem;
				int h = fld.needHeight;
				fld.size = vec2i(size.width, h);
				fld.position = vec2i(0, y);
				y += h;
			}

			if(btnCount != 0) {
				int btnWidth = min(220, size.width/min(btnCount,6));
				int btnOff = (size.width-(min(btnCount,6) * btnWidth)) / 2;
				int btnOrig = btnOff;
				uint n = 0;
				if(editButton !is null) {
					editButton.size = vec2i(btnWidth, 36);
					editButton.position = vec2i(btnOff, y+4);
					n += 1;
					y += 44;
					btnOff = btnOrig;
				}
				if(addHookButton !is null) {
					addHookButton.size = vec2i(btnWidth, 36);
					addHookButton.position = vec2i(btnOff, y+4);
					btnOff += btnWidth + 8;
					n += 1;
					if(n % 6 == 0) { btnOff = btnOrig; y += 44; }
				}
				for(uint i = 0, cnt = addFieldButtons.length; i < cnt; ++i) {
					addFieldButtons[i].size = vec2i(btnWidth, 36);
					addFieldButtons[i].position = vec2i(btnOff, y+4);
					btnOff += btnWidth + 8;
					n += 1;
					if(n % 6 == 0) { btnOff = btnOrig; y += 44; }
				}
				for(uint i = 0, cnt = addBlockButtons.length; i < cnt; ++i) {
					addBlockButtons[i].size = vec2i(btnWidth, 36);
					addBlockButtons[i].position = vec2i(btnOff, y+4);
					btnOff += btnWidth + 8;
					n += 1;
					if(n % 6 == 0) { btnOff = btnOrig; y += 44; }
				}
			}
		}

		if(Parent !is null) {
			if(Alignment !is null) {
				Position = Alignment.resolve(Parent.updatePosition.size);
				ClipRect = recti(vec2i(), Position.size);
			}

			AbsolutePosition = Position + Parent.updatePosition.topLeft;
			AbsoluteClipRect = (ClipRect + AbsolutePosition.topLeft).clipAgainst(Parent.absoluteClipRect);
		}
		else {
			if(Alignment !is null) {
				Position = Alignment.resolve(screenSize);
				ClipRect = recti(vec2i(), Position.size);
			}

			AbsolutePosition = Position;
			AbsoluteClipRect = ClipRect + Position.topLeft;
		}

		if(noClip)
			AbsoluteClipRect = AbsolutePosition;
		
		if(expanded) {
			uint cCnt = Children.length();
			for(uint i = 0; i != cCnt; ++i)
				Children[i].updateAbsolutePosition();
		}
		else if(removeButton !is null) {
			label.updateAbsolutePosition();
			text.updateAbsolutePosition();
			removeButton.updateAbsolutePosition();
		}
	}

	void draw() {
		if(text !is null && label.visible)
			skin.draw(SS_HorizBar, SF_Normal, recti_area(AbsolutePosition.topLeft, vec2i(size.width, 44)));
		if(btnCount != 0 && expanded) {
			int bH = (btnCount/6+1)*44;
			skin.draw(SS_PlainBox, SF_Normal, recti_area(vec2i(AbsolutePosition.topLeft.x, AbsolutePosition.botRight.y-bH), vec2i(size.width, bH)));
		}
		BaseGuiElement::draw();
	}
};

class EditorTab : Tab, IInputDialogCallback, QuestionDialogCallback {
	GuiPanel@ editPanel;
	BlockEditor@ editor;
	FileDesc baseFile;

	GuiPanel@ filePanel;
	FileFolder@ files;

	GuiButton@ newFile;
	GuiButton@ deleteFile;
	GuiButton@ duplicateFile;

	string folder;
	string loadedFile;
	FileDef@ type;
	bool duplicate = false;

	EditorTab(const string& folder, FileDef@ type) {
		this.folder = folder;
		@this.type = type;
		super();
		title = folder;
		initCompletions();

		int y = 12;
		if(type.defaultBlock.doc.length != 0) {
			GuiMarkupText txt(this, recti_area(312,12,900,100));
			txt.text = type.defaultBlock.doc;
			txt.updateAbsolutePosition();
			y += txt.size.height+8;
		}

		@editPanel = GuiPanel(this, Alignment(Left+300, Top+y, Right, Bottom));

		@filePanel = GuiPanel(this, Alignment(Left, Top, Left+300, Bottom-36));
		@files = FileFolder(filePanel, recti());
		files.load(folder, extension=".txt");

		@newFile = GuiButton(this, Alignment(Left, Bottom-36, Left+100, Bottom), "New");
		newFile.setIcon(icons::Create);
		newFile.color = colors::Green;

		@duplicateFile = GuiButton(this, Alignment(Left+100, Bottom-36, Left+200, Bottom), "Duplicate");
		duplicateFile.setIcon(icons::Export);
		duplicateFile.disabled = true;
		duplicateFile.color = Color(0x0080ffff);

		@deleteFile = GuiButton(this, Alignment(Left+200, Bottom-36, Left+300, Bottom), "Delete");
		deleteFile.setIcon(icons::Delete);
		deleteFile.color = colors::Red;
		deleteFile.disabled = true;

		updateAbsolutePosition();
	}

	Color get_activeColor() {
		return Color(0xd482ffff);
	}

	Color get_inactiveColor() {
		return Color(0xa800ffff);
	}

	Color get_seperatorColor() {
		return Color(0x75488dff);
	}	

	Sprite get_icon() {
		return icons::Paint;
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

	void checkEmptyDirectory(const string& path) {
		string dir = path;
		while(path_inside(topMod.abspath, dir) && topMod.abspath != dir) {
			if(isDirectory(dir)) {
				FileList list(dir, "*", false, false);
				if(list.length != 0)
					break;
				::deleteFile(dir);
			}
			dir = path_up(dir);
		}
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			loadedFile = path_join(folder, dialog.getTextInput(0));
			if(!loadedFile.endswith(".txt"))
				loadedFile += ".txt";
			title = getBasename(loadedFile);

			{
				string path = path_join(topMod.abspath, loadedFile);
				ensureFile(path);
				if(duplicate) {
					for(uint i = 0, cnt = editor.blocks.length; i < cnt; ++i) {
						if(editor.blocks[i].text.text.length != 0)
							editor.blocks[i].text.text = "DUPLICATE_"+editor.blocks[i].text.text;
					}
					editor.commit();
					editor.file.save(path);
				}
				else {
					WriteFile file(path);
				}
			}

			files.load(folder, extension=".txt");
			files.select(loadedFile);
		}
	}
	void changeCallback(InputDialog@ dialog) {}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			string path = path_join(topMod.abspath, loadedFile);
			if(fileExists(path)) {
				::deleteFile(path);
				checkEmptyDirectory(path);
			}
			deleteFile.disabled = true;
			duplicateFile.disabled = true;
			if(editor !is null) {
				editor.remove();
				@editor = null;
			}
			type.onChange();
			files.load(folder, extension=".txt");
		}
	}

	void updateRevertButton() {
		deleteFile.disabled = loadedFile.length == 0 || !fileExists(path_join(topMod.abspath, loadedFile));
		if(currentMod !is topMod && fileExists(path_join(currentMod.abspath, loadedFile))) {
			deleteFile.text = "Revert";
			deleteFile.color = Color(0xff8000ff);
			setMarkupTooltip(deleteFile, "Revert the selected file back to the version from the base game.");
		}
		else {
			deleteFile.text = "Delete";
			deleteFile.color = Color(0xff8000ff);
			setMarkupTooltip(deleteFile, "Delete this file completely from the game.");
		}
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Confirmed) {
			if(evt.caller is files) {
				setGuiFocus(this);
				loadedFile = files.getSelection().basePath;
				title = getBasename(loadedFile);
				if(editor !is null)
					editor.remove();
				@editor = BlockEditor(editPanel);
				editor.parse(resolve(loadedFile), type);
				baseFile.load(path_join(currentMod.abspath, loadedFile));
				editPanel.updateAbsolutePosition();
				duplicateFile.disabled = false;
				updateRevertButton();
			}
			else if(editor !is null) {
				editor.commit();
				string path = path_join(topMod.abspath, loadedFile);
				bool existed = fileExists(path);
				if(baseFile.exists && topMod !is baseMod && baseFile == editor.file) {
					if(existed) {
						::deleteFile(path);
						checkEmptyDirectory(path);
						existed = false;
					}
				}
				else {
					ensureFile(path);
					editor.file.save(path);
				}
				type.onChange();
				editPanel.updateAbsolutePosition();
				if(!existed) {
					files.load(folder, extension=".txt");
					files.select(loadedFile, bubble=false);
				}
				updateRevertButton();
			}
		}
		if(evt.type == GUI_Changed && cast<BlockEditor>(evt.caller) !is null) {
			editPanel.updateAbsolutePosition();
			return true;
		}
		if(evt.type == GUI_Clicked) {
			if(evt.caller is newFile) {
				string defname;
				auto@ sel = files.getSelection();
				if(sel !is null) {
					defname = path_up(sel.basePath.substr(folder.length+1));
					if(defname.length != 0)
						defname = path_join(defname, "");
				}

				duplicate = false;
				InputDialog@ dialog = InputDialog(this, this);
				dialog.addTitle("Create File");
				dialog.accept.text = "Create";
				dialog.addTextInput("Filename", defname);

				addDialog(dialog);
				dialog.focusInput();
				return true;
			}
			else if(evt.caller is duplicateFile) {
				string defname;
				auto@ sel = files.getSelection();
				if(sel !is null) {
					defname = path_up(sel.basePath.substr(folder.length+1));
					if(defname.length != 0)
						defname = path_join(defname, "");
				}

				duplicate = true;
				InputDialog@ dialog = InputDialog(this, this);
				dialog.addTitle("Duplicate File");
				dialog.accept.text = "Duplicate";
				dialog.addTextInput("Filename", defname);

				addDialog(dialog);
				dialog.focusInput();
				return true;
			}
			else if(evt.caller is deleteFile) {
				question("Are you sure you wish to delete "+loadedFile+" from the mod? This cannot be undone.\n\nIf the file consisted of changes to a base mod file, deleting the file from your mod will revert the changes back to the original version.", this);
				return true;
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createEditorTab(const string& folder, FileDef@ type) {
	return EditorTab(folder, type);
}

Tab@ createEditorTab(const string& file) {
	string folder;
	FileDef@ type;
	for(uint i = 0, cnt = fileFolders.length; i < cnt; ++i) {
		if(path_inside(fileFolders[i], file)) {
			folder = fileFolders[i];
			@type = cast<FileDef>(getClass(fileTypes[i]).create());
			break;
		}
	}
	if(type is null)
		return null;
	EditorTab tab(folder, type);
	tab.files.select(file);
	return tab;
}

array<string> fileClasses = {"statuses",      "abilities",      "anomalies",      "artifacts",      "influence",      "research",      "resources",      "buildings",      "biomes",      "creeps",      "orbitals",      "traits",      "subsystems",      "effectors",      "materials",      "sounds",      "constructions",      "random_events",      "cargo",      "attitudes"};
array<string> fileFolders = {"data/statuses", "data/abilities", "data/anomalies", "data/artifacts", "data/influence", "data/research", "data/resources", "data/buildings", "data/biomes", "data/creeps", "data/orbitals", "data/traits", "data/subsystems", "data/effectors", "data/materials", "data/sounds", "data/constructions", "data/random_events", "data/cargo", "data/attitudes"};
array<string> fileTypes   = {"StatusFile",    "AbilityFile",    "AnomalyFile",    "ArtifactFile",   "InfluenceFile",  "ResearchFile",  "ResourceFile",   "BuildingFile",   "BiomeFile",   "CreepFile",   "OrbitalFile",   "TraitFile",   "SubsystemFile",   "EffectorFile",   "MaterialFile",   "SoundFile",   "ConstructionFile",   "EventFile",          "CargoFile",  "AttitudeFile"};

class ModEditorCommand : ConsoleCommand {
	void execute(const string& args) {
		int found = -1;
		string check = args.trimmed();
		for(uint i = 0, cnt = fileClasses.length; i < cnt; ++i) {
			if(fileClasses[i].equals_nocase(check)) {
				found = int(i);
				break;
			}
		}

		if(found == -1) {
			print("Usage: mod_editor <class>\nSpecify one of the following classes of data files to edit:\n");
			for(uint i = 0, cnt = fileClasses.length; i < cnt; ++i) {
				print("   "+fileClasses[i]);
			}
			return;
		}

		auto@ tab = createEditorTab(fileFolders[found], cast<FileDef>(getClass(fileTypes[found]).create()));
		newTab(tab);
		switchToTab(tab);
	}
};

bool canEditFile(const string& basePath) {
	if(!basePath.endswith(".txt"))
		return false;
	for(uint i = 0, cnt = fileFolders.length; i < cnt; ++i) {
		if(path_inside(fileFolders[i], basePath)) {
			return true;
		}
	}
	return false;
}

string getLocaleFile(IGuiElement@ elem) {
	for(uint i = 0, cnt = tabCount; i < cnt; ++i) {
		auto@ tab = cast<EditorTab>(tabs[i]);
		if(tab !is null) {
			if(elem.isChildOf(tab)) {
				return tab.type.localeFile;
			}
		}

	}
	auto@ tab = cast<EditorTab>(ActiveTab);
	if(tab !is null)
		return tab.type.localeFile;
	return "misc.txt";
}

void init() {
	addConsoleCommand("mod_editor", ModEditorCommand());

	/*auto@ tab = createEditorTab("data/subsystems", SubsystemFile());*/
	/*newTab(tab);*/
	/*switchToTab(tab);*/
}

void fillTargetsFromTab(Field@ sourceField, TargetChooser@ fld) {
	auto@ tab = cast<EditorTab>(ActiveTab);
	if(tab !is null) {
		if(tab.editor !is null)
			tab.editor.fillTargets(sourceField, fld);
	}
}
