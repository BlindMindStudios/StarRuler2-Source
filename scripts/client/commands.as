import targeting.ObjectTarget;
import resources;
from obj_selection import selectedObject, selectedObjects, hoveredObject;
import targeting.ObjectTarget;
import targeting.PointTarget;
from input import activeCamera, mouseToGrid;
import void zoomTabTo(Object@ obj) from "tabs.GalaxyTab";
import vec3d strategicPosition(Object& obj) from "obj_selection";
import void openSupportOverlay(Object@ obj, Object@ to) from "tabs.GalaxyTab";

array<Object@>@ get_immediateSelection() {
	auto@ selected = selectedObjects;
	if(selected.length == 0) {
		@selected = array<Object@>();
		Object@ obj = hoveredObject;
		if(obj !is null)
			selected.insertLast(obj);
	}
	return selected;
}

bool anySelected(ObjectType ofType = OT_COUNT, bool owned = false, array<Object@>@ list = null) {
	auto@ objs = list !is null ? list : selectedObjects;
	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		Object@ obj = objs[i];
		
		bool passed = true;
		if(ofType != OT_COUNT && obj.type != ofType)
			passed = false;
		if(owned && obj.owner !is playerEmpire)
			passed = false;
		if(passed)
			return true;
	}
	
	return false;
}

class ExportResources : ObjectTargeting {
	const ResourceType@ res;
	array<Object@> objs;
	bool isQueued = false;
	array<BeamNode@> beams;

	ExportResources(const ResourceType@ type, array<Object@>& sources, bool isTemporary = mouseLeft) {
		@res = type;
		this.isTemporary = isTemporary;
		if(type !is null)
			icon = type.smallIcon;
		drawCrosshair = false;
		validIconColor = colors::White;
		iconSize = vec2i(32, 32);
		objs.reserve(sources.length);
		for(uint i = 0, cnt = sources.length; i < cnt; ++i) {
			Object@ obj = sources[i];
			
			if(obj.hasResources) {
				if(obj.owner !is playerEmpire)
					isQueued = true;
				else if(obj.isPlanet) {
					auto@ type = getResource(obj.primaryResourceType);
					if(type is null)
						continue;
					if(type.level > obj.level)
						isQueued = true;
				}
				objs.insertLast(obj);
			}
		}

		beams.length = objs.length;
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			auto@ beam = BeamNode(material::MoveBeam, 0.002f, vec3d(), vec3d(), true);
			beam.visible = false;
			if(isQueued)
				beam.color = Color(0xffe400ff);
			else
				beam.color = Color(0x76e0e0ff);
			@beams[i] = beam;
		}
	}

	~ExportResources() {
		clear();
	}

	void clear() {
		for(uint i = 0, cnt = beams.length; i < cnt; ++i) {
			beams[i].markForDeletion();
			@beams[i] = null;
		}
		beams.length = 0;
	}

	void cancel() {
		if(isTemporary)
			call(null);
	}

	void hover(Object@ target, const vec2i& mouse) {
		for(uint i = 0, cnt = beams.length; i < cnt; ++i) {
			auto@ beam = beams[i];
			beam.position = strategicPosition(objs[i]);
			if(target !is null && target.hasResources)
				beam.endPosition = strategicPosition(target);
			else
				beam.endPosition = mouseToGrid(mouse);
			beam.rebuildTransform();
			beam.visible = true;
		}
	}

	bool valid(Object@ target) {
		if(isTemporary && objs.length == 1 && objs[0] is target)
			return false;
		if(target is null || !target.hasResources)
			return false;
		if(!target.importEnabled)
			return false;
		return true;
	}

	void call(Object@ target) {
		bool anyExported = false;
		
		if(target is null || target.hasResources) {
			for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
				auto@ obj = objs[i];
				if(obj.hasResources) {
					obj.exportResource(0, obj !is target ? target : null);
					anyExported = true;
				}
			}
		}
		
		if(anyExported)
			sound::order_goto.play(priority=true);
		else
			sound::error.play(priority=true);
	}

	string emptyMessage() {
		if(res !is null && objs.length <= 1)
			return format(locale::EXPORT_RESOURCE_PROMPT, res.name);
		else
			return locale::EXPORT_RESOURCES_PROMPT;
	}

	string message(Object@ target, bool valid) {
		if(!valid) {
			if(isTemporary && objs.length == 1 && objs[0] is target)
				return emptyMessage();
			return locale::ONLY_PLANETS;
		}
	
		if(res !is null && objs.length <= 1) {
			if(!isQueued && target.owner is playerEmpire)
				return format(locale::EXPORT_RESOURCE, res.name, target.name);
			else
				return format(locale::QUEUE_EXPORT_RESOURCE, res.name, target.name);
		}
		else {
			return format(locale::EXPORT_RESOURCES, target.name);
		}
	}

	void draw(Object@ target, bool valid) override {
	}
};

