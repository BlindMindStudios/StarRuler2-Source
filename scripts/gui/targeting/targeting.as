#priority render 50
#priority draw -10

funcdef bool HoverFilterCB(Object@);
HoverFilterCB@ hoverFilter, lastHoverFilter;

class TargetMode {
	bool valid = false;
	bool isShifted = false;
	bool autoMultiple = false;
	
	bool isValidTarget(Object@ obj) {
		return true;
	}

	bool hover(const vec2i& mouse) {
		return false;
	}

	bool click() {
		return false;
	}

	vec3d get_position() {
		return vec3d();
	}

	Object@ get_target() {
		return null;
	}

	string get_message() {
		return "";
	}

	string get_desc() {
		return "";
	}

	bool onMouseWheel(int x, int y) {
		return false;
	}

	bool onMouseButton(int button, bool pressed) {
		if(!pressed) {
			if(button == 0) {
				targetingClick();
				return true;
			}
			else if(button == 1) {
				cancelTargeting(true);
				return true;
			}
		}
		else {
			if(button == 0 || button == 1)
				return true;
		}
		return false;
	}

	bool onMouseMoved(int x, int y) {
		return false;
	}

	bool onMouseDragged(int buttons, int x, int y, int dx, int dy) {
		if(buttons == 0x1)
			return true;
		return false;
	}

	bool onMouseDragEnd(int buttons) {
		if(buttons == 0x1)
			return true;
		return false;
	}

	bool onKeyEvent(int key, bool pressed) {
		if(key == KEY_ESC) {
			if(pressed) {
				return true;
			}
			else {
				cancelTargeting();
				return true;
			}
		}
		return false;
	}
};

class TargetVisuals {
	void draw(TargetMode@ mode) {
	}

	void render(TargetMode@ mode) {
	}
};

class TargetCallback {
	void call(TargetMode@ mode) {
	}

	void cancel() {
	}

	void cancel(bool wasExplicit) {
		cancel();
	}
};

TargetMode@ mode;
TargetVisuals@ visuals;
TargetCallback@ cb;
bool shown = false;

bool isTargeting() {
	return shown && mode !is null;
}

bool targetingClick() {
	if(mode is null)
		return false;
	if(!mode.click()) {
		sound::error.play(priority=true);
		return true;
	}
	auto@ _callback = cb;
	auto@ _mode = mode;

	if(!mode.autoMultiple || !shiftKey) {
		cancelTargeting();
	}
	else {
		sound::generic_click.play(priority=true);
		mode.isShifted = true;
	}

	if(_callback !is null)
		_callback.call(_mode);
	return true;
}

bool targetMouseWheel(int x, int y) {
	if(!shown || mode is null)
		return false;
	return mode.onMouseWheel(x, y);
}

bool targetMouseButton(int button, bool pressed) {
	if(!shown || mode is null)
		return false;
	return mode.onMouseButton(button, pressed);
}

bool targetMouseMoved(int x, int y) {
	if(!shown || mode is null)
		return false;
	return mode.onMouseMoved(x, y);
}

bool targetMouseDragged(int buttons, int x, int y, int dx, int dy) {
	if(!shown || mode is null)
		return false;
	return mode.onMouseDragged(buttons, x, y, dx, dy);
}

bool targetMouseDragEnd(int buttons) {
	if(!shown || mode is null)
		return false;
	return mode.onMouseDragEnd(buttons);
}

bool targetKeyEvent(int key, bool pressed) {
	if(!shown || mode is null)
		return false;
	return mode.onKeyEvent(key, pressed);
}

void startTargeting(TargetMode@ Mode, TargetVisuals@ Visuals, TargetCallback@ Cb) {
	@mode = Mode;
	@visuals = Visuals;
	@cb = Cb;
	@hoverFilter = HoverFilterCB(mode.isValidTarget);
}

void cancelTargeting(bool wasExplicit = false) {
	if(cb !is null)
		cb.cancel(wasExplicit);
	@mode = null;
	@visuals = null;
	@cb = null;
	@hoverFilter = null;
}

void showTargeting() {
	shown = true;
}

void hideTargeting() {
	shown = false;
}

void tick(double time) {
	if(shown && mode !is null) {
		bool valid = mode.hover(mousePos);
		if(mode !is null) {
			mode.valid = valid;
			if(mode.isShifted && !shiftKey)
				cancelTargeting();
		}
	}
}

void draw() {
	if(shown && visuals !is null)
		visuals.draw(mode);
}

void render(double time) {
	if(shown && visuals !is null)
		visuals.render(mode);
}
