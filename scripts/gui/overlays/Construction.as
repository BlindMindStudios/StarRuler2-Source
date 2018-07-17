import elements.BaseGuiElement;
import elements.GuiSkinElement;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiButton;
import elements.GuiOverlay;
import elements.GuiAccordion;
import elements.GuiListbox;
import elements.GuiProgressbar;
import elements.GuiPanel;
import elements.GuiMarkupText;
import elements.GuiContextMenu;
import elements.GuiCargoDisplay;
import elements.MarkupTooltip;
import constructible;
import ship_groups;
import buildings;
import constructions;
import orbitals;
import targeting.PointTarget;
import targeting.ObjectTarget;
import systems;
import cargo;
from obj_selection import hoveredObject;
from gui import animate_time;
from overlays.ContextMenu import FinanceDryDock;

export ConstructionParent, ConstructionDisplay;
export BuildElement;

const double ANIM1_TIME = 0.15;
const double ANIM2_TIME = 0.001;
const uint Q_HEIGHT = 250;
const uint WIDTH = 500;
interface ConstructionParent : IGuiElement {
	void close();
	void startBuild(const BuildingType@ type);
	Object@ get_object();
	Object@ get_slaved();
	void triggerUpdate();
};

class ConstructionOverlay : GuiOverlay, ConstructionParent {
	ConstructionDisplay@ construction;
	Object@ obj;
	Object@ slave;

	ConstructionOverlay(IGuiElement@ parent, Object@ obj) {
		if(obj.isOrbital) {
			Orbital@ orb = cast<Orbital>(obj);
			if(orb.hasMaster()) {
				@slave = obj;
				@obj = orb.getMaster();
			}
		}

		@this.obj = obj;
		super(parent);

		@construction = ConstructionDisplay(this, vec2i(parent.size.width/2, parent.size.height),
					Alignment(Right-0.5f-250, Top+20, Right-0.5f+250, Bottom-20));
		construction.animate(ANIM1_TIME);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Confirmed:
				triggerUpdate();
			break;
		}
		return GuiOverlay::onGuiEvent(evt);
	}

	void startBuild(const BuildingType@ type) {
	}

	Object@ get_object() {
		return obj;
	}

	Object@ get_slaved() {
		return slave;
	}

	void triggerUpdate() {
	}

	void update(double time) {
		construction.update(time);
	}
};

class DisplayBox : BaseGuiElement {
	ConstructionParent@ overlay;
	Alignment@ targetAlign;

	DisplayBox(ConstructionParent@ ov, vec2i origin, Alignment@ target) {
		@overlay = ov;
		@targetAlign = target;
		super(overlay, recti_area(origin, vec2i(1,1)));
		visible = false;
		updateAbsolutePosition();
	}

	void animate(double animTime = ANIM2_TIME) {
		visible = true;
		animate_time(this, targetAlign.resolve(overlay.size), animTime);
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Animation_Complete:
				@alignment = targetAlign;
				return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		switch(evt.type) {
			case MET_Button_Down:
				if(evt.button == 0)
					return true;
			break;
			case MET_Button_Up:
				if(evt.button == 0)
					return true;
			break;
		}

		return BaseGuiElement::onMouseEvent(evt, source);
	}

	void remove() override {
		@overlay = null;
		BaseGuiElement::remove();
	}

	void update(double time) {
	}

	void draw() {
		skin.draw(SS_OverlayBox, SF_Normal, AbsolutePosition, Color(0x888888ff));
		BaseGuiElement::draw();
	}
};

class ConstructionDisplay : DisplayBox {
	Object@ obj;
	Object@ slaved;

	GuiSkinElement@ nameBox;
	GuiText@ name;

	GuiSkinElement@ laborBox;
	GuiText@ labor;
	GuiSprite@ laborIcon;

	Constructible[] cons;
	GuiSkinElement@ queueBox;
	GuiPanel@ queue;

	QueueItem@[] queueItems;
	QueueItem@ draggingItem;
	QueueItem@ hoveredItem;

	GuiPanel@ buildPanel;
	BaseGuiElement@ buttonBox;
	GuiButton@ buildingsButton;
	GuiButton@ orbitalsButton;
	GuiButton@ shipsButton;
	GuiButton@ modulesButton;
	GuiButton@ constructionsButton;
	GuiAccordion@ buildingsList;
	GuiAccordion@ orbitalsList;
	GuiAccordion@ shipsList;
	GuiAccordion@ modulesList;
	GuiAccordion@ constructionsList;

	GuiProgressbar@ storageBox;
	GuiButton@ repeatButton;
	GuiButton@ drydockButton;

	GuiCargoDisplay@ cargo;

	bool hasBuildings = false;
	bool hasOrbitals = false;
	bool hasShips = false;
	bool hasConstructions = false;
	bool isBuildingFlagship = false;

	ConstructionDisplay(ConstructionParent@ ov, vec2i origin, Alignment@ target) {
		super(ov, origin, target);
		@obj = ov.object;
		@slaved = ov.slaved;

		//Header
		@nameBox = GuiSkinElement(this, Alignment(Left+8, Top+8, Left+0.5f-4, Top+42), SS_PlainOverlay);
		@name = GuiText(nameBox, Alignment().padded(8, 0), locale::CONSTRUCTION);
		name.font = FT_Medium;

		@laborBox = GuiSkinElement(this, Alignment(Left+0.5f+4, Top+8, Right-8, Top+42), SS_PlainOverlay);
		@laborIcon = GuiSprite(laborBox, Alignment(Left+8, Top+5, Width=24, Height=24));
		laborIcon.desc = Sprite(spritesheet::ResourceIcon, 6);
		@labor = GuiText(laborBox, Alignment(Left+40, Top, Right-8, Bottom));
		labor.font = FT_Medium;

		//Queue section
		@queueBox = GuiSkinElement(this, Alignment(Left+8, Top+50, Right-8, Top+Q_HEIGHT), SS_QueueBackground);
		GuiSkinElement bottomBar(queueBox, Alignment(Left+4, Bottom-34, Right-4, Bottom), SS_PlainBox);
		@queue = GuiPanel(queueBox, Alignment(Left, Top, Right, Bottom-34));
		@storageBox = GuiProgressbar(queueBox, recti_area(4, Q_HEIGHT-34-50, WIDTH-16-12-80, 34));
		storageBox.visible = false;
		storageBox.frontColor = Color(0x836000ff);
		storageBox.backColor = Color(0xffffff80);
		@cargo = GuiCargoDisplay(queueBox, recti_area((WIDTH-16)/2, Q_HEIGHT-34-50, (WIDTH-16)/2-12-80, 34));
		cargo.visible = false;

		@repeatButton = GuiButton(queueBox, Alignment(Right-8-32, Bottom-32, Width=30, Height=30));
		repeatButton.style = SS_IconToggle;
		repeatButton.color = Color(0x00ff00ff);
		repeatButton.toggleButton = true;
		repeatButton.setIcon(icons::Repeat);
		setMarkupTooltip(repeatButton, locale::TT_REPEAT_QUEUE, width=300);

		@drydockButton = GuiButton(queueBox, Alignment(Right-8-32-34, Bottom-32, Width=30, Height=30));
		drydockButton.style = SS_IconButton;
		drydockButton.color = Color(0x0080ffff);
		drydockButton.setIcon(Sprite(spritesheet::GuiOrbitalIcons, 3, playerEmpire.color));
		setMarkupTooltip(drydockButton, locale::TT_DRY_DOCK, width=300);

		//Build panel buttons
		@buttonBox = BaseGuiElement(this, Alignment(Left+8, Top+Q_HEIGHT+8, Right-8, Top+Q_HEIGHT+44));
		@buildingsButton = GuiButton(buttonBox, Alignment(Left, Top, Left, Bottom));
		buildingsButton.text = locale::BUILDINGS;
		buildingsButton.toggleButton = true;
		buildingsButton.disabled = true;
		buildingsButton.style = SS_TabButton;
		buildingsButton.buttonIcon = icons::Building;

		@orbitalsButton = GuiButton(buttonBox, Alignment(Left, Top, Left, Bottom));
		orbitalsButton.text = locale::ORBITALS;
		orbitalsButton.toggleButton = true;
		orbitalsButton.disabled = true;
		orbitalsButton.style = SS_TabButton;
		orbitalsButton.buttonIcon = icons::Orbital;

		@shipsButton = GuiButton(buttonBox, Alignment(Left, Top, Left, Bottom));
		shipsButton.text = locale::SHIPS;
		shipsButton.toggleButton = true;
		shipsButton.pressed = true;
		shipsButton.disabled = true;
		shipsButton.style = SS_TabButton;
		shipsButton.buttonIcon = icons::Ship;

		@modulesButton = GuiButton(buttonBox, Alignment(Left, Top, Left, Bottom));
		modulesButton.text = locale::ORBITAL_MODULES;
		modulesButton.toggleButton = true;
		modulesButton.disabled = true;
		modulesButton.visible = false;
		modulesButton.style = SS_TabButton;

		@constructionsButton = GuiButton(buttonBox, Alignment(Left, Top, Left, Bottom));
		constructionsButton.text = locale::PROJECTS;
		constructionsButton.toggleButton = true;
		constructionsButton.disabled = true;
		constructionsButton.style = SS_TabButton;
		constructionsButton.buttonIcon = icons::Project;

		//Build panel section
		@buildPanel = GuiPanel(this, Alignment(Left+8, Top+Q_HEIGHT+44, Right-8, Bottom-8));
		buildPanel.horizType = ST_Never;

		@buildingsList = GuiAccordion(buildPanel, recti(0, 0, WIDTH-16, 50));
		buildingsList.multiple = true;
		buildingsList.clickableHeaders = false;
		buildingsList.visible = false;

		@orbitalsList = GuiAccordion(buildPanel, recti(0, 0, WIDTH-16, 50));
		orbitalsList.multiple = true;
		orbitalsList.clickableHeaders = false;
		orbitalsList.visible = false;

		@shipsList = GuiAccordion(buildPanel, recti(-1, 0, WIDTH-16, 50));
		shipsList.multiple = true;
		shipsList.clickableHeaders = false;

		@modulesList = GuiAccordion(buildPanel, recti(-1, 0, WIDTH-16, 50));
		modulesList.multiple = true;
		modulesList.clickableHeaders = false;
		modulesList.visible = false;

		@constructionsList = GuiAccordion(buildPanel, recti(-1, 0, WIDTH-16, 50));
		constructionsList.multiple = true;
		constructionsList.clickableHeaders = false;
		constructionsList.visible = false;

		if(obj.isOrbital && !obj.hasConstruction) {
			shipsList.visible = false;
			shipsButton.pressed = false;
			modulesList.visible = true;
			modulesButton.pressed = true;
		}

		updateBuildList(true);
	}

