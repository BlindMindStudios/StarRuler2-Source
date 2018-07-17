import tabs.Tab;
import elements.GuiPanel;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import elements.GuiBackgroundPanel;
import elements.GuiButton;
import elements.GuiTextbox;
import icons;

from tabs.tabbar import popTab, newTab, switchToTab, findTab, ActiveTab, browseTab;
import Tab@ createCommunityDesignPage(int id) from "community.DesignPage";

const string URI_HINT = "://";
void openGeneralLink(const string& link, int button = 0) {
	if(link.findFirst(URI_HINT) != -1) {
		if(button == 0)
			openBrowser(link);
	}
	else if(link.startswith_nocase("design:")) {
		int id = toInt(link.substr(7));
		if(button == 2)
			newTab(createCommunityDesignPage(id));
		else
			browseTab(ActiveTab, createCommunityDesignPage(id), true);
	}
	else {
		openWikiLink(link, button);
	}
}

void openWikiLink(const string& link, int button = 0) {
	if(button == 0) {
		auto@ t = cast<WikiTab>(ActiveTab);
		if(t !is null)
			t.load(link);
		else
			browseTab(ActiveTab, createWikiTab(link), true);
	}
	else if(button == 2) {
		Tab@ newtb = createWikiTab(link, true);
		newTab(ActiveTab, newtb);

		if(shiftKey)
			switchToTab(newtb);
	}
}

class LinkableMarkupText : GuiMarkupText {
	LinkableMarkupText(IGuiElement@ parent, const recti& pos, bool paragraphize = false) {
		super(parent, pos);
		this.paragraphize = paragraphize;
		@tooltipObject = MarkupTooltip(300, 0.f, true, true);
	}

	LinkableMarkupText(IGuiElement@ parent, Alignment@ align, bool paragraphize = false) {
		super(parent, align);
		this.paragraphize = paragraphize;
		@tooltipObject = MarkupTooltip(300, 0.f, true, true);
	}

	void onLinkClicked(const string& link, int button) override {
		openGeneralLink(link, button);
	}
};

class WikiTab : Tab {
	WebData wdata;
	bool loading = false;
	string loadPage;
	string anchor;
	string[] history;

	GuiBackgroundPanel@ bg;
	GuiPanel@ panel;
	LinkableMarkupText@ text;

	GuiButton@ backButton;
	GuiButton@ goButton;
	GuiButton@ homeButton;
	GuiTextbox@ navBox;

	WikiTab() {
		super();
		@backButton = GuiButton(this, Alignment(Left+8, Top+4, Left+108, Top+36), locale::WIKI_BACK);
		backButton.buttonIcon = icons::Back;

		@homeButton = GuiButton(this, Alignment(Left+112, Top+4, Left+212, Top+36), locale::WIKI_HOME);
		@navBox = GuiTextbox(this, Alignment(Left+216, Top+4, Right-186, Top+36));

		@goButton = GuiButton(this, Alignment(Right-182, Top+4, Right-8, Top+36), locale::WIKI_BROWSER);
		goButton.buttonIcon = icons::Go;

		@bg = GuiBackgroundPanel(this, Alignment(Left+8, Top+40, Right-8, Bottom-8));
		bg.titleColor = Color(0xff83bcff);
		bg.title = title;

		@panel = GuiPanel(bg, Alignment(Left+8, Top+30, Right-4, Bottom-4));
		panel.horizType = ST_Never;
		@text = LinkableMarkupText(panel, recti(0, 0, 100, 100), true);
		text.defaultColor = Color(0xccccccff);
		load("Main Page");
	}

	Color get_activeColor() {
		return Color(0xff83bcff);
	}

	Color get_inactiveColor() {
		return Color(0xff0077ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x8d4969ff);
	}		

	TabCategory get_category() {
		return TC_Wiki;
	}

	Sprite get_icon() {
		return Sprite(material::TabWiki);
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();
		if(text.size.width != panel.size.width-20) {
			text.size = vec2i(panel.size.width-20, text.size.height);
			text.updateAbsolutePosition();
		}
	}

	void show() {
		Tab::show();
		if(loadPage.length != 0) {
			load(loadPage);
			loadPage = "";
		}
	}

	void load(const string& page, bool record = true, bool loadNow = false) {
		string ptitle = page;
		ptitle[0] = uppercase(ptitle[0]);

		title = format(locale::WIKI_TITLE, ptitle);
		bg.title = ptitle;
		navBox.text = ptitle;

		if((!visible && !loadNow) || loading) {
			loadPage = page;
			return;
		}

		text.text = locale::WIKI_LOADING;
		panel.updateAbsolutePosition();

		if(record) {
			if(history.length == 0 || history[history.length-1] != page)
				history.insertLast(page);
		}

		string link = page;
		int aPos = page.findFirst("#");
		if(aPos != -1 && aPos < int(page.length)-1) {
			anchor = page.substr(aPos+1);
			link = page.substr(0, aPos);
		}
		else {
			anchor = "";
		}

		loading = true;
		getWikiPage(link, wdata);
	}

	void back() {
		if(history.length <= 1) {
			if(previous !is null)
				popTab(this);
			return;
		}

		load(history[history.length - 2], false);
		history.removeAt(history.length - 1);
	}

	void tick(double time) {
		if(!visible)
			return;

		backButton.disabled = history.length <= 1 && previous is null;
		if(loading) {
			if(wdata.completed) {
				if(wdata.error)
					text.text = locale::WIKI_404;
				else
					text.text = wdata.result;
				panel.updateAbsolutePosition();
				loading = false;

				if(anchor.length != 0) {
					int pos = text.getAnchor(anchor);
					if(pos != -1)
						panel.scrollToVert(pos);
				}
			}
		}
		else {
			if(loadPage.length != 0) {
				load(loadPage);
				loadPage = "";
			}
		}
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case KET_Key_Up:
					if(event.key == KEY_ESC) {
						if(previous !is null)
							popTab(this);
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Confirmed:
				if(event.caller is navBox) {
					load(navBox.text);
					return true;
				}
			break;
			case GUI_Clicked:
				if(event.caller is homeButton) {
					if(previous !is null && previous.category == TC_Wiki)
						popTab(this);
					else
						load("Main Page");
					return true;
				}
				else if(event.caller is backButton) {
					back();
					return true;
				}
				else if(event.caller is goButton) {
					openBrowser("http://wiki.starruler2.com/"+navBox.text);
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void draw() {
		skin.draw(SS_WikiBG, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

Tab@ createWikiTab() {
	return WikiTab();
}

Tab@ createWikiTab(const string& page, bool loadNow = false) {
	WikiTab@ tab = WikiTab();
	tab.load(page, true, loadNow);
	return tab;
}

void showWikiPage(const string& page, bool background = false) {
	if(background) {
		newTab(createWikiTab(page, true));
	}
	else {
		WikiTab@ tb = cast<WikiTab>(findTab(TC_Wiki));
		if(tb !is null) {
			tb.load(page);
			switchToTab(tb);
		}
		else {
			switchToTab(newTab(createWikiTab(page, true)));
		}
	}
}
