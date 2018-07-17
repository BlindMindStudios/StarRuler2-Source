import tabs.Tab;
from input import activeCamera, copyPreviousCamera;
import systems;
import obj_selection;
import overlays.Popup;
import overlays.InfoBar;
from overlays.PlanetPopup import PlanetPopup;
from overlays.ShipPopup import ShipPopup;
from overlays.OrbitalPopup import OrbitalPopup;
from overlays.ObjectPopup import ObjectPopup;
from overlays.AsteroidPopup import AsteroidPopup;
from overlays.OddityPopup import OddityPopup;
from overlays.CivilianPopup import CivilianPopup;
from overlays.PickupPopup import PickupPopup;
from overlays.ArtifactPopup import ArtifactPopup;
from overlays.StarPopup import StarPopup;
from overlays.AnomalyOverlay import AnomalyOverlay;
from overlays.Quickbar import Quickbar;

from overlays.ContextMenu import openContextMenu;
from navigation.smart_pan import showSmartPan, hideSmartPan;
from targeting.targeting import showTargeting, hideTargeting;
from notifications.notifications import showNotifications, hideNotifications;
import tabs.tabbar;

from tabs.SystemTab import createSystemTab;

import GalaxyOverlay@ createSupportOverlay(IGuiElement@ tab, Object@ obj, Object@ to, bool animate) from "overlays.Supports";
import void doQuickExport(Object@,bool) from "commands";
import void doTransfer(Object@,bool) from "commands";
import void doQuickExport(const array<Object@>&,bool) from "commands";

const double POPUP_DELAY = 0.2;
const double POPUP_PROGRESS_DELAY = 0.1;
const int RADIAL_SIZE = 24;

bool calcExtents = true;
double refreshExtents = INFINITY;
vec3d extentMin, extentMax;

void insertExtent(const vec3d& lower, const vec3d& upper) {
	if(extentMin.x > lower.x)
		extentMin.x = lower.x;
	if(extentMin.y > lower.y)
		extentMin.y = lower.y;
	if(extentMin.z > lower.z)
		extentMin.z = lower.z;
	if(extentMax.x < upper.x)
		extentMax.x = upper.x;
	if(extentMax.y < upper.y)
		extentMax.y = upper.y;
	if(extentMax.z < upper.z)
		extentMax.z = upper.z;
}

void promptExtentRefresh() {
	refreshExtents = frameTime;
	calcExtents = true;
}

void setExtents(Camera@ cam) {
	if(calcExtents) {
		for(uint i = 0, cnt = systemCount; i < cnt; ++i) {
			auto sys = getSystem(i);
			if(i == 0) {
				extentMin = sys.position - vec3d(sys.radius);
				extentMax = sys.position + vec3d(sys.radius);
			}
			else {
				insertExtent(sys.position - vec3d(sys.radius), sys.position + vec3d(sys.radius));
			}
		}
		calcExtents = false;
	}
	
	cam.setPositionBound(extentMin - vec3d(500.0), extentMax + vec3d(500.0));
	cam.maxDistance = extentMin.distanceTo(extentMax) * 1.5;
}

class PopupRoot : BaseGuiElement {
	PopupRoot(BaseGuiElement@ parent) {
		super(parent, Alignment_Fill());
	}

	bool get_isRoot() const {
		return true;
	}
	