	void draw() {
		DisplayBox::draw();
		if(draggingItem !is null) {
			clearClip();
			if(hoveredItem !is null) {
				int y = hoveredItem.AbsolutePosition.topLeft.y;
				bool moved = hoveredItem !is draggingItem;
				if(mousePos.y > hoveredItem.AbsolutePosition.center.y) {
					int ind = queueItems.find(hoveredItem) + 1;
					if(ind >= 0 && uint(ind) < queueItems.length) {
						y = queueItems[ind].AbsolutePosition.topLeft.y;
						moved = true;
					}
					else if(queueItems[queueItems.length-1] !is draggingItem){
						y = queueItems[queueItems.length-1].AbsolutePosition.botRight.y+4;
						moved = true;
					}
				}
				if(moved) {
					drawLine(vec2i(queueBox.AbsolutePosition.topLeft.x, y),
							vec2i(queueBox.AbsolutePosition.botRight.x, y),
							Color(0xff8080ff), 3);
				}
			}
			else if(queueItems.length != 0 && mousePos.y < queueItems[0].absolutePosition.botRight.y - 10) {
				if(queueItems[0] !is draggingItem) {
					int y = queueBox.AbsolutePosition.topLeft.y;
					drawLine(vec2i(queueBox.AbsolutePosition.topLeft.x, y),
							vec2i(queueBox.AbsolutePosition.botRight.x, y),
							Color(0xff8080ff), 3);
				}
			}
			else {
				if(queueItems.length != 0 && queueItems[queueItems.length-1] !is draggingItem) {
					int y = queueBox.AbsolutePosition.topLeft.y;
					if(queueItems.length != 0)
						y = queueItems[queueItems.length-1].AbsolutePosition.botRight.y+4;
					drawLine(vec2i(queueBox.AbsolutePosition.topLeft.x, y),
							vec2i(queueBox.AbsolutePosition.botRight.x, y),
							Color(0xff8080ff), 3);
				}
			}
			if(!mouseLeft)
				@draggingItem = null;
			else
				draggingItem.draw(recti_area(mousePos - draggingItem.dragOffset, vec2i(500, 29)));
		}
	}

	void updateAbsolutePosition() {
		DisplayBox::updateAbsolutePosition();
		if(shipsList !is null) {
			if(buildPanel.vert.visible) {
				shipsList.size = vec2i(buildPanel.size.width - 20, shipsList.size.height);
				orbitalsList.size = vec2i(buildPanel.size.width - 20, orbitalsList.size.height);
				buildingsList.size = vec2i(buildPanel.size.width - 20, buildingsList.size.height);
				constructionsList.size = vec2i(buildPanel.size.width - 20, constructionsList.size.height);
				modulesList.size = vec2i(buildPanel.size.width - 20, modulesList.size.height);
			}
			else {
				shipsList.size = vec2i(buildPanel.size.width, shipsList.size.height);
				orbitalsList.size = vec2i(buildPanel.size.width, orbitalsList.size.height);
				buildingsList.size = vec2i(buildPanel.size.width, buildingsList.size.height);
				constructionsList.size = vec2i(buildPanel.size.width, constructionsList.size.height);
				modulesList.size = vec2i(buildPanel.size.width, modulesList.size.height);
			}
		}
	}

	void deselect() {
		for(uint i = 0, cnt = buildingsList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(buildingsList.items[i]);
			list.clearSelection();
		}
		for(uint i = 0, cnt = orbitalsList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(orbitalsList.items[i]);
			list.clearSelection();
		}
		for(uint i = 0, cnt = shipsList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(shipsList.items[i]);
			list.clearSelection();
		}
		for(uint i = 0, cnt = modulesList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(modulesList.items[i]);
			list.clearSelection();
		}
		for(uint i = 0, cnt = constructionsList.items.length; i < cnt; ++i) {
			GuiListbox@ list = cast<GuiListbox>(constructionsList.items[i]);
			list.clearSelection();
		}
	}

