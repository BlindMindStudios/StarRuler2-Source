import elements.BaseGuiElement;
import elements.GuiMarkupText;

export MarkupTooltip, setMarkupTooltip;
export addLazyMarkupTooltip;

class MarkupTooltip : MarkupRenderer, ITooltip {
	float Delay = 0.5f;
	bool visible = false;
	bool Persist = false;
	bool FollowMouse = true;
	bool Lazy = false;
	bool LazyUpdate = true;
	bool StaticPosition = false;
	double lastUpdate = -INFINITY;
	vec2i offset(12, 0);
	int Width = 250;
	int Padding = 10;
	SkinStyle background = SS_Tooltip;
	recti lastpos;
	string lastText;
	bool wrapAroundElement = true;

	MarkupTooltip(const string& txt, int width = 250, float delay = 0.5f, bool persist = false, bool followMouse = true) {
		super();
		parseTree(txt);
		visible = txt.length != 0;
		lastText = txt;
		Width = width;
		Delay = delay;
		Persist = persist;
		FollowMouse = followMouse;
	}

	MarkupTooltip(int width = 250, float delay = 0.5f, bool persist = false, bool followMouse = true) {
		super();
		Width = width;
		Delay = delay;
		Persist = persist;
		Lazy = true;
		FollowMouse = followMouse;
	}

	void update(const Skin@ skin, IGuiElement@ elem) {
		if(Lazy) {
			update(elem);
			lastUpdate = frameTime;
		}
	}

	void set_text(const string& txt) {
		visible = txt.length != 0;
		if(txt == lastText)
			return;
		lastText = txt;
		parseTree(txt);
	}

	void set_width(int w) {
		Width = w;
	}

	float get_delay() {
		return Delay;
	}

	bool get_persist() {
		return Persist;
	}

	void show(const Skin@ skin, IGuiElement@ elem) {
		if(Lazy)
			update(elem);
		visible = lastText.length != 0;
	}

	void hide(const Skin@ skin, IGuiElement@ elem) {
		if(Lazy)
			clear();
		visible = false;
	}

	void update(IGuiElement@ elem) {
		string tt;
		while(elem !is null && tt.length == 0) {
			tt = elem.tooltip;
			@elem = elem.parent;
		}
		text = tt;
	}

	void clear() override {
		lastText = "";
		MarkupRenderer::clear();
	}

	void draw(const Skin@ skin, IGuiElement@ elem) {
		if(Lazy && LazyUpdate) {
			if(lastUpdate < frameTime - 0.2) {
				update(elem);
				lastUpdate = frameTime;
			}
		}

		if(!visible)
			return;

		int prevHeight = height;
		vec2i size(Width, height + Padding * 2);
		vec2i pos;
		if(StaticPosition) {
			pos = offset;
		}
		else if(FollowMouse) {
			pos = mousePos + offset;
			if(wrapAroundElement) {
				if(pos.x + size.x >= screenSize.x) {
					pos = mousePos - offset;
					pos.x -= size.x;
				}
				if(pos.y + size.y > screenSize.y)
					pos.y = screenSize.y - size.y;
			}
		}
		else {
			recti elemPos = elem.absolutePosition;
			pos = vec2i(elemPos.botRight.x, elemPos.topLeft.y) + offset;
			if(pos.x + size.x >= screenSize.x) {
				if(wrapAroundElement) {
					pos = elemPos.topLeft - offset;
					pos.x -= size.x;
				}
				else {
					pos.x = screenSize.x - size.x;
				}
			}
			if(pos.y + size.y > screenSize.y)
				pos.y = screenSize.y - size.y;
		}

		//Draw the background
		recti absPos = recti_area(pos, size);
		skin.draw(background, SF_Normal, absPos);

		//Draw the markup
		draw(skin, absPos.padded(Padding));
		if(height != prevHeight)
			draw(skin, elem);
	}
};

void setMarkupTooltip(BaseGuiElement@ ele, const string& tooltip, bool hoverStyle = true, int width = 250) {
	MarkupTooltip@ obj = cast<MarkupTooltip>(ele.tooltipObject);
	if(obj is null) {
		@ele.tooltipObject = MarkupTooltip(tooltip, width, hoverStyle ? 0.f : 0.5f, hoverStyle);
	}
	else {
		obj.width = width;
		obj.Persist = hoverStyle;
		obj.text = tooltip;
	}
}

MarkupTooltip@ addLazyMarkupTooltip(BaseGuiElement@ ele, bool hoverStyle = true, int width = 250, bool update = false) {
	MarkupTooltip tt(width, hoverStyle ? 0.f : 0.5f, hoverStyle);
	tt.Lazy = true;
	tt.LazyUpdate = update;
	@ele.tooltipObject = tt;
	return tt;
}
