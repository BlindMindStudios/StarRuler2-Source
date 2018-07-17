import elements.GuiContextMenu;
import tabs.Tab;
from tabs.tabbar import ActiveTab;
from obj_selection import selectedObject, selectedObjects, isSelected;
from overlays.AnomalyOverlay import AnomalyOverlay;
import resources;
import pickups;
import orbitals;
import abilities;
import util.icon_view;
import systems;
import constructions;

import dialogs.MessageDialog;
import dialogs.QuestionDialog;
import dialogs.InputDialog;

import void openSupportOverlay(Object@ obj, Object@ to) from "tabs.GalaxyTab";
import void openSupportOverlay(Object@ obj) from "tabs.GalaxyTab";
import bool switchToTab(TabCategory cat) from "tabs.tabbar";

const Sprite EXPORT_ARROW(spritesheet::ContextIcons, 0);
const Sprite COLONIZE_ICON(spritesheet::ContextIcons, 1);
const Sprite IMPORT_ARROW(spritesheet::ContextIcons, 2);
TradePath pathCheck;

#include "include/resource_constants.as"

bool playedSound = false;
void playOptionSound(const SoundSource@ sound) {
	if(sound is null || playedSound)
		return;
	
	playedSound = true;
	sound.play(priority=true);
}

const string tag_Weapon = "Weapon";
bool hasWeapons(Object@ obj) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return false;

	return ship.blueprint.design.hasTag(tag_Weapon);
}

class AutoColonize : MultiOption {
	void call(Object@ selected) {
		if(selected.isPlanet) {
			Empire@ owner = selected.visibleOwner;
			if(owner is null || !owner.valid) {
				playerEmpire.autoColonize(selected);
				playOptionSound(sound::generic_click);
			}
		}
	}
};

class AutoColonizeLevel : MultiOption {
	void call(Object@ selected) {
		if(selected.isPlanet && !selected.owner.valid) {
			playerEmpire.autoColonize(selected);
			auto@ resType = getResource(selected.primaryResourceType);
			if(resType !is null && resType.level > 0)
				playerEmpire.autoImportToLevel(selected, resType.level);
			playOptionSound(sound::generic_click);
		}
	}
};

class AutoColonizeSystem : MultiOption {
	bool level = false;
	AutoColonizeSystem(bool importLevel = false) {
		level = importLevel;
	}

	void call(Object@ selected) {
		Region@ region = cast<Region>(selected);
		if(selected.isStar)
			@region = selected.region;
		if(region !is null) {
			uint plCnt = region.planetCount;
			for(uint i = 0; i < plCnt; ++i) {
				Planet@ pl = region.planets[i];
				if(pl is null)
					continue;
				if(pl.owner is null || pl.owner.valid)
					continue;
				if(!pl.known)
					continue;
				playerEmpire.autoColonize(pl);
				if(level) {
					auto@ resType = getResource(pl.primaryResourceType);
					if(resType.level != 0)
						playerEmpire.autoImportToLevel(pl, resType.level);
				}
			}
			playOptionSound(sound::generic_click);
		}
	}
};

class CancelColonizeSystem : MultiOption {
	void call(Object@ selected) {
		Region@ region = cast<Region>(selected);
		if(selected.isStar)
			@region = selected.region;
		if(region !is null) {
			uint plCnt = region.planetCount;
			for(uint i = 0; i < plCnt; ++i) {
				Planet@ pl = region.planets[i];
				if(pl is null)
					continue;
				if(pl.owner is null || pl.owner.valid)
					continue;
				if(!pl.known)
					continue;
				if(!pl.isBeingColonized)
					continue;
				playerEmpire.cancelColonization(pl);
				playerEmpire.cancelAutoImportTo(pl);
				pl.exportResource(0, null);
			}
			playOptionSound(sound::generic_click);
		}
	}
};

class CancelAutoColonize : MultiOption {
	void call(Object@ selected) {
		if(selected.hasSurfaceComponent && selected.isBeingColonized) {
			playerEmpire.cancelColonization(selected);
			playerEmpire.cancelAutoImportTo(selected);
			selected.exportResource(0, null);
			playOptionSound(sound::generic_click);
		}
	}
}

class Colonize : MultiOption, QuestionDialogCallback {
	void call(GuiContextMenu@ menu) {
		if(selected.canSafelyColonize)
			MultiOption::call(menu);
		else
			question(locale::COLONIZE, locale::COLONIZE_UNSAFE_PROMPT,
				locale::COLONIZE, locale::CANCEL, this);
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes) {
			GuiContextMenu@ m;
			MultiOption::call(m);
		}
	}

	void call(Object@ obj) {
		if(selected is obj)
			return;
		if(selected !is null && selected.isPlanet && selected.owner.controlled) {
			selected.colonize(obj, 1.0);
			playOptionSound(sound::order_goto);
		}
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		if(!selected.canSafelyColonize)
			drawRectangle(absPos, Color(0xff900040));
		MultiOption::draw(ele, flags, absPos);
	}
};

class RepackOrbital : Option {
	void call() {
		/*cast<Orbital>(selected).repack();*/
		playOptionSound(sound::generic_click);
	}
};

class CancelColonize : MultiOption {
	void call(Object@ obj) {
		if(obj is selected)
			return;
		if(selected.isPlanet && selected.owner.controlled) {
			selected.stopColonizing(obj);
			playOptionSound(sound::generic_click);
		}
	}
};

class CancelColonizeTarget : Option {
	Object@ target;
	CancelColonizeTarget(Object@ target) {
		@this.target = target;
	}

	void call() {
		if(selected.isPlanet && selected.owner.controlled) {
			selected.stopColonizing(target);
			playOptionSound(sound::generic_click);
		}
	}
};

class MoveTo : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI) {
			Region@ region = clicked.region;
			if(clicked.isStar && region !is null)
				selected.addGotoOrder(region, shiftKey);
			else
				selected.addGotoOrder(clicked, shiftKey);
			playOptionSound(sound::order_move);
		}
	}
};

class OddityGate : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI) {
			selected.addOddityGateOrder(cast<Oddity>(clicked), shiftKey);
			playOptionSound(sound::order_gate);
		}
	}
};