	void updateBuildList(bool full = false) {
		if(full) {
			buildingsList.clearSections();
			constructionsList.clearSections();
			orbitalsList.clearSections();
			shipsList.clearSections();
			modulesList.clearSections();
			if(obj is null || obj.owner !is playerEmpire)
				return;
			if(obj.hasConstruction && obj.hasSurfaceComponent && obj.owner.ImperialBldConstructionRate > 0.001) {
				array<GuiListbox@> cats;
				array<string> catNames;

				for(uint i = 0, cnt = getBuildingTypeCount(); i < cnt; ++i) {
					const BuildingType@ type = getBuildingType(i);
					if(type.civilian)
						continue;
					if(!type.canBuildOn(obj, ignoreState = true))
						continue;

					GuiListbox@ list;
					for(uint n = 0, ncnt = cats.length; n < ncnt; ++n) {
						if(catNames[n] == type.category) {
							@list = cats[n];
							break;
						}
					}

					if(list is null) {
						@list = GuiListbox(this, recti(0, 0, 100, 20));
						list.style = SS_NULL;
						list.itemHeight = 30;

						MarkupTooltip tt(400, 0.f, true, true);
						tt.Lazy = true;
						tt.LazyUpdate = false;
						tt.Padding = 4;
						@list.tooltipObject = tt;

						catNames.insertLast(type.category);
						cats.insertLast(list);
					}

					list.addItem(BuildElement(this, type, obj));
				}

				for(uint i = 0, cnt = cats.length; i < cnt; ++i) {
					auto@ list = cats[i];
					list.sortDesc();

					string title = localize("#BCAT_"+catNames[i]);
					if(title[0] == '#')
						title = catNames[i];

					uint sec = buildingsList.addSection(title, list);
					buildingsList.openSection(sec);
					list.updateHover();
				}

				hasBuildings = true;
				buildingsButton.disabled = false;
			}
			else {
				hasBuildings = false;
				buildingsButton.disabled = true;
			}
			if(obj.hasConstruction && obj.canBuildOrbitals) {
				GuiListbox@ list = GuiListbox(this, recti(0, 0, 100, 20));
				list.style = SS_NULL;
				list.itemHeight = 30;

				MarkupTooltip tt(400, 0.f, true, true);
				tt.Lazy = true;
				tt.LazyUpdate = false;
				tt.Padding = 4;
				@list.tooltipObject = tt;

				auto@ drydock = getOrbitalModule("DryDock");
				for(uint i = 0, cnt = getOrbitalModuleCount(); i < cnt; ++i) {
					auto@ def = getOrbitalModule(i);
					if(def is drydock)
						continue;
					if(def.canBuildBy(obj))
						list.addItem(BuildElement(this, def, obj));
				}
				list.sortDesc();
				uint sec = orbitalsList.addSection(locale::ORBITALS, list);
				orbitalsList.openSection(sec);
				addShipsToBuildList(orbitalsList, stations=true);
				hasOrbitals = true;
				orbitalsButton.disabled = false;
				list.updateHover();
			}
			else {
				hasOrbitals = false;
				orbitalsButton.disabled = true;
			}
			if(obj.isOrbital && !cast<Orbital>(obj).isStandalone) {
				GuiListbox@ list = GuiListbox(this, recti(0, 0, 100, 20));
				list.style = SS_NULL;
				list.itemHeight = 30;

				MarkupTooltip tt(400, 0.f, true, true);
				tt.Lazy = true;
				tt.LazyUpdate = false;
				tt.Padding = 4;
				@list.tooltipObject = tt;

				for(uint i = 0, cnt = getOrbitalModuleCount(); i < cnt; ++i) {
					auto@ def = getOrbitalModule(i);
					if(def.canBuildOn(cast<Orbital>(obj)))
						list.addItem(BuildElement(this, def, obj));
				}
				list.sortDesc();
				uint sec = modulesList.addSection(locale::ORBITAL_MODULES, list);
				modulesList.openSection(sec);
				modulesButton.disabled = false;
				list.updateHover();
			}
			else {
				modulesButton.disabled = true;
			}
			if(obj.hasConstruction && obj.canBuildShips) {
				addShipsToBuildList(shipsList, stations=false);
				hasShips = true;
				shipsButton.disabled = false;
			}
			else {
				hasShips = false;
				shipsButton.disabled = true;
			}
			if(obj.hasConstruction) {
				array<GuiListbox@> cats;
				array<string> catNames;

				for(uint i = 0, cnt = getConstructionTypeCount(); i < cnt; ++i) {
					const ConstructionType@ type = getConstructionType(i);
					if(!type.canBuild(obj, ignoreCost=true))
						continue;

					GuiListbox@ list;
					for(uint n = 0, ncnt = cats.length; n < ncnt; ++n) {
						if(catNames[n] == type.category) {
							@list = cats[n];
							break;
						}
					}

					if(list is null) {
						@list = GuiListbox(this, recti(0, 0, 100, 20));
						list.style = SS_NULL;
						list.itemHeight = 30;

						MarkupTooltip tt(400, 0.f, true, true);
						tt.Lazy = true;
						tt.LazyUpdate = false;
						tt.Padding = 4;
						@list.tooltipObject = tt;

						catNames.insertLast(type.category);
						cats.insertLast(list);
					}

					list.addItem(BuildElement(this, type, obj));
				}

				for(uint i = 0, cnt = cats.length; i < cnt; ++i) {
					auto@ list = cats[i];
					list.sortDesc();

					string title = localize("#BCAT_"+catNames[i]);
					if(title[0] == '#')
						title = catNames[i];

					uint sec = constructionsList.addSection(title, list);
					constructionsList.openSection(sec);
					list.updateHover();
				}

				if(cats.length != 0) {
					hasConstructions = true;
					constructionsButton.disabled = false;
				}
				else {
					hasConstructions = false;
					constructionsButton.disabled = true;
				}
			}
			else {
				hasConstructions = false;
				constructionsButton.disabled = true;
			}
			if(obj.laborIncome == 0 && hasConstructions && shipsButton.pressed) {
				shipsList.visible = false;
				shipsButton.pressed = false;
				constructionsButton.pressed = true;
				constructionsList.visible = true;
			}
			else if(shipsButton.disabled && shipsButton.pressed) {
				shipsList.visible = false;
				shipsButton.pressed = false;
				if(!orbitalsButton.disabled) {
					orbitalsButton.pressed = true;
					orbitalsList.visible = true;
				}
				else if(!buildingsButton.disabled) {
					buildingsButton.pressed = true;
					buildingsList.visible = true;
				}
				else if(!constructionsButton.disabled) {
					constructionsButton.pressed = true;
					constructionsList.visible = true;
				}
			}
		}
		else {
			for(uint i = 0, cnt = buildingsList.items.length; i < cnt; ++i) {
				GuiListbox@ list = cast<GuiListbox>(buildingsList.items[i]);
				for(uint j = 0, jcnt = list.itemCount; j < jcnt; ++j) {
					GuiListElement@ ele = list.getItemElement(j);

					if(cast<BuildElement>(ele) !is null)
						cast<BuildElement>(ele).update(this);
				}
			}
			for(uint i = 0, cnt = orbitalsList.items.length; i < cnt; ++i) {
				GuiListbox@ list = cast<GuiListbox>(orbitalsList.items[i]);
				for(uint j = 0, jcnt = list.itemCount; j < jcnt; ++j) {
					GuiListElement@ ele = list.getItemElement(j);

					if(cast<BuildElement>(ele) !is null)
						cast<BuildElement>(ele).update(this);
				}
			}
			for(uint i = 0, cnt = shipsList.items.length; i < cnt; ++i) {
				GuiListbox@ list = cast<GuiListbox>(shipsList.items[i]);
				for(uint j = 0, jcnt = list.itemCount; j < jcnt; ++j) {
					GuiListElement@ ele = list.getItemElement(j);

					if(cast<BuildElement>(ele) !is null)
						cast<BuildElement>(ele).update(this);
				}
			}
			for(uint i = 0, cnt = constructionsList.items.length; i < cnt; ++i) {
				GuiListbox@ list = cast<GuiListbox>(constructionsList.items[i]);
				for(uint j = 0, jcnt = list.itemCount; j < jcnt; ++j) {
					GuiListElement@ ele = list.getItemElement(j);

					if(cast<BuildElement>(ele) !is null)
						cast<BuildElement>(ele).update(this);
				}
			}
		}
		updateAbsolutePosition();
		gui_root.updateHover();
	}

