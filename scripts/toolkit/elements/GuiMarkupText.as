import elements.BaseGuiElement;
import elements.GuiPanel;
import util.formatting;

#section game
from hooks import Targets, TargetType;
import orbitals;
import buildings;
import resources;
import void drawResource(const ResourceType@ type, const recti& pos) from "elements.GuiResources";
import void drawSmallResource(const ResourceType@ type, const Resource@ r, const recti& pos, Object@ drawFrom = null, bool onPlanet = false) from "elements.GuiResources";
import void drawObjectIcon(Object@ obj, const recti& pos) from "util.icon_view";
#section all

from gui import gui_root;

export MarkupRenderer, GuiMarkupText;

const Color LINK_COLOR(0x98bbf5ff);
const Color LINK_HOVER_BG(0xffffff20);
const string strSemicolon(";"), NO_ANCHOR("");
const string PAR_SEP("\r");
const string LINE_SEP("\n");

enum TagType {
	TT_Text,
	TT_Font,
	TT_Color,
	TT_Stroke,
	TT_SkinColor,
	TT_HSpace,
	TT_VSpace,
	TT_VBlock,
	TT_Offset,
	TT_Padding,
	TT_Locale,
	TT_Bold,
	TT_Italic,
	TT_BR,
	TT_NL,
	TT_Data,
	TT_DLC
};

enum MarkupMode {
	MM_Draw,
	MM_Layout,
};

class MarkupData {
	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) {
	}

	bool contains(const Skin@ skin, MarkupState@ state, const vec2i& pos) {
		return false;
	}

	void set_hovered(bool value) {
	}

	string get_tooltip() {
		return "";
	}

	const string& get_anchor() {
		return NO_ANCHOR;
	}

	int get_anchorPosition() {
		return -1;
	}

	bool onClick(GuiMarkupText@ elem, int button, bool pressed) {
		return false;
	}
};

final class MarkupObjectIcon : MarkupData {
	uint objId;
	vec2i size;
	int offset;

#section game
	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		state.checkLine(size.x);
		if(mode == MM_Draw) {
			auto@ obj = getObjectByID(objId);
			if(obj !is null)
				drawObjectIcon(obj, recti_area(state.pos + vec2i(0, offset), size));
		}
		state.pos.x += size.x;

		if(tag.childCount > 0) {
			int prevPos = state.area.topLeft.x;
			state.area.topLeft.x = state.pos.x + 14;
			state.pos.x = state.area.topLeft.x;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.area.topLeft.x = prevPos;
			state.linebreak();
		}
		else {
			if(size.y+offset*2 > state.lineHeight)
				state.lineHeight = size.y+offset*2;
		}
	}
#section all
};

final class MarkupImage : MarkupData {
	Sprite spr;
	Color color;
	vec2i size;

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		state.checkLine(size.x);
		if(mode == MM_Draw)
			spr.draw(recti_area(state.pos, size), color);
		state.pos.x += size.x;

		if(tag.childCount > 0) {
			int prevPos = state.area.topLeft.x;
			state.area.topLeft.x = state.pos.x + 14;
			state.pos.x = state.area.topLeft.x;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.area.topLeft.x = prevPos;
			state.linebreak();
		}
		else {
			if(size.y > state.lineHeight)
				state.lineHeight = size.y;
		}
	}
};

final class MarkupAlign : MarkupData {
	double align = 0.5;
	double width = -1;
	double widthSpec = -1;
	int loffset = 0;
	int roffset = 0;

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		if(mode == MM_Draw) {
			state.clearLine();
			int startPos = state.pos.x;
			state.area.topLeft.x += loffset;
			state.area.botRight.x -= roffset;
			state.pos.x += loffset;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.clearLine();
			state.area.topLeft.x -= loffset;
			state.area.botRight.x += roffset;
			state.pos.x = startPos+width;
			state.linebreak();
		}
		else if(mode == MM_Layout) {
			state.clearLine();
			if(widthSpec <= 0)
				width = state.area.width;
			else if(widthSpec <= 1)
				width = double(state.area.width) * widthSpec;

			vec2i start = state.pos;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			vec2i end = state.pos;

			double diff = double(width) - double(end.x - start.x);
			loffset = diff * align;
			roffset = diff * (1.0 - align);

			state.pos = start;
			state.area.topLeft.x += loffset;
			state.area.botRight.x -= roffset;
			state.pos.x += loffset;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.clearLine();
			state.area.topLeft.x -= loffset;
			state.area.botRight.x += roffset;
			state.pos.x = start.x+width;
			state.linebreak();
		}
	}
};