class Rally : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasConstruction) {
			selected.rallyTo(clicked);
			playOptionSound(sound::order_move);
		}
	}
};

class ClearRally : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasConstruction) {
			selected.clearRally();
			playOptionSound(sound::order_move);
		}
	}
};

class Attack : SelectionOption {
	void call(Object@ selected) {
		selected.addAttackOrder(clicked, shiftKey);
		playOptionSound(sound::order_attack);
	}
};

class CaptureOption : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI && clicked.isPlanet) {
			selected.addCaptureOrder(cast<Planet>(clicked), shiftKey);
			playOptionSound(sound::order_attack);
		}
	}
};

class ProtectedOption : MultiOption {
	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		if(clicked.isProtected(playerEmpire))
			drawRectangle(absPos, Color(0x00c0ff40));
		MultiOption::draw(ele, flags, absPos);
	}
};

class PickUp : SingleSelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI && clicked.isPickup) {
			selected.addPickupOrder(cast<Pickup>(clicked), shiftKey);
			playOptionSound(sound::order_pickup);
		}
	}
};

class ScanAnomaly : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI && clicked.isAnomaly) {
			selected.addScanOrder(cast<Anomaly>(clicked), shiftKey);
			playOptionSound(sound::order_scan);
		}
	}
};

class InvestigateAnomaly : Option {
	void call() {
		if(clicked.isAnomaly) {
			AnomalyOverlay(ActiveTab, cast<Anomaly>(clicked));
			playOptionSound(sound::generic_click);
		}
	}
};

class TransferSupport : Option {
	void call() {
		if(clicked !is null && clicked !is selected)
			openSupportOverlay(selected, clicked);
		else
			openSupportOverlay(selected);
	}
};

class ClaimPlanet : Option {
	void call() {
		clicked.annex();
		playOptionSound(sound::order_attack);
	}
};

class RefreshOption : SelectionOption {
	void call(Object@ selected) {
		if(selected.hasLeaderAI) {
			selected.addRefreshOrder(clicked, shiftKey);
			playOptionSound(sound::order_refresh);
		}
	}
};

class ScuttleOrbital : Option, QuestionDialogCallback {
	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			cast<Orbital>(clicked).scuttle();
	}
	
	void call() {
		question(
			locale::SCUTTLE,
			format(locale::PROMPT_SCUTTLE, clicked.name),
			locale::SCUTTLE, locale::CANCEL,
			this).titleBox.color = Color(0xe00000ff);
	}
};

class ScuttleFlagship : Option, QuestionDialogCallback {
	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			cast<Ship>(clicked).scuttle();
	}
	
	void call() {
		question(
			locale::SCUTTLE,
			format(locale::PROMPT_SCUTTLE, clicked.name),
			locale::SCUTTLE, locale::CANCEL,
			this).titleBox.color = Color(0xe00000ff);
	}
};

class RetrofitOption : Option {
	Object@ constructAt;
	Object@ constructFrom;

	RetrofitOption(Object@ constructAt, Object@ constructFrom) {
		@this.constructAt = constructAt;
		@this.constructFrom = constructFrom;
	}

	void call() {
		selected.retrofitFleetAt(constructAt, constructFrom=constructFrom);
		playOptionSound(sound::order_refresh);
	}
};

class TerraformOption : Option, IInputDialogCallback {
	array<const ResourceType@> types;
	double laborFactor;
	double costFactor;

	void call() {
		@pathCheck.forEmpire = playerEmpire;
		pathCheck.generate(getSystem(selected.region), getSystem(clicked.region));
		if(!pathCheck.isUsablePath)
			return;

		laborFactor = 1.0 + config::TERRAFORM_COST_STEP * double(pathCheck.pathSize - 1);
		costFactor = selected.terraformCostMod * laborFactor;

		InputDialog@ dialog = InputDialog(this, null);
		dialog.addTitle(locale::TERRAFORM+" "+clicked.name);
		dialog.accept.text = locale::TERRAFORM;
		dialog.addSelection(locale::RESOURCE);

		for(uint i = 0, cnt = getResourceCount(); i < cnt; ++i) {
			const ResourceType@ res = getResource(i);
			if(res.terraformLabor > 0 && res.canTerraform(selected, clicked)) {
				dialog.addItem(format(locale::TERRAFORM_ITEM, res.name, formatMoney(
					res.terraformCost * costFactor), standardize(res.terraformLabor * laborFactor)));
				types.insertLast(res);
			}
		}

		addDialog(dialog);
		changeCallback(dialog);
	}

	void changeCallback(InputDialog@ dialog) {
		uint index = uint(dialog.getSelection(0));
		if(index < types.length)
			dialog.accept.disabled = !playerEmpire.canPay(types[index].terraformCost * costFactor);
		else
			dialog.accept.disabled = true;
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			uint index = uint(dialog.getSelection(0));
			if(index < types.length)
				selected.startTerraform(cast<Planet>(clicked), types[index].id);
		}
	}
};

class FinanceDryDock : Option, IInputDialogCallback {
	Object@ buildAt;
	const Design@ design;
	double curPct = 0.0;
	bool isFree = false;

	FinanceDryDock() {}
	FinanceDryDock(Object@ obj) {
		@selected = obj;
		call();
	}

	FinanceDryDock(const Design@ dsg, Object@ at) {
		@design = dsg;
		@buildAt = at;
		call();
	}

	void call() {
		Orbital@ orb = cast<Orbital>(selected);
		if(orb !is null) {
			@design = orb.getDesign(OV_DRY_Design);
			curPct = orb.getValue(OV_DRY_Financed);
			isFree = orb.getValue(OV_DRY_Free) != 0.0;
		}

		int price = getBuildCost(design);
		price = double(price) * config::DRYDOCK_BUILDCOST_FACTOR * playerEmpire.DrydockCostFactor;
		double have = playerEmpire.RemainingBudget;
		if(buildAt !is null)
			have -= 100.0;
		double remain = ceil((1.0 - curPct) * double(price));
		double maxPct = curPct + clamp(have / remain, 0.0, 1.0) * (1.0 - curPct);

		InputDialog@ dialog = InputDialog(this, null);
		dialog.addTitle(format(locale::FINANCE_DRY_DOCK, design.name));
		dialog.accept.text = locale::FINANCE;
		dialog.addSpinboxInput(locale::PERCENTAGE, defaultValue=max(maxPct*100.0,1.0),
			minValue=max(curPct*100.0,1.0), maxValue=100.0, decimals=0, step=5.0);
		dialog.addLabel("", FT_Medium, 0.5, true);

		addDialog(dialog);
		changeCallback(dialog);
	}