	void addShipsToBuildList(GuiAccordion@ acc, bool stations = false) {
		//Add ship classes
		ReadLock lock(playerEmpire.designMutex);
		uint clsCount = playerEmpire.designClassCount;
		for(uint i = 0; i < clsCount; ++i) {
			const DesignClass@ cls = playerEmpire.getDesignClass(i);

			//Check if we should display this class at all
			bool hasShips = false;
			for(uint j = 0, jcnt = cls.designCount; j < jcnt; ++j) {
				const Design@ dsg = cls.designs[j];
				if(dsg.obsolete)
					continue;
				if(dsg.hasTag(ST_Station) != stations)
					continue;
				if(dsg.hasTag(ST_Satellite))
					continue;
				hasShips = true;
				break;
			}

			if(!hasShips)
				continue;

			//Create the box
			GuiListbox@ list = GuiListbox(this, recti(0, 0, 100, 20));
			list.style = SS_NULL;
			list.itemHeight = 30;

			MarkupTooltip tt(400, 0.f, true, true);
			tt.Lazy = true;
			tt.LazyUpdate = false;
			tt.Padding = 4;
			@list.tooltipObject = tt;

			for(uint j = 0, jcnt = cls.designCount; j < jcnt; ++j) {
				const Design@ dsg = cls.designs[j];
				if(dsg.obsolete)
					continue;
				if(dsg.hasTag(ST_Station) != stations)
					continue;
				if(dsg.hasTag(ST_Satellite))
					continue;
				list.addItem(BuildElement(this, dsg, obj));
			}
			list.sortDesc();

			uint sec = acc.addSection(cls.name, list);
			acc.openSection(sec);
			list.updateHover();
		}

	}

	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) override {
		switch(evt.type) {
			case MET_Button_Down:
				if(source is queue && evt.button == 1)
					return true;
			break;
			case MET_Button_Up:
				if(evt.button == 0) {
					if(draggingItem !is null) {
						if(hoveredItem !is null) {
							if(mousePos.y > hoveredItem.AbsolutePosition.center.y) {
								int ind = queueItems.find(hoveredItem) + 1;
								if(ind >= 0 && uint(ind) < queueItems.length) {
									obj.moveConstruction(draggingItem.cons.id, queueItems[ind].cons.id);
								}
								else {
									obj.moveConstruction(draggingItem.cons.id, -1);
								}
							}
							else if(hoveredItem !is draggingItem) {
								obj.moveConstruction(draggingItem.cons.id, hoveredItem.cons.id);
							}
						}
						else if(queueItems.length != 0 && mousePos.y < queueItems[0].absolutePosition.botRight.y - 10) {
							if(queueItems[0] !is draggingItem)
								obj.moveConstruction(draggingItem.cons.id, queueItems[0].cons.id);
						}
						else {
							if(queueItems.length != 0 && queueItems[queueItems.length-1] !is draggingItem)
								obj.moveConstruction(draggingItem.cons.id, -1);
						}
						@draggingItem = null;
						updateQueue();
						updateTimer = 0.15;
						return true;
					}
					if(source is queue)
						selectQueue(null);
					return true;
				}
				else if(evt.button == 1) {
					if(source !is queue)
						overlay.close();
					return true;
				}
			break;
		}

		return DisplayBox::onMouseEvent(evt, source);
	}


	QueueItem@ selQueue;
	void selectQueue(QueueItem@ it) {
		@selQueue = it;
	}

	void updateQueue() {
		if(obj.owner !is playerEmpire
				|| !obj.hasConstruction) {
			cons.length = 0;
			return;
		}
		if(draggingItem !is null)
			return;

		cons.syncFrom(obj.getConstructionQueue());
		uint oldCnt = queueItems.length;
		uint newCnt = cons.length;

		for(uint i = newCnt; i < oldCnt; ++i)
			queueItems[i].remove();
		queueItems.length = newCnt;

		int selId = -1;
		if(selQueue !is null)
			selId = selQueue.cons.id;
		@selQueue = null;

		int y = 0;
		isBuildingFlagship = false;
		for(uint i = 0; i < newCnt; ++i) {
			QueueItem@ ele = queueItems[i];
			if(ele is null) {
				@ele = QueueItem(queue, this);
				@queueItems[i] = ele;
			}

			if(cons[i].dsg !is null)
				isBuildingFlagship = true;

			ele.first = i == 0;
			ele.update(cons[i], obj);
			ele.position = vec2i(0, y);
			y += ele.size.height;

			if(ele.cons.id == selId)
				@selQueue = ele;
		}
	}

	double updateTimer = 0.0;
	double longTimer = 5.0;
	void update(double time) override {
		updateTimer -= time;
		longTimer -= time;
		if(updateTimer <= 0) {
			updateTimer = randomd(0.1,0.9);

			updateQueue();

			if(longTimer <= 0) {
				updateBuildList(true);
				longTimer = 5.0;
			}
			else {
				if(obj.owner is playerEmpire) {
					if(hasShips != obj.hasConstruction && obj.canBuildShips
							|| hasOrbitals != obj.hasConstruction && obj.canBuildOrbitals
							|| hasBuildings != obj.hasConstruction && obj.hasSurfaceComponent && obj.owner.ImperialBldConstructionRate > 0.01)
						updateBuildList(true);
					else
						updateBuildList(false);
				}
			}

			int btnCount = 0;
			if(obj.hasConstruction) {
				nameBox.visible = true;
				laborBox.visible = true;
				queueBox.visible = true;

				buttonBox.alignment.top.pixels = Q_HEIGHT+8;
				buttonBox.alignment.bottom.pixels = Q_HEIGHT+44;

				if(obj.hasSurfaceComponent) {
					buildingsButton.visible = true;
					btnCount += 1;
				}
				else {
					buildingsButton.visible = false;
				}

				shipsButton.visible = true;
				orbitalsButton.visible = true;
				btnCount += 2;
			}
			else {
				nameBox.visible = false;
				laborBox.visible = false;
				queueBox.visible = false;

				buttonBox.alignment.top.pixels = 8;
				buttonBox.alignment.bottom.pixels = 44;
				buildPanel.alignment.top.pixels = 44;

				buildingsButton.visible = false;
				shipsButton.visible = false;
				orbitalsButton.visible = false;
			}
			/*if(obj.isOrbital) {*/
			/*	modulesButton.visible = true;*/
			/*	btnCount += 1;*/
			/*}*/
			/*else {*/
				modulesButton.visible = false;
			/*}*/
			if(hasConstructions) {
				constructionsButton.visible = true;
				btnCount += 1;
			}
			else {
				constructionsButton.visible = false;
			}

			if(btnCount <= 1) {
				buttonBox.visible = false;
				buildPanel.alignment.top.pixels = buttonBox.alignment.top.pixels;
			}
			else {
				buttonBox.visible = true;
				buildPanel.alignment.top.pixels = buttonBox.alignment.bottom.pixels;

				float pos = 0.f, step = 1.f / float(btnCount);
				if(modulesButton.visible) {
					modulesButton.alignment.left.percent = pos;
					pos += step;
					modulesButton.alignment.right.percent = pos;
				}
				if(buildingsButton.visible) {
					buildingsButton.alignment.left.percent = pos;
					pos += step;
					buildingsButton.alignment.right.percent = pos;
				}
				if(orbitalsButton.visible) {
					orbitalsButton.alignment.left.percent = pos;
					pos += step;
					orbitalsButton.alignment.right.percent = pos;
				}
				if(shipsButton.visible) {
					shipsButton.alignment.left.percent = pos;
					pos += step;
					shipsButton.alignment.right.percent = pos;
				}
				if(constructionsButton.visible) {
					constructionsButton.alignment.left.percent = pos;
					pos += step;
					constructionsButton.alignment.right.percent = pos;
				}
			}

			double curLabor = 0;
			if(obj.owner is playerEmpire)
				curLabor = obj.laborIncome;
			labor.text = formatMinuteRate(curLabor, " "+locale::RESOURCE_LABOR);

			double curStored = 0;
			if(obj.owner is playerEmpire)
				curStored = obj.currentLaborStored;
			double storCap = 0;
			if(obj.owner is playerEmpire)
				storCap = obj.laborStorageCapacity;
			if(obj.hasConstruction && (curStored > 0.001 || storCap > 0.001)) {
				storageBox.visible = true;

				float pct = 1.f;
				if(storCap > 0)
					pct = min(1.f, curStored / storCap);
				storageBox.progress = pct;
				storageBox.text = format(locale::STORED_LABOR, toString(curStored,0), toString(storCap,0));
				cargo.rect = recti_area((WIDTH-16)/2, Q_HEIGHT-34-50, (WIDTH-16)/2-12-80, 34);
			}
			else {
				storageBox.visible = false;
				cargo.rect = recti_area(4, Q_HEIGHT-34-50, (WIDTH-8)-12-80, 34);
			}

			//Update cargo
			cargo.visible = obj.hasCargo && obj.cargoTypes > 0;
			if(cargo.visible) {
				cargo.update(obj);
				storageBox.size = vec2i((WIDTH-16)/2-8, 34);
			}
			else {
				storageBox.size = vec2i(WIDTH-16-12-80, 34);
			}

			repeatButton.pressed = obj.owner is playerEmpire && obj.isRepeating;

			auto@ drydock = getOrbitalModule("DryDock");
			drydockButton.visible = obj.owner is playerEmpire && obj.canBuildShips && obj.canBuildOrbitals && drydock !is null && drydock.canBuildBy(obj);

			updateAbsolutePosition();
		}
	}

	void openDrydockMenu(Empire@ forEmp = playerEmpire) {
		GuiContextMenu menu(mousePos);
		menu.itemHeight = 36;
		menu.flexWidth = false;
		menu.width = 400;

		uint cnt = playerEmpire.designCount;
		for(uint i = 0; i < cnt; ++i) {
			auto@ dsg = playerEmpire.designs[i];
			if(dsg.obsolete || dsg.newer !is null || dsg.updated !is null)
				continue;
			if(dsg.hasTag(ST_Support))
				continue;
			if(dsg.hasTag(ST_Station))
				continue;
			if(dsg.hasTag(ST_Satellite))
				continue;
			menu.addOption(FlagshipDrydock(obj, dsg, forEmp));
		}

		menu.list.sortDesc();
		menu.updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Changed: {
				GuiListbox@ list = cast<GuiListbox>(evt.caller);
				if(list !is null && list.isChildOf(buildPanel)) {
					if(obj.owner !is playerEmpire)
						return true;

					BuildElement@ ele = cast<BuildElement>(list.selectedItem);
					if(ele !is null) {
						if(ele.dsg !is null) {
							if(ele.dsg.hasTag(ST_IsSupport)) {
								if(!obj.canBuildShips)
									return true;
								int selCons = -1;
								if(selQueue !is null)
									selCons = selQueue.cons.id;
								obj.addSupportShipConstruction(selCons, ele.dsg, shiftKey ? 1 : 10);
							}
							else if(ele.dsg.hasTag(ST_Station)) {
								if(!obj.canBuildOrbitals)
									return true;
								list.clearSelection();
								overlay.close();
								targetPoint(OrbitalTarget(obj, null, ele.dsg, constructFrom=slaved));
							}
							else {
								if(!obj.canBuildShips)
									return true;
								auto@ drydock = getOrbitalModule("DryDock");
								bool canDrydock = obj.canBuildOrbitals && drydock !is null && drydock.canBuildBy(obj);
								if(ctrlKey && canDrydock) {
									FinanceDryDock(ele.dsg, obj);
								}
								else {
									int cost = getBuildCost(ele.dsg, buildAt=obj);
									if(!playerEmpire.canPay(cost) && canDrydock)
										FinanceDryDock(ele.dsg, obj);
									else
										obj.buildFlagship(ele.dsg, constructFrom=slaved);
								}
							}
							list.clearSelection();
						}
						else if(ele.orb !is null) {
							if(ele.orb.isCore) {
								if(!obj.canBuildOrbitals)
									return true;
								list.clearSelection();
								overlay.close();
								targetPoint(OrbitalTarget(obj, ele.orb, constructFrom=slaved));
							}
							else {
								Orbital@ orb = cast<Orbital>(obj);
								if(orb is null)
									return true;
								orb.buildModule(ele.orb.id);
								updateTimer = 0.0;
								longTimer = 0.0;
								overlay.triggerUpdate();
							}
						}
						else if(ele.building !is null) {
							overlay.startBuild(ele.building);
							list.clearSelection();
						}
						else if(ele.construction !is null) {
							if(ele.construction.targets.length == 0) {
								obj.buildConstruction(ele.construction.id);
							}
							else if(ele.construction.targets[0].type == TT_Object) {
								targetObject(ConstructionTargetObject(obj, ele.construction));
								overlay.close();
							}
							else if(ele.construction.targets[0].type == TT_Point) {
								targetPoint(ConstructionTargetPoint(obj, ele.construction));
								overlay.close();
							}
							list.clearSelection();
						}

						updateBuildList(true);
						updateTimer = 0.0;
					}
				}
			} break;
			case GUI_Clicked:
				if(evt.caller is repeatButton) {
					obj.setRepeating(!obj.isRepeating);
					return true;
				}
				else if(evt.caller is drydockButton) {
					openDrydockMenu();
					return true;
				}
				else if(cast<QueueItem>(evt.caller) !is null) {
					updateTimer = 0.0;
					return true;
				}
				else if(evt.caller is buildingsButton) {
					buildingsButton.pressed = true;
					buildingsList.visible = true;

					orbitalsList.visible = false;
					orbitalsButton.pressed = false;
					shipsList.visible = false;
					shipsButton.pressed = false;
					modulesList.visible = false;
					modulesButton.pressed = false;
					constructionsList.visible = false;
					constructionsButton.pressed = false;
					updateAbsolutePosition();
				}
				else if(evt.caller is orbitalsButton) {
					orbitalsButton.pressed = true;
					orbitalsList.visible = true;

					buildingsList.visible = false;
					buildingsButton.pressed = false;
					shipsList.visible = false;
					shipsButton.pressed = false;
					modulesList.visible = false;
					modulesButton.pressed = false;
					constructionsList.visible = false;
					constructionsButton.pressed = false;
					updateAbsolutePosition();
				}
				else if(evt.caller is shipsButton) {
					shipsButton.pressed = true;
					shipsList.visible = true;

					orbitalsList.visible = false;
					orbitalsButton.pressed = false;
					buildingsList.visible = false;
					buildingsButton.pressed = false;
					modulesList.visible = false;
					modulesButton.pressed = false;
					constructionsList.visible = false;
					constructionsButton.pressed = false;
					updateAbsolutePosition();
				}
				else if(evt.caller is modulesButton) {
					modulesButton.pressed = true;
					modulesList.visible = true;

					orbitalsList.visible = false;
					orbitalsButton.pressed = false;
					buildingsList.visible = false;
					buildingsButton.pressed = false;
					shipsList.visible = false;
					shipsButton.pressed = false;
					constructionsList.visible = false;
					constructionsButton.pressed = false;
					updateAbsolutePosition();
				}
				else if(evt.caller is constructionsButton) {
					constructionsList.visible = true;
					constructionsButton.pressed = true;

					orbitalsList.visible = false;
					orbitalsButton.pressed = false;
					buildingsList.visible = false;
					buildingsButton.pressed = false;
					shipsList.visible = false;
					shipsButton.pressed = false;
					modulesList.visible = false;
					modulesButton.pressed = false;
					updateAbsolutePosition();
				}
			break;
		}
		return DisplayBox::onGuiEvent(evt);
	}
};

