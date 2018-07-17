import elements.BaseGuiElement;
import elements.GuiText;
import elements.GuiSkinElement;
import elements.GuiButton;
import elements.GuiSprite;
import icons;

class FileFolder : BaseGuiElement {
	array<FileFolder@> folders;
	array<FileElement@> files;
	bool expanded = true;

	string fullPath;
	string basePath;
	string basename;

	GuiSkinElement@ heading;
	GuiButton@ btn;
	GuiSprite@ toggle;

	FileFolder(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);

		@heading = GuiSkinElement(this, Alignment(Left, Top, Right, Top+30), SS_PlainBox);
		@btn = GuiButton(heading, Alignment().fill());
		btn.style = SS_IconButton;
		btn.buttonIcon = spritesheet::FileIcons+2;
		btn.horizAlign = 0.0;
		btn.font = FT_Bold;
		@toggle = GuiSprite(btn, Alignment(Right-26, Top+4, Right-4, Top+26));
		toggle.desc = icons::Minus;
	}

	void reset() {
		for(uint i = 0, cnt = folders.length; i < cnt; ++i)
			folders[i].remove();
		folders.length = 0;
		for(uint i = 0, cnt = files.length; i < cnt; ++i)
			files[i].remove();
		files.length = 0;
	}

	void update() {
		if(expanded) {
			toggle.desc = icons::Minus;
		}
		else {
			toggle.desc = icons::Plus;
		}

		if(cast<FileFolder>(parent) !is null)
			cast<FileFolder>(parent).update();
		else
			updateAbsolutePosition();
	}

	void clearSelection(bool upwards = true) {
		if(upwards) {
			if(cast<FileFolder>(parent) !is null)
				cast<FileFolder>(parent).clearSelection();
			else
				clearSelection(false);
		}
		else {
			for(uint i = 0, cnt = folders.length; i < cnt; ++i)
				folders[i].clearSelection(false);
			for(uint i = 0, cnt = files.length; i < cnt; ++i)
				files[i].pressed = false;
		}
	}

	FileElement@ getSelection() {
		for(uint i = 0, cnt = files.length; i < cnt; ++i)
			if(files[i].pressed)
				return files[i];
		for(uint i = 0, cnt = folders.length; i < cnt; ++i) {
			auto@ sel = folders[i].getSelection();
			if(sel !is null)
				return sel;
		}
		return null;
	}

	FileElement@ getFile(const string& basePath) {
		for(uint i = 0, cnt = files.length; i < cnt; ++i) {
			if(files[i].basePath == basePath)
				return files[i];
		}
		for(uint i = 0, cnt = folders.length; i < cnt; ++i) {
			auto@ sel = folders[i].getFile(basePath);
			if(sel !is null)
				return sel;
		}
		return null;
	}

	void select(const string& basePath, bool bubble = true) {
		clearSelection();
		auto file = getFile(basePath);
		if(file !is null) {
			file.pressed = true;
			if(bubble)
				emitConfirmed();
		}
	}

	FileFolder@ getRoot() {
		if(cast<FileFolder>(parent) !is null)
			return cast<FileFolder>(parent).getRoot();
		else
			return this;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked && evt.caller is btn) {
			expanded = !expanded;
			update();
		}
		if(evt.type == GUI_Clicked) {
			auto@ file = cast<FileElement>(evt.caller);
			if(file !is null) {
				clearSelection();
				file.pressed = true;
				setGuiFocus(null);
				getRoot().emitConfirmed();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void load(const string& folder, const string& base = "", const string& extension = "", bool resolve = true) {
		reset();

		fullPath = folder;
		basePath = folder;
		if(base.length != 0)
			basePath = base;
		basename = getBasename(folder);
		btn.text = basename;
		heading.visible = false;

		FileList list(folder, "*", false, resolve);
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			if(list.isDirectory[i]) {
				FileFolder elem(this, recti());
				elem.load(path_join(fullPath, list.basename[i]), path_join(basePath, list.basename[i]), resolve=resolve, extension=extension);
				elem.heading.visible = true;
				
				if(elem.folders.length == 0 && elem.files.length == 0)
					elem.remove();
				else
					folders.insertLast(elem);
			}
			else {
				string basename = list.basename[i];
				if(extension.length != 0 && !basename.endswith(extension))
					continue;

				FileElement elem(this, recti());
				elem.fullPath = list.path[i];
				elem.basePath = path_join(basePath, basename);
				elem.basename = basename;
				elem.update();
				
				files.insertLast(elem);
			}
		}

		updateAbsolutePosition();
	}

	uint get_needHeight() {
		int h = heading !is null && heading.visible ? 30 : 0;
		if(!expanded)
			return h;
		for(uint i = 0, cnt = folders.length; i < cnt; ++i)
			h += folders[i].needHeight;
		for(uint i = 0, cnt = files.length; i < cnt; ++i)
			h += files[i].needHeight;
		return h;
	}

	void updateAbsolutePosition() {
		int fileOffset = 30;
		int folderOffset = 0;
		if(cast<FileFolder>(parent) is null) {
			size = vec2i(parent.size.width-20, needHeight);
			fileOffset = 0;
			folderOffset = -30;
		}

		int y = heading !is null && heading.visible ? 30 : 0;
		for(uint i = 0, cnt = folders.length; i < cnt; ++i) {
			auto@ elem = folders[i];
			int h = elem.needHeight;
			elem.size = vec2i(size.width-30-folderOffset, h);
			elem.position = vec2i(30+folderOffset, y);
			y += h;
		}

		for(uint i = 0, cnt = files.length; i < cnt; ++i) {
			auto@ elem = files[i];
			int h = elem.needHeight;
			elem.size = vec2i(size.width-fileOffset, h);
			elem.position = vec2i(fileOffset, y);
			y += h;
		}

		BaseGuiElement::updateAbsolutePosition();
	}

	void draw() {
		skin.draw(SS_Panel, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class FileElement : GuiButton {
	string fullPath;
	string basePath;
	string basename;

	FileElement(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);

		style = SS_ListboxItem;
		toggleButton = true;
		horizAlign = 0.0;
		buttonIcon = spritesheet::FileIcons+0;
	}

	uint get_needHeight() {
		return 30;
	}

	void update() {
		text = basename;

		bool existsInMod = fileExists(path_join(topMod.abspath, basePath));
		bool existsInParent = false;

		if(topMod.parent is null) {
			if(currentMod is topMod) {
				existsInParent = true;
			}
			else {
				existsInParent = fileExists(path_join(currentMod.abspath, basePath));
			}
		}
		else {
			existsInParent = fileExists(path_join(topMod.parent.abspath, basePath));
		}

		Color color;
		if(topMod is currentMod) {
			color = Color(0xffffffff);
		}
		else if(existsInMod) {
			if(existsInParent)
				color = Color(0xffff00ff);
			else
				color = Color(0x00ff00ff);
		}
		else {
			color = Color(0xaaaaaaff);
		}

		textColor = color;
		Icon.color = color;
	}
};
