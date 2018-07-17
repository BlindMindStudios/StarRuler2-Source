#priority init 100
import elements.BaseGuiElement;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import elements.Gui3DObject;
import notifications;
import influence;
import planet_loyalty;
import util.icon_view;
import util.formatting;
from util.draw_model import drawLitModel;
from obj_selection import selectObject;
from overlays.AnomalyOverlay import AnomalyOverlay;
from gui import animate_speed, animate_time;
import hooks;

import tabs.tabbar;
import void showInfluenceVote(uint voteId) from "tabs.DiplomacyTab";
import Tab@ createInfluenceVoteTab(int voteId) from "tabs.InfluenceVoteTab";
import Tab@ createDiplomacyTab() from "tabs.DiplomacyTab";
import void zoomTabTo(Object@ obj) from "tabs.GalaxyTab";
import Tab@ createGalaxyTab(Object@ obj) from "tabs.GalaxyTab";

const double ANIM_SPEED = 1000.0;
const double CLASS_SCROLL = 30.0;
const double EVENT_SCROLL = 50.0;
const double FLASH_TIME = 1.0;
const double ICON_PULSE_TIME = 0.4;

void showNotifications() {
	overlay.visible = true;
}

void hideNotifications() {
	overlay.visible = false;
}

void gotoNotification(Notification@ n, bool bg = false) {
	if(n.type == NT_TreatyEvent) {
		Tab@ tb = findTab(TC_Diplomacy);
		if(tb is null)
			@tb = newTab(createDiplomacyTab());
		switchToTab(tb);
	}
	else if(n.type == NT_Card && cast<CardNotification>(n).voteId >= 0) {
		if(bg)
			newTab(createInfluenceVoteTab(cast<CardNotification>(n).voteId));
		else
			showInfluenceVote(cast<CardNotification>(n).voteId);
	}
	else {
		Object@ obj = n.relatedObject;
		if(obj !is null) {
			zoomTabTo(obj);
			if(n.type == NT_FlagshipBuilt)
				selectObject(obj);
		}
	}
}

class NotifyOverlay : BaseGuiElement {
	array<NotifyClass@> classes;

	NotifyOverlay() {
		super(null, Alignment().fill());
		updateAbsolutePosition();
	}

	//Don't consider this element part of the tree
	IGuiElement@ elementFromPosition(const vec2i& pos) {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(elem is this)
			return null;
		return elem;
	}
};

class ClassDisplay {
	Notification@ base;
	ClassDisplay(Notification@ n) {
		@base = n;
	}

	string formatDescription() {
		return "";
	}

	bool update(NotifyClass@ cls, double time) {
		return true;
	}

	bool goto(Notification@ evt, bool bg = false) {
		return false;
	}

	void draw(NotifyClass@ cls, const recti& iconPos) {
	}

	void add(NotifyClass@ cls, Notification@ n) {
	}
}

class NotifyClass : BaseGuiElement {
	recti animPos;
	bool shown = false;
	int textWidth = 0;
	double scroll = 0.0;
	bool animating = false;
	bool closing = false;
	bool hovered = false;
	Notification@ base;
	Sprite icon;
	array<NotifyEvent@> active;
	double flashTime = 0;
	int flashes = 0;
	ClassDisplay@ clsDisp;
	const Model@ iconModel;
	const Material@ iconMaterial;
	Object@ related;
	Draw3D@ drawObject;

	MarkupRenderer render;

	NotifyClass(Notification@ n) {
		super(overlay, recti());
		@base = n;
		@clsDisp = createClassDisplay(base);

		string clsText = n.formatClass();
		if(clsText.length == 0)
			clsText = n.formatEvent();
		else if(n.formatEvent().length != 0)
			add(n);
		icon = n.icon;
		if(!icon.valid) {
			@iconModel = n.model;
			@iconMaterial = n.material;
			if(iconModel is null) {
				@related = n.relatedObject;
				if(related !is null)
					@drawObject = makeDrawMode(related);
			}
		}

		render.defaultFont = FT_Medium;
		render.expandWidth = true;
		render.parse(skin, clsText, recti(0, 0, 300, 34));
		render.update(skin, recti(0, 0, 300, 34));
		textWidth = clamp(render.width+16, 300, 800);
		updateTooltip();
	}