class OrbitalTarget : PointTargeting {
	Object@ obj;
	Object@ constructFrom;
	const OrbitalModule@ def;
	const Design@ dsg;
	bool wasShifted;

	OrbitalTarget(Object@ obj, const OrbitalModule@ mod, const Design@ dsg = null, bool wasShifted = false, Object@ constructFrom = null) {
		@this.obj = obj;
		this.wasShifted = wasShifted;
		@this.dsg = dsg;
		@this.constructFrom = constructFrom;
		@def = mod;
		if(dsg !is null)
			icon = dsg.icon;
		else if(def.icon.valid)
			icon = def.icon;
		else
			icon = icons::Labor;
	}

	bool valid(const vec3d& pos) override {
		if(wasShifted && !shiftKey) {
			cancelTargeting();
			return false;
		}
		if(constructFrom !is null) {
			if(!canBuildOrbital(constructFrom, pos, true))
				return false;
		}
		else {
			if(!canBuildOrbital(obj, pos, true))
				return false;
		}
		if(def !is null) {
			if(!def.canBuildBy(obj))
				return false;
			if(!def.canBuildAt(obj, pos))
				return false;
		}
		return true;
	}

	void call(const vec3d& pos) override {
		if(dsg !is null)
			obj.buildStation(dsg, pos, frame=hoveredObject, constructFrom=constructFrom);
		else
			obj.buildOrbital(def.id, pos, frame=hoveredObject, constructFrom=constructFrom);
		if(shiftKey)
			targetPoint(OrbitalTarget(obj, def, dsg, true, constructFrom=constructFrom));
	}

	string message(const vec3d& pos, bool valid) {
		if(dsg !is null)
			return dsg.name;
		return def.name;
	}

	string desc(const vec3d& pos, bool valid) {
		if(valid) {
			double laborCost = 0;
			if(dsg !is null) {
				laborCost = getLaborCost(dsg);
				if(dsg.hasTag(ST_Station))
					laborCost *= obj.owner.OrbitalLaborCostFactor;
			}
			else if(def !is null)
				laborCost = def.laborCost * obj.owner.OrbitalLaborCostFactor;
			double laborIncome = max(obj.laborIncome, 0.01);

			Orbital@ orbFrame = cast<Orbital>(hoveredObject);
			if(orbFrame !is null && orbFrame.getValue(OV_FRAME_Usable) == 0.0)
				@orbFrame = null;
			if(orbFrame !is null && orbFrame.owner !is obj.owner)
				@orbFrame = null;

			double penFact = 1.0;
			if(orbFrame !is null) {
				laborCost *= orbFrame.getValue(OV_FRAME_LaborFactor);
				penFact = orbFrame.getValue(OV_FRAME_LaborPenaltyFactor);
			}

			TradePath path(obj.owner);
			Region@ target = getRegion(pos);
			if(target is null)
				return "";
			path.generate(getSystem(obj.region), getSystem(target));
			laborCost *= 1.0 + config::ORBITAL_LABOR_COST_STEP * penFact * double(path.pathSize - 1);

			return toString(laborCost,0)+" "+locale::RESOURCE_LABOR+", "+formatTime(laborCost / laborIncome);
		}
		Region@ reg = getRegion(pos);
		if(reg is null)
			return locale::OERR_SYSTEM;
		if(reg.MemoryMask & obj.owner.mask == 0 && reg.VisionMask & obj.owner.visionMask == 0)
			return locale::OERR_VISION;
		if(def !is null) {
			for(uint i = 0, cnt = def.hooks.length; i < cnt; ++i) {
				if(!def.hooks[i].canBuildBy(obj) || !def.hooks[i].canBuildAt(obj, pos))
					return def.hooks[i].getBuildError(obj, pos);
			}
		}
		return locale::OERR_TRADE;
	}
};

