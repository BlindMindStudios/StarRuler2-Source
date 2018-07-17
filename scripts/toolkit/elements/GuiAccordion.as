import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiPanel;
import elements.GuiText;

export GuiAccordion;

class GuiAccordion : BaseGuiElement {
	SkinStyle style = SS_NULL;
	int maxItemHeight = -1;
	int spacing = 4;
	bool expandItems = true;
	bool multiple = false;
	bool required = false;
	bool clickableHeaders = true;
	bool animate = true;
	double animSpeed = 3.0;

	IGuiElement@[] headers;
	IGuiElement@[] items;
	bool[] opened;
	double[] animSize;

	GuiAccordion(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
	}

	GuiAccordion(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
	}

	void draw() {
		if(style != SS_NULL) {
			uint flags = SF_Normal;
			if(isGuiFocusIn(this))
				flags |= SF_Focused;
			skin.draw(style, flags, AbsolutePosition);
		}
		updateAnimation(frameLength);
		BaseGuiElement::draw();
	}

	uint addSection(const string& header, IGuiElement@ item) {
		GuiButton btn(this, recti(0, 0, 100, 29), header);
		btn.font = FT_Medium;
		btn.style = SS_AccordionHeader;
		btn.horizAlign = 0.0;

		if(!clickableHeaders) {
			btn.disabled = true;
			btn.textColor = colors::White;
		}

		return addSection(btn, item);
	}

	uint get_sectionCount() {
		return items.length;
	}

	uint addSection(IGuiElement@ header, IGuiElement@ item) {
		@header.parent = this;
		@item.parent = this;

		headers.insertLast(header);
		items.insertLast(item);
		opened.insertLast(false);
		animSize.insertLast(0.0);
		updatePositions();
		return headers.length - 1;
	}

	uint addSection_r(IGuiElement@ header, IGuiElement@ item) {
		@header.parent = this;
		@item.parent = this;

		headers.insertLast(header);
		items.insertLast(item);
		opened.insertLast(false);
		animSize.insertLast(0.0);
		return headers.length - 1;
	}

	void clearSections() {
		for(uint i = 0, cnt = headers.length; i < cnt; ++i) {
			headers[i].remove();
			items[i].remove();
		}
		headers.length = 0;
		items.length = 0;
		animSize.length = 0;
	}

	void openSection(uint num, bool snap = true) {
		if(!multiple) {
			for(uint i = 0, cnt = headers.length; i < cnt; ++i) {
				opened[i] = false;
				if(snap)
					animSize[i] = 0.0;
			}
		}

		opened[num] = true;
		if(snap)
			animSize[num] = 1.0;
		updatePositions();
	}

	void closeSection(uint num, bool snap = true) {
		if(required)
			return;
		opened[num] = false;
		if(snap)
			animSize[num] = 0.0;
		updatePositions();
	}

	void toggleSection(uint num, bool snap = false) {
		if(opened[num])
			closeSection(num, snap);
		else
			openSection(num, snap);
		updatePositions();
	}


	void updateAnimation(double time) {
		bool animating = false;
		for(uint i = 0, cnt = animSize.length; i < cnt; ++i) {
			if(opened[i]) {
				if(animSize[i] < 1.0) {
					animSize[i] = clamp(animSize[i] + time * animSpeed, 0.0, 1.0);
					animating = true;

					auto@ p = cast<GuiPanel>(items[i]);
					if(p !is null)
						p.setAnimating(animSize[i] < 1.0);
				}
			}
			else {
				if(animSize[i] > 0.0) {
					animSize[i] = clamp(animSize[i] - time * animSpeed, 0.0, 1.0);
					animating = true;

					auto@ p = cast<GuiPanel>(items[i]);
					if(p !is null)
						p.setAnimating(animSize[i] > 0.0);
				}
			}
		}
		if(animating)
			updatePositions();
	}

	void updatePositions() {
		int y = 0, w = size.width, hh = 0;
		if(expandItems && !multiple) {
			for(uint i = 0, cnt = headers.length; i < cnt; ++i)
				hh += headers[i].size.height + spacing;
		}
		for(uint i = 0, cnt = headers.length; i < cnt; ++i) {
			IGuiElement@ header = headers[i];
			IGuiElement@ item = items[i];

			//Position header
			int h = header.size.height;
			header.size = vec2i(w, h);
			header.position = vec2i(0, y);
			
			y += h;

			//Position item
			if(opened[i] || animSize[i] > 0) {
				item.visible = true;
				if(!expandItems)
					h = item.size.height;
				else if(!multiple)
					h = size.height - hh;
				else if(maxItemHeight == -1)
					h = item.desiredSize.height;
				else
					h = min(maxItemHeight, item.desiredSize.height);
				h *= animSize[i];
				item.size = vec2i(w, h);
				item.position = vec2i(0, y);
				y += h;
			}
			else {
				item.visible = false;
			}

			y += spacing;
		}

		size = vec2i(w, y);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.type == GUI_Clicked && event.caller.parent is this) {
			for(uint i = 0, cnt = headers.length; i < cnt; ++i) {
				if(headers[i] is event.caller) {
					toggleSection(i);
					return true;
				}
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		updatePositions();
	}
};
