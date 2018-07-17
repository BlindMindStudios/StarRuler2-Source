#priority init 1501
import maps;

#section game
import dialogue;
#section all

#section server
import object_creation;
import systems;
import ship_groups;
import warandpeace;
import influence_global;
from cheats import setCheatsEnabled;
#section shadow
import systems;
#section all

const string SHIPSET = "ALL";
const string FOLDER = modProfile["designs"];
//const string FOLDER = "data/designs/pirates";
const bool OBSOLETE_DEFAULT = false;
const bool ENABLE_DISABLED = false;

Sandbox _map;
class Sandbox : Map {
	Sandbox() {
		super();

		isListed = false;
		isScenario = true;
	}

#section server
	void prepareSystem(SystemData@ data, SystemDesc@ desc) {
		@data.homeworlds = null;
		Map::prepareSystem(data, desc);
	}

	bool canHaveHomeworld(SystemData@ data, Empire@ emp) {
		return false;
	}

	void preGenerate() {
		Map::preGenerate();
		radius = 40000;
	}

	void placeSystems() {
		//Enemy gate system (Odatak)
		addSystem(vec3d(0, 0, 0), code=SystemCode()
			<< "NameSystem(Sandbox)"
			<< "MakeStar(Temperature = 5778, Radius = 75)"
			<< "ExpandSystem(2000)"
		);
	}

	void modSettings(GameSettings& settings) {
		settings.empires.length = 2;
		settings.empires[0].name = "Player";
		settings.empires[0].shipset = SHIPSET;
		settings.empires[1].name = "Enemy";
		settings.empires[1].shipset = "Gevron";
		settings.empires[1].type = ET_NoAI;
		config::ENABLE_UNIQUE_SPREADS = 0.0;
		config::DISABLE_STARTING_FLEETS = 1.0;
		config::ENABLE_DREAD_PIRATE = 0.0;
		config::ENABLE_INFLUENCE_EVENTS = 0.0;
		config::START_EXPLORED_MAP = 1.0;
	}

	void init() {
		Region@ system = getSystem(0).object;
		Empire@ player = getEmpire(0);
		Empire@ enemy = getEmpire(1);

		@player.shipset = getShipset(SHIPSET);
		
		player.Victory = -2;
		enemy.Victory = -2;

		player.modFTLCapacity(+1000000);
		enemy.modFTLCapacity(+1000000);

		player.modEnergyStored(+100000);
		enemy.modEnergyStored(+100000);

		player.modEnergyIncome(+500);
		enemy.modEnergyIncome(+500);

		player.setHostile(enemy, true);
		enemy.setHostile(player, true);

		player.ContactMask = int(~0);
		enemy.ContactMask = int(~0);

		player.visionMask |= enemy.mask;
		enemy.visionMask |= player.mask;

		system.grantVision(player);
		system.grantVision(enemy);

		for(uint i = 0, cnt = getSubsystemDefCount(); i < cnt; ++i) {
			auto@ def = getSubsystemDef(i);
			if(ENABLE_DISABLED || !def.hasTag("Disabled")) {
				if(def.hasTag("HeraldsDLC") && !hasDLC("Heralds"))
					continue;

				player.setUnlocked(def, true);
				enemy.setUnlocked(def, true);
				
				for(uint n = 0, ncnt = def.moduleCount; n < ncnt; ++n) {
					auto@ mod = def.modules[n];
					if(mod.hasTag("Disabled"))
						continue;
					if(mod.hasTag("HeraldsDLC") && !hasDLC("Heralds"))
						continue;
					player.setUnlocked(def, mod, true);
					enemy.setUnlocked(def, mod, true);
				}
			}
		}

		setCheatsEnabled(HOST_PLAYER, true);
	}
	
	int empTickIndex = 0;