void doExport(bool pressed) {
	if(pressed) {
		auto@ objs = immediateSelection;
		if(anySelected(ofType=OT_Planet, list=objs) || anySelected(ofType=OT_Asteroid, list=objs)) {
			const ResourceType@ res;
			Object@ obj = objs[0];
			if(obj !is null && obj.hasResources)
				@res = getResource(obj.primaryResourceType);
			targetObject(ExportResources(res, objs));
		}
		else {
			sound::error.play(priority=true);
		}
	}
}

void doCancelExport(bool pressed) {
	if(pressed) {
		bool anyCancelled = false;
		auto@ objs = immediateSelection;
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			auto@ obj = objs[i];
			if(obj.hasResources) {
				obj.exportResource(0, null);
				anyCancelled = true;
			}
		}
		
		if(anyCancelled)
			sound::order_goto.play(priority=true);
		else
			sound::error.play(priority=true);
	}
}

void doAutoImport(bool pressed) {
	if(pressed) {
		bool anyImported = false;
		auto@ objs = immediateSelection;
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			auto@ obj = objs[i];
			if(obj.isPlanet) {
				auto@ resType = getResource(obj.primaryResourceType);
				if(resType !is null && resType.level > 0) {
					playerEmpire.autoImportToLevel(obj, resType.level);
					anyImported = true;
				}
			}
		}
		
		if(anyImported)
			sound::generic_click.play(priority=true);
		else
			sound::error.play(priority=true);
	}
}

class TransferSupports : ObjectTargeting {
	Object@ obj;
	BeamNode@ beam;

	TransferSupports(Object@ source, bool isTemporary = mouseLeft) {
		@obj = source;
		this.isTemporary = isTemporary;
		icon = icons::ManageSupports;
		drawCrosshair = false;
		validIconColor = colors::White;
		iconSize = vec2i(32, 32);

		@beam = BeamNode(material::MoveBeam, 0.002f, vec3d(), vec3d(), true);
		beam.visible = false;
		beam.color = Color(0x76e0e0ff);
	}

	~TransferSupports() {
		clear();
	}

	void clear() {
		if(beam !is null) {
			beam.markForDeletion();
			@beam = null;
		}
	}

	void cancel() {
		if(isTemporary)
			call(null);
	}

	void hover(Object@ target, const vec2i& mouse) {
		beam.position = strategicPosition(obj);
		if(target !is null && target.hasLeaderAI && target.SupplyCapacity > 0)
			beam.endPosition = strategicPosition(target);
		else
			beam.endPosition = mouseToGrid(mouse);
		beam.rebuildTransform();
		beam.visible = true;
	}

	bool valid(Object@ target) {
		if(target is null || !target.hasLeaderAI)
			return false;
		if(target.owner !is obj.owner)
			return false;
		return true;
	}

	void call(Object@ target) {
		if(target !is null && target !is obj)
			openSupportOverlay(obj, target);
	}

	string emptyMessage() {
		return locale::TRANSFER_SUPPORT_SHIPS;
	}

