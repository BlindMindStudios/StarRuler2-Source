import overlays.Popup;
from overlays.PlanetPopup import PlanetPopup;

class ObjectPopupTooltip : ITooltip {
	Popup@ pop;
	Object@ obj;

	ObjectPopupTooltip() {
	}

	void set(Object@ Obj) {
		@obj = Obj;
	}

	void show(const Skin@ skin, IGuiElement@ elem) {
		if(obj is null)
			return;
		if(pop is null) {
			@pop = PlanetPopup(null);
			pop.set(obj);
			pop.mouseLinked = true;
			pop.isSelectable = true;
			pop.update();
		}
		pop.visible = true;
	}

	void hide(const Skin@ skin, IGuiElement@ elem) {
		if(pop !is null) {
			pop.remove();
			@pop = null;
		}
	}

	float get_delay() {
		return 0.f;
	}

	bool get_persist() {
		return true;
	}

	void update(const Skin@ skin, IGuiElement@ elem) {
	}

	void update() {
		if(pop is null)
			return;
		pop.update();
	}

	void draw(const Skin@ skin, IGuiElement@ elem) {
	}
};