	void add(Notification@ n) {
		if(active.length != 0) {
			NotifyEvent@ prev = active[active.length - 1];
			prev.visible = false;
		}

		NotifyEvent evt(this, n);
		animate_speed(evt, getEventArea(rect), ANIM_SPEED);
		evt.animating = true;
		active.insertLast(evt);
		flashes += n.flashCount;
		updateTooltip();

		if(n.pulseIcon)
			PulseIcon(this, n.icon);

		clsDisp.add(this, n);
	}

	void animate(const recti& pos) {
		if(closing)
			return;
		if(!shown) {
			rect = pos + vec2i(pos.width+60, 0);
			shown = true;
		}
		animating = true;
		animPos = pos;
		animate_speed(this, animPos, ANIM_SPEED);
		if(active.length != 0) {
			NotifyEvent@ prev = active[active.length - 1];
			prev.animating = true;
			animate_speed(prev, getEventArea(animPos), ANIM_SPEED);
		}
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Animation_Complete) {
			animating = false;
			if(closing)
				remove();
			return true;
		}
		else if(evt.type == GUI_Mouse_Entered) {
			hovered = true;
		}
		else if(evt.type == GUI_Mouse_Left) {
			hovered = false;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	recti getTextArea(const recti& atPos) {
		return recti_area(
			vec2i(8+max(atPos.size.width - textWidth - 80 - 8, 0), 4)+atPos.topLeft,
			vec2i(min(atPos.size.width-16, textWidth + 80), 26));
	}

	recti getEventArea(const recti& atPos) {
		recti textArea = getTextArea(atPos);
		int offset = max(30, atPos.size.width - textArea.width+30);
		return recti_area(vec2i(offset, 33), vec2i(atPos.size.width - offset, 26));
	}

	recti getIconArea(const recti& atPos) {
		recti iconPos = recti_area(atPos.botRight - vec2i(80, 60), vec2i(80, 60));
		return iconPos;
	}

	void updateAbsolutePosition() override {
		render.update(skin, getTextArea(rect));
		BaseGuiElement::updateAbsolutePosition();
	}

	bool update(double time) {
		//Update tooltip state
		if(settings::bIconifyNotifications) {
			if(tooltipObject is null)
				updateTooltip();
		}
		else {
			if(tooltipObject !is null)
				@tooltipObject = null;
		}

		//Update icon
		if(!icon.valid) {
			if(iconModel is null) {
				if(related !is null && drawObject is null)
					@drawObject = makeDrawMode(related);
			}
		}

		//Update class display
		if(!clsDisp.update(this, time))
			return false;

		return true;
	}

	void dismiss() {
		closing = true;
		animating = true;
		active.length = 0;
		animate_speed(this, rect+vec2i(size.width, 0), ANIM_SPEED);
		overlay.classes.remove(this);
		updatePositions();
	}

	void dismissEvents() {
		for(uint i = 0, cnt = active.length; i < cnt; ++i)
			active[i].remove();
		active.length = 0;
	}

	void dismissEvent(NotifyEvent@ evt) {
		active.remove(evt);
		evt.remove();

		if(active.length != 0) {
			NotifyEvent@ prev = active[active.length - 1];
			prev.animating = true;
			prev.visible = true;
			animate_speed(prev, getEventArea(animPos), ANIM_SPEED);
		}
	}

	void popEvent(bool bg = false) {
		NotifyEvent@ evt;
		Notification@ n;
		if(active.length == 0) {
			@n = base;
		}
		else {
			@evt = active[active.length - 1];
			@n = evt.notification;
		}

		if(!clsDisp.goto(n, bg))
			gotoNotification(n, bg);
		switch(n.triggerMode) {
			case NTM_Ignore:
				break;
			case NTM_KillClass:
				dismiss();
				break;
			case NTM_KillEvents:
				dismissEvents();
				break;
			case NTM_KillTop:
				if(evt !is null)
					dismissEvent(evt);
				break;
		}

		flashes = 0;
		updateTooltip();
	}

	void updateTooltip() {
		if(!settings::bIconifyNotifications) {
			@tooltipObject = null;
			return;
		}

		string tt = base.formatClass();
		if(tt.length == 0)
			tt = base.formatEvent();
		tt = "[font=Medium]"+tt+"[/font]";
		if(clsDisp !is null)
			tt += clsDisp.formatDescription();

		for(int i = active.length - 1; i >= 0; --i) {
			Notification@ n = active[i].notification;
			tt += "\n\n";
			tt += formatTimeStamp(n.time);
			tt += " [offset=80]";
			string evt = n.formatEvent();
			if(evt.length == 0)
				evt = n.formatClass();
			tt += evt;
			tt += "[/offset]";
		}

		setMarkupTooltip(this, tt, true, textWidth+30);
	}

	bool onMouseEvent(const MouseEvent& mevt, IGuiElement@ caller) override {
		if(mevt.type == MET_Button_Down) {
			return true;
		}
		else if(mevt.type == MET_Button_Up) {
			if(mevt.button == 0) {
				popEvent();
			}
			else if(mevt.button == 1) {
				if(caller is this)
					dismiss();
				else if(active.length != 0)
					dismissEvent(active[active.length - 1]);
			}
			else if(mevt.button == 2) {
				popEvent(true);
			}
			return true;
		}

		return BaseGuiElement::onMouseEvent(mevt, caller);
	}

	//Don't consider this element part of the tree
	IGuiElement@ elementFromPosition(const vec2i& pos) {
		IGuiElement@ elem = BaseGuiElement::elementFromPosition(pos);
		if(settings::bIconifyNotifications) {
			if(getIconArea(rect).isWithin(pos))
				return this;
			else
				return null;
		}
		else {
			if(elem is this) {
				if(getTextArea(rect).isWithin(pos))
					return this;
				if(getIconArea(rect).isWithin(pos))
					return this;
				return null;
			}
		}
		return elem;
	}

	void draw() override {
		recti textBox = getTextArea(rect);
		recti iconPos = getIconArea(rect);

		//Show the class text
		if(!settings::bIconifyNotifications) {
			skin.draw(SS_PlainOverlay, SF_Normal, textBox.padded(-8, -4));
		}

		BaseGuiElement::draw();

		if(!settings::bIconifyNotifications) {
			setClip(textBox);
			int tbWidth = textBox.width - iconPos.width;
			if(textWidth > tbWidth && !animating) {
				int area = textWidth + max(tbWidth / 3, 50);
				scroll = (scroll + frameLength * CLASS_SCROLL) % double(area);

				int startPos = area - int(scroll);
				if(startPos < textBox.width) {
					render.draw(skin, recti_area(textBox.topLeft+vec2i(startPos, 1),
								vec2i(size.width*2, textBox.height)));
				}
			}

			render.draw(skin, recti_area(textBox.topLeft-vec2i(int(scroll), -1),
						vec2i(size.width*2, textBox.height)));
		}

		//Show the icon
		clearClip();
		if(icon.sheet is spritesheet::Notifications) {
			icon.draw(iconPos);
		}
		else {
			spritesheet::Notifications.draw(0, iconPos);

			if(icon.valid) {
				vec2i iSize = icon.size;
				recti pos = iconPos.padded(30,0,0,0).aspectAligned(double(iSize.width) / double(iSize.height), 1.0, 0.5);
				icon.draw(pos);
			}
			else if(iconModel !is null) {
				recti pos = iconPos.padded(30,0,0,0).aspectAligned(1.0, 1.0, 0.5);
				drawLitModel(iconModel, iconMaterial, pos, quaterniond_fromAxisAngle(vec3d_front(), 0.5*pi));
			}
			else if(drawObject !is null) {
				recti pos = iconPos.padded(30,0,0,0).aspectAligned(1.0, 1.0, 0.5);
				if(related.owner !is null)
					NODE_COLOR = related.owner.color;
				else
					NODE_COLOR = colors::White;
				drawObject.preRender(related);
				drawObject.draw(pos, quaterniond_fromAxisAngle(vec3d_front(), 0.5*pi));
			}
		}

		//Show class-specifics
		clsDisp.draw(this, iconPos);

		//Show flashes
		if(flashTime > 0.0) {
			float alpha = 0.f;
			if(flashTime < FLASH_TIME * 0.5)
				alpha = 1.f - (FLASH_TIME * 0.5 - flashTime) / (FLASH_TIME * 0.5);
			else
				alpha = 1.f - (flashTime - FLASH_TIME * 0.5) / (FLASH_TIME * 0.5);

			Color col(0xffffffff);
			col.a = alpha * 255;
			spritesheet::Notifications.draw(7, iconPos, col);
			flashTime -= frameLength;
		}
		else {
			if(flashes > 0) {
				--flashes;
				flashTime = FLASH_TIME;
			}
		}
	}
};

class PulseIcon : BaseGuiElement {
	Sprite sprite;
	Color color;