	IGuiElement@ elementFromPosition(const vec2i& pos) {
		IGuiElement@ ele;
		GalaxyTab@ tab = cast<GalaxyTab>(Parent);
		if(tab.infoBar !is null && tab.infoBar.visible) {
			IGuiElement@ ele = tab.infoBar.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		if(tab.actionBar !is null && tab.actionBar.visible) {
			IGuiElement@ ele = tab.actionBar.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		if(tab.overlay !is null && tab.overlay.visible) {
			IGuiElement@ ele = tab.overlay.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		for(uint i = 0, cnt = tab.popups.length; i < cnt; ++i) {
			IGuiElement@ ele = tab.popups[i].elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		if(tab.selPopup !is null && tab.selPopup.visible) {
			IGuiElement@ ele = tab.selPopup.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		if(tab.hovPopup !is null && tab.hovPopup.visible) {
			IGuiElement@ ele = tab.hovPopup.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		if(tab.quickbar !is null && tab.quickbar.visible) {
			IGuiElement@ ele = tab.quickbar.elementFromPosition(pos);
			if(ele !is null)
				return ele;
		}
		return null;
	}

	void draw() {
		GalaxyTab@ tab = cast<GalaxyTab>(Parent);
		if(tab.quickbar !is null && tab.quickbar.visible)
			tab.quickbar.draw();
		for(uint i = 0, cnt = tab.popups.length; i < cnt; ++i)
			tab.popups[i].draw();
		if(tab.actionBar !is null && tab.actionBar.visible)
			tab.actionBar.draw();
		if(tab.selPopup !is null && tab.selPopup.visible)
			tab.selPopup.draw();
		if(tab.hovPopup !is null && tab.hovPopup.visible)
			tab.hovPopup.draw();
		if(tab.overlay !is null && tab.overlay.visible)
			tab.overlay.draw();
		if(tab.infoBar !is null && tab.infoBar.visible)
			tab.infoBar.draw();
	}
};

interface GalaxyOverlay : IGuiElement {
	bool objectInteraction(Object& object, uint mouseButton, bool doubleClicked);
	bool update(double time);
	bool isOpen();
	void close();
};

class GalaxyTab : Tab {
	PopupRoot@ popupRoot;
	SmartCamera cam;
	SmartCamera objCam;
	vec3d cam_diff;

	Popup@[] popups;
	Popup@ selPopup;
	Popup@ hovPopup;

	InfoBar@ infoBar;
	Quickbar@ quickbar;
	GalaxyOverlay@ overlay;
	ActionBar@ actionBar;

	Object@ pressedObject;
	double popupTimer = -1.0;
	double systemTimer = 0.0;

	SystemDesc@ viewingSystem;

	GalaxyTab() {
		super();
		_GalaxyTab();
		if(ctrlKey && playerEmpire.Homeworld !is null) {
			cam.reset();
			cam.zoomTo(playerEmpire.Homeworld);
			cam.camera.snap();
		}
		else {
			copyPreviousCamera(cam);
		}
	}

	GalaxyTab(const vec3d& position) {
		super();
		_GalaxyTab();
		cam.reset();
		cam.zoomTo(position);
		cam.camera.snap();
	}

	GalaxyTab(Object@ focusOn) {
		super();
		_GalaxyTab();
		cam.reset();
		if(focusOn !is null) {
			cam.zoomTo(focusOn);
			cam.camera.snap();
		}
	}

	GalaxyTab(Empire@ focusOn) {
		super();
		_GalaxyTab();
		cam.reset();
		if(focusOn.Homeworld !is null) {
			cam.zoomTo(focusOn.Homeworld);
			cam.camera.snap();
		}
		else if(focusOn.HomeObj !is null) {
			cam.zoomTo(focusOn.HomeObj);
			cam.camera.snap();
		}
	}

	void _GalaxyTab() {
		@popupRoot = PopupRoot(this);
		@quickbar = Quickbar(popupRoot);
		title = locale::GALAXY;
		setExtents(cam.camera);

		@actionBar = ActionBar(this, vec2i(-6, 22));
		actionBar.noClip = true;
	}

	void show() {
		@activeCamera = cam;
		showTargeting();
		showNotifications();
		Tab::show();
	}

	void hide() {
		@activeCamera = null;
		hideTargeting();
		hideNotifications();
		Tab::hide();
	}

	void save(SaveFile& file) {
		file << cam;

		uint cnt = popups.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			Object@ obj = popups[i].get();
			file << obj;
			vec2i pos = popups[i].position;
			file << pos;
		}

		file << quickbar;
	}

	void load(SaveFile& file) {
		file >> cam;

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			Object@ obj;
			file >> obj;

			vec2i pos;
			file >> pos;

			if(obj !is null) {
				Popup@ pop = pinObject(obj);
				pop.position = pos;
			}
		}

		file >> quickbar;
	}

	Color get_activeColor() {
		return Color(0xfcb44eff);
	}

	Color get_inactiveColor() {
		return Color(0xff9600ff);
	}
	
	Color get_seperatorColor() {
		return Color(0x8c642bff);
	}

	TabCategory get_category() {
		return TC_Galaxy;
	}

	Sprite get_icon() {
		return Sprite(material::TabGalaxy);
	}

	bool isPinned(Object@ obj) {
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			if(popups[i].displays(obj))
				return true;
		}
		return false;
	}

	bool hasObjectDisplay(Object@ obj) {
		if(selPopup !is null && selPopup.visible && selPopup.displays(obj))
			return true;
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			if(popups[i].objLinked && popups[i].displays(obj))
				return true;
		}
		return false;
	}

	Popup@ getDisplayedPopup(Object@ obj) {
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			if(popups[i].displays(obj))
				return popups[i];
		}
		return null;
	}

	void preRender(double time) {
		cam.animate(time);
		updateRenderCamera(cam.camera);
	}

	//Render the entire world
	void render(double time) {
		//Render the scene
		if(!hide_ui)
			prepareRender(cam.camera, recti(0, int(78.0 * uiScale), windowSize.width, windowSize.height));
		else
			prepareRender(cam.camera);
		renderWorld();
	}

	void draw() {
		//Draw pressed indicator
		if(pressedObject !is null) {
			if(popupTimer < POPUP_DELAY - POPUP_PROGRESS_DELAY) {
				shader::PROGRESS = float(
						min(POPUP_DELAY - popupTimer - POPUP_PROGRESS_DELAY,
							POPUP_DELAY - POPUP_PROGRESS_DELAY))
					/ float(POPUP_DELAY - POPUP_PROGRESS_DELAY);
				vec2i pos = mousePos;
				material::RadialProgress.draw(recti_area(
					pos - vec2i(RADIAL_SIZE / 2, RADIAL_SIZE / 2),
					vec2i(RADIAL_SIZE, RADIAL_SIZE)), Color(0x3986a0aa));
			}
		}

		Tab::draw();
	}

	void updateViewingSystem(bool force = false) {
		vec3d point = cam.camera.lookAt;
		SystemDesc@ cur;

		if(viewingSystem !is null && viewingSystem.position.distanceToSQ(point)
				< viewingSystem.radius * viewingSystem.radius) {
			@cur = viewingSystem;
		}
		else {
			@cur = getSystem(point);
		}

		if(force || viewingSystem !is cur) {
			if(cur is null)
				title = locale::GALAXY;
			else
				title = cur.object.name;
			@viewingSystem = cur;
		}
	}

	//This tab is considered a root, because
	//it does not act as an overlaid gui element itself
	bool get_isRoot() const {
		return true;
	}

	void openSystemOverlay(Object@ sys) {
		browseTab(this, createSystemTab(sys), true);
	}

	void toggleSupportOverlay(Object@ obj) {
		if(overlay !is null) {
			closeOverlay();
			return;
		}
		if(!obj.selected)
			selectObject(obj);
		openSupportOverlay(obj);
	}

	void openSupportOverlay(Object@ obj) {
		bool animate = true;
		if(overlay !is null) {
			overlay.remove();
			animate = false;
		}
		if(!obj.selected)
			selectObject(obj);
		@overlay = createSupportOverlay(popupRoot, obj, null, animate);
	}

	void openSupportOverlay(Object@ obj, Object@ other) {
		bool animate = true;
		if(overlay !is null) {
			overlay.remove();
			animate = false;
		}
		if(!obj.selected)
			selectObject(obj);
		@overlay = createSupportOverlay(popupRoot, obj, other, animate);
	}

	Popup@ pinObject(Object@ obj, bool floating = false) {
		Popup@ pop = makePopup(obj);
		if(pop is null)
			return null;

		pop.objLinked = floating;
		pop.separated = true;
		pop.position = findPinPosition();
		pop.set(obj);
		popups.insertLast(pop);
		return pop;
	}

	void zoomTo(Object@ obj, bool zoomIn = false) {
		cam.zoomTo(obj.position);
		if(zoomIn) {
			double zoomFactor = obj.radius * 5 / objCam.camera.distance;
			cam.camera.zoom(zoomFactor);
		}
	}

	void zoomTo(const vec3d& position) {
		cam.zoomTo(position);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked: {
				Popup@ pop = cast<Popup>(evt.caller);
				if(pop !is null && pop.parent is popupRoot) {
					switch(evt.value) {
						case PA_Select:
							selectObject(pop.get(), shiftKey);
							return true;
						case PA_Manage:
							openOverlay(pop.get());
							return true;
						case PA_Zoom:
							zoomTo(pop.get(), shiftKey);
							return true;
					}
					return true;
				}
			} break;
			case GUI_Controller_Down: {
				if(evt.value == GP_A) {
					selectObject(hoveredObject);
					return true;
				}
				else if(evt.value == GP_X) {
					openOverlay(hoveredObject);
					return true;
				}
			} break;
		}
		return Tab::onGuiEvent(evt);
	}