class ConstructionTargetPoint : PointTargeting {
	Object@ obj;
	const ConstructionType@ def;
	Targets targets;
	bool wasShifted = false;

	ConstructionTargetPoint(Object@ obj, const ConstructionType@ type, bool wasShifted = false) {
		@this.obj = obj;
		@def = type;
		targets = type.targets;
		this.wasShifted = wasShifted;
	}

	bool valid(const vec3d& pos) override {
		if(wasShifted && !shiftKey) {
			cancelTargeting();
			return false;
		}
		targets[0].filled = true;
		targets[0].point = pos;
		return def.canBuild(obj, targets);
	}

	void call(const vec3d& pos) override {
		obj.buildConstruction(def.id, pointTarg=pos);
		if(shiftKey)
			targetPoint(ConstructionTargetPoint(obj, def, wasShifted=true));
	}

	string message(const vec3d& pos, bool valid) {
		return def.name;
	}

	string desc(const vec3d& pos, bool valid) {
		if(valid)
			return def.formatCosts(obj, targets);
		return def.getTargetError(obj, targets);
	}
};

class ConstructionTargetObject : ObjectTargeting {
	Object@ obj;
	const ConstructionType@ def;
	Targets targets;
	bool wasShifted = false;

	ConstructionTargetObject(Object@ obj, const ConstructionType@ type, bool wasShifted = false) {
		@this.obj = obj;
		@def = type;
		targets = type.targets;
		this.wasShifted = wasShifted;
	}

	bool valid(Object@ target) override {
		if(wasShifted && !shiftKey) {
			cancelTargeting();
			return false;
		}
		targets[0].filled = true;
		@targets[0].obj = target;
		return def.canBuild(obj, targets);
	}

	void call(Object@ target) override {
		obj.buildConstruction(def.id, objTarg=target);
		if(shiftKey)
			targetObject(ConstructionTargetObject(obj, def, wasShifted=true));
	}

	string message(Object@ target, bool valid) {
		return def.name;
	}

	string desc(Object@ target, bool valid) {
		if(valid)
			return def.formatCosts(obj, targets);
		return def.getTargetError(obj, targets);
	}
};

const string slashStr("/");
class BuildElement : GuiListElement {
	const Design@ dsg;
	const OrbitalModule@ orb;
	const BuildingType@ building;
	const ConstructionType@ construction;
	Object@ buildAt;
	Color color;
	string nameText;
	string costText;
	string maintainText;
	string ttText;
	string timeText;
	string laborText;
	string energyText;
	Sprite icon;
	Color nameColor;
	Color iconColor = colors::White;
	bool isSupport = false;
	bool incomplete = false;
	array<Sprite> extraIcons;
	array<string> extraCosts;


	BuildElement(ConstructionDisplay@ disp, const Design@ Dsg, Object@ at) {
		@dsg = Dsg;
		@buildAt = at;
		update(disp);
	}

	BuildElement(ConstructionDisplay@ disp, const OrbitalModule@ Orb, Object@ at) {
		@orb = Orb;
		@buildAt = at;
		update(disp);
	}

	BuildElement(ConstructionDisplay@ disp, const BuildingType@ Type, Object@ at) {
		@building = Type;
		@buildAt = at;
		update(disp);
	}

	BuildElement(ConstructionDisplay@ disp, const ConstructionType@ Type, Object@ at) {
		@construction = Type;
		@buildAt = at;
		update(disp);
	}

	string get_tooltipText() {
		return ttText;
	}

	int opCmp(const GuiListElement@ other) const {
		const BuildElement@ be = cast<const BuildElement@>(other);
		if(be is null)
			return 0;
		if(dsg !is null) {
			if(be.dsg is null)
				return 0;
			if(dsg.size > be.dsg.size)
				return 1;
			if(dsg.size < be.dsg.size)
				return -1;
		}
		else if(orb !is null) {
			if(orb.totalRequirementCount > be.orb.totalRequirementCount)
				return 1;
			if(orb.totalRequirementCount < be.orb.totalRequirementCount)
				return -1;
			if(orb.buildCost > be.orb.buildCost)
				return 1;
			if(orb.buildCost < be.orb.buildCost)
				return -1;
		}
		else if(building !is null) {
			if(building.laborCost > be.building.laborCost)
				return -1;
			if(building.laborCost < be.building.laborCost)
				return 1;
			if(building.buildCostEst > be.building.buildCostEst)
				return 1;
			if(building.buildCostEst < be.building.buildCostEst)
				return -1;
			if(building.maintainCostEst > be.building.maintainCostEst)
				return 1;
			if(building.maintainCostEst < be.building.maintainCostEst)
				return -1;
		}
		return 0;
	}