	bool initialized = false;
	array<GroupData> groups;
	void tick(double time) {
		Region@ system = getSystem(0).object;
		Empire@ player = getEmpire(0);
		Empire@ enemy = getEmpire(1);

		if(!initialized) {
			guiDialogueAction(CURRENT_PLAYER, "Sandbox.Sandbox::SetupGUI");
			initialized = true;
		}

		int money = INT_MAX>>1;
		{
			int i = (empTickIndex++) % 2;
			Empire@ emp = getEmpire(i);

			//Make sure we have lodsamone
			if(emp.RemainingBudget < money/2)
				emp.addBonusBudget(money);
			if(emp.FTLStored < 500000)
				emp.modFTLStored(+500000);

			//Automatically spawn any ordered support ships on fleets
			uint SPAWN_LIMIT = 10;
			for(uint i = 0, cnt = emp.fleetCount; i < cnt && SPAWN_LIMIT > 0; ++i) {
				Ship@ fleet = cast<Ship>(emp.fleets[i]);
				if(fleet is null)
					continue;
				if(!fleet.hasOrderedSupports)
					continue;

				groups.syncFrom(fleet.getSupportGroups());
				for(uint n = 0, ncnt = groups.length; n < ncnt; ++n) {
					auto@ grp = groups[n];
					while(grp.ordered > 0 && SPAWN_LIMIT > 0) {
						Ship@ ship = createShip(fleet.position, grp.dsg, fleet.owner, groupLeader=null, free=true);
						fleet.supportBuildFinished(0, grp.dsg, null, ship);
						--grp.ordered;
						--SPAWN_LIMIT;
					}
				}
			}

			if(emp.player !is null) {
				emp.player.controlMask |= player.mask | enemy.mask;
				emp.player.viewMask |= player.mask | enemy.mask;
			}
		}

		//Make sure we always accept peace
		Lock lck(influenceLock);
		for(uint i = 0, cnt = activeTreaties.length; i < cnt; ++i) {
			if(activeTreaties[i].inviteMask & enemy.mask != 0)
				joinTreaty(enemy, activeTreaties[i].id);
		}
	}
#section shadow
	bool initialized = false;
	void tick(double time) {
		Region@ system = getSystem(0).object;
		Empire@ player = getEmpire(0);
		Empire@ enemy = getEmpire(1);

		if(!initialized && playerEmpire.valid) {
			CURRENT_PLAYER.controlMask |= player.mask | enemy.mask;
			CURRENT_PLAYER.viewMask |= player.mask | enemy.mask;

			guiDialogueAction("Sandbox.Sandbox::SetupGUI");
			initialized = true;
		}
	}
#section all
};

#section gui
from tabs.tabbar import tabBar, globalBar, closeTab, tabs, newTab, ActiveTab, browseTab;
from tabs.DesignOverviewTab import createDesignOverviewTab, DesignOverview;
from tabs.DesignEditorTab import DesignEditor;
from tabs.GlobalBar import GlobalBar;
from tabs.GalaxyTab import GalaxyTab;
from tabs.HomeTab import HomeTab;
from community.Home import createCommunityHome;
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiDropdown;
import elements.GuiListbox;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.GuiContextMenu;
import dialogs.QuestionDialog;
import util.design_export;
from targeting.PointTarget import PointTargeting, targetPoint;
import icons;

