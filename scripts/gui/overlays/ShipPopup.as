import overlays.Popup;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiSkinElement;
import elements.GuiBlueprint;
import elements.GuiImage;
import elements.GuiButton;
import elements.GuiGroupDisplay;
import elements.GuiProgressbar;
import elements.MarkupTooltip;
import elements.GuiStatusBox;
import elements.GuiCargoDisplay;
import constructible;
import util.constructible_view;
import ship_groups;
import icons;
import biomes;
import statuses;
from statuses import getStatusID;
import util.icon_view;
from overlays.ContextMenu import openContextMenu;
from obj_selection import isSelected, selectObject, clearSelection, addToSelection;

class ShipPopup : Popup {
	Object@ origObject;
	Ship@ ship;

	Constructible cons;
	bool hasConstruction = false;

	array<GuiStatusBox@> statusIcons;
	GuiBlueprint@ bpdisp;
	GuiText@ name;
	GuiText@ ownerName;

	GuiSprite@ shieldIcon;
	GuiProgressbar@ health;
	GuiProgressbar@ strength;
	GuiProgressbar@ exp;
	GuiProgressbar@ shield;
	GuiProgressbar@ supply;

	GuiCargoDisplay@ cargo;
	GuiGroupDisplay@ groupdisp;

	bool selected = false;

	ShipPopup(BaseGuiElement@ parent) {
		super(parent);
		size = vec2i(190, 220);

		@name = GuiText(this, Alignment(Left+40, Top+6, Right-4, Top+28));
		@ownerName = GuiText(this, Alignment(Left+40, Top+28, Right-6, Top+46));
		ownerName.horizAlign = 1.0;

		@bpdisp = GuiBlueprint(this, Alignment(Left+4, Top+50, Right-4, Bottom-80));
		bpdisp.popHover = true;
		bpdisp.popSize = vec2i(77, 40);

		@cargo = GuiCargoDisplay(bpdisp, Alignment(Left, Top, Right, Top+25));

		GuiSkinElement band(this, Alignment(Left+3, Bottom-80, Right-4, Bottom-50), SS_NULL);

		@health = GuiProgressbar(band, Alignment(Left, Top, Right, Bottom));
		health.tooltip = locale::HEALTH;

		@shield = GuiProgressbar(band, Alignment(Left+1, Top+20, Right-1, Bottom));
		shield.noClip = true;
		shield.tooltip = locale::SHIELD_STRENGTH;
		shield.textHorizAlign = 0.85;
		shield.textVertAlign = 1.65;
		shield.visible = false;
		shield.frontColor = Color(0x429cffff);
		shield.backColor = Color(0x59a8ff20);

		GuiSprite healthIcon(band, Alignment(Left, Top, Width=30, Height=30), icons::Health);
		healthIcon.noClip = true;

		@shieldIcon = GuiSprite(band, Alignment(Right-23, Bottom-23, Width=30, Height=30), icons::Shield);
		shieldIcon.visible = false;

		GuiSkinElement strband(this, Alignment(Left+3, Bottom-50, Right-4, Bottom-30), SS_NULL);

		@strength = GuiProgressbar(strband, Alignment(Left+0, Top, Right-0.5f, Bottom));
		strength.tooltip = locale::FLEET_STRENGTH;

		@exp = GuiProgressbar(strength, Alignment(Left, Bottom-4, Right, Bottom));
		exp.frontColor = Color(0xff009eff);
		exp.backColor = colors::Invisible;
		exp.visible = false;

		GuiSprite strIcon(strband, Alignment(Left, Top, Left+24, Bottom), icons::Strength);

		@supply = GuiProgressbar(strband, Alignment(Left+0.5f, Top, Right-1, Bottom));
		supply.tooltip = locale::SUPPLY;

		GuiSprite supIcon(strband, Alignment(Right-24, Top, Right, Bottom), icons::Supply);

		@groupdisp = GuiGroupDisplay(this, Alignment(Left+8, Bottom-31, Right-8, Bottom-3));

		updateAbsolutePosition();
	}

