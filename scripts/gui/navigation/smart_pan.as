#priority init 10
import navigation.scopes;
import navigation.SmartCamera;
from input import activeCamera;
import elements.BaseGuiElement;

const int TOPBAR_OFFSET = 77;
const int SCOPE_SPACING = 4;
const int SCOPE_WIDTH = 50;
const int SCOPE_HEIGHT = 50;
const int SCOPE_PADDING = 2;

const double SEARCH_INTERVAL = 1.0;
const uint MAX_SCOPES = 16;

Color scopeColor(0xffffff40);
Color scopeHoverColor(0x00ff0040);
Color scopeActiveColor(0xff000040);
Color scopePanningColor(0x0000ff40);
string ellipsis = "-";

const double smartPanSpeed = 10000.0;
const double fadeDistanceMin = 10000.0;
const double fadeDistanceMax = 16000.0;

ScopeSearch search;
double searchTimer = 0.0;
ScopeButton@ panningButton;
ScopeButton@[] buttons;
bool shown = false;
uint displayedScopes = 0;

void init() {
	search.maxDistance = 16000.0;

	@panningButton = ScopeButton();
	panningButton.visible = false;

	buttons.length = MAX_SCOPES;
	for(uint i = 0; i < MAX_SCOPES; ++i) {
		@buttons[i] = ScopeButton();
		buttons[i].visible = false;
	}
}

void showSmartPan() {
	shown = true;
	update();
	searchTimer = SEARCH_INTERVAL;
}

void hideSmartPan() {
	shown = false;
	for(uint i = 0; i < MAX_SCOPES; ++i)
		buttons[i].visible = false;
}

void toggleSmartPan() {
	if(shown)
		hideSmartPan();
	else
		showSmartPan();
}

void update() {
	search.position = activeCamera.lookAt;
	displayedScopes = searchScopes(search, MAX_SCOPES);

	for(uint i = 0; i < displayedScopes; ++i) {
		Scope@ scope = search.results[i];

		//Ignore current scope
		if(search.position.distanceTo(scope.position) < scope.radius
			|| (panningButton.visible && panningButton.scope is scope)) {
			buttons[i].visible = false;
			continue;
		}

		//Ready the scope button
		buttons[i].visible = true;
		buttons[i].set(scope);
		buttons[i].updatePosition();
	}

	//Hide extra buttons
	for(uint i = displayedScopes; i < MAX_SCOPES; ++i)
		buttons[i].visible = false;
}

void updatePositions() {
	for(uint i = 0; i < displayedScopes; ++i) {
		Scope@ scope = buttons[i].scope;
		if(scope is null || search.position.distanceTo(scope.position) < scope.radius
			|| (panningButton.visible && panningButton.scope is scope)) {
			buttons[i].visible = false;
		}
		else {
			buttons[i].visible = true;
			buttons[i].updatePosition();
		}
	}
}

bool waitForMove = true;
int buttonAlpha = 80;
void tick(double time) {
	if(!shown)
		return;

	//Fade the buttons out at large distances
	double dist = activeCamera.distance;
	if(dist > fadeDistanceMin) {
		if(dist >= fadeDistanceMax) {
			buttonAlpha = 0;
			return;
		}
		else {
			buttonAlpha = 80 - ceil(80.0 * (dist - fadeDistanceMin) / (fadeDistanceMax - fadeDistanceMin));
		}
	}
	else {
		buttonAlpha = 80;
	}

	//Check if we're panning with a button
	vec2i mpos = mousePos;
	if(buttonAlpha > 0 && mpos.x < 6 || mpos.x >= screenSize.width - 6) {
		if(!waitForMove) {
			bool found = false;
			if(panningButton.visible) {
				if(!panningButton.AbsolutePosition.isWithin(mpos)) {
					panningButton.visible = false;
				}
				else {
					double tickPan = time * smartPanSpeed;
					if(activeCamera.panTo(panningButton.scope.position, tickPan)) {
						panningButton.visible = false;
						waitForMove = true;
					}
				}
			}
			else {
				for(uint i = 0; i < displayedScopes; ++i) {
					if(buttons[i].visible && buttons[i].AbsolutePosition.isWithin(mpos)) {
						buttons[i].visible = false;
						panningButton.set(buttons[i].scope);
						panningButton.AbsolutePosition = buttons[i].AbsolutePosition;
						panningButton.AbsoluteClipRect = buttons[i].AbsoluteClipRect;
						panningButton.visible = true;
					}
				}
			}
		}
	}
	else {
		panningButton.visible = false;
		waitForMove = false;
	}

	//Update the buttons
	//if(searchTimer <= 0.0) {
		//searchTimer = SEARCH_INTERVAL;
		update();
	//}
	//else {
		//updatePositions();
		//searchTimer -= time;
	//}
}

