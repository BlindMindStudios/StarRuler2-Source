final class ShipyardNodeScript {
	const Model@ shipyard = getModel("Shipyard");
	const Material@ shipyard_mat = getMaterial("VolkurGenericPBR");
	const Design@ design;
	float progress = 0;

	ShipyardNodeScript(Node& node) {
	}
	
	void updateProgress(const Design@ dsgn, float percent) {
		@design = dsgn;
		progress = percent;
	}

	void render(Node& node) {
		node.applyTransform();
		
		shipyard_mat.switchTo();
		shipyard.draw();
		
		if(design !is null) {
			applyAbsTransform(vec3d(), vec3d((design.size + 8.0) / (design.size + 16.0)), quaterniond());
			design.hull.material.switchTo();
			design.hull.model.draw();
			undoTransform();
		}
		
		undoTransform();
	}
};