	void remove() {
		Popup::remove();
	}

	bool compatible(Object@ obj) {
		return cast<Ship>(obj) !is null;
	}

	void set(Object@ obj) {
		if(!obj.valid)
			return;
		if(origObject is null)
			@origObject = obj;
		@ship = cast<Ship>(obj);
		bpdisp.display(ship);

		if(ship.MaxShield > 0) {
			shield.visible = true;
			shieldIcon.visible = true;
			health.textHorizAlign = 0.3;
			health.textVertAlign = 0.25;
		}
		else {
			shield.visible = false;
			shieldIcon.visible = false;
			health.textHorizAlign = 0.5;
			health.textVertAlign = 0.5;
		}
		statusUpdate = 0.f;
	}

	Object@ get() {
		return ship;
	}

	bool displays(Object@ obj) {
		return obj is ship;
	}

	double dblClick = 0;
	bool onMouseEvent(const MouseEvent& evt, IGuiElement@ source) {
		if(source is name) {
			switch(evt.type) {
				case MET_Button_Up:
					if(evt.button == 0 && !dragged) {
						dragging = false;
						if(size.width == 800)
							size = vec2i(1200, 910);
						else if(size.width == 380)
							size = vec2i(800, 640);
						else if(size.width == 190)
							size = vec2i(380, 360);
						else
							size = vec2i(190, 220);
						return true;
					}
				break;
			}
		}
		else if(source is bpdisp) {
			switch(evt.type) {
				case MET_Button_Up:
					if(!dragged) {
						dragging = false;
						if(evt.button == 0) {
							if(frameTime < dblClick) {
								emitClicked(PA_Manage);
							}
							else {
								emitClicked(PA_Select);
								dblClick = frameTime + 0.2;
							}
							return true;
						}
						else if(evt.button == 1) {
							openContextMenu(ship);
							return true;
						}
						else if(evt.button == 2) {
							emitClicked(PA_Zoom);
							return true;
						}
					}
				break;
			}

		}
		return Popup::onMouseEvent(evt, source);
	}