final class MarkupLine : MarkupData {
	Color color(0xaaaaaaff);
	int width = 1;

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		state.checkLine(state.area.width - 1);
		if(mode == MM_Draw)
			drawRectangle(recti_area(state.pos+vec2i(0, 3), vec2i(state.area.width - 12, width)), color);
		state.pos.y += 8;
	}
};

const array<FontType> HeadingFonts = {FT_Medium, FT_Subtitle, FT_Bold};
const array<uint> HeadingOffsets = {16, 10, 0};
final class MarkupHeading : MarkupData {
	string name;
	FontType font;
	int position = 0;
	int offset;

	MarkupHeading(uint level, BBTag@ tag) {
		font = HeadingFonts[clamp(level-1, 0, 2)];
		offset = HeadingOffsets[clamp(level-1, 0, 2)];
		bbToPlainText(tag, name);
	}

	const string& get_anchor() {
		return name;
	}

	int get_anchorPosition() {
		return position;
	}

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		if(state.pos.y > state.area.topLeft.y)
			state.pos.y += offset;
		const Font@ prev = state.font;
		@state.font = skin.getFont(font);
		position = state.pos.y - state.absArea.topLeft.y;
		for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
			markupComp(skin, state, tag.children[i], mode);
		@state.font = prev;
		state.linebreak();
	}
};

final class MarkupLink : MarkupData {
	string link;
	string text;
	recti relPos;
	bool Hovered = false;

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		if(mode == MM_Draw) {
			state.checkLine(relPos.width);
			state.lineHeight = max(state.lineHeight, state.font.getLineHeight());

			if(Hovered)
				drawRectangle(relPos.padded(-2) + state.absArea.topLeft, LINK_HOVER_BG);
			state.font.draw(relPos + state.absArea.topLeft,
					text, locale::ELLIPSIS, LINK_COLOR, 0.0, 0.5);
			state.pos.x += relPos.width;
		}
		else if(mode == MM_Layout) {
			state.lineHeight = max(state.lineHeight, state.font.getLineHeight());

			vec2i dim = state.font.getDimension(text);
			dim.y = state.lineHeight;
			relPos = recti_area(state.pos - state.absArea.topLeft, dim);
			state.pos.x += relPos.width;

			state.checkLine(relPos.width);
		}
	}

	bool contains(const Skin@ skin, MarkupState@ state, const vec2i& pos) override {
		return relPos.contains(pos - state.absArea.topLeft);
	}

	void set_hovered(bool value) override {
		Hovered = value;
	}

	bool onClick(GuiMarkupText@ elem, int button, bool pressed) override {
		if(!pressed)
			elem.onLinkClicked(link, button);
		return true;
	}
};

class MarkupGuiElement : MarkupData {
	IGuiElement@ element;

	MarkupGuiElement(IGuiElement@ elem) {
		@element = elem;
		@element.parent = gui_root;
	}

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		vec2i size = element.size;
		state.checkLine(size.width);
		state.lineHeight = max(state.lineHeight, size.height);
		element.position = state.pos;
	}
};

final class MarkupTemplate : MarkupData {
	BBCode code;

	MarkupTemplate(const string& text, MarkupState@ state) {
		code.parse(text);

		BBTag@ root = code.root;
		for(uint i = 0, cnt = root.childCount; i < cnt; ++i) {
			BBTag@ tag = root.children[i];
			markupParse(tag, state);
		}
	}

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		BBTag@ root = code.root;
		for(uint i = 0, cnt = root.childCount; i < cnt; ++i)
			markupComp(skin, state, root.children[i], mode);
	}
};

class MarkupReference : MarkupData {
	Sprite icon;
	string name;
	string ttip;
	recti relPos;
	Color background(0x00000000);
	int refSize = -1;

	MarkupReference() {
	}

	MarkupReference(const Sprite& sprt, const string& tip) {
		icon = sprt;
		ttip = tip;
	}

	MarkupReference(const Sprite& sprt, const string& tip, const string& txt, const Color& bg, int sz = -1) {
		icon = sprt;
		ttip = tip;
		name = txt;
		background = bg;
		refSize = sz;
	}

	string get_tooltip() {
		return ttip;
	}

	bool contains(const Skin@ skin, MarkupState@ state, const vec2i& pos) override {
		return relPos.contains(pos - state.absArea.topLeft);
	}

	void drawIcon(const recti& pos) {
		icon.draw(pos);
	}

