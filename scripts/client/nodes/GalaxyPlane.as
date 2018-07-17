export setGalaxyPlanesShown;
export getGalaxyPlanesShown;

bool SHOW_GALAXY_PLANES = false;
void setGalaxyPlanesShown(bool enabled) {
	SHOW_GALAXY_PLANES = enabled;
}

bool getGalaxyPlanesShown() {
	return SHOW_GALAXY_PLANES;
}

class GalaxyPlaneScript  {
	vec3d origin;
	double radius;
	double planeDist = 0;

	GalaxyPlaneScript(Node& node) {
	}

	void establish(Node& node, vec3d Origin, double Radius) {
		origin = Origin;
		radius = Radius;

		node.scale = radius;
		node.position = origin;
		node.rebuildTransform();
	}

	bool preRender(Node& node) {
		if(!SHOW_GALAXY_PLANES)
			return false;

		//Calculate distance to plane
		line3dd camLine(cameraPos, cameraPos+cameraFacing);
		vec3d intersect;
		if(!camLine.intersectY(intersect, origin.y, false)) {
			intersect = cameraPos;
			intersect.y = origin.y;
			planeDist = sqrt(
					sqr(max(0.0, intersect.distanceTo(origin) - radius))
					+ sqr(cameraPos.y - origin.y));
		}
		else {
			planeDist = intersect.distanceTo(cameraPos);
				max(0.0, intersect.distanceTo(origin) - radius);
		}

		return planeDist > 3000.0;
	}
	
	void render(Node& node) {
		shader::RADIUS = radius;
		shader::PLANE_DISTANCE = planeDist;

		drawPolygonStart(PT_Quads, 1, material::GalaxyPlane);
		drawPolygonPoint(origin + vec3d(-radius, 0, -radius), vec2f(0.f, 0.f));
		drawPolygonPoint(origin + vec3d(+radius, 0, -radius), vec2f(1.f, 0.f));
		drawPolygonPoint(origin + vec3d(+radius, 0, +radius), vec2f(1.f, 1.f));
		drawPolygonPoint(origin + vec3d(-radius, 0, +radius), vec2f(0.f, 1.f));
		drawPolygonEnd();
	}
};
