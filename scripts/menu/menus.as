#priority init 100
#priority draw 100
import elements.BaseGuiElement;
import elements.GuiButton;
import elements.GuiListbox;
import elements.GuiText;
import elements.GuiSprite;
import elements.GuiPanel;
import dialogs.MessageDialog;
import version;
from gui import animate_speed, animate_time, animate_remove;

enum MenuAnimation {
	MAni_LeftOut,
	MAni_RightHide,

	MAni_RightOut,
	MAni_LeftHide,

	MAni_LeftIn,
	MAni_RightShow,

	MAni_RightIn,
	MAni_LeftShow,
};

GuiText@ version;
MenuContainer@ menu_container;
GuiSprite@ menu_logo;
MenuBox@ active_menu;
DescBox@ active_desc;

MenuBox@ main_menu;
MenuBox@ campaign_menu;
MenuBox@ load_menu;
MenuBox@ save_menu;
MenuBox@ options_menu;
MenuBox@ mods_menu;

const double MSLIDE_TIME = 0.6;
const double MANI_SPEED_1 = 200.0;
const double MANI_SPEED_2 = 120.0;
const int MANI_SPACE = -240;

const double MENU_OFFSET_TIME = 0.1;
const int MENU_OFFSET = 10;

const double BG_FADE_TIME = 0.7;
const double BG_FADE_DELAY = 0.2;

DynamicTexture logo;
DynamicTexture defaultBackground;
bool hasDefaultBackground = false;

DynamicTexture currentBackground;
double bgTimer = 0;
string displayedBackground;
string backgroundFile;

string latestSave;

void init() {
	//Show the version
	@version = GuiText(null, Alignment(Right-200, Bottom-20, Right-4, Bottom));
	version.horizAlign = 1.0;
	version.text = format("Version: $1 ($2)", GAME_VERSION, SCRIPT_VERSION);
	version.color = Color(0xaaaaaaaa);

	//Create container
	@menu_container = MenuContainer();

	//Ready backgrounds
	@defaultBackground.material.shader = shader::MenuBlur;
	defaultBackground.material.wrapHorizontal = TW_ClampEdge;
	defaultBackground.material.wrapVertical = TW_ClampEdge;

	@currentBackground.material.shader = shader::MenuSaveBackground;
	currentBackground.material.wrapHorizontal = TW_ClampEdge;
	currentBackground.material.wrapVertical = TW_ClampEdge;

	//Find latest savegame
	string dir = baseProfile["saves"];
	FileList files(dir, "*.sr2");

	uint cnt = files.length;
	int64 lastTime = 0;
	for(uint i = 0; i < cnt; ++i) {
		string basename = getBasename(files.basename[i], false);
		string fname = path_join(dir, basename)+".sr2";

		int64 mtime = getModifiedTime(fname);
		if(mtime > lastTime) {
			lastTime = mtime;
			latestSave = basename;
		}
	}

	//Find latest screenshot
	string latestShot;
	files.navigate(dir, "*.png");

	lastTime = 0;
	cnt = files.length;
	for(uint i = 0; i < cnt; ++i) {
		string fname = files.path[i];

		int64 mtime = getModifiedTime(fname);
		if(mtime > lastTime) {
			lastTime = mtime;
			latestShot = fname;
		}
	}

	//Set background from latest screenshot
	if(latestShot.length > 0 && fileExists(latestShot) && settings::bMenuBGScreenshot) {
		hasDefaultBackground = true;
		defaultBackground.load(latestShot);
	}
	else {
		hasDefaultBackground = true;
		defaultBackground.load("data/images/title_shot_BG.png");
	}

	if(hasDLC("Heralds"))
		logo.load("data/images/heralds_logo.png");
	else
		logo.load("data/images/sr_logo.png");
}

void tick(double time) {
	mouseLock = (game_state == GS_Game);

	if(backgroundFile.length != 0) {
		if(backgroundFile != displayedBackground) {
			if(currentBackground.isLoaded()) {
				currentBackground.load(backgroundFile);
				bgTimer = BG_FADE_TIME;
				displayedBackground = backgroundFile;
			}
		}
	}
	else {
		displayedBackground = "";
	}

	if(bgTimer >= 0)
		bgTimer = max(0.0, bgTimer - time);

	if(active_menu !is null)
		active_menu.tick(time);

	if(isUpdating)
		updateTick(time);
}

