void drawLitModel(const Model& model, const Material@ material, const recti& position, const quaterniond& rotation, double scale = 1.0, const vec3f& lightPos = vec3f(), const Color& lightColor = colors::White) {
	Light@ light = ::light[0];
	light.position = vec3f(position.center.x, -100.f, position.center.y);
	if(!lightPos.zero)
		light.position = lightPos;
	light.diffuse = lightColor;
	light.specular = light.diffuse;
	light.radius = 1000.f;
	light.att_quadratic = 1.f/(500.0*500.0);
	light.enable();
	light.enable();
	
	model.draw(material, position, rotation, scale);
	
	resetLights();
}