uint LastExportedDesign = 0;
dictionary designFileNames;
class SetupGUI : DialogueAction {
	void call() {
		isSandbox = true;

		//Global bar
		auto@ gbar = cast<GlobalBar>(globalBar);
		gbar.container.visible = false;

		@ui = SandboxUI(gbar);

		//Tab bar
		tabBar.goButton.visible = false;
		tabBar.homeButton.visible = false;

		for(uint i = 1, cnt = tabs.length; i < cnt; ++i)
			closeTab(tabs[1]);
		tabs[0].locked = true;

		//Quickbar
		auto@ gtab = cast<GalaxyTab>(tabs[0]);
		gtab.quickbar.visible = false;

		//Obsolete old designs
		if(OBSOLETE_DEFAULT) {
			for(uint i = 0, cnt = playerEmpire.designCount; i < cnt; ++i) {
				auto@ dsg = playerEmpire.designs[i];
				dsg.setObsolete(true);
				obsoletedDesigns.insert(dsg.id);
			}
		}

		//Import designs
		FileList list(FOLDER, "*.design", true);
		uint cnt = list.length;
		for(uint i = 0; i < cnt; ++i) {
			DesignDescriptor desc;
			read_design(list.path[i], desc);

			string fname = list.basename[i];
			fname = fname.substr(0, fname.length - list.extension[i].length - 1);
			designFileNames.set(desc.name, fname);

			if(desc.hull is null)
				continue;
			if(!playerEmpire.shipset.hasHull(desc.hull))
				@desc.hull = getBestHull(desc, getHullTypeTag(desc.hull));
			const Design@ newDesign = makeDesign(desc);
			if(newDesign is null)
				continue;
			if(desc.settings !is null)
				newDesign.setSettings(desc.settings);
			const DesignClass@ cls = playerEmpire.getDesignClass(desc.className);
			const Design@ orig = playerEmpire.getDesign(desc.name);
			if(orig !is null)
				playerEmpire.changeDesign(orig, newDesign, cls);
			else
				playerEmpire.addDesign(cls, newDesign);
		}
		LastExportedDesign = playerEmpire.designCount;

		//Designs tabs
		newTab(createDesignOverviewTab());
		newTab(createCommunityHome());
		tabs[2].locked = true;
	}
};

class FlagshipElement : GuiMarkupContextOption {
	const Design@ dsg;
	Empire@ forEmpire;

	FlagshipElement(const Design@ dsg, Empire@ emp) {
		@this.dsg = dsg;
		@this.forEmpire = emp;
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
		targetPoint(FlagshipTarget(dsg, forEmpire));
	}

	int opCmp(const GuiListElement@ other) const {
		auto@ cmp = cast<const FlagshipElement@>(other);
		if(cmp.dsg.size < dsg.size)
			return 1;
		if(cmp.dsg.size > dsg.size)
			return -1;
		return 0;
	}
};

class FlagshipTarget : PointTargeting {
	const Design@ dsg;
	Empire@ emp;

	FlagshipTarget(const Design@ dsg, Empire@ emp) {
		@this.dsg = dsg;
		@this.emp = emp;
		icon = dsg.icon;
		allowMultiple = true;
	}

	string message(const vec3d& pos, bool valid) {
		return dsg.name;
	}

	void call(const vec3d& pos) {
		cheatSpawnFlagship(pos, dsg, emp);
	}

	Color get_color() {
		return emp.color;
	}
};

class ConfirmClear : QuestionDialogCallback {
	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			for(uint i = 0; i < 2; ++i) {
				Empire@ emp = getEmpire(i);
				uint objCnt = emp.objectCount;
				for(uint n = 0; n < objCnt; ++n)
					cheatDestroy(emp.objects[n]);
			}
		}
	}
};

const string str_Support = "Support";
class RootText : GuiText {
	RootText(IGuiElement@ ParentElement, Alignment@ Align, const string& Txt, FontType font = FT_Normal) {
		super(ParentElement, Align, Txt, font);
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) {
		return null;
	}
};

class SandboxUI : BaseGuiElement {
	GuiText@ myStr;
	GuiText@ vsLabel;
	GuiText@ theirStr;

	GuiButton@ warToggle;
	GuiSprite@ warIcon;
	GuiSprite@ peaceIcon;
	GuiSprite@ warArrow;
	GuiText@ warText;

	GuiButton@ allyButton;
	GuiButton@ enemyButton;
	GuiButton@ clearButton;
	
	GuiText@ descText;

