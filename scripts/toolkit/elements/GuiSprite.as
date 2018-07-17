import elements.BaseGuiElement;

export GuiSprite;

class GuiSprite : BaseGuiElement {
	Sprite desc;
	Color color;
	const Shader@ shader;
	bool keepAspect = true;
	bool stretchOutside = false;
	double horizAlign = 0.5;
	double vertAlign = 0.5;
	float saturation = 1.f;

	GuiSprite(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
	}

	GuiSprite(IGuiElement@ ParentElement, Alignment@ Align, const Sprite& sprt) {
		desc = sprt;
		super(ParentElement, Align);
		updateAbsolutePosition();
	}

	GuiSprite(IGuiElement@ ParentElement, Alignment@ Align, const SpriteSheet@ Sheet, uint Sprite) {
		@desc.sheet = Sheet;
		desc.index = Sprite;
		super(ParentElement, Align);
		updateAbsolutePosition();
	}

	GuiSprite(IGuiElement@ ParentElement, const recti& Rectangle) {
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	GuiSprite(IGuiElement@ ParentElement, const recti& Rectangle, const Sprite& sprt) {
		desc = sprt;
		super(ParentElement, Rectangle);
		updateAbsolutePosition();
	}

	GuiSprite(IGuiElement@ ParentElement, const recti& Rectangle, const SpriteSheet@ Sheet, uint Sprite) {
		@desc.sheet = Sheet;
		desc.index = Sprite;
		super(ParentElement, Rectangle);
	}

	void set_sprite(uint index) {
		desc.index = index;
	}

	void set_sheet(const SpriteSheet@ sheet) {
		@desc.sheet = sheet;
		@desc.mat = null;
	}

	void set_material(const Material@ mat) {
		@desc.sheet = null;
		@desc.mat = mat;
	}

	void draw() {
		recti pos = AbsolutePosition;
		if(keepAspect) {
			vec2i size = desc.size;
			if(size.y != 0) {
				if(stretchOutside) {
					double aspect = desc.aspect;
					if(pos.width > pos.height) {
						size.x = pos.width;
						size.y = double(pos.width) * aspect;
					}
					else {
						size.y = pos.height;
						size.x = double(pos.height) / aspect;
					}
					pos = recti_area(pos.topLeft - vec2i((size.x-pos.width)/2, (size.y-pos.height)/2), size);
				}
				else {
					pos = pos.aspectAligned(double(size.x) / double(size.y), horizAlign, vertAlign);
				}
			}
		}
		if(saturation != 1.f) {
			shader::SATURATION_LEVEL = saturation;
			desc.draw(pos, color, shader::Desaturate);
		}
		else
		if(shader !is null)
			desc.draw(pos, color, shader);
		else
			desc.draw(pos, color);
		BaseGuiElement::draw();
	}
};