void switchToMenu(MenuBox@ menu, bool left = true, bool snap = false) {
	if(snap || active_menu is null) {
		if(active_menu !is null)
			active_menu.hide();
		if(menu !is null)
			menu.show();
	}
	else {
		active_menu.animate(left ? MAni_LeftOut : MAni_RightOut);
		if(menu !is null)
			menu.animate(left ? MAni_RightIn : MAni_LeftIn);
	}

	@active_menu = menu;
	if(menu_logo !is null)
		menu_logo.visible = menu !is null;
}

void showDescBox(DescBox@ box) {
	if(active_desc !is null)
		active_desc.hide();
	if(box !is null)
		box.show();
	@active_desc = box;
}

class MenuContainer : BaseGuiElement {
	bool animating = false;
	bool hide = false;

	MenuContainer() {
		super(null, recti());
		updateAbsolutePosition();
	}

	void updateAbsolutePosition() {
		if(!animating) {
			size = parent.size;
			position = vec2i(0, 0);
		}
		BaseGuiElement::updateAbsolutePosition();
	}

	void animateIn() {
		animating = true;
		hide = false;

		rect = recti_area(vec2i(-parent.size.x, 0), parent.size);
		animate_time(this, recti_area(vec2i(), parent.size), MSLIDE_TIME);
	}

	void animateOut() {
		animating = true;
		hide = true;

		rect = recti_area(vec2i(), parent.size);
		animate_time(this, recti_area(vec2i(-parent.size.x, 0), parent.size), MSLIDE_TIME);
	}
	
	void show() {
		hide = false;
		Position = recti_area(vec2i(), parent.size);
		animate_remove(this);
		updateAbsolutePosition();
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Animation_Complete:
				if(event.caller is this) {
					animating = false;
					if(hide)
						visible = false;
					return true;
				}
			break;
		}

		return BaseGuiElement::onGuiEvent(event);
	}
};

class MenuAction : GuiListElement {
	int value = -1;
	Sprite icon;
	string text;
	bool disabled = false;
	double offset = 0.0;
	Color color;

	MenuAction(const string& txt, int val, bool dis = false) {
		value = val;
		text = txt;
		disabled = dis;
	}

	MenuAction(const Sprite& sprt, const string& txt, int val, bool dis = false) {
		value = val;
		text = txt;
		disabled = dis;
		icon = sprt;
	}

	void set(const string& txt) {
		text = txt;
	}

	string get() {
		return text;
	}

	void draw(GuiListbox@ ele, uint flags, const recti& absPos) override {
		const Font@ font = ele.skin.getFont(ele.TextFont);
		int baseLine = font.getBaseline();
		vec2i textOffset(ele.horizPadding, (ele.lineHeight - baseLine) / 2);
		textOffset.x += offset * MENU_OFFSET;
		if(ele.itemStyle == SS_NULL)
			ele.skin.draw(SS_ListboxItem, flags, absPos);
		if(icon.valid) {
			int iSize = absPos.height - 6;
			recti iPos = recti_area(absPos.topLeft + vec2i(textOffset.x, 4), vec2i(iSize, iSize));
			iPos = iPos.aspectAligned(icon.aspect);
			icon.draw(iPos);
			textOffset.x += iSize + 8;
		}
		if(disabled)
			font.draw(absPos.topLeft + textOffset, text, Color(0x888888ff));
		else
			font.draw(absPos.topLeft + textOffset, text, color);
		if(flags & SF_Hovered != 0)
			offset = min(1.0, offset + (frameLength / MENU_OFFSET_TIME));
		else
			offset = max(0.0, offset - (frameLength / MENU_OFFSET_TIME));
	}

	bool onMouseEvent(const MouseEvent& event) {
		return disabled;
	}
};

class MenuBox : BaseGuiElement {
	GuiListbox@ items;
	GuiText@ title;

	MenuAnimation anim;
	bool animating = false;
	bool selectable = false;

	MenuBox() {
		super(menu_container, recti());
		visible = false;

		@title = GuiText(this, Alignment(Left, Top+4, Right, Top+44), "Load Game");
		title.horizAlign = 0.5;
		title.font = FT_Big;

		@items = GuiListbox(this, Alignment(Left+4, Top+44, Right-4, Bottom-4));
		items.itemStyle = SS_MainMenuItem;
		items.font = FT_Medium;

		updateAbsolutePosition();
	}