	vec2i objPos(Object@ obj) {
		return Popup::objPos(origObject);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Clicked:
				if(evt.caller is groupdisp) {
					dragging = false;
					if(!dragged) {
						if(groupdisp.hovered == 0) {
							if(cast<Ship>(groupdisp.leader) !is null) {
								selectObject(groupdisp.leader);
								set(groupdisp.leader);
							}
						}
						else {
							if(!shiftKey)
								clearSelection();
							Object@ leader = groupdisp.leader;
							GroupData@ dat = groupdisp.groups[groupdisp.hovered-1];
							bool found = false;
							for(uint i = 0, cnt = leader.supportCount; i < cnt; ++i) {
								Ship@ supp = cast<Ship>(leader.supportShip[i]);
								if(supp !is null && supp.blueprint.design is dat.dsg) {
									addToSelection(supp);
									if(!found) {
										set(supp);
										found = true;
									}
								}
							}
						}
					}
				}
			break;
			case GUI_Hover_Changed:
				if(evt.caller is bpdisp) {
					updateHealthBar();
					return true;
				}
			break;
		}
		return Popup::onGuiEvent(evt);
	}

	void draw() {
		Popup::updatePosition(ship);
		recti bgPos = AbsolutePosition;

		uint flags = SF_Normal;
		if(selected)
			flags |= SF_Hovered;

		Color col(0xffffffff);
		Empire@ owner;
		if(ship !is null) {
			@owner = ship.owner;
			if(owner !is null)
				col = owner.color;
		}

		skin.draw(SS_ShipPopupBG, flags, bgPos, col);

		if(owner !is null && owner.flag !is null) {
			vec2i s = bpdisp.absolutePosition.size;
			owner.flag.draw(
				bpdisp.absolutePosition
					.resized(s.x*0.5, s.y*0.5, 1.0, 0.0)
					.aspectAligned(1.0, horizAlign=1.0, vertAlign=0.0),
				owner.color * Color(0xffffff40));
		}

		skin.draw(SS_SubTitle, SF_Normal, recti_area(bgPos.topLeft + vec2i(2,2), vec2i(bgPos.width-5, 50-4)), col);
		drawFleetIcon(ship, recti_area(bgPos.topLeft+vec2i(-2, 2), vec2i(46,46)), showStrength=false);

		bpdisp.draw();

		//Construction display
		if(hasConstruction) {
			recti plPos = bpdisp.absolutePosition;
			plPos.topLeft.y += plPos.height / 2;
			drawRectangle(plPos, Color(0x00000040));

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

		if(cargo.visible)
			drawRectangle(cargo.absolutePosition, Color(0x00000040));

		bpdisp.visible = false;
		Popup::draw();
		bpdisp.visible = true;
	}

	void updateHealthBar() {
		if(ship is null)
			return;

		const Blueprint@ bp = ship.blueprint;
		const Design@ design = bp.design;
		const Hull@ hull = design.hull;

		Color high;
		Color low;

		double curHP = 0, maxHP = 1;
		if(bpdisp.hexHovered.x < 0 || bpdisp.hexHovered.y < 0) {
			curHP = bp.currentHP * bp.hpFactor;
			maxHP = (design.totalHP - bp.removedHP) * bp.hpFactor;

			high = Color(0x00ff00ff);
			low = Color(0xff0000ff);
		}
		else {
			vec2u hex = vec2u(bpdisp.hexHovered);
			const HexStatus@ status = bp.getHexStatus(hex.x, hex.y);
			if(status !is null) {
				maxHP = design.variable(hex, HV_HP) * bp.hpFactor;
				curHP = maxHP * double(status.hp) / double(0xff);
			}

			high = Color(0x9768ffff);
			low = Color(0xff689bff);
		}

		if(!ship.visible)
			curHP = maxHP;

		health.progress = curHP / maxHP;
		health.frontColor = low.interpolate(high, health.progress);
		if(shield.visible)
			health.text = standardize(curHP);
		else
			health.text = standardize(curHP)+" / "+standardize(maxHP);
	}

	void updateStrengthBar() {
		if(groupdisp.leader is null)
			return;

		double curStr = groupdisp.leader.getFleetStrength() * 0.001;
		double totStr = groupdisp.leader.getFleetMaxStrength() * 0.001;

		Ship@ leader = cast<Ship>(groupdisp.leader);
		const Design@ design;
		if(leader !is null)
			@design = leader.blueprint.design;

		if(!ship.visible)
			curStr = totStr;

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

		if(design !is null) {
			int curLevel = groupdisp.leader.getStatusStackCountAny(levelStatus);
			double needExp = groupdisp.leader.getRemainingExp();
			double totalExp = design.size * (config::EXPERIENCE_BASE_AMOUNT + config::EXPERIENCE_INCREASE_AMOUNT * curLevel);

			if(config::EXPERIENCE_GAIN_FACTOR != 0 && totalExp != 0) {
				exp.progress = 1.0 - (needExp / totalExp);
				exp.visible = true;
			}
			else {
				exp.visible = false;
			}
		}
		else {
			exp.visible = false;
		}
	}

	void updateSupplyBar() {
		double curSup = 0.0;
		double totSup = 0.0;

		Ship@ leader = cast<Ship>(groupdisp.leader);
		if(ship.MaxSupply >= 0) {
			curSup = ship.Supply;
			totSup = ship.MaxSupply;
		}
		else if(leader !is null) {
			curSup = leader.Supply;
			totSup = leader.MaxSupply;
		}

		if(!ship.visible)
			curSup = totSup;

		if(totSup == 0) {
			supply.progress = 0.f;
			supply.frontColor = Color(0xff6a00ff);
			supply.text = "--";
		}
		else {
			supply.progress = curSup / totSup;
			if(supply.progress > 1.001f) {
				supply.progress = 1.f;
				supply.font = FT_Bold;
			}
			else {
				supply.font = FT_Normal;
			}

			if(supply.progress < 0.5f)
				supply.frontColor = Color(0xd53f1eff).interpolate(Color(0xd5cc1eff), supply.progress/0.5f);
			else
				supply.frontColor = Color(0x4a9487ff);
			supply.text = standardize(curSup);
			supply.tooltip = locale::SUPPLY+": "+standardize(curSup)+"/"+standardize(totSup);
		}
	}

	float statusUpdate = 0.f;
	void update() {
		if(ship is null)
			return;
		const Font@ ft = skin.getFont(FT_Normal);
		Empire@ owner = ship.owner;
		bool owned = ship.owner is playerEmpire;
		const Blueprint@ bp = ship.blueprint;
		const Design@ design = bp.design;
		const Hull@ hull = design.hull;

		if(design !is bpdisp.design)
			set(ship);

		if(ship.visible) {
			@bpdisp.bp = bp;
			groupdisp.visible = true;
		}
		else {
			@bpdisp.bp = null;
			groupdisp.visible = false;
		}

		//Update name
		name.text = formatShipName(ship);
		if(ft.getDimension(name.text).x > name.size.width)
			name.font = FT_Detail;
		else
			name.font = FT_Normal;

		//Update owner
		if(owner !is null) {
			ownerName.color = owner.color;
			ownerName.text = owner.name;

			if(ft.getDimension(ownerName.text).x > ownerName.size.width)
				ownerName.font = FT_Detail;
			else
				ownerName.font = FT_Normal;
		}

		//Update whatever health is displayed
		updateHealthBar();

		//Update the strength display
		updateStrengthBar();

		//Update the supply display
		updateSupplyBar();

		//Update cargo
		cargo.visible = ship.hasCargo && ship.cargoTypes > 0;
		if(cargo.visible)
			cargo.update(ship);

		//Update construction
		if(owned && ship.hasConstruction) {
			DataList@ list = ship.getConstructionQueue(1);
			hasConstruction = receive(list, cons);
		}
		else {
			hasConstruction = false;
		}

		//Update statuses
		statusUpdate -= frameLength;
		if(statusUpdate <= 0.f) {
			array<Status> statuses;
			if(ship.visible && ship.statusEffectCount > 0)
				statuses.syncFrom(ship.getStatusEffects());
			uint prevCnt = statusIcons.length, cnt = statuses.length;
			for(uint i = cnt; i < prevCnt; ++i)
				statusIcons[i].remove();
			statusIcons.length = cnt;
			int y = 50;
			if(cargo.visible)
				y += 25;
			for(uint i = 0; i < cnt; ++i) {
				auto@ icon = statusIcons[i];
				if(icon is null) {
					@icon = GuiStatusBox(this, recti_area(6, y+25*i, 25, 25));
					icon.noClip = true;
					@statusIcons[i] = icon;
				}
				icon.update(statuses[i]);
			}
			statusUpdate += 1.f;
		}

		//Update energy display
		if(shield.visible) {
			float curshield = ship.Shield;
			float maxshield = max(ship.MaxShield, 0.01);

			shield.progress = min(curshield / maxshield, 1.0);
			shield.text = standardize(curshield, true);
			shield.tooltip = locale::SHIELD_STRENGTH+": "+standardize(curshield)+" / "+standardize(maxshield);
		}

		//Update group
		groupdisp.update(ship);

		Popup::update();
		Popup::updatePosition(ship);
	}
};

int levelStatus = -1;
void init() {
	levelStatus = getStatusID("ShipLevel");
}