class ScopeButton : BaseGuiElement {
	Scope@ scope;
	string name;
	bool left;
	bool Hovered;
	bool Pressed;

	ScopeButton() {
		Hovered = false;
		Pressed = false;
		super(null, recti(0, 0, SCOPE_WIDTH, SCOPE_HEIGHT));
	}

	void updatePosition() {
		vec3d camPos = activeCamera.lookAt;
		vec3d scopePos = scope.position;
		double flatAngle = activeCamera.screenAngle(scopePos);
		double percentage = 0.0;

		vec2i pos();
		if(flatAngle >= 0 && flatAngle <= 0.5) {
			left = false;
			percentage = 0.5 - flatAngle;
		}
		else if(flatAngle > 0.5 && flatAngle <= 1.0) {
			left = true;
			percentage = flatAngle - 0.5;
		}
		else if(flatAngle < 0 && flatAngle >= -0.5) {
			left = false;
			percentage = 0.5 + flatAngle * -1.0;
		}
		else if(flatAngle < -0.5 && flatAngle >= -1.0) {
			left = true;
			percentage = 1.5 + flatAngle;
		}

		if(left)
			pos.x = 0;
		else
			pos.x = screenSize.width - size.width;

		pos.y = TOPBAR_OFFSET;
		pos.y += double(screenSize.height - TOPBAR_OFFSET - SCOPE_HEIGHT) * percentage;

		bool overlap;
		do {
			overlap = false;
			recti box = recti_area(pos, size);
			if(panningButton.visible && panningButton.AbsolutePosition.overlaps(box)) {
				overlap = true;
				pos.y = panningButton.AbsolutePosition.topLeft.y;

				if(percentage < 0.5)
					pos.y += SCOPE_HEIGHT + SCOPE_SPACING;
				else
					pos.y -= SCOPE_HEIGHT + SCOPE_SPACING;
				continue;
			}

			for(uint i = 0; i < MAX_SCOPES; ++i) {
				if(buttons[i] is this)
					break;
				if(buttons[i].left == left && buttons[i].AbsolutePosition.overlaps(box)) {
					overlap = true;
					pos.y = buttons[i].AbsolutePosition.topLeft.y;

					if(percentage < 0.5)
						pos.y += SCOPE_HEIGHT + SCOPE_SPACING;
					else
						pos.y -= SCOPE_HEIGHT + SCOPE_SPACING;
					break;
				}
			}

			if(pos.y < 0 || pos.y + SCOPE_HEIGHT > screenSize.height) {
				visible = false;
				return;
			}
		} while(overlap);

		position = pos;
	}

	void set(Scope@ s) {
		@scope = s;
		name = scope.name;
	}

	void trigger() {
		activeCamera.zoomTo(scope.position);
	}

	bool onGuiEvent(const GuiEvent& event) {
		if(event.caller is this && buttonAlpha > 0) {
			switch(event.type) {
				case GUI_Mouse_Entered:
					Hovered = true;
				break;
				case GUI_Mouse_Left:
					Hovered = false;
					Pressed = false;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) {
		if(source is this && buttonAlpha > 0) {
			switch(event.type) {
				case MET_Button_Down:
					if(event.button == 0) {
						Pressed = true;
					}
					return true;
				case MET_Button_Up:
					if(event.button == 0 && Pressed) {
						Pressed = false;
						trigger();
					}
					return true;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void draw() {
		if(buttonAlpha <= 0)
			return;

		Color col = scopeColor;
		if(panningButton is this)
			col = scopePanningColor;
		else if(Pressed)
			col = scopeActiveColor;
		else if(Hovered && !panningButton.visible)
			col = scopeHoverColor;

		col.a = buttonAlpha;
		drawRectangle(AbsolutePosition, col);

		const Font@ fnt = skin.getFont(FT_Normal);
		recti textPos = AbsolutePosition;
		textPos.topLeft.x += SCOPE_PADDING;
		textPos.botRight.x -= SCOPE_PADDING;

		int vpadd = (textPos.height - fnt.getLineHeight()) / 2;
		textPos.topLeft.y += vpadd;
		textPos.botRight.y -= vpadd;

		fnt.draw(textPos, name, ellipsis);

		BaseGuiElement::draw();
	}
};