	vec2i findPinPosition() {
		vec2i psize = vec2i(180, 135);
		vec2i pos = vec2i(12, 36);

		bool overlaps;
		uint popCnt = popups.length;
		do {
			overlaps = false;
			for(uint i = 0; i < popCnt; ++i) {
				if(popups[i].Position.overlaps(recti_area(pos, psize))) {
					overlaps = true;
					pos.y += psize.height + 4;
					if(pos.y + psize.height + 4 > size.height - 258) {
						pos.x += psize.width + 4;
						pos.y = 36;
					}
					break;
				}
			}
		}
		while(overlaps);

		return pos;
	}

	void updateInfoBar(Object@ obj) {
		if(obj is null) {
			if(infoBar !is null) {
				if(infoBar.get() !is null && !infoBar.get().valid) {
					infoBar.remove();
					@infoBar = null;
				}
			}
			return;
		}
		if(infoBar is null) {
			@infoBar = createInfoBar(popupRoot, obj);
			if(infoBar !is null)
				infoBar.sendToBack();
			return;
		}
		if(infoBar.displays(obj))
			return;
		if(!infoBar.compatible(obj)) {
			infoBar.remove();
			@infoBar = createInfoBar(popupRoot, obj);
			if(infoBar !is null)
				infoBar.sendToBack();
			return;
		}
		infoBar.set(obj);
	}