	void changeCallback(InputDialog@ dialog) {
		double nextPct = dialog.getSpinboxInput(0) / 100.0;

		int price = ceil(double(getBuildCost(design) * config::DRYDOCK_BUILDCOST_FACTOR) * (nextPct - curPct) * playerEmpire.DrydockCostFactor);
		if(buildAt !is null)
			price += 100;
		int maintain = ceil(double(getMaintenanceCost(design)) * (nextPct - curPct));
		if(isFree)
			maintain = 0;
		dialog.accept.disabled = !playerEmpire.canPay(price);
		dialog.setLabel(1, formatMoney(price, maintain));
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			double pct = dialog.getSpinboxInput(0) / 100.0;
			Orbital@ orb = cast<Orbital>(selected);
			if(orb is null)
				buildAt.buildDryDock(design, pct);
			else
				orb.sendValue(OV_DRY_Financed, pct);
		}
	}
};

class WorkDryDock : Option {
	void call() {
		selected.workDryDock(cast<Orbital>(clicked));
		playOptionSound(sound::order_goto);
	}
};

class ExportLabor : SelectionOption {
	void call(Object@ selected) {
		selected.exportLaborTo(clicked);
		playOptionSound(sound::order_goto);
	}
};

class SetDefending : Option {
	Object@ obj;
	bool val;
	SetDefending(Object@ obj, bool value) {
		@this.obj = obj;
		this.val = value;
	}

	void call() {
		playerEmpire.setDefending(obj, val);
		playOptionSound(sound::order_refresh);
	}
};

class ExportResource : Option {
	Object@ from;
	Object@ to;
	const ResourceType@ type;
	uint index;

	ExportResource(Object@ From, Object@ To, const ResourceType@ Type, uint Index) {
		@from = From;
		@to = To;
		@type = Type;
		index = Index;
	}

	void call() {
		from.exportResource(index, to);
		playOptionSound(sound::order_goto);
	}

	int getWidth(GuiListbox@ ele) override {
		return Option::getWidth(ele) + 84;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();

		type.smallIcon.draw(recti_area(absPos.topLeft + vec2i(ele.horizPadding+3, (ele.lineHeight - 20) / 2), vec2i(20, 20)));
		EXPORT_ARROW.draw(recti_area(absPos.topLeft + vec2i(ele.horizPadding+26, (ele.lineHeight - 24) / 2), vec2i(24, 24)));
		drawObjectIcon(to, recti_area(absPos.topLeft + vec2i(ele.horizPadding+50, (ele.lineHeight - 26) / 2), vec2i(26, 26)));

		vec2i textOffset(ele.horizPadding+84, (ele.lineHeight - baseLine) / 2);
		font.draw(absPos.topLeft + textOffset, text);
	}
};

class ExportAnyResource : SelectionOption {
	void call(Object@ selected) {	
		if(selected.isPlanet) {
			if(selected !is clicked) {
				selected.exportResource(0, clicked);
				playOptionSound(sound::order_goto);
			}
		}
		else if(selected.isAsteroid) {
			if(selected.nativeResourceCount == 1) {
				selected.exportResource(0, clicked);
				playOptionSound(sound::order_goto);
			}
		}
	}
};

class BuildMiningBase : Option {
	uint resource;
	Object@ obj;
	Object@ slaved;

	BuildMiningBase(Object@ obj, uint resId, Object@ slaved = null) {
		@this.obj = obj;
		resource = resId;
		@this.slaved = slaved;
	}

	void call() {
		obj.buildAsteroid(cast<Asteroid>(clicked), resource, constructFrom=slaved);
		playOptionSound(sound::order_goto);
	}
};

class ImportResource : Option {
	Object@ from;
	Object@ to;
	const ResourceType@ type;
	uint index;

	ImportResource(Object@ From, Object@ To, const ResourceType@ Type, uint Index) {
		@from = From;
		@to = To;
		@type = Type;
		index = Index;
	}

	void call() {
		from.exportResource(index, to);
		playOptionSound(sound::generic_click);
	}

	int getWidth(GuiListbox@ ele) override {
		return Option::getWidth(ele) + 84;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();

		drawObjectIcon(to, recti_area(absPos.topLeft + vec2i(ele.horizPadding, (ele.lineHeight - 26) / 2), vec2i(26, 26)));
		IMPORT_ARROW.draw(recti_area(absPos.topLeft + vec2i(ele.horizPadding+26, (ele.lineHeight - 24) / 2), vec2i(24, 24)));
		type.smallIcon.draw(recti_area(absPos.topLeft + vec2i(ele.horizPadding+53, (ele.lineHeight - 20) / 2), vec2i(20, 20)));

		vec2i textOffset(ele.horizPadding+84, (ele.lineHeight - baseLine) / 2);
		font.draw(absPos.topLeft + textOffset, text);
	}
};

class AutoAssign : Option {
	const ResourceClass@ resCls;

	AutoAssign(const ResourceClass@ cls) {
		@resCls = cls;
	}

	void call() {
		playerEmpire.autoImportResourceOfClass(clicked, resCls.id);
		playOptionSound(sound::generic_click);
	}
};

class AutoAssignBoth : Option {
	const ResourceClass@ clsOne;
	const ResourceClass@ clsTwo;

	AutoAssignBoth(const ResourceClass@ one, const ResourceClass@ two) {
		@clsOne = one;
		@clsTwo = two;
	}

	void call() {
		playerEmpire.autoImportResourceOfClass(clicked, clsOne.id);
		playerEmpire.autoImportResourceOfClass(clicked, clsTwo.id);
		playOptionSound(sound::generic_click);
	}
};

class AutoAssignLevel : Option {
	uint level;

	AutoAssignLevel(uint level) {
		this.level = level;
	}

