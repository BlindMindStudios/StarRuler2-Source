import tabs.Tab;
from tabs.tabbar import newTab, switchToTab;

Tab@ createGraphicsEditorTab() {
	return GraphicsEditor();
}

class GraphicsEditor : Tab {
	string& get_title() {
		return locale::GRAPHICS_EDITOR;
	}

	Color get_activeColor() {
		return Color(0xaaaaaaff);
	}

	Color get_inactiveColor() {
		return Color(0x777777ff);
	}

	TabCategory get_category() {
		return TC_Graphics;
	}
};

interface Anchor {
	vec3d get_position() const;

	vec3d get_normal() const;
};

class PointAnchor : Anchor {	
	vec3d point;
	vec3d direction;
	
	vec3d get_position() const {
		return point;
	}
	
	vec3d get_normal() const {
		return direction;
	}
}

class CurveAnchor : Anchor {
	const Anchor@ from;
	const Anchor@ to;
	float percent;
	
	vec3d get_position() const {
		vec3d p0 = from.position;
		vec3d p1 = p0 + from.normal;
		vec3d p3 = to.position;
		vec3d p2 = p3 + to.normal;
		
		double t = percent, nt = 1.0 - percent;
		
		return p0 * (nt*nt*nt) + p1 * (3.0*t*nt*nt) + p2 * (3.0*t*t*nt) + p3 * (t*t*t);
	}
	
	vec3d get_normal() const {
		vec3d p0 = from.position;
		vec3d p1 = p0 + from.normal;
		vec3d p3 = to.position;
		vec3d p2 = p3 + to.normal;
		
		double t = percent, nt = 1.0 - percent;
		
		return (p0*(t*t) + p1 * (3.0*t*t - 4.0*t + 1.0) + p2*(-3.0*t*t + 2.0*t) + p3 * ((t - 1.0)*(t-1.0))).normalize();
	}
}

class GraphicsEditorCommand : ConsoleCommand {
	void execute(const string& args) {
		Tab@ editor = createGraphicsEditorTab();
		newTab(editor);
		switchToTab(editor);
	}
}

void init() {
	addConsoleCommand("graphics_editor", GraphicsEditorCommand());
}