	void closeOverlay() {
		if(overlay !is null)
			overlay.close();
	}

	float actTimer = 0.f;
	void updateActions() {
		actionBar.clear();
		actionBar.addEmpireAbilities(playerEmpire, null);
		actionBar.init(null);
	}

	void tick(double time) {
		if(refreshExtents > frameTime - time - 0.25)
			setExtents(cam.camera);

		if(!visible)
			return;

		//Update currently viewing system
		systemTimer -= time;
		if(systemTimer <= 0) {
			updateViewingSystem();
			systemTimer += 0.2;
		}

		//Update overlay
		if(overlay !is null) {
			if(!overlay.isOpen())
				@overlay = null;
			else if(!overlay.update(time))
				closeOverlay();
		}

		//Update actionbar
		actTimer -= time;
		if(actTimer <= 0.f) {
			updateActions();
			actTimer += 1.f;
		}
		actionBar.update(time);
		
		//Update infobar
		updateInfoBar(selectedObject);
		if(infoBar !is null)
			infoBar.update(time);

		//Update visibility of notifications
		if(infoBar !is null && infoBar.showingManage)
			hideNotifications();
		else
			showNotifications();

		//Update quickbar
		if(quickbar !is null)
			quickbar.update(time);

		//Update selection popup
		if(popupTimer != -1.0) {
			popupTimer -= time;
			if(popupTimer <= 0.0 && settings::bHoldForPopup) {
				if(pressedObject !is null) {
					selectObject(pressedObject);
					openPopup(pressedObject);
					@pressedObject = null;
				}
				popupTimer = -1.0;
			}
			else if(pressedObject !is null && (mousePos.distanceTo(pressStart) > 4.0 || (popupTimer <= 0.0 && !settings::bHoldForPopup))) {
				if(pressedObject.isPlanet || pressedObject.isAsteroid) {
					if(selectedObjects.length != 0 && pressedObject.selected)
						doQuickExport(selectedObjects, true);
					else
						doQuickExport(pressedObject, true);
				}
				else if(pressedObject.hasLeaderAI && pressedObject.SupplyCapacity > 0) {
					doTransfer(pressedObject, true);
				}
				@pressedObject = null;
				if(selPopup !is null) {
					selPopup.remove();
					@selPopup = null;
				}
			}
		}
		if(selPopup !is null) {
			if(selPopup.separated) {
				if(selPopup.findPin) {
					selPopup.position = findPinPosition();
					selPopup.findPin = false;
				}
				popups.insertLast(selPopup);
				@selPopup = null;
			}
			else if(selectedObject is null || !selPopup.displays(selectedObject)) {
				selPopup.remove();
				@selPopup = null;
			}
			else {
				selPopup.update();
			}
		}

		//Update hover popup
		Object@ hov = hoveredObject;
		if(hov !is null && !hasObjectDisplay(hov)) {
			if(hovPopup is null) {
				@hovPopup = makePopup(hov);
			}
			else if(!hovPopup.compatible(hov)) {
				hovPopup.remove();
				@hovPopup = makePopup(hov);
			}

			if(hovPopup !is null) {
				if(hovPopup.get() !is hov)
					hovPopup.set(hov);
				hovPopup.mouseLinked = true;
				hovPopup.visible = true;
				hovPopup.update();
			}
		}
		else {
			if(hovPopup !is null)
				hovPopup.visible = false;
		}
		
		//Update other popups
		for(uint i = 0, cnt = popups.length; i < cnt; ++i) {
			if(popups[i].parent is null) {
				popups.removeAt(i);
				--i; --cnt;
			}
			else {
				popups[i].update();
			}
		}
		popups.sortDesc();
	}

