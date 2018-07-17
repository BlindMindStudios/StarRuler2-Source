import dialogs.Dialog;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiTextbox;
import elements.GuiSpinbox;
import elements.GuiScrollbar;

interface ColorDialogCallback {
	void colorChosen(Color col);
};

class ColorPicker : BaseGuiElement {
	float hue = 1.f, sat = 1.f, value = 1.f, alpha = 1.f;
	Color picked;
	bool pressed = false;
	
	ColorPicker(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	void draw() {
		shader::HSV_VALUE = value;
		shader::HSV_SAT_START = 0.f;
		shader::HSV_SAT_END = 1.f;
		drawRectangle(AbsolutePosition, material::HSVPalette, Color());
		BaseGuiElement::draw();
	}
	
	Color get_color() const {
		Colorf col;
		col.fromHSV(hue, sat, value);
		col.a = alpha;
		return Color(col);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Down || (event.type == MET_Moved && pressed)) {
			pressed = true;
			hue = float(event.x - AbsolutePosition.topLeft.x);
			sat = 1.f - float(event.y - AbsolutePosition.topLeft.y) / float(AbsolutePosition.height);
			
			picked = color;

			GuiEvent evt;
			@evt.caller = this;
			evt.type = GUI_Changed;
			onGuiEvent(evt);
			return true;
		}
		else if(pressed && event.type == MET_Button_Up) {
			pressed = false;
			return true;
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}
};

class ColorBox : BaseGuiElement {
	Color color;
	
	ColorBox(IGuiElement@ parent, const recti& pos) {
		super(parent, pos);
	}

	void draw() {
		drawRectangle(AbsolutePosition, color);
		BaseGuiElement::draw();
	}
};

class ColorDialog : Dialog {
	ColorDialogCallback@ callback;
	ColorPicker@ picker;
	GuiScrollbar@ value;
	ColorBox@ display;
	
	GuiButton@ accept;
	
	GuiSpinbox@ r, g, b, a;

	ColorDialog(ColorDialogCallback@ CB, IGuiElement@ bind, Color startCol = Color()) {
		@callback = CB;
		super(bind);
		height = 330;
		width = 480;
		
		@picker = ColorPicker(window, recti_area(vec2i(6,6), vec2i(360,256)));
		@accept = GuiButton(window, recti(400, 300, 476, 326), locale::ACCEPT);
		@value = GuiScrollbar(window, recti(370, 6, 396, 280));
		value.page = 0;
		value.scroll = 5.f / 255.f;
		
		@r = GuiSpinbox(window, recti(400, 6, 450, 32), 0, 0, 255, 5, 0);
		@b = GuiSpinbox(window, recti(400, 36, 450, 62), 0, 0, 255, 5, 0);
		@g = GuiSpinbox(window, recti(400, 66, 450, 92), 0, 0, 255, 5, 0);
		@a = GuiSpinbox(window, recti(400, 96, 450, 122), 0, 0, 255, 5, 0);
		@display = ColorBox(window, recti(400, 126, 450, 152));
		
		color = startCol;
		addDialog(this);
	}
	
	void set_color(Color col) {
		syncBoxColor(col);
		syncRegionColor(col);
	}
	
	void syncBoxColor(Color col) {
		r.value = col.r;
		g.value = col.g;
		b.value = col.b;
		a.value = col.a;
		col.a = 255;
		display.color = col;
	}
	
	void syncRegionColor(Color col) {
		Colorf hsv = Colorf(col);
		
		value.pos = 1.f - hsv.value;
		picker.value = 1.f - value.pos;
		picker.hue = hsv.hue;
		picker.sat = hsv.saturation;
		picker.alpha = hsv.a;
		
		col.a = 255;
		display.color = col;
	}
	
	Color get_color() const {
		Color col;
		col.r = min(uint(r.value), 255);
		col.g = min(uint(g.value), 255);
		col.b = min(uint(b.value), 255);
		col.a = min(uint(a.value), 255);
		return col;
	}

	//Event callbacks
	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked) {
			if(event.caller is accept) {
				if(callback !is null)
					callback.colorChosen(color);
				close();
				return true;
			}
		}
		else if(event.type == GUI_Changed) {
			if(event.caller is picker) {
				syncBoxColor(picker.picked);
				return true;
			}
			else if(event.caller is value) {
				picker.value = 1.f - value.pos;
				syncBoxColor(picker.color);
				return true;
			}
			else {
				syncRegionColor(color);
				return true;
			}
		}
		return Dialog::onGuiEvent(event);
	}
	
	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(Closed)
			return false;
		if(event.type == MET_Scrolled && source is picker)
			return value.onMouseEvent(event, value);
		return Dialog::onMouseEvent(event, source);;
	}
};
