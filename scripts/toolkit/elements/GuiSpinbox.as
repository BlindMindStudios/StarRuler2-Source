import elements.BaseGuiElement;
import elements.GuiTextbox;
import elements.GuiButton;

export GuiSpinbox;

class GuiSpinbox : BaseGuiElement {
	GuiTextbox@ textbox;
	GuiButton@ upButton;
	GuiButton@ downButton;
	double step;
	int decimals;
	double min;
	double max;

	GuiSpinbox(IGuiElement@ ParentElement, const recti& Rectangle, double num) {
		super(ParentElement, Rectangle);
		_GuiSpinbox(num);
	}

	GuiSpinbox(IGuiElement@ ParentElement, Alignment@ align, double num) {
		super(ParentElement, align);
		_GuiSpinbox(num);
	}

	GuiSpinbox(IGuiElement@ ParentElement, Alignment@ align, double num, double min, double max, double step, int decimals) {
		super(ParentElement, align);
		_GuiSpinbox(num);
		this.min = min;
		this.max = max;
		this.step = step;
		this.decimals = decimals;
	}

	GuiSpinbox(IGuiElement@ ParentElement, const recti& pos, double num, double min, double max, double step, int decimals) {
		super(ParentElement, pos);
		_GuiSpinbox(num);
		this.min = min;
		this.max = max;
		this.step = step;
		this.decimals = decimals;
	}

	GuiSpinbox(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		_GuiSpinbox(0.0);
	}

	GuiSpinbox(IGuiElement@ ParentElement, Alignment@ align) {
		super(ParentElement, align);
		_GuiSpinbox(0.0);
	}

	void set_disabled(bool value) {
		upButton.visible = !value;
		downButton.visible = !value;
		textbox.disabled = value;
	}

	double get_value() {
		return clamp(toDouble(textbox.text), min, max);
	}

	void set_value(double val) {
		textbox.text = toString(clamp(val, min, max), decimals);
	}

	void set_maximum(double val) {
		max = val;
		if(!textbox.Focused)
			value = value;
	}

	void set_minimum(double val) {
		min = val;
		if(!textbox.Focused)
			value = value;
	}

	void set_font(FontType ft) {
		textbox.font = ft;
	}

	void set_color(const Color& color) {
		textbox.bgColor = color;
	}

	void _GuiSpinbox(double num) {
		step = 1.0;
		decimals = 0;
		min = -INFINITY;
		max = INFINITY;

		@textbox = GuiTextbox(this, Alignment(Left, Top, Right-20, Bottom));

		@upButton = GuiButton(this, Alignment(Right-20, Top, Right, Bottom-0.5f));
		upButton.style = SS_SpinButton;

		@downButton = GuiButton(this, Alignment(Right-20, Bottom-0.5f, Right, Bottom));
		downButton.style = SS_SpinButton;
			
		value = num;
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		int h = size.height / 2;
		textbox.alignment.right.pixels = h;
		upButton.alignment.left.pixels = h;
		downButton.alignment.left.pixels = h;

		BaseGuiElement::updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is upButton) {
			if(event.type == GUI_Clicked) {
				value = value + step;
				emitClicked();
				emitChanged();
				return true;
			}
		}
		else if(event.caller is downButton) {
			if(event.type == GUI_Clicked) {
				value = value - step;
				emitClicked();
				emitChanged();
				return true;
			}
		}
		else if(event.caller is textbox) {
			GuiEvent evt = event;
			@evt.caller = this;
			return BaseGuiElement::onGuiEvent(evt);
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source.isChildOf(this)) {
			switch(event.type) {
				case MET_Scrolled:
					value = value + event.y * step;
					emitClicked();
					emitChanged();
					return true;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
};