	vec2i pressStart;
	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) {
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0) {
					if(hoveredObject !is null && supportsPopup(hoveredObject)) {
						popupTimer = POPUP_DELAY;
						pressStart = mousePos;
						@pressedObject = hoveredObject;
						return true;
					}
				}
			break;
			case MET_Button_Up:
				if(evt.button == 0) {
					popupTimer = -1.0;
					@pressedObject = null;
					return false;
				}
			break;
		}
		return Tab::onMouseEvent(evt, source);
	}

	Popup@ makePopup(Object@ obj) {
		if(cast<Ship>(obj) !is null)
			return ShipPopup(popupRoot);
		if(cast<Planet>(obj) !is null)
			return PlanetPopup(popupRoot);
		if(cast<Orbital>(obj) !is null)
			return OrbitalPopup(popupRoot);
		if(cast<Asteroid>(obj) !is null)
			return AsteroidPopup(popupRoot);
		if(cast<Oddity>(obj) !is null)
			return OddityPopup(popupRoot);
		if(cast<Civilian>(obj) !is null)
			return CivilianPopup(popupRoot);
		if(cast<Pickup>(obj) !is null)
			return PickupPopup(popupRoot);
		if(cast<Artifact>(obj) !is null)
			return ArtifactPopup(popupRoot);
		if(cast<Star>(obj) !is null)
			return StarPopup(popupRoot);
		return ObjectPopup(popupRoot);
	}

	bool supportsPopup(Object@ obj) {
		return true;
	}

	void openPopup(Object& object) {
		if(selPopup !is null) {
			selPopup.remove();
			@selPopup = null;
		}
		if(hovPopup !is null && hovPopup.get() is object) {
			@selPopup = hovPopup;
			@hovPopup = null;

			vec2i newPos = selPopup.objPos(object);
			selPopup.objOffset = (selPopup.position - newPos);

			selPopup.objLinked = true;
			selPopup.mouseLinked = false;
			selPopup.update();
		}
		else {
			if(hovPopup !is null) {
				hovPopup.remove();
				@hovPopup = null;
			}
			@selPopup = makePopup(object);
			if(selPopup !is null) {
				selPopup.set(object);
				selPopup.objLinked = true;
			}
		}
	}

	void openManage(Object@ primary, Object@ open = null) {
		updateInfoBar(primary);
		if(infoBar !is null) {
			infoBar.update(0.0);
			if(open !is null)
				infoBar.showManage(open);
			else
				infoBar.showManage(primary);
		}
	}

	bool openOverlay(Object@ object) {
		if(overlay !is null)
			closeOverlay();
		if(object is null)
			return false;

		Planet@ planet = cast<Planet>(object);
		if(planet !is null) {
			openManage(planet);
			return true;
		}

		Orbital@ orb = cast<Orbital>(object);
		if(orb !is null && (!orb.hasLeaderAI || orb.hasConstruction || orb.SupplyCapacity == 0)) {
			openManage(orb);
			return true;
		}

		/*Star@ star = cast<Star>(object);*/
		/*if(star !is null) {*/
		/*	openSystemOverlay(star.region);*/
		/*	return true;*/
		/*}*/

		if(object.hasLeaderAI) {
			if(object.owner.controlled && !object.hasConstruction)
				openSupportOverlay(object);
			else
				openManage(object);
			return true;
		}

		if(object.hasSupportAI) {
			Object@ leader = cast<Ship>(object).Leader;
			if(leader !is null) {
				selectObject(leader);
				if(leader.owner.controlled)
					openSupportOverlay(leader);
				else
					openManage(leader);
			}
			return true;
		}
		
		if(object.isAnomaly) {
			AnomalyOverlay(this, cast<Anomaly>(object));
			return true;
		}

		if(object.isOddity) {
			Object@ link = cast<Oddity>(object).getLink();
			if(link !is null) {
				zoomTo(link, shiftKey);
				return true;
			}
		}
		return false;
	}
	
	bool objectInteraction(Object& object, uint mouseButton, bool doubleClicked) {
		if(overlay !is null) {
			if(overlay.objectInteraction(object, mouseButton, doubleClicked))
				return true;
		}

		if(mouseButton == 0) {
			if(object.isPickup) {
				Object@ prot = object.getProtector();
				if(prot !is null) {
					if(doubleClicked)
						openOverlay(prot);
					else
						selectObject(prot, shiftKey);
					return true;
				}
			}
			if(doubleClicked) {
				if(openOverlay(object))
					return true;
			}
		}
		else if(mouseButton == 1) {
			if(openContextMenu(object)) {
				if(hovPopup !is null)
					hovPopup.visible = false;
				clearHoveredObject();
				return true;
			}
			return false;
		}
		else if(mouseButton == 2) {
			if(object.isOddity) {
				Object@ link = cast<Oddity>(object).getLink();
				if(link !is null)
					zoomTo(link, shiftKey);
				else
					zoomTo(object, shiftKey);
			}
			else {
				zoomTo(object, shiftKey);
			}
		}
		return false;
	}
};