	void comp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) override {
		vec2i isize = icon.size;
		if(refSize != -1)
			isize = vec2i(int(double(refSize) * icon.aspect), refSize);
		else if(isize.y == 0)
			isize.y = 22;

		vec2i size = isize;
		vec2i tsize;
		if(name.length != 0) {
			tsize = state.font.getDimension(name);
			size.x += tsize.x + 8;
		}

		state.checkLine(size.x);
		if(mode == MM_Draw) {
			if(background.a != 0)
				drawRectangle(recti_area(state.pos, size), background);
			drawIcon(recti_area(state.pos, isize));
			if(name.length != 0) {
				int yOff = (state.font.getLineHeight() - state.font.getBaseline()) / 2;
				yOff += (isize.y-(tsize.y+yOff))/2;
				state.font.draw(state.pos + vec2i(isize.x+4, yOff), name, state.color);
			}
		}
		relPos = recti_area(state.pos - state.absArea.topLeft, size);
		if(size.y > state.lineHeight)
			state.lineHeight = size.y;
		state.pos.x += size.x;
	}
};

#section game
class MarkupLargeResource : MarkupReference {
	const ResourceType@ resource;

	MarkupLargeResource(const ResourceType& type) {
		@resource = type;
		icon = type.icon;
		name = type.name;
		ttip = getResourceTooltip(type);
		background = Color(0xffffff10);
	}

	void drawIcon(const recti& pos) override {
		drawResource(resource, pos);
	}
};

class MarkupSmallResource : MarkupReference {
	const ResourceType@ resource;

	MarkupSmallResource(const ResourceType& type) {
		@resource = type;
		icon = type.smallIcon;
		name = type.name;
		ttip = getResourceTooltip(type);
		background = Color(0xffffff10);
	}

	void drawIcon(const recti& pos) override {
		drawSmallResource(resource, null, pos);
	}
};
#section all

final class MarkupState {
	bool expandWidth = false;
	bool paragraphize = false;
	recti absArea;
	recti area;
	vec2i pos;
	const Font@ font;
	Color color;
	Color stroke;
	int lineHeight;
	int maxWidth = 0;
	bool wasPrintable = false;
	MarkupData@ contains;
	MarkupData@[] data;

#section game
	Targets@ targets;
#section all

	void checkLine(int width) {
		if(pos.x + width > area.botRight.x)
			linebreak();
	}

	int getLineHeight() {
		return max(font.getLineHeight(), lineHeight);
	}

	void linebreak() {
		maxWidth = max(maxWidth, pos.x - absArea.topLeft.x);
		pos.x = area.topLeft.x;
		pos.y += max(font.getLineHeight(), lineHeight);
		lineHeight = -1;
	}

	void clearLine() {
		if(pos.x > area.topLeft.x)
			linebreak();
	}

	void reset(const Skin@ skin, const recti& Area, FontType defaultFont, const Color& defaultColor, const Color& defaultStroke) {
		area = Area;
		absArea = Area;
		pos = area.topLeft;
		@font = skin.getFont(defaultFont);
		color = defaultColor;
		stroke = defaultStroke;
		lineHeight = 0;
		maxWidth = 0;
	}
};