	void call() {
		playerEmpire.autoImportToLevel(clicked, level);
		playOptionSound(sound::generic_click);
	}
};

class CancelAutoAssign : Option {
	void call() {
		playerEmpire.cancelAutoImportTo(clicked);
		playOptionSound(sound::generic_click);
	}
}

class StopExportResource : SingleSelectionOption {
	uint index;

	StopExportResource(uint Index) {
		index = Index;
	}

	void call(Object@ selected) {
		selected.exportResource(index, null);
		playOptionSound(sound::generic_click);
	}
};

class StopImportResource : Option {
	uint index;

	StopImportResource(uint Index) {
		index = Index;
	}

	void call() {
		clicked.exportResource(index, null);
		playOptionSound(sound::generic_click);
	}
};

class Abandon : SingleSelectionOption, QuestionDialogCallback {
	Object@ planet;
	Abandon() {
	}

	void questionCallback(QuestionDialog@ dialog, int answer) {
		if(answer == QA_Yes)
			planet.abandon();
	}

	void call(Object@ selected) {
		@planet = selected;
		question(
			locale::ABANDON,
			format(locale::PROMPT_ABANDON, selected.name),
			locale::ABANDON_ACCEPT, locale::CANCEL,
			this).titleBox.color = Color(0xe00000ff);
	}
};

class TriggerAbility : SingleSelectionOption {
	int id;
	TriggerAbility(int ID) {
		id = ID;
	}

	void call(Object@ selected) {
		selected.activateAbility(id);
		playOptionSound(sound::order_attack);
	}
};

class TargetAbility : MultiOption {
	int id;
	Object@ target;
	double range;
	Color bg = colors::Invisible;
	const AbilityType@ type;

	TargetAbility(int ID, Object@ targ, double range, const AbilityType@ type) {
		id = ID;
		@target = targ;
		this.range = range;
		@this.type = type;
	}

	void call(Object@ obj) {
		if(obj is null || (!obj.isArtifact && !obj.owner.controlled) || !obj.hasAbilities)
			return;
		int ablId = -1;
		if(obj is this.selected) {
			ablId = id;
			playOptionSound(type.activateSound);
		}
		else {
			ablId = obj.findAbilityOfType(type.id);
		}
		if(ablId != -1) {
			if(!obj.hasLeaderAI || range == INFINITY)
				obj.activateAbility(id, target);
			else
				obj.addAbilityOrder(id, target, shiftKey);
		}
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		drawRectangle(absPos, bg);
		MultiOption::draw(ele, flags, absPos);
	}
};

class ConstructionOption : Option {
	const ConstructionType@ type;
	Object@ from;
	Targets targets;
	Color bg(0x00000000);

	ConstructionOption(const ConstructionType@ type, Object@ from, Targets@ targets) {
		@this.type = type;
		@this.from = from;
		this.targets = targets;
	}

	void call() {
		from.buildConstruction(type.id, objTarg=targets[0].obj);
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		drawRectangle(absPos, bg);
		Option::draw(ele, flags, absPos);
	}
};

