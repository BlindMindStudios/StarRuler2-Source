import tabs.Tab;
import elements.GuiSkinElement;
import elements.GuiListbox;
import elements.GuiText;
import elements.GuiPanel;

from tabs.tabbar import newTab, switchToTab;

Tab@ createSkinViewerTab() {
	return SkinViewer();
}

class SkinViewerCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = createSkinViewerTab();
		newTab(editor);
		switchToTab(editor);
	}
};

void init() {
	addConsoleCommand("skin_viewer", SkinViewerCommand());
}

class SkinViewer : Tab {
	dictionary skinStyles;
	GuiListbox@ styles;
	GuiPanel@ leftPanel;
	
	SkinStyle selStyle;
	uint eleCnt;
	array<GuiText@> skinHeaders;
	array<GuiSkinElement@> skinExamples;

	void draw() {
		//Draw the background
		skin.draw(SS_DesignOverviewBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
	
	SkinViewer() {
		super();
		title = "Skin Viewer";

		@leftPanel = GuiPanel(this, Alignment(Left, Top, Right-0.25f, Bottom));
		
		@styles = GuiListbox(this, Alignment(Right-0.25f, Top+0+4, Right-0-4, Bottom-0-4));
		styles.required = true;

		updateStyles();
		updateAbsolutePosition();
		showSelectedStyle();
	}

	void updateStyles() {
		getSkinStyles(skinStyles);
		styles.clearItems();
		dictionary_iterator style = skinStyles.iterator();
		string name; int64 value;
		while(style.iterate(name, value))
			styles.addItem(name);
	}

	void addSkinExample(SkinStyle style, uint flags, Alignment@ alignment) {
		GuiSkinElement@ example = GuiSkinElement(leftPanel, recti(), 0);
		@example.alignment = alignment;
		example.style = style;
		example.flags = flags;
		skinExamples.insertLast(example);
	}
	
	void showStyle(SkinStyle style) {
		//Remove old ones
		for(uint i = 0; i < skinExamples.length; ++i)
			skinExamples[i].remove();
		for(uint i = 0; i < skinHeaders.length; ++i)
			skinHeaders[i].remove();
		skinExamples.length = 0;
		skinHeaders.length = 0;
		selStyle = style;

		//Add new ones
		eleCnt = skin.getStyleElementCount(style);
		int y = 0;
		for(uint i = 0; i < eleCnt; ++i) {
			uint flags = skin.getStyleElementFlags(style, i);

			//Add header
			GuiText@ txt = GuiText(leftPanel, recti(), getElementFlagName(flags));
			@txt.alignment = Alignment(Left+4, Top+4 + y, Right-0.5f-4, Top+24 + y);
			skinHeaders.insertLast(txt);
			y += 32;

			//Add examples
			addSkinExample(style, flags, Alignment(Left+4, Top+4 + y, Right-0.5f-4, Top+250 + y));
			
			addSkinExample(style, flags, Alignment(Left+4, Top+254 + y, Left+0.0f+20, Top+270 + y));
			
			addSkinExample(style, flags, Alignment(Left+24, Top+254 + y, Left+0.0f+88, Top+318 + y));

			addSkinExample(style, flags, Alignment(Left+92, Top+254 + y, Left+0.0f+292, Top+276 + y));

			y += 326;
		}
	}

	void tick(double time) {
		if(skinStyles.getSize() != getSkinStyleCount())
			updateStyles();
		if(skin.getStyleElementCount(selStyle) != eleCnt)
			showStyle(selStyle);
	}

	void showSelectedStyle() {
		if(styles.selected >= 0) {
			int64 styleID;
			skinStyles.get(styles.getItem(styles.selected), styleID);
			showStyle(SkinStyle(styleID));
		}
	}
	
	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Changed) {
			if(event.caller is styles) {
				showSelectedStyle();
				return true;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}
}