//The parse step pre-calculates values for quick drawing
void markupParse(BBTag@ tag, MarkupState@ state){
	bool setUnprintable = false;
	if(tag.type == -1) {
		tag.type = TT_Text;
		if(state.paragraphize) {
			tag.argument.paragraphize(PAR_SEP, LINE_SEP, !state.wasPrintable);
			state.wasPrintable = !tag.argument.isWhitespace();
		}
	}
	else if(tag.name == "font") {
		tag.type = TT_Font;
		tag.value = getFontType(tag.argument);
	}
	else if(tag.name == "h1") {
		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(MarkupHeading(1, tag));
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "h2") {
		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(MarkupHeading(2, tag));
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "h3") {
		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(MarkupHeading(3, tag));
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "br") {
		tag.type = TT_BR;
		state.wasPrintable = false;
	}
	else if(tag.name == "nl") {
		tag.type = TT_NL;
		state.wasPrintable = false;
	}
	else if(tag.name == "color") {
		if(tag.argument.length > 0 && tag.argument[0] == '#') {
			tag.type = TT_Color;
			tag.value = toColor(tag.argument).color;
		}
		else if(tag.argument.length > 0 && tag.argument[0] == '$') {
			tag.type = TT_Color;
			tag.value = getGlobalColor("icons", "colors::"+tag.argument.substr(1)).color;
		}
		else {
			tag.type = TT_SkinColor;
			tag.value = getColorType(tag.argument);
		}
	}
	else if(tag.name == "stroke") {
		if(tag.argument.length > 0 && tag.argument[0] == '#') {
			tag.type = TT_Stroke;
			tag.value = toColor(tag.argument).color;
		}
		else if(tag.argument.length > 0 && tag.argument[0] == '$') {
			tag.type = TT_Stroke;
			tag.value = getGlobalColor("icons", "colors::"+tag.argument.substr(1)).color;
		}
	}
	else if(tag.name == "hspace") {
		tag.type = TT_HSpace;
		tag.value = toInt(tag.argument);
		state.wasPrintable = false;
	}
	else if(tag.name == "vspace") {
		tag.type = TT_VSpace;
		tag.value = toInt(tag.argument);
		state.wasPrintable = false;
	}
	else if(tag.name == "vblock") {
		tag.type = TT_VBlock;
		tag.value = toInt(tag.argument);
	}
	else if(tag.name == "offset") {
		tag.type = TT_Offset;
		tag.value = toInt(tag.argument);
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "padding") {
		tag.type = TT_Padding;
		tag.value = toInt(tag.argument);
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "bbloc") {
		tag.type = TT_Data;
		state.data.insertLast(MarkupTemplate(localize(tag.argument), state));
		tag.value = state.data.length-1; //Because MarkupTemplate can add to state.data list

		state.wasPrintable = true;
	}
	else if(tag.name == "loc") {
		tag.type = TT_Text;

		string[] args;
		args = tag.argument.split(strSemicolon);

		switch(args.length) {
			case 1:
				tag.argument = localize(args[0]);
			break;
			case 2:
				tag.argument = format(localize(args[0]), localize(args[1]));
			break;
			case 3:
				tag.argument = format(localize(args[0]), localize(args[1]), localize(args[2]));
			break;
			case 4:
				tag.argument = format(localize(args[0]), localize(args[1]), localize(args[2]), localize(args[3]));
			break;
			case 5:
				tag.argument = format(localize(args[0]), localize(args[1]), localize(args[2]), localize(args[3]), localize(args[4]));
			break;
			default:
				throw("Error parsing bbcode: [loc] tag can have no more than 5 arguments.");
			break;
		}
		state.wasPrintable = true;
	}
	else if(tag.name == "b") {
		tag.type = TT_Bold;
	}
	else if(tag.name == "i") {
		tag.type = TT_Italic;
	}
	else if(tag.name == "sprite" || tag.name == "img") {
		string[] args = tag.argument.split(strSemicolon);

		MarkupImage img;
		if(args.length != 0) {
			uint argi = 0;
			if(tag.name == "sprite") {
				@img.spr.sheet = getSpriteSheet(args[argi]);
				++argi;

				if(args.length > argi) {
					img.spr.index = toUInt(args[argi]);
					++argi;
				}
				img.size = img.spr.size;
			}
			else {
				if(args[argi].length != 0 && args[argi][0] == '$') {
					img.spr = getGlobalSprite("icons", "icons::"+args[argi].substr(1));
					img.size = img.spr.size;
					++argi;
				}
				else {
					img.spr = getSprite(args[argi]);
					img.size = img.spr.size;
					++argi;
				}
			}

			if(args.length > argi) {
				string[] parts = args[argi].split("x");
				int w = 0, h = 0;

				if(parts.length >= 1)
					w = toInt(parts[0]);
				if(parts.length >= 2)
					h = toInt(parts[1]);

				if(w != 0 || h != 0) {
					if(w == 0)
						w = double(h) * (double(img.size.x) / double(img.size.y));
					else if(h == 0)
						h = double(w) * (double(img.size.y) / double(img.size.x));

					img.size.x = w;
					img.size.y = h;
				}
			}
			++argi;

			if(args.length > argi)
				img.color = toColor(args[argi]);
		}

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(img);
		state.wasPrintable = true;
	}
	else if(tag.name == "obj_icon") {
		string[] args = tag.argument.split(strSemicolon);

		if(args.length == 0)
			throw("Error parsing bbcode: [obj_icon] tag need arguments.");

		MarkupObjectIcon img;
		uint argi = 0;
		img.objId = toInt(args[argi]);
		img.size = vec2i(30);
		img.offset = -4;
		++argi;

		if(args.length > argi) {
			string[] parts = args[argi].split("x");
			int w = 0, h = 0;

			if(parts.length >= 1)
				w = toInt(parts[0]);
			if(parts.length >= 2)
				h = toInt(parts[1]);

			if(w != 0 || h != 0) {
				if(w == 0)
					w = double(h) * (double(img.size.x) / double(img.size.y));
				else if(h == 0)
					h = double(w) * (double(img.size.y) / double(img.size.x));

				img.size.x = w;
				img.size.y = h;
			}
		}
		++argi;

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(img);
		state.wasPrintable = true;
	}
	else if(tag.name == "align") {
		MarkupAlign dat;
		int found = tag.argument.findFirst(strSemicolon);
		if(found == -1) {
			dat.align = toDouble(tag.argument);
			dat.widthSpec = -1;
		}
		else {
			dat.align = toDouble(tag.argument.substr(0, found));
			dat.widthSpec = toDouble(tag.argument.substr(found+1, tag.argument.length - found - 1));
		}

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(dat);
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "center") {
		MarkupAlign dat;
		dat.align = 0.5;

		if(tag.argument.length != 0)
			dat.width = toDouble(tag.argument);

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(dat);
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "right") {
		MarkupAlign dat;
		dat.align = 1.0;

		if(tag.argument.length != 0)
			dat.width = toDouble(tag.argument);

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(dat);
		state.wasPrintable = false;
		setUnprintable = true;
	}
	else if(tag.name == "hr") {
		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(MarkupLine());
		state.wasPrintable = false;
	}
	else if(tag.name == "levels") {
		tag.type = TT_Data;
		tag.value = state.data.length;
		state.wasPrintable = true;

		string text;
		if(tag.childCount != 0)
			text = tag.children[0].argument;

		auto@ levs = text.split("/");
		auto@ args = tag.argument.split(";");
		int num = -1;
		if(args.length >= 1 && args[0].length != 0 && args[0][0] != '$')
			num = toInt(args[0]);

		text = "";
		for(uint i = 0, cnt = levs.length; i < cnt; ++i) {
			if(i != 0)
				text += "/";
			if(num == int(i)) {
				text += "[b]";
				if(args.length >= 2)
					text += format("[color=$1]", args[1]);
			}
			text += levs[i];
			if(num == int(i)) {
				if(args.length >= 2)
					text += "[/color]";
				text += "[/b]";
			}
		}

		state.data.insertLast(MarkupTemplate(text, state));
	}
	else if(tag.name == "dlc") {
		tag.type = TT_DLC;
	}
#section game
	else if(tag.name == "target") {
		int found = tag.argument.findFirst(strSemicolon);
		string type, arg;

		if(found == -1) {
			arg = tag.argument;
		}
		else {
			type = tag.argument.substr(0, found);
			arg = tag.argument.substr(found+1, tag.argument.length - found - 1);
		}

		Target@ targ;
		if(state.targets !is null)
			@targ = state.targets.get(arg);

		MarkupData@ dat;
		if(targ !is null) {
			if(targ.type == TT_Object && targ.obj !is null) {
				@dat = MarkupTemplate(formatObject(targ.obj, showIcon = true), state);
			}
			else if(targ.type == TT_Empire && targ.emp !is null) {
				if(type.equals_nocase("race"))
					@dat = MarkupTemplate(targ.emp.RaceName, state);
				else
					@dat = MarkupTemplate(formatEmpireName(targ.emp), state);
			}
		}
		if(dat is null)
			@dat = MarkupTemplate("[b]---[/b]", state);

		state.data.insertLast(dat);
		tag.value = state.data.length-1;
		tag.type = TT_Data;
		state.wasPrintable = true;
	}
#section all
	else if(tag.name == "template") {
		int found = tag.argument.findFirst(strSemicolon);
		string type, arg;

		if(found == -1) {
			type = tag.argument;
		}
		else {
			type = tag.argument.substr(0, found);
			arg = tag.argument.substr(found+1, tag.argument.length - found - 1);
		}

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.wasPrintable = true;

#section game
		if(type == "resource") {
			const ResourceType@ r = getResource(arg);
			if(r !is null) {
				string code = format("[nl/][img=$1][font=Subtitle][b][color=$2]$3 [img=$5;20/][/color][/b][/font][br/]$4[/img]",
					getSpriteDesc(r.icon),
					toString(getResourceRarityColor(r.rarity)), r.name,
					getResourceTooltip(r, null, null, false).replaced("\n", "[br/]"),
					getSpriteDesc(r.smallIcon));

				state.data.insertLast(MarkupTemplate(code, state));
				tag.value = state.data.length-1; //Because MarkupTemplate can add to state.data list
			}
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "resource_ref") {
			const ResourceType@ r = getResource(arg);
			if(r !is null)
				state.data.insertLast(MarkupSmallResource(r));
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "orbital_ref") {
			auto@ d = getOrbitalModule(arg);
			if(d !is null)
				state.data.insertLast(MarkupReference(d.icon, d.getTooltip(), d.name, Color(0xffffff10), 22));
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "orbital") {
			auto@ d = getOrbitalModule(arg);
			if(d !is null) {
				string code = format("[nl/][img=$2;38]$1",
					d.getTooltip().replaced("\n", "[br/]"),
					getSpriteDesc(d.icon));
				state.data.insertLast(MarkupTemplate(code, state));
				tag.value = state.data.length-1;
			}
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "building_ref") {
			const BuildingType@ d = getBuildingType(arg);
			if(d !is null)
				state.data.insertLast(MarkupReference(d.sprite, d.getTooltip(), d.name, Color(0xffffff10), 22));
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "subsys_ref") {
			auto@ s = getSubsystemDef(arg);
			if(s !is null)
				state.data.insertLast(MarkupReference(s.picture, format("[b]$1[/b]\n\n$2", s.name, s.description), s.name, Color(0xffffff10), 22));
			else
				state.data.insertLast(MarkupData());
		}
		else if(type == "building") {
			const BuildingType@ d = getBuildingType(arg);
			if(d !is null) {
				string code = format("[nl/][img=$1][font=Subtitle][b]$2[/b][/font][br/]$3[/img]",
					getSpriteDesc(d.sprite),
					d.name,
					d.getTooltip(false).replaced("\n", "[br/]"));
				state.data.insertLast(MarkupTemplate(code, state));
				tag.value = state.data.length-1;
			}
			else
				state.data.insertLast(MarkupData());
		}
		else
#section all
		{
			state.data.insertLast(MarkupData());
		}
	}
	else if(tag.name == "url") {
		tag.type = TT_Data;

		MarkupLink link;
		link.link = tag.argument;
		bbToPlainText(tag, link.text);

		tag.value = state.data.length;
		state.data.insertLast(link);
		state.wasPrintable = true;
	}
	else if(tag.name.length > 1 && tag.name[0] == '[') {
		int found = tag.name.findFirst("|");
		MarkupLink link;

		if(found == -1) {
			link.link = tag.name.substr(1, tag.name.length - 1);
			link.text = link.link;
		}
		else {
			link.link = tag.name.substr(1, found-1);
			link.text = tag.name.substr(found+1, tag.argument.length - found - 1);
		}

		tag.type = TT_Data;
		tag.value = state.data.length;
		state.data.insertLast(link);
		state.wasPrintable = true;
	}

	for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
		markupParse(tag.children[i], state);

	if(setUnprintable)
		state.wasPrintable = false;
}