	PulseIcon(NotifyClass@ cls, const Sprite& icon) {
		noClip = true;
		sprite = icon;
		super(cls, recti_area(cls.size, vec2i(1, 1)));

		recti target(cls.size * -2, cls.size);
		vec2i iSize = icon.size;
		if(iSize.x != 0 && iSize.y != 0)
			target = target.aspectAligned(double(iSize.x) / double(iSize.y), 1.0, 1.0);
		animate_time(this, target, ICON_PULSE_TIME);
		rect = target;
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Animation_Complete) {
			remove();
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() override {
		clearClip();
		sprite.draw(AbsolutePosition, color);
		BaseGuiElement::draw();
	}
};

class PulseCard : PulseIcon {
	Empire@ from;

	PulseCard(NotifyClass@ cls, const Sprite& icon, Empire@ emp) {
		super(cls, icon);
		@from = emp;
		color = Color(0xffffff80);
	}

	void draw() override {
		PulseIcon::draw();
		if(from !is null) {
			Color color = from.color;
			color.a = 0x80;
			material::CardBorder.draw(AbsolutePosition, color);
		}
	}
};

class NotifyEvent : BaseGuiElement {
	Notification@ notification;
	MarkupRenderer render;
	int textWidth;
	double scroll = 0.0;
	bool animating = false;

