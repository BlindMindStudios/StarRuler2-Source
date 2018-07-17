import dialogs.InputDialog;
import elements.BaseGuiElement;
import elements.GuiPanel;
import elements.GuiText;
import elements.GuiButton;
import elements.GuiSprite;
import elements.GuiCheckbox;
import elements.GuiSkinElement;
import elements.GuiContextMenu;
import elements.MarkupTooltip;
import resources, ship_groups;
import elements.Gui3DObject;
#include "dialogs/include/UniqueDialogs.as"
import obj_selection;
import icons;
from gui import animate_time;
from targeting.targeting import cancelTargeting;
from targeting.MoveTarget import isExtendedMoveTarget;

const int GROUP_WIDTH = 256;
const int GROUP_SPACING = 32;

const int SUPPORT_PADDING = 12;
const int SUPPORT_HEIGHT = 56;
const int SUPPORT_WIDTH = GROUP_WIDTH - SUPPORT_PADDING * 2;
const int SUPPORT_SPACING = 8;
const int BAR_WIDTH = SUPPORT_WIDTH + SUPPORT_PADDING * 2 + 20;
const vec2i addButtonSize = vec2i(180,32);

const double ANIM_TIME = 0.15;

from tabs.GalaxyTab import GalaxyOverlay;
GalaxyOverlay@ createSupportOverlay(IGuiElement@ tab, Object@ obj, Object@ to, bool animate = true) {
	return SupportOverlay(tab, obj, to, animate);
}

class SupportOverlay : GalaxyOverlay, BaseGuiElement {
	Object@ leader;

	GroupDisplay@ main;
	GroupDisplay@ secondary;

	SupportClass@[] selected;
	vec2i dragStart;
	bool leftDown = false;
	bool rightDown = false;
	bool dragging = false;
	bool closing = false;

	SupportClass@ clsHover;
	GroupDisplay@ grpHover;

	SupportOverlay(IGuiElement@ parent, Object@ Leader, Object@ To, bool animate) {
		@leader = Leader;
		super(parent, Alignment(Left, Top, Right, Bottom));

		if(To !is null)
			makeSecondary(To);

		@main = GroupDisplay(leader, this, 255);
		Alignment align(Left+4, Top+34, Left+4+BAR_WIDTH, Bottom);
		if(animate)
			main.animate(align);
		else
			@main.alignment = align;

		updateAbsolutePosition();
		bringToFront();
		setGuiFocus(this);
	}

	void makeSecondary(Object@ obj) {
		if(main !is null && obj is main.leader)
			@obj = null;
		if(secondary !is null) {
			if(obj is null) {
				secondary.remove();
				@secondary = null;
			}
			else {
				secondary.set(obj);
			}
		}
		else if(obj !is null) {
			@secondary = GroupDisplay(obj, this);
			@secondary.alignment = Alignment(Left+2+BAR_WIDTH, Top+94, Left+2+BAR_WIDTH*2, Bottom-220);
			secondary.sendToBack();
		}
	}

	GroupDisplay@ getHoveredGroup(vec2i absPos) {
		if(main.absolutePosition.isWithin(absPos))
			return main;
		if(secondary !is null && secondary.absolutePosition.isWithin(absPos))
			return secondary;
		return null;
	}

	SupportClass@ getHoveredClass(vec2i absPos) {
		GroupDisplay@ grp = getHoveredGroup(absPos);
		if(grp !is null)
			return grp.getHoveredClass(absPos);
		return null;
	}

	bool isOpen() {
		return parent !is null;
	}

	bool objectInteraction(Object& object, uint mouseButton, bool doubleClicked) {
		return false;
	}

	void close() {
		if(parent is null || closing)
			return;
		close(main);
	}

	void close(GroupDisplay@ disp) {
		if(disp is main) {
			main.animateClose();
			closing = true;
		}
		else if(disp is secondary) {
			secondary.remove();
			@secondary = null;
			deselect();
		}
	}