//The draw step draws anything that doesn't need its own element to do
void markupComp(const Skin@ skin, MarkupState@ state, BBTag@ tag, MarkupMode mode) {
	switch(tag.type) {
		case TT_Text: {
			vec2i prev = state.pos;
			state.lineHeight = max(state.lineHeight, state.font.getLineHeight());
			if(state.expandWidth) {
				vec2i dim = state.font.getDimension(tag.argument);
				if(mode == MM_Draw)
					state.font.draw(state.pos, tag.argument, state.color);
				state.pos.x += dim.x;
			}
			else {
				if(mode == MM_Draw) {
					state.pos = state.font.draw(
							state.area, state.pos - state.area.topLeft,
							state.lineHeight, tag.argument, state.color,
							stroke=state.stroke);
				}
				else {
					state.pos = state.font.getEndPosition(
							state.area, state.pos - state.area.topLeft,
							state.lineHeight, tag.argument);
				}
			}
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			if(prev.y != state.pos.y) {
				if(state.pos.x == state.area.topLeft.x)
					state.lineHeight = -1;
				else
					state.lineHeight = state.font.getLineHeight();
			}
		} break;
		case TT_BR:
			state.linebreak();
		break;
		case TT_NL:
			if(state.pos.x != state.area.topLeft.x)
				state.linebreak();
		break;
		case TT_Font: {
			const Font@ prev = state.font;
			@state.font = skin.getFont(FontType(tag.value));
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			@state.font = prev;
		} break;
		case TT_Bold: {
			const Font@ prev = state.font;
			if(prev.bold !is null)
				@state.font = prev.bold;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			@state.font = prev;
		} break;
		case TT_Italic: {
			const Font@ prev = state.font;
			if(prev.italic !is null)
				@state.font = prev.italic;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			@state.font = prev;
		} break;
		case TT_Color: {
			Color prev = state.color;
			state.color.color = tag.value;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.color = prev;
		} break;
		case TT_Stroke: {
			Color prev = state.stroke;
			state.stroke.color = tag.value;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.stroke = prev;
		} break;
		case TT_SkinColor: {
			Color prev = state.color;
			state.color = skin.getColor(SkinColor(tag.value));
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.color = prev;
		} break;
		case TT_HSpace: {
			state.pos.x += tag.value;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			if(tag.childCount > 0)
				state.pos.x -= tag.value;
		} break;
		case TT_VSpace: {
			state.pos.y += tag.value;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			if(tag.childCount > 0)
				state.pos.y -= tag.value;
		} break;
		case TT_VBlock: {
			int prevY = state.pos.y;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.pos.y += max(tag.value - (state.pos.y - prevY), 0);
		} break;
		case TT_Offset: {
			int prevStart = state.area.topLeft.x;
			if(state.pos.x - state.area.topLeft.x < tag.value)
				state.pos.x = tag.value + state.area.topLeft.x;
			state.area.topLeft.x = state.pos.x;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.area.topLeft.x = prevStart;
		} break;
		case TT_Padding: {
			if(state.pos.x - state.area.topLeft.x < tag.value)
				state.pos.x = tag.value + state.area.topLeft.x;
			state.area.topLeft.x += tag.value;
			state.area.botRight.x -= tag.value;
			for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
				markupComp(skin, state, tag.children[i], mode);
			state.area.topLeft.x -= tag.value;
			state.area.botRight.x += tag.value;
		} break;
		case TT_Data: {
			state.data[tag.value].comp(skin, state, tag, mode);
		} break;
		case TT_DLC: {
			if(hasDLC(tag.argument)) {
				for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
					markupComp(skin, state, tag.children[i], mode);
			}
		} break;
	}
}

