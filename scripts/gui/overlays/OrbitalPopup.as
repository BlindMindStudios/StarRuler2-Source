import overlays.Popup;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.MarkupTooltip;
import elements.GuiProgressbar;
import elements.GuiCargoDisplay;
from elements.Gui3DObject import Gui3DObject, ObjectAction;
import orbitals;
from obj_selection import isSelected;
import constructible;
import statuses;
import util.constructible_view;
from overlays.ContextMenu import openContextMenu;

class OrbitalPopup : Popup {
	Constructible cons;
	bool hasConstruction = false;

	array<GuiSprite@> statusIcons;

	GuiText@ name;
	Gui3DObject@ objView;

	GuiProgressbar@ health;
	GuiProgressbar@ strength;

	GuiCargoDisplay@ cargo;

	GuiSprite@ defIcon;

	Orbital@ obj;
	bool selected = false;
	double lastUpdate = -INFINITY;

	OrbitalPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(190, 155);

		@name = GuiText(this, Alignment(Left+4, Top+2, Right-4, Top+24));
		name.horizAlign = 0.5;

		@health = GuiProgressbar(this, Alignment(Left+3, Bottom-56, Right-4, Bottom-30));
		health.tooltip = locale::HEALTH;

		GuiSprite healthIcon(health, Alignment(Left+2, Top+1, Width=24, Height=24), icons::Health);

		@strength = GuiProgressbar(this, Alignment(Left+3, Bottom-30, Right-4, Bottom-4));
		strength.tooltip = locale::FLEET_STRENGTH;

		GuiSprite strIcon(strength, Alignment(Left+2, Top+1, Width=24, Height=24), icons::Strength);

		@objView = Gui3DObject(this, recti(34, 24, 156, 98));

		@cargo = GuiCargoDisplay(objView, Alignment(Left, Top, Right, Top+25));

		@defIcon = GuiSprite(this, Alignment(Right-44, Top+25, Width=40, Height=40));
		defIcon.desc = icons::Defense;
		setMarkupTooltip(defIcon, locale::TT_IS_DEFENDING);
		defIcon.visible = false;