	IGuiElement@ elementFromPosition(const vec2i& pos) {
		if(dragging) {
			//Cannot access inner elements while dragging,
			//we handle all the drag and drop stuff ourselves
			if(AbsoluteClipRect.isWithin(pos))
				return this;
			return null;
		}
		else {
			return BaseGuiElement::elementFromPosition(pos);
		}
	}

	void updateHover() {
		@grpHover = getHoveredGroup(mousePos);
		if(grpHover !is null)
			@clsHover = grpHover.getHoveredClass(mousePos);
		else
			@clsHover = null;
	}

	void dropGroups() {
		updateTimer = 0.1;

		Object@ transferTo;
		if(grpHover !is null)
			@transferTo = grpHover.leader;
		else
			@transferTo = hoveredObject;
		if(transferTo !is null && transferTo.owner.controlled && transferTo.hasLeaderAI) {
			for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
				SupportClass@ cls = selected[i];
				if(cls.disp.leader is transferTo || cls.disp is null)
					continue;

				uint amt = cls.dat.totalSize - cls.leaveAmount;
				cls.disp.leader.transferSupports(cls.dat.dsg, amt, transferTo);
			}
		}

		main.update();
		if(secondary !is null)
			secondary.update();
		deselect();
	}

	void deselect() {
		for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
			selected[i].selected = false;
			selected[i].leaveAmount = 0;
		}
		selected.length = 0;
	}

	void select(SupportClass@ cls) {
		cls.selected = true;
		cls.leaveAmount = 0;
		if(selected.find(cls) == -1)
			selected.insertLast(cls);
	}

	void deselect(SupportClass@ cls) {
		cls.selected = false;
		cls.leaveAmount = 0;
		selected.remove(cls);
	}

	void pingUpdate() {
		main.update();
		if(secondary !is null)
			secondary.update();
		updateTimer = 0.15;
	}

	double updateTimer = 0.0;
	bool update(double time) {
		if(closing)
			return true;
		if(selectedObject !is main.leader) {
			if(selectedObject is null || !selectedObject.hasLeaderAI)
				return false;
			main.set(selectedObject);
			if(secondary !is null) {
				secondary.remove();
				@secondary = null;
			}
		}

		updateTimer -= time;
		if(updateTimer <= 0) {
			main.update();
			if(secondary !is null) {
				secondary.update();
				secondary.visible = !main.animating;
			}
			updateTimer += 0.5;
		}

		return true;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(event.type == MET_Button_Down) {
			if(event.button == 0) {
				dragging = false;
				leftDown = true;
				dragStart = mousePos;

				if(clsHover !is null) {
					if(ctrlKey) {
						if(clsHover.selected)
							deselect(clsHover);
						else
							select(clsHover);
						leftDown = false;
					}
					else {
						if(!shiftKey)
							deselect();
						select(clsHover);
					}
				}
				else {
					deselect();
				}
			}
			else if(event.button == 1) {
				if(!leftDown)
					dragStart = mousePos;
				rightDown = true;
				return false;
			}
		}
		else if(event.type == MET_Moved) {
			updateHover();
			if(!dragging && leftDown && mousePos.distanceTo(dragStart) > 3 && selected.length != 0) {
				bool selSats = false;
				for(uint i = 0, cnt = selected.length; i < cnt; ++i)  {
					if(selected[i].dat.dsg.hasTag(ST_Satellite)) {
						selSats = true;
						break;
					}
				}
				if(!selSats) {
					dragging = true;
					for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
						if(shiftKey)
							selected[i].leaveAmount = selected[i].dat.totalSize - selected[i].dat.amount;
						else
							selected[i].leaveAmount = 0;
					}
				}
			}
			if(dragging) {
			}
		}
		else if(event.type == MET_Scrolled) {
			for(uint i = 0, cnt = selected.length; i < cnt; ++i) {
				SupportClass@ cls = selected[i];

				int y = event.y;
				if(shiftKey)
					y *= 10;
				cls.leaveAmount = clamp(cls.leaveAmount - y, 0, cls.dat.totalSize);
			}
			return true;
		}
		else if(event.type == MET_Button_Up) {
			if(event.button == 0) {
				leftDown = false;
				if(dragging) {
					dropGroups();
					dragging = false;
					return true;
				}
			}
			else if(event.button == 1) {
				rightDown = false;
				if(mousePos.distanceTo(dragStart) < 5 && !isExtendedMoveTarget() && hoveredObject is null) {
					close(main);
					cancelTargeting();
					return true;
				}
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onKeyEvent(const KeyboardEvent& event, IGuiElement@ source) override {
		switch(event.type) {
			case KET_Key_Down:
				if(event.key == KEY_ESC)
					return true;
			break;
			case KET_Key_Up:
				if(event.key == KEY_ESC) {
					close(main);
					return true;
				}
			break;
		}
		return BaseGuiElement::onKeyEvent(event, source);
	}

	bool get_isRoot() const override {
		return getHoveredGroup(mousePos) is null;
	}

	void draw() override {
		BaseGuiElement::draw();

		if(dragging) {
			vec2i dragDiff = mousePos - dragStart;
			for(uint i = 0, cnt = selected.length; i < cnt; ++i)
				selected[i].drawAt(selected[i].absolutePosition.topLeft + dragDiff, true);
		}
	}
};

class GroupDisplay : BaseGuiElement {
	SupportOverlay@ overlay;
	Object@ leader;
	Alignment@ targPos;
	bool animating = false;
	bool closing = false;

	//Group leader display
	GuiSkinElement@ capBG;
	GuiText@ capText;
	GuiText@ groupSize;

	//List of support groups
	GuiPanel@ listPanel;
	SupportClass@[] classes;
	GroupData[] groupData;

	//Action buttons
	GuiButton@ addButton;
	GuiButton@ rebuyButton;
	GuiButton@ clearButton;
	GuiCheckbox@ autoBuy;
	GuiCheckbox@ autoFill;
	GuiCheckbox@ allowFillFrom;

	GroupDisplay(Object@ obj, SupportOverlay@ Overlay, int offset = 0) {
		@leader = obj;
		@overlay = Overlay;

		super(overlay, recti());

		@capBG = GuiSkinElement(this, Alignment(Left, Top, Right-22, Top+50), SS_FullTitle);

		@capText = GuiText(this, Alignment(Left+12, Top+8, Right-12, Top+24), locale::SUPPORT_CAPACITY);
		capText.font = FT_Bold;

		@groupSize = GuiText(this, Alignment(Left+4, Top+20, Right-32, Top+48));
		groupSize.horizAlign = 1.0;

		@listPanel = GuiPanel(this, Alignment(Left+SUPPORT_PADDING, Top+55, Right-SUPPORT_PADDING, Bottom-offset-108));

		@addButton = GuiButton(this, recti(0, 0, 180, 32), locale::ADD_SUPPORTS);
		addButton.tooltip = locale::CREATE_SUPPORT_SHIPS;
		addButton.buttonIcon = icons::Add;

		@rebuyButton = GuiButton(this, Alignment(Left+4, Bottom-offset-60, Left+0.5f-15, Bottom-offset-30), locale::REBUY_GHOSTS);
		setMarkupTooltip(rebuyButton, locale::TT_REBUY_GHOSTS);
		rebuyButton.color = colors::Money;
		rebuyButton.setIcon(icons::Money);
		@clearButton = GuiButton(this, Alignment(Left+0.5f-6, Bottom-offset-60, Right-25, Bottom-offset-30), locale::CLEAR_GHOSTS);
		clearButton.color = colors::Red;
		clearButton.setIcon(icons::Remove);
		setMarkupTooltip(clearButton, locale::TT_CLEAR_GHOSTS);

		@autoFill = GuiCheckbox(this, Alignment(Left+8, Bottom-offset-29, Left+0.5f-15, Bottom-offset-3), locale::AUTO_FILL_SUPPORTS);
		setMarkupTooltip(autoFill, locale::TT_AUTO_FILL_SUPPORTS);
		@autoBuy = GuiCheckbox(this, Alignment(Left+0.5f-5+3, Bottom-offset-29, Right-25, Bottom-offset-3), locale::AUTO_BUY_SUPPORTS);
		setMarkupTooltip(autoBuy, locale::TT_AUTO_BUY_SUPPORTS);
		@allowFillFrom = GuiCheckbox(this, Alignment(Left+8, Bottom-offset-29, Left+0.5f-15, Bottom-offset-3), locale::ALLOW_FILL_FROM_SUPPORTS);
		setMarkupTooltip(allowFillFrom, locale::TT_ALLOW_FILL_FROM_SUPPORTS);

		update();
	}

	void remove() {
		@overlay = null;
		BaseGuiElement::remove();
	}

	void set(Object@ obj) {
		@leader = obj;
		update();
	}

	SupportClass@ getHoveredClass(vec2i absPos) {
		for(uint i = 0, cnt = classes.length; i < cnt; ++i) {
			if(classes[i].absolutePosition.isWithin(absPos))
				return classes[i];
		}
		return null;
	}

	void update() {
		groupData.syncFrom(leader.getSupportGroups());

		//Remove old buttons
		uint newCnt = groupData.length;
		uint oldCnt = classes.length;

		for(uint i = newCnt; i < oldCnt; ++i) {
			classes[i].remove();
			@classes[i] = null;
		}

		//Update current buttons
		classes.length = newCnt;
		int y = SUPPORT_SPACING;
		for(uint i = 0; i < newCnt; ++i) {
			if(classes[i] is null)
				@classes[i] = SupportClass(this);

			SupportClass@ cls = classes[i];
			cls.set(groupData[i]);
			cls.position = vec2i(0, y);
			y += SUPPORT_HEIGHT + SUPPORT_SPACING;
		}

		//Update action button position
		if(y + 36 > listPanel.size.height)
			y = listPanel.rect.botRight.y + 14;
		else
			y += 55;
		addButton.position = vec2i((GROUP_WIDTH - addButton.size.width) / 2, y);

		//Update group size
		uint size = 0;
		Ship@ leaderShip = cast<Ship>(leader);
		if(leaderShip !is null)
			size = leaderShip.blueprint.design.size;

		int supUsed = leader.SupplyUsed;
		int supCap = leader.SupplyCapacity;
		groupSize.text = toString(supUsed) + " / "
							+ toString(supCap);
		if(supUsed >= supCap)
			capBG.color = colors::Red;
		else if(float(supUsed) >= float(supCap) * 0.9f)
			capBG.color = Color(0xff8000ff);
		else
			capBG.color = colors::White;
		addButton.disabled = supUsed >= supCap;

		//Update controls
		autoFill.visible = !leader.isPlanet && !leader.isOrbital;
		allowFillFrom.visible = !autoFill.visible;
		autoBuy.visible = true;
		rebuyButton.visible = !leader.isPlanet;
		clearButton.visible = !leader.isPlanet;
		autoBuy.checked = leader.autoBuySupports;

		if(autoFill.visible) {
			autoFill.checked = leader.autoFillSupports;

			int cost = 0;
			for(uint i = 0; i < newCnt; ++i) {
				auto@ dat = groupData[i];
				if(dat.ghost > 0)
					cost += getBuildCost(dat.dsg) * dat.ghost;
			}

			rebuyButton.disabled = cost == 0 || !playerEmpire.canPay(cost);
			clearButton.disabled = cost == 0;
			rebuyButton.text = format(locale::REBUY_GHOSTS, formatMoney(cost));
		}
		else {
			allowFillFrom.checked = leader.allowFillFrom;
		}
	}

	void draw() {
		uint flags = SF_Normal;
		recti pos = AbsolutePosition;
		if(!listPanel.vert.visible)
			pos.botRight.x -= 20;
		skin.draw(SS_GroupPanel, flags, pos);
		BaseGuiElement::draw();
	}

	void animate(Alignment@ pos) {
		@targPos = pos;
		@alignment = null;
		recti endPos = targPos.resolve(parent.size);
		rect = endPos + vec2i(0, endPos.height);
		animate_time(this, endPos, ANIM_TIME);
		animating = true;
		if(overlay.secondary !is null)
			overlay.secondary.visible = false;
	}

	void animateClose() {
		if(parent is null || overlay is null)
			return;
		@alignment = null;
		recti endPos = rect + vec2i(0, rect.height);
		animate_time(this, endPos, ANIM_TIME);
		animating = true;
		closing = true;
		if(overlay.secondary !is null)
			overlay.secondary.visible = false;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(event.type == MET_Button_Down) {
			if(event.button == 1) {
				return true;
			}
		}
		else if(event.type == MET_Button_Up) {
			if(event.button == 1) {
				overlay.close(this);
				return true;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is addButton) {
				CreateSupportDialog dlg(overlay, leader, null, 10);
				addDialog(D_SupportAmount, dlg);
				return true;
			}
			if(evt.caller is clearButton) {
				leader.clearAllGhosts();
				overlay.pingUpdate();
				return true;
			}
			if(evt.caller is rebuyButton) {
				leader.rebuildAllGhosts();
				overlay.pingUpdate();
				return true;
			}
		}
		else if(evt.type == GUI_Changed) {
			if(evt.caller is autoFill) {
				leader.autoFillSupports = autoFill.checked;
				return true;
			}
			if(evt.caller is autoBuy) {
				leader.autoBuySupports = autoBuy.checked;
				return true;
			}
			if(evt.caller is allowFillFrom) {
				leader.allowFillFrom = allowFillFrom.checked;
				return true;
			}
		}
		else if(evt.type == GUI_Animation_Complete) {
			animating = false;
			if(closing) {
				if(overlay !is null)
					overlay.remove();
			}
			else {
				@alignment = targPos;
				if(overlay.secondary !is null)
					overlay.secondary.visible = true;
			}
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}
};

class SupportClass : BaseGuiElement {
	GroupDisplay@ disp;
	GroupData@ dat;
	bool selected = false;
	uint leaveAmount = 0;

	GuiButton@ addButton;
	GuiButton@ removeButton;

	SupportClass(GroupDisplay@ d) {
		@disp = d;
		super(disp.listPanel, recti(0, 0, SUPPORT_WIDTH, SUPPORT_HEIGHT));

		@addButton = GuiButton(this, Alignment(Right-40, Top, Right, Top+0.5f));
		addButton.tooltip = locale::CREATE_SUPPORT_SHIPS;
		addButton.color = colors::Green;
		addButton.visible = false;
		addButton.setIcon(icons::Add);

		@removeButton = GuiButton(this, Alignment(Right-40, Top+0.5f, Right, Bottom));
		removeButton.tooltip = locale::SCUTTLE_SUPPORT_SHIPS;
		removeButton.color = colors::Red;
		removeButton.setIcon(icons::Minus);
		removeButton.visible = false;
	}

	void remove() {
		@disp = null;
		BaseGuiElement::remove();
	}

	void set(GroupData@ data) {
		@dat = data;
	}

	void drawAt(const vec2i& absPos, bool dragging) {
		recti pos = recti_area(absPos, size);

		uint flags = SF_Normal;
		if(disp !is null && disp.overlay.clsHover is this)
			flags |= SF_Hovered;
		if(selected)
			flags |= SF_Active;

		uint tot = dat.totalSize;
		uint amount = dat.amount;
		uint ghost = dat.ghost;
		uint ordered = dat.ordered;

		if(dragging) {
			tot = dat.totalSize - leaveAmount;

			//Calculate proportions to take
			uint lv = leaveAmount;
			uint take = min(ordered, lv);
			lv -= take;
			ordered -= take;

			take = min(ghost, lv);
			lv -= take;
			ghost -= take;

			take = min(amount, lv);
			lv -= take;
			amount -= take;
		}
		else if(disp.overlay.dragging && selected) {
			tot = leaveAmount;

			//Calculate proportions to leave
			uint lv = leaveAmount;
			uint take = min(ghost, lv);
			lv -= take;
			ghost = take;

			take = min(ordered, lv);
			lv -= take;
			ordered = take;

			take = min(amount, lv);
			lv -= take;
			amount= take;
		}

		skin.draw(SS_PatternBox, flags, pos, dat.dsg.color);
		if(disp !is null && disp.overlay.clsHover is this && !dragging)
			skin.draw(SS_SubtleGlow, SF_Normal, pos, dat.dsg.color);

		Color col;
		col = dat.dsg.color;
		col.a = 0x80;
		dat.dsg.icon.draw(recti_area(pos.topLeft+vec2i(4,0), vec2i(pos.height, pos.height)), col);

		const Font@ normal = skin.getFont(FT_Normal);
		normal.draw(pos=recti_area(pos.topLeft + vec2i(pos.height+6, 6), vec2i(pos.width-pos.height-12, 22)), text=formatShipName(dat.dsg), stroke=colors::Black);

		const Font@ bold = skin.getFont(FT_Bold);
		bold.draw(pos=recti_area(pos.topLeft + vec2i(pos.height+12, 28), vec2i(60, 22)), text=toString(amount)+"x", stroke=colors::Black);

		if(ordered > 0)
			normal.draw(pos=recti_area(pos.topLeft + vec2i(pos.height+82, 28), vec2i(60, 22)), text="(+"+toString(ordered)+"x)", stroke=colors::Black, color=Color(0x80ff80ff));
		if(ghost > 0)
			normal.draw(pos=recti_area(pos.topLeft + vec2i(pos.height+132, 28), vec2i(60, 22)), text="(-"+toString(ghost)+"x)", stroke=colors::Black, color=Color(0xff8080ff));
	}

	bool onGuiEvent(const GuiEvent& evt) {
		if(evt.type == GUI_Clicked) {
			if(evt.caller is addButton) {

				GuiContextMenu menu(mousePos);

				uint canBuild = uint(double(disp.leader.SupplyAvailable) / dat.dsg.size);
				uint max = canBuild + dat.ghost;
				if(max > 0)
					menu.addOption(OrderSupports(disp.leader, dat.dsg, max));
				if(dat.ghost > 0 && dat.ghost < max)
					menu.addOption(OrderSupports(disp.leader, dat.dsg, dat.ghost));
				uint maxMoney = floor(double(playerEmpire.RemainingBudget) / double(getBuildCost(dat.dsg)));
				if(maxMoney < max && maxMoney != dat.ghost)
					menu.addOption(OrderSupports(disp.leader, dat.dsg, maxMoney));
				if(max > 10 && maxMoney > 10)
					menu.addOption(OrderSupports(disp.leader, dat.dsg, 10));
				if(max > 1 && maxMoney > 1)
					menu.addOption(OrderSupports(disp.leader, dat.dsg, 1));

				uint orderAmt = 10;
				if(dat.ghost != 0)
					orderAmt = dat.ghost;
				if(orderAmt > max)
					orderAmt = max;
				menu.addOption(CustomSupportOrder(disp.overlay, disp.leader, dat.dsg, orderAmt));
				menu.finalize();

				return true;
			}
			else if(evt.caller is removeButton) {
				InputDialog@ dialog = InputDialog(ScuttleSupports(this), disp.overlay);
				dialog.addTitle(locale::SCUTTLE_SUPPORT_SHIPS);
				dialog.accept.text = locale::REMOVE;

				uint defAmount = 0;
				if(dat.ghost > 0)
					defAmount = dat.ghost;
				if(dat.ordered > 0)
					defAmount = dat.ordered;
				dialog.addSpinboxInput(locale::AMOUNT, defAmount, 10.0, 1.0, dat.totalSize, 0);

				addDialog(D_SupportAmount, dialog);
				dialog.focusInput();
			}
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() {
		drawAt(AbsolutePosition.topLeft, false);

		bool hover = disp !is null && !disp.overlay.dragging && disp.overlay.clsHover is this;
		addButton.visible = hover && (disp.leader.SupplyAvailable >= uint(dat.dsg.size) || dat.ghost > 0);
		removeButton.visible = hover;

		BaseGuiElement::draw();
	}
};

class OrderSupports : GuiContextOption {
	Object@ forObject;
	const Design@ dsg;
	uint amount;
	int build = 0;
	int maintain = 0;

	OrderSupports(Object@ forObject, const Design@ dsg, uint amount) {
		double labor = 0;
		getBuildCost(dsg, this.build, maintain, labor, amount);

		this.amount = amount;
		@this.forObject = forObject;
		@this.dsg = dsg;

		string text = format(locale::ORDER_SUPPORT_COUNT, toString(amount), dsg.name);
		text += " ("+formatMoney(this.build, maintain)+")";
		super(text);
	}

	void call(GuiContextMenu@ menu) {
		if(dsg !is null && amount > 0)
			forObject.orderSupports(dsg, amount);
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		if(!playerEmpire.canPay(this.build))
			drawRectangle(absPos, Color(0xff900040));
		GuiContextOption::draw(ele, flags, absPos);
	}
};

class CustomSupportOrder : GuiContextOption {
	SupportOverlay@ overlay;
	Object@ forObject;
	const Design@ dsg;
	uint amount;

	CustomSupportOrder(SupportOverlay@ overlay, Object@ forObject, const Design@ dsg, uint amount) {
		this.amount = amount;
		@this.forObject = forObject;
		@this.dsg = dsg;
		@this.overlay = overlay;

		super(locale::ORDER_SUPPORT_CUSTOM);
	}

	void call(GuiContextMenu@ menu) {
		CreateSupportDialog dlg(overlay, forObject, dsg, amount);
		addDialog(D_SupportAmount, dlg);
	}
};

enum Dialogs {
	D_SupportAmount,
};

class ScuttleSupports : InputDialogCallback {
	Object@ at;
	const Design@ dsg;

	ScuttleSupports(SupportClass@ cls) {
		@at = cls.disp.leader;
		@dsg = cls.dat.dsg;
	}

	void inputCallback(InputDialog@ dialog, bool accepted) {
		if(accepted) {
			double amt = dialog.getSpinboxInput(0);
			at.scuttleSupports(dsg, round(amt));
		}
	}
};

class CreateSupportDialog : Dialog {
	array<const Design@> designs;
	const Design@ dsg;
	Object@ forObject;

	GuiText@ designLabel;
	GuiListbox@ designList;

	GuiText@ amountLabel;
	GuiSpinbox@ amountBox;

	GuiText@ costLabel;
	GuiText@ costText;

	GuiButton@ accept;
	GuiButton@ cancel;

	CreateSupportDialog(SupportOverlay@ overlay, Object@ obj, const Design@ design = null, int defaultNum = 10) {
		@dsg = design;
		@forObject = obj;
		super(overlay);

		addTitle(locale::ADD_SUPPORTS);
		width = 700;

		int y = 32;

		//Show list of designs
		if(dsg is null) {
			@designLabel = GuiText(bg, recti(12, y, width / 3 - 6, y+22), locale::ORDER_SUPPORT_DESIGN);
			designLabel.font = FT_Bold;
			@designList = GuiListbox(bg, recti(width / 3 + 6, y, width - 12, y+222));
			designList.required = true;
			designList.itemHeight = 40;
			designList.tabIndex = 0;
			designList.style = SS_PlainBox;

			{
				ReadLock lck(playerEmpire.designMutex);
				uint cnt = playerEmpire.designCount;
				designs.reserve(cnt);
				designs.length = 0;
				for(uint i = 0; i < cnt; ++i) {
					const Design@ other = playerEmpire.designs[i];
					if(other.obsolete || other.newest() !is other)
						continue;
					if(other.hasTag(ST_Support) || (obj.canHaveSatellites && other.hasTag(ST_Satellite))) {
						designList.addItem(GuiListText(formatShipName(other), other.icon * other.color));
						designs.insertLast(other);
					}
				}
			}

			y += 232;
			height += 232;
		}

		//Show spinbox
		@amountLabel = GuiText(bg, recti(12, y, width / 3 - 6, y+22), locale::ORDER_SUPPORT_AMOUNT);
		amountLabel.font = FT_Bold;
		@amountBox = GuiSpinbox(bg, recti(width / 3 + 6, y, width - 12, y+22), double(defaultNum));
		amountBox.tabIndex = 1;
		amountBox.min = 0;
		amountBox.decimals = 0;
		amountBox.step = 10.0;

		y += 32;
		height += 28;

		//Show cost
		@costLabel = GuiText(bg, recti(12, y, width / 3 - 6, y+22), locale::ORDER_SUPPORT_COST);
		costLabel.font = FT_Bold;
		@costText = GuiText(bg, recti(width / 3 + 6, y, width - 12, y+22));
		costText.font = FT_Medium;

		height += 32;

		@accept = GuiButton(bg, recti());
		accept.text = locale::BUILD;
		accept.tabIndex = 2;
		@accept.callback = this;

		@cancel = GuiButton(bg, recti());
		cancel.text = locale::CANCEL;
		cancel.tabIndex = 3;
		@cancel.callback = this;

		alignAcceptButtons(accept, cancel);
		updateCost();
	}

	const Design@ get_currentDesign() {
		if(dsg is null && designList.selected != -1)
			return designs[designList.selected];
		return dsg;
	}

	void updateCost() {
		const Design@ cur = currentDesign;
		if(cur !is null) {
			double canBuild = double(forObject.SupplyAvailable) / cur.size;
			canBuild += forObject.getGhostCount(cur);
			amountBox.maximum = floor(canBuild);

			int build = 0, maintain = 0;
			double time = 0.0;
			getBuildCost(cur, build, maintain, time, amountBox.value);

			costText.text = formatMoney(build)+" / "+formatMoney(maintain);
			if(playerEmpire.RemainingBudget >= build) {
				costText.color = Color(0xffffffff);
				accept.disabled = false;
			}
			else if(playerEmpire.canPay(build)) {
				costText.color = Color(0xfdff00ff);
				accept.disabled = false;
			}
			else {
				costText.color = Color(0xff0000ff);
				accept.disabled = true;
			}
		}
		else
			costText.text = "";
	}

	void close() {
		close(false);
	}

	void close(bool accepted) {
		if(accepted) {
			@dsg = currentDesign;
			int amount = ceil(amountBox.value);
			if(dsg !is null && amount > 0)
				forObject.orderSupports(dsg, amount);
		}
		Dialog::close();
	}

	void confirmDialog() {
		close(true);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(Closed)
			return false;
		if(event.type == GUI_Clicked && (event.caller is accept || event.caller is cancel)) {
			close(event.caller is accept);
			return true;
		}
		else if(event.type == GUI_Changed && (event.caller is amountBox || event.caller is designList)) {
			updateCost();
			return true;
		}
		else if(event.type == GUI_Confirmed) {
			close(true);
			return true;
		}
		return Dialog::onGuiEvent(event);
	}
};
