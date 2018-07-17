#include "scripts/binds.h"
#include "main/references.h"
#include "gui/skin.h"
#include "main/tick.h"
#include "render/render_state.h"
#include "render/font.h"
#include "profile/keybinds.h"
#include "../as_addons/include/scriptdictionary.h"

namespace scripts {

using namespace gui;

template<class A, class B>
B* castPtrRef(A* a) {
	if(!a)
		return 0;
	B* b = dynamic_cast<B*>(a);
	if(b)
		b->grab();
	return b;
}

const render::Font* get_font(const std::string& str) {
	return &devices.library.getFont(str);
}

int get_fontType(const std::string& str) {
	return skin::getFontIndex(str);
}

int get_colorType(const std::string& str) {
	return skin::getColorIndex(str);
}

const render::RenderState* get_mat(const std::string& str) {
	return &devices.library.getMaterial(str);
}

const skin::Skin* get_skin(const std::string& str) {
	return &devices.library.getSkin(str);
}

vec2i screen_size() {
	return vec2d(devices.driver->win_width / ui_scale,
			devices.driver->win_height / ui_scale);
}

vec2i window_size() {
	return vec2i(devices.driver->win_width,
				devices.driver->win_height);
}

bool window_focused() {
	return devices.driver->isWindowFocused();
}

bool window_minimized() {
	return devices.driver->isWindowMinimized();
}

bool window_mouseOver() {
	return devices.driver->isMouseOver();
}

void window_flash() {
	return devices.driver->flashWindow();
}

bool doClip = false;
recti clipRect;

void setClip(const recti& clip) {
	doClip = true;
	clipRect = clip;
}

void clearClip() {
	doClip = false;
}

recti* getClip() {
	if(doClip)
		return &clipRect;
	else
		return 0;
}

void skin_draw(skin::Skin& skin, unsigned style, unsigned flags, const recti& rect) {
	auto& element = skin.getElement(style, flags);
	element.draw(*devices.render,rect,getClip());
}

vec2i skin_size(skin::Skin& skin, unsigned style, unsigned flags) {
	auto& element = skin.getElement(style, flags);
	return element.area.getSize();
}

void skin_draw_c(skin::Skin& skin, unsigned style, unsigned flags, const recti& rect, const Color& color) {
	auto& element = skin.getElement(style, flags);
	element.draw(*devices.render,rect,getClip(),color);
}

void skin_text(skin::Skin& skin, unsigned fontClass, const vec2i& pos, const std::string& text) {
	auto& font = skin.getFont(fontClass);
	font.draw(devices.render,text.c_str(),pos.x,pos.y,0,getClip());
}

void skin_text_c(skin::Skin& skin, unsigned fontClass, const vec2i& pos, const std::string& text, const Color& color) {
	auto& font = skin.getFont(fontClass);
	font.draw(devices.render,text.c_str(),pos.x,pos.y,&color,getClip());
}

vec2i skin_char(skin::Skin& skin, unsigned fontClass, const vec2i& pos, int c, int lastC, const Color& color) {
	auto& font = skin.getFont(fontClass);
	return font.drawChar(devices.render,c,lastC,pos.x,pos.y,&color,getClip());
}

const render::Font* skin_font(skin::Skin& skin, unsigned fontClass) {
	return &skin.getFont(fontClass);
}

Color skin_color(skin::Skin& skin, unsigned color) {
	return skin.getColor(color);
}

static bool skin_irregular(skin::Skin& skin, unsigned index) {
	auto& style = skin.getStyle(index);
	return style.irregular;
}

static bool skin_pxactive(skin::Skin& skin, unsigned style, unsigned flags, const recti& box, const vec2i& px) {
	auto& element = skin.getElement(style, flags);
	return element.isPixelActive(box, px);
}

static unsigned skin_eleCount(skin::Skin& skin, int style) {
	if(!skin.hasStyle(style))
		return 0;
	const skin::Style& st = skin.getStyle(style);
	return st.elements.size();
}

static unsigned skin_eleFlags(skin::Skin& skin, int style, unsigned index) {
	if(!skin.hasStyle(style))
		return 0;
	const skin::Style& st = skin.getStyle(style);
	if(index >= st.elements.size())
		return 0;
	return st.elements[index]->flags;
}

vec2i getFontDimension(const render::Font& font, const std::string& text) {
	return font.getDimension(text.c_str());
}

vec2i getFontCharDim(const render::Font& font, int c, int lastC) {
	return font.getDimension(c, lastC);
}

void enum_skinElements(const std::string& name, unsigned index) {
	EnumBind skinElements("SkinFlags",false);
	skinElements[std::string("SF_") + name] = index;
}

void enum_skinFonts(const std::string& name, unsigned index) {
	EnumBind skinElements("FontType",false);
	skinElements[std::string("FT_") + name] = index;
}

void enum_skinColors(const std::string& name, unsigned index) {
	EnumBind skinElements("SkinColor",false);
	skinElements[std::string("SC_") + name] = index;
}

void enum_skinStyles(const std::string& name, unsigned index) {
	EnumBind skinElements("SkinStyle",false);
	skinElements[std::string("SS_") + name] = index;
}

void get_skinStyles(CScriptDictionary& map) {
	skin::enumerateStyleIndices([&map](const std::string& name, unsigned value) {
		asINT64 val = value;
		map.Set(name, val);
	});
}

vec2i getMousePos() {
	vec2i pos;
	devices.driver->getMousePos(pos.x,pos.y);
	return vec2d(pos) / ui_scale;
}

void setMousePos(const vec2i& pos) {
	vec2i scaledPos = vec2d(pos) * ui_scale;
	devices.driver->setMousePos(scaledPos.x, scaledPos.y);
}

void setMouseLock(bool lock) {
	devices.driver->setCursorShouldLock(lock);
}

void font_text(render::Font& font, const vec2i& pos, const std::string& text) {
	font.draw(devices.render,text.c_str(),pos.x,pos.y,0,getClip());
}

void font_text_c(render::Font& font, const vec2i& pos, const std::string& text, const Color& color) {
	font.draw(devices.render,text.c_str(),pos.x,pos.y,&color,getClip());
}

vec2i font_char(render::Font& font, const vec2i& pos, int c, int lastC, const Color& color) {
	return font.drawChar(devices.render,c,lastC,pos.x,pos.y,&color,getClip());
}

static void font_trunc_c(render::Font& font, const recti& pos, const std::string& text, const std::string& ellipsis, const Color& color, double horizAlign, double vertAlign) {
	vec2i dpos = pos.topLeft;
	int width = pos.getWidth();
	vec2i sz = font.getDimension(text.c_str());
	if(vertAlign != 0) {
		dpos.y += (int)(vertAlign * double(pos.getHeight() - sz.height));
		dpos.y += (font.getLineHeight() - font.getBaseline()) / 2;
	}
	if(sz.width <= width) {
		if(horizAlign != 0)
			dpos.x += (int)(horizAlign * double(width - sz.width));
		font.draw(devices.render, text.c_str(), dpos.x, dpos.y, &color, getClip());
		return;
	}

	vec2i esz = font.getDimension(ellipsis.c_str());
	width -= esz.width;
	int relX = 0;

	u8it it(text);
	int lastC = 0;
	while(int c = it++) {
		vec2i dim = font.getDimension(c, lastC);
		if(relX + dim.x > width) {
			font.draw(devices.render, ellipsis.c_str(), dpos.x + relX, dpos.y, &color, getClip());
			break;
		}

		font.drawChar(devices.render, c, lastC, dpos.x + relX, dpos.y, &color, getClip());
		relX += dim.x;
	}
}

static void font_trunc_cs(render::Font& font, const recti& pos, const std::string& text, const Color& stroke, const std::string& ellipsis, const Color& color, double horizAlign, double vertAlign, int strokeWidth) {
	if(stroke.a != 0) {
		font_trunc_c(font, pos+vec2i(-strokeWidth,-strokeWidth), text, ellipsis, stroke, horizAlign, vertAlign);
		font_trunc_c(font, pos+vec2i(strokeWidth,-strokeWidth), text, ellipsis, stroke, horizAlign, vertAlign);
		font_trunc_c(font, pos+vec2i(-strokeWidth,strokeWidth), text, ellipsis, stroke, horizAlign, vertAlign);
		font_trunc_c(font, pos+vec2i(strokeWidth,strokeWidth), text, ellipsis, stroke, horizAlign, vertAlign);
	}
	font_trunc_c(font, pos, text, ellipsis, color, horizAlign, vertAlign);
}

static vec2i font_wrap(render::Font& font, const recti& startPos, const vec2i& offset, int lineHeight, const std::string& text, const Color& color, bool draw = true, bool preserve = false) {
	if(lineHeight < 0)
		lineHeight = font.getLineHeight();
	int yOff = (font.getLineHeight() - font.getBaseline()) / 2;

	const char* str = text.c_str();
	const char* word = str;
	vec2i pos = startPos.topLeft;
	pos += offset;
	vec2i wordPos = pos;

	auto handleWord = [&](const char* from, const char* to) {
		if(pos.x > startPos.botRight.x) {
			pos.y += lineHeight;
			pos.x = startPos.topLeft.x + (pos.x - wordPos.x);
			wordPos.y = pos.y;
			wordPos.x = startPos.topLeft.x;

			if(!preserve)
				lineHeight = font.getLineHeight();
		}

		if(draw) {
			u8it it(from);
			int lastC = 0;
			while(it.str != to) {
				int c = it++;
				wordPos += font.drawChar(devices.render, c, lastC, wordPos.x, wordPos.y + yOff, &color, getClip());
				lastC = c;
				++word;
			}
		}
		else {
			wordPos.x = pos.x;
		}
	};

	u8it it(str);
	int lastC = 0;
	while(int c = it++) {
		//Skip over letters
		if(c != ' ') {
			if(c == '\n' || c == '\r') {
				if(word != it.str)
					handleWord(word, it.str);
				pos.x = startPos.topLeft.x + (pos.x - wordPos.x);
				pos.y += c == '\n' ? lineHeight : lineHeight+10;
				wordPos.x = startPos.topLeft.x;
				wordPos.y = pos.y;

				if(!preserve)
					lineHeight = font.getLineHeight();
			}
			else {
				pos.x += font.getDimension(c, lastC).x;
			}
			lastC = c;
			continue;
		}

		//Draw the previous word
		if(word != it.str)
			handleWord(word, it.str);

		//Set up for next word
		pos.x += font.getDimension(c, lastC).x;
		word = it.str;
		wordPos = pos;
		lastC = c;
	}

	//Draw the last word
	if(word != it.str)
		handleWord(word, it.str);

	return pos;
}

static vec2i font_wrap_dim(render::Font& font, const recti& startPos, const vec2i& offset, int lineHeight, const std::string& text, bool preserve) {
	Color col(0xffffffff);
	return font_wrap(font, startPos, offset, lineHeight, text, col, false, preserve);
}

static vec2i font_wrap_draw(render::Font& font, const recti& startPos, const vec2i& offset, int lineHeight, const std::string& text, const Color& color, bool preserve, const Color& stroke) {
	if(stroke.a != 0) {
		font_wrap(font, startPos+vec2i(-1,0), offset, lineHeight, text, stroke, true, preserve);
		font_wrap(font, startPos+vec2i(0,-1), offset, lineHeight, text, stroke, true, preserve);
		font_wrap(font, startPos+vec2i(0,1), offset, lineHeight, text, stroke, true, preserve);
		font_wrap(font, startPos+vec2i(1,0), offset, lineHeight, text, stroke, true, preserve);
	}
	return font_wrap(font, startPos, offset, lineHeight, text, color, true, preserve);
}

static double getUIScale() {
	return ui_scale;
}

static void setUIScale(double value) {
	if(value < 0.1 || value > 10) {
		scripts::throwException("UI scale value limited to range [0.1, 10].");
		return;
	}
	ui_scale = value;
}

void RegisterGuiBinds() {
	//-- SKIN ELEMENTS
	{
		ClassBind fnt("Font", asOBJ_REF | asOBJ_NOCOUNT, 0);
		classdoc(fnt, "Describes a font as defined in a data file, can be used to draw text on the screen.");

		fnt.addMember("const Font@ bold", offsetof(render::Font, bold))
			doc("The bold variant for this font, if specified. Null otherwise.");

		fnt.addMember("const Font@ italic", offsetof(render::Font, italic))
			doc("The italic variant for this font, if specified. Null otherwise.");

		fnt.addExternMethod("vec2i getDimension(const string &in text) const", asFUNCTION(getFontDimension))
			doc("Calculate the amount of space needed to draw a string with this font.",
				"Text to calculate for.", "Amount of space needed.");

		fnt.addExternMethod("vec2i getDimension(int c, int lastC) const", asFUNCTION(getFontCharDim))
			doc("Calculate the amount of space needed to draw a character with kerning.",
				"Character to calculate for.", "Previous character to kern with.",
				"Amount of space needed.");

		fnt.addMethod("uint getBaseline() const", asMETHOD(render::Font, getBaseline))
			doc("", "Baseline height for this font.");

		fnt.addMethod("uint getLineHeight() const", asMETHOD(render::Font, getLineHeight))
			doc("", "Line height for this font.");

		fnt.addExternMethod("void draw(const vec2i &in pos, const string &in text) const", asFUNCTION(font_text))
			doc("Draw text on screen with this font.",
				"Position to draw text at.", "Text to draw");

		fnt.addExternMethod("void draw(const vec2i &in pos, const string &in text, const Color&in color) const", asFUNCTION(font_text_c))
			doc("Draw text on screen with this font.",
				"Position to draw text at.", "Text to draw", "Color to draw the text in.");

		fnt.addExternMethod("vec2i draw(const vec2i &in pos, int c, int lastC, const Color&in color) const", asFUNCTION(font_char))
			doc("Draw a character on screen using kerning with the previous character.",
				"Position to draw the character at.", "Character to draw.",
				"Character previously drawn before it. (Character will be kerned with respect to it)", "Color to draw the character in.",
				"The size of the area the character was drawn in.");

		fnt.addExternMethod("void draw(const recti &in pos, const string &in text, const string &in ellipsis = locale::ELLIPSIS,"
				"const Color&in color = colors::White, double horizAlign = 0, double vertAlign = 0.5) const", asFUNCTION(font_trunc_c))
			doc("Draw text on screen with this font, appending an ellipsis if the text is too long.",
				"Box to draw the text inside.", "Text to draw.", "Ellipsis to append to text.",
				"Color to draw the text in.", "Horizontal alignment within the box.", "Vertical alignment within the box.");

		fnt.addExternMethod("void draw(const recti &in pos, const string &in text, const Color& stroke, const string &in ellipsis = locale::ELLIPSIS,"
				"const Color&in color = colors::White, double horizAlign = 0, double vertAlign = 0.5, int strokeWidth = 1) const", asFUNCTION(font_trunc_cs))
			doc("Draw text on screen with this font, appending an ellipsis if the text is too long.",
				"Box to draw the text inside.", "Text to draw.", "Color of the stroke.", "Ellipsis to append to text.",
				"Color to draw the text in.", "Horizontal alignment within the box.", "Vertical alignment within the box.",
				"Width of the stroke.");

		fnt.addExternMethod("vec2i draw(const recti &in pos, const vec2i& offset, int lineHeight, const string &in text,"
				" const Color&in color, bool preserveLineHeight = false, const Color& stroke = colors::Invisible) const", asFUNCTION(font_wrap_draw))
			doc("Draw text on screen with this font, word wrapping within the area.",
				"Box to draw the text inside.", "Offset of the first line of text in the box.",
				"Height of each drawn line.", "Text to draw.", "Color to draw the text in.",
				 "Whether lines after the first line should not reset the lineheight.",
				 "Color to draw a stroke with.", "Dimensions of the text that was drawn.");

		fnt.addExternMethod("vec2i getEndPosition(const recti &in pos, const vec2i& offset, int lineHeight,"
				" const string &in text, bool preserveLineHeight = false) const",
				asFUNCTION(font_wrap_dim))
			doc("Get the position the cursor would end up at after drawing this text with word wrap.",
				"Box to draw the text inside.", "Offset of the first line of text in the box.",
				"Height of each drawn line.", "Text to draw.", "Whether lines after the first line should not reset the lineheight.",
				"Dimension of the text that would be drawn.");

		{
			Namespace ns("font");
			foreach(it, devices.library.fonts)
				bindGlobal(format("const ::Font $1", it->first).c_str(), it->second);
		}
	}

	{
		EnumBind styleEnum("SkinStyle");
		classdoc(styleEnum, "Holds the identifiers for all styles defined in skin definitions.");
		skin::enumerateStyleIndices(enum_skinStyles);
		styleEnum["SS_NULL"] = -1;

		bind("void getSkinStyles(dictionary& result)", asFUNCTION(get_skinStyles))
			doc("Fill the passed dictionary with a mapping of all skin style names to their enum identifiers.",
				"Dictionary to fill.");

		bind("uint getSkinStyleCount()", asFUNCTION(skin::getStyleCount))
			doc("", "The amount of skin styles currently defined.");

		bind("string getElementFlagName(uint flags)", asFUNCTION(skin::getElementFlagName))
			doc("Retrieve the string name of a combination of skin flags.",
				"Flag mask to retrieve the name for.", "Name(s) of flags.");
	}

	{
		EnumBind colorEnum("SkinColor");
		classdoc(colorEnum, "Identifiers for all color classes in skin definitions.");
		skin::enumerateColorIndices(enum_skinColors);
	}

	{
		EnumBind fontEnum("FontType");
		classdoc(fontEnum, "Identifiers for all font classes in skin definitions.");
		skin::enumerateFontIndices(enum_skinFonts);
	}

	{
		EnumBind skinFlags("SkinFlags");
		classdoc(skinFlags, "Masks for skin style flags to alter how a style is presented.");
		skin::enumerateElementFlags(enum_skinElements);
	}

	ClassBind skin("Skin", asOBJ_REF | asOBJ_NOCOUNT, 0);
		classdoc(skin,
			"Represents a collection of styles that can be swapped out as a skin. "
			"Styles are individual elements that can be drawn in arbitrarily-sized screen areas (button backgrounds, hud bars, etc). "
			"Each style can be drawn with flags that alter its drawn style (hovered, active, etc).");

	skin.addExternMethod("void draw(SkinStyle style, SkinFlags flags, const recti &in box) const", asFUNCTION(skin_draw))
		doc("Draw a skin style on a screen area.",
			"Style to draw.", "Mask of skin flags for draw state.", "Coordinates on screen to draw at.");

	skin.addExternMethod("void draw(SkinStyle style, SkinFlags flags, const recti &in box, const Color&in color) const", asFUNCTION(skin_draw_c))
		doc("Draw a skin style on a screen area.",
			"Style to draw.", "Mask of skin flags for draw state.", "Coordinates on screen to draw at.", "Color to colorize the style as.");

	skin.addExternMethod("void draw(SkinStyle style, uint flags, const recti &in box) const", asFUNCTION(skin_draw))
		doc("Draw a skin style on a screen area.",
			"Style to draw.", "Mask of skin flags for draw state.", "Coordinates on screen to draw at.");

	skin.addExternMethod("void draw(SkinStyle style, uint flags, const recti &in box, const Color&in color) const", asFUNCTION(skin_draw_c))
		doc("Draw a skin style on a screen area.",
			"Style to draw.", "Mask of skin flags for draw state.", "Coordinates on screen to draw at.", "Color to colorize the style as.");

	skin.addExternMethod("void draw(FontType font, const vec2i &in pos, const string &in text) const", asFUNCTION(skin_text))
		doc("Draw text on screen with a specific font.",
			"Font class to draw with.", "Position to draw the text at.", "Text to draw.");

	skin.addExternMethod("void draw(FontType font, const vec2i &in pos, const string &in text, const Color&in color) const", asFUNCTION(skin_text_c))
		doc("Draw text on screen with a specific font.",
			"Font class to draw with.", "Position to draw the text at.", "Text to draw.", "Color to draw the text in.");

	skin.addExternMethod("vec2i draw(FontType font, const vec2i &in pos, int c, int lastC, const Color&in color) const", asFUNCTION(skin_char))
		doc("Draw a character on screen using kerning with the previous character.",
			"Font class to draw with.", "Position to draw the character at.", "Character to draw.",
			"Character previously drawn before it. (Character will be kerned with respect to it)", "Color to draw the character in.",
			"Size of the area the character was drawn in.");

	skin.addExternMethod("const Font@ getFont(FontType font) const", asFUNCTION(skin_font))
		doc("Retrieve the font associated with a font class by this skin.",
			"Font class to lookup.", "Associated font.");

	skin.addExternMethod("Color getColor(SkinColor color) const", asFUNCTION(skin_color))
		doc("Retrieve the color associated with a color class by this skin.",
			"Color class to lookup.", "Associated color.");

	skin.addExternMethod("vec2i getSize(SkinStyle style, SkinFlags flags) const", asFUNCTION(skin_size))
		doc("Retrieve the definition size of a skin style."
			"(Note: Non-uniform skin styles can be drawn at any size, not just the definition size.)",
			"Skin style definition to lookup.", "Skin flags for the style to lookup.",
			"Definition size of the style.");

	skin.addExternMethod("bool isIrregular(SkinStyle style) const", asFUNCTION(skin_irregular))
		doc("Whether a skin style was defined as irregular. Irregular styles require pixel-checking for focus and"
			" can not rely on bounding boxes.", "Skin style to lookup for.",
			"Whether the style was defined as irregular.");

	skin.addExternMethod("bool isPixelActive(SkinStyle style, SkinFlags flags, const recti &in box, const vec2i &in px) const", asFUNCTION(skin_pxactive))
		doc("Check whether a particular pixel would be active in an irregular style as it would be drawn.",
			"Skin style to check for.", "Skin flags for the style to check for.", "Box that the style would be drawn in.",
			"Pixel relative to the start of the box to check.", "Whether the specified pixel would be active.");

	skin.addExternMethod("bool isPixelActive(SkinStyle style, uint flags, const recti &in box, const vec2i &in px) const", asFUNCTION(skin_pxactive))
		doc("Check whether a particular pixel would be active in an irregular style as it would be drawn.",
			"Skin style to check for.", "Skin flags for the style to check for.", "Box that the style would be drawn in.",
			"Pixel relative to the start of the box to check.", "Whether the specified pixel would be active.");

	skin.addExternMethod("uint getStyleElementCount(SkinStyle style) const", asFUNCTION(skin_eleCount))
		doc("Get the amount of style elements are in a particular skin style. A style element",
			" directs the appearance of the style under particular flags.",
			"Skin style to check for.", "Amount of style elements.");

	skin.addExternMethod("uint getStyleElementFlags(SkinStyle style, uint index) const", asFUNCTION(skin_eleFlags))
		doc("Retrieve the flag mask a particular style element indicates the appearance for.",
			"Skin style to retrieve from.", "Index of the style element to retrieve from.",
			"Mask of skin style flags that the element indicates.");


	//-- Library access
	bind("const Font@ getFont(const string &in name)", asFUNCTION(get_font))
		doc("Get a font by name.", "", "");

	bind("FontType getFontType(const string &in name)", asFUNCTION(get_fontType))
		doc("Get a font type by name.", "", "");

	bind("SkinColor getColorType(const string &in name)", asFUNCTION(get_colorType))
		doc("Get a color type by name.", "", "");

	bind("const Skin@ getSkin(const string &in name)", asFUNCTION(get_skin))
		doc("Get a skin by name.", "", "");

	//-- GLOBAL
	bind("void setClip(const recti& in clip)", asFUNCTION(setClip))
		doc("Set the currently active clipping rectangle.",
			"Rectangle to clip all subsequent 2D draws in.");

	bind("void clearClip()", asFUNCTION(clearClip))
		doc("Clear the current clipping rectangle.");

	bind("vec2i get_screenSize()", asFUNCTION(screen_size))
		doc("Get the current size of the game screen.", "");

	bind("void flashWindow()", asFUNCTION(window_flash))
		doc("Flash the window to bring attention.");

	bind("bool get_windowFocused()", asFUNCTION(window_focused))
		doc("Whether the game window is currently focused.", "");

	bind("bool get_windowMinimized()", asFUNCTION(window_minimized))
		doc("Whether the game window is currently minimized.", "");

	bind("vec2i get_windowSize()", asFUNCTION(window_size))
		doc("Get the actual window size (independent of ui scaling).", "");

	bind("bool get_mouseOverWindow()", asFUNCTION(window_mouseOver))
		doc("Whether the mouse is currently over the window.", "");

	bind("vec2i get_mousePos()", asFUNCTION(getMousePos))
		doc("Get the current mouse position.", "");

	bind("void set_mousePos(const vec2i &in)", asFUNCTION(setMousePos))
		doc("Set the mouse position.", "New mouse position");

	bind("void set_mouseLock(bool lock)", asFUNCTION(setMouseLock))
		doc("Sets whether the cursor should be locked to the screen, if the user has enabled the feature.", "");

	bindGlobal("bool shiftKey", &devices.driver->shiftKey)
		doc("Whether the shift key is currently pressed.");

	bindGlobal("bool altKey", &devices.driver->altKey)
		doc("Whether the alt key is currently pressed.");

	bindGlobal("bool ctrlKey", &devices.driver->ctrlKey)
		doc("Whether the control key is currently pressed.");

	bindGlobal("bool mouseLeft", &devices.driver->leftButton)
		doc("Whether the left mouse button is currently pressed.");

	bindGlobal("bool mouseMiddle", &devices.driver->middleButton)
		doc("Whether the middle mouse button is currently pressed.");

	bindGlobal("bool mouseRight", &devices.driver->rightButton)
		doc("Whether the right mouse button is currently pressed.");

	bind("double get_uiScale()", asFUNCTION(getUIScale))
		doc("", "Global zoom factor on the entire UI.");

	bind("void set_uiScale(double value)", asFUNCTION(setUIScale))
		doc("", "New global zoom factor on the entire UI. Must be between 0.1 and 10.");

	bindGlobal("bool hide_ui", &hide_ui)
		doc("Whether to hide all 2D UI interface elements");
}

};