Tab@ createGalaxyTab() {
	return GalaxyTab();
}

Tab@ createGalaxyTab(Object@ focusOn) {
	return GalaxyTab(focusOn);
}

Tab@ createGalaxyTab(Empire@ focusOn) {
	return GalaxyTab(focusOn);
}

Tab@ createGalaxyTab(vec3d pos) {
	return GalaxyTab(pos);
}

void openOverlay(Tab@ _tab, Object@ obj) {
	GalaxyTab@ tab = cast<GalaxyTab>(_tab);
	if(tab is null)
		return;
	tab.openOverlay(obj);
}

void openOverlay(Object@ obj) {
	GalaxyTab@ tab = cast<GalaxyTab>(ActiveTab);
	if(tab is null)
		return;
	tab.openOverlay(obj);
}

void pinObject(Tab@ _tab, Object@ obj, bool floating) {
	GalaxyTab@ tab = cast<GalaxyTab>(_tab);
	if(tab is null)
		return;
	tab.pinObject(obj, floating);
}

void zoomTo(Object@ obj) {
	if(obj is null)
		return;
	Tab@ tab = findTab(TC_Galaxy);
	if(tab is null)
		@tab = newTab(createGalaxyTab());
	switchToTab(tab);
	zoomTabTo(tab, obj);
}