void bbToPlainText(BBTag@ tag, string& text) {
	switch(tag.type) {
		case -1:
		case TT_Text:
			text += tag.argument;
		break;
	}

	for(uint i = 0, cnt = tag.childCount; i < cnt; ++i)
		bbToPlainText(tag.children[i], text);
}

class MarkupRenderer {
	BBCode tree;
	MarkupState state;
	int prevWidth = -1;
	int height = 100;
	int width = 100;
	bool prepared = false;
	FontType defaultFont = FT_Normal;
	Color defaultColor;
	Color defaultStroke = colors::Invisible;

	void clear() {
		tree.clear();
	}

	void set_expandWidth(bool v) {
		state.expandWidth = v;
	}

	void set_paragraphize(bool v) {
		state.paragraphize = v;
	}

	void parse(const Skin@ skin, const string& str, const recti& pos) {
		parseTree(str);
		parseElements(skin, pos);
	}

	int getAnchor(const string& name) {
		return getAnchor(name, tree.root);
	}

	int getAnchor(const string& name, BBTag@ tag) {
		if(tag.type == TT_Data) {
			MarkupData@ dat = state.data[tag.value];
			if(dat.anchor == name)
				return dat.anchorPosition;
		}

		for(uint i = 0, cnt = tag.childCount; i < cnt; ++i) {
			int pos = getAnchor(name, tag.children[i]);
			if(pos != -1)
				return pos;
		}

		return -1;
	}