	string message(Object@ target, bool valid) {
		return locale::TRANSFER_SUPPORT_SHIPS;
	}

	void draw(Object@ target, bool valid) override {
	}
};

void doTransfer(bool pressed) {
	if(pressed) {
		auto@ objs = immediateSelection;
		Object@ source;
		for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
			if(objs[i].hasLeaderAI && objs[i].owner is playerEmpire) {
				@source = objs[i];
				break;
			}
		}
		if(source !is null)
			targetObject(TransferSupports(source));
	}
}

void doTransfer(Object@ source, bool isTemporary) {
	if(source !is null && source.owner is playerEmpire && source.hasLeaderAI)
		targetObject(TransferSupports(source, isTemporary));
}

class ColonizePlanets : ObjectTargeting {
	array<Object@> objs;

	ColonizePlanets(array<Object@>& sources) {
		allowMultiple = true;
		objs.reserve(sources.length);
		for(uint i = 0, cnt = sources.length; i < cnt; ++i) {
			Object@ obj = sources[i];
			if(obj.isPlanet)
				objs.insertLast(obj);
		}
	}

	bool valid(Object@ target) {
		if(target !is null && target.isPlanet) {
			auto@ owner = target.visibleOwner;
			if(owner is null || !owner.valid || (owner is playerEmpire && cast<Planet>(target).Population < 1.0))
				return true;
		}
		return false;
	}

	void call(Object@ target) {
		bool anyColonized = false;
		
		if(target.hasResources) {
			for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
				auto@ obj = objs[i];
				if(obj.isPlanet && obj.owner is playerEmpire && obj.canSafelyColonize && obj !is target) {
					obj.colonize(target);
					anyColonized = true;
				}
			}
		}
		
		if(anyColonized)
			sound::order_goto.play(priority=true);
		else
			sound::error.play(priority=true);
	}

	string message(Object@ target, bool valid) {
		if(valid)
			return locale::COLONIZE_GENERIC;
		else
			return locale::ONLY_PLANETS;
	}
};

void doColonize(bool pressed) {
	if(pressed) {
		auto@ objs = immediateSelection;
		if(anySelected(ofType=OT_Planet, owned=true, list=objs)) {
			targetObject(ColonizePlanets(objs));
		}
		else if(anySelected(ofType=OT_Planet, list=objs)) {
			bool anyColonized = false;
			
			for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
				auto@ obj = objs[i];
				if(obj.isPlanet && cast<Planet>(obj).Population < 1.0) {
					playerEmpire.autoColonize(obj);
					anyColonized = true;
				}
			}
			
			if(anyColonized)
				sound::generic_click.play(priority=true);
			else
				sound::error.play(priority=true);
		}
		else {
			sound::error.play(priority=true);
		}
	}
}

class AttackTarget : ObjectTargeting {
	array<Object@> objs;

	AttackTarget(array<Object@>& sources) {
		objs.reserve(sources.length);
		for(uint i = 0, cnt = sources.length; i < cnt; ++i) {
			Object@ obj = sources[i];
			
			if(obj.isShip && obj.owner is playerEmpire && obj.hasLeaderAI)
				objs.insertLast(obj);
		}
	}

	bool valid(Object@ target) {
		if(target !is null && playerEmpire.isHostile(target.owner))
			return target.isShip || target.isOrbital || target.isPlanet;
		return false;
	}

	void call(Object@ target) {
		bool anyAttacked = false;
		
		if(target.hasResources) {
			for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
				auto@ obj = objs[i];
				if(obj.hasLeaderAI && obj.owner is playerEmpire) {
					obj.addAttackOrder(target, shiftKey);
					anyAttacked = true;
				}
			}
		}
		
		if(anyAttacked)
			sound::order_attack.play(priority=true);
		else
			sound::error.play(priority=true);
	}

	string message(Object@ target, bool valid) {
		if(!valid)
			if(target.isShip || target.isOrbital || target.isPlanet)
				return locale::ONLY_WAR;
			else
				return locale::ONLY_ATTACKABLE;
	
		return format(locale::ATTACK_TARGET, target.name);
	}
};