bool openContextMenu(Object& clicked, Object@ selected = null) {
	//Play only one sound per context menu
	playedSound = false;

	if(selected is null)
		@selected = selectedObject;
	GuiContextMenu menu(mousePos);

	//Find the right visible owners
	Empire@ selOwner = null, clickedOwner = null;
	Region@ clickedRegion;
	if(selected !is null) {
		if(selected.hasSurfaceComponent)
			@selOwner = selected.visibleOwner;
		else
			@selOwner = selected.owner;
	}
	if(clicked !is null) {
		if(clicked.hasSurfaceComponent)
			@clickedOwner = clicked.visibleOwner;
		else
			@clickedOwner = clicked.owner;

		@clickedRegion = cast<Region>(clicked);
		if(clicked.isStar)
			@clickedRegion = clicked.region;
	}

	Orbital@ orbitalMaster;
	if(selected !is null && selected.isOrbital) {
		Orbital@ selOrb = cast<Orbital>(selected);
		if(selOrb.hasMaster())
			@orbitalMaster = selOrb.getMaster();
	}

	Object@ constructObj;
	Object@ constructSlave;
	if(orbitalMaster !is null && orbitalMaster.hasConstruction) {
		@constructObj = orbitalMaster;
		@constructSlave = selected;
	}
	else if(selected !is null && selected.hasConstruction)
		@constructObj = selected;


	//GuiContextMenu@ sub = menu.addSubMenu("Test");
	//sub.addOption("A");
	//sub.addOption("B");
	//sub.addOption("C");
	
	if(selected !is null && selOwner is playerEmpire && selected.hasLeaderAI && selected.isShip) {
		if(clicked.isAnomaly && cast<Anomaly>(clicked).progress < 1.f)
			addOption(menu, selected, clicked, locale::SCAN_ANOMALY, ScanAnomaly(), icons::Anomaly);
	}
	else if(clicked.isAnomaly) {
		addOption(menu, selected, clicked, locale::INVESTIGATE_ANOMALY, InvestigateAnomaly(), icons::Anomaly);
	}

	//Resource exporting
	if(selected !is null && selected.hasResources && clicked.hasResources) {
		if(selectedObjects.length > 1)
			addOption(menu, selected, clicked, format(locale::EXPORT_RESOURCES, clicked.name), ExportAnyResource());
		
		//Exports
		uint cnt = selected.nativeResourceCount;
		if(clicked is selected) {
			if(selected.owner is playerEmpire) {
				for(uint i = 0; i < cnt; ++i) {
					Object@ dest = selected.nativeResourceDestination[i];
					if(dest is null)
						continue;
					const ResourceType@ type = getResource(selected.nativeResourceType[i]);
					if(!type.exportable)
						continue;
					if(selected.nativeResourceLocked[i])
						continue;
					
					string text;
					
					if(selected.nativeResourceUsable[i] && dest.owner is playerEmpire)
						text = format(locale::STOP_EXPORT_RESOURCE, type.name, dest.name);
					else
						text = format(locale::STOP_EXPORT_RES_QUEUE, type.name, dest.name);
					addOption(menu, selected, clicked, text, StopExportResource(i), type.smallIcon);
				}
			}
		}
		else if(selected.exportEnabled && clicked.importEnabled
				&& (selected.region !is null && clicked.region !is null)) {
			for(uint i = 0; i < cnt; ++i) {
				const ResourceType@ type = getResource(selected.nativeResourceType[i]);
				if(!type.exportable)
					continue;
				if(selected.nativeResourceLocked[i])
					continue;

				bool usable = false;
				Object@ dest = selected.nativeResourceDestination[i];
				string text;

				if(selected.owner is playerEmpire)
					usable = selected.nativeResourceUsable[i];

				if(dest is clicked) {
					if(usable && clicked.owner is playerEmpire)
						text = format(locale::STOP_EXPORT_RESOURCE, type.name, dest.name);
					else
						text = format(locale::STOP_EXPORT_RES_QUEUE, type.name, dest.name);
					addOption(menu, selected, clicked, text, StopExportResource(i), type.smallIcon);
				}
				else {
					if(usable && clicked.owner is playerEmpire)
						text = format(locale::EXPORT_RESOURCE, type.name, clicked.name);
					else
						text = format(locale::QUEUE_EXPORT_RESOURCE, type.name, clicked.name);
					addOption(menu, selected, clicked, text, ExportResource(selected, clicked, type, i));
				}
			}
		}

		//Imports
		if(clicked !is selected) {
			if(selected.importEnabled && clicked.exportEnabled
					&& (selected.region !is null && clicked.region !is null)) {
				cnt = clicked.nativeResourceCount;
				for(uint i = 0; i < cnt; ++i) {
					const ResourceType@ type = getResource(clicked.nativeResourceType[i]);
					if(!type.exportable)
						continue;

					bool usable = false;
					Object@ dest = clicked.nativeResourceDestination[i];
					string text;

					if(clicked.owner is playerEmpire)
						usable = clicked.nativeResourceUsable[i];

					if(dest is selected) {
						if(usable && selected.owner is playerEmpire)
							text = format(locale::STOP_IMPORT_RESOURCE, type.name, clicked.name);
						else
							text = format(locale::STOP_IMPORT_RES_QUEUE, type.name, clicked.name);
						addOption(menu, selected, clicked, text, StopImportResource(i), type.smallIcon);
					}
					else {
						if(usable && selected.owner is playerEmpire)
							text = format(locale::IMPORT_RESOURCE, type.name, clicked.name);
						else
							text = format(locale::QUEUE_IMPORT_RESOURCE, type.name, clicked.name);
						addOption(menu, clicked, selected, text, ImportResource(clicked, selected, type, i));
					}
				}
			}
		}
	}

	//Auto-assign resources
	if(clicked.isPlanet && (clickedOwner is playerEmpire || clicked.isBeingColonized)) {
		if(clicked.hasAutoImports) {
			addOption(menu, selected, clicked, locale::CANCEL_AUTO_IMPORT, CancelAutoAssign());
		}
		else {
			uint clickedLevel = clicked.level;
			uint assignLevel = 0;
			auto@ resType = getResource(clicked.primaryResourceType);
			if(resType !is null) {
				if(clickedLevel > resType.level) {
					assignLevel = min(5, clickedLevel+1);
				}
				else if(clickedLevel == resType.level) {
					if(clicked.nativeResourceDestination[0] is null)
						assignLevel = clickedLevel+1;
					else
						assignLevel = 0;
				}
				else {
					assignLevel = resType.level;
				}
			}
			if(assignLevel != 0 && assignLevel > clickedLevel && assignLevel < uint(clicked.maxLevel)) {
				Sprite icon;
				if(assignLevel <= 3)
					icon = Sprite(spritesheet::ResourceClassIcons, clamp(assignLevel-1, 0, 2));

				addOption(menu, selected, clicked, format(locale::AUTO_IMPORT_LEVEL, toString(assignLevel)),
						AutoAssignLevel(assignLevel), icon);
			}
		}
	}

	//Colonization
	if(clicked.isPlanet && playerEmpire.NoAutoColonize == 0) {
		bool quarantined = clicked.quarantined;
		bool addedColonyOptions = false;
		
		if(selected !is null && selected.owner is playerEmpire && selected.isPlanet
				&& selected !is clicked && selected.maxPopulation > 1) {
			//Colonization from selected planet
			if(!selected.hasColonyTarget(clicked)) {
				if(clickedOwner is null || !clickedOwner.valid) {
					if(!quarantined) {
						addedColonyOptions = true;
						
						//TODO: Take slipstream & gate into account
						double eta = 1.0;
						eta += newtonArrivalTime(selected.colonyShipAccel, clicked.position - selected.position, vec3d()) / 60.0;
						if(selected.isColonizing)
							eta += double(selected.colonyOrderCount);
						if(selected.owner.HasFlux != 0)
							eta = 0;
						
						if(playerEmpire.ForbidColonization == 0) {
							if(eta <= 0)
								addOption(menu, selected, clicked, format(locale::COLONIZE_WITH_BASIC, selected.name), Colonize(), COLONIZE_ICON);
							else
								addOption(menu, selected, clicked, format(locale::COLONIZE_WITH, selected.name, toString(eta, 1)), Colonize(), COLONIZE_ICON);
						}
						
						if(clicked.isBeingColonized)
							addOption(menu, selected, clicked, locale::CANCEL_AUTO_COLONIZE, CancelAutoColonize());
					}
				}
				else if(clicked.owner is playerEmpire && clicked.population < 1) {
					if(playerEmpire.ForbidColonization == 0)
						addOption(menu, selected, clicked, locale::COLONIZE_CONTINUE, Colonize(), COLONIZE_ICON);
					addedColonyOptions = true;
				}
			}
			else {
				string text = format(locale::COLONIZE_CANCEL, clicked.name);
				addOption(menu, selected, clicked, text, CancelColonize());
				addedColonyOptions = true;
			}
		}
		
		if(!addedColonyOptions) {		
			//Auto-colonization
			if(clicked.isBeingColonized) {
				addOption(menu, selected, clicked, locale::CANCEL_AUTO_COLONIZE, CancelAutoColonize());
			}
			else {
				if(clickedOwner is null || !clickedOwner.valid) {
					addOption(menu, selected, clicked, quarantined ? locale::AUTO_COLONIZE_BLOCKED : locale::AUTO_COLONIZE, AutoColonize(), COLONIZE_ICON);

					auto@ resType = getResource(clicked.primaryResourceType);
					if(resType !is null && resType.level > 0) {
						addOption(menu, selected, clicked,
								format(locale::AUTO_COLONIZE_LEVEL, resType.level),
								AutoColonizeLevel(),
								Sprite(spritesheet::ResourceClassIcons, clamp(resType.level-1, 0, 2)));
					}
				}
			}
		}
	}

	if(selected !is null && selected.owner.controlled) {
		if(selected.isPlanet && clicked.isPlanet) {
			//Colonization order management
			if(selected is clicked) {
				uint colonyOrders = selected.colonyOrderCount;
				for(uint i = 0; i < colonyOrders; ++i) {
					Object@ target = selected.colonyTarget[i];
					if(target is null)
						break;
					string text = format(locale::COLONIZE_CANCEL, target.name);
					addOption(menu, selected, clicked, text, CancelColonizeTarget(target));
				}
			}
		}

		//Transfering support ships
		if(clicked !is null && clicked.owner is selected.owner) {
			if(selected.hasLeaderAI && selected.SupplyCapacity > 0) {
				if(selected is clicked) {
					addOption(menu, selected, clicked, locale::MANAGE_SUPPORTS, TransferSupport(), icons::ManageSupports);
				}
				else if(clicked.hasLeaderAI && clicked.SupplyCapacity > 0) {
					addOption(menu, selected, clicked, locale::TRANSFER_SUPPORT_SHIPS, TransferSupport(), icons::ManageSupports);
				}
			}
		}

		//Pickup goodies
		if(selected.hasLeaderAI && clicked.isPickup && selected.hasMover && selected.maxAcceleration > 0) {
			Pickup@ pickup = cast<Pickup>(clicked);
			const PickupType@ type = getPickupType(pickup.PickupType);

			Object@ prot = pickup.getProtector();
			if(prot !is null)
				addOption(menu, selected, prot, locale::ATTACK, Attack());
			if(shiftKey || (!pickup.isPickupProtected && type.canPickup(pickup, selected)))
				addOption(menu, selected, clicked, format(type.verb, type.name), PickUp());
		}

		//Combat options
		if(clickedOwner !is selected.owner && clickedOwner !is null && clickedOwner.valid) {
			Ship@ ship = cast<Ship>(selected);
			if(ship !is null && ship.hasLeaderAI) {
				const Design@ dsg = ship.blueprint.design;
				if(dsg !is null) {
					bool hasWeapons = dsg.hasTag(ST_Weapon);
					bool hasSupportAttack = ship.supportCount > 0 && ship.getFleetDPS() > 0;
					if((hasWeapons && ship.blueprint.canTarget(ship, clicked)) || (hasSupportAttack && (clicked.isShip || clicked.isOrbital)))
						addOption(menu, selected, clicked, locale::ATTACK, Attack(), icons::Strength);
				}
			}
		}

		if(selected.isShip && selected.hasLeaderAI && clicked.isPlanet
				&& clickedOwner !is null && clickedOwner.valid && clickedOwner !is playerEmpire) {
			if(playerEmpire.isHostile(clickedOwner) && !selected.hasOrbit) {
				if(clicked.isProtected(playerEmpire)) {
					addOption(menu, selected, clicked, locale::PROTECTED_OPTION, ProtectedOption(), icons::Strength * Color(0xff0000ff));
				}
				else {
					double base = clicked.baseLoyalty;
					double loy = clicked.currentLoyalty;
					double timer = config::SIEGE_LOYALTY_TIME * ceil(base / 10.0) * (loy / max(base, 1.0));
					timer *= selected.owner.CaptureTimeFactor;
					timer *= clicked.owner.CaptureTimeDifficulty;
					double cost = config::SIEGE_LOYALTY_SUPPLY_COST * loy;
					cost *= selected.owner.CaptureSupplyFactor;
					cost *= clicked.owner.CaptureSupplyDifficulty;
					addOption(menu, selected, clicked, format(locale::CAPTURE_OPTION, standardize(cost), formatTime(timer)), CaptureOption(), icons::Strength * Color(0xff8000ff));
				}
			}
		}

		//Movement options
		if(selected.hasMover && selected.hasLeaderAI && (!selected.hasOrbit || selected.maxAcceleration > 0)) {
			if(clicked !is null && clicked.isOddity && cast<Oddity>(clicked).isGate())
				addOption(menu, selected, clicked, locale::ODDITY_GATE, OddityGate());

			Object@ nameObj = clickedRegion is null ? @clicked : @clickedRegion;
			addOption(menu, selected, clicked, format(locale::MOVE_TO_OBJ, formatObjectName(nameObj)), MoveTo(),
					Sprite(spritesheet::ContextIcons, 0, Color(0xffcd00ff)));
		}
	}

	//System actions
	if(selected !is null && selected.owner is playerEmpire) {
		//Support resupply
		if(clicked !is null && selected.isShip && selected.hasLeaderAI) {
			if(clicked.isStar && clicked.region.AvailSupportMask & playerEmpire.mask != 0) {
				addOption(menu, selected, clicked.region, format(locale::REFRESH_SUPPORTS, clicked.region.name), RefreshOption(),
						icons::ManageSupports);
			}
			else if((clicked.isPlanet || (clicked.isOrbital && clicked.hasLeaderAI)) && clickedOwner is playerEmpire && clicked.supportCount > 0) {
				addOption(menu, selected, clicked, format(locale::REFRESH_SUPPORTS, clicked.name), RefreshOption(),
						icons::ManageSupports);
			}
		}

		//Asteroid base construction
		if(clicked !is null && constructObj !is null && constructObj.hasConstruction
			&& constructObj.canBuildAsteroids && clicked.isAsteroid &&
			cast<Asteroid>(clicked).canDevelop(playerEmpire)
			&& clicked.region !is null && constructObj.region !is null) {
	
			Object@ pathFrom = constructObj;
			if(constructSlave !is null && constructSlave.region !is null)
				@pathFrom = constructSlave;

			@pathCheck.forEmpire = playerEmpire;
			pathCheck.generate(getSystem(pathFrom.region), getSystem(clicked.region));

			if(pathCheck.isUsablePath) {
				double costFactor = 1.0 + config::ASTEROID_COST_STEP * double(pathCheck.pathSize - 1);
	
				Asteroid@ asteroid = cast<Asteroid>(clicked);
				for(uint i = 0, cnt = asteroid.getAvailableCount(); i < cnt; ++i) {
					uint resId = asteroid.getAvailable(i);
					double cost = asteroid.getAvailableCost(i);
					const ResourceType@ type = getResource(resId);
	
					if(type !is null && cost > 0.0)
						addOption(menu, selected, clicked,
								format(locale::BUILD_ASTEROID_OPTION,
										type.name, standardize(cost*costFactor, true)),
								BuildMiningBase(constructObj, resId, constructSlave),
								type.smallIcon);
				}
			}
		}

		//Terraforming
		if(clicked !is null && selected.hasConstruction
			&& selected.canTerraform && clicked.isPlanet
			&& clickedOwner is playerEmpire && !clicked.isTerraforming()
			&& clicked.region !is null && selected.region !is null
			&& clicked !is selected
			&& config::ENABLE_TERRAFORMING != 0
			&& playerEmpire.ForbidTerraform == 0) {

			@pathCheck.forEmpire = playerEmpire;
			pathCheck.generate(getSystem(selected.region), getSystem(clicked.region));
			if(pathCheck.isUsablePath)
				addOption(menu, selected, clicked, locale::TERRAFORM_OPTION, TerraformOption());
		}

		if(selected is clicked && selected.isPlanet) {
			//Abandon planet
			if(!selected.isContested)
				addOption(menu, selected, clicked, locale::ABANDON, Abandon(), icons::UnderSiege * colors::Red);
		}

		//Retrofit options
		if(selected.hasLeaderAI && clicked !is null && clicked.owner is playerEmpire
				&& selected.region !is null && selected.region is clicked.region) {

			//Figure out if we should redirect this
			Object@ constructFrom;
			Object@ constructAt;

			if(clicked.isOrbital) {
				Orbital@ orb = cast<Orbital>(clicked);
				if(orb.hasMaster()) {
					@constructAt = orb.getMaster();
					@constructFrom = clicked;
				}
				else {
					@constructAt = clicked;
				}
			}
			else {
				@constructAt = clicked;
			}

			if(constructAt.hasConstruction && constructAt.canBuildShips) {
				int cost = selected.getRetrofitCost();
				if(cost >= 0) {
					double labor = selected.getRetrofitLabor();
					addOption(menu, selected, clicked, format(locale::RETROFIT_OPTION, formatMoney(cost), standardize(labor, true)), RetrofitOption(constructAt, constructFrom));
				}
			}
		}
	}
	
	//System colonization
	if(clicked.isStar && playerEmpire.NoAutoColonize == 0) {
		Region@ region = clicked.region;
		if(region !is null) {
			//Check if there are any uncolonized planets
			uint plCnt = region.planetCount;
			bool hasUncolonized = false, hasUnderleveled = false, hasColonizing = false;
			for(uint i = 0; i < plCnt; ++i) {
				Planet@ pl = region.planets[i];
				if(pl is null)
					continue;
				if(pl.owner is null || pl.owner.valid)
					continue;
				if(!pl.known)
					continue;
				if(pl.isBeingColonized) {
					hasColonizing = true;
					continue;
				}
				hasUncolonized = true;
				auto@ resType = getResource(pl.primaryResourceType);
				if(resType !is null && resType.level != 0)
					hasUnderleveled = true;
			}

			if(hasUncolonized) {
				addOption(menu, selected, clicked, format(locale::AUTO_COLONIZE_SYSTEM, region.name), AutoColonizeSystem(), COLONIZE_ICON);
				if(hasUnderleveled)
					addOption(menu, selected, clicked, format(locale::AUTO_COLONIZE_SYSTEM_LEVEL, region.name), AutoColonizeSystem(true), Sprite(spritesheet::ResourceClassIcons, 7));
			}
			if(hasColonizing)
				addOption(menu, selected, clicked, format(locale::STOP_COLONIZE_SYSTEM, region.name), CancelColonizeSystem());
		}
	}

	//Defense projection
	if((selected is clicked && selected.owner is playerEmpire && selected.isPlanet)
			|| (clickedRegion !is null && clickedRegion.PlanetsMask & playerEmpire.mask != 0)
			|| (clickedOwner is playerEmpire && clicked.isOrbital && clicked.hasLeaderAI && clicked.region !is null && clicked.region.TradeMask & playerEmpire.TradeMask.value != 0 && clicked.SupplyCapacity > 0)
			|| playerEmpire.isDefending(clicked)) {
		Object@ obj = clickedRegion is null ? @clicked : @clickedRegion;
		bool isDefending = playerEmpire.isDefending(obj);
		if(isDefending) {
			Sprite sprt = icons::Defense;
			sprt.color = colors::Red;
			addOption(menu, selected, obj, format(locale::DEFENSE_OFF_OPTION, obj.name),
					SetDefending(obj, false), sprt);
		}
		else {
			addOption(menu, selected, clicked, format(locale::DEFENSE_ON_OPTION, obj.name),
					SetDefending(obj, true), icons::Defense);
		}
	}
	
	//Finance options
	if(clicked is selected && clicked.owner is playerEmpire) {
		Orbital@ orb = cast<Orbital>(clicked);
		if(orb !is null && orb.getDesign(OV_DRY_Design) !is null && orb.getValue(OV_DRY_Financed) < 1.f)
			addOption(menu, selected, clicked, locale::FINANCE_OPTION, FinanceDryDock());
	}
	else if(selected !is null && clicked !is null && clicked !is selected && selected.owner is playerEmpire && clicked.owner is playerEmpire) {
		Orbital@ orb = cast<Orbital>(clicked);
		if(orb !is null && orb.getDesign(OV_DRY_Design) !is null && selected.hasConstruction && selected.canBuildShips)
			addOption(menu, selected, clicked, locale::WORK_DRY_DOCK, WorkDryDock());
	}

	//Labor exporting
	if(selected !is null && selected.owner is playerEmpire && clickedOwner is playerEmpire
		&& selected.hasConstruction && selected.canExportLabor && clicked.hasConstruction && clicked.canImportLabor
		&& selected.laborIncome > 0) {
		addOption(menu, selected, clicked, format(locale::EXPORT_LABOR, clicked.name), ExportLabor(), icons::Labor);
	}
	
	//Rallying
	if(selected !is null && selected.owner is playerEmpire && selected.hasConstruction)
		if(selected.isRallying && (selected is clicked || selected.rallyObject is clicked))
			addOption(menu, selected, clicked, locale::STOP_RALLY, ClearRally(), COLONIZE_ICON);
		else if(selected.canBuildShips)
			addOption(menu, selected, clicked, format(locale::RALLY_TO, clicked.name), Rally(), COLONIZE_ICON);

	//Scuttle options
	if(clicked is selected && clicked.owner.controlled) {
		if(clicked.isOrbital && !cast<Orbital>(clicked).isContested)
			addOption(menu, selected, clicked, locale::SCUTTLE, ScuttleOrbital());
		else if(clicked.isShip && clicked.hasLeaderAI)
			addOption(menu, selected, clicked, locale::SCUTTLE, ScuttleFlagship());
	}

	//Abilities
	if(selected !is null && selected.hasAbilities
			&& (selected.owner.controlled || selected.isArtifact)) {
		array<Ability> abilities;
		abilities.syncFrom(selected.getAbilities());

		Targets targs;
		@targs.add(TT_Object, fill=true).obj = clicked;

		for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			Ability@ abl = abilities[i];
			if(abl.disabled)
				continue;
			if(selected.isArtifact)
				@abl.emp = playerEmpire;
			else
				@abl.emp = selected.owner;

			string option = format(locale::ABILITY_TRIGGER, abl.type.name);

			string costs = abl.formatCosts(targs);
			if(costs.length != 0)
				option += " ("+costs+")";
			if(abl.cooldown > 0)
				option += format(locale::ABILITY_CD, formatTime(abl.cooldown));
			else if(abl.type.cooldown > 0)
				option += format(locale::ABILITY_COOLDOWN, formatTime(abl.type.cooldown));

			if(abl.type.targets.length == 0) {
				if(selected !is clicked)
					continue;

				addOption(menu, selected, clicked, option,
					TriggerAbility(abl.id), abl.type.icon);
			}
			else if(abl.type.targets[0].type == TT_Object) {
				if(selected is clicked)
					continue;
				if(!abl.canActivate(targs, ignoreCost=true))
					continue;
				TargetAbility opt(abl.id, clicked, abl.getRange(targs), abl.type);
				if(!abl.canActivate(targs))
					opt.bg = Color(0xff900040);
				addOption(menu, selected, clicked, option, opt, abl.type.icon);
			}
		}
	}

	//Constructions
	if(constructObj !is null && clicked !is null) {
		Targets@ targs;
		for(uint i = 0, cnt = getConstructionTypeCount(); i < cnt; ++i) {
			auto@ cons = getConstructionType(i);
			if(!cons.inContext)
				continue;
			if(cons.targets.length == 0)
				continue;
			if(cons.targets[0].type != TT_Object)
				continue;

			if(targs is null) {
				@targs = Targets();
				@targs.add(TT_Object, true).obj = clicked;
			}

			if(!cons.canBuild(constructObj, targs, ignoreCost=true)) {
				continue;
			}

			bool haveCost = cons.canBuild(constructObj, targs, ignoreCost=false);
			ConstructionOption opt(cons, constructObj, targs);
			if(!haveCost)
				opt.bg = Color(0xff000030);

			string costs = cons.formatCosts(constructObj, targs);
			string optText;
			if(costs.length != 0)
				optText = format("$1: $2 ($3)", constructObj.name, cons.name, costs);
			else
				optText = format("$1: $2", constructObj.name, cons.name);

			addOption(menu, selected, clicked, optText, opt);
		}
	}

	//Only show the menu if there are options
	if(menu.list.itemCount == 0) {
		menu.remove();
		return false;
	}
	else {
		menu.updateAbsolutePosition();
		return true;
	}
}

