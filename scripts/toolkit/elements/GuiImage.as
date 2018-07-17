import elements.BaseGuiElement;

export GuiImage;

class GuiImage : BaseGuiElement {
	const Material@ mat;

	recti source;

	Color topleft;
	Color topright;
	Color botright;
	Color botleft;
	
	void set_material(const Material@ m) {
		@mat = m;
		if(m !is null)
			source = recti(vec2i(), mat.size);
	}
	
	GuiImage(IGuiElement@ ParentElement, const recti& Rectangle, const Material@ Material) {
		@material = Material;
		super(ParentElement, Rectangle);
	}

	GuiImage(IGuiElement@ ParentElement, Alignment@ align, const Material@ Material) {
		@material = Material;
		super(ParentElement, align);
	}

	void set_color(Color c) {
		topleft = c;
		topright = c;
		botright = c;
		botleft = c;
	}

	void draw() {
		if(mat !is null)
			mat.draw(AbsolutePosition, topleft);
		//TODO: Broken shit
		//  mat.draw(AbsolutePosition, source, topleft, topright, botright, botleft);
		BaseGuiElement::draw();
	}
};
