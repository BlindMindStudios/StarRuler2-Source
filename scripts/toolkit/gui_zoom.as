vec2i prev_size;
const vec2i min_resolution(1280, 720);
const double[] ui_zoom_factors = {0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0};
const int ui_default_zoom_index = 5;
int ui_zoom_index = ui_default_zoom_index;
bool canZoom = true;

int get_max_zoom_index() {
	for(int i = 0, cnt = ui_zoom_factors.length; i < cnt; ++i) {
		if(double(windowSize.x) / ui_zoom_factors[i] < min_resolution.x
		|| double(windowSize.y) / ui_zoom_factors[i] < min_resolution.y) {
			return max(i - 1, 0);
		}
	}
	return ui_zoom_factors.length - 1;
}

void ui_zoom_in(bool pressed) {
	if(!pressed) {
		if(!canZoom)
			return;
		if(ui_zoom_index >= max_zoom_index)
			return;
		ui_zoom_index += 1;
		uiScale = ui_zoom_factors[ui_zoom_index];
	}
}

void ui_zoom_out(bool pressed) {
	if(!pressed) {
		if(!canZoom)
			return;
		if(ui_zoom_index == 0)
			return;
		ui_zoom_index -= 1;
		uiScale = ui_zoom_factors[ui_zoom_index];
	}
}

void ui_zoom_reset(bool pressed) {
	if(!pressed) {
		ui_zoom_index = ui_default_zoom_index;
		uiScale = ui_zoom_factors[ui_zoom_index];
	}
}

void init() {
	keybinds::Global.addBind(KB_UI_ZOOM_IN, "ui_zoom_in");
	keybinds::Global.addBind(KB_UI_ZOOM_OUT, "ui_zoom_out");
	keybinds::Global.addBind(KB_UI_ZOOM_RESET, "ui_zoom_reset");
}

void tick(double time) {
	if(windowSize != prev_size) {
		//Calculate the default zoom
		if(windowSize.x < min_resolution.x || windowSize.y < min_resolution.y) {
			double xzoom = double(windowSize.x) / double(min_resolution.x);
			double yzoom = double(windowSize.y) / double(min_resolution.y);
			double factor = round(min(xzoom, yzoom) * 100.0) / 100.0;
			if(factor >= 0.1 && factor <= 10.0) {
				canZoom = false;
				uiScale = factor;
			}
		}
		else {
			if(!canZoom) {
				canZoom = true;
				uiScale = ui_zoom_factors[ui_zoom_index];
			}

			int max = max_zoom_index;
			if(ui_zoom_index > max) {
				ui_zoom_index = max;
				uiScale = ui_zoom_factors[ui_zoom_index];
			}
		}

		prev_size = windowSize;
	}
}