// {{{ Shortcut helpers for context menu
class Option : GuiContextOption {
	Object@ clicked;
	Object@ selected;

	void call() {
	}

	void call(GuiContextMenu@ menu) {
		call();
	}
};

class SelectionOption : Option {
	void call(Object@ selected) {
	}

	void call(GuiContextMenu@ menu) {
		if(selectedObject is null) {
			call(selected);
			return;
		}
		array<Object@>@ selection = selectedObjects;
		for(uint i = 0, cnt = selection.length; i < cnt; ++i)
			call(selection[i]);
	}
};

class MultiOption : Option {
	void call(Object@ selected) {
	}

	void call(GuiContextMenu@ menu) {
		if(selectedObject is null) {
			if(selected !is null)
				call(selected);
			if(clicked !is null && selected !is clicked)
				call(clicked);
			return;
		}
		array<Object@>@ selection = selectedObjects;
		bool haveClicked = false;
		for(uint i = 0, cnt = selection.length; i < cnt; ++i) {
			if(selection[i] is clicked)
				haveClicked = true;
			call(selection[i]);
		}
		if(!haveClicked && clicked !is null)
			call(clicked);
	}
};

class SingleSelectionOption : Option {
	void call(Object@ selected) {
	}

	void call(GuiContextMenu@ menu) {
		if(selectedObject is null) {
			call(selected);
			return;
		}
		call(selectedObject);
	}
};

void addOption(GuiContextMenu@ menu, Object@ selected, Object@ clicked, const string& text, Option@ opt, int value = 0) {
	@opt.clicked = clicked;
	@opt.selected = selected;
	opt.value = value;
	opt.text = text;
	menu.addOption(opt);
}

void addOption(GuiContextMenu@ menu, Object@ selected, Object@ clicked, const string& text, Option@ opt, const Sprite& sprt, int value = 0) {
	@opt.clicked = clicked;
	@opt.selected = selected;
	opt.value = value;
	opt.text = text;
	opt.icon = sprt;
	menu.addOption(opt);
}
// }}}