		updateAbsolutePosition();
	}

	bool compatible(Object@ Obj) {
		return cast<Orbital>(Obj) !is null;
	}

	void set(Object@ Obj) {
		@obj = cast<Orbital>(Obj);
		@objView.object = Obj;
		lastUpdate = -INFINITY;
		statusUpdate = 0.f;
	}

	Object@ get() {
		return obj;
	}

	void draw() {
		Popup::updatePosition(obj);
		recti bgPos = AbsolutePosition;

		uint flags = SF_Normal;
		SkinStyle style = isSelectable ? SS_SelectablePopup : SS_GenericPopupBG;
		if(selected)
			flags |= SF_Active;
		if(isSelectable && Hovered)
			flags |= SF_Hovered;
		skin.draw(style, flags, bgPos, obj.owner.color);
		if(obj.owner.flag !is null)
			obj.owner.flag.draw(
				objView.absolutePosition.aspectAligned(1.0, horizAlign=1.0, vertAlign=1.0),
				obj.owner.color * Color(0xffffff30));

		objView.draw();

		if(cargo.visible)
			drawRectangle(cargo.absolutePosition, Color(0x00000040));

		//Construction display
		if(hasConstruction) {
			recti plPos = objView.absolutePosition;
			const Font@ ft = skin.getFont(FT_Small);
			int sz = ft.getLineHeight() * 2 + 6;
			Color nameCol(0xffffffff);
			if(!cons.started)
				nameCol = Color(0xff0000ff);
			ft.draw(plPos.resized(0, sz, 0.0, 1.0),
				cons.name, locale::ELLIPSIS, nameCol, 0.5, 0.0);

			string prog = toString(cons.progress * 100.f, 0)+"%";
			if(cons.type == CT_DryDock)
				prog += " / "+toString(cons.pct * 100.f, 0)+"%";
			ft.draw(plPos.resized(0, sz - ft.getLineHeight(), 0.0, 1.0),
				prog, locale::ELLIPSIS, Color(0xffffffff), 0.5, 0.0);

			drawConstructible(cons, plPos.resized(0, plPos.size.height - sz + 6));
		}

		objView.visible = false;
		BaseGuiElement::draw();
		objView.visible = true;
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is objView) {
					dragging = false;
					if(!dragged) {
						switch(evt.value) {
							case OA_LeftClick:
								emitClicked(PA_Select);
								return true;
							case OA_RightClick:
								openContextMenu(obj);
								return true;
							case OA_MiddleClick:
							case OA_DoubleClick:
								if(isSelectable)
									emitClicked(PA_Select);
								else
									emitClicked(PA_Manage);
								return true;
						}
					}
				}
			break;
		}
		return Popup::onGuiEvent(evt);
	}

	void updateStrengthBar() {
		double curStr = 0, totStr = 0;
		if(obj.hasLeaderAI) {
			curStr = obj.getFleetStrength() * 0.001;
			totStr = obj.getFleetMaxStrength() * 0.001;
		}
		else {
			curStr = obj.dps * obj.efficiency * (obj.health + obj.armor) * 0.001;
			totStr = obj.dps * (obj.maxHealth + obj.maxArmor) * 0.001;
		}

		if(totStr == 0) {
			strength.progress = 0.f;
			strength.frontColor = Color(0xff6a00ff);
			strength.text = "--";
		}
		else {
			strength.progress = curStr / totStr;
			if(strength.progress > 1.001f) {
				strength.progress = 1.f;
				strength.font = FT_Bold;
			}
			else {
				strength.font = FT_Normal;
			}

			strength.frontColor = Color(0xff6a00ff).interpolate(Color(0xffc600ff), strength.progress);
			strength.text = standardize(curStr);
			strength.tooltip = locale::FLEET_STRENGTH+": "+standardize(curStr)+"/"+standardize(totStr);
		}
	}

	float statusUpdate = 0.f;
	void update() {
		if(frameTime - 0.2 < lastUpdate)
			return;
		lastUpdate = frameTime;

		bool owned = obj.owner is playerEmpire;
		if(!isSelectable)
			selected = separated && isSelected(obj);

		//Update static info
		name.text = obj.name;
		const Font@ ft = skin.getFont(FT_Normal);
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;
		if(obj.isDisabled)
			name.color = colors::Red;
		else
			name.color = colors::White;

		//Update hp display
		double curHP = obj.health + obj.armor;
		double maxHP = max(obj.maxHealth + obj.maxArmor, 0.001);

		Color high(0x00ff00ff);
		Color low(0xff0000ff);

		health.progress = curHP / maxHP;
		health.frontColor = low.interpolate(high, health.progress);
		health.text = standardize(curHP)+" / "+standardize(maxHP);

		defIcon.visible = playerEmpire.isDefending(obj);

		updateStrengthBar();

		//Find master obj
		Object@ fromMaster = obj;
		if(obj.hasMaster())
			@fromMaster = obj.getMaster();

		//Update cargo
		cargo.visible = fromMaster.hasCargo && fromMaster.cargoTypes > 0;
		if(cargo.visible)
			cargo.update(fromMaster);

		//Update construction
		Object@ constructObj = fromMaster;
		if(owned && constructObj.hasConstruction) {
			DataList@ list = constructObj.getConstructionQueue(1);
			hasConstruction = receive(list, cons);
		}
		else {
			const Design@ dsg = obj.getDesign(OV_DRY_Design);
			if(dsg !is null) {
				cons.type = CT_DryDock;
				@cons.obj = obj;
				@cons.dsg = dsg;
				cons.prog = obj.getValue(OV_DRY_Progress);
				cons.pct = obj.getValue(OV_DRY_Financed);
				cons.started = true;
				cons.id = -1;
				hasConstruction = true;
			}
			else {
				hasConstruction = false;
			}
		}

		//Update statuses
		statusUpdate -= frameLength;
		if(statusUpdate <= 0.f) {
			array<Status> statuses;
			if(obj.statusEffectCount > 0)
				statuses.syncFrom(obj.getStatusEffects());
			uint prevCnt = statusIcons.length, cnt = statuses.length;
			for(uint i = cnt; i < prevCnt; ++i)
				statusIcons[i].remove();
			statusIcons.length = cnt;
			for(uint i = 0; i < cnt; ++i) {
				auto@ icon = statusIcons[i];
				if(icon is null) {
					@icon = GuiSprite(this, recti_area(6, 25+25*i, 25, 25));
					@statusIcons[i] = icon;
				}

				auto@ status = statuses[i];
				icon.desc = status.type.icon;
				setMarkupTooltip(icon, format("[b]$1[/b]\n$2", status.type.name, status.type.description));
			}
			statusUpdate += 1.f;
		}

		Popup::update();
		Popup::updatePosition(obj);
	}
};