	void update(ConstructionDisplay@ disp) {
		int build = 0, maintain = 0;
		double labor = 0, time = 0, energy = 0;
		bool hasError = false, hasWarning = false;
		extraIcons.length = 0;
		extraCosts.length = 0;

		if(dsg !is null) {
			nameText = dsg.name+" ("+toString(dsg.size, 0)+")";
			ttText = "";
			getBuildCost(dsg, build, maintain, labor, -1, buildAt);
			icon = dsg.icon;

			double multiply = 1.0;
			if(dsg.hasTag(ST_Support)) {
				build *= 10;
				maintain *= 10;
				labor *= 10;
				multiply = 10.0;
				isSupport = true;
				iconColor = dsg.color;
			}
			else if(dsg.hasTag(ST_Station)) {
				labor *= buildAt.owner.OrbitalLaborCostFactor;
				build *= buildAt.owner.OrbitalBuildCostFactor;
			}
			else {
				isSupport = false;
				iconColor = dsg.dullColor;
			}

			for(uint i = 0, cnt = getCargoTypeCount(); i < cnt; ++i) {
				auto@ cargo = getCargoType(i);
				if(int(cargo.variable) == -1)
					continue;
				double amt = dsg.total(cargo.variable) * multiply;
				if(amt > 0) {
					extraIcons.insertLast(cargo.icon);
					extraCosts.insertLast(standardize(amt, true));
					if(buildAt is null || !buildAt.hasCargo || buildAt.getCargoStored(cargo.id) < amt)
						hasError = true;
				}
			}

			{
				double energyCost = dsg.total(SV_EnergyBuildCost);
				if(energyCost > 0) {
					extraIcons.insertLast(icons::Energy);
					extraCosts.insertLast(standardize(energyCost, true));
					if(buildAt is null || buildAt.owner.EnergyStored < energyCost)
						hasError = true;
				}
			}

			{
				int influenceCost = dsg.total(SV_InfluenceBuildCost);
				if(influenceCost > 0) {
					extraIcons.insertLast(icons::Influence);
					extraCosts.insertLast(toString(influenceCost, 0));
					if(buildAt is null || buildAt.owner.Influence < influenceCost)
						hasError = true;
				}
			}

			{
				double ftlCost = dsg.total(SV_FTLBuildCost);
				if(ftlCost > 0) {
					extraIcons.insertLast(icons::FTL);
					extraCosts.insertLast(standardize(ftlCost, true));
					if(buildAt is null || buildAt.owner.FTLStored < ftlCost)
						hasError = true;
				}
			}
		}
		else if(orb !is null) {
			color = Color(0xffffffff);
			nameText = orb.name;
			ttText = orb.getTooltip();
			build = orb.buildCost;
			build *= buildAt.constructionCostMod;
			build *= buildAt.owner.OrbitalBuildCostFactor;
			labor = orb.laborCost;
			labor *= buildAt.owner.OrbitalLaborCostFactor;
			maintain = orb.maintenance;
			energy = 0;
			icon = orb.icon;
			isSupport = false;

			if(!orb.canBuildBy(buildAt, ignoreCost=false))
				hasError = true;

			Sprite exIcon; string exCost;
			for(uint i = 0, cnt = orb.hooks.length; i < cnt; ++i) {
				if(orb.hooks[i].getCost(buildAt, exCost, exIcon)) {
					extraCosts.insertLast(exCost);
					extraIcons.insertLast(exIcon);
				}
			}
		}
		else if(building !is null) {
			nameText = building.name;
			build = building.buildCostEst * buildAt.owner.BuildingCostFactor;
			build *= buildAt.constructionCostMod;
			maintain = building.maintainCostEst;
			if(building.laborCost > 0)
				labor = building.laborCost;
			else
				time = building.getBuildTime(buildAt) / (buildAt.buildingConstructRate * buildAt.owner.BuildingConstructRate * buildAt.owner.ImperialBldConstructionRate);
			icon = building.sprite;
			iconColor = colors::White;
			isSupport = false;

			ttText = building.getTooltip(valueObject=buildAt, isOption=true);

			if(!building.canBuildOn(buildAt))
				hasError = true;

			Sprite exIcon; string exCost;
			for(uint i = 0, cnt = building.hooks.length; i < cnt; ++i) {
				if(building.hooks[i].getCost(buildAt, exCost, exIcon)) {
					extraCosts.insertLast(exCost);
					extraIcons.insertLast(exIcon);
				}
			}
		}
		else if(construction !is null) {
			nameText = construction.name;
			build = construction.getBuildCost(buildAt);
			maintain = construction.getMaintainCost(buildAt);
			labor = construction.getLaborCost(buildAt);
			time = construction.getTimeCost(buildAt);
			icon = construction.icon;
			iconColor = colors::White;
			isSupport = false;
			ttText = construction.formatTooltip(buildAt);

			if(!construction.canBuild(buildAt, null))
				hasError = true;

			Sprite exIcon; string exCost;
			for(uint i = 0, cnt = construction.hooks.length; i < cnt; ++i) {
				if(construction.hooks[i].getCost(buildAt, construction, null, exCost, exIcon)) {
					extraCosts.insertLast(exCost);
					extraIcons.insertLast(exIcon);
				}
			}
		}

		int borrow = build - playerEmpire.RemainingBudget;
		if(build > 0 && borrow > 0) {
			if(ttText.length != 0)
				ttText += "\n\n";
			if(playerEmpire.canBorrow(borrow)) {
				hasWarning = true;
				double rate = playerEmpire.BorrowRate;
				ttText += format(locale::NEED_BORROW,
					formatMoney(borrow), formatMoney(ceil(double(borrow) * rate)));
			}
			else {
				hasError = true;
				ttText += "[color=#f00]"+locale::CANNOT_BORROW+"[/color]";
			}
		}

		if(isSupport && !disp.isBuildingFlagship)
			nameColor = Color(0x999999ff);
		else if(hasError)
			nameColor = Color(0xff0000ff);
		else if(hasWarning)
			nameColor = Color(0xfdff00ff);
		else if(incomplete)
			nameColor = Color(0x999999ff);
		else
			nameColor = Color(0xffffffff);

		if(build != 0 || maintain != 0)
			costText = formatMoney(build);
		else
			costText.resize(0);
		if(maintain == 0)
			maintainText.resize(0);
		else
			maintainText = formatMoney(maintain);
		if(energy != 0)
			energyText = formatRate(energy);
		else
			energyText.resize(0);

		if(labor != 0) {
			laborText = standardize(labor, true);
			if(isSupport)
				timeText = formatTimeRate(labor, buildAt.laborIncome*(float(buildAt.supportBuildSpeed)/100.f));
			else
				timeText = formatTimeRate(labor, buildAt.laborIncome);
		}
		else if(time != 0) {
			laborText = "";
			timeText = formatTime(time);
		}
		else {
			laborText = "";
			timeText = "";
		}
	}

	void draw(GuiListbox@ ele, uint flags, const recti& pos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		const Font@ smallFont = ele.skin.getFont(FT_Small);

		//Background element
		ele.skin.draw(SS_BuildElement, flags, pos);

		//Icon
		int x = 4;
		if(icon.valid) {
			int isize = min(icon.size.width, 28);
			recti ipos = recti_area(vec2i(x,(30-isize)/2)+pos.topLeft, vec2i(isize, isize));
			if(dsg !is null && isSupport) {
				spritesheet::ResourceIconsSmallMods.draw(0, ipos.padded(-1));
				icon.draw(ipos.padded(3), iconColor);
			}
			else {
				icon.draw(ipos.aspectAligned(icon.aspect), iconColor);
			}
			x += isize+8;
		}

		//Time
		int tx = x;
		x = pos.width-2;

		//Labor
		if(laborText.length != 0) {
			if((costText.length == 0 && extraCosts.length < 4) || extraCosts.length == 0)
				x -= 120;
			else
				x -= 60;
			icons::Labor.draw(recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
			font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(92, 30)),
					horizAlign=0.0, vertAlign=0.5,
					text=laborText, ellipsis=locale::ELLIPSIS, color=colors::White);

			if(timeText.length != 0 && ((costText.length == 0 && extraCosts.length < 4) || extraCosts.length == 0)) {
				font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(92, 30)),
						horizAlign=1.0, vertAlign=0.5,
						text=timeText, ellipsis=locale::ELLIPSIS, color=colors::White);
			}
		}
		else if(timeText.length != 0) {
			x -= 120;
			spritesheet::ContextIcons.draw(1, recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
			font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(57, 30)),
					horizAlign=0.0, vertAlign=0.5,
					text=timeText, ellipsis=locale::ELLIPSIS, color=colors::White);
		}

		//Cost
		if(energyText.length != 0) {
			x -= 90;
			icons::Energy.draw(recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
			font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(62, 30)),
					horizAlign=0.0, vertAlign=0.5,
					text=energyText, ellipsis=locale::ELLIPSIS, color=colors::White);
		}

		if(costText.length != 0) {
			if(maintainText.length != 0) {
				x -= 135;
				icons::Money.draw(recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
				font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(92, 30)),
						horizAlign=0.0, vertAlign=0.5,
						text=costText, ellipsis=locale::ELLIPSIS, color=colors::White);
				font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(92, 30)),
						horizAlign=0.5, vertAlign=0.5,
						text=slashStr, ellipsis=locale::ELLIPSIS, color=colors::White);
				font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(92, 30)),
						horizAlign=1.0, vertAlign=0.5,
						text=maintainText, ellipsis=locale::ELLIPSIS, color=colors::White);
			}
			else {
				x -= 90;
				icons::Money.draw(recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
				font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(62, 30)),
						horizAlign=0.0, vertAlign=0.5,
						text=costText, ellipsis=locale::ELLIPSIS, color=colors::White);
			}
		}

		for(uint i = 0, cnt = extraCosts.length; i < cnt; ++i) {
			x -= 60;
			extraIcons[i].draw(recti_area(vec2i(x, 3)+pos.topLeft, vec2i(24, 24)));
			font.draw(pos=recti_area(vec2i(x+28, 0)+pos.topLeft, vec2i(32, 32)),
					horizAlign=0.0, vertAlign=0.5,
					text=extraCosts[i], ellipsis=locale::SHORT_ELLIPSIS, color=colors::White);
		}

		//Requirements
		if(orb !is null) {
			x = pos.width - 246;
			int cx = x;
			for(uint i = 0; i < TR_COUNT; ++i) {
				for(uint n = 0, ncnt = orb.affinities[i]; n < ncnt; ++n) {
					getTileResourceSprite(i).draw(
						recti_area(vec2i(cx, 3)+pos.topLeft, vec2i(24, 24)));
					cx += 24;
				}
			}
			for(uint i = 0, cnt = orb.requirements.length; i < cnt; ++i) {
				orb.requirements[i].icon.draw(
					recti_area(vec2i(cx, 3)+pos.topLeft, vec2i(24, 24)));
				cx += 24;
			}
		}

		//Name
		font.draw(pos=pos.padded(tx, 0, ((pos.width-2) - x), 0), vertAlign=0.5,
				text=nameText, ellipsis=locale::ELLIPSIS, color=nameColor);
	}
};

class QueueItem : BaseGuiElement {
	ConstructionDisplay@ display;
	Object@ obj;
	Constructible cons;
	Color color;
	string name;
	string timeText;
	float pct;
	bool first = false;
	SupportItem@[] supportItems;
	GuiButton@ cancelButton;

	vec2i dragStart;
	vec2i dragOffset;
	bool leftHeld = false;

