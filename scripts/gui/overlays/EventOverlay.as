import elements.BaseGuiElement;
import elements.GuiOverlay;
import elements.GuiBackgroundPanel;
import elements.GuiMarkupText;
import elements.GuiText;
import elements.GuiListbox;
import elements.GuiProgressbar;
import elements.Gui3DObject;
import elements.GuiButton;
import elements.GuiPanel;
import elements.GuiSprite;
import random_events;
import util.formatting;
import tabs.tabbar;

class Option : GuiButton {
	CurrentEvent@ event;
	const EventOption@ option;

	GuiSprite@ icon;
	GuiMarkupText@ content;
	uint index;

	Option(IGuiElement@ parent) {
		super(parent, recti());
		@icon = GuiSprite(this, Alignment(Left+4, Top+0.5f-30, Left+64, Top+0.5f+30));
		@content = GuiMarkupText(this, recti(68, 4, 100, 100));
		style = SS_ChoiceBox;
	}

	int set(CurrentEvent@ evt, const EventOption@ option, int y, uint index) {
		@this.event = evt;
		@this.option = option;
		this.index = index;
		position = vec2i(4, y);
		size = vec2i(parent.size.width-8, size.height);
		@content.targets = evt.targets;
		content.size = vec2i(size.width - 72, content.size.height);
		content.text = option.text;
		icon.desc = option.icon;
		updateAbsolutePosition();
		size = vec2i(size.width, max(content.size.height + 12, 68));
		return size.height;
	}
};

class EventOverlay : GuiOverlay {
	CurrentEvent event;
	GuiBackgroundPanel@ bg;
	GuiBackgroundPanel@ choices;
	
	GuiPanel@ descPanel;
	GuiMarkupText@ description;
	
	GuiPanel@ choicePanel;
	array<Option@> options;
	GuiProgressbar@ bar;

	EventOverlay(IGuiElement@ parent, int eventId) {
		super(parent);

		uint left = 500;
		uint right = 500;
		uint total = left + 12 + right;

		@bg = GuiBackgroundPanel(this, Alignment(Left+0.5f-total/2, Top+0.5f-200, Left+0.5f-total/2+left, Top+0.5f+200));
		bg.titleColor = Color(0x00ff00ff);

		@choices = GuiBackgroundPanel(this, Alignment(Left+0.5f-total/2+left+12, Top+0.5f-300, Left+0.5f+total/2, Top+0.5f+300));
		choices.title = locale::ANOMALY_CHOICES;
		choices.titleColor = Color(0xff8000ff);

		@descPanel = GuiPanel(bg, Alignment(Left+4, Top+36, Left+left-4, Bottom-8));

		@description = GuiMarkupText(descPanel, recti_area(4, 0, left-8, 100));
		description.fitWidth = true;

		@choicePanel = GuiPanel(choices, Alignment(Left, Top+38, Right, Bottom-34));

		@bar = GuiProgressbar(choices, Alignment(Left+12, Bottom-34, Right-12, Bottom-4));
		bar.frontColor = Color(0xf4b62bff);
		
		closeSelf = false;
		updateAbsolutePosition();
		update();
		bringToFront();

		overlays.insertLast(this);

		if(!receive(playerEmpire.getEvent(eventId), event))
			close();
		else
			update();
	}

	void remove() {
		overlays.remove(this);
		GuiOverlay::remove();
	}

	bool onGuiEvent(const GuiEvent& evt) override {
		switch(evt.type) {
			case GUI_Clicked:
				{
					Option@ opt = cast<Option>(evt.caller);
					if(opt !is null) {
						playerEmpire.chooseEventOption(event.id, opt.option.id);
						autoOpen = 1.0;
						timer = 0.05f;
					}
				}
			break;
		}
		return GuiOverlay::onGuiEvent(evt);
	}
	
	float timer = 0.f;
	void update() {
		if(event.type is null)
			return;
		timer -= frameLength;
		if(timer <= 0.f) {
			if(playerEmpire.currentEventID != event.id) {
				close();
				return;
			}
			if(!receive(playerEmpire.getEvent(event.id), event)) {
				close();
				return;
			}
			description.text = event.type.text;
			@description.targets = event.targets;
			bg.title = event.type.name;

			bar.visible = event.timer > 0;
			if(bar.visible) {
				if(event.type.timer > 0)
					bar.progress = 1.f - (event.timer / event.type.timer);
				else
					bar.progress = 0.f;
				bar.text = formatTime(event.timer);
			}
			
			uint optCount = event.options.length;
			uint oldCnt = options.length;
			for(uint i = optCount; i < oldCnt; ++i)
				options[i].remove();
			options.length = optCount;
			int y = 0;
			for(uint i = 0; i < optCount; ++i) {
				auto@ optType = event.options[i];

				if(options[i] is null)
					@options[i] = Option(choicePanel);
				y += options[i].set(event, optType, y, i) + 8;
			}
			updateAbsolutePosition();
			timer += 1.f;
		}
	}

	void updateAbsolutePosition() {
		GuiOverlay::updateAbsolutePosition();
	}
	
	void draw() {
		update();
		BaseGuiElement::draw();
	}
};

GuiButton@ eventButton;

double autoOpen = 0.0;
array<EventOverlay@> overlays;
void tick(double time) {
	for(uint i = 0, cnt = overlays.length; i < cnt; ++i)
		overlays[i].update();

	eventButton.visible = playerEmpire.hasCurrentEvents();
	eventButton.pressed = overlays.length != 0;

	if(autoOpen > 0) {
		if(overlays.length == 0 && eventButton.visible)
			EventOverlay(ActiveTab, playerEmpire.currentEventID);
		autoOpen -= time;
	}
}

class OpenEvent : onButtonClick {
	bool onClick(GuiButton@ btn) {
		for(uint i = 0, cnt = overlays.length; i < cnt; ++i) {
			if(overlays[i].isChildOf(ActiveTab)) {
				overlays[i].close();
				return true;
			}
		}
		EventOverlay(ActiveTab, playerEmpire.currentEventID);
		return true;
	}
};

void init() {
	@eventButton = GuiButton(null, Alignment(Left+0.5f-120, Top+TAB_HEIGHT+GLOBAL_BAR_HEIGHT, Width=240, Height=40), "Event");
	@eventButton.onClick = OpenEvent();
	eventButton.font = FT_Bold;
	eventButton.visible = false;
	eventButton.toggleButton = true;
}