	void parseTree(const string& str) {
		tree.parse(str);
		prevWidth = -1;
		prepared = false;
	}

	string getPlainText(const Skin@ skin, const recti& pos) {
		if(!prepared)
			parseElements(skin, pos);
		string text;
		bbToPlainText(tree.root, text);
		return text;
	}

	void parseElements(const Skin@ skin, const recti& pos) {
		BBTag@ root = tree.root;
		state.reset(skin, pos, defaultFont, defaultColor, defaultStroke);
		state.data.length = 0;
		for(uint i = 0, cnt = root.childCount; i < cnt; ++i)
			markupParse(root.children[i], state);
		prevWidth = -1;
		prepared = true;
	}

	void update(const Skin@ skin, const recti& pos) {
		if(!prepared)
			parseElements(skin, pos);
		if(pos.size.width != prevWidth) {
			state.reset(skin, pos, defaultFont, defaultColor, defaultStroke);
			BBTag@ root = tree.root;
			for(uint i = 0, cnt = root.childCount; i < cnt; ++i)
				markupComp(skin, state, root.children[i], MM_Layout);
			prevWidth = pos.size.width;
			height = (state.pos.y - state.area.topLeft.y)+3;
			if(state.pos.x > state.area.topLeft.x)
				height += state.getLineHeight();
			width = max(state.maxWidth, state.pos.x - state.area.topLeft.x);
		}
	}

	void draw(const Skin@ skin, const recti& pos) {
		if(pos.size.width != prevWidth)
			update(skin, pos);
		state.reset(skin, pos, defaultFont, defaultColor, defaultStroke);
		BBTag@ root = tree.root;
		for(uint i = 0, cnt = root.childCount; i < cnt; ++i)
			markupComp(skin, state, root.children[i], MM_Draw);
	}
};

class GuiMarkupText : BaseGuiElement {
	MarkupRenderer renderer;
	bool flexHeight = true;
	bool fitWidth = false;
	int Padding = 2;
	int hovered = -1;
	string text;
	bool memo = false;

	GuiMarkupText(IGuiElement@ ParentElement, Alignment@ Align) {
		super(ParentElement, Align);
		updateAbsolutePosition();
		renderer.defaultColor = skin.getColor(SC_Text);
	}

