import elements.BaseGuiElement;
import elements.GuiSkinElement;
import elements.GuiDraggable;

final class ElementDefinition {
	string type;
	Alignment alignment;
	
	ElementDefinition(IGuiElement@ element) {
		type = element.elementType;
		
		BaseGuiElement@ ele = cast<BaseGuiElement@>(element);
		alignment = ele.Alignment;
	}
};

final class GuiEditor : BaseGuiElement {
	BaseGuiElement@ focus;
	GuiDraggable@ editPanel;
	GuiElementEditor@ editor;
	bool left = false, top = false, right = false, bottom = false;

	GuiEditor() {
		super(null, Alignment_Fill());
		
		@editPanel = GuiDraggable(this, recti(0,0,128,128));
		editPanel.visible = false;
		
		@editor = GuiElementEditor(editPanel);
	}
	
	void drawScaleBound(AlignedPoint@ bound, const recti& within, bool horiz) {
		//Only show lines for scaled alignments
		if(bound.percent == 0.f)
			return;
	
		if(horiz) {
			int y = within.topLeft.y + bound.resolve(within.size.height);
			skin.draw(SS_AlignmentBoundHoriz, 0, recti(0,y,screenSize.width,y+1));
		}
		else {
			int x = within.topLeft.x + bound.resolve(within.size.width);
			skin.draw(SS_AlignmentBoundVert, 0, recti(x,0,x+1,screenSize.height));
		}
	}
	
	void draw() {
		if(focus !is null) {
			//Draw bounding box of selected element
			skin.draw(SS_EditHighlight, 0, focus.absolutePosition);
			
			//Draw alignment bounds
			Alignment@ align = focus.Alignment;
			if(align !is null) {
				recti within = focus.parent.absolutePosition;
				drawScaleBound(align.left, within, false);
				drawScaleBound(align.right, within, false);
				drawScaleBound(align.top, within, true);
				drawScaleBound(align.bottom, within, true);
			}
		}
	
		BaseGuiElement::draw();
	}
	
	void chooseElement(vec2i point) {
		//Hide this element so it won't be chosen
		Visible = false;
		IGuiElement@ element = getRootGuiElement().elementFromPosition(point);
		Visible = true;
		
		@focus = cast<BaseGuiElement@>(element);
		editPanel.visible = focus !is null;
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case MET_Button_Down:
					chooseElement(vec2i(event.x, event.y));
					return true;
			}
		}
		
		return BaseGuiElement::onMouseEvent(event,source);
	}
	
	void nudge(vec2i amount) {
		if(focus is null)
			return;
			
		if(focus.Alignment is null) {
			focus.move(amount);
		}
		else {
			//Adjust an alignment if its key is pressed, or no key is pressed (WASD)
			Alignment@ align = focus.Alignment;
			if(top || !(left || right || bottom))
				align.top.pixels += align.top.type == AS_Top ? amount.y : -amount.y;
			if(bottom || !(left || right || top))
				align.bottom.pixels += align.bottom.type == AS_Top ? amount.y : -amount.y;
			if(left || !(top || right || bottom))
				align.left.pixels += align.left.type == AS_Left ? amount.x : -amount.x;
			if(right || !(left || top || bottom))
				align.right.pixels += align.right.type == AS_Left ? amount.x : -amount.x;
		}
		
		focus.updateAbsolutePosition();
	}
	
	void nudgeScale(vec2f amount) {
		if(focus is null)
			return;
			
		if(focus.Alignment is null) {
			//TODO: Generate an alignment
			@focus.Alignment = Alignment(focus.rect);
		}
		
		//Adjust an alignment if its key is pressed, or no key is pressed (WASD)
		Alignment@ align = focus.Alignment;
		if(top || !(left || right || bottom))
			align.top.percent += align.top.type == AS_Top ? amount.y : -amount.y;
		if(bottom || !(left || right || top))
			align.bottom.percent += align.bottom.type == AS_Top ? amount.y : -amount.y;
		if(left || !(top || right || bottom))
			align.left.percent += align.left.type == AS_Left ? amount.x : -amount.x;
		if(right || !(left || top || bottom))
			align.right.percent += align.right.type == AS_Left ? amount.x : -amount.x;
		
		focus.updateAbsolutePosition();
	}
	
	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) {
		if(source is this) {
			switch(event.type) {
				case KET_Key_Down:
					switch(event.key) {
						case KEY_UP:
							if(ctrlKey)
								nudgeScale(vec2f(0,shiftKey ? -0.04 : -0.0025));
							else
								nudge(vec2i(0,shiftKey ? -10 : -1));
							break;
						case KEY_DOWN:
							if(ctrlKey)
								nudgeScale(vec2f(0,shiftKey ? 0.04 : 0.0025));
							else
								nudge(vec2i(0,shiftKey ? 10 : 1));
							break;
						case KEY_LEFT:
							if(ctrlKey)
								nudgeScale(vec2f(shiftKey ? -0.04 : -0.0025, 0));
							else
								nudge(vec2i(shiftKey ? -10 : -1, 0));
							break;
						case KEY_RIGHT:
							if(ctrlKey)
								nudgeScale(vec2f(shiftKey ? 0.04 : 0.0025, 0));
							else
								nudge(vec2i(shiftKey ? 10 : 1, 0));
							break;
						case KEY_ESC:
							@parent = null;
							break;
						case 'W': top = true; break;
						case 'A': left = true; break;
						case 'S': bottom = true; break;
						case 'D': right = true; break;
					}
				break;
				case KET_Key_Up:
					switch(event.key) {
						case 'W': top = false; break;
						case 'A': left = false; break;
						case 'S': bottom = false; break;
						case 'D': right = false; break;
					}
				break;
			}
			
			return true;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}
};

class GuiElementEditor : BaseGuiElement {
	BaseGuiElement@ element;
	
	GuiElementEditor(BaseGuiElement@ parent) {
		super(parent, Alignment_Fill());
		GuiSkinElement bg(this, Alignment_Fill(), SS_Panel);
	}
	
	void set_element(IGuiElement@ ele) {
		@element = cast<BaseGuiElement@>(ele);
		
		
	}
}

class GuiEditorCommand : ConsoleCommand {
	void execute(const string& args) {
		GuiEditor@ editor = GuiEditor();
	}
}

void init() {
	addConsoleCommand("gui_editor", GuiEditorCommand());
}