	SandboxUI(IGuiElement@ parent) {
		super(parent, Alignment().fill());

		@myStr = GuiText(this, Alignment(Left+4, Top+4, Left+204, Bottom-5));
		myStr.color = getEmpire(0).color;
		myStr.vertAlign = 0.0;

		@vsLabel = GuiText(this, Alignment(Left+4, Top+3, Left+204, Bottom-5), locale::VS);
		vsLabel.color = Color(0xaaaaaaff);
		vsLabel.vertAlign = 0.5;
		vsLabel.horizAlign = 0.5;

		@theirStr = GuiText(this, Alignment(Left+4, Top+3, Left+204, Bottom-4));
		theirStr.color = getEmpire(1).color;
		theirStr.vertAlign = 0.9;
		theirStr.horizAlign = 1.0;

		@warToggle = GuiButton(this, Alignment(Right-204, Top+3, Right-4, Bottom-5));

		@warIcon = GuiSprite(warToggle, recti(), Sprite(material::StatusWar));
		@peaceIcon = GuiSprite(warToggle, recti(), Sprite(material::StatusPeace));

		@warArrow = GuiSprite(warToggle, recti_area(84,16, 32,32), Sprite(spritesheet::ContextIcons, 0));

		@warText = GuiText(warToggle, Alignment().padded(4));
		warText.stroke = Color(0x00000080);
		warText.font = FT_Bold;
		warText.vertAlign = 0.2;
		warText.horizAlign = 0.5;

		Empire@ otherEmp = playerEmpire is getEmpire(0) ? getEmpire(1) : getEmpire(0);

		int w = 160;
		@allyButton = GuiButton(this, Alignment(Left+0.5f-w-w/2-6, Top+5, Left+0.5f-w/2-6, Bottom-5));
		allyButton.text = locale::SPAWN_ALLIED;
		allyButton.color = colors::Green;
		allyButton.buttonIcon = Sprite(spritesheet::ShipIcons, 1, playerEmpire.color);

		@enemyButton = GuiButton(this, Alignment(Left+0.5f-w/2, Top+5, Left+0.5f+w/2, Bottom-5));
		enemyButton.text = locale::SPAWN_ENEMY;
		enemyButton.color = colors::Red;
		enemyButton.buttonIcon = Sprite(spritesheet::ShipIcons, 1, otherEmp.color);

		@clearButton = GuiButton(this, Alignment(Left+0.5f+w/2+6, Top+5, Left+0.5f+w+w/2+6, Bottom-5));
		clearButton.text = locale::SANDBOX_CLEAR;
		clearButton.color = colors::Orange;
		clearButton.buttonIcon = icons::Close;

		@descText = RootText(this, Alignment(Left+250, Bottom+4, Right-4, Bottom+74), locale::SANDBOX_DESC);
		descText.noClip = true;
		descText.font = FT_Bold;
		descText.color = Color(0xaaaaaaff);
		descText.stroke = colors::Black;
		descText.horizAlign = 1.0;

		updateAbsolutePosition();
	}

	void openContext(Empire@ forEmp) {
		GuiContextMenu menu(mousePos);
		menu.itemHeight = 36;
		menu.flexWidth = false;
		menu.width = 400;

		uint cnt = playerEmpire.designCount;
		for(uint i = 0; i < cnt; ++i) {
			auto@ dsg = playerEmpire.designs[i];
			if(dsg.obsolete || dsg.newer !is null || dsg.updated !is null)
				continue;
			if(dsg.hull.hasTag(str_Support))
				continue;
			menu.addOption(FlagshipElement(dsg, forEmp));
		}

		menu.list.sortDesc();
		menu.updateAbsolutePosition();
	}

	void update() {
		double str = getEmpire(0).TotalMilitary;
		double enemyStr = getEmpire(1).TotalMilitary;

		myStr.text = format("$1 $2",
				standardize(sqr(str) * 0.001, true),
				locale::STRENGTH);
		theirStr.text = format("$1 $2",
				standardize(sqr(enemyStr) * 0.001, true),
				locale::STRENGTH);

		if(str > enemyStr) {
			myStr.font = FT_Bold;
			theirStr.font = FT_Normal;
		}
		else if(enemyStr > str) {
			myStr.font = FT_Normal;
			theirStr.font = FT_Bold;
		}
		else {
			myStr.font = FT_Normal;
			theirStr.font = FT_Normal;
		}
	}