	NotifyEvent(NotifyClass@ cls, Notification@ n) {
		@notification = n;
		super(cls, recti_area(vec2i(cls.size.width+20, 33), vec2i(20, 26)));

		string evtText = n.formatEvent();

		render.expandWidth = true;
		render.parse(skin, evtText, recti(0, 0, 300, 26));
		render.update(skin, recti(0, 0, 300, 26));
		textWidth = render.width+16;
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		if(evt.type == GUI_Animation_Complete) {
			animating = false;
			return true;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	void draw() override {
		if(settings::bIconifyNotifications)
			return;
		recti textBox = AbsolutePosition;
		skin.draw(SS_PlainOverlay, SF_Normal, textBox);

		//Show the event text
		if(textWidth > textBox.width - 80 && !animating) {
			int area = textWidth + max((textBox.width - 80) / 3, 50);
			scroll = (scroll + frameLength * EVENT_SCROLL) % double(area);

			int startPos = area - int(scroll);
			if(startPos < textBox.width) {
				render.draw(skin, recti_area(textBox.topLeft+vec2i(startPos, 5),
							vec2i(size.width*2, textBox.height)));
			}
		}

		render.draw(skin, recti_area(textBox.topLeft-vec2i(int(scroll), -5),
					vec2i(size.width*2, textBox.height)));

		BaseGuiElement::draw();
	}
};

void handle(Notification@ n) {
	if(n.time <= minGameTime)
		return;
		
	const SoundSource@ sound = n.sound;
	if(sound !is null)
		sound.play(priority=true);

	//Check if this notification can be added to any classes
	for(uint i = 0, cnt = overlay.classes.length; i < cnt; ++i) {
		NotifyClass@ cls = overlay.classes[i];
		if(cls.base.sharesClass(n)) {
			cls.add(n);
			if(i != 0) {
				overlay.classes.removeAt(i);
				overlay.classes.insertLast(cls);
			}
			return;
		}
	}

	//Add a new class if none is there
	overlay.classes.insertLast(NotifyClass(n));
	while(overlay.classes.length > uint(settings::dMaxNotifications))
		overlay.classes[0].dismiss();
}

void updatePositions() {
	vec2i osize = overlay.size;
	int w = osize.width * 0.25, h = 60, o = 12;
	for(uint i = 0, cnt = overlay.classes.length; i < cnt; ++i) {
		NotifyClass@ cls = overlay.classes[i];
		recti target = recti_area(osize - vec2i(w, h+h*i+o*i+8), vec2i(w, h));
		if(target != cls.animPos)
			cls.animate(target);
	}
}

uint nextNotify = 0;
array<Notification@> unhandled;
void tick(double time) {
	//Update notifications
	uint latest = playerEmpire.notificationCount;
	if(latest != nextNotify) {
		receiveNotifications(unhandled, playerEmpire.getNotifications(100, nextNotify, false));
		nextNotify = latest;
	}

	//Handle all unhandled
	if(unhandled.length > 0) {
		for(uint i = 0, cnt = unhandled.length; i < cnt; ++i)
			handle(unhandled[i]);
		unhandled.length = 0;
	}

	//Update positioning of classes
	updatePositions();

	//Update clasess
	for(uint i = 0, cnt = overlay.classes.length; i < cnt; ++i) {
		NotifyClass@ cls = overlay.classes[i];
		if(!cls.update(time)) {
			cls.dismiss();
			--i; --cnt;
		}
	}
}

class VoteDisplay : ClassDisplay {
	double timer = 0.0;
	InfluenceVote@ vote;

	VoteDisplay(Notification@ n) {
		super(n);

		@vote = InfluenceVote();
		VoteNotification@ vn = cast<VoteNotification>(n);
		receive(getInfluenceVoteByID(vn.vote.id), vote);
	}

	bool update(NotifyClass@ cls, double time) override {
		timer += time;
		if(timer >= 1.0) {
			timer = 0.0;

			VoteNotification@ vn = cast<VoteNotification>(base);
			receive(getInfluenceVoteByID(vn.vote.id), vote);

			if(!vote.active && base.time + 10.0 < gameTime
				&& (cls.active.length == 0 || settings::bIconifyNotifications))
				return false;
		}
		return true;
	}

	string formatDescription() {
		if(vote !is null && vote.id != uint(-1)) {
			if(vote.startedBy is defaultEmpire)
				return "\n[font=Small]"+vote.type.description+"[/font]";
		}
		return "";
	}

	void draw(NotifyClass@ cls, const recti& iconPos) override {
		const Font@ ft = cls.skin.getFont(FT_Bold);

		if(vote !is null && vote.id != uint(-1)) {
			//Show type of vote icon
			vote.type.icon.draw(iconPos.padded(30, 0, -10, 0).aspectAligned(vote.type.icon.aspect),
					Color(0xffffff70));
			if(vote.type.targets.targets.length > 0 && vote.type.targets.targets[0].type == TT_Object) {
				drawObjectIcon(vote.targets.targets[0].obj,
					iconPos.padded(30, 10, 10, 10));
			}

			//Show starter of proposition as glow color
			Color col = vote.startedBy.color;
			col.a = 0x80;
			spritesheet::Notifications.draw(8, iconPos, col);

			//Timer
			Color timerColor;
			string timeText;
			if(vote.totalFor > vote.totalAgainst) {
				timerColor = Color(0x00ff00ff);
				timeText = formatShortTime(vote.remainingTime);
			}
			else {
				timerColor = Color(0xff0000ff);
				timeText = formatShortTime(vote.remainingTime);
			}
			ft.draw(iconPos, timeText, locale::SHORT_ELLIPSIS, timerColor, 0.85, 0.9);

			//Status
			Color voteColor(0x00ff00ff);
			if(vote.totalAgainst >= vote.totalFor)
				voteColor = Color(0xff0000ff);

			int net = vote.totalFor - vote.totalAgainst;
			string netStr = toString(net, 0);
			if(net > 0)
				netStr = "+"+netStr;
			ft.draw(iconPos, netStr,
				locale::SHORT_ELLIPSIS, voteColor, 0.75, 0.1);
		}
	}

	void add(NotifyClass@ cls, Notification@ n) override {
		VoteNotification@ vn = cast<VoteNotification>(n);
		if(vn !is null) {
			if(vn.event.type == IVET_Card)
				PulseCard(cls, vn.event.cardEvent.card.type.icon, vn.event.emp);
		}
	}

	bool goto(Notification@ evt, bool bg = false) override {
		if(bg) {
			if(!ctrlKey && vote.type.targets.targets.length > 0 && vote.type.targets.targets[0].type == TT_Object)
				zoomTabTo(vote.targets.targets[0].obj);
			else
				newTab(createInfluenceVoteTab(vote.id));
		}
		else
			showInfluenceVote(vote.id);
		return true;
	}
};

class ContestDisplay : ClassDisplay {
	Region@ region;
	uint loyaltyState = CM_None;

	ContestDisplay(Notification@ n) {
		super(n);

		Object@ obj = base.relatedObject;
		@region = cast<Region>(obj);
		if(region is null)
			@region = obj.region;
	}

	bool update(NotifyClass@ cls, double time) override {
		//Dismiss empty contested notifications if the
		//system is no longer contested.
		if(base.time + 10.0 < gameTime) {
			//Check if we have any substantial actual notifications
			//left, and don't kill it if we do
			bool hasSubstantial = false;
			if(!settings::bIconifyNotifications) {
				for(uint i = 0, cnt = cls.active.length; i < cnt; ++i) {
					WarEventNotification@ wn = cast<WarEventNotification>(cls.active[i].notification);
					if(wn is null || wn.eventType != WET_ContestedSystem) {
						hasSubstantial = true;
						break;
					}
				}

			}

			if(region !is null && !hasSubstantial) {
				if(region.ContestedMask & playerEmpire.mask == 0)
					return false;
			}
		}

		if(region !is null)
			loyaltyState = region.getContestedState(playerEmpire);
		return true;
	}

	void draw(NotifyClass@ cls, const recti& iconPos) override {
		if(loyaltyState != CM_None) {
			Color col = ContestedColors[loyaltyState];
			col.a = 0x80;
			spritesheet::Notifications.draw(8, iconPos, col);
		}
	}
};

class AnomalyDisplay : ClassDisplay {
	Draw3D@ mode;

	AnomalyDisplay(Notification@ n) {
		super(n);

		AnomalyNotification@ dn = cast<AnomalyNotification>(n);
		@mode = makeDrawMode(dn.obj);
	}

	bool update(NotifyClass@ cls, double time) override {
		AnomalyNotification@ n = cast<AnomalyNotification>(cls.base);
		if(!n.obj.valid)
			return false;
		return true;
	}

	void draw(NotifyClass@ cls, const recti& iconPos) override {
		if(mode !is null)
			mode.draw(iconPos, quaterniond());
	}

	bool goto(Notification@ evt, bool bg = false) override {
		AnomalyNotification@ n = cast<AnomalyNotification>(evt);
		if(bg)
			zoomTabTo(n.obj);
		else
			AnomalyOverlay(ActiveTab, cast<Anomaly>(n.obj));
		return true;
	}
};

ClassDisplay@ createClassDisplay(Notification@ n) {
	ClassDisplay@ cls;
	switch(n.type) {
		case NT_Vote: @cls = VoteDisplay(n); break;
		case NT_WarEvent: @cls = ContestDisplay(n); break;
		case NT_Anomaly: @cls = AnomalyDisplay(n); break;
	}
	if(cls is null)
		@cls = ClassDisplay(n);
	return cls;
}

NotifyOverlay@ overlay;
double minGameTime = 0.0;
void init() {
	@overlay = NotifyOverlay();
	minGameTime = gameTime;
}

void save(SaveFile& file) {
	uint cnt = overlay.classes.length;
	file << cnt;
	for(uint i = 0; i < cnt; ++i) {
		NotifyClass@ cls = overlay.classes[i];
		file << cls.base;

		uint evcnt = cls.active.length;
		file << evcnt;
		for(uint j = 0; j < evcnt; ++j) {
			NotifyEvent@ evt = cls.active[j];
			file << evt.notification;
		}
	}
}

void load(SaveFile& file) {
	uint cnt = 0;
	file >> cnt;
	for(uint i = 0; i < cnt; ++i) {
		Notification@ n = loadNotification(file);
		NotifyClass cls(n);
		overlay.classes.insertLast(cls);

		uint evcnt = 0;
		file >> evcnt;

		for(uint j = 0; j < evcnt; ++j) {
			Notification@ n = loadNotification(file);
			cls.add(n);
		}
	}

	updatePositions();
}