	QueueItem(BaseGuiElement@ parent, ConstructionDisplay@ disp) {
		@display = disp;
		super(parent, recti(0, 0, 100, 32));
		updateAbsolutePosition();

		@cancelButton = GuiButton(this, Alignment(Right-32, Top+6, Right-5, Top+32));
		cancelButton.color = colors::Red;
		cancelButton.style = SS_IconButton;
		cancelButton.setIcon(icons::Remove);
		cancelButton.tooltip = locale::CANCEL_CONSTRUCTION;
	}

	void remove() override {
		BaseGuiElement::remove();
		@display = null;
	}

	void update(Constructible@ Cons, Object@ Obj) {
		@obj = Obj;
		cons = Cons;

		//Update construction data
		name = cons.name;
		if(cons.dsg !is null) {
			name += " ("+toString(cons.dsg.size, 0)+")";
			color = cons.dsg.dullColor;
		}

		double eta = cons.getETA(obj);
		if(eta == INFINITY)
			timeText = toString(cons.progress*100.f, 0.f)+"/"+toString(cons.percentage*100.f, 0.f)+"%";
		else
			timeText = formatTime(eta);
		pct = cons.progress;

		//Update support groups
		uint oldCnt = supportItems.length;
		uint newCnt = cons.groups.length;

		for(uint i = newCnt; i < oldCnt; ++i)
			supportItems[i].remove();
		supportItems.length = newCnt;

		int y = 32;
		for(uint i = 0; i < newCnt; ++i) {
			SupportItem@ ele = supportItems[i];
			if(ele is null) {
				@ele = SupportItem(this);
				@supportItems[i] = ele;
			}

			ele.update(cons.groups[i]);
			ele.position = vec2i(0, y);
			y += ele.size.height;
		}

		size = vec2i(size.width, y);
	}

	void updateAbsolutePosition() override {
		int w = parent.size.width;
		GuiPanel@ pn = cast<GuiPanel>(parent);
		if(pn !is null && pn.vert.visible)
			w -= 20;
		size = vec2i(w, size.height);
		BaseGuiElement::updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Mouse_Entered && display !is null) {
			@display.hoveredItem = this;
		}
		if(evt.type == GUI_Mouse_Left && display !is null) {
			if(!isAncestorOf(evt.caller) && display.hoveredItem is this)
				@display.hoveredItem = null;
		}
		if(evt.caller is cancelButton && evt.type == GUI_Clicked) {
			obj.cancelConstruction(cons.id);
			emitClicked();
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ caller) override {
		if(display is null)
			return true;
		if(event.type == MET_Button_Down) {
			if(event.button == 0) {
				leftHeld = true;
				dragStart = mousePos;
				dragOffset = mousePos - absolutePosition.topLeft;
			}
			return true;
		}
		if(event.type == MET_Moved){ 
			if(leftHeld) {
				if(dragStart.distanceTo(mousePos) > 5) {
					leftHeld = false;
					@display.draggingItem = this;
				}
				return true;
			}
		}
		if(event.type == MET_Button_Up) {
			if(event.button == 0) {
				if(leftHeld) {
					leftHeld = false;
					if(cons.dsg !is null)
						display.selectQueue(this);
					else
						display.selectQueue(null);
					return true;
				}
			}
			else if(event.button == 1) {
				if(caller is this) {
					obj.cancelConstruction(cons.id);
				}
				else {
					SupportItem@ it = cast<SupportItem>(caller);
					if(it !is null)
						obj.removeSupportShipConstruction(cons.id, it.dat.dsg, shiftKey ? it.dat.totalSize : 10);
				}
				emitClicked();
				return true;
			}
		}
		return BaseGuiElement::onMouseEvent(event, caller);
	}

	void draw(const recti& absPos) {
		const Font@ font = skin.getFont(FT_Normal);

		//Left panel (icon/size)
		skin.draw(SS_Field, SF_Normal, recti_area(
			absPos.topLeft, vec2i(38, 29)));

		if(cons.dsg !is null) {
			cons.dsg.icon.draw(recti_area(
				absPos.topLeft + vec2i(5, 0), vec2i(29, 29)), color);
		}
		else {
			Sprite icon = cons.icon;
			icon.draw(recti_area(
				absPos.topLeft + vec2i(5, 0), vec2i(29, 29)).aspectAligned(icon.aspect));
		}

		//Middle panel (progress/name)
		recti midBar = recti_area(absPos.topLeft + vec2i(40, 0), vec2i(absPos.width - 142, 29));
		skin.draw(SS_Field, SF_Normal, midBar);

		int w = (1.f - pct) * float(midBar.width - 4);
		drawRectangle(midBar.padded(2, 2, 2+w, 2), Color(0x474545aa));

		Color textColor(0xffffffff);
		if(!cons.started) {
			if(first)
				textColor = Color(0xff0000ff);
			else
				textColor = Color(0x999999ff);
		}
		font.draw(pos=midBar.padded(7, 0), text=name, color=textColor,
				horizAlign=0.0, vertAlign=0.5, stroke=colors::Black);

		//vec2i nameSize = font.getDimension(name);
		//drawResources(skin, absPos.topLeft + vec2i(80+nameSize.x, 3), cost, supplyCost);

		//Right panel (eta)
		skin.draw(SS_Field, SF_Normal, recti_area(
			absPos.botRight - vec2i(100, 29), vec2i(100, 29)));

		font.draw(pos=recti_area(absPos.botRight - vec2i(100, 29), vec2i(64, 29)),
				text=timeText, horizAlign=1.0, vertAlign=0.5, stroke=colors::Black);
	}

	void draw() override {
		//Selected box
		if(display.selQueue is this)
			drawRectangle(AbsolutePosition, Color(0x00808080));

		recti absPos = recti_area(AbsolutePosition.topLeft+vec2i(4,3), vec2i(AbsolutePosition.size.width-8, 29));
		draw(absPos);

		BaseGuiElement::draw();
	}
};

class SupportItem : BaseGuiElement {
	QueueItem@ item;
	GroupData dat;

	SupportItem(QueueItem@ parent) {
		@item = parent;
		super(parent, recti(0, 0, 100, 20));
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() override {
		size = vec2i(parent.size.width, 20);
		BaseGuiElement::updateAbsolutePosition();
	}

	void update(GroupData@ Dat) {
		dat = Dat;
	}

	void remove() override {
		@item = null;
		BaseGuiElement::remove();
	}

	void draw(const recti& absPos) {
		skin.draw(SS_Field, SF_Normal, absPos);

		recti ipos = recti_area(absPos.topLeft+vec2i(8, 2), vec2i(16, 16));
		spritesheet::ResourceIconsSmallMods.draw(0, ipos);
		dat.dsg.icon.draw(ipos.padded(2), dat.dsg.color);

		skin.draw(FT_Normal, absPos.topLeft+vec2i(32, 3), dat.dsg.name);
		skin.draw(FT_Normal, absPos.topLeft+vec2i(180, 3), toString(dat.amount)+"x");
		skin.draw(FT_Normal, absPos.topLeft+vec2i(260, 3), format("(+$1x)", toString(dat.ordered)), Color(0x80ff80ff));
	}

	void draw() override {
		recti absPos = AbsolutePosition.padded(72, 0, 76, 0);
		draw(absPos);

		BaseGuiElement::draw();
	}
};

class FlagshipDrydock : GuiMarkupContextOption {
	const Design@ dsg;
	Empire@ forEmpire;
	Object@ fromObj;

	FlagshipDrydock(Object@ obj, const Design@ dsg, Empire@ emp = playerEmpire) {
		@this.dsg = dsg;
		@this.forEmpire = emp;
		@this.fromObj = obj;
		super(format("[offset=10][color=$5][b]$2[/b][/color] [offset=260]([loc=SIZE/] $3)[/offset][/offset]",
				toString(dsg.color),
				dsg.name,
				standardize(dsg.size, true),
				getSpriteDesc(dsg.icon),
				toString(dsg.color.interpolate(colors::White, 0.5))),
				FT_Subtitle);
		icon = dsg.icon;
		icon.color = dsg.color;
	}

	void call(GuiContextMenu@ menu) {
		FinanceDryDock(dsg, fromObj);
	}

	int opCmp(const GuiListElement@ other) const {
		auto@ cmp = cast<const FlagshipDrydock@>(other);
		if(cmp.dsg.size < dsg.size)
			return 1;
		if(cmp.dsg.size > dsg.size)
			return -1;
		return 0;
	}
};
