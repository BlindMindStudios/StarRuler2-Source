import tabs.tabbar;
import elements.GuiBlueprint;
import community.DesignElement;
import elements.GuiMarkupText;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiPanel;
import elements.MarkupTooltip;
import icons;

class CommunityDesignList : Tab {
	WebData query;
	string listSpec;

	int offset = 0;

	GuiButton@ backButton;
	GuiText@ titleBox;

	GuiButton@ prevButton;
	GuiButton@ nextButton;

	GuiPanel@ panel;
	array<DesignElement@> elements;

	bool loaded = true;
	bool loading = false;
	bool hasNextPage = false;
	int elementsInPage = 10;

	CommunityDesignList(const string& spec) {
		@backButton = GuiButton(this, Alignment(Left+8, Top+8, Left+144, Height=50), locale::BACK);
		backButton.buttonIcon = icons::Back;

		@titleBox = GuiText(this, Alignment(Left+164, Top+8, Right-8, Top+60));
		titleBox.font = FT_Medium;
		titleBox.stroke = colors::Black;

		@prevButton = GuiButton(this, Alignment(Left+0.5f-152, Bottom-60, Left+0.5f-2, Bottom-8), locale::PREVIOUS);
		prevButton.disabled = true;
		prevButton.setIcon(icons::Previous);

		@nextButton = GuiButton(this, Alignment(Left+0.5f+2, Bottom-60, Left+0.5f+152, Bottom-8), locale::NEXT);
		nextButton.disabled = true;
		nextButton.setIcon(icons::Next);

		@panel = GuiPanel(this, Alignment(Left, Top+64, Right, Bottom-64));

		updateAbsolutePosition();
		listSpec = spec;
	}

	void reload() {
		load(listSpec);
	}

	void clear() {
		for(uint i = 0, cnt = elements.length; i < cnt; ++i)
			elements[i].remove();
		elements.length = 0;
	}

	void load(const string& spec) {
		listSpec = spec;

		if(!loading) {
			title = format(locale::COMMUNITY_TITLE, listSpec);
			titleBox.text = title;

			int limit = getListCount();
			int page = offset / limit;
			webAPICall(format("$1?page=$2&limit=$3", spec, toString(page), toString(limit)), query);

			loading = true;
			loaded = false;
		}
	}

	void show() {
		if(!loading)
			reload();
		Tab::show();
	}

	void tick(double time) {
		backButton.disabled = previous is null;
		prevButton.disabled = offset == 0 || loading;
		nextButton.disabled = hasNextPage || loading;
		
		if(loading && !loaded && query.completed)
			finish();
	}

	void finish() {
		loaded = true;
		loading = false;

		for(uint i = 0, cnt = elements.length; i < cnt; ++i)
			elements[i].remove();
		elements.length = 0;

		JSONTree tree;
		tree.parse(query.result);

		if(!tree.root.isArray())
			return;

		hasNextPage = tree.root.size() <= getListCount();
		elementsInPage = getListCount();
		prevButton.disabled = offset == 0;
		nextButton.disabled = hasNextPage;

		int startx = (size.width - elemsPerRow*712) / 2;
		int y = 12;
		int x = startx;
		for(uint i = 0, cnt = min(tree.root.size(), getListCount()); i < cnt; ++i) {
			auto@ mem = tree.root[i];
			if(mem !is null && mem.isObject()) {
				DesignElement elem(panel, recti_area(x,y, 700,160));
				elem.finishLoad(mem);
				elements.insertLast(elem);

				x += 712;
				if(x+712 >= size.width) {
					x = startx;
					y += 168;
				}
			}
		}
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

	int get_elemsPerRow() {
		return size.width / 712;
	}

	uint getListCount() {
		int rows = (size.height - 64 - 64 - 24) / 168;
		return clamp(elemsPerRow * rows, 3, 50);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is backButton) {
				popTab(this);
				return true;
			}
			else if(evt.caller is prevButton) {
				offset = max(0, offset-elementsInPage);
				clear();
				reload();
				return true;
			}
			else if(evt.caller is nextButton) {
				offset += elements.length;
				clear();
				reload();
				return true;
			}
		}
		return Tab::onGuiEvent(evt);
	}

	void draw() {
		skin.draw(SS_WikiBG, SF_Normal, AbsolutePosition);
		skin.draw(SS_PlainBox, SF_Normal, recti(AbsolutePosition.topLeft,
					vec2i(AbsolutePosition.botRight.x, AbsolutePosition.topLeft.y+64)));
		Tab::draw();
	}
};

Tab@ createCommunityDesignList(const string& spec = "designs/recent") {
	return CommunityDesignList(spec);
}
