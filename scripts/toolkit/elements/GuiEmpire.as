import elements.BaseGuiElement;
import settings.game_settings;
import empire_data;

export drawEmpirePicture, GuiEmpire;

void drawEmpirePicture(Empire@ emp, recti pos) {
	if(emp is null)
		return;

	if(emp.background !is null) {
		int s = max(pos.width, pos.height);
		emp.background.draw(recti_area(pos.topLeft - vec2i((s-pos.width)/2, (s-pos.height)/2), vec2i(s, s)));
	}

	if(emp.flag !is null) {
		int flagSize = min(min(pos.width * 0.6, pos.height * 0.6), 128.0);
		emp.flag.draw(recti_area(vec2i(pos.width - flagSize - 4, 4) + pos.topLeft,
					vec2i(flagSize, flagSize)), emp.color);
	}

	if(emp.portrait !is null) {
		int portraitSize = min(pos.width, pos.height);
		float aspect = float(emp.portrait.size.x) / float(emp.portrait.size.y);
		emp.portrait.draw(recti_area(vec2i(0, pos.height - portraitSize) + pos.topLeft,
					vec2i(portraitSize, portraitSize)).aspectAligned(aspect, 0.5, 1.0));
	}
}

void drawEmpirePicture(EmpireSettings@ emp, recti pos) {
	if(emp is null)
		return;

	auto@ bg = getEmpireColor(emp.color);
	if(bg !is null) {
		int s = max(pos.width, pos.height);
		bg.background.draw(recti_area(pos.topLeft - vec2i((s-pos.width)/2, (s-pos.height)/2), vec2i(s, s)));
	}

	auto@ flag = getEmpireFlag(emp.flag);
	if(flag !is null) {
		int flagSize = min(min(pos.width * 0.6, pos.height * 0.6), 128.0);
		flag.flag.draw(recti_area(vec2i(pos.width - flagSize - 4, 4) + pos.topLeft,
					vec2i(flagSize, flagSize)), bg.color);
	}

	auto@ portrait = getEmpirePortrait(emp.portrait);
	if(portrait !is null) {
		int portraitSize = min(pos.width, pos.height);
		float aspect = float(portrait.portrait.size.x) / float(portrait.portrait.size.y);
		portrait.portrait.draw(recti_area(vec2i(0, pos.height - portraitSize) + pos.topLeft,
					vec2i(portraitSize, portraitSize)).aspectAligned(aspect, 0.5, 1.0));
	}
}

class GuiEmpire : BaseGuiElement {
	Empire@ empire;
	EmpireSettings@ settings;

	bool showName = false;
	FontType nameFont = FT_Bold;

	SkinStyle background = SS_NULL;
	int padding = 0;

	GuiEmpire(IGuiElement@ parent, Alignment@ pos, Empire@ emp = null) {
		@empire = emp;
		super(parent, pos);
		updateAbsolutePosition();
	}

	GuiEmpire(IGuiElement@ parent, const recti& pos, Empire@ emp = null) {
		@empire = emp;
		super(parent, pos);
		updateAbsolutePosition();
	}

	void draw() {
		if(background != SS_NULL) {
			Color col;
			if(empire !is null)
				col = empire.color;
			skin.draw(background, SF_Normal, AbsolutePosition, col);
		}
		if(empire !is null) {
			drawEmpirePicture(empire, AbsolutePosition.padded(padding));
			if(showName) {
				const Font@ ft = skin.getFont(nameFont);
				//Because fuck the police
				ft.draw(pos=AbsolutePosition.padded(-1,-1,1,1), horizAlign=0.5, vertAlign=0.95,
					color=colors::Black, text=empire.name);
				ft.draw(pos=AbsolutePosition.padded(1,1,-1,-1), horizAlign=0.5, vertAlign=0.95,
					color=colors::Black, text=empire.name);
				ft.draw(pos=AbsolutePosition.padded(-1,1,1,-1), horizAlign=0.5, vertAlign=0.95,
					color=colors::Black, text=empire.name);
				ft.draw(pos=AbsolutePosition.padded(1,-1,-1,1), horizAlign=0.5, vertAlign=0.95,
					color=colors::Black, text=empire.name);
				ft.draw(pos=AbsolutePosition, horizAlign=0.5, vertAlign=0.95,
					color=empire.color.interpolate(colors::White, 0.3), text=empire.name);
			}

		}
		else if(settings !is null)
			drawEmpirePicture(settings, AbsolutePosition.padded(padding));
		BaseGuiElement::draw();
	}
};