void doAttack(bool pressed) {
	if(pressed) {
		auto@ objs = immediateSelection;
		if(anySelected(ofType=OT_Ship, owned=true, list=objs)) {
			targetObject(AttackTarget(objs));
		}
		else {
			sound::error.play(priority=true);
		}
	}
}

void doQuickExport(Object@ obj) {
	if(obj !is null && obj.hasResources) {
		array<Object@> objs;
		objs.insertLast(obj);
		targetObject(ExportResources(getResource(obj.primaryResourceType), objs));
	}
}

void doQuickExport(Object@ obj, bool isTemporary) {
	if(obj !is null && obj.hasResources) {
		array<Object@> objs;
		objs.insertLast(obj);
		targetObject(ExportResources(getResource(obj.primaryResourceType), objs, isTemporary));
	}
}

void doQuickExport(const array<Object@>& objs, bool isTemporary) {
	array<Object@> sources;
	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		if(objs[i] !is null && objs[i].hasResources && objs[i].primaryResourceType != uint(-1))
			sources.insertLast(objs[i]);
	}
	if(sources.length == 1)
		targetObject(ExportResources(getResource(sources[0].primaryResourceType), sources, isTemporary));
	else if(sources.length != 0)
		targetObject(ExportResources(null, sources, isTemporary));
}

void gotoHomeworld(bool pressed) {
	if(pressed) {
		Object@ hw = playerEmpire.Homeworld;
		if(hw !is null && hw.owner is playerEmpire)
			zoomTabTo(hw);
	}
}

void stopOrder(bool pressed) {
	if(!pressed) {
		for(uint i = 0, cnt = selectedObjects.length; i < cnt; ++i) {
			Object@ obj = selectedObjects[i];
			if(obj !is null && obj.hasLeaderAI)
				obj.clearOrders();
		}
	}
}

void init() {
	keybinds::Global.addBind(KB_EXPORT, "doExport");
	keybinds::Global.addBind(KB_TRANSFER_SUPPORTS, "doTransfer");
	keybinds::Global.addBind(KB_CANCEL_EXPORT, "doCancelExport");
	keybinds::Global.addBind(KB_AUTO_IMPORT, "doAutoImport");
	keybinds::Global.addBind(KB_COLONIZE, "doColonize");
	keybinds::Global.addBind(KB_ATTACK, "doAttack");
	keybinds::Global.addBind(KB_HOMEWORLD, "gotoHomeworld");
	keybinds::Global.addBind(KB_STOP, "stopOrder");
}

array<Ability> cacheAbilities;
Object@ cacheObj;
double cacheTime = INFINITY;

void cacheCurrent() {
	Object@ selected = selectedObject;
	if(selected !is cacheObj || cacheTime > frameTime) {
		@cacheObj = selected;
		cacheTime = frameTime + 2.0;

		if(cacheObj !is null && cacheObj.hasAbilities)
			cacheAbilities.syncFrom(cacheObj.getAbilities());
		else
			cacheAbilities.length = 0;
	}
}

bool objectKeyEvent(int key, bool pressed) {
	if(pressed)
		return false;
	int modKey = modifyKey(key) & ~MASK_SHIFT;
	cacheCurrent();
	for(uint i = 0, cnt = cacheAbilities.length; i < cnt; ++i) {
		auto@ abl = cacheAbilities[i];
		if(abl.disabled)
			continue;
		if(abl.type.hotkey == modKey) {
			if(abl.type.targets.length == 0) {
				if(abl.obj !is null)
					abl.obj.activateAbility(abl.id);
				else
					abl.emp.activateAbility(abl.id);
			}
			else if(abl.type.targets[0].type == TT_Point) {
				toggleAbilityTargetPoint(abl);
			}
			else if(abl.type.targets[0].type == TT_Object) {
				toggleAbilityTargetObject(abl);
			}
			return true;
		}
	}
	return false;
}