void zoomTabTo(Object@ obj) {
	zoomTabTo(ActiveTab, obj);
}

void zoomTabTo(Tab@ _tab, Object@ obj) {
	GalaxyTab@ tab = cast<GalaxyTab>(_tab);
	if(tab is null)
		return;
	tab.zoomTo(obj);
}

void zoomTabTo(vec3d pos) {
	zoomTabTo(ActiveTab, pos);
}

void zoomTabTo(Tab@ _tab, vec3d pos) {
	GalaxyTab@ tab = cast<GalaxyTab>(_tab);
	if(tab is null)
		return;
	tab.zoomTo(pos);
}

void openSupportOverlay(Object@ obj) {
	GalaxyTab@ tab = cast<GalaxyTab>(ActiveTab);
	if(tab is null)
		return;
	tab.openSupportOverlay(obj);
}

void toggleSupportOverlay(Object@ obj) {
	GalaxyTab@ tab = cast<GalaxyTab>(ActiveTab);
	if(tab is null)
		return;
	tab.toggleSupportOverlay(obj);
}

void openSupportOverlay(Object@ obj, Object@ to) {
	GalaxyTab@ tab = cast<GalaxyTab>(ActiveTab);
	if(tab is null)
		return;
	tab.openSupportOverlay(obj, to);
}

//Event sent when we control a new empire, so
//we can zoom the camera to its homeworld
void playingEmpire(Empire@ emp) {
	GalaxyTab@ tab = cast<GalaxyTab>(ActiveTab);
	if(tab is null)
		return;
	if(emp.Homeworld !is null)
		tab.zoomTo(emp.Homeworld);
	else
		tab.cam.reset();
}

Mutex zoomMtx;
Object@ zoomToObject;

void sendZoom(Object@ obj) {
	Lock lck(zoomMtx);
	@zoomToObject = obj;
}

void tick(double time) {
	if(zoomToObject !is null) {
		Lock lck(zoomMtx);
		zoomTo(zoomToObject);
		@zoomToObject = null;
	}
}

void resetGalaxyTabs() {
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		if(tabs[i].category == TC_Galaxy) {
			browseTab(tabs[i], createGalaxyTab());
		}
	}
}

void resetInfoBar() {
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		GalaxyTab@ tb = cast<GalaxyTab>(tabs[i]);
		if(tb !is null) {
			if(tb.infoBar !is null) {
				tb.infoBar.remove();
				@tb.infoBar = null;
			}
			tb.updateInfoBar(selectedObject);
		}
	}
}

void postReload(Message& msg) {
	resetGalaxyTabs();
}
