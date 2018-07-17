import tabs.tabbar;
import elements.GuiBlueprint;
import community.DesignElement;
import elements.GuiMarkupText;
import elements.GuiSkinElement;
import elements.GuiDropdown;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiButton;
import elements.GuiSprite;
import elements.GuiPanel;
import elements.GuiBackgroundPanel;
import elements.MarkupTooltip;
import dialogs.Dialog;
import util.formatting;
from tabs.WikiTab import LinkableMarkupText;
from community.DesignList import createCommunityDesignList;
from community.DesignPage import createCommunityDesignPage;
import icons;

class CommunityHome : Tab {
	WebData query;
	WebData wiki;
	string listSpec;

	BaseGuiElement@ container;

	GuiBackgroundPanel@ designBG;
	GuiPanel@ panel;
	array<DesignElement@> elements;

	GuiBackgroundPanel@ wikiBG;
	GuiPanel@ wikiPanel;
	LinkableMarkupText@ wikiText;

	GuiButton@ uploadButton;
	GuiButton@ recentDesigns;
	GuiButton@ topratedDesigns;
	GuiTextbox@ searchDesigns;
	GuiButton@ internetButton;

	bool loaded = true;
	bool loading = false;

	CommunityHome() {
		title = locale::COMMUNITY_HOME_TITLE;

		@container = BaseGuiElement(this, Alignment().fill());
		@internetButton = GuiButton(this, Alignment(Left+0.5f-200, Top+0.5f-30, Left+0.5f+200, Top+0.5f+30), locale::ENABLE_INTERNET);
		internetButton.visible = false;

		@designBG = GuiBackgroundPanel(container, Alignment(Left+29, Top+35, Left+35+600+48, Bottom-80));
		designBG.title = locale::FEATURED_DESIGNS;
		designBG.titleColor = colors::FTL;
		designBG.titleHeight = 42;
		designBG.titleFont = FT_Big;

		@panel = GuiPanel(designBG, Alignment(Left+4, Top+42, Right-4, Bottom-8));

		@uploadButton = GuiButton(container, Alignment(Left+34+600+48-200, Bottom-72, Width=200, Height=52), locale::UPLOAD_DESIGN);
		uploadButton.font = FT_Bold;
		uploadButton.setIcon(icons::Export);

		@recentDesigns = GuiButton(container, Alignment(Left+30+600+48-424, Bottom-75, Width=200, Height=30), locale::RECENT_DESIGNS);

		@topratedDesigns = GuiButton(container, Alignment(Left+30+600+48-424, Bottom-75+32, Width=200, Height=30), locale::TOPRATED_DESIGNS);

		@searchDesigns = GuiTextbox(container, Alignment(Left+30, Bottom-69, Width=200, Height=46));
		searchDesigns.emptyText = locale::SEARCH_DESIGNS_PROMPT;

		@wikiBG = GuiBackgroundPanel(container, Alignment(Left+30+600+48+30, Top+30, Right-30, Bottom-30));
		wikiBG.title = locale::COMMUNITY_WIKI;
		wikiBG.titleColor = colors::Research;
		wikiBG.titleHeight = 42;
		wikiBG.titleFont = FT_Big;

		@wikiPanel = GuiPanel(wikiBG, Alignment(Left+4, Top+42, Right-4, Bottom-12));

		@wikiText = LinkableMarkupText(wikiPanel, recti_area(12,12, 100,100), true);

		if(cloud::isActive)
			settings::bEnableInternet = true;

		updateAbsolutePosition();
		listSpec = "designs/featured";
	}

	void updateAbsolutePosition() {
		Tab::updateAbsolutePosition();
		if(wikiText.size.width != wikiPanel.size.width-44) {
			wikiText.size = vec2i(wikiPanel.size.width-44, wikiText.size.height);
			wikiText.updateAbsolutePosition();
		}
	}

	void reload() {
		if(settings::bEnableInternet) {
			container.visible = true;
			internetButton.visible = false;

			load(listSpec);
		}
		else {
			container.visible = false;
			internetButton.visible = true;
		}
	}