	double timer = 0.0;
	void tick(double time) {
		bool atWar = getEmpire(0).isHostile(getEmpire(1));
		if(atWar) {
			warText.text = locale::SANDBOX_WAR;
			warText.color = Color(0xff8080ff);
			warToggle.color = Color(0xff8080ff);

			warArrow.desc = Sprite(spritesheet::ContextIcons, 0);

			warIcon.rect = recti_area(6,4, 36,36);
			peaceIcon.rect = recti_area(174,20, 20,20);
		}
		else {
			warText.text = locale::SANDBOX_PEACE;
			warText.color = Color(0x80ff80ff);
			warToggle.color = Color(0x80ff80ff);

			warArrow.desc = Sprite(spritesheet::ContextIcons, 2);

			peaceIcon.rect = recti_area(158,4, 36,36);
			warIcon.rect = recti_area(6,20, 20,20);
		}

		timer += time;
		if(timer >= 0.5) {
			update();
			timer = 0.0;
		}

		descText.visible = cast<GalaxyTab>(ActiveTab) !is null;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Clicked) {
			Empire@ otherEmp = playerEmpire is getEmpire(0) ? getEmpire(1) : getEmpire(0);
			if(evt.caller is warToggle) {
				if(playerEmpire.isHostile(otherEmp))
					sendPeaceOffer(otherEmp);
				else
					declareWar(otherEmp);
				return true;
			}
			if(evt.caller is allyButton) {
				openContext(playerEmpire);
				return true;
			}
			if(evt.caller is enemyButton) {
				openContext(otherEmp);
				return true;
			}
			if(evt.caller is clearButton) {
				question(locale::SANDBOX_CONFIRM_CLEAR, ConfirmClear());
				return true;
			}
		}

		return BaseGuiElement::onGuiEvent(evt);
	}
};

SandboxUI@ ui;
bool isSandbox = false;
set_int obsoletedDesigns;
void deleteDesign(const Design@ design) {
	string fname;
	if(!designFileNames.get(design.name, fname))
		fname = design.name;
	string path = FOLDER+"/"+fname+".design";
	if(fileExists(path))
		deleteFile(path);
}
void exportDesign(const Design@ design) {
	string fname;
	if(!designFileNames.get(design.name, fname))
		fname = design.name;
	write_design(design, FOLDER+"/"+fname+".design", design.cls);
}
void tick(double time) {
	if(!isSandbox)
		return;

	//Make any home tabs into galaxy tabs
	for(uint i = 0, cnt = tabs.length; i < cnt; ++i) {
		auto@ tab = tabs[i];
		if(cast<HomeTab>(tab) !is null) {
			browseTab(tab, createDesignOverviewTab());
		}
	}

	//Update UI
	if(ui !is null)
		ui.tick(time);

	//Export any designs we have
	for(uint i = 0, cnt = playerEmpire.designCount; i < cnt; ++i) {
		auto@ dsg = playerEmpire.designs[i];
		if(dsg.updated !is null)
			continue;
		if(dsg.newer !is null) {
			if(!obsoletedDesigns.contains(dsg.id) && dsg.newer.name != dsg.name) {
				auto@ check = playerEmpire.getDesign(dsg.name);
				if(check is null || check.newer !is null || check.obsolete) {
					//Act as obsolete
					deleteDesign(dsg);
					obsoletedDesigns.insert(dsg.id);
				}
			}
			continue;
		}
		if(dsg.obsolete) {
			//Delete obsoleted designs
			if(!obsoletedDesigns.contains(dsg.id)) {
				deleteDesign(dsg);
				obsoletedDesigns.insert(dsg.id);
			}
		}
		else {
			//Export new designs
			if(i >= LastExportedDesign) {
				exportDesign(dsg);
			}
			//Re-export unobsoleted designs
			if(obsoletedDesigns.contains(dsg.id)) {
				exportDesign(dsg);
				obsoletedDesigns.erase(dsg.id);
			}
		}
	}
	LastExportedDesign = playerEmpire.designCount;
}
#section all
