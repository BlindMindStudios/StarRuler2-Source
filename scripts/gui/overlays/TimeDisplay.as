#priority init -100
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiMarkupText;
import elements.MarkupTooltip;
import tabs.Tab;
import util.formatting;
import timing;
from tabs.tabbar import TAB_HEIGHT, GLOBAL_BAR_HEIGHT, ActiveTab;

class TimeDisplay : BaseGuiElement {
	GuiSprite@ icon;
	GuiMarkupText@ text;
	bool showGameTime = true;
	bool clicking = false;
	bool wasAutoPause = false;
	string prevText;

	GuiButton@ pauseButton;
	GuiButton@ slowButton;
	GuiButton@ fastButton;

	TimeDisplay() {
		super(null, recti_area(-4,TAB_HEIGHT+GLOBAL_BAR_HEIGHT, 210, 30));
		@icon = GuiSprite(this, recti_area(9,3, 24,24));
		@text = GuiMarkupText(this, recti_area(35,6, 120,24));
		setMarkupTooltip(icon, locale::TT_GAMETIME);
		setMarkupTooltip(text, locale::TT_GAMETIME);

		if(mpClient) {
			size = vec2i(128, 30);
		}
		else {
			@slowButton = GuiButton(this, Alignment(Right-69, Top+7, Width=18, Height=18));
			setMarkupTooltip(slowButton, locale::TT_SLOWER);
			slowButton.allowOtherButtons = true;
			slowButton.spriteStyle = Sprite(spritesheet::TimeSlow, 0);

			@pauseButton = GuiButton(this, Alignment(Right-48, Top+7, Width=18, Height=18));
			setMarkupTooltip(pauseButton, locale::TT_PAUSE);
			pauseButton.allowOtherButtons = true;
			pauseButton.spriteStyle = Sprite(spritesheet::TimeStop, 0);

			@fastButton = GuiButton(this, Alignment(Right-26, Top+7, Width=18, Height=18));
			setMarkupTooltip(fastButton, locale::TT_FASTER);
			fastButton.allowOtherButtons = true;
			fastButton.spriteStyle = Sprite(spritesheet::TimeHaste, 0);
		}

		updateAbsolutePosition();
	}

	void tick(double time) {
		visible = (ActiveTab.category == TC_Galaxy) && ShowTimeDisplay;

		if(!mpClient && !mpServer && settings::bAutoPause) {
			bool shouldAutoPause = ActiveTab.category != TC_Galaxy && ActiveTab.category != TC_Diplomacy;
			if(gameSpeed != 0 && shouldAutoPause) {
				pause();
				wasAutoPause = true;
			}
			else if(!shouldAutoPause && wasAutoPause && gameSpeed == 0) {
				pause();
				wasAutoPause = false;
			}
		}
		string str;
		if(showGameTime) {
			double time = floor(gameTime / 60.0);
			int hrs = floor(time / 60.0);
			int mins = floor(time - (hrs * 60.0));
			str = format(locale::TIME_HM, toString(hrs), toString(mins));

			icon.desc = Sprite(spritesheet::MenuIcons, 0);
		}
		else {
			icon.desc = Sprite(material::TimeReal);
			str = strftime("%H:%M", getSystemTime());
		}
		if(abs(gameSpeed - 1.0) > 0.05) {
			if(mpIsSerializing)
				str += format(" [color=#fff900]$1[/color]", locale::WAITING);
			else if(gameSpeed == 0.0)
				str += format(" [color=#f00]$1[/color]", locale::PAUSED);
			else if(gameSpeed > 1.0)
				str += format("  [color=#0f0]x$1[/color]", toString(gameSpeed, 1));
			else
				str += format("  [color=#f00]x$1[/color]", toString(gameSpeed, 1));
		}
		if(str != prevText) {
			text.text = str;
			text.updateAbsolutePosition();
			prevText = str;
		}
		if(pauseButton !is null) {
			if(gameSpeed == 0.0)
				pauseButton.spriteStyle = Sprite(spritesheet::TimeResume, 0);
			else
				pauseButton.spriteStyle = Sprite(spritesheet::TimeStop, 0);
		}
	}

	bool onGuiEvent(const GuiEvent& evt) {
		switch(evt.type) {
			case GUI_Mouse_Left:
				if(evt.caller is this)
					clicking = false;
			break;
			case GUI_Clicked:
				if(evt.caller is pauseButton) {
					if(evt.value == 1)
						speed_default();
					else
						pause();
					return true;
				}
				else if(evt.caller is slowButton) {
					if(evt.value == 1)
						speed_slowest();
					else
						speed_slower();
					return true;
				}
				else if(evt.caller is fastButton) {
					if(evt.value == 1)
						speed_fastest();
					else
						speed_faster();
					return true;
				}
			break;
		}
		return BaseGuiElement::onGuiEvent(evt);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this || source is icon || source is text) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0) {
						clicking = true;
						return true;
					}
				break;
				case MET_Button_Up:
					if(event.button == 0) {
						if(clicking) {
							showGameTime = !showGameTime;
							if(showGameTime) {
								setMarkupTooltip(icon, locale::TT_GAMETIME);
								setMarkupTooltip(text, locale::TT_GAMETIME);
							}
							else {
								setMarkupTooltip(icon, locale::TT_REALTIME);
								setMarkupTooltip(text, locale::TT_REALTIME);
							}
						}
						return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() override {
		skin.draw(SS_TimeDisplay, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

TimeDisplay@ disp;
bool ShowTimeDisplay = true;
void init() {
	@disp = TimeDisplay();
}

void tick(double time) {
	disp.tick(time);
}