	void load(const string& spec) {
		listSpec = spec;
		webAPICall(spec, query);

		getWikiPage("Main Page", wiki);

		loading = true;
		loaded = false;
	}

	void show() {
		if(!loading)
			reload();
		Tab::show();
	}

	void tick(double time) {
		if(loading && !loaded && query.completed && wiki.completed)
			finish();
	}

	void finish() {
		loaded = true;
		loading = false;

		wikiText.text = wiki.result;

		for(uint i = 0, cnt = elements.length; i < cnt; ++i)
			elements[i].remove();
		elements.length = 0;

		JSONTree tree;
		tree.parse(query.result);

		if(!tree.root.isArray())
			return;

		int y = 12;
		for(uint i = 0, cnt = min(tree.root.size(), panel.size.height / 138); i < cnt; ++i) {
			auto@ mem = tree.root[i];
			if(mem !is null && mem.isObject()) {
				DesignElement elem(panel, recti_area(20,y, 600,130));
				elem.finishLoad(mem);
				elements.insertLast(elem);
				y += 138;
			}
		}

		updateAbsolutePosition();
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

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is recentDesigns) {
				browseTab(this, createCommunityDesignList("designs/recent"), true);
				return true;
			}
			else if(evt.caller is topratedDesigns) {
				browseTab(this, createCommunityDesignList("designs/toprated"), true);
				return true;
			}
			else if(evt.caller is uploadButton) {
				UploadDialog(this);
				return true;
			}
			else if(evt.caller is internetButton) {
				settings::bEnableInternet = true;
				saveSettings();
				reload();
				return true;
			}
		}
		else if(evt.type == GUI_Confirmed) {
			if(evt.caller is searchDesigns) {
				browseTab(this, createCommunityDesignList("designs/search/"+searchDesigns.text), true);
				searchDesigns.text = "";
				return true;
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_WikiBG, SF_Normal, AbsolutePosition);
		Tab::draw();
	}
};

class UploadDialog : Dialog {
	GuiDropdown@ design;
	GuiTextbox@ description;

	GuiButton@ accept;
	GuiButton@ cancel;

	array<const Design@> designs;

	UploadDialog(IGuiElement@ bind) {
		super(bind, bindInside=true);
		width = 600;
		height = 200;

		@accept = GuiButton(bg, recti());
		accept.text = locale::UPLOAD;
		accept.tabIndex = 100;
		accept.disabled = true;
		@accept.callback = this;
		accept.color = colors::Green;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 101;
		@cancel.callback = this;
		cancel.color = colors::Red;

		@design = GuiDropdown(bg, Alignment(Left+12, Top+40, Right-12, Top+76));

		ReadLock lck(playerEmpire.designMutex);
		uint cnt = playerEmpire.designCount;
		designs.reserve(cnt);
		designs.length = 0;
		design.addItem(locale::DESIGN_CHOOSE_PROMPT);
		for(uint i = 0; i < cnt; ++i) {
			const Design@ other = playerEmpire.designs[i];
			if(other.obsolete || other.newest() !is other)
				continue;
			design.addItem(formatShipName(other));
			designs.insertLast(other);
		}

		@description = GuiTextbox(bg, Alignment(Left+12, Top+80, Right-12, Bottom-46));
		description.multiLine = true;
		description.emptyText = locale::DESIGN_DESCRIPTION_PROMPT;

		addTitle(locale::UPLOAD_DESIGN, color=colors::FTL);

		alignAcceptButtons(accept, cancel);
		updatePosition();
	}

	void update() {
		accept.disabled = design.selected < 1;
	}

	void close() {
		close(false);
	}

	void close(bool accepted) {
		if(accepted && design.selected >= 1) {
			int id = upload_design(designs[design.selected-1], description.text, waitId=true);
			if(id > 0)
				browseTab(ActiveTab, createCommunityDesignPage(id), true);
		}
		Dialog::close();
	}

	void confirmDialog() {
		close(true);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked && (event.caller is accept || event.caller is cancel)) {
			close(event.caller is accept);
			return true;
		}
		else if(event.type == GUI_Changed) {
			update();
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};

Tab@ createCommunityHome() {
	return CommunityHome();
}