	void tick(double time) {
	}

	void animate(MenuAnimation type) {
		switch(type) {
			case MAni_LeftIn:
				sendToBack();
				show();
			case MAni_LeftOut:
				animate_speed(this, basePosition-vec2i(size.width/2+MANI_SPACE, 0), MANI_SPEED_1);
			break;
			case MAni_RightHide:
			case MAni_RightShow:
				animate_speed(this, basePosition, MANI_SPEED_2);
			break;
			case MAni_RightIn:
				sendToBack();
				show();
			case MAni_RightOut:
				animate_speed(this, basePosition+vec2i(size.width/2+MANI_SPACE, 0), MANI_SPEED_1);
			break;
			case MAni_LeftHide:
			case MAni_LeftShow:
				animate_speed(this, basePosition, MANI_SPEED_2);
			break;
		}

		anim = type;
		animating = true;
	}

	void completeAnimation(MenuAnimation type) {
		animating = false;
		switch(type) {
			case MAni_LeftOut:
				sendToBack();
				animate(MAni_RightHide);
			break;
			case MAni_RightHide:
				hide();
			break;
			case MAni_RightOut:
				sendToBack();
				animate(MAni_LeftHide);
			break;
			case MAni_LeftHide:
				hide();
			break;
			case MAni_LeftIn:
				bringToFront();
				animate(MAni_RightShow);
			break;
			case MAni_RightShow:
			break;
			case MAni_RightIn:
				bringToFront();
				animate(MAni_LeftShow);
			break;
			case MAni_LeftShow:
			break;
		}

		if(!animating)
			updateAbsolutePosition();
	}

	recti get_basePosition() {
		int width = 576;
		int height = min(648, int(Parent.size.height * 0.8f - 36));

		vec2i position = vec2i(Parent.size.width / 2 - 12 - width,
						 Parent.size.height * 0.2f + 24);
		return recti_area(position, vec2i(width, height));
	}

	void updateAbsolutePosition() {
		if(!animating)
			rect = basePosition;
		BaseGuiElement::updateAbsolutePosition();
	}

	void refresh() {
		clearMenu();
		buildMenu();
	}

	void clearMenu() {
		items.clearItems();
	}

	void buildMenu() {
	}

	void show() {
		clearMenu();
		buildMenu();
		visible = true;
	}

	void hide() {
		visible = false;
	}

	bool onGuiEvent(const GuiEvent& event) {
		switch(event.type) {
			case GUI_Changed:
				if(event.caller is items) {
					MenuAction@ act = cast<MenuAction>(items.selectedItem);
					if(act !is null)
						onSelected(act.text, act.value);
					if(!selectable)
						items.clearSelection();
					return true;
				}
			break;
			case GUI_Animation_Complete:
				if(event.caller is this) {
					completeAnimation(anim);
					return true;
				}
			break;
		}

		return BaseGuiElement::onGuiEvent(event);
	}

	void onSelected(const string& name, int value) {
	}