	GuiMarkupText(IGuiElement@ ParentElement, const recti& pos) {
		super(ParentElement, pos);
		updateAbsolutePosition();
		renderer.defaultColor = skin.getColor(SC_Text);
	}

	GuiMarkupText(IGuiElement@ ParentElement, Alignment@ Align, const string& txt) {
		super(ParentElement, Align);
		text = txt;
		updateAbsolutePosition();
		renderer.defaultColor = skin.getColor(SC_Text);
	}

	GuiMarkupText(IGuiElement@ ParentElement, const recti& pos, const string& txt) {
		super(ParentElement, pos);
		text = txt;
		updateAbsolutePosition();
		renderer.defaultColor = skin.getColor(SC_Text);
	}

	int getAnchor(const string& name) {
		return renderer.getAnchor(name);
	}

	string get_plainText() {
		return renderer.getPlainText(skin, AbsolutePosition.padded(Padding));
	}

	void clear() {
		renderer.clear();
	}

	void set_defaultColor(Color col) {
		renderer.defaultColor = col;
	}

	void set_defaultStroke(Color col) {
		renderer.defaultStroke = col;
	}

	void set_defaultFont(FontType type) {
		renderer.defaultFont = type;
	}

	void set_expandWidth(bool value) {
		renderer.expandWidth = value;
	}

	void set_paragraphize(bool value) {
		renderer.paragraphize = value;
	}

	int get_textWidth() {
		return renderer.width;
	}

	void set_padding(int padd) {
		Padding = padd;
		updateAbsolutePosition();
	}

	void set_text(const string& str) {
		if(memo) {
			if(text == str)
				return;
		}
		renderer.parseTree(str);
		if(memo)
			text = str;
	}

#section game
	void set_targets(const Targets@ targs) {
		if(targs is null) {
			@renderer.state.targets = null;
		}
		else {
			@renderer.state.targets = Targets();
			renderer.state.targets = targs;
		}
	}
#section all

	string get_tooltip() override {
		if(hovered != -1 && hovered < int(renderer.state.data.length))
			return renderer.state.data[hovered].tooltip;
		return "";
	}

	bool onGuiEvent(const GuiEvent& event) override {
		if(event.caller is this) {
			switch(event.type) {
				case GUI_Mouse_Left:
					hovered = -1;
				break;
			}
		}
		return BaseGuiElement::onGuiEvent(event);
	}

	int getOffsetItem(vec2i absPos) {
		for(int i = renderer.state.data.length - 1; i >= 0; --i) {
			MarkupData@ dat = renderer.state.data[i];
			if(dat.contains(skin, renderer.state, absPos))
				return i;
		}
		return -1;
	}

	bool onMouseEvent(const MouseEvent& event, IGuiElement@ source) override {
		if(source is this) {
			switch(event.type) {
				case MET_Moved: {
					int prevHovered = hovered;
					hovered = getOffsetItem(mousePos);
					if(prevHovered != hovered) {
						if(prevHovered != -1 && prevHovered < int(renderer.state.data.length))
							renderer.state.data[prevHovered].hovered = false;
						if(hovered != -1 && hovered < int(renderer.state.data.length))
							renderer.state.data[hovered].hovered = true;
						if(tooltipObject !is null)
							tooltipObject.update(skin, this);
					}
				} break;
				case MET_Button_Down:
					if(hovered != -1 && hovered < int(renderer.state.data.length))
						if(renderer.state.data[hovered].onClick(this, event.button, true))
							return true;
				break;
				case MET_Button_Up:
					if(hovered != -1 && hovered < int(renderer.state.data.length)) {
						if(renderer.state.data[hovered].onClick(this, event.button, false))
							return true;
					}
				break;
			}
		}
		return BaseGuiElement::onMouseEvent(event, source);
	}

	void onLinkClicked(const string& link, int button) {
	}

	void updateAbsolutePosition() {
		BaseGuiElement::updateAbsolutePosition();
		renderer.update(skin, AbsolutePosition.padded(Padding));
		if(Alignment is null) {
			vec2i sz = size;
			if(flexHeight)
				sz = vec2i(renderer.state.expandWidth ? textWidth+6 : Position.size.width, renderer.height + Padding * 2);
			if(fitWidth) {
				sz.x = parent.size.width - (position.x*2);
				GuiPanel@ pan = cast<GuiPanel>(parent);
				if(pan !is null && pan.vert.visible)
					sz.x -= pan.vert.size.width;
			}
			size = sz;
		}
	}

	void draw() {
		renderer.draw(skin, AbsolutePosition.padded(Padding));
		if(hovered < 0 || hovered > int(renderer.state.data.length))
			hovered = -1;
		BaseGuiElement::draw();
	}
};