	void draw() {
		skin.draw(SS_MainMenuPanel, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

class DescBox : BaseGuiElement {
	GuiText@ title;
	GuiPanel@ panel;

	DescBox() {
		super(menu_container, recti());
		visible = false;

		@title = GuiText(this, Alignment(Left, Top+4, Right, Top+44), "");
		title.horizAlign = 0.5;
		title.font = FT_Big;

		@panel = GuiPanel(this, Alignment(Left+3, Top+44, Right-4, Bottom-4));

		updateAbsolutePosition();
	}

	recti get_basePosition() {
		int width = 576;
		int height = min(648, int(Parent.size.height * 0.8f - 36));

		vec2i position = vec2i(Parent.size.width / 2 + 12,
						 Parent.size.height * 0.2f + 24);
		return recti_area(position, vec2i(width, height));
	}

	void updateAbsolutePosition() {
		rect = basePosition;
		BaseGuiElement::updateAbsolutePosition();
	}

	void refresh() {
	}

	void show() {
		visible = true;
	}

	void hide() {
		visible = false;
	}

	void draw() {
		skin.draw(SS_MainMenuDescPanel, SF_Normal, AbsolutePosition);
		BaseGuiElement::draw();
	}
};

//Pause the game when entering the menu if we're set to
double prevGameSpeed = 0;
void onGameStateChange() {
	if(game_state == GS_Menu) {
		if(!mpClient && !mpServer) {
			prevGameSpeed = gameSpeed;
			if(settings::bMenuPause && gameSpeed != 0)
				gameSpeed = 0;
		}
		active_menu.refresh();
	}
	else {
		if(!mpClient && !mpServer && settings::bMenuPause && gameSpeed == 0)
			gameSpeed = prevGameSpeed;
	}
}

//Render client view if a game is active
void preRender(double time) {
	if(game_running)
		preRenderClient();
}

void render(double time) {
	if(game_running)
		renderClient();
}

void drawBackground(DynamicTexture@ bg, double alpha = 1.0) {
	if(!bg.isLoaded(0))
		return;

	vec2i screen(screenSize);
	vec2i matSize(bg.size[0]);
	
	if(matSize.width == 0 || matSize.height == 0)
		return;

	float aspect = float(matSize.width) / float(matSize.height);
	if(aspect > 1.f) {
		matSize.height = float(screen.width) / aspect;
		matSize.width = screen.width;
	}
	else {
		matSize.height = screen.height;
		matSize.width = float(screen.height) * aspect;
	}

	recti pos = recti_area(
		vec2i((screen.width - matSize.width) / 2,
			  (screen.height - matSize.height) / 2),
		matSize);

	Color col(0xffffffff);
	col.a = alpha * 255;
	bg.draw(pos, col);
}

bool isUpdating = false;
bool startedUpdate = false;
WebData updateCheck;
void checkForUpdates() {
	if(isUpdating)
		return;
	isUpdating = true;
	webAPICall("updates/version", updateCheck);
}

void updateTick(double time) {
	if(startedUpdate) {
		if(!::updating) {
			startedUpdate = false;
			isUpdating = false;
			if(updateStatus < 0)
				message(format(locale::UPDATE_FAIL, toString(updateStatus)));
			else
				quitGame();
		}
	}
	else if(updateCheck.completed) {
		if(updateCheck.error) {
			message(locale::CHECK_UPDATE_FAIL+":\n"+updateCheck.errorStr);
			isUpdating = false;
			return;
		}
		else {
			string ver = updateCheck.result.trimmed();
			if(ver == GAME_VERSION) {
				message(locale::CHECK_UPDATE_UPTODATE);
				isUpdating = false;
				return;
			}

			//Do update
			startedUpdate = true;
			updateGame();
		}
	}
}

void draw() {
	//Draw background screenshot
	if(!game_running && defaultBackground.isLoaded() && hasDefaultBackground)
		drawBackground(defaultBackground);
	if(currentBackground.isLoaded() && backgroundFile.length != 0) {
		if(BG_FADE_TIME - bgTimer > BG_FADE_DELAY)
			drawBackground(currentBackground, (BG_FADE_TIME - bgTimer) / BG_FADE_TIME);
	}

	//Draw top and bottom bars
	vec2i screen = screenSize;
	double size = double(screen.x) / 1920;

	if(isUpdating) {
		gui_root.visible = false;

		string txt;
		if(updating)
			txt = format(locale::UPDATE_PROGRESS, toString(updateProgress, 0));
		else
			txt = locale::CHECKING_UPDATES;

		auto@ ft = gui_root.skin.getFont(FT_Big);
		ft.draw(pos=recti_area(vec2i(),screenSize), horizAlign=0.5, vertAlign=0.5,
			stroke=colors::Black, color=colors::Green, text=txt);
	}
	else if(inGalaxyCreation && !mpClient) {
		gui_root.visible = false;
		auto@ ft = gui_root.skin.getFont(FT_Big);
		ft.draw(pos=recti_area(vec2i(),screenSize), horizAlign=0.5, vertAlign=0.5,
			stroke=colors::Black, color=colors::Green, text=locale::MENU_LOADING);
	}
	else {
		gui_root.visible = true;
		if(menu_container.visible && logo.isLoaded()) {
			vec2i size = logo.material.size;
			int logoWidth = min(840, menu_container.size.width);
			int logoHeight = min(350, int(floor(0.2 * menu_container.size.height) + 23));
			recti area = recti_area(vec2i((menu_container.size.width-logoWidth)/2, 0), vec2i(logoWidth, logoHeight));
			area += menu_container.absolutePosition.topLeft;

			area = area.aspectAligned(float(size.x) / float(size.y), 0.5, 0.5);
			logo.draw(area, colors::White);
		}
	}
}
